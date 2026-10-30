#!/usr/bin/env python3
"""
test_actframes.py — Tests for tools/actframes.py (the battle action sprite
frames as text).

    python3 tools/test_actframes.py     (from the repository root)

Without the ROM: synthetic frames (rows with and without sprites, the
header's high nibble, the skipped bytes, an empty pack) through the
readable form and back; every refusal of the parser and the assembler; the
reader in the source; and the manifest's pieces.

With the ROM: every pack converts and assembles back byte-exact.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import actframes as af  # noqa: E402
import battle  # noqa: E402
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402
import maps  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists()
D = battle.defines(ed.ROOT)
# frame 0: 2 rows (hi 1), row 0 columns 0 and 7, row 1 none; frame 1: 1 row (hi 7), column 3
DATA = bytes([0x12, 0x81, 0x00, 0xC0, 0x00, 0xC2, 0x31, 0xFF, 0xFF,
              0x71, 0x10, 0xE0, 0x05, 0x01, 0x02])


class Form(unittest.TestCase):

    def test_parse(self):
        frames = af.parse(DATA, 'P')
        self.assertEqual([(f['rows'], f['hi'], f['sprites'], f['skip']) for f in frames],
                         [(2, 1, [(0, 0, 0xC0, 0x00), (0, 7, 0xC2, 0x31)], b'\xff\xff'),
                          (1, 7, [(0, 3, 0xE0, 0x05)], b'\x01\x02')])

    def test_round_trips(self):
        for data in (DATA, b''):
            self.assertEqual(af.assemble(af.render('P', data), 'P'), data)
        text = af.render('P', DATA)
        self.assertIn('frame 0 rows 2 hi 1\n  row 0: 0=C0/00 7=C2/31\n  row 1: -\n  skip FF FF\n', text)
        self.assertIn('@actframes P 0\n', af.render('P', b''))

    def test_edit(self):
        text = af.render('P', DATA).replace('row 1: -', 'row 1: 2=AA/BB')
        self.assertEqual(af.assemble(text, 'P'),
                         bytes([0x12, 0x81, 0x20, 0xC0, 0x00, 0xC2, 0x31, 0xAA, 0xBB, 0xFF, 0xFF]) + DATA[9:])

    def test_parse_refusals(self):
        for data, why in ((DATA[:9] + b'\x00' + DATA[9:], 'a 0 header ends the frames 7 B before'),
                          (bytes([0x03, 0x80]), "frame 0's row masks run past the data"),
                          (bytes([0x01, 0x80, 0x01]), "frame 0's sprites run past the data"),
                          (bytes([0x01, 0x00, 0x01]), "frame 0's skipped bytes run past the data")):
            with self.subTest(why=why):
                with self.assertRaisesRegex(af.ActFramesError, why):
                    af.parse(data, 'P')
        many = bytes([0x01, 0x00, 0, 0]) * 33
        with self.assertRaisesRegex(af.ActFramesError, '33 frames; the reader builds 32'):
            af.parse(many, 'P')
        self.assertEqual(len(af.parse(many[:-4], 'P')), 32)

    def test_assembler_refusals(self):
        text = af.render('P', DATA)

        def refused(new, why):
            with self.assertRaisesRegex(af.ActFramesError, why):
                af.assemble(new, 'P')

        refused(text.replace('@actframes P 2', '@actframes Q 2'), 'the first line')
        refused(text.replace('@actframes P 2', '@actframes P x'), 'the first line')
        refused(text.replace('@actframes P 2', '@actframes P 3'), 'expected frame 2')
        refused(text.replace('@actframes P 2', '@actframes P 1'), 'a line after frame 0')
        refused(af.render('P', b'') + 'frame 0 rows 1 hi 0\n', 'a line after an empty pack')
        refused(text.replace('frame 1 rows', 'frame 2 rows'), 'expected frame 1')
        refused(text.replace('rows 2 hi 1', 'rows 0 hi 1'), 'expected frame 0 rows R hi H')
        refused(text.replace('rows 2 hi 1', 'rows 16 hi 1'), 'expected frame 0 rows R hi H')
        refused(text.replace('rows 2 hi 1', 'rows 2 hi 16'), 'expected frame 0 rows R hi H')
        refused(text.replace('row 1: -', 'row 2: -'), 'expected row 1:')
        refused(text.replace('row 1: -', 'row 1:'), 'expected row 1:')
        refused(text.replace('0=C0/00 7=C2/31', '7=C2/31 0=C0/00'), 'columns 0-7 rising')
        refused(text.replace('0=C0/00 7=C2/31', '0=C0/00 0=C2/31'), 'columns 0-7 rising')
        refused(text.replace('7=C2/31', '8=C2/31'), 'bad sprite')
        refused(text.replace('7=C2/31', '7=C2/3'), 'bad sprite')
        refused(text.replace('skip FF FF', 'skip FF'), 'expected skip and 2 hex bytes')
        refused(text.replace('skip FF FF', 'skap FF FF'), 'expected skip and 2 hex bytes')
        refused(text.replace('skip FF FF', 'skip FF GG'), 'expected skip and 2 hex bytes')
        many = af.render('P', bytes([0x01, 0x00, 0, 0]) * 32)
        refused(many.replace('@actframes P 32', '@actframes P 33') + 'frame 32 rows 1 hi 0\n  row 0: -\n'
                '  skip 00 00\n', '33 frames; the reader builds 32')

    def test_maps_dispatch(self):
        p = {'label': 'P', 'piece': 'actframes', 'param': 'lz11 -> 15 B'}
        self.assertEqual(maps.assemble_piece(p, maps.render_piece(p, DATA)), DATA)
        with self.assertRaisesRegex(maps.MapsError, 'a 0 header ends'):
            maps.render_piece(p, b'\x00\x00')
        with self.assertRaisesRegex(maps.MapsError, 'the first line'):
            maps.assemble_piece(p, '@actframes Q 0\n')

    def test_reader_in_the_source(self):
        self.assertEqual(af.reader_problems(D), [])
        self.assertTrue(af.reader_problems(dict(D, Battle_ActFramesPerCall=5)))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'c1.asm'
            src = af.BANK_C1.read_text()
            path.write_text(src.replace('    JSR BattleAct_UnpackFrames\n', '', 1))
            self.assertIn('BattleAct_LoadCommon calls BattleAct_UnpackFrames 7 times, not 8',
                          af.reader_problems(D, path))
            path.write_text(src.replace('\nBattleAct_LoadCommon:', '\nBattleAct_LoadCommonX:'))
            self.assertIn('c1.asm: no BattleAct_LoadCommon', af.reader_problems(D, path))
            got = af.reader_problems(dict(D, Battle_ActFramesPerCall=5), path)
            self.assertEqual(len(got), 2)
            self.assertIn('c1.asm: no BattleAct_LoadCommon', got)


class Manifest(unittest.TestCase):

    def test_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        ps = [p for p in ed.read_manifest() if p['piece'] == 'actframes']
        self.assertEqual(len(ps), 128)
        for p in ps:
            self.assertEqual(maps.kind_of(rows[p['start']]['notes']), ('actframes', None))
            self.assertEqual(p['asset'], f'actframes/{p["label"]}.afr')
        self.assertTrue(maps.size_ok('actframes', None, 101))
        self.assertFalse(maps.size_ok('scenepal', None, 101))
        row = dict(rows[ps[0]['start']])
        self.assertEqual([(p['piece'], p['asset']) for p in ed.layout([row])],
                         [('actframes', f'actframes/{ps[0]["label"]}.afr')])

    def test_manifest_form(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'data_assets.csv'
            text = ed.MANIFEST.read_text()
            p = [x for x in ed.read_manifest() if x['piece'] == 'actframes'][0]
            line = f'{p["label"]},{p["start"]},{p["end"]},{p["size"]},actframes,actframes/{p["label"]}.afr,'
            self.assertIn(line, text)
            for old, new in (('actframes/', 'maps/'), ('.afr,', '.spal,')):
                path.write_text(text.replace(line, line.replace(old, new)))
                self.assertTrue(any('actframes piece' in x for x in ed.manifest_problems(path)), new)


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_round_trips(self):
        self.assertEqual(af.check(ed.read_rom()), [])

    def test_maps_check_sees_the_reader(self):
        saved = af.CALLS
        af.CALLS = 7
        try:
            self.assertTrue(any('7' in x for x in maps.check(ed.read_rom())))
        finally:
            af.CALLS = saved


if __name__ == '__main__':
    unittest.main()
