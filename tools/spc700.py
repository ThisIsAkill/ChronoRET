#!/usr/bin/env python3
"""
spc700.py — SPC700 decoder and disassembler (asar `arch spc700` syntax).

The sound driver in bank $C7 is SPC700 code: Audio_Boot uploads it from
$C7:24C3 (a length word, then $1BEF bytes) to ARAM $0200 and starts it there.
tools/disasm.py is 65816-only; this module is its SPC700 counterpart, used by
`tools/disasm.py --spc700` and by tools/test_spc700.py.

Source is written for asar's spc700 mode with explicit widths: `.b` on every
direct-page operand and `.w` on every absolute one, so the encoding never
depends on how a value or a define happens to be written. Every one of the
256 opcodes has one encoding, and the table below is checked against asar
by tools/test_spc700.py.

Usage:
    python3 tools/spc700.py [START [END]] [--entry ARAM ...] [--linear] [--check]
    python3 tools/disasm.py --spc700 [START [END]] [...]

    START/END   ARAM addresses (hex) of the range to print, default the
                whole driver ($0200-$1DEE); END is inclusive.
    --entry     trace from these ARAM addresses (recursive descent). The
                default is the driver's known entries: $0200 and the
                targets of its dispatch tables (DRIVER_ENTRIES and
                DISPATCH_TABLES below). Bytes no traced path reaches are
                printed as `db`.
    --linear    decode the range from START straight through instead.
    --check     assemble what was printed (on a blank image) and confirm
                it gives the ROM's bytes for the range.
"""

import argparse
import re
import sys
from pathlib import Path

ROM_PATH = Path('roms/chrono_trigger.sfc')

# The uploaded driver block: boot block 0 of Audio_BootBlockPtrs.
DRIVER_ROM = 0x0724C3          # file offset of the length word ($C7:24C3)
DRIVER_ARAM = 0x0200           # where Audio_Boot puts it, and its entry point

# Where the trace starts besides $0200: code reached only by a RET into an
# address pushed beforehand (the dispatchers push a table entry, or a fixed
# return address, and RET to it). Each table is (ARAM address, entries);
# zero entries are "none". See the NEXT.md SPC700 item for the evidence.
DISPATCH_TABLES = [
    (0x1544, 8),    # transfer modes (APUIO1 & 7), pushed at $105D/$1061
    (0x1554, 60),   # sequence commands $C4-$FF, pushed at $0743/$0747
    (0x1608, 60),   # their second handlers (0 = none), pushed at $077D/$078D
    (0x1680, 16),   # CPU commands $10-$1F, pushed at $0BC2/$0BC6
    (0x16A0, 16),   # their first-run handlers (0 = none), pushed at $0BCA/$0BD0
    (0x16C0, 32),   # CPU commands $80-$8F and $F0-$FF, pushed at $0E08/$0E0C
]
DRIVER_ENTRIES = [
    0x0200,         # Audio_Boot starts the driver here
    0x0768,         # return address pushed at $0784/$0787
    0x1029,         # return address pushed at $1057/$105A
]
# The driver's code and data, as the trace from those entries finds them:
# every byte of the code ranges is reached, no byte of the data ranges is.
CODE_RANGES = [(0x0200, 0x1543), (0x1722, 0x1D6C)]
DATA_RANGES = [(0x1544, 0x1721), (0x1D6D, 0x1DEE)]


def driver_block(rom: bytes) -> tuple[int, int, int]:
    """(file offset of the first program byte, ARAM start, length)."""
    length = rom[DRIVER_ROM] | rom[DRIVER_ROM + 1] << 8
    return DRIVER_ROM + 2, DRIVER_ARAM, length


def aram_to_rom(aram: int, rom: bytes) -> int:
    start, base, length = driver_block(rom)
    if not base <= aram < base + length:
        raise ValueError(f'ARAM ${aram:04X} is outside the driver block')
    return start + aram - base


def driver_entries(mem: bytes, base: int = DRIVER_ARAM) -> list[int]:
    """DRIVER_ENTRIES plus every nonzero entry of DISPATCH_TABLES."""
    out = list(DRIVER_ENTRIES)
    for table, count in DISPATCH_TABLES:
        for k in range(count):
            a = table + 2 * k - base
            word = mem[a] | mem[a + 1] << 8
            if word:
                out.append(word)
    return out


# ── Opcode table ─────────────────────────────────────────────────────────────
#
# opcode -> (mnemonic, operand template, operand byte layout)
# The layout lists the operand bytes in ROM order, one letter each:
#   d  direct-page byte        a  absolute word (2 letters' worth: 'a' = 2 bytes)
#   i  immediate byte          r  relative branch byte
#   m  mem.bit word (13-bit address, bit number in bits 13-15)
#   u  PCALL byte (address $FFxx)
# The template refers to the operands in layout order as {0}, {1}, ...;
# TCALL and the bit number of SET1/CLR1/BBS/BBC come from the opcode.

def _build() -> dict[int, tuple[str, str, str]]:
    t: dict[int, tuple[str, str, str]] = {}
    for n in range(16):
        t[n << 4 | 0x01] = ('tcall', str(n), '')
        bit = n >> 1
        t[n << 4 | 0x02] = ('clr1' if n & 1 else 'set1', f'{{0}}.{bit}', 'd')
        t[n << 4 | 0x03] = ('bbc' if n & 1 else 'bbs', f'{{0}}.{bit},{{1}}', 'dr')
    alu = ['or', 'and', 'eor', 'cmp', 'adc', 'sbc']
    for k, op in enumerate(alu):
        hi = k << 5
        t[hi | 0x04] = (op, 'a,{0}', 'd')
        t[hi | 0x05] = (op, 'a,{0}', 'a')
        t[hi | 0x06] = (op, 'a,(x)', '')
        t[hi | 0x07] = (op, 'a,({0}+x)', 'd')
        t[hi | 0x08] = (op, 'a,#{0}', 'i')
        t[hi | 0x09] = (op, '{1},{0}', 'dd')
        t[hi | 0x14] = (op, 'a,{0}+x', 'd')
        t[hi | 0x15] = (op, 'a,{0}+x', 'a')
        t[hi | 0x16] = (op, 'a,{0}+y', 'a')
        t[hi | 0x17] = (op, 'a,({0})+y', 'd')
        t[hi | 0x18] = (op, '{1},#{0}', 'id')
        t[hi | 0x19] = (op, '(x),(y)', '')
    rows = {
        0x00: ('nop', '', ''), 0x0A: ('or1', 'c,{0}', 'm'), 0x0B: ('asl', '{0}', 'd'),
        0x0C: ('asl', '{0}', 'a'), 0x0D: ('push', 'p', ''), 0x0E: ('tset', '{0},a', 'a'),
        0x0F: ('brk', '', ''),
        0x10: ('bpl', '{0}', 'r'), 0x1A: ('decw', '{0}', 'd'), 0x1B: ('asl', '{0}+x', 'd'),
        0x1C: ('asl', 'a', ''), 0x1D: ('dec', 'x', ''), 0x1E: ('cmp', 'x,{0}', 'a'),
        0x1F: ('jmp', '({0}+x)', 'a'),
        0x20: ('clrp', '', ''), 0x2A: ('or1', 'c,!{0}', 'm'), 0x2B: ('rol', '{0}', 'd'),
        0x2C: ('rol', '{0}', 'a'), 0x2D: ('push', 'a', ''), 0x2E: ('cbne', '{0},{1}', 'dr'),
        0x2F: ('bra', '{0}', 'r'),
        0x30: ('bmi', '{0}', 'r'), 0x3A: ('incw', '{0}', 'd'), 0x3B: ('rol', '{0}+x', 'd'),
        0x3C: ('rol', 'a', ''), 0x3D: ('inc', 'x', ''), 0x3E: ('cmp', 'x,{0}', 'd'),
        0x3F: ('call', '{0}', 'a'),
        0x40: ('setp', '', ''), 0x4A: ('and1', 'c,{0}', 'm'), 0x4B: ('lsr', '{0}', 'd'),
        0x4C: ('lsr', '{0}', 'a'), 0x4D: ('push', 'x', ''), 0x4E: ('tclr', '{0},a', 'a'),
        0x4F: ('pcall', '{0}', 'u'),
        0x50: ('bvc', '{0}', 'r'), 0x5A: ('cmpw', 'ya,{0}', 'd'), 0x5B: ('lsr', '{0}+x', 'd'),
        0x5C: ('lsr', 'a', ''), 0x5D: ('mov', 'x,a', ''), 0x5E: ('cmp', 'y,{0}', 'a'),
        0x5F: ('jmp', '{0}', 'a'),
        0x60: ('clrc', '', ''), 0x6A: ('and1', 'c,!{0}', 'm'), 0x6B: ('ror', '{0}', 'd'),
        0x6C: ('ror', '{0}', 'a'), 0x6D: ('push', 'y', ''), 0x6E: ('dbnz', '{0},{1}', 'dr'),
        0x6F: ('ret', '', ''),
        0x70: ('bvs', '{0}', 'r'), 0x7A: ('addw', 'ya,{0}', 'd'), 0x7B: ('ror', '{0}+x', 'd'),
        0x7C: ('ror', 'a', ''), 0x7D: ('mov', 'a,x', ''), 0x7E: ('cmp', 'y,{0}', 'd'),
        0x7F: ('reti', '', ''),
        0x80: ('setc', '', ''), 0x8A: ('eor1', 'c,{0}', 'm'), 0x8B: ('dec', '{0}', 'd'),
        0x8C: ('dec', '{0}', 'a'), 0x8D: ('mov', 'y,#{0}', 'i'), 0x8E: ('pop', 'p', ''),
        0x8F: ('mov', '{1},#{0}', 'id'),
        0x90: ('bcc', '{0}', 'r'), 0x9A: ('subw', 'ya,{0}', 'd'), 0x9B: ('dec', '{0}+x', 'd'),
        0x9C: ('dec', 'a', ''), 0x9D: ('mov', 'x,sp', ''), 0x9E: ('div', 'ya,x', ''),
        0x9F: ('xcn', 'a', ''),
        0xA0: ('ei', '', ''), 0xAA: ('mov1', 'c,{0}', 'm'), 0xAB: ('inc', '{0}', 'd'),
        0xAC: ('inc', '{0}', 'a'), 0xAD: ('cmp', 'y,#{0}', 'i'), 0xAE: ('pop', 'a', ''),
        0xAF: ('mov', '(x+),a', ''),
        0xB0: ('bcs', '{0}', 'r'), 0xBA: ('movw', 'ya,{0}', 'd'), 0xBB: ('inc', '{0}+x', 'd'),
        0xBC: ('inc', 'a', ''), 0xBD: ('mov', 'sp,x', ''), 0xBE: ('das', 'a', ''),
        0xBF: ('mov', 'a,(x+)', ''),
        0xC0: ('di', '', ''), 0xC4: ('mov', '{0},a', 'd'), 0xC5: ('mov', '{0},a', 'a'),
        0xC6: ('mov', '(x),a', ''), 0xC7: ('mov', '({0}+x),a', 'd'), 0xC8: ('cmp', 'x,#{0}', 'i'),
        0xC9: ('mov', '{0},x', 'a'), 0xCA: ('mov1', '{0},c', 'm'), 0xCB: ('mov', '{0},y', 'd'),
        0xCC: ('mov', '{0},y', 'a'), 0xCD: ('mov', 'x,#{0}', 'i'), 0xCE: ('pop', 'x', ''),
        0xCF: ('mul', 'ya', ''),
        0xD0: ('bne', '{0}', 'r'), 0xD4: ('mov', '{0}+x,a', 'd'), 0xD5: ('mov', '{0}+x,a', 'a'),
        0xD6: ('mov', '{0}+y,a', 'a'), 0xD7: ('mov', '({0})+y,a', 'd'), 0xD8: ('mov', '{0},x', 'd'),
        0xD9: ('mov', '{0}+y,x', 'd'), 0xDA: ('movw', '{0},ya', 'd'), 0xDB: ('mov', '{0}+x,y', 'd'),
        0xDC: ('dec', 'y', ''), 0xDD: ('mov', 'a,y', ''), 0xDE: ('cbne', '{0}+x,{1}', 'dr'),
        0xDF: ('daa', 'a', ''),
        0xE0: ('clrv', '', ''), 0xE4: ('mov', 'a,{0}', 'd'), 0xE5: ('mov', 'a,{0}', 'a'),
        0xE6: ('mov', 'a,(x)', ''), 0xE7: ('mov', 'a,({0}+x)', 'd'), 0xE8: ('mov', 'a,#{0}', 'i'),
        0xE9: ('mov', 'x,{0}', 'a'), 0xEA: ('not1', '{0}', 'm'), 0xEB: ('mov', 'y,{0}', 'd'),
        0xEC: ('mov', 'y,{0}', 'a'), 0xED: ('notc', '', ''), 0xEE: ('pop', 'y', ''),
        0xEF: ('sleep', '', ''),
        0xF0: ('beq', '{0}', 'r'), 0xF4: ('mov', 'a,{0}+x', 'd'), 0xF5: ('mov', 'a,{0}+x', 'a'),
        0xF6: ('mov', 'a,{0}+y', 'a'), 0xF7: ('mov', 'a,({0})+y', 'd'), 0xF8: ('mov', 'x,{0}', 'd'),
        0xF9: ('mov', 'x,{0}+y', 'd'), 0xFA: ('mov', '{1},{0}', 'dd'), 0xFB: ('mov', 'y,{0}+x', 'd'),
        0xFC: ('inc', 'y', ''), 0xFD: ('mov', 'y,a', ''), 0xFE: ('dbnz', 'y,{0}', 'r'),
        0xFF: ('stop', '', ''),
    }
    for k, v in rows.items():
        assert k not in t, f'{k:02X} twice'
        t[k] = v
    # $x0 rows with odd high nibble are the 8 conditional branches (set above),
    # even ones the flag instructions; all 256 are now defined.
    assert len(t) == 256, sorted(set(range(256)) - set(t))
    return t


OPCODES = _build()
SIZES = {'d': 1, 'i': 1, 'r': 1, 'u': 1, 'a': 2, 'm': 2}


def length(op: int) -> int:
    return 1 + sum(SIZES[k] for k in OPCODES[op][2])


# Flow: no fall-through after these; calls return.
TERMINATORS = {'bra', 'jmp', 'ret', 'reti', 'brk', 'stop', 'sleep'}
CALLS = {'call', 'pcall', 'tcall'}
# Mnemonics with both a direct-page and an absolute form of the same operand:
# those get an explicit width so a define can't change the encoding. The
# rest get one too (asar accepts it), for uniformity.
WIDTH_KINDS = {'d': '.b', 'a': '.w'}


class Insn:
    """One decoded instruction at an ARAM address."""

    def __init__(self, data: bytes, pc: int):
        self.pc = pc
        self.op = data[0]
        self.mnemonic, self.template, self.layout = OPCODES[self.op]
        self.size = length(self.op)
        self.raw = bytes(data[:self.size])
        self.values = []
        k = 1
        for kind in self.layout:
            if SIZES[kind] == 2:
                self.values.append(self.raw[k] | self.raw[k + 1] << 8)
            else:
                self.values.append(self.raw[k])
            k += SIZES[kind]

    @property
    def end(self) -> int:
        return self.pc + self.size

    def branch_target(self):
        """ARAM target of a relative branch (the last 'r' operand), or None."""
        if 'r' not in self.layout:
            return None
        rel = self.values[self.layout.index('r')]
        return (self.end + (rel - 256 if rel >= 128 else rel)) & 0xFFFF

    def jump_target(self):
        """Static target of JMP abs / CALL abs / PCALL, or None."""
        if self.op in (0x5F, 0x3F):
            return self.values[0]
        if self.op == 0x4F:
            return 0xFF00 | self.values[0]
        return None

    @property
    def falls_through(self) -> bool:
        return self.mnemonic not in TERMINATORS

    def text(self, name=None) -> str:
        """asar source; name(kind, value) may return a symbol for an operand."""
        parts = []
        for kind, value in zip(self.layout, self.values):
            sym = name(kind, value, self) if name else None
            if kind == 'r':
                tgt = self.branch_target()
                parts.append(sym or f'${tgt:04X}')
            elif kind == 'm':
                addr, bit = value & 0x1FFF, value >> 13
                parts.append(f'{sym or f"${addr:04X}"}.{bit}')
            elif kind == 'a':
                parts.append(sym or f'${value:04X}')
            elif kind == 'u':
                parts.append(sym or f'${0xFF00 | value:04X}')
            else:
                parts.append(sym or f'${value:02X}')
        operand = self.template.format(*parts)
        widths = {WIDTH_KINDS[k] for k in self.layout if k in WIDTH_KINDS}
        mnem = self.mnemonic + (widths.pop() if len(widths) == 1 else '')
        return f'{mnem} {operand}'.rstrip()


def decode(data: bytes, pc: int) -> Insn:
    return Insn(data, pc)


# ── Disassembly ──────────────────────────────────────────────────────────────

def trace(mem: bytes, base: int, entries: list[int]) -> dict[int, Insn]:
    """Recursive descent over mem (loaded at ARAM base) from entries."""
    end = base + len(mem)
    insns: dict[int, Insn] = {}
    todo = list(entries)
    while todo:
        pc = todo.pop()
        while base <= pc < end and pc not in insns:
            if pc + length(mem[pc - base]) > end:
                break
            ins = decode(mem[pc - base:], pc)
            insns[pc] = ins
            for tgt in (ins.branch_target(), ins.jump_target()):
                if tgt is not None and base <= tgt < end:
                    todo.append(tgt)
            if not ins.falls_through:
                break
            pc = ins.end
    return insns


def linear(mem: bytes, base: int, start: int, stop: int) -> dict[int, Insn]:
    insns, pc = {}, start
    while pc < stop and pc + length(mem[pc - base]) <= stop:
        insns[pc] = decode(mem[pc - base:], pc)
        pc = insns[pc].end
    return insns


def render(mem: bytes, base: int, start: int, stop: int, insns: dict[int, Insn],
           labels: dict[int, str] | None = None) -> list[str]:
    """asar source for ARAM start..stop-1: instructions where decoded, db elsewhere.

    Branch/jump targets inside the range get `.loc_XXXX` labels (globals from
    `labels` win); everything else keeps its address. A target that lands
    inside another printed instruction (code that branches into an operand
    byte) is written as that instruction's label plus the offset. The caller
    supplies the `arch spc700` / `base` lines.
    """
    labels = dict(labels or {})
    in_range = {pc: i for pc, i in insns.items() if start <= pc and i.end <= stop}
    # The printed stream: decoded instructions where they start, bytes elsewhere.
    stream, pc = [], start
    while pc < stop:
        if pc in in_range:
            stream.append((pc, in_range[pc]))
            pc = in_range[pc].end
        else:
            stream.append((pc, None))
            pc += 1
    printed = {pc: ins for pc, ins in stream if ins is not None}
    inside = {}
    for pc, ins in printed.items():
        for k in range(1, ins.size):
            inside[pc + k] = pc
    # Globals: the range start, call and jump targets, entries given by the
    # caller; a branch that would cross a global gets a global target too
    # (asar's .local labels belong to the global above them).
    glob = {pc for pc, name in labels.items() if not name.startswith('.')} | {start}
    for ins in printed.values():
        tgt = ins.jump_target()
        if tgt in printed:
            glob.add(tgt)
    changed = True
    while changed:
        changed = False
        order = sorted(glob)
        owner = lambda a: max((g for g in order if g <= a), default=start)  # noqa: E731
        for pc, ins in printed.items():
            tgt = ins.branch_target()
            if tgt is not None and start <= tgt < stop:
                host = tgt if tgt in printed else inside.get(tgt)
                if host is not None and owner(host) != owner(pc) and host not in glob:
                    glob.add(host)
                    changed = True
    for g in glob:
        labels.setdefault(g, f'Spc_{g:04X}')
    refs = {}
    for ins in printed.values():
        for tgt in (ins.branch_target(), ins.jump_target()):
            if tgt is None or not start <= tgt < stop or tgt in refs:
                continue
            if tgt in printed:
                labels.setdefault(tgt, f'.loc_{tgt:04X}')
                refs[tgt] = labels[tgt]
            elif tgt in inside:
                host = inside[tgt]
                labels.setdefault(host, f'.loc_{host:04X}')
                refs[tgt] = f'{labels[host]}+{tgt - host}'

    def name(kind, value, ins):
        if kind == 'r':
            return refs.get(ins.branch_target())
        if kind == 'a' and ins.jump_target() is not None:
            return refs.get(value)
        if kind == 'u':
            return refs.get(0xFF00 | value)
        return None

    out, pending = [], []

    def flush():
        while pending:
            chunk, pending[:] = pending[:8], pending[8:]
            out.append('    db ' + ','.join(f'${b:02X}' for b in chunk))

    for pc, ins in stream:
        if pc in labels:
            flush()
            out.append(f'{labels[pc]}:')
        if ins is not None:
            flush()
            out.append(f'    {ins.text(name):<36}; ${pc:04X}: {ins.raw.hex(" ")}')
        else:
            pending.append(mem[pc - base])
    flush()
    return out


def source(mem: bytes, base: int, first: int, start: int, stop: int,
           insns: dict[int, Insn]) -> list[str]:
    """A complete asar snippet for ARAM start..stop-1 (org at its ROM address)."""
    rom_addr = 0xC00000 | first + start - base
    return ([f'; ARAM ${start:04X}-${stop - 1:04X} (ROM ${rom_addr >> 16:02X}:{rom_addr & 0xFFFF:04X})',
             'hirom', f'org ${rom_addr:06X}', 'arch spc700', f'base ${start:04X}']
            + render(mem, base, start, stop, insns) + ['base off', 'arch 65816'])


def check(lines: list[str], rom: bytes, first: int, base: int, start: int, stop: int) -> str | None:
    """Assemble the snippet onto a blank image; None if it gives the ROM's bytes."""
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        asm, img = Path(tmp) / 'spc.asm', Path(tmp) / 'spc.sfc'
        asm.write_text('\n'.join(lines) + '\n')
        img.write_bytes(bytes(len(rom)))
        r = subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', str(asm), str(img)],
                           capture_output=True, text=True)
        if r.returncode:
            return (r.stdout + r.stderr).strip()
        out = img.read_bytes()
    lo, hi = first + start - base, first + stop - base
    if out[lo:hi] != rom[lo:hi]:
        bad = next(i for i in range(lo, hi) if out[i] != rom[i])
        return f'differs at ARAM ${bad - first + base:04X}: ${out[bad]:02X}, ROM ${rom[bad]:02X}'
    return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    ap.add_argument('start', nargs='?', help='first ARAM address (hex), default the driver start')
    ap.add_argument('end', nargs='?', help='last ARAM address (hex, inclusive)')
    ap.add_argument('--entry', action='append', default=[], help='trace from this ARAM address')
    ap.add_argument('--linear', action='store_true', help='decode the range straight through')
    ap.add_argument('--check', action='store_true', help='reassemble the output and compare')
    ap.add_argument('--rom', default=str(ROM_PATH))
    args = ap.parse_args(argv)

    rom = Path(args.rom).read_bytes()
    first, base, size = driver_block(rom)
    mem = rom[first:first + size]
    parse = lambda s: int(s.lstrip('$'), 16)  # noqa: E731
    start = parse(args.start) if args.start else base
    stop = parse(args.end) + 1 if args.end else base + size
    if not (base <= start < stop <= base + size):
        print(f'error: range must lie in ${base:04X}-${base + size - 1:04X}', file=sys.stderr)
        return 2
    if args.linear:
        insns = linear(mem, base, start, stop)
    else:
        insns = trace(mem, base, [parse(e) for e in args.entry] or driver_entries(mem, base))
    lines = source(mem, base, first, start, stop, insns)
    print('\n'.join(lines))
    if args.check:
        err = check(lines, rom, first, base, start, stop)
        print(f'; check: {err or "reassembles to the ROM bytes"}', file=sys.stderr)
        return 1 if err else 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
