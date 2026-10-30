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
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'x.inc').write_text('struct Open $C00000\n.A: skip 1\n')
            saved = records.INCLUDE
            records.INCLUDE = Path(tmp)
            try:
                with self.assertRaisesRegex(records.RecordsError, 'struct Open: no endstruct'):
                    records._struct_fields('Open')
            finally:
                records.INCLUDE = saved

    def test_piece_without_a_layout(self):
        with self.assertRaisesRegex(records.RecordsError, 'X: no layout in tools/records.py'):
            records.piece_layout({'label': 'X', 'start': '$C0:0000', 'param': 'table 1 x 1 B'})

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
        for size, why in ((7, 'not a whole number of 2-byte records'), (6, '3 records, the reader'),
                          (10, '5 records, the reader')):
            with self.subTest(size=size), self.assertRaisesRegex(records.RecordsError, why):
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
            'columns': head + good.replace('\t0A 0B 0C', ''),
            'number': head + good.replace('$0203', 'x'),
            'bytes_short': head + good.replace('0A 0B 0C', '0A 0B'),
            'bytes_hex': head + good.replace('0A 0B 0C', '0A 0B 0G'),
            'count': head + good + good.replace('0\t', '1\t', 1),
        }
        for name, text in cases.items():
            with self.subTest(case=name), self.assertRaises(records.RecordsError):
                records.encode(text, lay, 'T')
        with self.assertRaisesRegex(records.RecordsError, '9 values, the layout has 10'):
            records.encode(cases['columns'], lay, 'T')
        with self.assertRaises(records.RecordsError):        # a label in another bank
            records.encode(head + good.replace('$0405', 'L'), lay, 'T', {'L': 0x090000})


import battle  # noqa: E402

D = battle.defines(ed.ROOT)
F = lambda a: a - 0xC00000      # noqa: E731


def obj_rom(lists):
    """A synthetic image: the three object tables (every entry $FFFF but
    the first few, which point at `lists`), and the object records."""
    rom = bytearray(0x400000)
    lo, hi = F(D['BattleRom_PcAttackObjs']), F(D['BattleRom_EnemyActObjs']) + 512
    rom[lo:hi] = b'\xff' * (hi - lo)
    ce = F(0xCE0000)
    for k, (ofs, recs) in enumerate(lists):
        if k % 2 == 0:                      # in PcAttackObjs, else in EnemyActObjs
            rom[lo + 2 * k:lo + 2 * k + 2] = ofs.to_bytes(2, 'little')
        else:
            rom[hi - 2 - 2 * k:hi - 2 * k] = ofs.to_bytes(2, 'little')
        for j, t in enumerate(recs):
            rom[ce + ofs + 4 * j] = t
    return rom


END, MARK, STOP = 0x80, 0x40, 0x20        # 1xx ends a list, 010 is a mark, 001 ends it (count 0)


def lists_of(n_ends):
    """16 lists: records of type 0, each list ended by an end record."""
    out = []
    for k in range(16):
        out += [0x01] * n_ends + [END if k % 2 else STOP]
    return out


class Derived(unittest.TestCase):

    def test_object_lists(self):
        recs = lists_of(1)
        rom = obj_rom([(0x9000, recs)])
        self.assertEqual(records.obj_lists_extent(bytes(rom), D), (F(0xCE9000), F(0xCE9000) + 4 * len(recs)))
        marks = [0x01, MARK, 0x01] + recs
        rom = obj_rom([(0x9000, marks)])
        self.assertEqual(records.obj_lists_extent(bytes(rom), D)[1], F(0xCE9000) + 4 * len(marks))

    def test_first_record_of_lists_1_to_15_untested(self):
        recs = [END] + [END, END] * 15             # each later list's first record is skipped, its second ends it
        rom = obj_rom([(0x9000, recs)])
        self.assertEqual(records.obj_lists_extent(bytes(rom), D)[1], F(0xCE9000) + 4 * 31)

    def test_overlapping_and_gaps(self):
        recs = lists_of(1)
        rom = obj_rom([(0x9000, recs), (0x9008, recs[2:] + [0x01, END])])
        s, e = records.obj_lists_extent(bytes(rom), D)
        self.assertEqual(s, F(0xCE9000))
        rom = obj_rom([(0x9000, recs), (0x9000 + 4 * len(recs) + 4, recs)])
        with self.assertRaisesRegex(records.RecordsError, 'leave a gap'):
            records.obj_lists_extent(bytes(rom), D)
        rom = obj_rom([(0x9000, recs), (0x9002, recs)])
        with self.assertRaisesRegex(records.RecordsError, 'leave a gap'):
            records.obj_lists_extent(bytes(rom), D)

    def test_loc_tilesets(self):
        rom = bytearray(0x400000)
        for k in range(512):
            rom[F(0xF60000) + 14 * k + 1] = D['LocRom_SetNone']
        rom[F(0xF60000) + 14 * 7 + 1] = 12
        rom[F(0xF60000) + 14 * 9 + 1] = 3
        self.assertEqual(records._loc_tilesets(bytes(rom), D), 13)

    def test_loc_palettes(self):
        rom = bytearray(0x400000)
        rom[F(0xF60000) + 14 * 300 + 3] = 87
        self.assertEqual(records._loc_palettes(bytes(rom), D), 7 * 88)
        self.assertEqual(records._loc_palettes(bytes(rom), dict(D, LocPal_RowBytes=28)), -1)
        self.assertEqual(records._loc_palettes(bytes(rom), dict(D, LocPal_SetBytes=0xD0)), -1)

    def test_loc_fields_from_the_struct_and_survey(self):
        rom = bytearray(0x400000)
        rows = [{'start': '$F6:0000', 'size': str(14 * 4)}]                # four records
        rom[F(0xF60000) + 14 * 3 + 3] = 5                                   # record 3's Palette (struct offset 3)
        rom[F(0xF60000) + 14 * 4 + 3] = 9                                   # past the survey's records
        rom[F(0xF60000) + 14 * 3 + 1] = 6                                   # record 3's Tileset12
        self.assertEqual(records._loc_palettes(bytes(rom), D, rows), 7 * 6)
        self.assertEqual(records._loc_tilesets(bytes(rom), D, rows), 7)
        rom[F(0xF60000) + 14 * 2 + 4:F(0xF60000) + 14 * 2 + 6] = bytes([0x02, 0x01])   # MapProps: u16 at 4
        self.assertEqual(records._loc_field(bytes(rom), D, 'MapProps', rows), [0, 0, 0x102, 0])
        with self.assertRaisesRegex(records.RecordsError, 'struct LocRom is 14 B; LocRom_RecSize is 16'):
            records._loc_palettes(bytes(rom), dict(D, LocRom_RecSize=16), rows)
        with self.assertRaisesRegex(records.RecordsError, 'no survey row of whole LocRom records'):
            records._loc_palettes(bytes(rom), D, [{'start': '$F6:0000', 'size': '15'}])
        with self.assertRaisesRegex(records.RecordsError, 'no survey row of whole LocRom records'):
            records._loc_palettes(bytes(rom), D, [])

    def test_bg_set_rows_from_the_source(self):
        self.assertEqual(records._bg_set_rows(), 15)
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'd1.asm'
            path.write_text('BattleFx_BgSetPalOfs:\n    dw $0000, $01E0  ; sets\n')
            self.assertEqual(records._bg_set_rows(path), 18)
            path.write_text('BattleFx_BgSetPalOfsX:\n    dw $0000\n')
            with self.assertRaisesRegex(records.RecordsError, 'no BattleFx_BgSetPalOfs'):
                records._bg_set_rows(path)
            path.write_text('BattleFx_BgSetPalOfs:\n    db $00\n')
            with self.assertRaisesRegex(records.RecordsError, 'expected a dw line'):
                records._bg_set_rows(path)

    def test_derived_counts(self):
        rom = ed.read_rom() if HAVE_ROM else None
        if rom is None:
            self.skipTest('needs the ROM')
        self.assertEqual(records.derived_problems(rom, D, ed.read_manifest()), [])
        for name, value, start in (('Battle_LevelMax', 98, '$CC:2632'), ('Battle_EnemyRec46Bytes', 4, '$CC:4700'),
                                   ('Battle_EnemyPartNone', 254, '$CC:7AC9'), ('Battle_EffectRecSize', 13, '$CC:7AC9'),
                                   ('BattleCD_GfxPartTiles', 16, '$CF:A000'), ('ObjPal_CopyCount', 0x18, '$E4:0000'),
                                   ('SprRec_FirstNpc', 8, '$E4:F000'), ('LocRom_SetNone', 53, '$F6:1C00'),
                                   ('Battle_ActObjects', 15, '$CE:8870'), ('LocPal_RowBytes', 28, '$F6:24C0'),
                                   ('Pal_Row0SetMask', 8, '$FF:B210'), ('Menu_WinStyleMask', 3, '$FF:B210')):
            got = records.derived_problems(rom, dict(D, **{name: value}), ed.read_manifest())
            self.assertTrue(any(x.startswith(start) for x in got), (name, got))
        no_piece = [p for p in ed.read_manifest() if p['label'] != 'BattleRom_ActObjRec_Lists']
        self.assertTrue(any('no records piece starts at the object lists' in x
                            for x in records.derived_problems(rom, D, no_piece)))
        bad = bytearray(rom)
        bad[F(D['BattleRom_EnemyActObjs'])] ^= 0x02                 # an object pointer moved off a record
        self.assertTrue(any(x.startswith('$CE:8870') for x in records.derived_problems(bytes(bad), D)))
        saved = records.DERIVED
        records.DERIVED = dict(saved, **{'$CC:0000': ('nothing', lambda r, d: 1)})
        try:
            self.assertTrue(any(x.startswith('$CC:0000') for x in records.derived_problems(rom, D)))
        finally:
            records.DERIVED = saved

    def test_extraction_refuses_a_wrong_count(self):
        if not HAVE_ROM:
            self.skipTest('needs the ROM')
        saved = records.DERIVED
        records.DERIVED = dict(saved, **{'$CC:2632': ('levels', lambda r, d: 99)})
        try:
            with self.assertRaisesRegex(records.RecordsError, '\\$CC:2632: levels give 99 records'):
                records.extract_all(ed.read_rom(), ed.read_manifest())
            self.assertTrue(records.check(ed.read_rom()))
        finally:
            records.DERIVED = saved


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_every_piece_round_trips(self):
        self.assertEqual(records.check(ed.read_rom()), [])

    def test_a_piece_that_does_not_encode_back(self):
        saved = records.encode
        records.encode = lambda *a, **k: b''
        try:
            got = records.check(ed.read_rom())
            self.assertTrue(got and all('does not encode back' in x for x in got))
            with self.assertRaisesRegex(records.RecordsError, 'does not encode back'):
                records.extract_all(ed.read_rom(), ed.read_manifest())
        finally:
            records.encode = saved


if __name__ == '__main__':
    unittest.main(verbosity=1)
