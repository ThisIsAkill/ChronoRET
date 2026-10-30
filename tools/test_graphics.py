#!/usr/bin/env python3
"""
test_graphics.py — Tests for tools/graphics.py (the tile graphics as
indexed PNGs).

    python3 tools/test_graphics.py          (from the repository root)

Without the ROM: the tile layouts on hand-made tiles (planes, bit order,
the 3bpp plane 2), the codecs' round trips, the PNG reader on images this
tool does not write (other row filters, a lower bit depth) and its
refusals (not indexed, interlaced, a bad CRC, cut short, no signature,
IHDR or IEND, data that does not inflate or is the wrong size, an unknown
row filter), the param and sidecar lines, the piece size, the image
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
            + chunk(b'PLTE', g.grey_ramp(4) + bytes(36)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


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

    def test_malformed_png_refused(self):
        good = self.png()
        ihdr_end = 8 + 12 + 13

        def chunk_file(*chunks):
            return b'\x89PNG\r\n\x1a\n' + b''.join(g._chunk(k, b) for k, b in chunks)
        ihdr = good[16:29]
        for data, why in (
                (b'GIF89a' + good[6:], 'not a PNG file'),
                (good[:ihdr_end + 3], 'ends inside a chunk header'),
                (good[:-12], 'no IHDR or no IEND'),
                (chunk_file((b'IHDR', ihdr), (b'PLTE', g.grey_ramp(4)), (b'IDAT', b'not zlib'), (b'IEND', b'')), 'does not inflate'),
                (chunk_file((b'IHDR', ihdr), (b'PLTE', g.grey_ramp(4)), (b'IDAT', zlib.compress(bytes(10))), (b'IEND', b'')),
                 'image data is 10 B, not'),
                (chunk_file((b'IHDR', ihdr), (b'PLTE', g.grey_ramp(4)), (b'IDAT', zlib.compress(bytes([5] + [0] * 128) * 16)),
                            (b'IEND', b'')), 'row filter 5')):
            with self.subTest(why=why):
                with self.assertRaisesRegex(g.GraphicsError, why):
                    g.read_png(data)

    def test_palette_must_be_the_ramp_written(self):
        good = self.png()
        _, _, px = g.read_png(good)
        i = good.index(b'PLTE') - 4
        n = int.from_bytes(good[i:i + 4], 'big')
        ramp = g.grey_ramp(4)
        # an editor's reorder: colours 1 and 2 swapped, the indices remapped; the picture is the same
        swapped = ramp[:3] + ramp[6:9] + ramp[3:6] + ramp[9:]
        remap = [{1: 2, 2: 1}.get(v, v) for v in px]
        png = png_with(128, 16, remap)
        png = png.replace(g._chunk(b'PLTE', g.grey_ramp(4) + bytes(36)), g._chunk(b'PLTE', swapped))
        with self.assertRaisesRegex(g.GraphicsError, r'not the grey ramp .* \(entry 1 is \(170, 170, 170\)'):
            g.from_image('2bpp', 32, png, b'')
        no_plte = good[:i] + good[i + 12 + n:]
        with self.assertRaisesRegex(g.GraphicsError, 'no PLTE chunk'):
            g.read_png(no_plte)
        self.assertEqual(g.from_image('2bpp', 32, good, b''), DATA)      # the ramp as written

    def test_bytes_after_iend_and_second_ihdr_refused(self):
        good = self.png()
        with self.assertRaisesRegex(g.GraphicsError, '4 B after its IEND chunk'):
            g.read_png(good + b'junk')
        twice = good[:33] + good[8:33] + good[33:]
        with self.assertRaisesRegex(g.GraphicsError, 'second or malformed IHDR'):
            g.read_png(twice)

    def test_png_errors_name_the_file(self):
        with self.assertRaisesRegex(g.GraphicsError, '^x.png: not a PNG file'):
            g.from_image('2bpp', 32, b'junk', b'', 'x.png')

    def test_param_and_sidecar_lines_checked(self):
        with self.assertRaisesRegex(g.GraphicsError, 'not a graphics param'):
            g.parse_param('2bpp 32 tile')
        side = g.sidecar('X', '$FF:0000', '$FF:01FF', '2bpp', 32, b'')
        with self.assertRaisesRegex(g.GraphicsError, 'no tiles line'):
            g.read_sidecar(side.replace('tiles 32', 'tile 32'))
        with self.assertRaisesRegex(g.GraphicsError, 'format, tiles or width'):
            g.read_sidecar(side.replace('width 16', 'width 8'))

    def test_piece_size_checked(self):
        p = {'label': 'X', 'param': '2bpp 32 tiles', 'size': str(len(DATA) + 1), 'start': '$FF:0000',
             'end': '$FF:01FF'}
        side = g.sidecar('X', '$FF:0000', '$FF:01FF', '2bpp', 32, b'')
        with self.assertRaisesRegex(g.GraphicsError, '512 B; the piece is 513'):
            g.encode_piece(p, self.png(), side)

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
        p = {'label': 'X', 'param': '2bpp 32 tiles', 'size': str(len(DATA)), 'start': '$FF:0000', 'end': '$FF:01FF'}
        side = g.sidecar('X', '$FF:0000', '$FF:01FF', '2bpp', 32, b'')
        self.assertEqual(g.encode_piece(p, self.png(), side), DATA)
        with self.assertRaisesRegex(g.GraphicsError, 'the sidecar says 4bpp'):
            g.encode_piece(p, self.png(), side.replace('format 2bpp', 'format 4bpp'))
        with self.assertRaisesRegex(g.GraphicsError, 'the sidecar is for Y'):
            g.encode_piece(p, self.png(), side.replace('region X', 'region Y'))
        with self.assertRaisesRegex(g.GraphicsError, r'the sidecar is for X \$12:3456'):
            g.encode_piece(p, self.png(), side.replace('$FF:0000 $FF:01FF', '$12:3456 $12:FFFF'))
        with self.assertRaisesRegex(g.GraphicsError, 'a second format line'):
            g.encode_piece(p, self.png(), side + 'format 2bpp\n')

    def test_tail_kept(self):
        data = DATA + b'\x12\x34'
        png, tail = g.to_image('2bpp', data, 2)
        p = {'label': 'X', 'param': '2bpp 32 tiles + 2 B', 'size': str(len(data)), 'start': '$FF:0000',
             'end': '$FF:0201'}
        side = g.sidecar('X', '$FF:0000', '$FF:0201', '2bpp', 32, tail)
        self.assertEqual(g.encode_piece(p, png, side), data)
        with self.assertRaisesRegex(g.GraphicsError, 'the tail is XX bytes'):
            g.encode_piece(p, png, side.replace('tail 12 34', 'tail 12 3'))


def fake_rows(packs):
    """Survey rows for derive_packed: the location records and packs
    ([(table, index, unpacked size)])."""
    rows = [{'start': '$F6:0000', 'size': str(14 * 4), 'kind': 'table', 'format': '', 'notes': ''}]
    for k, (table, i, size) in enumerate(packs):
        rows.append({'start': f'$E0:{k * 16:04X}', 'size': '16', 'kind': 'packed_lz',
                     'format': f'lz12 -> {size} B', 'notes': f'via {table}[{i}]; repacks'})
    return rows


class Packed(unittest.TestCase):
    """Which packs are tiles, from the data that names them (a synthetic
    ROM: four location records, a pack list, no scene headers)."""

    def rom(self, recs, lists):
        rom = bytearray(ed.ROM_SIZE)
        for k, (t12, t3) in enumerate(recs):
            rom[0x360000 + 14 * k + 1], rom[0x360000 + 14 * k + 2] = t12, t3
        for k, b in enumerate(lists):
            rom[0x361C00 + k] = b
        return bytes(rom)

    def test_uses_give_format_and_extent(self):
        rows = fake_rows([('LocGfx_PackPtrs', 1, 4096), ('LocGfx_PackPtrs', 2, 4096), ('LocGfx_PackPtrs', 3, 4096),
                          ('LocGfx_PackPtrs', 4, 4096), ('BattleRom_SprTilesPtr', 0, 2816)])
        lists = [1, 0xFF, 0xFF, 0xFF, 0xFF, 2, 4, 0xFF]          # pack 1 in slot 0, 2 in slot 5, 4 in slot 6
        got, conflicts = g.derive_packed(self.rom([(0, 3), (0xFF, 0xFF), (0xFF, 0xFF), (0xFF, 0xFF)], lists),
                                         rows)
        self.assertEqual(conflicts, [])
        self.assertEqual(got['$E0:0000'], ('4bpp', 4096, ('loc12',)))
        self.assertEqual(got['$E0:0010'], ('4bpp', 3968, ('loc12',)))      # pack 5: $0F80 B uploaded
        self.assertEqual(got['$E0:0020'], ('2bpp', 4096, ('loc3',)))
        self.assertNotIn('$E0:0030', got)                                  # slot 6: no reader traced
        self.assertEqual(got['$E0:0040'], ('4bpp', 2816, ('spr',)))

    def test_party_slot_is_not_a_proof(self):
        def rom_with(obj):
            rom = bytearray(self.rom([(0xFF, 0xFF)] * 4, [0xFF] * 8))
            rom[0x06FD00:0x06FD02] = bytes([0x02, 0xFD])                # one scene header, at $C6:FD02
            hdr = bytearray([0x80] * 0x20)
            hdr[0x0C:0x10] = bytes(obj)
            rom[0x06FD02:0x06FD22] = hdr
            return bytes(rom)
        rows = fake_rows([('C2SceneRom_ObjPacks', 5, 8192)])
        got, _ = g.derive_packed(rom_with([0x80, 0x80, 5, 0x80]), rows)
        self.assertNotIn('$E0:0000', got)                       # slot 2: the party graphics go over it
        got, _ = g.derive_packed(rom_with([5, 0x80, 0x80, 0x80]), rows)
        self.assertEqual(got['$E0:0000'], ('4bpp', 8192, ('scene_obj',)))   # into slot 1, not past it
        got, _ = g.derive_packed(rom_with([0x80, 5, 0x80, 0x80]), rows)
        self.assertEqual(got['$E0:0000'], ('4bpp', 4096, ('scene_obj',)))

    def test_two_formats_refused(self):
        rows = fake_rows([('LocGfx_PackPtrs', 1, 4096)])
        got, conflicts = g.derive_packed(self.rom([(0, 1), (0xFF, 0xFF), (0xFF, 0xFF), (0xFF, 0xFF)],
                                                  [1] + [0xFF] * 7), rows)
        self.assertNotIn('$E0:0000', got)
        self.assertEqual(conflicts, ['$E0:0000: read as 2bpp and 4bpp'])

    def test_manifest_gfxpack_form_checked(self):
        import tempfile
        text = ed.MANIFEST.read_text()
        line = next(ln for ln in text.splitlines() if ',gfxpack,' in ln)
        bad = line.replace('; 4bpp', '; 5bpp')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'm.csv'
            path.write_text(text.replace(line, bad))
            self.assertTrue(any('a gfxpack piece' in x for x in ed.manifest_problems(path)))
        with self.assertRaisesRegex(ed.DataError, 'not a pack param'):
            ed.pack_param('4bpp 3 tiles')

    def test_packed_must_be_what_the_data_gives(self):
        packed = {('loc12',): {'$E0:0000': 4096}}
        self.assertEqual(g.packed_problems({'$E0:0000': ('4bpp', 4096, ('loc12',))}, [], packed), [])
        self.assertEqual(g.packed_problems({'$E0:0000': ('4bpp', 3968, ('loc12',))}, [], packed),
                         ["packed graphics: $E0:0000 is ('4bpp', 3968, ('loc12',)) by the data, "
                          "('4bpp', 4096, ('loc12',)) in PACKED"])
        self.assertEqual(g.packed_problems({'$E0:0000': ('4bpp', 4096, ('loc12',))}, ['$E0:0010: read as x'], packed),
                         ['packed graphics: $E0:0010: read as x'])

    def test_pack_param_and_size(self):
        self.assertEqual(g.parse_param('lz12 -> 4096 B; 4bpp 124 tiles + 128 B'), ('4bpp', 124, 128))
        data = DATA + b'\x12\x34'
        png, tail = g.to_image('2bpp', data, 2)
        p = {'label': 'X', 'param': 'lz11 -> 514 B; 2bpp 32 tiles + 2 B', 'size': '300', 'piece': 'gfxpack',
             'start': '$E0:0000', 'end': '$E0:012B'}
        side = g.sidecar('X', '$E0:0000', '$E0:012B', '2bpp', 32, tail)
        self.assertEqual(g.encode_piece(p, png, side), data)              # the unpacked size, not the piece's
        p['param'] = 'lz11 -> 515 B; 2bpp 32 tiles + 2 B'
        with self.assertRaisesRegex(g.GraphicsError, '514 B; the piece is 515'):
            g.encode_piece(p, png, side)


class Source(unittest.TestCase):

    def test_manifest_gfxpack_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        pieces = [p for p in ed.read_manifest() if p['piece'] == 'gfxpack']
        want = {start for items in g.PACKED.values() for start in items}
        self.assertEqual({p['start'] for p in pieces}, want)
        for keys in g.PACKED:
            self.assertTrue(keys and all(k in g.PACK_PROOFS for k in keys))
        for p in pieces:
            self.assertEqual(rows[p['start']]['kind'], 'packed_lz')
            mode, size = ed.pack_param(p['param'])
            fmt, tiles, tail = g.parse_param(p['param'])
            self.assertEqual(tiles * g.TILE_BYTES[fmt] + tail, size)
            self.assertEqual((fmt, tiles, tail), g.packed_layout(p['start'], size))

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

    def test_check_compares_with_the_data(self):
        saved = g.derive_packed
        g.derive_packed = lambda rom, rows: ({}, ['a conflict'])
        try:
            got = g.check(ed.read_rom())
        finally:
            g.derive_packed = saved
        self.assertIn('packed graphics: a conflict', got)
        self.assertTrue(any('by the data, None in PACKED' not in x and 'None by the data' in x for x in got))


if __name__ == '__main__':
    unittest.main()
