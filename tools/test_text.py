#!/usr/bin/env python3
"""
test_text.py — Tests for tools/text.py, the readable text and its encoder.

    python3 tools/test_text.py          (from the repository root)

Without the ROM: the control codes follow the matched TextWin_CodeTable;
the encoder on small synthetic strings and units (the greedy dictionary
rule and the entries it skips, explicit runs, every tag, pointer tables
with shared and raw entries, counted and fixed-size strings, ASCII), the
decoder's output encoding back to the same bytes, and the errors an edit
can make; the units are survey rows of the text kind.

With the ROM: every unit extracts and encodes back to the ROM's bytes and
holds only text, the 15 message tables hold 4,579 pointers, and the greedy
rule gives every one of their 10,883 glyph runs (no explicit run).
"""

import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402
import text  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists()
G = text.CHARS


def glyphs(s: str) -> bytes:
    return bytes(G[c] for c in s)


# A small dictionary of neutral strings: entries 0-3, one code $12 reaches
# ($20), and 116-118, which the greedy rule skips, so a test entry there
# must never be chosen.
ENTRIES = [b''] * (text.DICT_ENTRIES + 1)
for k, s in {0: 'abc', 1: 'ab', 2: 'bc', 3: 'c a', 0x20: 'mno', 116: 'wxyz', 117: 'xy',
             118: 'z w', 127: 'kkk'}.items():
    ENTRIES[k] = glyphs(s)
DIC = text.Dictionary(ENTRIES)


def unit(body: str, label: str = 'P', address: str = '$D8:0000') -> str:
    return f'@piece {label} {address}\n' + body


def piece(label: str = 'P', offset: int = 0x180000) -> dict:
    return {'label': label, 'offset': offset}


class Codes(unittest.TestCase):

    def test_operands_follow_the_code_table(self):
        handlers = text.code_table()
        self.assertEqual(len(handlers), text.FIRST_DICT)
        self.assertEqual({c for c, n in text.OPERANDS.items() if n},
                         {c for c, h in enumerate(handlers)
                          if h in ('TextWin_CodeStatusArg', 'TextWin_CodeWide', 'TextWin_CodeExt')})
        self.assertEqual(text.END, 0)
        self.assertEqual(text.TAG_CODES['line indent'], 6)
        self.assertEqual(text.TAG_CODES['char0'], 0x13)
        self.assertEqual(text.TAG_CODES['item'], 0x1F)

    def test_glyph_map_is_one_to_one(self):
        self.assertEqual(len(text.GLYPHS), len(text.CHARS))
        self.assertTrue(all(g >= text.FIRST_GLYPH for g in text.GLYPHS))
        for c in '{}[]«»@;':
            self.assertNotIn(c, text.CHARS)
        self.assertEqual(text.CHARS['0'], 0xD4)     # TextWin_HexGlyphs
        self.assertEqual(text.CHARS['A'], 0xA0)


class Encoder(unittest.TestCase):

    def enc(self, s: str, compress: bool = True) -> bytes:
        return text.encode_msg(s, DIC, 'test', compress)

    def test_greedy_longest_match(self):
        d = text.FIRST_DICT
        self.assertEqual(self.enc('abc'), bytes([d + 0]))
        self.assertEqual(self.enc('abq'), bytes([d + 1, G['q']]))
        self.assertEqual(self.enc('bc abc'), bytes([d + 2, G[' '], d + 0]))
        self.assertEqual(self.enc('c abc'), bytes([d + 3, d + 2]))      # left to right, longest first
        self.assertEqual(self.enc('wxyz'), glyphs('wxyz'))             # 116-118 are skipped
        self.assertEqual(self.enc('kkk'), glyphs('kkk'))                # 127: only through code $12

    def test_runs_end_at_codes(self):
        d = text.FIRST_DICT
        self.assertEqual(self.enc('a{line}bc{end}'), bytes([G['a'], 5, d + 2, 0]))
        self.assertEqual(self.enc('a\nbc'), bytes([d + 0]))             # a line break is no byte

    def test_explicit_forms(self):
        d = text.FIRST_DICT
        self.assertEqual(self.enc('«abc»'), glyphs('abc'))
        self.assertEqual(self.enc('«a[bc]»'), bytes([G['a'], d + 2]))
        self.assertEqual(self.enc('[ab]c'), bytes([d + 1, G['c']]))
        self.assertEqual(self.enc('{dict 74}'), bytes([d + 116]))
        self.assertEqual(self.enc('abc', compress=False), glyphs('abc'))
        self.assertEqual(self.enc('{ext [mno]}'), bytes([0x12, 0x20 - 0x1F + 8]))
        self.assertEqual(self.enc('{ext [kkk]}'), bytes([0x12, 0x68]))
        self.assertEqual(text.decode_msg(bytes([0x12, 9]), DIC), '{ext [mno]}')

    def test_tags(self):
        cases = {'{end}': b'\x00', '{wait 03}': b'\x03\x03', '{wide 02D0}': b'\x02\xD0',
                 '{tech}': b'\x12\x00', '{enemy}': b'\x12\x01', '{ext 68}': b'\x12\x68',
                 '{char6}': b'\x19', '{name0}': b'\x1A', '{member2}': b'\x1D', '{nadia}': b'\x1E',
                 '{num24}': b'\x0F', '{wait page indent}': b'\x0C', '{$9F}': b'\x9F', '{gF4}': b'\xF4'}
        for tag, want in cases.items():
            with self.subTest(tag=tag):
                self.assertEqual(self.enc(tag), want)

    def test_decode_encode_round_trip(self):
        rnd = random.Random(5)
        for n in range(300):
            data = bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 40)))
            for compress in (True, False):
                with self.subTest(n=n, compress=compress):
                    s = text.decode_msg(data, DIC, compress=compress)
                    self.assertEqual(self.enc(s, compress), data)

    def test_expanded_when_the_rule_holds(self):
        d = text.FIRST_DICT
        self.assertEqual(text.decode_msg(bytes([d + 0, G[' '], d + 1, G['q'], 0]), DIC), 'abc abq{end}\n')
        self.assertEqual(text.decode_msg(glyphs('abc'), DIC), '«abc»')
        self.assertEqual(text.decode_msg(bytes([G['a'], d + 2]), DIC), '«a[bc]»')

    def test_errors(self):
        for bad in ('{nope}', 'ä', '[zz]', '{dict 7F}', '{wide 03D0}', '{ext [abc]}', '{ext [zz]}'):
            with self.subTest(bad=bad), self.assertRaises(text.TextError):
                self.enc(bad)


class Units(unittest.TestCase):

    def test_pointer_table_and_strings(self):
        body = ('@table ptr 4\n@set 3 $0000\n@mode msg\n@at 0 2\nabc{end}\n'
                '@at 1\nbc{wait 00}\n; a comment\n\nbc{end}\n')
        out = text.encode_unit(unit(body), [piece()], DIC)['P']
        d = text.FIRST_DICT
        self.assertEqual(out, bytes([0x08, 0, 0x0A, 0, 0x08, 0, 0, 0,
                                     d + 0, 0, d + 2, 3, 0, d + 2, 0]))

    def test_pointer_across_pieces_and_records(self):
        body = ('@table ptr 2\n'
                '@piece Q $D8:0100\n@at 1\n@d abc\n@at 0\n@d x\n@records 4 $EF\n@r a\n@r ab_d\n@r\n')
        out = text.encode_unit(unit(body), [piece(), piece('Q', 0x180100)], None)
        self.assertEqual(out['P'], bytes([0x04, 0x01, 0x00, 0x01]))
        self.assertEqual(out['Q'], bytes([3]) + glyphs('abc') + bytes([1, G['x']])
                         + glyphs('a') + b'\xEF' * 3 + glyphs('ab') + b'\xFF' + glyphs('d') + b'\xEF' * 4)

    def test_ascii(self):
        out = text.encode_unit(unit('@mode ascii\nAB/\nC{block}{$00}\n'), [piece()], None)['P']
        self.assertEqual(out, b'AB/C\x80\x00')
        self.assertEqual(text.encode_ascii(text.decode_ascii(bytes(range(256))), 't'), bytes(range(256)))

    def test_unit_errors(self):
        cases = {
            'entry_unset': '@table ptr 2\n@at 0\nx',
            'entry_twice': '@table ptr 1\n@at 0\n@at 0\nx',
            'no_table': '@at 3\nx',
            'record_long': '@records 2 $EF\n@r abc',
            'other_bank': '@table ptr 1\n',
            'not_text': '@bytes 01 02',
        }
        for name, body in cases.items():
            with self.subTest(case=name), self.assertRaises(text.TextError):
                pieces = [piece()]
                if name == 'other_bank':
                    body += '@piece Q $D9:0000\n@at 0\nx'
                    pieces.append(piece('Q', 0x190000))
                text.encode_unit(unit(body), pieces, DIC)
        with self.assertRaises(text.TextError):         # pieces must be the manifest's
            text.encode_unit(unit('x', 'R'), [piece()], DIC)

    def test_units_are_survey_text_rows(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        for start, (u, fmt) in text.ROWS.items():
            with self.subTest(row=start):
                self.assertIn(start, rows)
                self.assertIn(rows[start]['kind'], ('text', 'table'))
        pieces = [p for p in ed.read_manifest() if p['piece'] == 'text']
        self.assertEqual(len(pieces), len(text.ROWS))
        self.assertEqual(set(text.units_of(pieces)), set(text.UNITS))


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_every_unit_round_trips(self):
        self.assertEqual(text.check(ed.read_rom()), [])

    def test_units_hold_only_text(self):
        # Extraction refuses a unit with bytes that are not text: here the
        # enemy names' row stretched over the 2 bytes after the last name.
        rom = ed.read_rom()
        names = text.units_of(ed.read_manifest())['EnemyNames']
        longer = [dict(names[0], stop=names[0]['stop'] + 2)]
        with self.assertRaises(text.TextError):
            text.extract_unit(rom, 'EnemyNames', longer)

    def test_message_tables(self):
        rom = ed.read_rom()
        units = text.units_of(ed.read_manifest())
        dic = text.rom_dictionary(rom)
        pointers, runs = 0, []
        compress = text.Dictionary.compress

        def count(self, glyph_run):
            runs.append(glyph_run)
            return compress(self, glyph_run)
        for start in text.MESSAGE_TABLES:
            name = f'Messages_{start[1:3]}{start[4:]}'
            stats: dict = {}
            dic.compress = count.__get__(dic)
            out = text.extract_unit(rom, name, units[name], dic, stats)
            del dic.compress
            self.assertNotIn('explicit_runs', stats, name)
            self.assertNotIn('«', out)
            pointers += int(out.split('@table ptr ')[1].split()[0])
        self.assertEqual(pointers, 4579)
        self.assertEqual(len(runs), 2 * 10883)      # each run decoded twice (the mode trial)

    def test_skipped_entries_are_needed(self):
        # With entries 116-118 the greedy rule would differ from the ROM.
        rom = ed.read_rom()
        dic = text.rom_dictionary(rom)
        full = text.Dictionary(dic.entries)
        full.candidates = {}
        for k, e in enumerate(dic.entries[:text.DICT_ENTRIES]):
            full.candidates.setdefault(e[0], []).append((e, k))
        for lst in full.candidates.values():
            lst.sort(key=lambda x: -len(x[0]))
        entry = dic.entries[116]
        self.assertEqual(full.compress(entry), bytes([text.FIRST_DICT + 116]))
        self.assertNotEqual(dic.compress(entry), bytes([text.FIRST_DICT + 116]))


if __name__ == '__main__':
    unittest.main(verbosity=1)
