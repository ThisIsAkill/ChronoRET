#!/usr/bin/env python3
"""
test_lint_size.py — Tests for the lint's SIZE rule on combined claims
(`Name (N bytes with A and B, $XXXX–$YYYY)`, tools/lint_readability.py).

    python3 tools/test_lint_size.py          (from the repository root)

The synthetic cases run anywhere, against a hand-made layout:

  * true claims: one companion, a wrapped claim with a hyphen and a
    comma-formatted size, `Name1-3` naming a run, `header: see` sub-entries
    that the claim does not name ("its sub-entries"), a range ending before
    a gap;
  * false claims: the wrong size, the wrong start, an end inside a row, an
    end before the routine's own end, a row inside the range left unnamed.

The pinned case needs the ROM and asar (skipped otherwise): the claim a
review found wrong in C6Scene_PerspQuad0's header (458 bytes, $EB3B–$ED04,
ending one byte into C6Scene_PerspTail) is found, and the header as it is
now passes.
"""

import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asm_source  # noqa: E402
import lint_readability as lint  # noqa: E402
import xref  # noqa: E402

READY = bool(xref.ROM_PATH.exists() and shutil.which('asar'))


def layout(*rows):
    """Rows (start, end, name) in bank $C2."""
    return lint.Layout([{'address': f'$C2:{s:04X}', 'end': f'$C2:{e:04X}', 'name': n}
                        for s, e, n in rows])


def region(name, header):
    lines = [f'; {h}' for h in header] + [f'{name}:', '    RTS']
    return asm_source.Region(name, 'fake.asm', lines, 0, len(header), len(lines))


LAY = layout((0x8000, 0x800F, 'Before'),
             (0x8010, 0x801F, 'Main'),
             (0x8020, 0x802F, 'MainTail'),
             (0x8030, 0x803F, 'Quad1'),
             (0x8040, 0x804F, 'Quad2'),
             (0x8050, 0x805F, 'Quad3'),
             (0x8060, 0x806F, 'SubA'),
             (0x8070, 0x807F, 'After'),
             (0x8090, 0x809F, 'PastGap'))


def findings(header, parent_of=None, lay=LAY):
    r = region('Main', header)
    return lint.size_findings(r, lay, {}, parent_of or {})


class Combined(unittest.TestCase):

    def test_one_companion(self):
        self.assertEqual(findings(['$C2:8010 — Main (32 bytes with MainTail, $8010–$802F)']), [])

    def test_wrapped_hyphen_comma(self):
        self.assertEqual(findings(['$C2:8010 — Main (32 bytes with MainTail and',
                                   ';   nothing else, $C2:8010-$C2:802F)']), [])
        big = layout((0x1000, 0x1FFF, 'Main'), (0x2000, 0x2FFF, 'Next'))
        self.assertEqual(findings(['Main (8,192 bytes with Next, $1000–$2FFF)'], lay=big), [])

    def test_name_run(self):
        self.assertEqual(findings(['Main (80 bytes with MainTail, Quad1-3,',
                                   '  $8010–$805F)']), [])

    def test_sub_entries(self):
        parents = {'SubA': 'Quad3'}
        self.assertEqual(findings(['Main (96 bytes with MainTail, Quad1-3 and its',
                                   'sub-entries, $8010–$806F)'], parents), [])
        parents = {n: 'Main' for n in ('MainTail', 'Quad1', 'Quad2', 'Quad3', 'SubA')}
        self.assertEqual(findings(['Main (96 bytes with its sub-entries, $8010–$806F)'],
                                  parents), [])

    def test_end_before_gap(self):
        parents = {n: 'Main' for n in ('MainTail', 'Quad1', 'Quad2', 'Quad3', 'SubA', 'After')}
        self.assertEqual(findings(['Main (112 bytes with its sub-entries, $8010–$807F)'],
                                  parents), [])

    def test_wrong_size(self):
        out = findings(['Main (30 bytes with MainTail, $8010–$802F)'])
        self.assertEqual(len(out), 1)
        self.assertIn('is 32 bytes', out[0])

    def test_wrong_start(self):
        out = findings(['Main (31 bytes with MainTail, $8011–$802F)'])
        self.assertEqual(len(out), 1)
        self.assertIn('Main starts at $C2:8010', out[0])

    def test_end_inside_row(self):
        out = findings(['Main (33 bytes with MainTail and Quad1, $8010–$8030)'])
        self.assertEqual(len(out), 1)
        self.assertIn('inside Quad1', out[0])

    def test_end_before_own_end(self):
        out = findings(['Main (8 bytes with nothing, $8010–$8017)'])
        self.assertEqual(len(out), 1)
        self.assertIn('alone runs to $C2:801F', out[0])

    def test_unnamed_row(self):
        out = findings(['Main (48 bytes with MainTail, $8010–$803F)'])
        self.assertEqual(len(out), 1)
        self.assertIn('also holds Quad1', out[0])

    def test_end_in_gap(self):
        parents = {n: 'Main' for n in ('MainTail', 'Quad1', 'Quad2', 'Quad3', 'SubA', 'After')}
        out = findings(['Main (128 bytes with its sub-entries, $8010–$808F)'], parents)
        self.assertEqual(len(out), 1)
        self.assertIn('not the end of a row', out[0])

    def test_unreadable_claim_reported(self):
        out = findings(['Main (32 bytes with MainTail (a tail), $8010–$802F)'])
        self.assertEqual(len(out), 1)
        self.assertIn('cannot read', out[0])
        self.assertEqual(findings(['Main is 24 bytes with MainTail; see $8020.']), [])

    def test_plain_claim_still_checked(self):
        self.assertEqual(findings(['Main (16 bytes, $8010–$801F)']), [])
        self.assertEqual(len(findings(['Main (17 bytes, $8010–$8020)'])), 1)


@unittest.skipUnless(READY, 'needs the ROM and asar')
class Pinned(unittest.TestCase):

    def test_persp_quad0(self):
        lay = lint._layout()
        regions = asm_source.file_regions(Path('asm/bankC6/bankC6.asm'))
        r = next(r for r in regions if r.name == 'C6Scene_PerspQuad0')
        self.assertEqual(lint.size_findings(r, lay, {}, {}), [])
        wrong = region('C6Scene_PerspQuad0',
                       ['$C6:EB3B — C6Scene_PerspQuad0 (458 bytes with Quad1-3 and Tail, '
                        '$EB3B–$ED04)'])
        out = lint.size_findings(wrong, lay, {}, {})
        self.assertEqual(len(out), 1)
        self.assertIn('inside C6Scene_PerspTail', out[0])


if __name__ == '__main__':
    unittest.main()
