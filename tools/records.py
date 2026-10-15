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

Where the layouts come from (no field is invented):

  structs    a ROM struct of asm/include/ (STRUCTS: the struct whose records
             fill the row); its fields are read from the struct itself: a
             1-byte field is u8, a 2-byte field u16, a longer one a byte per
             column (Name0, Name1, ...), an unnamed `skip` Unk_XX (its offset).
  arrays     the survey row's format, which states the element width the
             reader uses ("1 B per ...", "2 B per ...", "N u16 ...") and, for
             some, the fields of a small record ("2 B per tech id: target
             mode, flags"); ARRAYS below, one line each, with the reader.
             Where the format names a word as an address or offset in a bank
             the field is a pointer (ptr16): it is written as the label of the
             data piece it points at when it points at one's start.
  palettes   every `palette` row: SNES BGR555 words, written as 5-bit R, G,
             B and bit 15 (kept for an exact round trip). A palette row's
             record is a colour, or the colour set its format states.

A row's size must be a whole number of records (and, where a count is given,
exactly that many): the bytes past the reader's extent are survey rows of
their own (DATA_PLAN.md lists the corrections).

The readable form, one tab-separated file per piece:

  ; comment lines (what the table is, its layout and reader)
  Index  Field1  Field2 ...           the header: the layout's columns
  0      $1F     $0200   ...          one line per record: u8/u16/u24 as $hex,
                                      s8 as signed decimal, R/G/B as decimal
                                      0-31, ptr16 as a label or $hex

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
                    field, n = m.group(1) or f'Unk_{off:02X}', int(m.group(2))
                    if n == 1:
                        out.append((field, 'u8'))
                    elif n == 2:
                        out.append((field, 'u16'))
                    else:
                        out += [(f'{field}{k}', 'u8') for k in range(n)]
                    off += n
                raise RecordsError(f'struct {name}: no endstruct')
    raise RecordsError(f'no struct {name} in asm/include/')


# Row start -> the ROM struct whose records fill it (the struct's address is
# the row's, or the row holds the records a base-address struct indexes).
STRUCTS = {
    '$CC:1BEB': 'BattleRom_TechRec',
    '$CC:5E00': 'BattleRom_EnemyReward',
    '$CC:F3B6': 'BattleRom_FrameLayout',
    '$CC:F604': 'BattleRom_CursorSprite',
    '$CC:F6D4': 'BattleRom_FxOverlaySpr',
    '$CD:4000': 'BattleRom_PcAttackScript',
    '$CD:4015': 'BattleRom_PcAttackAct',
    '$CD:45A6': 'BattleRom_PcTechAct',
    '$CD:4926': 'BattleRom_EnemyAttackAct',
    '$CD:4F26': 'BattleRom_EnemyAttack2Act',
    '$CD:5526': 'BattleRom_EnemyTechAct',
    '$CD:5C26': 'BattleRom_Kind3Act',
    '$CE:8870': 'BattleRom_ActObjRec',        # the records BattleRom_ActObjRec ($CE:0000 base) indexes
    '$D1:50A2': 'BattleRom_ActObjInit',
    '$E4:F600': 'BattleRom_EnemySpr',
    '$F6:0000': 'LocRom',
}


def _f(*names: str, t: str = 'u8') -> list[tuple[str, str]]:
    return [(n, t) for n in names]


def _rep(n: int, *fields: tuple[str, str]) -> list[tuple[str, str]]:
    """n copies of the fields, numbered (Level0, Gain0, Level1, ...)."""
    return [(f'{name}{k}', t) for k in range(n) for name, t in fields]


# Row start -> (fields of one record, record count or None for the whole
# row). From the survey's format of each row (the reader's element width,
# and the fields where it names them); the comment names the reader.
ARRAYS: dict[str, tuple[list[tuple[str, str]], int | None]] = {
    '$C6:F560': (_f('Divisor', t='u16'), 32),                 # C2Scene zoom (M7A/M7B)
    '$C6:F5A0': (_f('Divisor', t='u16'), 32),                 # C2Scene zoom (M7C/M7D)
    '$C6:FD00': (_f('Header', t='ptr16:C6'), None),           # C2SceneRom_HeaderTable
    '$C7:0E11': (_rep(16, ('Sample', 'u16')), 83),            # AudioRom_SongSamples
    '$C7:241D': (_f('Echo', t='u16'), 83),                    # AudioRom_SongEcho
    '$CC:1ACB': (_f('TargetMode', 'Flags'), None),            # BattleRom_TechInfo
    '$CC:1BB5': (_f('TargetMode'), None),                     # BattleRom_ItemTargetMode
    '$CC:249F': (_f('Char0', 'Char1', 'Char2'), None),        # BattleRom_TechUserSets
    '$CC:253B': (_f('MpCost'), None),                         # BattleRom_TechMpCost
    '$CC:2583': (_f('AttackNum'), None),                      # BattleRom_PcAttackNum
    '$CC:258A': (_rep(4, ('Level', 'u8'), ('Gain', 'u8')), 7),    # BattleRom_HpGrowth
    '$CC:25C2': (_rep(4, ('Level', 'u8'), ('Gain', 'u8')), 7),    # BattleRom_MpGrowth
    '$CC:2632': (_f('Exp', t='u16'), None),                   # BattleRom_ExpToLevel
    '$CC:26FA': (_rep(8, ('Tp', 'u16')), 7),                  # BattleRom_TechTpCost
    '$CC:276A': (_f('FirstTech', 'TechCount'), 7),            # BattleRom_CharTechs
    '$CC:2953': (_f('Bit0', 'Bit1', 'Bit2'), 5),              # MenuRom_ComboNeeds
    '$CC:2963': (_f('Members'), None),                        # MenuRom_TechByteMembers
    '$CC:2983': (_f('Members'), 5),                           # MenuRom_ComboMembers
    '$CC:29D7': (_f('Boost', t='u16'), None),                 # MenuRom_ItemBoosts
    '$CC:2AB0': (_f('AreaRec', t='ptr16:CC'), None),          # BattleRom_AreaRecPtr
    '$CC:2BDC': (_f('Nibbles'), None),                        # BattleRom_TechWaitNib
    '$CC:2C6D': (_f('Items', t='ptr16:CC'), None),            # MenuRom_ShopLists
    '$CC:2D69': (_f('Value', t='u16'), None),                 # MenuRom_Char5Attack
    '$CC:86C9': (_f('TargetMode', 'Area'), None),             # BattleRom_EnemyTechTarget
    '$CC:F395': (_f('Offset', t='u16'), None),                # BattleRom_TechEntryBase
    '$CC:F39B': (_f('Offset', t='u16'), None),                # BattleRom_TechRowMapOffset
    '$CC:F3A1': (_f('Offset'), None),                         # BattleRom_TechEntryOffset
    '$CC:F40A': (_f('Bytes', t='u16'), 5),                    # BattleRom_FrameBytes
    '$CC:F414': (_f('FromDir'), None),                        # BattleRom_PathFromDir
    '$CC:F434': (_f('Facing'), None),                         # BattleRom_PathFacing
    '$CC:F494': (_f('DX', t='s8'), None),                     # BattleRom_PathStepDX
    '$CC:F4FC': (_f('Extra', t='s8'), 5),                     # BattleRom_FrameExtraCount
    '$CC:F505': (_f('Bytes'), 5),                             # BattleRom_LayoutSprBytes
    '$CC:F544': (_f('Interval'), None),                       # BattleRom_EnemyMoveInterval
    '$CC:F594': (_f('DY', t='s8'), None),                     # BattleRom_PathStepDY
    '$CC:F5FD': (_f('Frames'), 7),                            # BattleRom_FxOverlayPeriod
    '$CC:F63C': (_f('Flag'), 7),                              # BattleRom_PcPathAlways
    '$CC:F754': (_f('Offset', t='u16'), None),                # BattleRom_FxCycleList
    '$CC:F7C0': (_f('Offset', t='u16'), 32),                  # BattleRom_ActFrameBase
    '$CC:F820': (_f('Pixels'), 9),                            # BattleRom_Times16
    '$CC:F829': (_f('Offset'), 6),                            # BattleRom_HitSetOffset
    '$CC:F846': (_f('Offset'), 7),                            # BattleRom_CharTimes6
    '$CC:F84D': (_f('Address', t='u16'), None),               # BattleRom_SprTileListPtr
    '$CC:F8ED': (_f('Offset', t='u16'), None),                # BattleRom_StatsOffset
    '$CC:F903': (_f('Tile'), 10),                             # BattleRom_DigitTiles
    '$CC:F90D': (_f('Tile'), 10),                             # BattleRom_DigitTilesB
    '$CC:F917': (_f('Offset', t='u16'), None),                # BattleRom_SlotTimes16
    '$CC:F939': (_f('Offset'), 8),                            # BattleRom_EnemyRecOfs
    '$CC:F941': (_f('Address', t='u16'), None),               # BattleRom_FrameDestBase
    '$CC:F957': (_f('Source', t='u16'), 4),                   # BattleRom_GfxStepSrcA
    '$CC:F95F': (_f('Source', t='u16'), 4),                   # BattleRom_GfxStepSrcB
    '$CC:F967': (_f('Vram', t='u16'), 4),                     # BattleRom_GfxStepVramA
    '$CC:F96F': (_f('Vram', t='u16'), 4),                     # BattleRom_GfxStepVramB
    '$CC:F977': (_f('Bytes', t='u16'), 4),                    # BattleRom_GfxStepSizeA
    '$CC:F97F': (_f('Bytes', t='u16'), 4),                    # BattleRom_GfxStepSizeB
    '$CC:F987': (_f('Source', t='u16'), None),                # BattleRom_FrameDmaSrcA
    '$CC:F99D': (_f('Source', t='u16'), None),                # BattleRom_FrameDmaSrcB
    '$CC:F9B3': (_f('Vram', t='u16'), None),                  # BattleRom_FrameDmaVramA
    '$CC:F9C9': (_f('Vram', t='u16'), None),                  # BattleRom_FrameDmaVramB
    '$CC:F9DF': (_f('Bytes', t='u16'), 5),                    # BattleRom_FrameDmaSizeA
    '$CC:F9E9': (_f('Bytes', t='u16'), 5),                    # BattleRom_FrameDmaSizeB
    '$CC:FA23': (_f('Offset', t='u16'), 3),                   # BattleRom_NameAttrL1
    '$CC:FA29': (_f('Offset', t='u16'), 3),                   # BattleRom_NameAttrL02
    '$CC:FA2F': (_f('Offset', t='u16'), 3),                   # BattleRom_HpCellL0
    '$CC:FA35': (_f('Offset', t='u16'), 3),                   # BattleRom_HpCellL1
    '$CC:FA3B': (_f('Offset', t='u16'), 3),                   # BattleRom_HpCellL2
    '$CC:FADD': (_f('Offset', t='u16'), None),                # BattleRom_MenuCursorCell
    '$CC:FAE3': (_f('Offset', t='u16'), None),                # BattleRom_TechCursorCell
    '$CC:FAE9': (_f('Offset', t='u16'), None),                # BattleRom_ItemCursorCell
    '$CC:FAF0': (_f('Offset'), None),                         # BattleRom_CmdOffset
    '$CC:FAF3': (_f('Tile', 'Attr'), 44),                     # BattleRom_SprRecInit
    '$CC:FB6F': (_f('Square'), 16),                           # BattleRom_Squares
    '$CC:FB7F': (_f('WeightA', 'WeightB'), 7),                # BattleRom_ActLerpWeights
    '$CC:FB91': (_f('Kind'), None),                           # BattleRom_EnemyAnimKind
    '$CC:FBAB': (_f('Mover'), None),                          # BattleRom_EnemyMover
    '$CC:FBC8': (_f('SlotA', 'SlotB'), 3),                    # BattleRom_PcPartners
    '$CC:FBCE': (_f('Value'), None),                          # BattleRom_Div5
    '$CC:FC1E': (_f('Offset', t='u16'), 7),                   # BattleRom_CharRecOffset
    '$CD:64B0': (_f('ObjRec', t='ptr16:CE'), None),           # BattleRom_PcAttackObjs
    '$CD:656E': (_f('ObjRec', t='ptr16:CE'), None),           # BattleRom_TechObjs
    '$CD:666E': (_f('ObjRec', t='ptr16:CE'), None),           # BattleRom_EnemyActObjs
    '$CD:686E': (_f('PalStep', t='ptr16:CD'), 95),            # BattleRom_PcAttackPals
    '$CD:692C': (_f('PalStep', t='ptr16:CD'), None),          # BattleRom_PcTechPals
    '$CD:6A2C': (_f('PalStep', t='ptr16:CD'), 256),           # BattleRom_EnemyActPals
    '$CD:6C2C': (_f('PalStep', t='ptr16:CD'), 96),            # BattleRom_Kind3Pals
    '$CD:6CEC': (_f('Colours'), None),                        # BattleRom_WeaponColourIdx
    '$CD:6D4C': (_f('Sound'), None),                          # BattleRom_PcAttackSfxA
    '$CD:6DAC': (_f('Sound'), None),                          # BattleRom_PcAttackSfxB
    '$CE:0000': (_f('Subscript', t='ptr16:CE'), 128),         # BattleRom_ActSubscripts
    '$CE:EFEA': (_f('Step'), 8),                              # BattleRom_DissolvePhaseStep
    '$CE:EFF2': (_f('Vram', t='u16'), 4),                     # BattleRom_FxTileVram
    '$CE:EFFA': (_f('Byte0'), 2),                             # BattleRom_FxRecByte0
    '$CE:F03E': (_f('Mask'), 8),                              # BattleRom_FxBitMask
    '$CE:F046': (_f('Offset'), None),                         # BattleRom_FxColumnOfs
    '$CE:F146': (_f('Value', t='u16'), 8),                    # BattleRom_Op80PairB
    '$CE:F156': (_f('Bytes', t='u16'), None),                 # BattleRom_LayoutFrameBytes
    '$CE:F166': (_f('Address', t='u16'), None),               # BattleRom_SlotFrameBuf
    '$CE:F17C': (_f('Vram', t='u16'), None),                  # BattleRom_SlotFrameVram
    '$CE:F1C2': (_f('Mask', t='u16'), 8),                     # BattleRom_DissolveMask
    '$CE:F24E': (_f('Offset', t='u16'), None),                # BattleRom_HdmaSetOfs
    '$CE:F28E': (_f('X', 'Y'), 256),                          # BattleRom_HalfPlaneEdge
    '$CE:F48E': (_f('Sine'), 256),                            # BattleRom_AbsSine
    '$CF:8000': (_rep(64, ('Tile', 'u16')), None),            # BattleRom_FxTileLists
    '$CF:A000': (_rep(32, ('Tile', 'u16')), None),            # BattleRom_FxGfxLists
    '$CF:E000': (_f('Colours', t='u16'), None),               # BattleRom_FxGfxColours
    '$D1:5E10': (_f('Lift', t='s8'), None),                   # BattleRom_HitNumBounce
    '$D1:5E49': (_f('Lift', t='s8'), None),                   # BattleRom_HitNumBounceAlt
    '$D1:5F42': (_f('Frame'), None),                          # BattleRom_PcKoFrame
    '$E1:DE80': (_f('Flag'), None),                           # BattleRom_UnkE1DE80
    '$E4:2600': (_f('Offset', t='u16'), 256),                 # BattleRom_SprAnimFrames
    '$E4:2800': (_f('Offset', t='u16'), 256),                 # BattleRom_SprAnimDurs
    '$E4:FFE0': (_f('Low', t='u16'), 7),                      # RomE4_PtrInit
    '$E5:0000': (_f('Offset', t='u16'), 513),                 # ExitRom_LocOfs
    '$F5:F000': (_f('Offset', t='u16'), 513),                 # TreasureRom_LocOfs
    '$F6:1C00': (_rep(8, ('Pack', 'u8')), 64),                # LocGfx_Lists
    '$FD:A849': (_f('Address', t='u16'), 3),                  # BattleRom_CmdPtr
    '$FD:A89D': (_f('FirstTech'), 8),                         # BattleRom_CharFirstTech
    '$FF:C9AC': (_rep(10, ('Char', 'u8')), 8),                # MenuRom_NameChars
    '$FF:CE70': (_f('Tile'), 8),                              # MenuRom_PortraitTiles
    '$FF:CE78': (_f('Colours', t='ptr16:FF'), 8),             # MenuRom_PortraitPals
    '$FF:CE88': (_f('Tile', t='u16'), None),                  # MenuRom_CharIconTiles
    '$FF:CE92': (_f('Colours', t='ptr16:FF'), None),          # MenuRom_CharIconPals
    '$FF:CF0E': (_f('Table', t='ptr16:CC'), 5),               # MenuRom_ItemTablesA
    '$FF:CF18': (_f('RecSize'), 5),                           # MenuRom_ItemRecSizesA
    '$FF:CF1D': (_f('Table', t='ptr16:CC'), 5),               # MenuRom_ItemTablesB
    '$FF:CF27': (_f('RecSize'), None),                        # MenuRom_ItemRecSizesB
    '$FF:D554': (_f('Tile', t='u16'), 7),                     # MenuRom_ButtonLetters
    '$FF:D562': (_f('Tile', t='u16'), 12),                    # MenuRom_CfgIcons
}

# Palette rows whose colours come in sets (the format's record); others are
# lists of single colours. Row start -> (colours per record, count or None).
PALETTE_SETS = {
    '$D1:4100': (3, None),          # 6 B per colour set (BattleAct_OpLoadPalEntry)
    '$D1:4400': (7, None),          # 14 B per colour set
    '$D1:4B00': (3, None),          # BattleRom_WeaponColours: 6 B per record
    '$D1:4D90': (12, None),         # BattleRom_SpecialPals: 24 B per entry
    '$D1:6000': (4, None),          # BattleRom_FxColours: 8 B per colour set
    '$F6:24C0': (105, 88),          # LocPal_Rom: 88 x $D2 B
    '$FF:B210': (8, None),          # FieldRom_PalRow0Sets: sets 16 B apart
    '$FF:CC84': (16, None),         # MenuRom_SlotIconPals: 16 colours per character
}
# Palette rows whose reader copies a fixed number of colours (the format's
# "N colours -> $AA-$BB"): the row holds exactly those.
PALETTE_COUNTS = {
    '$FF:9C78': 4, '$FF:CB9C': 4, '$FF:CBC4': 8, '$FF:CC34': 8, '$FF:CE04': 8,
    '$FF:CE30': 16, '$D1:38F2': 3,
}
# Palette rows not structured (their colours and other words are not split yet).
PALETTE_SKIP = {'$E4:2A00'}


class Layout:
    def __init__(self, fields: list[tuple[str, str]], count: int | None, source: str):
        self.fields = fields
        self.count = count
        self.source = source
        self.size = sum(WIDTHS[t.split(':')[0]] for _, t in fields)

    def columns(self) -> list[str]:
        out = []
        for name, t in self.fields:
            out += [f'{name}R', f'{name}G', f'{name}B', f'{name}Bit15'] if t == 'colour' else [name]
        return out


def layout_for(start: str, kind: str) -> Layout | None:
    """The layout of the survey row at `start` (of `kind`), or None when it
    is not structured."""
    if start in STRUCTS:
        return Layout(_struct_fields(STRUCTS[start]), None, f'struct {STRUCTS[start]} (asm/include/)')
    if start in ARRAYS:
        fields, count = ARRAYS[start]
        return Layout(fields, count, 'the survey row\'s format (the reader\'s element width)')
    if kind == 'palette' and start not in PALETTE_SKIP:
        per, count = PALETTE_SETS.get(start, (1, PALETTE_COUNTS.get(start)))
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
            w = WIDTHS[t.split(':')[0]]
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
            w = WIDTHS[kind]
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
    back to the ROM's bytes (raises RecordsError otherwise)."""
    labels, addresses = piece_labels(pieces)
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
    problems = []
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
