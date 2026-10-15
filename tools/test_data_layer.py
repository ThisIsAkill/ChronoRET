#!/usr/bin/env python3
"""
test_data_layer.py — Tests for the data layer: tools/extract_data.py, its
manifest (symbols/data_assets.csv), the lint's FILEREAD rule for asm/data/
and the isolated assembly of the whole ROM (tools/verify.py).

    python3 tools/test_data_layer.py          (from the repository root)

Without the ROM: the manifest is what the tool makes from the survey and
covers it exactly; a manifest edited by hand (a path out of build/assets/,
an added line) is refused; the lint refuses every planted file read in the
data layer but the manifest's own incbins (the ROM by a relative or an
absolute path, an asset the manifest does not list, a listed asset in the
wrong file or twice, a path built from a define, a range of a listed file).

With the ROM, asar and strace: asm/data/ is exactly what `generate` writes,
and the isolated assembly of asm/rom.asm refuses the same planted reads
(the file is not in the isolated tree, or strace sees asar open it outside).
"""

import contextlib
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_survey  # noqa: E402
import extract_data as ed  # noqa: E402

ROOT = ed.ROOT
HAVE_ROM = ed.ROM_PATH.exists()
HAVE_ASAR = shutil.which('asar') is not None
HAVE_STRACE = shutil.which('strace') is not None
NOT_LISTED = Path('build/assets/unknown/NotListed.bin')


def plants(root: Path) -> dict[str, tuple[str, str]]:
    """{case: (file under asm/, line to append)}: each a file read the data
    layer must refuse."""
    rom_abs = str(ed.ROM_PATH.resolve()) if HAVE_ROM else '/nonexistent/chrono_trigger.sfc'
    asset_abs = str((ROOT / ed.ASSETS / 'packed_lz' / 'C3Pack_000.bin').resolve())
    not_listed_abs = str((root / NOT_LISTED).resolve())
    return {
        'rom_relative': ('data/bankC3.asm', 'incbin "../../roms/chrono_trigger.sfc"'),
        'rom_absolute': ('data/bankC3.asm', f'incbin "{rom_abs}":0..16'),
        'not_listed': ('data/bankC3.asm', 'incbin "../../build/assets/unknown/NotListed.bin"'),
        'not_listed_absolute': ('data/bankC3.asm', f'incbin "{not_listed_abs}"'),
        'dotdot': ('data/bankC3.asm', 'incbin "../../build/assets/../../roms/chrono_trigger.sfc"'),
        'listed_absolute': ('data/bankC3.asm', f'incbin "{asset_abs}":0..16'),
        'listed_range': ('data/bankC3.asm', 'incbin "../../build/packs/C3Pack_000.lz":0..2'),
        'listed_twice': ('data/bankC3.asm', 'incbin "../../build/packs/C3Pack_000.lz"'),
        'listed_other_bank': ('data/bankC4.asm', 'incbin "../../build/packs/C3Pack_000.lz"'),
        'listed_in_code': ('bankC0/bankC0.asm', 'incbin "../../build/packs/C3Pack_000.lz"'),
        'define_path': ('data/bankC3.asm', '!p = "../../build/packs/C3Pack_000.lz"\nincbin "!p"'),
        'built_name': ('data/bankC3.asm', '!a = incbin\n!a!a'),
    }


def planted_tree(tmp: Path, case: str) -> Path:
    shutil.copytree(ROOT / 'asm', tmp / 'asm', symlinks=True)
    rel, line = plants(tmp)[case]
    path = tmp / 'asm' / rel
    path.write_text(path.read_text() + f'\norg $C3FFF0\n{line}\n')
    return tmp


class Manifest(unittest.TestCase):

    def test_manifest_is_the_tools(self):
        self.assertEqual(ed.manifest_problems(), [])

    def test_pieces_cover_the_survey(self):
        rows = data_survey.read_rows()
        pieces = ed.layout(rows)
        self.assertEqual(sum(int(p['size']) for p in pieces), sum(int(r['size']) for r in rows))
        ranges = [(p['offset'], p['stop']) for p in pieces]
        self.assertEqual(ranges, sorted(ranges))
        self.assertTrue(all(a[1] <= b[0] for a, b in zip(ranges, ranges[1:])))
        for p in pieces:
            if p['piece'] in ('extracted', 'packed'):
                self.assertRegex(p['asset'], ed.ASSET)
                self.assertNotIn('..', p['asset'])

    def test_hand_edits_refused(self):
        text = ed.MANIFEST.read_text()
        first = next(ln for ln in text.splitlines() if ',extracted,' in ln)
        edits = {
            'path_out': text.replace(first, first.replace(first.split(',')[5], '../../roms/chrono_trigger.sfc')),
            'added': text + 'Rom,$C0:0000,$C0:FFFF,65536,extracted,unknown/Rom.bin,\n',
            'renamed': text.replace(first, first.replace(first.split(',')[5],
                                                         first.split(',')[5].replace('.bin', 'X.bin'))),
        }
        for name, edited in edits.items():
            with self.subTest(edit=name), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / 'data_assets.csv'
                path.write_text(edited)
                self.assertTrue(ed.manifest_problems(path))

    def test_generated_without_rom(self):
        self.assertEqual(ed.generated_problems(None), [])


class Lint(unittest.TestCase):

    def test_the_data_layer_is_clean(self):
        import lint_readability as L
        self.assertEqual(L.file_read_findings(), [])

    def test_planted_reads_refused(self):
        import lint_readability as L
        for case in plants(ROOT):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root = planted_tree(Path(tmp), case)
                found = L.file_read_findings(root / 'asm')
                self.assertTrue(found, case)
                self.assertEqual({f[3] for f in found}, {'FILEREAD'})


@unittest.skipUnless(HAVE_ROM and HAVE_ASAR, 'needs the ROM and asar')
class WithRom(unittest.TestCase):

    def test_generated_is_current(self):
        self.assertEqual(ed.generated_problems(ed.read_rom()), [])

    @unittest.skipUnless(HAVE_STRACE, 'needs strace')
    def test_isolated_assembly_refuses(self):
        import isolated
        import verify
        import c3pack
        c3pack.ensure_built(ROOT)
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp) / 'clean'
            work.mkdir()
            verify.assemble_whole(0x00, 0xFF, work, ROOT)       # the tree as it is assembles
            self.assertEqual(isolated.run_mode(), 'strace')
        # The reads asar would perform (the define-built and range cases are
        # the lint's alone: asar reads the listed placeholder for those).
        # A path into the copy's absent build/ fails as a missing file; an
        # absolute path out of it is opened, and strace refuses it.
        expect = {'rom_relative': "wasn't found", 'dotdot': "wasn't found",
                  'not_listed': 'outside itself', 'not_listed_absolute': 'outside itself',
                  'rom_absolute': 'outside itself', 'listed_absolute': 'outside itself'}
        for case, why in expect.items():
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root = planted_tree(Path(tmp), case)
                # a real file where the non-listed path points, beside the copy
                fake = root / NOT_LISTED
                fake.parent.mkdir(parents=True)
                fake.write_bytes(b'\x01' * 16)
                work = Path(tmp) / 'work'
                work.mkdir()
                err = io.StringIO()
                with self.assertRaises(SystemExit), contextlib.redirect_stderr(err):
                    verify.assemble_whole(0x00, 0xFF, work, root)
                self.assertIn(why, err.getvalue())

if __name__ == '__main__':
    unittest.main(verbosity=1)
