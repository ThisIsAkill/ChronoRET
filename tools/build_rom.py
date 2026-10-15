#!/usr/bin/env python3
"""
build_rom.py — `make build`: the ROM from the source and the extracted
assets, with no copy of the original.

  1. tools/extract_data.py extract: the assets (build/assets/), from your
     own ROM, checked against rom.sha256 (skipped when current).
  2. tools/c3pack.py build: the packed $C3 module (build/c3pack/module.lz).
  3. The data packs: every `packed` piece of symbols/data_assets.csv is
     packed from its unpacked asset with tools/c3pack.py's packer, in the
     mode the manifest gives, to build/packs/<label>.lz. A pack is redone
     only when its asset, its mode or the packer change, or the .lz is no
     longer what was packed (a key beside it, build/packs/<label>.key, holds
     the inputs' hash and the output's sha256); a first build packs about 2.3 MB, in
     parallel. A pack whose size differs from its piece fails the build
     (the placement is fixed by the survey; an edited asset needs the
     layout regenerated, which is later work).
  4. The text: every `text` piece is encoded from its unit's readable
     text (build/assets/text/<unit>.txt) with tools/text.py, the
     dictionary unit first (the message text is compressed with it), to
     build/text/<label>.bin. It takes a fraction of a second, so it is
     redone every build; a file is rewritten only when its bytes change. A
     piece whose size differs fails the build, as a pack's does.
  5. The records: every `records` piece is encoded from its readable
     table (build/assets/records/<label>.tsv) with tools/records.py to
     build/records/<label>.bin, the same way (a file is rewritten only when
     its bytes change; a piece whose size differs fails the build).
  6. asar assembles asm/rom.asm (asm/main.asm, then the data layer
     asm/data/) onto a blank 4 MB image of $00 and again onto one of $FF.
     The two must be identical, which proves the source and the assets
     write every byte of the ROM; the result is build/chrono_trigger.built.sfc.

    python3 tools/build_rom.py [-o OUT]
"""

import argparse
import hashlib
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import c3pack  # noqa: E402
import extract_data  # noqa: E402
import records  # noqa: E402
import text  # noqa: E402

ROM_ASM = Path('asm/rom.asm')
OUT_ROM = Path('build/chrono_trigger.built.sfc')
ROM_SIZE = 0x400000


class BuildError(Exception):
    pass


def _pack_one(job: tuple[str, str, int, str]) -> tuple[str, bytes]:
    label, src, mode, _ = job
    return label, c3pack.pack(Path(src).read_bytes(), mode)


def build_packs(root: Path = ROOT, quiet: bool = True) -> int:
    """Pack every `packed` piece (see the docstring); returns how many were
    packed (0 when all were current)."""
    root = Path(root)
    packer = hashlib.sha256(Path(c3pack.__file__).read_bytes()).hexdigest()
    out_dir = root / extract_data.PACKS
    out_dir.mkdir(parents=True, exist_ok=True)
    jobs, sizes = [], {}
    for p in extract_data.read_manifest():
        if p['piece'] != 'packed':
            continue
        mode = int(extract_data.PACK_PARAM.match(p['param']).group(1))
        src = root / extract_data.ASSETS / p['asset']
        key = hashlib.sha256(f'{packer}\0{mode}\0'.encode() + src.read_bytes()).hexdigest()
        out, stamp = out_dir / f'{p["label"]}.lz', out_dir / f'{p["label"]}.key'
        sizes[p['label']] = int(p['size'])
        if out.exists() and stamp.exists() and \
                stamp.read_text() == f'{key} {hashlib.sha256(out.read_bytes()).hexdigest()}':
            continue
        jobs.append((p['label'], str(src), mode, key))
    if jobs:
        if not quiet:
            print(f'build_rom: packing {len(jobs):,} stream(s)')
        keys = {j[0]: j[3] for j in jobs}
        workers = min(len(jobs), os.cpu_count() or 1)
        if workers > 1:
            with ProcessPoolExecutor(workers) as ex:
                results = list(ex.map(_pack_one, jobs, chunksize=8))
        else:
            results = [_pack_one(j) for j in jobs]
        for label, data in results:
            stamp = out_dir / f'{label}.key'
            stamp.unlink(missing_ok=True)
            c3pack._write(out_dir / f'{label}.lz', data)
            c3pack._write(stamp, f'{keys[label]} {hashlib.sha256(data).hexdigest()}'.encode())
    wrong = []
    for label, size in sizes.items():
        got = (out_dir / f'{label}.lz').stat().st_size
        if got != size:
            wrong.append(f'{label}: {got} B, its piece {size} B')
    if wrong:
        raise BuildError('packs that do not fit their place:\n  ' + '\n  '.join(wrong))
    return len(jobs)


def build_text(root: Path = ROOT) -> int:
    """Encode every `text` piece (see the docstring); returns how many files
    were written."""
    root = Path(root)
    units = text.units_of(extract_data.read_manifest())
    texts = {u: (root / extract_data.ASSETS / ps[0]['asset']).read_text(encoding='utf-8')
             for u, ps in units.items()}
    try:
        encoded = text.encode_units(texts, units)
    except text.TextError as e:
        raise BuildError(f'text: {e}') from None
    out_dir = root / extract_data.TEXT_OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    wrong, written = [], 0
    for ps in units.values():
        for p in ps:
            data = encoded[p['label']]
            if len(data) != int(p['size']):
                wrong.append(f'{p["label"]}: {len(data)} B, its piece {p["size"]} B')
                continue
            path = out_dir / f'{p["label"]}.bin'
            if not path.exists() or path.read_bytes() != data:
                c3pack._write(path, data)
                written += 1
    if wrong:
        raise BuildError('text that does not fit its place:\n  ' + '\n  '.join(wrong))
    return written


def build_records(root: Path = ROOT) -> int:
    """Encode every `records` piece (see the docstring); returns how many
    files were written."""
    root = Path(root)
    pieces = extract_data.read_manifest()
    texts = {p['label']: (root / extract_data.ASSETS / p['asset']).read_text(encoding='utf-8')
             for p in pieces if p['piece'] == 'records'}
    try:
        encoded = records.encode_all(texts, pieces)
    except records.RecordsError as e:
        raise BuildError(f'records: {e}') from None
    out_dir = root / extract_data.RECORDS_OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    wrong, written = [], 0
    for p in pieces:
        if p['piece'] != 'records':
            continue
        data = encoded[p['label']]
        if len(data) != int(p['size']):
            wrong.append(f'{p["label"]}: {len(data)} B, its piece {p["size"]} B')
            continue
        path = out_dir / f'{p["label"]}.bin'
        if not path.exists() or path.read_bytes() != data:
            c3pack._write(path, data)
            written += 1
    if wrong:
        raise BuildError('records that do not fit their place:\n  ' + '\n  '.join(wrong))
    return written


def assemble(fill: int, out: Path, root: Path = ROOT) -> bytes:
    out.write_bytes(bytes([fill]) * ROM_SIZE)
    r = subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', str(ROM_ASM), str(out.resolve())],
                       cwd=root, capture_output=True, text=True)
    if r.returncode != 0:
        raise BuildError(f'asar failed on {ROM_ASM}:\n{r.stdout}{r.stderr}')
    data = out.read_bytes()
    if len(data) != ROM_SIZE:
        raise BuildError(f'{ROM_ASM} wrote {len(data):,} bytes, not {ROM_SIZE:,}')
    return data


def build(out: Path = OUT_ROM, root: Path = ROOT, quiet: bool = True) -> Path:
    root = Path(root)
    try:
        extract_data.extract(root, quiet=quiet)
    except extract_data.DataError as e:
        raise BuildError(str(e)) from None
    cwd = os.getcwd()
    os.chdir(root)
    try:
        c3pack.ensure_built(Path('.'))
    finally:
        os.chdir(cwd)
    build_packs(root, quiet=quiet)
    build_text(root)
    build_records(root)
    out = root / out
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out.parent) as tmp:
        lo = assemble(0x00, Path(tmp) / 'lo.sfc', root)
        hi = assemble(0xFF, Path(tmp) / 'hi.sfc', root)
        if lo != hi:
            gaps = [i for i in range(ROM_SIZE) if lo[i] != hi[i]]
            raise BuildError(f'{len(gaps):,} byte(s) are written by nothing (blank $00 and $FF images '
                             f'differ), the first at ${0xC0 + (gaps[0] >> 16):02X}:{gaps[0] & 0xFFFF:04X}')
        os.replace(Path(tmp) / 'lo.sfc', out)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('-o', '--output', type=Path, default=OUT_ROM)
    args = ap.parse_args()
    try:
        out = build(args.output, quiet=False)
    except BuildError as e:
        print(f'build_rom: {e}', file=sys.stderr)
        return 1
    print(f'Built -> {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out} '
          f'(every byte written by the source and the assets; no ROM copy)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
