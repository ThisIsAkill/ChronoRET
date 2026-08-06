#!/usr/bin/env python3
"""
diff_rom.py — Compare a built ROM against the original to confirm a
byte-exact (or track partial) match.

Usage:
    python3 diff_rom.py <original.sfc> <built.sfc>

Exit codes:
    0 = identical
    1 = differences found (summary printed)
    2 = usage / file error
"""
import sys
from pathlib import Path

SNES_HEADER_SIZE = 512  # some dumps include a copier header; we normalize it out


def strip_header(data: bytes) -> bytes:
    """Strip a 512-byte copier header if present (ROM size not a multiple
    of 1024 after removing it would indicate no header was present)."""
    if len(data) % 1024 == SNES_HEADER_SIZE % 1024 and len(data) > SNES_HEADER_SIZE:
        # Heuristic: if stripping 512 bytes makes the size a clean power-of-2-ish
        # SNES size, assume a header was present.
        remainder = len(data) - SNES_HEADER_SIZE
        if remainder in (0x80000, 0x100000, 0x200000, 0x300000, 0x400000):
            return data[SNES_HEADER_SIZE:]
    return data


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    orig_path, built_path = Path(sys.argv[1]), Path(sys.argv[2])
    for p in (orig_path, built_path):
        if not p.is_file():
            print(f"error: file not found: {p}")
            return 2

    orig = strip_header(orig_path.read_bytes())
    built = strip_header(built_path.read_bytes())

    if len(orig) != len(built):
        print(f"SIZE MISMATCH: original={len(orig)} bytes, built={len(built)} bytes")
        return 1

    diffs = [i for i in range(len(orig)) if orig[i] != built[i]]

    if not diffs:
        print(f"MATCH: {len(orig)} bytes identical.")
        return 0

    total = len(orig)
    matched = total - len(diffs)
    pct = 100.0 * matched / total
    print(f"DIFF: {len(diffs)} byte(s) differ out of {total} ({pct:.4f}% matched)")

    # Show first few contiguous diff ranges for quick orientation
    ranges = []
    start = diffs[0]
    prev = diffs[0]
    for i in diffs[1:]:
        if i != prev + 1:
            ranges.append((start, prev))
            start = i
        prev = i
    ranges.append((start, prev))

    print(f"First {min(10, len(ranges))} diff range(s):")
    for s, e in ranges[:10]:
        print(f"  0x{s:06X} - 0x{e:06X} ({e - s + 1} byte(s))")

    return 1


if __name__ == "__main__":
    sys.exit(main())
