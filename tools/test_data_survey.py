#!/usr/bin/env python3
"""
test_data_survey.py — Tests for tools/data_survey.py and symbols/data_survey.csv.

    python3 tools/test_data_survey.py          (from the repository root)

Without the ROM or asar: the CSV is consistent on its own (fields, sizes,
order, banks), and the checker finds planted gaps, overlaps and bad sizes,
and reads a hand-made Decomp_ToWram stream to its end.

With the ROM and asar: the CSV covers exactly the bytes the source does not
emit, and every packed_lz row is one stream that ends at the row's last byte
and unpacks to the size its format gives.
"""

import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_survey as ds  # noqa: E402

READY = bool(ds.ROM_PATH.exists() and shutil.which('asar'))


def row(start, end, kind='table', conf='confirmed', fmt='x'):
    s, e = ds.parse_addr(start), ds.parse_addr(end) + 1
    return {'start': start, 'end': end, 'size': str(e - s), 'bank': start[:3], 'kind': kind,
            'format': fmt, 'readers': '', 'confidence': conf, 'notes': ''}


class Csv(unittest.TestCase):

    def test_csv_is_consistent(self):
        rows = ds.read_rows()
        _, problems = ds.check_rows(rows)
        self.assertEqual(problems, [])
        self.assertGreater(len(rows), 1000)

    def test_finds_overlap_size_and_bank_errors(self):
        rows = [row('$C3:1000', '$C3:10FF'), row('$C3:10F0', '$C3:11FF')]
        self.assertTrue(any('overlaps' in p for p in ds.check_rows(rows)[1]))
        bad = row('$C3:1000', '$C3:10FF')
        bad['size'] = '255'
        self.assertTrue(any('size' in p for p in ds.check_rows([bad])[1]))
        self.assertTrue(any('crosses' in p for p in ds.check_rows([row('$C3:FF00', '$C4:00FF')])[1]))
        self.assertTrue(any('kind' in p for p in ds.check_rows([row('$C3:0000', '$C3:0001', kind='code')])[1]))
        self.assertTrue(any('packed_lz' in p
                            for p in ds.check_rows([row('$C3:0000', '$C3:0001', kind='packed_lz')])[1]))

    def test_coverage_differences(self):
        free = [(0x100, 0x200), (0x300, 0x400)]
        self.assertEqual(ds.coverage_problems([(0x100, 0x200), (0x300, 0x400)], free), [])
        gap = ds.coverage_problems([(0x100, 0x180), (0x300, 0x400)], free)
        self.assertEqual(len(gap), 1)
        self.assertIn('not in the CSV', gap[0])
        extra = ds.coverage_problems([(0x100, 0x200), (0x2F0, 0x400)], free)
        self.assertEqual(len(extra), 1)
        self.assertIn('emitted by source', extra[0])

    def test_unpack_end(self):
        # W = 9: one control byte $00 (eight literals), then the final end marker $00.
        stream = bytes([9, 0, 0]) + bytes(range(1, 9)) + bytes([0])
        self.assertEqual(ds.unpack_end(stream + b'\xAA', 0), (len(stream), 8))
        # a back-reference with nothing unpacked yet is refused
        with self.assertRaises(ds.SurveyError):
            ds.unpack_end(bytes([3, 0, 1, 1, 0, 0]), 0)


@unittest.skipUnless(READY, 'needs the ROM and asar')
class Rom(unittest.TestCase):

    def test_covers_exactly_the_unemitted_bytes(self):
        ranges, problems = ds.check_rows(ds.read_rows())
        self.assertEqual(problems, [])
        self.assertEqual(ds.coverage_problems(ranges, ds.unemitted_ranges()), [])

    def test_pack_rows_are_streams(self):
        rows = ds.read_rows()
        problems, _ = ds.pack_problems(rows, ds.ROM_PATH.read_bytes(), repack=False)
        self.assertEqual(problems, [])


if __name__ == '__main__':
    unittest.main()
