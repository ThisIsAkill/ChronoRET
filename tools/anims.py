#!/usr/bin/env python3
"""
anims.py — The sprite animation lists of bank $E4 (the frame-id lists at
$E4:3000 and the duration lists at $E4:A800) as readable text, extracted
from your own ROM into the ignored build/assets/anims/, and the assembler
that rebuilds their exact bytes (DATA_PLAN.md, the animation lists).

No list is ever committed (README, "Legal"): extraction writes them, the
build assembles them back. What this tool holds is how the code reads them:

  The offsets. BattleRom_SprAnimFrames ($E4:2600) and BattleRom_SprAnimDurs
  ($E4:2800) hold one word per animation: the bank-$E4 offset of its
  frame-id list and of its duration list. The field reads them through
  Field_E4Ptr2 / Field_E4Ptr3 (RomE4_PtrInit words 2 and 3), the menu
  through MenuRom_E4AnimFrames / MenuRom_E4AnimTimes (the same words), and
  battle by name; each takes the animation number from byte 3
  (SprRec_Anim) of a sprite record.

  The frame-id lists. Every reader takes the size of a facing's block
  from the next animation's offset: Evt_LoadSpriteRec, Battle_InitScene
  and Menu_SprLoad all compute (next entry - this entry) / 4, the
  stride (Obj_AnimFacingStride, Battler_FacingStride, .AnimLen). Facing
  f's block starts at the offset + f x stride, and row r of it at + r x 4:
  Obj_AnimFrameLookup reads offset + facing x stride + row x 4 + column,
  Battle_TickPcSlots the same with AnimId x 4, Menu_SprAnimate with
  4 x anim + Dir x AnimLen. A row's entry $FF (Anim_EndMarker) ends it.
  So animation k's list is exactly its four facing blocks, offset k to
  offset k + 1: the extent is the readers'.

  The duration lists. Row r of animation k's durations is at its offset
  + r x 4 (Obj_AnimTickAndQueue: Obj_AnimTimeTbl + row x 4 + column;
  Battle_TickPcSlots: AnimDurBase + AnimId x 4; Menu_SprAnimate:
  .AnimTimes + 4 x anim); a duration of 0 ends the row. No reader bounds
  the number of rows, so a list is taken up to the next animation's
  offset (inferred, as the survey notes).

  The end. The lists run in order from RomE4_PtrInit words 5 ($3000) and
  6 ($A800), the offsets the first animation names. The last animation
  with an extent is the one before the first whose next offset is lower
  (animation 193's next entry is 0: the readers' stride for it is no
  size). What follows the last list is kept apart: the bytes up to the
  last non-zero one are a row of their own (no reader gives them an
  extent), the zeros after them padding up to the next table.

The readable forms (build/assets/anims/):

  <label>.anf   @animframes LABEL $BB:AAAA SIZE, then per animation:
                  @anim K $BB:AAAA stride S
                  facing F            (0-3), then its S bytes as rows of
                    00 01 02 FF        four hex bytes (the last row shorter
                                       when S is not a multiple of 4)
  <label>.ant   @animtimes LABEL $BB:AAAA SIZE, then per animation:
                  @anim K $BB:AAAA bytes N
                    08 08 10 00        its N bytes as rows of four

The animations follow each other with no gap, numbered from 0; the
assembler checks each address and size and fails on anything else.

    python3 tools/anims.py check        extract both lists from the ROM to
                                        text and assemble them back:
                                        byte-exact? (and the offsets, the
                                        extent and the pieces, against the
                                        ROM)
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FACINGS = 4
ROW = 4
COUNT = 256                         # entries of each offset table
# piece -> (the offset table, the RomE4_PtrInit word of the first list, the table after the area)
KINDS = {'animframes': ('BattleRom_SprAnimFrames', 5, 'animtimes'),
         'animtimes': ('BattleRom_SprAnimDurs', 6, None)}
ASSET_EXT = {'animframes': 'anf', 'animtimes': 'ant'}
ASSET_DIR = 'anims'
OUT = 'anims'                           # build/anims/<label>.bin
INCBIN_NOTE = {'animframes': 'sprite animation frame-id lists', 'animtimes': 'sprite animation duration lists'}
FORMAT = {'animframes': 'animation frame-id lists:', 'animtimes': 'animation duration lists:'}
HEAD = ('; {label}: sprite animation {what}, extracted from your own ROM by tools/anims.py (never commit it).',)
ADDR = re.compile(r'^\$([C-F][0-9A-F]):([0-9A-F]{4})$')
BYTE = re.compile(r'^[0-9A-F]{2}$')


class AnimsError(Exception):
    pass


ERROR = AnimsError


def addr(offset: int) -> str:
    return f'${0xC0 + (offset >> 16):02X}:{offset & 0xFFFF:04X}'


def parse_addr(text: str, where: str) -> int:
    m = ADDR.match(text)
    if not m:
        raise AnimsError(f'{where}: bad address {text!r} (expected $BB:AAAA)')
    return (int(m.group(1), 16) - 0xC0) << 16 | int(m.group(2), 16)


def _word(rom: bytes, ofs: int) -> int:
    return rom[ofs] | rom[ofs + 1] << 8


# ── The lists, from the ROM ──────────────────────────────────────────────

def offsets(rom: bytes, d: dict, kind: str) -> list[int]:
    t = d[KINDS[kind][0]] - 0xC00000
    return [_word(rom, t + 2 * k) for k in range(COUNT)]


def derive(rom: bytes, d: dict | None = None) -> dict[str, dict]:
    """{piece: {'lists': [(k, start, stop)] (file offsets), 'start', 'stop'
    (the lists' area), 'end' (the end of the area: the next table),
    'rest' (the end of the bytes after the lists up to the last non-zero
    one)}} for both kinds."""
    if d is None:
        sys.path.insert(0, str(ROOT / 'tools'))
        import battle
        d = battle.defines(ROOT)
    bank = (d['AnimRom'] - 0xC00000) & 0xFF0000
    init = d['RomE4_PtrInit'] - 0xC00000
    out: dict[str, dict] = {}
    count = None
    for kind, (_, word, _) in KINDS.items():
        offs = offsets(rom, d, kind)
        base = _word(rom, init + 2 * word)
        if offs[0] != base:
            raise AnimsError(f'{kind}: animation 0\'s offset is ${offs[0]:04X}, RomE4_PtrInit word {word} '
                             f'${base:04X}')
        n = next((k for k in range(COUNT - 1) if offs[k + 1] < offs[k]), COUNT - 1)
        if count is not None and n != count:
            raise AnimsError(f'the frame lists have an extent for {count} animations, the duration lists for {n}')
        count = n
        lists = [(k, bank + offs[k], bank + offs[k + 1]) for k in range(n)]
        if kind == 'animframes':
            bad = [k for k, s, e in lists if (e - s) % FACINGS]
            if bad:
                raise AnimsError(f'animation {bad[0]}\'s frame-id list is not four whole facing blocks')
        out[kind] = {'lists': lists, 'start': bank + base, 'stop': bank + offs[n]}
    out['animframes']['end'] = out['animtimes']['start']
    out['animtimes']['end'] = d['RomE4_SprRec'] - 0xC00000
    for kind, v in out.items():
        if v['stop'] > v['end']:
            raise AnimsError(f'{kind}: the lists run to {addr(v["stop"])}, past the next table at {addr(v["end"])}')
        v['rest'] = v['stop'] + len(rom[v['stop']:v['end']].rstrip(b'\0'))
    return out


def want_rows(lists: dict[str, dict]) -> list[tuple[int, int, str]]:
    """The survey rows the lists make: (start, stop, piece kind or
    'extracted' or 'fill'), in address order."""
    out = []
    for kind in KINDS:
        v = lists[kind]
        out.append((v['start'], v['stop'], kind))
        if v['rest'] > v['stop']:
            out.append((v['stop'], v['rest'], 'extracted'))
        if v['end'] > v['rest']:
            out.append((v['rest'], v['end'], 'fill'))
    return out


# ── The readable forms ───────────────────────────────────────────────────

def _rows(data: bytes) -> list[str]:
    return ['  ' + ' '.join(f'{b:02X}' for b in data[k:k + ROW]) for k in range(0, len(data), ROW)]


def render(kind: str, label: str, start: int, data: bytes, lists: list[tuple[int, int, int]]) -> str:
    what = 'frame-id lists' if kind == 'animframes' else 'duration lists'
    out = [h.format(label=label, what=what) for h in HEAD]
    out.append(f'@{kind} {label} {addr(start)} {len(data)}')
    pos = start
    for k, s, e in lists:
        if s != pos:
            raise AnimsError(f'{label}: the lists do not tile the piece at {addr(pos)}')
        body = data[s - start:e - start]
        if kind == 'animframes':
            stride = len(body) // FACINGS
            out.append(f'@anim {k} {addr(s)} stride {stride}')
            for f in range(FACINGS):
                out.append(f'facing {f}')
                out += _rows(body[f * stride:(f + 1) * stride])
        else:
            out.append(f'@anim {k} {addr(s)} bytes {len(body)}')
            out += _rows(body)
        pos = e
    if pos != start + len(data):
        raise AnimsError(f'{label}: the lists end at {addr(pos)}, the piece at {addr(start + len(data))}')
    return '\n'.join(out) + '\n'


def _lines(text: str) -> list[tuple[str, list[str]]]:
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        line = line.split(';', 1)[0].split()
        if line:
            out.append((str(n), line))
    return out


def _take(lines: list, i: int, n: int, name: str) -> tuple[bytes, int]:
    """n bytes in rows of four from lines[i:], and the next line index."""
    out = bytearray()
    while len(out) < n:
        if i >= len(lines) or not BYTE.match(lines[i][1][0]):
            raise AnimsError(f'{name}:{lines[i][0] if i < len(lines) else "end"}: expected {n - len(out)} more '
                             f'byte(s) in rows of {ROW}')
        ln, row = lines[i]
        want = min(ROW, n - len(out))
        if len(row) != want or not all(BYTE.match(b) for b in row):
            raise AnimsError(f'{name}:{ln}: a row of {want} hex byte(s) (rows of {ROW})')
        out += bytes(int(b, 16) for b in row)
        i += 1
    return bytes(out), i


def assemble(kind: str, text: str, label: str, start: int, size: int, name: str = '<anim>') -> bytes:
    lines = _lines(text)
    if not lines or lines[0][1] != [f'@{kind}', label, addr(start), str(size)]:
        raise AnimsError(f'{name}: the first line must be @{kind} {label} {addr(start)} {size}')
    out = bytearray()
    i, k = 1, 0
    word = 'stride' if kind == 'animframes' else 'bytes'
    while i < len(lines):
        ln, f = lines[i]
        where = f'{name}:{ln}'
        if len(f) != 5 or f[0] != '@anim' or f[3] != word or not f[4].isdigit():
            raise AnimsError(f'{where}: expected @anim {k} $BB:AAAA {word} N')
        if f[1] != str(k):
            raise AnimsError(f'{where}: animation {f[1]}, expected {k}')
        if parse_addr(f[2], where) != start + len(out):
            raise AnimsError(f'{where}: animation {k} starts at {f[2]}, the bytes before end at '
                             f'{addr(start + len(out))}')
        n = int(f[4])
        i += 1
        if kind == 'animframes':
            for facing in range(FACINGS):
                if i >= len(lines) or lines[i][1] != ['facing', str(facing)]:
                    raise AnimsError(f'{name}:{lines[i][0] if i < len(lines) else "end"}: expected "facing {facing}"')
                block, i = _take(lines, i + 1, n, name)
                out += block
        else:
            block, i = _take(lines, i, n, name)
            out += block
        k += 1
    if len(out) != size:
        raise AnimsError(f'{name}: the lists make {len(out)} B, the piece is {size} B')
    return bytes(out)


# ── The readers, the pieces ──────────────────────────────────────────────

def reader_problems(rom: bytes, d: dict) -> list[str]:
    """Where the field and menu do not read the two offset tables
    (RomE4_PtrInit words 2 and 3, MenuRom_E4AnimFrames / AnimTimes)."""
    problems = []
    init = d['RomE4_PtrInit'] - 0xC00000
    for kind, (table, _, _) in KINDS.items():
        word = 2 if kind == 'animframes' else 3
        menu = d['MenuRom_E4AnimFrames' if kind == 'animframes' else 'MenuRom_E4AnimTimes'] - 0xC00000
        if _word(rom, init + 2 * word) != d[table] & 0xFFFF or menu != init + 2 * word \
                or d[table] >> 16 != d['AnimRom'] >> 16:
            problems.append(f'Field_E4Ptr{word} (RomE4_PtrInit word {word}) and the menu\'s word are not {table}')
    return problems


def is_piece_row(row: dict) -> str | None:
    """The piece kind of a survey row (no ROM needed), or None."""
    for kind, prefix in FORMAT.items():
        if row['kind'] == 'table' and row['format'].startswith(prefix):
            return kind
    return None


def layout_problems(lists: dict[str, dict], pieces: list[dict]) -> list[str]:
    want = want_rows(lists)
    lo, hi = want[0][0], want[-1][1]
    have = [(p['offset'], p['stop'], p['piece']) for p in pieces if lo <= p['offset'] < hi]
    if have != want:
        miss = [x for x in want if x not in have] + [x for x in have if x not in want]
        s, e, k = miss[0]
        return [f'the pieces of the animation lists are not the lists: first {addr(s)}-{addr(e - 1)} {k} '
                f'(the lists want {", ".join(f"{addr(a)}-{addr(b - 1)} {c}" for a, b, c in want)})']
    return []


def piece_text(p: dict, rom: bytes, lists: dict[str, dict]) -> str:
    """The text of an animframes / animtimes piece, checked to assemble
    back to the ROM's bytes."""
    kind, s, e = p['piece'], p['offset'], p['stop']
    text = render(kind, p['label'], s, rom[s:e], lists[kind]['lists'])
    if assemble(kind, text, p['label'], s, e - s, p['label']) != rom[s:e]:
        raise AnimsError(f'{p["label"]}: does not assemble back to its bytes')
    return text


def extract_texts(rom: bytes, pieces: list[dict], d: dict | None = None) -> tuple[dict[str, str], list[str]]:
    """({label: text} of every piece of KINDS, the problems): the readers'
    tables and the pieces are checked against the lists first."""
    if not any(p['piece'] in KINDS for p in pieces):
        return {}, []
    if d is None:
        sys.path.insert(0, str(ROOT / 'tools'))
        import battle
        d = battle.defines(ROOT)
    problems = reader_problems(rom, d)
    try:
        lists = derive(rom, d)
    except AnimsError as err:
        return {}, problems + [f'anims: {err}']
    problems += layout_problems(lists, pieces)
    if problems:
        return {}, problems
    texts = {}
    for p in pieces:
        if p['piece'] in KINDS:
            try:
                texts[p['label']] = piece_text(p, rom, lists)
            except AnimsError as err:
                problems.append(str(err))
    return texts, problems


def assemble_piece(p: dict, text: str) -> bytes:
    return assemble(p['piece'], text, p['label'], p['offset'], int(p['size']), p['label'])


def check(rom: bytes, quiet: bool = True) -> list[str]:
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    return extract_texts(rom, extract_data.read_manifest())[1]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    try:
        rom = extract_data.read_rom()
        problems = check(rom, quiet=False)
    except (AnimsError, extract_data.DataError) as e:
        print(f'anims: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'anims: {p}', file=sys.stderr)
    if problems:
        return 1
    lists = derive(rom)
    n = len(lists['animframes']['lists'])
    size = {k: v['stop'] - v['start'] for k, v in lists.items()}
    print(f'OK: the frame-id lists ({size["animframes"]:,} B) and duration lists ({size["animtimes"]:,} B) of '
          f'{n} animations convert to text and assemble back byte-exact')
    return 0


if __name__ == '__main__':
    sys.exit(main())
