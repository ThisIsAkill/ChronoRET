#!/usr/bin/env python3
"""
test_lint_spc700.py — Tests for the readability lint's SPC700 rules
(tools/lint_spc700.py) and the SPC700 rows of tools/progress.py.

    python3 tools/test_lint_spc700.py          (from the repository root)

The synthetic cases run anywhere: a small source file with a hand-made
layout and call sites, one case per rule (ADDR, CALL, CONST, WIDTH,
OPCODE, PLUMB, HEADER, STATE, SIZE, CALLERS), each with a clean twin.

The pinned cases need the ROM and asar (skipped otherwise): the source in
asm/spc700/ has no finding, and the generated rows of
symbols/spc700_functions.csv give the first batch's routines with their
ARAM and ROM ranges.
"""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lint_spc700 as S  # noqa: E402

READY = bool(Path('roms/chrono_trigger.sfc').exists() and shutil.which('asar'))

GOOD = '''\
; $0B96 — Spc_Poll (6 bytes, $0B96–$0B9B; ROM $C7:2E5B–$2E60)
; Reads port 0.
; Callers note: CALL from Spc_Main ($0299).
; Entry: P=0
; Exit:  X = CPUIO0
; Sub-entries: Spc_PollTail.
Spc_Poll:
    mov.b x,!SPC_CPUIO0
    bne .done
Spc_PollTail:                           ; header: see Spc_Poll
    mov a,#!Spc_Big
.done:
    ret
'''

ROWS = [
    {'name': 'Spc_Poll', 'address': '$0B96', 'end': '$0B99', 'rom': '$C7:2E5B'},
    {'name': 'Spc_PollTail', 'address': '$0B9A', 'end': '$0B9B', 'rom': '$C7:2E5F'},
]
SITES = {0x0B96: [0x0299, 0x0B97], 0x0B9A: [0x0299]}


def lint(text, rows=ROWS, sites=SITES):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'driver.asm'
        path.write_text(text)
        found = S.body_findings(path) + S.header_findings(path, rows, sites)
    return [(f, rule) for f, _, rule, _ in found]


class Rules(unittest.TestCase):

    def test_clean(self):
        self.assertEqual(lint(GOOD), [])

    def test_body_rules(self):
        cases = [('    mov.b x,!SPC_CPUIO0', '    mov.b x,$F4', 'ADDR'),
                 ('    bne .done', '    bne $0B9D', 'CALL'),
                 ('    mov a,#!Spc_Big', '    mov a,#$40', 'CONST'),
                 ('    mov.b x,!SPC_CPUIO0', '    mov x,!SPC_CPUIO0', 'WIDTH')]
        for old, new, rule in cases:
            with self.subTest(rule=rule):
                self.assertIn(rule, [r for _, r in lint(GOOD.replace(old, new))])
        self.assertEqual(lint(GOOD.replace('    mov a,#!Spc_Big', '    mov a,#$40 ; lint-ok: a count')), [])
        self.assertEqual(lint(GOOD.replace('    mov a,#!Spc_Big', '    mov a,#8')), [])
        # registers, (x) forms and one-encoding instructions need no width
        self.assertEqual(lint(GOOD.replace('    mov a,#!Spc_Big', '    mov a,(x+)\n    mov1 c,!Spc_Bit.3')), [])
        self.assertIn('OPCODE', [r for _, r in lint(GOOD.replace('    ret', '    db $6F ; ret'))])
        self.assertIn('PLUMB', [r for _, r in lint(GOOD.replace('    ret', '    print "x"\n    ret'))])
        self.assertIn('CALL', [r for _, r in lint(GOOD.replace('    bne .done', '    bbs.b !Spc_F.3,$0B9D'))])
        # the negated bit forms spc700.py prints for opcodes $2A/$6A
        for raw in ('    and1 c,!$1234.3', '    or1 c,!$1234.0'):
            with self.subTest(raw=raw):
                self.assertIn('ADDR', [r for _, r in lint(GOOD.replace('    ret', raw + '\n    ret'))])
        self.assertEqual(lint(GOOD.replace('    ret', '    and1 c,!!Spc_Bit.3\n    ret')), [])

    def test_header(self):
        self.assertIn(('Spc_Poll', 'HEADER'), lint(GOOD.replace('; Exit:  X = CPUIO0\n', '')))
        self.assertIn(('Spc_PollTail', 'HEADER'),
                      lint(GOOD.replace('; Sub-entries: Spc_PollTail.\n', '')))
        self.assertIn(('Spc_Poll', 'STATE'), lint(GOOD.replace('; Entry: P=0', '; Entry: A any')))
        self.assertEqual(lint(GOOD.replace('; Entry: P=0', '; Entry: P any, A any')), [])
        self.assertEqual(lint(GOOD.replace('; Entry: P=0', '; Entry: SP, P, A, X, Y any')), [])
        self.assertEqual(lint(GOOD.replace('; Entry: P=0', '; Entry: P = 1')), [])
        for loose in ('; Entry: A = P', '; Entry: P', '; Entry: the P flag as the caller left it'):
            with self.subTest(loose=loose):
                self.assertIn(('Spc_Poll', 'STATE'), lint(GOOD.replace('; Entry: P=0', loose)))

    def test_size(self):
        self.assertIn(('Spc_Poll', 'SIZE'), lint(GOOD.replace('(6 bytes', '(5 bytes')))
        self.assertIn(('Spc_Poll', 'SIZE'), lint(GOOD.replace('$0B9B; ROM', '$0B9C; ROM')))
        self.assertIn(('Spc_Poll', 'SIZE'), lint(GOOD.replace('ROM $C7:2E5B', 'ROM $C7:2E5C')))
        alone = GOOD.replace('(6 bytes, $0B96–$0B9B; ROM $C7:2E5B–$2E60)',
                             '(4 bytes, $0B96–$0B99; ROM $C7:2E5B–$2E5E)')
        self.assertEqual(lint(alone), [])
        self.assertEqual([r for _, r in lint(GOOD, rows=None)], [])

    def test_callers(self):
        # $0B97 is inside the routine: internal flow, not a caller
        self.assertEqual(lint(GOOD.replace('($0299)', '($0299 and the sub-entry)')), [])
        self.assertIn(('Spc_Poll', 'CALLERS'), lint(GOOD.replace(' ($0299)', '')))
        self.assertIn(('Spc_Poll', 'CALLERS'), lint(GOOD, sites={0x0B9A: [0x0400]}))
        self.assertEqual(lint(GOOD.replace(' ($0299)', ''), sites=None), [])
        # only the Callers note lines (and their continuations) name callers
        moved = GOOD.replace(' ($0299)', '').replace('; Reads port 0.', '; Reads port 0 (see $0299).')
        self.assertIn(('Spc_Poll', 'CALLERS'), lint(moved))
        wrapped = GOOD.replace(' ($0299)', ' and\n;   Spc_Other ($0299)')
        self.assertEqual(lint(wrapped), [])
        # CALLERS cannot be opted out of; the other header rules can
        opted = GOOD.replace(' ($0299)', '').replace('Spc_Poll:\n', 'Spc_Poll: ; lint-ok: test\n')
        self.assertEqual(lint(opted), [('Spc_Poll', 'CALLERS')])
        self.assertEqual(lint(opted.replace('; Entry: P=0', '; Entry: A any')), [('Spc_Poll', 'CALLERS')])


@unittest.skipUnless(READY, 'needs the ROM and asar')
class Pinned(unittest.TestCase):

    def test_tree_is_clean(self):
        self.assertEqual(S.collect(), [])

    def test_rows(self):
        import generated
        rows = {r['name']: r for r in generated.spc700_rows()}
        for name, aram, rom, size in (('Spc_Start', '$0200', '$C7:24C5', 153),
                                      ('Spc_MainLoop', '$0299', '$C7:255E', 222),
                                      ('Spc_WriteDsp', '$07A3', '$C7:2A68', 5),
                                      ('Spc_StartSong', '$0BE6', '$C7:2EAB', 272),
                                      ('Spc_RunHighCommand', '$0DFB', '$C7:30C0', 22)):
            with self.subTest(name=name):
                r = rows[name]
                self.assertEqual((r['address'], r['rom'], int(r['size'])), (aram, rom, size))
        self.assertNotIn('Spc_Start', {r['name'] for r in generated.function_rows()})
        self.assertTrue(all(r['kind'] in ('code', 'data') for r in rows.values()))

    def test_65816_figures_leave_the_driver_out(self):
        import json
        import generated
        import spc700
        generated.ensure()
        data = json.loads(generated.PROGRESS_JSON.read_text())
        rom = spc700.ROM_PATH.read_bytes()
        first, base, size = spc700.driver_block(rom)
        block = range(spc700.DRIVER_ROM, first + size)
        for sl in data['slices']:
            lo = int(sl['start'][1:3], 16) - 0xC0 << 16 | int(sl['start'][4:], 16)
            if lo <= block[-1] and block[0] < lo + 0x1000 and not sl['functions']:
                self.assertEqual(sl['emitted_bytes'], 0, sl['start'])
        # every emitted byte of the block is in a row, but the length word
        # before the program (2 bytes, no label), once it is emitted
        spc_rows = sum(int(r['size']) for r in generated.spc700_rows())
        self.assertIn(data['spc700']['emitted_bytes'] - spc_rows, (0, 2))


if __name__ == '__main__':
    unittest.main()
