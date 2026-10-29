#!/usr/bin/env python3
"""
test_scripts.py — Tests for tools/scripts.py (the scene and layer-effect
scripts' readable forms).

    python3 tools/test_scripts.py          (from the repository root)

Without the ROM: the disassembler and the assembler on a synthetic scene
pack and a synthetic fx table and scripts, with stub interpreters (next,
stay, a branch, a jump, a call and its return, a spawn, the end; pages,
$7F and $FF), the jump encodings found by changing the bytes, and the
structure refusals; the manifest's scene and fx pieces; the opcode names
from the source.

With the ROM and asar: every scene pack and the fx scripts disassemble and
assemble back byte-exact, and the opcodes classed return, ram and done are
the known ones.
"""

import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_data as ed  # noqa: E402
import scripts  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists() and shutil.which('asar') is not None


def _sext(b):
    return b - 256 if b >= 0x80 else b


class SceneStub(scripts.SceneLang):
    """$00 next 1; $02 n next 2; $1A w jump to w + 1; $1C t o branch by o
    (else next 3); $36 w call w (back at +3); $37 return; $38 n wait (stay,
    then next 2); $09 w b spawn w in bank b (next 4); $52 done."""

    def __init__(self):
        self.name, self.count = 'scene', 0x53
        self.names = [f'Op{op:02X}_Stub' for op in range(self.count)]
        self.cache, self.specs, self.dirty = {}, {}, False

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


def assemble_scene(text):
    return scripts.assemble_scene(SceneStub(), text, 'Pack', len(PACK), 'pack.scn')


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
        self.refused('@entry 0 F_D10008', '@entry 0 $0008', 'is a script: name its label')

    def test_page_must_be_a_page(self):
        self.refused('    Page $12', '    Page $80', 'page byte below')

    def test_data_after_end_is_data(self):
        self.refused('@bytes 99', '    Page $19', 'nothing reaches')


class Source(unittest.TestCase):

    def test_manifest_pieces(self):
        pieces = ed.read_manifest()
        scene = [p for p in pieces if p['piece'] == 'scene']
        fx = [p for p in pieces if p['piece'] == 'fx']
        self.assertEqual(len(scene), 8)
        self.assertEqual([p['start'] for p in fx], sorted(scripts.FX_ROWS))
        for p in scene:
            self.assertEqual(p['asset'], f'scene/{p["label"]}.scn')


@unittest.skipUnless(HAVE_ROM, 'needs the ROM and asar')
class WithRom(unittest.TestCase):

    def test_round_trips_and_exits(self):
        self.assertEqual(scripts.check(ed.read_rom()), [])


if __name__ == '__main__':
    unittest.main()
