#!/usr/bin/env python3
"""
test_index_claims.py — Tests for the lint's INDEX rule (tools/index_claims.py).

    python3 tools/test_index_claims.py          (from the repository root)

The synthetic cases run anywhere: a few routines are assembled by hand into a
blank ROM, with the instruction boundaries a real Xref would take from asar,
and judged under a hand-written header:

  * a true claim (no X flag change; PHY/PLY at 16 bits around a SEP #$10),
  * a false claim through a callee's SEP #$10, named with the call chain,
  * a PLY at 8 bits (the save does not bring the high byte back),
  * qualified wording ("low byte kept, high byte cleared", "with X=1 at
    entry", an Entry line declaring X=1, "X" next to M as the flag),
  * a claim limited to one path, and code the analysis cannot follow.

The pinned cases need the ROM and asar (skipped otherwise): the tree has no
INDEX finding, and C2Scene_QueueEdgeCol's SEP #$30 at $C2:0923 is found when
its header claims Y unchanged.
"""

import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asm_source  # noqa: E402
import index_claims  # noqa: E402
import xref  # noqa: E402

READY = bool(xref.ROM_PATH.exists() and shutil.which('asar'))

# 65816 encodings used below.
SEP = lambda v: bytes((0xE2, v))          # noqa: E731
REP = lambda v: bytes((0xC2, v))          # noqa: E731
JSR = lambda t: bytes((0x20, t & 0xFF, t >> 8 & 0xFF))   # noqa: E731
RTS, PHY, PLY, TCS = b'\x60', b'\x5A', b'\x7A', b'\x1B'
BEQ = lambda d: bytes((0xF0, d & 0xFF))   # noqa: E731
LDA8 = lambda v: bytes((0xA9, v))         # noqa: E731  LDA #imm with M=1


class FakeXref:
    """What index_claims.Analyzer reads from tools/xref.py's Xref."""

    def __init__(self):
        self.rom = bytearray(0x10000)
        self.rows, self.boundaries, self.labels = [], {}, {}
        self.pc = 0x8000

    def routine(self, name, *insns):
        start = self.pc
        self.labels[name] = start
        for code in insns:
            self.rom[self.pc:self.pc + len(code)] = code
            self.boundaries[self.pc] = ('fake.asm', 0, True)
            self.pc += len(code)
        self.rows.append((start, self.pc - 1, name))
        self.rows.sort()
        return start

    def routine_at(self, off):
        for s, e, n in self.rows:
            if s <= off <= e:
                return n
        return ''

    def name_at(self, off):
        return next((n for n, o in self.labels.items() if o == off), '')

    def _table_targets(self, table):
        return ()


def region(name, header):
    lines = [f'; {h}' for h in header] + [f'{name}:', '    RTS']
    return asm_source.Region(name, 'fake.asm', lines, 0, len(header), len(lines))


def judge(xr, name, *header):
    an = index_claims.Analyzer(xr)
    return [t for _, t in index_claims.routine_findings(an, region(name, header))]


ENTRY = 'Entry: M=1, X=0, DP=0, DB=$7E'


class SyntheticTest(unittest.TestCase):

    def setUp(self):
        xr = self.xr = FakeXref()
        self.bar = xr.routine('Bar', SEP(0x10), REP(0x10), RTS)              # SEP #$10, back to 16-bit
        xr.routine('CallsBar', JSR(self.bar), RTS)
        xr.routine('Plain', LDA8(1), RTS)
        xr.routine('SavesY', PHY, SEP(0x10), REP(0x10), PLY, RTS)             # Y saved and restored at 16 bits
        xr.routine('PullsY8', SEP(0x10), PHY, PLY, REP(0x10), RTS)            # saved at 8 bits: one byte
        xr.routine('Branchy', BEQ(4), JSR(self.bar), RTS, RTS)                # one exit keeps Y, one loses it
        xr.routine('Thread', SEP(0x10), TCS, RTS)                             # thread switch: not followed

    def test_true_claim(self):
        self.assertEqual(judge(self.xr, 'Plain', ENTRY, 'Exit: M=1, X=0; X and Y unchanged'), [])

    def test_sep_in_callee(self):
        found = judge(self.xr, 'CallsBar', ENTRY, 'Exit: M=1, X=0; A clobbered, Y unchanged')
        self.assertEqual(len(found), 1)
        self.assertIn('Y is kept', found[0])
        self.assertIn('JSR Bar at $C0:8005 -> SEP #$10 at $C0:8000 in Bar', found[0])
        found = judge(self.xr, 'CallsBar', ENTRY, 'Exit: M=1, X=0; X/Y preserved')
        self.assertEqual(len(found), 2)

    def test_ply_restores_at_16_bits(self):
        self.assertEqual(judge(self.xr, 'SavesY', ENTRY, 'Exit: M=1, X=0; Y unchanged'), [])
        found = judge(self.xr, 'PullsY8', ENTRY, 'Exit: M=1, X=0; Y unchanged')
        self.assertEqual(len(found), 1)
        self.assertIn('SEP #$10 at', found[0])

    def test_qualified(self):
        for exit_line in ("Exit: M=1, X=0; Y's low byte kept, high byte cleared (Bar's SEP #$10)",
                          'Exit: M=1, X=0; Y unchanged with X=1 at entry',
                          'Exit: M=1, X=0; Y unchanged (X=1 callers only)',
                          'Exit: M=1, X, DP and DB unchanged'):
            with self.subTest(exit_line):
                self.assertEqual(judge(self.xr, 'CallsBar', ENTRY, exit_line), [])
        self.assertEqual(judge(self.xr, 'CallsBar', 'Entry: M=1, X=1, DP=0, DB=$7E',
                               'Exit: M=1, X=1; Y unchanged'), [])

    def test_conditional_claim(self):
        # Limited to a path that keeps it: not judged.
        self.assertEqual(judge(self.xr, 'Branchy', ENTRY, 'Exit: M=1, X=0; Y unchanged on the BEQ path'), [])
        # Unconditional: the JSR Bar path loses the high byte.
        self.assertEqual(len(judge(self.xr, 'Branchy', ENTRY, 'Exit: M=1, X=0; Y unchanged')), 1)
        # Limited, but no exit keeps it whole (the other path changes Y).
        self.assertEqual(len(judge(self.xr, 'CallsBar', ENTRY, 'Exit: M=1, X=0; Y unchanged if Z')), 1)

    def test_unfollowable(self):
        self.assertEqual(judge(self.xr, 'Thread', ENTRY, 'Exit: M=1, X=0; Y unchanged'), [])

    def test_lint_ok(self):
        self.assertEqual(judge(self.xr, 'CallsBar', ENTRY,
                               'Exit: M=1, X=0; Y unchanged  ; lint-ok: callers enter with X=1'), [])

    def test_claim_parsing(self):
        cl = index_claims.claims('M=1, X=0; A clobbered, X, Y and DP unchanged; else Y kept')
        self.assertEqual([(sorted(r), c) for r, _, c in cl],
                         [(['X', 'Y'], False), (['Y'], True)])
        self.assertEqual(index_claims.claims('M=1, X, DP and DB unchanged'), [])
        cl = index_claims.claims('Y = Obj_Cur when a tile was probed (else unchanged)')
        self.assertEqual([(sorted(r), c) for r, _, c in cl], [(['Y'], True)])


@unittest.skipUnless(READY, 'needs roms/chrono_trigger.sfc and asar')
class PinnedTest(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.xr = index_claims._default_xref()
        cls.regions = asm_source.regions()

    def test_tree_has_no_findings(self):
        self.assertEqual(index_claims.analyze(self.xr, self.regions), [])

    def test_sep_in_body(self):
        an = index_claims.Analyzer(self.xr)
        r = region('C2Scene_QueueEdgeCol', ['Entry: M=0, X=0, DP=0, DB=$7E',
                                            'Exit: M=0, X=0; X = the entry offset; Y unchanged'])
        found = [t for _, t in index_claims.routine_findings(an, r)]
        self.assertEqual(len(found), 1)
        self.assertIn('SEP #$30 at $C2:0923 in C2Scene_QueueEdgeCol', found[0])


if __name__ == '__main__':
    unittest.main()
