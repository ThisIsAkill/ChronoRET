#!/usr/bin/env python3
"""
test_maps.py — Tests for tools/maps.py (the location maps and metatiles as
text).

    python3 tools/test_maps.py          (from the repository root)

Without the ROM: a synthetic map (16x16 layers, layer 3 on and off, runs
across row ends, a stream that ends early) and metatile pack through the
readable forms and back, every refusal of the reader and the assembler,
the manifest's map pieces, and which packs the location records name
(a synthetic ROM and survey; check compares them with the manifest).

With the ROM: every map and metatile pack converts and assembles back
byte-exact.
"""

import re
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


class SceneLayers(unittest.TestCase):

    MAPS = bytes((i * 7) & 0xFF for i in range(2 * 96 * 64))
    META = bytes(range(256)) * 16
    BG3 = bytes(range(256)) * 16

    def test_round_trips(self):
        for render, assemble, data in ((maps.render_scene_maps, maps.assemble_scene_maps, self.MAPS),
                                       (maps.render_scene_meta, maps.assemble_scene_meta, self.META),
                                       (maps.render_bg3, maps.assemble_bg3, self.BG3),
                                       (maps.render_bg3, maps.assemble_bg3, self.BG3[:2048])):
            with self.subTest(render=render.__name__, n=len(data)):
                self.assertEqual(assemble(render('S', data), 'S'), data)

    def test_size_refused(self):
        for render, n, why in ((maps.render_scene_maps, 100, 'the two layer maps are 12288'),
                               (maps.render_scene_meta, 100, 'the two metatile sets are 4096'),
                               (maps.render_bg3, 100, 'no whole number of 32x32-word screens')):
            with self.subTest(why=why):
                with self.assertRaisesRegex(maps.MapsError, why):
                    render('S', bytes(n))

    def test_scene_maps_refusals(self):
        text = maps.render_scene_maps('S', self.MAPS)
        row = text.split('@layer1 96x64\n')[1].split('\n')[0]
        for old, new, why in (('@scenemaps S', '@scenemaps T', 'the first line is @scenemaps S'),
                              ('@layer2 96x64', '@layer2 96x63', 'expected @layer2 96x64'),
                              (row + '\n', row + ' 00\n', '97 cells; the row is 96'),
                              (row + '\n', '', 'needs 64 rows'),
                              (row, row.replace(row[:2], 'ZZ', 1), "'ZZ' is not 2 hex digits")):
            with self.subTest(new=new[:20]):
                with self.assertRaisesRegex(maps.MapsError, why):
                    maps.assemble_scene_maps(text.replace(old, new, 1), 'S')
        with self.assertRaisesRegex(maps.MapsError, 'a line after layer 2'):
            maps.assemble_scene_maps(text + '00\n', 'S')

    def test_scene_meta_refusals(self):
        text = maps.render_scene_meta('S', self.META)
        for old, new, why in (('@scenemeta S', '@scenemeta T', 'the first line is @scenemeta S'),
                              ('@layer2 256', '@layer2 255', 'expected @layer2 256'),
                              ('01: ', '02: ', 'expected 01:')):
            with self.subTest(new=new):
                with self.assertRaisesRegex(maps.MapsError, why):
                    maps.assemble_scene_meta(text.replace(old, new, 1), 'S')
        with self.assertRaisesRegex(maps.MapsError, 'needs 256 metatile lines'):
            maps.assemble_scene_meta(text.split('@layer2')[0] + '@layer2 256\n00: 000/0 000/0 000/0 000/0\n', 'S')
        with self.assertRaisesRegex(maps.MapsError, 'a line after layer 2'):
            maps.assemble_scene_meta(text + '@x\n', 'S')

    def test_bg3_refusals(self):
        text = maps.render_bg3('S', self.BG3)
        for old, new, why in (('@bg3map S 2', '@bg3map S 3', 'the first line is @bg3map S 1\\|2'),
                              ('@screen 1', '@screen 2', 'expected @screen 1')):
            with self.subTest(new=new):
                with self.assertRaisesRegex(maps.MapsError, why):
                    maps.assemble_bg3(text.replace(old, new, 1), 'S')
        first_row = text.split('@screen 0\n')[1].split('\n')[0]
        with self.assertRaisesRegex(maps.MapsError, '33 words; a row is 32'):
            maps.assemble_bg3(text.replace(first_row, first_row + ' 000/0', 1), 'S')
        with self.assertRaisesRegex(maps.MapsError, '2 screens are 66 lines'):
            maps.assemble_bg3(text + '000/0\n', 'S')

    def test_scene_palettes(self):
        data = bytes(range(64)) + bytes([0xFF, 0xFF])           # 33 colours: two rows and one, bit 15 in the last
        text = maps.render_scene_pal('S', data)
        self.assertEqual(maps.assemble_scene_pal(text, 'S', len(data)), data)
        self.assertIn('\n02: 31,31,31!\n', text)
        self.assertEqual(maps.colour_text(0x7FFF), '31,31,31')
        self.assertEqual(maps.colour_value('1,2,3', 'x'), 1 | 2 << 5 | 3 << 10)
        for bad in ('32,0,0', '1,2', '1,2,3!!', '1,2,3?', '-1,0,0', '100,0,0'):
            with self.assertRaisesRegex(maps.MapsError, 'bad colour'):
                maps.colour_value(bad, 'x')
        for n in (0, 3):
            with self.assertRaisesRegex(maps.MapsError, 'no whole number of colours'):
                maps.render_scene_pal('S', bytes(n))
        row1 = text.split('\n01: ')[1].split('\n')[0]
        for new_text, size, why in ((text.replace('@scenepal S 33', '@scenepal T 33'), len(data), 'first line is'),
                                    (text, len(data) + 2, 'first line is @scenepal S 34'),
                                    (text, 65, 'first line is'),
                                    (text.replace('01: ', '03: '), len(data), 'expected 01: and 16 colours'),
                                    (text.replace('01: ' + row1, '01: ' + row1 + ' 0,0,0'), len(data),
                                     'expected 01: and 16 colours'),
                                    (text + '03: 0,0,0\n', len(data), '33 colours are 3 rows; there are 4'),
                                    (text.replace('01: 0,', '01: 32,'), len(data), 'bad colour')):
            with self.subTest(why=why):
                with self.assertRaisesRegex(maps.MapsError, why):
                    maps.assemble_scene_pal(new_text, 'S', size)

    def test_only_named_scene_packs(self):
        self.assertEqual(maps.kind_of('via C2SceneRom_PalettePacks[3]; x'), ('scenepal', None))
        self.assertIsNone(maps.kind_of('via C2SceneRom_PalettePacks[2]; x'))
        self.assertEqual(maps.kind_of('via C2SceneRom_Bg3MapPacks[4]; x'), ('scenebg3', 0x1000))
        self.assertIsNone(maps.kind_of('via C2SceneRom_Bg3MapPacks[5]; x'))     # no header names it
def fake_rows(packs, records=4):
    """Survey rows for derive_named: the location records and packs
    ([(table, index)]), the pack k at $E0:k0."""
    rows = [{'start': '$F6:0000', 'size': str(14 * records), 'kind': 'table', 'format': '', 'notes': ''}]
    for k, (table, i) in enumerate(packs):
        rows.append({'start': f'$E0:{k * 16:04X}', 'size': '16', 'kind': 'packed_lz',
                     'format': 'lz11 -> 4096 B', 'notes': f'via {table}[{i}]; repacks'})
    return rows


def fake_rom(recs):
    """A ROM of zeros with the location records [(mapprops, tileset12,
    tileset3)]."""
    rom = bytearray(ed.ROM_SIZE)
    for k, (mp, t12, t3) in enumerate(recs):
        at = 0x360000 + 14 * k
        rom[at + 1], rom[at + 2] = t12, t3
        rom[at + 4:at + 6] = mp.to_bytes(2, 'little')
    return bytes(rom)


class Named(unittest.TestCase):
    """Which packs are maps and metatiles, from the location records that
    name them (a synthetic ROM and survey)."""

    ROWS = fake_rows([('Map_PropsPtrs', 0), ('Map_PropsPtrs', 258), ('LocGfx_Meta12Ptrs', 0),
                      ('LocGfx_Meta12Ptrs', 1), ('LocGfx_Meta3Ptrs', 0), ('LocGfx_Meta3Ptrs', 1)])
    RECS = [(258, 1, 0xFF), (258, 0xFF, 1), (258, 0xFF, 0xFF), (258, 1, 1)]

    def test_records_name_the_packs(self):
        named, problems = maps.derive_named(fake_rom(self.RECS), self.ROWS)
        self.assertEqual(problems, [])
        # MapProps is 16-bit; $FF in Tileset12/Tileset3 names nothing
        self.assertEqual(named, {'$E0:0010', '$E0:0030', '$E0:0050'})

    def test_a_record_naming_no_pack_row(self):
        _, problems = maps.derive_named(fake_rom(self.RECS[:3] + [(7, 0xFF, 0xFF)]), self.ROWS)
        self.assertEqual(problems, ['location record 3 names Map_PropsPtrs[7], which no survey pack row is'])

    def test_manifest_compared_both_ways(self):
        pieces = [{'start': s, 'piece': 'mapprops'} for s in ('$E0:0000', '$E0:0010')] + \
                 [{'start': '$E0:0030', 'piece': 'packed'}, {'start': '$E0:0050', 'piece': 'metatiles'}]
        self.assertEqual(maps.named_problems(fake_rom(self.RECS), self.ROWS, pieces),
                         ['$E0:0030: a location record names it, and the manifest keeps it packed',
                          '$E0:0000: converted in the manifest, and no location record names it'])

    def test_check_compares_the_manifest(self):
        got = maps.check(fake_rom([(10, 0, 0)]))         # Map_PropsPtrs[10], which stays packed, and the rest 0
        self.assertIn('$F0:3C27: a location record names it, and the manifest keeps it packed', got)
        self.assertIn('$F0:0050: converted in the manifest, and no location record names it', got)


class Source(unittest.TestCase):

    def test_manifest_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        pieces = [p for p in ed.read_manifest() if p['piece'] in maps.PIECES]
        self.assertEqual(sum(p['piece'] == 'mapprops' for p in pieces), 197)
        self.assertEqual(sum(p['piece'] == 'metatiles' for p in pieces), 71)
        scene = [p for p in ed.read_manifest() if p['piece'] in ('scenemaps', 'scenemeta', 'scenebg3', 'scenepal')]
        self.assertEqual(sorted(p['piece'] for p in scene).count('scenebg3'), 5)
        self.assertEqual([p['label'] for p in scene if p['piece'] == 'scenepal'],
                         [f'ScenePalPack_{k:03d}' for k in range(3, 11)])
        row = dict(rows[[p for p in scene if p['piece'] == 'scenepal'][0]['start']])
        self.assertEqual([p['piece'] for p in ed.layout([row])], ['scenepal'])
        self.assertEqual([p['piece'] for p in ed.layout([dict(row, format='lz12 -> 33 B: odd')])], ['packed'])
        unnamed = {(t, i) for t, ns in maps.UNNAMED.items() for i in ns}
        via = {p['start']: re.search(r'via (\w+)\[(\d+)\]', rows.get(p['start'], {'notes': ''})['notes']) for p in ed.read_manifest()}
        kept = [p for p in ed.read_manifest() if via[p['start']]
                and (via[p['start']].group(1), int(via[p['start']].group(2))) in unnamed]
        self.assertEqual([p['piece'] for p in kept], ['packed'] * 6)   # no record names them: plain packed pieces
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

    def test_check_reports_each_failure(self):
        import extract_data
        rom = ed.read_rom()
        saved = (extract_data.unpack_piece, maps.assemble_piece, maps.render_piece)
        try:
            extract_data.unpack_piece = lambda r, p: (None, f'{p["label"]}: no stream')
            self.assertIn('ScenePalPack_003: no stream', maps.check(rom))
            extract_data.unpack_piece = saved[0]
            maps.assemble_piece = lambda p, t: b''
            self.assertIn('ScenePalPack_003: does not assemble back', maps.check(rom))
            maps.assemble_piece = saved[1]

            def fail(p, d):
                raise maps.MapsError(f'{p["label"]}: refused')
            maps.render_piece = fail
            self.assertIn('ScenePalPack_003: refused', maps.check(rom))
        finally:
            extract_data.unpack_piece, maps.assemble_piece, maps.render_piece = saved

    def test_scene_packs_are_the_headers(self):
        self.assertEqual(maps.scene_named(ed.read_rom()), maps.SCENE_NAMED)
        saved = maps.SCENE_NAMED
        maps.SCENE_NAMED = dict(saved, C2SceneRom_Bg3MapPacks={0})
        try:
            self.assertTrue(any('the scene headers name' in x for x in maps.check(ed.read_rom())))
        finally:
            maps.SCENE_NAMED = saved
        import battle
        d = battle.defines(ed.ROOT)
        self.assertIn(d['C2Scene_ExtraPalPack'], maps.scene_named(ed.read_rom())['C2SceneRom_PalettePacks'])
        self.assertNotIn(d['C2Scene_ExtraPalPack'], {4, 5, 6, 7, 8, 9, 10})


if __name__ == '__main__':
    unittest.main()
