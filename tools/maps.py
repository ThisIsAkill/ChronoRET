#!/usr/bin/env python3
"""
maps.py — The location maps and their metatiles as readable text,
extracted from your own ROM into the ignored build/assets/maps/, and the
assembler that rebuilds their exact (unpacked) bytes (DATA_PLAN.md, the
location maps).

No map is ever committed (README, "Legal"): extraction writes them, the
build assembles them back and packs them (tools/c3pack.py). What this tool
holds is how the code reads them:

  mapprops   a Map_PropsPtrs pack a location record names (LocRom.MapProps;
             one no record names stays packed, UNNAMED): LocLoad_UnkA33B
             unpacks it to MapProps ($7E:B500) and takes the six header
             bytes (struct MapProps), then Map_UnpackTilePlanes reads the
             rest through the WRAM port:
               - layer 1's metatile numbers (Map_TileProps): H1 rows of W1
                 bytes, W/H = (two bits of MapProps.Size1 + 1) x 16;
               - layer 2's (Map_Layer2Tiles), sized by Size1 bits 4-7;
               - layer 3's (Map_Layer3Tiles), sized by Size3 bits 0-3, only
                 when Size3 bit 7 is set;
               - three bytes per layer-1 tile (Map_TileHiBits, Map_TileAttrA,
                 Map_TileAttrB): an entry of the three, or, when the first
                 byte has bit 7 set, a run: the first byte AND $7F, the
                 other two, then a count (0 = 256) of tiles that get them,
                 carried across row ends.
             It stops when the last plane is full. Five maps' streams end
             before that: the game then reads what follows in WRAM, which
             the readable form marks (--------). HiBits bit 0 / 1 is bit 8
             of the layer-1 / layer-2 metatile number (Map_WriteRow1/2).
  metatiles  a LocGfx_Meta12Ptrs pack (LocRom.Tileset12; 512 metatiles at
             Map_Meta12TL, $7E:B000) or LocGfx_Meta3Ptrs pack (.Tileset3;
             256 at Map_Meta3TL, $7E:C000) a location record names (as
             for the maps): 8 bytes per metatile, four words
             top-left, top-right, bottom-left, bottom-right, which the
             row and column writers (Map_WriteRow1 ...) send unchanged to
             Map_BufC800 and the edge buffers, uploaded to the layers' BG
             tilemaps in VRAM: SNES tilemap words (vhopppcc cccccccc).

The readable forms (build/assets/maps/):

  <label>.map   @map LABEL, the header (size1 size3 move2 move3 screens
                colormath, hex), then @layer1 WxH, @layer2 WxH [@layer3
                WxH] grids of hex metatile numbers, then @attrs WxH: one
                cell per layer-1 tile, HHAABB (HiBits, AttrA, AttrB) or
                -------- where the stream ends. The runs are re-made from
                the grid (every repeat of two or more is a run of up to 256,
                as all 197 maps are written): change cells, not runs.
  <label>.meta  @metatiles LABEL N, then N lines: the metatile number and
                its four words, each TTT/P[p][h][v]: tile number (hex),
                palette, then priority, horizontal and vertical flip.

    python3 tools/maps.py check     extract every map and metatile pack
                                    from the ROM to text and assemble them
                                    back: byte-exact? and are they the
                                    packs the location records name?
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PROPS_TABLE = 'Map_PropsPtrs'
# The scene layer packs: {table: (piece kind, unpacked size)}. Their indexes
# are the ones the eight scene headers name (SCENE_NAMED; check() derives
# it from the headers): C2Scene_LoadMetatiles (C2Scene_HdrMetatiles),
# C2Scene_LoadBgMaps (C2Scene_HdrMaps), C2Scene_LoadBg3Map
# (C2Scene_HdrBg3Map).
SCENE_TABLES = {'C2SceneRom_MetatilePacks': ('scenemeta', 0x1000), 'C2SceneRom_MapPacks': ('scenemaps', 0x3000),
                'C2SceneRom_Bg3MapPacks': ('scenebg3', 0x1000)}
SCENE_NAMED = {'C2SceneRom_MetatilePacks': {0, 1, 2, 3, 4, 5}, 'C2SceneRom_MapPacks': {0, 1, 2, 3, 4, 5, 6, 7},
               'C2SceneRom_Bg3MapPacks': {0, 1, 2, 3, 4}}
SCENE_HDR = {'C2SceneRom_MetatilePacks': 'C2Scene_HdrMetatiles', 'C2SceneRom_MapPacks': 'C2Scene_HdrMaps',
             'C2SceneRom_Bg3MapPacks': 'C2Scene_HdrBg3Map'}
SCENE_MAP_W, SCENE_MAP_H = 96, 64      # C2Scene_MapCols x C2Scene_MapRows, per layer (C2Scene_LayerMaps)
SCENE_METATILES = 256                  # per layer: C2Scene_LayerMetatiles $3000 and $3800, 8 B each
META_TABLES = {'LocGfx_Meta12Ptrs': 512, 'LocGfx_Meta3Ptrs': 256}    # metatiles per pack (the RAM tables)
# A pack is a map or metatiles only when a location record names it (its
# LocRom.MapProps, .Tileset12 or .Tileset3; derive_named, which check()
# compares with the manifest): these entries no record names stay plain
# `packed` pieces. (The 1-B Meta12 packs, 16 and 55-63, are not whole
# tables and stay packed by their size.)
UNNAMED = {'Map_PropsPtrs': {10, 30, 141, 172}, 'LocGfx_Meta12Ptrs': {54}, 'LocGfx_Meta3Ptrs': {3}}
# The LocRom field that names each table's entries, and the value that
# names none (LocLoad_UnkA33B, LocLoad_Unk09DD, LocLoad_Unk0A14).
NAMED_BY = {'Map_PropsPtrs': ('MapProps', None), 'LocGfx_Meta12Ptrs': ('Tileset12', 'LocRom_SetNone'),
            'LocGfx_Meta3Ptrs': ('Tileset3', 'LocRom_SetNone')}
LOCROM_ROW = '$F6:0000'
HEADER = ('size1', 'size3', 'move2', 'move3', 'screens', 'colormath')   # struct MapProps, in order
LAYER3_ON = 0x80                      # MapProps.Size3 bit 7: layer 3's plane is in the stream (Map_Unk0BCA)
RUN = 0x80                            # an attribute entry's first byte with bit 7: a run (Map_RunFlagMask = $7F)
MISSING = '--------'
HEAD = ('; {label}: {what}, extracted from your own ROM by tools/maps.py (never commit it).',
        '; The build assembles it back; the format is in tools/maps.py. This file is',
        '; regenerated by extraction: an edit is lost when it runs again.')


class MapsError(Exception):
    pass


# ── Maps (MapProps) ──────────────────────────────────────────────────────

def sizes(size1: int, size3: int) -> list[tuple[int, int]]:
    """[(width, height)] of layers 1-3, as LocLoad_UnkA33B makes them."""
    def wh(b):
        return ((b & 3) + 1) * 16, ((b >> 2 & 3) + 1) * 16
    return [wh(size1), wh(size1 >> 4), wh(size3)]


def split_map(data: bytes, where: str = '<map>') -> dict:
    """The parts of an unpacked map, as Map_UnpackTilePlanes reads them:
    {'header', 'layers' [(w, h, bytes)], 'attrs' [(hi, a, b)] (as far as
    the stream goes), 'cells', 'end'}; refuses a stream it does not read
    whole."""
    if len(data) < 6:
        raise MapsError(f'{where}: {len(data)} B, no MapProps header')
    header = data[:6]
    dims = sizes(header[0], header[1])
    count = 3 if header[1] & LAYER3_ON else 2
    pos, layers = 6, []
    for w, h in dims[:count]:
        if pos + w * h > len(data):
            raise MapsError(f'{where}: the stream ends inside a layer plane')
        layers.append((w, h, data[pos:pos + w * h]))
        pos += w * h
    cells = dims[0][0] * dims[0][1]
    attrs = []
    while len(attrs) < cells and pos < len(data):
        b = data[pos]
        if b & RUN:
            if pos + 4 > len(data):
                raise MapsError(f'{where}: the stream ends inside a run')
            n = data[pos + 3] or 256
            if len(attrs) + n > cells:
                raise MapsError(f'{where}: a run goes {len(attrs) + n - cells} tile(s) past the plane')
            attrs += [(b & ~RUN & 0xFF, data[pos + 1], data[pos + 2])] * n
            pos += 4
        else:
            if pos + 3 > len(data):
                raise MapsError(f'{where}: the stream ends inside an entry')
            attrs.append((b, data[pos + 1], data[pos + 2]))
            pos += 3
    if pos != len(data):
        raise MapsError(f'{where}: {len(data) - pos} B after the planes, which nothing reads')
    return {'header': header, 'layers': layers, 'attrs': attrs, 'cells': cells, 'end': pos}


def encode_attrs(attrs: list[tuple[int, int, int]]) -> bytes:
    """The attribute stream: a run for every repeat of two or more (up to
    256 a run), an entry otherwise."""
    out, i = bytearray(), 0
    while i < len(attrs):
        t = attrs[i]
        if not 0 <= t[0] < RUN:
            raise MapsError(f'tile {i}: HiBits ${t[0]:02X} has bit 7 set, which marks a run')
        n = 1
        while i + n < len(attrs) and attrs[i + n] == t and n < 256:
            n += 1
        if n >= 2:
            out += bytes([t[0] | RUN, t[1], t[2], n & 0xFF])
        else:
            out += bytes(t)
        i += n
    return bytes(out)


def render_map(label: str, data: bytes) -> str:
    m = split_map(data, label)
    rebuilt = m['header'] + b''.join(p for _, _, p in m['layers']) + encode_attrs(m['attrs'])
    if rebuilt != data:
        raise MapsError(f'{label}: its runs are not the ones the readable form re-makes')
    h = m['header']
    dims = sizes(h[0], h[1])
    out = [line.format(label=label, what='a location map (MapProps)') for line in HEAD]
    out.append(f'@map {label}')
    notes = {'size1': f'layer 1 {dims[0][0]}x{dims[0][1]}, layer 2 {dims[1][0]}x{dims[1][1]}',
             'size3': (f'layer 3 {dims[2][0]}x{dims[2][1]} ({"in" if h[1] & LAYER3_ON else "not in"} the '
                       f'stream); bits 4-6: own step 2, own step 3, Map_Unk0BC9'),
             'move2': 'layer set 2 own step', 'move3': 'layer set 3 own step',
             'screens': 'main screen bits 0-3, sub screen 4-7', 'colormath': 'CGADSUB'}
    for name, v in zip(HEADER, h):
        out.append(f'{name} ${v:02X}    ; {notes[name]}')
    for k, (w, hh, plane) in enumerate(m['layers']):
        out.append(f'@layer{k + 1} {w}x{hh}')
        for r in range(hh):
            out.append(' '.join(f'{b:02X}' for b in plane[r * w:(r + 1) * w]))
    w, hh = dims[0]
    out.append(f'@attrs {w}x{hh}    ; HiBits AttrA AttrB per layer-1 tile; {MISSING}: past the stream')
    cells = [f'{a:02X}{b:02X}{c:02X}' for a, b, c in m['attrs']] + [MISSING] * (m['cells'] - len(m['attrs']))
    for r in range(hh):
        out.append(' '.join(cells[r * w:(r + 1) * w]))
    return '\n'.join(out) + '\n'


def _lines(text: str) -> list[tuple[int, list[str]]]:
    out = []
    for no, line in enumerate(text.split('\n'), 1):
        code = line.split(';', 1)[0].strip()
        if code:
            out.append((no, code.split()))
    return out


def _hex(t: str, where: str, digits: int) -> int:
    if not re.fullmatch(rf'[0-9A-Fa-f]{{{digits}}}', t):
        raise MapsError(f'{where}: {t!r} is not {digits} hex digits')
    return int(t, 16)


def assemble_map(text: str, label: str, name: str = '<map>') -> bytes:
    lines = [(f'{name}:{no}', w) for no, w in _lines(text)]
    if not lines or lines[0][1] != ['@map', label]:
        raise MapsError(f'{name}: the first line is @map {label}')
    i, header = 1, []
    for field in HEADER:
        where, w = lines[i] if i < len(lines) else (name, ['(end)'])
        if len(w) != 2 or w[0] != field or not re.fullmatch(r'\$[0-9A-Fa-f]{2}', w[1]):
            raise MapsError(f'{where}: expected {field} $XX')
        header.append(int(w[1][1:], 16))
        i += 1
    dims = sizes(header[0], header[1])
    want = [f'@layer{k + 1}' for k in range(3 if header[1] & LAYER3_ON else 2)] + ['@attrs']
    planes, attrs = [], []
    for k, tag in enumerate(want):
        w_, h_ = dims[0] if tag == '@attrs' else dims[k]
        where, w = lines[i] if i < len(lines) else (name, ['(end)'])
        if w != [tag, f'{w_}x{h_}']:
            raise MapsError(f'{where}: expected {tag} {w_}x{h_} (from size1/size3)')
        i += 1
        rows = lines[i:i + h_]
        if len(rows) != h_:
            raise MapsError(f'{where}: {tag} needs {h_} rows')
        for rw, cells in rows:
            if len(cells) != w_:
                raise MapsError(f'{rw}: {len(cells)} cells; the row is {w_}')
        i += h_
        if tag != '@attrs':
            planes.append(bytes(_hex(c, rw, 2) for rw, cells in rows for c in cells))
            continue
        flat = [(rw, c) for rw, cells in rows for c in cells]
        ended = False
        for rw, c in flat:
            if c == MISSING:
                ended = True
                continue
            if ended:
                raise MapsError(f'{rw}: a cell after {MISSING}: the stream ends only once')
            v = _hex(c, rw, 6)
            attrs.append((v >> 16, v >> 8 & 0xFF, v & 0xFF))
    if i != len(lines):
        raise MapsError(f'{lines[i][0]}: a line after the attribute grid')
    try:
        tail = encode_attrs(attrs)
    except MapsError as e:
        raise MapsError(f'{name}: {e}') from None
    return bytes(header) + b''.join(planes) + tail


# ── Metatiles ────────────────────────────────────────────────────────────

def word_text(v: int) -> str:
    return (f'{v & 0x3FF:03X}/{v >> 10 & 7}' + ('p' if v & 0x2000 else '') + ('h' if v & 0x4000 else '')
            + ('v' if v & 0x8000 else ''))


WORD = re.compile(r'^([0-9A-Fa-f]{3})/([0-7])(p?)(h?)(v?)$')


def word_value(t: str, where: str) -> int:
    m = WORD.match(t)
    if not m or int(m.group(1), 16) > 0x3FF:
        raise MapsError(f'{where}: {t!r} is not a tilemap word TTT/P[p][h][v]')
    return (int(m.group(1), 16) | int(m.group(2)) << 10 | bool(m.group(3)) << 13 | bool(m.group(4)) << 14
            | bool(m.group(5)) << 15)


def render_meta(label: str, data: bytes, count: int) -> str:
    if len(data) != 8 * count:
        raise MapsError(f'{label}: {len(data)} B; {count} metatiles are {8 * count}')
    out = [line.format(label=label, what='metatiles (four tilemap words each)') for line in HEAD]
    out.append(f'@metatiles {label} {count}    ; N: top-left top-right bottom-left bottom-right')
    for n in range(count):
        words = [data[8 * n + 2 * k] | data[8 * n + 2 * k + 1] << 8 for k in range(4)]
        out.append(f'{n:03X}: ' + ' '.join(word_text(v) for v in words))
    return '\n'.join(out) + '\n'


def assemble_meta(text: str, label: str, count: int, name: str = '<meta>') -> bytes:
    lines = [(f'{name}:{no}', w) for no, w in _lines(text)]
    if not lines or lines[0][1] != ['@metatiles', label, str(count)]:
        raise MapsError(f'{name}: the first line is @metatiles {label} {count}')
    if len(lines) != count + 1:
        raise MapsError(f'{name}: {len(lines) - 1} metatile lines; the table holds {count}')
    out = bytearray()
    for n, (where, w) in enumerate(lines[1:]):
        if len(w) != 5 or w[0] != f'{n:03X}:':
            raise MapsError(f'{where}: expected {n:03X}: and four words')
        for t in w[1:]:
            out += word_value(t, where).to_bytes(2, 'little')
    return bytes(out)


# ── Scene layers ─────────────────────────────────────────────────────────

def render_scene_maps(label: str, data: bytes) -> str:
    size = 2 * SCENE_MAP_W * SCENE_MAP_H
    if len(data) != size:
        raise MapsError(f'{label}: {len(data)} B; the two layer maps are {size}')
    out = [line.format(label=label, what='a scene\'s BG1 and BG2 metatile maps') for line in HEAD]
    out.append(f'@scenemaps {label}')
    for k in range(2):
        out.append(f'@layer{k + 1} {SCENE_MAP_W}x{SCENE_MAP_H}')
        base = k * SCENE_MAP_W * SCENE_MAP_H
        for r in range(SCENE_MAP_H):
            out.append(' '.join(f'{b:02X}' for b in data[base + r * SCENE_MAP_W:base + (r + 1) * SCENE_MAP_W]))
    return '\n'.join(out) + '\n'


def assemble_scene_maps(text: str, label: str, name: str = '<smap>') -> bytes:
    lines = [(f'{name}:{no}', w) for no, w in _lines(text)]
    if not lines or lines[0][1] != ['@scenemaps', label]:
        raise MapsError(f'{name}: the first line is @scenemaps {label}')
    out, i = bytearray(), 1
    for k in range(2):
        tag = [f'@layer{k + 1}', f'{SCENE_MAP_W}x{SCENE_MAP_H}']
        where, w = lines[i] if i < len(lines) else (name, ['(end)'])
        if w != tag:
            raise MapsError(f'{where}: expected {" ".join(tag)}')
        rows = lines[i + 1:i + 1 + SCENE_MAP_H]
        if len(rows) != SCENE_MAP_H or any(r[1][0].startswith('@') for r in rows):
            raise MapsError(f'{where}: {tag[0]} needs {SCENE_MAP_H} rows')
        for rw, cells in rows:
            if len(cells) != SCENE_MAP_W:
                raise MapsError(f'{rw}: {len(cells)} cells; the row is {SCENE_MAP_W}')
            out += bytes(_hex(c, rw, 2) for c in cells)
        i += 1 + SCENE_MAP_H
    if i != len(lines):
        raise MapsError(f'{lines[i][0]}: a line after layer 2')
    return bytes(out)


def render_scene_meta(label: str, data: bytes) -> str:
    size = 2 * 8 * SCENE_METATILES
    if len(data) != size:
        raise MapsError(f'{label}: {len(data)} B; the two metatile sets are {size}')
    out = [line.format(label=label, what='a scene\'s BG1 and BG2 metatiles (four tilemap words each)')
           for line in HEAD]
    out.append(f'@scenemeta {label}    ; N: top-left top-right bottom-left bottom-right')
    for k in range(2):
        out.append(f'@layer{k + 1} {SCENE_METATILES}')
        base = k * 8 * SCENE_METATILES
        for n in range(SCENE_METATILES):
            words = [data[base + 8 * n + 2 * j] | data[base + 8 * n + 2 * j + 1] << 8 for j in range(4)]
            out.append(f'{n:02X}: ' + ' '.join(word_text(v) for v in words))
    return '\n'.join(out) + '\n'


def assemble_scene_meta(text: str, label: str, name: str = '<smeta>') -> bytes:
    lines = [(f'{name}:{no}', w) for no, w in _lines(text)]
    if not lines or lines[0][1] != ['@scenemeta', label]:
        raise MapsError(f'{name}: the first line is @scenemeta {label}')
    out, i = bytearray(), 1
    for k in range(2):
        where, w = lines[i] if i < len(lines) else (name, ['(end)'])
        if w != [f'@layer{k + 1}', str(SCENE_METATILES)]:
            raise MapsError(f'{where}: expected @layer{k + 1} {SCENE_METATILES}')
        rows = lines[i + 1:i + 1 + SCENE_METATILES]
        if len(rows) != SCENE_METATILES:
            raise MapsError(f'{where}: @layer{k + 1} needs {SCENE_METATILES} metatile lines')
        for n, (rw, cells) in enumerate(rows):
            if len(cells) != 5 or cells[0] != f'{n:02X}:':
                raise MapsError(f'{rw}: expected {n:02X}: and four words')
            for t in cells[1:]:
                out += word_value(t, rw).to_bytes(2, 'little')
        i += 1 + SCENE_METATILES
    if i != len(lines):
        raise MapsError(f'{lines[i][0]}: a line after layer 2')
    return bytes(out)


BG3_SCREEN = 32 * 32                   # words per 32x32 screen (BG3SC $7800, 64x32: two screens)


def render_bg3(label: str, data: bytes) -> str:
    if not data or len(data) % (2 * BG3_SCREEN):
        raise MapsError(f'{label}: {len(data)} B is no whole number of 32x32-word screens')
    out = [line.format(label=label, what='a scene\'s BG3 tilemap (tilemap words)') for line in HEAD]
    n = len(data) // (2 * BG3_SCREEN)
    out.append(f'@bg3map {label} {n}    ; screens of 32 rows of 32 words, TTT/P[p][h][v]')
    for s in range(n):
        out.append(f'@screen {s}')
        for r in range(32):
            base = 2 * (s * BG3_SCREEN + 32 * r)
            out.append(' '.join(word_text(data[base + 2 * c] | data[base + 2 * c + 1] << 8) for c in range(32)))
    return '\n'.join(out) + '\n'


def assemble_bg3(text: str, label: str, name: str = '<bg3>') -> bytes:
    lines = [(f'{name}:{no}', w) for no, w in _lines(text)]
    if not lines or len(lines[0][1]) != 3 or lines[0][1][:2] != ['@bg3map', label] \
            or lines[0][1][2] not in ('1', '2'):
        raise MapsError(f'{name}: the first line is @bg3map {label} 1|2')
    n = int(lines[0][1][2])
    if len(lines) != 1 + n * 33:
        raise MapsError(f'{name}: {n} screens are {n * 33} lines after the first; there are {len(lines) - 1}')
    out = bytearray()
    for s in range(n):
        where, w = lines[1 + 33 * s]
        if w != ['@screen', str(s)]:
            raise MapsError(f'{where}: expected @screen {s}')
        for rw, cells in lines[2 + 33 * s:34 + 33 * s]:
            if len(cells) != 32:
                raise MapsError(f'{rw}: {len(cells)} words; a row is 32')
            for t in cells:
                out += word_value(t, rw).to_bytes(2, 'little')
    return bytes(out)


def scene_named(rom: bytes, root: Path = ROOT) -> dict[str, set[int]]:
    """{table: the indexes the eight scene headers name} (SCENE_HDR),
    from the header table's words up to its first header."""
    sys.path.insert(0, str(ROOT / 'tools'))
    import battle
    d = battle.defines(root)
    F = lambda a: a - 0xC00000      # noqa: E731
    tab = d['C2SceneRom_HeaderTable']
    words, first = [], None
    while first is None or tab + 2 * len(words) < first:
        w = (tab & 0xFF0000) | rom[F(tab) + 2 * len(words)] | rom[F(tab) + 2 * len(words) + 1] << 8
        words.append(w)
        first = min(first or w, w)
    out = {t: set() for t in SCENE_HDR}
    for h in words:
        for t, field in SCENE_HDR.items():
            v = rom[F(h) + d[field]]
            if not v & 0x80:                 # bit 7: nothing loaded
                out[t].add(v)
    return out


# ── Pieces ───────────────────────────────────────────────────────────────

def kind_of(notes: str) -> tuple[str, int] | None:
    """('mapprops', 0), ('metatiles', count) or (scene kind, unpacked size)
    for a pack row's notes."""
    m = re.search(r'\bvia ([A-Za-z0-9_]+)\[(\d+)\]', notes)
    if not m or int(m.group(2)) in UNNAMED.get(m.group(1), ()):
        return None
    if m.group(1) in SCENE_TABLES:
        return SCENE_TABLES[m.group(1)] if int(m.group(2)) in SCENE_NAMED[m.group(1)] else None
    if m.group(1) == PROPS_TABLE:
        return 'mapprops', 0
    if m.group(1) in META_TABLES:
        return 'metatiles', META_TABLES[m.group(1)]
    return None


def render_piece(p: dict, data: bytes) -> str:
    if p['piece'] == 'mapprops':
        return render_map(p['label'], data)
    if p['piece'] == 'scenemaps':
        return render_scene_maps(p['label'], data)
    if p['piece'] == 'scenemeta':
        return render_scene_meta(p['label'], data)
    if p['piece'] == 'scenebg3':
        return render_bg3(p['label'], data)
    return render_meta(p['label'], data, meta_count(p))


def assemble_piece(p: dict, text: str) -> bytes:
    if p['piece'] == 'mapprops':
        return assemble_map(text, p['label'], p['label'])
    if p['piece'] == 'scenemaps':
        return assemble_scene_maps(text, p['label'], p['label'])
    if p['piece'] == 'scenemeta':
        return assemble_scene_meta(text, p['label'], p['label'])
    if p['piece'] == 'scenebg3':
        return assemble_bg3(text, p['label'], p['label'])
    return assemble_meta(text, p['label'], meta_count(p), p['label'])


PIECES = ('mapprops', 'metatiles', 'scenemaps', 'scenemeta', 'scenebg3')
ASSET_EXT = {'mapprops': 'map', 'metatiles': 'meta', 'scenemaps': 'smap', 'scenemeta': 'smeta', 'scenebg3': 'bg3'}


def meta_count(p: dict) -> int:
    m = re.match(r'^lz(11|12) -> (\d+) B', p['param'])
    return int(m.group(2)) // 8


def derive_named(rom: bytes, rows: list[dict], root: Path = ROOT) -> tuple[set[str], list[str]]:
    """({survey row start of every map and metatile pack a location record
    names}, problems): from the LocRom records' MapProps, Tileset12 and
    Tileset3 fields, as the location load reads them."""
    sys.path.insert(0, str(ROOT / 'tools'))
    import battle
    import data_survey
    import records
    d = battle.defines(root)
    by_table: dict[tuple[str, int], str] = {}
    for r in rows:
        m = re.search(r'\bvia ([A-Za-z0-9_]+)\[(\d+)\]', r['notes'])
        if r['kind'] == 'packed_lz' and m and m.group(1) in NAMED_BY:
            by_table[(m.group(1), int(m.group(2)))] = r['start']
    fields, off = {}, 0
    for name, t in records._struct_fields('LocRom'):
        fields[name] = (off, records.width(t))
        off += records.width(t)
    recs = next((r for r in rows if r['start'] == LOCROM_ROW), None)
    if recs is None:
        return set(), [f'no survey row at {LOCROM_ROW} (the LocRom records)']
    size = d['LocRom_RecSize']
    base = data_survey.parse_addr(LOCROM_ROW)
    named, problems = set(), []
    for k in range(int(recs['size']) // size):
        for table, (field, none) in NAMED_BY.items():
            at, w = fields[field]
            v = int.from_bytes(rom[base + k * size + at:base + k * size + at + w], 'little')
            if none is not None and v == d[none]:
                continue
            start = by_table.get((table, v))
            if start is None:
                problems.append(f'location record {k} names {table}[{v}], which no survey pack row is')
            else:
                named.add(start)
    return named, problems


def named_problems(rom: bytes, rows: list[dict], pieces: list[dict], root: Path = ROOT) -> list[str]:
    """What differs between the packs the location records name
    (derive_named) and the manifest's mapprops and metatiles pieces."""
    named, problems = derive_named(rom, rows, root)
    converted = {p['start'] for p in pieces if p['piece'] in ('mapprops', 'metatiles')}
    for start in sorted(named - converted):
        problems.append(f'{start}: a location record names it, and the manifest keeps it packed')
    for start in sorted(converted - named):
        problems.append(f'{start}: converted in the manifest, and no location record names it')
    return problems


def check(rom: bytes, quiet: bool = True) -> list[str]:
    sys.path.insert(0, str(ROOT / 'tools'))
    import data_survey
    import extract_data
    problems = named_problems(rom, data_survey.read_rows(), extract_data.read_manifest())
    named = scene_named(rom)
    if named != SCENE_NAMED:
        problems.append(f'the scene headers name {named}, not SCENE_NAMED {SCENE_NAMED}')
    for p in extract_data.read_manifest():
        if p['piece'] not in PIECES:
            continue
        data, why = extract_data.unpack_piece(rom, p)
        if data is None:
            problems.append(why)
            continue
        try:
            if assemble_piece(p, render_piece(p, data)) != data:
                problems.append(f'{p["label"]}: does not assemble back')
        except MapsError as e:
            problems.append(str(e))
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    try:
        problems = check(extract_data.read_rom(), quiet=False)
    except (MapsError, extract_data.DataError) as e:
        print(f'maps: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'maps: {p}', file=sys.stderr)
    if problems:
        return 1
    ps = extract_data.read_manifest()
    n = {k: sum(1 for p in ps if p['piece'] == k) for k in PIECES}
    print(f'OK: all {n["mapprops"]} location maps, {n["metatiles"]} metatile packs and the scene layer packs '
          f'({n["scenemaps"]} maps, {n["scenemeta"]} metatile sets, {n["scenebg3"]} BG3 tilemaps) convert to '
          f'text and assemble back byte-exact')
    return 0


if __name__ == '__main__':
    sys.exit(main())
