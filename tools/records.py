#!/usr/bin/env python3
"""
records.py — Tables and palettes as readable records, extracted from your own
ROM into the ignored build/assets/records/, and an encoder that rebuilds the
exact bytes at build time (DATA_PLAN.md, step 6).

No value is ever committed (README, "Legal"). This tool holds only layouts:
for each survey row it structures, the record's fields (name and width) and,
where the reader fixes it, the record count. tools/extract_data.py places
each such row as a `records` piece: extract writes build/assets/records/
<label>.tsv, tools/build_rom.py encodes it to build/records/<label>.bin,
asm/data/ incbins that, and tools/verify.py counts it apart, never as
emitted by source.

A row is structured only when its reader proves both the layout and the
record count; every other table or palette stays an extracted blob. No
field is invented:

  structs    a ROM struct of asm/include/ (STRUCTS: the struct and the count
             its reader's index bound gives); its fields are read from the
             struct itself: a 1-byte field is u8; a wider one is u16 (or
             words) only where FIELD_TYPES names the reader that reads it so,
             else one unsplit column of its bytes (bytesN); an unnamed `skip`
             is Unk_XX (Unk_XX_YY when wider).
  arrays     the survey row's format, which states the element width the
             reader uses ("1 B per ...", "2 B per ...") and, for some, the
             fields of a small record; ARRAYS below, one line each with the
             reader and its index bound (a stated domain: character ids 0-6,
             PC slots, the 11 battler slots, ...). Words the format names as
             an address or offset in a bank are pointers (ptr16): written as
             the label of the data piece they point at when they point at
             one's start.
  palettes   palette rows whose reader copies a fixed number of colours
             (PALETTES): SNES BGR555 words, written as 5-bit R, G, B and bit
             15 (kept for an exact round trip).

A row's size must be exactly its count of records: the bytes past the
reader's extent are survey rows of their own (DATA_PLAN.md lists them).

Where the count comes from the source or the ROM rather than a stated
domain, DERIVED re-derives it and `check` (and the extraction) compare it
with the layout: the defines that size a record or bound an index
(Battle_LevelMax, SprRec_FirstNpc, ...), the largest index the only source
of it holds (LocRom.Tileset12 for LocGfx_Lists), and the object records
the action object lists cover (obj_lists_extent: BattleAct_IndexObjLists
run from every object pointer).

The readable form, one tab-separated file per piece:

  ; comment lines (what the table is, its layout and reader)
  Index  Field1  Field2 ...           the header: the layout's columns
  0      $1F     $0200   ...          one line per record: u8/u16/u24 as $hex,
                                      s8 as signed decimal, R/G/B as decimal
                                      0-31, ptr16 as a label or $hex, bytesN
                                      as N hex bytes in ROM order (`01 02`)

    python3 tools/records.py check      extract every records piece from the
                                        ROM and encode it back: byte-exact?
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INCLUDE = ROOT / 'asm' / 'include'


class RecordsError(Exception):
    pass


# ── Layouts ─────────────────────────────────────────────────────────────────

WIDTHS = {'u8': 1, 's8': 1, 'u16': 2, 'u24': 3, 'ptr16': 2, 'colour': 2}


def width(t: str) -> int:
    """Bytes of a field type ('bytesN': N bytes the reader does not split)."""
    kind = t.split(':')[0]
    return int(kind[5:]) if kind.startswith('bytes') else WIDTHS[kind]


# The element type of a struct field wider than a byte, where its reader
# shows it (else the field stays one unsplit `bytesN` column: its width is
# not known, so it is not split into bytes or words). A u16 field of more
# than 2 bytes becomes Name0, Name1, ... words.
FIELD_TYPES = {
    ('BattleRom_FrameLayout', 'RowOffset'): 'u16',   # Battle_DrawBattlerFrame: REP #$21, ADC [RowPtr], INC x2
    ('BattleRom_EnemyReward', 'Unk0'): 'u16',        # BattleFD reward sum: REP #$20, LDA .Unk0,X
    ('BattleRom_EnemyReward', 'Gold'): 'u16',        # the same, LDA .Gold,X
    ('LocRom', 'MapProps'): 'u16',                   # LocLoad_UnkA33B: 16-bit entry number
    ('LocRom', 'Events'): 'u16',                     # LocLoad_Unk56D4: 16-bit entry number
    ('TreasureRom', 'Tile'): 'u16',                  # Field_CheckTileInFront: REP #$20, LDA .Tile,X, CMP Field_FrontTile
    ('TreasureRom', 'Contents'): 'u16',              # the same, REP #$20, LDA .Contents,X
}


def _struct_fields(name: str) -> list[tuple[str, str]]:
    """The fields of ROM struct `name` (asm/include/*.inc) as columns."""
    for path in sorted(INCLUDE.glob('*.inc')):
        lines = path.read_text(errors='replace').splitlines()
        for i, line in enumerate(lines):
            if re.match(rf'^struct\s+{name}\s+\$[0-9A-Fa-f]{{6}}\b', line):
                out, off = [], 0
                for body in lines[i + 1:]:
                    if body.strip().startswith('endstruct'):
                        return out
                    m = re.match(r'^\s*(?:\.([A-Za-z_][A-Za-z0-9_]*):)?\s*skip\s+(\d+)\b', body)
                    if not m:
                        continue
                    n = int(m.group(2))
                    field = m.group(1) or (f'Unk_{off:02X}' if n == 1 else f'Unk_{off:02X}_{off + n - 1:02X}')
                    t = FIELD_TYPES.get((name, m.group(1)))
                    if n == 1:
                        out.append((field, 'u8'))
                    elif t == 'u16' and n == 2:
                        out.append((field, 'u16'))
                    elif t == 'u16' and n % 2 == 0:
                        out += [(f'{field}{k}', 'u16') for k in range(n // 2)]
                    else:
                        out.append((field, f'bytes{n}'))
                    off += n
                raise RecordsError(f'struct {name}: no endstruct')
    raise RecordsError(f'no struct {name} in asm/include/')


# A row is structured only when its reader proves both the layout and the
# record count (DATA_PLAN.md, step 6): every entry below names the reader
# and how it bounds the index. Rows whose bound no reader proves stay
# extracted blobs, however regular they look.

# Row start -> (the ROM struct whose records fill it, record count).
STRUCTS = {
    '$CC:5E00': ('BattleRom_EnemyReward', 255),   # BattleFD reward sum: id = a byte of Battler_UnkAF0A, $FF (Battle_EntryNone)
                                                  # skipped. Caveat: this rests on a present enemy never having id $FF;
                                                  # BattleSys_StealItem indexes the records by it with no $FF guard
    '$CC:F604': ('BattleRom_CursorSprite', 4),    # BattleMenu_DrawCursorSprites: X by 4 to CPX #BattleOam_CursorBytes ($10)
    '$CD:4000': ('BattleRom_PcAttackScript', 1),  # one header (its fields are read at fixed offsets)
    '$CD:5C26': ('BattleRom_Kind3Act', 68),       # BattleAct kind 3: index Battle_ActId - $BC, ids $BC-$FF
    '$F6:0000': ('LocRom', 512),                  # LocLoad_Unk092B: Loc_Id low byte x 14, + $E00 for bit 8 (9-bit id)
    '$E5:0402': ('ExitRom', 814),                 # Map_LoadExitTiles: records ExitRom_LocOfs[id] to [id + 1]; the
                                                  # 513th offset (the end) is $1A44 = $0402 + 814 x 7
    '$F5:F402': ('TreasureRom', 249),             # Map_LoadTreasureTiles: the same through TreasureRom_LocOfs; its
                                                  # end $F7E6 = $F402 + 249 x 4
    '$CE:8870': ('BattleRom_ActObjRec', 4691),    # BattleAct_IndexObjLists: 16 lists from each object pointer
                                                  # (DERIVED: obj_lists_extent re-derives the records they cover)
}


def _f(*names: str, t: str = 'u8') -> list[tuple[str, str]]:
    return [(n, t) for n in names]


def _rep(n: int, *fields: tuple[str, str]) -> list[tuple[str, str]]:
    """n copies of the fields, numbered (Level0, Gain0, Level1, ...)."""
    return [(f'{name}{k}', t) for k in range(n) for name, t in fields]


# Row start -> (fields of one record, record count). The element width and,
# where the format names them, the fields come from the survey row's format
# (taken from the reader); the count is the reader's index range: an index
# domain the format states ("per character id 0-6", "per PC slot", "per
# battler slot", Battle_NumSlots = 11), or the bound of the index the
# comment names.
SLOTS = 11          # Battle_NumSlots: battler slots 0-10
PC_SLOTS = 3        # Battle_NumPcSlots
ARRAYS: dict[str, tuple[list[tuple[str, str]], int]] = {
    '$C6:F560': (_f('Divisor', t='u16'), 32),                 # C2Scene zoom (M7A/M7B), 32 steps
    '$C6:F5A0': (_f('Divisor', t='u16'), 32),                 # C2Scene zoom (M7C/M7D), 32 steps
    '$CC:2583': (_f('AttackNum'), 7),                         # BattleRom_PcAttackNum: character ids 0-6
    '$CC:258A': (_rep(4, ('Level', 'u8'), ('Gain', 'u8')), 7),    # BattleRom_HpGrowth: character ids 0-6
    '$CC:25C2': (_rep(4, ('Level', 'u8'), ('Gain', 'u8')), 7),    # BattleRom_MpGrowth: character ids 0-6
    '$CC:26FA': (_rep(8, ('Tp', 'u16')), 7),                  # BattleRom_TechTpCost: character ids 0-6
    '$CC:276A': (_f('FirstTech', 'TechCount'), 7),            # BattleRom_CharTechs: character ids 0-6
    '$CC:2953': (_f('Bit0', 'Bit1', 'Bit2'), 5),              # MenuRom_ComboNeeds: combos 0-4
    '$CC:2983': (_f('Members'), 5),                           # MenuRom_ComboMembers: combos 0-4
    '$CC:86C9': (_f('TargetMode', 'Area'), 256),              # BattleRom_EnemyTechTarget: X = 8-bit Battle_UnkB18C x 2
    '$CC:F395': (_f('Offset', t='u16'), PC_SLOTS),            # BattleRom_TechEntryBase: per PC slot
    '$CC:F4FC': (_f('Extra', t='s8'), 8),                     # BattleRom_FrameExtraCount: Battler_FrameLayout = Flags AND 7
    '$CC:F544': (_f('Interval'), 32),                         # BattleRom_EnemyMoveInterval: (delay / 2) * 4 + speed / 2, at most 31
    '$CC:F5FD': (_f('Frames'), 7),                            # BattleRom_FxOverlayPeriod: overlay blocks 1-7
    '$CC:F63C': (_f('Flag'), 7),                              # BattleRom_PcPathAlways: character ids 0-6
    '$CC:F829': (_f('Offset'), 6),                            # BattleRom_HitSetOffset: record sets 0-5
    '$CC:F846': (_f('Offset'), 7),                            # BattleRom_CharTimes6: character ids 0-6
    '$CC:F8ED': (_f('Offset', t='u16'), SLOTS),               # BattleRom_StatsOffset: per battler slot
    '$CC:F903': (_f('Tile'), 10),                             # BattleRom_DigitTiles: digits 0-9
    '$CC:F90D': (_f('Tile'), 10),                             # BattleRom_DigitTilesB: digits 0-9
    '$CC:F917': (_f('Offset', t='u16'), SLOTS),               # BattleRom_SlotTimes16: per battler slot
    '$CC:F939': (_f('Offset'), 8),                            # BattleRom_EnemyRecOfs: enemies 0-7
    '$CC:F941': (_f('Address', t='u16'), SLOTS),              # BattleRom_FrameDestBase: per battler slot
    '$CC:F957': (_f('Source', t='u16'), 4),                   # BattleRom_GfxStepSrcA: graphics steps 0-3
    '$CC:F95F': (_f('Source', t='u16'), 4),                   # BattleRom_GfxStepSrcB
    '$CC:F967': (_f('Vram', t='u16'), 4),                     # BattleRom_GfxStepVramA
    '$CC:F96F': (_f('Vram', t='u16'), 4),                     # BattleRom_GfxStepVramB
    '$CC:F977': (_f('Bytes', t='u16'), 4),                    # BattleRom_GfxStepSizeA
    '$CC:F97F': (_f('Bytes', t='u16'), 4),                    # BattleRom_GfxStepSizeB
    '$CC:F987': (_f('Source', t='u16'), SLOTS),               # BattleRom_FrameDmaSrcA: per battler slot
    '$CC:F99D': (_f('Source', t='u16'), SLOTS),               # BattleRom_FrameDmaSrcB
    '$CC:F9B3': (_f('Vram', t='u16'), SLOTS),                 # BattleRom_FrameDmaVramA
    '$CC:F9C9': (_f('Vram', t='u16'), SLOTS),                 # BattleRom_FrameDmaVramB
    '$CC:FA23': (_f('Offset', t='u16'), PC_SLOTS),            # BattleRom_NameAttrL1: per PC slot
    '$CC:FA29': (_f('Offset', t='u16'), PC_SLOTS),            # BattleRom_NameAttrL02
    '$CC:FA2F': (_f('Offset', t='u16'), PC_SLOTS),            # BattleRom_HpCellL0
    '$CC:FA35': (_f('Offset', t='u16'), PC_SLOTS),            # BattleRom_HpCellL1
    '$CC:FA3B': (_f('Offset', t='u16'), PC_SLOTS),            # BattleRom_HpCellL2
    '$CC:FAF3': (_f('Tile', 'Attr'), 44),                     # BattleRom_SprRecInit: Battle_SprRec records 0-43
    '$CC:FB6F': (_f('Square'), 16),                           # BattleRom_Squares: n 0-15
    '$CC:FB7F': (_f('WeightA', 'WeightB'), 7),                # BattleRom_ActLerpWeights: 7 pairs
    '$CC:FBC8': (_f('SlotA', 'SlotB'), PC_SLOTS),             # BattleRom_PcPartners: per PC slot
    '$CC:FC1E': (_f('Offset', t='u16'), 7),                   # BattleRom_CharRecOffset: character ids 0-6
    '$CD:6A2C': (_f('PalStep', t='ptr16:CD'), 256),           # BattleRom_EnemyActPals: 256 palette indexes
    # ($CE:0000, BattleRom_ActSubscripts, is in tools/battle.py's actions unit)
    '$CE:EFEA': (_f('Step'), 8),                              # BattleRom_DissolvePhaseStep: patterns 0-7
    '$CE:EFF2': (_f('Vram', t='u16'), 4),                     # BattleRom_FxTileVram: tile sets 0-3
    '$CE:EFFA': (_f('Byte0'), 2),                             # BattleRom_FxRecByte0: colour-math cases 0/1
    '$CE:F03E': (_f('Mask'), 8),                              # BattleRom_FxBitMask: bits 0-7
    '$CE:F146': (_f('Byte0', 'Byte1'), 8),                    # BattleRom_Op80PairB: (arg AND $38) / 4; byte 0 -> PalAnimRecs89+3, byte 1 -> +15
    '$CE:F156': (_f('Bytes', t='u16'), 8),                    # BattleRom_LayoutFrameBytes: Battler_FrameLayout = Flags AND 7
    '$CE:F166': (_f('Address', t='u16'), SLOTS),              # BattleRom_SlotFrameBuf: per battler slot
    '$CE:F17C': (_f('Vram', t='u16'), SLOTS),                 # BattleRom_SlotFrameVram: per battler slot
    '$CE:F1C2': (_f('Mask', t='u16'), 8),                     # BattleRom_DissolveMask: pixel columns 0-7
    '$CE:F48E': (_f('Sine'), 256),                            # BattleRom_AbsSine: angles 0-255
    '$D1:5F42': (_f('Frame'), 28),                            # BattleRom_PcKoFrame: Pc_CharId (0-6) x 4 + Battler_Facing (0-3)
    '$E4:2600': (_f('Offset', t='u16'), 256),                 # BattleRom_SprAnimFrames: 256 animations
    '$E4:2800': (_f('Offset', t='u16'), 256),                 # BattleRom_SprAnimDurs: 256 animations
    '$E4:FFE0': (_f('Low', t='u16'), 7),                      # RomE4_PtrInit: 7 table pointers
    '$E5:0000': (_f('Offset', t='u16'), 513),                 # ExitRom_LocOfs: 512 locations and the end
    '$F5:F000': (_f('Offset', t='u16'), 513),                 # TreasureRom_LocOfs: 512 locations and the end
    '$FD:A849': (_f('Address', t='u16'), PC_SLOTS),           # BattleRom_CmdPtr: per PC slot
    '$FD:A89D': (_f('FirstTech'), 8),                         # BattleRom_CharFirstTech: character ids 0-6 and the end byte
    '$FF:C9AC': (_rep(10, ('Char', 'u8')), 8),                # MenuRom_NameChars: 8 rows of 10
    '$FF:CF0E': (_f('Table', t='ptr16:CC'), 5),               # MenuRom_ItemTablesA: item categories 0-4
    '$FF:CF18': (_f('RecSize'), 5),                           # MenuRom_ItemRecSizesA: item categories 0-4
    '$FF:CF1D': (_f('Table', t='ptr16:CC'), 5),               # MenuRom_ItemTablesB: item categories 0-4
    '$FF:D562': (_f('Tile', t='u16'), 12),                    # MenuRom_CfgIcons: entries 0-11
    # (data-tables-3) Each count below is the whole domain of the reader's
    # index, or the bound DERIVED re-derives from the source or the ROM.
    '$CC:4700': ([('Hp', 'u16'), ('Unk3F', 'u8')] + [(f'Unk4C_{k}', 'u8') for k in range(3, 8)]
                 + [(f'Unk64_{k:X}', 'u8') for k in range(12)] + [(f'Unk46_{k}', 'u8') for k in range(3)], 256),
                                                              # BattleRom_EnemyStats: BattleFD_UnkB438, id = a byte of
                                                              # Battler_UnkAF0A (high byte cleared) x 23; +0 is copied to
                                                              # CurHp/MaxHp lo and hi, the rest byte by byte
    '$CC:7AC9': ([(f'Byte{k}', 'u8') for k in range(12)], 255),
                                                              # BattleRom_EnemyEffectRecA: BattleSys_UnkD7C4, part number =
                                                              # a byte of BattleRom_UnkCC6FCB, $FF (Battle_EnemyPartNone)
                                                              # skipped, x Battle_EffectRecSize, copied byte by byte
    '$CC:2632': (_f('Exp', t='u16'), 100),                    # BattleRom_ExpToLevel: BattleSys_ApplyExpStep, PcStatBlk.Level
                                                              # clamped to Battle_LevelMax (99) x 2, read 16-bit
    '$CD:666E': (_f('Objects', t='ptr16:CE'), 256),           # BattleRom_EnemyActObjs: Battle_ActObjIdx (1 B, its high byte
                                                              # zeroed) x 2
    '$CE:F28E': (_f('Point', t='u16'), 256),                  # BattleRom_HalfPlaneEdge: BattleCD_FxOpHalfPlane, an angle byte
                                                              # x 2, read 16-bit into BattleCE_LineP1
    '$CF:A000': ([(f'Entry{k}', 'u16') for k in range(32)], 256),
                                                              # BattleRom_FxGfxLists: BattleCD_ConvertFxGfx, the set (a byte:
                                                              # Battle_FxTileSet) x 64, BattleCD_GfxPartTiles (32) words
    '$CF:E000': (_f('Colours', t='u16'), 256),                # BattleRom_FxGfxColours: the same set x 2, read 16-bit
    '$E4:2A00': (_f('Offset', t='u16'), 256),                 # MenuRom_E4Palettes' table: Menu_SprLoad, a sprite record's
                                                              # palette byte (byte 2) x 2
    '$E4:F000': (_f('Gfx', 'Frames', 'Pal', 'Anim', 'Size'), 263),
                                                              # RomE4_SprRec: Evt_LoadSpriteRec (a record byte) and
                                                              # Evt_Op82_InitWramSprite / Menu_SprLoad kind 1 (SprRec_FirstNpc
                                                              # + a byte): records 0-262
    '$F6:1C00': (_f(*[f'Pack{k}' for k in range(8)]), 54),    # LocGfx_Lists: LocLoad_Unk0960, LocRom.Tileset12 x
                                                              # LocGfx_ListSize, $FF none; the only source of the index is
                                                              # LocRom, whose values reach entry 53 (DERIVED)
    '$FF:D296': (_f('Nibbles'), 256),                         # MenuRom_SlotEraNibbles: Menu_UnkD36C, a 9-bit location / 2
}

# Palette rows: row start -> (colours per record, record count). Only rows
# whose reader copies a fixed number of colours (the format's "N colours ->
# $AA-$BB" or a stated count); the rest stay blobs.
PALETTES: dict[str, tuple[int, int]] = {
    '$C6:F540': (1, 16), '$C6:F5E0': (1, 16), '$C6:F600': (1, 16),
    '$C6:F620': (1, 16),        # C2Scene_LoadVram copies 33 B: one byte past the row
    '$D0:FD00': (1, 48),        # BattleFx_LoadBgRows2To4: 48 colours
    '$D1:38F2': (1, 3), '$D1:38FA': (1, 3),      # Battle_InitSceneGfx: 6 B each
    '$D1:4D80': (1, 8),         # Battle_HitNumColoursA and B: 16 B
    '$D1:5980': (1, 62),        # BattleCF_FrameUpdate: steps 0-$3D
    '$FF:9C68': (1, 4), '$FF:9C70': (1, 4), '$FF:9C78': (1, 4),
    '$FF:9DF0': (1, 13),        # the reader copies 16 colours: these 13 and MenuRom_MainPalC's 3 after them
    '$FF:9E0A': (1, 3),
    '$FF:CB9C': (1, 4), '$FF:CBAC': (1, 4), '$FF:CBB4': (1, 4), '$FF:CBBC': (1, 4),
    '$FF:CBC4': (1, 8), '$FF:CBE4': (1, 24), '$FF:CC14': (1, 8), '$FF:CC34': (1, 8),
    '$FF:CC64': (1, 8), '$FF:CC74': (1, 8), '$FF:CDF4': (1, 8), '$FF:CE04': (1, 8),
    '$FF:CE30': (1, 16), '$FF:CE9A': (1, 16),
    '$E4:0000': (12, 256),      # the sprite palettes: a sprite record's palette byte x Pal_ObjColorBytes (Obj_PalSrc,
                                # the field's 24-byte copy of colours 1-12; MenuRom_E4Palettes' offsets the same)
}


# ── Counts and extents the check re-derives ───────────────────────────────

def obj_lists_extent(rom: bytes, d: dict) -> tuple[int, int]:
    """[start, stop) (file offsets) of the object records the action
    object lists cover: every word of BattleRom_PcAttackObjs, TechObjs and
    EnemyActObjs (one table after the other; Battle_ActObjIdx, a byte x 2,
    reaches no further from any of them) is an offset in bank $CE, from
    which BattleAct_IndexObjLists reads Battle_ActObjects lists of 4-byte
    records: a record whose top three bits (Battle_ActObjRecTypeMask) are
    1xx or 001 ends a list, 010 is a mark, and the first record of lists
    1-15 is not tested. Raises when the covered records leave a gap."""
    ce = (d['BattleRom_ScriptsCE'] - 0xC00000) & 0xFF0000
    lo, hi = d['BattleRom_PcAttackObjs'] - 0xC00000, d['BattleRom_EnemyActObjs'] - 0xC00000 + 2 * 256
    starts = {rom[a] | rom[a + 1] << 8 for a in range(lo, hi, 2)} - {0xFFFF}
    covered = set()
    for x in starts:
        lists, first = 0, True
        while True:
            t = rom[ce + x] & d['Battle_ActObjRecTypeMask']
            covered.add(x)
            x += 4
            if first and lists:
                first = False
                continue
            first = False
            if t == 0 or t & d['Battle_ActObjRecMark'] and not t & 0x80:
                continue
            lists += 1
            if lists == d['Battle_ActObjects']:
                break
            first = True
    s, e = min(covered), max(covered) + 4
    if len(covered) != (e - s) // 4 or any((x - s) % 4 for x in covered):
        raise RecordsError(f'the object lists leave a gap in ${s:04X}-${e - 1:04X}')
    return ce + s, ce + e


def _loc_tilesets(rom: bytes, d: dict) -> int:
    """Entries of LocGfx_Lists the locations name: 1 + the largest
    LocRom.Tileset12 other than LocRom_SetNone."""
    base = d['LocRom'] if 'LocRom' in d else 0xF60000
    used = [rom[base - 0xC00000 + 14 * k + 1] for k in range(512)]
    return 1 + max(v for v in used if v != d['LocRom_SetNone'])


# Row start -> (what, count(rom, defines)): the reader's bound, re-derived
# from the source's defines or the ROM by `check` (and the extraction),
# against the layout's count.
DERIVED = {
    '$CE:8870': ('the records the object lists cover', lambda rom, d: (lambda se: (se[1] - se[0]) // 4)(
        obj_lists_extent(rom, d))),
    '$CC:4700': ('256 ids; 3 + Battle_EnemyRec4FBytes + Rec64Bytes + Rec46Bytes = 23 B',
                 lambda rom, d: 256 if 3 + d['Battle_EnemyRec4FBytes'] + d['Battle_EnemyRec64Bytes']
                 + d['Battle_EnemyRec46Bytes'] == 23 else -1),
    '$CC:7AC9': ('part numbers below Battle_EnemyPartNone, Battle_EffectRecSize B',
                 lambda rom, d: d['Battle_EnemyPartNone'] if d['Battle_EffectRecSize'] == 12 else -1),
    '$CC:2632': ('levels 0-Battle_LevelMax', lambda rom, d: d['Battle_LevelMax'] + 1),
    '$CF:A000': ('256 sets of BattleCD_GfxPartTiles words', lambda rom, d: 256 if d['BattleCD_GfxPartTiles'] == 32
                 else -1),
    '$E4:0000': ('256 palettes of Pal_ObjColorBytes (ObjPal_CopyCount + 1)',
                 lambda rom, d: 256 if d['Pal_ObjColorBytes'] == d['ObjPal_CopyCount'] + 1 == 24 else -1),
    '$E4:F000': ('SprRec_FirstNpc + 256 records', lambda rom, d: d['SprRec_FirstNpc'] + 256),
    '$F6:1C00': ('1 + the largest LocRom.Tileset12', _loc_tilesets),
}


def derived_problems(rom: bytes, d: dict | None = None, pieces: list[dict] | None = None) -> list[str]:
    """Where a DERIVED count is not the layout's, or the object records'
    piece does not start where the lists do."""
    if d is None:
        sys.path.insert(0, str(ROOT / 'tools'))
        import battle
        d = battle.defines(ROOT)
    problems = []
    for start, (what, count) in DERIVED.items():
        kind = 'palette' if start in PALETTES else 'table'
        lay = layout_for(start, kind)
        try:
            n = count(rom, d)
        except RecordsError as err:
            problems.append(f'{start}: {err}')
            continue
        if lay is None or n != lay.count:
            problems.append(f'{start}: {what} give {n} records, the layout {lay.count if lay else None}')
    try:
        s, _ = obj_lists_extent(rom, d)
        if pieces is not None and not any(p['offset'] == s and p['piece'] == 'records' for p in pieces):
            problems.append(f'no records piece starts at the object lists\' first record (${s & 0xFFFF:04X})')
    except RecordsError:
        pass
    return problems


class Layout:
    def __init__(self, fields: list[tuple[str, str]], count: int, source: str):
        self.fields = fields
        self.count = count
        self.source = source
        self.size = sum(width(t) for _, t in fields)

    def columns(self) -> list[str]:
        out = []
        for name, t in self.fields:
            out += [f'{name}R', f'{name}G', f'{name}B', f'{name}Bit15'] if t == 'colour' else [name]
        return out


def layout_for(start: str, kind: str) -> Layout | None:
    """The layout of the survey row at `start` (of `kind`), or None when it
    is not structured."""
    if kind in ('table', 'map') and start in STRUCTS:
        name, count = STRUCTS[start]
        return Layout(_struct_fields(name), count, f'struct {name} (asm/include/)')
    if kind == 'table' and start in ARRAYS:
        fields, count = ARRAYS[start]
        return Layout(fields, count, 'the survey row\'s format (the reader\'s element width)')
    if kind == 'palette' and start in PALETTES:
        per, count = PALETTES[start]
        fields = [('Colour', 'colour')] if per == 1 else [(f'C{k}', 'colour') for k in range(per)]
        return Layout(fields, count, 'BGR555 colours')
    return None


def check_extent(layout: Layout, size: int, where: str) -> int:
    """The record count of a row of `size` bytes (raises when the row is not
    whole records, or not the count the reader gives)."""
    if size % layout.size:
        raise RecordsError(f'{where}: {size} B is not a whole number of {layout.size}-byte records')
    n = size // layout.size
    if layout.count is not None and n != layout.count:
        raise RecordsError(f'{where}: {n} records, the reader\'s extent is {layout.count}')
    return n


# ── Bytes <-> readable ──────────────────────────────────────────────────────

def _value(data: bytes, t: str, labels: dict[int, str], bank: int) -> list[str]:
    kind, _, arg = t.partition(':')
    v = int.from_bytes(data, 'little')
    if kind == 'colour':
        return [str(v & 31), str(v >> 5 & 31), str(v >> 10 & 31), str(v >> 15)]
    if kind == 's8':
        return [str(v - 256 if v >= 128 else v)]
    if kind.startswith('bytes'):
        return [' '.join(f'{b:02X}' for b in data)]
    if kind == 'ptr16':
        target = (int(arg, 16) - 0xC0) << 16 | v
        if target in labels:
            return [labels[target]]
        return [f'${v:04X}']
    return [f'${v:0{2 * len(data)}X}']


def decode(data: bytes, layout: Layout, label: str, where: str, labels: dict[int, str] | None = None,
           reader: str = '') -> str:
    labels = labels or {}
    n = check_extent(layout, len(data), label)
    out = [f'; {label} {where}: {n} records of {layout.size} B; layout from {layout.source}.',
           '; Extracted from your own ROM by tools/records.py (never commit it); the build',
           '; encodes it back. Like every asset it is extracted again when it changes.']
    if reader:
        out.append(f'; Read by {reader}')
    out.append('\t'.join(['Index'] + layout.columns()))
    for k in range(n):
        rec, o, cols = data[k * layout.size:(k + 1) * layout.size], 0, [str(k)]
        for _, t in layout.fields:
            w = width(t)
            cols += _value(rec[o:o + w], t, labels, 0)
            o += w
        out.append('\t'.join(cols))
    return '\n'.join(out) + '\n'


def _number(text: str, where: str) -> int:
    m = re.fullmatch(r'\$([0-9A-Fa-f]+)|(-?\d+)', text)
    if not m:
        raise RecordsError(f'{where}: {text!r} is not a number ($hex or decimal)')
    return int(m.group(1), 16) if m.group(1) else int(m.group(2))


def encode(text: str, layout: Layout, label: str, addresses: dict[str, int] | None = None) -> bytes:
    """The bytes of a readable file. `addresses`: {label: file offset} the
    ptr16 fields may name."""
    addresses = addresses or {}
    lines = [ln for ln in text.split('\n') if ln.strip() and not ln.startswith(';')]
    if not lines or lines[0].split('\t') != ['Index'] + layout.columns():
        raise RecordsError(f'{label}: the header must be: Index, {", ".join(layout.columns())}')
    out = bytearray()
    for k, line in enumerate(lines[1:]):
        where = f'{label} record {k}'
        cols = line.split('\t')
        if cols[0] != str(k):
            raise RecordsError(f'{where}: the index is {cols[0]!r}, records go 0, 1, 2, ...')
        cols = cols[1:]
        if len(cols) != len(layout.columns()):
            raise RecordsError(f'{where}: {len(cols)} values, the layout has {len(layout.columns())}')
        i = 0
        for name, t in layout.fields:
            kind, _, arg = t.partition(':')
            w = width(t)
            if kind.startswith('bytes'):
                c = cols[i]
                i += 1
                try:
                    raw = bytes(int(x, 16) for x in c.split())
                except ValueError:
                    raise RecordsError(f'{where}: {name}: {c!r} is not {w} hex bytes') from None
                if len(raw) != w:
                    raise RecordsError(f'{where}: {name}: {c!r} is not {w} hex bytes')
                out += raw
                continue
            if kind == 'colour':
                r, g, b, hi = (_number(c, f'{where} {name}') for c in cols[i:i + 4])
                if not all(0 <= c < 32 for c in (r, g, b)) or hi not in (0, 1):
                    raise RecordsError(f'{where}: {name} needs R, G, B in 0-31 and bit 15 0 or 1')
                v = r | g << 5 | b << 10 | hi << 15
                i += 4
            else:
                c = cols[i]
                i += 1
                if kind == 'ptr16' and not c.startswith('$'):
                    base, _, off = c.partition('+')
                    if base not in addresses:
                        raise RecordsError(f'{where}: {name}: no data label {base!r}')
                    target = addresses[base] + (_number(off, where) if off else 0)
                    if target >> 16 != int(arg, 16) - 0xC0:
                        raise RecordsError(f'{where}: {name}: {base} is not in bank ${arg}')
                    v = target & 0xFFFF
                else:
                    v = _number(c, f'{where} {name}')
                    if kind == 's8':
                        if not -128 <= v < 128:
                            raise RecordsError(f'{where}: {name} {v} is not a signed byte')
                        v &= 0xFF
                if not 0 <= v < 1 << 8 * w:
                    raise RecordsError(f'{where}: {name} {c} does not fit {w} byte(s)')
            out += v.to_bytes(w, 'little')
    if layout.count is not None and len(lines) - 1 != layout.count:
        raise RecordsError(f'{label}: {len(lines) - 1} records, the reader\'s extent is {layout.count}')
    return bytes(out)


def piece_labels(pieces: list[dict]) -> tuple[dict[int, str], dict[str, int]]:
    """{file offset: label} and {label: file offset} of the manifest's
    pieces: what a ptr16 field is written as, and resolved from."""
    labels = {p['offset']: p['label'] for p in pieces}
    return labels, {v: k for k, v in labels.items()}


def piece_layout(piece: dict) -> Layout:
    """The layout of a manifest `records` piece (its param starts with the
    survey row's kind)."""
    lay = layout_for(piece['start'], piece['param'].split()[0])
    if lay is None:
        raise RecordsError(f'{piece["label"]}: no layout in tools/records.py')
    return lay


def extract_all(rom: bytes, pieces: list[dict]) -> dict[str, str]:
    """{label: readable file} of every records piece, each checked to encode
    back to the ROM's bytes, after the DERIVED counts (raises RecordsError
    otherwise)."""
    labels, addresses = piece_labels(pieces)
    problems = derived_problems(rom, pieces=pieces)
    if problems:
        raise RecordsError('; '.join(problems))
    out = {}
    for p in pieces:
        if p['piece'] != 'records':
            continue
        lay = piece_layout(p)
        data = rom[p['offset']:p['stop']]
        text = decode(data, lay, p['label'], f'{p["start"]}-{p["end"]}', labels)
        if encode(text, lay, p['label'], addresses) != data:
            raise RecordsError(f'{p["label"]}: does not encode back to the ROM\'s bytes')
        out[p['label']] = text
    return out


def encode_all(texts: dict[str, str], pieces: list[dict]) -> dict[str, bytes]:
    """{label: bytes} of every records piece from its readable file."""
    _, addresses = piece_labels(pieces)
    return {p['label']: encode(texts[p['label']], piece_layout(p), p['label'], addresses)
            for p in pieces if p['piece'] == 'records'}


# ── Command line ────────────────────────────────────────────────────────────

def check(rom: bytes) -> list[str]:
    """Extract every records piece and encode it back; the problems."""
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    pieces = extract_data.read_manifest()
    labels, addresses = piece_labels(pieces)
    problems = derived_problems(rom, pieces=pieces)
    for p in pieces:
        if p['piece'] != 'records':
            continue
        lay = piece_layout(p)
        data = rom[p['offset']:p['stop']]
        text = decode(data, lay, p['label'], f'{p["start"]}-{p["end"]}', labels)
        if encode(text, lay, p['label'], addresses) != data:
            problems.append(f'{p["label"]}: does not encode back to the ROM\'s bytes')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    try:
        problems = check(extract_data.read_rom())
    except (RecordsError, extract_data.DataError) as e:
        print(f'records: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'records: {p}', file=sys.stderr)
    if problems:
        return 1
    print('OK: every records piece extracts and encodes back to the ROM\'s bytes')
    return 0


if __name__ == '__main__':
    sys.exit(main())
