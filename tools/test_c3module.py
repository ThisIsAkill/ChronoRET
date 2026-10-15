#!/usr/bin/env python3
"""
test_c3module.py — Tests for the packed $C3 module's trace (tools/c3module.py)
and its lint rules (tools/lint_c3module.py).

    python3 tools/test_c3module.py          (from the repository root)

Without the ROM: the lint's header rules on a small synthetic source (SIZE
and CALLERS against a given layout and call sites, a placeholder block
exempt), the KERNEL rule against given labels, and planted file reads
caught by the lint's FILEREAD rule: round 178's T2 (a function reading
the file), T3 (an incsrc'd include with an absolute incbin), T5 (a
symlink), T7 (a labelled incbin in the stubs) and T4b (a macro reading the
ROM, in a bank file).

With the ROM: the trace reaches the module's entry, its program table's
targets and the kernel's entries, and finds the call sites the headers
name (C3Mod_Init from $3000, C3Mod_AudioSend from $3187); with asar too,
the module's source passes every rule (tools/lint_c3module.py); and with
strace, the same five plants are refused by the isolated assemblies
(tools/isolated.py) of c3pack.source_bytes() and verify.assemble_onto(). The trace's known anomalies are handled
($3C57 decoded 16-bit, nothing decoded in the staff text).
"""

import re
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


ABS_MODULE = str(Path('build/c3pack/rom_module.bin').resolve())
HOLE = re.compile(r'^    %C3ModRomBytes\(\$7E([0-9A-F]{4}), \$7E([0-9A-F]{4})\)$', re.M)


def first_hole(text):
    """The first block of ROM bytes in module.asm: (line, start, end)."""
    m = HOLE.search(text)
    return m.group(0), int(m.group(1), 16), int(m.group(2), 16)


def plant(root: Path, case: str) -> None:
    """Plant one of the audit's ways of passing ROM bytes off as source
    (round 178) in a copy of asm/ at root."""
    asm = root / 'asm'
    mod = asm / 'bankC3/packed/module.asm'

    line, lo, hi = first_hole(mod.read_text())
    o, e = lo - 0x3000, hi - 0x3000                 # offsets in the module

    def module_hole(text):
        src = mod.read_text()
        mod.write_text(src.replace(line, text, 1))

    if case == 'T2':        # a function reading the file, defined in an include
        with (asm / 'include/macros.inc').open('a') as f:
            f.write(f'\nfunction romb(o) = readfile1("{ABS_MODULE}", o)\n')
        module_hole('\n'.join(f'    db romb(${k:X})' for k in range(o, o + 8))
                    + f'\n    %C3ModRomBytes($7E{lo + 8:04X}, $7E{hi:04X})')
    elif case == 'T3':      # an incsrc'd include with an absolute incbin
        (asm / 'include/evil.inc').write_text(f'incbin "{ABS_MODULE}":${o:X}..${e:X}\n')
        module_hole('    incsrc "../../include/evil.inc"')
    elif case == 'T5':      # a symlink under asm/
        (asm / 'include/tiles.bin').symlink_to(ABS_MODULE)
        module_hole(f'    incbin "../../include/tiles.bin":${o:X}..${e:X}')
    elif case == 'T7':      # a labelled incbin in the stubs file
        with (asm / 'bankC3/packed/unmatched.asm').open('a') as f:
            f.write(f'%C3ModOrg($7E{lo:04X})\nC3Mod_Junk: incbin "{ABS_MODULE}":${o:X}..${o + 8:X}\n')
    elif case == 'T4b':     # a macro in include/ reading the ROM, used in a bank file
        with (asm / 'include/macros.inc').open('a') as f:
            f.write('\nmacro DataBlock(a, b)\n    incbin "../../roms/chrono_trigger.sfc":<a>..<b>\n'
                    'endmacro\n')
        bank = asm / 'bankC3/bankC3.asm'
        bank.write_text(bank.read_text() + '\n; $C3:1200 — C3Rom_Pack0 (275 bytes, $1200–$1312)\n'
                        '; A pack. Entry: none. Exit: none.\norg $C31200\nC3Rom_Pack0:\n'
                        '    %DataBlock($31200, $31313)\n')
    elif case == 'N1':      # the image define set again after module.inc
        src = mod.read_text().replace('incsrc "module.inc"\n',
                                      f'incsrc "module.inc"\n!C3Mod_RomImage = "{ABS_MODULE}"\n')
        mod.write_text(src)
    elif case == 'N2':      # a readfile name pasted from defines
        module_hole(f'!rfA = rea\n!rfB = dfile1\n    db !rfA!rfB("{ABS_MODULE}", ${o:X})\n'
                    f'    %C3ModRomBytes($7E{lo + 1:04X}, $7E{hi:04X})')
    elif case == 'N3':      # an incbin pasted from defines
        module_hole(f'!dA = inc\n!dB = bin\n    !dA!dB "{ABS_MODULE}":${o:X}..${e:X}')
    elif case == 'N3c':     # the same in a macro of macros.inc, used in a bank file
        rom = str(c3pack.ROM_PATH.resolve())
        with (asm / 'include/macros.inc').open('a') as f:
            f.write(f'\n!dA = inc\n!dB = bin\nmacro DataBlock(a, b)\n    !dA!dB "{rom}":<a>..<b>\n'
                    'endmacro\n')
        bank = asm / 'bankC3/bankC3.asm'
        bank.write_text(bank.read_text() + '\n; $C3:1200 — C3Rom_Pack0 (275 bytes, $1200–$1312)\n'
                        '; A pack. Entry: none. Exit: none.\norg $C31200\nC3Rom_Pack0:\n'
                        '    %DataBlock($31200, $31313)\n')
    else:
        raise ValueError(case)


CASES = ('T2', 'T3', 'T5', 'T7', 'T4b', 'N1', 'N2', 'N3', 'N3c')


class FileReads(unittest.TestCase):
    """Bytes read from a file are never source (round 178's audit): the
    lint names every such read (FILEREAD), wherever and however written."""

    def test_lexical(self):
        import lint_readability as L
        for case in CASES:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                shutil.copytree('asm', root / 'asm', symlinks=True)
                self.assertEqual(L.file_read_findings(root / 'asm'), [])
                plant(root, case)
                found = L.file_read_findings(root / 'asm')
                self.assertTrue(found)
                self.assertEqual({f[3] for f in found}, {'FILEREAD'})

    def test_the_tree_is_clean(self):
        import lint_readability as L
        self.assertEqual(L.file_read_findings(), [])

    def test_allowed_lines_only_there(self):
        import lint_readability as L
        with tempfile.TemporaryDirectory() as tmp:
            asm = Path(tmp) / 'asm'
            asm.mkdir()
            (asm / 'bank.asm').write_text('    incbin "../../build/c3pack/module.lz"   ; lint-ok: no\n'
                                          'X: db filesize("a.inc")\n    incsrc "/etc/a.inc"\n'
                                          '    incsrc "../outside.inc"\n    incsrc "!evil"\n')
            found = sorted(f[2] for f in L.file_read_findings(asm))
            self.assertEqual(found, [1, 2, 3, 4, 5])


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class Trace(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.mem = c3module.module_bytes()
        cls.insns, cls.anomalies = c3module.trace(cls.mem)
        d = c3module.discover(cls.mem)
        cls.sites = c3module.call_sites(cls.insns, d.patched)

    def test_entries_reached(self):
        for a, *_ in c3module.ENTRIES:
            self.assertIn(a, self.insns)
        for a, _, _ in c3module.table_entries(self.mem):
            self.assertIn(a, self.insns)

    def test_known_anomalies(self):
        # $45D6 returns with M=0 (CALL_EXITS): Prog0's BIT #$40 at $3C57 is 16-bit
        self.assertFalse(self.insns[0x3C57].m)
        self.assertEqual(self.insns[0x3C57].size, 3)
        # the staff text is data: no instruction in it; the JSR $B574 at
        # $82A5 is a call into generated code (GENERATED), not followed
        lo, hi, _ = c3module.DATA_RANGES[0]
        self.assertFalse([a for a in self.insns if lo <= a <= hi])
        self.assertEqual(self.insns[0x82A5].operand, 0xB574)
        self.assertEqual(self.anomalies, [])

    def test_discovery(self):
        # the rules reach what the module only names at run time
        d = c3module.discover(self.mem)
        self.assertIn((0x3F14, 0x0A), d.scripts)          # LDA #$3F14 / STA $0A20 at $3C5C
        self.assertIn(0x3749, d.entries)                  # task added by the script at $3F14
        self.assertIn(0x45B0, d.patched[0x35FC])          # LDA #$45B0 / STA $35FD at $3CDB
        self.assertIn(0x5EF8, d.patched[0x5E43])          # bytes $F8, $5E written over $5E44/5
        self.assertIn(0x7F12, d.entries)                  # TASK_TABLES $7EC7
        self.assertIn(0x9317, d.script_bytes)             # SCRIPT_REDIRECTS $8CD0
        self.assertNotIn((0x9315, 0x0A), d.scripts)       # (resumed at + 2, not started)
        # $564D and $5640, called by page $0B's script $5568, start page
        # $0A at their values; page $0B goes on after the calls
        self.assertIn((0x5635, 0x0A), d.scripts)
        self.assertIn((0x5604, 0x0A), d.scripts)
        self.assertIn(0x55D8, d.script_bytes)
        # poke16 of page $0B's pointer by page $0A's script breaks the wait
        # loops; the scripts after them add the tasks $992A and $997D
        self.assertIn((0x97A9, 0x0B), d.scripts)
        self.assertIn((0x934A, 0x0B), d.scripts)
        self.assertIn(0x992A, d.entries)
        self.assertIn(0x997D, d.entries)
        # opcode $xF (end) has no operand: $424D, after one, is code only
        self.assertIn(0x424D, d.insns)
        self.assertNotIn(0x424D, d.script_bytes)
        # task references the CALLERS rule wants: script opcodes and LDX #
        self.assertIn(0x9453, d.refs[0x3176])             # opcode $F8
        self.assertIn(0x94C6, d.refs[0x3176])             # opcode $F7
        self.assertIn(0x63E8, d.refs[0x3495])             # LDX #$3495 / JSR $395E
        self.assertGreater(len(c3module.code_bytes(d.insns)), 20000)

    def test_sites(self):
        self.assertEqual(self.sites[0x3063], [0x3000])
        self.assertIn(0x3187, self.sites[0x377E])
        # the lint's sites include the script opcodes and LDX # task adds
        sites = lint_c3module.module_sites()
        self.assertIn(0x5B1D, sites[0x388B])              # opcode $F8: C3Mod_UploadPalette
        self.assertIn(0x5BA9, sites[0x34AB])              # LDX #$34AB / JSR $395E

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

    def isolated_root(self, tmp, case):
        root = Path(tmp)
        shutil.copytree('asm', root / 'asm', symlinks=True)
        (root / 'roms').mkdir()
        (root / 'roms' / 'chrono_trigger.sfc').symlink_to(c3pack.ROM_PATH.resolve())
        plant(root, case)
        return root

    @unittest.skipUnless(shutil.which('strace'), 'needs strace')
    def test_module_reads_rejected(self):
        # The module's ROM bytes read any other way than %C3ModRomBytes never
        # count as source: source_bytes() refuses (a read outside the copy,
        # or a symlink).
        for case in ('T2', 'T3', 'T5', 'T7', 'N1', 'N2', 'N3'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root = self.isolated_root(tmp, case)
                c3pack.build(root)
                with self.assertRaises(c3pack.PackError):
                    c3pack.source_bytes(root)

    def test_without_strace(self):
        # No strace: the isolated assembly still runs (a warning), unless
        # CHRONORET_REQUIRE_STRACE asks for the file-open check.
        import os
        from unittest import mock
        import isolated
        real_which = shutil.which
        no_strace = mock.patch.object(isolated.shutil, 'which',
                                      lambda n: None if n == 'strace' else real_which(n))
        with mock.patch.dict(os.environ, {isolated.REQUIRE_ENV: ''}):
            expected = c3pack.source_bytes()
            with no_strace:
                self.assertEqual(c3pack.source_bytes(), expected)
            self.assertEqual(isolated.run_mode(), 'none')      # the figures are unchecked
        with no_strace, mock.patch.dict(os.environ, {isolated.REQUIRE_ENV: '1'}):
            with self.assertRaises(c3pack.PackError):
                c3pack.source_bytes()
        isolated._modes.clear()

    def test_fingerprint_has_the_mode(self):
        # outputs made without the strace check are not current where it runs
        from unittest import mock
        import generated
        import isolated
        with mock.patch.object(isolated, 'expected_mode', lambda: 'strace'):
            a = generated.fingerprint()
        with mock.patch.object(isolated, 'expected_mode', lambda: 'none'):
            b = generated.fingerprint()
        self.assertNotEqual(a, b)

    @unittest.skipUnless(shutil.which('strace'), 'needs strace')
    def test_bank_read_rejected(self):
        import verify
        for case in ('T4b', 'N3c'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root = self.isolated_root(tmp, case)
                work = Path(tmp) / 'work'
                work.mkdir()
                with self.assertRaises(SystemExit):
                    verify.assemble_onto(0x00, work, root)


if __name__ == '__main__':
    unittest.main(verbosity=1)
