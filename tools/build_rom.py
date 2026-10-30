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
  6. The scene and layer-effect scripts: every `scene` piece is
     assembled from build/assets/scene/<label>.scn to its unpacked bytes
     in build/scene/ (step 3 packs them), every `fx` piece from
     build/assets/fx/<label>.bfx to build/fx/<label>.bin, with
     tools/scripts.py, every line checked against the handlers.
  6c. The graphics: every `graphics` piece is encoded from its PNG and
     sidecar (build/assets/gfx/) with tools/graphics.py to build/gfx/,
     every `gfxpack` piece the same way to its unpacked bytes in
     build/gfxpack/, before step 3 packs them.
  6b. The battle scripts: every unit of `battle` pieces is assembled from
     its readable file (build/assets/battle/<unit>.bscr) with
     tools/battle.py, every line checked against the readers, to
     build/battle/<label>.bin per piece (a file is rewritten only when its
     bytes change; a piece whose size differs fails the build).
  7. asar assembles asm/rom.asm (asm/main.asm, then the data layer
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
import maps  # noqa: E402
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
        if p['piece'] not in ('packed', 'events', 'scene', 'gfxpack') + maps.PIECES:
            continue
        mode = extract_data.pack_param(p['param'])[0]
        src = (root / extract_data.ASSETS / p['asset'] if p['piece'] == 'packed'
               else root / extract_data.EVENTS_OUT / f'{p["label"]}.bin' if p['piece'] == 'events'
               else root / extract_data.MAPS_OUT / f'{p["label"]}.bin' if p['piece'] in maps.PIECES
               else root / extract_data.GFXPACK_OUT / f'{p["label"]}.bin' if p['piece'] == 'gfxpack'
               else root / extract_data.SCENE_OUT / f'{p["label"]}.bin')
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
        raise BuildError('packs that do not fit their place (a pack must come out the size the ROM\'s '
                         'stream is, since every pointer and placement is fixed: an edit that changes it '
                         'cannot be built):\n  ' + '\n  '.join(wrong))
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


def build_events(root: Path = ROOT) -> int:
    """Assemble every `events` piece's disassembly (build/assets/events/
    <label>.evt, tools/events.py) to its unpacked bytes in build/events/
    <label>.bin, which build_packs packs; returns how many files were
    written (a file is rewritten only when its bytes change)."""
    import events
    root = Path(root)
    pieces = extract_data.read_manifest()
    evp = [p for p in pieces if p['piece'] == 'events']
    if not evp:
        return 0
    names = events.opcode_names()
    addrs = {p['label']: 0xC00000 + p['offset'] for p in pieces if p['piece'] == 'text'}
    try:
        interp = events.Interpreter(root)        # every opcode line is checked against its handler
        interp.load(root)
    except events.EventsError as e:
        raise BuildError(f'events: {e}') from None
    out_dir = root / extract_data.EVENTS_OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    written, wrong = 0, []
    for p in evp:
        text = (root / extract_data.ASSETS / p['asset']).read_text()
        size = int(extract_data.PACK_PARAM.match(p['param']).group(2))
        if size and events.is_raw(text):
            raise BuildError(f'events: {p["label"]} is kept as bytes, not disassembled')
        try:
            data = events.assemble(text, names, addrs, p['label'], interp)
        except events.EventsError as e:
            raise BuildError(f'events: {e}') from None
        if len(data) != size:
            wrong.append(f'{p["label"]}: {len(data)} B unpacked, its pack holds {size} B')
            continue
        path = out_dir / f'{p["label"]}.bin'
        if not path.exists() or path.read_bytes() != data:
            c3pack._write(path, data)
            written += 1
    interp.save(root)
    if wrong:
        raise BuildError('event scripts that do not fit their place:\n  ' + '\n  '.join(wrong))
    return written


def build_scripts(root: Path = ROOT) -> int:
    """Assemble every scene piece (to its unpacked bytes in build/scene/,
    which build_packs packs) and fx piece (build/fx/), each from its
    readable file with tools/scripts.py, every line checked against the
    handlers; returns how many files were written."""
    import scripts
    root = Path(root)
    pieces = [p for p in extract_data.read_manifest() if p['piece'] in ('scene', 'fx')]
    if not pieces:
        return 0
    try:
        scene, fx = scripts.langs(root)
        pairs = scripts.scene_pairs_built(root)
    except scripts.ScriptsError as e:
        raise BuildError(f'scripts: {e}') from None
    written, wrong = 0, []
    try:
        for p in pieces:
            text_ = (root / extract_data.ASSETS / p['asset']).read_text()
            try:
                data = scripts.assemble_piece(scene if p['piece'] == 'scene' else fx, text_, p, pairs)
            except scripts.ScriptsError as e:
                raise BuildError(f'scripts: {e}') from None
            size = (int(extract_data.PACK_PARAM.match(p['param']).group(2)) if p['piece'] == 'scene'
                    else int(p['size']))
            if len(data) != size:
                wrong.append(f'{p["label"]}: {len(data)} B, its piece {size} B')
                continue
            out_dir = root / (extract_data.SCENE_OUT if p['piece'] == 'scene' else extract_data.FX_OUT)
            out_dir.mkdir(parents=True, exist_ok=True)
            path = out_dir / f'{p["label"]}.bin'
            if not path.exists() or path.read_bytes() != data:
                c3pack._write(path, data)
                written += 1
    finally:
        scene.save(root)
        fx.save(root)
    if wrong:
        raise BuildError('scripts that do not fit their place:\n  ' + '\n  '.join(wrong))
    return written


def build_graphics(root: Path = ROOT) -> int:
    """Encode every `graphics` piece from its PNG and sidecar
    (build/assets/gfx/, tools/graphics.py) to build/gfx/<label>.bin, and
    every `gfxpack` piece to its unpacked bytes in build/gfxpack/ (which
    build_packs packs); returns how many files were written. A PNG that
    is not what the format can hold fails the build."""
    import graphics
    root = Path(root)
    written = 0
    for p in extract_data.read_manifest():
        if p['piece'] not in ('graphics', 'gfxpack'):
            continue
        src = root / extract_data.ASSETS / p['asset']
        side = root / extract_data.ASSETS / graphics.sidecar_path(p['asset'])
        try:
            data = graphics.encode_piece(p, src.read_bytes(), side.read_text())
        except (OSError, graphics.GraphicsError) as e:
            raise BuildError(f'graphics: {e}') from None
        out_dir = root / (extract_data.GFX_OUT if p['piece'] == 'graphics' else extract_data.GFXPACK_OUT)
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / f'{p["label"]}.bin'
        if not path.exists() or path.read_bytes() != data:
            c3pack._write(path, data)
            written += 1
    return written


def build_maps(root: Path = ROOT) -> int:
    """Assemble every `mapprops` and `metatiles` piece from its text
    (build/assets/maps/, tools/maps.py) to its unpacked bytes in
    build/maps/, which build_packs packs; returns how many files were
    written."""
    import maps
    root = Path(root)
    written = 0
    for p in extract_data.read_manifest():
        if p['piece'] not in maps.PIECES:
            continue
        try:
            data = maps.assemble_piece(p, (root / extract_data.ASSETS / p['asset']).read_text())
        except (OSError, maps.MapsError) as e:
            raise BuildError(f'maps: {e}') from None
        out_dir = root / extract_data.MAPS_OUT
        out_dir.mkdir(parents=True, exist_ok=True)
        path = out_dir / f'{p["label"]}.bin'
        if not path.exists() or path.read_bytes() != data:
            c3pack._write(path, data)
            written += 1
    return written


def build_battle(root: Path = ROOT) -> int:
    """Assemble every battle script unit (see the docstring); returns how
    many files were written."""
    import battle
    root = Path(root)
    pieces = extract_data.read_manifest()
    units = sorted({p['param'].split('/')[0] for p in pieces if p['piece'] == 'battle'})
    if not units:
        return 0
    try:
        interp = battle.ActInterp(root)          # every opcode line is checked against its handler
        interp.load(root)
        fmt = battle.AiFormat(root, interp.image, interp.labels)
    except battle.BattleError as e:
        raise BuildError(f'battle: {e}') from None
    out_dir = root / extract_data.BATTLE_OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    written, wrong = 0, []
    try:
        for unit in units:
            text_ = (root / extract_data.ASSETS / f'battle/{unit}.bscr').read_text()
            try:
                out = battle.assemble_unit(unit, text_, pieces, interp, fmt, root)
            except battle.BattleError as e:
                raise BuildError(f'battle: {unit}: {e}') from None
            for p in pieces:
                if p['piece'] != 'battle' or p['param'].split('/')[0] != unit:
                    continue
                data = out.get(p['label'], b'')
                if len(data) != int(p['size']):
                    wrong.append(f'{p["label"]}: {len(data)} B, its piece {p["size"]} B')
                    continue
                path = out_dir / f'{p["label"]}.bin'
                if not path.exists() or path.read_bytes() != data:
                    c3pack._write(path, data)
                    written += 1
    finally:
        interp.save(root)
    if wrong:
        raise BuildError('battle scripts that do not fit their place:\n  ' + '\n  '.join(wrong))
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
    build_events(root)
    build_scripts(root)
    build_maps(root)
    build_graphics(root)
    build_packs(root, quiet=quiet)
    build_text(root)
    build_records(root)
    build_battle(root)
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
