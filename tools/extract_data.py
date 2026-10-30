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
             when written; a non-empty pack it cannot follow fails the
             extraction); the build assembles it to build/events/
             <label>.bin and packs that to build/packs/<label>.lz, which is
             incbin'd. param as for packed. Counted as "event scripts".
  battle     a row of a battle script unit (tools/battle.py's ROWS: the action
             scripts with their script and subscript tables, or the enemy
             behaviour scripts with their table): the unit's readable file
             goes to build/assets/battle/<unit>.bscr (checked to assemble
             back, every line against the readers, when it is written; a
             unit it cannot follow fails the extraction); the build
             assembles it to build/battle/<label>.bin, which is incbin'd.
             param: <unit>/<role>. Counted as "battle scripts".
  scene      a scene script pack (a Decomp_ToWram stream reached through
             C2SceneRom_ScriptPacks): build/assets/scene/<label>.scn holds
             its disassembly (tools/scripts.py; checked to assemble back
             when written); the build assembles it to build/scene/
             <label>.bin and packs that, which is incbin'd. param as for
             packed. Counted as "scene scripts".
  mapprops   a location map pack (Map_PropsPtrs): build/assets/maps/
             <label>.map, its header and tile planes as text (tools/maps.py;
             checked to assemble back when written); the build assembles it
             to build/maps/<label>.bin and packs that. param as for packed.
             Counted as "maps".
  metatiles  a metatile pack (LocGfx_Meta12Ptrs / Meta3Ptrs) of a whole
             table: build/assets/maps/<label>.meta, its tilemap words as
             text; built the same way. Counted as "maps".
  fx         the battle layer-effect scripts with their table
             (tools/scripts.py's FX_ROWS): build/assets/fx/<label>.bfx; the
             build assembles it to build/fx/<label>.bin, which is incbin'd.
             Counted as "layer-effect scripts".
  graphics   a row of tile graphics whose format a reader proves
             (tools/graphics.py's FORMATS): build/assets/gfx/<label>.png (an
             indexed PNG, palette index = pixel value) and <label>.gfx (its
             sidecar); the build encodes them to build/gfx/<label>.bin,
             which is incbin'd. param: "<format> N tiles [+ T B]". Counted
             as "graphics".
  sprframes  a sprite_layout row of frame records (tools/sprites.py: the
             runs from the set pointers, each with its sprite records'
             record size): build/assets/sprites/<label>.spr, its frames'
             tile words and position pairs as text (checked to assemble
             back when written, after the rows are checked against the
             runs); the build assembles it to build/sprites/<label>.bin,
             which is incbin'd. No param. Counted as "sprite frames".
  animframes, animtimes, drawlist  the pieces of the text tools
             (TEXT_TOOLS below): the sprite animation frame-id and duration
             lists of bank $E4 (tools/anims.py: build/assets/anims/
             <label>.anf / .ant) and the menu's draw lists (tools/
             drawlists.py: build/assets/menu/<label>.mdl), each checked
             against its readers and to assemble back when written; the
             build assembles them to build/<OUT>/<label>.bin, which is
             incbin'd. No param. Counted under their kinds.
  records   a table or palette row with a layout in tools/records.py (a
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
import battle  # noqa: E402
import maps  # noqa: E402
import graphics  # noqa: E402
import scripts  # noqa: E402
import sprites  # noqa: E402
import anims  # noqa: E402
import drawlists  # noqa: E402
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
BATTLE_OUT = Path('build/battle')      # the assembled battle script pieces (tools/build_rom.py)
MAPS_OUT = Path('build/maps')          # the assembled (unpacked) maps and metatiles (tools/build_rom.py)
SCENE_OUT = Path('build/scene')        # the assembled (unpacked) scene scripts (tools/build_rom.py)
FX_OUT = Path('build/fx')              # the assembled layer-effect scripts (tools/build_rom.py)
GFX_OUT = Path('build/gfx')            # the encoded graphics pieces (tools/build_rom.py)
SPRITES_OUT = Path('build/sprites')    # the assembled sprite frame pieces (tools/build_rom.py)
STAMP_NAME = '.extracted'
ROM_SIZE = 0x400000

# Paths as the generated asm/data/*.asm write them (relative to asm/data/).
ASSET_PREFIX = '../../build/assets/'
PACK_PREFIX = '../../build/packs/'
TEXT_PREFIX = '../../build/text/'
RECORDS_PREFIX = '../../build/records/'
BATTLE_PREFIX = '../../build/battle/'
FX_PREFIX = '../../build/fx/'
GFX_PREFIX = '../../build/gfx/'
SPRITES_PREFIX = '../../build/sprites/'

MANIFEST_COLUMNS = ['label', 'start', 'end', 'size', 'piece', 'asset', 'param']
PIECES = ('fill', 'table', 'extracted', 'packed', 'text', 'records', 'events', 'battle', 'scene', 'fx',
          'mapprops', 'metatiles', 'scenemaps', 'scenemeta', 'scenebg3',
          'graphics', 'sprframes', 'animframes', 'animtimes', 'drawlist')
LABEL = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
ASSET = re.compile(r'^[a-z_]+/[A-Za-z_][A-Za-z0-9_]*\.bin$')
TEXT_ASSET = re.compile(r'^text/([A-Za-z_][A-Za-z0-9_]*)\.txt$')
EVENTS_ASSET = re.compile(r'^events/([A-Za-z_][A-Za-z0-9_]*)\.evt$')
EVENTS_OUT = Path('build/events')      # the assembled (unpacked) event scripts (tools/build_rom.py)
EVENT_PACK = re.compile(r'\bvia Evt_PackPtrs\[')
BATTLE_ASSET = re.compile(r'^battle/([a-z]+)\.bscr$')
MAPS_ASSET = re.compile(r'^maps/([A-Za-z_][A-Za-z0-9_]*)\.([a-z0-9]+)$')
SCENE_ASSET = re.compile(r'^scene/([A-Za-z_][A-Za-z0-9_]*)\.scn$')
SCENE_PACK = re.compile(r'\bvia C2SceneRom_ScriptPacks\[')
GFX_ASSET = re.compile(r'^gfx/([A-Za-z_][A-Za-z0-9_]*)\.png$')
SPRITES_ASSET = re.compile(r'^sprites/([A-Za-z_][A-Za-z0-9_]*)\.spr$')
FX_ASSET = re.compile(r'^fx/([A-Za-z_][A-Za-z0-9_]*)\.bfx$')
BATTLE_PARAM = re.compile(r'^([a-z]+)/([a-z]+)$')
RECORDS_ASSET = re.compile(r'^records/([A-Za-z_][A-Za-z0-9_]*)\.tsv$')
RECORDS_PARAM = re.compile(r'^(table|palette|map) (\d+) x (\d+) B$')
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
    '$E4:2300': 3,      # BattleRom_SprFramesPtr (into the sprite frame pieces, tools/sprites.py)
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


# The text tools: modules that turn pieces of their own kinds into
# readable text and back. Each has KINDS (its piece kinds), ASSET_DIR and
# ASSET_EXT ({kind: extension}: build/assets/<dir>/<label>.<ext>), OUT
# (build/<OUT>/<label>.bin, what is incbin'd), INCBIN_NOTE, ERROR,
# is_piece_row(survey row) -> kind or None (no ROM), extract_texts(rom,
# pieces) -> ({label: text}, problems) and assemble_piece(piece, text).
TEXT_TOOLS = (anims, drawlists)


def text_tool(piece: str):
    """The text tool of a piece kind, or None."""
    return next((t for t in TEXT_TOOLS if piece in t.KINDS), None)


def text_out(p: dict) -> Path:
    """The assembled file of a text tool's piece, relative to the root."""
    return Path('build') / text_tool(p['piece']).OUT / f'{p["label"]}.bin'


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
        elif piece == 'scene':
            asset = f'scene/{label}.scn'
        elif piece in maps.PIECES:
            asset = f'maps/{label}.{maps.ASSET_EXT[piece]}'
        elif piece == 'fx':
            asset = f'fx/{label}.bfx'
        elif piece == 'graphics':
            asset = f'gfx/{label}.png'
        elif piece == 'sprframes':
            asset = f'sprites/{label}.spr'
        elif text_tool(piece):
            asset = f'{text_tool(piece).ASSET_DIR}/{label}.{text_tool(piece).ASSET_EXT[piece]}'
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
            mk = maps.kind_of(row['notes'])
            if mk and (mk[0] == 'mapprops' or mk[0] == 'metatiles' and int(m.group(2)) == 8 * mk[1]
                       or mk[0] not in ('mapprops', 'metatiles') and int(m.group(2)) == mk[1]):
                add(label, s, e, mk[0], param=f'lz{m.group(1)} -> {m.group(2)} B', row=row)
                continue
            add(label, s, e, 'events' if EVENT_PACK.search(row['notes'])
                else 'scene' if SCENE_PACK.search(row['notes']) else 'packed',
                param=f'lz{m.group(1)} -> {m.group(2)} B', row=row)
        elif kind == 'graphics' and graphics.layout_for(row['start'], e - s) is not None:
            add(label, s, e, 'graphics', param=graphics.param_of(*graphics.layout_for(row['start'], e - s)),
                row=row)
        elif sprites.is_piece_row(row):
            add(label, s, e, 'sprframes', row=row)
        elif any(t.is_piece_row(row) for t in TEXT_TOOLS):
            add(label, s, e, next(t.is_piece_row(row) for t in TEXT_TOOLS if t.is_piece_row(row)), row=row)
        elif row['start'] in scripts.FX_ROWS:
            if kind != 'battle_script':
                raise DataError(f'{row["start"]}: a {kind} row cannot be the layer-effect scripts')
            add(label, s, e, 'fx', row=row)
        elif row['start'] in battle.ROWS:
            unit, role = battle.ROWS[row['start']]
            if kind not in ('battle_script', 'table'):
                raise DataError(f'{row["start"]}: a {kind} row cannot be a battle script unit\'s')
            add(label, s, e, 'battle', asset=f'battle/{unit}.bscr', param=f'{unit}/{role}', row=row)
        elif row['start'] in text.ROWS:
            unit, fmt = text.ROWS[row['start']]
            if kind not in ('text', 'table'):
                raise DataError(f'{row["start"]}: a {kind} row cannot be a text unit\'s')
            add(label, s, e, 'text', asset=f'text/{unit}.txt', param=fmt, row=row)
        elif row['start'] not in TABLES and kind in ('table', 'palette', 'map') \
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
        elif p['piece'] in maps.PIECES:
            m = MAPS_ASSET.match(p['asset'])
            if not m or m.group(1) != p['label'] or m.group(2) != maps.ASSET_EXT[p['piece']] \
                    or not PACK_PARAM.match(p['param']):
                problems.append(f'{where}: a {p["piece"]} piece\'s asset is maps/<label>.'
                                f'{maps.ASSET_EXT[p["piece"]]} and its param "lzNN -> N B": {p["asset"]!r}, '
                                f'{p["param"]!r}')
        elif p['piece'] == 'scene':
            m = SCENE_ASSET.match(p['asset'])
            if not m or m.group(1) != p['label'] or not PACK_PARAM.match(p['param']):
                problems.append(f'{where}: a scene piece\'s asset is scene/<label>.scn and its param '
                                f'"lzNN -> N B": {p["asset"]!r}, {p["param"]!r}')
        elif p['piece'] == 'graphics':
            m = GFX_ASSET.match(p['asset'])
            if not m or m.group(1) != p['label'] or not graphics.PARAM.match(p['param']):
                problems.append(f'{where}: a graphics piece\'s asset is gfx/<label>.png and its param '
                                f'"<format> N tiles [+ T B]": {p["asset"]!r}, {p["param"]!r}')
        elif p['piece'] == 'sprframes':
            m = SPRITES_ASSET.match(p['asset'])
            if not m or m.group(1) != p['label'] or p['param']:
                problems.append(f'{where}: a sprframes piece\'s asset is sprites/<label>.spr and it has no '
                                f'param: {p["asset"]!r}, {p["param"]!r}')
        elif text_tool(p['piece']):
            t = text_tool(p['piece'])
            if p['asset'] != f'{t.ASSET_DIR}/{p["label"]}.{t.ASSET_EXT[p["piece"]]}' or p['param']:
                problems.append(f'{where}: a {p["piece"]} piece\'s asset is {t.ASSET_DIR}/<label>.'
                                f'{t.ASSET_EXT[p["piece"]]} and it has no param: {p["asset"]!r}, {p["param"]!r}')
        elif p['piece'] == 'fx':
            m = FX_ASSET.match(p['asset'])
            if not m or m.group(1) != p['label'] or p['param']:
                problems.append(f'{where}: an fx piece\'s asset is fx/<label>.bfx and it has no param: '
                                f'{p["asset"]!r}, {p["param"]!r}')
        elif p['piece'] == 'battle':
            m, mp = BATTLE_ASSET.match(p['asset']), BATTLE_PARAM.match(p['param'])
            if not m or not mp or m.group(1) != mp.group(1) or m.group(1) not in battle.UNITS \
                    or mp.group(2) not in battle.ROLES:
                problems.append(f'{where}: a battle piece\'s asset is battle/<unit>.bscr of a unit of '
                                f'tools/battle.py and its param "<unit>/<role>": {p["asset"]!r}, {p["param"]!r}')
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
        elif p['piece'] in ('packed', 'events', 'scene') + maps.PIECES:
            out[f'{PACK_PREFIX}{p["label"]}.lz'] = p
        elif p['piece'] == 'fx':
            out[f'{FX_PREFIX}{p["label"]}.bin'] = p
        elif p['piece'] == 'graphics':
            out[f'{GFX_PREFIX}{p["label"]}.bin'] = p
        elif p['piece'] == 'sprframes':
            out[f'{SPRITES_PREFIX}{p["label"]}.bin'] = p
        elif text_tool(p['piece']):
            out[f'../../{text_out(p)}'] = p
        elif p['piece'] == 'text':
            out[f'{TEXT_PREFIX}{p["label"]}.bin'] = p
        elif p['piece'] == 'records':
            out[f'{RECORDS_PREFIX}{p["label"]}.bin'] = p
        elif p['piece'] == 'battle':
            out[f'{BATTLE_PREFIX}{p["label"]}.bin'] = p
    return out


def placeholder_files(pieces: list[dict]) -> dict[Path, int]:
    """{path relative to the root: size} of every file the data layer
    incbins: what the isolated assemblies (tools/verify.py) replace with
    fill bytes."""
    out = {}
    for p in pieces:
        if p['piece'] == 'extracted':
            out[ASSETS / p['asset']] = int(p['size'])
        elif p['piece'] in ('packed', 'events', 'scene') + maps.PIECES:
            out[PACKS / f'{p["label"]}.lz'] = int(p['size'])
        elif p['piece'] == 'fx':
            out[FX_OUT / f'{p["label"]}.bin'] = int(p['size'])
        elif p['piece'] == 'graphics':
            out[GFX_OUT / f'{p["label"]}.bin'] = int(p['size'])
        elif p['piece'] == 'sprframes':
            out[SPRITES_OUT / f'{p["label"]}.bin'] = int(p['size'])
        elif text_tool(p['piece']):
            out[text_out(p)] = int(p['size'])
        elif p['piece'] == 'text':
            out[TEXT_OUT / f'{p["label"]}.bin'] = int(p['size'])
        elif p['piece'] == 'records':
            out[RECORDS_OUT / f'{p["label"]}.bin'] = int(p['size'])
        elif p['piece'] == 'battle':
            out[BATTLE_OUT / f'{p["label"]}.bin'] = int(p['size'])
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
                why = ('a sprite set\'s first frame record' if target['piece'] == 'sprframes'
                       else 'inside the piece: not a stream start')
                out.append((f'{target["label"]}+${t - target["offset"]:X}', why))
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
        '; their disassembly first), text or records it encodes into',
        '; build/text/ and build/records/, battle and layer-effect',
        '; scripts it assembles into build/battle/ and build/fx/, or',
        '; graphics it encodes from images into build/gfx/',
        '; (symbols/data_assets.csv lists them; nothing here is ROM data).',
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
        elif p['piece'] == 'scene':
            out.append(f'    incbin "{PACK_PREFIX}{p["label"]}.lz"          ; {p["param"]}, scene script')
        elif p['piece'] == 'mapprops':
            out.append(f'    incbin "{PACK_PREFIX}{p["label"]}.lz"          ; {p["param"]}, location map')
        elif p['piece'] in ('scenemaps', 'scenemeta', 'scenebg3'):
            out.append(f'    incbin "{PACK_PREFIX}{p["label"]}.lz"          ; {p["param"]}, scene layer data')
        elif p['piece'] == 'metatiles':
            out.append(f'    incbin "{PACK_PREFIX}{p["label"]}.lz"          ; {p["param"]}, metatiles')
        elif p['piece'] == 'fx':
            out.append(f'    incbin "{FX_PREFIX}{p["label"]}.bin"          ; layer-effect scripts')
        elif p['piece'] == 'graphics':
            out.append(f'    incbin "{GFX_PREFIX}{p["label"]}.bin"          ; graphics: {p["param"]}')
        elif p['piece'] == 'sprframes':
            out.append(f'    incbin "{SPRITES_PREFIX}{p["label"]}.bin"          ; sprite frame records')
        elif text_tool(p['piece']):
            out.append(f'    incbin "../../{text_out(p)}"          ; {text_tool(p["piece"]).INCBIN_NOTE[p["piece"]]}')
        elif p['piece'] == 'records':
            out.append(f'    incbin "{RECORDS_PREFIX}{p["label"]}.bin"          ; records: {p["param"]}')
        elif p['piece'] == 'battle':
            out.append(f'    incbin "{BATTLE_PREFIX}{p["label"]}.bin"          ; battle scripts: {p["param"]}')
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
    for tool in ('events.py', 'battle.py', 'scripts.py', 'graphics.py', 'maps.py', 'sprites.py', 'anims.py',
                 'drawlists.py', 'absint.py', 'disasm.py'):
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
            for a in [p['asset']] + ([graphics.sidecar_path(p['asset'])] if p['piece'] == 'graphics' else []):
                f = out_dir / a
                lines.append(f'{hashlib.sha256(f.read_bytes()).hexdigest() if f.exists() else "-"} {a}')
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
    problems += extract_battle(rom, out_dir, pieces, root)
    problems += extract_scripts(rom, out_dir, pieces, root)
    problems += extract_sprites(rom, out_dir, pieces)
    problems += extract_text_tools(rom, out_dir, pieces)
    for p in pieces:
        s, e = p['offset'], p['stop']
        if p['piece'] == 'fill':
            value = int(p['param'][1:], 16)
            if rom[s:e] != bytes([value]) * (e - s):
                problems.append(f'{p["label"]}: not uniform {p["param"]} fill in this ROM')
            continue
        if p['piece'] in ('table', 'text', 'records'):
            continue
        if p['piece'] in ('events', 'battle', 'scene', 'fx', 'sprframes') or text_tool(p['piece']):
            continue
        if p['piece'] in maps.PIECES:
            data, why = unpack_piece(rom, p)
            if data is None:
                problems.append(why)
                continue
            try:
                text_ = maps.render_piece(p, data)
                if maps.assemble_piece(p, text_) != data:
                    problems.append(f'{p["label"]}: does not assemble back to its bytes')
                    continue
            except maps.MapsError as err:
                problems.append(str(err))
                continue
            dest = out_dir / p['asset']
            dest.parent.mkdir(parents=True, exist_ok=True)
            c3pack._write(dest, text_.encode())
            continue
        if p['piece'] == 'graphics':
            fmt, tiles, tail = graphics.parse_param(p['param'])
            png, t = graphics.to_image(fmt, rom[s:e], tail)
            dest = out_dir / p['asset']
            dest.parent.mkdir(parents=True, exist_ok=True)
            c3pack._write(dest, png)
            c3pack._write(out_dir / graphics.sidecar_path(p['asset']),
                          graphics.sidecar(p['label'], p['start'], p['end'], fmt, tiles, t).encode())
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
    checked to assemble back to the unpacked bytes, every opcode line
    against its handler; the problems. A non-empty pack the disassembler
    cannot follow is a problem, never kept as bytes. Each pack is
    disassembled afresh; what the handlers do with given bytes is kept
    between runs (build/events/traces.*, refused when changed by hand),
    since tracing them all takes minutes."""
    import c3pack
    import events
    evp = [p for p in pieces if p['piece'] == 'events']
    if not evp:
        return []
    texts_pieces = [(p['label'], 0xC00000 + p['offset'], 0xC00000 + p['stop'])
                    for p in pieces if p['piece'] == 'text']
    addrs = {n: a for n, a, _ in texts_pieces}
    names = events.opcode_names()
    try:
        interp = events.Interpreter(Path(root))
        interp.load(Path(root))
    except events.EventsError as e:
        return [f'events: {e}']
    problems = []
    for k, p in enumerate(evp, 1):
        data, why = unpack_piece(rom, p)
        if data is None:
            problems.append(why)
            continue
        text = events.extract_pack(interp, names, data, p['label'], texts_pieces)
        if data and events.is_raw(text):
            problems.append(f'{p["label"]}: the event script cannot be disassembled: '
                            f'{text.splitlines()[1][2:]}')
            continue
        try:
            if events.assemble(text, names, addrs, p['label'], interp) != data:
                problems.append(f'{p["label"]}: the event script does not assemble back')
                continue
        except events.EventsError as e:
            problems.append(str(e))
            continue
        dest = out_dir / p['asset']
        dest.parent.mkdir(parents=True, exist_ok=True)
        c3pack._write(dest, text.encode())
        if not quiet and k % 100 == 0:
            print(f'extract_data: {k} event scripts disassembled')
    interp.save(Path(root))
    return problems


def extract_battle(rom: bytes, out_dir: Path, pieces: list[dict], root: Path = ROOT) -> list[str]:
    """Write the readable file of every battle script unit (tools/battle.py),
    each disassembled afresh and checked to assemble back to the ROM's
    bytes, every line against the readers; the problems. A unit the tool
    cannot follow is a problem, never kept as bytes. What the action
    handlers do with given bytes is kept between runs (build/battle/
    traces.*, refused when changed by hand)."""
    import c3pack
    units = sorted({p['param'].split('/')[0] for p in pieces if p['piece'] == 'battle'})
    if not units:
        return []
    try:
        interp = battle.ActInterp(Path(root))
        interp.load(Path(root))
        fmt = battle.AiFormat(Path(root), interp.image, interp.labels)
    except battle.BattleError as e:
        return [f'battle: {e}']
    problems = []
    try:
        for unit in units:
            try:
                text_ = battle.extract_unit(unit, rom, pieces, interp, fmt, Path(root))
            except battle.BattleError as e:
                problems.append(f'battle: {unit}: {e}')
                continue
            dest = out_dir / f'battle/{unit}.bscr'
            dest.parent.mkdir(parents=True, exist_ok=True)
            c3pack._write(dest, text_.encode())
    finally:
        interp.save(Path(root))
    return problems


def extract_scripts(rom: bytes, out_dir: Path, pieces: list[dict], root: Path = ROOT) -> list[str]:
    """Write the readable file of every scene and fx piece
    (tools/scripts.py), each disassembled afresh and checked to assemble
    back to its bytes, every line against the handlers; the problems. A
    piece the tool cannot follow is a problem, never kept as bytes."""
    import c3pack
    problems = []
    for p, text_ in scripts.extract_all(rom, pieces, Path(root), problems):
        dest = out_dir / p['asset']
        dest.parent.mkdir(parents=True, exist_ok=True)
        c3pack._write(dest, text_.encode())
    return problems


def extract_sprites(rom: bytes, out_dir: Path, pieces: list[dict]) -> list[str]:
    """Write the readable file of every sprframes piece (tools/sprites.py),
    each checked to assemble back to the ROM's bytes, after the readers'
    record sizes and the pieces are checked against the runs the set
    pointers make; the problems."""
    import c3pack
    if not any(p['piece'] == 'sprframes' for p in pieces):
        return []
    d = battle.defines(ROOT)
    problems = sprites.size_problems(rom, d)
    try:
        runs = sprites.derive(rom, d)
    except sprites.SpritesError as err:
        return problems + [f'sprites: {err}']
    problems += sprites.layout_problems(runs, pieces)
    if problems:
        return problems
    for p in pieces:
        if p['piece'] != 'sprframes':
            continue
        try:
            text_ = sprites.piece_text(p, rom, runs)
        except sprites.SpritesError as err:
            problems.append(str(err))
            continue
        dest = out_dir / p['asset']
        dest.parent.mkdir(parents=True, exist_ok=True)
        c3pack._write(dest, text_.encode())
    return problems


def extract_text_tools(rom: bytes, out_dir: Path, pieces: list[dict]) -> list[str]:
    """Write the readable file of every piece of the TEXT_TOOLS (each
    tool's extract_texts checks its pieces against what the readers make
    of the ROM and that every text assembles back to the ROM's bytes);
    the problems. A tool with a problem writes nothing."""
    import c3pack
    problems = []
    for t in TEXT_TOOLS:
        texts, found = t.extract_texts(rom, pieces)
        if found:
            problems += found
            continue
        for p in pieces:
            if p['piece'] in t.KINDS:
                dest = out_dir / p['asset']
                dest.parent.mkdir(parents=True, exist_ok=True)
                c3pack._write(dest, texts[p['label']].encode())
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
