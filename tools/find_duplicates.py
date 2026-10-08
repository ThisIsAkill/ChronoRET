#!/usr/bin/env python3
"""
find_duplicates.py — Find copies of matched routines elsewhere in the ROM.

A routine that appears twice in the ROM only has to be understood once:
the second copy is a near-free match (same instructions, same names,
re-verified at its own address).

Exact mode (default) lists, for every matched routine of at least --min
bytes, every other place in the ROM holding exactly the same bytes: inside
other matched routines (duplicated logic worth a cross-reference) or in
unmatched code (candidates to match next).

Relocatable mode (--relocatable) decodes each matched routine as 65816 code
and turns it into a pattern in which the operand bytes of absolute and long
operands are wildcards: JSR/JMP/JML/JSL targets, indirect jump vectors and
absolute/long data addresses (and direct-page operands with --mask-dp).
Opcodes, immediates, relative branch offsets, block-move banks and PEA/PER
operands must still match exactly. It then reports every place in the ROM
matching that pattern, with the operands that differ and, where a target is
a matched routine, its name.

Decoding starts from the entry state documented in the routine's header
("Entry: M=1, X=0", "On entry: M=1, X/Y 16-bit", ...), or the bank default
when the header says nothing, follows branches and JMPs inside the routine,
tracks REP/SEP, and applies the "Exit:" widths of callees whose headers state
them. A decode that hits BRK/COP/WDM/STP or overlapping instructions is
rejected and the other M/X widths are tried. Bytes no decode reaches (jump
tables, code entered only through a table) and data entries (db/dw/dl) stay
exact.

--fragments N also finds partial copies: every run of N decoded instructions
is searched (anchored on its rarest exact byte pair through a ROM-wide pair
index) and each hit is grown an instruction at a time in both directions.
Results are ranked by size; a copy found from two sources is listed once.

Usage:
    python3 tools/find_duplicates.py [--min 16] [--banks C0-C3,FD] [--json]
    python3 tools/find_duplicates.py --relocatable [--mask-dp] [--fragments 6]
            [--min-instructions 6] [--max-differing 3] [--unmatched-only]
            [--max-hits 20] [--json]
"""

import argparse
import csv
import json
import re
import sys
import time
from array import array
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from disasm import _OPCODES, CPUState, format_operand, insn_len  # noqa: E402

ROM_PATH = Path('roms/chrono_trigger.sfc')
FUNCTIONS = Path('symbols/functions.csv')
ASM_DIR = Path('asm')

# Absolute / long operands: masked in relocatable mode.
ABS_MODES = {'abs', 'abs_x', 'abs_y', 'long', 'long_x',
             'abs_ind', 'abs_x_ind', 'abs_ind_long'}
DP_MODES = {'dp', 'dp_x', 'dp_y', 'dp_ind', 'dp_x_ind', 'dp_ind_y',
            'dp_ind_long', 'dp_ind_long_y'}
# PEA pushes a constant (often a DB pair or return address), so it stays exact.
EXACT_MNEMONICS = {'PEA'}
# Opcodes that never appear in sane game code (BRK, COP, WDM, STP).
INSANE = {0x00, 0x02, 0x42, 0xDB}
JUMPS = {'JMP', 'JML', 'BRA', 'BRL'}
ENDS = {'RTS', 'RTL', 'RTI', 'STP'}
BRANCHES = {'BPL', 'BMI', 'BVC', 'BVS', 'BCC', 'BCS', 'BNE', 'BEQ', 'BRA', 'BRL'}
CONTROL = {'JSR', 'JMP', 'JSL', 'JML'}


def offset(addr: str) -> int:
    return (int(addr[1:3], 16) - 0xC0) << 16 | int(addr[4:], 16)


def snes(off: int) -> str:
    return f'${0xC0 + (off >> 16):02X}:{off & 0xFFFF:04X}'


def parse_banks(spec: str) -> list[int]:
    banks = []
    for part in spec.split(','):
        if '-' in part:
            a, b = (int(x, 16) for x in part.split('-'))
            banks.extend(range(a, b + 1))
        else:
            banks.append(int(part, 16))
    return banks


# ── Entry state from the source headers ─────────────────────────────────────

_M_PATTERNS = [(r'\bM=([01])\b', {'1': True, '0': False}),
               (r'\bM=(8|16)\b', {'8': True, '16': False}),
               (r'\b(8|16)-bit A\b', {'8': True, '16': False}),
               (r'\bA (8|16)-bit\b', {'8': True, '16': False})]
_X_PATTERNS = [(r'\bX=([01])\b', {'1': True, '0': False}),
               (r'\bX/Y (8|16)-bit\b', {'8': True, '16': False}),
               (r'\b(8|16)-bit X', {'8': True, '16': False}),
               (r'\bX=(8|16)\b', {'8': True, '16': False})]


def _width(text: str, patterns) -> bool | None:
    for pat, values in patterns:
        m = re.search(pat, text)
        if m:
            return values[m.group(1)]
    return None


def stated_state(block: list[str], key: str = 'entry') -> tuple[bool | None, bool | None]:
    """(m8, x8) from the "Entry:" / "On entry:" (or "Exit:") paragraph of a
    header; None = not stated or "either width"."""
    text, inside = [], False
    for line in block:
        body = line.lstrip(';').strip()
        if re.match(rf'(on )?{key}\b', body, re.I):
            inside = True
        elif inside and re.match(r'[A-Z][\w /]*:', body):
            break
        if inside:
            text.append(body)
    text = ' '.join(text)
    m8 = None if re.search(r'\bM either width', text) else _width(text, _M_PATTERNS)
    x8 = None if re.search(r'\bX either width', text) else _width(text, _X_PATTERNS)
    return m8, x8


def parse_headers(names: set[str]) -> dict[str, dict]:
    """name -> {'m8', 'x8', 'data'} for every routine label in asm/."""
    info: dict[str, dict] = {}
    for path in sorted(ASM_DIR.rglob('*.asm')):
        lines = path.read_text(errors='replace').splitlines()
        block: list[str] = []
        prev_comment = False
        stale = True           # code seen since the last comment block
        bank_default = (None, None)
        for i, raw in enumerate(lines):
            line = raw.strip()
            if line.startswith(';'):
                if not prev_comment:
                    block, stale = [], False
                block.append(line)
                prev_comment = True
                continue
            prev_comment = False
            if not line or line.startswith('!') or re.match(
                    r'(org|base|arch|hirom|incsrc|warnpc)\b', line, re.I):
                if bank_default == (None, None) and any('on entry' in b.lower() for b in block):
                    text = ' '.join(block)
                    bank_default = (_width(text, _M_PATTERNS), _width(text, _X_PATTERNS))
                continue
            label = re.match(r'([A-Za-z_]\w*):', line)
            if label and label.group(1) in names:
                m8, x8 = stated_state(block) if not stale else (None, None)
                exit_m8, exit_x8 = stated_state(block, 'exit') if not stale else (None, None)
                nxt = next((ln.strip() for ln in lines[i + 1:]
                            if ln.strip() and not ln.strip().startswith(';')), '')
                info[label.group(1)] = {
                    'm8': m8,
                    'x8': x8,
                    'exit': (exit_m8, exit_x8),
                    'default': bank_default,
                    'data': bool(re.match(r'(db|dw|dl|dd|incbin)\b', nxt, re.I)),
                }
            stale = True
    return info


# ── Decoding ────────────────────────────────────────────────────────────────

def decode(rom: bytes, start: int, end: int, m8: bool, x8: bool, exits: dict):
    """Follow the code from `start` inside [start, end) and return
    (insns, ok), insns = {offset: (opcode, mnemonic, mode, length, m8, x8)}.
    A call to a routine whose header states its exit widths applies them."""
    insns: dict[int, tuple] = {}
    owner: dict[int, int] = {}
    work = [(start, m8, x8)]
    while work:
        pc, m, x = work.pop()
        while start <= pc < end:
            if pc in insns:
                break
            op = rom[pc]
            if op in INSANE:
                return insns, False
            mnem, mode = _OPCODES[op]
            n = insn_len(mode, CPUState(m, x, False))
            if pc + n > end and mnem not in ENDS:
                return insns, False
            for b in range(pc, min(pc + n, end)):
                if b in owner:
                    return insns, False
                owner[b] = pc
            insns[pc] = (op, mnem, mode, n, m, x)
            if mnem == 'REP':
                m = m and not rom[pc + 1] & 0x20
                x = x and not rom[pc + 1] & 0x10
            elif mnem == 'SEP':
                m = m or bool(rom[pc + 1] & 0x20)
                x = x or bool(rom[pc + 1] & 0x10)
            nxt = pc + n
            if mnem in ('JSR', 'JSL') and mode in ('abs', 'long'):
                callee = int.from_bytes(rom[pc + 1:pc + n], 'little')
                if mode == 'abs':
                    callee |= (start & 0xFF0000) + 0xC00000
                em, ex = exits.get(callee, (None, None))
                m = m if em is None else em
                x = x if ex is None else ex
            if mnem in BRANCHES:
                if mode == 'rel':
                    d = rom[pc + 1]
                    d = d - 256 if d >= 128 else d
                else:
                    d = int.from_bytes(rom[pc + 1:pc + 3], 'little')
                    d = d - 65536 if d >= 32768 else d
                target = nxt + d
                if start <= target < end:
                    work.append((target, m, x))
            if mnem in ('JMP', 'JSR') and mode == 'abs':
                target = (start & 0xFF0000) | int.from_bytes(rom[pc + 1:pc + 3], 'little')
                if start <= target < end:
                    work.append((target, m, x))
            if mnem in JUMPS or mnem in ENDS:
                break
            pc = nxt
    return insns, True


def best_decode(rom, start, end, hint, exits):
    """Try the documented entry state first, then every other width."""
    m8, x8 = hint.get('m8'), hint.get('x8')
    dm, dx = hint.get('default', (None, None))
    order = []
    for m in ([m8] if m8 is not None else [dm if dm is not None else True, not (dm if dm is not None else True)]):
        for x in ([x8] if x8 is not None else [dx if dx is not None else False, not (dx if dx is not None else False)]):
            order.append((m, x, True))
    for m in (True, False):
        for x in (False, True):
            if (m, x, True) not in order:
                order.append((m, x, False))
    best = None
    for m, x, documented in order:
        insns, ok = decode(rom, start, end, m, x, exits)
        if not ok:
            continue
        covered = sum(i[3] for i in insns.values())
        if documented and covered:
            return insns, (m, x)
        if best is None or covered > best[2]:
            best = (insns, (m, x), covered)
    return (best[0], best[1]) if best else ({}, None)


# ── Patterns and search ─────────────────────────────────────────────────────

def build_pattern(rom, start, end, insns, mask_dp):
    """Return (pattern, masked) — pattern: list of byte|None; masked:
    [(rel_offset, mnemonic, mode, length, m8, x8)] for wildcarded operands."""
    pat: list[int | None] = list(rom[start:end])
    masked = []
    for pc, (op, mnem, mode, n, m, x) in sorted(insns.items()):
        if mnem in EXACT_MNEMONICS:
            continue
        if mode in ABS_MODES or (mask_dp and mode in DP_MODES):
            for b in range(pc + 1, min(pc + n, end)):
                pat[b - start] = None
            masked.append((pc - start, mnem, mode, n, m, x))
    return pat, masked


def exact_runs(pat):
    runs, i = [], 0
    while i < len(pat):
        if pat[i] is None:
            i += 1
            continue
        j = i
        while j < len(pat) and pat[j] is not None:
            j += 1
        runs.append((i, bytes(pat[i:j])))
        i = j
    return runs


class PairIndex:
    """Where every byte pair occurs in the ROM, so search() can anchor on
    the rarest exact pair of a pattern instead of scanning the ROM."""

    def __init__(self, rom: bytes):
        self.at: dict[int, array] = {}
        for parity in (0, 1):
            words = memoryview(rom[parity:parity + ((len(rom) - parity) & ~1)]).cast('H')
            for i, key in enumerate(words):
                where = self.at.get(key)
                if where is None:
                    where = self.at[key] = array('I')
                where.append(2 * i + parity)
        self.empty = array('I')

    def __call__(self, a: int, b: int) -> array:
        return self.at.get(a | b << 8, self.empty)


def search(rom, pat, index=None):
    """Every offset where `pat` matches. Without an index: anchor on the
    longest exact run with bytes.find. With one: anchor on the rarest exact
    byte pair. Then verify the other exact runs as slices."""
    runs = exact_runs(pat)
    if not runs:
        return []
    size, hits = len(pat), []
    pairs = [(o + k, b[k], b[k + 1]) for o, b in runs for k in range(len(b) - 1)]
    if index is not None and pairs:
        off, a, b = min(pairs, key=lambda p: len(index(p[1], p[2])))
        for pos in index(a, b):
            base = pos - off
            if 0 <= base and base + size <= len(rom) and all(
                    rom[base + o:base + o + len(r)] == r for o, r in runs):
                hits.append(base)
        return hits
    anchor_off, anchor = max(runs, key=lambda r: len(r[1]))
    rest = [r for r in runs if r[0] != anchor_off]
    pos = rom.find(anchor)
    while pos != -1:
        base = pos - anchor_off
        if 0 <= base and base + size <= len(rom) and all(
                rom[base + o:base + o + len(b)] == b for o, b in rest):
            hits.append(base)
        pos = rom.find(anchor, pos + 1)
    return hits


def operand_text(rom, at, rel, mnem, mode, n, m, x, names):
    pc = at + rel
    val = int.from_bytes(rom[pc + 1:pc + n], 'little')
    bank = 0xC0 + (at >> 16)
    text = f'{mnem} {format_operand(val, mode, (pc + n) & 0xFFFF, bank, CPUState(m, x, False))}'
    target = None
    if mnem in CONTROL:
        if mode in ('long', 'long_x'):
            target = val
        elif mode == 'abs':
            target = bank << 16 | val
    if target is not None:
        label = f'${target >> 16:02X}:{target & 0xFFFF:04X}'
        text = f'{mnem} {label}'
        if target in names:
            text += f' ({names[target]})'
    return text, target


def fragments(rom, start, pat, insns, seed_len, max_hits, banks, index):
    """Seed-and-extend: search every run of `seed_len` consecutive decoded
    instructions, then grow each hit an instruction at a time in both
    directions while the pattern still matches. Returns
    ([(source_offset, copy_offset, length)], seeds skipped for max_hits)."""
    starts = sorted(insns)
    length = {pc: insns[pc][3] for pc in starts}

    def same(pc, d):
        return all(pat[pc - start + k] is None or rom[pc + d + k] == pat[pc - start + k]
                   for k in range(length[pc]))

    found, covered, skipped = [], {}, 0
    for i in range(len(starts) - seed_len + 1):
        run = starts[i:i + seed_len]
        if any(run[k] + length[run[k]] != run[k + 1] for k in range(seed_len - 1)):
            continue
        a, b = run[0], run[-1] + length[run[-1]]
        hits = [p for p in search(rom, pat[a - start:b - start], index)
                if p != a and (0xC0 + (p >> 16)) in banks]
        if max_hits and len(hits) > max_hits:
            skipped += 1
            continue
        for p in hits:
            d = p - a
            if any(lo <= a < hi for lo, hi in covered.get(d, ())):
                continue
            lo_i, hi_i = i, i + seed_len - 1
            while (lo_i > 0 and starts[lo_i - 1] + length[starts[lo_i - 1]] == starts[lo_i]
                   and starts[lo_i - 1] + d >= 0 and same(starts[lo_i - 1], d)):
                lo_i -= 1
            while (hi_i + 1 < len(starts) and starts[hi_i] + length[starts[hi_i]] == starts[hi_i + 1]
                   and starts[hi_i + 1] + length[starts[hi_i + 1]] + d <= len(rom)
                   and same(starts[hi_i + 1], d)):
                hi_i += 1
            lo, hi = starts[lo_i], starts[hi_i] + length[starts[hi_i]]
            covered.setdefault(d, []).append((lo, hi))
            found.append((lo - start, lo + d, hi - lo))
    return found, skipped


# ── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__.split('\n\n', 1)[1])
    ap.add_argument('--min', type=int, default=16, help='smallest routine size to look for')
    ap.add_argument('--banks', default='C0-FF', help='banks to search, e.g. C0-C3,FD')
    ap.add_argument('--relocatable', action='store_true',
                    help='mask absolute/long operands (JSR/JMP/JSL/JML targets, data addresses)')
    ap.add_argument('--mask-dp', action='store_true',
                    help='with --relocatable, also mask direct-page operands')
    ap.add_argument('--min-instructions', type=int, default=0,
                    help='skip routines that decode to fewer instructions (data tables exempt)')
    ap.add_argument('--max-hits', type=int, default=20,
                    help='skip patterns matching more places than this (0 = no limit)')
    ap.add_argument('--fragments', type=int, default=0, metavar='N',
                    help='with --relocatable, also find partial copies: seed on every run of N '
                         'instructions and extend (sizes are then the copy, not the routine)')
    ap.add_argument('--max-differing', type=int, default=None, metavar='N',
                    help='with --relocatable, drop copies with more than N differing operands')
    ap.add_argument('--unmatched-only', action='store_true',
                    help='only list copies outside matched routines')
    ap.add_argument('--json', action='store_true', help='machine-readable output')
    args = ap.parse_args()
    t0 = time.monotonic()

    rom = ROM_PATH.read_bytes()
    with FUNCTIONS.open() as f:
        rows = list(csv.DictReader(f))
    spans = [(offset(r['address']), offset(r['address']) + int(r['size']), r['name']) for r in rows]
    owner, names = {}, {}
    for start, end, name in spans:
        names[0xC00000 + start] = name
        for i in range(start, end):
            owner[i] = name
    hints = parse_headers({n for _, _, n in spans})
    exits = {0xC00000 + start: hints[name]['exit'] for start, _, name in spans
             if name in hints}
    search_banks = set(parse_banks(args.banks))
    index = PairIndex(rom) if args.fragments else None

    results, skipped, undecoded, skipped_seeds = [], [], [], 0
    for start, end, name in spans:
        size = end - start
        if size < args.min:
            continue
        hint = hints.get(name, {})
        is_data = hint.get('data', False)
        insns, state = ({}, None) if is_data else best_decode(rom, start, end, hint, exits)
        if not is_data and state is None:
            undecoded.append(name)
        if not is_data and len(insns) < args.min_instructions:
            continue
        if args.relocatable and insns:
            pat, masked = build_pattern(rom, start, end, insns, args.mask_dp)
        else:
            pat, masked = list(rom[start:end]), []
        hits = [p for p in search(rom, pat)
                if p != start and (0xC0 + (p >> 16)) in search_banks]
        if args.max_hits and len(hits) > args.max_hits:
            skipped.append((name, len(hits)))
            hits = []
        found = [(0, p, size) for p in hits]
        if args.fragments and insns:
            more, n_skipped = fragments(rom, start, pat, insns, args.fragments,
                                        args.max_hits, search_banks, index)
            found += more
            skipped_seeds += n_skipped
        for rel, p, length in found:
            if length < args.min:
                continue
            where = owner.get(p)
            if where and args.unmatched_only:
                continue
            diffs, n_masked, n_insns = [], 0, 0
            for pc in insns:
                n_insns += rel <= pc - start < rel + length
            for mrel, mnem, mode, n, m, x in masked:
                if not rel <= mrel < rel + length:
                    continue
                n_masked += 1
                a, b = start + mrel, p - rel + mrel
                if rom[a + 1:a + n] == rom[b + 1:b + n]:
                    continue
                src, st = operand_text(rom, start, mrel, mnem, mode, n, m, x, names)
                dst, dt = operand_text(rom, p - rel, mrel, mnem, mode, n, m, x, names)
                diffs.append({'source': src, 'copy': dst,
                              'delta': (dt - st) if st is not None and dt is not None else None})
            if insns and n_insns < args.min_instructions:
                continue
            if args.max_differing is not None and len(diffs) > args.max_differing:
                continue
            results.append({
                'address': snes(p), 'end': snes(p + length - 1), 'size': length,
                'source': name if rel == 0 else f'{name}+${rel:X}',
                'source_address': snes(start + rel), 'whole': length == size,
                'routine_size': size,
                'inside': where, 'instructions': n_insns,
                'masked_operands': n_masked, 'differing_operands': len(diffs),
                'differences': diffs, 'entry_state': (
                    None if state is None else
                    f"M={'8' if state[0] else '16'} X={'8' if state[1] else '16'}"),
            })

    # One line per copy: largest first, dropping any copy that mostly
    # overlaps one already kept (the same code found from two sources).
    kept: list[dict] = []
    for r in sorted(results, key=lambda r: (-r['size'], r['differing_operands'], r['address'])):
        lo = offset(r['address'])
        hi = lo + r['size']
        if not any(min(hi, k[1]) - max(lo, k[0]) > r['size'] // 2 for k in
                   ((offset(q['address']), offset(q['address']) + q['size']) for q in kept)):
            kept.append(r)
    results = kept
    elapsed = time.monotonic() - t0

    if args.json:
        json.dump({'mode': 'relocatable' if args.relocatable else 'exact',
                   'mask_dp': args.mask_dp, 'min': args.min,
                   'candidates': results,
                   'fragments': args.fragments,
                   'skipped_too_many_hits': [{'source': n, 'hits': h} for n, h in skipped],
                   'skipped_seeds': skipped_seeds,
                   'undecoded': undecoded, 'seconds': round(elapsed, 2)}, sys.stdout, indent=2)
        print()
        return 0

    if not args.relocatable:
        for r in results:
            where = f"inside {r['inside']}" if r['inside'] else 'unmatched'
            print(f"{r['address']}  {r['size']:4} B  copy of {r['source']} ({r['source_address']})  {where}")
        print(f'{len(results)} byte-identical copies of matched routines of {args.min}+ bytes.')
        return 0

    for rank, r in enumerate(results, 1):
        where = f"inside {r['inside']}" if r['inside'] else 'unmatched'
        part = '' if r['whole'] else f" [part, routine is {r['routine_size']} B]"
        print(f"{rank:3}. {r['address']}-{r['end'][4:]}  {r['size']:4} B  {r['source']} ({r['source_address']}){part}  "
              f"{where}  {r['differing_operands']}/{r['masked_operands']} operands differ")
        deltas = {d['delta'] for d in r['differences'] if d['delta'] is not None}
        for d in r['differences']:
            print(f"       {d['source']} -> {d['copy']}")
        if len(deltas) == 1 and len([d for d in r['differences'] if d['delta'] is not None]) > 1:
            print(f"       (every call target shifted by {deltas.pop():+#x})")
    total = sum(r['size'] for r in results)
    print(f'{len(results)} candidate(s), {total} bytes, in {elapsed:.1f} s.')
    if skipped:
        print(f'{len(skipped)} pattern(s) skipped, more than --max-hits {args.max_hits} matches: '
              + ', '.join(f'{n} ({h})' for n, h in skipped), file=sys.stderr)
    if skipped_seeds:
        print(f'{skipped_seeds} fragment seed(s) skipped, more than --max-hits {args.max_hits} matches.',
              file=sys.stderr)
    if undecoded:
        print(f'{len(undecoded)} routine(s) searched exactly (no sane decode): '
              + ', '.join(undecoded), file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
