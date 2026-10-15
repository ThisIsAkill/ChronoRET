#!/usr/bin/env python3
"""
text.py — The game's text: a readable form, extracted from your own ROM into
the ignored build/assets/text/, and an encoder that turns it back into the
exact original bytes at build time.

No text is ever committed (README, "Legal"). This tool holds only the
encoding: the character map, the control codes, the dictionary rule and
which survey rows are text units. tools/extract_data.py calls `extract_unit`
when it extracts the assets, and tools/build_rom.py calls `encode_units`
when it builds; the encoded pieces (build/text/<label>.bin) are incbin'd by
asm/data/ like the packs, and tools/verify.py counts them apart, never as
emitted by source.

The encoding is the matched decoder's in bank $C2 (TextWin_State0 and the
handlers of TextWin_CodeTable, TextWin_CodeExt, TextWin_State1):

  $A0-$FF   a glyph of the text font (TextWin_DrawGlyph, TextWinRom_Font).
            The readable character of each comes from the font itself (the
            glyphs drawn from TextWinRom_Font and TextWinRom_FontRight) and
            from the code: TextWin_HexGlyphs gives "0"-"9" as $D4-$DD and
            "A"-"F" as $A0-$A5, TextWin_StrNadia spells a name with $A0 = "A"
            and $BA = "a", TextWin_GlyphWidths gives the blanks ($EF and $FF
            are 4 pixels wide, $F4-$FE 0). GLYPHS below. A glyph with no
            character is written {gXX}.
  $21-$9F   dictionary entry (byte - TextWin_FirstDict) of TextWin_DictPtrs
            ($DE:FA00): a length byte, then that many glyphs (TextWin_State1).
  $00-$20   a control code, through TextWin_CodeTable; the codes whose
            handler reads the next string byte (TextWin_CodeStatusArg,
            TextWin_CodeWide, TextWin_CodeExt) take one operand. The table
            is read from asm/bankC2/bankC2.asm, so the tags follow the
            matched handlers (HANDLERS below).

The dictionary rule. The 15 message tables (4,579 pointers) use 41,838
dictionary bytes. Each of their 10,883 runs of glyphs between two control
codes (or pointer targets) is exactly what a greedy longest match gives,
left to right, over dictionary entries 0-126 *except 116-118*: those three are in the
dictionary but no string uses them (with them, 171 runs would come out
different). Entries never tie (no two have the same text), so the rule is
deterministic: GREEDY_SKIP. The readable text is therefore stored fully
expanded and recompressed by the encoder. A run the rule does not give (none
in the message tables; possible in stale bytes) is written explicitly as
«...» with [xyz] for each dictionary entry, which the encoder takes as is.

A unit holds text only: its strings, their pointer tables, the dictionary,
the names and the credits. Bytes in a unit's rows that are not text make
extraction fail; they belong in their own survey rows (extracted as data).

The readable form, one UTF-8 file per unit (build/assets/text/<unit>.txt):

  ; ...                  a comment line
  @piece LABEL $BB:AAAA  the bytes that follow are piece LABEL's (the
                         manifest's piece at that address)
  @mode MODE             how text lines are encoded: msg (TextWin strings,
                         compressed with the dictionary), plain (TextWin
                         strings of a table that uses no dictionary),
                         glyph (glyphs only) or ascii
  @table NAME COUNT      a table of COUNT 16-bit pointers (bank-local)
  @at [NAME:]I ...       entries I of table NAME (default `ptr`) point here
  @set [NAME:]I $XXXX    entry I holds a value that points at no text
  @d TEXT                a dictionary entry: a length byte, then the glyphs
  @records SIZE $PP      fixed-size records follow, padded with $PP
  @r TEXT                one record
  other lines            text; a line break in the file is not a byte.
                         Tags: {end} {line} {wait 03} {char0} ... (CODES);
                         {gXX} a glyph by number; {$XX} a raw byte; [xyz] a
                         dictionary entry by its text; {ext [xyz]} the same
                         entry through code $12 (TextWin_CodeExt); «...» glyphs taken
                         literally (no dictionary), with [xyz] inside.

    python3 tools/text.py check          extract every unit from the ROM
                                         and encode it back: byte-exact?
    python3 tools/text.py stats          per unit: strings, dictionary
                                         bytes, explicit runs
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANK_C2 = ROOT / 'asm' / 'bankC2' / 'bankC2.asm'
CONSTANTS = ROOT / 'asm' / 'include' / 'constants_menu.inc'


class TextError(Exception):
    pass


# ── The encoding, from the matched decoder ──────────────────────────────────

def _defines() -> dict[str, int]:
    out = {}
    for line in CONSTANTS.read_text().splitlines():
        m = re.match(r'^!(TextWin_[A-Za-z0-9_]+)\s*=\s*(\$[0-9A-Fa-f]+|\d+)\b', line)
        if m:
            v = m.group(2)
            out[m.group(1)] = int(v[1:], 16) if v.startswith('$') else int(v)
    return out


_D = _defines()
FIRST_GLYPH = _D['TextWin_FirstGlyph']          # $A0
FIRST_DICT = _D['TextWin_FirstDict']            # $21
CODE12_DICT = _D['TextWin_Code12Dict']          # 8
CODE12_BASE = _D['TextWin_Code12DictBase']      # $1F
DICT_PTRS = _D['TextWin_DictPtrs']              # $DE:FA00
DICT_ENTRIES = FIRST_GLYPH - FIRST_DICT         # 127 reached by a string byte (128 with code $12)

# The dictionary entries the original encoder did not use (see the
# docstring): greedy longest match over the others reproduces every string.
GREEDY_SKIP = frozenset({116, 117, 118})

# Glyph -> character. $A0-$D3 letters and $D4-$DD digits (TextWin_HexGlyphs,
# TextWin_StrNadia), the rest as drawn by the font; $E1/$E2 are the opening
# and closing quotes (the font's shapes, and $E1 follows a space 136 times of
# 182, $E2 precedes one). $EF is the space; $FF, the other 4-pixel blank, is
# written "_" (it separates words in the item and tech names).
GLYPHS = {FIRST_GLYPH + i: c for i, c in enumerate(
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!?'
    '/“”:&()\'.,=-+%♪ ♥…∞#')}
GLYPHS[0xFF] = '_'
CHARS = {c: g for g, c in GLYPHS.items()}

# What each handler of TextWin_CodeTable does, by name: (operand bytes, tag).
# A tag is a name, or a function of the code (and operand).
STATUS_TAGS = {0: 'end', 4: 'step', 5: 'line', 6: 'line indent', 7: 'wait line',
               8: 'wait line indent', 9: 'page', 10: 'page indent', 11: 'wait page',
               12: 'wait page indent'}       # TextWin_Status values (FieldMsg_Status*)
HANDLERS = {
    'TextWin_CodeSetStatus': 0,       # TextWin_Status = the code
    'TextWin_CodeStatusArg': 1,       # $03 n: a wait of n (FieldMsg_WaitUnit frames each)
    'TextWin_CodeWide': 1,            # $01/$02 n: glyph $01nn/$02nn
    'TextWin_CodeNum8': 0,
    'TextWin_CodeNum16': 0,
    'TextWin_CodeNum24': 0,
    'TextWin_CodeNop': 0,
    'TextWin_CodeArgName': 0,
    'TextWin_CodeExt': 1,             # $12 n: tech name, enemy name or dictionary entry
    'TextWin_CodeCharName': 0,
    'TextWin_CodeName0': 0,
    'TextWin_CodeMemberName': 0,
    'TextWin_CodeNadia': 0,
    'TextWin_CodeItemName': 0,
    'TextWin_CodeName7': 0,
}


def code_table(path: Path = BANK_C2) -> list[str]:
    """The handler of each control code, from TextWin_CodeTable's source."""
    lines = path.read_text().splitlines()
    try:
        i = lines.index('TextWin_CodeTable:')
    except ValueError:
        raise TextError(f'{path}: no TextWin_CodeTable') from None
    out = []
    for line in lines[i + 1:]:
        m = re.match(r'^\s+dw\s+([A-Za-z_][A-Za-z0-9_]*)', line)
        if not m:
            break
        out.append(m.group(1))
    if len(out) != FIRST_DICT:
        raise TextError(f'TextWin_CodeTable has {len(out)} entries, not {FIRST_DICT}')
    unknown = sorted(set(out) - set(HANDLERS))
    if unknown:
        raise TextError(f'TextWin_CodeTable handlers this tool does not know: {unknown}')
    return out


def _code_tags() -> tuple[dict[int, int], dict[int, str]]:
    """{code: operand bytes}, {code: tag of a code without operand}."""
    ops, tags = {}, {}
    first = {}
    for code, handler in enumerate(code_table()):
        ops[code] = HANDLERS[handler]
        first.setdefault(handler, code)
        if handler == 'TextWin_CodeSetStatus':
            tags[code] = STATUS_TAGS.get(code, f'status {code:02X}')
        elif handler == 'TextWin_CodeCharName':
            tags[code] = f'char{code - first[handler]}'
        elif handler == 'TextWin_CodeMemberName':
            tags[code] = f'member{code - first[handler]}'
        elif ops[code] == 0:
            tags[code] = {'TextWin_CodeNum8': 'num8', 'TextWin_CodeNum16': 'num16',
                          'TextWin_CodeNum24': 'num24', 'TextWin_CodeNop': 'nop',
                          'TextWin_CodeArgName': 'argname', 'TextWin_CodeName0': 'name0',
                          'TextWin_CodeNadia': 'nadia', 'TextWin_CodeItemName': 'item',
                          'TextWin_CodeName7': 'name7'}[handler]
    return ops, tags


OPERANDS, CODE_TAGS = _code_tags()
TAG_CODES = {t: c for c, t in CODE_TAGS.items()}
END = TAG_CODES['end']
WIDE = [c for c, h in enumerate(code_table()) if h == 'TextWin_CodeWide']
WAIT = next(c for c, h in enumerate(code_table()) if h == 'TextWin_CodeStatusArg')
EXT = next(c for c, h in enumerate(code_table()) if h == 'TextWin_CodeExt')
EXT_TAGS = {0: 'tech', 1: 'enemy'}           # TextWin_ExtTable: TextWin_ExtTechName, TextWin_ExtEnemyName
BREAK_AFTER = {TAG_CODES[t] for t in STATUS_TAGS.values() if t in TAG_CODES and t != 'step'}

# ── The units: which survey rows are text, and how each is laid out ─────────
#
# A unit is one readable file; each of its rows is a piece of the manifest
# (piece kind `text`). Formats: strtable (16-bit pointers to the strings
# after them, the count from the first pointer), strings (strings only),
# ptrs NAME (a table of pointers into the unit), dict (length-prefixed
# entries), records SIZE $PP (fixed-size names), ascii.

MESSAGE_TABLES = ['$D8:D000', '$D8:DD80', '$DE:C000', '$DE:E300', '$F6:A000', '$F6:B230',
                  '$F7:0000', '$F7:4900', '$F8:4650', '$F9:B000', '$FC:BA00', '$FF:4460',
                  '$FF:5860', '$FF:6B00', '$FF:8400']
STALE = ['$F6:9FE9', '$F6:B223', '$F6:C814', '$F7:48B8', '$F9:FA76', '$FC:B9E8', '$FC:F9CF',
         '$FF:583D', '$FF:6AB6', '$FF:83C5']

UNITS: dict[str, list[tuple[str, str]]] = {
    'Dictionary': [('$DE:FA00', 'ptrs ptr'), ('$DE:FAFE', 'ptrs ptr128'), ('$DE:FB00', 'dict')],
    **{f'Messages_{a[1:3]}{a[4:]}': [(a, 'strtable')] for a in MESSAGE_TABLES},
    'StaleText': [(a, 'strings') for a in STALE],
    'TreasureMessages': [('$DE:FF00', 'strtable')],
    'SceneLabels': [('$C6:F000', 'strings'), ('$C6:F400', 'ptrs ptr')],
    'MenuDescriptions': [('$CC:2EB1', 'strtable')],
    'TechInfo': [('$CC:3A09', 'ptrs ptr'), ('$CC:3B0D', 'strings')],
    'EnemyScriptMessages': [('$CC:CBC9', 'ptrs ptr'), ('$CC:CD90', 'strings')],
    'BattleMessages': [('$CE:EF11', 'strtable')],
    'MenuNameTexts': [('$FF:CF3B', 'strtable')],
    'MenuSlotTexts': [('$FF:D03E', 'strtable')],
    'MenuEraTexts': [('$FF:D396', 'strtable')],
    'MenuSettingsTexts': [('$FF:D3FE', 'strtable')],
    'ItemNames': [('$CC:0B5E', 'records 11 $EF')],
    'TechNames': [('$CC:15C4', 'records 11 $EF')],
    'EnemyNames': [('$CC:6500', 'records 11 $EF')],
    'Credits': [('$FD:A000', 'ascii')],
}
ROWS = {start: (unit, fmt) for unit, rows in UNITS.items() for start, fmt in rows}
DICTIONARY_UNIT = 'Dictionary'
ASCII_BLOCK_END = 0x80          # Credits_Text: a byte >= $80 ends a block


def snes(offset: int) -> str:
    return f'${0xC0 + (offset >> 16):02X}:{offset & 0xFFFF:04X}'


def _word(rom: bytes, o: int) -> int:
    return rom[o] | rom[o + 1] << 8


# ── Text <-> bytes, for one stretch of text ─────────────────────────────────

class Dictionary:
    """The dictionary entries (bytes) and the greedy compressor."""

    def __init__(self, entries: list[bytes]):
        self.entries = entries
        self.by_text = {}
        self.all_by_text = {}       # every entry, the one code $12 alone reaches too
        for k, e in enumerate(entries):
            t = glyph_text(e, strict=True)
            if t is not None:
                self.all_by_text.setdefault(t, k)
        for k, e in enumerate(entries):
            t = glyph_text(e, strict=True)
            if t is not None and k < DICT_ENTRIES:
                self.by_text.setdefault(t, k)
        self.entries_ok = {k for k, e in enumerate(entries) if e and min(e) >= FIRST_GLYPH}
        self.candidates: dict[int, list[tuple[bytes, int]]] = {}
        for k, e in enumerate(entries[:DICT_ENTRIES]):
            if k in GREEDY_SKIP or not e or min(e) < FIRST_GLYPH:
                continue
            self.candidates.setdefault(e[0], []).append((e, k))
        for lst in self.candidates.values():
            lst.sort(key=lambda x: -len(x[0]))

    def compress(self, glyphs: bytes) -> bytes:
        out, i = bytearray(), 0
        while i < len(glyphs):
            for e, k in self.candidates.get(glyphs[i], ()):
                if glyphs.startswith(e, i):
                    out.append(FIRST_DICT + k)
                    i += len(e)
                    break
            else:
                out.append(glyphs[i])
                i += 1
        return bytes(out)


def glyph_text(data: bytes, strict: bool = False) -> str | None:
    out = []
    for b in data:
        if b in GLYPHS:
            out.append(GLYPHS[b])
        elif strict:
            return None
        else:
            out.append(f'{{g{b:02X}}}')
    return ''.join(out)


def _tokens(data: bytes) -> list[tuple]:
    """A stretch of TextWin string bytes as tokens: ('g', b), ('d', k),
    ('c', code, operand or None), ('raw', b) for a code whose operand is
    cut off by the stretch's end."""
    out, i = [], 0
    while i < len(data):
        b = data[i]
        i += 1
        if b >= FIRST_GLYPH:
            out.append(('g', b))
        elif b >= FIRST_DICT:
            out.append(('d', b - FIRST_DICT))
        elif OPERANDS[b]:
            if i >= len(data):
                out.append(('raw', b))
            else:
                out.append(('c', b, data[i]))
                i += 1
        else:
            out.append(('c', b, None))
    return out


def _code_tag(code: int, arg: int | None, dic: 'Dictionary | None' = None) -> str:
    if arg is None:
        return '{' + CODE_TAGS[code] + '}'
    if code in WIDE:
        return f'{{wide {code:02X}{arg:02X}}}'
    if code == WAIT:
        return f'{{wait {arg:02X}}}'
    if code == EXT and arg in EXT_TAGS:
        return '{' + EXT_TAGS[arg] + '}'
    if code == EXT and dic is not None and arg >= CODE12_DICT:
        k = CODE12_BASE + arg - CODE12_DICT
        t = glyph_text(dic.entries[k], strict=True) if k < len(dic.entries) else None
        if t is not None and dic.all_by_text.get(t) == k:
            return f'{{ext [{t}]}}'
    return f'{{ext {arg:02X}}}'


def decode_msg(data: bytes, dic: Dictionary, stats: dict | None = None, compress: bool = True) -> str:
    """A stretch of TextWin string bytes as readable text: fully expanded
    where the greedy rule gives the original bytes back, else explicit
    (`compress` False: the text of a table that uses no dictionary, its
    glyphs as they are and any dictionary byte as [xyz])."""
    out = []
    run: list[tuple] = []

    def flush():
        if not run:
            return
        orig = bytes(t[1] if t[0] == 'g' else FIRST_DICT + t[1] for t in run)
        expanded = b''.join(bytes([t[1]]) if t[0] == 'g' else dic.entries[t[1]] for t in run)
        if compress and all(t[0] == 'g' or t[1] in dic.entries_ok for t in run) \
                and dic.compress(expanded) == orig:
            out.append(glyph_text(expanded))
        else:
            parts = []
            for t in run:
                if t[0] == 'g':
                    parts.append(glyph_text(bytes([t[1]])))
                else:
                    text = glyph_text(dic.entries[t[1]], strict=True)
                    parts.append(f'[{text}]' if text is not None and dic.by_text.get(text) == t[1]
                                 else f'{{dict {t[1]:02X}}}')
            out.append('«' + ''.join(parts) + '»' if compress else ''.join(parts))
            if stats is not None and compress:
                stats['explicit_runs'] = stats.get('explicit_runs', 0) + 1
        if stats is not None:
            stats['dict_bytes'] = stats.get('dict_bytes', 0) + sum(1 for t in run if t[0] == 'd')
        run.clear()

    for t in _tokens(data):
        if t[0] in ('g', 'd'):
            run.append(t)
            continue
        flush()
        if t[0] == 'raw':
            out.append(f'{{${t[1]:02X}}}')
            continue
        out.append(_code_tag(t[1], t[2], dic))
        if t[1] in BREAK_AFTER:
            out.append('\n')
    flush()
    return ''.join(out)


TAG = re.compile(r'\{([^{}]*)\}|\[([^\[\]]*)\]|«([^«»]*)»|(.)', re.S)


def _parse_tag(tag: str, where: str, dic: 'Dictionary | None' = None) -> bytes:
    m = re.fullmatch(r'ext \[([^\[\]]*)\]', tag)
    if m:
        k = dic.all_by_text.get(m.group(1)) if dic is not None else None
        if k is None or not CODE12_BASE <= k < CODE12_BASE + 256 - CODE12_DICT:
            raise TextError(f'{where}: {{{tag}}}: no dictionary entry code $12 reaches')
        return bytes([EXT, k - CODE12_BASE + CODE12_DICT])
    if tag in TAG_CODES:
        return bytes([TAG_CODES[tag]])
    if tag in EXT_TAGS.values():
        return bytes([EXT, next(k for k, v in EXT_TAGS.items() if v == tag)])
    m = re.fullmatch(r'\$([0-9A-Fa-f]{2})', tag)
    if m:
        return bytes([int(m.group(1), 16)])
    m = re.fullmatch(r'g([0-9A-Fa-f]{2})', tag)
    if m:
        return bytes([int(m.group(1), 16)])
    m = re.fullmatch(r'wide ([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})', tag)
    if m and int(m.group(1), 16) in WIDE:
        return bytes([int(m.group(1), 16), int(m.group(2), 16)])
    m = re.fullmatch(r'(wait|ext|dict) ([0-9A-Fa-f]{2})', tag)
    if m:
        v = int(m.group(2), 16)
        if m.group(1) == 'dict':
            if v >= DICT_ENTRIES:
                raise TextError(f'{where}: {{dict {v:02X}}}: a string byte reaches entries 00-'
                                f'{DICT_ENTRIES - 1:02X} only')
            return bytes([FIRST_DICT + v])
        return bytes([WAIT if m.group(1) == 'wait' else EXT, v])
    raise TextError(f'{where}: unknown tag {{{tag}}}')


def _glyphs_of(text: str, where: str, dic: Dictionary | None) -> list[tuple[str, bytes]]:
    """Text with characters, {gXX}, {$XX} and (with a dictionary) [xyz] as
    ('g', glyph bytes) and ('x', bytes taken as they are) items."""
    out = []
    for m in TAG.finditer(text):
        tag, ref, lit, ch = m.groups()
        if ch is not None:
            if ch == '\n':
                continue
            if ch not in CHARS:
                raise TextError(f'{where}: {ch!r} is no glyph of the text font')
            out.append(('g', bytes([CHARS[ch]])))
        elif tag is not None:
            if re.fullmatch(r'g[0-9A-Fa-f]{2}', tag):
                out.append(('g', _parse_tag(tag, where)))
            elif re.fullmatch(r'\$[0-9A-Fa-f]{2}', tag) or (dic is not None and tag.startswith('dict ')):
                out.append(('x', _parse_tag(tag, where)))
            else:
                raise TextError(f'{where}: tag {{{tag}}} is not allowed here')
        elif ref is not None:
            if dic is None or ref not in dic.by_text:
                raise TextError(f'{where}: [{ref}] is no dictionary entry')
            out.append(('x', bytes([FIRST_DICT + dic.by_text[ref]])))
        else:
            raise TextError(f'{where}: «» is not allowed here')
    return out


def encode_glyphs(text: str, where: str) -> bytes:
    return b''.join(b for _, b in _glyphs_of(text, where, None))


def encode_msg(text: str, dic: Dictionary, where: str, compress: bool = True) -> bytes:
    out, run = bytearray(), bytearray()

    def flush():
        if run:
            out.extend(dic.compress(bytes(run)) if compress else run)
            run.clear()

    for m in TAG.finditer(text):
        tag, ref, lit, ch = m.groups()
        if ch is not None:
            if ch == '\n':
                continue
            if ch not in CHARS:
                raise TextError(f'{where}: {ch!r} is no glyph of the text font')
            run.append(CHARS[ch])
            continue
        if tag is not None and re.fullmatch(r'g[0-9A-Fa-f]{2}', tag):
            run.append(int(tag[1:], 16))
            continue
        flush()
        if tag is not None:
            out.extend(_parse_tag(tag, where, dic))
        elif ref is not None:
            if ref not in dic.by_text:
                raise TextError(f'{where}: [{ref}] is no dictionary entry')
            out.append(FIRST_DICT + dic.by_text[ref])
        else:
            out.extend(b"".join(b for _, b in _glyphs_of(lit, where, dic)))
    flush()
    return bytes(out)


def decode_ascii(data: bytes) -> str:
    out = []
    for b in data:
        c = chr(b)
        if b == ASCII_BLOCK_END:
            out.append('{block}\n')
        elif 0x20 <= b < 0x7F and c not in '{}':
            out.append(c)
            if c == '/':
                out.append('\n')
        else:
            out.append(f'{{${b:02X}}}')
    return ''.join(out)


def encode_ascii(text: str, where: str) -> bytes:
    out = bytearray()
    for m in re.finditer(r'\{([^{}]*)\}|(.)', text, re.S):
        tag, ch = m.groups()
        if ch is not None:
            if ch != '\n':
                if not 0x20 <= ord(ch) < 0x7F:
                    raise TextError(f'{where}: {ch!r} is not ASCII text')
                out.append(ord(ch))
        elif tag == 'block':
            out.append(ASCII_BLOCK_END)
        elif re.fullmatch(r'\$[0-9A-Fa-f]{2}', tag):
            out.append(int(tag[1:], 16))
        else:
            raise TextError(f'{where}: unknown tag {{{tag}}}')
    return bytes(out)


# Lines of text must not begin like a directive or a comment; a character
# there is written as its tag.
def _safe_lines(text: str) -> str:
    lines = []
    for line in text.split('\n'):
        if line[:1] in ('@', ';'):
            line = f'{{${ord(line[0]):02X}}}' + line[1:]
        lines.append(line)
    return '\n'.join(lines)


# ── Units: extraction (ROM -> readable) ─────────────────────────────────────

def rom_dictionary(rom: bytes) -> Dictionary:
    base = DICT_PTRS - 0xC00000
    entries = []
    for k in range(DICT_ENTRIES + 1):
        o = (base & 0xFF0000) | _word(rom, base + 2 * k)
        entries.append(bytes(rom[o + 1:o + 1 + rom[o]]))
    return _dictionary(entries)


def _dictionary(entries: list[bytes]) -> Dictionary:
    return Dictionary(entries)


def _string_end(rom: bytes, o: int, stop: int) -> int:
    """The offset after the string at o ($00 and the operands as the decoder
    reads them), at most stop."""
    while o < stop:
        b = rom[o]
        o += 1
        if b == END:
            return o
        if b < FIRST_DICT and OPERANDS[b]:
            o += 1
    return min(o, stop)


def _table_count(rom: bytes, s: int, e: int) -> int:
    """The entries of a strtable's pointer table: the first pointer bounds
    it; it ends early at the first entry that does not point after it into
    the row (TechInfo's table is followed by bytes that are no pointers)."""
    first = _word(rom, s)
    n0 = (first - (s & 0xFFFF)) // 2
    if n0 <= 0 or s + 2 * n0 > e:
        raise TextError(f'{snes(s)}: the first word {first:04X} is no pointer past the table')
    bank = s & 0xFF0000
    n = 0
    while n < n0 and s + 2 * n0 <= (bank | _word(rom, s + 2 * n)) < e:
        n += 1
    return n


def extract_unit(rom: bytes, unit: str, pieces: list[dict], dic: Dictionary | None = None,
                 stats: dict | None = None) -> str:
    """The readable file of a unit. `pieces`: the manifest's pieces of the
    unit, in address order (label, offset, stop, param)."""
    dic = dic or rom_dictionary(rom)
    stats = {} if stats is None else stats
    tables = {}             # name -> (offset of the table, count)
    regions = {}            # label -> [(start, end, kind, extra)]
    for p in pieces:
        s, e, fmt = p['offset'], p['stop'], p['param'].split()
        regs = []
        name = fmt[1] if fmt[0] == 'ptrs' else 'ptr' if fmt[0] == 'strtable' else None
        if name in tables:
            raise TextError(f'{unit}: two pointer tables named {name}')
        if fmt[0] == 'ptrs':
            n = (e - s) // 2
            tables[fmt[1]] = (s, n)
            regs.append((s, s + 2 * n, 'table', fmt[1]))
            if s + 2 * n < e:
                regs.append((s + 2 * n, e, 'bytes', None))
        elif fmt[0] == 'strtable':
            n = _table_count(rom, s, e)
            tables['ptr'] = (s, n)
            regs.append((s, s + 2 * n, 'table', 'ptr'))
            regs.append((s + 2 * n, e, 'strings', None))
        elif fmt[0] == 'strings':
            regs.append((s, e, 'strings', None))
        elif fmt[0] == 'dict':
            o = s
            while o < e and o + 1 + rom[o] <= e:
                regs.append((o, o + 1 + rom[o], 'dict', None))
                o += 1 + rom[o]
            if o < e:
                regs.append((o, e, 'bytes', None))
        elif fmt[0] == 'records':
            size, pad = int(fmt[1]), int(fmt[2][1:], 16)
            n = (e - s) // size
            regs += [(s + k * size, s + (k + 1) * size, 'record', (size, pad)) for k in range(n)]
            if s + n * size < e:
                regs.append((s + n * size, e, 'bytes', None))
        elif fmt[0] == 'ascii':
            last = max((o for o in range(s, e) if rom[o] == ASCII_BLOCK_END), default=s - 1) + 1
            regs.append((s, last, 'ascii', None))
            if last < e:
                regs.append((last, e, 'bytes', None))
        else:
            raise TextError(f'{p["label"]}: unknown format {p["param"]!r}')
        regions[p['label']] = regs

    # Pointer targets inside the unit ({file offset: entries}); other values stay raw.
    def owner(t):
        for p in pieces:
            if p['offset'] <= t < p['stop']:
                return p
        return None

    targets: dict[int, list[str]] = {}
    raw_sets = []
    for name, (ts, n) in tables.items():
        bank = ts & 0xFF0000
        for i in range(n):
            v = _word(rom, ts + 2 * i)
            t = bank | v
            ref = f'{name}:{i}' if name != 'ptr' else str(i)
            if v and owner(t) is not None:
                targets.setdefault(t, []).append(ref)
            else:
                raw_sets.append((ref, v))

    # Strings regions: the text runs from the first target (or the start when
    # nothing points in) to the end of the string at the last target; the
    # bytes around are not text.
    for p in pieces:
        new = []
        for s, e, kind, extra in regions[p['label']]:
            if kind != 'strings':
                new.append((s, e, kind, extra))
                continue
            inside = sorted(t for t in targets if s <= t < e)
            if not inside:
                new.append((s, e, 'text', None))
                continue
            a, z = inside[0], _string_end(rom, inside[-1], e)
            if a > s:
                new.append((s, a, 'bytes', None))
            new.append((a, z, 'text', None))
            if z < e:
                new.append((z, e, 'bytes', None))
        regions[p['label']] = new

    # Targets that are not at a place a marker can go: kept as raw values.
    def placeable(t):
        p = owner(t)
        for s, e, kind, _ in regions[p['label']]:
            if s <= t < e:
                return kind in ('text', 'bytes', 'ascii') or t == s and kind in ('dict', 'record')
        return False

    for t in [t for t in targets if not placeable(t)]:
        raw_sets += [(ref, t & 0xFFFF) for ref in targets.pop(t)]

    out = [f'; {unit}: text extracted from your own ROM by tools/text.py (never commit it).',
           '; The build encodes this file back into the bytes (the format is in tools/text.py).',
           '; Like every asset it is extracted again when it no longer is what extraction',
           '; wrote, and a piece whose size changes would fail the build.']
    strings = 0
    for p in pieces:
        out.append('')
        out.append(f'@piece {p["label"]} {snes(p["offset"])}')
        mode = None
        for s, e, kind, extra in regions[p['label']]:
            if kind == 'table':
                out.append(f'@table {extra} {(e - s) // 2}')
                for ref, v in raw_sets:
                    if (ref.rpartition(':')[0] or 'ptr') == extra:
                        out.append(f'@set {ref} ${v:04X}')
                continue
            cuts = sorted({s} | {t for t in targets if s < t < e})
            if kind == 'text':
                o = s
                while o < e:            # string starts after each {end}
                    o = _string_end(rom, o, e)
                    if o < e:
                        cuts.append(o)
                cuts = sorted(set(cuts))
            segments = list(zip(cuts, cuts[1:] + [e]))
            want = {'text': 'msg', 'ascii': 'ascii'}.get(kind)
            if kind == 'text':
                trial: dict = {}
                for a, z in segments:
                    decode_msg(rom[a:z], dic, trial)
                if trial.get('explicit_runs') and not trial.get('dict_bytes'):
                    want = 'plain'      # a table that uses no dictionary
            if want and mode != want:
                out.append(f'@mode {want}')
                mode = want
            for a, z in segments:
                if a in targets:
                    out.append('@at ' + ' '.join(targets[a]))
                if kind == 'text':
                    strings += 1
                    out.append(_safe_lines(decode_msg(rom[a:z], dic, stats, compress=want == 'msg')).rstrip('\n'))
                elif kind == 'ascii':
                    out.append(_safe_lines(decode_ascii(rom[a:z])).rstrip('\n'))
                elif kind == 'dict':
                    text = glyph_text(rom[a + 1:z])
                    out.append(f'@d {text}')
                elif kind == 'record':
                    size, pad = extra
                    body = bytes(rom[a:z]).rstrip(bytes([pad]))
                    if mode != 'records':
                        out.append(f'@records {size} ${pad:02X}')
                        mode = 'records'
                    out.append(('@r ' + glyph_text(body)) if body else '@r')
                else:
                    raise TextError(f'{p["label"]}: {snes(a)}-{snes(z - 1)} ({z - a} B) is not text: '
                                    f'its own row of symbols/data_survey.csv, not part of the unit')
    stats['strings'] = stats.get('strings', 0) + strings
    return '\n'.join(out) + '\n'


# ── Units: encoding (readable -> bytes) ─────────────────────────────────────

def parse_unit(text: str, name: str = '<unit>') -> list[dict]:
    """The pieces of a readable file: [{label, address, items}], each item a
    (kind, ..., line number) tuple in file order."""
    pieces: list[dict] = []
    mode = 'msg'
    records = None
    buf: list[str] = []
    buf_line = 0

    def flush():
        nonlocal buf
        if buf:
            if not pieces:
                raise TextError(f'{name}:{buf_line}: text before the first @piece')
            pieces[-1]['items'].append(('text', mode, '\n'.join(buf), buf_line))
            buf = []

    for no, line in enumerate(text.split('\n'), 1):
        where = f'{name}:{no}'
        if line.startswith(';') or not line:
            continue
        if not line.startswith('@'):
            if not buf:
                buf_line = no
            buf.append(line)
            continue
        flush()
        word, _, rest = line[1:].partition(' ')
        if word in ('r', 'd'):
            if not pieces:
                raise TextError(f'{where}: @{word} before the first @piece')
            if word == 'r' and records is None:
                raise TextError(f'{where}: @r before @records')
            pieces[-1]['items'].append((word, rest, records, no))
            continue
        args = rest.split()
        if word == 'piece':
            if len(args) != 2:
                raise TextError(f'{where}: @piece LABEL $BB:AAAA')
            pieces.append({'label': args[0], 'address': args[1], 'items': []})
            mode, records = 'msg', None
            continue
        if not pieces:
            raise TextError(f'{where}: @{word} before the first @piece')
        items = pieces[-1]['items']
        try:
            if word == 'mode':
                if args not in (['msg'], ['plain'], ['glyph'], ['ascii']):
                    raise ValueError
                mode = args[0]
            elif word == 'table':
                items.append(('table', args[0], int(args[1]), no))
            elif word == 'at':
                refs = [(a.rpartition(':')[0] or 'ptr', int(a.rpartition(':')[2])) for a in args]
                if not refs:
                    raise ValueError
                items.append(('at', refs, no))
            elif word == 'set':
                tname, _, i = args[0].rpartition(':')
                if not re.fullmatch(r'\$[0-9A-Fa-f]{4}', args[1]):
                    raise ValueError
                items.append(('set', tname or 'ptr', int(i), int(args[1][1:], 16), no))
            elif word == 'records':
                if not re.fullmatch(r'\$[0-9A-Fa-f]{2}', args[1]):
                    raise ValueError
                records = (int(args[0]), int(args[1][1:], 16))
            else:
                raise TextError(f'{where}: unknown directive @{word}')
        except (ValueError, IndexError):
            raise TextError(f'{where}: malformed @{word}: {line}') from None
    flush()
    return pieces


def encode_unit(text: str, pieces: list[dict], dic: Dictionary | None, name: str = '<unit>') -> dict[str, bytes]:
    """{label: bytes} of a unit's readable file. `pieces`: the manifest's
    pieces of the unit (label, offset); `dic`: the dictionary (None for the
    dictionary unit itself, which has no msg text)."""
    parsed = parse_unit(text, name)
    want = [(p['label'], p['offset']) for p in pieces]
    have = [(p['label'], p['address']) for p in parsed]
    if [w[0] for w in want] != [h[0] for h in have] or \
            any(snes(o) != a for (_, o), (_, a) in zip(want, have)):
        raise TextError(f'{name}: its pieces are {have}, the manifest\'s '
                        f'{[(lbl, snes(o)) for lbl, o in want]}')
    out: dict[str, bytearray] = {}
    tables: dict[str, tuple[str, int, int]] = {}       # name -> (label, position, count)
    entries: dict[tuple[str, int], int] = {}            # (table, i) -> pointer value
    for p, (label, offset) in zip(parsed, want):
        buf = out[label] = bytearray()
        for item in p['items']:
            kind, where = item[0], f'{name}:{item[-1]}'
            if kind == 'text':
                _, mode, body, _ = item
                if mode in ('msg', 'plain'):
                    if dic is None:
                        raise TextError(f'{where}: {mode} text needs the dictionary')
                    buf += encode_msg(body, dic, where, compress=mode == 'msg')
                elif mode == 'ascii':
                    buf += encode_ascii(body, where)
                else:
                    buf += encode_glyphs(body, where)
            elif kind == 'table':
                if item[1] in tables:
                    raise TextError(f'{where}: table {item[1]} twice')
                tables[item[1]] = (label, len(buf), item[2])
                buf += bytes(2 * item[2])
            elif kind == 'at':
                addr = 0xC00000 + offset + len(buf)
                for ref in item[1]:
                    if ref in entries:
                        raise TextError(f'{where}: entry {ref[0]}:{ref[1]} is set twice')
                    entries[ref] = addr
            elif kind == 'set':
                ref = (item[1], item[2])
                if ref in entries:
                    raise TextError(f'{where}: entry {ref[0]}:{ref[1]} is set twice')
                entries[ref] = item[3] | -1 << 24      # a raw value (no bank check)
            elif kind == 'd':
                body = encode_glyphs(item[1], where)
                if len(body) > 255:
                    raise TextError(f'{where}: a dictionary entry holds at most 255 glyphs')
                buf.append(len(body))
                buf += body
            elif kind == 'r':
                size, pad = item[2]
                body = encode_glyphs(item[1], where)
                if len(body) > size:
                    raise TextError(f'{where}: a record of {len(body)} bytes; at most {size}')
                buf += body + bytes([pad]) * (size - len(body))
    starts = {label: offset for label, offset in want}
    for tname, (label, pos, count) in tables.items():
        bank = 0xC0 + (starts[label] >> 16)
        for i in range(count):
            v = entries.pop((tname, i), None)
            if v is None:
                raise TextError(f'{name}: entry {tname}:{i} points nowhere (no @at or @set)')
            if v < 0:
                v &= 0xFFFF
            elif v >> 16 != bank:
                raise TextError(f'{name}: entry {tname}:{i} points into bank ${v >> 16:02X}, '
                                f'the table is in ${bank:02X}')
            out[label][pos + 2 * i:pos + 2 * i + 2] = (v & 0xFFFF).to_bytes(2, 'little')
    if entries:
        (tname, i), _ = next(iter(entries.items()))
        raise TextError(f'{name}: @at or @set for {tname}:{i}, which no table has')
    return {label: bytes(b) for label, b in out.items()}


def dictionary_of(encoded: dict[str, bytes], pieces: list[dict]) -> Dictionary:
    """The dictionary from the encoded Dictionary unit: entry k is the
    length-prefixed string TextWin_DictPtrs entry k points at."""
    image = {}
    for p in pieces:
        for k, b in enumerate(encoded[p['label']]):
            image[p['offset'] + k] = b
    base = DICT_PTRS - 0xC00000
    entries = []
    for k in range(DICT_ENTRIES + 1):
        if base + 2 * k + 1 not in image:
            raise TextError(f'the dictionary unit does not hold TextWin_DictPtrs entry {k}')
        o = (base & 0xFF0000) | image[base + 2 * k] | image[base + 2 * k + 1] << 8
        if o not in image:
            raise TextError(f'dictionary entry {k} points outside the dictionary unit')
        entries.append(bytes(image[o + 1 + j] for j in range(image[o])))
    return _dictionary(entries)


def units_of(pieces: list[dict]) -> dict[str, list[dict]]:
    """{unit: its pieces in address order} from the manifest's text pieces."""
    out: dict[str, list[dict]] = {}
    for p in pieces:
        if p['piece'] == 'text':
            out.setdefault(Path(p['asset']).stem, []).append(p)
    return out


def encode_units(texts: dict[str, str], units: dict[str, list[dict]]) -> dict[str, bytes]:
    """{label: bytes} of every unit, the dictionary first (msg text needs it)."""
    if DICTIONARY_UNIT not in units:
        raise TextError('no Dictionary unit in the manifest')
    out = encode_unit(texts[DICTIONARY_UNIT], units[DICTIONARY_UNIT], None, DICTIONARY_UNIT)
    dic = dictionary_of(out, units[DICTIONARY_UNIT])
    for unit, pieces in units.items():
        if unit != DICTIONARY_UNIT:
            out.update(encode_unit(texts[unit], pieces, dic, unit))
    return out


# ── Command line ────────────────────────────────────────────────────────────

def _manifest_units() -> dict[str, list[dict]]:
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    return units_of(extract_data.read_manifest())


def check(rom: bytes, verbose: bool = False) -> list[str]:
    """Extract every unit and encode it back; the problems (empty: exact)."""
    units = _manifest_units()
    dic = rom_dictionary(rom)
    texts, problems = {}, []
    for unit, pieces in units.items():
        stats: dict = {}
        texts[unit] = extract_unit(rom, unit, pieces, dic, stats)
        if verbose:
            size = sum(p['stop'] - p['offset'] for p in pieces)
            print(f'  {unit:<22} {size:>7,} B  {stats.get("strings", 0):>5} strings  '
                  f'{stats.get("dict_bytes", 0):>6,} dictionary bytes  '
                  f'{stats.get("explicit_runs", 0)} explicit runs')
    encoded = encode_units(texts, units)
    for pieces in units.values():
        for p in pieces:
            if encoded[p['label']] != rom[p['offset']:p['stop']]:
                got = encoded[p['label']]
                where = next((k for k in range(min(len(got), p['stop'] - p['offset']))
                              if got[k] != rom[p['offset'] + k]), min(len(got), p['stop'] - p['offset']))
                problems.append(f'{p["label"]}: encodes to {len(got)} B, not the ROM\'s '
                                f'{p["stop"] - p["offset"]}; first difference at {snes(p["offset"] + where)}')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check', 'stats'))
    args = ap.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    try:
        rom = extract_data.read_rom()
        problems = check(rom, verbose=args.command == 'stats')
    except (TextError, extract_data.DataError) as e:
        print(f'text: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'text: {p}', file=sys.stderr)
    if problems:
        return 1
    print('OK: every text unit extracts and encodes back to the ROM\'s bytes')
    return 0


if __name__ == '__main__':
    sys.exit(main())
