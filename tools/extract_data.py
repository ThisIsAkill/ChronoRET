#!/usr/bin/env python3
"""
extract_data.py — The data layer: every ROM byte the 65816 and SPC700 source
does not emit, placed by generated source from the user's own ROM.

No ROM byte is ever committed (README, "Legal"). The data is described by
symbols/data_survey.csv (one row per region, DATA_PLAN.md); this tool turns
the survey into three things:

  symbols/data_assets.csv   the manifest (committed): one line per placed
                            piece, with its label, extent, how its bytes are
                            made and, for an asset, its path. Made from the
                            survey alone (no ROM): `layout()` below.
  asm/data/*.asm            the placement (committed, generated): per bank,
                            an `org` and a label at every piece, then a fill
                            directive, an incbin of an asset or a pointer
                            table written as labels. They hold no ROM byte:
                            only addresses, labels, fill values the survey
                            states, and incbin paths.
  build/assets/             the assets (ignored, never committed), written
                            from the user's ROM by `extract`: one file per
                            extracted or packed piece, one readable text file
                            per text unit. Packed streams are written
                            unpacked; tools/build_rom.py packs them back with
                            tools/c3pack.py at build time, and encodes the
                            text with tools/text.py.

How each piece's bytes are made (the manifest's `piece` column):

  fill       a padding row: `fill` of the value the survey names. Source.
  table      a pointer table whose entries all resolve to labels (a row or
             code label, plus an offset where an entry points inside a row,
             or $000000): `dl Label` / `dw Label` lines. Source; generating
             them reads the ROM's pointers once, the committed lines are
             labels only. A table row whose size is not a whole number of
             entries leaves a tail, which is extracted.
  extracted  the ROM's bytes, copied to build/assets/<kind>/<label>.bin and
             incbin'd. Counted as "extracted from the ROM" by
             tools/verify.py, never as emitted by source.
  packed     a Decomp_ToWram stream: its unpacked bytes go to
             build/assets/packed_lz/<label>.bin with the mode in the
             manifest; the build packs them to build/packs/<label>.lz,
             which is incbin'd. Counted as "packed from extracted assets".
  events     a location event script pack (a Decomp_ToWram stream reached
             through Evt_PackPtrs): build/assets/events/<label>.evt holds
             its disassembly (tools/events.py; checked to assemble back
             when written; a pack the disassembler cannot follow is kept
             there as bytes); the build assembles it to build/events/
             <label>.bin and packs that to build/packs/<label>.lz, which is
             incbin'd. param as for packed. Counted as "event scripts".
  records    a table or palette row with a layout in tools/records.py (a
             ROM struct, the reader's element width, BGR555 colours): its
             records go to build/assets/records/<label>.tsv (checked to
             encode back when written); the build encodes it to
             build/records/<label>.bin, which is incbin'd. param: the row's
             kind, then the record count and size. Counted as "records".
  text       a row of a text unit (tools/text.py's UNITS): the unit's
             readable text goes to build/assets/text/<unit>.txt (checked to
             encode back to the ROM's bytes when it is written); the build
             encodes it to build/text/<label>.bin, which is incbin'd. param
             is the row's layout in the unit. Counted as "text encoded from
             extracted text".

Why the placement is committed: it is the readable map of the ROM's data
(labels, addresses, what each region is, who reads it) and review sees how
it changes; it contains no ROM data. Its incbin lines are the only ones the
lint allows outside the two of the packed $C3 module (lint_readability.py,
FILEREAD): each must name a path this manifest lists (an asset, a pack or an
encoded text piece).

    python3 tools/extract_data.py extract     write build/assets/ from the ROM
                                              (checked against rom.sha256;
                                              nothing is redone when current)
    python3 tools/extract_data.py generate    rewrite the manifest and
                                              asm/data/ (needs the ROM and
                                              asar: the pointer tables)
    python3 tools/extract_data.py check       the manifest and asm/data/ are
                                              what `generate` writes (without
                                              the ROM the table entries are
                                              not compared)
"""

import argparse
import bisect
import csv
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import data_survey  # noqa: E402
import records  # noqa: E402
import text  # noqa: E402

ROM_PATH = ROOT / 'roms' / 'chrono_trigger.sfc'
ROM_SHA = ROOT / 'rom.sha256'
MANIFEST = ROOT / 'symbols' / 'data_assets.csv'
DATA_DIR = ROOT / 'asm' / 'data'
ASSETS = Path('build/assets')          # relative to the repository root
PACKS = Path('build/packs')
TEXT_OUT = Path('build/text')          # the encoded text pieces (tools/build_rom.py)
RECORDS_OUT = Path('build/records')    # the encoded records pieces (tools/build_rom.py)
STAMP_NAME = '.extracted'
ROM_SIZE = 0x400000

# Paths as the generated asm/data/*.asm write them (relative to asm/data/).
ASSET_PREFIX = '../../build/assets/'
PACK_PREFIX = '../../build/packs/'
TEXT_PREFIX = '../../build/text/'
RECORDS_PREFIX = '../../build/records/'

MANIFEST_COLUMNS = ['label', 'start', 'end', 'size', 'piece', 'asset', 'param']
PIECES = ('fill', 'table', 'extracted', 'packed', 'text', 'records', 'events')
LABEL = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
ASSET = re.compile(r'^[a-z_]+/[A-Za-z_][A-Za-z0-9_]*\.bin$')
TEXT_ASSET = re.compile(r'^text/([A-Za-z_][A-Za-z0-9_]*)\.txt$')
EVENTS_ASSET = re.compile(r'^events/([A-Za-z_][A-Za-z0-9_]*)\.evt$')
EVENTS_OUT = Path('build/events')      # the assembled (unpacked) event scripts (tools/build_rom.py)
EVENT_PACK = re.compile(r'\bvia Evt_PackPtrs\[')
RECORDS_ASSET = re.compile(r'^records/([A-Za-z_][A-Za-z0-9_]*)\.tsv$')
RECORDS_PARAM = re.compile(r'^(table|palette) (\d+) x (\d+) B$')
PACK_PARAM = re.compile(r'^lz(11|12) -> (\d+) B$')
FILL = re.compile(r'^(\d+) x \$([0-9A-F]{2})$')

# Pointer tables written as labels (row start -> entry size). Each is a
# survey row read by matched code as an array of long (3 B) or bank-local
# word (2 B) pointers; `generate` fails if an entry does not resolve.
TABLES = {
    '$C6:FDF0': 3,      # C2SceneRom_ObjPacks
    '$C6:FE20': 3,      # C2SceneRom_BgPacks
    '$C6:FEA0': 3,      # C2SceneRom_PalettePacks
    '$C6:FF00': 3,      # C2SceneRom_MetatilePacks
    '$C6:FF20': 3,      # C2SceneRom_MapPacks
    '$C6:FF40': 3,      # C2SceneRom_Bg3MapPacks
    '$C6:FF80': 3,      # C2SceneRom_Unk7000Packs
    '$C6:FFA0': 3,      # C2SceneRom_Unk7200Packs
    '$C6:FFC0': 3,      # C2SceneRom_ListPacks
    '$C6:FFE0': 3,      # C2SceneRom_ScriptPacks
    '$D0:E000': 3,      # BattleRom_BgMapPtrs
    '$D1:0000': 2,      # BattleRom_PcAttackFrames (bank $D1)
    '$D1:0060': 2,      # BattleRom_ActFrames (bank $D1)
    '$E4:2000': 3,      # BattleRom_SprTilesPtr
    '$F6:1E00': 3,      # Map_PropsPtrs
    '$F6:2100': 3,      # LocGfx_Meta12Ptrs
    '$F6:21C0': 3,      # LocGfx_Meta3Ptrs
    '$F6:2220': 3,      # LocGfx_PackPtrs
    '$FC:F9F0': 3,      # Evt_PackPtrs
    '$FE:0000': 3,      # C3Rom_PackPtrs
}

# Label prefixes of the packs, by the pointer table that reaches them (the
# survey's "via Table[i]"); the label is the prefix and the entry number.
PACK_PREFIXES = {
    'C3Rom_PackPtrs': 'C3Pack',
    'Evt_PackPtrs': 'EvtPack',
    'LocGfx_PackPtrs': 'LocGfxPack',
    'LocGfx_Meta12Ptrs': 'LocMeta12Pack',
    'LocGfx_Meta3Ptrs': 'LocMeta3Pack',
    'Map_PropsPtrs': 'MapPropsPack',
    'BattleRom_SprTilesPtr': 'SprTilesPack',
    'BattleRom_BgMapPtrs': 'BattleBgMapPack',
    'BattleRom_PcAttackFrames/ActFrames': 'ActFramesPack',
    'C2Scene_DialPacks': 'SceneDialPack',
    'C2SceneRom_ObjPacks': 'SceneObjPack',
    'C2SceneRom_BgPacks': 'SceneBgPack',
    'C2SceneRom_PalettePacks': 'ScenePalPack',
    'C2SceneRom_MetatilePacks': 'SceneMetatilePack',
    'C2SceneRom_MapPacks': 'SceneMapPack',
    'C2SceneRom_Bg3MapPacks': 'SceneBg3MapPack',
    'C2SceneRom_Unk7000Packs': 'Scene7000Pack',
    'C2SceneRom_Unk7200Packs': 'Scene7200Pack',
    'C2SceneRom_ListPacks': 'SceneListPack',
    'C2SceneRom_ScriptPacks': 'SceneScriptPack',
}
# A pack that a define names on its own (one pointer, no table).
SINGLE_PACKS = {'Credits_GfxPack', 'MenuRom_ScreenGfx'}

KIND_LABELS = {
    'packed_lz': 'Pack', 'graphics': 'Gfx', 'sprite_layout': 'SprLayout', 'text': 'Text',
    'font': 'Font', 'brr_sample': 'Brr', 'music_sequence': 'Music', 'spc_data': 'SpcData',
    'table': 'Table', 'battle_script': 'BattleScript', 'event_script': 'EvtScript',
    'palette': 'Palette', 'tilemap': 'Tilemap', 'map': 'MapData', 'padding': 'Padding',
    'unknown': 'Unknown',
}


class DataError(Exception):
    pass


def addr(offset: int) -> str:
    return f'${0xC0 + (offset >> 16):02X}:{offset & 0xFFFF:04X}'


def long_addr(offset: int) -> str:
    return f'${0xC0 + (offset >> 16):02X}{offset & 0xFFFF:04X}'


# ── The layout (survey -> pieces), no ROM needed ─────────────────────────────

_CODE_NAMES: list[dict[str, int | None]] = []


def code_names() -> dict[str, int | None]:
    """{name: address or None} of the labels and structs the code source
    defines (a text scan of asm/, no assembly): a survey name that is one
    already (a ROM struct in asm/include/, a label-only stub) is not placed
    again; its struct's address is checked instead (define_problems)."""
    if not _CODE_NAMES:
        names: dict[str, int | None] = {}
        asm = ROOT / 'asm'
        for path in sorted(asm.rglob('*')):
            if not path.is_file() or path.suffix not in ('.asm', '.inc') or DATA_DIR in path.parents:
                continue
            for line in path.read_text(errors='replace').splitlines():
                m = re.match(r'^struct\s+([A-Za-z_][A-Za-z0-9_]*)\s+\$([0-9A-Fa-f]{6})\b', line)
                if m:
                    names[m.group(1)] = int(m.group(2), 16)
                    continue
                m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):', line)
                if m:
                    names.setdefault(m.group(1), None)
        _CODE_NAMES.append(names)
    return _CODE_NAMES[0]


def survey_names(row: dict) -> list[str]:
    """The names the survey gives a row (its defines and ROM structs), the
    main one first."""
    notes = row['notes']
    m = re.match(r'named ([A-Za-z0-9_, ]+?)(?:;|$)', notes)
    if m:
        return [n.strip() for n in m.group(1).split(',') if LABEL.match(n.strip())]
    m = re.match(r'([A-Z][A-Za-z0-9]*_[A-Za-z0-9_]+)(?:;|$| \(| = [A-Za-z_])', notes)
    if m:
        return [m.group(1)]
    return []


def row_names(row: dict) -> list[str]:
    """The survey's names of a row that become labels here: those the code
    source does not define already."""
    taken = code_names()
    return [n for n in survey_names(row) if n not in taken]


def row_label(row: dict, start: int) -> str:
    """The label of a row: its survey name, else one made from what reaches
    it (a pack's pointer table and entry, a sample or song number), else its
    kind and address."""
    names = row_names(row)
    if names:
        return names[0]
    notes = row['notes']
    if row['kind'] == 'packed_lz':
        m = re.search(r'via ([A-Za-z0-9_/]+)\[(\d+)\]', notes)
        if m and m.group(1) in SINGLE_PACKS:
            return m.group(1)
        if m and m.group(1) in PACK_PREFIXES:
            return f'{PACK_PREFIXES[m.group(1)]}_{int(m.group(2)):03d}'
    if row['kind'] == 'text' and notes.startswith('message table,'):
        return f'MsgTable_{long_addr(start)[1:]}'
    m = re.match(r'sample (\d+) \(', notes)
    if m:
        return f'AudioSample_{int(m.group(1)):02d}'
    m = re.match(r'song 0x([0-9a-fA-F]{2}) \(', notes)
    if m:
        return f'AudioSong_{m.group(1).upper()}'
    return f'{KIND_LABELS[row["kind"]]}_{long_addr(start)[1:]}'


def layout(rows: list[dict] | None = None) -> list[dict]:
    """The pieces, in address order: one per survey row, a pointer table row
    with a tail two. Each piece is a manifest line (MANIFEST_COLUMNS, all
    strings) plus 'offset'/'stop' ints and the survey row."""
    rows = data_survey.read_rows() if rows is None else rows
    _, problems = data_survey.check_rows(rows)
    if problems:
        raise DataError('symbols/data_survey.csv: ' + '; '.join(problems[:5]))
    pieces, used = [], set()

    def unique(name: str) -> str:
        if name not in used:
            return name
        for suffix in ['_Cont'] + [f'_{n}' for n in range(2, 100)]:
            if name + suffix not in used:
                return name + suffix
        raise DataError(f'no unique label for {name}')

    def add(label, s, e, piece, asset='', param='', row=None):
        label = unique(label)
        used.add(label)
        if piece in ('extracted', 'packed'):
            kind = row['kind']
            asset = f'{kind}/{label}.bin'
        elif piece == 'records':
            asset = f'records/{label}.tsv'
        elif piece == 'events':
            asset = f'events/{label}.evt'
        pieces.append({'label': label, 'start': addr(s), 'end': addr(e - 1), 'size': str(e - s),
                       'piece': piece, 'asset': asset, 'param': param,
                       'offset': s, 'stop': e, 'row': row})

    for row in rows:
        s, e = data_survey.parse_addr(row['start']), data_survey.parse_addr(row['end']) + 1
        label = row_label(row, s)
        kind = row['kind']
        if kind == 'padding':
            m = FILL.match(row['format'])
            if not m or int(m.group(1)) != e - s:
                raise DataError(f'{row["start"]}: a padding row\'s format must be "N x $VV" with N its size')
            add(label, s, e, 'fill', param=f'${m.group(2)}', row=row)
        elif kind == 'packed_lz':
            m = data_survey.PACK_FORMAT.match(row['format'])
            add(label, s, e, 'events' if EVENT_PACK.search(row['notes']) else 'packed',
                param=f'lz{m.group(1)} -> {m.group(2)} B', row=row)
        elif row['start'] in text.ROWS:
            unit, fmt = text.ROWS[row['start']]
            if kind not in ('text', 'table'):
                raise DataError(f'{row["start"]}: a {kind} row cannot be a text unit\'s')
            add(label, s, e, 'text', asset=f'text/{unit}.txt', param=fmt, row=row)
        elif row['start'] not in TABLES and kind in ('table', 'palette') \
                and records.layout_for(row['start'], kind) is not None:
            lay = records.layout_for(row['start'], kind)
            try:
                n = records.check_extent(lay, e - s, row['start'])
            except records.RecordsError as err:
                raise DataError(f'symbols/data_survey.csv: {err}') from None
            add(label, s, e, 'records', param=f'{kind} {n} x {lay.size} B', row=row)
        elif row['start'] in TABLES:
            size = TABLES[row['start']]
            whole = (e - s) // size * size
            add(label, s, s + whole, 'table', param=f'{"dl" if size == 3 else "dw"} x {whole // size}',
                row=row)
            if whole < e - s:
                add(label + '_Tail', s + whole, e, 'extracted', row=row)
        else:
            add(label, s, e, 'extracted', row=row)
    return pieces


def render_manifest(pieces: list[dict]) -> str:
    buf = io.StringIO()
    buf.write('# The data layer\'s manifest: every piece tools/extract_data.py places, made from\n'
              '# symbols/data_survey.csv by `python3 tools/extract_data.py generate` (never by hand;\n'
              '# the lint checks it is that tool\'s output). piece: fill (source: the value in param),\n'
              '# table (source: pointer entries as labels), extracted (the ROM\'s bytes, from\n'
              '# build/assets/<asset>), packed (build/assets/<asset> holds the unpacked bytes, the build\n'
              '# packs them in the mode of param to build/packs/<label>.lz). The assets are written\n'
              '# from the user\'s own ROM into the ignored build/ directory; holds no ROM bytes.\n')
    w = csv.DictWriter(buf, fieldnames=MANIFEST_COLUMNS, lineterminator='\n', extrasaction='ignore')
    w.writeheader()
    w.writerows(pieces)
    return buf.getvalue()


def read_manifest(path: Path = MANIFEST) -> list[dict]:
    with open(path, newline='') as f:
        reader = csv.DictReader(line for line in f if not line.startswith('#'))
        if reader.fieldnames != MANIFEST_COLUMNS:
            raise DataError(f'{path.name}: columns are {reader.fieldnames}, expected {MANIFEST_COLUMNS}')
        out = list(reader)
    for p in out:
        try:
            p['offset'] = data_survey.parse_addr(p['start'])
            p['stop'] = data_survey.parse_addr(p['end']) + 1
            size = int(p['size'])
        except (data_survey.SurveyError, ValueError) as err:
            raise DataError(f'{path.name}: {p.get("label")}: {err}') from None
        if size != p['stop'] - p['offset'] or size <= 0:
            raise DataError(f'{path.name}: {p["label"]}: size {size} does not match its extent')
    return out


def manifest_problems(path: Path = MANIFEST) -> list[str]:
    """What is wrong with the committed manifest, without the ROM: its form
    (labels, asset paths under build/assets/ only, no '..' or absolute path,
    each piece kind with the fields it needs) and that it is exactly what
    layout() makes from the survey. Used by the lint (FILEREAD)."""
    try:
        have = read_manifest(path)
    except (OSError, DataError) as err:
        return [f'the data manifest cannot be read: {err}']
    problems = []
    seen_labels, seen_assets = set(), set()
    for p in have:
        where = f'{path.name}: {p["label"]}'
        if not LABEL.match(p['label']) or p['label'] in seen_labels:
            problems.append(f'{where}: a label must be a unique name')
        seen_labels.add(p['label'])
        if p['piece'] not in PIECES:
            problems.append(f'{where}: unknown piece {p["piece"]!r}')
        if p['piece'] in ('extracted', 'packed'):
            if not ASSET.match(p['asset']) or p['asset'] in seen_assets \
                    or Path(p['asset']).stem != p['label']:
                problems.append(f'{where}: the asset must be <kind>/<label>.bin, once: {p["asset"]!r}')
            seen_assets.add(p['asset'])
        elif p['piece'] == 'events':
            m = EVENTS_ASSET.match(p['asset'])
            if not m or m.group(1) != p['label'] or not PACK_PARAM.match(p['param']):
                problems.append(f'{where}: an events piece\'s asset is events/<label>.evt and its param '
                                f'"lzNN -> N B": {p["asset"]!r}, {p["param"]!r}')
        elif p['piece'] == 'records':
            m = RECORDS_ASSET.match(p['asset'])
            if not m or m.group(1) != p['label'] or not RECORDS_PARAM.match(p['param']):
                problems.append(f'{where}: a records piece\'s asset is records/<label>.tsv and its param '
                                f'"<kind> N x S B": {p["asset"]!r}, {p["param"]!r}')
        elif p['piece'] == 'text':
            m = TEXT_ASSET.match(p['asset'])
            if not m or m.group(1) not in text.UNITS:
                problems.append(f'{where}: a text piece\'s asset is text/<unit>.txt of a unit of '
                                f'tools/text.py: {p["asset"]!r}')
        elif p['asset']:
            problems.append(f'{where}: a {p["piece"]} piece has no asset')
        if p['piece'] == 'packed' and not PACK_PARAM.match(p['param']):
            problems.append(f'{where}: a packed piece\'s param is "lzNN -> N B"')
    try:
        want = render_manifest(layout())
    except DataError as err:
        return problems + [str(err)]
    if path.read_text() != want:
        problems.append(f'{path.name} is not what tools/extract_data.py makes from '
                        f'symbols/data_survey.csv (run `python3 tools/extract_data.py generate`)')
    return problems


def allowed_incbins(pieces: list[dict]) -> dict[str, dict]:
    """{incbin path as asm/data/ writes it: piece} for every asset piece."""
    out = {}
    for p in pieces:
        if p['piece'] == 'extracted':
            out[ASSET_PREFIX + p['asset']] = p
        elif p['piece'] in ('packed', 'events'):
            out[f'{PACK_PREFIX}{p["label"]}.lz'] = p
        elif p['piece'] == 'text':
            out[f'{TEXT_PREFIX}{p["label"]}.bin'] = p
        elif p['piece'] == 'records':
            out[f'{RECORDS_PREFIX}{p["label"]}.bin'] = p
    return out


def placeholder_files(pieces: list[dict]) -> dict[Path, int]:
    """{path relative to the root: size} of every file the data layer
    incbins: what the isolated assemblies (tools/verify.py) replace with
    fill bytes."""
    out = {}
    for p in pieces:
        if p['piece'] == 'extracted':
            out[ASSETS / p['asset']] = int(p['size'])
        elif p['piece'] in ('packed', 'events'):
            out[PACKS / f'{p["label"]}.lz'] = int(p['size'])
        elif p['piece'] == 'text':
            out[TEXT_OUT / f'{p["label"]}.bin'] = int(p['size'])
        elif p['piece'] == 'records':
            out[RECORDS_OUT / f'{p["label"]}.bin'] = int(p['size'])
    return out


# ── The placement (asm/data/*.asm) ───────────────────────────────────────────

def code_symbols(root: Path = ROOT) -> dict[int, str]:
    """{file offset: global label} of the code source (asm/main.asm
    assembled with asar's symbol output); the module's placeholder is
    built first."""
    import c3pack
    cwd = os.getcwd()
    os.chdir(root)
    try:
        c3pack.ensure_built(Path('.'))
        with tempfile.TemporaryDirectory() as tmp:
            out, sym = Path(tmp) / 'out.sfc', Path(tmp) / 'out.sym'
            out.write_bytes(bytes(ROM_SIZE))
            r = subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', '--symbols=wla',
                                f'--symbols-path={sym}', 'asm/main.asm', str(out)],
                               capture_output=True, text=True)
            if r.returncode != 0:
                raise DataError(f'asar failed on asm/main.asm:\n{r.stdout}{r.stderr}')
            text = sym.read_text()
    finally:
        os.chdir(cwd)
    labels = {}
    section = None
    for line in text.splitlines():
        if line.startswith('['):
            section = line.strip()
            continue
        m = re.match(r'^([0-9A-Fa-f]{2}):([0-9A-Fa-f]{4}) (\S+)$', line)
        if section == '[labels]' and m and '.' not in m.group(3) and ':' not in m.group(3):
            bank = int(m.group(1), 16)
            if bank >= 0xC0:
                labels.setdefault((bank - 0xC0) << 16 | int(m.group(2), 16), m.group(3))
    return labels


def table_entries(piece: dict, rom: bytes, pieces: list[dict], code: dict[int, str]) -> list[str]:
    """The table's entries as label expressions (raises DataError for one
    that does not resolve)."""
    size = 3 if piece['param'].startswith('dl') else 2
    starts = [p['offset'] for p in pieces]
    code_offsets = sorted(code)
    out = []
    for k in range(piece['offset'], piece['stop'], size):
        v = int.from_bytes(rom[k:k + size], 'little')
        if size == 2:
            if v == 0:
                out.append(('$0000', ''))
                continue
            v |= (0xC0 + (k >> 16)) << 16
        if v == 0:
            out.append(('$000000', 'none'))
            continue
        if v < 0xC00000:
            raise DataError(f'{piece["label"]} entry {(k - piece["offset"]) // size}: '
                            f'{v:06X} is not a ROM address')
        t = v - 0xC00000
        i = bisect.bisect_right(starts, t) - 1
        if i >= 0 and t < pieces[i]['stop']:
            target = pieces[i]
            if t == target['offset']:
                out.append((target['label'], ''))
            else:
                out.append((f'{target["label"]}+${t - target["offset"]:X}', 'inside the piece: not a stream start'))
            continue
        if t in code:
            out.append((code[t], ''))
            continue
        j = bisect.bisect_right(code_offsets, t) - 1
        if j < 0 or code_offsets[j] >> 16 != t >> 16:
            raise DataError(f'{piece["label"]} entry {(k - piece["offset"]) // size}: no label for {v:06X}')
        base = code_offsets[j]
        out.append((f'{code[base]}+${t - base:X}', 'into code: stale; this restates the pointer value'))
    directive = 'dl' if size == 3 else 'dw'
    lines = []
    for n, (expr, note) in enumerate(out):
        comment = f'{n}' + (f': {note}' if note else '')
        lines.append(f'    {directive} {expr:<34} ; {comment}')
    return lines


def wrap(text: str, width: int = 96, prefix: str = '; ') -> list[str]:
    words, lines, cur = text.split(), [], ''
    for w in words:
        if cur and len(prefix) + len(cur) + 1 + len(w) > width:
            lines.append(prefix + cur)
            cur = w
        else:
            cur = f'{cur} {w}' if cur else w
    if cur:
        lines.append(prefix + cur)
    return lines


def render_bank(bank: int, pieces: list[dict], tables: dict[str, list[str]] | None) -> str:
    """One bank's placement. `tables`: {label: entry lines}; None renders no
    entries (the comparison without the ROM)."""
    out = [
        '; ============================================================',
        f'; Bank ${bank:02X}: the data the code source does not emit',
        ';',
        '; Generated by tools/extract_data.py from symbols/data_survey.csv;',
        '; do not edit (run `python3 tools/extract_data.py generate`). Each',
        '; piece is a row of the survey (its kind, format, readers and',
        '; confidence are there) at its address. fill and pointer tables are',
        '; source; incbin reads an asset that tools/extract_data.py writes',
        '; from your own ROM to build/assets/, a pack tools/build_rom.py',
        '; makes from one in build/packs/ (event scripts assembled from',
        '; their disassembly first), or text or records it encodes into',
        '; build/text/ and build/records/ (symbols/data_assets.csv lists',
        '; them; nothing here is ROM data).',
        '; ============================================================',
    ]
    for p in pieces:
        row = p['row']
        out.append('')
        head = f'{p["start"]}-{p["end"]} ({int(p["size"]):,} B), {row["kind"]}, {row["confidence"]}: {row["format"]}'
        out += wrap(head)
        first = p['offset'] == data_survey.parse_addr(row['start'])
        if row['readers'] and first:
            out += wrap(f'Read by {row["readers"]}.')
        names = [p['label']]
        if first:
            names += [n for n in row_names(row) if n != p['label']]
        if first:
            known = [n for n in survey_names(row) if n not in names]
            if known:
                out += wrap(f'Also {", ".join(known)} (a struct or label of the code source).')
        out.append(f'org {long_addr(p["offset"])}')
        for n in names:
            out.append(f'{n}:')
        if p['piece'] == 'fill':
            out.append(f'    fillbyte {p["param"]}')
            out.append(f'    fill {int(p["size"])}')
        elif p['piece'] == 'extracted':
            out.append(f'    incbin "{ASSET_PREFIX}{p["asset"]}"')
        elif p['piece'] == 'packed':
            out.append(f'    incbin "{PACK_PREFIX}{p["label"]}.lz"          ; {p["param"]}')
        elif p['piece'] == 'events':
            out.append(f'    incbin "{PACK_PREFIX}{p["label"]}.lz"          ; {p["param"]}, event script')
        elif p['piece'] == 'records':
            out.append(f'    incbin "{RECORDS_PREFIX}{p["label"]}.bin"          ; records: {p["param"]}')
        elif p['piece'] == 'text':
            out.append(f'    incbin "{TEXT_PREFIX}{p["label"]}.bin"          ; text unit '
                       f'{Path(p["asset"]).stem} ({p["param"]})')
        elif tables is not None:
            out += tables[p['label']]
    return '\n'.join(out) + '\n'


def render_index(banks: list[int]) -> str:
    out = [
        '; ============================================================',
        '; The data layer: every byte asm/main.asm does not emit, placed',
        '; by bank (generated by tools/extract_data.py; asm/rom.asm',
        '; includes this after asm/main.asm).',
        '; ============================================================',
        '',
    ]
    out += [f'incsrc "bank{b:02X}.asm"' for b in banks]
    return '\n'.join(out) + '\n'


def render_all(pieces: list[dict], tables: dict[str, list[str]] | None) -> dict[Path, str]:
    by_bank: dict[int, list[dict]] = {}
    for p in pieces:
        by_bank.setdefault(0xC0 + (p['offset'] >> 16), []).append(p)
    files = {DATA_DIR / f'bank{b:02X}.asm': render_bank(b, ps, tables) for b, ps in sorted(by_bank.items())}
    files[DATA_DIR / 'data.asm'] = render_index(sorted(by_bank))
    return files


def tables_from_rom(pieces: list[dict], rom: bytes) -> dict[str, list[str]]:
    code = code_symbols()
    return {p['label']: table_entries(p, rom, pieces, code) for p in pieces if p['piece'] == 'table'}


def define_problems(pieces: list[dict]) -> list[str]:
    """Survey names that are defines in asm/include/ must hold the address of
    the label placed here (a define is how the code still reaches the data,
    since asm/main.asm is assembled without the data layer)."""
    defines = {}
    for path in sorted((ROOT / 'asm' / 'include').glob('*.inc')):
        for line in path.read_text(errors='replace').splitlines():
            m = re.match(r'^!([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$([0-9A-Fa-f]{6})\b', line)
            if m:
                defines[m.group(1)] = int(m.group(2), 16)
    structs = {n: a for n, a in code_names().items() if a is not None}
    problems = []
    for p in pieces:
        row = p['row']
        if p['offset'] != data_survey.parse_addr(row['start']):
            continue
        for n in survey_names(row) + [p['label']]:
            if n in defines and defines[n] != 0xC00000 + p['offset']:
                problems.append(f'!{n} = ${defines[n]:06X}, but its piece starts at {long_addr(p["offset"])}')
            if n in structs and structs[n] != 0xC00000 + p['offset']:
                problems.append(f'struct {n} is at ${structs[n]:06X}, but its piece starts at '
                                f'{long_addr(p["offset"])}')
    return problems


MASK = re.compile(r'^    (?:dl|dw) ')


def generated_problems(rom: bytes | None) -> list[str]:
    """Differences between asm/data/ and what `generate` writes (with the
    ROM in full; without it, the table entries are left out)."""
    pieces = layout()
    tables = tables_from_rom(pieces, rom) if rom is not None else None
    problems = []
    want = render_all(pieces, tables)
    have = {p: p.read_text() for p in sorted(DATA_DIR.glob('*'))} if DATA_DIR.exists() else {}
    for path in sorted(set(want) | set(have)):
        a, b = want.get(path), have.get(path)
        if a is not None and b is not None and tables is None:
            a = '\n'.join(x for x in a.splitlines() if not MASK.match(x))
            b = '\n'.join(x for x in b.splitlines() if not MASK.match(x))
        if a != b:
            problems.append(f'{path.relative_to(ROOT)} is not what tools/extract_data.py generates')
    return problems + define_problems(pieces)


# ── Extraction ───────────────────────────────────────────────────────────────

def expected_sha() -> str:
    return ROM_SHA.read_text().split()[0]


def read_rom() -> bytes:
    if not ROM_PATH.exists():
        raise DataError(f'no ROM at {ROM_PATH.relative_to(ROOT)}: the data is extracted from your own ROM')
    rom = ROM_PATH.read_bytes()
    if hashlib.sha256(rom).hexdigest() != expected_sha():
        raise DataError(f'{ROM_PATH.relative_to(ROOT)} is not the expected ROM (rom.sha256)')
    return rom


def _stamp_key(rom_sha: str) -> str:
    h = hashlib.sha256(b'extract_data v1\0' + rom_sha.encode())
    h.update(MANIFEST.read_bytes())
    h.update(Path(__file__).read_bytes())
    h.update(Path(text.__file__).read_bytes())         # the readable text's format
    h.update(Path(records.__file__).read_bytes())      # the records' layouts
    for tool in ('events.py', 'absint.py', 'disasm.py'):   # the event scripts' disassembly
        h.update((ROOT / 'tools' / tool).read_bytes())
    return h.hexdigest()


def _stamp_text(key: str, out_dir: Path, pieces: list[dict]) -> str:
    """The stamp: the inputs' key, then the sha256 of every asset as it is
    now ('-' for a missing one), so an asset changed or removed by hand
    no longer matches the stamp written after extraction."""
    lines, seen = [key], set()
    for p in pieces:
        if p['asset'] and p['asset'] not in seen:       # a text unit's file serves several pieces
            seen.add(p['asset'])
            f = out_dir / p['asset']
            lines.append(f'{hashlib.sha256(f.read_bytes()).hexdigest() if f.exists() else "-"} {p["asset"]}')
    return '\n'.join(lines) + '\n'


def extract(root: Path = ROOT, quiet: bool = True) -> Path:
    """Write build/assets/ from the ROM (see the docstring); returns its path.
    Nothing is rewritten when the ROM, manifest and this tool are unchanged
    and every asset still has the sha256 recorded at extraction; otherwise
    all are written again."""
    import c3pack
    out_dir = Path(root) / ASSETS
    stamp = out_dir / STAMP_NAME
    pieces = read_manifest()
    key = _stamp_key(expected_sha())
    if stamp.exists() and stamp.read_text() == _stamp_text(key, out_dir, pieces):
        return out_dir
    rom = read_rom()
    stamp.unlink(missing_ok=True)
    problems = extract_text(rom, out_dir, pieces) + extract_records(rom, out_dir, pieces)
    problems += extract_events(rom, out_dir, pieces, root, quiet)
    for p in pieces:
        s, e = p['offset'], p['stop']
        if p['piece'] == 'fill':
            value = int(p['param'][1:], 16)
            if rom[s:e] != bytes([value]) * (e - s):
                problems.append(f'{p["label"]}: not uniform {p["param"]} fill in this ROM')
            continue
        if p['piece'] in ('table', 'text', 'records'):
            continue
        if p['piece'] == 'events':
            continue
        dest = out_dir / p['asset']
        dest.parent.mkdir(parents=True, exist_ok=True)
        if p['piece'] == 'extracted':
            c3pack._write(dest, rom[s:e])
            continue
        mode, size = (int(x) for x in PACK_PARAM.match(p['param']).groups())
        try:
            data, end, got = c3pack.unpack(rom, s)
        except c3pack.PackError as err:
            problems.append(f'{p["label"]}: {err}')
            continue
        if end != e or got != mode or len(data) != size:
            problems.append(f'{p["label"]}: the stream ends at {addr(end - 1)}, mode {got}, '
                            f'{len(data)} B; the manifest says {p["end"]}, {p["param"]}')
            continue
        c3pack._write(dest, data)
    if problems:
        raise DataError('extraction failed:\n  ' + '\n  '.join(problems))
    stamp.write_text(_stamp_text(key, out_dir, pieces))
    if not quiet:
        n = len({p['asset'] for p in pieces if p['asset']})
        print(f'extract_data: {n:,} assets written to {ASSETS}/')
    return out_dir


def unpack_piece(rom: bytes, p: dict) -> tuple[bytes | None, str | None]:
    """(the unpacked bytes of a packed or events piece, or None and why)."""
    import c3pack
    mode, size = (int(x) for x in PACK_PARAM.match(p['param']).groups())
    try:
        data, end, got = c3pack.unpack(rom, p['offset'])
    except c3pack.PackError as err:
        return None, f'{p["label"]}: {err}'
    if end != p['stop'] or got != mode or len(data) != size:
        return None, (f'{p["label"]}: the stream ends at {addr(end - 1)}, mode {got}, '
                      f'{len(data)} B; the manifest says {p["end"]}, {p["param"]}')
    return data, None


def extract_events(rom: bytes, out_dir: Path, pieces: list[dict], root: Path = ROOT,
                   quiet: bool = True) -> list[str]:
    """Write the disassembly of every events piece (tools/events.py), each
    checked to assemble back to the unpacked bytes; the problems. A pack's
    disassembly is cached (build/events/cache/, by its bytes and the
    tools), since following every handler takes minutes."""
    import c3pack
    import events
    evp = [p for p in pieces if p['piece'] == 'events']
    if not evp:
        return []
    texts_pieces = [(p['label'], 0xC00000 + p['offset'], 0xC00000 + p['stop'])
                    for p in pieces if p['piece'] == 'text']
    addrs = {n: a for n, a, _ in texts_pieces}
    names = events.opcode_names()
    tools = hashlib.sha256()
    for tool in ('events.py', 'absint.py', 'disasm.py'):
        tools.update((ROOT / 'tools' / tool).read_bytes())
    tools.update(events._asm_hash(Path(root)).encode())
    cache = Path(root) / EVENTS_OUT / 'cache'
    cache.mkdir(parents=True, exist_ok=True)
    interp, problems, done = None, [], 0
    for p in evp:
        data, why = unpack_piece(rom, p)
        if data is None:
            problems.append(why)
            continue
        key = hashlib.sha256(tools.digest() + p['label'].encode() + b'\0' + data).hexdigest()
        hit = cache / f'{key}.evt'
        text = hit.read_text() if hit.exists() else None
        if text is not None:
            try:
                if events.assemble(text, names, addrs, p['label']) != data:
                    text = None
            except events.EventsError:
                text = None
        if text is None:
            if interp is None:
                interp = events.Interpreter(Path(root))
            text = events.extract_pack(interp, names, data, p['label'], texts_pieces)
            if events.assemble(text, names, addrs, p['label']) != data:
                problems.append(f'{p["label"]}: the event script does not assemble back')
                continue
            c3pack._write(hit, text.encode())
            done += 1
            if not quiet and done % 50 == 0:
                print(f'extract_data: {done} event scripts disassembled')
        dest = out_dir / p['asset']
        dest.parent.mkdir(parents=True, exist_ok=True)
        c3pack._write(dest, text.encode())
    return problems


def extract_records(rom: bytes, out_dir: Path, pieces: list[dict]) -> list[str]:
    """Write the readable file of every records piece (tools/records.py),
    each checked to encode back to the ROM's bytes; the problems."""
    import c3pack
    try:
        texts = records.extract_all(rom, pieces)
    except records.RecordsError as err:
        return [f'records: {err}']
    for p in pieces:
        if p['piece'] == 'records':
            dest = out_dir / p['asset']
            dest.parent.mkdir(parents=True, exist_ok=True)
            c3pack._write(dest, texts[p['label']].encode('utf-8'))
    return []


def extract_text(rom: bytes, out_dir: Path, pieces: list[dict]) -> list[str]:
    """Write the readable file of every text unit (tools/text.py) and check
    that the encoder makes the ROM's bytes from them again; the problems."""
    import c3pack
    units = text.units_of(pieces)
    if not units:
        return []
    problems, texts = [], {}
    try:
        dic = text.rom_dictionary(rom)
        for unit, ps in units.items():
            texts[unit] = text.extract_unit(rom, unit, ps, dic)
        encoded = text.encode_units(texts, units)
    except text.TextError as err:
        return [f'text: {err}']
    for unit, ps in units.items():
        bad = [p['label'] for p in ps if encoded[p['label']] != rom[p['offset']:p['stop']]]
        if bad:
            problems.append(f'text unit {unit}: {", ".join(bad)} do not encode back to the ROM\'s bytes')
            continue
        dest = out_dir / 'text' / f'{unit}.txt'
        dest.parent.mkdir(parents=True, exist_ok=True)
        c3pack._write(dest, texts[unit].encode('utf-8'))
    return problems


# ── Command line ─────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('extract', 'generate', 'check'))
    args = ap.parse_args()
    try:
        if args.command == 'extract':
            extract(quiet=False)
            return 0
        if args.command == 'generate':
            rom = read_rom()
            pieces = layout()
            files = render_all(pieces, tables_from_rom(pieces, rom))
            if DATA_DIR.exists():
                for old in DATA_DIR.glob('*'):
                    if old not in files:
                        old.unlink()
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            for path, text in files.items():
                path.write_text(text)
            MANIFEST.write_text(render_manifest(pieces))
            problems = define_problems(pieces)
            for p in problems:
                print(f'extract_data: {p}', file=sys.stderr)
            print(f'extract_data: {len(pieces):,} pieces in {len(files) - 1} bank files, '
                  f'{MANIFEST.relative_to(ROOT)} written')
            return 1 if problems else 0
        problems = manifest_problems()
        rom = None
        if ROM_PATH.exists() and shutil.which('asar'):
            rom = read_rom()
        else:
            print('extract_data: no ROM or asar: the pointer tables\' entries are not compared')
        problems += generated_problems(rom)
        for p in problems:
            print(f'extract_data: {p}', file=sys.stderr)
        if problems:
            return 1
        print('OK: the manifest and asm/data/ are what tools/extract_data.py generates')
        return 0
    except DataError as err:
        print(f'extract_data: {err}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
