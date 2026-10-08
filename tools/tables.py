#!/usr/bin/env python3
"""
tables.py — Find data tables near matched code and print them as source.

Many unmatched byte ranges next to matched routines are tables: word jump
tables used by JMP (abs,X) / JSR (abs,X) / push-and-RTS dispatch, long
pointer tables, byte lookup tables and fixed-size records. They are cheap to
match once found; this tool finds them and writes the first draft.

  scan   Lists candidate tables in the unmatched bytes of a bank, ranked by
         confidence (0-1):
           words  runs of little-endian words whose targets are labels,
                  instruction starts in matched code, or unmatched bytes
                  right after a terminator (RTS/RTL/RTI/JMP/BRA/BRL/JML)
           rts    the same with entries = target-1 (push-and-RTS dispatch)
           longs  runs of 3-byte pointers into ROM, in at most 3 banks
         A candidate is confirmed by a referencing instruction whose operand
         is its start: JMP/JSR (abs,X) in the same bank (strongest; the table
         is then cut where its lowest target begins), a long read (LDA.l
         T,X ...) from any of --ref-banks, or an absolute read in the same
         bank (weak: DB is often $7E). "T" in the output stands for the
         table. A bound check just before the site (CMP/CPX/CPY #n then
         BCC/BCS) is shown as a length hint; "adjacent" marks a candidate
         that touches matched bytes.
  emit   Prints asar source for one table in the project's style: header
         (purpose placeholder, referencing sites, entry count) and dw/dl/db
         lines. Pointer entries use existing label names from the assembled
         symbol file; an unknown target stays a literal with "; TODO name".

Limits: in unmatched code there are no known instruction boundaries, so a
site there is decoded at every byte and can be an operand that happens to
look like one; data runs of RAM addresses that land on matched instruction
starts look like code pointers (they score lower without a site); split
tables (low bytes, then high bytes) and pointers relative to a base are not
detected. A table's length is a draft: check it against its bound check or
its neighbours before matching.

Usage:
    python3 tools/tables.py scan [--bank C1] [--min 3] [--top 40] [--all]
    python3 tools/tables.py emit $C1:1FF8 --count 33 --kind words [--name N]
        --kind words|longs|bytes|records:SIZE
        --literal       words: plain hex values, no label lookup
        --rts           words: entries are target-1 (default: detected)
        --per-line N    bytes/literal words per line (default 8)
        --no-org        omit the org line (table follows code directly)
        --ref-banks S   banks searched for referencing code (default C0-C3,CC,CD,FD)

Labels and instruction starts come from one asar build with --symbols=wla
(the [labels] and [addr-to-line mapping] sections); matched bytes from
tools/verify.py's two-base method.
"""

import argparse
import re
import subprocess
import sys
import tempfile
from bisect import bisect_right
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify  # noqa: E402
from disasm import _OPCODES  # noqa: E402

ROM_PATH = Path('roms/chrono_trigger.sfc')
MAIN_ASM = Path('asm/main.asm')
BANK_FILES = 'asm/bank*/*.asm'
STUB_FILES = 'asm/include/unmatched*.asm'

# Last byte(s) of an instruction after which execution never falls through.
TERM1 = {0x60, 0x6B, 0x40}                  # RTS RTL RTI
TERM2 = {0x80}                              # BRA rel
TERM3 = {0x4C, 0x82, 0x6C, 0x7C, 0xDC}      # JMP abs, BRL, JMP (abs), JMP (abs,X), JML [abs]
TERM4 = {0x5C}                              # JML long
BAD_FIRST = {0x00, 0x02, 0x42, 0xDB, 0xFF}  # BRK COP WDM STP, $FF fill

# Instructions that can read a table at their operand. Writes and
# read-modify-writes are left out (a ROM table is never written), and so are
# JMP (abs) / JML [abs], whose pointer lives in bank 0 (RAM).
READS = {'LDA', 'LDX', 'LDY', 'ADC', 'SBC', 'AND', 'ORA', 'EOR', 'CMP', 'CPX', 'CPY', 'BIT'}
DISPATCH = {0x7C, 0xFC}                     # JMP (abs,X), JSR (abs,X)
ABS_MODES = {'abs', 'abs_x', 'abs_y'}
LONG_MODES = {'long', 'long_x'}


def ref_weight(opcode: int) -> float:
    """How much one referencing instruction confirms a table at its operand."""
    if opcode in DISPATCH:
        return 0.3                          # program bank: certainly this bank
    if _OPCODES[opcode][1] in LONG_MODES:
        return 0.25                         # full address: certainly this table
    return 0.1                              # abs read: only if DB is this bank
GLOBAL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):')


def snes_to_offset(bank: int, addr: int):
    if bank >= 0xC0:
        return (bank - 0xC0) << 16 | addr
    if bank < 0x40 and addr >= 0x8000:
        return bank << 16 | addr
    if 0x80 <= bank < 0xC0 and addr >= 0x8000:
        return (bank - 0x80) << 16 | addr
    return None


def snes(off: int) -> str:
    return f'${0xC0 + (off >> 16):02X}:{off & 0xFFFF:04X}'


def org_addr(off: int) -> str:
    return f'${0xC0 + (off >> 16):02X}{off & 0xFFFF:04X}'


def parse_addr(text: str) -> int:
    t = text.strip().lstrip('$').replace(':', '')
    if len(t) != 6:
        raise SystemExit(f'address must be bank:addr, e.g. $C1:1FF8 (got {text})')
    off = snes_to_offset(int(t[:2], 16), int(t[2:], 16))
    if off is None:
        raise SystemExit(f'{text} is not a ROM address')
    return off


# ── Facts from one build ─────────────────────────────────────────────────────

class Facts:
    """ROM bytes, matched bytes, labels and instruction starts."""

    def __init__(self):
        if not ROM_PATH.exists():
            raise SystemExit(f'No ROM at {ROM_PATH}.')
        self.rom = ROM_PATH.read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            lo = verify.assemble_onto(0x00, work)
            hi = verify.assemble_onto(0xFF, work)
            self.emitted = {i for i in range(len(lo)) if lo[i] == hi[i]}
            del lo, hi
            sym, rom_copy = work / 'out.sym', work / 'sym.sfc'
            rom_copy.write_bytes(self.rom)
            subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', '--symbols=wla',
                            f'--symbols-path={sym}', str(MAIN_ASM), str(rom_copy)],
                           check=True, capture_output=True)
            text = sym.read_text()
        self.globals_bank, self.globals_stub = set(), set()
        for pattern, into in ((BANK_FILES, self.globals_bank), (STUB_FILES, self.globals_stub)):
            for path in sorted(Path('.').glob(pattern)):
                for line in path.read_text().splitlines():
                    m = GLOBAL.match(line)
                    if m:
                        into.add(m.group(1))
        self.labels = defaultdict(list)   # offset -> names
        self.starts = {}                  # matched line start -> (file, line number)
        files = {}
        section = ''
        for line in text.splitlines():
            if line.startswith('['):
                section = line
                continue
            if section == '[labels]':
                m = re.match(r'^([0-9A-Fa-f]{2}):([0-9A-Fa-f]{4}) (\S+)$', line)
                if m:
                    off = snes_to_offset(int(m.group(1), 16), int(m.group(2), 16))
                    if off is not None:
                        self.labels[off].append(m.group(3))
            elif section == '[source files]':
                m = re.match(r'^([0-9a-fA-F]{4}) \S+ (.+)$', line)
                if m:
                    files[int(m.group(1), 16)] = m.group(2)
            elif section == '[addr-to-line mapping]':
                m = re.match(r'^([0-9a-fA-F]{2}):([0-9a-fA-F]{4}) ([0-9a-fA-F]{4}):([0-9a-fA-F]{8})', line)
                if m:
                    off = snes_to_offset(int(m.group(1), 16), int(m.group(2), 16))
                    if off is not None:
                        self.starts[off] = (files.get(int(m.group(3), 16)), int(m.group(4), 16))
        self._lines = {}
        # Global labels defined in bank files, by address, to name the
        # routine around a referencing site.
        self.routines = sorted((off, n) for off, names in self.labels.items()
                               for n in names if n in self.globals_bank)
        self._route_offs = [o for o, _ in self.routines]

    def label(self, off: int):
        """Best name at an offset: bank-file global, then stub, then sublabel."""
        names = self.labels.get(off)
        if not names:
            return None
        for group in (self.globals_bank, self.globals_stub):
            for n in names:
                if n in group:
                    return n
        return names[0]

    def routine_at(self, off: int):
        i = bisect_right(self._route_offs, off) - 1
        if i < 0 or (off >> 16) != (self._route_offs[i] >> 16):
            return None
        return self.routines[i][1]

    def source_line(self, off: int):
        """Source text of the matched line that starts at off, if any."""
        where = self.starts.get(off)
        if not where or not where[0]:
            return None
        path, no = where
        if path not in self._lines:
            self._lines[path] = Path(path).read_text().splitlines()
        lines = self._lines[path]
        return lines[no - 1] if 0 < no <= len(lines) else None

    def word(self, off: int) -> int:
        return self.rom[off] | self.rom[off + 1] << 8


# ── Referencing instructions ────────────────────────────────────────────────

class Refs:
    """Instructions that can read a table, indexed by the table address.

    Positions in `banks` (file bank numbers) are decoded at every byte: in
    unmatched code there are no known instruction boundaries, so a hit there
    is a hint, not proof. Absolute operands are taken in the site's own bank
    (program bank for JMP/JSR (abs,X); for reads this assumes DB = PB);
    long operands anywhere. In matched code only line starts count, and the
    source must name the table's label (otherwise the operand is RAM).
    """

    def __init__(self, facts: Facts, banks):
        self.facts = facts
        self.by_target = defaultdict(list)   # offset -> [(site, opcode)]
        rom = facts.rom
        for bank_off in sorted({b << 16 for b in banks}):
            end = min(bank_off + 0x10000, len(rom))
            for p in range(bank_off, end - 3):
                if p in facts.emitted and p not in facts.starts:
                    continue                 # inside a matched instruction
                entry = _OPCODES.get(rom[p])
                if not entry:
                    continue
                mnem, mode = entry
                if rom[p] in DISPATCH or (mode in ABS_MODES and mnem in READS) or mnem == 'PEA':
                    tgt = bank_off | (rom[p + 1] | rom[p + 2] << 8)
                elif mode in LONG_MODES and mnem in READS:
                    tgt = snes_to_offset(rom[p + 3], rom[p + 1] | rom[p + 2] << 8)
                    if tgt is None:
                        continue
                else:
                    continue
                if p in facts.emitted and mode not in LONG_MODES:
                    # (A long operand that maps to ROM is a ROM read whatever
                    # the source calls it.)
                    text = (facts.source_line(p) or '').split(';')[0]
                    names = set(re.findall(r'[A-Za-z_]\w*', text))
                    if not names & set(facts.labels.get(tgt, ())):
                        continue
                self.by_target[tgt].append((p, rom[p]))

    def sites(self, target: int):
        """[(site, opcode, matched, routine)] best first."""
        out = []
        for p, op in self.by_target.get(target, []):
            matched = p in self.facts.emitted
            out.append((p, op, matched, self.facts.routine_at(p) if matched else None))
        out.sort(key=lambda s: (not s[2], -ref_weight(s[1]), s[0]))
        return out

    def bound_hint(self, site: int):
        """CMP/CPX/CPY #n followed by BCC/BCS within a few bytes before site."""
        rom = self.facts.rom
        for back in range(3, 14):
            p = site - back
            if rom[p] in (0xC9, 0xE0, 0xC0) and rom[p + 2] in (0x90, 0xB0) and p + 4 <= site:
                return rom[p + 1], {0xC9: 'CMP', 0xE0: 'CPX', 0xC0: 'CPY'}[rom[p]]
        return None


def describe_site(facts: Facts, site, opcode, name: str) -> str:
    mnem, mode = _OPCODES[opcode]
    shape = {'abs_x_ind': f'{mnem} ({name},X)', 'abs_ind': f'{mnem} ({name})',
             'abs_x': f'{mnem} {name},X', 'abs_y': f'{mnem} {name},Y',
             'long_x': f'{mnem}.l {name},X', 'long': f'{mnem}.l {name}',
             'abs_ind_long': f'{mnem} [{name}]'}.get(mode, f'{mnem} {name}')
    return shape


DEFAULT_REF_BANKS = 'C0-C3,CC,CD,FD'


def ref_banks(spec: str, own: int):
    """File bank numbers to look for referencing instructions in."""
    banks = {own}
    for part in spec.split(','):
        lo, _, hi = part.strip().lstrip('$').partition('-')
        for b in range(int(lo, 16), int(hi or lo, 16) + 1):
            banks.add(b - 0xC0 if b >= 0xC0 else b)
    return banks


# ── Scan ─────────────────────────────────────────────────────────────────────

def classify_target(facts: Facts, off: int):
    """('label'|'start'|'term'|'bad'|'miss', score) for a code pointer target."""
    rom = facts.rom
    if off >= len(rom):
        return 'bad', 0.0
    if off in facts.labels:
        return 'label', 1.0
    if off in facts.emitted:
        return ('start', 0.9) if off in facts.starts else ('bad', 0.0)
    if rom[off] in BAD_FIRST or (off & 0xFFFF) < 4:
        return 'miss', 0.0
    if (rom[off - 1] in TERM1 or rom[off - 2] in TERM2 or rom[off - 3] in TERM3
            or rom[off - 4] in TERM4):
        return 'term', 0.6
    return 'miss', 0.0


def word_run(facts: Facts, start: int, bank_off: int, minus: int, limit_end: int,
             tolerance: int = 2, stops=frozenset()):
    """Entries (target, kind, score) of a word table starting at start.

    The run stops at `tolerance` consecutive implausible entries, at a
    target inside matched code that is not an instruction start, at matched
    bytes, at another label, or at a byte in `stops` (code known to start
    there). A dispatch-confirmed table is scanned with a higher tolerance and
    then cut where its lowest target begins: handlers usually follow their
    table directly.
    """
    entries, misses = [], 0
    p = start
    while p + 1 < limit_end and len(entries) < 512:
        if p in facts.emitted or p + 1 in facts.emitted or p in stops or p + 1 in stops:
            break
        if entries and p in facts.labels:
            break                                   # another named thing starts here
        w = facts.word(p)
        if w in (0x0000, 0xFFFF):
            kind, score = 'miss', 0.0
        else:
            kind, score = classify_target(facts, bank_off | ((w + minus) & 0xFFFF))
        if kind == 'bad':
            break
        if score == 0:
            misses += 1
            if misses >= tolerance:
                break
        else:
            misses = 0
        entries.append((w, kind, score))
        p += 2
    while entries and entries[-1][2] == 0:
        entries.pop()
    if tolerance > 2 and entries:
        targets = [bank_off | ((e[0] + minus) & 0xFFFF) for e in entries]
        after = [t for t in targets if t > start]
        low = min(after) if after else None
        if low is not None and (low - start) % 2 == 0:
            cut = (low - start) // 2
            if cut < len(entries):
                entries = entries[:cut]
            elif cut <= len(entries) + 8:
                # Re-read up to the lowest target, if every entry on the way
                # is plausible (or is that shared tail itself).
                extra, q = [], start + 2 * len(entries)
                while q < low and not ({q, q + 1} & facts.emitted):
                    w = facts.word(q)
                    t = bank_off | ((w + minus) & 0xFFFF)
                    kind, score = classify_target(facts, t)
                    if score == 0 and t != low:
                        break
                    extra.append((w, kind, score))
                    q += 2
                if q == low:
                    entries += extra
    return entries


def long_run(facts: Facts, start: int, limit_end: int):
    rom, entries, banks = facts.rom, [], set()
    p = start
    while p + 2 < limit_end and len(entries) < 512:
        if any(q in facts.emitted for q in (p, p + 1, p + 2)):
            break
        if entries and p in facts.labels:
            break
        lo, bk = facts.word(p), rom[p + 2]
        off = snes_to_offset(bk, lo)
        if off is None or off >= len(rom) or not (0xC0 <= bk <= 0xFF) or (lo, bk) == (0xFFFF, 0xFF):
            break
        if bk not in banks and len(banks) >= 3:
            break
        banks.add(bk)
        entries.append((lo | bk << 16, 'label' if off in facts.labels else 'ptr',
                        1.0 if off in facts.labels else 0.5))
        p += 3
    return entries


def scan_bank(facts: Facts, bank: int, min_entries: int, ref_banks):
    bank_off = (bank - 0xC0) << 16
    end = min(bank_off + 0x10000, len(facts.rom))
    refs = Refs(facts, ref_banks)
    cands = []
    # Dispatch sites whose table follows within 32 bytes: their own bytes are
    # code, so no table runs through them.
    stops = frozenset(q for tgt, sites in refs.by_target.items() for p, op in sites
                      if op in DISPATCH and p + 3 <= tgt <= p + 0x20 for q in range(p, p + 3))

    def confirm(base: int):
        sites = refs.sites(base)
        bonus = 0.0
        for p, op, matched, _ in sites[:1]:
            bonus = ref_weight(op) + (0.1 if matched else 0.0)
            if op in DISPATCH and not matched and 0xAA not in facts.rom[p - 6:p]:
                bonus -= 0.15                       # no TAX just before: maybe an operand byte
            if not matched and op not in DISPATCH and (
                    _OPCODES[op][1] in ABS_MODES or _OPCODES[op][0] != 'LDA'):
                bonus = 0.05                        # unconfirmed abs read / odd long read: weak
        return sites, bonus

    for start in range(bank_off, end - 1):
        if start in facts.emitted:
            continue
        dispatched = any(op in DISPATCH for _, op in refs.by_target.get(start, []))
        for minus, kind in ((0, 'words'), (1, 'rts')):
            if kind == 'rts' and dispatched:
                continue
            entries = word_run(facts, start, bank_off, minus, end, 6 if dispatched else 2, stops)
            n = len(entries)
            if n < min_entries:
                continue
            hits = [e for e in entries if e[2] > 0]
            strong = sum(1 for e in entries if e[1] in ('label', 'start'))
            if len(hits) / n < (0.4 if dispatched else 0.6) or len({e[0] for e in entries}) < 2:
                continue
            if strong == 0 and len(hits) < 4:
                continue
            mean = sum(e[2] for e in entries) / n
            sites, bonus = confirm(start)
            if kind == 'rts' and not any(_OPCODES[op][0] in ('LDA', 'LDX', 'LDY') for _, op, _, _ in sites):
                bonus -= 0.15                       # RTS dispatch reads its table with a load
            conf = min(1.0, 0.75 * mean + bonus + (0.1 if start in facts.labels else 0)
                       - (0.15 if n < 4 else 0) - (0 if sites else 0.2))
            cands.append({'start': start, 'kind': kind, 'n': n, 'size': 2 * n,
                          'conf': conf, 'entries': entries, 'sites': sites,
                          'hits': {k: sum(1 for e in entries if e[1] == k)
                                   for k in ('label', 'start', 'term', 'miss')}})
        entries = long_run(facts, start, end)
        n = len(entries)
        if n >= max(4, min_entries) and len({e[0] for e in entries}) >= n / 2:
            labelled = sum(1 for e in entries if e[1] == 'label')
            sites, bonus = confirm(start)
            if labelled or sites or n >= 6:
                conf = min(1.0, 0.35 + 0.4 * labelled / n + bonus
                           + (0.1 if len({e[0] >> 16 for e in entries}) == 1 else 0))
                cands.append({'start': start, 'kind': 'longs', 'n': n, 'size': 3 * n,
                              'conf': conf, 'entries': entries, 'sites': sites,
                              'hits': {'label': labelled, 'ptr': n - labelled}})

    # Keep the best of overlapping candidates.
    cands.sort(key=lambda c: (-c['conf'], -c['size']))
    taken, out = set(), []
    for c in cands:
        span = set(range(c['start'], c['start'] + c['size']))
        if span & taken:
            continue
        taken |= span
        c['adjacent'] = (c['start'] - 1 in facts.emitted) or (c['start'] + c['size'] in facts.emitted)
        c['bound'] = None
        if c['sites']:
            c['bound'] = refs.bound_hint(c['sites'][0][0])
        out.append(c)
    # Data that matched code already reads by name but the source does not
    # emit yet (any shape: byte tables too).
    named = []
    for tgt, sites in refs.by_target.items():
        if tgt >> 16 != bank - 0xC0 or tgt in facts.emitted:
            continue
        matched = [p for p, op in sites if p in facts.emitted]
        readers = sorted({facts.routine_at(p) for p in matched} - {None})
        if not readers:
            continue
        name = facts.label(tgt)
        if not name:
            # The name the source uses: a define (!Name) or a struct.
            operands = [(facts.source_line(p) or '').split(';')[0] for p in matched]
            if all(re.search(r'[+.]\w', o.split(None, 1)[-1]) for o in operands):
                continue                    # base+N or struct field: part of a table listed
            m = re.search(r'!\w+', operands[0])
            name = m.group(0) if m else None
        elif '.' in name:
            continue
        named.append((tgt, name, readers, any(op in DISPATCH for _, op in sites)))
    return out, sorted(named)


def cmd_scan(args) -> int:
    facts = Facts()
    banks = [int(b.lstrip('$'), 16) for b in args.bank.split(',')]
    for bank in banks:
        cands, named = scan_bank(facts, bank, args.min, ref_banks(args.ref_banks, bank - 0xC0))
        if not args.all:
            cands = [c for c in cands if c['conf'] >= 0.5]
        cands = cands[:args.top]
        print(f'Bank ${bank:02X}: {len(cands)} candidate(s)'
              + ('' if args.all else ' with confidence >= 0.50 (--all for every one)'))
        print(f'{"conf":>4}  {"start":<8} {"kind":<5} {"n":>4}  {"label / referencing site":<52} hits')
        for c in cands:
            name = facts.label(c['start'])
            ref = ''
            if c['sites']:
                p, op, matched, routine = c['sites'][0]
                where = f'in {routine}' if matched and routine else 'unmatched'
                ref = f'{describe_site(facts, p, op, "T")} @ {snes(p)} ({where})'
                if len(c['sites']) > 1:
                    ref += f' +{len(c["sites"]) - 1}'
            text = ' '.join(x for x in (name and f'[{name}]', ref) if x) or '-'
            hits = ' '.join(f'{k}:{v}' for k, v in c['hits'].items() if v)
            extra = []
            if c['bound']:
                extra.append(f'bound {c["bound"][1]} #${c["bound"][0]:02X}')
            if c['adjacent']:
                extra.append('adjacent')
            print(f'{c["conf"]:4.2f}  {snes(c["start"])} {c["kind"]:<5} {c["n"]:>4}  {text:<52} {hits}'
                  + (f'  ({", ".join(extra)})' if extra else ''))
        if named:
            print(f'\nRead by matched code, not emitted yet ({len(named)}):')
            for tgt, name, readers, dispatch in named:
                print(f'      {snes(tgt)} {name or "-":<28} {"dispatch" if dispatch else "data":<8} '
                      f'read by {", ".join(readers)}')
        print()
    return 0


# ── Emit ─────────────────────────────────────────────────────────────────────

def idx_text(i: int, count: int) -> str:
    return str(i) if count <= 10 else f'${i:02X}'


def line(code: str, comment: str) -> str:
    return f'    {code:<31} ; {comment}' if comment else f'    {code}'


def cmd_emit(args) -> int:
    facts = Facts()
    start = parse_addr(args.address)
    bank_off = start & ~0xFFFF
    kind, size = args.kind, None
    if kind.startswith('records:'):
        size = int(kind.split(':', 1)[1], 0)
        kind = 'records'
    elif kind not in ('words', 'longs', 'bytes'):
        raise SystemExit('--kind must be words, longs, bytes or records:SIZE')
    width = {'words': 2, 'longs': 3, 'bytes': 1, 'records': size}[kind]
    total = width * args.count
    end = start + total - 1
    rom = facts.rom
    name = args.name or facts.label(start) or f'Table_{org_addr(start)[1:]}'
    target_bank = (int(args.target_bank.lstrip('$'), 16) - 0xC0) << 16 if args.target_bank else bank_off

    unit = {'words': 'words', 'longs': 'long pointers', 'bytes': 'bytes',
            'records': f'records of {size} bytes'}[kind]
    out = ['; ' + '=' * 66,
           f'; {name} ({org_addr(start)}–{org_addr(end)}, {args.count} {unit})',
           '; ' + '=' * 66,
           '; TODO: what the table holds and how it is indexed.']
    refs = Refs(facts, ref_banks(args.ref_banks, start >> 16)).sites(start)
    if refs:
        out.append('; Referenced by:')
        groups = []                         # matched sites grouped per routine
        for p, op, matched, routine in refs:
            shape = describe_site(facts, p, op, name)
            if matched and groups and groups[-1][0] == (shape, routine):
                groups[-1][1].append(p)
            else:
                groups.append(((shape, routine if matched else None), [p]))
        for (shape, routine), sites in groups[:args.max_refs]:
            where = routine or 'unmatched code'
            at = snes(sites[0]) + (f' and {len(sites) - 1} more' if len(sites) > 1 else '')
            out.append(f';   {shape} at {at} ({where})')
        if len(groups) > args.max_refs:
            out.append(f';   ... and {len(groups) - args.max_refs} more sites')
    else:
        out.append('; Referenced by: no absolute/long operand in this bank names it (indexed')
        out.append(';   from another base, or reached through a pointer).')
    already = [o for o in range(start, end + 1) if o in facts.emitted]
    if already:
        out.append(f'; NOTE: {len(already)} of these bytes are already emitted by source.')
    if not args.no_org:
        out.append(f'org {org_addr(start)}')
    out.append(f'{name}:')

    if kind == 'words' and not args.literal:
        words = [facts.word(start + 2 * i) for i in range(args.count)]
        minus = 1 if args.rts else 0
        if not args.rts:
            direct = sum(1 for w in words if facts.label(target_bank | w))
            shifted = sum(1 for w in words if facts.label(target_bank | ((w + 1) & 0xFFFF)))
            minus = 1 if shifted > direct else 0
        for i, w in enumerate(words):
            label = facts.label(target_bank | ((w + minus) & 0xFFFF))
            idx = idx_text(i, args.count)
            if label:
                out.append(line(f'dw {label}' + ('-1' if minus else ''), idx))
            else:
                out.append(line(f'dw ${w:04X}', f'{idx} TODO name'))
    elif kind == 'longs':
        for i in range(args.count):
            p = start + 3 * i
            lo, bk = facts.word(p), rom[p + 2]
            off = snes_to_offset(bk, lo)
            label = facts.label(off) if off is not None else None
            idx = idx_text(i, args.count)
            if label:
                out.append(line(f'dl {label}', idx))
            else:
                out.append(line(f'dl ${bk:02X}{lo:04X}', f'{idx} TODO name'))
    elif kind == 'records':
        for i in range(args.count):
            p = start + size * i
            out.append(line('db ' + ','.join(f'${b:02X}' for b in rom[p:p + size]),
                            idx_text(i, args.count)))
    else:
        per = args.per_line
        is_words = kind == 'words'
        n_lines = (args.count + per - 1) // per
        for li in range(n_lines):
            i0 = li * per
            k = min(per, args.count - i0)
            if is_words:
                vals = ','.join(f'${facts.word(start + 2 * (i0 + j)):04X}' for j in range(k))
                code = f'dw {vals}'
            else:
                code = 'db ' + ','.join(f'${b:02X}' for b in rom[start + i0:start + i0 + k])
            out.append(line(code, idx_text(i0, args.count) if n_lines > 1 else ''))
    print('\n'.join(out))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('scan', help='rank candidate tables in unmatched bytes')
    s.add_argument('--bank', default='C1', help='bank(s), e.g. C1 or C0,C1')
    s.add_argument('--min', type=int, default=3, help='minimum entries (default 3)')
    s.add_argument('--top', type=int, default=40)
    s.add_argument('--all', action='store_true', help='include low-confidence candidates')
    s.add_argument('--ref-banks', default=DEFAULT_REF_BANKS,
                   help=f'banks searched for referencing code (default {DEFAULT_REF_BANKS})')
    e = sub.add_parser('emit', help='print asar source for one table')
    e.add_argument('address')
    e.add_argument('--count', type=int, required=True)
    e.add_argument('--kind', default='words')
    e.add_argument('--name')
    e.add_argument('--literal', action='store_true')
    e.add_argument('--rts', action='store_true')
    e.add_argument('--target-bank', help='bank of word targets (default: the table\'s)')
    e.add_argument('--per-line', type=int, default=8)
    e.add_argument('--no-org', action='store_true')
    e.add_argument('--ref-banks', default=DEFAULT_REF_BANKS)
    e.add_argument('--max-refs', type=int, default=8, help='referencing sites listed (default 8)')
    args = ap.parse_args()
    return cmd_scan(args) if args.cmd == 'scan' else cmd_emit(args)


if __name__ == '__main__':
    sys.exit(main())
