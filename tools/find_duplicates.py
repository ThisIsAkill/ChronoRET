#!/usr/bin/env python3
"""
find_duplicates.py — Find byte-identical copies of matched routines.

A routine that appears twice in the ROM only has to be understood once:
the second copy is a near-free match (same instructions, same names,
re-verified at its own address). This lists, for every matched routine
of at least --min bytes, every other place in the ROM holding exactly the
same bytes: inside other matched routines (duplicated logic worth a
cross-reference) or in unmatched code (candidates to match next).

Usage:
    python3 tools/find_duplicates.py [--min 16] [--banks C0-C3,FD]
"""

import argparse
import csv
import sys
from pathlib import Path

ROM_PATH = Path('roms/chrono_trigger.sfc')
FUNCTIONS = Path('symbols/functions.csv')


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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--min', type=int, default=16, help='smallest routine size to look for')
    ap.add_argument('--banks', default='C0-FF', help='banks to search, e.g. C0-C3,FD')
    args = ap.parse_args()

    rom = ROM_PATH.read_bytes()
    with FUNCTIONS.open() as f:
        rows = list(csv.DictReader(f))
    spans = [(offset(r['address']), offset(r['address']) + int(r['size']), r['name']) for r in rows]
    owner = {}
    for start, end, name in spans:
        for i in range(start, end):
            owner[i] = name

    search = set(parse_banks(args.banks))
    found = 0
    for start, end, name in spans:
        if end - start < args.min:
            continue
        needle = rom[start:end]
        pos = rom.find(needle)
        hits = []
        while pos != -1:
            if pos != start and (0xC0 + (pos >> 16)) in search:
                where = owner.get(pos)
                hits.append(f'{snes(pos)} ({"inside " + where if where else "unmatched"})')
            pos = rom.find(needle, pos + 1)
        if hits:
            found += 1
            print(f'{name} ({snes(start)}, {end - start} B):')
            for h in hits:
                print(f'    also at {h}')
    print(f'{found} matched routine(s) of {args.min}+ bytes have byte-identical copies.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
