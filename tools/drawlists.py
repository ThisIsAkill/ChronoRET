#!/usr/bin/env python3
"""
drawlists.py — The menu's draw lists (bank $FF, run by Menu_RunDrawList) as
readable text, extracted from your own ROM into the ignored
build/assets/menu/, and the assembler that rebuilds their exact bytes
(DATA_PLAN.md, the menu draw lists).

No list is ever committed (README, "Legal"): extraction writes them, the
build assembles them back. What this tool holds is how the code reads them:

  Menu_RunDrawList runs the list at $FF:X: a byte below $80 is a command c:
  the MenuRom_DrawArgLens[c] + 1 bytes after it are its arguments (copied
  to Menu_DrawArg0 on by an MVN), and Menu_DrawCmdTable's routine at byte
  offset c runs (JSR (Menu_DrawCmdTable,X), so c is even and below twice
  the table's length). The first byte with bit 7 set ends the list.

  So a list's extent is its reader's: commands up to and with its end
  byte. A survey row that holds whole commands and no end byte is a list
  that runs on into the next row's list (the reader does not stop at the
  row's end): its text ends with `continues`, and the next row must be a
  draw list. Every other row stays bytes.

The readable form (build/assets/menu/<label>.mdl):

  @drawlist LABEL $BB:AAAA SIZE
  @arglens 03 00 05 ...              MenuRom_DrawArgLens as the list was
                                     extracted (check() compares it with the
                                     ROM): each command's argument count
  $00 Fill 05 00 FF 00               a command: its byte, its routine's name
                                     (Menu_DrawCmd...), its argument bytes
  end $FF                            the end byte (any with bit 7 set), or
  continues                          (no end byte: the next list follows)

    python3 tools/drawlists.py check    extract every draw list from the ROM
                                        to text and assemble it back:
                                        byte-exact? (and the commands
                                        against the readers)
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANK_C2 = ROOT / 'asm' / 'bankC2' / 'bankC2.asm'

KINDS = ('drawlist',)
ASSET_DIR = 'menu'
ASSET_EXT = {'drawlist': 'mdl'}
OUT = 'menulists'                       # build/menulists/<label>.bin
INCBIN_NOTE = {'drawlist': 'menu draw list'}
FORMAT = 'Menu_RunDrawList draw list'   # the survey format of a row that is one
END = 0x80                              # a byte with bit 7 set ends a list
ADDR = re.compile(r'^\$([C-F][0-9A-F]):([0-9A-F]{4})$')
BYTE = re.compile(r'^[0-9A-F]{2}$')
CMD = re.compile(r'^\$([0-9A-F]{2})$')


class DrawListsError(Exception):
    pass


ERROR = DrawListsError


def addr(offset: int) -> str:
    return f'${0xC0 + (offset >> 16):02X}:{offset & 0xFFFF:04X}'


def command_names(path: Path = BANK_C2) -> list[str]:
    """The routines of Menu_DrawCmdTable, in order (Menu_DrawCmd stripped)."""
    lines = Path(path).read_text().splitlines()
    try:
        i = lines.index('Menu_DrawCmdTable:')
    except ValueError:
        raise DrawListsError(f'{Path(path).name}: no Menu_DrawCmdTable') from None
    out = []
    for line in lines[i + 1:]:
        m = re.match(r'^\s+dw\s+(.*?)\s*(?:;.*)?$', line)
        if not m:
            break
        out += [n.strip() for n in m.group(1).split(',')]
    if not out or not all(n.startswith('Menu_DrawCmd') for n in out):
        raise DrawListsError('Menu_DrawCmdTable: expected dw lines of Menu_DrawCmd routines')
    return [n[len('Menu_DrawCmd'):] for n in out]


# ── Lists, from the bytes ────────────────────────────────────────────────

def parse(data: bytes, arglens: bytes, names: list[str], where: str) -> tuple[list[tuple[int, bytes]], int | None]:
    """The commands of a list in `data` (the row's bytes) and its end byte,
    or None when the commands fill the row with no end byte. Fails when a
    command is not one the reader can run, or a command or the list does
    not end with the row."""
    cmds, x = [], 0
    while x < len(data):
        c = data[x]
        if c & END:
            if x + 1 != len(data):
                raise DrawListsError(f'{where}: the list ends at byte {x}, {len(data) - x - 1} B before the row ends')
            return cmds, c
        if c % 2 or c // 2 >= len(names) or c >= len(arglens):
            raise DrawListsError(f'{where}: byte {x}: ${c:02X} is not a command (even, below '
                                 f'${2 * len(names):02X})')
        n = arglens[c] + 1
        if x + 1 + n > len(data):
            raise DrawListsError(f'{where}: byte {x}: command ${c:02X} runs past the row')
        cmds.append((c, data[x + 1:x + 1 + n]))
        x += 1 + n
    return cmds, None


def render(label: str, start: int, data: bytes, arglens: bytes, names: list[str]) -> str:
    cmds, end = parse(data, arglens, names, label)
    out = [f'; {label}: a menu draw list, extracted from your own ROM by tools/drawlists.py (never commit it).',
           f'@drawlist {label} {addr(start)} {len(data)}',
           '@arglens ' + ' '.join(f'{b:02X}' for b in arglens)]
    for c, args in cmds:
        out.append(f'${c:02X} {names[c // 2]} ' + ' '.join(f'{b:02X}' for b in args))
    out.append(f'end ${end:02X}' if end is not None else 'continues')
    return '\n'.join(out) + '\n'


def assemble(text: str, label: str, start: int, size: int, names: list[str], name: str = '<mdl>') -> bytes:
    lines = [(str(n), ln.split(';', 1)[0].split()) for n, ln in enumerate(text.splitlines(), 1)]
    lines = [(n, f) for n, f in lines if f]
    if not lines or lines[0][1] != ['@drawlist', label, addr(start), str(size)]:
        raise DrawListsError(f'{name}: the first line must be @drawlist {label} {addr(start)} {size}')
    if len(lines) < 2 or lines[1][1][:1] != ['@arglens'] or not all(BYTE.match(b) for b in lines[1][1][1:]):
        raise DrawListsError(f'{name}: the second line must be @arglens and the argument counts (hex bytes)')
    arglens = bytes(int(b, 16) for b in lines[1][1][1:])
    out = bytearray()
    for i, (ln, f) in enumerate(lines[2:], 2):
        where = f'{name}:{ln}'
        last = i == len(lines) - 1
        if f == ['continues'] or f[0] == 'end':
            if not last:
                raise DrawListsError(f'{where}: {f[0]} must be the last line')
            if f[0] == 'end':
                m = re.match(r'^\$([0-9A-F]{2})$', f[1]) if len(f) == 2 else None
                if not m or not int(m.group(1), 16) & END:
                    raise DrawListsError(f'{where}: expected end $VV, VV with bit 7 set')
                out.append(int(m.group(1), 16))
            break
        m = CMD.match(f[0])
        if not m or len(f) < 2:
            raise DrawListsError(f'{where}: expected $CC Name args, end $VV or continues')
        c = int(m.group(1), 16)
        if c & END or c % 2 or c // 2 >= len(names) or c >= len(arglens) or f[1] != names[c // 2]:
            raise DrawListsError(f'{where}: ${c:02X} {f[1]} is not a command of Menu_DrawCmdTable')
        if len(f) - 2 != arglens[c] + 1 or not all(BYTE.match(b) for b in f[2:]):
            raise DrawListsError(f'{where}: ${c:02X} {f[1]} takes {arglens[c] + 1} argument byte(s)')
        out.append(c)
        out += bytes(int(b, 16) for b in f[2:])
    else:
        raise DrawListsError(f'{name}: the list has no end line (end $VV or continues)')
    if len(out) != size:
        raise DrawListsError(f'{name}: the list makes {len(out)} B, the piece is {size} B')
    return bytes(out)


# ── The pieces ───────────────────────────────────────────────────────────

def is_piece_row(row: dict) -> str | None:
    return 'drawlist' if row['kind'] == 'table' and row['format'].startswith(FORMAT) else None


def rom_arglens(rom: bytes, d: dict, names: list[str]) -> bytes:
    a = d['MenuRom_DrawArgLens'] - 0xC00000
    return bytes(rom[a:a + 2 * len(names)])


def extract_texts(rom: bytes, pieces: list[dict], d: dict | None = None,
                  path: Path = BANK_C2) -> tuple[dict[str, str], list[str]]:
    """({label: text} of every drawlist piece, the problems): each list is
    parsed as its reader runs it and checked to assemble back; a list
    without an end byte must be followed by another drawlist piece."""
    lists = [p for p in pieces if p['piece'] == 'drawlist']
    if not lists:
        return {}, []
    if d is None:
        sys.path.insert(0, str(ROOT / 'tools'))
        import battle
        d = battle.defines(ROOT)
    names = command_names(path)
    arglens = rom_arglens(rom, d, names)
    starts = {p['offset'] for p in lists}
    texts, problems = {}, []
    for p in lists:
        s, e = p['offset'], p['stop']
        try:
            if s >> 16 != (d['MenuRom_DrawArgLens'] - 0xC00000) >> 16:
                raise DrawListsError(f'{p["label"]}: not in bank $FF, where Menu_RunDrawList reads')
            text = render(p['label'], s, rom[s:e], arglens, names)
            if text.endswith('continues\n') and e not in starts:
                raise DrawListsError(f'{p["label"]}: the list runs past its row, and no draw list follows it')
            if assemble(text, p['label'], s, e - s, names, p['label']) != rom[s:e]:
                raise DrawListsError(f'{p["label"]}: does not assemble back to its bytes')
            texts[p['label']] = text
        except DrawListsError as err:
            problems.append(str(err))
    return texts, problems


def assemble_piece(p: dict, text: str) -> bytes:
    return assemble(text, p['label'], p['offset'], int(p['size']), command_names(), p['label'])


def arglens_problems(rom: bytes, texts: dict[str, str], d: dict, names: list[str]) -> list[str]:
    """Where a list's @arglens is not the ROM's MenuRom_DrawArgLens."""
    want = ' '.join(f'{b:02X}' for b in rom_arglens(rom, d, names))
    return [f'{label}: @arglens is not MenuRom_DrawArgLens' for label, t in texts.items()
            if t.splitlines()[2] != f'@arglens {want}']


def check(rom: bytes, quiet: bool = True) -> list[str]:
    sys.path.insert(0, str(ROOT / 'tools'))
    import battle
    import extract_data
    d = battle.defines(ROOT)
    texts, problems = extract_texts(rom, extract_data.read_manifest(), d)
    return problems + arglens_problems(rom, texts, d, command_names())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    try:
        rom = extract_data.read_rom()
        problems = check(rom)
    except (DrawListsError, extract_data.DataError) as e:
        print(f'drawlists: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'drawlists: {p}', file=sys.stderr)
    if problems:
        return 1
    ps = [p for p in extract_data.read_manifest() if p['piece'] == 'drawlist']
    print(f'OK: all {len(ps)} menu draw lists ({sum(int(p["size"]) for p in ps):,} B) convert to text and '
          f'assemble back byte-exact')
    return 0


if __name__ == '__main__':
    sys.exit(main())
