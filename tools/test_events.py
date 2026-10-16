#!/usr/bin/env python3
"""
test_events.py — Tests for tools/events.py (the event scripts' disassembly)
and tools/absint.py (the interpreter it asks).

    python3 tools/test_events.py          (from the repository root)

Without the ROM: the opcode names come from Evt_OpcodeTable in the source;
the interpreter on hand-assembled code (known and unknown values, both ways
of an unknown branch, which script bytes it reads and which decide
something, a loop on an unknown value ending, a callee it cannot follow);
the readable form's assembler on a synthetic script (labels, jumps,
inner opcodes, text pointers, @raw) and its refusals; the manifest's
events pieces.

With the ROM and asar: a sample of the packs disassembles and assembles
back byte-exact, and every fixed length the handlers' headers state is
the length the interpreter derives.
"""

import random
import re
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import absint  # noqa: E402
import data_survey  # noqa: E402
import events  # noqa: E402
import extract_data as ed  # noqa: E402

HAVE_ROM = ed.ROM_PATH.exists() and shutil.which('asar') is not None


def machine(code: bytes) -> tuple[absint.Machine, int]:
    """A machine whose image holds `code` at $C0:8000 (emitted)."""
    image = bytearray(0x400000)
    image[0x8000:0x8000 + len(code)] = code
    mask = bytearray(0x400000)
    mask[0x8000:0x8000 + len(code)] = b'\x01' * len(code)
    return absint.Machine(bytes(image), mask), 0xC08000


def entry(pc: int, y: int) -> absint.State:
    s = absint.State()
    s.pc, s.a, s.b, s.x, s.y, s.d, s.db = pc, 0, 0, 0, y, 0x0100, None
    s.m, s.xf = True, False
    s.c = s.z = s.n = s.v = None
    s.sp, s.spt, s.mem, s.memt = [], [], {}, {}
    s.at = s.xt = s.yt = s.ft = absint.E
    s.depth = 0
    return s


SCRIPT = 0x7F2001
# INY; TYX; LDA $7F2001,X; CMP #$05; BEQ +2; INX; RTS; INX; INX; RTS
COMPARE = bytes([0xC8, 0xBB, 0xBF, 0x01, 0x20, 0x7F, 0xC9, 0x05, 0xF0, 0x02, 0xE8, 0x60, 0xE8, 0xE8, 0x60])


class Interpreter(unittest.TestCase):

    def test_known_branch(self):
        m, pc = machine(COMPARE)
        for value, want in ((5, 3), (6, 2)):
            ends = m.run(entry(pc, 0), {SCRIPT: 0x99, SCRIPT + 1: value})
            self.assertEqual([(s.x, how) for s, how in ends], [(want, 'rts')])
            self.assertEqual(m.reads, {SCRIPT + 1})
            self.assertEqual(m.control, {SCRIPT + 1})          # the byte decided the branch

    def test_unknown_branch_goes_both_ways(self):
        # INY; TYX; LDA $0010 (unknown); BEQ +2; INX; RTS; INX; INX; RTS
        code = bytes([0xC8, 0xBB, 0xAD, 0x10, 0x00, 0xF0, 0x02, 0xE8, 0x60, 0xE8, 0xE8, 0x60])
        m, pc = machine(code)
        ends = m.run(entry(pc, 4), {})
        self.assertEqual(sorted(s.x for s, _ in ends), [6, 7])
        self.assertEqual(m.control, set())

    def test_jump_taint(self):
        # INY; TYX; LDA $7F2001,X; REP #$20; AND #$00FF; STA $10; TXA; CLC; ADC $10; TAX; SEP #$20; RTS
        code = bytes([0xC8, 0xBB, 0xBF, 0x01, 0x20, 0x7F, 0xC2, 0x20, 0x29, 0xFF, 0x00, 0x85, 0x10, 0x8A,
                      0x18, 0x65, 0x10, 0xAA, 0xE2, 0x20, 0x60])
        m, pc = machine(code)
        ends = m.run(entry(pc, 2), {SCRIPT + 3: 7})
        (s, _), = ends
        self.assertEqual(s.x, 3 + 7)
        self.assertEqual(s.xt, frozenset({SCRIPT + 3}))         # the position comes from the byte

    def test_loop_on_unknown_ends(self):
        # loop: LDA $0010; BNE loop; RTS
        m, pc = machine(bytes([0xAD, 0x10, 0x00, 0xD0, 0xFB, 0x60]))
        self.assertEqual(len(m.run(entry(pc, 0), {})), 1)

    def test_callee_outside_the_source(self):
        # JSL $7E3000 (WRAM: not followed); TYX; RTS
        m, pc = machine(bytes([0x22, 0x00, 0x30, 0x7E, 0xBB, 0x60]))
        (s, _), = m.run(entry(pc, 9), {})
        self.assertIsNone(s.x)                                   # Y is unknown after it


NAMES = [f'Op{op:02X}' for op in range(256)]
NAMES[0xB8] = 'OpB8_SetMsgPtr'          # the one opcode that takes a data label


class Readable(unittest.TestCase):

    def text(self):
        # header 32 bytes: the scripts start at $20
        return '\n'.join([
            '; a synthetic script', '@objects 1', '@jump Op10 1 + 1',
            *[f'@func 0 {f} L_0020' for f in range(16)],
            'L_0020:', '    Op12 $07 $00', '    @inner +1 L_0021 Op07 $00',
            '    OpB8_SetMsgPtr Table_X+$10', '    Op10 ->L_end', 'L_end:', '@bytes 01 02 03']) + '\n'

    def test_assemble(self):
        out = events.assemble(self.text(), NAMES, {'Table_X': 0xD80000})
        self.assertEqual(out[:3], bytes([1, 0x20, 0]))
        body = out[1 + 32:]
        self.assertEqual(body[:3], bytes([0x12, 0x07, 0x00]))
        self.assertEqual(body[3:7], bytes([0xB8, 0x10, 0x00, 0xD8]))
        self.assertEqual(body[7:9], bytes([0x10, 1]))          # $29 = $27 + 1 + 1
        self.assertEqual(body[9:], bytes([1, 2, 3]))
        self.assertEqual(events.stats(self.text())['data'], 3)

    def test_refusals(self):
        base = self.text()
        cases = {
            'jump_out_of_reach': base.replace('->L_end', '->L_0020'),   # Op10 only jumps forward
            'unknown_opcode': base.replace('OpB8_SetMsgPtr', 'NoSuchOp'),
            'label_operand_elsewhere': base.replace('Op12 $07 $00', 'Op12 Table_X'),
            'label_and_bytes': base.replace('OpB8_SetMsgPtr Table_X+$10', 'OpB8_SetMsgPtr $00 Table_X'),
            'no_label': base.replace('->L_end', '->L_9999'),
            'no_func': base.replace('@func 0 3 L_0020\n', ''),
            'no_data_label': base.replace('Table_X', 'Table_Y'),
            'not_a_byte': base.replace('@bytes 01', '@bytes 1FF'),
            'inner_mismatch': base.replace('@inner +1 L_0021 Op07', '@inner +1 L_0021 Op08'),
            'no_jump_operand': base.replace('Op12 $07 $00', 'Op12 $07 ->L_end'),
        }
        for name, text in cases.items():
            with self.subTest(case=name), self.assertRaises((events.EventsError, ValueError)):
                events.assemble(text, NAMES, {'Table_X': 0xD80000})

    def test_raw(self):
        data = bytes(random.Random(1).randrange(256) for _ in range(40))
        text = events.render_raw(data, 'T', 'why')
        self.assertEqual(events.assemble(text, NAMES, {}), data)
        self.assertEqual(events.stats(text), {'code': 0, 'data': 0, 'raw': 40})


class Source(unittest.TestCase):

    def test_opcode_names_from_the_table(self):
        names = events.opcode_names()
        self.assertEqual(len(names), 256)
        self.assertEqual(len(set(names)), 256)
        self.assertEqual(names[0x10], 'Op10_JumpFwd')
        self.assertEqual(names[0xB8], 'OpB8_SetMsgPtr')
        self.assertTrue(all(n in names for n in events.TEXT_POINTER_OPS))

    def test_manifest_events_pieces(self):
        pieces = [p for p in ed.read_manifest() if p['piece'] == 'events']
        rows = [r for r in data_survey.read_rows() if ed.EVENT_PACK.search(r['notes'])]
        self.assertEqual(len(pieces), len(rows))
        for p in pieces:
            self.assertRegex(p['asset'], ed.EVENTS_ASSET)
            self.assertRegex(p['param'], ed.PACK_PARAM)


@unittest.skipUnless(HAVE_ROM, 'needs the ROM and asar')
class WithRom(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.rom = ed.read_rom()
        cls.interp = events.Interpreter()
        cls.names = events.opcode_names()
        cls.pieces = [p for p in ed.read_manifest() if p['piece'] == 'events']
        cls.texts = [(p['label'], 0xC00000 + p['offset'], 0xC00000 + p['stop'])
                     for p in ed.read_manifest() if p['piece'] == 'text']

    def test_regrouped_operands_refused(self):
        # An operand moved to a line of its own (the bytes stay the same):
        # the handler's length refuses it.
        addrs = {n: a for n, a, _ in self.texts}
        for p in self.pieces:
            data, _ = ed.unpack_piece(self.rom, p)
            if not data:
                continue
            text = events.extract_pack(self.interp, self.names, data, p['label'], self.texts)
            m = re.search(r'^    (Op8B_PlaceAtTile) (\$[0-9A-F]{2}) \$([0-9A-F]{2})$', text, re.M)
            if not m:
                continue
            bad = text.replace(m.group(0), f'    {m.group(1)} {m.group(2)}\n    {self.names[int(m.group(3), 16)]}', 1)
            self.assertEqual(events.assemble(bad, self.names, addrs), data)     # same bytes ...
            with self.assertRaisesRegex(events.EventsError, 'takes 3 bytes'):
                events.assemble(bad, self.names, addrs, interp=self.interp)    # ... refused
            return
        self.fail('no Op8B_PlaceAtTile line found')

    def test_tampered_caches_refused(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / events.CODE_DIR).mkdir(parents=True)
            interp = events.Interpreter()
            interp.cache = {1: {(): {(): {'reads': [], 'outs': []}}}}
            interp.specs = {0x10: (1, 1, 1)}
            interp.dirty = True
            interp.save(root)
            interp.load(root)                                     # as written: accepted
            data_f = root / events.CODE_DIR / 'traces.pickle'
            data_f.write_bytes(data_f.read_bytes() + b'\0')      # poisoned
            with self.assertRaisesRegex(events.EventsError, 'changed by hand'):
                events.Interpreter().load(root)
        # a cached code image changed by hand is assembled again
        code = ed.ROOT / events.CODE_DIR / 'code.bin'
        image = bytearray(code.read_bytes())
        image[0x5D6E] ^= 0xFF                                    # inside Evt_OpcodeTable
        code.write_bytes(bytes(image))
        self.assertEqual(events.code_image()[0], self.interp.image)

    def test_raw_packs_refused(self):
        import build_rom
        p = next(p for p in self.pieces if int(p['size']) > 64)
        path = ed.ROOT / ed.ASSETS / p['asset']
        kept = path.read_text()
        data, _ = ed.unpack_piece(self.rom, p)
        try:
            path.write_text(events.render_raw(data, p['label'], 'test'))
            with self.assertRaisesRegex(build_rom.BuildError, 'kept as bytes'):
                build_rom.build_events()
        finally:
            path.write_text(kept)

    def test_sample_round_trips(self):
        addrs = {n: a for n, a, _ in self.texts}
        for p in self.pieces[::40]:
            with self.subTest(pack=p['label']):
                data, why = ed.unpack_piece(self.rom, p)
                self.assertIsNone(why)
                text = events.extract_pack(self.interp, self.names, data, p['label'], self.texts)
                self.assertNotIn('@raw', text if data else '')
                self.assertEqual(events.assemble(text, self.names, addrs), data)

    def test_lengths_agree_with_the_handlers_headers(self):
        claims = {}
        src = events.BANK_C0.read_text()
        for m in re.finditer(r'; Event opcode \$([0-9A-F]{2}) \((\d+) bytes?[:)]', src):
            claims[int(m.group(1), 16)] = int(m.group(2))
        seen = 0
        for p in self.pieces[::40]:
            data, _ = ed.unpack_piece(self.rom, p)
            if not data:
                continue
            d = events.disassemble(self.interp, data)
            for o in d['ops'].values():
                if o.op in claims and o.op not in (0xF1, 0xFF):   # their headers give two lengths
                    self.assertEqual(o.length, claims[o.op], f'opcode ${o.op:02X}')
                    seen += 1
        self.assertGreater(seen, 1000)


if __name__ == '__main__':
    unittest.main(verbosity=1)
