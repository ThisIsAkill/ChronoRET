#!/usr/bin/env python3
"""
test_drawlists.py — Tests for tools/drawlists.py (the menu draw lists as
text).

    python3 tools/test_drawlists.py     (from the repository root)

Without the ROM: synthetic lists (ended, and one that runs on into the next)
through the readable form and back; every refusal of the parser, the
assembler and the extraction; the command names from the source; and the
manifest's pieces.

With the ROM: every draw list converts and assembles back byte-exact.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import battle  # noqa: E402
import data_survey  # noqa: E402
import drawlists as dl  # noqa: E402
import extract_data as ed  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists()
D = battle.defines(ed.ROOT)
NAMES = dl.command_names()
ARGLENS = bytes([3, 0, 5, 0, 5, 0, 4, 0, 1, 0, 1, 0, 3, 0, 1, 0, 5, 0, 5, 0, 5, 0])
START = 0x3FC000                        # $FF:C000
ENDED = bytes([0x08, 0xC2, 0x33, 0x00, 1, 2, 3, 4, 0xFF])
RUNS_ON = bytes([0x08, 0x80, 0x93, 0x0E, 0xB0, 0xB6])


def make_rom():
    rom = bytearray(0x400000)
    a = D['MenuRom_DrawArgLens'] - 0xC00000
    rom[a:a + len(ARGLENS)] = ARGLENS
    rom[START:START + len(RUNS_ON)] = RUNS_ON
    rom[START + len(RUNS_ON):START + len(RUNS_ON) + len(ENDED)] = ENDED
    return rom


def pieces():
    s2 = START + len(RUNS_ON)
    return [{'label': 'A', 'piece': 'drawlist', 'offset': START, 'stop': s2, 'size': str(len(RUNS_ON))},
            {'label': 'B', 'piece': 'drawlist', 'offset': s2, 'stop': s2 + len(ENDED), 'size': str(len(ENDED))}]


class Form(unittest.TestCase):

    def test_names_from_the_source(self):
        self.assertEqual(NAMES, ['Fill', 'CopyBlock', 'Window', 'String', 'SetMap', 'CopyRom', 'MapRec', 'CopyRom',
                                 'SwapBlocks', 'Frame', 'Inside'])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'c2.asm'
            path.write_text('Menu_DrawCmdTablX:\n    dw Menu_DrawCmdFill\n')
            with self.assertRaisesRegex(dl.DrawListsError, 'no Menu_DrawCmdTable'):
                dl.command_names(path)
            path.write_text('Menu_DrawCmdTable:\n    dw Menu_DrawCmdFill, Other\n')
            with self.assertRaisesRegex(dl.DrawListsError, 'expected dw lines'):
                dl.command_names(path)

    def test_round_trips(self):
        for data in (ENDED, RUNS_ON):
            text = dl.render('L', START, data, ARGLENS, NAMES)
            self.assertEqual(dl.assemble(text, 'L', START, len(data), NAMES), data)
        self.assertIn('$00 Fill 01 02 03 04\nend $FF\n', dl.render('L', START, ENDED, ARGLENS, NAMES))
        self.assertTrue(dl.render('L', START, RUNS_ON, ARGLENS, NAMES).endswith('$0E CopyRom B0 B6\ncontinues\n'))

    def test_parse_refusals(self):
        for data, why in ((ENDED + b'\x00', 'ends at byte 8, 1 B before'),
                          (bytes([0x01, 0]), '\\$01 is not a command'),
                          (bytes([0x16, 0]), '\\$16 is not a command'),
                          (bytes([0x00, 1, 2]), 'runs past the row')):
            with self.assertRaisesRegex(dl.DrawListsError, why):
                dl.parse(data, ARGLENS, NAMES, 'L')
        with self.assertRaisesRegex(dl.DrawListsError, 'is not a command'):
            dl.parse(bytes([0x14, 0, 0, 0, 0, 0, 0]), ARGLENS[:20], NAMES, 'L')

    def test_assembler_refusals(self):
        text = dl.render('L', START, ENDED, ARGLENS, NAMES)
        lines = text.splitlines()

        def refused(new, why, size=len(ENDED)):
            with self.assertRaisesRegex(dl.DrawListsError, why):
                dl.assemble('\n'.join(new), 'L', START, size, NAMES)

        refused([x.replace('@drawlist L', '@drawlist M') for x in lines], 'the first line')
        refused(lines, 'the first line', size=10)
        refused([x for x in lines if not x.startswith('@arglens')], 'the second line must be @arglens')
        refused([x.replace('@arglens 03', '@arglens G3') for x in lines], 'the second line')
        refused(lines[:-1], 'no end line')
        refused(lines[:-1] + ['continues', 'end $FF'], 'continues must be the last line')
        refused(lines[:-1] + ['end $7F'], 'bit 7 set')
        refused(lines[:-1] + ['end FF'], 'bit 7 set')
        refused([x.replace('$00 Fill', '$01 Fill') for x in lines], 'not a command of Menu_DrawCmdTable')
        refused([x.replace('$00 Fill', '$00 Window') for x in lines], 'not a command of Menu_DrawCmdTable')
        refused([x.replace('$00 Fill', '$80 Fill') for x in lines], 'not a command of Menu_DrawCmdTable')
        refused([x.replace('$00 Fill', '$16 Fill') for x in lines], 'not a command of Menu_DrawCmdTable')
        refused([x.replace('$00 Fill 01 02 03 04', '$00 Fill 01 02 03') for x in lines], 'takes 4 argument byte')
        refused([x.replace('$00 Fill 01 02 03 04', '$00 Fill 01 02 03 4') for x in lines], 'takes 4 argument byte')
        refused([x.replace('$00 Fill', '00 Fill') for x in lines], 'expected \\$CC Name')
        refused([x.replace('$08 SetMap C2 33', '$08') for x in lines], 'expected \\$CC Name')
        refused(lines[:-1] + ['continues'], 'makes 8 B, the piece is 9 B')

    def test_edit(self):
        lines = dl.render('L', START, ENDED, ARGLENS, NAMES).splitlines()
        lines = [x.replace('$00 Fill 01 02 03 04', '$00 Fill 0A 0B 0C 0D') for x in lines]
        self.assertEqual(dl.assemble('\n'.join(lines), 'L', START, len(ENDED), NAMES),
                         ENDED[:4] + bytes([10, 11, 12, 13, 0xFF]))


class Extract(unittest.TestCase):

    def test_extract_texts(self):
        rom = make_rom()
        texts, problems = dl.extract_texts(bytes(rom), pieces(), D)
        self.assertEqual(problems, [])
        self.assertEqual(sorted(texts), ['A', 'B'])
        self.assertEqual(dl.extract_texts(bytes(rom), [], D), ({}, []))
        self.assertEqual(dl.arglens_problems(bytes(rom), texts, D, NAMES), [])
        bad = bytearray(rom)
        bad[D['MenuRom_DrawArgLens'] - 0xC00000] = 2
        self.assertEqual(dl.arglens_problems(bytes(bad), texts, D, NAMES), ['A: @arglens is not MenuRom_DrawArgLens',
                                                                              'B: @arglens is not MenuRom_DrawArgLens'])

    def test_extract_refusals(self):
        rom = make_rom()
        texts, problems = dl.extract_texts(bytes(rom), pieces()[:1], D)
        self.assertEqual(problems, ['A: the list runs past its row, and no draw list follows it'])
        moved = [dict(p, offset=p['offset'] - 0x10000, stop=p['stop'] - 0x10000) for p in pieces()]
        rom2 = bytearray(rom)
        rom2[START - 0x10000:START - 0x10000 + 15] = rom[START:START + 15]
        self.assertEqual(dl.extract_texts(bytes(rom2), moved, D)[1],
                         [f'{x}: not in bank $FF, where Menu_RunDrawList reads' for x in 'AB'])
        short = [pieces()[0], dict(pieces()[1], stop=pieces()[1]['stop'] - 1, size='8')]
        self.assertEqual(dl.extract_texts(bytes(rom), short, D)[1],
                         ['B: the list runs past its row, and no draw list follows it'])
        saved = dl.assemble
        dl.assemble = lambda text, label, start, size, names, name='': bytes(size)
        try:
            self.assertIn('A: does not assemble back to its bytes', dl.extract_texts(bytes(rom), pieces(), D)[1])
        finally:
            dl.assemble = saved


class Manifest(unittest.TestCase):

    def test_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        ps = [p for p in ed.read_manifest() if p['piece'] == 'drawlist']
        self.assertEqual(len(ps), 56)
        for p in ps:
            self.assertEqual(dl.is_piece_row(rows[p['start']]), 'drawlist')
            self.assertEqual(p['asset'], f'menu/{p["label"]}.mdl')
            self.assertIn(f'../../build/menulists/{p["label"]}.bin', ed.allowed_incbins(ps))
            self.assertEqual(ed.placeholder_files(ps)[ed.text_out(p)], int(p['size']))
        row = {'start': '$FF:C000', 'end': '$FF:C008', 'size': '9', 'bank': '$FF', 'kind': 'table',
               'format': dl.FORMAT + ' (x)', 'readers': '', 'confidence': 'confirmed', 'notes': 'x'}
        self.assertEqual([(p['piece'], p['asset']) for p in ed.layout([row])],
                         [('drawlist', 'menu/Table_FFC000.mdl')])
        self.assertEqual([p['piece'] for p in ed.layout([dict(row, kind='unknown')])], ['extracted'])

    def test_manifest_form(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'data_assets.csv'
            text = ed.MANIFEST.read_text()
            p = [x for x in ed.read_manifest() if x['piece'] == 'drawlist'][0]
            line = f'{p["label"]},{p["start"]},{p["end"]},{p["size"]},drawlist,menu/{p["label"]}.mdl,'
            self.assertIn(line + '\n', text)
            for bad in (line + 'x', line.replace('.mdl,', '.bin,'), line.replace('menu/', 'anims/')):
                path.write_text(text.replace(line + '\n', bad + '\n'))
                self.assertTrue(any('drawlist piece' in x for x in ed.manifest_problems(path)), bad)


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_round_trips(self):
        self.assertEqual(dl.check(ed.read_rom()), [])

    def test_extraction(self):
        rom = ed.read_rom()
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(ed.extract_text_tools(rom, Path(tmp), ed.read_manifest()), [])
            self.assertEqual(len(list((Path(tmp) / 'menu').iterdir())), 56)
            bad = [p for p in ed.read_manifest() if p['label'] != 'MenuRom_ShopQtyList']
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIn('MenuRom_ShopMembersList: the list runs past its row, and no draw list follows it',
                          ed.extract_text_tools(rom, Path(tmp), bad))
            self.assertFalse((Path(tmp) / 'menu').exists())


if __name__ == '__main__':
    unittest.main()
