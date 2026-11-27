#!/usr/bin/env python3
"""
menutext.py — The menu's string tables (bank $FF, drawn by Menu_DrawString)
as readable text, extracted from your own ROM into the ignored
build/assets/menu/, and the assembler that rebuilds their exact bytes
(DATA_PLAN.md, the menu strings). No string is ever committed.

How the code reads them:

  Menu_DrawStringLoop reads a string at DB:Y: a 0 byte ends it; a byte
  below Menu_TextFirstTile ($10) is a control code, run through
  Menu_TextCtrlTable (Menu_TextCtrl) and not counted; any other byte is a
  tile, put (Menu_PutChar) and counted down in Menu_TextLeft, which ends
  the string at 0 (the caller's count: bits 0-6 of its flags byte, 0 =
  256). Code $04 runs the loop on a sub-string (a long pointer), sharing
  the count; code $05 on a name in RAM with a count of its own; code $07
  takes one off the count without testing it.

  The argument bytes of each code are its handler's: ARGS, which
  arg_problems re-derives by running every handler (tools/absint.py) with
  Y on the code's arguments and reading how far Y has moved at its RTS.

  A string's extent is its reader's: up to its 0, or up to the tile that
  takes the count to 0, whichever comes first, for the count each caller
  passes. Only strings a caller is known to draw are proved:

    MenuRom_ItemTextPtrs  Menu_DrawInvEntry draws entry id (1 to
                          Menu_ItemIdEnd - 1; id 0 is drawn as blanks)
                          with a count of Menu_ItemTextLen (9);
    MenuRom_StringPtrs    Menu_DrawCmdString (draw list command $06) draws
                          entry arg 0-1 with the count of arg 4: the
                          entries the draw lists (tools/drawlists.py) name;
                          the equipment labels Menu_EquipLabelPtrs names
                          are copied (Menu_InfoLabelBytes) to
                          Menu_InfoLabel, which a proved string draws as
                          its sub-string (code $04).

  Sub-strings a proved string names in the piece are proved with the same
  count. Every other byte of the piece stays @bytes: a table entry no
  caller is known to read is written as its word ($XXXX).

The readable form (build/assets/menu/<label>.mtx):

  @menutext LABEL $BB:AAAA SIZE
  @table N                       the N table words come first
  @entry I NAME | $XXXX          entry I: a proved string's label (or an
                                 inline one), else the word as it is
  NAME:                          a proved string, on the next line:
      ABC{end}                   glyphs (text.py's names for the codes,
                                 a display convention; _ is tile $FF),
                                 {gXX} any other tile, {cXX a b ..} code XX
                                 and its argument bytes, {end} the 0,
                                 {@NAME} a label inside the string; a
                                 string the count ends has no {end}
  @bytes 01 02 ..                bytes no proved string covers

    python3 tools/menutext.py check     extract both tables to text and back:
                                        byte-exact? (and ARGS against the
                                        handlers, the proofs against the ROM)
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANK_C2 = ROOT / 'asm' / 'bankC2' / 'bankC2.asm'

KINDS = ('menutext',)
ASSET_DIR = 'menu'
ASSET_EXT = {'menutext': 'mtx'}
OUT = 'menutext'
INCBIN_NOTE = {'menutext': 'menu strings'}
FORMAT = 'menu strings:'
ARGS = (0, 0, 2, 4, 3, 2, 2, 2, 1, 1, 1, 4, 3, 0, 0, 0)    # per control code $00-$0F
FIRST_TILE = 0x10                                          # Menu_TextFirstTile
TABLES = {'$FF:B310': 'items', '$FF:C457': 'strings'}       # the pieces, by survey row start
CODE = re.compile(r'^c([0-9A-F]{2})((?: [0-9A-F]{2})*)$')
TOKEN = re.compile(r'\{([^{}]*)\}|([^{}])')
ADDR = re.compile(r'^\$([C-F][0-9A-F]):([0-9A-F]{4})$')


class MenuTextError(Exception):
    pass


ERROR = MenuTextError


def addr(offset: int) -> str:
    return f'${0xC0 + (offset >> 16):02X}:{offset & 0xFFFF:04X}'


def _glyphs():
    sys.path.insert(0, str(ROOT / 'tools'))
    import text
    return text.GLYPHS, text.CHARS


# ── The control codes, from their handlers ───────────────────────────────

def _table_names(path: Path = BANK_C2) -> list[str]:
    lines = Path(path).read_text().splitlines()
    try:
        i = lines.index('Menu_TextCtrlTable:')
    except ValueError:
        raise MenuTextError(f'{Path(path).name}: no Menu_TextCtrlTable') from None
    out = []
    for line in lines[i + 1:]:
        m = re.match(r'^\s+dw\s+(.*?)\s*(?:;.*)?$', line)
        if not m:
            break
        out += [n.strip() for n in m.group(1).split(',')]
    return out


def derive_args(root: Path = ROOT) -> list[int | None]:
    """The argument bytes of each control code: its handler run (absint)
    with Y = $1000 on the arguments, M=0, X=0, DP=0 and DB=$FF (as
    Menu_TextCtrl jumps to it); how far Y has moved at every RTS, or None
    when that is not one number."""
    sys.path.insert(0, str(ROOT / 'tools'))
    import absint
    import scripts
    lang = scripts.Lang(root)
    names = _table_names(Path(root) / 'asm' / 'bankC2' / 'bankC2.asm')
    out = []
    for code, name in enumerate(names):
        s = scripts.AnimLang._state()
        s.pc = lang.labels[name]
        s.a, s.b, s.x, s.y = (code * 2) & 0xFF, 0, 0x2000, 0x1000
        s.d, s.db, s.m, s.xf = 0, 0xFF, False, False
        try:
            ends = lang.machine.run(s, {})
        except absint.Unresolved:
            out.append(None)
            continue
        got = {None if st.y is None else st.y - 0x1000 for st, how in ends if how == 'rts'}
        out.append(got.pop() if len(got) == 1 and None not in got and len(ends) else None)
    return out


def arg_problems(root: Path = ROOT, derived: list | None = None) -> list[str]:
    got = derive_args(root) if derived is None else derived
    if tuple(got) != ARGS:
        return [f'Menu_TextCtrlTable\'s handlers take {got} argument bytes, not ARGS {list(ARGS)}']
    return []


# ── Walking a string as the reader does ──────────────────────────────────

def walk(rom: bytes, start: int, count: int, where: str) -> tuple[int, bool, list[int]]:
    """(the string's end, whether its 0 ends it, the long addresses of the
    sub-strings it names) for the string at file offset `start` drawn with
    `count` (1-256), as Menu_DrawStringLoop reads it."""
    x, left, subs = start, count, []
    while True:
        if x >= len(rom):
            raise MenuTextError(f'{where}: the string at {addr(start)} runs past the ROM')
        c = rom[x]
        if c == 0:
            return x + 1, True, subs
        x += 1
        if c < FIRST_TILE:
            a = rom[x:x + ARGS[c]]
            if c == 0x04:
                subs.append(a[0] | a[1] << 8 | a[2] << 16)
            if c == 0x07:
                left = (left - 1) & 0xFF
            x += ARGS[c]
            continue
        left = (left - 1) & 0xFF
        if left == 0:
            return x, False, subs


# ── The proofs: which strings a caller draws, with what count ────────────

def _words(rom: bytes, start: int, n: int) -> list[int]:
    return [rom[start + 2 * k] | rom[start + 2 * k + 1] << 8 for k in range(n)]


def _equip_labels(path: Path = BANK_C2) -> list[str]:
    lines = Path(path).read_text().splitlines()
    i = lines.index('Menu_EquipLabelPtrs:')
    out = []
    for line in lines[i + 1:]:
        m = re.match(r'^\s+dw\s+(.*?)\s*(?:;.*)?$', line)
        if not m:
            break
        out += [re.match(r'!([A-Za-z0-9_]+)&\$FFFF$', v.strip()).group(1) for v in m.group(1).split(',')]
    return out


def draw_uses(rom: bytes, pieces: list[dict]) -> dict[int, set[int]]:
    """{MenuRom_StringPtrs entry: the counts} of the draw lists' $06
    commands (Menu_DrawCmdString: entry = args 0-1, count = arg 4 bits 0-6,
    0 = 256)."""
    sys.path.insert(0, str(ROOT / 'tools'))
    import drawlists
    import battle
    d = battle.defines(ROOT)
    names = drawlists.command_names()
    lens = drawlists.rom_arglens(rom, d, names)
    string_cmd = 2 * names.index('String')
    out: dict[int, set[int]] = {}
    for p in pieces:
        if p['piece'] != 'drawlist':
            continue
        cmds, _ = drawlists.parse(rom[p['offset']:p['stop']], lens, names, p['label'])
        for c, a in cmds:
            if c == string_cmd:
                out.setdefault(a[0] | a[1] << 8, set()).add(a[4] & d['Menu_TextCountMask'] or 256)
    return out


def proofs(rom: bytes, p: dict, pieces: list[dict], d: dict) -> dict:
    """{'entries': N, 'strings': {start: (end, ended by 0)}} of a piece:
    the table's length and the proved strings (file offsets)."""
    s, e = p['offset'], p['stop']
    kind = TABLES.get(p['start'])
    bank = s & 0xFF0000
    if kind == 'items':
        n = d['Menu_ItemIdEnd']
        words = _words(rom, s, n)
        starts = {(bank | w): {d['Menu_ItemTextLen']} for w in words[1:]}
    elif kind == 'strings':
        words, k = [], 0
        while True:
            w = rom[s + 2 * k] | rom[s + 2 * k + 1] << 8
            if words and s + 2 * k >= bank + min(words):
                break
            words.append(w)
            k += 1
        n = len(words)
        uses = draw_uses(rom, pieces)
        bad = [i for i in uses if i >= n]
        if bad:
            raise MenuTextError(f'{p["label"]}: a draw list draws entry {bad[0]}, past the {n} entries')
        starts = {}
        for i, counts in uses.items():
            starts.setdefault(bank | words[i], set()).update(counts)
        # the equipment labels: copied to Menu_InfoLabel, drawn as a sub-string
        info = 0x7E0000 | d['Menu_InfoLabel']
        labels = [d[name] - 0xC00000 for name in _equip_labels()]
        drawn = set()
        for a, counts in list(starts.items()):
            for c in counts:
                drawn |= _all_subs(rom, a, c, p['label'])
        if info in drawn:
            for a in labels:
                end, zero, _ = walk(rom, a, 256, p['label'])
                if not zero or end - a > d['Menu_InfoLabelBytes']:
                    raise MenuTextError(f'{p["label"]}: the label at {addr(a)} has no 0 in its '
                                        f'{d["Menu_InfoLabelBytes"]} copied bytes')
                starts.setdefault(a, set()).add(256)
    else:
        raise MenuTextError(f'{p["label"]}: not a menu string table of TABLES')
    strings: dict[int, tuple[int, bool]] = {}
    todo = [(a, c) for a, cs in starts.items() for c in cs]
    while todo:
        a, c = todo.pop()
        if not s + 2 * n <= a < e:
            continue
        end, zero, subs = walk(rom, a, c, p['label'])
        if end > e:
            raise MenuTextError(f'{p["label"]}: the string at {addr(a)} runs past the piece')
        old = strings.get(a)
        if old and old != (end, zero):
            raise MenuTextError(f'{p["label"]}: the string at {addr(a)} ends differently for different counts')
        if not old:
            strings[a] = (end, zero)
            todo += [(x - 0xC00000, c) for x in subs if x >= 0xC00000]
    return {'entries': n, 'strings': strings}


def _all_subs(rom: bytes, a: int, c: int, where: str, depth: int = 0) -> set[int]:
    """The long addresses of the sub-strings the string at `a` names, and
    theirs in turn (ROM ones are walked on, 4 deep at most)."""
    _, _, subs = walk(rom, a, c, where)
    out = set(subs)
    if depth < 4:
        for x in subs:
            if x >= 0xC00000:
                out |= _all_subs(rom, x - 0xC00000, c, where, depth + 1)
    return out


# ── The readable form ────────────────────────────────────────────────────

def _tile(b: int, glyphs: dict) -> str:
    return glyphs[b] if b in glyphs else f'{{g{b:02X}}}'


def render(label: str, start: int, data: bytes, proof: dict) -> str:
    glyphs, _ = _glyphs()
    n, strings = proof['entries'], proof['strings']
    bank = start & 0xFF0000
    names = {a: f'S_{0xC00000 + a:06X}' for a in strings}
    covered = {}
    for a, (end, _) in strings.items():
        for x in range(a, end):
            covered.setdefault(x, a)
    inline = {}
    words = _words(data, 0, n)
    for w in words:
        t = bank | w
        if t in covered and t not in names:
            inline[t] = f'S_{0xC00000 + t:06X}'
    out = [f'; {label}: menu strings, extracted from your own ROM by tools/menutext.py (never commit it).',
           f'@menutext {label} {addr(start)} {len(data)}', f'@table {n}']
    for i, w in enumerate(words):
        t = bank | w
        out.append(f'@entry {i} ' + (names.get(t) or inline.get(t) or f'${w:04X}'))
    x = start + 2 * n
    stop = start + len(data)
    while x < stop:
        if x in strings:
            end, zero = strings[x]
            out.append(names[x] + ':')
            line, y = [], x
            while y < end:
                if y != x and y in inline:
                    line.append(f'{{@{inline[y]}}}')
                if y != x and y in names:
                    raise MenuTextError(f'{label}: the string at {addr(y)} starts inside another')
                c = data[y - start]
                if c == 0:
                    line.append('{end}')
                    y += 1
                elif c < FIRST_TILE:
                    line.append('{c%02X%s}' % (c, ''.join(f' {b:02X}' for b in data[y + 1 - start:y + 1 + ARGS[c] - start])))
                    y += 1 + ARGS[c]
                else:
                    line.append(_tile(c, glyphs))
                    y += 1
            out.append('    ' + ''.join(line))
            x = end
            continue
        z = x + 1
        while z < stop and z not in strings and z - x < 16:
            z += 1
        out.append('@bytes ' + ' '.join(f'{b:02X}' for b in data[x - start:z - start]))
        x = z
    return '\n'.join(out) + '\n'


def _encode_string(line: str, chars: dict, where: str, pos: int, labels: dict) -> bytes:
    out, ended = bytearray(), False
    for m in TOKEN.finditer(line):
        tok, ch = m.group(1), m.group(2)
        if ended:
            raise MenuTextError(f'{where}: {{end}} must end the string')
        if ch is not None:
            if ch not in chars:
                raise MenuTextError(f'{where}: {ch!r} is not a glyph (write {{gXX}})')
            out.append(chars[ch])
            continue
        if tok == 'end':
            out.append(0)
            ended = True
        elif tok.startswith('@'):
            if tok[1:] in labels:
                raise MenuTextError(f'{where}: label {tok[1:]} twice')
            labels[tok[1:]] = pos + len(out)
        elif re.fullmatch(r'g[0-9A-F]{2}', tok):
            v = int(tok[1:], 16)
            if v < FIRST_TILE:
                raise MenuTextError(f'{where}: {{{tok}}} is a control code, not a tile')
            out.append(v)
        else:
            cm = CODE.match(tok)
            if not cm:
                raise MenuTextError(f'{where}: bad token {{{tok}}}')
            c = int(cm.group(1), 16)
            args = cm.group(2).split()
            if not 1 <= c < FIRST_TILE or len(args) != ARGS[c]:
                raise MenuTextError(f'{where}: {{{tok}}}: code $01-$0F with its {ARGS[c] if c < 16 else "?"} '
                                    f'argument byte(s)')
            out.append(c)
            out += bytes(int(a, 16) for a in args)
    return bytes(out)


def assemble(text: str, label: str, start: int, size: int, name: str = '<mtx>') -> bytes:
    _, chars = _glyphs()
    lines = [(f'{name}:{n}', ln) for n, ln in enumerate(text.splitlines(), 1)
             if ln.strip() and not ln.startswith(';')]
    if not lines or lines[0][1].split() != ['@menutext', label, addr(start), str(size)]:
        raise MenuTextError(f'{name}: the first line must be @menutext {label} {addr(start)} {size}')
    if len(lines) < 2 or not re.fullmatch(r'@table \d+', lines[1][1].strip()):
        raise MenuTextError(f'{name}: the second line must be @table N')
    n = int(lines[1][1].split()[1])
    entries = lines[2:2 + n]
    if len(entries) != n or any(w.split()[:2] != ['@entry', str(i)] or len(w.split()) != 3
                                for i, (_, w) in enumerate(entries)):
        raise MenuTextError(f'{name}: the table needs {n} @entry I TARGET lines, in order')
    body, labels, pos, i = bytearray(), {}, start + 2 * n, 2 + n
    while i < len(lines):
        where, ln = lines[i]
        w = ln.split()
        if w[0] == '@bytes':
            if not all(re.fullmatch(r'[0-9A-F]{2}', b) for b in w[1:]) or len(w) < 2:
                raise MenuTextError(f'{where}: @bytes takes XX bytes')
            body += bytes(int(b, 16) for b in w[1:])
            i += 1
            continue
        if len(w) == 1 and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*:', w[0]):
            if w[0][:-1] in labels:
                raise MenuTextError(f'{where}: label {w[0][:-1]} twice')
            labels[w[0][:-1]] = pos + len(body)
            if i + 1 >= len(lines) or not lines[i + 1][1].startswith('    '):
                raise MenuTextError(f'{where}: a label is followed by its string, indented')
            body += _encode_string(lines[i + 1][1].strip(), chars, lines[i + 1][0], pos + len(body), labels)
            i += 2
            continue
        raise MenuTextError(f'{where}: expected a label, its string, or @bytes')
    table = bytearray()
    for where, ln in entries:
        t = ln.split()[2]
        if re.fullmatch(r'\$[0-9A-F]{4}', t):
            table += int(t[1:], 16).to_bytes(2, 'little')
        elif t in labels:
            table += (labels[t] & 0xFFFF).to_bytes(2, 'little')
        else:
            raise MenuTextError(f'{where}: no label {t}')
    data = bytes(table) + bytes(body)
    if len(data) != size:
        raise MenuTextError(f'{name}: the piece makes {len(data)} B; it is {size} B')
    return data


# ── The pieces ───────────────────────────────────────────────────────────

def is_piece_row(row: dict) -> str | None:
    return 'menutext' if row['kind'] == 'text' and row['format'].startswith(FORMAT) else None


def piece_text(p: dict, rom: bytes, pieces: list[dict], d: dict) -> str:
    s, e = p['offset'], p['stop']
    text = render(p['label'], s, rom[s:e], proofs(rom, p, pieces, d))
    if assemble(text, p['label'], s, e - s, p['label']) != rom[s:e]:
        raise MenuTextError(f'{p["label"]}: does not assemble back to its bytes')
    return text


def extract_texts(rom: bytes, pieces: list[dict], d: dict | None = None,
                  derived: list | None = None) -> tuple[dict[str, str], list[str]]:
    mine = [p for p in pieces if p['piece'] == 'menutext']
    if not mine:
        return {}, []
    if d is None:
        sys.path.insert(0, str(ROOT / 'tools'))
        import battle
        d = battle.defines(ROOT)
    problems = arg_problems(ROOT, derived)
    if problems:
        return {}, problems
    texts = {}
    for p in mine:
        try:
            texts[p['label']] = piece_text(p, rom, pieces, d)
        except MenuTextError as err:
            problems.append(str(err))
    return texts, problems


def assemble_piece(p: dict, text: str) -> bytes:
    return assemble(text, p['label'], p['offset'], int(p['size']), p['label'])


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
        problems = check(extract_data.read_rom())
    except (MenuTextError, extract_data.DataError) as e:
        print(f'menutext: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'menutext: {p}', file=sys.stderr)
    if problems:
        return 1
    print('OK: the menu string tables convert to text and assemble back byte-exact')
    return 0


if __name__ == '__main__':
    sys.exit(main())
