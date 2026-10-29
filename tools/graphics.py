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
  * A pack (a Decomp_ToWram stream) is tiles when the code that reads its
    unpacked bytes makes them so (PACK_PROOFS), for each use the data
    makes of it: the location records and their pack lists, the eight
    scene headers, the sprite graphics table (derive_packed, which
    check() compares with PACKED). Two uses that disagree, or none,
    leave it a plain packed piece. The tiles cover what the readers
    read; the bytes after them are the sidecar's tail. The build encodes
    the image to the unpacked bytes and packs them (tools/c3pack.py)
    back to the ROM's stream.

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

    python3 tools/graphics.py check     extract every graphics region and
                                        graphics pack (unpacked) from the
                                        ROM to images and encode them back:
                                        byte-exact? and does the data give
                                        each pack's PACKED format?
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
    '$D1:4C80': ('2bpp', 'BattleRom_InitTiles2bpp: Battle_InitSceneGfx widens its 16 tiles into the 4bpp tile '
                         'buffer !Battle_InitTileBuf: 16 B (planes 0-1) and 16 zero bytes (planes 2-3) per tile'),
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
                         'sprite tiles (OBSEL): 4bpp. ' + _MENU),
    '$FF:9E10': ('4bpp', 'MenuRom_WindowGfx: Menu_LoadGraphics copies its $1400 B to Menu_TileBuf, which '
                         'Menu_VramRecsWin sends to VRAM $3000: BG1/BG2 tiles, 4bpp in mode 1. ' + _MENU),
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


# ── Packed graphics (Decomp_ToWram streams whose unpacked bytes are tiles) ─

# The proofs, by the code that reads the unpacked bytes. A pack's format is
# given by every use the data makes of it (derive_packed): a pack no proved
# use names stays a plain `packed` piece.
_FIELD = ('the field draws locations in BG mode 1 (NmiHandler writes BGMODE = Nmi_BgMode every frame) with '
          'BG1/BG2 tiles at VRAM $1000 and BG3 tiles at $5000 (Ppu_SetBgLayout, from LocLoad_DrawMap)')
_SCENE = ('BankC2_InitHwRegs: BG mode 1, sprite tiles at VRAM $0000 (OBSEL), BG1/BG2 tiles at $2000, BG3 '
          'tiles at $7000')
PACK_PROOFS = {
    'spr': ('4bpp', 'BattleRom_SprTilesPtr (Field_E4Ptr0, MenuRom_E4GfxPtrs) entries: Evt_Op82_InitWramSprite and '
                    'Evt_Op83_InitEnemySprite unpack them to $7F:ObjQ_Unk71, with Obj_GfxBank = $7F, and Menu_SprLoad '
                    'to Menu_SprUnpackBuf; the sprite tile builders read them 32 B per tile number (Spr_CopyTile, '
                    'Spr_CopyTile7F) into the sprite tiles: 4bpp. ' + _SPR),
    'loc12': ('4bpp', 'LocGfx_PackPtrs entries named by packs 0-5 of a LocGfx_Lists entry (LocRom.Tileset12): '
                      'LocLoad_Unk0960 and LocLoad_UploadPack upload them to VRAM $2000-$4FBF ($1000 B each, '
                      '$0F80 B of pack 5): BG1/BG2 tiles, 4bpp. ' + _FIELD),
    'loc3': ('2bpp', 'LocGfx_PackPtrs entries named by LocRom.Tileset3: LocLoad_Unk6DCF uploads $1000 B of them '
                     'to VRAM $5000: BG3 tiles, 2bpp. ' + _FIELD),
    'scene_bg': ('4bpp', 'C2SceneRom_BgPacks entries named by a scene header\'s bytes C2Scene_HdrBgGfx..+6: '
                         'C2Scene_LoadBgGfx unpacks them $1000 B apart to C2Scene_DecompBuf and C2Scene_LoadVram '
                         'DMAs the $7000 B to VRAM $2000: BG1/BG2 tiles, 4bpp. ' + _SCENE),
    'scene_bg3': ('2bpp', 'C2SceneRom_BgPacks entries named by a scene header\'s byte C2Scene_HdrBg3Gfx: '
                          'C2Scene_LoadBg3Gfx, and C2Scene_LoadVram DMAs $1000 B to VRAM $7000: BG3 tiles, 2bpp. '
                          + _SCENE),
    'scene_obj': ('4bpp', 'C2SceneRom_ObjPacks entries named by a scene header\'s bytes C2Scene_HdrObjGfx..+3: '
                          'C2Scene_LoadObjGfx unpacks them $1000 B apart to C2Scene_DecompBuf and C2Scene_LoadVram '
                          'DMAs the $4000 B to VRAM $0000: sprite tiles, 4bpp. ' + _SCENE),
}


def derive_packed(rom: bytes, rows: list[dict], root: Path = ROOT) -> tuple[dict, list[str]]:
    """({survey row start: (format, bytes the readers read as tiles, proof
    keys)}, conflicts): every pack a proved use names, from the data that
    names it (the location records and lists, the eight scene headers)."""
    sys.path.insert(0, str(ROOT / 'tools'))
    import battle
    import records
    d = battle.defines(root)
    F = lambda a: a - 0xC00000      # noqa: E731
    by_table: dict[tuple[str, int], dict] = {}
    for r in rows:
        m = re.search(r'\bvia ([A-Za-z0-9_/]+)\[(\d+)\]', r['notes'])
        if r['kind'] == 'packed_lz' and m:
            by_table[(m.group(1), int(m.group(2)))] = r
    uses: dict[str, list[tuple[str, int]]] = {}

    def use(table, i, key, nbytes):
        r = by_table.get((table, i))
        if r is not None:
            uses.setdefault(r['start'], []).append((key, nbytes))
    for (table, i) in by_table:
        if table == 'BattleRom_SprTilesPtr':
            use(table, i, 'spr', 1 << 30)
    # the location records: LocRom.Tileset12 -> LocGfx_Lists packs 0-5, .Tileset3 -> a pack
    fields, off = {}, 0
    for name, t in records._struct_fields('LocRom'):
        fields[name] = off
        off += records.width(t)
    recs = next(r for r in rows if r['start'] == '$F6:0000')
    n = int(recs['size']) // d['LocRom_RecSize']
    base, lists, none = 0xF60000, d['LocGfx_Lists'], d['LocRom_SetNone']
    for k in range(n):
        rec = F(base) + k * d['LocRom_RecSize']
        t12, t3 = rom[rec + fields['Tileset12']], rom[rec + fields['Tileset3']]
        if t12 != none:
            for slot in range(6):
                p = rom[F(lists) + t12 * d['LocGfx_ListSize'] + slot]
                if p != none:
                    use('LocGfx_PackPtrs', p, 'loc12', d['LocGfx_Pack5Bytes'] if slot == 5 else d['LocGfx_PackBytes'])
        if t3 != none:
            use('LocGfx_PackPtrs', t3, 'loc3', d['LocGfx_PackBytes'])
    # the scene headers (the table's words up to its first header)
    tab = d['C2SceneRom_HeaderTable']
    words, first = [], None
    while first is None or tab + 2 * len(words) < first:
        w = (tab & 0xFF0000) | rom[F(tab) + 2 * len(words)] | rom[F(tab) + 2 * len(words) + 1] << 8
        words.append(w)
        first = min(first or w, w)
    slot = d['C2Scene_PackSlotSize']
    for h in words:
        hb = rom[F(h):F(h) + 0x20]
        for key, table, at, count, total in (
                ('scene_bg', 'C2SceneRom_BgPacks', d['C2Scene_HdrBgGfx'], d['C2Scene_BgPackCount'],
                 d['C2Scene_BgGfxBytes']),
                ('scene_obj', 'C2SceneRom_ObjPacks', d['C2Scene_HdrObjGfx'], d['C2Scene_ObjPackCount'],
                 d['C2Scene_ObjGfxBytes']),
                ('scene_bg3', 'C2SceneRom_BgPacks', d['C2Scene_HdrBg3Gfx'], 1, d['C2Scene_PackBytes'])):
            packs = hb[at:at + count]
            for k, p in enumerate(packs):
                if p & 0x80:
                    continue                    # bit 7: the slot is left as it was
                run = 1
                while k + run < count and packs[k + run] & 0x80:
                    run += 1                    # what overflows into a slot left alone is DMAed too
                use(table, p, key, min(run * slot, total - k * slot))
    out, conflicts = {}, []
    for start, us in uses.items():
        fmts = {PACK_PROOFS[k][0] for k, _ in us}
        if len(fmts) > 1:
            conflicts.append(f'{start}: read as {" and ".join(sorted(fmts))}')
            continue
        fmt = fmts.pop()
        size = int(re.search(r'-> (\d+) B', next(r for r in rows if r['start'] == start)['format']).group(1))
        read = min(size, max(nb for _, nb in us))
        out[start] = (fmt, read // TILE_BYTES[fmt] * TILE_BYTES[fmt], tuple(sorted({k for k, _ in us})))
    return out, conflicts


# Survey row start -> bytes read as tiles, by proof (PACK_PROOFS; derive_packed
# finds the same from the data, and check() asserts it). The pack's bytes past
# them stay as they are (the sidecar's tail).
PACKED = {
    ('scene_bg',): {
        '$C4:0000': 4096, '$C4:0EB8': 4096, '$C4:1D3A': 4096, '$C4:2C32': 4096, '$C4:3AA0': 4096,
        '$C4:4839': 4096, '$C4:55D7': 4096, '$C4:6423': 4096, '$C4:72C2': 4096, '$C4:804F': 4096,
        '$C4:8C47': 4096, '$C4:8E33': 4096, '$C4:9E45': 4096, '$C4:AD56': 4096, '$C4:BD49': 4096,
        '$C4:C704': 4096, '$C4:D3FF': 4096, '$C4:D945': 4096, '$C4:DB31': 4096, '$C4:E882': 4096,
        '$C5:0000': 4096, '$C5:0EE8': 4096, '$C5:1E26': 4096, '$C5:2E1C': 4096, '$C5:3CC9': 4096,
        '$C5:4A9B': 4096, '$C5:5A48': 4096, '$C5:65A5': 4096, '$C5:7151': 4096, '$C5:8000': 4096,
        '$C5:8B02': 4096, '$C5:8F5A': 4096,
    },
    ('scene_bg3',): {
        '$C4:F7AF': 4096, '$C4:FD72': 1024, '$C5:97F7': 512, '$C5:9848': 256,
    },
    ('scene_obj',): {
        '$C5:B798': 8192, '$C5:CD21': 4096, '$C5:D597': 4096, '$C5:D80B': 4096, '$C5:DA88': 4096,
        '$C5:E0F7': 4096, '$C5:EAAF': 4096, '$C5:ED14': 4096, '$C6:0000': 4096, '$C6:07B6': 4096,
    },
    ('spr',): {
        '$D2:EE80': 2816, '$D2:F85E': 2176, '$D3:E280': 1600, '$D3:E746': 384, '$D3:E8A9': 608,
        '$D3:EA5B': 960, '$D3:EE14': 160, '$D3:EEB0': 448, '$D3:F04A': 192, '$D3:F0AC': 288,
        '$D3:F19D': 320, '$D3:F2A7': 352, '$D3:F3CC': 544, '$D3:F5BD': 160, '$D3:F639': 160,
        '$D3:F671': 288, '$D3:F70B': 160, '$D3:F7A7': 640, '$D3:F996': 608, '$D3:FB9E': 320,
        '$D3:FC56': 416, '$D3:FDBB': 160, '$D3:FE37': 320, '$D3:FEC9': 416, '$D4:FB00': 672,
        '$D4:FCFB': 384, '$D4:FDB0': 480, '$D5:8C00': 8192, '$D5:A040': 6368, '$D5:B299': 15712,
        '$D5:E178': 448, '$D5:E1B5': 8192, '$D5:F8F7': 2368, '$D6:0000': 5824, '$D6:14EF': 7328,
        '$D6:2962': 9312, '$D6:45F3': 3104, '$D6:4CBA': 6144, '$D6:601E': 3488, '$D6:6A12': 6720,
        '$D6:7FB6': 3680, '$D6:8BA3': 4064, '$D6:978A': 3616, '$D6:A28D': 3168, '$D6:A93A': 5504,
        '$D6:B7D9': 5984, '$D6:C77E': 12288, '$D6:EE0A': 1952, '$D6:F3DE': 2176, '$D7:0000': 1760,
        '$D7:0501': 2720, '$D7:0D18': 10112, '$D7:2AD8': 4096, '$D7:34F6': 8672, '$D7:4EEF': 1856,
        '$D7:5411': 1728, '$D7:59BC': 12800, '$D7:7F00': 2432, '$D7:8814': 3648, '$D7:934F': 3744,
        '$D7:9E73': 8928, '$D7:BBB6': 416, '$D7:BD33': 3488, '$D7:C930': 3488, '$D7:D52D': 8192,
        '$D7:E897': 7104, '$D8:0000': 8704, '$D8:1808': 8160, '$D8:3486': 3808, '$D8:4148': 13888,
        '$D8:6E83': 9472, '$D8:8BD3': 9248, '$D8:A952': 8192, '$D8:B80F': 3296, '$D8:C2EA': 960,
        '$D8:C629': 864, '$D8:C896': 864, '$D8:CB1D': 864, '$D8:CDDC': 416, '$D9:0000': 2464,
        '$D9:0727': 2336, '$D9:0DE6': 2336, '$D9:1331': 2336, '$D9:181E': 2336, '$D9:1DE2': 2336,
        '$D9:2392': 2336, '$D9:297A': 2336, '$D9:30E7': 2336, '$D9:36B1': 2336, '$D9:3D14': 2336,
        '$D9:4385': 2336, '$D9:4A58': 2336, '$D9:5200': 2656, '$D9:5A9C': 2336, '$D9:61D3': 2464,
        '$D9:6922': 1312, '$D9:6D63': 1312, '$D9:7162': 1312, '$D9:7513': 1312, '$D9:7947': 2752,
        '$D9:8208': 2560, '$D9:8B63': 768, '$D9:8DE3': 3904, '$D9:99DF': 2592, '$D9:A2A0': 6656,
        '$D9:B008': 3072, '$D9:B88E': 2560, '$D9:C115': 1728, '$D9:C7CA': 3936, '$D9:D2BC': 2848,
        '$D9:DB66': 2400, '$D9:E2CE': 2528, '$D9:EC5D': 5024, '$DA:0000': 3968, '$DA:0BB9': 3232,
        '$DA:158D': 960, '$DA:1838': 288, '$DA:1922': 320, '$DA:1989': 768, '$DA:1C16': 288,
        '$DA:1CA5': 288, '$DA:1D5D': 1344, '$DA:21B4': 704, '$DA:2338': 448, '$DA:23ED': 224,
        '$DA:24A5': 160, '$DA:24E9': 416, '$DA:2604': 128, '$DA:2671': 480, '$DA:27FA': 800,
        '$DA:2AD2': 288, '$DA:2B4B': 480, '$DA:2C92': 352, '$DA:2D64': 992, '$DA:2F73': 896,
        '$DA:3208': 1024, '$DA:350B': 416, '$DA:35D2': 1280, '$DA:39C4': 1376, '$DA:3C82': 416,
        '$DA:3D51': 288, '$DA:3DF8': 224, '$DA:3E2B': 160, '$DA:3EB2': 288, '$DA:3F34': 160,
        '$DA:3F7A': 160, '$DA:3FD3': 160, '$DA:4060': 160, '$DA:40EE': 160, '$DA:4175': 160,
        '$DA:41D9': 288, '$DA:42C2': 160, '$DA:4350': 160, '$DA:43D1': 160, '$DA:4453': 1184,
        '$DA:47FA': 800, '$DA:4AEE': 1600, '$DA:50D0': 2304, '$DA:58A4': 2432, '$DA:6180': 1504,
        '$DA:66C4': 576, '$DA:68A1': 256, '$DA:6933': 1376, '$DA:6DD7': 2496, '$DA:7655': 2016,
        '$DA:7D2F': 1088, '$DA:8064': 1760, '$DA:8456': 1952, '$DA:8AA0': 2336, '$DA:9256': 4480,
        '$DA:A108': 1312, '$DA:A5D3': 928, '$DA:A97F': 4992, '$DA:BA15': 160, '$DA:BAAD': 1152,
        '$DA:BE53': 288, '$DA:BF50': 288, '$DA:BFF1': 512, '$DA:C1BE': 288, '$DA:C267': 608,
        '$DA:C323': 4096, '$DA:CF29': 576, '$DA:D038': 160, '$DA:D0C3': 960, '$DA:D28C': 128,
        '$DA:D2B3': 224, '$DA:D370': 1216, '$DA:D6DE': 448, '$DA:D807': 160, '$DA:D85A': 192,
        '$DA:D8A7': 1312, '$DA:DC28': 1312, '$DA:E04E': 1664, '$DA:E533': 1216, '$DA:E878': 5440,
        '$DA:F75B': 160, '$DA:F7AB': 256, '$DA:F848': 736, '$DA:FA69': 544, '$DF:0000': 11392,
        '$DF:2033': 2944, '$DF:2923': 8512, '$DF:4464': 10528, '$DF:6613': 8832, '$DF:853B': 4768,
        '$DF:9671': 5664, '$DF:A800': 6656, '$DF:BE59': 512, '$DF:BFF6': 1056, '$DF:C2CA': 4096,
        '$DF:CE53': 9280, '$DF:EA2D': 4320, '$DF:F75D': 544, '$DF:F913': 768, '$DF:FB31': 1728,
        '$E0:0000': 5024, '$E0:0EBD': 4384, '$E0:1E2E': 1216, '$E0:2188': 1248, '$E0:2565': 4992,
        '$E0:34E2': 2624, '$E0:3E6F': 10976, '$E0:60ED': 12384, '$E0:847E': 3200, '$E0:8D74': 7296,
        '$E0:A3FD': 11968, '$E0:CECC': 640, '$E0:D085': 12288, '$E0:F35A': 3264, '$E1:0000': 192,
        '$E1:00AA': 11296, '$E1:25D8': 11296, '$E1:4AF7': 23776, '$E1:9319': 2176, '$E1:9995': 10080,
        '$E1:B7AC': 2048, '$E1:BF3E': 608, '$E1:C12F': 1184, '$E1:C4D9': 832, '$E1:C712': 3552,
        '$E1:D321': 3104,
    },
    ('loc12',): {
        '$E2:0000': 4096, '$E2:0C1E': 4096, '$E2:17EA': 4096, '$E2:2582': 4096, '$E2:3404': 4096,
        '$E2:4079': 4096, '$E2:4B99': 4096, '$E2:5845': 4096, '$E2:66E1': 4096, '$E2:74B1': 4096,
        '$E2:84DF': 4096, '$E2:92C7': 3968, '$E2:A1DA': 4096, '$E2:B004': 4096, '$E2:BDD9': 3968,
        '$E2:CB3A': 4096, '$E2:D738': 4096, '$E2:E754': 4096, '$E2:F262': 4096, '$E5:D3A8': 4096,
        '$E5:DE39': 4096, '$E5:EB9C': 4096, '$E5:F9B4': 4096, '$E6:0000': 3968, '$E6:0C86': 4096,
        '$E6:2082': 4096, '$E6:29C9': 4096, '$E6:360F': 4096, '$E6:45A3': 4096, '$E6:553B': 4096,
        '$E6:62CF': 4096, '$E6:6B77': 4096, '$E6:77F2': 4096, '$E6:86D4': 4096, '$E6:9341': 4096,
        '$E6:A258': 4096, '$E6:AF6B': 4096, '$E6:BE36': 4096, '$E6:CBA8': 4096, '$E6:DAFA': 4096,
        '$E6:EA91': 4096, '$E6:F7C6': 4096, '$E7:0000': 4096, '$E7:0C77': 4096, '$E7:1912': 4096,
        '$E7:241E': 4096, '$E7:2F66': 4096, '$E7:3D02': 4096, '$E7:4ACB': 4096, '$E7:5629': 4096,
        '$E7:6185': 4096, '$E7:6E06': 4096, '$E7:7AC9': 4096, '$E7:88B0': 4096, '$E7:96C8': 4096,
        '$E7:A5B1': 4096, '$E7:B4A9': 4096, '$E7:C45E': 4096, '$E7:D32D': 4096, '$E7:E12C': 4096,
        '$E7:F1B1': 4096, '$E8:0000': 4096, '$E8:1017': 3968, '$E8:1B9E': 4096, '$E8:2990': 4096,
        '$E8:3746': 4096, '$E8:41A5': 4096, '$E8:4DDB': 4096, '$E8:5D77': 4096, '$E8:6D29': 4096,
        '$E8:7C55': 4096, '$E8:8B93': 4096, '$E8:9A80': 4096, '$E8:A712': 4096, '$E8:B305': 4096,
        '$E8:BEEC': 4096, '$E8:CB33': 4096, '$E8:D898': 4096, '$E8:E7D8': 4096, '$E8:F6BE': 4096,
        '$E9:0000': 4096, '$E9:0B58': 4096, '$E9:1848': 4096, '$E9:2766': 4096, '$E9:3217': 4096,
        '$E9:4060': 4096, '$E9:4CC8': 4096, '$E9:5A87': 4096, '$E9:68EA': 4096, '$E9:756F': 4096,
        '$E9:814F': 4096, '$E9:8A2B': 4096, '$E9:94CA': 4096, '$E9:9EE2': 3968, '$E9:A9CD': 4096,
        '$E9:B893': 4096, '$E9:C560': 4096, '$E9:CFD4': 4096, '$E9:D9F4': 4096, '$E9:E5AF': 4096,
        '$E9:F1B4': 4096, '$EA:0000': 4096, '$EA:0CD4': 4096, '$EA:1A3F': 4096, '$EA:270C': 4096,
        '$EA:33FA': 4096, '$EA:411E': 4096, '$EA:4D83': 3968, '$EA:5A79': 4096, '$EA:6B8C': 4096,
        '$EA:7885': 3968, '$EA:82C7': 4096, '$EA:911C': 4096, '$EA:9FC2': 4096, '$EA:AD49': 4096,
        '$EA:B67A': 4096, '$EA:C011': 4096, '$EA:CA0D': 3968, '$EA:D93F': 3968, '$EA:E172': 4096,
        '$EA:EDA0': 3968, '$EA:EF8C': 1536, '$EA:F41A': 4096, '$EB:0000': 4096, '$EB:0C55': 4096,
        '$EB:19F5': 4096, '$EB:27C2': 4096, '$EB:34BC': 3968, '$EB:43A7': 4096, '$EB:4FFA': 4096,
        '$EB:5C53': 4096, '$EB:67C7': 4096, '$EB:733E': 3968, '$EB:7F1F': 4096, '$EB:8E6E': 4096,
        '$EB:9D78': 4096, '$EB:ABAF': 4096, '$EB:B8F7': 4096, '$EB:C65D': 4096, '$EB:D3CA': 4096,
        '$EB:E153': 4096, '$EB:ED01': 4096, '$EB:FA12': 4096, '$EC:0000': 4096, '$EC:0E5D': 4096,
        '$EC:1B72': 4096, '$EC:2786': 4096, '$EC:36D6': 4096, '$EC:462E': 4096, '$EC:51AE': 4096,
        '$EC:5F9E': 4096, '$EC:6E57': 4096, '$EC:79C2': 4096, '$EC:85F8': 4096, '$EC:9117': 4096,
        '$EC:9C7F': 4096, '$EC:A8B4': 4096, '$EC:B4F9': 4096, '$EC:C046': 4096, '$EC:CDA8': 4096,
        '$EC:DA50': 4096, '$EC:E3F8': 4096, '$EC:EC67': 4096, '$EC:F61D': 4096, '$EF:C000': 512,
        '$EF:C1D3': 4096, '$EF:C806': 3968, '$EF:CDC3': 3968, '$EF:D02D': 3968, '$EF:D2AD': 4096,
        '$EF:D91D': 4096, '$EF:E5AB': 3968, '$EF:E80C': 4096, '$EF:F2E1': 3968, '$FD:6800': 4096,
        '$FD:7467': 4096, '$FD:7E5C': 3968, '$FD:804F': 4096,
    },
    ('loc3',): {
        '$E5:2000': 3968, '$E5:2362': 3968, '$E5:26B9': 3968, '$E5:2D13': 3072, '$E5:3227': 3968,
        '$E5:36BD': 3072, '$E5:3C21': 3968, '$E5:452F': 3072, '$E5:49DC': 3968, '$E5:4D0E': 3968,
        '$E5:4F46': 3968, '$E5:5273': 3072, '$E5:5A3C': 3968, '$E5:6104': 256, '$E5:6156': 3968,
        '$E5:66EC': 3968, '$E5:69C0': 3968, '$E5:6F49': 3968,
    },
}


def packed_layout(start: str, size: int) -> tuple[str, int, int] | None:
    """(format, whole tiles, tail bytes) of a packed survey row of `size`
    unpacked bytes, or None."""
    for keys, items in PACKED.items():
        if start in items:
            fmt = PACK_PROOFS[keys[0]][0]
            n = items[start] // TILE_BYTES[fmt]
            return fmt, n, size - n * TILE_BYTES[fmt]
    return None


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


def write_png(width: int, height: int, pixels: list[int], colours: int) -> bytes:
    """An 8-bit indexed PNG with a grey ramp of `colours` entries."""
    pal = b''.join(bytes([v, v, v]) for v in (i * 255 // max(colours - 1, 1) for i in range(colours)))
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += bytes(pixels[y * width:(y + 1) * width])
    return (b'\x89PNG\r\n\x1a\n' + _chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 3, 0, 0, 0))
            + _chunk(b'PLTE', pal) + _chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + _chunk(b'IEND', b''))


def read_png(data: bytes) -> tuple[int, int, list[int]]:
    """(width, height, the palette index of every pixel) of an indexed PNG
    (bit depth 1, 2, 4 or 8, not interlaced, any row filters); anything
    else is refused."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise GraphicsError('not a PNG file')
    pos, ihdr, idat, end = 8, None, bytearray(), False
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
            ihdr = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat += body
        elif kind == b'IEND':
            end = True
            break
        pos += 12 + n
    if ihdr is None or not end:
        raise GraphicsError('the PNG has no IHDR or no IEND')
    width, height, depth, ctype, comp, filt, interlace = ihdr
    if ctype != 3:
        raise GraphicsError(f'the PNG is colour type {ctype}, not indexed (3): keep it indexed, the palette '
                            f'index is the pixel value')
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
    return width, height, pixels


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


PACKED_PARAM = re.compile(r'^lz(11|12) -> (\d+) B; (.*)$')


def parse_param(param: str) -> tuple[str, int, int]:
    """(format, tiles, tail) of a graphics piece's param, or of the part
    after the pack mode of a gfxpack piece's."""
    m = PACKED_PARAM.match(param)
    if m:
        param = m.group(3)
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
        w, h, px = read_png(png)
    except GraphicsError as e:
        raise GraphicsError(f'{name}: {e}') from None
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
    if s['region'].split()[:1] != [p['label']]:
        raise GraphicsError(f'{p["label"]}: the sidecar is for {s["region"]}')
    data = from_image(fmt, tiles, png, s['tail'], p['label'] + '.png')
    m = PACKED_PARAM.match(p['param'])
    size = int(m.group(2)) if m else int(p['size'])        # a pack: its unpacked size
    if len(data) != size:
        raise GraphicsError(f'{p["label"]}: {len(data)} B; the piece is {size}')
    return data


def check(rom: bytes, quiet: bool = True) -> list[str]:
    import extract_data
    import data_survey
    problems = []
    got, conflicts = derive_packed(rom, data_survey.read_rows())
    problems += [f'packed graphics: {c}' for c in conflicts]
    want = {start: (PACK_PROOFS[keys[0]][0], nb, keys) for keys, items in PACKED.items()
            for start, nb in items.items()}
    for start in sorted(set(got) | set(want)):
        if got.get(start) != want.get(start):
            problems.append(f'packed graphics: {start} is {got.get(start)} by the data, {want.get(start)} in '
                            f'PACKED')
    for p in extract_data.read_manifest():
        if p['piece'] not in ('graphics', 'gfxpack'):
            continue
        fmt, tiles, tail = parse_param(p['param'])
        if p['piece'] == 'gfxpack':
            data, why = extract_data.unpack_piece(rom, p)
            if data is None:
                problems.append(why)
                continue
        else:
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
    ps = extract_data.read_manifest()
    n = sum(1 for p in ps if p['piece'] == 'graphics')
    k = sum(1 for p in ps if p['piece'] == 'gfxpack')
    print(f'OK: all {n} graphics regions and {k} graphics packs (unpacked) convert to images and encode back '
          f'byte-exact; the packs\' formats are what the data that names them gives')
    return 0


if __name__ == '__main__':
    sys.exit(main())
