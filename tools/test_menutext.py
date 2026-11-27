#!/usr/bin/env python3
"""
test_menutext.py — Tests for tools/menutext.py (the menu string tables as
text).

    python3 tools/test_menutext.py      (from the repository root)

Without the ROM: the reader's walk on synthetic strings (the 0, the count,
code arguments, code $07, sub-strings); a synthetic table through the
readable form and back; every refusal of the assembler; the argument
check; and the manifest's pieces.

With the ROM (and asar): the control codes' arguments from their
handlers; both tables convert and assemble back; the proofs refuse what
they must.
"""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402
import menutext as mt  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists() and shutil.which('asar') is not None
START = 0x3F0000                        # $FF:0000
# a table of 3 words, then: "AB"{line}"C"{end} at +6; a sub-string user at +12; data at +20
DATA = bytes([0x06, 0x00, 0x08, 0x00, 0x34, 0x12])
DATA += bytes([0xA0, 0xA1, 0x01, 0xA2, 0x00, 0x99])                      # +6, the 0 at +10, +11 data
DATA += bytes([0x04, 0x06, 0x00, 0xFF, 0x0A, 0x05, 0xAA, 0x00])          # +12: sub-string $FF:0006, attr 5
DATA += bytes([0x77, 0x88])                                             # +20 data


def rom_of(data):
    rom = bytearray(0x400000)
    rom[START:START + len(data)] = data
    return bytes(rom)


def proof():
    return {'entries': 3, 'strings': {START + 6: (START + 11, True), START + 12: (START + 20, True)}}


class Walk(unittest.TestCase):

    def test_zero_and_count(self):
        rom = rom_of(DATA)
        self.assertEqual(mt.walk(rom, START + 6, 256, 'w'), (START + 11, True, []))
        self.assertEqual(mt.walk(rom, START + 6, 2, 'w'), (START + 8, False, []))       # two tiles
        self.assertEqual(mt.walk(rom, START + 6, 3, 'w'), (START + 10, False, []))      # the code is not counted
        self.assertEqual(mt.walk(rom, START + 12, 256, 'w'), (START + 20, True, [0xFF0006]))

    def test_code_07_takes_one_off(self):
        rom = rom_of(bytes([0xA0, 0x07, 0x00, 0x00, 0xA1, 0xA2, 0x00]))
        self.assertEqual(mt.walk(rom, START, 3, 'w')[:2], (START + 5, False))             # A, code 7, B: 3 used
        rom = rom_of(bytes([0xA0, 0x07, 0x00, 0x00, 0xA1, 0x00]))
        self.assertEqual(mt.walk(rom, START, 2, 'w')[:2], (START + 6, True))              # 0 after code 7: not tested

    def test_runs_past_the_rom(self):
        rom = bytearray(0x400000)
        rom[-2:] = bytes([0xA0, 0xA1])
        with self.assertRaisesRegex(mt.MenuTextError, 'runs past the ROM'):
            mt.walk(bytes(rom), len(rom) - 2, 256, 'w')


class Form(unittest.TestCase):

    def test_round_trip(self):
        text = mt.render('T', START, DATA, proof())
        self.assertEqual(mt.assemble(text, 'T', START, len(DATA)), DATA)
        self.assertIn('@entry 0 S_FF0006\n@entry 1 S_FF0008\n@entry 2 $1234\n', text)
        self.assertIn('S_FF0006:\n    AB{@S_FF0008}{c01}C{end}\n@bytes 99\n', text)
        self.assertIn('S_FF000C:\n    {c04 06 00 FF}{c0A 05}K{end}\n@bytes 77 88\n', text)

    def test_count_ended_string_has_no_end(self):
        p = {'entries': 3, 'strings': {START + 6: (START + 8, False)}}
        text = mt.render('T', START, DATA, p)
        self.assertIn('S_FF0006:\n    AB\n@bytes 01 A2 00 99', text)
        self.assertEqual(mt.assemble(text, 'T', START, len(DATA)), DATA)

    def test_string_inside_another_refused(self):
        p = {'entries': 3, 'strings': {START + 6: (START + 11, True), START + 8: (START + 11, True)}}
        with self.assertRaisesRegex(mt.MenuTextError, 'starts inside another'):
            mt.render('T', START, DATA, p)

    def test_edit(self):
        text = mt.render('T', START, DATA, proof()).replace('{c0A 05}K', '{c0A 06}{gAB}')
        got = mt.assemble(text, 'T', START, len(DATA))
        self.assertEqual(got[17:19], bytes([0x06, 0xAB]))

    def test_assembler_refusals(self):
        text = mt.render('T', START, DATA, proof())

        def refused(new, why, size=len(DATA)):
            with self.assertRaisesRegex(mt.MenuTextError, why):
                mt.assemble(new, 'T', START, size)

        refused(text.replace('@menutext T', '@menutext U'), 'the first line')
        refused(text, 'the first line', size=len(DATA) + 1)
        refused(text.replace('@table 3', '@table x'), 'the second line')
        refused(text.replace('@table 3', '@table 4'), 'the table needs 4')
        refused(text.replace('@entry 1 ', '@entry 2 '), 'the table needs 3')
        refused(text.replace('@entry 0 S_FF0006', '@entry 0 S_NONE'), 'no label S_NONE')
        refused(text.replace('S_FF000C:\n', 'S_FF0006:\n'), 'label S_FF0006 twice')
        refused(text.replace('{@S_FF0008}', '{@S_FF0006}'), 'label S_FF0006 twice')
        refused(text.replace('    {c04 06 00 FF}', '{c04 06 00 FF}'), 'a label is followed by its string')
        refused(text.replace('{c0A 05}', '{c0A 05 06}'), 'code \\$01-\\$0F with its 1 argument')
        refused(text.replace('{c0A 05}', '{c1A 05}'), 'code \\$01-\\$0F')
        refused(text.replace('{c0A 05}', '{q}'), 'bad token')
        refused(text.replace('K{end}', '{g05}{end}'), 'is a control code, not a tile')
        refused(text.replace('AB{@', 'A\u00a7{@'), 'is not a glyph')
        refused(text.replace('C{end}', '{end}C'), '{end} must end the string')
        refused(text.replace('@bytes 99', '@bytes 9'), '@bytes takes XX bytes')
        refused(text.replace('@bytes 99\n', '@bytes\n'), '@bytes takes XX bytes')
        refused(text.replace('@bytes 99\n', ''), 'the piece makes 21 B; it is 22 B')
        refused(text + 'stray\n', 'expected a label, its string, or @bytes')


class Args(unittest.TestCase):

    def test_arg_problems(self):
        self.assertEqual(mt.arg_problems(derived=list(mt.ARGS)), [])
        bad = list(mt.ARGS)
        bad[3] = 3
        self.assertEqual(len(mt.arg_problems(derived=bad)), 1)
        self.assertTrue(mt.arg_problems(derived=list(mt.ARGS[:15]) + [None]))

    def test_table_names_from_the_source(self):
        names = mt._table_names()
        self.assertEqual(len(names), 16)
        self.assertEqual(names[4], 'Menu_TextSubString')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'c2.asm'
            path.write_text('Menu_TextCtrlTablX:\n')
            with self.assertRaisesRegex(mt.MenuTextError, 'no Menu_TextCtrlTable'):
                mt._table_names(path)

    def test_extract_stops_on_wrong_args(self):
        bad = list(mt.ARGS)
        bad[2] = 1
        texts, problems = mt.extract_texts(b'', [{'piece': 'menutext'}], {}, derived=bad)
        self.assertEqual(texts, {})
        self.assertTrue(problems[0].startswith('Menu_TextCtrlTable'))
        self.assertEqual(mt.extract_texts(b'', [], {}), ({}, []))


class Manifest(unittest.TestCase):

    def test_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        ps = [p for p in ed.read_manifest() if p['piece'] == 'menutext']
        self.assertEqual([(p['start'], p['asset']) for p in ps],
                         [('$FF:B310', 'menu/MenuRom_ItemTextPtrs.mtx'), ('$FF:C457', 'menu/MenuRom_StringPtrs.mtx')])
        self.assertEqual(sorted(mt.TABLES), [p['start'] for p in ps])
        for p in ps:
            self.assertEqual(mt.is_piece_row(rows[p['start']]), 'menutext')
            self.assertEqual(ed.placeholder_files(ps)[ed.text_out(p)], int(p['size']))
        self.assertEqual(mt.is_piece_row(dict(rows['$FF:B310'], kind='table')), None)


@unittest.skipUnless(HAVE_ROM, 'needs the ROM and asar')
class WithRom(unittest.TestCase):

    def test_args_from_the_handlers(self):
        self.assertEqual(mt.derive_args(), list(mt.ARGS))
        self.assertEqual(mt.arg_problems(), [])

    def test_round_trips(self):
        self.assertEqual(mt.check(ed.read_rom()), [])

    def test_proofs(self):
        import battle
        rom, ps, d = ed.read_rom(), ed.read_manifest(), battle.defines(ed.ROOT)
        strings = {p['start']: mt.proofs(rom, p, ps, d) for p in ps if p['piece'] == 'menutext'}
        items = strings['$FF:B310']
        self.assertEqual(items['entries'], d['Menu_ItemIdEnd'])
        self.assertEqual(sorted(e - s for s, (e, _) in items['strings'].items()), [5, 6, 7, 7, 9])
        self.assertFalse(items['strings'][0x3FB509][1])                   # the last string: the count of 9 ends it
        labels = [d[n] - 0xC00000 for n in mt._equip_labels()]
        self.assertTrue(all(a in strings['$FF:C457']['strings'] for a in labels))
        # without the draw lists, no string of MenuRom_StringPtrs is proved
        p = next(x for x in ps if x['start'] == '$FF:C457')
        self.assertEqual(mt.proofs(rom, p, [x for x in ps if x['piece'] != 'drawlist'], d)['strings'], {})

    def test_proof_refusals(self):
        import battle
        rom, ps, d = ed.read_rom(), ed.read_manifest(), battle.defines(ed.ROOT)
        p = next(x for x in ps if x['start'] == '$FF:C457')
        with self.assertRaisesRegex(mt.MenuTextError, 'not a menu string table'):
            mt.proofs(rom, dict(p, start='$FF:0000'), ps, d)
        saved = mt.draw_uses
        mt.draw_uses = lambda rom, pieces: {99: {256}}
        try:
            with self.assertRaisesRegex(mt.MenuTextError, 'draws entry 99, past the 64 entries'):
                mt.proofs(rom, p, ps, d)
        finally:
            mt.draw_uses = saved
        mt.draw_uses = lambda rom, pieces: {7: {2, 256}}               # entry 7 drawn two ways
        try:
            with self.assertRaisesRegex(mt.MenuTextError, 'ends differently for different counts'):
                mt.proofs(rom, p, ps, d)
        finally:
            mt.draw_uses = saved
        with self.assertRaisesRegex(mt.MenuTextError, 'has no 0 in its'):
            mt.proofs(rom, p, ps, dict(d, Menu_InfoLabelBytes=5))
        short = dict(p, stop=p['stop'] - 40, size=str(int(p['size']) - 40))
        with self.assertRaisesRegex(mt.MenuTextError, 'runs past the piece'):
            mt.proofs(rom, short, ps, d)

    def test_piece_text_refuses_a_bad_round_trip(self):
        import battle
        rom, ps, d = ed.read_rom(), ed.read_manifest(), battle.defines(ed.ROOT)
        p = next(x for x in ps if x['start'] == '$FF:B310')
        saved = mt.assemble
        mt.assemble = lambda *a, **k: b''
        try:
            with self.assertRaisesRegex(mt.MenuTextError, 'does not assemble back'):
                mt.piece_text(p, rom, ps, d)
            self.assertIn('MenuRom_ItemTextPtrs: does not assemble back to its bytes', mt.check(rom))
        finally:
            mt.assemble = saved


if __name__ == '__main__':
    unittest.main()
