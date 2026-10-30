#!/usr/bin/env python3
"""
graphics.py — The raw tile graphics as editable images, extracted from your
own ROM into the ignored build/assets/gfx/, and the encoder that rebuilds
their exact bytes (DATA_PLAN.md, step 8).

No image is ever committed (README, "Legal"): extraction writes them, the
build encodes them back. What this tool holds is only how the code reads
each region, and the proof of it (FORMATS below):

  * A region's format (bits per pixel, the tile layout) is the one the
    code that reads it gives it: where its DMA or VRAM upload sends it and
    what the PPU makes of that VRAM at that point (the BG mode and the
    layer's character base, or the sprite tiles), or how the code itself
    rebuilds the tiles (copying 2bpp tiles as planes 0-1 of 4bpp ones,
    expanding 3bpp tiles). The tile layouts are the SNES's:
      2bpp  16 B per 8x8 tile: per row r, byte 2r plane 0, 2r+1 plane 1;
      4bpp  32 B: planes 0-1 as 2bpp, then planes 2-3 the same way;
      3bpp  24 B (Menu_Expand3bppTiles): planes 0-1 as 2bpp, then 8 bytes
            of plane 2, one per row.
    A pixel's value is its bits, bit 7 of each plane byte the leftmost.
  * A region whose format no reader proves stays extracted, and the
    figures list it (DATA_PLAN.md).

The readable form, per region (build/assets/gfx/):

  <label>.png   an indexed PNG, 16 tiles (128 pixels) wide, the tiles in
                order left to right, top to bottom; a pixel's palette
                index is its value. The palette is a grey ramp (the
                region's own palette is not proven here): change the
                pixels, not the palette. Cells past the last tile must
                stay 0.
  <label>.gfx   the sidecar: format, tile count, the region, and the bytes
                after the last whole tile that the format does not cover
                (kept as they are).

Editing the PNG and building encodes it back; a PNG that is not 8-bit or
lower indexed, the wrong size, uses an index the format cannot hold, or
draws past the last tile fails the build with the reason.

    python3 tools/graphics.py check     extract every graphics region from
                                        the ROM to images and encode them
                                        back: byte-exact?
"""

import argparse
import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TILE_BYTES = {'2bpp': 16, '3bpp': 24, '4bpp': 32}
BPP = {'2bpp': 2, '3bpp': 3, '4bpp': 4}
WIDTH_TILES = 16

# Survey row start -> (format, proof). The proof names the code that reads
# the region and what makes its format; the tile count is the row's size
# over the tile size, and the bytes past the last whole tile stay as they
# are (the sidecar's tail).
_SPR = ('copied 32 B per tile number by the sprite tile builders (Spr_CopyTile and its bank copiers '
        'GfxRom_D2-D5, Spr_LoadLargeObj) into the sprite tile buffer, which is DMAed to VRAM where the '
        'OAM records name its tiles: sprite (OBJ) tiles, 4bpp on the SNES; Battle_InitScene reads them '
        'the same way through Battler_TileGfxPtr')
_MENU = ('Menu_InitPpuAndRam: mode 1, BG1/BG2 tiles at VRAM word $0000, BG3 tiles at $7000, sprite '
         'tiles at $4000 (OBSEL); Menu_LoadGraphics runs after it')
FORMATS = {
    '$D2:0000': ('4bpp', 'character 6 sprite tiles: ' + _SPR),
    '$D2:72C0': ('4bpp', 'character 0 sprite tiles: ' + _SPR),
    '$D3:0000': ('4bpp', 'character 4 sprite tiles: ' + _SPR),
    '$D3:6B40': ('4bpp', 'character 2 sprite tiles: ' + _SPR),
    '$D4:0000': ('4bpp', 'character 1 sprite tiles: ' + _SPR),
    '$D4:7C40': ('4bpp', 'character 3 sprite tiles: ' + _SPR),
    '$D5:0000': ('4bpp', 'character 5 sprite tiles: ' + _SPR),
    '$C6:F500': ('4bpp', 'C2SceneRom_MapMarkerTiles: C2Scene_MapView sets OBSEL to sprite tiles at VRAM $6000 '
                         '(!OBSEL_Size16And32_Base6000) and DMAs the two 32-B tiles to sprite tiles 0 and 2 '
                         '(C2Scene_MapObjVram): sprite tiles, 4bpp'),
    '$D1:3900': ('4bpp', 'BattleRom_InitTiles4bpp: Battle_InitSceneGfx copies its 64 tiles, 32 B each, into '
                         '!Battle_InitTileBuf after the 16 tiles it widens from $D1:4C80 to 32 B (16 B, then 16 zero '
                         'bytes as planes 2-3): the buffer is the code\'s own 32-B 4bpp tiles. The VRAM layer it '
                         'goes to ($1800, Battle_InitUploadStep) is not traced, so the depth rests on that layout, '
                         'not on a BG mode'),
    '$D1:4C80': ('2bpp', 'BattleRom_InitTiles2bpp: Battle_InitSceneGfx widens its 16 tiles into !Battle_InitTileBuf: '
                         '16 B and 16 zero bytes per tile. The 16 B are planes 0-1, rows interleaved, which is the '
                         'same layout at every depth, so this does not depend on the depth of the buffer or of the '
                         'layer'),
    '$FF:0000': ('4bpp', 'Menu_VramRecsWin sends $FF:0000, $1F80 B, to VRAM $2010: BG1/BG2 tiles ($2010 = tile '
                         '$201 of the character base $0000), 4bpp in mode 1. ' + _MENU),
    '$FF:8E60': ('2bpp', 'MenuRom_Font2bpp: Menu_LoadGraphics copies $E00 B from it to Menu_Bg3TileBuf, which '
                         'Menu_VramRecsFont sends to VRAM $7000, the BG3 tiles: 2bpp in mode 1; it also copies '
                         'each 16-B tile as planes 0-1 of a 32-B 4bpp tile of Menu_TileBuf (VRAM $0000). '
                         + _MENU),
    '$FF:9260': ('2bpp', 'inside the $E00 B of MenuRom_Font2bpp that Menu_LoadGraphics sends to the BG3 tiles '
                         '(see $FF:8E60)'),
    '$FF:9390': ('2bpp', 'inside the $E00 B of MenuRom_Font2bpp that Menu_LoadGraphics sends to the BG3 tiles '
                         '(see $FF:8E60), to $FF:9C5F; BankFF_WidenTiles also copies its first ten tiles as '
                         'planes 0-1 of 4bpp tiles'),
    '$FF:9CF0': ('4bpp', 'MenuRom_ObjTiles: Menu_LoadGraphics copies four 64-B pieces (two 32-B tiles each) '
                         'over 4bpp tiles of Menu_TileBuf, which Menu_VramRecObj sends to VRAM $4000, the '
                         'sprite tiles (OBSEL): 4bpp. Before the upload Menu_TilesOrPlanes23 sets planes 2-3 of '
                         'all eight to planes 0 OR 1, so the stored planes 2-3 are not what the menu shows '
                         '(this is the only reader). ' + _MENU),
    '$FF:9E10': ('4bpp', 'MenuRom_WindowGfx: Menu_LoadGraphics copies its $1400 B to Menu_TileBuf, which '
                         'Menu_VramRecsWin sends to VRAM $3000: BG1/BG2 tiles, 4bpp in mode 1. Before the upload '
                         'Menu_TilesOrPlane3 (also in Menu_LoadWindowGfx) sets plane 3 to planes 0 OR 1 OR 2, so '
                         'the stored plane 3 is not what the menu shows. ' + _MENU),
    '$FF:C9FC': ('2bpp', 'MenuRom_Font2bppB: Menu_LoadGraphics copies its $100 B over tile $10 of the 2bpp '
                         'font buffer (Menu_Font2bppBTile), sent with it to the BG3 tiles (see $FF:8E60)'),
    '$FF:CAFC': ('2bpp', 'MenuRom_GlyphRows: BankFF_BuildTileSets copies its ten 16-B tiles 32 B apart as '
                         'planes 0-1 of 4bpp tiles'),
    '$FF:D5E4': ('4bpp', 'MenuRom_Tiles4bpp: Menu_LoadGraphics copies its $600 B to the start of the $12A0 B '
                         'it moves to Menu_TileBuf, which Menu_VramRecFontB sends to VRAM $1000: BG1/BG2 tiles, '
                         '4bpp in mode 1. ' + _MENU),
    '$FF:DBE4': ('3bpp', 'MenuRom_Tiles3bpp: Menu_Expand3bppTiles reads 24 B per tile (planes 0-1, then plane '
                         '2) and writes 4bpp tiles; the first $65 of them go to VRAM $1000 with the 4bpp tiles '
                         '(Menu_TilesBBytes). ' + _MENU),
    '$FF:E55C': ('4bpp', 'Menu_VramRecsWin sends $FF:E55C, $380 B, to VRAM $1E00: BG1/BG2 tiles, 4bpp in '
                         'mode 1 (Menu_Expand3bppTiles also reads these bytes as its 3bpp tiles $65 on, which '
                         'nothing uses). ' + _MENU),
    '$FF:EB88': ('4bpp', 'MenuRom_VramTiles: Menu_VramRecRomTiles sends its $480 B to VRAM $2010: BG1/BG2 '
                         'tiles, 4bpp in mode 1. ' + _MENU),
}


class GraphicsError(Exception):
    pass


# ── Tiles ─────────────────────────────────────────────────────────────────

def decode_tiles(fmt: str, data: bytes) -> list[list[int]]:
    """The tiles of `data` (a whole number of them), each 64 pixel values
    row by row."""
    n = TILE_BYTES[fmt]
    if len(data) % n:
        raise GraphicsError(f'{len(data)} B is no whole number of {fmt} tiles')
    out = []
    for t in range(len(data) // n):
        b = data[t * n:(t + 1) * n]
        px = []
        for r in range(8):
            planes = [b[2 * r], b[2 * r + 1]]
            if fmt == '4bpp':
                planes += [b[16 + 2 * r], b[17 + 2 * r]]
            elif fmt == '3bpp':
                planes.append(b[16 + r])
            for x in range(8):
                bit = 7 - x
                px.append(sum(((p >> bit) & 1) << k for k, p in enumerate(planes)))
        out.append(px)
    return out


def encode_tiles(fmt: str, tiles: list[list[int]]) -> bytes:
    n, bpp = TILE_BYTES[fmt], BPP[fmt]
    out = bytearray()
    for px in tiles:
        b = bytearray(n)
        for r in range(8):
            for x in range(8):
                v = px[r * 8 + x]
                if not 0 <= v < 1 << bpp:
                    raise GraphicsError(f'pixel value {v} does not fit {fmt}')
                bit = 1 << (7 - x)
                for k in range(bpp):
                    if v >> k & 1:
                        if k < 2:
                            b[2 * r + k] |= bit
                        elif fmt == '4bpp':
                            b[16 + 2 * r + k - 2] |= bit
                        else:
                            b[16 + r] |= bit
        out += b
    return bytes(out)


# ── PNG (indexed; written and read here, no library) ──────────────────────

def _chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)


def grey_ramp(colours: int) -> bytes:
    """The palette write_png writes: `colours` greys, black to white."""
    return b''.join(bytes([v, v, v]) for v in (i * 255 // max(colours - 1, 1) for i in range(colours)))


def write_png(width: int, height: int, pixels: list[int], colours: int) -> bytes:
    """An 8-bit indexed PNG with a grey ramp of `colours` entries."""
    pal = grey_ramp(colours)
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += bytes(pixels[y * width:(y + 1) * width])
    return (b'\x89PNG\r\n\x1a\n' + _chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 3, 0, 0, 0))
            + _chunk(b'PLTE', pal) + _chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + _chunk(b'IEND', b''))


def read_png(data: bytes) -> tuple[int, int, list[int]]:
    """(width, height, the palette index of every pixel) of an indexed PNG
    (bit depth 1, 2, 4 or 8, not interlaced, any row filters, a PLTE
    chunk); anything else is refused."""
    return read_png_palette(data)[:3]


def read_png_palette(data: bytes) -> tuple[int, int, list[int], bytes]:
    """read_png, and the PLTE chunk's bytes."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise GraphicsError('not a PNG file')
    pos, ihdr, idat, end, plte = 8, None, bytearray(), False, None
    while pos < len(data):
        if pos + 8 > len(data):
            raise GraphicsError('the PNG ends inside a chunk header')
        n, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        crc = data[pos + 8 + n:pos + 12 + n]
        if len(body) != n or len(crc) != 4:
            raise GraphicsError(f'the PNG ends inside its {kind!r} chunk')
        if struct.unpack('>I', crc)[0] != zlib.crc32(kind + body) & 0xFFFFFFFF:
            raise GraphicsError(f'the PNG\'s {kind!r} chunk fails its CRC')
        if kind == b'IHDR':
            if ihdr is not None or len(body) != 13:
                raise GraphicsError('the PNG has a second or malformed IHDR chunk')
            ihdr = struct.unpack('>IIBBBBB', body)
        elif kind == b'PLTE':
            plte = bytes(body)
        elif kind == b'IDAT':
            idat += body
        elif kind == b'IEND':
            end = True
            if pos + 12 + n != len(data):
                raise GraphicsError(f'the PNG has {len(data) - pos - 12 - n} B after its IEND chunk')
            break
        pos += 12 + n
    if ihdr is None or not end:
        raise GraphicsError('the PNG has no IHDR or no IEND')
    width, height, depth, ctype, comp, filt, interlace = ihdr
    if ctype != 3:
        raise GraphicsError(f'the PNG is colour type {ctype}, not indexed (3): keep it indexed, the palette '
                            f'index is the pixel value')
    if plte is None:
        raise GraphicsError('the PNG has no PLTE chunk (an indexed PNG must have its palette)')
    if depth not in (1, 2, 4, 8) or comp or filt or interlace:
        raise GraphicsError(f'the PNG is bit depth {depth}, compression {comp}, filter {filt}, interlace '
                            f'{interlace}: only 1/2/4/8-bit, standard, not interlaced')
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as e:
        raise GraphicsError(f'the PNG\'s image data does not inflate: {e}') from None
    stride = (width * depth + 7) // 8
    if len(raw) != height * (stride + 1):
        raise GraphicsError(f'the PNG\'s image data is {len(raw)} B, not {height * (stride + 1)}')
    bpp = max(1, depth // 8)
    prev = bytearray(stride)
    pixels = []
    for y in range(height):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 0:
                pass
            elif f == 1:
                line[i] = (line[i] + a) & 0xFF
            elif f == 2:
                line[i] = (line[i] + b) & 0xFF
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
            else:
                raise GraphicsError(f'the PNG uses row filter {f}')
        prev = line
        for x in range(width):
            bit = x * depth
            v = line[bit // 8] >> (8 - depth - bit % 8) & ((1 << depth) - 1)
            pixels.append(v)
    return width, height, pixels, plte


# ── Regions ───────────────────────────────────────────────────────────────

def layout_for(start: str, size: int) -> tuple[str, int, int] | None:
    """(format, whole tiles, tail bytes) of a survey row, or None."""
    if start not in FORMATS:
        return None
    fmt = FORMATS[start][0]
    n = TILE_BYTES[fmt]
    return fmt, size // n, size % n


PARAM = re.compile(r'^(2bpp|3bpp|4bpp) (\d+) tiles(?: \+ (\d+) B)?$')


def param_of(fmt: str, tiles: int, tail: int) -> str:
    return f'{fmt} {tiles} tiles' + (f' + {tail} B' if tail else '')


def parse_param(param: str) -> tuple[str, int, int]:
    m = PARAM.match(param)
    if not m:
        raise GraphicsError(f'not a graphics param: {param!r}')
    return m.group(1), int(m.group(2)), int(m.group(3) or 0)


def to_image(fmt: str, data: bytes, tail: int) -> tuple[bytes, bytes]:
    """(the PNG, the tail bytes) of a region."""
    body = data[:len(data) - tail] if tail else data
    tiles = decode_tiles(fmt, body)
    rows = (len(tiles) + WIDTH_TILES - 1) // WIDTH_TILES
    w, h = WIDTH_TILES * 8, rows * 8
    px = [0] * (w * h)
    for t, tile in enumerate(tiles):
        tx, ty = t % WIDTH_TILES, t // WIDTH_TILES
        for r in range(8):
            px[(ty * 8 + r) * w + tx * 8:(ty * 8 + r) * w + tx * 8 + 8] = tile[r * 8:r * 8 + 8]
    return write_png(w, h, px, 1 << BPP[fmt]), data[len(data) - tail:] if tail else b''


def from_image(fmt: str, tiles: int, png: bytes, tail: bytes, name: str = '<png>') -> bytes:
    """The region's bytes from its PNG and tail; refuses a PNG of another
    size, a value the format cannot hold, or pixels past the last tile."""
    try:
        w, h, px, plte = read_png_palette(png)
    except GraphicsError as e:
        raise GraphicsError(f'{name}: {e}') from None
    ramp = grey_ramp(1 << BPP[fmt])
    if plte[:len(ramp)] != ramp:
        k = next((i for i in range(len(ramp) // 3) if plte[3 * i:3 * i + 3] != ramp[3 * i:3 * i + 3]),
                 len(plte) // 3)
        raise GraphicsError(f'{name}: the palette is not the grey ramp tools/graphics.py wrote (entry {k} is '
                            f'{tuple(plte[3 * k:3 * k + 3])}, not {tuple(ramp[3 * k:3 * k + 3])}): an editor that '
                            f'sorted or changed it has renumbered the pixels, which would change the bytes. Keep '
                            f'the palette as written and change only the pixels')
    rows = (tiles + WIDTH_TILES - 1) // WIDTH_TILES
    if (w, h) != (WIDTH_TILES * 8, rows * 8):
        raise GraphicsError(f'{name}: the image is {w}x{h}; {tiles} {fmt} tiles are {WIDTH_TILES * 8}x{rows * 8}')
    limit = 1 << BPP[fmt]
    bad = next((i for i, v in enumerate(px) if v >= limit), None)
    if bad is not None:
        raise GraphicsError(f'{name}: pixel ({bad % w}, {bad // w}) is index {px[bad]}; {fmt} holds 0-{limit - 1}')
    out = []
    for t in range(rows * WIDTH_TILES):
        tx, ty = t % WIDTH_TILES, t // WIDTH_TILES
        tile = []
        for r in range(8):
            tile += px[(ty * 8 + r) * w + tx * 8:(ty * 8 + r) * w + tx * 8 + 8]
        if t >= tiles:
            if any(tile):
                raise GraphicsError(f'{name}: cell {t} is past the last tile ({tiles - 1}) and is not empty')
            continue
        out.append(tile)
    return encode_tiles(fmt, out) + tail


def sidecar(label: str, start: str, end: str, fmt: str, tiles: int, tail: bytes) -> str:
    return '\n'.join([
        f'; {label}: graphics extracted from your own ROM by tools/graphics.py (never commit it, nor the PNG).',
        '; Edit the PNG\'s pixels (palette index = pixel value; the grey palette is not the game\'s). The',
        '; build encodes them back; this file is regenerated by extraction.',
        f'region {label} {start} {end}',
        f'format {fmt}',
        f'tiles {tiles}',
        f'width {WIDTH_TILES}',
        'palette grey (not proven)',
        'tail ' + (' '.join(f'{b:02X}' for b in tail) if tail else '-'),
    ]) + '\n'


def read_sidecar(text: str, name: str = '<gfx>') -> dict:
    out = {}
    for line in text.split('\n'):
        line = line.split(';', 1)[0].strip()
        if not line:
            continue
        key, _, rest = line.partition(' ')
        if key in out:
            raise GraphicsError(f'{name}: a second {key} line')
        out[key] = rest
    for k in ('region', 'format', 'tiles', 'width', 'tail'):
        if k not in out:
            raise GraphicsError(f'{name}: no {k} line')
    if out['format'] not in TILE_BYTES or not out['tiles'].isdigit() or out['width'] != str(WIDTH_TILES):
        raise GraphicsError(f'{name}: format, tiles or width is not what tools/graphics.py writes')
    tail = out['tail']
    if tail == '-':
        out['tail'] = b''
    elif re.fullmatch(r'[0-9A-Fa-f]{2}( [0-9A-Fa-f]{2})*', tail):
        out['tail'] = bytes(int(t, 16) for t in tail.split())
    else:
        raise GraphicsError(f'{name}: the tail is XX bytes or -')
    out['tiles'] = int(out['tiles'])
    return out


def sidecar_path(asset: str) -> str:
    return asset[:-len('.png')] + '.gfx'


def encode_piece(p: dict, png: bytes, side: str) -> bytes:
    """The bytes of a graphics piece from its PNG and sidecar, checked
    against the manifest's param."""
    fmt, tiles, tail = parse_param(p['param'])
    s = read_sidecar(side, p['label'])
    if (s['format'], s['tiles'], len(s['tail'])) != (fmt, tiles, tail):
        raise GraphicsError(f'{p["label"]}: the sidecar says {s["format"]} {s["tiles"]} tiles + '
                            f'{len(s["tail"])} B; the manifest {p["param"]}')
    if s['region'].split() != [p['label'], p['start'], p['end']]:
        raise GraphicsError(f'{p["label"]}: the sidecar is for {s["region"]}, not {p["label"]} {p["start"]} '
                            f'{p["end"]}')
    data = from_image(fmt, tiles, png, s['tail'], p['label'] + '.png')
    if len(data) != int(p['size']):
        raise GraphicsError(f'{p["label"]}: {len(data)} B; the piece is {p["size"]}')
    return data


def check(rom: bytes, quiet: bool = True) -> list[str]:
    import extract_data
    problems = []
    for p in extract_data.read_manifest():
        if p['piece'] != 'graphics':
            continue
        fmt, tiles, tail = parse_param(p['param'])
        data = rom[p['offset']:p['stop']]
        png, t = to_image(fmt, data, tail)
        side = sidecar(p['label'], p['start'], p['end'], fmt, tiles, t)
        try:
            if encode_piece(p, png, side) != data:
                problems.append(f'{p["label"]}: does not encode back')
        except GraphicsError as e:
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
    except (GraphicsError, extract_data.DataError) as e:
        print(f'graphics: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'graphics: {p}', file=sys.stderr)
    if problems:
        return 1
    n = sum(1 for p in extract_data.read_manifest() if p['piece'] == 'graphics')
    print(f'OK: all {n} graphics regions convert to images and encode back byte-exact')
    return 0


if __name__ == '__main__':
    sys.exit(main())
