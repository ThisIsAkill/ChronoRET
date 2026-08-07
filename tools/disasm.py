#!/usr/bin/env python3
"""
disasm.py — Recursive-descent 65816 disassembler for Chrono Trigger decomp.

Usage:
    python3 tools/disasm.py <rom.sfc> <bank_hex> [entry_hex ...]

    <bank_hex>   ROM bank in hex, e.g. 00, FD
    [entry_hex]  One or more SNES word addresses (within-bank offset) to
                 start tracing from, e.g. FF00 8000.  If omitted, scans
                 the full bank linearly.

Examples:
    python3 tools/disasm.py roms/chrono_trigger.sfc 00 FF00 FF10 FF14 FF18
    python3 tools/disasm.py roms/chrono_trigger.sfc FD C000

Output:
    Disassembly to stdout, summary (calls, jumps, returns) to stderr.
"""

import sys
import struct
from collections import defaultdict
from pathlib import Path

# ---------------------------------------------------------------------------
# HiROM address ↔ file-offset conversion
# ---------------------------------------------------------------------------
def snes_to_file(bank: int, addr: int) -> int | None:
    """Return file offset for a HiROM SNES address, or None if not ROM."""
    if bank >= 0xC0:
        return (bank - 0xC0) * 0x10000 + addr
    if 0x00 <= bank <= 0x3F:
        if addr < 0x8000:
            return None  # system area, not ROM
        return bank * 0x10000 + addr
    if 0x80 <= bank <= 0xBF:
        if addr < 0x8000:
            return None
        return (bank - 0x80) * 0x10000 + addr
    return None


def file_to_snes(offset: int) -> tuple[int, int]:
    """Return (bank, addr) SNES address for a file offset (HiROM)."""
    bank = offset >> 16
    addr = offset & 0xFFFF
    return bank + 0xC0, addr  # canonical form is $C0+ bank

# ---------------------------------------------------------------------------
# 65816 instruction table
# mode key:
#   impl, A, rel, rlong, imm, imm_m, imm_x, dp, dp_x, dp_y,
#   dp_ind, dp_x_ind, dp_ind_y, dp_ind_long, dp_ind_long_y,
#   sr, sr_ind_y, abs, abs_x, abs_y, abs_ind, abs_x_ind, abs_ind_long,
#   long, long_x, block
# ---------------------------------------------------------------------------
_OPCODES: dict[int, tuple[str, str]] = {
    0x00: ('BRK',  'imm'),
    0x01: ('ORA',  'dp_x_ind'),
    0x02: ('COP',  'imm'),
    0x03: ('ORA',  'sr'),
    0x04: ('TSB',  'dp'),
    0x05: ('ORA',  'dp'),
    0x06: ('ASL',  'dp'),
    0x07: ('ORA',  'dp_ind_long'),
    0x08: ('PHP',  'impl'),
    0x09: ('ORA',  'imm_m'),
    0x0A: ('ASL',  'A'),
    0x0B: ('PHD',  'impl'),
    0x0C: ('TSB',  'abs'),
    0x0D: ('ORA',  'abs'),
    0x0E: ('ASL',  'abs'),
    0x0F: ('ORA',  'long'),
    0x10: ('BPL',  'rel'),
    0x11: ('ORA',  'dp_ind_y'),
    0x12: ('ORA',  'dp_ind'),
    0x13: ('ORA',  'sr_ind_y'),
    0x14: ('TRB',  'dp'),
    0x15: ('ORA',  'dp_x'),
    0x16: ('ASL',  'dp_x'),
    0x17: ('ORA',  'dp_ind_long_y'),
    0x18: ('CLC',  'impl'),
    0x19: ('ORA',  'abs_y'),
    0x1A: ('INC',  'A'),
    0x1B: ('TCS',  'impl'),
    0x1C: ('TRB',  'abs'),
    0x1D: ('ORA',  'abs_x'),
    0x1E: ('ASL',  'abs_x'),
    0x1F: ('ORA',  'long_x'),
    0x20: ('JSR',  'abs'),
    0x21: ('AND',  'dp_x_ind'),
    0x22: ('JSL',  'long'),
    0x23: ('AND',  'sr'),
    0x24: ('BIT',  'dp'),
    0x25: ('AND',  'dp'),
    0x26: ('ROL',  'dp'),
    0x27: ('AND',  'dp_ind_long'),
    0x28: ('PLP',  'impl'),
    0x29: ('AND',  'imm_m'),
    0x2A: ('ROL',  'A'),
    0x2B: ('PLD',  'impl'),
    0x2C: ('BIT',  'abs'),
    0x2D: ('AND',  'abs'),
    0x2E: ('ROL',  'abs'),
    0x2F: ('AND',  'long'),
    0x30: ('BMI',  'rel'),
    0x31: ('AND',  'dp_ind_y'),
    0x32: ('AND',  'dp_ind'),
    0x33: ('AND',  'sr_ind_y'),
    0x34: ('BIT',  'dp_x'),
    0x35: ('AND',  'dp_x'),
    0x36: ('ROL',  'dp_x'),
    0x37: ('AND',  'dp_ind_long_y'),
    0x38: ('SEC',  'impl'),
    0x39: ('AND',  'abs_y'),
    0x3A: ('DEC',  'A'),
    0x3B: ('TSC',  'impl'),
    0x3C: ('BIT',  'abs_x'),
    0x3D: ('AND',  'abs_x'),
    0x3E: ('ROL',  'abs_x'),
    0x3F: ('AND',  'long_x'),
    0x40: ('RTI',  'impl'),
    0x41: ('EOR',  'dp_x_ind'),
    0x42: ('WDM',  'imm'),
    0x43: ('EOR',  'sr'),
    0x44: ('MVP',  'block'),
    0x45: ('EOR',  'dp'),
    0x46: ('LSR',  'dp'),
    0x47: ('EOR',  'dp_ind_long'),
    0x48: ('PHA',  'impl'),
    0x49: ('EOR',  'imm_m'),
    0x4A: ('LSR',  'A'),
    0x4B: ('PHK',  'impl'),
    0x4C: ('JMP',  'abs'),
    0x4D: ('EOR',  'abs'),
    0x4E: ('LSR',  'abs'),
    0x4F: ('EOR',  'long'),
    0x50: ('BVC',  'rel'),
    0x51: ('EOR',  'dp_ind_y'),
    0x52: ('EOR',  'dp_ind'),
    0x53: ('EOR',  'sr_ind_y'),
    0x54: ('MVN',  'block'),
    0x55: ('EOR',  'dp_x'),
    0x56: ('LSR',  'dp_x'),
    0x57: ('EOR',  'dp_ind_long_y'),
    0x58: ('CLI',  'impl'),
    0x59: ('EOR',  'abs_y'),
    0x5A: ('PHY',  'impl'),
    0x5B: ('TCD',  'impl'),
    0x5C: ('JML',  'long'),
    0x5D: ('EOR',  'abs_x'),
    0x5E: ('LSR',  'abs_x'),
    0x5F: ('EOR',  'long_x'),
    0x60: ('RTS',  'impl'),
    0x61: ('ADC',  'dp_x_ind'),
    0x62: ('PER',  'rlong'),
    0x63: ('ADC',  'sr'),
    0x64: ('STZ',  'dp'),
    0x65: ('ADC',  'dp'),
    0x66: ('ROR',  'dp'),
    0x67: ('ADC',  'dp_ind_long'),
    0x68: ('PLA',  'impl'),
    0x69: ('ADC',  'imm_m'),
    0x6A: ('ROR',  'A'),
    0x6B: ('RTL',  'impl'),
    0x6C: ('JMP',  'abs_ind'),
    0x6D: ('ADC',  'abs'),
    0x6E: ('ROR',  'abs'),
    0x6F: ('ADC',  'long'),
    0x70: ('BVS',  'rel'),
    0x71: ('ADC',  'dp_ind_y'),
    0x72: ('ADC',  'dp_ind'),
    0x73: ('ADC',  'sr_ind_y'),
    0x74: ('STZ',  'dp_x'),
    0x75: ('ADC',  'dp_x'),
    0x76: ('ROR',  'dp_x'),
    0x77: ('ADC',  'dp_ind_long_y'),
    0x78: ('SEI',  'impl'),
    0x79: ('ADC',  'abs_y'),
    0x7A: ('PLY',  'impl'),
    0x7B: ('TDC',  'impl'),
    0x7C: ('JMP',  'abs_x_ind'),
    0x7D: ('ADC',  'abs_x'),
    0x7E: ('ROR',  'abs_x'),
    0x7F: ('ADC',  'long_x'),
    0x80: ('BRA',  'rel'),
    0x81: ('STA',  'dp_x_ind'),
    0x82: ('BRL',  'rlong'),
    0x83: ('STA',  'sr'),
    0x84: ('STY',  'dp'),
    0x85: ('STA',  'dp'),
    0x86: ('STX',  'dp'),
    0x87: ('STA',  'dp_ind_long'),
    0x88: ('DEY',  'impl'),
    0x89: ('BIT',  'imm_m'),
    0x8A: ('TXA',  'impl'),
    0x8B: ('PHB',  'impl'),
    0x8C: ('STY',  'abs'),
    0x8D: ('STA',  'abs'),
    0x8E: ('STX',  'abs'),
    0x8F: ('STA',  'long'),
    0x90: ('BCC',  'rel'),
    0x91: ('STA',  'dp_ind_y'),
    0x92: ('STA',  'dp_ind'),
    0x93: ('STA',  'sr_ind_y'),
    0x94: ('STY',  'dp_x'),
    0x95: ('STA',  'dp_x'),
    0x96: ('STX',  'dp_y'),
    0x97: ('STA',  'dp_ind_long_y'),
    0x98: ('TYA',  'impl'),
    0x99: ('STA',  'abs_y'),
    0x9A: ('TXS',  'impl'),
    0x9B: ('TXY',  'impl'),
    0x9C: ('STZ',  'abs'),
    0x9D: ('STA',  'abs_x'),
    0x9E: ('STZ',  'abs_x'),
    0x9F: ('STA',  'long_x'),
    0xA0: ('LDY',  'imm_x'),
    0xA1: ('LDA',  'dp_x_ind'),
    0xA2: ('LDX',  'imm_x'),
    0xA3: ('LDA',  'sr'),
    0xA4: ('LDY',  'dp'),
    0xA5: ('LDA',  'dp'),
    0xA6: ('LDX',  'dp'),
    0xA7: ('LDA',  'dp_ind_long'),
    0xA8: ('TAY',  'impl'),
    0xA9: ('LDA',  'imm_m'),
    0xAA: ('TAX',  'impl'),
    0xAB: ('PLB',  'impl'),
    0xAC: ('LDY',  'abs'),
    0xAD: ('LDA',  'abs'),
    0xAE: ('LDX',  'abs'),
    0xAF: ('LDA',  'long'),
    0xB0: ('BCS',  'rel'),
    0xB1: ('LDA',  'dp_ind_y'),
    0xB2: ('LDA',  'dp_ind'),
    0xB3: ('LDA',  'sr_ind_y'),
    0xB4: ('LDY',  'dp_x'),
    0xB5: ('LDA',  'dp_x'),
    0xB6: ('LDX',  'dp_y'),
    0xB7: ('LDA',  'dp_ind_long_y'),
    0xB8: ('CLV',  'impl'),
    0xB9: ('LDA',  'abs_y'),
    0xBA: ('TSX',  'impl'),
    0xBB: ('TYX',  'impl'),
    0xBC: ('LDY',  'abs_x'),
    0xBD: ('LDA',  'abs_x'),
    0xBE: ('LDX',  'abs_y'),
    0xBF: ('LDA',  'long_x'),
    0xC0: ('CPY',  'imm_x'),
    0xC1: ('CMP',  'dp_x_ind'),
    0xC2: ('REP',  'imm'),
    0xC3: ('CMP',  'sr'),
    0xC4: ('CPY',  'dp'),
    0xC5: ('CMP',  'dp'),
    0xC6: ('DEC',  'dp'),
    0xC7: ('CMP',  'dp_ind_long'),
    0xC8: ('INY',  'impl'),
    0xC9: ('CMP',  'imm_m'),
    0xCA: ('DEX',  'impl'),
    0xCB: ('WAI',  'impl'),
    0xCC: ('CPY',  'abs'),
    0xCD: ('CMP',  'abs'),
    0xCE: ('DEC',  'abs'),
    0xCF: ('CMP',  'long'),
    0xD0: ('BNE',  'rel'),
    0xD1: ('CMP',  'dp_ind_y'),
    0xD2: ('CMP',  'dp_ind'),
    0xD3: ('CMP',  'sr_ind_y'),
    0xD4: ('PEI',  'dp'),
    0xD5: ('CMP',  'dp_x'),
    0xD6: ('DEC',  'dp_x'),
    0xD7: ('CMP',  'dp_ind_long_y'),
    0xD8: ('CLD',  'impl'),
    0xD9: ('CMP',  'abs_y'),
    0xDA: ('PHX',  'impl'),
    0xDB: ('STP',  'impl'),
    0xDC: ('JML',  'abs_ind_long'),
    0xDD: ('CMP',  'abs_x'),
    0xDE: ('DEC',  'abs_x'),
    0xDF: ('CMP',  'long_x'),
    0xE0: ('CPX',  'imm_x'),
    0xE1: ('SBC',  'dp_x_ind'),
    0xE2: ('SEP',  'imm'),
    0xE3: ('SBC',  'sr'),
    0xE4: ('CPX',  'dp'),
    0xE5: ('SBC',  'dp'),
    0xE6: ('INC',  'dp'),
    0xE7: ('SBC',  'dp_ind_long'),
    0xE8: ('INX',  'impl'),
    0xE9: ('SBC',  'imm_m'),
    0xEA: ('NOP',  'impl'),
    0xEB: ('XBA',  'impl'),
    0xEC: ('CPX',  'abs'),
    0xED: ('SBC',  'abs'),
    0xEE: ('INC',  'abs'),
    0xEF: ('SBC',  'long'),
    0xF0: ('BEQ',  'rel'),
    0xF1: ('SBC',  'dp_ind_y'),
    0xF2: ('SBC',  'dp_ind'),
    0xF3: ('SBC',  'sr_ind_y'),
    0xF4: ('PEA',  'abs'),
    0xF5: ('SBC',  'dp_x'),
    0xF6: ('INC',  'dp_x'),
    0xF7: ('SBC',  'dp_ind_long_y'),
    0xF8: ('SED',  'impl'),
    0xF9: ('SBC',  'abs_y'),
    0xFA: ('PLX',  'impl'),
    0xFB: ('XCE',  'impl'),
    0xFC: ('JSR',  'abs_x_ind'),
    0xFD: ('SBC',  'abs_x'),
    0xFE: ('INC',  'abs_x'),
    0xFF: ('SBC',  'long_x'),
}

# Instructions that end a basic block (no fall-through)
_TERMINATORS = {'JML', 'JMP', 'BRA', 'BRL', 'RTS', 'RTL', 'RTI', 'STP'}
# Instructions that fall through AND branch
_BRANCHES = {'BPL', 'BMI', 'BVC', 'BVS', 'BCC', 'BCS', 'BNE', 'BEQ'}
# Call instructions (fall through after call)
_CALLS = {'JSR', 'JSL'}
# ---------------------------------------------------------------------------

class CPUState:
    """Track 65816 mode flags through static analysis."""
    def __init__(self, m: bool = True, x: bool = True, e: bool = True):
        self.m = m   # accumulator 8-bit when True
        self.x = x   # index 8-bit when True
        self.e = e   # emulation mode when True

    def apply_rep(self, operand: int) -> None:
        if operand & 0x20: self.m = False
        if operand & 0x10: self.x = False

    def apply_sep(self, operand: int) -> None:
        if operand & 0x20: self.m = True
        if operand & 0x10: self.x = True

    def apply_xce(self, carry: bool | None) -> None:
        """XCE swaps carry and emulation bit. carry=None → unknown."""
        if carry is False:
            self.e = False
        elif carry is True:
            self.e = True
        # in native mode, M and X are 1 after switching to emulation,
        # 0 (or last set) after switching to native

    def copy(self) -> 'CPUState':
        return CPUState(self.m, self.x, self.e)

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, CPUState): return NotImplemented
        return (self.m, self.x, self.e) == (other.m, other.x, other.e)

    def __repr__(self) -> str:
        return f"M={'8' if self.m else '16'} X={'8' if self.x else '16'} E={'emu' if self.e else 'nat'}"


def insn_len(mode: str, state: CPUState) -> int:
    """Return total instruction byte length (opcode included)."""
    extra: dict[str, int] = {
        'impl': 0, 'A': 0,
        'imm': 1, 'imm_m': 2 if not state.m else 1, 'imm_x': 2 if not state.x else 1,
        'dp': 1, 'dp_x': 1, 'dp_y': 1,
        'dp_ind': 1, 'dp_x_ind': 1, 'dp_ind_y': 1,
        'dp_ind_long': 1, 'dp_ind_long_y': 1,
        'sr': 1, 'sr_ind_y': 1,
        'abs': 2, 'abs_x': 2, 'abs_y': 2,
        'abs_ind': 2, 'abs_x_ind': 2, 'abs_ind_long': 2,
        'long': 3, 'long_x': 3,
        'rel': 1, 'rlong': 2,
        'block': 2,
    }
    return 1 + extra.get(mode, 0)


def format_operand(op: int, mode: str, pc: int, bank: int, state: CPUState) -> str:
    """Format operand as asar-style assembly text."""
    if mode == 'impl' or mode == 'A':
        return ''
    if mode == 'imm':
        return f'#${op:02X}'
    if mode == 'imm_m':
        if state.m:
            return f'#${op:02X}'
        return f'#${op:04X}'
    if mode == 'imm_x':
        if state.x:
            return f'#${op:02X}'
        return f'#${op:04X}'
    if mode == 'dp':      return f'${op:02X}'
    if mode == 'dp_x':    return f'${op:02X},X'
    if mode == 'dp_y':    return f'${op:02X},Y'
    if mode == 'dp_ind':  return f'(${op:02X})'
    if mode == 'dp_x_ind':return f'(${op:02X},X)'
    if mode == 'dp_ind_y':return f'(${op:02X}),Y'
    if mode == 'dp_ind_long':    return f'[${op:02X}]'
    if mode == 'dp_ind_long_y':  return f'[${op:02X}],Y'
    if mode == 'sr':      return f'${op:02X},S'
    if mode == 'sr_ind_y':return f'(${op:02X},S),Y'
    if mode == 'abs':     return f'${op:04X}'
    if mode == 'abs_x':   return f'${op:04X},X'
    if mode == 'abs_y':   return f'${op:04X},Y'
    if mode == 'abs_ind': return f'(${op:04X})'
    if mode == 'abs_x_ind': return f'(${op:04X},X)'
    if mode == 'abs_ind_long': return f'[${op:04X}]'
    if mode == 'long':    return f'${op:06X}'
    if mode == 'long_x':  return f'${op:06X},X'
    if mode == 'rel':
        offset = op if op < 128 else op - 256
        target = (pc + offset) & 0xFFFF
        return f'${target:04X}'
    if mode == 'rlong':
        offset = op if op < 32768 else op - 65536
        target = (pc + offset) & 0xFFFF
        return f'${target:04X}'
    if mode == 'block':
        src = (op >> 8) & 0xFF
        dst = op & 0xFF
        return f'${src:02X},${dst:02X}'
    return f'${op:X}'


def read_operand(rom: bytes, offset: int, mode: str, state: CPUState) -> tuple[int, int]:
    """Read operand bytes; return (value, bytes_read)."""
    nbytes = insn_len(mode, state) - 1
    if nbytes == 0:
        return 0, 0
    if offset + nbytes > len(rom):
        return 0, 0
    if nbytes == 1:
        return rom[offset], 1
    if nbytes == 2:
        return struct.unpack_from('<H', rom, offset)[0], 2
    if nbytes == 3:
        lo, hi, bk = rom[offset], rom[offset+1], rom[offset+2]
        return lo | (hi << 8) | (bk << 16), 3
    return 0, 0


def branch_target(mode: str, operand: int, pc_after: int) -> int | None:
    """Compute branch target PC (word address within bank) for branch/rel modes."""
    if mode == 'rel':
        offset = operand if operand < 128 else operand - 256
        return (pc_after + offset) & 0xFFFF
    if mode == 'rlong':
        offset = operand if operand < 32768 else operand - 65536
        return (pc_after + offset) & 0xFFFF
    return None


# SNES hardware register names
_HW_REGS: dict[int, str] = {
    0x2100:'INIDISP', 0x2101:'OBSEL',  0x2102:'OAMADDL', 0x2103:'OAMADDH',
    0x2104:'OAMDATA', 0x2105:'BGMODE', 0x2106:'MOSAIC',  0x2107:'BG1SC',
    0x2108:'BG2SC',   0x2109:'BG3SC',  0x210A:'BG4SC',   0x210B:'BG12NBA',
    0x210C:'BG34NBA', 0x210D:'BG1HOFS',0x210E:'BG1VOFS', 0x210F:'BG2HOFS',
    0x2110:'BG2VOFS', 0x2111:'BG3HOFS',0x2112:'BG3VOFS', 0x2113:'BG4HOFS',
    0x2114:'BG4VOFS', 0x2115:'VMAIN',  0x2116:'VMADDL',  0x2117:'VMADDH',
    0x2118:'VMDATAL', 0x2119:'VMDATAH',0x211A:'M7SEL',   0x211B:'M7A',
    0x211C:'M7B',     0x211D:'M7C',    0x211E:'M7D',     0x211F:'M7X',
    0x2120:'M7Y',     0x2121:'CGADD',  0x2122:'CGDATA',  0x2123:'W12SEL',
    0x2124:'W34SEL',  0x2125:'WOBJSEL',0x2126:'WH0',     0x2127:'WH1',
    0x2128:'WH2',     0x2129:'WH3',    0x212A:'WBGLOG',  0x212B:'WOBJLOG',
    0x212C:'TM',      0x212D:'TS',     0x212E:'TMW',     0x212F:'TSW',
    0x2130:'CGWSEL',  0x2131:'CGADSUB',0x2132:'COLDATA', 0x2133:'SETINI',
    0x2134:'MPYL',    0x2135:'MPYM',   0x2136:'MPYH',    0x2137:'SLHV',
    0x2138:'RDOAM',   0x2139:'RDVRAML',0x213A:'RDVRAMH', 0x213B:'RDCGRAM',
    0x213C:'OPHCT',   0x213D:'OPVCT',  0x213E:'STAT77',  0x213F:'STAT78',
    0x2140:'APUIO0',  0x2141:'APUIO1', 0x2142:'APUIO2',  0x2143:'APUIO3',
    0x2180:'WMDATA',  0x2181:'WMADDL', 0x2182:'WMADDM',  0x2183:'WMADDH',
    0x4016:'JOYA',    0x4017:'JOYB',
    0x4200:'NMITIMEN',0x4201:'WRIO',   0x4202:'WRMPYA',  0x4203:'WRMPYB',
    0x4204:'WRDIVL',  0x4205:'WRDIVH', 0x4206:'WRDIVB',
    0x4207:'HTIMEL',  0x4208:'HTIMEH', 0x4209:'VTIMEL',  0x420A:'VTIMEH',
    0x420B:'MDMAEN',  0x420C:'HDMAEN', 0x420D:'MEMSEL',
    0x4210:'RDNMI',   0x4211:'TIMEUP', 0x4212:'HVBJOY',  0x4213:'RDIO',
    0x4214:'RDDIVL',  0x4215:'RDDIVH', 0x4216:'RDMPYL',  0x4217:'RDMPYH',
    0x4218:'JOY1L',   0x4219:'JOY1H',  0x421A:'JOY2L',   0x421B:'JOY2H',
    0x421C:'JOY3L',   0x421D:'JOY3H',  0x421E:'JOY4L',   0x421F:'JOY4H',
}
# DMA channel registers
for _ch in range(8):
    _b = 0x4300 + _ch * 0x10
    _HW_REGS[_b+0] = f'DMAP{_ch}'
    _HW_REGS[_b+1] = f'BBAD{_ch}'
    _HW_REGS[_b+2] = f'A1T{_ch}L'
    _HW_REGS[_b+3] = f'A1T{_ch}H'
    _HW_REGS[_b+4] = f'A1B{_ch}'
    _HW_REGS[_b+5] = f'DAS{_ch}L'
    _HW_REGS[_b+6] = f'DAS{_ch}H'
    _HW_REGS[_b+7] = f'DAS{_ch}B'
    _HW_REGS[_b+8] = f'A2A{_ch}L'
    _HW_REGS[_b+9] = f'A2A{_ch}H'
    _HW_REGS[_b+0xA] = f'NTRL{_ch}'


def hw_comment(mnemonic: str, mode: str, operand: int) -> str:
    """Return a hardware register comment if operand is a known reg address."""
    if mode in ('abs', 'abs_x', 'abs_y') and 0x2100 <= operand <= 0x43FF:
        reg = _HW_REGS.get(operand)
        if reg:
            return f'; {reg}'
    return ''


# ---------------------------------------------------------------------------
# Disassembler core
# ---------------------------------------------------------------------------
class Disassembler:
    def __init__(self, rom: bytes, bank: int):
        self.rom = rom
        self.bank = bank
        # file offset of start of this bank's data in rom
        self.bank_file_start = snes_to_file(bank, 0x0000) or snes_to_file(bank + 0xC0, 0x0000) or 0

        self.visited: dict[int, CPUState] = {}   # addr → state at decode time
        self.insns: dict[int, tuple] = {}         # addr → (bytes, mnemonic, operand_str, hw_note)
        self.calls: set[int] = set()              # JSL/JSR targets (24-bit)
        self.jumps: set[int] = set()              # JML/JMP targets (24-bit)
        self.returns: list[int] = []              # addresses of RTS/RTL/RTI
        self.indirect_jumps: list[int] = []       # addresses of indirect JMP/JML
        self.work: list[tuple[int, CPUState]] = []  # (addr, state) to explore

    def _rom_byte(self, bank: int, addr: int) -> int | None:
        offset = snes_to_file(bank, addr)
        if offset is None or offset >= len(self.rom):
            return None
        return self.rom[offset]

    def _rom_slice(self, bank: int, addr: int, n: int) -> bytes | None:
        offset = snes_to_file(bank, addr)
        if offset is None or offset + n > len(self.rom):
            return None
        return self.rom[offset:offset + n]

    def queue(self, bank: int, addr: int, state: CPUState) -> None:
        if bank == self.bank:
            if addr not in self.visited:
                self.work.append((addr, state.copy()))

    def decode_one(self, addr: int, state: CPUState) -> int | None:
        """Decode instruction at word-address addr; return next addr or None."""
        if addr in self.visited:
            return None
        self.visited[addr] = state.copy()

        raw = self._rom_byte(self.bank, addr)
        if raw is None:
            return None

        entry = _OPCODES.get(raw)
        if entry is None:
            return None
        mnemonic, mode = entry

        # Read operand
        op_offset = snes_to_file(self.bank, (addr + 1) & 0xFFFF)
        if op_offset is None:
            return None
        operand, op_bytes = read_operand(self.rom, op_offset, mode, state)
        total = 1 + op_bytes
        next_addr = (addr + total) & 0xFFFF

        # Format operand string
        op_str = format_operand(operand, mode, next_addr, self.bank, state)
        hw = hw_comment(mnemonic, mode, operand)

        # Collect raw bytes
        raw_bytes = self._rom_slice(self.bank, addr, total) or b''
        self.insns[addr] = (raw_bytes, mnemonic, op_str, hw)

        # --- Update CPU state ---
        new_state = state.copy()
        if mnemonic == 'REP':
            new_state.apply_rep(operand)
        elif mnemonic == 'SEP':
            new_state.apply_sep(operand)
        elif mnemonic == 'XCE':
            # We track carry loosely: CLC before XCE → native mode
            # Without data-flow analysis we just flip emulation mode
            new_state.e = not new_state.e
            if not new_state.e:
                # entering native: M and X from last SEP/REP; leave as-is
                pass
            else:
                # entering emulation: force 8-bit
                new_state.m = True
                new_state.x = True

        # --- Control flow ---
        is_term = mnemonic in _TERMINATORS and mnemonic not in _BRANCHES
        is_branch = mnemonic in _BRANCHES
        is_call = mnemonic in _CALLS

        if mnemonic in ('JSL', 'JML') and mode == 'long':
            target_bank = (operand >> 16) & 0xFF
            target_addr = operand & 0xFFFF
            if mnemonic == 'JSL':
                self.calls.add(operand)
                if target_bank == self.bank:
                    self.queue(self.bank, target_addr, new_state)
            else:  # JML
                self.jumps.add(operand)
                if target_bank == self.bank:
                    self.queue(self.bank, target_addr, new_state)
                return None  # terminates this path

        elif mnemonic == 'JSR' and mode == 'abs':
            target = operand & 0xFFFF
            self.calls.add((self.bank << 16) | target)
            self.queue(self.bank, target, new_state)

        elif mnemonic == 'JMP' and mode == 'abs':
            target = operand & 0xFFFF
            self.jumps.add((self.bank << 16) | target)
            self.queue(self.bank, target, new_state)
            return None

        elif mnemonic in ('JMP', 'JML') and mode in ('abs_ind', 'abs_x_ind', 'abs_ind_long'):
            self.indirect_jumps.append(addr)
            return None

        elif mnemonic == 'BRA' or mnemonic == 'BRL':
            tgt = branch_target(mode, operand, next_addr)
            if tgt is not None:
                self.jumps.add((self.bank << 16) | tgt)
                self.queue(self.bank, tgt, new_state)
            return None

        elif is_branch:
            tgt = branch_target(mode, operand, next_addr)
            if tgt is not None:
                self.jumps.add((self.bank << 16) | tgt)
                self.queue(self.bank, tgt, new_state)
            # Queue fall-through as a separate work item instead of continuing
            # linearly. Linear continuation lets the decoder pass through a
            # REP/SEP inside the loop body and corrupt the M/X state at the
            # branch target — the classic "loop-exit BEQ" trap. By terminating
            # here and re-queuing the fall-through, both paths start from the
            # correct state captured at the branch instruction.
            self.queue(self.bank, next_addr, new_state)
            return None

        elif mnemonic in ('RTS', 'RTL', 'RTI'):
            self.returns.append(addr)
            return None

        elif mnemonic == 'STP':
            return None

        return next_addr if not is_term else None

    def trace(self, entries: list[int]) -> None:
        """Trace from a list of word-address entry points."""
        for e in entries:
            self.work.append((e, CPUState(m=True, x=True, e=True)))

        while self.work:
            addr, state = self.work.pop()
            if addr in self.visited:
                continue
            cur = addr
            cur_state = state.copy()
            while cur is not None:
                if cur in self.visited:
                    break  # already decoded from here; stop this path
                nxt = self.decode_one(cur, cur_state)
                if nxt is not None:
                    # propagate REP/SEP/XCE state changes forward
                    raw = self.rom[snes_to_file(self.bank, cur)]
                    op_tbl = _OPCODES.get(raw)
                    if op_tbl and op_tbl[0] == 'REP':
                        op_offset = snes_to_file(self.bank, (cur + 1) & 0xFFFF)
                        cur_state.apply_rep(self.rom[op_offset])
                    elif op_tbl and op_tbl[0] == 'SEP':
                        op_offset = snes_to_file(self.bank, (cur + 1) & 0xFFFF)
                        cur_state.apply_sep(self.rom[op_offset])
                    elif op_tbl and op_tbl[0] == 'XCE':
                        cur_state.apply_xce(not cur_state.m)
                cur = nxt

    def print_disasm(self, out=sys.stdout) -> None:
        """Print sorted disassembly of all visited instructions."""
        sorted_addrs = sorted(self.insns)
        prev = None
        for addr in sorted_addrs:
            if prev is not None and addr != prev:
                out.write(f'\n; --- gap: ${prev:04X}–${addr-1:04X} ---\n\n')
            raw_bytes, mnemonic, op_str, hw = self.insns[addr]
            hex_str = ' '.join(f'{b:02X}' for b in raw_bytes)
            asm = f'{mnemonic} {op_str}'.rstrip()
            out.write(f'${self.bank:02X}:{addr:04X}  {hex_str:<12}  {asm:<20} {hw}\n')
            prev = addr + len(raw_bytes)

    def print_summary(self, out=sys.stderr) -> None:
        out.write('\n' + '='*60 + '\n')
        out.write(f'BANK ${self.bank:02X} SWEEP SUMMARY\n')
        out.write('='*60 + '\n')

        out.write(f'\nInstructions traced: {len(self.insns)}\n')
        out.write(f'Unique addresses visited: {len(self.visited)}\n')

        out.write('\nJSL/JSR call targets:\n')
        for t in sorted(self.calls):
            bk, ad = (t >> 16), t & 0xFFFF
            out.write(f'  ${bk:02X}:{ad:04X}\n')

        out.write('\nJML/JMP jump targets:\n')
        for t in sorted(self.jumps):
            bk, ad = (t >> 16), t & 0xFFFF
            out.write(f'  ${bk:02X}:{ad:04X}\n')

        out.write('\nRTS/RTL/RTI locations:\n')
        for a in sorted(self.returns):
            out.write(f'  ${self.bank:02X}:{a:04X}\n')

        if self.indirect_jumps:
            out.write('\nIndirect jumps (targets unknown without runtime):\n')
            for a in sorted(self.indirect_jumps):
                out.write(f'  ${self.bank:02X}:{a:04X}\n')


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    rom_path = Path(sys.argv[1])
    if not rom_path.is_file():
        print(f'error: ROM not found: {rom_path}')
        return 2

    rom = rom_path.read_bytes()
    # strip 512-byte copier header if present
    if len(rom) % 1024 == 512 and len(rom) > 512:
        remainder = len(rom) - 512
        if remainder in (0x80000, 0x100000, 0x200000, 0x300000, 0x400000):
            rom = rom[512:]

    bank = int(sys.argv[2], 16)

    # Determine ROM range for this bank
    rom_start = snes_to_file(bank, 0x8000) if bank < 0x80 else snes_to_file(bank, 0x0000)
    if rom_start is None:
        rom_start = snes_to_file(bank + 0xC0, 0x0000) or 0
    rom_end = rom_start + 0x8000 if bank < 0x80 else rom_start + 0x10000

    entries: list[int] = []
    if len(sys.argv) > 3:
        entries = [int(a, 16) for a in sys.argv[3:]]
    else:
        # Linear scan mode: find every possible instruction start
        # (heuristic: just queue every byte as a potential entry for completeness)
        start_addr = 0x8000 if bank < 0x80 else 0x0000
        entries = list(range(start_addr, start_addr + (rom_end - rom_start), 1))

    d = Disassembler(rom, bank)
    d.trace(entries)
    d.print_disasm()
    d.print_summary()
    return 0


if __name__ == '__main__':
    sys.exit(main())
