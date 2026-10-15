#!/usr/bin/env python3
"""
test_data_layer.py — Tests for the data layer: tools/extract_data.py, its
manifest (symbols/data_assets.csv), the lint's FILEREAD rule for asm/data/
and the isolated assembly of the whole ROM (tools/verify.py), with the
encoded text pieces of tools/text.py among the files it lists.

    python3 tools/test_data_layer.py          (from the repository root)

Without the ROM: the manifest is what the tool makes from the survey and
covers it exactly; a manifest edited by hand (a path out of build/assets/,
an added line) is refused; the lint refuses every planted file read in the
data layer but the manifest's own incbins (the ROM by a relative or an
absolute path, an asset the manifest does not list, a listed asset in the
wrong file or twice, a path built from a define, a range of a listed file;
the same for the encoded text pieces, and the readable text itself, which
is never incbin'd).

With the ROM, asar and strace: asm/data/ is exactly what `generate` writes,
and the isolated assembly of asm/rom.asm refuses the same planted reads
(the file is not in the isolated tree, or strace sees asar open it outside);
a data-layer write over code bytes that keeps their values is found; an
asset, pack, readable text or encoded text piece changed by hand is redone
by the next build.
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
        'text_not_listed': ('data/bankDE.asm', 'incbin "../../build/text/NotListed.bin"'),
        'text_listed_twice': ('data/bankDE.asm', 'incbin "../../build/text/TextWin_DictPtrs.bin"'),
        'text_listed_other_bank': ('data/bankC4.asm', 'incbin "../../build/text/TextWin_DictPtrs.bin"'),
        'text_readable': ('data/bankDE.asm', 'incbin "../../build/assets/text/Dictionary.txt"'),
        'records_not_listed': ('data/bankCC.asm', 'incbin "../../build/records/NotListed.bin"'),
        'records_listed_twice': ('data/bankF6.asm', 'incbin "../../build/records/Table_F60000.bin"'),
        'records_listed_other_bank': ('data/bankC4.asm', 'incbin "../../build/records/Table_F60000.bin"'),
        'records_readable': ('data/bankF6.asm', 'incbin "../../build/assets/records/Table_F60000.tsv"'),
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
            if p['piece'] == 'text':
                self.assertRegex(p['asset'], ed.TEXT_ASSET)
            if p['piece'] == 'records':
                self.assertRegex(p['asset'], ed.RECORDS_ASSET)

    def test_hand_edits_refused(self):
        text = ed.MANIFEST.read_text()
        first = next(ln for ln in text.splitlines() if ',extracted,' in ln)
        words = next(ln for ln in text.splitlines() if ',text,' in ln)
        recs = next(ln for ln in text.splitlines() if ',records,' in ln and not ln.startswith("Table_F60000,"))
        edits = {
            'text_path_out': text.replace(words, words.replace(words.split(',')[5], 'text/../../../roms/x.txt')),
            'text_unknown_unit': text.replace(words, words.replace(words.split(',')[5], 'text/NoSuchUnit.txt')),
            'records_path_out': text.replace(recs, recs.replace(recs.split(',')[5], 'records/../../x.tsv')),
            'records_other_label': text.replace(recs, recs.replace(recs.split(',')[5], 'records/Table_F60000.tsv')),
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
                  'text_not_listed': "wasn't found", 'text_readable': "wasn't found",
                  'records_not_listed': "wasn't found", 'records_readable': "wasn't found",
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

    @unittest.skipUnless(HAVE_STRACE, 'needs strace')
    def test_data_write_over_code_refused(self):
        # A data-layer write over code bytes that keeps their values is
        # invisible in the whole ROM; the data layer assembled on its own
        # shows it (the four bytes are the ROM's at $C0:0010).
        import verify
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp) / 'clean'
            work.mkdir()
            self.assertEqual(verify.data_writes_outside(work, ROOT), [])
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / 'asm', root / 'asm', symlinks=True)
            bank = root / 'asm' / 'data' / 'bankDC.asm'
            bank.write_text(bank.read_text() + '\norg $C00010\n    db $C2,$10,$20,$64\n')
            work = root / 'work'
            work.mkdir()
            self.assertEqual(verify.data_writes_outside(work, root), [0x10, 0x11, 0x12, 0x13])

    def test_caches_repaired(self):
        # A byte of an asset or of a pack changed by hand is redone by the
        # next build, not kept because its stamp or key still matches.
        import build_rom
        rom = ed.read_rom()
        ed.extract()
        build_rom.build_packs()
        pieces = ed.read_manifest()
        raw = next(p for p in pieces if p['piece'] == 'extracted')
        packed = next(p for p in pieces if p['piece'] == 'packed')
        asset = ROOT / ed.ASSETS / raw['asset']
        lz = ROOT / ed.PACKS / f'{packed["label"]}.lz'
        words = next(p for p in pieces if p['piece'] == 'text')
        table = next(p for p in pieces if p['piece'] == 'records')
        readable_table = ROOT / ed.ASSETS / table['asset']
        encoded_table = ROOT / ed.RECORDS_OUT / f'{table["label"]}.bin'
        build_rom.build_records()
        kept_table = readable_table.read_text(encoding='utf-8')
        readable = ROOT / ed.ASSETS / words['asset']
        encoded = ROOT / ed.TEXT_OUT / f'{words["label"]}.bin'
        build_rom.build_text()
        kept = readable.read_text(encoding='utf-8')
        for path in (asset, lz, encoded, encoded_table):
            data = bytearray(path.read_bytes())
            data[0] ^= 0xFF
            path.write_bytes(bytes(data))
        readable.write_text(kept.replace('@piece', '; @piece', 1), encoding='utf-8')
        readable_table.write_text(kept_table.replace('Index', 'Indx', 1), encoding='utf-8')
        ed.extract()
        build_rom.build_packs()
        build_rom.build_text()
        build_rom.build_records()
        self.assertEqual(asset.read_bytes(), rom[raw['offset']:raw['stop']])
        self.assertEqual(lz.read_bytes(), rom[packed['offset']:packed['stop']])
        self.assertEqual(readable.read_text(encoding='utf-8'), kept)
        self.assertEqual(encoded.read_bytes(), rom[words['offset']:words['stop']])
        self.assertEqual(readable_table.read_text(encoding='utf-8'), kept_table)
        self.assertEqual(encoded_table.read_bytes(), rom[table['offset']:table['stop']])


if __name__ == '__main__':
    unittest.main(verbosity=1)
