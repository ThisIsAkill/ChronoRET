#!/usr/bin/env python3
"""
test_c3module.py — Tests for the packed $C3 module's trace (tools/c3module.py)
and its lint rules (tools/lint_c3module.py).

    python3 tools/test_c3module.py          (from the repository root)

Without the ROM: the lint's header rules on a small synthetic source (SIZE
and CALLERS against a given layout and call sites, a placeholder block
exempt), the KERNEL rule against given labels, and planted file reads
caught: an incbin or readfile in the module's files (ROMBYTES) and an
incbin of the ROM in a bank file (PLUMB; only bankC3.asm's module.lz line
is allowed).

With the ROM: the trace reaches the module's entry, its program table's
targets and the kernel's entries, and finds the call sites the headers
name (C3Mod_Init from $3000, C3Mod_AudioSend from $3187); with asar too,
the module's source passes every rule (tools/lint_c3module.py), and a raw
incbin of the ROM's module in place of %C3ModRomBytes is not counted as
source by c3pack.source_bytes(). The trace's known anomalies are handled
($3C57 decoded 16-bit, nothing decoded in the staff text).
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


class FileReads(unittest.TestCase):
    """Bytes read from a file are never source: ROMBYTES in the module's
    files, PLUMB in the bank files (and module.asm)."""

    def test_rombytes(self):
        import lint_readability as L
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'module.inc').write_text(
                'macro C3ModRomBytes(start, end)\n    ' + lint_c3module.ROMBYTES_LINE + '\nendmacro\n'
                'macro Other()\n    incbin "x.bin"\nendmacro\n')
            (root / 'module.asm').write_text(
                'C3Mod_Rest31BF:\n    incbin "../../../build/c3pack/rom_module.bin":$1BF..$77A\n'
                'C3Mod_Other:\n    db readfile1("../../../roms/chrono_trigger.sfc", 0)\n')
            found = [(Path(p).name, no) for p, _, no, rule, _ in lint_c3module.rombytes_findings(root)]
            self.assertEqual(sorted(found), [('module.asm', 2), ('module.asm', 4), ('module.inc', 5)])
            rules = [rule for _, _, rule, _ in L.lint_file(root / 'module.asm')]
            self.assertEqual(rules.count('PLUMB'), 2)

    def test_bank_incbin(self):
        import lint_readability as L
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bankC3.asm'
            path.write_text('; $C3:1200 — BankC3_Pack0 (10 bytes, $1200–$1209)\n'
                            'org $C31200\nBankC3_Pack0:\n'
                            '    incbin "../../roms/chrono_trigger.sfc":$31200..$3120A\n'
                            '    incbin "../../build/c3pack/module.lz"   ; lint-ok: not here\n')
            found = [(no, rule) for _, no, rule, _ in L.lint_file(path)]
            self.assertEqual(found, [(4, 'PLUMB'), (5, 'PLUMB')])
        real = Path('asm/bankC3/bankC3.asm')
        if real.exists():
            self.assertFalse([f for f in L.lint_file(real) if f[2] == 'PLUMB'])


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

    def test_known_anomalies(self):
        # $45D6 returns with M=0 (CALL_EXITS): Prog0's BIT #$40 at $3C57 is 16-bit
        self.assertFalse(self.insns[0x3C57].m)
        self.assertEqual(self.insns[0x3C57].size, 3)
        # the staff text is data: no instruction in it, the path into it reported
        lo, hi, _ = c3module.DATA_RANGES[0]
        self.assertFalse([a for a in self.insns if lo <= a <= hi])
        self.assertIn((0xB574, 'enters data'), self.anomalies)

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

    def test_source_bytes_cannot_read_the_rom(self):
        # A raw incbin of the ROM's module in place of %C3ModRomBytes builds
        # the same bytes, but those bytes do not count as source.
        real = len(c3pack.source_bytes())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree('asm', root / 'asm')
            (root / 'roms').mkdir()
            (root / 'roms' / 'chrono_trigger.sfc').symlink_to(c3pack.ROM_PATH.resolve())
            src = root / c3pack.MODULE_SOURCE
            text = src.read_text()
            line = '    %C3ModRomBytes($7E31BF, $7E377A)'
            self.assertIn(line, text)
            src.write_text(text.replace(line, '    incbin "../../../build/c3pack/rom_module.bin":$1BF..$77A'))
            c3pack.build(root)
            self.assertEqual(len(c3pack.source_bytes(root)), real)


if __name__ == '__main__':
    unittest.main(verbosity=1)
