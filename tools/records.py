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
with the layout: the reader itself, run by tools/absint.py once per value
of its index byte (READERS: each value must read exactly its own record,
so the record size and the count come from the code), the defines that
bound an index (Battle_LevelMax, SprRec_FirstNpc, ...), the largest index
the only source of it holds (LocRom.Tileset12 for LocGfx_Lists), and the
object records the action object lists cover (obj_lists_extent:
BattleAct_IndexObjLists run from every object pointer, and
BattleAct_StepObjAnim's facing blocks inside them).

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
    # (data-tables-3) DERIVED checks each count below: READERS runs the
    # reader for each index value, or a define, register width or the ROM
    # gives it (see DERIVED).
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
                                                              # BattleRom_FxGfxLists: BattleCD_ConvertFxGfx, the set
                                                              # (Battle_FxTileSet) x 64, BattleCD_GfxPartTiles (32) words.
                                                              # ASSUMED: the set is a byte only with B = 0 at
                                                              # BattleCD_LoadFxGfx4's TAX, not traced (READERS)
    '$CF:E000': (_f('Colours', t='u16'), 256),                # BattleRom_FxGfxColours: the same set x 2, read 16-bit (the
                                                              # same assumption)
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
    '$F6:24C0': (15, 616),      # LocPal_Rom: LocLoad_Unk7084 copies 7 rows of colours 1-15 (LocPal_RowBytes each) of
                                # entry LocRom.Palette (x LocPal_SetBytes) to Pal_Buf rows 1-7, which Pal_LoadUnkRow0
                                # copies to Pal_CgramBuf and Pal_UploadCgram DMAs to CGRAM: 88 entries (DERIVED)
    '$D0:FA00': (16, 15),       # BattleRom_BgSetPalettes: BattleFx_LoadBgSet copies 3 rows of 16 colours from
                                # BattleFx_BgSetPalOfs[set] (sets 0-5) to BG palette rows 2-4 (DERIVED)
    '$FF:B210': (8, 9),         # MenuRom_WindowPals: Menu_LoadWindowPal copies 8 colours of style 0-7 (x 16 B),
                                # Pal_LoadUnkRow0 15 colours from style x 16 + 2 (styles 0-7): 144 B (DERIVED)
    '$CC:F77B': (2, 1),         # BattleRom_FxTintColours: Battle_FxOverlay2Tint writes its 4 bytes into live
                                # palette bytes 6-9 (colours 3-4)
    '$E4:0000': (12, 256),      # the sprite palettes: a sprite record's palette byte x Pal_ObjColorBytes (Obj_PalSrc,
                                # the field's 24-byte copy of colours 1-12; MenuRom_E4Palettes' offsets the same)
}


# ── Counts and extents the check re-derives ───────────────────────────────

def obj_lists(rom: bytes, d: dict) -> tuple[set[int], list[tuple[int, int | None]]]:
    """The object pointers (offsets in bank $CE) and, read from each as
    BattleAct_IndexObjLists reads them, every list: (its first record, the
    Battle_ActObjMarkCount it leaves, None when it sets none). The pointers
    are every word of BattleRom_PcAttackObjs, TechObjs and EnemyActObjs
    (one table after the other; Battle_ActObjIdx, a byte x 2, reaches no
    further from any of them) but the words $FFFF (25 in this ROM), taken
    as unused: IndexObjLists has no test for $FFFF, and obj_lists_extent
    refuses one that would point into the records the lists cover."""
    ce = (d['BattleRom_ScriptsCE'] - 0xC00000) & 0xFF0000
    lo, hi = d['BattleRom_PcAttackObjs'] - 0xC00000, d['BattleRom_EnemyActObjs'] - 0xC00000 + 2 * 256
    starts = {rom[a] | rom[a + 1] << 8 for a in range(lo, hi, 2)}
    lists = []
    for x in starts - {0xFFFF}:
        n, first, start, count, marks = 0, True, x, 0, None
        while True:
            t = rom[ce + x] & d['Battle_ActObjRecTypeMask']
            x += 4
            count += 1
            if first and n:
                first = False
                continue
            first = False
            if t == 0:
                continue
            if t & d['Battle_ActObjRecMark'] and not t & 0x80:
                marks, count = count, 0
                continue
            if not t & 0x80:                    # 001: the mark count is 0
                marks = 0
            lists.append((start, marks))
            n += 1
            if n == d['Battle_ActObjects']:
                break
            first, start, count, marks = True, x, 0, None
    return starts, lists


def obj_lists_extent(rom: bytes, d: dict) -> tuple[int, int]:
    """[start, stop) (file offsets) of the object records the action
    object lists cover (obj_lists). BattleAct_IndexObjLists reads
    Battle_ActObjects lists of 4-byte records from each pointer: a record
    whose top three bits (Battle_ActObjRecTypeMask) are 1xx or 001 ends a
    list, 010 is a mark, and the first record of lists 1-15 is not tested.
    BattleAct_StepObjAnim then reads, for each facing 0 to
    Battle_FacingRight, from the list's first record + facing x the mark
    count x 4 up to a record with a type: those reads must stay inside
    what IndexObjLists covers. Raises when the covered records leave a gap,
    when a list sets no mark count (the count it would leave is another
    list's, not traced), when StepObjAnim would read outside, or when a
    $FFFF word would point into the covered records."""
    ce = (d['BattleRom_ScriptsCE'] - 0xC00000) & 0xFF0000
    starts, lists = obj_lists(rom, d)
    covered = set()
    for x in starts - {0xFFFF}:
        n, first = 0, True
        while True:
            t = rom[ce + x] & d['Battle_ActObjRecTypeMask']
            covered.add(x)
            x += 4
            if first and n:
                first = False
                continue
            first = False
            if t == 0 or t & d['Battle_ActObjRecMark'] and not t & 0x80:
                continue
            n += 1
            if n == d['Battle_ActObjects']:
                break
            first = True
    s, e = min(covered), max(covered) + 4
    if len(covered) != (e - s) // 4 or any((x - s) % 4 for x in covered):
        raise RecordsError(f'the object lists leave a gap in ${s:04X}-${e - 1:04X}')
    if 0xFFFF in starts and s <= 0xFFFF < e:
        raise RecordsError('a $FFFF object pointer (taken as unused) points into the object records')
    for start, marks in lists:
        if marks is None:
            raise RecordsError(f'the object list at ${start:04X} sets no mark count (StepObjAnim\'s facing blocks '
                               f'would use another list\'s)')
        for facing in range(d['Battle_FacingRight'] + 1):
            y = start + facing * marks * 4
            while True:
                if not s <= y < e:
                    raise RecordsError(f'BattleAct_StepObjAnim reads ${y:04X} for facing {facing} of the list at '
                                       f'${start:04X}, outside the object records (${s:04X}-${e - 1:04X})')
                if rom[ce + y] & d['Battle_ActObjRecTypeMask']:
                    break
                y += 4
    return ce + s, ce + e


def _struct(name: str) -> tuple[int, dict[str, int], int]:
    """(base address, {field: offset}, record bytes) of ROM struct `name`
    (asm/include/*.inc), its `skip` lines read as _struct_fields reads them."""
    for path in sorted(INCLUDE.glob('*.inc')):
        lines = path.read_text(errors='replace').splitlines()
        for i, line in enumerate(lines):
            m = re.match(rf'^struct\s+{name}\s+\$([0-9A-Fa-f]{{6}})\b', line)
            if not m:
                continue
            fields, off = {}, 0
            for body in lines[i + 1:]:
                if body.strip().startswith('endstruct'):
                    return int(m.group(1), 16), fields, off
                f = re.match(r'^\s*(?:\.([A-Za-z_][A-Za-z0-9_]*):)?\s*skip\s+(\d+)\b', body)
                if f:
                    if f.group(1):
                        fields[f.group(1)] = off
                    off += int(f.group(2))
            raise RecordsError(f'struct {name}: no endstruct')
    raise RecordsError(f'no struct {name} in asm/include/')


def _loc_field(rom: bytes, d: dict, field: str, rows: list[dict] | None = None) -> list[int]:
    """Every LocRom record's `field`: struct LocRom gives the base, the
    record size, which must be LocRom_RecSize, and the field's offset and
    width; the count is the records' survey row's size over the record
    size (as maps.derive_named reads them)."""
    base, offsets, size = _struct('LocRom')
    if size != d['LocRom_RecSize']:
        raise RecordsError(f'struct LocRom is {size} B, LocRom_RecSize {d["LocRom_RecSize"]}')
    start = f'${base >> 16:02X}:{base & 0xFFFF:04X}'
    if STRUCTS.get(start, (None,))[0] != 'LocRom':
        raise RecordsError(f'struct LocRom is at {start}, which is not its STRUCTS row')
    if rows is None:
        sys.path.insert(0, str(ROOT / 'tools'))
        import data_survey
        rows = data_survey.read_rows()
    row = next((r for r in rows if r['start'] == start), None)
    if row is None or int(row['size']) % size:
        raise RecordsError(f'no survey row of whole LocRom records at {start}')
    at, w = offsets[field], width(dict(_struct_fields('LocRom'))[field])
    return [int.from_bytes(rom[base - 0xC00000 + k * size + at:base - 0xC00000 + k * size + at + w], 'little')
            for k in range(int(row['size']) // size)]


def _loc_tilesets(rom: bytes, d: dict, code=None, rows: list[dict] | None = None) -> int:
    """Entries of LocGfx_Lists the locations name: 1 + the largest
    LocRom.Tileset12 other than LocRom_SetNone, over the LocRom records
    (_loc_field)."""
    return 1 + max(v for v in _loc_field(rom, d, 'Tileset12', rows) if v != d['LocRom_SetNone'])


def _loc_palettes(rom: bytes, d: dict, code=None, rows: list[dict] | None = None) -> int:
    """Rows of 15 colours in LocPal_Rom the locations name: 7 per entry,
    1 + the largest LocRom.Palette entries (LocRom's only reader of it is
    LocLoad_Unk7084)."""
    if d['LocPal_SetBytes'] != 7 * d['LocPal_RowBytes'] or d['LocPal_RowBytes'] != 30:
        return -1
    return 7 * (1 + max(_loc_field(rom, d, 'Palette', rows)))


def _bg_set_rows(path: Path = ROOT / 'asm' / 'bankD1' / 'bankD1.asm') -> int:
    """Rows of 16 colours BattleFx_LoadBgSet reaches: the source's
    BattleFx_BgSetPalOfs (one word per background set) + 3 rows."""
    lines = path.read_text().splitlines()
    try:
        i = lines.index('BattleFx_BgSetPalOfs:')
    except ValueError:
        raise RecordsError('bankD1.asm: no BattleFx_BgSetPalOfs') from None
    m = re.match(r'^\s+dw\s+([^;]*)', lines[i + 1])
    if not m:
        raise RecordsError('BattleFx_BgSetPalOfs: expected a dw line')
    ofs = [int(v.strip().lstrip('$'), 16) for v in m.group(1).split(',')]
    return (max(ofs) + 3 * 32) // 32



# ── Bounds from the readers' code ───────────────────────────────────────────
#
# For the rows in READERS the count is not taken from a comment: the reader
# is run (tools/absint.py, on the code the source assembles to) once for
# each of the 256 values of the index byte it is given, with the table's
# bytes known and everything else unknown (B too, unless a run says
# otherwise). Where the code did not clear or mask the index's high byte,
# the address is unknown and the run reads nothing from the table. Each
# value must read exactly its own record (value x the layout's record size,
# that many bytes), and the count is the values that read one: all of
# 0..count-1 (but `skip`), none above. Each run below says what it is given
# and why.

class _Reach:
    """A run per index value v: the routine (`entry` label), the RAM it is
    given (`ram(v, defines, labels)`, {address: byte}), ROM bytes it is given
    besides the row's (`known`, the same shape; `also`: (name, bytes) ranges
    from the ROM), its registers (`regs`; 'v' stands for the value), DP
    (`dp`, a define name or 0), where a path stops (`stop` labels;
    `after_load`: also after every LDA long,X of the table), the values
    that read no record (`skip`), and tools/absint.py's limits
    (`callee_steps`; `widen_after`, the visits of a branch before a loop's
    states are joined). `vary(defines)`: RAM bytes the index's value must
    not depend on (a high byte the code masks off): tools/absint.py knows a
    word only whole, so each value is run with them $00 and with them $FF,
    and both runs must read the same."""

    def __init__(self, entry, ram, known=None, regs=None, stop=(), after_load=False, skip=(), dp=0, also=(),
                 callee_steps=3000, widen_after=48, vary=None):
        self.entry, self.ram, self.known = entry, ram, known or (lambda v, d, L: {})
        self.regs, self.stop, self.after_load, self.skip = regs or {}, stop, after_load, set(skip)
        self.dp, self.also, self.callee_steps, self.widen_after = dp, also, callee_steps, widen_after
        self.vary = vary


def _w(d: dict, name: str, k: int = 0) -> int:
    """The WRAM address of RAM define `name` (+ k)."""
    return 0x7E0000 | (d[name] + k) & 0xFFFF


def _dp(d: dict, name: str, k: int = 0) -> int:
    """The address of direct-page define `name` (+ k) with DP = 0."""
    return 0x7E0000 | (d[name] + k) & 0xFF


_FX_OPERANDS = 0x7EF000       # scratch WRAM holding the three operand bytes a run of FxOpHalfPlane is given


def _enemy_act(kind: int, act_id: int, table: str) -> '_Reach':
    """BattleAct_LoadScript for an enemy caster (the first enemy slot, its
    Battler_Unk984D value 0) with Battle_ActKind `kind` and Battle_ActId
    `act_id`: its record (record 0 of `table`) holds v in every byte."""
    return _Reach('BattleAct_LoadScript', lambda v, d, L: {
        _w(d, 'Battle_ActKind'): kind, _w(d, 'Battle_ActCaster'): d['Battle_FirstEnemySlot'],
        _w(d, 'Battle_ActId'): act_id, _w(d, 'Battler_Unk984D', 2 * d['Battle_FirstEnemySlot']): 0,
        _w(d, 'Battler_Unk984D', 2 * d['Battle_FirstEnemySlot'] + 1): 0},
        known=lambda v, d, L: {L[table] + k: v for k in range(7)},
        regs={'b': 0}, stop=('BattleAct_LoadCommon',), after_load=True)


def _fx_gfx(other: str, size: int, stop: tuple = ()) -> '_Reach':
    """BattleCD_ConvertFxGfx with X = the set v and DP $67 =
    BattleCD_GfxPartTiles (what BattleCD_LoadFxGfx4 passes); the other of
    its two tables given too (`other`, `size` B)."""
    return _Reach('BattleCD_ConvertFxGfx', lambda v, d, L: {
        _dp(d, 'BattleCD_Tmp67'): d['BattleCD_GfxPartTiles'] & 0xFF,
        _dp(d, 'BattleCD_Tmp67', 1): d['BattleCD_GfxPartTiles'] >> 8},
        regs={'x': 'v'}, also=((other, size),), stop=stop, callee_steps=20000, widen_after=1000)


READERS: dict[str, list[_Reach]] = {
    # BattleFD_UnkB438 for enemy entry 0 (X and DP $02), its id byte in
    # Battler_UnkAF0A. B unknown: the TDC at the entry clears it.
    '$CC:4700': [_Reach('BattleFD_UnkB438', lambda v, d, L: {
        _w(d, 'Battler_UnkAF0A', d['Battle_FirstEnemySlot']): v, 0x7E0002: 0, 0x7E0003: 0}, regs={'x': 0})],
    # BattleSys_UnkD7C4 for action record 0, whose part number (byte 3 of
    # its BattleRom_UnkCC6FCB record) is v, the other bytes 0; stopped at
    # the end of the copy. B unknown: the TDC before the TAX clears it.
    # Part number $FF (Battle_EnemyPartNone) is skipped and reads nothing.
    '$CC:7AC9': [_Reach('BattleSys_UnkD7C4', lambda v, d, L: {_w(d, 'Battle_UnkB18C'): 0},
                        known=lambda v, d, L: {**{d['BattleRom_UnkCC6FCB'] - 1 + k: 0 for k in range(11)},
                                               d['BattleRom_UnkCC6FCB'] + 3: v},
                        stop=('BattleSys_CopyEffectBytes78', 'BattleSys_UnkD7C4_after_part'), skip=(0xFF,))],
    # BattleAct_LoadScript, kind 1 (Battle_ActId 0: EnemyAttackAct, 1:
    # EnemyAttack2Act) and kind 2 (EnemyTechAct). B = 0 at the entry, for
    # the dispatch's TAX (as BattleAct_BuildBattlerList leaves it; see the
    # loaders' banner); the index is the 16-bit read of Battle_ActObjIdx,
    # whose high byte the parameter block's clear at the entry zeroes.
    '$CD:666E': [_enemy_act(1, 0, 'BattleRom_EnemyAttackAct'), _enemy_act(1, 1, 'BattleRom_EnemyAttack2Act'),
                 _enemy_act(2, 0, 'BattleRom_EnemyTechAct')],
    # BattleCD_FxOpHalfPlane for channel 0 (DP $43), its register byte v,
    # the step and flags operands 0 (the angle = v + 0, a byte add). B
    # unknown: the TDC at the entry clears it.
    '$CE:F28E': [_Reach('BattleCD_FxOpHalfPlane', lambda v, d, L: {
        _dp(d, 'BattleCD_FxScriptPtr'): _FX_OPERANDS & 0xFF,
        _dp(d, 'BattleCD_FxScriptPtr', 1): _FX_OPERANDS >> 8 & 0xFF,
        _dp(d, 'BattleCD_FxScriptPtr', 2): _FX_OPERANDS >> 16,
        _dp(d, 'BattleFx_RecOfs'): 0, _dp(d, 'BattleFx_RecOfs', 1): 0,
        _FX_OPERANDS: 0, _FX_OPERANDS + 1: 0, _FX_OPERANDS + 2: 0,
        _w(d, 'Battle_FxChanReg'): v}, stop=('BattleCD_FxLineDeltas',))],
    # BattleCD_ConvertFxGfx for each set byte. That X is a byte rests on B
    # = 0 at BattleCD_LoadFxGfx4's 8-bit LDA / 16-bit TAX of
    # Battle_FxTileSet, which is ASSUMED, not traced: before the first part
    # BattleCD_WaitFrameRefresh runs the battle menu's refresh, before the
    # later ones BattleCD_QueueVramDma's waits.
    '$CF:A000': [_fx_gfx('BattleRom_FxGfxColours', 0x200)],
    '$CF:E000': [_fx_gfx('BattleRom_FxGfxLists', 0x4000, stop=('BattleCD_ConvertFxGfx_tile',))],   # (read before .tile)
    # Menu_SprLoad from .pointers (the definition is in Menu_SprScratch and
    # byte 0 is not $FF): byte 2 = v, byte 4 = 0 (no alternate palette) and
    # byte 5 = 0 (as the STZ before .pointers leaves it), byte 1 unknown;
    # byte 3, the high byte of the 16-bit read of byte 2, $00 and $FF (the
    # AND Eng_LowByteMask clears it: `vary`); A 8-bit = byte 0, B unknown;
    # DP = an object page. The
    # table's address is the word at MenuRom_E4Palettes (RomE4_PtrInit),
    # given from the ROM. Stopped at .palette (or .done).
    '$E4:2A00': [_Reach('Menu_SprLoad_pointers', lambda v, d, L: {
        _w(d, 'Menu_SprScratch', 2): v, _w(d, 'Menu_SprScratch', 4): 0, _w(d, 'Menu_SprScratch', 5): 0},
        regs={'a': 0, 'm': True, 'xf': True}, stop=('Menu_SprLoad_palette', 'Menu_SprLoad_done'), dp='Menu_SprPages',
        vary=lambda d: [_w(d, 'Menu_SprScratch', 3)],
        also=(('RomE4_PtrInit', 0x20),))],
}


def _code():
    """(image, emitted mask, labels) of the source's code: tools/events.py's
    code image (cached in build/events/)."""
    sys.path.insert(0, str(ROOT / 'tools'))
    import events
    return events.code_image(ROOT)


REACH_DIR = ROOT / 'build' / 'records-reach'      # the runs' results, by what they depend on


class _Seen(dict):
    """The defines, recording which are read."""

    def __init__(self, d: dict):
        super().__init__(d)
        self.seen: dict = {}

    def __getitem__(self, k):
        self.seen[k] = super().__getitem__(k)
        return self.seen[k]

    def get(self, k, default=None):
        return self[k] if k in self else default


def _reach_key(rom: bytes, d: dict, start: str, image: bytes, mask, labels: dict, values) -> str:
    """What the runs of row `start` depend on: this tool and tools/absint.py
    (READERS and the interpreter), the code image, the labels and defines,
    the ROM bytes given, the values run."""
    import hashlib
    h = hashlib.sha256()
    for f in ('records.py', 'absint.py', 'disasm.py'):
        h.update((ROOT / 'tools' / f).read_bytes())
    h.update(image + bytes(mask))
    used = _Seen(d)                             # only the defines the runs are given
    for r in READERS[start]:
        r.ram(0, used, labels)
        r.known(0, used, labels)
        for name in [r.dp] * isinstance(r.dp, str) + [n for n, _ in r.also]:
            used.get(name)
        if r.vary:
            r.vary(used)
    h.update(repr((sorted(used.seen.items()), sorted(labels.items()), start, list(values))).encode())
    lay = layout_for(start, 'palette' if start in PALETTES else 'table')
    bank, low = (int(x, 16) for x in start[1:].split(':'))
    o = (bank << 16 | low) - 0xC00000
    h.update(rom[o:o + (lay.count + 8) * lay.size])
    for r in READERS[start]:
        for name, n in r.also:
            a = (d[name] if name in d else labels.get(name, 0xC00000)) - 0xC00000
            h.update(rom[a:a + n])
    return h.hexdigest()


def reader_reads(rom: bytes, d: dict, start: str, code=None, values=range(256)) -> list[dict]:
    """Per READERS run of row `start`: {index value: the row offsets read}
    (a string where the run could not be followed). The results are kept
    in build/records-reach/ by a hash of everything they depend on (and
    of themselves: a file changed by hand is run again), but not for a
    `code` image passed in (the tests')."""
    import hashlib
    import json
    image, mask, labels = code if code is not None else _code()
    key = _reach_key(rom, d, start, image, mask, labels, values)
    cache = REACH_DIR / (start[1:].replace(':', '') + '.json')
    if code is None and cache.exists():
        try:
            saved = json.loads(cache.read_text())
            body = json.dumps(saved['runs'], sort_keys=True)
            if saved['key'] == key and saved['sha'] == hashlib.sha256(body.encode()).hexdigest():
                return [{int(v): x for v, x in run.items()} for run in saved['runs']]
        except (ValueError, KeyError, TypeError):
            pass
    out = _run_readers(rom, d, start, image, mask, labels, values)
    if code is None:
        runs = json.loads(json.dumps(out))         # (the values' keys as strings, as read back)
        body = json.dumps(runs, sort_keys=True)
        REACH_DIR.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps({'key': key, 'sha': hashlib.sha256(body.encode()).hexdigest(), 'runs': runs}))
    return out


def _run_readers(rom: bytes, d: dict, start: str, image: bytes, mask, labels: dict, values) -> list[dict]:
    sys.path.insert(0, str(ROOT / 'tools'))
    import absint
    import disasm
    bank, low = (int(x, 16) for x in start[1:].split(':'))
    table = bank << 16 | low
    lay = layout_for(start, 'palette' if start in PALETTES else 'table')
    span = (lay.count + 8) * lay.size          # reads past the count are seen too
    out = []
    for r in READERS[start]:
        try:
            stops = {labels[n] for n in r.stop}
            entry = labels[r.entry]
        except KeyError as err:
            raise RecordsError(f'{start}: no label {err} in the source') from None
        if r.after_load:
            op = bytes([0xBF, table & 0xFF, table >> 8 & 0xFF, table >> 16])
            k = image.find(op)
            while k >= 0:
                if all(mask[k:k + 4]):
                    b, lo = disasm.file_to_snes(k + 4)
                    stops.add(b << 16 | lo)
                k = image.find(op, k + 1)

        class Machine(absint.Machine):
            def step(self, s, base_depth):
                if s.pc in stops:
                    return ('stop', None)
                return super().step(s, base_depth)

        m = Machine(image, mask, max_steps=400000, callee_steps=r.callee_steps)
        m.widen_after = r.widen_after           # (a loop the run must follow to its end: no joining)
        given = {table + k: rom[table - 0xC00000 + k] for k in range(span)}
        others = set()
        for name, n in r.also:
            a = d[name] if name in d else labels[name]
            given.update({a + k: rom[a - 0xC00000 + k] for k in range(n)})
            others.update(range(a, a + n))
        got = {}
        for v in values:
            runs = []
            for fill in (0x00, 0xFF) if r.vary else (None,):
                s = absint.State()
                s.pc = entry
                regs = {'a': None, 'b': None, 'x': None, 'y': None, 'm': True, 'xf': False}
                regs.update({k: (v if x == 'v' else x) for k, x in r.regs.items()})
                s.a, s.b, s.x, s.y, s.m, s.xf = (regs[k] for k in ('a', 'b', 'x', 'y', 'm', 'xf'))
                s.d, s.db = (d[r.dp] if isinstance(r.dp, str) else r.dp), 0x7E
                s.c = s.z = s.n = s.v = None
                s.sp, s.spt, s.memt = [], [], {}
                s.mem = r.ram(v, d, labels)
                if fill is not None:
                    s.mem.update({a: fill for a in r.vary(d)})
                s.at = s.xt = s.yt = s.ft = absint.E
                s.depth = 0
                known = dict(given)
                known.update(r.known(v, d, labels))
                try:
                    m.run(s, known)
                except absint.Unresolved as err:
                    runs.append(str(err))
                    continue
                runs.append(sorted(a - table for a in m.reads if table <= a < table + span and a not in others))
            if any(x != runs[0] for x in runs):
                runs = ['the reads change with the bytes at ' + ', '.join(f'${a:06X}' for a in r.vary(d))
                        + ' ($00 or $FF), which do not fix the index']
            got[v] = runs[0]
        out.append(got)
    return out


def reader_count(rom: bytes, d: dict, start: str, code=None, values=range(256)) -> int:
    """The record count READERS' runs of row `start` give (see above);
    raises RecordsError where a value reads other than its record, or
    where values below the count read none (of `values`, those run)."""
    lay = layout_for(start, 'palette' if start in PALETTES else 'table')
    counts = []
    for r, got in zip(READERS[start], reader_reads(rom, d, start, code, values)):
        read = []
        for v, offs in sorted(got.items()):
            if isinstance(offs, str):
                raise RecordsError(f'{r.entry} with index {v} cannot be followed: {offs}')
            if offs and offs != list(range(v * lay.size, (v + 1) * lay.size)):
                raise RecordsError(f'{r.entry} with index {v} reads offsets {offs[0]}-{offs[-1]} '
                                   f'({len(offs)} B), not record {v} ({lay.size} B)')
            if offs:
                read.append(v)
        n = max(read) + 1 if read else 0
        missing = [v for v in values if v < n and v not in read and v not in r.skip]
        if missing or not read:
            raise RecordsError(f'{r.entry} reads no record for index {missing[0] if missing else 0} '
                               f'(the index\'s high byte not cleared?)')
        counts.append(n)
    if len(set(counts)) != 1:
        raise RecordsError(f'the runs of {start}\'s readers give {counts} records')
    return counts[0]


def _reader(start: str):
    return lambda rom, d, code=None: reader_count(rom, d, start, code)


# Row start -> (what, count(rom, defines, code)): the bound, re-derived by
# `check` (and the extraction) against the layout's count. Three kinds:
# the readers' own runs (READERS); a define the reader bounds the index by
# (Battle_LevelMax, SprRec_FirstNpc, Menu_SramUnk05F3Mask) or a register's
# width (the palette byte, an 8-bit WRMPYA operand), with the record size
# the defines give checked against the layout's; data (the object lists,
# LocRom.Tileset12).
DERIVED = {
    '$CE:8870': ('the records the object lists cover', lambda rom, d, code=None: (lambda se: (se[1] - se[0]) // 4)(
        obj_lists_extent(rom, d))),
    '$CC:4700': ('BattleFD_UnkB438 run for each id byte', _reader('$CC:4700')),
    '$CC:7AC9': ('BattleSys_UnkD7C4 run for each part number', _reader('$CC:7AC9')),
    '$CC:2632': ('levels 0-Battle_LevelMax', lambda rom, d, code=None: d['Battle_LevelMax'] + 1),
    '$CD:666E': ('BattleAct_LoadScript run for each object index', _reader('$CD:666E')),
    '$CE:F28E': ('BattleCD_FxOpHalfPlane run for each angle byte', _reader('$CE:F28E')),
    '$CF:A000': ('BattleCD_ConvertFxGfx run for each set byte (B = 0 assumed at the caller\'s TAX)',
                 _reader('$CF:A000')),
    '$CF:E000': ('BattleCD_ConvertFxGfx run for each set byte (B = 0 assumed at the caller\'s TAX)',
                 _reader('$CF:E000')),
    '$E4:0000': ('the palette byte\'s 256 values (an 8-bit WRMPYA operand) x Pal_ObjColorBytes, which must be '
                 'ObjPal_CopyCount + 1 and the layout\'s record size',
                 lambda rom, d, code=None: 256 if d['Pal_ObjColorBytes'] == d['ObjPal_CopyCount'] + 1
                 == layout_for('$E4:0000', 'palette').size else -1),
    '$E4:2A00': ('Menu_SprLoad run for each palette byte', _reader('$E4:2A00')),
    '$E4:F000': ('SprRec_FirstNpc + 256 records', lambda rom, d, code=None: d['SprRec_FirstNpc'] + 256),
    '$F6:1C00': ('1 + the largest LocRom.Tileset12', _loc_tilesets),
    '$F6:24C0': ('7 rows x (1 + the largest LocRom.Palette)', _loc_palettes),
    '$D0:FA00': ('rows up to the last BattleFx_BgSetPalOfs + 3 rows', lambda rom, d, code=None: _bg_set_rows()),
    '$FF:B210': ('8-colour rows up to style Pal_Row0SetMask x 16 + 2 + 30 B',
                 lambda rom, d, code=None: (d['Pal_Row0SetMask'] * 16 + 2 + 30) // 16
                 if d['Menu_WinStyleMask'] == d['Pal_Row0SetMask'] else -1),
    '$FF:D296': ('the location word (Menu_ReadSlotSummary: AND Menu_SramUnk05F3Mask) / 2',
                 lambda rom, d, code=None: (d['Menu_SramUnk05F3Mask'] + 1) // 2),
}


def derived_problems(rom: bytes, d: dict | None = None, pieces: list[dict] | None = None,
                     code=None) -> list[str]:
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
            n = count(rom, d, code)
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
