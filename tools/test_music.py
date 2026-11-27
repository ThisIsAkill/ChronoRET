#!/usr/bin/env python3
"""
test_music.py — Tests for tools/music.py (the music sequences' readable
form) and tools/spcwalk.py (the walk of the driver's score reader that
gives the format).

    python3 tools/test_music.py          (from the repository root)

Without the ROM (and without asar): the format, derived from the matched
driver source, against the table below and the driver's own operand-count
table, and a mutation sweep of the driver (every operand read, pointer step
and count deleted or changed alters the format or is refused: every
command's length is tied to its handler); the walk on synthetic
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
from unittest import mock
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

    def test_handler_mutation_sweep(self):
        """Each length comes from the handler code: deleting any one operand
        read (`call Spc_ReadSeqByte`) or pointer step (`inc.b
        !Spc_TrackPtr+x`) in the command handlers, or any one entry of the
        operand-count table, changes what the walk finds or makes it
        refuse."""
        text = (ROOT / spcwalk.DRIVER).read_text()
        includes = [(ROOT / p).read_text() for p in spcwalk.INCLUDES]
        base = spcwalk.derive(spcwalk.Source(text, includes), commands_only=True)['commands']
        lines = text.split('\n')
        first = next(i for i, ln in enumerate(lines) if ln.startswith('Spc_SeqTempo:'))
        targets = [i for i, ln in enumerate(lines) if i > first and ln.strip().split(';')[0].strip() in
                   ('call Spc_ReadSeqByte', 'inc.b !Spc_TrackPtr+x')]
        self.assertGreaterEqual(len(targets), 15)        # 19 in the matched driver
        counts = next(i for i, ln in enumerate(lines) if ln.startswith('Spc_SeqOperandCounts:'))
        mutants = [lines[:i] + lines[i + 1:] for i in targets]
        for k in range(1, 6):                              # each db line: one count changed
            row = lines[counts + k].split(';')[0].split(None, 1)[1].split(',')
            for j in range(len(row)):
                changed = list(row)
                changed[j] = "0" if int(changed[j]) else "1"   # (the step reads it as zero or not)
                mutants.append(lines[:counts + k] + ['    db ' + ','.join(changed)] + lines[counts + k + 1:])
        for m in mutants:
            try:
                got = spcwalk.derive(spcwalk.Source('\n'.join(m), includes), commands_only=True)['commands']
            except spcwalk.WalkError:
                continue
            self.assertNotEqual(got, base, 'a mutated driver gave the same format')

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
!Spc_Temp9C = $9C
!Spc_Temp9D = $9D
!Spc_Temp9E = $9E
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


def four(code: str) -> spcwalk.Source:
    """The synthetic reader with command $FF's handler replaced (its lines
    without the indent)."""
    return fake('\n'.join('    ' + ln if ln and not ln.endswith(':') else ln for ln in code.strip().split('\n')))


class WalkRefusals(unittest.TestCase):
    """Each refusal of the walk, on a synthetic handler that needs it."""

    def refused(self, code, why, src=None):
        with self.assertRaisesRegex(spcwalk.WalkError, why):
            spcwalk.derive(src or four(code))

    def test_note_path_that_reads_refused(self):
        # every byte below !Spc_SeqFirstCmd must take one byte and a wait
        src = spcwalk.Source(READER.replace('.byte:\n    ret', '.byte:\n    call Spc_ReadSeqByte\n    ret'), [DEFINES])
        self.refused(None, r'below !Spc_SeqFirstCmd.*not one byte and a wait', src)

    def test_note_path_that_steps_on_refused(self):
        src = spcwalk.Source(READER.replace('.byte:\n    ret', '.byte:\n    bra Spc_TrackStep'), [DEFINES])
        self.refused(None, 'not one byte and a wait', src)

    def test_two_jump_words_refused(self):
        self.refused("""
call Spc_ReadSeqByte
mov.b !Spc_Temp9B,a
call Spc_ReadSeqByte
mov.b !Spc_Temp9C,a
call Spc_ReadSeqByte
mov.b !Spc_Temp9D,a
bbs.b !Spc_Temp9E.0,.second
movw.b ya,!Spc_Temp9B
addw.b ya,!Spc_Scratch00
mov.b !Spc_TrackPtr+x,a
mov.b !Spc_TrackPtr+1+x,y
ret
.second:
movw.b ya,!Spc_Temp9C
addw.b ya,!Spc_Scratch00
mov.b !Spc_TrackPtr+x,a
mov.b !Spc_TrackPtr+1+x,y
ret""", 'two jump operands')

    def test_reads_past_its_length_refused(self):
        # steps on at +1 one way, reads two bytes and sets the pointer the other
        self.refused("""
bbs.b !Spc_Temp9E.0,.far
ret
.far:
call Spc_ReadSeqByte
call Spc_ReadSeqByte
mov.b a,!Spc_Temp9E
mov.b !Spc_TrackPtr+x,a
mov.b !Spc_TrackPtr+1+x,a
ret""", r'it reads \[1, 3\] bytes, its length is 1')

    def test_read_after_the_pointer_is_set_refused(self):
        self.refused("""
mov.b a,!Spc_Temp9E
mov.b !Spc_TrackPtr+x,a
mov.b !Spc_TrackPtr+1+x,a
call Spc_ReadSeqByte
ret""", 'a read from a pointer the walk has set')

    def test_pointer_decrement_refused(self):
        self.refused('dec.b !Spc_TrackPtr+x\nret', 'a pointer change the walk does not model')

    def test_pointer_high_byte_alone_refused(self):
        self.refused('inc.b !Spc_TrackPtr+1+x\nret', 'high byte moved alone')

    def test_branch_into_an_instruction_it_cannot_split_refused(self):
        self.refused('cmp a,#$10\nbeq .x+2\n.x:\nmov y,#$DD\nret', 'which the walk cannot split')
        self.refused('cmp a,#$10\nbeq .x+1\n.x:\nmov.b !Spc_Temp9B,a\nret', 'which the walk cannot split')
        self.refused('cmp a,#$10\nbeq .x+1\n.x:\nmov y,#$E8\nret', 'not a 1-byte instruction')

    def test_command_table_size_refused(self):
        src = spcwalk.Source(READER.replace('Spc_SeqEnd, Spc_SeqFour', 'Spc_SeqEnd'), [DEFINES])
        self.refused(None, 'not one word per command', src)

    def test_store_into_the_driver_refused(self):
        self.refused('mov.w Spc_SeqOperandCounts,a\nret', 'a store into the driver')

    def test_pop_from_an_empty_stack_refused(self):
        self.refused('pop a\npop a\npop a\npop a\npop a\nret', 'POP from an empty stack')

    def test_indexed_jump_refused(self):
        self.refused('jmp (Spc_SeqCmdTable+x)', 'an indexed jump')

    def test_table_read_past_its_end_refused(self):
        self.refused('mov.w a,Spc_SeqOperandCounts+9\nret', 'past the table')

    def test_direct_page_store_with_unknown_index_wraps(self):
        # a .b store reaches the whole page (it wraps), so even a base above
        # the pointer may reach it; a .w one only base..base+$FF
        self.refused('mov.b x,!Spc_Temp9B\nmov.b $F0+x,a\nret', 'may reach the track pointer')
        c = spcwalk.derive(four('mov.b x,!Spc_Temp9B\nmov.w $0300+x,a\nret'))['commands']
        self.assertEqual(c[0xFF]['length'], 1)

    def test_too_many_states_refused(self):
        # an operand loop that never ends grows the pointer without bound
        self.refused('.loop:\ncall Spc_ReadSeqByte\nbbs.b !Spc_Temp9E.0,.loop\nret', 'more than')

    def test_state_limit_has_a_margin(self):
        # the real walk stays under half the limit (it peaks at 3,022 states,
        # for a note byte)
        w = spcwalk.Walker(spcwalk.load_source(ROOT))
        with mock.patch.object(spcwalk, 'MAX_STATES', spcwalk.MAX_STATES // 2):
            w.run(0x00)
            w.run(0xF5)


class WalkSemantics(unittest.TestCase):
    """The instructions and the join, where a wrong model changes the result."""

    def test_table_ret_reaches_every_entry(self):
        # a RET into a table entry pushed with an unknown index goes to every
        # nonzero entry (here a step on and an end)
        src = spcwalk.Source(READER.replace('Spc_SeqFour:\n    ret', 'Spc_SeqFour:\n'
                                            '    mov.b y,!Spc_Temp9E\n'
                                            '    mov.w a,Spc_Pick+1+y\n    push a\n'
                                            '    mov.w a,Spc_Pick+y\n    push a\n    ret') + """
Spc_Pick:
    dw Spc_PickA, 0, Spc_PickB
Spc_PickA:
    ret
Spc_PickB:
    pop a
    pop a
    ret
""", [DEFINES])
        c = spcwalk.derive(src)['commands'][0xFF]
        self.assertEqual((c['next'], c['end']), (True, True))

    def test_join_keeps_memory_differences(self):
        c = spcwalk.derive(four("""
bbs.b !Spc_Temp9E.0,.one
mov.b !Spc_Temp9B,#$00
bra .join
.one:
mov.b !Spc_Temp9B,#$01
.join:
mov.b a,!Spc_Temp9B
beq .end
ret
.end:
pop a
pop a
ret"""))['commands'][0xFF]
        self.assertEqual((c['next'], c['end']), (True, True))

    def test_dbnz(self):
        c = spcwalk.derive(four('mov y,#$02\n.loop:\ncall Spc_ReadSeqByte\ndbnz y,.loop\nret'))['commands'][0xFF]
        self.assertEqual(c['length'], 3)

    def test_incw_decw(self):
        code = """
mov.b !Spc_Temp9B,#{lo}
mov.b !Spc_Temp9C,#{hi}
{op}.b !Spc_Temp9B
mov.b a,!Spc_Temp9C
beq .end
ret
.end:
pop a
pop a
ret"""
        for lo, hi, op, end in (('$00', '$01', 'decw', True), ('$FF', '$00', 'incw', False),
                                ('$FF', '$FF', 'incw', True)):
            c = spcwalk.derive(four(code.format(lo=lo, hi=hi, op=op)))['commands'][0xFF]
            self.assertEqual((c['end'], c['next']), (end, not end), (lo, hi, op))

    def test_unplaced_store_forgets_the_track_bytes(self):
        # a .w store through an unknown index forgets ('x', base) values too
        c = spcwalk.derive(four("""
mov a,#$00
mov.w $0300+x,a
mov.b x,!Spc_Temp9B
mov.w $0300+x,a
mov.b x,!Spc_CurTrack
mov.w a,$0300+x
beq .end
ret
.end:
pop a
pop a
ret"""))['commands'][0xFF]
        self.assertEqual((c['next'], c['end']), (True, True))


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


def song(data: bytes, entries: list[int], origin: int = 0x9000, notrack: int | None = None) -> bytes:
    """A song of these data bytes, its tracks at these data offsets."""
    notrack = origin + len(data) if notrack is None else notrack
    words = [origin + e if isinstance(e, int) and e >= 0 else e for e in entries]
    words = [w if w is not None else notrack for w in words] + [notrack] * (8 - len(words))
    head = origin.to_bytes(2, 'little') + notrack.to_bytes(2, 'little')
    head += b''.join(w.to_bytes(2, 'little') for w in words) * 2
    body = head + bytes(data)
    return len(body).to_bytes(2, 'little') + body


class MusicRefusals(unittest.TestCase):
    """Each refusal of tools/music.py on a song or file that needs it."""

    def setUp(self):
        self.fmt = real_format()
        self.text = music.render(music.Unit('song', song_bytes(), self.fmt), 'Test')

    def render_refused(self, data, why, kind='song'):
        with self.assertRaisesRegex(music.MusicError, why):
            music.render(music.Unit(kind, data, self.fmt), 'Test')

    def assemble_refused(self, text, why):
        with self.assertRaisesRegex(music.MusicError, why):
            music.assemble(text, self.fmt, 'Test')

    def test_length_word_refused(self):
        data = bytearray(song_bytes())
        data[0] += 1
        self.render_refused(bytes(data), 'the length word')

    def test_command_past_the_data_refused(self):
        self.render_refused(song(bytes([0xC4]), [0]), 'run past the data')

    def test_track_past_the_data_refused(self):
        self.render_refused(song(bytes([0x00, 0x01]), [0]), 'runs past the data')

    def test_overlapping_commands_refused(self):
        # a jump into Volume's operand
        self.render_refused(song(bytes([0xC4, 0xEB, 0xF6, 0x01, 0x90]), [0, 2]), 'reached inside')

    def test_entry_outside_the_data_refused(self):
        self.render_refused(song(bytes([0xEB]), [0x40]), 'outside the data')

    def test_jump_outside_the_data_refused(self):
        self.render_refused(song(bytes([0xF6, 0x00, 0xA0]), [0]), 'a jump to \\$A000, outside the data')

    def test_unreached_bytes_before_a_track_refused(self):
        self.render_refused(song(bytes([0x11, 0xEB]), [1]), 'do not follow a command that stops')

    def test_first_line_must_be_the_kind(self):
        self.assemble_refused(self.text.replace('@song\n', ''), 'first line must be @song or @effects')

    def test_label_at_the_end_refused(self):
        self.assemble_refused(self.text + 'L_End:\n', 'at the end, on nothing')

    def test_bytes_before_the_first_line_refused(self):
        self.assemble_refused(self.text.replace('L_2024:\n', '@bytes 00\nL_2024:\n'),
                              '@bytes must follow a command that does not step on')

    def test_track_on_the_no_track_word_refused(self):
        self.assemble_refused(self.text.replace('@notrack $9015', '@notrack $9000'), 'is the "no track" word')

    def test_effects_out_of_order_refused(self):
        text = music.render(music.Unit('effects', effects_bytes(), self.fmt), 'Fx')
        swapped = text.replace('@effect $00 ', '@effect $XX ').replace('@effect $01 ', '@effect $00 ').replace(
            '@effect $XX ', '@effect $01 ')
        self.assemble_refused(swapped, 'out of order')

    def test_pieces_that_do_not_add_up_refused(self):
        ps = [{'label': 'A', 'offset': 0, 'stop': 10, 'param': 'song, part 1 of 1'}]
        with self.assertRaisesRegex(music.MusicError, 'its pieces'):
            music.assemble_unit('Test', self.text, ps, self.fmt)

    def test_disassembly_that_does_not_round_trip_refused(self):
        data = song_bytes()
        other = music.render(music.Unit('song', song(bytes([0xEB]), [0]), self.fmt), 'Other')
        ps = [{'label': 'A', 'offset': 0, 'stop': len(data), 'param': 'song, part 1 of 1'}]
        with mock.patch.object(music, 'render', return_value=other), \
                self.assertRaisesRegex(music.MusicError, 'does not assemble to the same bytes'):
            music.extract_unit('Test', data, ps, self.fmt)

    def test_check_compares_every_piece(self):
        data = song_bytes()
        ps = [{'label': 'A', 'offset': 0, 'stop': len(data), 'param': 'song, part 1 of 1',
               'piece': 'music', 'asset': 'music/Test.mus'}]
        with mock.patch.object(ed, 'read_manifest', return_value=ps), \
                mock.patch.object(music, 'load_format', return_value=self.fmt):
            self.assertEqual(music.check(data), [])
            with mock.patch.object(music, 'assemble_unit', return_value={'A': b'\0' * len(data)}):
                self.assertEqual(music.check(data), ['A: does not assemble back to its bytes'])


def shift_ranges(d: dict) -> None:
    """Ties, rests and commands one byte up together: only the 12 note
    sets are then wrong."""
    d['first_tie'] += 1
    d['first_rest'] += 1
    d['first_cmd'] += 1
    d['commands'].pop(str(d['first_cmd'] - 1))


class FormatChecks(unittest.TestCase):

    def test_format_key_follows_the_driver(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for p in [spcwalk.DRIVER] + spcwalk.INCLUDES:
                (root / p).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / p, root / p)
            key = music._format_key(root)
            (root / spcwalk.DRIVER).write_text((root / spcwalk.DRIVER).read_text() + '; changed\n')
            self.assertNotEqual(music._format_key(root), key)
            (root / spcwalk.INCLUDES[1]).write_text((root / spcwalk.INCLUDES[1]).read_text() + '; changed\n')
            self.assertNotEqual(music._format_key(root), key)

    def test_format_sanity_refused(self):
        base = real_format_data()
        for change, why in ((lambda d: d['durations'].__setitem__(1, d['durations'][0]), 'distinct lengths'),
                            (lambda d: d.__setitem__('first_rest', d['first_rest'] + 1), 'note, tie and rest'),
                            (lambda d: d['commands'].pop('255'), 'note, tie and rest'),
                            (shift_ranges, 'note, tie and rest')):
            d = json.loads(json.dumps(base))
            change(d)
            with self.assertRaisesRegex(music.MusicError, why):
                music.Format(d)

    def test_only_table_songs_and_effect_blocks_are_units(self):
        import data_survey
        rows = [r for r in data_survey.read_rows() if r['kind'] == 'music_sequence']
        units = [music.unit_of_row(r, ed.row_label(r, data_survey.parse_addr(r['start']))) for r in rows]
        orphan = [u for r, u in zip(rows, units) if r['start'] == '$CB:F164']
        self.assertEqual(orphan, [None])
        self.assertTrue(all(u for r, u in zip(rows, units) if r['start'] != '$CB:F164'))
        self.assertIsNone(music.unit_of_row({'kind': 'table', 'notes': 'song 0x01 (Audio_SongTable entry 1)'}, 'X'))


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
