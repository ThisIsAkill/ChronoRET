#!/usr/bin/env python3
"""
test_scripts.py — Tests for tools/scripts.py (the scene and layer-effect
scripts' readable forms).

    python3 tools/test_scripts.py          (from the repository root)

Without the ROM: the disassembler and the assembler on a synthetic scene
pack and a synthetic fx table and scripts, with stub interpreters (next,
stay, a branch, a jump, a call and its return, a spawn, the end; pages,
$7F and $FF), the jump encodings found by changing the bytes, and every
refusal of tools/scripts.py (each one has a test that fails without it):
the structure, the lines, the outcomes a handler may not have, a callee
not followed and not trusted, the entries a scene's lists give and the fx
table's words, the header table's pairs from the build's own inputs, the
trace file's checks; the manifest's scene and fx pieces.

With asar (the code image): the trusted routines' code has no direct
store to what they are trusted to leave alone.

With the ROM and asar: every scene pack and the fx scripts disassemble and
assemble back byte-exact, the opcodes classed return, ram and done are the
known ones, and the trusted routines are exactly the ones the data needs.
"""

import hashlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_data as ed  # noqa: E402
import scripts  # noqa: E402

HAVE_ASAR = shutil.which('asar') is not None
HAVE_ROM = ed.ROM_PATH.exists() and HAVE_ASAR


def _sext(b):
    return b - 256 if b >= 0x80 else b


class SceneStub(scripts.SceneLang):
    """$00 next 1; $02 n next 2; $1A w jump to w + 1; $1C t o branch by o
    (else next 3); $36 w call w (back at +3); $37 return; $38 n wait (stay,
    then next 2); $09 w b spawn w in bank b (next 4); $52 done; $3E next
    2 after a callee not followed ($C2:0E1D, C2Anim_Run's address here);
    $34 w next 3 after calling w ($C2:1819 not followed)."""

    def __init__(self, labels=None):
        self.name, self.count = 'scene', 0x53
        self.names = [f'Op{op:02X}_Stub' for op in range(self.count)]
        self.cache, self.specs, self.dirty = {}, {}, False
        self.labels = labels or {}

    def _trace(self, known, ptr):
        op = known[ptr]

        def pos(d, t=False, taint=(), ret=None, new=None):
            return ('pos', d, t, taint, ret, new)
        if op == 0x00:
            outs, reads = [pos(1)], []
        elif op == 0x02:
            outs, reads = [pos(2)], [1]
        elif op == 0x1A:
            t = (ptr & 0xFF0000) | (known[ptr + 1] | known[ptr + 2] << 8) + 1
            outs, reads = [pos(t - ptr, True, (1, 2), None, t)], [1, 2]
        elif op == 0x1C:
            o = _sext(known[ptr + 2])
            outs = [pos(3)] + ([pos(o, True, (2,), None, ptr + o)] if o else [pos(0)])
            reads = [1, 2]
        elif op == 0x36:
            t = (ptr & 0xFF0000) | known[ptr + 1] | known[ptr + 2] << 8
            outs, reads = [pos(t - ptr, True, (1, 2), 3, t)], [1, 2]
        elif op == 0x37:
            outs, reads = [('return',)], []
        elif op == 0x38:
            outs, reads = [pos(0), pos(2)], [1]
        elif op == 0x09:
            outs = [pos(4), ('spawn', None, None, (1, 2, 3), (1, 2), (3,))]
            reads = [1, 2, 3]
        elif op == 0x52:
            outs, reads = [('done',)], []
        elif op == 0x01:
            return {'reads': [], 'control': [], 'outs': [('ram', True)], 'opaque': [(0xC0FFEE, 'why')], 'chains': []}
        elif op == 0x03:
            outs, reads = [pos(2), pos(3, True, (2,), None, ptr + 3)], [1, 2]
        elif op == 0x04:
            outs, reads = [pos(2), ('spawn', None, None, (1,), (1,), ())], [1]
        elif op == 0x05:
            outs, reads = [pos(3, True, (1,), None, ptr + 3), pos(4, True, (1,), None, ptr + 4)], [1]
        elif op == 0x06:
            outs, reads = [pos(8, True, (1,), None, ptr + 8)], [1]
        elif op == 0x08:
            outs, reads = [pos(3, True, (1,), 3, ptr + 3), pos(4, True, (1,), 3, ptr + 4)], [1]
        elif op == 0x3E:
            return {'reads': [1], 'control': [], 'outs': [pos(2)], 'opaque': [(0xC20E1D, 'an indirect call')],
                    'chains': [(0xC20E1D,)]}
        elif op == 0x34:
            return {'reads': [1, 2], 'control': [1, 2], 'outs': [pos(3)], 'opaque': [(0xC70004, 'too long')],
                    'chains': [(0xC21819, 0xC70004)]}
        else:
            outs, reads = [('bad', 'not in the stub')], []
        return {'reads': reads, 'control': reads, 'outs': outs, 'opaque': []}


B = 0x7F0400
PACK = bytes([0x09, 0x20, 0x04, 0x7F,        # $0400 spawn $0420
              0x36, 0x10, 0x04,              # $0404 call $0410
              0x1C, 0x05, 0x06,              # $0407 branch to $040D
              0x38, 0x10,                    # $040A wait
              0x52,                          # $040C done
              0x1A, 0x0F, 0x04,              # $040D jump to $0410
              0x02, 0x01,                    # $0410 the called part
              0x37,                          # $0412 return
              0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,  # data
              0x02, 0x05,                    # $0420 the spawned script
              0x52])
ENTRIES = {B}


def scene_text():
    return scripts.render_scene(SceneStub(), 'Pack', PACK, ENTRIES)


def assemble_scene(text, entries=ENTRIES):
    return scripts.assemble_scene(SceneStub(), text, 'Pack', len(PACK), entries, 'pack.scn')


class Scene(unittest.TestCase):

    def test_round_trip(self):
        text = scene_text()
        self.assertEqual(assemble_scene(text), PACK)
        self.assertIn('    Op09_Stub ->L_0420 $7F', text)
        self.assertIn('    Op36_Stub ->L_0410', text)
        self.assertIn('    Op1C_Stub $05 ->L_040D', text)
        self.assertIn('    Op1A_Stub ->L_0410', text)
        self.assertIn('@jump Op1A_Stub word 1 - 1', text)       # found by changing the bytes
        self.assertIn('@jump Op1C_Stub byte 2 sext 0', text)
        self.assertIn('@bytes AA BB CC DD EE FF 11 22 33 44 55 66 77', text)

    def refused(self, old, new, why):
        text = scene_text()
        self.assertIn(old, text)
        with self.assertRaisesRegex(scripts.ScriptsError, why):
            assemble_scene(text.replace(old, new, 1))

    def test_unreached_opcode_line_refused(self):
        self.refused('@bytes AA BB CC DD EE FF 11 22 33 44 55 66 77',
                     '    Op02_Stub $BB\n@bytes CC DD EE FF 11 22 33 44 55 66 77', 'nothing reaches')

    def test_reached_bytes_as_data_refused(self):
        self.refused('    Op52_Stub\nL_040D:', '@bytes 52\nL_040D:', 'is reached')

    def test_regrouped_operands_refused(self):
        self.refused('    Op38_Stub $10\n    Op52_Stub', '    Op38_Stub\n    Op10_Stub $52', 'takes 2 bytes')

    def test_wrong_jump_encoding_refused(self):
        self.refused('@jump Op1C_Stub byte 2 sext 0', '@jump Op1C_Stub byte 2 sext 3', 'not its encoding')

    def test_jump_to_a_missing_label_refused(self):
        text = scene_text().replace('    Op1C_Stub $05 ->L_040D', '    Op1C_Stub $05 ->L_FAR')
        text = text.replace('L_0420:', 'L_0420:') + ''
        text = text.replace('@region Pack $7F0400', '@region Pack $7F0400')
        lines = text.split('\n')
        with self.assertRaisesRegex(scripts.ScriptsError, 'no label L_FAR'):
            assemble_scene('\n'.join(lines))

    def test_wrong_spawn_operand_refused(self):
        self.refused('@spawn Op09_Stub 1 3', '@spawn Op09_Stub 2 3', 'script address is operand 2')

    def test_wrong_spawn_bank_operand_refused(self):
        self.refused('@spawn Op09_Stub 1 3', '@spawn Op09_Stub 1 2', "@spawn line is not where")

    def test_spawn_written_as_bytes_refused(self):
        self.refused('    Op09_Stub ->L_0420 $7F', '    Op09_Stub $20 $04 $7F', 'script address is written as bytes')

    def test_jump_written_as_bytes_refused(self):
        self.refused('    Op1A_Stub ->L_0410', '    Op1A_Stub $0F $04', 'target is written as bytes')

    def test_inner_line_must_share_the_bytes(self):
        self.refused('    Op38_Stub $10\n', '    Op38_Stub $10\n    @inner +1 L_X Op02_Stub $52\n',
                     'not the bytes it shares')

    def test_bad_byte_is_a_scripts_error(self):
        self.refused('    Op38_Stub $10', '    Op38_Stub $1000', 'not a \\$XX byte')

    def test_bad_number_is_a_scripts_error(self):
        self.refused('@jump Op1C_Stub byte 2 sext 0', '@jump Op1C_Stub byte two sext 0', 'not a number')

    def test_entries_must_be_the_lists(self):
        text = scene_text()
        with self.assertRaisesRegex(scripts.ScriptsError, 'missing L_0420'):
            assemble_scene(text, {B, B + 0x20})
        with self.assertRaisesRegex(scripts.ScriptsError, 'not one: L_0420'):
            assemble_scene(text.replace('@region', '@entry L_0420\n@region', 1))
        self.assertEqual(assemble_scene(text.replace('@region', '@entry L_0420\n@region', 1), {B, B + 0x20}),
                         PACK)

    def test_jump_to_another_bank_refused(self):
        lines = [('x:1', ['@jump', 'Op1A_Stub', 'word', '1', '-', '1']), ('x:2', ['@region', 'A', '$7F0400']),
                 ('x:3', ['Op1A_Stub', '->L_B']), ('x:4', ['@region', 'B', '$7E0000']), ('x:5', ['L_B:']),
                 ('x:6', ['Op00_Stub'])]
        with self.assertRaisesRegex(scripts.ScriptsError, 'L_B is in another bank'):
            scripts.assemble_body(SceneStub(), lines, {'A': (0x7F0400, 3), 'B': (0x7E0000, 1)}, 'x')

    def test_entry_needs_a_label(self):
        text = scene_text().replace('@region', '@entry L_NONE\n@region', 1)
        with self.assertRaisesRegex(scripts.ScriptsError, 'a label of the pack'):
            assemble_scene(text)

    def test_call_goes_on_only_when_it_returns(self):
        # the called part ends instead of returning: the bytes after the
        # call are no longer reached (they must be data)
        pack = bytearray(PACK)
        pack[0x12] = 0x52
        d = scripts.disassemble(SceneStub(), {B + i: v for i, v in enumerate(pack)},
                                [(B, B + len(pack))], ENTRIES)
        self.assertNotIn(B + 7, d['ops'])
        self.assertIn(B + 4, d['ops'])

    def test_exits(self):
        d = scripts.disassemble(SceneStub(), {B + i: v for i, v in enumerate(PACK)}, [(B, B + len(PACK))],
                                ENTRIES)
        self.assertEqual({o.op for o in d['ops'].values() if o.ret}, {0x37})
        self.assertEqual({o.op for o in d['ops'].values() if o.done}, {0x52})

    def test_malformed_lines_refused(self):
        for old, new, why in (
                ('@jump Op1C_Stub byte 2 sext 0', '@jump Op1C_Stub byte 2', '@jump NAME word'),
                ('@spawn Op09_Stub 1 3', '@spawn Op09_Stub 1', '@spawn NAME J B'),
                ('@region Pack $7F0400', '@region Pack $7F0401', '@region LABEL'),
                ('@region Pack $7F0400', 'Op00_Stub\n@region Pack $7F0400', 'outside a @region'),
                ('L_0410:', 'L_0410:\nL_0410:', 'label L_0410 twice'),
                ('    Op38_Stub $10\n', '    Op38_Stub $10\n    @inner +1\n', '@inner \\+K LABEL'),
                ('    Op38_Stub $10\n', '    Op38_Stub $10\n    @inner 1 L_X Op10_Stub\n', '@inner \\+K LABEL'),
                ('    Op1A_Stub ->L_0410\n', '    Op1A_Stub ->L_0410\n    @inner +1 L_040D Op0F_Stub\n',
                 'label L_040D twice'),
                ('    Op52_Stub', '    OpZZ_Stub', 'unknown opcode OpZZ_Stub'),
                ('@jump Op1A_Stub word 1 - 1\n', '', 'Op1A_Stub has no @jump line'),
                ('@jump Op1A_Stub word 1 - 1', '@jump Op1A_Stub word 2 - 1', "Op1A_Stub's target is operand 2"),
                ('@bytes AA BB', '@bytes AA BBB', '@bytes takes XX bytes'),
                ('@scene Pack $7F0400', '@scene Other $7F0400', 'the first line is @scene Pack'),
                ('@bytes AA BB', '@bytes AA', '34 bytes; Pack is 35')):
            with self.subTest(new=new):
                self.refused(old, new, why)

    def test_jump_out_of_reach_refused(self):
        lines = [('x:1', ['@jump', 'Op1C_Stub', 'byte', '2', 'sext', '0']), ('x:2', ['@region', 'A', '$7F0400']),
                 ('x:3', ['Op1C_Stub', '$05', '->L_FAR'])] + [('x:4', ['@bytes', '00'])] * 200 + [
                 ('x:5', ['L_FAR:']), ('x:6', ['Op00_Stub'])]
        with self.assertRaisesRegex(scripts.ScriptsError, "L_FAR is out of the jump's reach"):
            scripts.assemble_body(SceneStub(), lines, {'A': (0x7F0400, 204)}, 'x')

    def test_outcomes_refused(self):
        for op, why in ((0x07, 'not in the stub'), (0x01, 'depends on a callee'),
                        (0x03, 'goes on at \\+2 and \\+3'), (0x04, 'no operand word'),
                        (0x05, '2 computed targets'), (0x06, 'no word or byte of its operands')):
            with self.subTest(op=op):
                with self.assertRaisesRegex(scripts.ScriptsError, why):
                    scripts.classify(SceneStub(), {B + i: v for i, v in enumerate([op, 0x10, 0, 0, 0])}, B)

    def test_two_call_targets_refused(self):
        lang = SceneStub()
        lang.specs[0x08] = ('byte', 1, 'add', 0)
        with self.assertRaisesRegex(scripts.ScriptsError, 'two call targets'):
            scripts.classify(lang, {B + i: v for i, v in enumerate([0x08, 0x10, 0, 0, 0])}, B)

    def test_flow_leaving_the_pack_refused(self):
        pack = bytearray(PACK)
        pack[0x0E] = 0x60                                       # $1A jumps to $0461, past the pack
        with self.assertRaisesRegex(scripts.ScriptsError, 'outside the scripts'):
            scripts.disassemble(SceneStub(), {B + i: v for i, v in enumerate(pack)}, [(B, B + len(pack))],
                                ENTRIES)
        pack = bytearray(PACK)
        pack[-1] = 0x02                                         # the last opcode needs a byte more
        with self.assertRaisesRegex(scripts.ScriptsError, 'run past the scripts'):
            scripts.disassemble(SceneStub(), {B + i: v for i, v in enumerate(pack)}, [(B, B + len(pack))],
                                ENTRIES)

    def test_trace_file_checked(self):
        lang = SceneStub()
        lang.code_key = 'x'
        lang.cache = {0x02: {((False, 1),): {(5,): {'reads': [1], 'control': [], 'outs': [], 'opaque': []}}}}
        lang.dirty = True
        with tempfile.TemporaryDirectory() as tmp:
            lang.save(tmp)
            data_f, key_f, _ = lang._trace_files(Path(tmp))
            fresh = SceneStub()
            fresh.code_key = 'x'
            fresh.load(tmp)
            self.assertEqual(fresh.cache[0x02][((False, 1),)][(5,)]['reads'], [1])
            data_f.write_bytes(data_f.read_bytes().replace(b'[1]', b'[2]'))
            with self.assertRaisesRegex(scripts.ScriptsError, 'changed by hand'):
                fresh.load(tmp)
            raw = b'{"cache": 5}'
            data_f.write_bytes(raw)
            key_f.write_text(key_f.read_text().split()[0] + ' ' + hashlib.sha256(raw).hexdigest())
            with self.assertRaisesRegex(scripts.ScriptsError, 'not a trace file'):
                fresh.load(tmp)


class Trust(unittest.TestCase):
    """A callee the interpreter cannot follow is refused unless TRUST
    names the routine it is in (or, through C2Script_CallNear, the routine
    the operand calls)."""

    KNOWN = {B: 0x3E, B + 1: 0x00, B + 2: 0x34, B + 3: 0x00, B + 4: 0x00, B + 5: 0x52}

    def test_untrusted_callee_refused(self):
        with self.assertRaisesRegex(scripts.ScriptsError, 'no reason in TRUST'):
            scripts.classify(SceneStub(), self.KNOWN, B)

    def test_trusted_callee(self):
        o = scripts.classify(SceneStub({'C2Anim_Run': 0xC20E1D}), self.KNOWN, B)
        self.assertEqual((o.length, o.trusted), (2, {'C2Anim_Run'}))

    def test_call_trusted_by_its_target(self):
        labels = {'C2Script_CallNear_call': 0xC21819, 'C2Scene_ZoneSoundAtEntry': 0xC21234}
        known = dict(self.KNOWN)
        known[B + 3], known[B + 4] = 0x34, 0x12
        self.assertEqual(scripts.classify(SceneStub(labels), known, B + 2).trusted, {'C2Scene_ZoneSoundAtEntry'})
        known[B + 3] = 0x35                                     # another target: not trusted
        with self.assertRaisesRegex(scripts.ScriptsError, 'no reason in TRUST'):
            scripts.classify(SceneStub(labels), known, B + 2)


class Pairs(unittest.TestCase):
    """Which list pack goes with which script pack, from the header table."""

    @staticmethod
    def headers(ptrs, hdrs):
        out = bytearray()
        for p in ptrs:
            out += p.to_bytes(2, 'little')
        for li, si in hdrs:
            h = bytearray(23)
            h[0x15], h[0x16] = li, si
            out += h
        return bytes(out)

    def test_table_ends_at_the_first_header(self):
        # two words, then the headers: what follows the table is no entry
        hdr = self.headers([0xFD04, 0xFD1B], [(1, 0), (0x80, 1)])
        got = scripts._pairs(hdr, 0xC6FD00, lambda i: bytes([i]), scripts.ROOT)
        self.assertEqual(got, {0: bytes([1])})                  # bit 7: no list pack

    def test_header_outside_the_piece_refused(self):
        hdr = self.headers([0xFD04, 0xFF00], [(1, 0)])
        with self.assertRaisesRegex(scripts.ScriptsError, "scene 1's header \\$C6FF00 is not in the table"):
            scripts._pairs(hdr, 0xC6FD00, lambda i: b'', scripts.ROOT)
        with self.assertRaisesRegex(scripts.ScriptsError, 'no header inside the table piece'):
            scripts._pairs(bytes([0x40, 0xFD, 0x40]), 0xC6FD00, lambda i: b'', scripts.ROOT)

    def test_built_pairs_from_the_build_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(scripts.ScriptsError, 'bankC6.asm'):
                scripts.scene_pairs_built(root)                 # no asm/data, no assets
            (root / 'asm' / 'data').mkdir(parents=True)
            shutil.copytree(scripts.ROOT / 'asm' / 'include', root / 'asm' / 'include')   # the header offsets
            src = root / 'asm' / 'data' / 'bankC6.asm'
            src.write_text('C2SceneRom_ListPacksX:\n')
            with self.assertRaisesRegex(scripts.ScriptsError, 'no C2SceneRom_ListPacks table'):
                scripts.scene_pairs_built(root)
            src.write_text('C2SceneRom_ListPacks:\n    dl SceneScriptPack_000\n    dl SceneListPack_001\n'
                           '    dl $000000\n')
            with self.assertRaisesRegex(scripts.ScriptsError, 'C2SceneRom_HeaderTable: .*No such file'):
                scripts.scene_pairs_built(root)
            assets = root / ed.ASSETS
            (assets / 'table').mkdir(parents=True)
            (assets / 'table' / 'C2SceneRom_HeaderTable.bin').write_bytes(
                self.headers([0xFD06, 0xFD1D, 0xFD34], [(0, 0), (1, 1), (2, 2)]))
            with self.assertRaisesRegex(scripts.ScriptsError, 'SceneScriptPack_000 is not a packed piece'):
                scripts.scene_pairs_built(root)
            src.write_text('C2SceneRom_ListPacks:\n    dl $000000\n    dl SceneListPack_001\n    dl $000000\n')
            with self.assertRaisesRegex(scripts.ScriptsError, 'SceneListPack_001: .*No such file'):
                scripts.scene_pairs_built(root)
            (assets / 'packed_lz').mkdir()
            (assets / 'packed_lz' / 'SceneListPack_001.bin').write_bytes(b'lists')
            self.assertEqual(scripts.scene_pairs_built(root), {1: b'lists'})


class FxStub(scripts.FxLang):
    """Bytes below $80 and $7F: next 1; $FF done; $81 n next 2; $91 w call
    w (DP $40 = w - 1; back at +3); $92 return."""

    def __init__(self):
        self.name, self.first, self.count = 'fx', 0x80, 0xFA
        self.names = [None] * 256
        for op in range(0x80, 0xFA):
            self.names[op] = f'Op{op:02X}_Stub'
        self.no_page, self.end = 0x7F, 0xFF
        self.cache, self.specs, self.dirty = {}, {}, False

    def head(self):
        return 1

    def _trace(self, known, ptr):
        op = known[ptr]
        if op < 0x80:
            outs, reads = [('pos', 1, False, (), None, None)], []
        elif op == 0xFF:
            outs, reads = [('done',)], []
        elif op == 0x81:
            outs, reads = [('pos', 2, False, (), None, None)], [1]
        elif op == 0x91:
            t = (ptr & 0xFF0000) | known[ptr + 1] | known[ptr + 2] << 8
            outs, reads = [('pos', t - ptr, True, (1, 2), 3, t)], [1, 2]
        elif op == 0x92:
            outs, reads = [('return',)], []
        else:
            outs, reads = [('bad', 'not in the stub')], []
        return {'reads': reads, 'control': [], 'outs': outs, 'opaque': []}


FX = 0xD10000
FXDATA = bytes([0x08, 0x00, 0x10, 0x00, 0x30, 0x00, 0x30, 0x00])   # $D1:0000: four entries: $0008, $0010, $0030 twice
FXDATA += bytes([0x03, 0x12, 0x7F, 0x91, 0x14, 0x00, 0xFF, 0x99])   # $0008: head, page, no page, call, end, data
FXDATA += bytes([0x01, 0x81, 0x04, 0xFF, 0x81, 0x02, 0x92])         # $0010: head, op, end; $0014 the called part
FXDATA += bytes([0x00]) * 9


def fx_text():
    return scripts.render_fx(FxStub(), 'FxTab', FX, FXDATA)


def assemble_fx(text):
    return scripts.assemble_fx(FxStub(), text, 'FxTab', FX, len(FXDATA), 'fx.bfx')


class Fx(unittest.TestCase):

    def test_round_trip(self):
        text = fx_text()
        self.assertEqual(assemble_fx(text), FXDATA)
        self.assertIn('@entry 2 $0030', text)                   # past the scripts: its word
        self.assertIn('F_D10008:\n    @head $03\nL_D10009:\n    Page $12\n    NoPage\n    Op91_Stub ->L_D10014',
                      text)

    def refused(self, old, new, why):
        text = fx_text()
        self.assertIn(old, text)
        with self.assertRaisesRegex(scripts.ScriptsError, why):
            assemble_fx(text.replace(old, new, 1))

    def test_entry_to_code_refused(self):
        self.refused('@entry 0 F_D10008', '@entry 0 L_D10009', 'not a script')

    def test_entry_word_of_a_script_refused(self):
        self.refused('@entry 0 F_D10008', '@entry 0 $0008', 'inside the scripts')

    def test_entry_word_inside_the_scripts_refused(self):
        self.refused('@entry 0 F_D10008', '@entry 0 $0009', 'inside the scripts')

    def test_head_no_entry_names_refused(self):
        self.refused('@entry 1 F_D10010', '@entry 1 $0030', 'a @head line no entry names')

    def test_malformed_lines_refused(self):
        for old, new, why in (
                ('@table FxTab $D10000', '@table FxTab $D10001', 'the first line is @table FxTab'),
                ('@entry 0 F_D10008', '@entry 1 F_D10008', '@entry I TARGET, in order'),
                ('@entry 0 F_D10008', '@entry 0 F_NONE', 'no label F_NONE'),
                ('@bytes 99\n', '', 'the scripts are 23 bytes; they are 24'),
                ('    NoPage', '    NoPage $12', 'NoPage takes no operand')):
            with self.subTest(new=new):
                self.refused(old, new, why)

    def test_head_must_be_one_offset(self):
        class Machine:
            @staticmethod
            def run(s, known):
                return []                                       # no way that sets the pointer
        lang = FxStub()
        lang.labels, lang.d, lang.chan, lang.machine = {'BattleCD_StartFxChannel': 0}, {scripts.FX_TABLE: 0}, 0, \
            Machine()
        with self.assertRaisesRegex(scripts.ScriptsError, 'no one start offset'):
            scripts.FxLang.head(lang)

    def test_table_must_end_at_the_first_script(self):
        data = bytearray(FXDATA)
        data[0] = 0x09
        with self.assertRaisesRegex(scripts.ScriptsError, 'the table does not end where the first script starts'):
            scripts.render_fx(FxStub(), 'FxTab', FX, bytes(data))

    def test_call_into_a_head_refused(self):
        self.refused('    Op91_Stub ->L_D10014', '    Op91_Stub ->F_D10010', "runs into a script's head")

    def test_page_must_be_a_page(self):
        self.refused('    Page $12', '    Page $80', 'page byte below')

    def test_data_after_end_is_data(self):
        self.refused('@bytes 99', '    Page $19', 'nothing reaches')


class AnimStub(scripts.AnimLang):
    """$00 n: next 2 (writes the record byte n); $07: stay."""

    def __init__(self):
        self.name, self.count, self.timer = 'anim', 8, 0x0E
        self.names = [f'Op{op:02X}_Stub' for op in range(8)]
        self.cache, self.specs, self.dirty = {}, {}, False
        self.labels = {}

    def _trace(self, known, ptr):
        op = known[ptr]
        if op == 0x00:
            return {'reads': [1], 'control': [], 'outs': [('pos', 2, False, (), None, None)], 'opaque': []}
        if op == 0x07:
            return {'reads': [], 'control': [], 'outs': [('pos', 0, False, (), None, None)], 'opaque': []}
        return {'reads': [], 'control': [], 'outs': [('bad', 'not in the stub')], 'opaque': []}


class AnimFrameStub(scripts.AnimLang):
    """$00 n: next 2; $04 lo hi t: ShowFrame, next 4; $07: stay."""

    def __init__(self):
        self.name, self.count, self.timer = 'anim', 8, 0x0E
        self.names = [f'Op{op:02X}_Stub' for op in range(8)]
        self.handler_names = [f'C2Anim_H{op}' for op in range(8)]
        self.handler_names[4] = 'C2Anim_OpShowFrame'
        self.cache, self.specs, self.dirty = {}, {}, False
        self.labels = {}

    def head(self):
        return 0

    def _trace(self, known, ptr):
        n = {0x00: 2, 0x04: 4, 0x07: 0}.get(known[ptr])
        if n is None:
            return {'reads': [], 'control': [], 'outs': [('bad', 'not in the stub')], 'opaque': []}
        return {'reads': list(range(1, n)), 'control': [], 'outs': [('pos', n, False, (), None, None)],
                'opaque': []}


AN = 0xC30000
ANDATA = bytes([0x04, 0x00, 0x05, 0x00])                       # entries $0004, $0005 (inside the first op)
ANDATA += bytes([0x00, 0x07])                                   # $0004: op 0 $07 ($0005: the stay as an entry)
ANDATA += bytes([0x04, 0x12, 0x00, 0x08, 0x07])                 # $0006: ShowFrame $0012 8, stay
ANDATA += bytes([0x04, 0x17, 0x00, 0x02, 0x07])                 # $000B: ShowFrame $0017 (not reached: data)
ANDATA += bytes([0x99, 0x99])                                   # $0010 data
ANDATA += bytes([0x01, 0xF8, 0x10, 0x34, 0x12])                 # $0012: a frame of one piece
ANDATA += bytes([0x01, 0x00, 0x00, 0x00, 0x00])                 # $0017: a frame no reached op names


def anim_text():
    return scripts.render_fx(AnimFrameStub(), 'AnTab', AN, ANDATA)


class Anim(unittest.TestCase):

    def test_round_trip(self):
        text = anim_text()
        self.assertEqual(scripts.assemble_fx(AnimFrameStub(), text, 'AnTab', AN, len(ANDATA)), ANDATA)
        self.assertIn('    @frame -8,16:1234\n', text)
        self.assertIn('@entry 1 L_C30005', text)                # an entry inside an opcode: its @inner label
        self.assertEqual(scripts.stats(text)['frames'], 5)
        self.assertIn('scene animation scripts', text)

    def refused(self, old, new, why):
        text = anim_text()
        self.assertIn(old, text)
        with self.assertRaisesRegex(scripts.ScriptsError, why):
            scripts.assemble_fx(AnimFrameStub(), text.replace(old, new, 1), 'AnTab', AN, len(ANDATA))

    def test_frame_refusals(self):
        self.refused('    @frame -8,16:1234', '@bytes 01 F8 10 34 12', 'a ShowFrame names a frame here')
        self.refused('    @frame -8,16:1234', '    @frame -8,16:12345', 'bad frame piece')
        self.refused('    @frame -8,16:1234', '    @frame -129,16:1234', 'bad frame piece')
        self.refused('    @frame -8,16:1234', '    @frame -8,16', 'bad frame piece')
        self.refused('    @frame -8,16:1234', '    @frame', '@frame takes 1-255 pieces')
        self.assertIn('@bytes 01 00 00 00 00', anim_text())

    def test_frame_no_op_names_refused(self):
        text = anim_text()
        lines = text.splitlines()
        k = max(i for i, x in enumerate(lines) if x.startswith('@bytes'))
        lines[k:] = ['    @frame 0,0:0000 0,0:0000']
        new = '\n'.join(lines) + '\n'
        with self.assertRaisesRegex(scripts.ScriptsError, 'no ShowFrame names an @frame here|the scripts are'):
            scripts.assemble_fx(AnimFrameStub(), new, 'AnTab', AN, len(ANDATA))

    def test_entry_to_data_refused(self):
        text = anim_text().replace('@bytes 04 17 00 02 07 99 99', 'D_X:\n@bytes 04 17 00 02 07 99 99', 1)
        text = text.replace('@entry 1 L_C30005', '@entry 1 D_X')
        with self.assertRaisesRegex(scripts.ScriptsError, 'D_X is not a script'):  # ... but no entry names it
            scripts.assemble_fx(AnimFrameStub(), text, 'AnTab', AN, len(ANDATA))

    def test_frames_found(self):
        lang = AnimFrameStub()
        known = {AN + i: b for i, b in enumerate(ANDATA)}
        d = scripts._fx_disassembly(lang, AN, ANDATA)
        self.assertEqual(scripts.anim_frames(lang, d, known, (AN + 4, AN + len(ANDATA))), {AN + 0x12: 5})
        self.assertEqual(scripts.anim_frames(lang, d, known, (AN + 4, AN + 0x15)), {})       # runs past the region
        zero = {**known, AN + 0x12: 0}
        self.assertEqual(scripts.anim_frames(lang, d, zero, (AN + 4, AN + len(ANDATA))), {})
        over = {**known, AN + 7: 0x05}                    # the frame at $0005 would overlap the opcodes
        d2 = scripts._fx_disassembly(lang, AN, bytes(over[AN + i] for i in range(len(ANDATA))))
        self.assertEqual(scripts.anim_frames(lang, d2, over, (AN + 4, AN + len(ANDATA))), {})

    def test_overlapping_frames_stay_bytes(self):
        data = bytearray(ANDATA)
        data[0x0A] = 0x00                                       # the stay becomes op 0 $04: ShowFrame at $000C ...
        data[0x0B:0x11] = bytes([0x04, 0x04, 0x17, 0x00, 0x07, 0x07])  # ... naming $0017, then stay
        data[0x12] = 0x02                                       # $0012's frame now runs over $0017's
        lang = AnimFrameStub()
        known = {AN + i: b for i, b in enumerate(data)}
        d = scripts._fx_disassembly(lang, AN, bytes(data))
        frames = scripts.anim_frames(lang, d, known, (AN + 4, AN + len(data)))
        self.assertEqual(frames, {})

    def test_head_must_be_one_offset(self):
        class Machine:
            @staticmethod
            def run(s, known):
                return []
        lang = AnimFrameStub()
        lang.labels, lang.d, lang.machine = {'C2Scene_SetAnim': 0}, {'C2SceneRom_AnimTable': 0xC3E000,
                                                                        'C2Scene_TaskCur': 0x0D}, Machine()
        lang.task, lang.root = 0x1000, scripts.ROOT
        with self.assertRaisesRegex(scripts.ScriptsError, 'C2Scene_SetAnim: no one start offset'):
            scripts.AnimLang.head(lang)


class Locks(unittest.TestCase):
    """The checks behind TRUST's reasons: the static scan at every width,
    the animation ops' record bytes, the unpackers' room."""

    def test_closure_scans_each_width(self):
        class Image:
            image = bytearray(0x400000)
        lang = Image()
        lang.image[0x8000:0x800B] = bytes([0xC2, 0x20, 0x20, 0x10, 0x80, 0xE2, 0x20, 0x20, 0x10, 0x80, 0x60])
        lang.image[0x8010:0x8015] = bytes([0xA9, 0x00, 0x85, 0x58, 0x60])  # M=1: LDA #0, STA $58; M=0: LDA #$8500, CLI
        got = scripts._code_closure(lang, [(0xC08000, True)])
        self.assertIn((0xC08010, 'LDA', 'imm_m', 0x8500), got)
        self.assertIn((0xC08010, 'LDA', 'imm_m', 0x00), got)
        self.assertIn((0xC08012, 'STA', 'dp', 0x58), got)

    def test_anim_op_naming_a_guarded_byte_refused(self):
        lang = AnimStub()
        guard = {5, 6, 7, 8, 9, 0x0E}
        bad = [('S', {B: 0x00, B + 1: 0x06, B + 2: 0x07}, (B, B + 3), {B})]
        self.assertEqual(scripts.anim_lock(lang, bad, {0x00}, guard),
                         ['anim: S $7F0400: Op00_Stub writes task record byte $06'])
        good = [('S', {B: 0x00, B + 1: 0x26, B + 2: 0x07}, (B, B + 3), {B})]
        self.assertEqual(scripts.anim_lock(lang, good, {0x00}, guard), [])

    def test_anim_ops_found_by_their_writes(self):
        writes = {0: lambda v: {v}, 4: lambda v: {0x0E}, 5: lambda v: {7}}
        named, out = scripts.anim_named_ops(AnimStub(), lambda op, v: writes.get(op, lambda v: set())(v),
                                            {5, 6, 7, 8, 9, 0x0E})
        self.assertEqual(named, {0})
        self.assertEqual(out, ['anim: Op05_Stub writes task record byte(s) [7] whatever its operand'])

    def test_struct_offsets(self):
        f = scripts.struct_offsets(scripts.ROOT, 'C2Scene_Task')
        self.assertEqual((f['ScriptReturn'], f['ScriptBank'], f['AnimTimer'], f['OpState'], f['Unk37']),
                         (0x05, 0x09, 0x0E, 0x32, 0x37))
        with tempfile.TemporaryDirectory() as tmp:
            inc = Path(tmp) / 'asm' / 'include'
            inc.mkdir(parents=True)
            (inc / 'x.inc').write_text('struct S $7E0000\n.A: skip 1 ; a\n            skip $10\n.B:\n.C: skip 2\n'
                                       '.D: skip 3\nendstruct\n')
            self.assertEqual(scripts.struct_offsets(tmp, 'S'), {'A': 0, 'B': 0x11, 'C': 0x11, 'D': 0x13})
            (inc / 'x.inc').write_text('struct S $7E0000\n.A: skip one\nendstruct\n')
            with self.assertRaisesRegex(scripts.ScriptsError, 'a line not read'):
                scripts.struct_offsets(tmp, 'S')

    def test_unpack_must_fit(self):
        keep = [(B, 0x100, 'the script buffer')]
        self.assertEqual(scripts.unpack_fit('R', {0xC40000: 4096}, {0x7FF000}, keep), [])
        self.assertEqual(scripts.unpack_fit('R', {0xC40000: 4097}, {0x7FF000}, keep),
                         ['unpack: R: the pack at $C40000 (4097 B) runs past the end of bank $7F from $7FF000'])
        self.assertEqual(scripts.unpack_fit('R', {0xC40000: 0x200}, {0x7F0300}, keep),
                         ['unpack: R: the pack at $C40000 unpacked at $7F0300 covers the script buffer'])


class Source(unittest.TestCase):

    def test_manifest_pieces(self):
        pieces = ed.read_manifest()
        scene = [p for p in pieces if p['piece'] == 'scene']
        fx = [p for p in pieces if p['piece'] == 'fx']
        self.assertEqual(len(scene), 8)
        self.assertEqual([p['start'] for p in fx], sorted(scripts.FX_ROWS))
        for p in scene:
            self.assertEqual(p['asset'], f'scene/{p["label"]}.scn')


# The code image is the source assembled with the packed $C3 module, whose source incbins
# the ROM's bytes it does not cover: it needs the ROM as well as asar.
@unittest.skipUnless(HAVE_ROM, 'needs the ROM and asar (the code image is assembled from the source and the module)')
class WithSource(unittest.TestCase):

    def test_trusted_routines_from_their_code(self):
        scene, fx = scripts.SceneLang(), scripts.FxLang()
        for lang in (scene, fx):
            for name in scripts.TRUST[lang.name]:
                self.assertIn(name, lang.labels)
            self.assertEqual(scripts.trust_check(lang), [])
        scene.ptr = scene.d['C2Anim_Ptr']                       # a byte C2Anim_Run does write
        self.assertTrue(any('C2Anim_Run' in x for x in scripts.trust_check(scene)))


@unittest.skipUnless(HAVE_ROM, 'needs the ROM and asar')
class WithRom(unittest.TestCase):

    def test_anim_lock_sees_every_script(self):
        info = []
        self.assertEqual(scripts.anim_check(ed.read_rom(), info=info), [])
        self.assertEqual(info, [('C2SceneRom_AnimTable', 161, 708), ('C2Scene_AnimLeaderMarker', 1, 3),
                                ('C2Scene_AnimObjAMarker', 1, 4), ('C2Scene_Unk8600', 1, 1), ('named', [0, 1, 2])])

    def test_unpack_lock_sees_every_unpacker(self):
        info = []
        self.assertEqual(scripts.unpack_check(scripts.SceneLang(), ed.read_rom(), info), [])
        bufs = [0x7F9000 + 0x1000 * k for k in range(7)]
        self.assertEqual(info, [
            ('C2Scene_LoadBgGfx', ['C2SceneRom_BgPacks'], bufs, 4096),
            ('C2Scene_LoadExtraObjPack', ['C2SceneRom_ObjPacks'], [0x7F9000], 8192),
            ('C2Scene_LoadUnkC600', ['C2SceneRom_PalettePacks'], [0x7EC600], 608),
            ('C2Scene_UnpackBg3MapPack', ['C2SceneRom_Bg3MapPacks'], [0x7F9000], 4096),
            ('C2Scene_UnpackBgPack', ['C2SceneRom_BgPacks'], [0x7F9000], 4096),
            ('C6Scene_UnpackObjPackA', ['C2SceneRom_ObjPacks'], [0x7F9000], 8192),
            ('C6Scene_UnpackObjPackB', ['C2SceneRom_ObjPacks'], [0x7F9000], 8192),
            ('C6Scene_UnpackPalPackA', ['C2SceneRom_PalettePacks'], [0x7F8C00], 608),
            ('C6Scene_UnpackPalPackB', ['C2SceneRom_PalettePacks'], [0x7F8C00], 608)])
        self.assertEqual(tuple(r[0] for r in info), scripts.UNPACKERS)

    def test_check_runs_the_locks(self):
        saved = scripts.anim_check, scripts.unpack_check, scripts.trust_check
        scripts.anim_check = lambda rom, root=scripts.ROOT, info=None: ['anim lock ran']
        scripts.unpack_check = lambda lang, rom, info=None: ['unpack lock ran']
        scripts.trust_check = lambda lang: [f'trust lock ran: {lang.name}']
        try:
            got = scripts.check(ed.read_rom())
        finally:
            scripts.anim_check, scripts.unpack_check, scripts.trust_check = saved
        for x in ('anim lock ran', 'unpack lock ran', 'trust lock ran: scene', 'trust lock ran: fx'):
            self.assertIn(x, got)

    def test_anim_piece(self):
        lang = scripts.anim_lang()
        self.assertEqual(lang.head(), 0)
        p = [x for x in ed.read_manifest() if x['piece'] == 'anim']
        self.assertEqual([(x['start'], x['asset']) for x in p], [('$C3:E000', 'anim/C2SceneRom_AnimTable.ban')])
        self.assertEqual(scripts.ANIM_ROWS, {'$C3:E000'})
        saved = scripts.EXITS['anim']
        scripts.EXITS['anim'] = {'ret': {0x07}, 'ram': set(), 'done': set()}
        try:
            self.assertTrue(any(x.startswith('anim: the opcodes classed ret') for x in
                                scripts.exits_check(ed.read_rom(), ed.read_manifest())))
        finally:
            scripts.EXITS['anim'] = saved

    def test_anim_trusts_nothing(self):
        real = scripts._fx_disassembly

        def marked(lang, start, data):
            d = real(lang, start, data)
            if lang.name == 'anim':
                next(iter(d['ops'].values())).trusted = ['C2Scene_Something']
            return d
        scripts._fx_disassembly = marked
        try:
            got = scripts.exits_check(ed.read_rom(), ed.read_manifest())
        finally:
            scripts._fx_disassembly = real
        self.assertTrue(any(x.startswith('anim: an animation op needs a trusted callee') for x in got))

    def test_anim_row_is_the_piece(self):
        row = {'start': '$C3:E000', 'end': '$C3:E001', 'size': '2', 'bank': '$C3', 'kind': 'event_script',
               'format': 'x', 'readers': '', 'confidence': 'confirmed', 'notes': 'x'}
        self.assertEqual([(p['piece'], p['asset']) for p in ed.layout([row])],
                         [('anim', 'anim/EvtScript_C3E000.ban')])
        with self.assertRaisesRegex(ed.DataError, 'cannot be the animation scripts'):
            ed.layout([dict(row, kind='table')])

    def test_round_trips_and_exits(self):
        self.assertEqual(scripts.check(ed.read_rom()), [])


if __name__ == '__main__':
    unittest.main()
