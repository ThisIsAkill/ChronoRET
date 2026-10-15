#!/usr/bin/env python3
"""
c3module.py — Trace and disassembly of the unpacked $C3 module.

The bank $C3 module (BankC3_PackedModule, packed at $C3:1313) runs from WRAM
$7E:3000-$7E:B57E once C3_BootModule has unpacked it (tools/c3pack.py has
the format and the build). It is 65816 code and data mixed. This tool finds
its code the way tools/spc700.py does for the sound driver: a recursive
trace, with the M and X widths tracked (REP, SEP, PHP/PLP), from its known
entries:

  ENTRIES          where control enters from outside: C3_BootModule's JML
                   to $7E:3000, and the module routines the kernel calls by
                   address (the C3Mod_* stubs of ram_engine.inc);
  DISPATCH_TABLES  word tables of module addresses that code jumps through
                   (JSR (table,X)); every entry is traced.

A call (JSR, JSL into $7E) is assumed to return with the widths it was
entered with, except the callees in CALL_EXITS. A path (the straight run
from a branch point: an entry, a branch target or a call target) that
decodes BRK, COP, WDM or STP, runs off the module or enters DATA_RANGES is
dropped whole, back to that branch point, and reported (`--anomalies`): it
is a wrong guess at a width, or data; so is any path that runs into a
dropped one. Paths queued from a dropped path (its branch and call
targets) are still traced on their own. The anomalies found so far are
handled in CALL_EXITS ($45D6 returns with M=0, so C3Mod_Prog0's BIT at
$3C57 is 16-bit) and DATA_RANGES (the staff text, which a JSR $B574 at
$82A5 reaches; its path, $8280 on, is kept but looks mis-decoded: a PLB
with no PHB follows; open).

The traced instruction bytes are the module's known code; tools/progress.py
counts the matched code against them together with any matched code the
trace has not reached yet. Code reached only through addresses the program
stores at run time (its task lists C3_TaskList, C3_NmiTaskList, C3_ScratchF0
calls) is found as entries are added here, so the figure is a lower bound
that grows as the module is read.

Usage:
    python3 tools/c3module.py [START [END]] [--linear] [--m 0|1 --x 0|1]
    python3 tools/c3module.py --summary
    python3 tools/c3module.py --anomalies

    START/END  module addresses (hex, $7E bank implied; END exclusive), printed
               as asar source with raw operands and explicit widths: traced
               instructions where the trace reached, `db` elsewhere.
    --linear   decode START..END straight through with the given widths.
"""

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import c3pack  # noqa: E402
from disasm import _OPCODES  # noqa: E402

BASE = 0x3000                   # module addresses are 16-bit, in bank $7E
BANK = 0x7E
SIZE = c3pack.MODULE_SIZE

# (address, M=1?, X=1?, what enters there)
ENTRIES = [
    (0x3000, True, False, 'C3_BootModule: JML C3Mod_Code with M=1, X=0'),
    (0x377A, True, False, 'C3Mod_AudioCommand, JSL from the kernel'),
    (0x37F3, True, False, 'C3Mod_CallW, JSL from the kernel'),
    (0x398A, True, False, 'C3Mod_RunTasks, JSL from C3_ModuleFrame'),
    (0x39BE, True, False, 'C3Mod_RunNmiTasks, JSL from C3_ModuleNmi'),
]
# (table, entries, M=1?, X=1?, dispatcher)
DISPATCH_TABLES = [
    (0x3043, 16, True, False, 'the programs, JSR ($3043,X) at $300A (C3_EntryArg bits 0-4)'),
]
# Known anomalies, handled so that the trace decodes them right:
# callees that do not return with the widths they were entered with:
# {address: (M=1 after?, X=1 after?)}, None = as on entry.
CALL_EXITS = {
    0x45D6: (False, None),      # REP #$20 at $4604, then JMP $4309, whose RTS is at M=0
                                # (so C3Mod_Prog0's BIT #$40 at $3C57 is 16-bit)
}
# Data no path may enter: (first, last, what). A path that reaches it is
# dropped as an anomaly.
DATA_RANGES = [
    (0xAADE, 0xB57E, 'the staff text ("EXECUTIVE PRODUCER/..." to "CODE END 7E")'),
]

BRANCHES = {'BPL', 'BMI', 'BVC', 'BVS', 'BCC', 'BCS', 'BNE', 'BEQ'}
STOPS = {'RTS', 'RTL', 'RTI'}
BAD = {'BRK', 'COP', 'WDM', 'STP'}
EXTRA = {'impl': 0, 'A': 0, 'imm': 1, 'abs': 2, 'abs_x': 2, 'abs_y': 2, 'abs_ind': 2,
         'abs_x_ind': 2, 'abs_ind_long': 2, 'long': 3, 'long_x': 3, 'rel': 1, 'rlong': 2,
         'block': 2}


@dataclass
class Insn:
    pc: int
    mnemonic: str
    mode: str
    size: int
    operand: int
    m: bool
    x: bool

    def target(self) -> int | None:
        """The module address a branch, JSR, JMP, JSL or JML goes to, if any."""
        nxt = self.pc + self.size
        if self.mode == 'rel':
            return (nxt + (self.operand ^ 0x80) - 0x80) & 0xFFFF
        if self.mode == 'rlong':
            return (nxt + (self.operand ^ 0x8000) - 0x8000) & 0xFFFF
        if self.mnemonic in ('JSR', 'JMP') and self.mode == 'abs':
            return self.operand
        if self.mnemonic in ('JSL', 'JML') and self.mode == 'long' and self.operand >> 16 == BANK:
            return self.operand & 0xFFFF
        return None


def module_bytes() -> bytes:
    """The ROM's module, unpacked."""
    rom = c3pack.ROM_PATH.read_bytes()
    return c3pack.unpack(rom, c3pack.MODULE_ROM)[0]


def decode(mem: bytes, pc: int, m: bool, x: bool) -> Insn | None:
    if not BASE <= pc < BASE + len(mem):
        return None
    op = mem[pc - BASE]
    mnemonic, mode = _OPCODES[op]
    if mode == 'imm_m':
        n = 1 if m else 2
    elif mode == 'imm_x':
        n = 1 if x else 2
    else:
        n = EXTRA.get(mode, 1)
    if pc + 1 + n > BASE + len(mem):
        return None
    value = int.from_bytes(mem[pc + 1 - BASE:pc + 1 + n - BASE], 'little')
    return Insn(pc, mnemonic, mode, 1 + n, value, m, x)


def table_entries(mem: bytes) -> list[tuple[int, bool, bool]]:
    out = []
    for table, count, m, x, _ in DISPATCH_TABLES:
        for k in range(count):
            a = table + 2 * k - BASE
            out.append((mem[a] | mem[a + 1] << 8, m, x))
    return out


def trace(mem: bytes, entries=None):
    """({pc: Insn} reached, [(pc, reason)] anomalies). A path that hits an
    anomaly is dropped back to its last branch point."""
    if entries is None:
        entries = [(a, m, x) for a, m, x, _ in ENTRIES] + table_entries(mem)
    insns: dict[int, Insn] = {}
    seen = set()
    dropped = set()                     # states on a path that ended in an anomaly
    kept = []                           # (instructions, states, the state it ran into)
    anomalies = []
    data = {a for lo, hi, _ in DATA_RANGES for a in range(lo, hi + 1)}
    work = [(a, m, x, ()) for a, m, x in entries]
    while work:
        pc, m, x, stack = work.pop()
        path = []
        ok = True
        states = []
        join = None
        while True:
            if (pc, m, x) in seen:
                join = (pc, m, x)               # runs into a path traced before
                break
            seen.add((pc, m, x))
            states.append((pc, m, x))
            if pc in data:
                anomalies.append((pc, 'enters data'))
                ok = False
                break
            ins = decode(mem, pc, m, x)
            if ins is None:
                anomalies.append((pc, 'runs off the module'))
                ok = False
                break
            if ins.mnemonic in BAD:
                anomalies.append((pc, ins.mnemonic))
                ok = False
                break
            path.append(ins)
            nxt = pc + ins.size
            if ins.mnemonic == 'REP':
                m, x = m and not ins.operand & 0x20, x and not ins.operand & 0x10
            elif ins.mnemonic == 'SEP':
                m, x = m or bool(ins.operand & 0x20), x or bool(ins.operand & 0x10)
            elif ins.mnemonic == 'PHP':
                stack = stack + ((m, x),)
            elif ins.mnemonic == 'PLP' and stack:
                (m, x), stack = stack[-1], stack[:-1]
            t = ins.target()
            if ins.mnemonic in BRANCHES:
                work.append((t, m, x, stack))
            elif ins.mnemonic in ('BRA', 'BRL', 'JMP', 'JML'):
                if t is None:
                    break                       # indirect, or out of the module
                pc = t
                continue
            elif ins.mnemonic in ('JSR', 'JSL') and t is not None:
                work.append((t, m, x, ()))
                em, ex = CALL_EXITS.get(t, (None, None))
                m = m if em is None else em
                x = x if ex is None else ex
            elif ins.mnemonic in STOPS:
                break
            pc = nxt
        if ok:
            kept.append((path, states, join))
        else:
            dropped.update(states)          # back to the path's start, its last branch point
    # A path that runs into a dropped one shares its anomaly: drop it too.
    changed = True
    while changed:
        changed = False
        for item in [k for k in kept if k[2] in dropped]:
            kept.remove(item)
            dropped.update(item[1])
            changed = True
    for path, _, _ in kept:
        for ins in path:
            insns.setdefault(ins.pc, ins)
    return insns, anomalies


def code_bytes(insns) -> set[int]:
    return {a for ins in insns.values() for a in range(ins.pc, ins.pc + ins.size)}


def call_sites(insns) -> dict[int, list[int]]:
    """{target: [site, ...]} for every JSR, JSL, JMP, JML and BRL into the module."""
    out = {}
    for ins in insns.values():
        if ins.mnemonic in ('JSR', 'JSL', 'JMP', 'JML', 'BRL'):
            t = ins.target()
            if t is not None:
                out.setdefault(t, []).append(ins.pc)
    return out


# ── Printing ─────────────────────────────────────────────────────────────────

def operand_text(ins: Insn) -> str:
    v, mode = ins.operand, ins.mode
    t = ins.target()
    if t is not None and ins.mnemonic not in ('JSL', 'JML'):
        return f'${t:04X}'
    w2, w4, w6 = f'${v:02X}', f'${v:04X}', f'${v:06X}'
    return {
        'impl': '', 'A': 'A', 'imm': f'#{w2}',
        'imm_m': f'#{w2}' if ins.m else f'#{w4}', 'imm_x': f'#{w2}' if ins.x else f'#{w4}',
        'dp': w2, 'dp_x': f'{w2},X', 'dp_y': f'{w2},Y', 'dp_ind': f'({w2})',
        'dp_x_ind': f'({w2},X)', 'dp_ind_y': f'({w2}),Y', 'dp_ind_long': f'[{w2}]',
        'dp_ind_long_y': f'[{w2}],Y', 'sr': f'{w2},S', 'sr_ind_y': f'({w2},S),Y',
        'abs': w4, 'abs_x': f'{w4},X', 'abs_y': f'{w4},Y', 'abs_ind': f'({w4})',
        'abs_x_ind': f'({w4},X)', 'abs_ind_long': f'[{w4}]', 'long': w6, 'long_x': f'{w6},X',
        'block': f'${v & 0xFF:02X},${v >> 8:02X}',
    }.get(mode, w4)


def width(ins: Insn) -> str:
    if ins.mnemonic in ('JSR', 'JSL', 'JMP', 'JML', 'BRL', 'PER', 'MVN', 'MVP') or ins.mode in (
            'impl', 'A', 'rel', 'rlong'):
        return ''
    n = ins.size - 1
    return {1: '.b', 2: '.w', 3: '.l'}.get(n, '')


def render(mem: bytes, start: int, stop: int, insns: dict[int, Insn]) -> list[str]:
    labels = {t for ins in insns.values() for t in [ins.target()] if t is not None}
    out, pc, data = [], start, []

    def flush():
        while data:
            chunk = data[:8]
            del data[:8]
            out.append('    db ' + ','.join(f'${b:02X}' for b in chunk))

    while pc < stop:
        ins = insns.get(pc)
        if pc in labels or (ins is not None and data):
            flush()
            if pc in labels:
                out.append(f'.L{pc:04X}:')
        if ins is None or pc + ins.size > stop:
            data.append(mem[pc - BASE])
            pc += 1
            continue
        text = f'    {ins.mnemonic}{width(ins)} {operand_text(ins)}'.rstrip()
        out.append(f'{text:<36}; ${pc:04X} M{8 if ins.m else 16} X{8 if ins.x else 16}')
        pc += ins.size
    flush()
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('start', nargs='?')
    ap.add_argument('end', nargs='?')
    ap.add_argument('--linear', action='store_true')
    ap.add_argument('--m', type=int, default=1)
    ap.add_argument('--x', type=int, default=0)
    ap.add_argument('--summary', action='store_true')
    ap.add_argument('--anomalies', action='store_true')
    args = ap.parse_args(argv)
    if not c3pack.ROM_PATH.exists():
        print(f'No ROM at {c3pack.ROM_PATH}', file=sys.stderr)
        return 2
    mem = module_bytes()
    if args.linear:
        start = int(args.start, 16)
        stop = int(args.end, 16) if args.end else BASE + SIZE
        insns, pc, m, x = {}, start, bool(args.m), bool(args.x)
        while pc < stop:
            ins = decode(mem, pc, m, x)
            if ins is None:
                break
            insns[pc] = ins
            if ins.mnemonic == 'REP':
                m, x = m and not ins.operand & 0x20, x and not ins.operand & 0x10
            elif ins.mnemonic == 'SEP':
                m, x = m or bool(ins.operand & 0x20), x or bool(ins.operand & 0x10)
            pc += ins.size
    else:
        insns, anomalies = trace(mem)
        if args.summary or args.anomalies:
            print(f'{len(insns)} instructions, {len(code_bytes(insns)):,} code bytes traced of '
                  f'{SIZE:,}; {len(anomalies)} path(s) dropped')
            if args.anomalies:
                for pc, why in anomalies:
                    print(f'  ${pc:04X}: {why}')
            return 0
    start = int(args.start, 16) if args.start else BASE
    stop = int(args.end, 16) if args.end else BASE + SIZE
    print('\n'.join(render(mem, start, stop, insns)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
