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
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import c3pack  # noqa: E402
import isolated  # noqa: E402

ROM_PATH = Path('roms/chrono_trigger.sfc')
MAIN_ASM = Path('asm/main.asm')
ROM_SIZE = 0x400000


def assemble_onto(fill: int, workdir: Path, root: Path = Path('.')) -> bytes:
    """The source assembled onto an image of `fill`, where it cannot read the
    ROM (tools/isolated.py: a copy of asm/ only, no roms/ or build/, every
    file asar opens checked). The packed $C3 module's incbin gets a
    placeholder of the fill byte, so its bytes are not "emitted by source"
    here; main() checks them on their own."""
    c3pack.ensure_built(root)           # the packed $C3 module, checked against the ROM in main()
    iso = Path(workdir) / f'isolated_{fill:02x}'
    iso.mkdir()
    try:
        tree = isolated.make_tree(root, iso)
    except isolated.IsolationError as e:
        sys.stderr.write(f'verify: {e}\n')
        sys.exit(2)
    placeholder = tree / c3pack.MODULE_LZ
    placeholder.parent.mkdir(parents=True)
    placeholder.write_bytes(bytes([fill]) * c3pack.MODULE_PACKED_SIZE)
    out = iso / f'base_{fill:02x}.sfc'
    out.write_bytes(bytes([fill]) * ROM_SIZE)
    try:
        isolated.run_asar(['--no-title-check', '--fix-checksum=off', str(MAIN_ASM), str(out.resolve())],
                          tree, iso)
    except isolated.IsolationError as e:
        sys.stderr.write(f'verify: {e}\n')
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

    # The packed $C3 module: bankC3.asm incbins what tools/c3pack.py packs
    # from the module's source (a placeholder in the isolated assemblies), so
    # it is checked here on its own: the packed bytes must be the ROM's. How
    # much of the unpacked module is source comes from c3pack.source_bytes(),
    # isolated the same way.
    packed = range(c3pack.MODULE_ROM, c3pack.MODULE_ROM + c3pack.MODULE_PACKED_SIZE)
    built = c3pack.MODULE_LZ.read_bytes()
    packed_emitted = len(built)
    mismatched += [c3pack.MODULE_ROM + k for k in range(len(packed))
                   if k >= len(built) or built[k] != rom[c3pack.MODULE_ROM + k]]
    per_bank: dict[str, int] = {}
    for i in emitted:
        if i in packed:
            continue
        name = bank_name(i)
        per_bank[name] = per_bank.get(name, 0) + 1

    if args.json:
        print(json.dumps({
            'emitted_bytes': len(emitted),
            'mismatched_bytes': len(mismatched),
            'per_bank': per_bank,
            'packed_module_bytes': packed_emitted,
            'file_check': isolated.run_mode(),
            'ranges': [[s, e] for s, e in to_ranges(emitted)] if args.ranges else None,
        }, indent=2))
    else:
        for name in sorted(per_bank):
            print(f'  {name:<16} {per_bank[name]:>7,} bytes emitted by source')
        if packed_emitted:
            try:
                source = len(c3pack.source_bytes())
            except c3pack.PackError as e:
                sys.stderr.write(f'verify: {e}\n')
                return 2
            print(f'  {"$C3 packed":<16} {packed_emitted:>7,} bytes packed by tools/c3pack.py from the '
                  f'module ({source:,} of its {c3pack.MODULE_SIZE:,} unpacked bytes from source, '
                  f'the rest the ROM\'s)')
        print(f'  {"total":<16} {len(emitted) + packed_emitted:>7,} bytes')
        if args.ranges:
            for s, e in to_ranges(emitted):
                print(f'    0x{s:06X}-0x{e - 1:06X}  ({e - s} B)')

    if len(built) != len(packed):
        print(f'MISMATCH: {c3pack.MODULE_LZ} is {len(built):,} bytes, the ROM\'s pack '
              f'{len(packed):,}', file=sys.stderr)
        return 1
    mismatched.sort()
    if mismatched:
        print(f'MISMATCH: {len(mismatched)} emitted byte(s) differ from the ROM:', file=sys.stderr)
        for s, e in to_ranges(mismatched)[:20]:
            print(f'  0x{s:06X}-0x{e - 1:06X}', file=sys.stderr)
        return 1
    out = sys.stderr if args.json else sys.stdout
    if isolated.run_mode() == 'strace':
        print('File check: strace (asar opened no file outside the source).', file=out)
    else:
        print('UNCHECKED: no strace file-open check ran (tools/isolated.py), so a byte read '
              'from the ROM could count as source here; CI runs the check.', file=out)
    print('VERIFIED: every source-emitted byte matches the ROM.', file=out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
