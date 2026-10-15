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

With the ROM: every unit extracts and encodes back to the ROM's bytes, the
15 message tables hold 4,579 pointers, and the greedy rule gives every run
of their text (no explicit run).
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


# A small dictionary: entries 0-3 and three more; 116-118 are skipped by the
# greedy rule, so a test entry there must never be chosen.
ENTRIES = [b''] * (text.DICT_ENTRIES + 1)
for k, s in {0: 'the', 1: 'th', 2: 'he', 3: 'e t', 116: 'your', 117: 'ou', 118: 'r a', 127: 'xyz'}.items():
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
        self.assertEqual(self.enc('the'), bytes([d + 0]))
        self.assertEqual(self.enc('tha'), bytes([d + 1, G['a']]))
        self.assertEqual(self.enc('he the'), bytes([d + 2, G[' '], d + 0]))
        self.assertEqual(self.enc('e the'), bytes([d + 3, d + 2]))      # left to right, longest first
        self.assertEqual(self.enc('your'), glyphs('your'))             # 116-118 are skipped
        self.assertEqual(self.enc('xyz'), glyphs('xyz'))                # 127: only through code $12

    def test_runs_end_at_codes(self):
        d = text.FIRST_DICT
        self.assertEqual(self.enc('t{line}he{end}'), bytes([G['t'], 5, d + 2, 0]))
        self.assertEqual(self.enc('t\nhe'), bytes([d + 0]))             # a line break is no byte

    def test_explicit_forms(self):
        d = text.FIRST_DICT
        self.assertEqual(self.enc('«the»'), glyphs('the'))
        self.assertEqual(self.enc('«t[he]»'), bytes([G['t'], d + 2]))
        self.assertEqual(self.enc('[th]e'), bytes([d + 1, G['e']]))
        self.assertEqual(self.enc('{dict 74}'), bytes([d + 116]))
        self.assertEqual(self.enc('the', compress=False), glyphs('the'))

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
        self.assertEqual(text.decode_msg(bytes([d + 0, G[' '], d + 1, G['a'], 0]), DIC), 'the tha{end}\n')
        self.assertEqual(text.decode_msg(glyphs('the'), DIC), '«the»')
        self.assertEqual(text.decode_msg(bytes([G['t'], d + 2]), DIC), '«t[he]»')

    def test_errors(self):
        for bad in ('{nope}', 'ä', '[zz]', '{dict 7F}', '{wide 03D0}'):
            with self.subTest(bad=bad), self.assertRaises(text.TextError):
                self.enc(bad)


class Units(unittest.TestCase):

    def test_pointer_table_and_strings(self):
        body = ('@table ptr 4\n@set 3 $0000\n@mode msg\n@at 0 2\nthe{end}\n'
                '@at 1\nhe{wait 00}\n; a comment\n\nhe{end}\n@bytes 01 02\n@fill 3 $FF\n')
        out = text.encode_unit(unit(body), [piece()], DIC)['P']
        d = text.FIRST_DICT
        self.assertEqual(out, bytes([0x08, 0, 0x0A, 0, 0x08, 0, 0, 0,
                                     d + 0, 0, d + 2, 3, 0, d + 2, 0, 1, 2, 0xFF, 0xFF, 0xFF]))

    def test_pointer_across_pieces_and_records(self):
        body = ('@table ptr 2\n'
                '@piece Q $D8:0100\n@at 1\n@d the\n@at 0\n@d x\n@records 4 $EF\n@r a\n@r ab_d\n@r\n')
        out = text.encode_unit(unit(body), [piece(), piece('Q', 0x180100)], None)
        self.assertEqual(out['P'], bytes([0x04, 0x01, 0x00, 0x01]))
        self.assertEqual(out['Q'], bytes([3]) + glyphs('the') + bytes([1, G['x']])
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

    def test_message_tables(self):
        rom = ed.read_rom()
        units = text.units_of(ed.read_manifest())
        dic = text.rom_dictionary(rom)
        pointers = 0
        for start in text.MESSAGE_TABLES:
            name = f'Messages_{start[1:3]}{start[4:]}'
            stats: dict = {}
            out = text.extract_unit(rom, name, units[name], dic, stats)
            self.assertNotIn('explicit_runs', stats, name)
            self.assertNotIn('«', out)
            pointers += int(out.split('@table ptr ')[1].split()[0])
        self.assertEqual(pointers, 4579)

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
        self.assertEqual(full.compress(glyphs('your')), bytes([text.FIRST_DICT + 116]))
        self.assertNotEqual(dic.compress(glyphs('your')), bytes([text.FIRST_DICT + 116]))


if __name__ == '__main__':
    unittest.main(verbosity=1)
