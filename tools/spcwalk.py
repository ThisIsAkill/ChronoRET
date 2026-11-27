#!/usr/bin/env python3
"""
spcwalk.py — The SPC700 sound driver's score reader, run on its matched
source (asm/spc700/driver.asm) to find what each byte of a track does.

tools/absint.py runs 65816 code only, and the driver's bytes come from an
assembly that needs asar; this walks the driver's source text instead, so
the format it finds holds without the ROM or asar (the source is the
matched one: `make gate` proves it assembles to the ROM's driver).

The walk starts at Spc_TrackStep, the driver's step of one track, with the
track's first byte (the byte under test) known and every other byte of the
track, every register and every RAM byte unknown, except:

  * X and !Spc_CurTrack hold "the track" (a song or an effect track:
    `cmp x,#!Spc_TrackFirstSfx` is unknown, so both kinds are followed);
  * !Spc_Scratch00 (the song's move offset) is a symbol, so a pointer
    computed as a word + the move is recognised;
  * the track pointer (!Spc_TrackPtr+X) is "the byte under test + k":
    `mov a,(!Spc_TrackPtr+x)` (Spc_ReadSeqByte) reads stream byte k (byte
    0 is the one under test, byte k>0 an unknown operand symbol), and the
    pointer's INC moves k on.

Every instruction is run on those values: known values are computed,
anything with an unknown input is unknown, a branch on an unknown flag is
followed both ways, CALL/RET and PUSH/POP keep an exact stack (a RET into
an address pushed from a table entry goes to that entry: with an unknown
index, to every nonzero entry of the table), and `label+N` targets (a
branch onto an operand byte, the driver's two quirks) run the instruction
that byte encodes (tools/spc700.py's table). States that meet at one
instruction with the same stack and pointer are joined (a value both agree
on is kept, any other becomes unknown), so loops and the note step's many
paths converge. A walk ends:

  step     at Spc_TrackStep again with the stack as it began (the loop
           reads the track's next byte),
  return   by a RET to Spc_TrackStep's caller (the track waits for its
           next pass, or has ended),

and leaves the pointer either at byte k (moved by INC only), or set by a
store: from a word of two operand bytes plus !Spc_Scratch00 (a jump), or
from anything else (a place the stream's bytes do not give: a saved loop
start, an effect's track). An instruction the walk does not model, a store
through an unknown address that may reach the track pointer (an indexed
store with an unknown index is taken to reach its base to base+$FF, not
wrapping in the direct page), a RET to an
unknown address or too many states stops it with WalkError.

    python3 tools/spcwalk.py [BYTE ...]     print what each byte does
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import spc700  # noqa: E402

DRIVER = Path('asm/spc700/driver.asm')
INCLUDES = [Path('asm/include/constants_engine.inc'), Path('asm/spc700/spc700.inc')]
MAX_STATES = 400000


class WalkError(Exception):
    pass


# ── The source ──────────────────────────────────────────────────────────────

class Lbl:
    """A code or table label in an expression (its offset added)."""

    def __init__(self, name: str, off: int = 0):
        self.name, self.off = name, off

    def __add__(self, k):
        if isinstance(k, int):
            return Lbl(self.name, self.off + k)
        return NotImplemented

    __radd__ = __add__

    def __sub__(self, k):
        if isinstance(k, int):
            return Lbl(self.name, self.off - k)
        return NotImplemented

    def __rshift__(self, k):
        if k == 8 and self.off == 0:
            return ('code', self.name, 1)
        raise WalkError(f'{self.name}+{self.off} >> {k}: not an address byte')

    def __and__(self, k):
        if k == 0xFF and self.off == 0:
            return ('code', self.name, 0)
        raise WalkError(f'{self.name}+{self.off} & {k}: not an address byte')


TOKEN = re.compile(r'\$[0-9A-Fa-f]+|%[01]+|\d+|![A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*|>>|<<|[-+*/&|()~^]|\s+')
BRANCHES = {'bne', 'beq', 'bcs', 'bcc', 'bpl', 'bmi', 'bvs', 'bvc', 'bra'}
TARGETED = BRANCHES | {'jmp', 'call', 'cbne', 'dbnz', 'bbs', 'bbc'}


class Insn:
    __slots__ = ('idx', 'line', 'mnem', 'ops', 'text', 'target', 'scope')

    def __repr__(self):
        return f'{self.line}: {self.text}'


class Source:
    """The driver's instructions, labels, tables and the defines they use."""

    def __init__(self, driver_text: str, include_texts: list[str]):
        self.defines: dict[str, str] = {}
        for text in include_texts:
            for line in text.splitlines():
                m = re.match(r'^!([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+)', line)
                if m:
                    self.defines[m.group(1)] = m.group(2).strip()
        self.values: dict[str, object] = {}
        self.insns: list[Insn] = []
        self.labels: dict[str, int] = {}            # name -> index of the next instruction
        self.tables: dict[str, list] = {}           # name -> bytes (int or ('code', label, half))
        self.next_of: dict[int, int] = {}           # a split instruction -> the one after its host
        self._parse(driver_text)

    def define(self, name: str):
        if name not in self.values:
            if name not in self.defines:
                raise WalkError(f'no define !{name}')
            self.values[name] = None
            self.values[name] = self.eval(self.defines[name])
        v = self.values[name]
        if v is None:
            raise WalkError(f'!{name} refers to itself')
        return v

    def eval(self, expr: str):
        out, pos = [], 0
        while pos < len(expr):
            m = TOKEN.match(expr, pos)
            if not m:
                raise WalkError(f'cannot read the expression {expr!r}')
            t = m.group(0)
            pos = m.end()
            if t.isspace():
                continue
            if t.startswith('$'):
                out.append(str(int(t[1:], 16)))
            elif t.startswith('%') and len(t) > 1:
                out.append(str(int(t[1:], 2)))
            elif t.startswith('!'):
                out.append(f'_d({t[1:]!r})')
            elif t[0].isalpha() or t[0] == '_':
                out.append(f'_l({t!r})')
            else:
                out.append(t)
        try:
            return eval(''.join(out), {'__builtins__': {}}, {'_d': self.define, '_l': Lbl})
        except WalkError:
            raise
        except Exception as e:                      # noqa: BLE001 (a malformed expression)
            raise WalkError(f'cannot evaluate {expr!r}: {e}') from None

    def _parse(self, text: str) -> None:
        glob = None
        pending: list[str] = []
        table = None                                # the label whose dw/db lines are being read
        in_macro = False
        for no, raw in enumerate(text.splitlines(), 1):
            code = raw.split(';', 1)[0].rstrip()
            if not code.strip():
                continue
            s = code.strip()
            if s.startswith('macro '):
                in_macro = True
                continue
            if s == 'endmacro':
                in_macro = False
                continue
            if in_macro or s.startswith(('%', 'org ', 'base ', 'arch ')):
                table = None
                continue
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):$', s) if not code[0].isspace() else None
            ml = re.match(r'^\.([A-Za-z_][A-Za-z0-9_]*):$', s)
            if m:
                glob = m.group(1)
                pending.append(glob)
                table = glob
                continue
            if ml:
                if glob is None:
                    raise WalkError(f'line {no}: a local label before any global one')
                pending += [f'{glob}.{ml.group(1)}', f'{glob}_{ml.group(1)}']   # asar's two spellings
                table = None
                continue
            w = s.split(None, 1)
            if w[0] in ('dw', 'db'):
                if table is None:
                    continue                        # (the block's length word: no label reads it)
                self.tables.setdefault(table, [])
                for item in (x.strip() for x in w[1].split(',')):
                    v = self.eval(item)
                    if w[0] == 'db':
                        if not isinstance(v, int):
                            raise WalkError(f'line {no}: db {item}')
                        bs = [v & 0xFF]
                    elif isinstance(v, Lbl):
                        if v.off:
                            raise WalkError(f'line {no}: dw {item}')
                        bs = [('code', v.name, 0), ('code', v.name, 1)]
                    else:
                        bs = [v & 0xFF, v >> 8 & 0xFF]
                    self.tables[table].extend(bs)
                pending = []
                continue
            ins = Insn()
            ins.idx, ins.line, ins.text, ins.scope, ins.target = len(self.insns), no, s, glob, None
            ins.mnem = w[0].split('.', 1)[0]        # (the .b/.w width: one ARAM space with P=0)
            ins.ops = _split_ops(w[1]) if len(w) > 1 else []
            for name in pending:
                self.labels[name] = ins.idx
            pending = []
            table = None
            self.insns.append(ins)
        for ins in list(self.insns):
            if ins.mnem in TARGETED:
                try:
                    ins.target = self._target(ins.ops[-1], ins)
                except WalkError as e:
                    ins.target = e                  # raised if a walk ever runs it

    def _target(self, t: str, ins: Insn) -> int:
        m = re.fullmatch(r'(\.?[A-Za-z_][A-Za-z0-9_]*)(?:\+(\d+))?', t)
        if not m:
            raise WalkError(f'line {ins.line}: target {t!r}')
        name = f'{ins.scope}{m.group(1)}' if m.group(1).startswith('.') else m.group(1)
        if name not in self.labels:
            raise WalkError(f'line {ins.line}: no label {name}')
        i = self.labels[name]
        if not m.group(2):
            return i
        # a branch onto an operand byte: the instruction at the label must
        # be `mov r,#$NN` (2 bytes) and the byte its immediate, which must
        # encode a 1-byte instruction; that runs, then the one after.
        host, k = self.insns[i], int(m.group(2))
        im = re.fullmatch(r'#\$([0-9A-Fa-f]{2})', host.ops[-1]) if host.mnem == 'mov' and len(host.ops) == 2 else None
        if k != 1 or not im or host.ops[0] not in ('a', 'x', 'y'):
            raise WalkError(f'line {ins.line}: {t} is inside {host.text}, which the walk cannot split')
        op = int(im.group(1), 16)
        if spc700.length(op) != 1:
            raise WalkError(f'line {ins.line}: {t} lands on ${op:02X}, not a 1-byte instruction')
        mnem, template, _ = spc700.OPCODES[op]
        v = Insn()
        v.idx, v.line, v.scope, v.target = len(self.insns), host.line, host.scope, None
        v.mnem, v.ops = mnem, _split_ops(template) if template else []
        v.text = f'{mnem} {template}'.strip() + f' (the byte ${op:02X} of {host.text})'
        self.insns.append(v)
        self.next_of[v.idx] = i + 1
        return v.idx

    def next_index(self, i: int) -> int:
        return self.next_of.get(i, i + 1)


def _split_ops(s: str) -> list[str]:
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


# ── The walk ────────────────────────────────────────────────────────────────

TRACK = ('track',)
UNSET = ('unset',)
CALLER = (('caller', 1), ('caller', 0))


class State:
    __slots__ = ('i', 'stack', 'a', 'x', 'y', 'c', 'z', 'n', 'mem', 'k', 'lo', 'hi', 'carry')

    def copy(self):
        s = State()
        s.i, s.stack, s.a, s.x, s.y = self.i, self.stack, self.a, self.x, self.y
        s.c, s.z, s.n, s.mem = self.c, self.z, self.n, dict(self.mem)
        s.k, s.lo, s.hi, s.carry = self.k, self.lo, self.hi, self.carry
        return s


def _i(v):
    return isinstance(v, int)


def _join(old: State, new: State):
    """old joined with new, or None when new adds nothing to old."""
    j = old.copy()
    changed = False
    for f in ('a', 'x', 'y', 'c', 'z', 'n'):
        if getattr(old, f) is not None and getattr(old, f) != getattr(new, f):
            setattr(j, f, None)
            changed = True
    absent = ('absent',)                            # (an absent key reads as its initial value)
    for key in set(old.mem) | set(new.mem):
        a, b = old.mem.get(key, absent), new.mem.get(key, absent)
        if a != b and a is not None:
            j.mem[key] = None
            changed = True
    return j if changed else None


class Walker:
    def __init__(self, src: Source):
        self.src = src
        d = src.define
        self.ptr = d('Spc_TrackPtr')
        self.scratch = d('Spc_Scratch00')
        self.cur = d('Spc_CurTrack')
        if 'Spc_TrackStep' not in src.labels:
            raise WalkError('no Spc_TrackStep in the driver')
        self.start = src.labels['Spc_TrackStep']
        self.first = 0

    # locations: ('reg', r) | ('imm', v) | ('mem', addr) | ('x', base) | ('tab', Lbl, index) |
    # ('stream',) | ('unk', base or None)
    def loc(self, s: State, op: str, ins: Insn):
        if op in ('a', 'x', 'y'):
            return ('reg', op)
        if op.startswith('#'):
            v = self.src.eval(op[1:])
            if _i(v):
                return ('imm', v & 0xFF)
            if isinstance(v, tuple) and v[0] == 'code':
                return ('imm', v)
            raise WalkError(f'line {ins.line}: immediate {op!r}')
        if op in ('(x)', '(x+)'):
            return ('mem', s.x) if _i(s.x) else ('unk', None)
        if re.fullmatch(r'\((.*)\)\+y', op):
            return ('unk', None)                    # (dp)+y: a pointer the walk does not follow
        m = re.fullmatch(r'\((.*)\+x\)', op)
        if m:
            base = self.src.eval(m.group(1))
            if base == self.ptr and s.x == TRACK:
                return ('stream',)
            return ('unk', None)
        m = re.fullmatch(r'(.*)\+([xy])', op)
        if m:
            base = self.src.eval(m.group(1))
            ix = s.x if m.group(2) == 'x' else s.y
            if isinstance(base, Lbl):
                return ('tab', base, ix)
            if m.group(2) == 'x' and ix == TRACK:
                return ('x', base)
            if _i(ix):
                return ('mem', (base + ix) & 0xFFFF)
            return ('unk', base)
        base = self.src.eval(op)
        if isinstance(base, Lbl):
            return ('tab', base, 0)
        if not _i(base):
            raise WalkError(f'line {ins.line}: operand {op!r}')
        return ('mem', base & 0xFFFF)

    def _initial(self, addr):
        if addr == self.cur:
            return TRACK
        if addr == self.scratch:
            return ('scratch', 0)
        if addr == self.scratch + 1:
            return ('scratch', 1)
        return None

    def mem(self, s: State, addr):
        return s.mem.get(addr, self._initial(addr))

    def read(self, s: State, loc, ins: Insn):
        kind = loc[0]
        if kind == 'reg':
            return getattr(s, loc[1])
        if kind == 'imm':
            return loc[1]
        if kind == 'mem':
            return self.mem(s, loc[1])
        if kind == 'x':
            if loc[1] == self.ptr:
                return s.lo if s.lo is not UNSET else ('ptr', 0, s.k)
            if loc[1] == self.ptr + 1:
                return s.hi if s.hi is not UNSET else ('ptr', 1, s.k)
            return s.mem.get(loc)
        if kind == 'stream':
            if s.lo is not UNSET or s.hi is not UNSET:
                raise WalkError(f'line {ins.line}: a read from a pointer the walk has set')
            return self.first if s.k == 0 else ('op', s.k)
        if kind == 'tab':
            lbl, ix = loc[1], loc[2]
            table = self.src.tables.get(lbl.name)
            if table is None:
                raise WalkError(f'line {ins.line}: a read of {lbl.name}, which is code')
            if _i(ix):
                at = lbl.off + ix
                if not 0 <= at < len(table):
                    raise WalkError(f'line {ins.line}: {lbl.name}+{at} is past the table')
                return table[at]
            if any(isinstance(b, tuple) for b in table):
                return ('tab', lbl.name, lbl.off & 1)
            return None
        return None

    def write(self, s: State, loc, v, ins: Insn):
        kind = loc[0]
        if kind == 'reg':
            setattr(s, loc[1], v)
        elif kind == 'mem':
            a = loc[1]
            if v is None and self._initial(a) is None:
                s.mem.pop(a, None)
            else:
                s.mem[a] = v
        elif kind == 'x':
            if loc[1] == self.ptr:
                s.lo = v
            elif loc[1] == self.ptr + 1:
                s.hi = v
            elif v is None:
                s.mem.pop(loc, None)
            else:
                s.mem[loc] = v
        elif kind == 'unk':
            base = loc[1]
            # an indexed store with an unknown index reaches base..base+$FF
            # (taken as not wrapping in the direct page)
            if base is None or base <= self.ptr + 1 and self.ptr < base + 0x100:
                raise WalkError(f'line {ins.line}: {ins.text}: a store the walk cannot place, which may '
                                f'reach the track pointer')
            for key in list(s.mem):
                if _i(key) and base <= key < base + 0x100:
                    del s.mem[key]
        else:
            raise WalkError(f'line {ins.line}: {ins.text}: a store into the driver')

    @staticmethod
    def nz(s: State, v, bits=8):
        if _i(v):
            s.z = v == 0
            s.n = bool(v >> (bits - 1) & 1)
        else:
            s.z = s.n = None

    def run(self, first: int) -> list[tuple]:
        """The outcomes of a track whose byte under test is `first`: a sorted
        list of (end, pointer) with end 'step' or 'return' and pointer
        ('rel', k) or ('set', lo, hi, k) (k: the bytes read before)."""
        self.first = first
        s = State()
        s.i, s.stack = self.start, CALLER
        s.a = s.y = None
        s.x = TRACK
        s.c = s.z = s.n = None
        s.mem, s.k, s.lo, s.hi, s.carry = {}, 0, UNSET, UNSET, False
        todo, at, outs, steps = [s], {}, set(), 0
        while todo:
            s = todo.pop()
            first_step = True
            while True:
                if not first_step and s.i == self.start and s.stack == CALLER:
                    outs.add(('step', self._ptr(s)))
                    break
                first_step = False
                point = (s.i, s.stack, s.k, s.lo, s.hi, s.carry)
                old = at.get(point)
                if old is not None:
                    j = _join(old, s)
                    if j is None:
                        break                       # nothing new here
                    s = j
                at[point] = s.copy()
                steps += 1
                if steps > MAX_STATES:
                    raise WalkError(f'byte ${first:02X}: more than {MAX_STATES:,} states')
                more = self.step(s, self.src.insns[s.i])
                if more == 'return':
                    outs.add(('return', self._ptr(s)))
                    break
                if isinstance(more, list):
                    todo += more
                    break
        return sorted(outs, key=repr)

    @staticmethod
    def _ptr(s: State):
        if s.lo is UNSET and s.hi is UNSET:
            return ('rel', s.k)
        if s.lo is UNSET or s.hi is UNSET:
            return ('half', s.lo if s.lo is not UNSET else None, s.hi if s.hi is not UNSET else None)
        return ('set', s.lo, s.hi, s.k)

    def step(self, s: State, ins: Insn):
        """Run one instruction on s (in place); returns True to go on, a list
        of states (a branch both ways, a table RET) or 'return'."""
        if isinstance(ins.target, WalkError):
            raise ins.target
        mn, ops = ins.mnem, ins.ops
        nxt = self.src.next_index(ins.idx)
        s.i = nxt
        if mn in BRANCHES:
            if mn == 'bra':
                s.i = ins.target
                return True
            flag, want = {'bne': ('z', False), 'beq': ('z', True), 'bcs': ('c', True), 'bcc': ('c', False),
                          'bpl': ('n', False), 'bmi': ('n', True), 'bvs': ('v', True), 'bvc': ('v', False)}[mn]
            have = getattr(s, flag) if flag != 'v' else None
            return self._fork(s, ins.target, None if have is None else have == want)
        if mn == 'jmp':
            if ops[0].startswith('('):
                raise WalkError(f'line {ins.line}: {ins.text}: an indexed jump')
            s.i = ins.target
            return True
        if mn == 'call':
            s.stack = s.stack + (('ret', nxt, 1), ('ret', nxt, 0))
            s.i = ins.target
            return True
        if mn == 'ret':
            return self._ret(s, ins)
        if mn == 'push':
            s.stack = s.stack + ((('psw', s.c, s.z, s.n) if ops[0] == 'p' else getattr(s, ops[0])),)
            return True
        if mn == 'pop':
            if not s.stack:
                raise WalkError(f'line {ins.line}: a POP from an empty stack')
            v, s.stack = s.stack[-1], s.stack[:-1]
            if ops[0] == 'p':
                if not (isinstance(v, tuple) and v[0] == 'psw'):
                    raise WalkError(f'line {ins.line}: POP P of a value PUSH P did not push')
                s.c, s.z, s.n = v[1:]
            else:
                setattr(s, ops[0], v)
            return True
        if mn in ('clrc', 'setc', 'notc'):
            s.c = False if mn == 'clrc' else True if mn == 'setc' else (None if s.c is None else not s.c)
            return True
        if mn in ('clrp', 'di', 'ei', 'nop', 'clrv'):
            return True
        if mn == 'mov':
            return self._mov(s, ins)
        if mn in ('or', 'and', 'eor', 'adc', 'sbc', 'cmp'):
            return self._alu(s, ins)
        if mn in ('inc', 'dec'):
            return self._incdec(s, ins)
        if mn in ('asl', 'lsr', 'rol', 'ror'):
            loc = self.loc(s, ops[0], ins)
            v = self.read(s, loc, ins)
            r = None
            if _i(v) and (mn in ('asl', 'lsr') or s.c is not None):
                cin = int(bool(s.c)) if mn in ('rol', 'ror') else 0
                if mn in ('asl', 'rol'):
                    s.c, r = bool(v & 0x80), (v << 1 | cin) & 0xFF
                else:
                    s.c, r = bool(v & 1), v >> 1 | cin << 7
            else:
                s.c = None
            self.write(s, loc, r, ins)
            self.nz(s, r)
            return True
        if mn == 'xcn':
            s.a = (s.a >> 4 | s.a << 4) & 0xFF if _i(s.a) else None
            self.nz(s, s.a)
            return True
        if mn == 'mul':
            if _i(s.a) and _i(s.y):
                r = s.a * s.y
                s.a, s.y = r & 0xFF, r >> 8
            else:
                s.a = s.y = None
            self.nz(s, s.y)
            return True
        if mn == 'div':
            if _i(s.a) and _i(s.y) and _i(s.x) and s.x and s.y < s.x:
                ya = s.y << 8 | s.a
                s.a, s.y = ya // s.x, ya % s.x
            else:
                s.a = s.y = None
            self.nz(s, s.a)
            return True
        if mn in ('movw', 'addw', 'subw', 'cmpw'):
            return self._word(s, ins)
        if mn in ('incw', 'decw'):
            a = self.src.eval(ops[0])
            lo, hi = self.mem(s, a), self.mem(s, a + 1)
            if _i(lo) and _i(hi):
                v = ((hi << 8 | lo) + (1 if mn == 'incw' else -1)) & 0xFFFF
                self.write(s, ('mem', a), v & 0xFF, ins)
                self.write(s, ('mem', a + 1), v >> 8, ins)
                self.nz(s, v, 16)
            else:
                self.write(s, ('mem', a), None, ins)
                self.write(s, ('mem', a + 1), None, ins)
                s.z = s.n = None
            return True
        if mn in ('set1', 'clr1', 'not1'):
            addr, bit = self._bit(ops[0], ins)
            v = self.mem(s, addr)
            if _i(v):
                v = v | 1 << bit if mn == 'set1' else v & ~(1 << bit) if mn == 'clr1' else v ^ 1 << bit
            else:
                v = None
            self.write(s, ('mem', addr), v, ins)
            return True
        if mn == 'mov1':
            if ops[0] == 'c':
                addr, bit = self._bit(ops[1], ins)
                v = self.mem(s, addr)
                s.c = bool(v >> bit & 1) if _i(v) else None
            else:
                addr, bit = self._bit(ops[0], ins)
                v = self.mem(s, addr)
                v = (v & ~(1 << bit) | int(s.c) << bit) if _i(v) and s.c is not None else None
                self.write(s, ('mem', addr), v, ins)
            return True
        if mn in ('bbs', 'bbc'):
            addr, bit = self._bit(ops[0], ins)
            v = self.mem(s, addr)
            return self._fork(s, ins.target, None if not _i(v) else bool(v >> bit & 1) == (mn == 'bbs'))
        if mn == 'cbne':
            v = self.read(s, self.loc(s, ops[0], ins), ins)
            take = v != s.a if _i(v) and _i(s.a) else (False if v is not None and v == s.a else None)
            return self._fork(s, ins.target, take)
        if mn == 'dbnz':
            loc = self.loc(s, ops[0], ins)
            v = self.read(s, loc, ins)
            v = (v - 1) & 0xFF if _i(v) else None
            self.write(s, loc, v, ins)
            return self._fork(s, ins.target, None if v is None else v != 0)
        if mn in ('tset', 'tclr'):
            loc = self.loc(s, ops[0], ins)
            v = self.read(s, loc, ins)
            if _i(v) and _i(s.a):
                self.nz(s, (s.a - v) & 0xFF)
                self.write(s, loc, v | s.a if mn == 'tset' else v & ~s.a & 0xFF, ins)
            else:
                s.z = s.n = None
                self.write(s, loc, None, ins)
            return True
        raise WalkError(f'line {ins.line}: {ins.text}: an instruction the walk does not model')

    @staticmethod
    def _fork(s: State, target: int, take):
        if take is True:
            s.i = target
            return True
        if take is False:
            return True
        t = s.copy()
        t.i = target
        return [s, t]

    def _ret(self, s: State, ins: Insn):
        if len(s.stack) < 2:
            raise WalkError(f'line {ins.line}: a RET with {len(s.stack)} byte(s) on the stack')
        lo, hi = s.stack[-1], s.stack[-2]
        s.stack = s.stack[:-2]
        if (hi, lo) == CALLER:
            return 'return'
        if isinstance(lo, tuple) and isinstance(hi, tuple) and lo[:2] == hi[:2] and lo[-1] == 0 and hi[-1] == 1:
            if lo[0] == 'ret':
                s.i = lo[1]
                return True
            if lo[0] == 'code':
                s.i = self._code(lo[1], ins)
                return True
        if isinstance(lo, tuple) and isinstance(hi, tuple) and lo[0] == hi[0] == 'tab' and lo[1] == hi[1] \
                and lo[2] == 0 and hi[2] == 1:
            table = self.src.tables[lo[1]]
            outs = []
            for k in range(0, len(table) - 1, 2):
                a, b = table[k], table[k + 1]
                if a == 0 and b == 0:
                    continue
                if not (isinstance(a, tuple) and isinstance(b, tuple) and a[1] == b[1]):
                    raise WalkError(f'line {ins.line}: {lo[1]} entry {k // 2} is not an address')
                t = s.copy()
                t.i = self._code(a[1], ins)
                outs.append(t)
            return outs
        raise WalkError(f'line {ins.line}: a RET to {hi!r}/{lo!r}, which the walk cannot follow')

    def _code(self, name: str, ins: Insn) -> int:
        if name not in self.src.labels:
            raise WalkError(f'line {ins.line}: no code label {name}')
        return self.src.labels[name]

    def _bit(self, op: str, ins: Insn):
        m = re.fullmatch(r'(.*)\.([0-7])', op)
        a = self.src.eval(m.group(1)) if m else None
        if not _i(a):
            raise WalkError(f'line {ins.line}: bit operand {op!r}')
        return a, int(m.group(2))

    def _mov(self, s: State, ins: Insn):
        dst, src = ins.ops
        if dst == 'sp' or src == 'sp':
            raise WalkError(f'line {ins.line}: {ins.text}: the walk keeps its own stack')
        v = self.read(s, self.loc(s, src, ins), ins)
        if src == '(x+)':
            s.x = (s.x + 1) & 0xFF if _i(s.x) else None
        ld = self.loc(s, dst, ins)
        self.write(s, ld, v, ins)
        if dst == '(x+)':
            s.x = (s.x + 1) & 0xFF if _i(s.x) else None
        if ld[0] == 'reg':
            self.nz(s, v)
        return True

    def _alu(self, s: State, ins: Insn):
        mn = ins.mnem
        dst, src = ins.ops
        ld, ls = self.loc(s, dst, ins), self.loc(s, src, ins)
        a, b = self.read(s, ld, ins), self.read(s, ls, ins)
        r = None
        if _i(a) and _i(b):
            if mn == 'or':
                r = a | b
            elif mn == 'and':
                r = a & b
            elif mn == 'eor':
                r = a ^ b
            elif mn == 'cmp':
                s.c = a >= b
                self.nz(s, (a - b) & 0xFF)
                return True
            elif s.c is not None:
                if mn == 'adc':
                    t = a + b + int(s.c)
                    s.c, r = t > 0xFF, t & 0xFF
                else:
                    t = a - b - (1 - int(s.c))
                    s.c, r = t >= 0, t & 0xFF
            else:
                s.c = None
        else:
            if mn == 'cmp' and a is not None and a == b:
                s.c, s.z, s.n = True, True, False   # the same symbol on both sides
                return True
            if mn in ('adc', 'sbc', 'cmp'):
                s.c = None
        if mn == 'cmp':
            s.z = s.n = None
            return True
        self.write(s, ld, r, ins)
        self.nz(s, r)
        return True

    def _incdec(self, s: State, ins: Insn):
        loc = self.loc(s, ins.ops[0], ins)
        if loc[0] == 'x' and loc[1] in (self.ptr, self.ptr + 1):
            if ins.mnem != 'inc' or s.lo is not UNSET or s.hi is not UNSET:
                raise WalkError(f'line {ins.line}: {ins.text}: a pointer change the walk does not model')
            if loc[1] == self.ptr:
                s.k += 1
                s.carry = True
            elif not s.carry:
                raise WalkError(f'line {ins.line}: {ins.text}: the pointer\'s high byte moved alone')
            else:
                s.carry = False                     # the carry of the INC before it
            s.z = s.n = None
            return True
        v = self.read(s, loc, ins)
        r = (v + (1 if ins.mnem == 'inc' else -1)) & 0xFF if _i(v) else None
        self.write(s, loc, r, ins)
        self.nz(s, r)
        return True

    def _word(self, s: State, ins: Insn):
        mn = ins.mnem
        if mn == 'movw' and ins.ops[0] != 'ya':
            a = self.src.eval(ins.ops[0])
            self.write(s, ('mem', a), s.a, ins)
            self.write(s, ('mem', a + 1), s.y, ins)
            return True
        a = self.src.eval(ins.ops[1])
        if not _i(a):
            raise WalkError(f'line {ins.line}: {ins.text}')
        lo, hi = self.mem(s, a), self.mem(s, a + 1)
        if mn == 'movw':
            s.a, s.y = lo, hi
            if _i(lo) and _i(hi):
                self.nz(s, hi << 8 | lo, 16)
            else:
                s.z = s.n = None
            return True
        ya = s.y << 8 | s.a if _i(s.a) and _i(s.y) else None
        m = hi << 8 | lo if _i(lo) and _i(hi) else None
        if ya is not None and m is not None:
            t = ya + m if mn == 'addw' else ya - m
            s.c = t > 0xFFFF if mn == 'addw' else t >= 0
            t &= 0xFFFF
            self.nz(s, t, 16)
            if mn != 'cmpw':
                s.a, s.y = t & 0xFF, t >> 8
            return True
        s.c = s.z = s.n = None
        if mn == 'cmpw':
            return True
        if mn == 'addw' and lo == ('scratch', 0) and hi == ('scratch', 1) and s.a is not None and s.y is not None:
            word = (s.a, s.y)
            s.a, s.y = ('moved', 0, word), ('moved', 1, word)
            return True
        s.a = s.y = None
        return True


# ── What each byte does ─────────────────────────────────────────────────────

def load_source(root: Path = ROOT) -> Source:
    root = Path(root)
    return Source((root / DRIVER).read_text(), [(root / p).read_text() for p in INCLUDES])


def derive(src: Source | None = None, root: Path = ROOT) -> dict:
    """What each byte $00-$FF of a track does, from the walk. Every byte
    below !Spc_SeqFirstCmd must take one byte and return (the track waits a
    pass). A command ($C4-$FF) gets:
      length     where it steps on, else the bytes it read (every way the
                 same, and no way reads past it);
      next       it can step on (one length only);
      jump       the operand index of a word it can set the pointer to,
                 plus the song's move (two adjacent operands);
      end        it can return with the track ended;
      elsewhere  it can set the pointer from anything else;
      handler    its entry of Spc_SeqCmdTable."""
    src = src or load_source(root)
    w = Walker(src)
    first_cmd = src.define('Spc_SeqFirstCmd')
    table = src.tables.get('Spc_SeqCmdTable')
    if table is None or len(table) != 2 * (256 - first_cmd):
        raise WalkError('Spc_SeqCmdTable is not one word per command')
    out = {}
    for b in range(256):
        outs = w.run(b)
        if b < first_cmd:
            if outs != [('return', ('rel', 1))]:
                raise WalkError(f'byte ${b:02X} (below !Spc_SeqFirstCmd): {outs}, not one byte and a wait')
            out[b] = {'length': 1, 'next': True, 'jump': None, 'end': False, 'elsewhere': False}
            continue
        nexts, jumps, ends, elsewhere = set(), set(), False, False
        for end, ptr in outs:
            if ptr[0] == 'half':
                raise WalkError(f'command ${b:02X}: the pointer is left half set')
            if end == 'return':
                ends = True
            elif ptr[0] == 'rel':
                nexts.add(ptr[1])
            else:
                lo, hi = ptr[1], ptr[2]
                if isinstance(lo, tuple) and lo[0] == 'moved' and hi == ('moved', 1, lo[2]) and lo[1] == 0:
                    wd = lo[2]
                    if isinstance(wd[0], tuple) and isinstance(wd[1], tuple) and wd[0][0] == wd[1][0] == 'op' \
                            and wd[1][1] == wd[0][1] + 1:
                        jumps.add(wd[0][1])
                        continue
                    raise WalkError(f'command ${b:02X}: a pointer moved from {wd!r}, not a word of its operands')
                elsewhere = True
        if len(nexts) > 1:
            raise WalkError(f'command ${b:02X}: it steps on at +{" and +".join(map(str, sorted(nexts)))}')
        if len(jumps) > 1:
            raise WalkError(f'command ${b:02X}: two jump operands')
        reads = sorted({p[1] if p[0] == 'rel' else p[3] for _, p in outs})
        if nexts:
            length = min(nexts)
        elif len(reads) == 1:
            length = reads[0]
        else:
            raise WalkError(f'command ${b:02X}: no single length ({outs})')
        if any(k > length for k in reads) or any(e == 'return' and p[0] == 'rel' and p[1] != length
                                                 for e, p in outs):
            raise WalkError(f'command ${b:02X}: it reads {reads} bytes, its length is {length}')
        if jumps and min(jumps) + 1 >= length:
            raise WalkError(f'command ${b:02X}: its jump word is past its length')
        h = table[2 * (b - first_cmd)]
        out[b] = {'length': length, 'next': bool(nexts), 'jump': min(jumps) if jumps else None,
                  'end': ends, 'elsewhere': elsewhere, 'handler': h[1] if isinstance(h, tuple) else None}
    return {'first_cmd': first_cmd, 'first_tie': src.define('Spc_SeqFirstTie'),
            'first_rest': src.define('Spc_SeqFirstRest'),
            'durations': [int(x) for x in src.tables['Spc_DurationTable']],
            'num_durations': src.define('Spc_NumDurations'), 'commands': out}


def main(argv=None) -> int:
    args = sys.argv[1:] if argv is None else argv
    w = Walker(load_source())
    for a in args or [f'{b:02X}' for b in range(0xC4, 0x100)]:
        b = int(a, 16)
        print(f'${b:02X}', w.run(b))
    return 0


if __name__ == '__main__':
    sys.exit(main())
