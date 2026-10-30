#!/usr/bin/env python3
"""
test_anims.py — Tests for tools/anims.py (the sprite animation lists as
text).

    python3 tools/test_anims.py         (from the repository root)

Without the ROM: a synthetic bank $E4 (offset tables, lists with facing
blocks that are not whole rows, the byte after the last list, padding)
through the lists, the readable forms and back; every refusal of the
lists, the readers' tables, the pieces and the assembler; and the
manifest's pieces.

With the ROM: both lists convert and assemble back byte-exact, and the
pieces are the lists.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anims  # noqa: E402
import battle  # noqa: E402
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists()
D = battle.defines(ed.ROOT)
F = lambda a: a - 0xC00000      # noqa: E731
E4 = F(0xE40000)
FRAMES = [0x3000, 0x3020, 0x3034, 0x3044]       # anims 0-2: strides 8, 5, 4; anim 3 has no extent
TIMES = [0xA800, 0xA806, 0xA80A, 0xA812]


def make_rom():
    rom = bytearray(0x400000)
    init = F(D['RomE4_PtrInit'])
    for word, v in ((2, 0x2600), (3, 0x2800), (5, 0x3000), (6, 0xA800)):
        rom[init + 2 * word:init + 2 * word + 2] = v.to_bytes(2, 'little')
    for table, offs in ((D['BattleRom_SprAnimFrames'], FRAMES), (D['BattleRom_SprAnimDurs'], TIMES)):
        for k, v in enumerate(offs):
            rom[F(table) + 2 * k:F(table) + 2 * k + 2] = v.to_bytes(2, 'little')
    for a in range(FRAMES[0], FRAMES[-1]):
        rom[E4 + a] = (a * 7) & 0xFF or 1
    for a in range(TIMES[0], TIMES[-1]):
        rom[E4 + a] = (a * 3) & 0xFF
    rom[E4 + FRAMES[-1]] = rom[E4 + TIMES[-1]] = 0xDD
    return rom


def lists_of(rom):
    return anims.derive(bytes(rom), D)


def pieces_of(lists):
    return [{'offset': s, 'stop': e, 'piece': k} for s, e, k in anims.want_rows(lists)]


class Lists(unittest.TestCase):

    def test_lists(self):
        got = lists_of(make_rom())
        self.assertEqual(got['animframes']['lists'], [(k, E4 + FRAMES[k], E4 + FRAMES[k + 1]) for k in range(3)])
        self.assertEqual(got['animtimes']['lists'], [(k, E4 + TIMES[k], E4 + TIMES[k + 1]) for k in range(3)])
        self.assertEqual([(s - E4, e - E4, k) for s, e, k in anims.want_rows(got)], [
            (0x3000, 0x3044, 'animframes'), (0x3044, 0x3045, 'extracted'), (0x3045, 0xA800, 'fill'),
            (0xA800, 0xA812, 'animtimes'), (0xA812, 0xA813, 'extracted'),
            (0xA813, F(D['RomE4_SprRec']) - E4, 'fill')])

    def test_no_byte_after_the_lists(self):
        rom = make_rom()
        rom[E4 + FRAMES[-1]] = 0
        self.assertEqual([k for _, _, k in anims.want_rows(lists_of(rom))][:3], ['animframes', 'fill', 'animtimes'])

    def test_refusals(self):
        rom = make_rom()
        bad = bytearray(rom)
        bad[F(D['RomE4_PtrInit']) + 10] = 0x10                         # word 5: $3010
        with self.assertRaisesRegex(anims.AnimsError, 'animation 0\'s offset is \\$3000, RomE4_PtrInit word 5'):
            lists_of(bad)
        bad = bytearray(rom)
        t = F(D['BattleRom_SprAnimDurs']) + 2 * 3
        bad[t:t + 2] = (0xA800).to_bytes(2, 'little')                   # the durations end one animation early
        with self.assertRaisesRegex(anims.AnimsError, 'an extent for 3 animations, the duration lists for 2'):
            lists_of(bad)
        bad = bytearray(rom)
        t = F(D['BattleRom_SprAnimFrames']) + 2 * 1
        bad[t:t + 2] = (0x3022).to_bytes(2, 'little')                   # anim 0: 34 B
        with self.assertRaisesRegex(anims.AnimsError, 'animation 0\'s frame-id list is not four whole facing'):
            lists_of(bad)
        bad = bytearray(rom)
        t = F(D['BattleRom_SprAnimFrames']) + 2 * 3
        bad[t:t + 2] = (0xA810).to_bytes(2, 'little')                   # past the duration lists' start
        with self.assertRaisesRegex(anims.AnimsError, 'past the next table'):
            lists_of(bad)

    def test_readers_tables(self):
        rom = make_rom()
        self.assertEqual(anims.reader_problems(bytes(rom), D), [])
        bad = bytearray(rom)
        bad[F(D['RomE4_PtrInit']) + 6] = 0x02                           # word 3: $2802
        self.assertTrue(any('Field_E4Ptr3' in x for x in anims.reader_problems(bytes(bad), D)))
        self.assertTrue(any('Field_E4Ptr2' in x for x in
                            anims.reader_problems(bytes(rom), dict(D, MenuRom_E4AnimFrames=D['RomE4_PtrInit'] + 6))))
        self.assertTrue(anims.reader_problems(bytes(rom), dict(D, AnimRom=0xE30000)))

    def test_pieces_are_the_lists(self):
        lists = lists_of(make_rom())
        pieces = pieces_of(lists)
        self.assertEqual(anims.layout_problems(lists, pieces), [])
        for k in range(len(pieces)):
            for wrong in ('extracted', 'fill', 'animframes', 'animtimes', 'table'):
                if wrong != pieces[k]['piece']:
                    bad = pieces[:k] + [dict(pieces[k], piece=wrong)] + pieces[k + 1:]
                    self.assertTrue(anims.layout_problems(lists, bad), (k, wrong))
        self.assertTrue(anims.layout_problems(lists, pieces[:-1]))
        cut = [dict(pieces[0], stop=pieces[0]['stop'] - 4), dict(pieces[1], offset=pieces[1]['offset'] - 4)]
        self.assertTrue(anims.layout_problems(lists, cut + pieces[2:]))


class Form(unittest.TestCase):

    def piece(self, kind):
        rom = make_rom()
        lists = lists_of(rom)
        v = lists[kind]
        return bytes(rom[v['start']:v['stop']]), v['start'], v['lists']

    def test_round_trips(self):
        for kind in anims.KINDS:
            data, s, lists = self.piece(kind)
            text = anims.render(kind, 'P', s, data, lists)
            self.assertEqual(anims.assemble(kind, text, 'P', s, len(data)), data)
        data, s, lists = self.piece('animframes')
        text = anims.render('animframes', 'P', s, data, lists)
        self.assertIn('@anim 1 $E4:3020 stride 5', text)
        block = text.split('@anim 1')[1].split('facing 1')[0].splitlines()
        self.assertEqual([len(x.split()) for x in block[2:]], [4, 1])          # a 5-byte block: a row and one byte

    def test_edit(self):
        data, s, lists = self.piece('animtimes')
        lines = anims.render('animtimes', 'P', s, data, lists).splitlines()
        k = lines.index('@anim 1 $E4:A806 bytes 4') + 1
        lines[k] = '  01 02 03 00'
        want = bytearray(data)
        want[6:10] = bytes([1, 2, 3, 0])
        self.assertEqual(anims.assemble('animtimes', '\n'.join(lines), 'P', s, len(data)), bytes(want))

    def test_assembler_refusals(self):
        for kind, word in (('animframes', 'stride'), ('animtimes', 'bytes')):
            data, s, lists = self.piece(kind)
            lines = anims.render(kind, 'P', s, data, lists).splitlines()

            def refused(new, why, size=len(data)):
                with self.assertRaisesRegex(anims.AnimsError, why):
                    anims.assemble(kind, '\n'.join(new), 'P', s, size)

            head = next(i for i, x in enumerate(lines) if x.startswith(f'@{kind}'))
            refused(lines[:head] + [f'@{kind} Q {anims.addr(s)} {len(data)}'] + lines[head + 1:], 'the first line')
            refused(lines, 'the first line', size=len(data) + 1)
            a1 = next(i for i, x in enumerate(lines) if x.startswith('@anim 1'))
            refused([x.replace('@anim 1 ', '@anim 2 ', 1) for x in lines], 'animation 2, expected 1')
            refused([x.replace(f' {word} ', ' size ', 1) if x.startswith('@anim 1') else x for x in lines],
                    'expected @anim 1')
            refused([x.replace('$E4:', '$E4:1', 1) if x.startswith('@anim 1') else x for x in lines], 'bad address')
            moved = list(lines)
            parts = moved[a1].split()
            parts[2] = anims.addr(anims.parse_addr(parts[2], 'x') + 1)
            moved[a1] = ' '.join(parts)
            refused(moved, 'animation 1 starts at')
            longer = list(lines)
            parts = longer[a1].split()
            parts[4] = str(int(parts[4]) + 1)
            longer[a1] = ' '.join(parts)
            refused(longer, 'more byte|a row of|expected "facing')
            row = a1 + (2 if kind == 'animframes' else 1)
            short = list(lines)
            short[row] = ' '.join(short[row].split()[:3])
            refused(short, 'a row of 4 hex byte')
            hexes = list(lines)
            hexes[row] = hexes[row].replace(hexes[row].split()[0], 'G1', 1)
            refused(hexes, 'expected|a row of')
            low = list(lines)
            low[row] = '  aa ' + ' '.join(low[row].split()[1:])
            refused(low, 'expected|a row of')
            refused(lines[:-1], 'more byte')
            refused(lines + ['  00'], 'expected @anim 3')
            if kind == 'animframes':
                refused([x.replace('facing 2', 'facing 3') for x in lines], 'expected "facing 2"')
        data, s, lists = self.piece('animtimes')
        lines = anims.render('animtimes', 'P', s, data, lists).splitlines()
        last = lines.index('@anim 2 $E4:A80A bytes 8')
        with self.assertRaisesRegex(anims.AnimsError, 'the lists make 10 B, the piece is 18 B'):
            anims.assemble('animtimes', '\n'.join(lines[:last]), 'P', s, len(data))

    def test_render_refusals(self):
        data, s, lists = self.piece('animtimes')
        with self.assertRaisesRegex(anims.AnimsError, 'do not tile the piece'):
            anims.render('animtimes', 'P', s, data, lists[1:])
        with self.assertRaisesRegex(anims.AnimsError, 'the lists end at'):
            anims.render('animtimes', 'P', s, data + b'\0', lists)

    def test_piece_text(self):
        rom = make_rom()
        lists = lists_of(rom)
        v = lists['animtimes']
        p = {'label': 'P', 'piece': 'animtimes', 'offset': v['start'], 'stop': v['stop'],
             'size': str(v['stop'] - v['start'])}
        text = anims.piece_text(p, bytes(rom), lists)
        self.assertEqual(anims.assemble_piece(p, text), bytes(rom[v['start']:v['stop']]))
        saved = anims.assemble
        anims.assemble = lambda kind, text, label, start, size, name='': bytes(size)
        try:
            with self.assertRaisesRegex(anims.AnimsError, 'P: does not assemble back'):
                anims.piece_text(p, bytes(rom), lists)
        finally:
            anims.assemble = saved


class Extract(unittest.TestCase):

    def pieces(self, rom):
        lists = lists_of(rom)
        out = []
        for s, e, k in anims.want_rows(lists):
            out.append({'label': f'L{s:X}', 'offset': s, 'stop': e, 'size': str(e - s), 'piece': k})
        return out

    def test_extract_texts(self):
        rom = make_rom()
        pieces = self.pieces(rom)
        texts, problems = anims.extract_texts(bytes(rom), pieces, D)
        self.assertEqual(problems, [])
        self.assertEqual(sorted(texts), sorted(p['label'] for p in pieces if p['piece'] in anims.KINDS))
        self.assertEqual(anims.extract_texts(bytes(rom), [p for p in pieces if p['piece'] == 'fill'], D), ({}, []))

    def test_extract_refusals(self):
        rom = make_rom()
        pieces = self.pieces(rom)
        texts, problems = anims.extract_texts(bytes(rom), pieces[1:], D)
        self.assertEqual(texts, {})
        self.assertTrue(any('not the lists' in x for x in problems))
        bad = bytearray(rom)
        bad[F(D['RomE4_PtrInit']) + 4] ^= 1
        texts, problems = anims.extract_texts(bytes(bad), pieces, D)
        self.assertEqual(texts, {})
        self.assertTrue(any('Field_E4Ptr2' in x for x in problems))
        bad = bytearray(rom)
        bad[F(D['RomE4_PtrInit']) + 10] ^= 1
        texts, problems = anims.extract_texts(bytes(bad), pieces, D)
        self.assertEqual(texts, {})
        self.assertTrue(any(x.startswith('anims: animframes') for x in problems))
        saved = anims.piece_text

        def fail(*a):
            raise anims.AnimsError('lost')
        anims.piece_text = fail
        try:
            self.assertIn('lost', anims.extract_texts(bytes(rom), pieces, D)[1])
        finally:
            anims.piece_text = saved


class Manifest(unittest.TestCase):

    def test_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        pieces = [p for p in ed.read_manifest() if p['piece'] in anims.KINDS]
        self.assertEqual(sorted(p['piece'] for p in pieces), ['animframes', 'animtimes'])
        for p in pieces:
            self.assertEqual(anims.is_piece_row(rows[p['start']]), p['piece'])
            self.assertEqual(p['asset'], f'anims/{p["label"]}.{anims.ASSET_EXT[p["piece"]]}')
            self.assertEqual(p['param'], '')
            self.assertIn(f'../../build/anims/{p["label"]}.bin', ed.allowed_incbins(pieces))
            self.assertEqual(ed.placeholder_files(pieces)[ed.text_out(p)], int(p['size']))

    def test_survey_rows_choose_the_piece(self):
        row = {'start': '$E4:3000', 'end': '$E4:300F', 'size': '16', 'bank': '$E4', 'kind': 'table',
               'format': anims.FORMAT['animframes'] + ' x', 'readers': '', 'confidence': 'confirmed', 'notes': 'x'}
        self.assertEqual([(p['piece'], p['asset']) for p in ed.layout([row])],
                         [('animframes', 'anims/Table_E43000.anf')])
        self.assertEqual([p['piece'] for p in ed.layout([dict(row, format=anims.FORMAT['animtimes'])])],
                         ['animtimes'])
        self.assertEqual([p['piece'] for p in ed.layout([dict(row, format='lists')])], ['extracted'])
        self.assertEqual([p['piece'] for p in ed.layout([dict(row, kind='unknown')])], ['extracted'])

    def test_manifest_form(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'data_assets.csv'
            text = ed.MANIFEST.read_text()
            for p in [x for x in ed.read_manifest() if x['piece'] in anims.KINDS]:
                ext = anims.ASSET_EXT[p['piece']]
                line = f'{p["label"]},{p["start"]},{p["end"]},{p["size"]},{p["piece"]},anims/{p["label"]}.{ext},'
                self.assertIn(line + '\n', text)
                other = 'ant' if ext == 'anf' else 'anf'
                for bad in (line + 'x', line.replace(f'.{ext},', f'.{other},'), line.replace('anims/', 'sprites/')):
                    path.write_text(text.replace(line + '\n', bad + '\n'))
                    self.assertTrue(any(f'{p["piece"]} piece' in x for x in ed.manifest_problems(path)), bad)


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_round_trips(self):
        self.assertEqual(anims.check(ed.read_rom()), [])

    def test_the_lists(self):
        lists = anims.derive(ed.read_rom())
        self.assertEqual(len(lists['animframes']['lists']), 193)

    def test_extraction(self):
        rom = ed.read_rom()
        pieces = ed.read_manifest()
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(ed.extract_text_tools(rom, Path(tmp), pieces), [])
            self.assertEqual(sorted(x.name for x in (Path(tmp) / 'anims').iterdir()),
                             ['AnimRom_FrameLists.anf', 'AnimRom_TimeLists.ant'])
        k = next(i for i, p in enumerate(pieces) if p['piece'] == 'animtimes')
        bad = pieces[:k] + [dict(pieces[k], piece='extracted')] + pieces[k + 1:]
        with tempfile.TemporaryDirectory() as tmp:
            self.assertTrue(ed.extract_text_tools(rom, Path(tmp), bad))
            self.assertFalse((Path(tmp) / 'anims').exists())


if __name__ == '__main__':
    unittest.main()
