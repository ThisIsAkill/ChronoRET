#!/usr/bin/env python3
"""
draft.py — Draft source for an unmatched routine: asar source in the
project's style that already assembles byte-exact and already uses every
name the project knows, so the matcher's work is understanding and naming.

Usage:
    python3 tools/draft.py C1:3714 [C1:3800] [options]
    make draft ADDR=C1:3714 [END=C1:3800] [DRAFT_ARGS="--m 1 --x 0"]
        (writes build/draft_C13714.asm and runs --check)

Addresses may be written C1:3714, $C1:3714, C13714 or 0xC13714.

Options:
    --m 0|1  --x 0|1   entry widths (1 = 8-bit). Default M=1, X=0.
    --dp HEX           entry direct page (default 0).
    --db HEX           entry data bank (default 7E).
    --name NAME        label for the routine (default: the existing label at
                       the start address, else Sub_<bank><addr>).
    --names SET        battle or engine: which RAM/constant names to use
                       (default battle for bank $C1, engine otherwise).
    -o FILE            write the draft there instead of stdout.
    --check            assemble the draft in place of the region (temporary
                       copy of the tree) and confirm byte-exactness with
                       `make diff` plus a two-base coverage check.
    --compare          for a region that is already matched: compare the
                       draft's operands with the hand-written source.
    --no-callers       skip the ROM caller scan.

What it does:
  * Disassembles from the start address, following internal branches, until
    the routine ends: every path has reached RTS/RTL/RTI/JMP/BRA/BRL (or a
    tail jump/fall-through into a known label) and no branch of its own
    reaches past that point. With an end address it covers exactly
    [start, end]; bytes no path reaches become `db` with a TODO.
  * Tracks M/X through REP/SEP/PHP/PLP, DP through PHD/TCD/PLD and DB
    through PHB/PHK/PHA/PLB (known A from LDA #imm / TDC). A width that
    becomes unknown (PLP without a matching PHP, two paths that disagree)
    stops that path and is flagged in the draft.
  * Names operands from asm/include (RAM/DP defines, struct fields, tilemap
    functions, hardware registers), call/jump targets from the assembled
    symbol table (matched labels and unmatched*.asm stubs), immediates from
    constants used in the same context in the existing source (unambiguous
    only; otherwise the literal stays with a TODO). Unknown targets become
    Sub_<addr> names, listed as stub suggestions at the end.
  * Header skeleton: entry state, exit widths at each return, the Callers
    block tools/callers.py generates from tools/xref.py's CONFIRMED sites
    (unconfirmed byte patterns in unmatched code go on a `Callers note`
    line with a TODO), callees,
    and the direct-page scratch it uses.
  * --check also runs the readability lint on the drafted routine in the
    temporary tree and prints what is left per rule.
"""

import argparse
import difflib
import textwrap
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from disasm import _OPCODES  # noqa: E402

ROM_PATH = ROOT / 'roms' / 'chrono_trigger.sfc'
INCLUDE = ROOT / 'asm' / 'include'
HARDWARE = ROOT / 'asm' / 'hardware.inc'

BRANCHES = {'BPL', 'BMI', 'BVC', 'BVS', 'BCC', 'BCS', 'BNE', 'BEQ'}
FLOW = BRANCHES | {'BRA', 'BRL', 'JMP', 'JML', 'JSR', 'JSL', 'PER'}
TERMINATORS = {'RTS', 'RTL', 'RTI', 'JMP', 'JML', 'BRA', 'BRL', 'STP'}
A_WRITERS = {'LDA', 'ADC', 'SBC', 'AND', 'ORA', 'EOR', 'TXA', 'TYA', 'TSC',
             'PLA', 'XBA', 'MVN', 'MVP'}
NO_SUFFIX = {'REP', 'SEP', 'MVN', 'MVP', 'BRK', 'COP', 'WDM'} | FLOW

# ── Addresses ───────────────────────────────────────────────────────────────


def parse_addr(text: str) -> int:
    t = text.strip().upper().replace('$', '').replace(':', '')
    if t.startswith('0X'):
        t = t[2:]
    v = int(t, 16)
    if v < 0x10000:
        raise SystemExit(f'address needs a bank: {text}')
    return v


def rom_offset(addr: int):
    bank, lo = addr >> 16, addr & 0xFFFF
    if bank >= 0xC0:
        return (bank - 0xC0) << 16 | lo
    if bank < 0x40 or 0x80 <= bank < 0xC0:
        if lo >= 0x8000:
            return (bank & 0x3F) << 16 | lo
    return None


def canon(addr: int) -> int:
    """Canonical bus address: WRAM as $7E/$7F, hardware as $00, ROM as $C0+."""
    bank, lo = addr >> 16, addr & 0xFFFF
    if bank in (0x7E, 0x7F):
        return addr
    if bank < 0x40 or 0x80 <= bank < 0xC0:
        if lo < 0x2000:
            return 0x7E0000 | lo
        if lo < 0x8000:
            return lo                     # hardware / open bus
        return (0xC0 | (bank & 0x3F)) << 16 | lo
    return addr


def fmt24(addr: int) -> str:
    return f'${addr >> 16:02X}:{addr & 0xFFFF:04X}'


# ── Knowledge: everything the tree already names ────────────────────────────

DEFINE = re.compile(r'^\s*!([A-Za-z_]\w*)\s*=\s*([^;]+?)\s*(?:;(.*))?$')
GLOBAL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):')
SIZE = re.compile(r'(?:^|[\s(])(\$[0-9A-Fa-f]+|\d+)(?:-(\d+))?\s*(B|bytes?|words?)\b')


def py_expr(text: str, lookup) -> int | None:
    """Evaluate an asar expression with known names; None when it can't."""
    t = text.strip()

    def sub_define(m):
        v = lookup('!' + m.group(1))
        if v is None:
            raise KeyError(m.group(1))
        return str(v)

    def sub_name(m):
        v = lookup(m.group(0))
        if v is None:
            raise KeyError(m.group(0))
        return str(v)
    try:
        for _ in range(8):
            if '!' not in t:
                break
            t = re.sub(r'!([A-Za-z_]\w*)', sub_define, t)
        t = re.sub(r'\$([0-9A-Fa-f]+)', lambda m: str(int(m.group(1), 16)), t)
        t = re.sub(r'%([01]+)', lambda m: str(int(m.group(1), 2)), t)
        t = re.sub(r'[A-Za-z_][A-Za-z0-9_]*(?:\[\d+\])?(?:\.[A-Za-z_]\w*)?', sub_name, t)
        if not re.fullmatch(r'[0-9+\-*/%&|^~<>() ]*', t):
            return None
        return int(eval(t.replace('/', '//'), {'__builtins__': {}}))
    except Exception:
        return None


class Knowledge:
    def __init__(self, bank: int, sym_text: str, family: str | None = None):
        self.bank = bank
        self.family = family or ('battle' if bank == 0xC1 else 'engine')
        self.pref = f'ram_{self.family}.inc'
        self.foreign = '_engine.inc' if self.family == 'battle' else '_battle.inc'
        self.stub_file = 'unmatched_battle.asm' if self.family == 'battle' else 'unmatched.asm'
        self.raw_defines: dict[str, str] = {}       # name -> rhs text (last wins)
        self.define_file: dict[str, str] = {}
        self.define_size: dict[str, int] = {}
        self.define_order: dict[str, int] = {}
        self.structs = []                           # (name, base, stride, [(field, off, size)])
        self.functions = []                         # (name, expr text, params)
        self.sym: dict[str, int] = {}               # every symbol asar printed
        self.addr_labels: dict[int, list[str]] = {}  # canonical ROM addr -> global labels
        self.local_labels: dict[int, list[str]] = {}
        self.hw: dict[int, str] = {}
        self.globals: set[str] = set()
        self.stubs: dict[str, Path] = {}            # stub label -> file
        self._parse_includes()
        self._parse_sources()
        self._parse_sym(sym_text)
        self._values: dict[str, int | None] = {}
        self._build_tables()

    # -- parsing --
    def _parse_includes(self):
        n = 0
        files = sorted(INCLUDE.glob('*.inc')) + [HARDWARE]
        for path in files:
            lines = path.read_text().splitlines()
            i = 0
            while i < len(lines):
                line = lines[i]
                m = DEFINE.match(line)
                if m and '?=' not in line:
                    name = m.group(1)
                    if name.endswith('_inc'):
                        i += 1
                        continue
                    self.raw_defines[name] = m.group(2)
                    self.define_file[name] = path.name
                    self.define_order[name] = n
                    n += 1
                    cm = SIZE.search(m.group(3) or '')
                    comment = m.group(3) or ''
                    if cm:
                        hi = cm.group(2)
                        val = cm.group(1)
                        size = int(val[1:], 16) if val.startswith('$') else int(val)
                        if hi:
                            size = int(hi)
                        if cm.group(3).startswith('word'):
                            size *= 2
                        self.define_size[name] = size
                    elif '16-bit' in comment:
                        self.define_size[name] = 2
                    elif '24-bit' in comment:
                        self.define_size[name] = 3
                sm = re.match(r'^struct\s+(\w+)\s+(\$[0-9A-Fa-f]+)', line)
                if sm:
                    fields, off = [], 0
                    i += 1
                    stride = None
                    while i < len(lines) and not lines[i].strip().startswith('endstruct'):
                        fm = re.match(r'^\s*(?:\.(\w+):)?\s*skip\s+(\$?[0-9A-Fa-f]+)', lines[i])
                        if fm:
                            sz = fm.group(2)
                            sz = int(sz[1:], 16) if sz.startswith('$') else int(sz)
                            if fm.group(1):
                                fields.append((fm.group(1), off, sz))
                            off += sz
                        i += 1
                    if i < len(lines):
                        am = re.search(r'align\s+(\$?[0-9A-Fa-f]+)', lines[i])
                        if am:
                            a = am.group(1)
                            stride = int(a[1:], 16) if a.startswith('$') else int(a)
                    self.structs.append((sm.group(1), int(sm.group(2)[1:], 16),
                                         stride or off, fields, path.name))
                fn = re.match(r'^function\s+(\w+)\(([^)]*)\)\s*=\s*([^;]+)', line)
                if fn:
                    self.functions.append((fn.group(1), [p.strip() for p in fn.group(2).split(',')],
                                           fn.group(3).strip(), path.name))
                hm = re.match(r'^([A-Z][A-Z0-9_]*)\s*=\s*\$([0-9A-Fa-f]+)', line)
                if hm and path == HARDWARE:
                    self.hw.setdefault(int(hm.group(2), 16), hm.group(1))
                i += 1
        for path in sorted(INCLUDE.glob('unmatched*.asm')):
            for line in path.read_text().splitlines():
                m = GLOBAL.match(line)
                if m:
                    self.stubs[m.group(1)] = path
                    self.globals.add(m.group(1))

    def _parse_sources(self):
        """Global labels, local aliases, callee exit states, call sites."""
        self.bank_defines: dict[str, str] = {}
        self.exit_state: dict[str, tuple] = {}
        self.source_lines: dict[str, list[str]] = {}   # global label -> its code lines
        for path in sorted((ROOT / 'asm').glob('bank*/*.asm')):
            lines = path.read_text().splitlines()
            current = None
            for i, line in enumerate(lines):
                m = DEFINE.match(line)
                if m:
                    self.bank_defines.setdefault(m.group(1), m.group(2))
                g = GLOBAL.match(line)
                if g:
                    current = g.group(1)
                    self.globals.add(current)
                    self.source_lines[current] = []
                    # Exit line(s) of the header above.
                    j, block = i - 1, []
                    while j >= 0 and (lines[j].startswith(';') or lines[j].strip().lower().startswith('org')
                                      or lines[j].startswith('!') or not lines[j].strip()):
                        if lines[j].startswith(';'):
                            block.append(lines[j])
                        j -= 1
                        if len(block) > 80:
                            break
                    block.reverse()
                    text, grab = '', False
                    for b in block:
                        s = b[1:].strip()
                        if re.match(r'(Entry/Exit|Exit)\b', s):
                            grab, text = True, s
                        elif grab and b.startswith(';  ') and not re.match(r'(Callers|Callees|Calls|Note)\b', s):
                            text += ' ' + s
                        else:
                            grab = False
                    if text:
                        em = re.search(r'\bM=([01])\b', text)
                        xm = re.search(r'\bX=([01])\b', text)
                        x = int(xm.group(1)) if xm else None
                        if x is None and re.search(r'X/Y 8-bit', text):
                            x = 1
                        if x is None and re.search(r'X/Y 16-bit', text):
                            x = 0
                        self.exit_state[current] = (int(em.group(1)) if em else None, x)
                elif current is not None:
                    self.source_lines[current].append(line)

    def _parse_sym(self, text: str):
        for line in text.splitlines():
            m = re.match(r'^([0-9A-F]{2}):([0-9A-F]{4}) (\S+)$', line)
            if not m:
                continue
            addr = int(m.group(1), 16) << 16 | int(m.group(2), 16)
            name = m.group(3)
            self.sym[name] = addr
            if '.' in name:
                continue
            if name in self.globals and (rom_offset(addr) is not None):
                self.addr_labels.setdefault(canon(addr), []).append(name)
            elif rom_offset(addr) is not None and name not in self.hw.values():
                self.local_labels.setdefault(canon(addr), []).append(name)

    # -- values --
    def value(self, ref: str) -> int | None:
        """Value of !Define, Struct.Field, Struct[i].Field or label."""
        if ref in self._values:
            return self._values[ref]
        self._values[ref] = None
        v = None
        if ref.startswith('!'):
            rhs = self.raw_defines.get(ref[1:]) or self.bank_defines.get(ref[1:])
            if rhs is not None:
                v = py_expr(rhs, self.value)
        else:
            am = re.match(r'^(\w+)\[(\d+)\]\.(\w+)$', ref)
            if am:
                for name, base, stride, fields, _ in self.structs:
                    if name == am.group(1):
                        for f, off, _sz in fields:
                            if f == am.group(3):
                                v = base + int(am.group(2)) * stride + off
            elif ref in self.sym:
                v = self.sym[ref]
                if (v >> 16) == 0 and '.' in ref:
                    v &= 0xFFFF
        self._values[ref] = v
        return v

    # -- lookup tables --
    def _build_tables(self):
        """canonical address -> [(text, raw value, priority)]"""
        t: dict[int, list] = {}

        def add(addr, text, raw, pri, order=0):
            t.setdefault(addr, []).append((pri, order, text, raw))

        for name, fname in self.define_file.items():
            if not fname.startswith('ram_') or fname.endswith(self.foreign):
                continue
            raw = self.value('!' + name)
            if raw is None:
                continue
            pref = 0 if fname == self.pref else 4
            order = self.define_order[name]
            if self.field_dp(name):
                base = 0x7E0100 + raw                # field dp offsets (DP_Field)
                kind = 'fielddp'
            else:
                base = (0x7E0000 | raw) if raw <= 0xFFFF else canon(raw)
                kind = 'abs'
            add(base, ('!' + name, kind), raw, pref, order)
            size = self.define_size.get(name, 1)
            for k in range(1, min(size, 0x40)):
                add(base + k, (f'!{name}+{k}', kind), raw + k, pref + 2, order)
        for name, base, stride, fields, fname in self.structs:
            if fname.endswith(self.foreign):
                continue
            pref = 1 if fname == self.pref else 5
            cb = canon(base) if base > 0xFFFF else (0x7E0000 | base)
            if base == 0:
                pref += 6                            # OamEntry-style relative records
            count = 1
            if stride:
                count = max(1, min(32, 0x800 // max(stride, 1)))
            for i in range(count):
                for f, off, sz in fields:
                    text = f'{name}.{f}' if i == 0 else f'{name}[{i}].{f}'
                    add(cb + i * stride + off, (text, 'abs'), base + i * stride + off, pref + (1 if i else 0))
                    for k in range(1, min(sz, 8)):
                        add(cb + i * stride + off + k, (f'{text}+{k}', 'abs'),
                            base + i * stride + off + k, pref + 2)
        for name, params, expr, fname in self.functions:
            if fname.endswith(self.foreign):
                continue
            pref = 3 if fname == self.pref else 6
            if len(params) != 2:
                continue
            for r in range(8):
                for c in range(32):
                    v = py_expr(expr.replace(params[0], f'({r})').replace(params[1], f'({c})'), self.value)
                    if v is not None:
                        cb = 0x7E0000 | v if v <= 0xFFFF else canon(v)
                        add(cb, (f'{name}({r},{c})', 'abs'), v, pref)
        for addr, name in self.hw.items():
            add(addr, (name, 'hw'), addr, 0)
        for addr, names in self.addr_labels.items():
            for name in names:
                add(addr, (name, 'label'), self.sym[name], 7)
        for v in t.values():
            v.sort(key=lambda e: (e[0], e[1]))
        self.table = t

    def nearest_below(self, addr, reach=0x40):
        """(name, raw, k): the closest define of our set below addr, nothing in between."""
        if not hasattr(self, '_sorted'):
            rows = []
            for name, fname in self.define_file.items():
                if fname != self.pref:
                    continue
                raw = self.value('!' + name)
                if raw is None:
                    continue
                cb = 0x7E0100 + raw if self.field_dp(name) else \
                    ((0x7E0000 | raw) if raw <= 0xFFFF else canon(raw))
                if not self.field_dp(name):
                    rows.append((cb, name, raw))
            self._sorted = sorted(rows)
        best = None
        for cb, name, raw in self._sorted:
            if cb > addr:
                break
            best = (cb, name, raw)
        if best and 0 < addr - best[0] < reach and best[1] not in self.define_size:
            return best[1], best[2], addr - best[0]
        return None

    def field_dp(self, name: str) -> bool:
        """Engine names written as a 1-2 digit value are offsets into !DP_Field."""
        return self.define_file.get(name) == 'ram_engine.inc' and \
            re.fullmatch(r'\$[0-9A-Fa-f]{1,2}', self.raw_defines[name].strip()) is not None

    def inside(self, addr) -> str:
        """Hint for an unnamed address that falls inside a known record or array."""
        if addr is None:
            return ''
        for name, base, stride, fields, fname in self.structs:
            if fname.endswith(self.foreign) or base == 0 or not stride:
                continue
            cb = canon(base) if base > 0xFFFF else (0x7E0000 | base)
            if cb <= addr < cb + stride * 16:
                i, off = divmod(addr - cb, stride)
                return f' (inside {name}' + (f'[{i}]' if i else '') + f', +${off:02X})'
        best = None
        for name, fname in self.define_file.items():
            if fname != self.pref:
                continue
            raw = self.value('!' + name)
            size = self.define_size.get(name)
            if raw is None or not size:
                continue
            cb = (0x7E0000 | raw) if raw <= 0xFFFF else canon(raw)
            if self.field_dp(name):
                cb = 0x7E0100 + raw
            if cb < addr < cb + size and (best is None or cb > best[1]):
                best = (name, cb)
        if best:
            return f' (inside !{best[0]}, +{addr - best[1]})'
        return ''

    def candidates(self, addr: int):
        return self.table.get(addr, [])

    def dp_names(self) -> dict[int, str]:
        """!DP_* define values -> name (for relocated direct pages)."""
        out = {}
        for name in self.define_file:
            if name.startswith('DP_'):
                v = self.value('!' + name)
                if v is not None:
                    out.setdefault(v, '!' + name)
        ram: dict[int, list] = {}
        for name, f in self.define_file.items():
            if f == self.pref:
                v = self.value('!' + name)
                if v is not None and 0 < v <= 0xFFFF and v not in out:
                    ram.setdefault(v, []).append('!' + name)
        for v, names in ram.items():
            if len(names) == 1:
                out[v] = names[0]
        return out

    def label_at(self, addr: int) -> str | None:
        names = self.addr_labels.get(canon(addr))
        if not names:
            return None
        stub_names = sorted((n for n in names if n in self.stubs),
                            key=lambda n: (self.stubs[n].name != self.stub_file, n))
        real = [n for n in names if n not in self.stubs]
        return (real or stub_names)[0]


# ── Constant corpus: immediates as the existing source names them ───────────

INSTR = re.compile(r'^\s+([A-Za-z]{3})(\.[bwlBWL])?\s*(.*?)\s*(?:;.*)?$')


def operand_base(text: str) -> str:
    t = text.strip()
    t = re.sub(r',\s*[XYSxys]\)?$', '', t)
    t = re.sub(r'\),\s*[Yy]$', ')', t)
    t = t.strip('()[]')
    t = re.sub(r',\s*[XxSs]$', '', t)
    return t


class Corpus:
    def __init__(self, kb: Knowledge, exclude=()):
        foreign = (kb.foreign,)

        def ours(text):
            for n in re.findall(r'!(\w+)', text):
                f = kb.define_file.get(n, '')
                if f.endswith(foreign):
                    return False
            return True
        self.ours = ours
        self.kb = kb
        self.k1: dict[tuple, set] = {}
        self.k2: dict[tuple, set] = {}
        self.k3: dict[tuple, dict] = {}
        self.by_value: dict[int, set] = {}
        self.dp_values: dict[int, set] = {}
        self.ram_values: dict[int, set] = {}
        self.bank_values: dict[int, set] = {}
        wraps = sorted(n for n in kb.define_file if kb.value('!' + n) == 0x10000
                       and kb.define_file[n].startswith('constants'))
        self.wrap_name = '!' + wraps[0] if wraps else None
        for n in kb.define_file:
            if 'Bank' in n and ours('!' + n):
                v = kb.value('!' + n)
                if v is not None and v <= 0xFF:
                    self.bank_values.setdefault(v, set()).add('!' + n)
        for n, f in kb.define_file.items():
            if f.startswith('ram_'):
                v = kb.value('!' + n)
                if v is not None and v <= 0xFFFF:
                    self.ram_values.setdefault(v, set()).add('!' + n)
        for n in kb.define_file:
            if n.startswith('DP_'):
                v = kb.value('!' + n)
                if v is not None:
                    self.dp_values.setdefault(v, set()).add('!' + n)
        consts = {n for n, f in kb.define_file.items()
                  if f.startswith('constants') or (f == 'hardware.inc' and not n.startswith('DP_'))}
        for n in consts:
            v = kb.value('!' + n)
            if v is not None and ours('!' + n):
                self.by_value.setdefault(v, set()).add('!' + n)
        for label, lines in kb.source_lines.items():
            if label in exclude:
                continue
            ins = []
            for line in lines:
                m = INSTR.match(line)
                if m and m.group(1).upper() in _MNEMS:
                    ins.append((m.group(1).upper(), m.group(3), (m.group(2) or '').lower()))
            for i, (mn, opnd, sfx) in enumerate(ins):
                if not opnd.startswith('#') or mn in ('REP', 'SEP') or '!' not in opnd:
                    continue
                text = opnd[1:].strip()
                if not ours(text):
                    continue
                v = py_expr(text, kb.value)
                if v is None:
                    continue
                v &= {'.b': 0xFF, '.w': 0xFFFF}.get(sfx, 0xFFFFFF)
                for j in (i - 1, i + 1):
                    if 0 <= j < len(ins) and ins[j][1] and not ins[j][1].startswith('#') \
                            and ins[j][0] not in FLOW:
                        a = py_expr(operand_base(ins[j][1]), kb.value)
                        if a is not None:
                            self.k1.setdefault((mn, a & 0xFFFF, v), set()).add(text)
                            self.k2.setdefault((a & 0xFFFF, v), set()).add(text)
                d = self.k3.setdefault((mn, v), {})
                d[text] = d.get(text, 0) + 1

    def name(self, mn: str, value: int, neighbours: list[int], next_mn=None):
        """(text or None, todo or None)"""
        if mn == 'LDA' and next_mn == 'TCD':
            dps = sorted(self.dp_values.get(value, ()))
            if not dps:
                dps = sorted(n for n in self.ram_values.get(value, ()) if self.ours(n))
            if len(dps) == 1:
                return dps[0], None
            if dps:
                return None, 'TODO: direct page? ' + ' / '.join(dps[:3])
        for table, key in ((self.k1, lambda a: (mn, a, value)), (self.k2, lambda a: (a, value))):
            found = set()
            for a in neighbours:
                found |= table.get(key(a), set())
            if len(found) == 1:
                return found.pop(), None
            if len(found) > 1:
                return None, 'TODO: constant? ' + ' / '.join(sorted(found)[:3])
        d = self.k3.get((mn, value), {})
        if K3 and value > 8 and len(d) == 1 and next(iter(d.values())) >= 2:
            return next(iter(d)), None
        cands = set(d) | self.by_value.get(value, set())
        if cands and value > 8:
            return None, 'TODO: constant? ' + ' / '.join(sorted(cands)[:3])
        if value > 8:
            return None, 'TODO: name this constant'
        return None, None


_MNEMS = {m for m, _ in _OPCODES.values()}
K3 = True


# ── Disassembly with state tracking ─────────────────────────────────────────

class State:
    __slots__ = ('m', 'x', 'dp', 'db', 'a_lo', 'a_hi', 'stack')

    def __init__(self, m, x, dp, db):
        self.m, self.x, self.dp, self.db = m, x, dp, db
        self.a_lo = self.a_hi = None
        self.stack = []

    def copy(self):
        s = State(self.m, self.x, self.dp, self.db)
        s.a_lo, s.a_hi, s.stack = self.a_lo, self.a_hi, list(self.stack)
        return s

    def key(self):
        return (self.m, self.x)

    def push(self, *vals):
        self.stack.extend(vals)

    def pop(self, n):
        out = []
        for _ in range(n):
            out.append(self.stack.pop() if self.stack else None)
        return out


def operand_size(mode, st):
    sizes = {'impl': 0, 'A': 0, 'imm': 1, 'dp': 1, 'dp_x': 1, 'dp_y': 1, 'dp_ind': 1,
             'dp_x_ind': 1, 'dp_ind_y': 1, 'dp_ind_long': 1, 'dp_ind_long_y': 1, 'sr': 1,
             'sr_ind_y': 1, 'abs': 2, 'abs_x': 2, 'abs_y': 2, 'abs_ind': 2, 'abs_x_ind': 2,
             'abs_ind_long': 2, 'long': 3, 'long_x': 3, 'rel': 1, 'rlong': 2, 'block': 2}
    if mode == 'imm_m':
        return None if st.m is None else (1 if st.m else 2)
    if mode == 'imm_x':
        return None if st.x is None else (1 if st.x else 2)
    return sizes[mode]


class Insn:
    def __init__(self, addr, op, mn, mode, n, val, st):
        self.addr, self.op, self.mn, self.mode, self.n, self.val = addr, op, mn, mode, n, val
        self.st = st                      # state before execution
        self.target = None                # flow target (24-bit)
        self.dead = False                 # decoded linearly, no path reaches it
        self.text = ''
        self.comment = ''


class Draft:
    def __init__(self, rom, kb, start, end, st0, name):
        self.rom, self.kb, self.start, self.end = rom, kb, start, end
        self.bank = start >> 16
        self.st0 = st0
        self.name = name
        self.insns: dict[int, Insn] = {}
        self.flags: list[str] = []
        self.flag_at: dict[int, str] = {}
        self.exits: list[tuple] = []
        self.fall_into = None
        self.dead_spans = []

    def byte(self, addr):
        return self.rom[rom_offset(addr)]

    def known_other(self, addr):
        """A global label (other than ours) starts here."""
        name = self.kb.label_at(addr)
        return name if (name and addr != self.start) else None

    def in_range(self, addr):
        if (addr >> 16) != self.bank:
            return False
        if self.end is not None:
            return self.start <= addr <= self.end
        return addr >= self.start

    def run(self):
        work = [(self.start, self.st0.copy())]
        seen: dict[int, tuple] = {}
        while work:
            addr, st = work.pop()
            while True:
                if not self.in_range(addr):
                    break
                if addr in seen:
                    if seen[addr] != st.key():
                        self.flag(addr, f'paths disagree on M/X here ({seen[addr]} vs {st.key()})')
                    break
                if self.end is None and addr != self.start and self.known_other(addr) \
                        and addr not in self.branch_targets():
                    self.fall_into = (addr, self.known_other(addr))
                    break
                ins, why = self.decode(addr, st)
                if ins is None:
                    self.flag(addr, why)
                    break
                mn, n = ins.mn, ins.n
                seen[addr] = st.key()
                self.insns[addr] = ins
                nxt = addr + 1 + n
                self.step(ins, st)
                if mn in BRANCHES:
                    if self.follow(ins.target, conditional=True):
                        work.append((ins.target, st.copy()))
                elif mn in ('BRA', 'BRL', 'JMP', 'JML') and ins.target is not None:
                    if self.follow(ins.target, conditional=False):
                        work.append((ins.target, st.copy()))
                if mn in TERMINATORS:
                    if mn in ('RTS', 'RTL', 'RTI'):
                        self.exits.append((addr, st.m, st.x))
                    break
                if st.m is None and st.x is None:
                    self.flag(nxt, 'M and X unknown; stopped')
                    break
                addr = nxt
        return self

    def decode(self, addr, st):
        op = self.byte(addr)
        mn, mode = _OPCODES[op]
        n = operand_size(mode, st)
        if n is None:
            return None, f'{"M" if mode == "imm_m" else "X"} width unknown here; stopped'
        if self.end is not None and addr + n > self.end:
            return None, 'instruction runs past the end address; stopped'
        val = 0
        for k in range(n):
            val |= self.byte(addr + 1 + k) << (8 * k)
        ins = Insn(addr, op, mn, mode, n, val, st.copy())
        nxt = addr + 1 + n
        pc_bank = addr & 0xFF0000
        if mode == 'rel':
            off = val - 256 if val >= 128 else val
            ins.target = pc_bank | ((nxt + off) & 0xFFFF)
        elif mode == 'rlong':
            off = val - 65536 if val >= 32768 else val
            ins.target = pc_bank | ((nxt + off) & 0xFFFF)
        elif mn in ('JMP', 'JSR') and mode == 'abs':
            ins.target = pc_bank | val
        elif mn in ('JML', 'JSL') and mode == 'long':
            ins.target = val
        return ins, None

    def fill_gaps(self):
        """Decode bytes no path reaches linearly, when they decode cleanly as code."""
        if not self.insns:
            return
        addrs = sorted(self.insns)
        last = addrs[-1] + 1 + self.insns[addrs[-1]].n
        stop = self.end + 1 if self.end is not None else last
        spans, pc = [], self.start
        for a in addrs + [stop]:
            if a > pc:
                spans.append((pc, a))
            if a in self.insns:
                pc = max(pc, a + 1 + self.insns[a].n)
        for lo, hi in spans:
            prev = max((a for a in self.insns if a < lo), default=None)
            st = (self.insns[prev].st if prev is not None else self.st0).copy()
            if prev is not None:
                self.step(self.insns[prev], st)
            new, pc, ok = [], lo, True
            while pc < hi:
                ins, _ = self.decode(pc, st)
                if ins is None or ins.mn in ('BRK', 'COP', 'WDM', 'STP') or pc + 1 + ins.n > hi:
                    ok = False
                    break
                ins.dead = True
                new.append(ins)
                self.step(ins, st)
                pc += 1 + ins.n
            if ok:
                for ins in new:
                    self.insns[ins.addr] = ins
                self.dead_spans.append((lo, hi))

    def branch_targets(self):
        return {i.target for i in self.insns.values() if i.target is not None}

    def follow(self, target, conditional):
        if target is None or not self.in_range(target) or target < self.start:
            return False
        if self.known_other(target):
            return False
        if conditional or self.end is not None:
            return True
        # unconditional and open-ended: only nearby forward/backward code
        return abs(target - self.start) < 0x800

    def flag(self, addr, msg):
        self.flags.append(f'{fmt24(addr)}: {msg}')
        self.flag_at.setdefault(addr, msg)

    def step(self, ins, st):
        mn, val = ins.mn, ins.val
        if mn == 'REP':
            if val & 0x20:
                st.m = 0
            if val & 0x10:
                st.x = 0
        elif mn == 'SEP':
            if val & 0x20:
                st.m = 1
            if val & 0x10:
                st.x = 1
        elif mn == 'PHP':
            st.push(('P', st.m, st.x))
        elif mn == 'PLP':
            p = st.pop(1)[0]
            if isinstance(p, tuple) and p[0] == 'P':
                st.m, st.x = p[1], p[2]
            else:
                st.m = st.x = None
                self.flag(ins.addr, 'PLP without a matching PHP: M/X unknown after it')
        elif mn == 'PHB':
            st.push(st.db)
        elif mn == 'PHK':
            st.push(ins.addr >> 16)
        elif mn == 'PLB':
            v = st.pop(1)[0]
            st.db = v if isinstance(v, int) else None
            if st.db is None:
                self.flag(ins.addr, 'PLB of an unknown value: DB unknown after it')
        elif mn == 'PHD':
            st.push(None if st.dp is None else st.dp >> 8, None if st.dp is None else st.dp & 0xFF)
        elif mn == 'PLD':
            lo, hi = st.pop(2)
            st.dp = (hi << 8 | lo) if isinstance(lo, int) and isinstance(hi, int) else None
        elif mn == 'TCD':
            st.dp = (st.a_hi << 8 | st.a_lo) if st.a_lo is not None and st.a_hi is not None else None
        elif mn == 'PHA':
            if st.m == 0:
                st.push(st.a_hi, st.a_lo)
            else:
                st.push(st.a_lo)
        elif mn in ('PHX', 'PHY'):
            st.push(*([None] if st.x else [None, None]))
        elif mn in ('PEA', 'PEI', 'PER'):
            st.push(None, None)
        elif mn in ('PLX', 'PLY'):
            st.pop(1 if st.x else 2)
        if mn == 'PLA':
            st.pop(1 if st.m else 2)
        if mn == 'LDA' and ins.mode == 'imm_m':
            st.a_lo = val & 0xFF
            if st.m == 0:
                st.a_hi = val >> 8
        elif mn == 'TDC':
            st.a_lo = None if st.dp is None else st.dp & 0xFF
            st.a_hi = None if st.dp is None else st.dp >> 8
        elif mn in A_WRITERS or (ins.mode == 'A') or mn in ('JSR', 'JSL'):
            st.a_lo = st.a_hi = None
        if mn in ('JSR', 'JSL'):
            if ins.mode in ('abs', 'long'):
                tgt = (ins.addr & 0xFF0000 | ins.val) if mn == 'JSR' else ins.val
                name = self.kb.label_at(tgt)
                ex = self.kb.exit_state.get(name or '', (None, None))
                if ex[0] is not None:
                    st.m = ex[0]
                if ex[1] is not None:
                    st.x = ex[1]


# ── Rendering ───────────────────────────────────────────────────────────────

class Renderer:
    def __init__(self, d: Draft, corpus: Corpus):
        self.d, self.kb, self.corpus = d, d.kb, corpus
        self.stubs: dict[int, list] = {}
        self.callees: list[str] = []
        self.scratch: list[str] = []
        self.dp_names = self.kb.dp_names()
        self.labels: dict[int, str] = {}    # addr -> label text at that address
        self.scope_of: dict[int, str] = {}

    def stub(self, addr, why):
        name = f'Sub_{addr >> 16:02X}{addr & 0xFFFF:04X}'
        self.stubs.setdefault(addr, [name, []])[1].append(why)
        return name

    def plan_labels(self):
        d = self.d
        addrs = sorted(d.insns)
        globals_in = {a: self.kb.label_at(a) for a in addrs if a != d.start and self.kb.label_at(a)}
        self.labels[d.start] = d.name
        for a, n in globals_in.items():
            self.labels[a] = n
        scope = d.name
        targets = d.branch_targets()
        for a in addrs:
            if a in self.labels:
                scope = self.labels[a]
            elif a in targets:
                self.labels[a] = f'.loc_{a & 0xFFFF:04X}'
            self.scope_of[a] = scope

    def target_text(self, ins, target, why):
        d = self.d
        if target in d.insns and target in self.labels:
            lab = self.labels[target]
            if lab.startswith('.') and self.scope_of[target] != self.scope_of[ins.addr]:
                return f'{self.scope_of[target]}_{lab[1:]}'
            return lab
        if rom_offset(target) is None:
            nm, _ = self.mem_text(ins, 'long', target)
            if nm:
                return nm
        name = self.kb.label_at(target)
        if name:
            return name
        locs = self.kb.local_labels.get(canon(target))
        if locs:
            return locs[0]
        return self.stub(target, why)

    def mem_text(self, ins, kind, value):
        """Name for a memory operand. kind: dp / abs / long. Returns (text, note)."""
        st = ins.st
        if kind == 'dp':
            if st.dp is None:
                return None, 'TODO: DP unknown here'
            full = (st.dp + value) & 0xFFFF
            addr = canon(full)
            want, mask = value, 0xFF
        elif kind == 'abs':
            if st.db is None:
                return None, 'TODO: DB unknown here'
            addr = canon(st.db << 16 | value)
            want, mask = value, 0xFFFF
        else:
            addr = canon(value)
            want, mask = value, 0xFFFFFF
        cands = self.kb.candidates(addr)
        if kind == 'dp':
            # field dp offsets only when DP is the field page; hw only via !DP_
            cands = [c for c in cands if c[2][1] != 'label']
        if kind != 'dp':
            cands = [c for c in cands if c[2][1] != 'fielddp'] + \
                [c for c in cands if c[2][1] == 'fielddp']
        best = []
        for pri, order, (text, ckind), raw in cands:
            if kind == 'dp':
                if ckind == 'fielddp':
                    if st.dp != 0x0100:
                        continue
                    expr, ev = text, raw
                elif st.dp == 0:
                    expr, ev = text, raw
                else:
                    dpn = self.dp_names.get(st.dp, f'${st.dp:04X}')
                    expr, ev = f'{text}-{dpn}', raw - st.dp
            elif ckind == 'fielddp':
                dpn = self.dp_names.get(0x0100, '$0100')
                expr, ev = f'{dpn}+{text}', 0x0100 + raw
            else:
                expr, ev = text, raw
            if (ev & mask) != (want & mask):
                if kind == 'long' and (ev & 0xFFFF) == (want & 0xFFFF) and ev <= 0xFFFF:
                    expr = f'{expr}|${want & 0xFF0000:06X}'
                else:
                    continue
            best.append((pri, order, expr))
        if not best and kind != 'dp' or (not best and st.dp == 0):
            near = self.kb.nearest_below(addr)
            if near:
                name, raw, k = near
                ev = raw + k
                expr = f'!{name}+{k}'
                if (ev & mask) == (want & mask):
                    return expr, f'TODO: check: {k} past !{name} (beyond its stated size)'
                if kind == 'long' and ((ev & 0xFFFF) == (want & 0xFFFF)) and ev <= 0xFFFF:
                    return f'{expr}|${want & 0xFF0000:06X}', f'TODO: check: {k} past !{name}'
        if not best:
            return None, None
        best.sort()
        top = [b for b in best if b[0] == best[0][0]]
        note = None
        if len(top) > 1:
            others = [b[2] for b in top[1:4]]
            note = 'TODO: also ' + ', '.join(others)
        return top[0][2], note

    def next_mn(self, ins):
        nxt = self.d.insns.get(ins.addr + 1 + ins.n)
        return nxt.mn if nxt else None

    @staticmethod
    def full_addr(ins, kind, val):
        st = ins.st
        if kind == 'dp':
            return None if st.dp is None else canon((st.dp + val) & 0xFFFF)
        if kind == 'abs':
            return None if st.db is None else canon(st.db << 16 | val)
        return canon(val)

    def neighbour_addrs(self, ins):
        out = []
        addrs = sorted(self.d.insns)
        i = addrs.index(ins.addr)
        for j in (i - 1, i + 1):
            if 0 <= j < len(addrs):
                o = self.d.insns[addrs[j]]
                if o.mode.startswith('dp') and o.st.dp is not None:
                    out.append((o.st.dp + o.val) & 0xFFFF)
                elif o.mode.startswith('abs') or o.mode.startswith('long'):
                    if o.mn not in FLOW:
                        out.append(o.val & 0xFFFF)
                # dp operands in the corpus are written as their define (raw value)
                if o.mode.startswith('dp') and o.st.dp is not None and o.st.dp != 0:
                    out.append(o.val)
        return out

    def render(self, ins):
        mn, mode, val, st = ins.mn, ins.mode, ins.val, ins.st
        notes = []
        sfx = ''
        if mode == 'impl':
            return mn, ''
        if mode == 'A':
            return f'{mn} A', ''
        if mn in ('JSR', 'JMP', 'JSL', 'JML') and mode in ('abs', 'long'):
            t = self.target_text(ins, ins.target, f'{mn} from {self.d.name}')
            if mn in ('JSR', 'JSL') and t not in self.callees:
                self.callees.append(t)
            return f'{mn} {t}', ''
        if mode in ('rel', 'rlong'):
            t = self.target_text(ins, ins.target, f'{mn} from {self.d.name}')
            dist = ins.target - (ins.addr + 1 + ins.n)
            if mode == 'rlong' and abs(dist) > 0x7FFF:
                wrap = self.corpus.wrap_name or '$10000'
                return f'{mn} {t}{"-" if dist > 0 else "+"}{wrap}', 'offset wraps around the bank'
            return f'{mn} {t}', ''
        if mode in ('imm', 'imm_m', 'imm_x'):
            n = ins.n
            lit = f'${val:0{2 * n}X}'
            if mn in ('REP', 'SEP'):
                return f'{mn} #{lit}', ''
            if mn in ('BRK', 'COP', 'WDM'):
                return f'{mn} #{lit}', 'TODO: BRK/COP/WDM in code: data?'
            sfx = '.b' if n == 1 else '.w'
            name, todo = self.corpus.name(mn, val, self.neighbour_addrs(ins), self.next_mn(ins))
            if name:
                return f'{mn}{sfx} #{name}', ''
            return f'{mn}{sfx} #{lit}', todo or ''
        if mode == 'block':
            a, b = val & 0xFF, val >> 8
            names = []
            for v in (a, b):
                c = sorted(n for n in self.corpus.bank_values.get(v, set()))
                names.append(c[0] if len(c) == 1 else f'${v:02X}')
            return f'{mn} {names[0]},{names[1]}', 'lint-ok: MVN/MVP operands are bank bytes; TODO: check'
        if mode in ('sr', 'sr_ind_y'):
            body = f'${val:02X},S' if mode == 'sr' else f'(${val:02X},S),Y'
            return f'{mn}.b {body}', 'TODO: stack-relative'
        if mode.startswith('dp') or mn == 'PEI':
            kind, sfx, w = 'dp', '.b', 2
        elif mode.startswith('long'):
            kind, sfx, w = 'long', '.l', 6
        else:
            kind, sfx, w = 'abs', '.w', 4
        if mn in ('JMP', 'JSR', 'JML') and mode in ('abs_ind', 'abs_x_ind', 'abs_ind_long'):
            if mode == 'abs_x_ind':
                t = self.kb.label_at(ins.addr & 0xFF0000 | val)
                body = t or f'${val:04X}'
                if t:
                    return f'{mn} ({body},X)', ''
                off = rom_offset(ins.addr & 0xFF0000 | val)
                words = ' '.join(f'${self.d.rom[off + 2 * k] | self.d.rom[off + 2 * k + 1] << 8:04X}'
                                 for k in range(4))
                return f'{mn} ({body},X)', f'TODO: jump table: name it (first words {words})'
            st_db = st.db                   # (abs) and [abs] read bank 0
            st.db = 0
            name, note = self.mem_text(ins, 'abs', val)
            st.db = st_db
            body = name or f'${val:04X}'
            return (f'{mn} ({body})' if mode == 'abs_ind' else f'{mn} [{body}]'), note or ''
        if mn == 'PEA':
            name, todo = self.corpus.name(mn, val, [])
            return f'PEA.w #{name or f"${val:04X}"}', todo or ''
        name, note = self.mem_text(ins, kind, val)
        if name and re.fullmatch(r'!BattleTmp_\w+', name) and name not in self.scratch:
            self.scratch.append(name)
        body = name or f'${val:0{w}X}'
        if name is None and not note:
            note = 'TODO: unnamed' + self.kb.inside(self.full_addr(ins, kind, val))
        fmt = {'dp': '{}', 'dp_x': '{},X', 'dp_y': '{},Y', 'dp_ind': '({})', 'dp_x_ind': '({},X)',
               'dp_ind_y': '({}),Y', 'dp_ind_long': '[{}]', 'dp_ind_long_y': '[{}],Y',
               'abs': '{}', 'abs_x': '{},X', 'abs_y': '{},Y', 'long': '{}', 'long_x': '{},X'}[mode]
        if mn == 'PEI':
            fmt = '({})'
        return f'{mn}{sfx} {fmt.format(body)}', note or ''


# ── Callers ─────────────────────────────────────────────────────────────────

def find_callers(start, end):
    """Call sites of the routine from tools/xref.py: [(addr, kind, routine, status, hit)].

    CONFIRMED sites and DOUBTFUL ones in unmatched code (a byte pattern whose
    boundary the sweep could not establish) are kept; a DOUBTFUL site inside
    matched code is proven not to be an instruction and is dropped, and so
    are sites inside the region itself.
    """
    import xref
    xr = xref.Xref()
    out = []
    for h in xr.xref(rom_offset(start)):
        addr = 0xC00000 + h.offset
        if start <= addr <= end:
            continue
        if h.status == 'CONFIRMED' or not h.routine:
            out.append((addr, h.kind, h.routine, h.status, h))
    return out


# ── Output ──────────────────────────────────────────────────────────────────

def state_text(m, x, dp, db):
    f = lambda v: '?' if v is None else str(v)  # noqa: E731
    dps = '?' if dp is None else (f'${dp:04X}' if dp else '0')
    dbs = '?' if db is None else f'${db:02X}'
    return f'M={f(m)}, X={f(x)}, DP={dps}, DB={dbs}'


def generate(rom, kb, args, start, end, st0):
    name = args.name or kb.label_at(start) or f'Sub_{start >> 16:02X}{start & 0xFFFF:04X}'
    d = Draft(rom, kb, start, end, st0, name).run()
    d.fill_gaps()
    if not d.insns:
        raise SystemExit('nothing decoded at the start address')
    hi = end if end is not None else max(a + d.insns[a].n for a in d.insns)
    # Leave the region's own source (if it is already matched) out of the
    # constant corpus, so a draft of matched code shows what new code gets.
    own = {n for n, a in kb.sym.items() if n in kb.source_lines and start <= canon(a) <= hi}
    corpus = Corpus(kb, exclude=own)
    r = Renderer(d, corpus)
    r.plan_labels()
    addrs = sorted(d.insns)
    if not addrs:
        raise SystemExit('nothing decoded at the start address')
    last = max(a + 1 + d.insns[a].n for a in addrs) - 1
    region_end = end if end is not None else last
    body = []
    pc = start
    todo = 0
    for a in addrs:
        if a > pc:
            body.append(f'    ; TODO: {a - pc} byte(s) no path reaches ({fmt24(pc)}): data or dead code')
            body.append('    db ' + ','.join(f'${d.byte(pc + k):02X}' for k in range(a - pc)))
            todo += 1
        ins = d.insns[a]
        if any(lo == a for lo, _ in d.dead_spans):
            span = next(hi for lo, hi in d.dead_spans if lo == a)
            body.append(f'    ; TODO: no path reaches {fmt24(a)}–{fmt24(span - 1)} (dead code, or data '
                        'decoded as code): check')
            todo += 1
        if a in r.labels:
            lab = r.labels[a]
            if lab.startswith('.'):
                body.append(f'{lab}:')
            elif a != start:
                body.append('')
                body.append(f'{lab}:                  ; TODO: entry point inside this routine')
                todo += 1
        text, note = r.render(ins)
        if a in d.flag_at:
            note = (note + '; ' if note else '') + 'TODO: ' + d.flag_at[a]
        line = f'    {text}'
        if note:
            line = f'{line:<40}; {note}'
            todo += note.count('TODO')
        body.append(line)
        pc = a + 1 + ins.n
    if end is not None and pc <= end:
        body.append(f'    ; TODO: {end - pc + 1} byte(s) no path reaches ({fmt24(pc)}): data or dead code')
        body.append('    db ' + ','.join(f'${d.byte(pc + k):02X}' for k in range(end - pc + 1)))
        todo += 1
        region_end = end
    if d.fall_into:
        body.append(f'    ; falls through into {d.fall_into[1]} ({fmt24(d.fall_into[0])})')
    for a, msg in sorted(d.flag_at.items()):
        if a not in d.insns:
            body.append(f'    ; TODO: {fmt24(a)}: {msg}')
            todo += 1
    stopped = any('stopped' in m for m in d.flag_at.values())

    size = region_end - start + 1
    callers = [] if args.no_callers else find_callers(start, region_end)
    hdr = [
        f'; {fmt24(start)} — {name} ({size} bytes, ${start & 0xFFFF:04X}–${region_end & 0xFFFF:04X})',
        '; TODO: what it is for (one paragraph), and what each name below means.',
        f'; Entry: {state_text(st0.m, st0.x, st0.dp, st0.db)} (assumed by the draft: --m/--x/--dp/--db)',
    ]
    if stopped:
        hdr.append('; Exit:  TODO (the draft stopped early: see the TODOs at the end)')
    elif d.exits:
        ex = sorted({(m, x) for _, m, x in d.exits}, key=str)
        hdr.append('; Exit:  TODO (at the return: ' + '; '.join(f'M={m}, X={x}' for m, x in ex) + ')')
    elif d.fall_into:
        hdr.append(f'; Exit:  falls through into {d.fall_into[1]}')
    else:
        hdr.append('; Exit:  TODO (no return: ends in a jump)')
    if callers:
        # The block tools/callers.py generates (rerun it once the routine is
        # in the tree); what it cannot confirm goes on a hand-written note.
        import callers as callers_tool
        hdr += callers_tool.render([c[4] for c in callers if c[3] == 'CONFIRMED'])
        unsure = [c for c in callers if c[3] != 'CONFIRMED']
        if unsure:
            text = 'TODO check these unconfirmed byte patterns (real calls, or data?): ' + \
                ', '.join(f'{c[1]} {fmt24(c[0])}' for c in unsure[:8]) + \
                (f' and {len(unsure) - 8} more' if len(unsure) > 8 else '')
            wrapped = textwrap.wrap(text, 84)
            hdr.append('; Callers note: ' + wrapped[0])
            hdr += [';               ' + w for w in wrapped[1:]]
    elif not args.no_callers:
        hdr.append('; Callers note: none found by the ROM scan (TODO: pointer table / indirect?)')
    hdr.append('; Callees: ' + (', '.join(r.callees) if r.callees else 'none'))
    if r.scratch:
        hdr.append('; Direct-page roles (TODO: give each an alias here, as the other routines do):')
        for n in sorted(r.scratch):
            hdr.append(f'; !{name}_Unk{n.rsplit("_", 1)[1]} = {n}')
    out = [
        '; ' + '=' * 66,
        f'; DRAFT from tools/draft.py ({fmt24(start)}–{fmt24(region_end)}). Assembles byte-exact;',
        '; every TODO below still needs a human: names, constants, comments.',
        '; ' + '=' * 66,
    ] + hdr + [f'org ${start:06X}', f'{name}:'] + body
    if r.stubs:
        unm = kb.stub_file
        out += ['', f'; ---- stubs needed (asm/include/{unm}, or the address of a label the',
                ';      draft could not resolve) ----']
        for addr in sorted(r.stubs):
            nm, why = r.stubs[addr]
            out.append(f'; org ${addr:06X}')
            out.append(f'; {nm}:{" " * max(1, 18 - len(nm))}; {why[0]}')
    todo += sum(1 for line in out[:len(hdr) + 6] if 'TODO' in line)
    info = {'name': name, 'start': start, 'end': region_end, 'todo': todo, 'flags': d.flags,
            'stubs': r.stubs, 'draft': d, 'renderer': r, 'callers': callers}
    return '\n'.join(out) + '\n', info


# ── Check: assemble the draft in place of the region ────────────────────────

def source_chunks(path: Path):
    """[(label, first line, end line)]: each routine's lines as tools/asm_source.py cuts them."""
    import asm_source
    regions = asm_source.file_regions(path)
    lines = regions[0].lines if regions else path.read_text().splitlines()
    return lines, [(r.name, r.start, r.end) for r in regions]


def assemble(tree: Path, fill: int | None, rom: bytes, out: Path):
    out.write_bytes(rom if fill is None else bytes([fill]) * len(rom))
    r = subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', 'asm/main.asm', str(out)],
                       cwd=tree, capture_output=True, text=True)
    return r


def check(text, info, kb, rom):
    start, end = info['start'], info['end']
    bank = start >> 16
    with tempfile.TemporaryDirectory() as tmp:
        tree = Path(tmp) / 'tree'
        tree.mkdir()
        for item in ('asm', 'tools', 'Makefile'):
            src = ROOT / item
            if src.is_dir():
                shutil.copytree(src, tree / item)
            else:
                shutil.copy(src, tree / item)
        (tree / 'roms').mkdir()
        os.symlink(ROM_PATH, tree / 'roms' / 'chrono_trigger.sfc')
        draft_lines = text.splitlines()
        defined = {m.group(1) for m in (GLOBAL.match(l) for l in draft_lines) if m}
        bankfile, cut, lines = None, [], []
        for path in sorted((tree / 'asm').glob('bank*/*.asm')):
            plines, chunks = source_chunks(path)
            c = [(lab, a, b) for lab, a, b in chunks
                 if lab in kb.sym and start <= canon(kb.sym[lab]) <= end]
            if c:
                bankfile, cut, lines = path, c, plines
                break
        if bankfile is None:
            bankfile = tree / 'asm' / f'bank{bank:02X}' / f'bank{bank:02X}.asm'
            if not bankfile.exists():
                return False, f'no bank file for ${bank:02X}'
            lines = bankfile.read_text().splitlines()

        def directive(l):
            st = l.strip()
            return bool(st) and not st.startswith(';') and not l[:1].isspace() \
                and not GLOBAL.match(l) and not st.startswith('.') and not st.lower().startswith('org')
        if cut:
            drop = set()
            for _lab, a, b in cut:
                drop |= {i for i in range(a, b) if not directive(lines[i])}
            # after the chunk's own directives (arch, hirom, incsrc, defines)
            last_dir = max((i for i in range(cut[0][1], cut[0][2]) if directive(lines[i])), default=-1)
            first = min(i for i in drop if i > last_dir) if any(i > last_dir for i in drop) else min(drop)
            new = []
            for i, l in enumerate(lines):
                if i == first:
                    new += [''] + draft_lines + ['']
                if i not in drop:
                    new.append(l)
        else:
            new = lines + [''] + draft_lines
        bankfile.write_text('\n'.join(new) + '\n')
        # stubs: drop ones the draft now defines, add the ones it needs
        for path in (tree / 'asm' / 'include').glob('unmatched*.asm'):
            src = path.read_text().splitlines()
            outl, i = [], 0
            while i < len(src):
                if src[i].startswith('org') and i + 1 < len(src):
                    m = GLOBAL.match(src[i + 1])
                    if m and m.group(1) in defined:
                        i += 2
                        continue
                outl.append(src[i])
                i += 1
            if path.name == kb.stub_file:
                for addr, (nm, _why) in sorted(info['stubs'].items()):
                    if nm not in defined:
                        outl += [f'org ${addr:06X}', f'{nm}:']
            path.write_text('\n'.join(outl) + '\n')
        r = subprocess.run(['make', '-s', 'diff'], cwd=tree, capture_output=True, text=True)
        report = (r.stdout + r.stderr).strip()
        if r.returncode != 0:
            first = re.search(r'0x([0-9A-F]{6}) - 0x([0-9A-F]{6})', report)
            msg = report.splitlines()[-6:]
            if first:
                off = int(first.group(1), 16)
                addr = 0xC00000 + off
                d = info['draft']
                near = max((a for a in d.insns if a <= addr), default=None)
                where = ''
                if near is not None:
                    ins = d.insns[near]
                    where = f' (draft instruction at {fmt24(near)}: {info["renderer"].render(ins)[0]})'
                return False, f'make diff: first mismatch at {fmt24(addr)}{where}\n' + '\n'.join(msg)
            return False, 'make diff failed:\n' + '\n'.join(msg)
        # coverage: every byte of the region emitted by source
        lo_rom = Path(tmp) / 'lo.sfc'
        hi_rom = Path(tmp) / 'hi.sfc'
        for fill, out in ((0x00, lo_rom), (0xFF, hi_rom)):
            a = assemble(tree, fill, rom, out)
            if a.returncode != 0:
                return False, a.stdout + a.stderr
        lo_b, hi_b = lo_rom.read_bytes(), hi_rom.read_bytes()
        s, e = rom_offset(start), rom_offset(end)
        for off in range(s, e + 1):
            if lo_b[off] != hi_b[off]:
                return False, f'byte at {fmt24(0xC00000 + off)} is not emitted by the draft'
            if lo_b[off] != rom[off]:
                return False, f'first mismatch at {fmt24(0xC00000 + off)} (blank base)'
        msg = f'make diff: {report.splitlines()[-1]}; all {e - s + 1} bytes of ' \
              f'{fmt24(start)}–{fmt24(end)} emitted by the draft'
        found = []
        for n in sorted(defined):
            lint = subprocess.run([sys.executable, 'tools/lint_readability.py', '--show', n],
                                  cwd=tree, capture_output=True, text=True)
            found += [l for l in lint.stdout.splitlines() if l.strip()]
        rules = {}
        for l in found:
            m = re.search(r'\b(ADDR|CALL|CONST|WIDTH|OPCODE|PLUMB|HEADER|CALLERS)\b', l)
            if m:
                rules[m.group(1)] = rules.get(m.group(1), 0) + 1
        msg += '\nlint (what is left for the readability standard): ' + \
            (', '.join(f'{k} {v}' for k, v in sorted(rules.items())) if rules else 'clean')
        return True, msg


# ── Compare with hand-written source ────────────────────────────────────────

def compare(text, info, kb):
    """Operand-by-operand comparison with the source that already covers the region."""
    def instrs(lines):
        out = []
        for l in lines:
            code = l.split(';')[0]
            m = re.match(r'^(?:[A-Za-z_]\w*:|\.[\w]+:)?\s+([A-Za-z]{3})(\.[bwl])?\s*(.*)$', code)
            if m and m.group(1).upper() in _MNEMS:
                out.append((m.group(1).upper(), re.sub(r'\s+', '', m.group(3))))
            elif re.match(r'^\s+d[bwl]\s', code):
                out.append(('DB', code.strip()))
        return out
    start, end = info['start'], info['end']
    hand = []
    for lab in sorted((n for n in kb.source_lines if n in kb.sym and start <= canon(kb.sym[n]) <= end),
                      key=lambda n: kb.sym[n]):
        hand += instrs(kb.source_lines[lab])
    mine = instrs(text.splitlines())
    same = named = total = equiv = 0
    diffs = []

    sm = difflib.SequenceMatcher(a=[h[0] for h in hand], b=[m[0] for m in mine], autojunk=False)
    pairs = []
    for blk in sm.get_matching_blocks():
        pairs += [(hand[blk.a + k], mine[blk.b + k]) for k in range(blk.size)]
    for (hm, ho), (dm, do) in pairs:
        if not ho or ho.startswith('.') or hm in BRANCHES | {'BRA', 'BRL'}:
            continue
        total += 1
        hn = '!' in ho or re.search(r'[A-Za-z]', ho.replace(',X', '').replace(',Y', '').replace(',S', ''))
        if hn:
            named += 1
        if ho == do:
            same += 1
            equiv += 1
            continue
        hv = py_expr(operand_base(ho.lstrip('#')), kb.value)
        dv = py_expr(operand_base(do.lstrip('#')), kb.value)
        if not ho.startswith('#') and hv is not None and dv is not None \
                and (hv & 0xFFFF) == (dv & 0xFFFF) and '!' in do:
            equiv += 1
            diffs.append(f'  alias  {hm} {ho}  <->  {do}')
        else:
            diffs.append(f'  differ {hm} {ho}  <->  {do}')
    return {'hand': len(hand), 'draft': len(mine), 'operands': total, 'same': same,
            'equiv': equiv, 'diffs': diffs}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('start')
    ap.add_argument('end', nargs='?')
    ap.add_argument('--m', type=int, choices=(0, 1), default=1)
    ap.add_argument('--x', type=int, choices=(0, 1), default=0)
    ap.add_argument('--dp', default='0')
    ap.add_argument('--db', default='7E')
    ap.add_argument('--name')
    ap.add_argument('--names', choices=('battle', 'engine'),
                    help='which RAM/constant set to name from (default: battle for $C1, else engine)')
    ap.add_argument('-o', '--output')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--compare', action='store_true')
    ap.add_argument('--no-callers', action='store_true')
    args = ap.parse_args()

    os.chdir(ROOT)
    start = parse_addr(args.start)
    end = parse_addr(args.end) if args.end else None
    if rom_offset(start) is None:
        raise SystemExit('start is not a ROM address')
    rom = ROM_PATH.read_bytes()

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / 'sym.sfc'
        out.write_bytes(rom)
        sym = Path(tmp) / 'out.sym'
        r = subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', '--symbols=wla',
                            f'--symbols-path={sym}', 'asm/main.asm', str(out)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stdout + r.stderr)
            return 2
        sym_text = sym.read_text()
    kb = Knowledge(start >> 16, sym_text, args.names)
    st0 = State(args.m, args.x, int(args.dp.replace('$', ''), 16), int(args.db.replace('$', ''), 16))
    text, info = generate(rom, kb, args, start, end, st0)

    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(text)
        print(f'draft -> {args.output}', file=sys.stderr)
    else:
        sys.stdout.write(text)
    print(f'{info["name"]}: {fmt24(info["start"])}–{fmt24(info["end"])}, '
          f'{len(info["draft"].insns)} instructions, {info["todo"]} TODO(s), '
          f'{len(info["stubs"])} stub(s) needed', file=sys.stderr)
    for f in info['flags']:
        print(f'  flag: {f}', file=sys.stderr)
    for addr, (nm, why) in sorted(info['stubs'].items()):
        print(f'  stub: org ${addr:06X} / {nm}:  ; {why[0]}', file=sys.stderr)
    rc = 0
    if args.compare:
        c = compare(text, info, kb)
        if not c['hand']:
            print('compare: no hand-written source covers this region', file=sys.stderr)
        else:
            print(f'compare: {c["operands"]} non-branch operands; identical text {c["same"]} '
                  f'({100 * c["same"] / max(1, c["operands"]):.0f}%), identical or another name for the same address '
                  f'{c["equiv"]} ({100 * c["equiv"] / max(1, c["operands"]):.0f}%); instructions '
                  f'hand {c["hand"]} / draft {c["draft"]}', file=sys.stderr)
            for line in c['diffs']:
                print(line, file=sys.stderr)
    if args.check:
        ok, msg = check(text, info, kb, rom)
        print(('CHECK OK: ' if ok else 'CHECK FAILED: ') + msg, file=sys.stderr)
        rc = 0 if ok else 1
    return rc


if __name__ == '__main__':
    sys.exit(main())
