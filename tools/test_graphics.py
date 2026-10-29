#!/usr/bin/env python3
"""
test_graphics.py — Tests for tools/graphics.py (the tile graphics as
indexed PNGs).

    python3 tools/test_graphics.py          (from the repository root)

Without the ROM: the tile layouts on hand-made tiles (planes, bit order,
the 3bpp plane 2), the codecs' round trips, the PNG reader on images this
tool does not write (other row filters, a lower bit depth) and its
refusals (not indexed, interlaced, a bad CRC, cut short), the image
checks (size, an index the format cannot hold, a cell past the last tile,
a sidecar that does not match), and the manifest's graphics pieces.

With the ROM: every graphics region converts and encodes back byte-exact.
"""

import random
import struct
import sys
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402
import graphics as g  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists()


def png_with(width, height, pixels, depth=8, ctype=3, filters=None, interlace=0):
    """A PNG written the way other tools may write one."""
    rows = []
    for y in range(height):
        row = pixels[y * width:(y + 1) * width]
        if depth < 8:
            b, acc, n = bytearray(), 0, 0
            for v in row:
                acc = acc << depth | v
                n += depth
                if n == 8:
                    b.append(acc)
                    acc, n = 0, 0
            if n:
                b.append(acc << (8 - n))
            row = bytes(b)
        else:
            row = bytes(row)
        f = (filters or [0])[y % len(filters or [0])]
        line, prev = bytearray(row), rows[-1][1] if rows else bytes(len(row))
        bpp = 1
        out = bytearray()
        for i in range(len(line)):
            a = line[i - bpp] if i >= bpp else 0
            b_, c = prev[i], prev[i - bpp] if i >= bpp else 0
            pred = {0: 0, 1: a, 2: b_, 3: (a + b_) // 2}.get(f)
            if f == 4:
                p = a + b_ - c
                pa, pb, pc = abs(p - a), abs(p - b_), abs(p - c)
                pred = a if pa <= pb and pa <= pc else b_ if pb <= pc else c
            out.append((line[i] - pred) & 0xFF)
        rows.append((bytes([f]) + bytes(out), bytes(line)))
    raw = b''.join(r for r, _ in rows)
    chunk = g._chunk
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, depth, ctype, 0, 0,
                                                                interlace))
            + chunk(b'PLTE', bytes(48)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


class Tiles(unittest.TestCase):

    def test_2bpp_layout(self):
        # row 0: plane 0 = $80 (leftmost pixel), plane 1 = $01 (rightmost)
        tile = bytes([0x80, 0x01]) + bytes(14)
        px = g.decode_tiles('2bpp', tile)[0]
        self.assertEqual(px[:8], [1, 0, 0, 0, 0, 0, 0, 2])
        self.assertEqual(g.encode_tiles('2bpp', [px]), tile)

    def test_4bpp_planes_2_and_3_after_16_bytes(self):
        tile = bytearray(32)
        tile[16], tile[17] = 0x80, 0x80        # row 0, planes 2 and 3, leftmost pixel
        self.assertEqual(g.decode_tiles('4bpp', bytes(tile))[0][0], 12)

    def test_3bpp_plane_2_one_byte_per_row(self):
        tile = bytearray(24)
        tile[16 + 7] = 0x01                    # row 7's plane 2, rightmost pixel
        self.assertEqual(g.decode_tiles('3bpp', bytes(tile))[0][63], 4)

    def test_round_trips(self):
        rnd = random.Random(7)
        for fmt, n in g.TILE_BYTES.items():
            data = bytes(rnd.randrange(256) for _ in range(n * 37))
            self.assertEqual(g.encode_tiles(fmt, g.decode_tiles(fmt, data)), data)
            png, tail = g.to_image(fmt, data, 0)
            self.assertEqual(g.from_image(fmt, 37, png, tail), data)

    def test_partial_tile_refused(self):
        with self.assertRaisesRegex(g.GraphicsError, 'no whole number'):
            g.decode_tiles('2bpp', bytes(17))

    def test_value_too_big_refused(self):
        with self.assertRaisesRegex(g.GraphicsError, 'does not fit'):
            g.encode_tiles('2bpp', [[4] + [0] * 63])


DATA = bytes(range(256)) * 2                 # 32 2bpp tiles


class Images(unittest.TestCase):

    def png(self):
        return g.to_image('2bpp', DATA, 0)[0]

    def test_other_filters_and_depth_read(self):
        _, _, px = g.read_png(self.png())
        for filters in ([1], [2], [3], [4], [0, 1, 2, 3, 4]):
            self.assertEqual(g.read_png(png_with(128, 16, px, 8, 3, filters))[2], px)
        self.assertEqual(g.from_image('2bpp', 32, png_with(128, 16, px, 4, 3, [4]), b''), DATA)

    def test_edit_encodes(self):
        _, _, px = g.read_png(self.png())
        px[0] = 3
        out = g.from_image('2bpp', 32, png_with(128, 16, px), b'')
        self.assertEqual(out[0] & 0x80 and out[1] & 0x80, 0x80)
        self.assertEqual(out[2:], DATA[2:])

    def test_not_indexed_refused(self):
        with self.assertRaisesRegex(g.GraphicsError, 'not indexed'):
            g.read_png(png_with(128, 16, [0] * 2048, 8, 0))

    def test_interlaced_refused(self):
        with self.assertRaisesRegex(g.GraphicsError, 'interlace 1'):
            g.read_png(png_with(128, 16, [0] * 2048, 8, 3, None, 1))

    def test_bad_crc_refused(self):
        b = bytearray(self.png())
        b[45] ^= 0xFF                          # a palette byte: only the CRC tells
        with self.assertRaisesRegex(g.GraphicsError, "PLTE' chunk fails its CRC"):
            g.read_png(bytes(b))

    def test_cut_short_refused(self):
        with self.assertRaisesRegex(g.GraphicsError, "ends inside its b'IDAT' chunk"):
            g.read_png(self.png()[:-14])

    def test_wrong_size_refused(self):
        with self.assertRaisesRegex(g.GraphicsError, 'the image is 128x24'):
            g.from_image('2bpp', 32, png_with(128, 24, [0] * 128 * 24), b'')

    def test_index_too_big_refused(self):
        _, _, px = g.read_png(self.png())
        px[5] = 4
        with self.assertRaisesRegex(g.GraphicsError, r'pixel \(5, 0\) is index 4'):
            g.from_image('2bpp', 32, png_with(128, 16, px), b'')

    def test_cell_past_the_last_tile_refused(self):
        png, _ = g.to_image('2bpp', DATA[:16 * 20], 0)       # 20 tiles: two rows, 12 cells empty
        _, _, px = g.read_png(png)
        px[8 * 128 + 127] = 1
        with self.assertRaisesRegex(g.GraphicsError, 'cell 31 is past the last tile'):
            g.from_image('2bpp', 20, png_with(128, 16, px), b'')

    def test_sidecar_must_match(self):
        p = {'label': 'X', 'param': '2bpp 32 tiles', 'size': str(len(DATA))}
        side = g.sidecar('X', '$FF:0000', '$FF:01FF', '2bpp', 32, b'')
        self.assertEqual(g.encode_piece(p, self.png(), side), DATA)
        with self.assertRaisesRegex(g.GraphicsError, 'the sidecar says 4bpp'):
            g.encode_piece(p, self.png(), side.replace('format 2bpp', 'format 4bpp'))
        with self.assertRaisesRegex(g.GraphicsError, 'the sidecar is for Y'):
            g.encode_piece(p, self.png(), side.replace('region X', 'region Y'))

    def test_tail_kept(self):
        data = DATA + b'\x12\x34'
        png, tail = g.to_image('2bpp', data, 2)
        p = {'label': 'X', 'param': '2bpp 32 tiles + 2 B', 'size': str(len(data))}
        side = g.sidecar('X', '$FF:0000', '$FF:0201', '2bpp', 32, tail)
        self.assertEqual(g.encode_piece(p, png, side), data)
        with self.assertRaisesRegex(g.GraphicsError, 'the tail is XX bytes'):
            g.encode_piece(p, png, side.replace('tail 12 34', 'tail 12 3'))


class Source(unittest.TestCase):

    def test_manifest_graphics_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        pieces = [p for p in ed.read_manifest() if p['piece'] == 'graphics']
        self.assertEqual({p['start'] for p in pieces}, set(g.FORMATS))
        for p in pieces:
            self.assertEqual(rows[p['start']]['kind'], 'graphics')
            fmt, tiles, tail = g.parse_param(p['param'])
            self.assertEqual(tiles * g.TILE_BYTES[fmt] + tail, int(p['size']))
            self.assertEqual(fmt, g.FORMATS[p['start']][0])


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_round_trips(self):
        self.assertEqual(g.check(ed.read_rom()), [])


if __name__ == '__main__':
    unittest.main()
