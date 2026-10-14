#!/usr/bin/env python3
"""
test_spc700.py — Tests for the SPC700 decoder and disassembler (tools/spc700.py).

    python3 tools/test_spc700.py          (from the repository root)

Without the ROM or asar only the table checks run: 256 opcodes, the
lengths, and the decoding of a few hand-checked byte strings.

With asar: every opcode, printed by the table with sample operands, is
assembled by asar's spc700 mode and must give back the same bytes (so the
syntax the disassembler writes, the `.b`/`.w` widths included, is the
syntax asar reads).

With the ROM and asar: the whole driver block, traced from its known
entries, reassembles to the ROM's bytes (with the branches into operand
bytes it uses); the trace reaches exactly the code ranges the NEXT.md plan
gives (spc700.CODE_RANGES) and no byte of the data ranges; and the source
in asm/spc700/ assembles over the same bytes (make gate checks that in
full).
"""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spc700  # noqa: E402

HAVE_ASAR = shutil.which('asar') is not None
HAVE_ROM = spc700.ROM_PATH.exists()


def sample(op: int) -> bytes:
    """The opcode with operand bytes $34 $12 (branches: $34 $02)."""
    n = spc700.length(op)
    if 'r' in spc700.OPCODES[op][2] and n == 3:
        return bytes([op, 0x34, 0x02])
    return bytes([op, 0x34, 0x12])[:n]


class Table(unittest.TestCase):

    def test_all_opcodes_defined(self):
        self.assertEqual(sorted(spc700.OPCODES), list(range(256)))

    def test_lengths(self):
        self.assertEqual(spc700.length(0x00), 1)      # nop
        self.assertEqual(spc700.length(0xE4), 2)      # mov a,dp
        self.assertEqual(spc700.length(0xE5), 3)      # mov a,abs
        self.assertEqual(spc700.length(0x8F), 3)      # mov dp,#imm
        self.assertEqual(spc700.length(0xFA), 3)      # mov dp,dp
        self.assertEqual(spc700.length(0x03), 3)      # bbs dp.0,rel
        self.assertEqual(spc700.length(0xAA), 3)      # mov1 c,mem.bit
        self.assertEqual(spc700.length(0x4F), 2)      # pcall
        # 75 one-byte opcodes (16 TCALL, 4 PUSH, 4 POP, 8 flag ops, NOP, BRK, RET, RETI,
        # SLEEP, STOP, 8 (X)-forms, the (X)+ moves, 6 register INC/DEC, 4 shifts of A,
        # 6 register moves, MUL, DIV, XCN, DAA, DAS), 99 of two bytes, 82 of three.
        counts = [sum(spc700.length(op) == n for op in range(256)) for n in (1, 2, 3)]
        self.assertEqual(counts, [75, 99, 82])

    def test_operand_order(self):
        # Two-operand forms store the source first: FA ss dd, 8F ii dd.
        self.assertEqual(spc700.decode(b'\xfa\x8e\xbc', 0x0BED).text(), 'mov.b $BC,$8E')
        self.assertEqual(spc700.decode(b'\x8f\x30\xf1', 0x023C).text(), 'mov.b $F1,#$30')
        self.assertEqual(spc700.decode(b'\x69\xbc\xbb', 0x0C13).text(), 'cmp.b $BB,$BC')

    def test_branches(self):
        ins = spc700.decode(b'\xd0\xfb', 0x020B)
        self.assertEqual(ins.branch_target(), 0x0208)
        ins = spc700.decode(b'\x83\x87\xb4', 0x02E2)
        self.assertEqual((ins.text(), ins.branch_target()), ('bbs.b $87.4,$0299', 0x0299))
        self.assertEqual(spc700.decode(b'\x3f\xa3\x07', 0).jump_target(), 0x07A3)
        self.assertEqual(spc700.decode(b'\x4f\xc0', 0).jump_target(), 0xFFC0)
        self.assertFalse(spc700.decode(b'\x6f', 0).falls_through)
        self.assertTrue(spc700.decode(b'\x3f\x00\x00', 0).falls_through)

    def test_mem_bit(self):
        ins = spc700.decode(b'\xaa\x34\x72', 0)
        self.assertEqual(ins.text(), 'mov1 c,$1234.3')
        self.assertEqual(spc700.decode(b'\x2a\x34\x12', 0).text(), 'or1 c,!$1234.0')


def assemble(lines: list[str], size: int = 0x10000) -> bytes:
    with tempfile.TemporaryDirectory() as tmp:
        asm, img = Path(tmp) / 't.asm', Path(tmp) / 't.sfc'
        asm.write_text('\n'.join(['hirom', 'org $C00000', 'arch spc700', 'base $0400'] + lines) + '\n')
        img.write_bytes(bytes(size))
        r = subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', str(asm), str(img)],
                           capture_output=True, text=True)
        if r.returncode:
            raise AssertionError(r.stdout + r.stderr)
        return img.read_bytes()


@unittest.skipUnless(HAVE_ASAR, 'needs asar')
class Asar(unittest.TestCase):

    def test_every_opcode_round_trips(self):
        lines, want, pc = [], bytearray(), 0x0400
        for op in range(256):
            ins = spc700.decode(sample(op) + b'\0\0', pc)
            lines.append('    ' + ins.text())
            want += ins.raw
            pc += ins.size
        out = assemble(lines)[:len(want)]
        pc = 0
        for op in range(256):
            n = spc700.length(op)
            self.assertEqual(out[pc:pc + n].hex(), want[pc:pc + n].hex(), f'{op:02X}: {lines[op]}')
            pc += n


@unittest.skipUnless(HAVE_ASAR and HAVE_ROM, 'needs the ROM and asar')
class Driver(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.rom = spc700.ROM_PATH.read_bytes()
        cls.first, cls.base, cls.size = spc700.driver_block(cls.rom)
        cls.mem = cls.rom[cls.first:cls.first + cls.size]
        cls.insns = spc700.trace(cls.mem, cls.base, spc700.driver_entries(cls.mem))

    def test_block(self):
        self.assertEqual((self.first, self.base, self.size), (0x0724C5, 0x0200, 0x1BEF))

    def test_trace_finds_the_code_ranges(self):
        covered = set()
        for ins in self.insns.values():
            covered.update(range(ins.pc, ins.end))
        code = set()
        for lo, hi in spc700.CODE_RANGES:
            code.update(range(lo, hi + 1))
        self.assertEqual(covered, code)
        for lo, hi in spc700.DATA_RANGES:
            self.assertFalse(covered & set(range(lo, hi + 1)))
        everything = sorted(code | {a for lo, hi in spc700.DATA_RANGES for a in range(lo, hi + 1)})
        self.assertEqual(everything, list(range(self.base, self.base + self.size)))

    def test_branches_into_operands(self):
        starts = sorted(self.insns)
        overlaps = [b for a, b in zip(starts, starts[1:]) if self.insns[a].end > b]
        self.assertEqual(overlaps, [0x03BA, 0x0DB2, 0x129B, 0x192C])

    def test_whole_driver_round_trips(self):
        stop = self.base + self.size
        lines = spc700.source(self.mem, self.base, self.first, self.base, stop, self.insns)
        self.assertIsNone(spc700.check(lines, self.rom, self.first, self.base, self.base, stop))

    def test_linear_round_trips(self):
        stop = self.base + self.size
        insns = spc700.linear(self.mem, self.base, self.base, stop)
        lines = spc700.source(self.mem, self.base, self.first, self.base, stop, insns)
        self.assertIsNone(spc700.check(lines, self.rom, self.first, self.base, self.base, stop))


if __name__ == '__main__':
    unittest.main()
