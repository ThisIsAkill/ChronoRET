#!/usr/bin/env python3
"""
verify.py — Prove every byte the source emits is byte-exact, independent of
the base ROM, and count matched bytes per bank.

`make diff` assembles over a copy of the original ROM, so a region the source
never writes still "matches". This tool closes that gap: it assembles the same
source onto two synthetic bases (all $00 and all $FF). A byte is *emitted by
source* exactly when both builds agree on it; every such byte must equal the
real ROM.

Usage:
    python3 tools/verify.py                 verify, print per-bank totals
    python3 tools/verify.py --json          same, machine-readable
    python3 tools/verify.py --ranges        also list emitted ranges

Exit status is non-zero on any mismatch or assembler error.
"""

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROM_PATH = Path('roms/chrono_trigger.sfc')
MAIN_ASM = Path('asm/main.asm')
ROM_SIZE = 0x400000


def assemble_onto(fill: int, workdir: Path) -> bytes:
    out = workdir / f'base_{fill:02x}.sfc'
    out.write_bytes(bytes([fill]) * ROM_SIZE)
    result = subprocess.run(
        ['asar', '--no-title-check', '--fix-checksum=off', str(MAIN_ASM), str(out)],
        capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        sys.exit(2)
    return out.read_bytes()


def to_ranges(offsets: list[int]) -> list[tuple[int, int]]:
    ranges = []
    for off in offsets:
        if ranges and ranges[-1][1] == off:
            ranges[-1] = (ranges[-1][0], off + 1)
        else:
            ranges.append((off, off + 1))
    return ranges


def bank_name(offset: int) -> str:
    # HiROM: file bank N is SNES bank $C0+N ($00-$3F:8000-FFFF are mirrors).
    return f'${0xC0 + (offset >> 16):02X}'


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--ranges', action='store_true')
    args = ap.parse_args()

    if not ROM_PATH.exists():
        sys.stderr.write(f'No ROM at {ROM_PATH}\n')
        return 2
    rom = ROM_PATH.read_bytes()
    if len(rom) != ROM_SIZE:
        sys.stderr.write(f'Expected unheadered {ROM_SIZE}-byte ROM\n')
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        lo = assemble_onto(0x00, Path(tmp))
        hi = assemble_onto(0xFF, Path(tmp))

    emitted = [i for i in range(ROM_SIZE) if lo[i] == hi[i]]
    mismatched = [i for i in emitted if lo[i] != rom[i]]

    per_bank: dict[str, int] = {}
    for i in emitted:
        name = bank_name(i)
        per_bank[name] = per_bank.get(name, 0) + 1

    if args.json:
        print(json.dumps({
            'emitted_bytes': len(emitted),
            'mismatched_bytes': len(mismatched),
            'per_bank': per_bank,
            'ranges': [[s, e] for s, e in to_ranges(emitted)] if args.ranges else None,
        }, indent=2))
    else:
        for name in sorted(per_bank):
            print(f'  {name:<16} {per_bank[name]:>7,} bytes emitted by source')
        print(f'  {"total":<16} {len(emitted):>7,} bytes')
        if args.ranges:
            for s, e in to_ranges(emitted):
                print(f'    0x{s:06X}-0x{e - 1:06X}  ({e - s} B)')

    if mismatched:
        print(f'MISMATCH: {len(mismatched)} emitted byte(s) differ from the ROM:', file=sys.stderr)
        for s, e in to_ranges(mismatched)[:20]:
            print(f'  0x{s:06X}-0x{e - 1:06X}', file=sys.stderr)
        return 1
    print('VERIFIED: every source-emitted byte matches the ROM.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
