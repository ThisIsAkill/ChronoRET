#!/usr/bin/env python3
"""
test_records.py — Tests for tools/records.py, tables and palettes as
readable records.

    python3 tools/test_records.py          (from the repository root)

Without the ROM: every layout names a survey row of the table or palette
kind, structs are read field by field from asm/include/, every structured
row is whole records (and the reader's count where one is given), and the
encoder on synthetic records (colours, signed bytes, pointers written as
labels, struct columns) round-trips and refuses bad input.

With the ROM: every records piece extracts and encodes back to the ROM's
bytes.
"""

import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402
import records  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists()


class Layouts(unittest.TestCase):

    def test_layouts_name_survey_rows(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        for start in list(records.STRUCTS) + list(records.ARRAYS):
            with self.subTest(row=start):
                self.assertIn(start, rows)
                self.assertIn(rows[start]['kind'], ('table', 'map') if start in records.STRUCTS else ('table',))
                self.assertNotIn(start, ed.TABLES)
        for start in records.PALETTES:
            with self.subTest(row=start):
                self.assertEqual(rows[start]['kind'], 'palette')

    def test_every_layout_has_its_readers_count(self):
        counts = [c for _, c in records.STRUCTS.values()] + [c for _, c in records.ARRAYS.values()] \
            + [c for _, c in records.PALETTES.values()]
        self.assertTrue(all(isinstance(c, int) and c > 0 for c in counts))

    def test_structs_from_the_source(self):
        fields = records._struct_fields('BattleRom_TechRec')
        self.assertEqual(fields[:2], [('UserSet', 'u8'), ('Flags', 'u8')])
        self.assertIn(('Unk_04', 'u8'), fields)                    # an unnamed skip
        self.assertEqual(fields[-1], ('PartUnk', 'bytes3'))         # no element width known: unsplit
        layout = records._struct_fields('BattleRom_FrameLayout')   # 6 words, read 16-bit
        self.assertEqual(layout[:6], [(f'RowOffset{k}', 'u16') for k in range(6)])
        self.assertIn(('Unk_02_05', 'bytes4'), records._struct_fields('BattleRom_ActObjInit'))
        loc = records._struct_fields('LocRom')
        self.assertIn(('MapProps', 'u16'), loc)
        self.assertIn(('Unk06', 'bytes2'), loc)
        with self.assertRaises(records.RecordsError):
            records._struct_fields('NoSuchStruct')

    def test_structured_rows_are_whole_records(self):
        pieces = [p for p in ed.read_manifest() if p['piece'] == 'records']
        self.assertGreater(len(pieces), 50)
        for p in pieces:
            with self.subTest(piece=p['label']):
                lay = records.piece_layout(p)
                n = records.check_extent(lay, int(p['size']), p['label'])
                self.assertEqual(p['param'].split()[1:], [str(n), 'x', str(lay.size), 'B'])

    def test_extent_refused(self):
        lay = records.Layout([('A', 'u16')], 4, 'test')
        self.assertEqual(records.Layout([('A', 'bytes5')], 1, 'test').size, 5)
        for size in (7, 6, 10):
            with self.subTest(size=size), self.assertRaises(records.RecordsError):
                records.check_extent(lay, size, 'x')
        self.assertEqual(records.check_extent(lay, 8, 'x'), 4)


class Codec(unittest.TestCase):

    LAYOUT = records.Layout([('A', 'u8'), ('B', 's8'), ('C', 'u16'), ('D', 'ptr16:C8'), ('E', 'colour'),
                             ('F', 'u24'), ('G', 'bytes3')], 21, 'test')

    def test_round_trip(self):
        rnd = random.Random(3)
        labels = {0x081234: 'Some_Label'}
        data = bytes(rnd.randrange(256) for _ in range(self.LAYOUT.size * 20))
        data += bytes([1, 2, 3, 4, 0x34, 0x12, 5, 6, 7, 8, 9, 10, 11, 12])      # D points at the label
        text = records.decode(data, self.LAYOUT, 'T', '$C0:0000', labels)
        self.assertIn('Some_Label', text)
        self.assertEqual(records.encode(text, self.LAYOUT, 'T', {'Some_Label': 0x081234}), data)

    def test_colour_columns(self):
        lay = records.Layout([('Colour', 'colour')], 1, 'test')
        text = records.decode(bytes([0x1F, 0x80]), lay, 'P', '$C0:0000')
        self.assertIn('Index\tColourR\tColourG\tColourB\tColourBit15\n0\t31\t0\t0\t1', text)
        self.assertEqual(records.encode('Index\tColourR\tColourG\tColourB\tColourBit15\n0\t1\t2\t3\t0\n',
                                        lay, 'P'), (1 | 2 << 5 | 3 << 10).to_bytes(2, 'little'))

    def test_bad_input(self):
        head = 'Index\tA\tB\tC\tD\tER\tEG\tEB\tEBit15\tF\tG\n'
        good = '0\t$01\t-1\t$0203\t$0405\t1\t2\t3\t0\t$060708\t0A 0B 0C\n'
        lay = records.Layout(self.LAYOUT.fields, 1, 'test')
        self.assertEqual(records.encode(head + good, lay, 'T')[-3:], bytes([10, 11, 12]))
        cases = {
            'header': 'Index\tA\n' + good,
            'index': head + good.replace('0\t', '1\t', 1),
            'too_big': head + good.replace('$01', '$100'),
            's8_range': head + good.replace('-1', '-129'),
            'colour_range': head + good.replace('\t1\t2\t3\t0', '\t32\t2\t3\t0'),
            'label': head + good.replace('$0405', 'NoLabel'),
            'columns': head + good.replace('\t$060708', ''),
            'number': head + good.replace('$0203', 'x'),
            'bytes_short': head + good.replace('0A 0B 0C', '0A 0B'),
            'bytes_hex': head + good.replace('0A 0B 0C', '0A 0B 0G'),
            'count': head + good + good.replace('0\t', '1\t', 1),
        }
        for name, text in cases.items():
            with self.subTest(case=name), self.assertRaises(records.RecordsError):
                records.encode(text, lay, 'T')
        with self.assertRaises(records.RecordsError):        # a label in another bank
            records.encode(head + good.replace('$0405', 'L'), lay, 'T', {'L': 0x090000})


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_every_piece_round_trips(self):
        self.assertEqual(records.check(ed.read_rom()), [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
