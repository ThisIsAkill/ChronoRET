#!/usr/bin/env python3
"""
test_battle.py — Tests for tools/battle.py (the battle scripts' readable
form) and the absint change it needs (16-bit PHA/PLA byte by byte).

    python3 tools/test_battle.py          (from the repository root)

Without the ROM: the opcode, test and action names come from the source's
tables; the action unit's disassembler and assembler on a synthetic unit
(a script table, the subscript table, a header with threads, a call, a
wait, a counted opcode, data) with a stub interpreter, and the structure
refusals; the behaviour scripts' reader model and assembler on a synthetic
table and scripts (one and two tests, ChooseByChance, data after a stop
code, a script kept as bytes) and their refusals; a tampered trace file;
the manifest's battle pieces.

With the ROM and asar: both units disassemble and assemble back byte-exact,
checked against the readers.
"""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import absint  # noqa: E402
import battle  # noqa: E402
import extract_data as ed  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists() and shutil.which('asar') is not None


class Absint(unittest.TestCase):

    def test_pha_pla_keep_a_known_high_byte(self):
        # REP #$20; PHA; SEP #$20; LDA $0010 (unknown); REP #$20; PLA; RTS
        code = bytes([0xC2, 0x20, 0x48, 0xE2, 0x20, 0xAD, 0x10, 0x00, 0xC2, 0x20, 0x68, 0x60])
        image = bytearray(0x400000)
        image[0x8000:0x8000 + len(code)] = code
        mask = bytearray(0x400000)
        mask[0x8000:0x8000 + len(code)] = b'\x01' * len(code)
        m = absint.Machine(bytes(image), mask)
        s = absint.State()
        s.pc, s.a, s.b, s.x, s.y, s.d, s.db = 0xC08000, None, 0x12, 0, 0, 0, 0x7E
        s.m, s.xf = True, False
        s.c = s.z = s.n = s.v = None
        s.sp, s.spt, s.mem, s.memt = [], [], {}, {}
        s.at = s.xt = s.yt = s.ft = absint.E
        s.depth = 0
        (end, how), = m.run(s, {})
        self.assertEqual((end.a, end.b, how), (None, 0x12, 'rts'))


# ── The action unit, with a stub interpreter ─────────────────────────────

CD, CE = 0xCD, 0xCE


class Stub:
    """Opcodes: $00 ends the thread (stays), $02 n (next 2), $22 n v (waits,
    then next 3), $1E n (calls subscript n: the table at $CE:0000, back at
    +2), $1F (returns: the pointer from RAM), $80 c ... (next (c & $0F) + 1,
    counted from its own byte)."""

    def __init__(self):
        self.count = 0xDB
        self.names = [f'Op{op:02X}_Stub' for op in range(self.count)]

    def run(self, known, ptr, kind):
        op = known[ptr]
        if op == 0x00:
            return {'reads': [], 'control': [], 'outs': [('pos', 0, False, (), 1, None, None)], 'opaque': []}
        if op == 0x02:
            return {'reads': [1], 'control': [], 'outs': [('pos', 2, False, (), 1, None, None)], 'opaque': []}
        if op == 0x22:
            return {'reads': [1, 2], 'control': [1, 2], 'opaque': [],
                    'outs': [('pos', 0, False, (), 1, None, None), ('pos', 3, False, (), 1, None, None)]}
        if op == 0x1E:
            n = known[ptr + 1]
            t = CE << 16 | known[0xCE0000 + 2 * n] | known[0xCE0001 + 2 * n] << 8
            return {'reads': [1], 'control': [], 'opaque': [],
                    'outs': [('pos', t - ptr, True, (1,), 1, 2, t)]}
        if op == 0x1F:
            return {'reads': [], 'control': [], 'outs': [('unknown', 1, False)], 'opaque': []}
        if op == 0x80:
            n = (known[ptr + 1] & 0x0F) + 1
            return {'reads': list(range(1, n)), 'control': [1], 'opaque': [],
                    'outs': [('pos', n, True, (1,), 1, None, None)]}
        return {'reads': [], 'control': [], 'outs': [('bad', 'not in the stub')], 'opaque': []}


def action_pieces() -> list[battle.Piece]:
    # the script region at $CD:1000: a header at $1000 (threads 0 and 8 of
    # the first group: mask $8080, none in the second), thread 0 at $1008,
    # thread 8 at $1012; a subscript at $CE:0400 (bank $CE, as the call
    # takes it)
    region = bytearray(0x20)
    region[0:8] = bytes([0x80, 0x80, 0x00, 0x00, 0x08, 0x10, 0x12, 0x10])
    region[8:0x12] = bytes([0x02, 0x05, 0x22, 0x01, 0x02, 0x1E, 0x00, 0x80, 0x02, 0x00])
    region[0x12:0x15] = bytes([0x02, 0x07, 0x00])        # thread 8: next, then end
    region[0x15:0x1A] = bytes([0x11, 0x22, 0x33, 0x44, 0x55])    # data, after the $00
    region[0x1A:0x20] = bytes([0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    sub_region = bytes([0x02, 0x09, 0x1F, 0xAA, 0xBB, 0x00])     # $CE:0400: a subscript, data, a stray $00
    table = bytes([0x00, 0x10, 0xFF, 0xFF, 0x00, 0x30])          # $1000, none, $3000 (no script)
    subs = bytes([0x00, 0x04, 0xFF, 0xFF])
    return [battle.Piece('Tab', 'table', 0xCD5000, table), battle.Piece('Subs', 'subscripts', 0xCE0000, subs),
            battle.Piece('Reg', 'scripts', 0xCD1000, bytes(region)),
            battle.Piece('SubReg', 'scripts', 0xCE0400, sub_region)]


BANKS = {'Tab': CD, 'Subs': CE}


def action_text():
    ps = action_pieces()
    stub = Stub()
    d = battle.disassemble_actions(stub, ps, BANKS)
    return battle.render_actions(d, ps, stub.names, BANKS), ps, stub


def assemble_text(text, stub=None):
    ps = action_pieces()
    stub = stub or Stub()
    return battle.assemble_actions(text, {p.label: (p.role, p.start, len(p.data)) for p in ps}, stub.names,
                                   BANKS, stub, count=stub.count)


class Actions(unittest.TestCase):

    def test_round_trip(self):
        text, ps, stub = action_text()
        out = assemble_text(text)
        for p in ps:
            self.assertEqual(out[p.label], p.data, p.label)
        self.assertIn('@threads $8080 $0000 L_CD1008 L_CD1012', text)
        self.assertIn('@entry 2 $3000', text)                   # no script there: its word
        self.assertIn('@entry 1 none', text)
        self.assertIn('    Op80_Stub $02 $00', text)            # counted from its own byte
        self.assertIn('@bytes 11 22 33 44 55', text)            # after the end: data
        self.assertIn('L_CE0400:', text)                        # the subscript, from the table

    def refused(self, old, new, why):
        text, _, _ = action_text()
        self.assertIn(old, text)
        with self.assertRaisesRegex(battle.BattleError, why):
            assemble_text(text.replace(old, new, 1))

    def test_entry_to_code_refused(self):
        self.refused('@entry 0 S_CD1000', '@entry 0 L_CD1008', 'not a script header')

    def test_header_word_refused(self):
        self.refused('@entry 0 S_CD1000', '@entry 0 $1000', 'is a script line')

    def test_thread_count_refused(self):
        self.refused('@threads $8080 $0000', '@threads $8088 $0000', 'set 3 threads')

    def test_thread_into_bytes_refused(self):
        text, _, _ = action_text()
        text = text.replace('@bytes 11 22 33 44 55', 'L_X:\n@bytes 11 22 33 44 55').replace(
            'L_CD1008 L_CD1012', 'L_CD1008 L_X')
        with self.assertRaisesRegex(battle.BattleError, 'not an opcode line'):
            assemble_text(text)

    def test_bytes_after_an_opcode_that_goes_on_refused(self):
        self.refused('    Op02_Stub $07\n    Op00_Stub', '    Op02_Stub $07\n@bytes 00', 'is reached')

    def test_regrouped_operands_refused(self):
        self.refused('    Op22_Stub $01 $02\n    Op1E_Stub $00',
                     '    Op22_Stub $01\n    Op02_Stub $1E $00', 'takes 3 bytes')

    def test_halt_must_not_be_an_opcode(self):
        self.refused('    Op00_Stub\n@bytes 11', '    Halt $00\n@bytes 11', 'not an opcode')

    def test_size_kept(self):
        self.refused('@bytes 11 22 33 44 55', '@bytes 11 22 33 44', 'is not 32 bytes')

    def test_trace_file_tampered_refused(self):
        interp = battle.ActInterp.__new__(battle.ActInterp)
        interp.code_key = 'test'
        interp.cache = {2: {((False, 1),): {(5,): {'reads': [1], 'control': [], 'opaque': [],
                                                     'outs': [('pos', 2, False, (), 1, None, None)]}}}}
        interp.dirty = True
        with tempfile.TemporaryDirectory() as tmp:
            interp.save(Path(tmp))
            got = battle.ActInterp.__new__(battle.ActInterp)
            got.code_key = 'test'
            got.cache, got.dirty = {}, False
            got.load(Path(tmp))
            self.assertEqual(got.cache, interp.cache)
            f = Path(tmp) / battle.CACHE_DIR / 'traces.json'
            f.write_text(f.read_text().replace('[5]', '[6]'))
            with self.assertRaisesRegex(battle.BattleError, 'changed by hand'):
                got.load(Path(tmp))


# ── The behaviour scripts, with a stub format ─────────────────────────────

def stub_format() -> battle.AiFormat:
    fmt = battle.AiFormat.__new__(battle.AiFormat)
    fmt.block_end, fmt.part_end, fmt.restart = 0xFE, 0xFF, 4
    fmt.fixed = [0xCC8D08, 0xCC8D1E]
    fmt.tests = [f'Test{c:02X}' for c in range(0x29)]
    fmt.acts = [f'Act{c:02X}' for c in range(0x17)]
    fmt.lengths = [4, 4, 6, 0, 1, 255, 4, 4, 4, 2, 3, 5, 4, 3, 2, 2, 4, 10, 16, 3, 10, 16, 12]
    return fmt


BASE = 0xCC8B08
ONE = bytes([0x00, 0, 0, 0, 0xFE, 0x01, 1, 2, 3, 0xFE, 0xFF,          # main: test 00; act 01
             0x00, 0, 0, 0, 0xFE, 0x00, 0, 6, 0, 0xFE, 0xFF])          # reaction: test 00; act 00
TWO = bytes([0x17, 0x32, 0, 0, 0x03, 1, 2, 0, 0xFE,                   # two tests
             0x04, 0x01, 1, 2, 3, 0x09, 7, 0xFE,                      # ChooseByChance, two actions
             0x05, 9, 0, 0, 0xFE, 0x80, 0x12, 0x34, 0xFE, 0xFF,       # stop code: the rest is data
             0xFF])                                                    # an empty reaction part
BAD = bytes([0x00, 0, 0, 0, 0xFE, 0x01, 1, 2, 0xFF, 0x01, 0, 0, 0, 0xFE, 0xFF, 0xFF])  # $FF inside the main part


def ai_piece() -> battle.Piece:
    scripts = ONE + ONE + TWO + BAD
    at = {}
    a = 0x8D08
    for name, s in (('f1', ONE), ('f2', ONE), ('two', TWO), ('bad', BAD)):
        at[name] = a
        a += len(s)
    table = bytearray()
    for i in range(256):
        t = at['two'] if i == 1 else at['bad'] if i == 2 else at['f1']
        table += t.to_bytes(2, 'little')
    return battle.Piece('AiTab', 'enemy', BASE, bytes(table) + scripts)


class Behaviour(unittest.TestCase):

    def text(self):
        p = ai_piece()
        return battle.render_ai(stub_format(), p), p

    def test_round_trip(self):
        text, p = self.text()
        self.assertEqual(battle.assemble_ai(text, stub_format(), p.label, p.start, len(p.data)), p.data)
        self.assertIn('    test Test17 $32 $00 $00\n    test Test03 $01 $02 $00\n    do', text)
        self.assertIn('    act Act04\n    act Act01 $01 $02 $03\n    act Act09 $07\n    done', text)
        self.assertIn('    test Test05 $09 $00 $00\n    do\n@bytes 80 12 34\n    done', text)
        bad = 0x8D08 + 2 * len(ONE) + len(TWO)
        self.assertRegex(text, rf'; A_{bad:04X} is kept as bytes: .*first \$FF')
        self.assertEqual(battle.stats('enemy', text)['kept'], len(BAD))

    def refused(self, old, new, why):
        text, p = self.text()
        self.assertIn(old, text)
        with self.assertRaisesRegex(battle.BattleError, why):
            battle.assemble_ai(text.replace(old, new, 1), stub_format(), p.label, p.start, len(p.data))

    def test_record_length_refused(self):
        self.refused('act Act09 $07', 'act Act09 $07 $00', 'are 2 bytes')

    def test_regrouped_records_refused(self):
        # the same bytes as two records of other lengths
        self.refused('    act Act04\n    act Act01 $01 $02 $03\n    act Act09 $07',
                     '    act Act04\n@bytes 01 01 02 03\n    act Act09 $07', 'reads? a')

    def test_kept_script_must_stay_bytes(self):
        text, p = self.text()
        lines = text.split('\n')
        k = lines.index(f'A_{0x8D08 + 2 * len(ONE) + len(TWO):04X}:')
        lines[k + 1] = '    test Test00 $00 $00 $00\n    do\n    act Act01 $01 $02 $FF\n    test Test01 $00 $00 $00'
        with self.assertRaises(battle.BattleError):
            battle.assemble_ai('\n'.join(lines), stub_format(), p.label, p.start, len(p.data))

    def test_unreached_line_refused(self):
        # the data after the stop code written as a record: no reader reads it
        self.refused('@bytes 80 12 34', '@bytes 80\n    act Act0E $34', 'no script reaches')

    def test_operand_delimiter_refused(self):
        # a $FE in a test's operands: the readers' scan stops there
        self.refused('test Test17 $32 $00 $00', 'test Test17 $32 $FE $00', 'reads? a|cannot be read')


class Source(unittest.TestCase):

    def test_names_from_the_tables(self):
        names, count = battle.act_names()
        self.assertEqual(count, 0xDB)
        self.assertEqual(names[0x1E], 'Op1E_Call')
        self.assertEqual(names[0x12], 'Op12_MoveToCalc')
        tests, acts = battle.ai_names()
        self.assertEqual(tests[0x17], 'TestChance')
        self.assertEqual(acts[1], 'RunAttack')
        self.assertEqual(acts[4], 'ChooseByChance')

    def test_manifest_battle_pieces(self):
        pieces = [p for p in ed.read_manifest() if p['piece'] == 'battle']
        self.assertEqual(len(pieces), len(battle.ROWS))
        self.assertEqual({p['param'].split('/')[0] for p in pieces}, set(battle.UNITS))
        for p in pieces:
            self.assertEqual(p['asset'], f'battle/{p["param"].split("/")[0]}.bscr')
            if p['param'].endswith('/table') or p['param'].endswith('/subscripts'):
                self.assertIn(p['label'], battle.TABLE_BANKS)


@unittest.skipUnless(HAVE_ROM, 'needs the ROM and asar')
class WithRom(unittest.TestCase):

    def test_units_round_trip(self):
        rom = ed.read_rom()
        self.assertEqual(battle.check(rom), [])


if __name__ == '__main__':
    unittest.main()
