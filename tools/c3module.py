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
                   (JSR (table,X)); every entry is traced;

and from what the module only names at run time, by the rules of
discover() (applied until nothing new turns up; `--entries` lists every
address each one found and the instructions that show it): tasks (X loaded
before the task-list adders or replace exits, TASK_TABLES copied whole into
C3_TaskList), scripts (addresses stored to C3Script_Ptr of page $0A00 or
$0B00, each parsed on its page with C3_RunScript's opcodes for its own
flow, the routines it calls and the tasks it adds or removes, and the
scripts it starts on the other page by poke16 to that page's pointer;
SCRIPT_REDIRECTS for the routines that write a script pointer themselves)
and patches (addresses written over a
JSR / JMP operand: self-modifying calls). Calls into GENERATED code (the
copy routine C3_BuildCopyCode writes at $B574) are not followed.

A call (JSR, JSL into $7E) is assumed to return with the widths it was
entered with, except the callees in CALL_EXITS. A path (the straight run
from a branch point: an entry, a branch target or a call target) that
decodes BRK, COP, WDM or STP, runs off the module or enters DATA_RANGES is
dropped whole, back to that branch point, and reported (`--anomalies`): it
is a wrong guess at a width, or data; so is any path that runs into a
dropped one. Paths queued from a dropped path (its branch and call
targets) are still traced on their own. The anomalies found so far are
handled: CALL_EXITS ($45D6 returns with M=0, so C3Mod_Prog0's BIT at $3C57
is 16-bit), DATA_RANGES (the staff texts), GENERATED (JSR $B574 at $82A5),
the patches ($0000 at $35FC is a placeholder) and SCRIPT_REDIRECTS ($9315
is resumed at $9317; $5640 and $564D, called by page $0B's script, start
page $0A's); none is left.

The traced instruction bytes are the module's known code; tools/progress.py
counts the matched code against them together with any matched code the
trace has not reached yet. A few blocks still look like code that no rule
reaches (e.g. $3209, called only from $3425 in another unreached block),
so the figure can still grow a little.

Usage:
    python3 tools/c3module.py [START [END]] [--linear] [--m 0|1 --x 0|1]
    python3 tools/c3module.py --summary
    python3 tools/c3module.py --anomalies
    python3 tools/c3module.py --entries     every entry, script and patch discover() found

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
    (0xA651, 0xB57E, 'the staff texts: "PRODUCER/KAZU`KO AOKI@..." ($A651-$AADB, "`" for HI),'
                     ' then "EXECUTIVE PRODUCER/..." to "CODE END 7E"'),
]

# Code the module writes at run time and calls: (address, what), not traced
# (its bytes in the module are something else). A JSR there is a call that
# returns with the widths it was entered with.
GENERATED = {
    0xB574: 'C3_BuildCopyCode\'s output: the module builds 1,024 LDA abs / STA dp pairs, with '
            'LDA #page / TCD every 128, and an RTS at $7E:B574 (X = $0C00, Y = $0200; JSLs at '
            '$3CFB, $799D, $8569), over the end of the staff text, and calls it with JSR $B574 '
            'right after C3_ScaleBitmap (e.g. $82A5, between PHD and PLD)',
}

# How the module reaches code no instruction names (discover() applies them
# until nothing new turns up; --entries lists what each one found):
#   TASK_CALLS  a task address loaded into X before a JSR to the module's own
#               task-list adders or a JMP to a task's replace exit: the task
#               runs from C3Mod_RunTasks (M=0, X=0) or C3Mod_RunNmiTasks (M=1,
#               X=0);
#   scripts     a script address stored to C3Script_Ptr of page $0A00 or
#               $0B00 ($0A20 / $0B20, which C3_RunScript runs from); each
#               script is parsed (C3_RunScript's opcodes) on its page for
#               its own flow, the routines it calls (opcode $x0:
#               C3Mod_CallW, M=0, X=0), the tasks it adds (opcodes $x8: NMI
#               task, $xA: task) and the scripts it starts on the other
#               page (opcode $x2, poke16 of that page's pointer: how a
#               page's wait loop, a jump-and-yield to itself, is broken);
#   patches     an address stored over the operand of a JSR / JMP abs: the
#               call is to that address (self-modifying code), with the
#               widths at the call; the static operand is followed too when
#               it is in the module (the default: C3Mod_Return at $3023,
#               $5E54 at $5E43), not when it is a placeholder ($0000 at
#               $35FC).
# Script routines that set a C3Script_Ptr themselves: {routine: (pointer,
# [values], conditional?, evidence)}. The pointer is $20 (direct page: the
# page the calling script runs on, DP = $0A00 or $0B00) or $0A20 / $0B20
# (that page, whichever runs). Written to the running page, the script
# resumes at value + 2 (C3_RunScript adds 2 to the pointer after the call)
# and does not go on after the opcode, unless the write is conditional;
# written to the other page, the script goes on and the other page starts
# at the value itself. A script that calls a routine storing to a pointer
# that is not here is an anomaly, as is a routine with a page-$0A/$0B
# pointer called from a script whose page is unknown.
TASK_CALLS = {
    0x395E: (False, False, 'JSR to the task-list adder at $395E'),
    0x3974: (True, False, 'JSR to the NMI-task-list adder at $3974'),
    0x39B1: (False, False, 'JMP to C3Mod_TaskReplace'),
    0x39E8: (True, False, 'JMP to C3Mod_NmiTaskReplace'),
}
SCRIPT_PTRS = (0x0A20, 0x0B20)
# Word tables of task addresses copied whole into C3_TaskList, and of
# script addresses: (table, entries, evidence).
TASK_TABLES = [
    (0x7EC7, 5, 'LDX #$7EC7 / LDA #9 / LDY #C3_TaskList / MVN at $7ED4: five tasks'),
    (0x7EDC, 6, 'LDX #$7EDC / LDA #$B / LDY #C3_TaskList / MVN at $7EEB: six tasks'),
]
SCRIPT_TABLES = []                  # (table, entries, page $0A / $0B, evidence)
# Instructions overwritten with a BRA from a table of BRA words: (site,
# table, entries, evidence); each BRA's target is traced (M=0, X=0: the
# loop around the site runs with both 16-bit).
PATCHED_BRANCHES = [
    (0x3634, 0x3689, 4, 'the INX / NOP at $3634 in C3Mod_BuildM7Tables\'s loop is replaced by a '
                        'word of the table $3689 (BRA +6, +$22, +$2C, +$36): $368D by LDA.l / '
                        'STA.l $7E3634 at $7A0C, $368F at $45C5; the first two words have no reader '
                        'found. Other writers put INX / INX, DEX / DEX ($8066, $8051) or NOP / INX '
                        '($45D1) there'),
]
SCRIPT_REDIRECTS = {
    0x3F59: (0x20, [0x3F68, 0x3FAA], False, 'LDA $3F66,X (X = 0 or 2: the table $3F68, $3FAA) / STA $20'),
    0x996F: (0x20, [0x9415], True, 'LDA #$9415 / STA $20 when $006A is nonzero, else nothing'),
    0x564D: (0x0A20, [0x5635], False, 'LDA #$5635 / STA $0A20 / RTS'),
    0x5640: (0x0A20, [0x5604], False, 'LDA #$0080 / STA $582E / LDA #$5604 / STA $0A20 / RTS'),
    0x8CD0: (0x0A20, [0x9315], True, 'LDX #$9315 / STX $0A20 when C3_EntryArg bits 0-3 are all set '
                                     '(then JMP $8AF0), else nothing'),
    0x7286: (0x0A20, [0x72A2, 0x72C1, 0x72E2, 0x72FA], True,
             'when $004B is nonzero, LDA $729C,X (X = $3448\'s value AND 6: the table $72A2, $72C1, '
             '$72E2, $72FA) / STA $0A20; else nothing'),
}
# Tasks named by the module's own task-list removers (LDX #task / JSR):
# {remover: (NMI list?, what)}; their sites are references to the task
# (the CALLERS rule wants them), not entries.
TASK_REMOVES = {
    0x3934: (False, 'JSR to the task-list remover at $3934'),
    0x3949: (True, 'JSR to the NMI-task-list remover at $3949'),
}

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


def trace(mem: bytes, entries=None, patched=frozenset()):
    """({pc: Insn} reached, [(pc, reason)] anomalies). A path that hits an
    anomaly is dropped back to its last branch point. With no entries, the
    whole discovery (discover()); `patched`: JSR/JMP sites whose operand is
    written at run time (their static target is not followed)."""
    if entries is None:
        d = discover(mem)
        return d.insns, d.anomalies
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
            if t in GENERATED or (pc in patched and t is not None and not BASE < t < BASE + len(mem)):
                t = None if ins.mnemonic in ('JMP', 'JML') else -1      # not followed
            if ins.mnemonic in BRANCHES:
                work.append((t, m, x, stack))
            elif ins.mnemonic in ('BRA', 'BRL', 'JMP', 'JML'):
                if t is None:
                    break                       # indirect, or out of the module
                pc = t
                continue
            elif ins.mnemonic in ('JSR', 'JSL') and t is not None:
                if t >= 0:
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


class Discovery:
    """The module's code and scripts as far as the rules above reach."""

    def __init__(self, insns, anomalies, entries, scripts, script_bytes, patched, refs):
        self.insns = insns              # {pc: Insn}
        self.anomalies = anomalies      # [(pc, why)]
        self.entries = entries          # {address: (M=1?, X=1?, evidence)}, beyond ENTRIES and tables
        self.scripts = scripts          # {(script start, page $0A / $0B): evidence}
        self.script_bytes = script_bytes
        self.patched = patched          # {JSR/JMP site: {targets written over its operand}}
        # {address: [site, ...]}: the script opcodes that call it ($x0) or add or remove it
        # as a task ($x7-$xA), and the LDX #address before a JSR / JMP to the task-list
        # adders, replace exits and removers
        self.refs = refs


def _predecessors(insns):
    pred = {}
    for ins in insns.values():
        nxt = ins.pc + ins.size
        t = ins.target()
        if ins.mnemonic not in ('BRA', 'BRL', 'JMP', 'JML') and ins.mnemonic not in STOPS:
            pred.setdefault(nxt, []).append(ins.pc)
        if t is not None and (ins.mnemonic in BRANCHES or ins.mnemonic in ('BRA', 'BRL', 'JMP', 'JML')):
            pred.setdefault(t, []).append(ins.pc)
    return pred


LOADS = {'A': 'LDA', 'X': 'LDX', 'Y': 'LDY'}
WRITES = {
    'A': {'LDA', 'PLA', 'TXA', 'TYA', 'TDC', 'TSC', 'XBA', 'ADC', 'SBC', 'AND', 'ORA', 'EOR', 'INC',
          'DEC', 'ASL', 'LSR', 'ROL', 'ROR', 'JSR', 'JSL', 'MVN', 'MVP'},
    'X': {'LDX', 'PLX', 'TAX', 'TSX', 'TYX', 'INX', 'DEX', 'JSR', 'JSL', 'MVN', 'MVP'},
    'Y': {'LDY', 'PLY', 'TAY', 'TXY', 'INY', 'DEY', 'JSR', 'JSL', 'MVN', 'MVP'},
}


def immediates_before(insns, pred, pc, reg, depth=12, size=3):
    """The 16-bit immediates that reach register `reg` at `pc`, walking back
    through the instructions that lead there (both sides of a join), each
    path ending at the load, or at anything else that writes the register
    (then that path gives nothing)."""
    found, seen = [], set()
    work = [(p, depth) for p in pred.get(pc, [])]
    while work:
        p, d = work.pop()
        if p in seen or d == 0:
            continue
        seen.add(p)
        ins = insns[p]
        if ins.mnemonic == LOADS[reg] and ins.mode in ('imm_m', 'imm_x') and ins.size == size:
            found.append((ins.operand, p))
            continue
        if ins.mnemonic in WRITES[reg] or (reg == 'A' and ins.mode == 'A'):
            continue
        work += [(q, d - 1) for q in pred.get(p, [])]
    return found


def parse_script(mem, start, page, sets_ptr, out):
    """Follow a C3_RunScript script from `start`, running on `page` ($0A or
    $0B: its DP is page << 8); fills out['bytes'], out['calls'],
    out['nmi'], out['tasks'], out['removes'] ([(address, opcode site)]),
    out['starts'] ([((address, page), evidence)]: scripts it starts on the
    other page) and out['bad']."""
    def byte(a):
        return mem[a - BASE]

    def word(a):
        return mem[a - BASE] | mem[a + 1 - BASE] << 8

    def other(dest, v, p, why):
        """A pointer write: (resume addresses on this page, goes on?)."""
        if dest == 0x20 or dest >> 8 == page:
            return [v + 2], False
        out['starts'].append(((v, dest >> 8), f'{why}: opcode at ${p:04X} of a script on page ${page:02X}'))
        return [], True
    work = [start]
    while work:
        p = work.pop()
        while True:
            if not BASE <= p < BASE + len(mem) - 4:
                out['bad'].append((p, 'script runs off the module'))
                break
            if (p, page) in out['ops']:
                break
            out['ops'].add((p, page))
            op, q, stop = byte(p), p + 1, False
            if op < 0x80:                           # variables
                kind = op >> 4
                nxt = q + (2 if kind == 0 else 1 if kind == 2 else 1 if op & 0x20 else 2)
            elif op < 0xA0:                         # loops: limit, target
                work.append(word(q + 2))
                nxt = q + 4
            else:
                f = op & 0x0F
                nxt = q + {0: 2, 1: 3, 2: 4, 3: 2, 4: 0, 5: 1, 6: 4, 7: 2, 8: 2, 9: 2, 0xA: 2,
                           0xB: 2, 0xC: 0, 0xD: 2, 0xE: 2, 0xF: 0}[f]
                if f == 0:
                    r = word(q)
                    out['calls'].append((r, p))
                    if sets_ptr(r):
                        if r in SCRIPT_REDIRECTS:
                            dest, values, cond, why = SCRIPT_REDIRECTS[r]
                            goes_on = True
                            for v in values:
                                resume, on = other(dest, v, p, f'${r:04X} ({why})')
                                work += resume
                                goes_on = on or cond
                            stop = not goes_on
                        else:
                            out['bad'].append((p, f'calls ${r:04X}, which sets the script pointer '
                                                  f'(not in SCRIPT_REDIRECTS)'))
                elif f in (1, 2) and word(q) in (0x0A20, 0x0A21, 0x0B20, 0x0B21):
                    a, v = word(q), word(q + 2)
                    if f == 2 and a & 0xFF == 0x20:     # poke16 C3Script_Ptr: STA, then skip 2
                        resume, on = other(a, v, p, f'poke16 ${a:04X} = ${v:04X}')
                        work += resume
                        stop = not on
                    else:
                        out['bad'].append((p, f'pokes half of the script pointer ${a:04X}'))
                elif f in (3, 0xD, 0xE):
                    work.append(word(q))
                    stop = f != 3
                elif f == 8:
                    out['nmi'].append((word(q), p))
                elif f == 0xA:
                    out['tasks'].append((word(q), p))
                elif f in (7, 9):
                    out['removes'].append((word(q), p))
                elif f in (4, 0xF):
                    stop = True
            out['bytes'].update(range(p, nxt))
            if stop:
                break
            p = nxt


_DISCOVERED = {}


def discover(mem: bytes) -> Discovery:
    """Apply the rules (ENTRIES, DISPATCH_TABLES, TASK_CALLS, scripts,
    patches) until nothing new turns up."""
    key = hash(mem)
    if key in _DISCOVERED:
        return _DISCOVERED[key]
    entries, scripts, patched = {}, {}, {}
    sets_ptr = {}
    # The stores of SCRIPT_REDIRECTS' routines are theirs (they resume at
    # the value + 2), not script starts.
    redirect_sites = set()
    for r in SCRIPT_REDIRECTS:
        redirect_sites |= set(trace(mem, [(r, False, False)])[0])
    for _ in range(64):
        base = [(a, m, x) for a, m, x, _ in ENTRIES] + table_entries(mem)
        for table, count, why in TASK_TABLES:
            for k in range(count):
                v = mem[table + 2 * k - BASE] | mem[table + 2 * k + 1 - BASE] << 8
                if v not in entries:
                    entries[v] = (False, False, f'task: entry {k} of the table at ${table:04X} ({why})')
        for site, table, count, why in PATCHED_BRANCHES:
            for k in range(count):
                op, off = mem[table + 2 * k - BASE], mem[table + 2 * k + 1 - BASE]
                if op == 0x80:                      # BRA
                    v = site + 2 + (off ^ 0x80) - 0x80
                    if v not in entries:
                        entries[v] = (False, False, f'patched branch: entry {k} of the table at '
                                                    f'${table:04X} written over ${site:04X} ({why})')
        for table, count, page, why in SCRIPT_TABLES:
            for k in range(count):
                v = mem[table + 2 * k - BASE] | mem[table + 2 * k + 1 - BASE] << 8
                scripts.setdefault((v, page), f'entry {k} of the script table at ${table:04X} ({why})')
        insns, anomalies = trace(mem, base + [(a, m, x) for a, (m, x, _) in entries.items()],
                                 frozenset(patched))
        pred = _predecessors(insns)
        new = 0

        def add(addr, m, x, why):
            nonlocal new
            if BASE <= addr < BASE + len(mem) and addr not in entries:
                entries[addr] = (m, x, why)
                new += 1
        halves = {}                     # {(site, 0 low / 1 high): [(byte, load site, store site)]}
        for ins in insns.values():
            reg = {'STA': 'A', 'STX': 'X', 'STY': 'Y'}.get(ins.mnemonic)
            if reg is None or ins.mode not in ('abs', 'long') or (ins.mode == 'long' and ins.operand >> 16 != BANK):
                continue
            if (ins.m if reg == 'A' else ins.x) is not True:
                continue                # an 8-bit store: one byte of an operand?
            dest = ins.operand & 0xFFFF
            for k in (0, 1):
                site = insns.get(dest - 1 - k)
                if site is not None and site.mnemonic in ('JSR', 'JMP') and site.mode == 'abs':
                    for v, at in immediates_before(insns, pred, ins.pc, reg, size=2):
                        halves.setdefault((site.pc, k), []).append((v, at, ins.pc))
        for (spc, k), lows in list(halves.items()):
            if k != 0:
                continue
            site = insns[spc]
            for lo, lat, lst in lows:
                for hi, hat, hst in halves.get((spc, 1), []):
                    v = lo | hi << 8
                    if v not in patched.setdefault(spc, set()):
                        patched[spc].add(v)
                        new += 1
                    add(v, site.m, site.x, f'patched: bytes ${lo:02X} (LDA at ${lat:04X}, store at ${lst:04X}) '
                                           f'and ${hi:02X} (LDA at ${hat:04X}, store at ${hst:04X}) written '
                                           f'over the {site.mnemonic} at ${spc:04X}')
        refs = {}
        for ins in insns.values():
            if ins.mnemonic in ('JSR', 'JMP') and ins.mode == 'abs' and ins.operand in TASK_CALLS:
                m, x, why = TASK_CALLS[ins.operand]
                for v, at in immediates_before(insns, pred, ins.pc, 'X'):
                    add(v, m, x, f'task: LDX #${v:04X} at ${at:04X}, {why} at ${ins.pc:04X}')
                    refs.setdefault(v, set()).add(at)
            if ins.mnemonic == 'JSR' and ins.mode == 'abs' and ins.operand in TASK_REMOVES:
                for v, at in immediates_before(insns, pred, ins.pc, 'X'):
                    refs.setdefault(v, set()).add(at)
            reg = {'STA': 'A', 'STX': 'X', 'STY': 'Y'}.get(ins.mnemonic)
            if reg is None or ins.mode not in ('abs', 'long') or (ins.mode == 'long' and ins.operand >> 16 != BANK):
                continue
            dest = ins.operand & 0xFFFF
            if dest in SCRIPT_PTRS and ins.pc not in redirect_sites:
                for v, at in immediates_before(insns, pred, ins.pc, reg):
                    if BASE <= v < BASE + len(mem) and (v, dest >> 8) not in scripts:
                        scripts[(v, dest >> 8)] = (f'{LOADS[reg]} #${v:04X} at ${at:04X}, {ins.mnemonic} ${dest:04X} '
                                      f'at ${ins.pc:04X}')
                        new += 1
            site = insns.get(dest - 1)
            if site is not None and site.mnemonic in ('JSR', 'JMP') and site.mode == 'abs':
                for v, at in immediates_before(insns, pred, ins.pc, reg):
                    if v not in patched.setdefault(site.pc, set()):
                        patched[site.pc].add(v)
                        new += 1
                    add(v, site.m, site.x, f'patched: {LOADS[reg]} #${v:04X} at ${at:04X} written over '
                                           f'the {site.mnemonic} at ${site.pc:04X} by ${ins.pc:04X}')
        out = {'bytes': set(), 'ops': set(), 'calls': [], 'nmi': [], 'tasks': [], 'removes': [],
               'starts': [], 'bad': []}
        for s, page in list(scripts):
            parse_script(mem, s, page, lambda r: _sets_ptr(mem, r, sets_ptr), out)
        for key, why in out['starts']:
            if key not in scripts:
                scripts[key] = why
                new += 1
        for lst, (m, x), kind in ((out['calls'], (False, False), 'script call (opcode $x0)'),
                                  (out['nmi'], (True, False), 'script NMI task (opcode $x8)'),
                                  (out['tasks'], (False, False), 'script task (opcode $xA)')):
            for v, at in lst:
                add(v, m, x, f'{kind} at ${at:04X}')
        for lst in (out['calls'], out['nmi'], out['tasks'], out['removes']):
            for v, at in lst:
                refs.setdefault(v, set()).add(at)
        if not new:
            break
    anomalies = anomalies + [(p, why) for p, why in out['bad']]
    d = Discovery(insns, anomalies, entries, scripts, out['bytes'], patched,
                  {v: sorted(sites) for v, sites in refs.items()})
    _DISCOVERED[key] = d
    return d


def _sets_ptr(mem, r, cache):
    """Whether script routine r (traced alone) stores to C3Script_Ptr ($20,
    direct page, or $0A20 / $0B20 absolute)."""
    if r not in cache:
        insns, _ = trace(mem, [(r, False, False)])
        cache[r] = any(i.mnemonic in ('STA', 'STX', 'STY', 'STZ')
                       and ((i.mode == 'dp' and i.operand in (0x20, 0x21))
                            or (i.mode in ('abs', 'long') and i.operand & 0xFFFF in SCRIPT_PTRS))
                       for i in insns.values())
    return cache[r]


def code_bytes(insns) -> set[int]:
    return {a for ins in insns.values() for a in range(ins.pc, ins.pc + ins.size)}


def call_sites(insns, patched=None, refs=None) -> dict[int, list[int]]:
    """{target: [site, ...]} for every JSR, JSL, JMP, JML and BRL into the
    module; with `patched` (Discovery.patched), also the patched calls
    (the site of a JSR / JMP whose operand is written at run time, for
    each address written there); with `refs` (Discovery.refs), also the
    script opcodes and task-list calls that name it."""
    out = {}
    for ins in insns.values():
        if ins.mnemonic in ('JSR', 'JSL', 'JMP', 'JML', 'BRL'):
            t = ins.target()
            if t is not None and BASE <= t < BASE + SIZE:
                out.setdefault(t, []).append(ins.pc)
    for site, targets in (patched or {}).items():
        for t in targets:
            if site not in out.setdefault(t, []):
                out[t].append(site)
    for t, sites in (refs or {}).items():
        for site in sites:
            if site not in out.setdefault(t, []):
                out[t].append(site)
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
    ap.add_argument('--entries', action='store_true', help='what discover() found, with its evidence')
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
        d = discover(mem)
        insns, anomalies = d.insns, d.anomalies
        if args.entries:
            for a, (m, x, why) in sorted(d.entries.items()):
                print(f'entry  ${a:04X} M{8 if m else 16} X{8 if x else 16}  {why}')
            for (a, page), why in sorted(d.scripts.items()):
                print(f'script ${a:04X} page ${page:02X}  {why}')
            for site, targets in sorted(d.patched.items()):
                print(f'patch  ${site:04X} -> ' + ', '.join(f'${v:04X}' for v in sorted(targets)))
            print(f'{len(d.script_bytes):,} script bytes')
            return 0
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
