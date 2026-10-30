#!/usr/bin/env python3
"""
test_sprites.py — Tests for tools/sprites.py (the sprite frame records as
text).

    python3 tools/test_sprites.py       (from the repository root)

Without the ROM: a synthetic image (set pointers into every frame area, the
sprite records that size them, a run no record sizes, two sets sharing an
address, padding after an area's last record) through the runs, the
readable form and back; every refusal of the runs, the readers' record
sizes (the characters' sprite records among them), the pieces and the
assembler; the manifest's sprframes pieces, their generated comments, and
extraction's use of this tool (and its place in the stamp).

With the ROM: every frame-record piece converts and assembles back
byte-exact, the pieces are the runs, and check and extraction report
every problem.
"""

import sys
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import battle  # noqa: E402
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402
import sprites  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists()
D = battle.defines(ed.ROOT)
F = lambda a: a - 0xC00000      # noqa: E731
SIZES = {'RomE4_SprRec': 70, 'RomE4_EnemySprRec': 30}      # 14 and 3 records
PC = D['Pc_NumChars']           # RomE4_SprRec 0-6: the characters' own sets, size 0


def frame(size: int, seed: int) -> bytes:
    words = size * 2 // 5
    out = bytearray()
    for j in range(words):
        out += ((seed * 7 + j) & 0x7FF | (0x4000 if j % 5 == 1 else 0)).to_bytes(2, 'little')
    out += bytes((seed + 3 * k) & 0xFF for k in range(words // 2))
    return bytes(out)


def make_rom():
    """(image, {set: (file offset, record size or None, frames)})."""
    rom = bytearray(0x400000)
    sets = {10: (F(0xDC0000), 40, 3), 11: (F(0xDC0078), 80, 2), 12: (F(0xDD0000), 120, 2),
            13: (F(0xDE0000), None, 2), 14: (F(0xDE0050), 240, 1), 15: (F(0xE1E000), 40, 1),
            16: (F(0xE30000), 40, 2), 17: (F(0xE30050), 80, 1), 18: (F(0xE30050), 80, 1)}
    for i, (ofs, size, n) in sets.items():
        p = ofs + 0xC00000
        rom[F(D['BattleRom_SprFramesPtr']) + 3 * i:F(D['BattleRom_SprFramesPtr']) + 3 * i + 3] = p.to_bytes(3, 'little')
        for k in range(n):
            rec = frame(size or 40, 16 * i + k)
            rom[ofs + k * (size or 40):ofs + k * (size or 40) + len(rec)] = rec
    sizes = {s: c for s, (_, c, _) in sets.items() if c}
    for k in range(PC):                                          # the characters' records
        r = F(D['RomE4_SprRec']) + 5 * k
        rom[r + D['SprRec_Frames']], rom[r + D['SprRec_Size']] = k, 0x10 * (k & 1)   # bit 4 is not the size
    recs = [(11, 1), (12, 2), (14, 3), (15, 0), (16, 0), (17, 1), (10, 0)]  # (set, size bits) in RomE4_SprRec
    for k, (s, c) in enumerate(recs):
        r = F(D['RomE4_SprRec']) + 5 * (PC + k)
        rom[r + D['SprRec_Frames']], rom[r + D['SprRec_Size']] = s, c | 0x10   # bit 4 is not the size
    e = F(D['RomE4_EnemySprRec']) + 10
    rom[e + D['SprRec_Frames']], rom[e + D['SprRec_Size']] = 18, 1
    assert all(sprites.CLASS_BYTES[c] == sizes[s] for s, c in recs)
    rom[sets[14][0] + 239] = 0                                    # the area's last record ends in a zero
    rom[sets[14][0] + 238] = 9
    fb = F(D['BattleRom_FrameBytes'])
    for k, v in enumerate((40, 80, 120, 240, 320)):
        rom[fb + 2 * k:fb + 2 * k + 2] = v.to_bytes(2, 'little')
    init = F(D['RomE4_PtrInit'])
    rom[init + 2:init + 4] = (D['BattleRom_SprFramesPtr'] & 0xFFFF).to_bytes(2, 'little')
    return rom, sets


def runs_of(rom):
    return sprites.derive(bytes(rom), D, SIZES)


class Runs(unittest.TestCase):

    def test_runs(self):
        rom, sets = make_rom()
        runs = runs_of(rom)
        got = [(sprites.addr(r['start']), r['stop'] - r['start'], r['bytes'], r['sets']) for r in runs]
        self.assertEqual(got, [
            ('$DC:0000', 120, 40, [10]), ('$DC:0078', 160, 80, [11]), ('$DC:0118', 0x10000 - 0x118, 0, []),
            ('$DD:0000', 240, 120, [12]), ('$DD:00F0', 0x10000 - 0xF0, 0, []),
            ('$DE:0000', 80, None, [13]), ('$DE:0050', 240, 240, [14]), ('$DE:0140', 0xC000 - 0x140, 0, []),
            ('$E1:E000', 40, 40, [15]), ('$E1:E028', 0x2000 - 0x28, 0, []),
            ('$E3:0000', 80, 40, [16]), ('$E3:0050', 80, 80, [17, 18]), ('$E3:00A0', 0x10000 - 0xA0, 0, [])])
        self.assertEqual([k for _, _, k in sprites.want_rows(runs)][:7],
                         ['frames', 'padding', 'frames', 'padding', 'unsized', 'frames', 'padding'])

    def test_rows_merge_only_when_they_meet(self):
        rom, _ = make_rom()
        t = F(D['BattleRom_SprFramesPtr'])
        for i, a in ((20, 0xDE0140), (19, 0xDEBF10)):                  # unsized, then one record up to $DE:C000
            rom[t + 3 * i:t + 3 * i + 3] = a.to_bytes(3, 'little')
        rom[F(0xDEBFFF)] = 1
        rec = F(D['RomE4_EnemySprRec']) + 20
        rom[rec + D['SprRec_Frames']], rom[rec + D['SprRec_Size']] = 19, 3
        rows = [(sprites.addr(a), sprites.addr(b), k) for a, b, k in sprites.want_rows(runs_of(rom))]
        self.assertIn(('$DE:BF10', '$DE:C000', 'frames'), rows)           # not merged with $E1:E000's run
        self.assertIn(('$E1:E000', '$E1:E028', 'frames'), rows)

    def test_last_run_rounded_up_to_a_record(self):
        rom, sets = make_rom()
        rom[sets[11][0] + 160:sets[11][0] + 161] = b'\x01'              # one byte into a third record
        run = [r for r in runs_of(rom) if r['sets'] == [11]][0]
        self.assertEqual(run['stop'] - run['start'], 240)

    def test_last_run_rounded_past_the_area(self):
        rom, sets = make_rom()
        end = F(0xE20000)                                               # $E1's area ends with its bank
        last = sets[15][0] + (end - sets[15][0]) // 40 * 40             # past the area's last whole record
        rom[last - 1] = 1
        run = [r for r in runs_of(rom) if r['sets'] == [15]][0]
        self.assertEqual(run['stop'], last)
        rom[last] = 1                                                   # rounds up past $E1:FFFF
        with self.assertRaisesRegex(sprites.SpritesError, 'the last run of its area, at \\$E1:E000, rounded up '
                                    "to whole 40-B records, ends at \\$E2:0008, past the area's end \\$E2:0000"):
            runs_of(rom)

    def test_size_bits_only(self):
        rom, _ = make_rom()
        e = F(D['RomE4_EnemySprRec']) + 10
        rom[e + D['SprRec_Size']] = 0x05                                # bits 0-1 = 1 still
        self.assertEqual([r['bytes'] for r in runs_of(rom) if r['sets'] == [17, 18]], [80])

    def test_refusals(self):
        rom, sets = make_rom()
        bad = bytearray(rom)
        t = F(D['BattleRom_SprFramesPtr']) + 3 * 30
        bad[t:t + 3] = (0xDEC000).to_bytes(3, 'little')
        with self.assertRaisesRegex(sprites.SpritesError, 'outside the frame areas'):
            runs_of(bad)
        bad = bytearray(rom)
        bad[t:t + 3] = (0xD00000).to_bytes(3, 'little')
        with self.assertRaisesRegex(sprites.SpritesError, 'outside the frame areas'):
            runs_of(bad)
        bad = bytearray(rom)
        t5 = F(D['BattleRom_SprFramesPtr']) + 3 * 15
        bad[t5:t5 + 3] = (0xE1E028).to_bytes(3, 'little')
        with self.assertRaisesRegex(sprites.SpritesError, 'no set starts the frame area at \\$E1:E000'):
            runs_of(bad)
        bad = bytearray(rom)
        e = F(D['RomE4_EnemySprRec']) + 20
        bad[e + D['SprRec_Frames']], bad[e + D['SprRec_Size']] = 17, 2  # set 17 at 120 B, set 18 at 80
        with self.assertRaisesRegex(sprites.SpritesError, 'given record sizes \\[80, 120\\]'):
            runs_of(bad)
        bad = bytearray(rom)
        r = F(D['RomE4_SprRec']) + 5 * (PC + 4)
        bad[r + D['SprRec_Size']] = 2                                   # set 16: 80 B before set 17 is not 120s
        with self.assertRaisesRegex(sprites.SpritesError, 'not a whole number of 120-B records'):
            runs_of(bad)

    def test_record_tables_from_the_survey(self):
        self.assertEqual(sprites._row_size('$E4:F000') // D['SprRec_Bytes'], 262)
        with self.assertRaisesRegex(sprites.SpritesError, 'no row at \\$E4:F001'):
            sprites._row_size('$E4:F001')

    def test_record_extent(self):
        rom, _ = make_rom()
        r = F(D['RomE4_SprRec']) + 5 * 14                               # record 14: past the extent
        rom[r + D['SprRec_Frames']], rom[r + D['SprRec_Size']] = 13, 0
        self.assertIsNone([x for x in runs_of(rom) if x['sets'] == [13]][0]['bytes'])
        self.assertEqual([x for x in sprites.derive(bytes(rom), D, dict(SIZES, RomE4_SprRec=75))
                          if x['sets'] == [13]][0]['bytes'], 40)


class Form(unittest.TestCase):

    def piece(self):
        rom, sets = make_rom()
        runs = runs_of(rom)
        s, e = F(0xE30000), F(0xE300A0)
        return bytes(rom[s:e]), s, sprites.runs_in(runs, s, e)

    def test_round_trip(self):
        data, s, runs = self.piece()
        text = sprites.render('P', s, data, runs)
        self.assertEqual(sprites.assemble(text, 'P', s, len(data)), data)
        self.assertIn('@set $E3:0050 80 17,18', text)
        self.assertEqual(sprites.frames_of(text), 3)

    def test_words(self):
        for v in (0, 0x7FF, 0x4123, 0x8001, 0xC7FF, 0x3800, 0xFFFF, 0x0800):
            t = sprites.word_text(v)
            self.assertEqual(sprites.word_value(t, 'w'), v, t)
        self.assertEqual(sprites.word_text(0xC000 | 0x1800 | 0x12), '012hv^3')
        for bad in ('800', '12', '0123', '012x', '012^0', '012^8', '012vh', '01a'):
            with self.assertRaisesRegex(sprites.SpritesError, 'bad tile word'):
                sprites.word_value(bad, 'w')

    def test_pairs_signed(self):
        rec = bytes(32) + bytes([0x80, 0x7F, 0xFF, 0x00, 1, 2, 3, 4])
        lines = sprites.render_frame(0, rec)
        self.assertEqual(lines[-1], '  @ -128,127 -1,0 1,2 3,4')

    def test_edit_assembles(self):
        data, s, runs = self.piece()
        text = sprites.render('P', s, data, runs)
        lines = text.splitlines()
        k = lines.index('frame 1') + 1
        words = lines[k].split()
        words[0] = '7FFh'
        lines[k] = '  ' + ' '.join(words)
        lines[k + 1] = '  @ -5,6 ' + ' '.join(lines[k + 1].split()[2:])     # the first pair
        got = sprites.assemble('\n'.join(lines), 'P', s, len(data))
        want = bytearray(data)
        want[40:42] = (0x47FF).to_bytes(2, 'little')
        want[40 + 32:40 + 34] = bytes([0xFB, 6])
        self.assertEqual(got, bytes(want))

    def test_assembler_refusals(self):
        data, s, runs = self.piece()
        text = sprites.render('P', s, data, runs)
        lines = text.splitlines()

        def refused(new_lines, why, size=len(data)):
            with self.assertRaisesRegex(sprites.SpritesError, why):
                sprites.assemble('\n'.join(new_lines), 'P', s, size)

        head = next(i for i, x in enumerate(lines) if x.startswith('@sprframes'))
        refused(lines[:head] + ['@sprframes Q $E3:0000 160'] + lines[head + 1:], 'the first line must be')
        refused(lines, 'the first line must be', size=200)
        st = [i for i, x in enumerate(lines) if x.startswith('@set')]
        refused([x.replace('@set $E3:0050', '@set $E3:0058') for x in lines], 'the run starts at \\$E3:0058')
        for v in (0, 20, 60, 160, 200, 320, 480):                       # no reader's record size
            refused([x.replace('@set $E3:0000 40', f'@set $E3:0000 {v}') for x in lines], 'BYTES one of')
        refused([x.replace('@set $E3:0000 40 16', '@set $E3:0000 40') for x in lines], 'expected @set')
        refused([x.replace('@set $E3:0000 40 16', '@set $E3:0000 40 16,') for x in lines], 'expected @set')
        refused([x.replace('frame 1', 'frame 2') for x in lines], 'expected "frame 1"')
        refused([x.replace('@set $E3:0050', '@set E3:0050') for x in lines], 'bad address')
        refused(lines[:st[0]] + lines[st[0] + 1:], 'after an @set')
        refused(lines[:st[1] + 1] + lines[st[1] + 1:st[1] + 1] + lines[st[0]:st[1]] + lines[st[1]:],
                'the run starts at|the run before has no frame|expected')
        f1 = lines.index('frame 1')
        short = list(lines)
        short[f1 + 1] = ' '.join(short[f1 + 1].split()[:15])
        refused(short, 'lines of 16 tile words')
        nopos = lines[:f1 + 2] + lines[f1 + 3:]
        refused(nopos, 'lines of 16 tile words, then @')
        few = list(lines)
        few[f1 + 2] = few[f1 + 2].rsplit(' ', 1)[0]
        refused(few, '3 pairs; a 40-B frame has 4')
        far = list(lines)
        far[f1 + 2] = far[f1 + 2].replace('@ ', '@ 128,0 ', 1).rsplit(' ', 1)[0]
        refused(far, 'bad position pair')
        tok = list(lines)
        tok[f1 + 1] = tok[f1 + 1].replace(tok[f1 + 1].split()[0], 'zzz', 1)
        refused(tok, 'bad tile word')
        refused(lines[:head] + ['@sprframes P $E3:0000 200'] + lines[head + 1:], 'the runs make 160 B, the piece '
                'is 200 B', size=200)
        refused(lines[:st[1] + 1], 'the last run has no frame')
        empty = lines[:st[1]] + [lines[st[1]]] + [lines[st[1]].replace('$E3:0050', '$E3:0078')] + lines[st[1] + 1:]
        refused(empty, 'the run before has no frame')

    def test_piece_text(self):
        rom, _ = make_rom()
        p = {'label': 'P', 'offset': F(0xE30000), 'stop': F(0xE300A0)}
        text = sprites.piece_text(p, bytes(rom), runs_of(rom))
        self.assertEqual(sprites.assemble(text, 'P', p['offset'], 160), bytes(rom[p['offset']:p['stop']]))
        saved = sprites.assemble
        sprites.assemble = lambda *a, **k: bytes(160)          # an assembler that loses the bytes
        try:
            with self.assertRaisesRegex(sprites.SpritesError, 'P: does not assemble back'):
                sprites.piece_text(p, bytes(rom), runs_of(rom))
        finally:
            sprites.assemble = saved

    def test_render_refusals(self):
        data, s, runs = self.piece()
        with self.assertRaisesRegex(sprites.SpritesError, 'do not tile the piece'):
            sprites.render('P', s, data, runs[1:])
        with self.assertRaisesRegex(sprites.SpritesError, 'the runs end at'):
            sprites.render('P', s, data + bytes(40), runs)
        with self.assertRaisesRegex(sprites.SpritesError, 'do not tile the piece'):
            sprites.render('P', s, data, [dict(runs[0], bytes=None)] + runs[1:])
        with self.assertRaisesRegex(sprites.SpritesError, 'do not tile the piece at \\$E3:0050'):
            sprites.render('P', s, data[:120], runs)                       # the last run ends past the piece


class Locks(unittest.TestCase):

    def test_reader_sizes(self):
        rom, _ = make_rom()
        self.assertEqual(sprites.size_problems(bytes(rom), D), [])
        self.assertTrue(sprites.size_problems(bytes(rom), dict(D, Frame8_Bytes=0x48)))
        self.assertTrue(sprites.size_problems(bytes(rom), dict(D, LargeObj_LayoutOfs=0xB0)))
        self.assertTrue(sprites.size_problems(bytes(rom), dict(D, SprBuf_Tiles=0x50)))
        self.assertTrue(sprites.size_problems(bytes(rom), dict(D, Menu_SprDefSizeMask=7)))
        self.assertTrue(sprites.size_problems(bytes(rom), dict(D, MenuRom_E4FramePtrs=D['RomE4_PtrInit'] + 4)))
        bad = bytearray(rom)
        bad[F(D['BattleRom_FrameBytes']) + 6] = 0xF8
        self.assertTrue(any('BattleRom_FrameBytes' in x for x in sprites.size_problems(bytes(bad), D)))
        bad = bytearray(rom)
        bad[F(D['RomE4_PtrInit']) + 2] ^= 1
        self.assertTrue(any('Field_E4Ptr1' in x for x in sprites.size_problems(bytes(bad), D)))
        for bank in (D['AnimRom'] + 0x10000, D['AnimRom'] - 0x10000):  # the table is not in AnimRom's bank
            self.assertTrue(any('Field_E4Ptr1' in x for x in sprites.size_problems(bytes(rom), dict(D, AnimRom=bank))))

    def test_character_records(self):
        rom, _ = make_rom()
        base = F(D['RomE4_SprRec'])
        for k in range(PC):
            for field, value in (('SprRec_Frames', (k + 1) % PC), ('SprRec_Size', 1), ('SprRec_Size', 0x13)):
                bad = bytearray(rom)
                bad[base + 5 * k + D[field]] = value
                got = sprites.size_problems(bytes(bad), D)
                self.assertEqual(len(got), 1, (k, field))
                self.assertRegex(got[0], f'RomE4_SprRec record {k} is set .*: Battle_InitScene takes character {k}')
        ok = bytearray(rom)
        ok[base + 5 * 3 + D['SprRec_Size']] = 0x1C                      # bits 2-4 are not the size
        self.assertEqual(sprites.size_problems(bytes(ok), D), [])
        self.assertEqual(sprites.size_problems(bytes(rom), dict(D, Pc_NumChars=PC + 1))[0][:22],
                         f'RomE4_SprRec record {PC} ')

    def test_menu_tables_from_the_source(self):
        rom, _ = make_rom()
        with tempfile.TemporaryDirectory() as tmp:
            c2 = Path(tmp) / 'asm' / 'bankC2'
            c2.mkdir(parents=True)
            src = (ed.ROOT / 'asm' / 'bankC2' / 'bankC2.asm').read_text()
            self.assertIn('Menu_SprTileCounts:\n    db 1, 2, 3, 6\n', src)
            (c2 / 'bankC2.asm').write_text(src)
            self.assertEqual(sprites.size_problems(bytes(rom), D, Path(tmp)), [])
            (c2 / 'bankC2.asm').write_text(src.replace('Menu_SprTileCounts:\n    db 1, 2, 3, 6\n',
                                                       'Menu_SprTileCounts:\n    db 1, 2, 3, 5\n'))
            self.assertTrue(any('Menu_SprLoad' in x for x in sprites.size_problems(bytes(rom), D, Path(tmp))))
            (c2 / 'bankC2.asm').write_text(src.replace('Menu_SprFrameBytes:', 'Menu_SprFrameBytesX:'))
            with self.assertRaisesRegex(sprites.SpritesError, 'no Menu_SprFrameBytes'):
                sprites.size_problems(bytes(rom), D, Path(tmp))

    def test_pieces_are_the_runs(self):
        rom, _ = make_rom()
        runs = runs_of(rom)
        kind = {'frames': 'sprframes', 'unsized': 'extracted', 'padding': 'fill'}
        pieces = [{'offset': s, 'stop': e, 'piece': kind[k]} for s, e, k in sprites.want_rows(runs)]
        other = [{'offset': F(0xDEC000), 'stop': F(0xDEC100), 'piece': 'text'}]
        self.assertEqual(sprites.layout_problems(runs, pieces + other), [])
        for k in range(len(pieces)):
            for wrong in ('extracted', 'fill', 'sprframes'):
                if wrong != pieces[k]['piece']:
                    bad = pieces[:k] + [dict(pieces[k], piece=wrong)] + pieces[k + 1:]
                    self.assertTrue(sprites.layout_problems(runs, bad), (k, wrong))
        cut = pieces[:1] + [dict(pieces[1], offset=pieces[1]['offset'] + 40)]
        cut[0] = dict(cut[0], stop=cut[0]['stop'] + 40)
        self.assertTrue(sprites.layout_problems(runs, cut + pieces[2:]))
        self.assertTrue(sprites.layout_problems(runs, pieces[:-1]))


class Manifest(unittest.TestCase):

    def test_pieces(self):
        rows = {r['start']: r for r in data_survey.read_rows()}
        pieces = [p for p in ed.read_manifest() if p['piece'] == 'sprframes']
        self.assertEqual(len(pieces), 9)
        for p in pieces:
            self.assertTrue(sprites.is_piece_row(rows[p['start']]))
            self.assertEqual(p['asset'], f'sprites/{p["label"]}.spr')
            self.assertEqual(p['param'], '')
            self.assertIn(f'../../build/sprites/{p["label"]}.bin', ed.allowed_incbins(pieces))
            self.assertEqual(ed.placeholder_files(pieces)[ed.SPRITES_OUT / f'{p["label"]}.bin'], int(p['size']))
        others = [r for r in rows.values() if r['kind'] == 'sprite_layout' and not sprites.is_piece_row(r)]
        self.assertEqual(len(others), 4)
        for r in others:
            self.assertEqual([p['piece'] for p in ed.read_manifest() if p['start'] == r['start']], ['extracted'])

    def test_survey_rows_choose_the_piece(self):
        row = {'start': '$DC:0000', 'end': '$DC:0027', 'size': '40', 'bank': '$DC', 'kind': 'sprite_layout',
               'format': sprites.FORMAT + ': x', 'readers': '', 'confidence': 'confirmed', 'notes': 'runs'}
        self.assertEqual([(p['piece'], p['asset']) for p in ed.layout([row])],
                         [('sprframes', 'sprites/SprLayout_DC0000.spr')])
        self.assertEqual([p['piece'] for p in ed.layout([dict(row, format='per sprite set')])], ['extracted'])
        self.assertEqual([p['piece'] for p in ed.layout([dict(row, kind='table')])], ['extracted'])

    def test_comment_says_the_extent_is_inferred(self):
        row = {'confidence': 'confirmed', 'notes': '6 runs; extent inferred: a reader bounds no frame count'}
        self.assertEqual(ed.confidence({'piece': 'sprframes'}, row), 'confirmed (extent inferred)')
        self.assertEqual(ed.confidence({'piece': 'extracted'}, row), 'confirmed')
        self.assertEqual(ed.confidence({'piece': 'sprframes'}, dict(row, notes='runs')), 'confirmed')
        pieces = ed.layout()
        for p in [x for x in pieces if x['piece'] == 'sprframes']:
            for bank in (ed.render_bank(p['offset'] >> 16 | 0xC0, [x for x in pieces if x['offset'] >> 16 ==
                                                                   p['offset'] >> 16], None),
                         (ed.ROOT / 'asm' / 'data' / f'bank{p["start"][1:3]}.asm').read_text()):
                self.assertIn(f'; {p["start"]}-{p["end"]} ({int(p["size"]):,} B), sprite_layout, '
                              f'{p["row"]["confidence"]} (extent inferred): ', bank)
                self.assertIn(f'{p["label"]}:\n    incbin "../../build/sprites/{p["label"]}.bin"', bank)

    def test_extract_writes_the_sprites(self):
        stubs = {n: mock.patch.object(ed, n, return_value=[]) for n in
                 ('extract_text', 'extract_records', 'extract_events', 'extract_battle', 'extract_scripts')}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(ed, 'read_manifest', return_value=[]), \
                mock.patch.object(ed, 'read_rom', return_value=b''), \
                mock.patch.object(ed, 'extract_sprites', return_value=['the sprites failed']) as got:
            for st in stubs.values():
                st.start()
            try:
                with self.assertRaisesRegex(ed.DataError, 'the sprites failed'):
                    ed.extract(Path(tmp))
                self.assertEqual(got.call_count, 1)
                got.return_value = []
                (Path(tmp) / ed.ASSETS).mkdir(parents=True)
                piece = [p for p in ed.layout() if p['piece'] == 'sprframes'][:1]
                with mock.patch.object(ed, 'read_manifest', return_value=piece):
                    self.assertEqual(ed.extract(Path(tmp)), Path(tmp) / ed.ASSETS)   # extract_sprites writes it
                self.assertEqual(got.call_args.args[2], piece)
            finally:
                for st in stubs.values():
                    st.stop()

    def test_stamp_follows_this_tool(self):
        with tempfile.TemporaryDirectory() as tmp:
            tools = Path(tmp) / 'tools'
            shutil.copytree(ed.ROOT / 'tools', tools, ignore=shutil.ignore_patterns('__pycache__'))
            with mock.patch.object(ed, 'ROOT', Path(tmp)):
                key = ed._stamp_key('0' * 64)
                (tools / 'sprites.py').write_text((tools / 'sprites.py').read_text() + '# changed\n')
                self.assertNotEqual(ed._stamp_key('0' * 64), key)

    def test_manifest_form(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'data_assets.csv'
            text = ed.MANIFEST.read_text()
            path.write_text(text)
            self.assertEqual(ed.manifest_problems(path), [])
            p = [x for x in ed.read_manifest() if x['piece'] == 'sprframes'][0]
            line = f'{p["label"]},{p["start"]},{p["end"]},{p["size"]},sprframes,sprites/{p["label"]}.spr,'
            self.assertIn(line + '\n', text)
            for bad in (line + 'x', line.replace('.spr,', '.bin,'), line.replace('sprites/', 'gfx/')):
                path.write_text(text.replace(line + '\n', bad + '\n'))
                self.assertTrue(any('sprframes piece' in x for x in ed.manifest_problems(path)), bad)


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_round_trips(self):
        self.assertEqual(sprites.check(ed.read_rom()), [])

    def test_check_sees_a_piece_that_does_not_assemble_back(self):
        saved = sprites.assemble
        sprites.assemble = lambda text, label, start, size, name='': bytes(size)
        try:
            got = sprites.check(ed.read_rom())
        finally:
            sprites.assemble = saved
        self.assertEqual(len(got), 9)
        self.assertTrue(all('does not assemble back' in x for x in got))

    def test_extraction(self):
        rom = ed.read_rom()
        pieces = ed.read_manifest()
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(ed.extract_sprites(rom, Path(tmp), pieces), [])
            got = sorted(x.name for x in (Path(tmp) / 'sprites').iterdir())
            self.assertEqual(got, sorted(f'{p["label"]}.spr' for p in pieces if p['piece'] == 'sprframes'))
        k = next(i for i, p in enumerate(pieces) if p['piece'] == 'sprframes')
        bad = pieces[:k] + [dict(pieces[k], stop=pieces[k]['stop'] - 40)] + pieces[k + 1:]
        with tempfile.TemporaryDirectory() as tmp:
            self.assertTrue(any('not the runs' in x for x in ed.extract_sprites(rom, Path(tmp), bad)))
            self.assertFalse((Path(tmp) / 'sprites').exists())
        def fail(*a, **k):
            raise sprites.SpritesError('no runs')
        for name, stub, why in (('size_problems', lambda *a, **k: ['a reader\'s size'], 'a reader\'s size'),
                                ('derive', fail, 'sprites: no runs')):
            saved = getattr(sprites, name)
            setattr(sprites, name, stub)
            try:
                with tempfile.TemporaryDirectory() as tmp:
                    self.assertIn(why, ed.extract_sprites(rom, Path(tmp), pieces))
                    self.assertFalse((Path(tmp) / 'sprites').exists())
            finally:
                setattr(sprites, name, saved)

    def test_check_reports_the_sizes_and_the_layout(self):
        rom = ed.read_rom()
        for name in ('size_problems', 'layout_problems'):
            with mock.patch.object(sprites, name, return_value=[f'{name} found one']):
                self.assertEqual(sprites.check(rom), [f'{name} found one'])

    def test_extraction_reports_a_piece_that_fails(self):
        rom = ed.read_rom()
        pieces = ed.read_manifest()
        bad = next(p['label'] for p in pieces if p['piece'] == 'sprframes')
        real = sprites.piece_text

        def piece_text(p, rom_, runs):
            if p['label'] == bad:
                raise sprites.SpritesError(f'{bad}: broken')
            return real(p, rom_, runs)
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(sprites, 'piece_text', piece_text):
            self.assertEqual(ed.extract_sprites(rom, Path(tmp), pieces), [f'{bad}: broken'])
            self.assertFalse((Path(tmp) / 'sprites' / f'{bad}.spr').exists())
            self.assertEqual(len(list((Path(tmp) / 'sprites').iterdir())), 8)

    def test_check_sees_a_wrong_size(self):
        saved = sprites.CLASS_BYTES
        sprites.CLASS_BYTES = (40, 80, 120, 200)
        try:
            self.assertTrue(sprites.check(ed.read_rom()))
        finally:
            sprites.CLASS_BYTES = saved

    def test_check_sees_a_wrong_area(self):
        saved = sprites.AREAS
        sprites.AREAS = {**saved, 0xDE: (0x0000, 0xC100)}
        try:
            self.assertTrue(sprites.check(ed.read_rom()))
        finally:
            sprites.AREAS = saved


if __name__ == '__main__':
    unittest.main()
