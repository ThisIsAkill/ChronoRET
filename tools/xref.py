#!/usr/bin/env python3
"""
xref.py — Every code reference to an address in the ROM, with a verdict.

Finds the byte patterns that would transfer control to the target:

  JSR abs, JMP abs   same bank as the site
  JSL, JML long      from anywhere, any HiROM mirror of the target bank
  BRL                same bank, 16-bit relative
  Bxx / BRA          8-bit relative (only with --branches)

A byte pattern is only a call if its first byte is really an opcode. Each
hit is classified:

  CONFIRMED  the site is on an instruction boundary
  DOUBTFUL   the site is most likely inside another instruction's operand
             (or in data)

How the boundary is decided:

  matched code   (the site lies in a row of symbols/functions.csv) the
                 source is assembled with asar's address-to-line mapping;
                 a site is a boundary exactly when an instruction line of
                 the source starts there. Authoritative.
  unmatched code a self-synchronising sweep: decode forward from every
                 offset in the 64 bytes before the site, under each of the
                 four M/X start states, tracking REP/SEP. A sweep that
                 decodes BRK, COP, STP or WDM is implausible and dropped;
                 of the rest, the site is CONFIRMED when more than half land
                 exactly on it. The score printed is that fraction.

Each hit names the matched routine that contains it, if any.

Usage:
    python3 tools/xref.py $C1:00D7              (also C100D7, C1:00D7, a label)
    python3 tools/xref.py Battle_Divide --branches
    python3 tools/xref.py $C0:00BF --json
    python3 tools/xref.py $C0:00BF --confirmed  only CONFIRMED hits
"""

import argparse
import bisect
import csv
import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from disasm import _OPCODES  # noqa: E402

ROM_PATH = Path('roms/chrono_trigger.sfc')
MAIN_ASM = Path('asm/main.asm')
FUNCTIONS_CSV = Path('symbols/functions.csv')

WINDOW = 64                      # sweep start offsets before a site
IMPLAUSIBLE = {0x00, 0x02, 0x42, 0xDB}   # BRK, COP, WDM, STP
BRANCH_OPS = {0x10: 'BPL', 0x30: 'BMI', 0x50: 'BVC', 0x70: 'BVS', 0x80: 'BRA',
              0x90: 'BCC', 0xB0: 'BCS', 0xD0: 'BNE', 0xF0: 'BEQ'}
# Start states for the sweep, (M 8-bit, X 8-bit, weight). The weights are a
# prior: this engine runs with 8-bit A and 16-bit X/Y almost everywhere, then
# 16/16. Calibrated on the matched code, where the source gives the truth.
STATES = ((True, False, 0.60), (False, False, 0.25), (True, True, 0.10), (False, True, 0.05))
STATE_NAMES = ('m8x16', 'm16x16', 'm8x8', 'm16x8')
DATA_DIRECTIVES = ('db', 'dw', 'dl', 'dd', 'incbin', 'fill', 'skip')

_EXTRA = {'impl': 0, 'A': 0, 'imm': 1, 'dp': 1, 'dp_x': 1, 'dp_y': 1, 'dp_ind': 1,
          'dp_x_ind': 1, 'dp_ind_y': 1, 'dp_ind_long': 1, 'dp_ind_long_y': 1, 'sr': 1,
          'sr_ind_y': 1, 'abs': 2, 'abs_x': 2, 'abs_y': 2, 'abs_ind': 2, 'abs_x_ind': 2,
          'abs_ind_long': 2, 'long': 3, 'long_x': 3, 'rel': 1, 'rlong': 2, 'block': 2}
# Instruction length per opcode for each (M 8-bit, X 8-bit) state.
_LEN = {}
for _m in (True, False):
    for _x in (True, False):
        table = []
        for op in range(256):
            mode = _OPCODES[op][1]
            if mode == 'imm_m':
                table.append(2 if _m else 3)
            elif mode == 'imm_x':
                table.append(2 if _x else 3)
            else:
                table.append(1 + _EXTRA[mode])
        _LEN[(_m, _x)] = table


def to_offset(bank: int, addr: int):
    """HiROM file offset of a SNES address, or None if it is not ROM."""
    if 0xC0 <= bank <= 0xFF:
        return (bank - 0xC0) << 16 | addr
    if 0x40 <= bank <= 0x7D:
        return (bank - 0x40) << 16 | addr
    if addr >= 0x8000 and (bank <= 0x3F or 0x80 <= bank <= 0xBF):
        return (bank & 0x3F) << 16 | addr
    return None


def fmt(off: int) -> str:
    return f'${0xC0 + (off >> 16):02X}:{off & 0xFFFF:04X}'


@dataclass
class Hit:
    site: str
    kind: str
    status: str            # CONFIRMED / DOUBTFUL
    basis: str             # source / sweep
    score: float
    routine: str           # matched routine containing the site ('' if none)
    note: str
    offset: int


class Xref:
    """ROM, matched rows and source boundaries, loaded once and reused."""

    def __init__(self, rom_path: Path = ROM_PATH):
        self.rom = rom_path.read_bytes()
        self.rows = self._read_rows()
        self._row_starts = [r[0] for r in self.rows]
        self.labels, self.boundaries, self.source_lines = self._assemble(rom_path)
        self._memo: dict[int, dict] = {}
        self._index = None

    # ── loading ────────────────────────────────────────────────────────────
    @staticmethod
    def _read_rows():
        rows = []
        if FUNCTIONS_CSV.exists():
            with FUNCTIONS_CSV.open() as f:
                for row in csv.DictReader(f):
                    s, e = row['address'], row['end']
                    rows.append((to_offset(int(s[1:3], 16), int(s[4:], 16)),
                                 to_offset(int(e[1:3], 16), int(e[4:], 16)), row['name']))
        return sorted(rows)

    @staticmethod
    def _assemble(rom_path: Path):
        """asar's symbol file: labels and the address of every source line."""
        labels, boundaries, where = {}, {}, {}
        with tempfile.TemporaryDirectory() as tmp:
            rom_copy, sym = Path(tmp) / 'x.sfc', Path(tmp) / 'x.sym'
            shutil.copy(rom_path, rom_copy)
            res = subprocess.run(['asar', '--no-title-check', '--fix-checksum=off',
                                  '--symbols=wla', f'--symbols-path={sym}', str(MAIN_ASM),
                                  str(rom_copy)], capture_output=True, text=True)
            if res.returncode != 0:
                sys.stderr.write(res.stdout + res.stderr)
                raise SystemExit('xref: asar failed')
            text = sym.read_text()
        section, files, texts = None, {}, {}
        for line in text.splitlines():
            if line.startswith('['):
                section = line.strip()
                continue
            if section == '[labels]':
                m = re.match(r'^([0-9a-fA-F]{2}):([0-9a-fA-F]{4}) (\S+)$', line)
                if m:
                    off = to_offset(int(m.group(1), 16), int(m.group(2), 16))
                    if off is not None:
                        labels[m.group(3)] = off
            elif section == '[source files]':
                m = re.match(r'^([0-9a-fA-F]{4}) \S+ (.+)$', line)
                if m:
                    files[int(m.group(1), 16)] = m.group(2)
            elif section == '[addr-to-line mapping]':
                m = re.match(r'^([0-9a-fA-F]{2}):([0-9a-fA-F]{4}) ([0-9a-fA-F]{4}):([0-9a-fA-F]{8})$', line)
                if m:
                    off = to_offset(int(m.group(1), 16), int(m.group(2), 16))
                    if off is not None:
                        where[off] = (int(m.group(3), 16), int(m.group(4), 16))
        for off, (fid, no) in where.items():
            path = files.get(fid)
            if path is None:
                continue
            if path not in texts:
                p = Path(path)
                texts[path] = p.read_text().splitlines() if p.exists() else []
            lines = texts[path]
            src = lines[no - 1] if 0 < no <= len(lines) else ''
            boundaries[off] = (path, no, _is_instruction(src))
        return labels, boundaries, texts

    # ── lookups ────────────────────────────────────────────────────────────
    def routine_at(self, off: int) -> str:
        i = bisect.bisect_right(self._row_starts, off) - 1
        if i >= 0 and self.rows[i][0] <= off <= self.rows[i][1]:
            return self.rows[i][2]
        return ''

    def resolve(self, text: str) -> int:
        t = text.strip()
        if t in self.labels:
            return self.labels[t]
        m = re.match(r'^\$?([0-9A-Fa-f]{2}):?([0-9A-Fa-f]{4})$', t)
        if not m:
            raise SystemExit(f'xref: cannot read address {text!r} (use $BB:AAAA, BBAAAA or a label)')
        off = to_offset(int(m.group(1), 16), int(m.group(2), 16))
        if off is None or off >= len(self.rom):
            raise SystemExit(f'xref: {text} is not a ROM address')
        return off

    # ── candidate sites ────────────────────────────────────────────────────
    def _build_index(self):
        """All JSR/JMP/BRL/JSL/JML byte patterns in the ROM, by target offset."""
        rom, idx = self.rom, {}
        n = len(rom)
        for op, kind in ((0x20, 'JSR'), (0x4C, 'JMP'), (0x82, 'BRL'), (0x22, 'JSL'), (0x5C, 'JML')):
            pos = rom.find(op)
            while pos >= 0:
                if kind in ('JSL', 'JML'):
                    if pos + 3 < n:
                        t = to_offset(rom[pos + 3], rom[pos + 1] | rom[pos + 2] << 8)
                        if t is not None:
                            idx.setdefault(t, []).append((pos, kind))
                elif pos + 2 < n:
                    word = rom[pos + 1] | rom[pos + 2] << 8
                    if kind == 'BRL':
                        word = (pos + 3 + word) & 0xFFFF
                    idx.setdefault((pos & ~0xFFFF) | word, []).append((pos, kind))
                pos = rom.find(op, pos + 1)
        self._index = idx

    def candidates(self, target: int, branches: bool = False):
        if self._index is None:
            self._build_index()
        sites = list(self._index.get(target, []))
        if branches:
            rom = self.rom
            lo = max(target & ~0xFFFF, target - 129)
            for pos in range(lo, min(len(rom) - 1, target + 127)):
                if rom[pos] in BRANCH_OPS and (pos >> 16) == (target >> 16):
                    rel = rom[pos + 1]
                    rel -= 256 if rel >= 128 else 0
                    if ((pos + 2 + rel) & 0xFFFF) == (target & 0xFFFF):
                        sites.append((pos, BRANCH_OPS[rom[pos]]))
        return sorted(set(sites))

    # ── boundary test ──────────────────────────────────────────────────────
    def _source_verdict(self, pos: int):
        b = self.boundaries.get(pos)
        if b and b[2]:
            return True, 1.0, f'{Path(b[0]).name}:{b[1]}'
        # Name the instruction (or data line) the byte belongs to.
        for back in range(1, 5):
            prev = self.boundaries.get(pos - back)
            if prev:
                what = 'instruction' if prev[2] else 'data'
                return False, 0.0, f'byte {back} of the {what} at {fmt(pos - back)} ({Path(prev[0]).name}:{prev[1]})'
        return False, 0.0, 'not an instruction start in the source'

    def _sweep(self, pos: int):
        memo = self._memo.setdefault(pos, {})
        rom = self.rom
        lo = max(pos & ~0xFFFF, pos - WINDOW)          # code never runs across a bank
        lands = [0] * len(STATES)
        alive = [0] * len(STATES)
        for start in range(pos - 1, lo - 1, -1):
            for n, (m0, x0, _) in enumerate(STATES):
                path, o, m, x = [], start, m0, x0
                while True:
                    key = (o, m, x)
                    if key in memo:
                        res = memo[key]
                        break
                    if o >= pos:
                        res = 'land' if o == pos else 'miss'
                        break
                    op = rom[o]
                    if op in IMPLAUSIBLE:
                        res = 'reject'
                        break
                    path.append(key)
                    ln = _LEN[(m, x)][op]
                    if op == 0xC2:                         # REP
                        m = m and not rom[o + 1] & 0x20
                        x = x and not rom[o + 1] & 0x10
                    elif op == 0xE2:                       # SEP
                        m = m or bool(rom[o + 1] & 0x20)
                        x = x or bool(rom[o + 1] & 0x10)
                    o += ln
                for key in path:
                    memo[key] = res
                if res != 'reject':
                    alive[n] += 1
                    lands[n] += res == 'land'
        sweeps = (pos - lo) * len(STATES)
        weight = sum(w for (_, _, w), a in zip(STATES, alive) if a)
        if not sweeps or sum(alive) * 4 < sweeps or not weight:
            return False, 0.0, f'{sum(alive)}/{sweeps} sweeps plausible (too few: data?)'
        score = sum(w * l / a for (_, _, w), l, a in zip(STATES, lands, alive) if a) / weight
        detail = ' '.join(f'{name}:{l}/{a}' for name, l, a in zip(STATE_NAMES, lands, alive))
        return score > 0.5, score, f'landed {detail}'

    def classify(self, pos: int, kind: str) -> Hit:
        routine = self.routine_at(pos)
        if routine:
            ok, score, note = self._source_verdict(pos)
            basis = 'source'
        else:
            ok, score, note = self._sweep(pos)
            basis = 'sweep'
        return Hit(fmt(pos), kind, 'CONFIRMED' if ok else 'DOUBTFUL', basis,
                   round(score, 2), routine, note, pos)

    def xref(self, target: int, branches: bool = False) -> list[Hit]:
        return [self.classify(pos, kind) for pos, kind in self.candidates(target, branches)]

    def name_at(self, off: int) -> str:
        names = [n for n, o in self.labels.items() if o == off and not n.startswith(':')]
        return names[0] if names else ''


def _is_instruction(src: str) -> bool:
    code = src.split(';', 1)[0].strip()
    m = re.match(r'^(?:[A-Za-z_.][A-Za-z0-9_.]*:|[+-]+)\s*(.*)$', code)
    if m and not src[:1].isspace():
        code = m.group(1)
    word = code.split()[0].lower() if code.split() else ''
    if not word or word in DATA_DIRECTIVES:
        return False
    return bool(re.match(r'^[a-z]{3}(\.[bwl])?$', word)) or word.startswith('%')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('address', help='$BB:AAAA, BBAAAA or a label')
    ap.add_argument('--branches', action='store_true', help='also 8-bit relative branches')
    ap.add_argument('--confirmed', action='store_true', help='only CONFIRMED hits')
    ap.add_argument('--json', action='store_true')
    args = ap.parse_args()

    if not ROM_PATH.exists():
        print(f'xref: no ROM at {ROM_PATH}', file=sys.stderr)
        return 2
    xr = Xref()
    target = xr.resolve(args.address)
    hits = xr.xref(target, args.branches)
    if args.confirmed:
        hits = [h for h in hits if h.status == 'CONFIRMED']
    name = xr.name_at(target)
    if args.json:
        print(json.dumps({'target': fmt(target), 'name': name,
                          'hits': [{k: v for k, v in asdict(h).items() if k != 'offset'}
                                   for h in hits]}, indent=2))
        return 0
    confirmed = sum(h.status == 'CONFIRMED' for h in hits)
    print(f'{fmt(target)}{" " + name if name else ""}: {confirmed} confirmed, '
          f'{len(hits) - confirmed} doubtful')
    for h in hits:
        where = f'in {h.routine}' if h.routine else 'unmatched'
        print(f'  {h.status:<9}  {h.site}  {h.kind:<3}  {where:<40}  {h.basis}: {h.note}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
