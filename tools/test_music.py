#!/usr/bin/env python3
"""
test_music.py — Tests for tools/music.py (the music sequences' readable
form) and tools/spcwalk.py (the walk of the driver's score reader that
gives the format).

    python3 tools/test_music.py          (from the repository root)

Without the ROM (and without asar): the format, derived from the matched
driver source, against the table below and the driver's own operand-count
table (every command's length tied to its handler); the walk on synthetic
handlers (a variable length, a jump word that is not two adjacent
operands, an unmodelled instruction, a RET to an unknown address, a half
set pointer, a branch onto an operand byte); a synthetic song and effect
block, rendered and assembled back, and the assembler's structure refusals
(operand counts, a jump onto bytes, reached bytes written as data,
regrouped bytes, a unit kept as bytes, stray labels and words, an
unreached line, data after a command that steps on); a mutation sweep:
every single-token change to the synthetic song either assembles to the
same bytes or is refused; a tampered format cache; the manifest's music
pieces.

With the ROM: every song and effect block disassembles and assembles back
byte-exact (tools/music.py check).
"""

import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_data as ed  # noqa: E402
import music  # noqa: E402
import spcwalk  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
HAVE_ROM = ed.ROM_PATH.exists()

# What the driver's handlers do, as the walk finds it: length, then the
# flows (n next, j<k> a jump word at operand byte k, e end, x elsewhere).
EXPECTED = {
    0xC4: (2, 'n'), 0xC5: (3, 'n'), 0xC6: (2, 'n'), 0xC7: (3, 'n'), 0xC8: (3, 'n'), 0xC9: (4, 'n'),
    0xCA: (1, 'n'), 0xCB: (4, 'n'), 0xCC: (1, 'n'), 0xCD: (3, 'n'), 0xCE: (1, 'n'), 0xCF: (2, 'n'),
    0xD0: (1, 'n'), 0xD1: (1, 'n'), 0xD2: (1, 'n'), 0xD3: (1, 'n'), 0xD4: (1, 'n'), 0xD5: (1, 'n'),
    0xD6: (2, 'n'), 0xD7: (1, 'n'), 0xD8: (1, 'n'), 0xD9: (2, 'n'), 0xDA: (2, 'n'), 0xDB: (2, 'n'),
    0xDC: (2, 'n'), 0xDD: (2, 'n'), 0xDE: (2, 'n'), 0xDF: (2, 'n'), 0xE0: (2, 'n'), 0xE1: (1, 'n'),
    0xE2: (2, 'n'), 0xE3: (1, 'n x'), 0xE4: (1, 'n'), 0xE5: (1, 'n'), 0xE6: (1, 'n'), 0xE7: (1, 'n'),
    0xE8: (2, 'n'), 0xE9: (2, 'e x'), 0xEA: (2, 'e x'), 0xEB: (1, 'e'), 0xEC: (1, 'e'), 0xED: (1, 'e'),
    0xEE: (1, 'e'), 0xEF: (1, 'e'), 0xF0: (2, 'n'), 0xF1: (3, 'n'), 0xF2: (2, 'n'), 0xF3: (3, 'n'),
    0xF4: (2, 'n'), 0xF5: (4, 'n j2'), 0xF6: (3, 'j1'), 0xF7: (3, 'n'), 0xF8: (3, 'n'), 0xF9: (2, 'n'),
    0xFA: (4, 'n j2'), 0xFB: (1, 'n'), 0xFC: (1, 'n'), 0xFD: (2, 'n'), 0xFE: (1, 'e'), 0xFF: (1, 'e'),
}

_FORMAT = None


def real_format_data() -> dict:
    """The format derived from the source (once; seconds)."""
    global _FORMAT
    if _FORMAT is None:
        _FORMAT = music.derive_format(ROOT)
    return _FORMAT


def real_format() -> music.Format:
    return music.Format(json.loads(json.dumps(real_format_data())))


def flows(c: dict) -> str:
    out = (['n'] if c['next'] else []) + ([f'j{c["jump"]}'] if c['jump'] is not None else [])
    return ' '.join(out + (['e'] if c['end'] else []) + (['x'] if c['elsewhere'] else []))


class DriverFormat(unittest.TestCase):

    def test_every_command_from_its_handler(self):
        fmt = real_format()
        self.assertEqual({b: (c['length'], flows(c)) for b, c in fmt.cmds.items()}, EXPECTED)

    def test_lengths_agree_with_the_operand_count_table(self):
        # Spc_RunSeqCommand reads the first operand when the count is
        # nonzero and the handler the rest: every walked length is the
        # source table's count + 1 (the look-ahead skips by the same table)
        src = spcwalk.load_source(ROOT)
        counts = src.tables['Spc_SeqOperandCounts']
        fmt = real_format()
        for b, c in fmt.cmds.items():
            self.assertEqual(c['length'], counts[b - fmt.first_cmd] + 1, f'${b:02X}')

    def test_notes_ties_rests(self):
        fmt = real_format()
        self.assertEqual((fmt.first_tie, fmt.first_rest, fmt.first_cmd, fmt.nd), (0xA8, 0xB6, 0xC4, 14))
        self.assertEqual(fmt.durations, [192, 96, 64, 72, 48, 32, 36, 24, 16, 12, 8, 6, 4, 3])
        self.assertEqual(fmt.layout['num_tracks'], 8)

    def test_names_from_the_handler_table(self):
        fmt = real_format()
        self.assertEqual(fmt.names[0xC4], 'Volume')
        self.assertEqual(fmt.names[0xDC], 'SetTrackSample')
        self.assertEqual(fmt.names[0xF6], 'Jump')
        self.assertEqual(fmt.names[0xEB], 'EndTrack_EB')         # a handler seven commands share
        self.assertEqual(fmt.names[0xE5], 'NullCommand_E5')


# ── The walk on synthetic handlers ──────────────────────────────────────────

DEFINES = """
!Spc_TrackPtr = $02
!Spc_Scratch00 = $00
!Spc_CurTrack = $A6
!Spc_TempA5 = $A5
!Spc_Temp9B = $9B
!Spc_SeqFirstCmd = $FC
!Spc_SeqFirstTie = $A8
!Spc_SeqFirstRest = $B6
!Spc_NumDurations = $0E
"""

READER = """
Spc_TrackStep:
    call Spc_ReadSeqByte
    cmp a,#!Spc_SeqFirstCmd
    bcc .byte
    call Spc_RunSeqCommand
    bra Spc_TrackStep
.byte:
    ret
Spc_RunSeqCommand:
    sbc a,#!Spc_SeqFirstCmd
    mov.b !Spc_TempA5,a
    asl a
    mov y,a
    mov.w a,Spc_SeqCmdTable+1+y
    push a
    mov.w a,Spc_SeqCmdTable+y
    push a
    mov.b y,!Spc_TempA5
    mov.w a,Spc_SeqOperandCounts+y
    bne Spc_ReadSeqByte
    ret
Spc_ReadSeqByte:
    mov.b a,(!Spc_TrackPtr+x)
    mov.b !Spc_TempA5,a
    inc.b !Spc_TrackPtr+x
    bne .done
    inc.b !Spc_TrackPtr+1+x
.done:
    ret
Spc_SeqOne:
    cmp a,#$10
    beq .x+1
.x:
    mov y,#$DD                          ; the BEQ lands on $DD: mov a,y
    ret
Spc_SeqJump:
    mov y,a
    call Spc_ReadSeqByte
    mov a,y
    mov.b y,!Spc_TempA5
    addw.b ya,!Spc_Scratch00
    mov.b !Spc_TrackPtr+x,a
    mov.b !Spc_TrackPtr+1+x,y
    ret
Spc_SeqEnd:
    pop a
    pop a
    ret
Spc_SeqFour:
    ret
Spc_SeqCmdTable:
    dw Spc_SeqOne, Spc_SeqJump, Spc_SeqEnd, Spc_SeqFour
Spc_SeqOperandCounts:
    db 1,2,0,0
Spc_DurationTable:
    db $C0,$60,$40,$48,$30,$20,$24,$18,$10,$0C,$08,$06,$04,$03
"""


def fake(handler_four: str = '    ret') -> spcwalk.Source:
    return spcwalk.Source(READER.replace('Spc_SeqFour:\n    ret', 'Spc_SeqFour:\n' + handler_four), [DEFINES])


class Walk(unittest.TestCase):

    def test_synthetic_reader(self):
        c = spcwalk.derive(fake())['commands']
        self.assertEqual((c[0xFC]['length'], c[0xFC]['next']), (2, True))     # through the operand-byte branch
        self.assertEqual((c[0xFD]['length'], c[0xFD]['jump'], c[0xFD]['next']), (3, 1, False))
        self.assertEqual((c[0xFE]['length'], c[0xFE]['end']), (1, True))
        self.assertEqual((c[0xFF]['length'], c[0xFF]['next']), (1, True))
        self.assertEqual(c[0x05]['length'], 1)

    def test_variable_length_refused(self):
        four = ('    call Spc_ReadSeqByte\n    cmp a,#$10\n    bcc .short\n    call Spc_ReadSeqByte\n'
                '.short:\n    ret')
        with self.assertRaisesRegex(spcwalk.WalkError, r'steps on at \+2 and \+3'):
            spcwalk.derive(fake(four))

    def test_jump_word_not_adjacent_refused(self):
        four = ('    call Spc_ReadSeqByte\n    mov.b !Spc_Temp9B,a\n    call Spc_ReadSeqByte\n'
                '    call Spc_ReadSeqByte\n    mov.b y,!Spc_TempA5\n    mov.b a,!Spc_Temp9B\n'
                '    addw.b ya,!Spc_Scratch00\n    mov.b !Spc_TrackPtr+x,a\n    mov.b !Spc_TrackPtr+1+x,y\n    ret')
        with self.assertRaisesRegex(spcwalk.WalkError, 'not a word of its operands'):
            spcwalk.derive(fake(four))

    def test_unmodelled_instruction_refused(self):
        with self.assertRaisesRegex(spcwalk.WalkError, 'does not model'):
            spcwalk.derive(fake('    sleep\n    ret'))

    def test_ret_to_unknown_refused(self):
        with self.assertRaisesRegex(spcwalk.WalkError, 'RET to'):
            spcwalk.derive(fake('    push a\n    push a\n    ret'))

    def test_half_set_pointer_refused(self):
        with self.assertRaisesRegex(spcwalk.WalkError, 'half set'):
            spcwalk.derive(fake('    mov.b !Spc_TrackPtr+x,a\n    ret'))

    def test_store_that_may_reach_the_pointer_refused(self):
        with self.assertRaisesRegex(spcwalk.WalkError, 'may reach the track pointer'):
            spcwalk.derive(fake('    mov.b x,!Spc_Temp9B\n    mov.b $00+x,a\n    ret'))


# ── A synthetic song and effect block ───────────────────────────────────────

def song_bytes() -> bytes:
    """Two tracks, a loop, a loop exit, a jump and data after it; origin
    $9000 (data offset y has the word $9000 + y)."""
    origin = 0x9000
    data = bytearray([0xC4, 0x64, 0x00, 0xE2, 0x03])          # Volume $64, note 0 192, LoopStart $03
    loop = len(data)
    data += bytes([0xA9, 0xB7, 0xE3])                         # tie 96, rest 96, LoopEnd
    t1 = len(data)
    data += bytes([0xC6, 0x40, 0x31])                         # Pan $40 (track 1), note 3 64
    data += bytes([0xF5, 0x02, (origin + loop) & 0xFF, (origin + loop) >> 8])   # LoopJump $02 ->loop
    data += bytes([0xF6, (origin + t1) & 0xFF, (origin + t1) >> 8])             # Jump ->t1
    data += bytes([0xEB, 0x11, 0x22])                         # nothing reaches these
    notrack = origin + len(data)
    head = bytearray(origin.to_bytes(2, 'little') + notrack.to_bytes(2, 'little'))
    for _ in range(2):
        for p in [origin, origin + t1] + [notrack] * 6:
            head += p.to_bytes(2, 'little')
    body = head + data
    return len(body).to_bytes(2, 'little') + bytes(body)


def effects_bytes() -> bytes:
    table = bytearray(1024)
    track = bytearray([0xDC, 0x05, 0x31, 0xE9, 0x01, 0xEB, 0xFF, 0xFF])  # SetTrackSample, note, SfxTrack1 $01
    a = 0x2F00 + 1024
    table[0:2] = a.to_bytes(2, 'little')
    table[4:6] = (a + 5).to_bytes(2, 'little')
    table[6:8] = (0x0012).to_bytes(2, 'little')                         # high byte 0: no track
    body = table + track
    return len(body).to_bytes(2, 'little') + bytes(body)


class Song(unittest.TestCase):

    def setUp(self):
        self.fmt = real_format()
        self.data = song_bytes()
        self.text = music.render(music.Unit('song', self.data, self.fmt), 'Test')

    def assemble(self, text):
        return music.assemble(text, self.fmt, 'Test')

    def test_round_trip(self):
        self.assertEqual(self.assemble(self.text), self.data)
        for line in ('@tracks A L_2024 L_202C none', '    Volume $64', '    note 0 192', '    tie 96',
                     '    rest 96', '    LoopJump $02 ->L_2029', '    Jump ->L_202C', '@bytes EB 11 22'):
            self.assertIn(line, self.text)

    def refused(self, old, new, why):
        self.assertIn(old, self.text)
        with self.assertRaisesRegex(music.MusicError, why):
            self.assemble(self.text.replace(old, new, 1))

    def test_operand_count_refused(self):
        self.refused('    Volume $64', '    Volume $64 $00', 'takes 1 operand bytes; the line gives 2')
        self.refused('    Pan $40', '    Pan', 'takes 1 operand bytes; the line gives 0')

    def test_jump_operand_place_refused(self):
        self.refused('    LoopJump $02 ->L_2029', '    LoopJump ->L_2029 $02', 'at operand 2')
        self.refused('    Jump ->L_202C', '    Jump $2C $90', 'its jump: ->LABEL')

    def test_jump_onto_bytes_refused(self):
        self.refused('@bytes EB 11 22', 'L_X:\n@bytes EB 11 22', 'on bytes nothing reaches')

    def test_reached_bytes_as_data_refused(self):
        self.refused('    note 0 192\n    LoopStart $03', '@bytes 00 E2 03', 'is reached as a command')

    def test_regrouped_bytes_refused(self):
        # the same bytes, two lines turned into data after the first
        self.refused('    tie 96\n    rest 96\n    LoopEnd', '    tie 96\n@bytes B7 E3', 'is reached as a command')

    def test_raw_refused(self):
        with self.assertRaisesRegex(music.MusicError, 'cannot be kept as bytes'):
            self.assemble('@song\n@raw\n@bytes 00\n')

    def test_stray_label_refused(self):
        self.refused('    Pan $40', '    Pan $40\nL_Stray:', 'not a track entry or a jump target')

    def test_undefined_label_refused(self):
        self.refused('    Jump ->L_202C', '    Jump ->L_Nowhere', 'no label L_Nowhere')

    def test_stray_words_refused(self):
        self.refused('    note 0 192', '    note 0 192 loud', 'note N LENGTH')
        self.refused('    Volume $64', '    Volume 64', r'takes \$XX bytes')
        self.refused('    Volume $64', '    Loudness $64', 'not a command')
        self.refused('@origin $9000', '@origin $9000\n@tempo $10', 'unknown or misplaced')

    def test_length_not_in_the_table_refused(self):
        self.refused('    note 0 192', '    note 0 100', 'not a length')

    def test_unreached_line_refused(self):
        self.refused('@bytes EB 11 22', '    EndTrack_EB\n@bytes 11 22', 'no track reaches this line')

    def test_bytes_after_a_command_that_goes_on_refused(self):
        self.refused('    Pan $40', '    Pan $40\n@bytes 00', 'must follow a command|is reached')

    def test_header_after_tracks_refused(self):
        self.refused('@bytes EB 11 22', '@bytes EB 11 22\n@notrack $1234', 'after the tracks have begun')

    def test_mutation_sweep(self):
        """No other text gives the same bytes: every change of one token
        (deleted, doubled, or swapped with the next on its line) and of one
        line (deleted, doubled, swapped with the next) is refused or gives
        other bytes (a regrouping of the same bytes is never accepted); and
        the changes that are accepted are read back the same way."""
        lines = self.text.split('\n')
        variants = []
        for i, line in enumerate(lines):
            if not line.strip() or line.startswith(';'):
                continue
            variants.append(lines[:i] + lines[i + 1:])
            variants.append(lines[:i + 1] + [line] + lines[i + 1:])
            if i + 1 < len(lines):
                variants.append(lines[:i] + [lines[i + 1], line] + lines[i + 2:])
            toks = line.split()
            indent = line[:len(line) - len(line.lstrip())]
            for k in range(len(toks)):
                for new in (toks[:k] + toks[k + 1:], toks[:k + 1] + [toks[k]] + toks[k + 1:],
                            toks[:k] + toks[k + 1:k + 2] + [toks[k]] + toks[k + 2:]):
                    variants.append(lines[:i] + [indent + ' '.join(new)] + lines[i + 1:])
        accepted = 0
        for v in variants:
            text = '\n'.join(v)
            if text == self.text:
                continue
            try:
                got = self.assemble(text)
            except music.MusicError:
                continue
            accepted += 1
            if canon(text) != canon(self.text):
                self.assertNotEqual(got, self.data, f'another text gave the same bytes:\n{text}')
            again = music.render(music.Unit('song', got, self.fmt), 'Test')
            self.assertEqual(self.assemble(again), got)
        self.assertGreater(len(variants), 100)
        self.assertLess(accepted, len(variants) // 4)


def canon(text: str) -> tuple:
    """A readable file up to the order of its header lines (which mean the
    same in any order)."""
    lines = [ln.split(';', 1)[0].split() for ln in text.split('\n')]
    lines = [ln for ln in lines if ln]
    k = next((i for i, ln in enumerate(lines) if i and (not ln[0].startswith('@') or ln[0] == '@bytes')), len(lines))
    return tuple(map(tuple, lines[:1])), tuple(sorted(map(tuple, lines[1:k]))), tuple(map(tuple, lines[k:]))


class Effects(unittest.TestCase):

    def test_round_trip(self):
        fmt = real_format()
        data = effects_bytes()
        text = music.render(music.Unit('effects', data, fmt), 'Fx')
        self.assertEqual(music.assemble(text, fmt, 'Fx'), data)
        self.assertIn('@effect $00 L_3300 none', text)
        self.assertIn('@effect $01 L_3305 $0012', text)
        self.assertIn('    SfxTrack1 $01', text)
        self.assertIn('@bytes FF', text)
        with self.assertRaisesRegex(music.MusicError, '256 @effect'):
            music.assemble(text.replace('@effect $FF none none\n', ''), fmt, 'Fx')
        with self.assertRaisesRegex(music.MusicError, 'a word is written only'):
            music.assemble(text.replace('@effect $01 L_3305 $0012', '@effect $01 L_3305 $3305'), fmt, 'Fx')

    def test_jump_in_an_effect_refused(self):
        fmt = real_format()
        data = bytearray(effects_bytes())
        data[2 + 1024:2 + 1024 + 3] = bytes([0xF6, 0x00, 0x33])
        with self.assertRaisesRegex(music.MusicError, 'a jump in an effect track'):
            music.render(music.Unit('effects', bytes(data), fmt), 'Fx')


class Cache(unittest.TestCase):

    def test_tampered_format_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for p in [spcwalk.DRIVER] + spcwalk.INCLUDES:
                (root / p).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / p, root / p)
            raw = json.dumps(real_format_data(), sort_keys=True, separators=(',', ':')).encode()
            (root / music.CACHE_DIR).mkdir(parents=True)
            f = root / music.CACHE_DIR / 'format.json'
            f.write_bytes(raw)
            (root / music.CACHE_DIR / 'format.key').write_text(
                f'{music._format_key(root)} {hashlib.sha256(raw).hexdigest()}')
            self.assertEqual(music.load_format(root).cmds[0xC4]['length'], 2)
            f.write_text(f.read_text().replace('"length":2', '"length":3', 1))
            with self.assertRaisesRegex(music.MusicError, 'changed by hand'):
                music.load_format(root)


class Manifest(unittest.TestCase):

    def test_music_pieces(self):
        pieces = ed.read_manifest()
        units = music.unit_pieces(pieces)
        self.assertEqual(len([u for u in units if u.startswith('AudioSong_')]), 83)
        self.assertIn('AudioRom_Block2F00', units)
        self.assertIn('AudioRom_Block2F00Alt', units)
        self.assertEqual([p['param'] for p in units['AudioSong_18']], ['song, part 1 of 2', 'song, part 2 of 2'])
        orphan = next(p for p in pieces if p['start'] == '$CB:F164')
        self.assertEqual(orphan['piece'], 'extracted')            # no table reaches it: not read
        for p in pieces:
            if p['piece'] == 'music':
                self.assertRegex(p['asset'], ed.MUSIC_ASSET)
                self.assertRegex(p['param'], ed.MUSIC_PARAM)

    def test_manifest_edits_refused(self):
        text = ed.MANIFEST.read_text()
        line = next(ln for ln in text.splitlines() if ',music,' in ln)
        for edited in (text.replace(line, line.replace('music/', 'music/../../')),
                       text.replace(line, line.replace(',music,', ',extracted,')),
                       text.replace(line, line.replace('part 1 of', 'part 3 of'))):
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'data_assets.csv'
                path.write_text(edited)
                self.assertTrue(ed.manifest_problems(path))


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class WithRom(unittest.TestCase):

    def test_every_unit_round_trips(self):
        self.assertEqual(music.check(ed.read_rom(), ROOT), [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
