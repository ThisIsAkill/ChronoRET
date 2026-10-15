#!/usr/bin/env python3
"""
data_survey.py — Check symbols/data_survey.csv, the map of every ROM byte the
source does not emit, and print its totals.

The CSV (one row per region; DATA_PLAN.md has the method and the plan) must
cover exactly the bytes `tools/verify.py` does not count as "emitted by
source" (the packed $C3 module, which verify counts apart, counts as
emitted): no gap, no overlap, no row across a bank boundary, each row's
size equal to its extent. This tool checks that against a fresh verify-style
assembly (the source on all-$00 and all-$FF bases), so the CSV goes stale,
and the check fails, as soon as matching data in source shrinks the
unemitted set; rows inside newly emitted bytes must then be removed or cut.

    python3 tools/data_survey.py              check the CSV, print totals
    python3 tools/data_survey.py --totals     totals only (no ROM needed)
    python3 tools/data_survey.py --packs      also check every packed_lz row:
                                              it is one Decomp_ToWram stream
                                              ending at the row's last byte and
                                              unpacking to the size its format
                                              names; with tools/c3pack.py
                                              present, it repacks byte-exact
    python3 tools/data_survey.py --gaps       list the bytes the CSV misses or
                                              claims wrongly (to update it)

Without the ROM (or asar) only the CSV's own consistency is checked. Exit
status is non-zero on any failure.

The CSV holds offsets, sizes, names, formats and counts only, never ROM
bytes; fill rows name their fill value, which is a format fact.
"""

import argparse
import csv
import re
import shutil
import sys
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))

CSV_PATH = ROOT / 'symbols' / 'data_survey.csv'
ROM_PATH = ROOT / 'roms' / 'chrono_trigger.sfc'
ROM_SIZE = 0x400000
COLUMNS = ['start', 'end', 'size', 'bank', 'kind', 'format', 'readers', 'confidence', 'notes']
KINDS = {'packed_lz', 'graphics', 'sprite_layout', 'text', 'font', 'brr_sample', 'music_sequence',
         'spc_data', 'table', 'battle_script', 'event_script', 'palette', 'tilemap', 'map',
         'padding', 'unknown'}
CONFIDENCE = {'confirmed', 'probable', 'unknown'}
ADDR = re.compile(r'^\$([C-F][0-9A-F]):([0-9A-F]{4})$')
PACK_FORMAT = re.compile(r'^lz(11|12) -> (\d+) B\b')


class SurveyError(Exception):
    pass


def parse_addr(text: str) -> int:
    """File offset of a `$BB:AAAA` HiROM address (bank $C0 + n is offset n * $10000)."""
    m = ADDR.match(text)
    if not m:
        raise SurveyError(f'bad address {text!r} (expected $BB:AAAA, bank $C0-$FF)')
    return (int(m.group(1), 16) - 0xC0) << 16 | int(m.group(2), 16)


def read_rows(path: Path = CSV_PATH) -> list[dict]:
    with open(path, newline='') as f:
        lines = [line for line in f if not line.startswith('#')]
    reader = csv.DictReader(lines)
    if reader.fieldnames != COLUMNS:
        raise SurveyError(f'{path.name}: columns are {reader.fieldnames}, expected {COLUMNS}')
    return list(reader)


def check_rows(rows: list[dict]) -> tuple[list[tuple[int, int]], list[str]]:
    """The rows' [start, end) offset ranges, in order, and the problems found
    in the CSV on its own (fields, sizes, order, overlaps, bank boundaries)."""
    problems, ranges = [], []
    prev_end = -1
    for n, row in enumerate(rows, 2):
        where = f'row {n} ({row.get("start")})'
        try:
            s, e = parse_addr(row['start']), parse_addr(row['end']) + 1
        except SurveyError as err:
            problems.append(f'{where}: {err}')
            continue
        if not row['size'].isdigit() or int(row['size']) != e - s:
            problems.append(f'{where}: size {row["size"]} but the extent is {e - s} bytes')
        if e <= s:
            problems.append(f'{where}: ends before it starts')
        if s >> 16 != (e - 1) >> 16:
            problems.append(f'{where}: crosses a bank boundary')
        if row['bank'] != f'${0xC0 + (s >> 16):02X}':
            problems.append(f'{where}: bank {row["bank"]} does not match the start')
        if row['kind'] not in KINDS:
            problems.append(f'{where}: unknown kind {row["kind"]!r}')
        if row['confidence'] not in CONFIDENCE:
            problems.append(f'{where}: unknown confidence {row["confidence"]!r}')
        if row['kind'] == 'packed_lz' and not PACK_FORMAT.match(row['format']):
            problems.append(f'{where}: a packed_lz format must start "lz11|lz12 -> N B"')
        if s < prev_end:
            problems.append(f'{where}: overlaps or is out of order with the row before')
        prev_end = max(prev_end, e)
        ranges.append((s, e))
    return ranges, problems


def unemitted_ranges() -> list[tuple[int, int]]:
    """[start, end) ranges of the bytes the source does not emit (verify.py's
    definition: the source assembled onto all-$00 and all-$FF bases)."""
    import os
    import verify
    os.chdir(ROOT)                      # verify assembles asm/main.asm by a relative path
    with tempfile.TemporaryDirectory() as tmp:
        lo = verify.assemble_onto(0x00, Path(tmp))
        hi = verify.assemble_onto(0xFF, Path(tmp))
    # The packed $C3 module is a placeholder in these assemblies; verify.py
    # counts it as emitted on its own (c3pack packs it from source), so it is
    # not data to survey either.
    import c3pack
    packed = range(c3pack.MODULE_ROM, c3pack.MODULE_ROM + c3pack.MODULE_PACKED_SIZE)
    out, start = [], None
    for i in range(ROM_SIZE):
        free = lo[i] != hi[i] and i not in packed
        if free and start is None:
            start = i
        elif not free and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, ROM_SIZE))
    return out


def coverage_problems(ranges, free) -> list[str]:
    """Differences between the rows' bytes and the unemitted bytes."""
    def merged(rs):
        out = []
        for s, e in sorted(rs):
            if out and s <= out[-1][1]:
                out[-1][1] = max(out[-1][1], e)
            else:
                out.append([s, e])
        return out

    def minus(a, b):
        out, j = [], 0
        for s, e in a:
            cur = s
            while j < len(b) and b[j][1] <= cur:
                j += 1
            k = j
            while k < len(b) and b[k][0] < e:
                if b[k][0] > cur:
                    out.append((cur, b[k][0]))
                cur = max(cur, b[k][1])
                k += 1
            if cur < e:
                out.append((cur, e))
        return out

    a, b = merged(ranges), merged(free)
    name = lambda s, e: f'${0xC0 + (s >> 16):02X}:{s & 0xFFFF:04X}-${0xC0 + ((e - 1) >> 16):02X}:{(e - 1) & 0xFFFF:04X}'
    problems = [f'not in the CSV (unemitted): {name(s, e)} ({e - s} B)' for s, e in minus(b, a)]
    problems += [f'in the CSV but emitted by source: {name(s, e)} ({e - s} B)' for s, e in minus(a, b)]
    return problems


def unpack_end(rom: bytes, start: int) -> tuple[int, int]:
    """(offset just past the final end marker, unpacked size) of the
    Decomp_ToWram stream at `start` (the format: Decomp_ToWram's header in
    asm/bankC3/bankC3.asm). Raises SurveyError where the routine would
    misread it."""
    try:
        w = rom[start] | rom[start + 1] << 8
        x, seg_end = start + 2, start + 2 + w
        mode = 11 if rom[seg_end] & 0xC0 else 12
        mask, size, left = (1 << mode) - 1, 0, 8
        while True:
            if x == seg_end:
                m = rom[x]
                if m & 0x3F == 0:
                    return x + 1, size
                left, seg_end, x = m & 0x3F, start + (rom[x + 1] | rom[x + 2] << 8), x + 3
                continue
            if x > seg_end:
                raise SurveyError('items run past an end marker')
            c = rom[x]
            if c == 0:
                size, x = size + 8, x + 9
                continue
            x += 1
            for i in range(left):
                if c >> i & 1:
                    v = rom[x] | rom[x + 1] << 8
                    if v & mask == 0 or v & mask > size:
                        raise SurveyError('a back-reference before the start')
                    size, x = size + (v >> mode) + 3, x + 2
                else:
                    size, x = size + 1, x + 1
            left = 8
    except IndexError:
        raise SurveyError('runs off the end of the ROM') from None


def pack_problems(rows, rom, repack: bool = True) -> tuple[list[str], int]:
    """Problems with the packed_lz rows, and how many were repacked (with
    tools/c3pack.py present and `repack`)."""
    c3pack = None
    if repack:
        try:
            import c3pack
        except ImportError:
            pass
    problems, repacked = [], 0
    for row in rows:
        if row['kind'] != 'packed_lz':
            continue
        s, e = parse_addr(row['start']), parse_addr(row['end']) + 1
        want = int(PACK_FORMAT.match(row['format']).group(2))
        try:
            end, size = unpack_end(rom, s)
        except SurveyError as err:
            problems.append(f'{row["start"]}: not a pack ({err})')
            continue
        if end != e or size != want:
            problems.append(f'{row["start"]}: the stream ends at +{end - s} and unpacks to {size} B; '
                            f'the row says +{e - s} and {want} B')
            continue
        if c3pack is not None:
            data, _, mode = c3pack.unpack(rom, s)
            if c3pack.pack(data, mode) != rom[s:e]:
                problems.append(f'{row["start"]}: does not repack byte-exact')
            repacked += 1
    return problems, repacked


def totals(rows) -> str:
    by_kind, by_conf, conf_kind, count = Counter(), Counter(), defaultdict(Counter), Counter()
    for row in rows:
        n = int(row['size'])
        by_kind[row['kind']] += n
        by_conf[row['confidence']] += n
        conf_kind[row['kind']][row['confidence']] += n
        count[row['kind']] += 1
    total = sum(by_kind.values())
    lines = [f'{"kind":<16}{"bytes":>11}{"of ROM":>9}{"rows":>7}   confirmed / probable / unknown']
    for kind, n in by_kind.most_common():
        c = conf_kind[kind]
        lines.append(f'{kind:<16}{n:>11,}{100 * n / ROM_SIZE:>8.2f}%{count[kind]:>7}'
                     f'   {c["confirmed"]:,} / {c["probable"]:,} / {c["unknown"]:,}')
    lines.append(f'{"total":<16}{total:>11,}{100 * total / ROM_SIZE:>8.2f}%{len(rows):>7}')
    lines.append('confidence: ' + ', '.join(f'{k} {by_conf[k]:,} ({100 * by_conf[k] / total:.2f}%)'
                                            for k in ('confirmed', 'probable', 'unknown')))
    return '\n'.join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--totals', action='store_true', help='print the totals only')
    ap.add_argument('--packs', action='store_true', help='also check every packed_lz row against the ROM')
    ap.add_argument('--gaps', action='store_true', help='list every coverage difference')
    ap.add_argument('--csv', type=Path, default=CSV_PATH)
    args = ap.parse_args()

    try:
        rows = read_rows(args.csv)
    except (OSError, SurveyError) as err:
        print(f'data_survey: {err}', file=sys.stderr)
        return 1
    ranges, problems = check_rows(rows)
    if args.totals:
        print(totals(rows))
        return 1 if problems else 0

    have_rom = ROM_PATH.exists() and shutil.which('asar') is not None
    if have_rom:
        problems += coverage_problems(ranges, unemitted_ranges())
        if args.packs:
            more, repacked = pack_problems(rows, ROM_PATH.read_bytes())
            problems += more
            print(f'packed_lz rows checked against the ROM; {repacked} repacked byte-exact'
                  + ('' if repacked else ' (tools/c3pack.py not present: unpack check only)'))
    else:
        print('data_survey: no ROM or asar: checking the CSV on its own (no coverage check)')

    print(totals(rows))
    if problems:
        shown = problems if args.gaps else problems[:20]
        print(f'FAIL: {len(problems)} problem(s):', file=sys.stderr)
        for p in shown:
            print('  ' + p, file=sys.stderr)
        if len(shown) < len(problems):
            print(f'  ... {len(problems) - len(shown)} more (--gaps lists all)', file=sys.stderr)
        return 1
    print('OK: the rows cover exactly the bytes the source does not emit'
          if have_rom else 'OK: the CSV is consistent')
    return 0


if __name__ == '__main__':
    sys.exit(main())
