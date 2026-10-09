#!/usr/bin/env python3
"""
test_xref.py — Regression tests for tools/xref.py's verdicts.

    python3 tools/test_xref.py          (from the repository root)

Needs the ROM in roms/ and asar on PATH; skips otherwise.

What it pins:
  * call sites in unmatched code that the sweep alone rejected and the
    deeper analysis (Xref(), deep by default) confirms,
    and a byte pattern it correctly keeps DOUBTFUL. The fixtures were picked
    when their code was unmatched; matching it since would make the source
    answer instead. So these tests treat every matched routine that holds a
    fixture byte as unmatched (Xref(hide=...)): the unmatched-code analysis
    judges the fixtures however much of the ROM is matched;
  * matched code: every verdict comes from the source, so the deeper
    analysis changes none of them, and no site in a matched data table is
    CONFIRMED;
  * held-out score: half of the matched routines are treated as unmatched in
    turn and judged by the unmatched-code analysis, against the source's
    answer. The deeper analysis must find at least the calls the sweep alone
    finds, and every site it wrongly confirms the sweep alone also wrongly
    confirms. The split depends on the matched routines, so a few
    exceptions (HELD_OUT_SLACK of the calls) are allowed and listed.
"""

import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import xref  # noqa: E402

# symbols/functions.csv is generated (not tracked); Xref regenerates it.
READY = bool(xref.ROM_PATH.exists() and shutil.which('asar'))

# (site, kind, target): real calls in unmatched code.
REAL_CALLS = [
    ('$C2:38FB', 'JSR', '$C2:0568'),   # after REP #$20 and a JSR that returns with M=1
    ('$C2:3902', 'JSR', '$C2:0568'),
    ('$C2:385B', 'JSR', '$C2:066C'),
    ('$C2:3862', 'JSR', '$C2:066C'),
    ('$C2:3702', 'JSR', '$C2:0568'),   # the same pattern after an explicit SEP #$20
    ('$C2:3717', 'JSR', '$C2:066C'),
    ('$C2:7457', 'JMP', '$C2:04D9'),   # LDA #$C2 / LDX #$74AE / JMP: tail call
]
# (site, kind, target, covering instruction): byte patterns inside an operand.
NOT_CALLS = [
    ('$C1:B78C', 'BRL', '$C1:883D', '$C1:B78B'),   # LDA $AE82,X / BNE: 82 AE D0
]
# test_held_out: the share of the calls that may break each subset rule.
HELD_OUT_SLACK = 0.001


def fixture_hide(xr):
    """Start offsets of the matched rows that hold any byte of a fixture:
    the call instruction of a REAL_CALLS site, or the covering instruction
    and the pattern of a NOT_CALLS site."""
    spans = [(xr.resolve(site), xr.resolve(site) + 3) for site, _, _ in REAL_CALLS]
    spans += [(xr.resolve(insn), xr.resolve(site) + 3) for site, _, _, insn in NOT_CALLS]
    return {r[0] for r in xr.rows for lo, hi in spans if r[0] < hi and lo <= r[1]}


def hit(xr, site, kind, target):
    pos, tgt = xr.resolve(site), xr.resolve(target)
    hits = [h for h in xr.xref(tgt) if h.offset == pos and h.kind == kind]
    assert len(hits) == 1, f'{kind} {site} -> {target} is not a candidate'
    return hits[0]


@unittest.skipUnless(READY, 'needs roms/chrono_trigger.sfc and asar')
class XrefTest(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.deep = xref.Xref(deep=True)
        cls.plain = xref.Xref(deep=False)
        # The fixtures' own routines treated as unmatched (see the docstring).
        hide = fixture_hide(cls.plain)
        cls.fx_deep = xref.Xref(hide=hide, deep=True)
        cls.fx_plain = xref.Xref(hide=hide, deep=False)
        cls.fx_default = xref.Xref(hide=hide)

    def test_real_calls_confirmed(self):
        for site, kind, target in REAL_CALLS:
            with self.subTest(site=site):
                h = hit(self.fx_deep, site, kind, target)
                self.assertEqual(h.status, 'CONFIRMED', h.note)
                self.assertEqual(h.routine, '')

    def test_operand_bytes_doubtful(self):
        # The flow's note; a matched site would get the source's
        # 'byte N of the instruction at ...' instead.
        for site, kind, target, insn in NOT_CALLS:
            with self.subTest(site=site):
                h = hit(self.fx_deep, site, kind, target)
                self.assertEqual((h.status, h.basis), ('DOUBTFUL', 'flow'), h.note)
                self.assertIn(f'operand of the instruction at {insn}', h.note)

    def test_library_default_is_deep(self):
        # tools/callers.py and the lint's CALLERS rule use Xref(): the deeper
        # analysis, which confirms this call the sweep alone keeps DOUBTFUL.
        self.assertTrue(self.fx_default.deep)
        h = hit(self.fx_default, '$C2:38FB', 'JSR', '$C2:0568')
        self.assertEqual(h.status, 'CONFIRMED', h.note)
        h = hit(self.fx_plain, '$C2:38FB', 'JSR', '$C2:0568')
        self.assertEqual((h.status, h.basis), ('DOUBTFUL', 'sweep'))

    def test_exit_state(self):
        # $C2:3ACB returns with M=1 whichever width it is entered with.
        off = self.deep.resolve('$C2:3ACB')
        self.assertEqual(self.deep.exit_state(off, False, False), (True, False))

    def test_matched_code_unchanged(self):
        xr = self.deep
        if xr._index is None:
            xr._build_index()
        sites = sorted({s for lst in xr._index.values() for s in lst if xr.routine_at(s[0])})
        self.assertGreater(len(sites), 1000)
        for pos, kind in sites:
            d, p = xr.classify(pos, kind), self.plain.classify(pos, kind)
            self.assertEqual((d.status, d.basis), (p.status, 'source'), d.site)
            b = xr.boundaries.get(pos)
            if b and not b[2]:                       # a data line of the source
                self.assertEqual(d.status, 'DOUBTFUL', d.site)

    def test_held_out(self):
        base = self.plain
        if base._index is None:
            base._build_index()
        truth = {s: base._source_verdict(s[0])[0]
                 for lst in base._index.values() for s in lst if base.routine_at(s[0])}
        found, wrong = {False: set(), True: set()}, {False: set(), True: set()}
        for fold in (0, 1):
            hide = {r[0] for i, r in enumerate(base.rows) if i % 2 == fold}
            for deep in (False, True):
                xr = xref.Xref(hide=hide, deep=deep)
                for s, is_code in truth.items():
                    if not xr.routine_at(s[0]) and xr.classify(*s).status == 'CONFIRMED':
                        (found if is_code else wrong)[deep].add(s)
        calls = sum(truth.values())
        self.assertGreaterEqual(len(found[True]) / calls, 0.995)
        self.assertGreaterEqual(len(found[True]), len(found[False]))
        self.assertLessEqual(len(wrong[True]), len(wrong[False]))
        # Which routines are held out together shifts as routines get
        # matched; a rare call the deeper analysis loses (e.g. a hidden
        # routine entered with widths that only its own source rules out)
        # or wrongly gains is allowed, not a trend.
        slack = int(calls * HELD_OUT_SLACK)
        for name, extra in (('found by the sweep alone only', found[False] - found[True]),
                            ('wrongly confirmed by the deeper analysis only',
                             wrong[True] - wrong[False])):
            self.assertLessEqual(len(extra), slack,
                                 f'{len(extra)} sites {name}: '
                                 + ', '.join(xref.fmt(o) + ' ' + k for o, k in sorted(extra)))


if __name__ == '__main__':
    unittest.main(verbosity=2)
