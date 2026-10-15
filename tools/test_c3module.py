#!/usr/bin/env python3
"""
test_c3module.py — Tests for the packed $C3 module's trace (tools/c3module.py)
and its lint rules (tools/lint_c3module.py).

    python3 tools/test_c3module.py          (from the repository root)

Without the ROM: the lint's header rules on a small synthetic source (SIZE
and CALLERS against a given layout and call sites, a placeholder block
exempt) and the KERNEL rule against given labels.

With the ROM: the trace reaches the module's entry, its program table's
targets and the kernel's entries, and finds the call sites the headers
name (C3Mod_Init from $3000, C3Mod_AudioSend from $3187); with asar too,
the module's source passes every rule (tools/lint_c3module.py), and a wrong
kernel define is caught.
"""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import c3module  # noqa: E402
import c3pack  # noqa: E402
import lint_c3module  # noqa: E402

HAVE_ROM = c3pack.ROM_PATH.exists()
HAVE_ASAR = shutil.which('asar') is not None

SOURCE = """\
; $7E:3000 — C3Mod_First (3 bytes, $3000–$3002)
; Does nothing much.
; Callers note: $4000.
; Entry: M=1, X=0, DP any, DB=$00.
; Exit:  as on entry.
C3Mod_First:
    NOP
    NOP
    RTS

; $7E:3003 — C3Mod_Second (2 bytes, $3003–$3005)
; Wrong size claim, and a caller not named.
; Entry: M=1, X=0, DP any, DB=$00.
; Exit:  as on entry.
C3Mod_Second:
    NOP
    RTS

C3Mod_Rest3005:
    %C3ModRomBytes($7E3005, $7E3010)
"""
ROWS = [
    {'address': '$7E:3000', 'end': '$7E:3002', 'name': 'C3Mod_First'},
    {'address': '$7E:3003', 'end': '$7E:3004', 'name': 'C3Mod_Second'},
]


class Rules(unittest.TestCase):

    def findings(self, sites):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'module.asm'
            path.write_text(SOURCE)
            return [(f, rule) for f, _, rule, _ in lint_c3module.header_findings(path, ROWS, sites)]

    def test_size_and_callers(self):
        found = self.findings({0x3000: [0x4000], 0x3003: [0x4010, 0x3001]})
        self.assertIn(('C3Mod_Second', 'SIZE'), found)
        self.assertIn(('C3Mod_Second', 'CALLERS'), found)      # $4010 and $3001 are not named
        self.assertNotIn(('C3Mod_First', 'CALLERS'), found)
        self.assertNotIn(('C3Mod_First', 'SIZE'), found)
        self.assertFalse([f for f in found if f[0] == 'C3Mod_Rest3005'])

    def test_callers_named(self):
        found = self.findings({0x3000: [0x4000, 0x3001]})       # $3001: inside the routine
        self.assertNotIn(('C3Mod_First', 'CALLERS'), found)
        found = self.findings({0x3000: [0x4002]})
        self.assertIn(('C3Mod_First', 'CALLERS'), found)

    def test_kernel(self):
        module = {'C3Mod_RunTasks': 0x7E398A}
        rom = {'C3_ModuleFrame': 0xC308D0, 'ReentryVectors': 0xC00000}
        self.assertEqual(lint_c3module.kernel_findings(module, rom), [])
        bad = lint_c3module.kernel_findings({'C3Mod_RunTasks': 0x7E398B},
                                            {**rom, 'C3_ModuleFrame': 0xC308D1})
        self.assertEqual(sorted(f[3] for f in bad), ['KERNEL', 'KERNEL'])


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class Trace(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.mem = c3module.module_bytes()
        cls.insns, cls.anomalies = c3module.trace(cls.mem)
        cls.sites = c3module.call_sites(cls.insns)

    def test_entries_reached(self):
        for a, *_ in c3module.ENTRIES:
            self.assertIn(a, self.insns)
        for a, _, _ in c3module.table_entries(self.mem):
            self.assertIn(a, self.insns)

    def test_sites(self):
        self.assertEqual(self.sites[0x3063], [0x3000])
        self.assertIn(0x3187, self.sites[0x377E])

    def test_no_overlap(self):
        owner = {}
        for ins in self.insns.values():
            for a in range(ins.pc, ins.pc + ins.size):
                self.assertNotIn(a, owner, f'${a:04X} is in two instructions')
                owner[a] = ins.pc


@unittest.skipUnless(HAVE_ROM and HAVE_ASAR, 'needs the ROM and asar')
class Source(unittest.TestCase):

    def test_clean(self):
        self.assertEqual(lint_c3module.collect(), [])


if __name__ == '__main__':
    unittest.main(verbosity=1)
