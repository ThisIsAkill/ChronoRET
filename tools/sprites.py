#!/usr/bin/env python3
"""
sprites.py — The sprite frame records (banks $DC, $DD, $DE, $E1, $E3) as
readable text, extracted from your own ROM into the ignored
build/assets/sprites/, and the assembler that rebuilds their exact bytes
(DATA_PLAN.md, the sprite frame records).

No frame is ever committed (README, "Legal"): extraction writes them, the
build assembles them back. What this tool holds is how the code reads them:

  The set pointers. BattleRom_SprFramesPtr ($E4:2300) holds 256 long
  pointers, one per sprite set. The field reads the same table (Field_E4Ptr1,
  whose low word Field_InitLoadState takes from RomE4_PtrInit word 1) and so
  does the menu (MenuRom_E4FramePtrs, the same word): Evt_LoadSpriteRec,
  Evt_Op82_InitWramSprite, Evt_Op83_InitEnemySprite and Menu_SprLoad each
  take a set number from byte 1 (SprRec_Frames) of a sprite record and the
  frame pointer from this table, and so does Battle_InitScene for an enemy
  (BattleRom_EnemySpr.FrameSet, byte 1 of its RomE4_EnemySprRec record).
  Not for a party member: Battle_InitScene's .pc_sprite loop takes the set
  number from Pc_CharId itself, and nothing writes that battler's
  Battler_FrameLayout. That agrees with the records only because
  RomE4_SprRec records 0-6 (Pc_NumChars) have SprRec_Frames 0-6 and size 0,
  so character n's set n is 40-B records whichever reader takes it
  (size_problems checks that).

  The record size. Byte 4 (SprRec_Size) bits 0-1 of the same record give
  the frame size, and every reader agrees on it:
    the field  Obj_BuildSpriteFrameStep sends size 0 / 1 / 2 to
               Obj_BuildFrame4 / 8 / 12 (Frame4_Bytes $28, Frame8_Bytes $50,
               Frame12_Bytes $78 per frame); size 3 is Spr_LoadLargeObj,
               96 tile words (SprBuf_Tiles) then 24 position pairs at
               LargeObj_LayoutOfs ($C0): 240 B. It reads that one record
               at Obj_FrameOfs and never steps by frame, and it never
               reads the size: "size 3" is inferred from its caller at
               $C0:47E9, which calls it only when the size is 3;
    the menu   Menu_SprLoad: Menu_SprTileCounts[size] (1, 2, 3, 6) units of
               Menu_SprFrameBytes (40, 80, 120, 240 B);
    battle     an enemy's layout is FieldBtlObj.Flags & 7, which is
               Obj_SprSize & ObjSpr_SizeMask (the record's size), and
               Battle_DrawBattlerFrameAnyLayout steps BattleRom_FrameBytes
               (40, 80, 120, 240 B for layouts 0-3) per frame id.
  Only the menu and battle step 240 B per frame of a size-3 set.
  A frame record holds N tile words (N = 16, 32, 48, 96: two bytes per
  8x8 tile; the builders copy tile (word & SprFrame_TileMask $07FF) and
  mirror it when bit 14, SprFrame_HFlip, is set; Battle_DrawBattlerFrame-
  AnyLayout writes a blank tile for tile 0; no reader tests bits 11-13 or
  15), then N / 4 position pairs: signed bytes OfsX, OfsY of each 16x16
  sprite (Obj_BuildFrame4 ..., Spr_LoadLargeObj: SprTileSrc.OfsX
  sign-extended and .OfsY; the battle and menu readers copy the same bytes).

  The extent is inferred. The records of a set start at its pointer;
  frame f is at pointer + f x size. The readers bound neither the number
  of frames nor a set's end, so the records are taken from each pointer up
  to the next pointer (sets that share an address are one run), in the
  five areas the pointers reach (AREAS). Every run between two pointers is
  a whole number of its set's records (derive refuses one that is not);
  the last run of an area is taken to end at its last non-zero byte,
  rounded up to a whole record (refused if that passes the area's end),
  and the zero bytes after it are probable padding. A run no sprite record
  gives a size (no reader of it found) is kept as bytes (the survey's
  sprite_layout rows that are not frame records).

The readable form (build/assets/sprites/<label>.spr):

  @sprframes LABEL $BB:AAAA SIZE      the piece: its label, start and size
  @set $BB:AAAA BYTES SETS            a run: its address, the record size
                                      (40, 80, 120 or 240) and the set
                                      numbers whose pointer is this address
  frame N                             a record, numbered from 0 in its run;
    TTT ...                           its N tile words, 16 per line: the
                                      tile number (3 hex digits), then h for
                                      bit 14 (mirrored), v for bit 15, ^n
                                      for bits 11-13 (= n), none of which a
                                      reader tests
    @ X,Y ...                         its N / 4 position pairs, signed

The runs follow each other with no gap; the assembler checks each address
and the record counts, and fails on anything else.

    python3 tools/sprites.py check      extract every frame-record piece from
                                        the ROM to text and assemble it back:
                                        byte-exact? (and the readers' record
                                        sizes and the runs, against the ROM)
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The areas the set pointers reach: SNES bank -> [start, end) offsets in the
# bank. $DE ends at its message tables ($DE:C000); $E1 starts after its
# packed sprite graphics, at its first set ($E1:E000).
AREAS = {0xDC: (0x0000, 0x10000), 0xDD: (0x0000, 0x10000), 0xDE: (0x0000, 0xC000),
         0xE1: (0xE000, 0x10000), 0xE3: (0x0000, 0x10000)}
CLASS_BYTES = (40, 80, 120, 240)        # by sprite record size bits 0-1
SET_COUNT = 256                         # BattleRom_SprFramesPtr entries
REC_TABLES = (('RomE4_SprRec', 'SprRec_Bytes', '$E4:F000'),
              ('RomE4_EnemySprRec', 'EvtSpr_EnemyRecBytes', '$E4:F600'))
FORMAT = 'frame records'                # a survey sprite_layout row in this form starts so
PIECE = 'sprframes'
ASSET_EXT = 'spr'
HEAD = ('; {label}: sprite frame records, extracted from your own ROM by tools/sprites.py (never commit it).',
        '; Per run: @set address, record size, the sets that point here; per frame its tile words',
        '; (TTT tile, h bit 14 mirrored, v bit 15, ^n bits 11-13), then @ its (x, y) position pairs.')
WORD = re.compile(r'^([0-7][0-9A-F]{2})(h?)(v?)(?:\^([1-7]))?$')
PAIR = re.compile(r'^(-?\d{1,3}),(-?\d{1,3})$')
ADDR = re.compile(r'^\$([C-F][0-9A-F]):([0-9A-F]{4})$')


class SpritesError(Exception):
    pass


def addr(offset: int) -> str:
    return f'${0xC0 + (offset >> 16):02X}:{offset & 0xFFFF:04X}'


def parse_addr(text: str, where: str) -> int:
    m = ADDR.match(text)
    if not m:
        raise SpritesError(f'{where}: bad address {text!r} (expected $BB:AAAA)')
    return (int(m.group(1), 16) - 0xC0) << 16 | int(m.group(2), 16)


# ── The tile words and position pairs ────────────────────────────────────

def word_text(v: int) -> str:
    hi = (v >> 11) & 7
    return f'{v & 0x7FF:03X}{"h" if v & 0x4000 else ""}{"v" if v & 0x8000 else ""}{f"^{hi}" if hi else ""}'


def word_value(t: str, where: str) -> int:
    m = WORD.match(t)
    if not m:
        raise SpritesError(f'{where}: bad tile word {t!r} (TTT[h][v][^n])')
    return (int(m.group(1), 16) | (0x4000 if m.group(2) else 0) | (0x8000 if m.group(3) else 0)
            | (int(m.group(4)) << 11 if m.group(4) else 0))


def _signed(b: int) -> int:
    return b - 256 if b & 0x80 else b


def render_frame(n: int, rec: bytes) -> list[str]:
    words = len(rec) * 2 // 5
    out = [f'frame {n}']
    for k in range(0, words, 16):
        out.append('  ' + ' '.join(word_text(rec[2 * j] | rec[2 * j + 1] << 8) for j in range(k, k + 16)))
    pos = rec[2 * words:]
    out.append('  @ ' + ' '.join(f'{_signed(pos[j])},{_signed(pos[j + 1])}' for j in range(0, len(pos), 2)))
    return out


# ── The runs, from the ROM ───────────────────────────────────────────────

def _row_size(start: str) -> int:
    sys.path.insert(0, str(ROOT / 'tools'))
    import data_survey
    for row in data_survey.read_rows():
        if row['start'] == start:
            return int(row['size'])
    raise SpritesError(f'symbols/data_survey.csv has no row at {start}')


def set_pointers(rom: bytes, d: dict) -> list[int]:
    t = d['BattleRom_SprFramesPtr'] - 0xC00000
    return [rom[t + 3 * i] | rom[t + 3 * i + 1] << 8 | rom[t + 3 * i + 2] << 16 for i in range(SET_COUNT)]


def set_classes(rom: bytes, d: dict, sizes: dict | None = None) -> dict[int, set[int]]:
    """{set: the record sizes its sprite records give it}: byte SprRec_Frames
    and SprRec_Size & ObjSpr_SizeMask of every whole record of RomE4_SprRec
    and RomE4_EnemySprRec (the survey rows' extents; `sizes` overrides)."""
    out: dict[int, set[int]] = {}
    for name, rec_name, start in REC_TABLES:
        base, rec = d[name] - 0xC00000, d[rec_name]
        size = sizes[name] if sizes else _row_size(start)
        for i in range(size // rec):
            r = rom[base + rec * i:base + rec * i + rec]
            out.setdefault(r[d['SprRec_Frames']], set()).add(CLASS_BYTES[r[d['SprRec_Size']] & d['ObjSpr_SizeMask']])
    return out


def derive(rom: bytes, d: dict | None = None, sizes: dict | None = None) -> list[dict]:
    """The runs, in address order: {'start', 'stop' (file offsets), 'bytes'
    (record size, None when no record gives one), 'sets'}, and the padding
    after each area's last run as {'start', 'stop', 'bytes': 0}."""
    if d is None:
        sys.path.insert(0, str(ROOT / 'tools'))
        import battle
        d = battle.defines(ROOT)
    ptrs = set_pointers(rom, d)
    classes = set_classes(rom, d, sizes)
    at: dict[int, list[int]] = {}
    for i, p in enumerate(ptrs):
        if p == 0:
            continue
        bank, ofs = p >> 16, p & 0xFFFF
        if bank not in AREAS or not AREAS[bank][0] <= ofs < AREAS[bank][1]:
            raise SpritesError(f'set {i} points at {addr(p - 0xC00000)}, outside the frame areas (AREAS)')
        at.setdefault(p - 0xC00000, []).append(i)
    runs = []
    for bank, (lo, hi) in sorted(AREAS.items()):
        base = (bank - 0xC0) << 16
        starts = sorted(a for a in at if a >> 16 == bank - 0xC0)
        if not starts or starts[0] != base + lo:
            raise SpritesError(f'no set starts the frame area at {addr(base + lo)}')
        for k, s in enumerate(starts):
            e = starts[k + 1] if k + 1 < len(starts) else base + hi
            got = set().union(*(classes.get(i, set()) for i in at[s]))
            if len(got) > 1:
                raise SpritesError(f'the sets {at[s]} at {addr(s)} are given record sizes {sorted(got)}')
            size = got.pop() if got else None
            if k + 1 == len(starts):
                used = len(rom[s:e].rstrip(b'\0'))
                if size:
                    used = -(-used // size) * size
                if s + used > e:
                    raise SpritesError(f'the last run of its area, at {addr(s)}, rounded up to whole {size}-B '
                                       f'records, ends at {addr(s + used)}, past the area\'s end {addr(e)}')
                runs.append({'start': s, 'stop': s + used, 'bytes': size, 'sets': at[s]})
                if s + used < e:
                    runs.append({'start': s + used, 'stop': e, 'bytes': 0, 'sets': []})
            else:
                if size and (e - s) % size:
                    raise SpritesError(f'the run at {addr(s)} ({e - s} B) is not a whole number of '
                                       f'{size}-B records')
                runs.append({'start': s, 'stop': e, 'bytes': size, 'sets': at[s]})
    return runs


def want_rows(runs: list[dict]) -> list[tuple[int, int, str]]:
    """The survey rows the runs make: (start, stop, 'frames' | 'unsized' |
    'padding'), consecutive runs of one kind merged."""
    out: list[tuple[int, int, str]] = []
    for r in runs:
        kind = 'padding' if r['bytes'] == 0 else 'frames' if r['bytes'] else 'unsized'
        if out and out[-1][2] == kind and out[-1][1] == r['start']:
            out[-1] = (out[-1][0], r['stop'], kind)
        else:
            out.append((r['start'], r['stop'], kind))
    return out


# ── The readable form ────────────────────────────────────────────────────

def render(label: str, start: int, data: bytes, runs: list[dict]) -> str:
    """The text of the piece at `start` (file offset) holding `data`, cut by
    `runs` (those inside it, with their record sizes)."""
    out = [h.format(label=label) for h in HEAD]
    out.append(f'@sprframes {label} {addr(start)} {len(data)}')
    pos = start
    for r in runs:
        if r['start'] != pos or not r['bytes'] or r['stop'] > start + len(data):
            raise SpritesError(f'{label}: the runs do not tile the piece at {addr(pos)}')
        out.append(f'@set {addr(r["start"])} {r["bytes"]} {",".join(str(i) for i in r["sets"])}')
        for n, k in enumerate(range(r['start'], r['stop'], r['bytes'])):
            out += render_frame(n, data[k - start:k - start + r['bytes']])
        pos = r['stop']
    if pos != start + len(data):
        raise SpritesError(f'{label}: the runs end at {addr(pos)}, the piece at {addr(start + len(data))}')
    return '\n'.join(out) + '\n'


def _lines(text: str) -> list[tuple[str, list[str]]]:
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        line = line.split(';', 1)[0].split()
        if line:
            out.append((str(n), line))
    return out


def assemble(text: str, label: str, start: int, size: int, name: str = '<spr>') -> bytes:
    """The bytes of a piece's text; `label`, `start` and `size` are the
    manifest's. Fails on a header that is not the piece's, a run that does
    not start where the one before ended, a record size that is not a
    reader's, a frame with the wrong number of words or pairs, or runs that
    do not end at the piece's end."""
    lines = _lines(text)
    if not lines or lines[0][1] != ['@sprframes', label, addr(start), str(size)]:
        raise SpritesError(f'{name}: the first line must be @sprframes {label} {addr(start)} {size}')
    out = bytearray()
    i, rec, frame = 1, 0, 0
    while i < len(lines):
        ln, f = lines[i]
        where = f'{name}:{ln}'
        if f[0] == '@set':
            if len(f) != 4 or not f[2].isdigit() or int(f[2]) not in CLASS_BYTES \
                    or not re.match(r'^\d+(,\d+)*$', f[3]):
                raise SpritesError(f'{where}: expected @set $BB:AAAA BYTES SETS, BYTES one of {CLASS_BYTES}')
            if rec and frame == 0:
                raise SpritesError(f'{where}: the run before has no frame')
            if parse_addr(f[1], where) != start + len(out):
                raise SpritesError(f'{where}: the run starts at {f[1]}, the bytes before end at '
                                   f'{addr(start + len(out))}')
            rec, frame = int(f[2]), 0
            i += 1
            continue
        if f != ['frame', str(frame)] or not rec:
            raise SpritesError(f'{where}: expected "frame {frame}"' + ('' if rec else ' after an @set'))
        words = rec * 2 // 5
        body = lines[i + 1:i + 2 + words // 16]
        if len(body) != words // 16 + 1 or any(len(b) != 16 for _, b in body[:-1]) or body[-1][1][:1] != ['@']:
            raise SpritesError(f'{where}: a {rec}-B frame is {words // 16} lines of 16 tile words, then @ and '
                               f'{words // 4} pairs')
        for bl, ws in body[:-1]:
            for w in ws:
                out += word_value(w, f'{name}:{bl}').to_bytes(2, 'little')
        pl, pairs = body[-1][0], body[-1][1][1:]
        if len(pairs) != words // 4:
            raise SpritesError(f'{name}:{pl}: {len(pairs)} pairs; a {rec}-B frame has {words // 4}')
        for p in pairs:
            m = PAIR.match(p)
            if not m or not all(-128 <= int(v) <= 127 for v in m.groups()):
                raise SpritesError(f'{name}:{pl}: bad position pair {p!r} (X,Y, each -128..127)')
            out += bytes(int(v) & 0xFF for v in m.groups())
        frame += 1
        i += len(body) + 1
    if rec and frame == 0:
        raise SpritesError(f'{name}: the last run has no frame')
    if len(out) != size:
        raise SpritesError(f'{name}: the runs make {len(out)} B, the piece is {size} B')
    return bytes(out)


def frames_of(text: str) -> int:
    return sum(1 for _, f in _lines(text) if f[0] == 'frame')


# ── The readers' record sizes, and the pieces ────────────────────────────

def _db(label: str, path: Path) -> list[int]:
    """The bytes of a `db` table in the source, after `label:`."""
    lines = path.read_text().splitlines()
    try:
        i = lines.index(f'{label}:')
    except ValueError:
        raise SpritesError(f'{path.name}: no {label}') from None
    out = []
    for line in lines[i + 1:]:
        m = re.match(r'^\s+db\s+(.*?)\s*(?:;.*)?$', line)
        if not m:
            break
        out += [int(v[1:], 16) if v.startswith('$') else int(v) for v in (x.strip() for x in m.group(1).split(','))]
    return out


def size_problems(rom: bytes, d: dict, root: Path = ROOT) -> list[str]:
    """Where the readers' record sizes are not CLASS_BYTES, the three
    readers do not use one pointer table, or a character's sprite record
    (RomE4_SprRec 0-6) is not the set and size Battle_InitScene assumes."""
    problems = []
    field = [d['Frame4_Bytes'], d['Frame8_Bytes'], d['Frame12_Bytes'],
             d['LargeObj_LayoutOfs'] + d['LargeObj_LayoutOfs'] // 4]
    if d['LargeObj_LayoutOfs'] != d['SprBuf_Tiles'] * d['Frame_TileWordBytes']:
        problems.append('Spr_LoadLargeObj: the position pairs (LargeObj_LayoutOfs) do not follow the '
                        'SprBuf_Tiles tile words')
    if tuple(field) != CLASS_BYTES:
        problems.append(f'the field builders read {field} B per frame, not {CLASS_BYTES}')
    c2 = root / 'asm' / 'bankC2' / 'bankC2.asm'
    counts, fbytes = _db('Menu_SprTileCounts', c2), _db('Menu_SprFrameBytes', c2)
    menu = [fbytes[c] if c < len(fbytes) else None for c in counts[:4]]
    if tuple(menu) != CLASS_BYTES or d['Menu_SprDefSizeMask'] != d['ObjSpr_SizeMask']:
        problems.append(f'Menu_SprLoad reads {menu} B per frame, not {CLASS_BYTES}')
    fb = d['BattleRom_FrameBytes'] - 0xC00000
    battle = [rom[fb + 2 * k] | rom[fb + 2 * k + 1] << 8 for k in range(4)]
    if tuple(battle) != CLASS_BYTES:
        problems.append(f'BattleRom_FrameBytes gives {battle} B for layouts 0-3, not {CLASS_BYTES}')
    init = d['RomE4_PtrInit'] - 0xC00000
    menu_ptrs = d['MenuRom_E4FramePtrs'] - 0xC00000
    want = d['BattleRom_SprFramesPtr'] & 0xFFFF
    if menu_ptrs != init + 2 or (rom[init + 2] | rom[init + 3] << 8) != want \
            or d['BattleRom_SprFramesPtr'] >> 16 != d['AnimRom'] >> 16:
        problems.append('Field_E4Ptr1 (RomE4_PtrInit word 1) and MenuRom_E4FramePtrs are not '
                        'BattleRom_SprFramesPtr')
    base, rec = d['RomE4_SprRec'] - 0xC00000, d['SprRec_Bytes']
    for i in range(d['Pc_NumChars']):
        r = rom[base + rec * i:base + rec * i + rec]
        if r[d['SprRec_Frames']] != i or r[d['SprRec_Size']] & d['ObjSpr_SizeMask']:
            problems.append(f'RomE4_SprRec record {i} is set {r[d["SprRec_Frames"]]}, size '
                            f'{r[d["SprRec_Size"]] & d["ObjSpr_SizeMask"]}: Battle_InitScene takes character '
                            f'{i}\'s set from Pc_CharId, so it must be set {i}, size 0')
    return problems


def is_piece_row(row: dict) -> bool:
    """A survey row that is frame records (no ROM needed)."""
    return row['kind'] == 'sprite_layout' and row['format'].startswith(FORMAT)


def runs_in(runs: list[dict], s: int, e: int) -> list[dict]:
    return [r for r in runs if s <= r['start'] < e]


def layout_problems(runs: list[dict], pieces: list[dict]) -> list[str]:
    """Where the manifest's pieces in the frame areas are not the rows the
    runs make (want_rows): sprframes pieces for the sized runs, extracted
    sprite_layout pieces for the unsized ones, fill for the padding."""
    problems = []
    want = want_rows(runs)
    piece_of = {'frames': PIECE, 'unsized': 'extracted', 'padding': 'fill'}
    areas = [(((b - 0xC0) << 16) + lo, ((b - 0xC0) << 16) + hi) for b, (lo, hi) in AREAS.items()]
    have = [(p['offset'], p['stop'], p['piece']) for p in pieces
            if any(lo <= p['offset'] < hi for lo, hi in areas)]
    got = [(s, e, piece_of[k]) for s, e, k in want]
    if have != got:
        miss = [x for x in got if x not in have] + [x for x in have if x not in got]
        s, e, k = miss[0]
        problems.append(f'the pieces in the frame areas are not the runs: first {addr(s)}-{addr(e - 1)} {k} '
                        f'(the runs want {", ".join(f"{addr(a)}-{addr(b - 1)} {c}" for a, b, c in got[:3])} ...)')
    return problems


def piece_text(p: dict, rom: bytes, runs: list[dict]) -> str:
    """The text of a sprframes piece of the manifest, checked to assemble
    back to the ROM's bytes."""
    s, e = p['offset'], p['stop']
    text = render(p['label'], s, rom[s:e], runs_in(runs, s, e))
    if assemble(text, p['label'], s, e - s, p['label']) != rom[s:e]:
        raise SpritesError(f'{p["label"]}: does not assemble back to its bytes')
    return text


def check(rom: bytes, quiet: bool = True) -> list[str]:
    sys.path.insert(0, str(ROOT / 'tools'))
    import battle
    import extract_data
    d = battle.defines(ROOT)
    problems = size_problems(rom, d)
    try:
        runs = derive(rom, d)
    except SpritesError as e:
        return problems + [str(e)]
    pieces = extract_data.read_manifest()
    problems += layout_problems(runs, pieces)
    for p in pieces:
        if p['piece'] != PIECE:
            continue
        try:
            piece_text(p, rom, runs)
        except SpritesError as err:
            problems.append(str(err))
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    try:
        rom = extract_data.read_rom()
        problems = check(rom, quiet=False)
    except (SpritesError, extract_data.DataError) as e:
        print(f'sprites: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'sprites: {p}', file=sys.stderr)
    if problems:
        return 1
    runs = derive(rom)
    sized = [r for r in runs if r['bytes']]
    frames = sum((r['stop'] - r['start']) // r['bytes'] for r in sized)
    unsized = [r for r in runs if r['bytes'] is None]
    print(f'OK: {frames:,} frame records in {len(sized)} runs ({sum(r["stop"] - r["start"] for r in sized):,} B) '
          f'convert to text and assemble back byte-exact; {len(unsized)} runs no sprite record sizes '
          f'({sum(r["stop"] - r["start"] for r in unsized):,} B) stay bytes')
    return 0


if __name__ == '__main__':
    sys.exit(main())
