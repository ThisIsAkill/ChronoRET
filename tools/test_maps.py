#!/usr/bin/env python3
"""
test_maps.py — Tests for tools/maps.py (the location maps and metatiles as
text).

    python3 tools/test_maps.py          (from the repository root)

Without the ROM: a synthetic map (16x16 layers, layer 3 on and off, runs
across row ends, a stream that ends early) and metatile pack through the
readable forms and back, every refusal of the reader and the assembler,
and the manifest's map pieces.

With the ROM: every map and metatile pack converts and assembles back
byte-exact.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402
import maps  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists()


def make_map(layer3=False, attrs=None):
    header = bytes([0x00, 0x80 if layer3 else 0x00, 0, 0, 0x13, 0x00])
    planes = bytes(range(256)) + bytes(255 - i for i in range(256)) + (bytes([7]) * 256 if layer3 else b'')
    if attrs is None:
        attrs = [(1, 2, 3)] * 20 + [(0, 0, k) for k in range(5)] + [(4, 5, 6)] * 231   # a run over row ends
    return header + planes + maps.encode_attrs(attrs), attrs


class Maps(unittest.TestCase):

    def test_round_trip(self):
        for layer3 in (False, True):
            data, _ = make_map(layer3)
            text = maps.render_map('M', data)
            self.assertEqual(maps.assemble_map(text, 'M'), data)
            self.assertEqual('@layer3 16x16' in text, layer3)

    def test_runs_as_the_maps_have_them(self):
        self.assertEqual(maps.encode_attrs([(1, 2, 3)] * 300 + [(0, 0, 1)]),
                         bytes([0x81, 2, 3, 0, 0x81, 2, 3, 44, 0, 0, 1]))     # 256 is 0; a single stays three bytes

    def test_stream_that_ends_early(self):
        data, _ = make_map(attrs=[(1, 2, 3)] * 100)
        text = maps.render_map('M', data)
        self.assertIn(maps.MISSING, text)
        self.assertEqual(maps.assemble_map(text, 'M'), data)
        head, _, rest = text.rpartition(maps.MISSING)
        cells = head + '000000' + rest                                  # a cell after the end
        with self.assertRaisesRegex(maps.MapsError, 'the stream ends only once'):
            maps.assemble_map(cells, 'M')

    def test_reader_refusals(self):
        data, _ = make_map()
        for bad, why in ((data[:5], 'no MapProps header'), (data[:300], 'inside a layer plane'),
                         (data + b'\x00', '1 B after the planes'),
                         (data[:518] + bytes([0x81, 1, 1]), 'inside a run'),
                         (data[:518] + bytes([0x01, 1]), 'inside an entry'),
                         (data[:518] + bytes([1, 1, 1, 0x81, 1, 1, 0]), 'goes 1 tile')):
            with self.subTest(why=why):
                with self.assertRaisesRegex(maps.MapsError, why):
                    maps.split_map(bad, 'M')

    def test_other_runs_refused_when_extracting(self):
        data, _ = make_map(attrs=[(1, 2, 3)] * 256)
        single = data[:518] + bytes([1, 2, 3]) + bytes([0x81, 2, 3, 255])       # the same tiles, other runs
        with self.assertRaisesRegex(maps.MapsError, 'not the ones the readable form re-makes'):
            maps.render_map('M', single)

    def test_assembler_refusals(self):
        data, _ = make_map()
        text = maps.render_map('M', data)
        row = text.split('@layer1 16x16\n')[1].split('\n')[0]
        for old, new, why in (('@map M', '@map N', 'the first line is @map M'),
                              ('size3 $00', 'size3 $0', 'expected size3 \\$XX'),
                              ('size1 $00', 'size1 $01', 'expected @layer1 32x16'),
                              (row + '\n', row + ' 00\n', '17 cells; the row is 16'),
                              (row + '\n', '', '2 cells; the row is 16'),
                              (row, row.replace('00', 'G0', 1), "'G0' is not 2 hex digits"),
                              ('@attrs 16x16', '@layer9 1x1\n@attrs 16x16', 'expected @attrs 16x16'),
                              ('010203', '810203', 'HiBits \\$81 has bit 7 set')):
            with self.subTest(new=new):
                self.assertIn(old, text)
                with self.assertRaisesRegex(maps.MapsError, why):
                    maps.assemble_map(text.replace(old, new, 1), 'M')
        with self.assertRaisesRegex(maps.MapsError, '@attrs needs 16 rows'):
            maps.assemble_map('\n'.join(text.split('\n')[:-5]), 'M')
        with self.assertRaisesRegex(maps.MapsError, 'a line after the attribute grid'):
            maps.assemble_map(text + '00\n', 'M')
        with self.assertRaisesRegex(maps.MapsError, 'expected size1'):
            maps.assemble_map('@map M\n', 'M')

    def test_edit_assembles(self):
        data, _ = make_map()
        text = maps.render_map('M', data).replace('@layer1 16x16\n00 01', '@layer1 16x16\nAA 01', 1)
        out = maps.assemble_map(text, 'M')
        self.assertEqual(out[6], 0xAA)
        self.assertEqual(out[7:], data[7:])


class Metatiles(unittest.TestCase):

    DATA = bytes(range(256)) * 8                 # 256 metatiles of 8 bytes

    def test_round_trip(self):
        text = maps.render_meta('T', self.DATA, 256)
        self.assertEqual(maps.assemble_meta(text, 'T', 256), self.DATA)
        self.assertIn('000: 100/0 302/0 104/1 306/1', text)
        self.assertEqual(maps.word_value('3FF/7phv', 'x'), 0xFFFF)

    def test_refusals(self):
        text = maps.render_meta('T', self.DATA, 256)
        with self.assertRaisesRegex(maps.MapsError, '1 B; 256 metatiles are 2048'):
            maps.render_meta('T', b'\x00', 256)
        for old, new, why in (('@metatiles T 256', '@metatiles T 255', 'the first line is'),
                              ('001: ', '002: ', 'expected 001:'),
                              ('100/0 ', '400/0 ', "'400/0' is not a tilemap word"),
                              ('100/0 ', '100/8 ', "'100/8' is not a tilemap word")):
            with self.subTest(new=new):
                with self.assertRaisesRegex(maps.MapsError, why):
                    maps.assemble_meta(text.replace(old, new, 1), 'T', 256)
        with self.assertRaisesRegex(maps.MapsError, '255 metatile lines'):
            maps.assemble_meta(text.rsplit('\n', 2)[0] + '\n', 'T', 256)


class Source(unittest.TestCase):

    def test_manifest_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        pieces = [p for p in ed.read_manifest() if p['piece'] in ('mapprops', 'metatiles')]
        self.assertEqual(sum(p['piece'] == 'mapprops' for p in pieces), 201)
        for p in pieces:
            kind = maps.kind_of(rows[p['start']]['notes'])
            self.assertEqual(kind[0], p['piece'])
            if p['piece'] == 'metatiles':
                self.assertEqual(maps.meta_count(p), kind[1])
        for p in ed.read_manifest():               # a pack of another size stays packed
            if p['piece'] == 'packed' and maps.kind_of(rows[p['start']]['notes']):
                self.assertEqual(maps.kind_of(rows[p['start']]['notes'])[0], 'metatiles')
                self.assertNotEqual(maps.meta_count(p), maps.kind_of(rows[p['start']]['notes'])[1])


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_round_trips(self):
        self.assertEqual(maps.check(ed.read_rom()), [])


if __name__ == '__main__':
    unittest.main()
