#!/usr/bin/env python3
"""
actframes.py — The battle action sprite frames (the packs BattleRom_PcAttackFrames
and BattleRom_ActFrames point at, bank $D1) as readable text, the unpacked
form of each pack (DATA_PLAN.md, the battle action frames). tools/maps.py
places them with the other packed text pieces: extraction writes
build/assets/actframes/<label>.afr, the build assembles it and packs it.

No frame is ever committed (README, "Legal"). What this tool holds is how
the code reads them:

  BattleAct_LoadCommon unpacks the pack at bank $D1 + Battle_ActFramesPtr
  into Battle_ActFrameBuf (Decomp_ToWramVec) and stores two zero bytes
  after it (at Battle_DecompLen). BattleAct_UnpackFrames, called
  CALLS times, builds Battle_ActFramesPerCall frames per call from there:

    a header byte: bits 0-3 the row count (Battle_ActFrameRowsMask), bits
      4-7 kept in DP $80 and not read; a header of 0 ends the data;
    one bit mask per row, bit 7 = column 0 (Battle_ActFrameCols columns);
    per set bit, rows then columns in order: a tile byte and an attribute
      byte (a 16x16 sprite at column x 16, row x 16);
    2 bytes the reader skips.

  So a pack's extent is its frames up to the end of the unpacked data (the
  appended zero ends them); a pack whose data holds a 0 header, runs past
  its end, or holds more frames than the CALLS calls build is refused.

The readable form (build/assets/actframes/<label>.afr):

  @actframes LABEL N                  the pack's N frames
  frame K rows R hi H                 a frame: its row count and the header's
                                      high nibble (kept as it is)
    row 0: 2=12/30 3=13/30            the row's sprites: column=tile/attribute
    row 1: -                          (hex); - for a row with none
    skip 00 00                        the 2 bytes the reader skips

    python3 tools/actframes.py check    every action-frame pack to text and
                                        back: byte-exact?
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANK_C1 = ROOT / 'asm' / 'bankC1' / 'bankC1.asm'
COLS = 8                                # Battle_ActFrameCols
ROWS_MASK = 0x0F                        # Battle_ActFrameRowsMask
CALLS = 8                               # JSRs of BattleAct_UnpackFrames in BattleAct_LoadCommon
PER_CALL = 4                            # Battle_ActFramesPerCall
TABLE = 'BattleRom_PcAttackFrames/ActFrames'   # the survey's "via" name of the packs
SPRITE = re.compile(r'^([0-7])=([0-9A-F]{2})/([0-9A-F]{2})$')
BYTE = re.compile(r'^[0-9A-F]{2}$')


class ActFramesError(Exception):
    pass


def parse(data: bytes, where: str, max_frames: int = CALLS * PER_CALL) -> list[dict]:
    """The frames of a pack's unpacked bytes, as the reader reads them."""
    frames, x = [], 0
    while x < len(data):
        h = data[x]
        if h == 0:
            raise ActFramesError(f'{where}: byte {x}: a 0 header ends the frames {len(data) - x} B before the '
                                 f'data does')
        rows = h & ROWS_MASK
        if x + 1 + rows > len(data):
            raise ActFramesError(f'{where}: frame {len(frames)}\'s row masks run past the data')
        masks = data[x + 1:x + 1 + rows]
        x += 1 + rows
        sprites = []
        for r, m in enumerate(masks):
            for c in range(COLS):
                if m & (0x80 >> c):
                    if x + 2 > len(data):
                        raise ActFramesError(f'{where}: frame {len(frames)}\'s sprites run past the data')
                    sprites.append((r, c, data[x], data[x + 1]))
                    x += 2
        if x + 2 > len(data):
            raise ActFramesError(f'{where}: frame {len(frames)}\'s skipped bytes run past the data')
        frames.append({'rows': rows, 'hi': h >> 4, 'sprites': sprites, 'skip': data[x:x + 2]})
        x += 2
    if len(frames) > max_frames:
        raise ActFramesError(f'{where}: {len(frames)} frames; the reader builds {max_frames}')
    return frames


def render(label: str, data: bytes) -> str:
    frames = parse(data, label)
    out = [f'; {label}: battle action sprite frames, extracted from your own ROM by tools/actframes.py '
           f'(never commit it).',
           f'@actframes {label} {len(frames)}']
    for k, f in enumerate(frames):
        out.append(f'frame {k} rows {f["rows"]} hi {f["hi"]}')
        for r in range(f['rows']):
            cells = [f'{c}={t:02X}/{a:02X}' for rr, c, t, a in f['sprites'] if rr == r]
            out.append(f'  row {r}: ' + (' '.join(cells) if cells else '-'))
        out.append('  skip ' + ' '.join(f'{b:02X}' for b in f['skip']))
    return '\n'.join(out) + '\n'


def assemble(text: str, label: str, name: str = '<afr>') -> bytes:
    lines = [(str(n), ln.split(';', 1)[0].split()) for n, ln in enumerate(text.splitlines(), 1)]
    lines = [(n, f) for n, f in lines if f]
    if not lines or len(lines[0][1]) != 3 or lines[0][1][:2] != ['@actframes', label] \
            or not lines[0][1][2].isdigit():
        raise ActFramesError(f'{name}: the first line must be @actframes {label} N')
    n = int(lines[0][1][2])
    out = bytearray()
    i = 1
    for k in range(n):
        ln, f = lines[i] if i < len(lines) else ('end', [])
        m = re.match(r'^frame (\d+) rows (\d+) hi (\d+)$', ' '.join(f))
        if not m or int(m.group(1)) != k or not 1 <= int(m.group(2)) <= ROWS_MASK or int(m.group(3)) > 15:
            raise ActFramesError(f'{name}:{ln}: expected frame {k} rows R hi H (R 1-15, H 0-15)')
        rows, hi = int(m.group(2)), int(m.group(3))
        masks, pairs = bytearray(rows), bytearray()
        for r in range(rows):
            ln, f = lines[i + 1 + r] if i + 1 + r < len(lines) else ('end', [])
            if f[:2] != ['row', f'{r}:'] or len(f) < 3:
                raise ActFramesError(f'{name}:{ln}: expected row {r}: and its sprites (or -)')
            if f[2:] == ['-']:
                continue
            last = -1
            for cell in f[2:]:
                sm = SPRITE.match(cell)
                if not sm or int(sm.group(1)) <= last:
                    raise ActFramesError(f'{name}:{ln}: bad sprite {cell!r} (C=TT/AA, columns 0-7 rising)')
                last = int(sm.group(1))
                masks[r] |= 0x80 >> last
                pairs += bytes([int(sm.group(2), 16), int(sm.group(3), 16)])
        ln, f = lines[i + 1 + rows] if i + 1 + rows < len(lines) else ('end', [])
        if len(f) != 3 or f[0] != 'skip' or not all(BYTE.match(b) for b in f[1:]):
            raise ActFramesError(f'{name}:{ln}: expected skip and 2 hex bytes')
        out += bytes([rows | hi << 4]) + masks + pairs + bytes(int(b, 16) for b in f[1:])
        i += 2 + rows
    if i != len(lines):
        raise ActFramesError(f'{name}:{lines[i][0]}: a line after frame {n - 1}' if n else
                             f'{name}:{lines[i][0]}: a line after an empty pack')
    if n > CALLS * PER_CALL:
        raise ActFramesError(f'{name}: {n} frames; the reader builds {CALLS * PER_CALL}')
    return bytes(out)


def reader_problems(d: dict, path: Path = BANK_C1) -> list[str]:
    """Where the source's reader is not the one this tool follows."""
    problems = []
    if (d['Battle_ActFrameCols'], d['Battle_ActFrameRowsMask'], d['Battle_ActFramesPerCall']) != \
            (COLS, ROWS_MASK, PER_CALL):
        problems.append('Battle_ActFrameCols / RowsMask / FramesPerCall are not COLS / ROWS_MASK / PER_CALL')
    text = Path(path).read_text()
    try:
        body = text[text.index('\nBattleAct_LoadCommon:'):]
    except ValueError:
        return problems + [f'{Path(path).name}: no BattleAct_LoadCommon']
    body = body[:body.index('\n    RTS') if '\n    RTS' in body else len(body)]
    calls = body.count('JSR BattleAct_UnpackFrames')
    if calls != CALLS:
        problems.append(f'BattleAct_LoadCommon calls BattleAct_UnpackFrames {calls} times, not {CALLS}')
    return problems


def check(rom: bytes, quiet: bool = True) -> list[str]:
    sys.path.insert(0, str(ROOT / 'tools'))
    import battle
    import maps
    return reader_problems(battle.defines(ROOT)) + [x for x in maps.check(rom) if 'ActFramesPack' in x]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    try:
        problems = check(extract_data.read_rom())
    except (ActFramesError, extract_data.DataError) as e:
        print(f'actframes: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'actframes: {p}', file=sys.stderr)
    if problems:
        return 1
    ps = [p for p in extract_data.read_manifest() if p['piece'] == 'actframes']
    print(f'OK: all {len(ps)} battle action-frame packs convert to text and assemble back byte-exact')
    return 0


if __name__ == '__main__':
    sys.exit(main())
