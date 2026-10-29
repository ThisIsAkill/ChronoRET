#!/usr/bin/env python3
"""
absint.py — A 65816 interpreter over partly known state, for asking what a
matched routine does with the bytes it is given.

It runs the code the source assembles to (an image of asm/main.asm, never
the ROM's code bytes) from an entry point with some registers and memory
known (the rest unknown, None). Every instruction is executed exactly; a
value computed from an unknown one is unknown. A conditional branch whose
flag is unknown follows both ways; a state already seen is not run again,
so waits and loops on unknown values end. What comes back is every way the
routine can return, with the registers it returns, and which known memory
bytes it read on the way (with `MVN`/`MVP` sources). tools/events.py uses it
to take each event opcode's operand bytes and its next-opcode position
from the handler itself.

Limits, by design: hardware registers and memory not given read as
unknown; code outside the assembled image (WRAM, the packed $C3 module)
is treated as a call that returns with A, X, Y and the flags unknown;
`BRK`, `COP`, `STP`, `WAI` and `XCE` end a path as unresolved.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import disasm  # noqa: E402

OPS = disasm._OPCODES
E = frozenset()          # no taint


class Unresolved(Exception):
    pass


def _wram(addr: int) -> int:
    """Canonical address: low WRAM and its mirrors as $7E:0000-$1FFF."""
    bank, low = addr >> 16, addr & 0xFFFF
    if (bank < 0x40 or 0x80 <= bank < 0xC0) and low < 0x2000:
        return 0x7E0000 | low
    return addr


class State:
    __slots__ = ('pc', 'a', 'b', 'x', 'y', 'd', 'db', 'm', 'xf', 'c', 'z', 'n', 'v', 'sp', 'mem', 'depth',
                 'at', 'xt', 'yt', 'ft', 'spt', 'memt', 'frames')
    # frames: per call in progress, (the state to go on with if the callee
    # cannot be followed: its return with A, X, Y and flags unknown, the
    # step count at the call, the callee's address).
    # at/xt/yt/ft: the known (script) addresses the register's value, or the
    # flags, were computed from; spt/memt the same for the stack and memory.

    def copy(self) -> 'State':
        s = State()
        for k in State.__slots__:
            setattr(s, k, getattr(self, k))
        s.sp = list(self.sp)
        s.spt = list(self.spt)
        s.frames = list(self.frames)
        s.mem = dict(self.mem)
        s.memt = dict(self.memt)
        return s

    def key(self):
        return (self.pc, self.a, self.b, self.x, self.y, self.d, self.db, self.m, self.xf, self.c, self.z,
                self.n, self.v, tuple(self.sp), tuple(sorted(self.mem.items())), self.at, self.xt, self.yt,
                self.ft, tuple(self.spt), tuple(sorted(self.memt.items())))


class Machine:
    """`image`: the assembled code (4 MB, HiROM file order); `known`:
    {address: byte} of memory given (script bytes); `code`: a set of file
    offsets the source emits (calls elsewhere are external)."""

    def __init__(self, image: bytes, code: bytearray, max_steps: int = 200000, callee_steps: int = 4000):
        self.image = image
        self.code = code
        self.max_steps = max_steps
        self.callee_steps = callee_steps
        self.widen_after = 48
        self.opaque: set[tuple[int, str]] = set()

    # ── memory ──
    def _rom(self, addr: int) -> int | None:
        """A byte the source emits (code and its tables); the data the
        source does not emit reads unknown."""
        bank, low = addr >> 16, addr & 0xFFFF
        off = disasm.snes_to_file(bank, low)
        return None if off is None or not self.code[off] else self.image[off]

    def read8(self, s: State, addr: int | None) -> int | None:
        if addr is None:
            return None
        addr = _wram(addr & 0xFFFFFF)
        if addr in s.mem:
            v = s.mem[addr]
            if v is not None and addr in self.known:
                self.reads.add(addr)
            return v
        if addr in self.known:
            self.reads.add(addr)
            return self.known[addr]
        bank, low = addr >> 16, addr & 0xFFFF
        if bank >= 0xC0 or (bank < 0x7E and low >= 0x8000):
            return self._rom(addr)
        return None

    def write8(self, s: State, addr: int | None, v: int | None):
        if addr is None:
            return
        s.mem[_wram(addr & 0xFFFFFF)] = v

    def taint(self, s: State, addr: int | None, wide: bool) -> frozenset:
        """The known (script) addresses the bytes at addr come from."""
        if addr is None:
            return E
        out = E
        for a in ([addr, addr + 1] if wide else [addr]):
            a = _wram(a & 0xFFFFFF)
            if a in s.memt:
                out |= s.memt[a]
            elif a in self.known and a not in s.mem:
                out |= frozenset((a,))
        return out

    def read(self, s: State, addr: int | None, wide: bool) -> int | None:
        lo = self.read8(s, addr)
        if not wide:
            return lo
        hi = self.read8(s, None if addr is None else addr + 1)
        return None if lo is None or hi is None else lo | hi << 8

    def write(self, s: State, addr: int | None, v: int | None, wide: bool, t: frozenset = E):
        if addr is not None:
            for a in ([addr, addr + 1] if wide else [addr]):
                s.memt[_wram(a & 0xFFFFFF)] = t
        self.write8(s, addr, None if v is None else v & 0xFF)
        if wide:
            self.write8(s, None if addr is None else addr + 1, None if v is None else v >> 8 & 0xFF)

    # ── registers ──
    @staticmethod
    def get_a(s: State) -> int | None:
        if s.m:
            return s.a
        return None if s.a is None or s.b is None else s.a | s.b << 8

    @staticmethod
    def get_c16(s: State) -> int | None:
        return None if s.a is None or s.b is None else s.a | s.b << 8

    @staticmethod
    def set_a(s: State, v: int | None):
        if s.m:
            s.a = None if v is None else v & 0xFF
        else:
            s.a = None if v is None else v & 0xFF
            s.b = None if v is None else v >> 8 & 0xFF

    @staticmethod
    def flags_nz(s: State, v: int | None, wide: bool):
        if v is None:
            s.n = s.z = None
        else:
            s.z = (v & (0xFFFF if wide else 0xFF)) == 0
            s.n = bool(v & (0x8000 if wide else 0x80))

    def push8(self, s: State, v, t: frozenset = E):
        s.sp.append(v)
        s.spt.append(t)

    def pull8(self, s: State):
        if not s.sp:
            raise Unresolved('stack underflow')
        self.last_t = s.spt.pop()
        return s.sp.pop()

    def pull_data8(self, s: State) -> int | None:
        v = self.pull8(s)
        return v if isinstance(v, int) else None

    def push16(self, s: State, v: int | None, t: frozenset = E):
        self.push8(s, None if v is None else v >> 8 & 0xFF, t)
        self.push8(s, None if v is None else v & 0xFF, t)

    def pull16(self, s: State) -> int | None:
        lo = self.pull_data8(s)
        t = self.last_t
        hi = self.pull_data8(s)
        self.last_t = t | self.last_t
        return None if lo is None or hi is None else lo | hi << 8

    # ── addressing ──
    def ea(self, s: State, mode: str, op: int) -> int | None:
        bank = s.pc >> 16
        d, db, x, y = s.d, s.db, s.x, s.y
        if mode == 'dp':
            return None if d is None else (d + op) & 0xFFFF
        if mode == 'dp_x':
            return None if d is None or x is None else (d + op + x) & 0xFFFF
        if mode == 'dp_y':
            return None if d is None or y is None else (d + op + y) & 0xFFFF
        if mode in ('abs', 'abs_x', 'abs_y'):
            idx = 0 if mode == 'abs' else (x if mode == 'abs_x' else y)
            if db is None or idx is None:
                return None
            return ((db << 16) + op + idx) & 0xFFFFFF
        if mode == 'long':
            return op
        if mode == 'long_x':
            return None if x is None else (op + x) & 0xFFFFFF
        if mode in ('dp_ind', 'dp_ind_y', 'dp_x_ind'):
            base = self.ea(s, 'dp_x' if mode == 'dp_x_ind' else 'dp', op)
            ptr = self.read(s, base, True)
            if ptr is None or db is None:
                return None
            idx = (y if mode == 'dp_ind_y' else 0)
            return None if idx is None else ((db << 16) + ptr + idx) & 0xFFFFFF
        if mode in ('dp_ind_long', 'dp_ind_long_y'):
            base = self.ea(s, 'dp', op)
            lo = self.read(s, base, True)
            hi = self.read8(s, None if base is None else base + 2)
            if lo is None or hi is None:
                return None
            idx = y if mode == 'dp_ind_long_y' else 0
            return None if idx is None else ((hi << 16) + lo + idx) & 0xFFFFFF
        if mode in ('sr', 'sr_ind_y'):
            return None
        raise Unresolved(f'address mode {mode}')

    # ── running ──
    def run(self, entry: State, known: dict[int, int]) -> list[tuple[State, str]]:
        """Every end of the routine entered with `entry` (whose sp holds
        what is below the return), with memory `known` ({address: byte}):
        [(state at the end, how it ended)]; self.reads is then the set of
        known addresses read."""
        self.known = known
        self.reads = set()
        self.control = set()
        self.opaque = set()
        entry.frames = []
        base_depth = len(entry.sp)
        stack = [entry]
        seen = set()
        visits: dict[int, int] = {}
        joined: dict[int, State] = {}
        ends = []
        steps = 0
        while stack:
            s = stack.pop()
            while True:
                steps += 1
                self._steps = steps
                if steps > self.max_steps:
                    raise Unresolved('too many steps')
                if self._branchy(s.pc):        # every loop passes a branch or jump
                    visits[s.pc] = visits.get(s.pc, 0) + 1
                    if visits[s.pc] > self.widen_after:
                        # a loop that keeps changing state: join it with the
                        # state the last time here (what differs becomes
                        # unknown), so it comes back to a state already seen
                        last = joined.get(s.pc)
                        if last is not None:
                            for k2 in set(s.mem) | set(last.mem):
                                if s.mem.get(k2, 'x') != last.mem.get(k2, 'y'):
                                    s.mem[k2] = None
                            for r in ('a', 'b', 'x', 'y', 'c', 'z', 'n', 'v'):
                                if getattr(s, r) != getattr(last, r):
                                    setattr(s, r, None)
                        joined[s.pc] = s.copy()
                    k = hash(s.key())
                    if k in seen:
                        break
                    seen.add(k)
                try:
                    if s.frames and steps - s.frames[-1][1] > self.callee_steps:
                        raise Unresolved('a callee runs too long')
                    r = self.step(s, base_depth)
                except Unresolved as e:
                    if not s.frames:
                        raise
                    # the callee cannot be followed: go on after the call as
                    # if it returned with A, X, Y and the flags unknown
                    fallback, _, callee = s.frames[-1]
                    self.opaque.add((callee, str(e)))
                    s = fallback.copy()
                    continue
                if r is None:
                    continue
                kind, other = r
                if kind == 'fork':
                    stack.append(other)
                    continue
                ends.append((s, kind))
                break
        return ends

    BRANCHY = {'BPL', 'BMI', 'BVC', 'BVS', 'BCC', 'BCS', 'BNE', 'BEQ', 'BRA', 'BRL', 'JMP', 'JML'}

    def _branchy(self, pc: int) -> bool:
        off = disasm.snes_to_file(pc >> 16, pc & 0xFFFF)
        return off is not None and OPS[self.image[off]][0] in self.BRANCHY

    def step(self, s: State, base_depth: int):
        pc = s.pc
        off = disasm.snes_to_file(pc >> 16, pc & 0xFFFF)
        if off is None or not self.code[off]:
            raise Unresolved(f'execution outside the source at ${pc:06X}')
        opc = self.image[off]
        mn, mode = OPS[opc]
        cpu = disasm.CPUState(m=s.m, x=s.xf, e=False)
        n = disasm.insn_len(mode, cpu)
        op, _ = disasm.read_operand(self.image, off + 1, mode, cpu)
        nxt = (pc & 0xFF0000) | ((pc + n) & 0xFFFF)
        s.pc = nxt
        if mn not in ('BPL', 'BMI', 'BVC', 'BVS', 'BCC', 'BCS', 'BNE', 'BEQ', 'BRA', 'BRL', 'JMP', 'JML', 'JSR',
                      'JSL', 'RTS', 'RTL', 'STA', 'STX', 'STY', 'STZ', 'PHA', 'PHX', 'PHY', 'PHB', 'PHD', 'PHK',
                      'PHP', 'PEA', 'PEI', 'NOP', 'MVN', 'MVP'):
            # the flags this instruction sets come from its inputs
            if mn in ('CLC', 'SEC', 'CLV', 'REP', 'SEP'):
                s.ft = E
            else:
                mem = E
                if mode not in ('impl', 'A', 'imm', 'imm_m', 'imm_x', 'rel', 'rlong', 'block'):
                    try:
                        mem = self.taint(s, self.ea(s, mode, op), not s.m)
                    except Unresolved:
                        pass
                    mem |= s.xt if mode in ('abs_x', 'dp_x', 'long_x', 'dp_x_ind') else E
                    mem |= s.yt if mode in ('abs_y', 'dp_y', 'dp_ind_y', 'dp_ind_long_y') else E
                regs = {'TAX': s.at, 'TAY': s.at, 'TXA': s.xt, 'TYA': s.yt, 'TXY': s.xt, 'TYX': s.yt,
                        'INX': s.xt, 'DEX': s.xt, 'INY': s.yt, 'DEY': s.yt, 'CPX': s.xt, 'CPY': s.yt,
                        'LDA': E, 'LDX': E, 'LDY': E, 'TDC': E, 'TCD': s.at, 'PLA': E, 'PLX': E, 'PLY': E,
                        'PLB': E, 'PLD': E, 'PLP': E}
                s.ft = regs.get(mn, s.at) | mem
        wm, wx = not s.m, not s.xf
        bank = pc & 0xFF0000

        def index_taint():
            if mode in ('abs_x', 'dp_x', 'long_x', 'dp_x_ind'):
                return s.xt
            if mode in ('abs_y', 'dp_y', 'dp_ind_y', 'dp_ind_long_y'):
                return s.yt
            return E

        def operand_taint(wide):
            if mode in ('imm', 'imm_m', 'imm_x'):
                return E
            if mode == 'A':
                return s.at
            return self.taint(s, self.ea(s, mode, op), wide) | index_taint()

        def operand_value(wide):
            if mode in ('imm', 'imm_m', 'imm_x'):
                return op
            if mode == 'A':
                return self.get_a(s)
            v = self.read(s, self.ea(s, mode, op), wide)
            if v is not None:
                self.control |= index_taint()     # a known byte picked by a script value
            return v

        def branch(cond):
            target = bank | disasm.branch_target(mode, op, nxt)
            if cond is not None:
                self.control |= s.ft              # the way taken depends on a script value
            if cond is None:
                o = s.copy()
                o.pc = target
                return ('fork', o)
            if cond:
                s.pc = target
            return None

        # loads / stores
        if mn in ('LDA', 'LDX', 'LDY'):
            wide = wm if mn == 'LDA' else wx
            v = operand_value(wide)
            t = operand_taint(wide)
            if mn == 'LDA':
                self.set_a(s, v)
                s.at = t
            elif mn == 'LDX':
                s.x, s.xt = v, t
            else:
                s.y, s.yt = v, t
            self.flags_nz(s, v, wide)
            return None
        if mn in ('STA', 'STX', 'STY', 'STZ'):
            wide = wx if mn in ('STX', 'STY') else wm
            v = {'STA': self.get_a(s), 'STX': s.x, 'STY': s.y, 'STZ': 0}[mn]
            t = {'STA': s.at, 'STX': s.xt, 'STY': s.yt, 'STZ': E}[mn]
            self.control |= index_taint()         # where it lands depends on a script value
            self.write(s, self.ea(s, mode, op), v, wide, t)
            return None
        # transfers
        if mn in ('TAX', 'TAY'):
            v = self.get_c16(s) if wx else s.a
            if wx and s.a is not None and s.b is None:
                v = None
            setattr(s, 'x' if mn == 'TAX' else 'y', v)
            setattr(s, 'xt' if mn == 'TAX' else 'yt', s.at)
            self.flags_nz(s, v, wx)
            return None
        if mn in ('TXA', 'TYA'):
            v = s.x if mn == 'TXA' else s.y
            s.at = s.xt if mn == 'TXA' else s.yt
            if s.m:
                s.a = None if v is None else v & 0xFF
                self.flags_nz(s, s.a, False)
            else:
                self.set_a(s, v)
                self.flags_nz(s, v, True)
            return None
        if mn in ('TXY', 'TYX'):
            v = s.x if mn == 'TXY' else s.y
            setattr(s, 'y' if mn == 'TXY' else 'x', v)
            setattr(s, 'yt' if mn == 'TXY' else 'xt', s.xt if mn == 'TXY' else s.yt)
            self.flags_nz(s, v, wx)
            return None
        if mn == 'TDC':
            s.a, s.b = (None, None) if s.d is None else (s.d & 0xFF, s.d >> 8)
            s.at = E
            self.flags_nz(s, s.d, True)
            return None
        if mn == 'TCD':
            s.d = self.get_c16(s)
            self.flags_nz(s, s.d, True)
            return None
        if mn == 'XBA':
            s.a, s.b = s.b, s.a
            self.flags_nz(s, s.a, False)
            return None
        if mn in ('TXS', 'TCS') and not s.frames:
            return ('stack', None)            # the handler resets the stack: it does not return
        if mn in ('TSX', 'TXS', 'TCS', 'TSC'):
            raise Unresolved(f'{mn}: the stack pointer is not modelled')
        # flags
        if mn == 'CLC':
            s.c = False
            return None
        if mn == 'SEC':
            s.c = True
            return None
        if mn == 'CLV':
            s.v = False
            return None
        if mn in ('CLI', 'SEI', 'CLD', 'NOP', 'WDM'):
            if mn == 'SED':
                raise Unresolved('decimal mode')
            return None
        if mn == 'SED':
            raise Unresolved('decimal mode')
        if mn == 'REP':
            if op & 0x20:
                s.m = False
            if op & 0x10:
                s.xf = False
            if op & 0x01:
                s.c = False
            if op & 0x02:
                s.z = False
            if op & 0x80:
                s.n = False
            if op & 0x40:
                s.v = False
            return None
        if mn == 'SEP':
            if op & 0x20:
                s.m = True
                s.a = s.a
            if op & 0x10:
                s.xf = True
                s.x = None if s.x is None else s.x & 0xFF
                s.y = None if s.y is None else s.y & 0xFF
            if op & 0x01:
                s.c = True
            if op & 0x02:
                s.z = True
            if op & 0x80:
                s.n = True
            if op & 0x40:
                s.v = True
            return None
        # stack
        if mn == 'PHA':
            # byte by byte: a known high byte (B) comes back known even when
            # the low one is not
            if wm:
                self.push8(s, s.b, s.at)
            self.push8(s, s.a, s.at)
            return None
        if mn == 'PLA':
            lo = self.pull_data8(s)
            t = self.last_t
            if wm:
                hi = self.pull_data8(s)
                t |= self.last_t
                s.a, s.b = lo, hi
                v = None if lo is None or hi is None else lo | hi << 8
            else:
                s.a = v = lo
            s.at = t
            self.flags_nz(s, v, wm)
            return None
        if mn in ('PHX', 'PHY'):
            (self.push16 if wx else self.push8)(s, s.x if mn == 'PHX' else s.y, s.xt if mn == 'PHX' else s.yt)
            return None
        if mn in ('PLX', 'PLY'):
            v = self.pull16(s) if wx else self.pull_data8(s)
            setattr(s, 'x' if mn == 'PLX' else 'y', v)
            setattr(s, 'xt' if mn == 'PLX' else 'yt', self.last_t)
            self.flags_nz(s, v, wx)
            return None
        if mn == 'PHB':
            self.push8(s, s.db)
            return None
        if mn == 'PLB':
            s.db = self.pull_data8(s)
            self.flags_nz(s, s.db, False)
            return None
        if mn == 'PHK':
            self.push8(s, pc >> 16)
            return None
        if mn == 'PHD':
            self.push16(s, s.d)
            return None
        if mn == 'PLD':
            s.d = self.pull16(s)
            self.flags_nz(s, s.d, True)
            return None
        if mn == 'PEA':
            self.push16(s, op)
            return None
        if mn == 'PEI':
            self.push16(s, self.read(s, self.ea(s, 'dp', op), True))
            return None
        if mn == 'PER':
            raise Unresolved('PER')
        if mn == 'PHP':
            self.push8(s, ('P', s.m, s.xf, s.c, s.z, s.n, s.v))
            return None
        if mn == 'PLP':
            p = self.pull8(s)
            if not (isinstance(p, tuple) and p[0] == 'P'):
                raise Unresolved('PLP of a byte that is not a pushed P')
            _, s.m, s.xf, s.c, s.z, s.n, s.v = p
            if s.xf:
                s.x = None if s.x is None else s.x & 0xFF
                s.y = None if s.y is None else s.y & 0xFF
            return None
        # arithmetic and logic
        if mn in ('ADC', 'SBC'):
            v = operand_value(wm)
            s.at = s.at | operand_taint(wm)
            acc = self.get_a(s)
            mask = 0xFFFF if wm else 0xFF
            if acc is None or v is None or s.c is None:
                self.set_a(s, None)
                s.c = s.z = s.n = s.v = None
                return None
            if mn == 'ADC':
                r = acc + v + int(s.c)
                s.c = r > mask
            else:
                r = acc - v - (1 - int(s.c))
                s.c = r >= 0
            s.v = None
            r &= mask
            self.set_a(s, r)
            self.flags_nz(s, r, wm)
            return None
        if mn in ('AND', 'ORA', 'EOR'):
            v = operand_value(wm)
            s.at = s.at | operand_taint(wm)
            # byte by byte: an AND with a zero byte, or an ORA with $FF, is
            # known whatever the other byte is
            regs = [s.a, s.b] if wm else [s.a]
            vals = [None if v is None else v & 0xFF, None if v is None else v >> 8 & 0xFF][:len(regs)]
            res = []
            for x, y in zip(regs, vals):
                if mn == 'AND' and (x == 0 or y == 0):
                    res.append(0)
                elif mn == 'ORA' and (x == 0xFF or y == 0xFF):
                    res.append(0xFF)
                elif x is None or y is None:
                    res.append(None)
                else:
                    res.append({'AND': x & y, 'ORA': x | y, 'EOR': x ^ y}[mn])
            s.a = res[0]
            if wm:
                s.b = res[1]
            r = None if None in res else res[0] | (res[1] << 8 if wm else 0)
            self.flags_nz(s, r, wm)
            return None
        if mn in ('CMP', 'CPX', 'CPY'):
            wide = wm if mn == 'CMP' else wx
            v = operand_value(wide)
            reg = {'CMP': self.get_a(s), 'CPX': s.x, 'CPY': s.y}[mn]
            if reg is None or v is None:
                s.c = s.z = s.n = None
            else:
                mask = 0xFFFF if wide else 0xFF
                s.c = reg >= v
                r = (reg - v) & mask
                self.flags_nz(s, r, wide)
            return None
        if mn == 'BIT':
            v = operand_value(wm)
            acc = self.get_a(s)
            if mode not in ('imm', 'imm_m'):
                s.n = None if v is None else bool(v & (0x8000 if wm else 0x80))
                s.v = None if v is None else bool(v & (0x4000 if wm else 0x40))
            s.z = None if v is None or acc is None else (acc & v) == 0
            return None
        if mn in ('INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR', 'TSB', 'TRB'):
            if mode == 'A':
                v, addr, t = self.get_a(s), None, s.at
            else:
                addr = self.ea(s, mode, op)
                v = self.read(s, addr, wm)
                t = self.taint(s, addr, wm)
            mask = 0xFFFF if wm else 0xFF
            top = 0x8000 if wm else 0x80
            if mn in ('TSB', 'TRB'):
                acc = self.get_a(s)
                s.z = None if v is None or acc is None else (acc & v) == 0
                r = None if v is None or acc is None else ((v | acc) if mn == 'TSB' else (v & ~acc)) & mask
            elif v is None:
                r = None
                if mn in ('ASL', 'LSR', 'ROL', 'ROR'):
                    s.c = None
            elif mn == 'INC':
                r = (v + 1) & mask
            elif mn == 'DEC':
                r = (v - 1) & mask
            elif mn == 'ASL':
                s.c = bool(v & top)
                r = (v << 1) & mask
            elif mn == 'LSR':
                s.c = bool(v & 1)
                r = v >> 1
            elif mn == 'ROL':
                if s.c is None:
                    r = None
                    s.c = bool(v & top)
                else:
                    r = ((v << 1) | int(s.c)) & mask
                    s.c = bool(v & top)
            else:
                if s.c is None:
                    r = None
                    s.c = bool(v & 1)
                else:
                    r = (v >> 1) | (top if s.c else 0)
                    s.c = bool(v & 1)
            if mn not in ('TSB', 'TRB'):
                self.flags_nz(s, r, wm)
            if mode == 'A':
                self.set_a(s, r)
            else:
                self.write(s, addr, r, wm, t)
            return None
        if mn in ('INX', 'INY', 'DEX', 'DEY'):
            reg = 'x' if mn in ('INX', 'DEX') else 'y'
            v = getattr(s, reg)
            mask = 0xFFFF if wx else 0xFF
            r = None if v is None else (v + (1 if mn[:2] == 'IN' else -1)) & mask
            setattr(s, reg, r)
            self.flags_nz(s, r, wx)
            return None
        # block moves
        if mn in ('MVN', 'MVP'):
            src_bank, dst_bank = op >> 8 & 0xFF, op & 0xFF
            count = self.get_c16(s)
            if count is None:
                raise Unresolved(f'a block move of unknown size at ${pc:06X}')
            ct = s.at
            self.control |= ct                    # how much moves depends on a script value
            step = 1 if mn == 'MVN' else -1
            for _ in range(count + 1):
                src = None if s.x is None else src_bank << 16 | s.x
                v = self.read8(s, src)
                t = self.taint(s, src, False)
                self.write(s, None if s.y is None else dst_bank << 16 | s.y, v, False, t)
                s.x = None if s.x is None else (s.x + step) & 0xFFFF
                s.y = None if s.y is None else (s.y + step) & 0xFFFF
            s.a, s.b = 0xFF, 0xFF
            s.xt = s.xt | ct
            s.yt = s.yt | ct
            s.at = E
            s.db = dst_bank
            return None
        # branches and jumps
        if mn in ('BRA', 'BRL'):
            s.pc = bank | disasm.branch_target(mode, op, nxt)
            return None
        conds = {'BEQ': s.z, 'BNE': None if s.z is None else not s.z, 'BCS': s.c,
                 'BCC': None if s.c is None else not s.c, 'BMI': s.n, 'BPL': None if s.n is None else not s.n,
                 'BVS': s.v, 'BVC': None if s.v is None else not s.v}
        if mn in conds:
            return branch(conds[mn])
        if mn in ('JMP', 'JML'):
            if mode == 'abs':
                s.pc = bank | op
            elif mode == 'long':
                s.pc = op
            elif mode == 'abs_x_ind':
                self.control |= s.xt
                t = None if s.x is None else self.read(s, bank | ((op + s.x) & 0xFFFF), True)
                if t is None:
                    raise Unresolved(f'an indirect jump through an unknown entry at ${pc:06X}')
                s.pc = bank | t
            elif mode in ('abs_ind', 'abs_ind_long'):
                t = self.read(s, op, True)
                hi = self.read8(s, op + 2) if mode == 'abs_ind_long' else pc >> 16
                if t is None or hi is None:
                    raise Unresolved('an indirect jump through unknown memory')
                s.pc = hi << 16 | t
            return None
        if mn in ('JSR', 'JSL'):
            if mn == 'JSR' and mode == 'abs_x_ind':
                self.control |= s.xt
                t = None if s.x is None else self.read(s, bank | ((op + s.x) & 0xFFFF), True)
                if t is None:
                    raise Unresolved(f'an indirect call through an unknown entry at ${pc:06X}')
                target = bank | t
            else:
                target = (bank | op) if mn == 'JSR' else op
            toff = disasm.snes_to_file(target >> 16, target & 0xFFFF)
            if toff is None or not self.code[toff]:
                s.a = s.b = s.x = s.y = None          # external: returns with these unknown
                s.at = s.xt = s.yt = s.ft = E
                s.c = s.z = s.n = s.v = None
                return None
            fb = s.copy()
            fb.pc = nxt
            fb.a = fb.b = fb.x = fb.y = None
            fb.at = fb.xt = fb.yt = fb.ft = E
            fb.c = fb.z = fb.n = fb.v = None
            s.frames = s.frames + [(fb, self._steps, target)]
            ret = (nxt - 1) & 0xFFFF
            if mn == 'JSL':
                self.push8(s, ('R', pc >> 16))
            self.push8(s, ('R', ret >> 8))
            self.push8(s, ('R', ret & 0xFF))
            s.pc = target
            return None
        if mn in ('RTS', 'RTL'):
            if len(s.sp) <= base_depth:
                return ('rts' if mn == 'RTS' else 'rtl', None)
            lo, hi = self.pull8(s), self.pull8(s)
            bk = self.pull8(s) if mn == 'RTL' else ('R', pc >> 16)
            if s.frames:
                s.frames = s.frames[:-1]
            if not all(isinstance(v, tuple) and v[0] == 'R' for v in (lo, hi, bk)):
                raise Unresolved(f'{mn} to an address the code built on the stack')
            s.pc = bk[1] << 16 | ((hi[1] << 8 | lo[1]) + 1) & 0xFFFF
            return None
        raise Unresolved(f'{mn} at ${pc:06X}')
