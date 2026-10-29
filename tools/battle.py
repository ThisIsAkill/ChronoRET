#!/usr/bin/env python3
"""
battle.py — The battle scripts as readable text, extracted from your own ROM
into the ignored build/assets/battle/, and an assembler that rebuilds their
exact bytes, which the build incbins (DATA_PLAN.md, step 7).

No script is ever committed (README, "Legal"); this tool holds only how the
battle code reads them, and takes even that from the matched source. Two
units, one readable file each:

actions.bscr — the action scripts (BattleAct_RunThread's language), with
the five script tables (BattleRom_PcAttackScripts ... Kind3Scripts) and
the subscript table (BattleRom_ActSubscripts) that point into them:

  * The opcodes are BattleAct_OpcodeTable's, read from the source; a byte of
    !Battle_ActNumOpcodes or more is not run (the thread halts on it).
  * Each opcode's operand bytes and where the thread goes on are what the
    handler does with the bytes it is given: tools/absint.py runs the
    handler's assembled code (an assembly of asm/main.asm, not the ROM) as
    BattleAct_RunThread calls it (Y = 0, B = 0, the script pointer in DP
    $E6-$E8, the opcode in !Battle_ActOpcode), for a battler thread (0), the
    target-set thread (4) and an object thread (8), with the script bytes
    known and all other RAM unknown, both ways of every branch on an unknown
    value. Its operands are the script bytes it reads; every way it returns
    leaves the pointer:
      next   the pointer moved on by a constant (the opcode's length), or by
             a count read from its own bytes as far as it reads (opcode $80);
      stay   the pointer unchanged (a wait, or the end of the thread);
      call   the pointer set from the subscript table by an operand, with
             the place after the operands kept as the return address;
      end    the pointer taken from RAM no script byte sets (a return);
      stale  the pointer moved by a count from RAM this opcode did not leave
             ($98/$99 in the target-set thread and in an object thread
             entered mid-move, $18 in the target-set and object threads):
             not followed, no return.
    Opcode $80 with a count of 0 (256 bytes copied, advance 1) is refused.
    A handler that waits (the pointer unchanged) is run for a second frame
    from the state the first left (the movers $10-$18 and $98-$9D keep
    their length in RAM):
    where that frame goes on is its length. The length is where it goes on
    (else the bytes it reads). A handler whose pointer depends on a callee
    the interpreter could not follow makes the unit fail to disassemble.
  * A script starts with a header: two 16-bit thread masks, high byte first,
    then one 16-bit thread offset per set bit (BattleAct_LoadAttack and the
    other loaders). Threads, subscripts and what they reach are code; bytes
    never reached are data.

enemy.bscr — the enemy behaviour scripts (BattleRom_AiScriptPtrs: one bank-$CC
address per enemy id, 256, then the scripts). These are records in blocks,
not a language with jumps, and are read under the records rule: the layout
is the one the readers walk (BattleAi_RunMainPart, BattleAi_FindReactPart,
BattleAi_TestPassed, BattleAi_EnemyTurn): a script is a main part and a
reaction part, each ended by $FF (the reaction part starts after the first
$FF byte: FindReactPart scans for it); a part is blocks; a block is one or
two 4-byte test records (two when byte 4 is not $FE), $FE, the action
records, $FE. An action record is its code and !BattleRom_AiActLength[code]
bytes in all (BattleFD_AiActLength, read from the assembled source); code 4
(BattleAi_ChooseByChance) is its code alone (it steps past it with INX). An
action code of $80 or more ends the records (the bytes to the $FE are not
read as records: data). A script whose parts the readers would split two
different ways is kept as bytes and counted so.

The readable forms:

  actions.bscr
    @table LABEL $BB            a script or subscript table (its bank)
    @entry I TARGET             entry I: a label, none ($FFFF) or $XXXX
    @region LABEL $AAAAAA       the scripts of a piece, from its address
    LABEL:                      a label
        @threads $M1 $M2 L ...  a script header: masks and thread labels
        Op12_MoveToCalc $0C $1B an opcode by its handler's name and its
                                operand bytes (the assembler checks the
                                length against the handler)
        @inner +K LABEL OP ...  an opcode reached inside the one above
        Halt $FF                a byte that is not an opcode, reached
    @bytes 01 02 ...            bytes no opcode reaches (data)

  enemy.bscr
    @enemies LABEL $AAAAAA      the table, then one line per enemy id:
    @enemy I LABEL
    LABEL:
        test NAME $b1 $b2 $b3   a test record (BattleAi_TestTable's name)
        do                      $FE: the tests end
        act NAME $..            an action record (BattleAi_RunTable's name,
                                or the choose handler's for a no-op run)
        done                    $FE: the actions end
        end                     $FF: the part ends
    @bytes ...                  bytes read as no record

    python3 tools/battle.py check     disassemble every battle script afresh
                                      and assemble it back, every line
                                      checked against the readers: byte-
                                      exact?
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import absint  # noqa: E402
import events  # noqa: E402

CACHE_DIR = Path('build/battle')            # the code image and the traces (relative to the root)
BANK_C1 = ROOT / 'asm' / 'bankC1' / 'bankC1.asm'
INCLUDE = ROOT / 'asm' / 'include'

# The survey rows each unit is made of: start -> (unit, role).
ROWS = {
    '$CD:5EC6': ('actions', 'table'),       # BattleRom_PcAttackScripts
    '$CD:5EF0': ('actions', 'table'),       # BattleRom_PcTechScripts
    '$CD:5FF0': ('actions', 'table'),       # BattleRom_EnemyAttackScripts
    '$CD:61F0': ('actions', 'table'),       # BattleRom_EnemyTechScripts
    '$CD:63F0': ('actions', 'table'),       # BattleRom_Kind3Scripts
    '$CE:0000': ('actions', 'subscripts'),  # BattleRom_ActSubscripts
    '$CD:6E0C': ('actions', 'scripts'),
    '$CD:96FA': ('actions', 'scripts'),
    '$CE:0380': ('actions', 'scripts'),
    '$CE:8294': ('actions', 'scripts'),
    '$CE:D428': ('actions', 'scripts'),
    '$CC:8B08': ('enemy', 'enemy'),               # BattleRom_AiScriptPtrs and the scripts
}
UNITS = ('actions', 'enemy')
ROLES = ('table', 'subscripts', 'scripts', 'enemy')

# The bank of each table's offsets: the bank the loader (or opcode $1E)
# stores with them (LDA.w #!BattleRom_ScriptBankPc / Enemy).
TABLE_BANKS = {
    'BattleRom_PcAttackScripts': 'BattleRom_ScriptBankPc',      # BattleAct_LoadAttack
    'BattleRom_PcTechScripts': 'BattleRom_ScriptBankPc',        # BattleAct_LoadTech
    'BattleRom_EnemyAttackScripts': 'BattleRom_ScriptBankEnemy',  # BattleAct_LoadAttack
    'BattleRom_EnemyTechScripts': 'BattleRom_ScriptBankEnemy',  # BattleAct_LoadTech
    'BattleRom_Kind3Scripts': 'BattleRom_ScriptBankPc',         # BattleAct_LoadKind3
    'BattleRom_ActSubscripts': 'BattleRom_ScriptBankPc',        # BattleAct_OpCall
}

# The kinds of thread the handlers tell apart (by !Battle_ActThread), each
# traced as one of its threads: 0-3 a battler's, 4 the target set's, 8-15
# an object's. Threads 5-7 are never run (BattleAct_RunThreads).
KINDS = {'battler': 0, 'set': 4, 'object': 8}


def thread_kind(t: int) -> str | None:
    return 'battler' if t < 4 else 'set' if t == 4 else None if t < 8 else 'object'


class BattleError(Exception):
    pass


def defines(root: Path = ROOT) -> dict[str, int]:
    """{name: value} of the `!Name = $hex` (or decimal) defines in asm/include/."""
    out = {}
    for path in sorted((Path(root) / 'asm' / 'include').glob('*.inc')):
        for line in path.read_text(errors='replace').splitlines():
            m = re.match(r'^!([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\$[0-9A-Fa-f]+|[0-9]+)(?![\w$+*-])', line)
            if m:
                v = m.group(2)
                out.setdefault(m.group(1), int(v[1:], 16) if v.startswith('$') else int(v))
    return out


def table_handlers(label: str, path: Path = BANK_C1) -> list[str]:
    """The `dw` entries of a jump table in the source."""
    lines = Path(path).read_text().splitlines()
    try:
        i = lines.index(f'{label}:')
    except ValueError:
        raise BattleError(f'{path.name}: no {label}') from None
    out = []
    for line in lines[i + 1:]:
        m = re.match(r'^\s+dw\s+([A-Za-z_][A-Za-z0-9_]*)', line)
        if not m:
            break
        out.append(m.group(1))
    return out


def act_names(root: Path = ROOT) -> tuple[list[str], int]:
    """(the name of every action opcode, the number that run): handler
    names from BattleAct_OpcodeTable, with the opcode in front."""
    count = defines(root)['Battle_ActNumOpcodes']
    handlers = table_handlers('BattleAct_OpcodeTable', Path(root) / 'asm' / 'bankC1' / 'bankC1.asm')
    if len(handlers) < count:
        raise BattleError(f'BattleAct_OpcodeTable has {len(handlers)} entries, fewer than {count}')
    out = []
    for op, h in enumerate(handlers[:count]):
        short = h[len('BattleAct_Op'):] if h.startswith('BattleAct_Op') else h.removeprefix('BattleAct_')
        out.append(f'Op{op:02X}_{short}')
    return out, count


def ai_names(root: Path = ROOT) -> tuple[list[str], list[str]]:
    """(test names, action names) from BattleAi_TestTable and BattleAi_RunTable
    (BattleAi_ChooseTable's for a run handler that does nothing)."""
    path = Path(root) / 'asm' / 'bankC1' / 'bankC1.asm'
    tests = table_handlers('BattleAi_TestTable', path)
    runs = table_handlers('BattleAi_RunTable', path)
    chooses = table_handlers('BattleAi_ChooseTable', path)
    if len(runs) != len(chooses):
        raise BattleError('BattleAi_RunTable and BattleAi_ChooseTable differ in length')

    def unique(names):
        return [n if names.count(n) == 1 else f'{n}_{i:02X}' for i, n in enumerate(names)]
    t = unique([n.removeprefix('BattleAi_') for n in tests])
    a = unique([(c if r.startswith('BattleAi_RunNop') else r).removeprefix('BattleAi_')
                for r, c in zip(runs, chooses)])
    return t, a


# ── The action interpreter, from the source ────────────────────────────────

class Op:
    __slots__ = ('off', 'op', 'length', 'fixed', 'next', 'stay', 'end', 'stale', 'call', 'halt', 'inside')


STALE = 0x1000000      # a mark kept in a path's memory (no address): it advanced by an unknown count


class _Machine(absint.Machine):
    """absint's machine, marking a path that enters BattleAct_AdvanceScript
    with an unknown count (A, 16-bit there): the pointer moves by a length
    from RAM, which is not a return."""
    advance: int | None = None

    def step(self, s, base_depth):
        if s.pc == self.advance and (s.a is None or s.b is None):
            s.mem[STALE] = 1
        return super().step(s, base_depth)


class ActInterp:
    """The action opcodes as the matched handlers run them."""

    def __init__(self, root: Path = ROOT):
        root = Path(root)
        self.image, self.mask, self.labels = events.code_image(root, root / CACHE_DIR)
        self.code_key = hashlib.sha256(self.image + bytes(self.mask)).hexdigest()
        self.names, self.count = act_names(root)
        d = defines(root)
        table = self.labels.get('BattleAct_OpcodeTable')
        if table is None:
            raise BattleError('no BattleAct_OpcodeTable in the source')
        off = (table >> 16) - 0xC0 << 16 | table & 0xFFFF
        self.handlers = [(table & 0xFF0000) | self.image[off + 2 * op] | self.image[off + 2 * op + 1] << 8
                         for op in range(self.count)]
        self.ram = {k: 0x7E0000 | d[k] for k in ('Battle_ActScriptPtr', 'Battle_ActNextOp', 'Battle_ActOpcode',
                                                 'Battle_ActThread', 'Battle_ActThreadOfs', 'Battle_ActObjThread')}
        self.first_obj = d['Battle_ActFirstObjThread']
        self.machine = _Machine(self.image, self.mask, max_steps=5000000, callee_steps=200000)
        self.machine.advance = self.labels.get('BattleAct_AdvanceScript')
        self.cache: dict[int, dict[tuple, dict[tuple, dict]]] = {}
        self.dirty = False

    def _entry(self, op: int, ptr: int, thread: int, mem: dict | None = None, memt: dict | None = None):
        s = absint.State()
        s.pc = self.handlers[op]
        s.a, s.b, s.x, s.y = 0, 0, op * 2, 0          # BattleRun_Thread: TDC after the 16-bit TAX
        s.d, s.db = 0, 0x7E
        s.m, s.xf = True, False
        s.c = s.z = s.n = s.v = None
        s.sp, s.spt = [], []
        s.mem = dict(mem) if mem is not None else {}
        s.memt = dict(memt) if memt is not None else {}
        s.mem.pop(STALE, None)
        p = self.ram['Battle_ActScriptPtr']
        # $E9 is only the high byte of AdvanceScript's 16-bit add to the bank
        # byte: the pointer's three bytes do not depend on it
        s.mem.update({p: ptr & 0xFF, p + 1: ptr >> 8 & 0xFF, p + 2: ptr >> 16, p + 3: 0,
                      self.ram['Battle_ActNextOp']: 0, self.ram['Battle_ActOpcode']: op,
                      self.ram['Battle_ActThread']: thread, self.ram['Battle_ActThread'] + 1: 0,
                      self.ram['Battle_ActThreadOfs']: thread * 4})
        # (BattleAct_RunThread stores the thread with a 16-bit STY: its high
        # byte is 0, which the handlers' 16-bit LDX of it reads)
        if thread >= self.first_obj:
            s.mem[self.ram['Battle_ActObjThread']] = thread - self.first_obj
        for k in list(s.memt):
            if p <= k < p + 4:
                del s.memt[k]
        s.at = s.xt = s.yt = s.ft = absint.E
        s.depth = 0
        return s

    def run(self, known: dict[int, int], ptr: int, kind: str) -> dict:
        """What the opcode at ptr does in a thread of `kind`: {'reads',
        'control', 'outs', 'opaque'} (offsets relative to ptr; see the
        docstring)."""
        op = f'{kind}:{known[ptr]}'
        for pattern, by_values in self.cache.get(op, {}).items():
            places = [k if absolute else ptr + k for absolute, k in pattern]
            if all(p in known for p in places):
                out = by_values.get(tuple(known[p] for p in places))
                if out is not None:
                    return out
        out = self._trace(known, ptr, KINDS[kind])
        keys = set(out['control']) | set(out['reads'])
        for x in out['outs']:
            if x[0] == 'pos':
                keys |= set(x[3])
        pattern = tuple(sorted((False, k) if 0 <= k < 64 else (True, ptr + k) for k in keys))
        values = tuple(known.get(k if absolute else ptr + k) for absolute, k in pattern)
        if None not in values:
            self.cache.setdefault(op, {}).setdefault(pattern, {})[values] = out
            self.dirty = True
        return out

    def _trace(self, known: dict[int, int], ptr: int, thread: int) -> dict:
        op = known[ptr]
        m = self.machine
        p = self.ram['Battle_ActScriptPtr']
        reads, control, opaque, outs = set(), set(), set(), set()

        def pointer(st):
            v = [st.mem.get(p + i) for i in range(3)]
            t = absint.E
            for i in range(3):
                t |= st.memt.get(p + i, absint.E)
            return (None if None in v else v[0] | v[1] << 8 | v[2] << 16), t

        def saved_return(st, new):
            # the place after the operands, kept in RAM for the return
            for k in range(1, 16):
                r = ptr + k
                for a, v in st.mem.items():
                    if p <= a < p + 4 or v != (r & 0xFF):
                        continue
                    if st.mem.get(a + 1) == (r >> 8 & 0xFF) and a + 1 not in range(p, p + 4):
                        return k
            return None

        # frame 1 from the entry state; frame 2 from each state a wait (the
        # pointer unchanged) left, as the thread runs the opcode again
        stays = []
        for frame in (1, 2):
            starts = [self._entry(op, ptr, thread)] if frame == 1 else stays
            stays = []
            seen = set()
            for s in starts:
                try:
                    ends = m.run(s, known)
                except absint.Unresolved as e:
                    return {'reads': [], 'control': [], 'outs': [('bad', str(e))], 'opaque': []}
                reads |= {a - ptr for a in m.reads}
                control |= {a - ptr for a in m.control}
                opaque |= m.opaque
                for st, how in ends:
                    if how != 'rts':
                        outs.add(('bad', f'returns with {how}'))
                        continue
                    new, t = pointer(st)
                    if new is None:
                        outs.add(('unknown', frame, bool(m.opaque), STALE in st.mem))
                        continue
                    d = new - ptr
                    # (a call's target is kept as an address: it comes from the
                    # subscript table, wherever the opcode is)
                    ret = saved_return(st, new) if t else None
                    outs.add(('pos', d, bool(t), tuple(sorted(a - ptr for a in t)), frame, ret,
                              new if ret is not None else None))
                    if d == 0 and not t and frame == 1:
                        key = hash(tuple(sorted((k, v) for k, v in st.mem.items() if k != STALE)))
                        if key not in seen:
                            seen.add(key)
                            stays.append(self._entry(op, ptr, thread, st.mem, st.memt))
            if not stays:
                break
        return {'reads': sorted(k for k in reads if k > 0), 'control': sorted(control),
                'outs': sorted(outs, key=str), 'opaque': sorted(opaque)}

    # The traces are kept between runs in build/battle/traces.json (plain
    # JSON), keyed by the tools' and the source's hash, with the file's
    # sha256 in traces.key: tamper-evident, not tamper-proof (it catches a
    # file changed by hand, not one forged with its key). CI never has the
    # file and traces afresh, and every unit still has to assemble back to
    # the ROM's bytes, which verify checks.
    def _trace_files(self, root: Path) -> tuple[Path, Path, str]:
        h = hashlib.sha256(self.code_key.encode())
        # the tracing part of this file (the interpreter section), and the
        # tools it runs on
        me = (ROOT / 'tools' / 'battle.py').read_text()
        h.update(me[me.index('# ── The action interpreter'):me.index('\ndef classify(')].encode())
        for tool in ('events.py', 'absint.py', 'disasm.py'):
            h.update((ROOT / 'tools' / tool).read_bytes())
        return root / CACHE_DIR / 'traces.json', root / CACHE_DIR / 'traces.key', h.hexdigest()

    def load(self, root: Path = ROOT) -> None:
        data_f, key_f, key = self._trace_files(Path(root))
        if not (data_f.exists() and key_f.exists()):
            return
        want, _, digest = key_f.read_text().partition(' ')
        if want != key:
            return
        raw = data_f.read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest.strip():
            raise BattleError(f'{data_f} is not what tools/battle.py wrote (changed by hand?); '
                              f'delete it and {key_f.name} to trace the handlers again')
        try:
            j = json.loads(raw.decode())
            self.cache = {op: {tuple(tuple(k) for k in pat): {tuple(v): _out_from(o) for v, o in by}
                               for pat, by in pats} for op, pats in j}
        except (ValueError, KeyError, TypeError, IndexError) as e:
            raise BattleError(f'{data_f}: not a trace file ({e}); delete it to trace again') from None
        self.dirty = False

    def save(self, root: Path = ROOT) -> None:
        if not self.dirty:
            return
        data_f, key_f, key = self._trace_files(Path(root))
        raw = json.dumps([[op, [[[list(k) for k in pat], [[list(v), _out_to(o)] for v, o in by.items()]]
                                for pat, by in pats.items()]] for op, pats in self.cache.items()],
                         separators=(',', ':')).encode()
        data_f.parent.mkdir(parents=True, exist_ok=True)
        data_f.write_bytes(raw)
        key_f.write_text(f'{key} {hashlib.sha256(raw).hexdigest()}')
        self.dirty = False


def _out_to(o: dict) -> dict:
    return {'reads': list(o['reads']), 'control': list(o['control']), 'opaque': [list(x) for x in o['opaque']],
            'outs': [[x[0], x[1], x[2], list(x[3]), x[4], x[5], x[6]] if x[0] == 'pos' else list(x)
                     for x in o['outs']]}


def _out_from(o: dict) -> dict:
    return {'reads': o['reads'], 'control': o['control'], 'opaque': [tuple(x) for x in o['opaque']],
            'outs': [(x[0], x[1], x[2], tuple(x[3]), x[4], x[5], x[6]) if x[0] == 'pos' else tuple(x)
                     for x in o['outs']]}


def classify(interp: ActInterp, known: dict[int, int], ptr: int, kind: str) -> Op:
    """The opcode at ptr in a thread of `kind`, from its handler (see the
    docstring); raises BattleError when the handler cannot be followed."""
    o = Op()
    o.off, o.op = ptr, known[ptr]
    o.next = o.stay = o.end = o.stale = o.halt = False
    o.call, o.inside = None, []
    if o.op >= interp.count:
        o.length, o.halt, o.fixed = 1, True, True
        return o
    res = interp.run(known, ptr, kind)
    where = f'${ptr:06X} opcode ${o.op:02X} ({interp.names[o.op]}, {kind} thread)'
    bad = [x for x in res['outs'] if x[0] == 'bad']
    if bad:
        raise BattleError(f'{where}: {bad[0][1]}')
    reads = res['reads']
    poss = [x for x in res['outs'] if x[0] == 'pos']
    static = sorted({x[1] for x in poss if not x[2] and x[1] > 0})
    counted = sorted({x[1] for x in poss if x[2] and x[5] is None and reads and x[1] == 1 + max(reads)})
    calls = sorted({(x[6], x[5]) for x in poss if x[2] and x[5] is not None})
    other = [x for x in poss if x[2] and x[5] is None and not (reads and x[1] == 1 + max(reads))]
    if other:
        raise BattleError(f'{where}: it goes on at {other[0][1]:+d}, computed from script bytes, which '
                          f'is neither past its operands nor a call')
    if any(x[2] for x in res['outs'] if x[0] == 'unknown'):
        raise BattleError(f'{where}: where it goes on depends on a callee the interpreter cannot follow '
                          f'({res["opaque"][0][1] if res["opaque"] else "?"})')
    # Two constant moves: the longer is the length; the shorter lands in
    # its own operands, which then run as the next opcode (opcode $26 in
    # an object thread: BattleAct_StartAnim advances 2 of its 3 bytes).
    if len(static) > 1 and not counted and not calls:
        o.inside = [ptr + d for d in static[:-1]]
        static = static[-1:]
    lengths = set(static) | set(counted) | {k for _, k in calls}
    if len(lengths) > 1:
        raise BattleError(f'{where}: it goes on at +{" and +".join(map(str, sorted(lengths)))}')
    # fixed: the length is where it goes on; else (it never goes on) the
    # bytes it reads
    o.fixed = bool(lengths)
    o.length = lengths.pop() if lengths else 1 + max(reads, default=0)
    o.next = bool(static or counted or calls)
    o.stay = any(x[1] == 0 and not x[2] for x in poss)
    if len(calls) > 1:
        raise BattleError(f'{where}: two call targets')
    o.call = calls[0][0] if calls else None
    # a pointer from RAM no script byte set: a return (when no second
    # frame showed it to be the resume of a wait)
    # (a pointer moved by a count from RAM that this opcode did not leave, as
    # the movers do in the target-set thread with the length of an earlier
    # one, is 'stale': no return either)
    unknown = [x for x in res['outs'] if x[0] == 'unknown']
    resumed = any(x[4] == 2 for x in poss)
    o.end = any(not (len(x) > 3 and x[3]) for x in unknown) and not resumed
    o.stale = any(len(x) > 3 and x[3] for x in unknown) and not resumed
    return o


# ── The action unit ────────────────────────────────────────────────────────

class Piece:
    """A manifest piece of a unit: label, role, SNES start, bytes."""
    __slots__ = ('label', 'role', 'start', 'data')

    def __init__(self, label: str, role: str, start: int, data: bytes):
        self.label, self.role, self.start, self.data = label, role, start, bytes(data)

    @property
    def stop(self) -> int:
        return self.start + len(self.data)


def _known(pieces: list[Piece]) -> dict[int, int]:
    known = {}
    for p in pieces:
        for i, b in enumerate(p.data):
            known[p.start + i] = b
    return known


def _banks(root: Path = ROOT) -> dict[str, int]:
    d = defines(root)
    return {t: d[b] for t, b in TABLE_BANKS.items()}


def _word(known: dict[int, int], a: int) -> int:
    return known[a] | known[a + 1] << 8


def disassemble_actions(interp: ActInterp, pieces: list[Piece], banks: dict[str, int]) -> dict:
    """{'entries' {table: [target or None]}, 'headers' {addr: (m1, m2,
    [thread addrs])}, 'ops' {addr: Op}, 'code_entries' set}."""
    known = _known(pieces)
    regions = [(p.start, p.stop) for p in pieces if p.role == 'scripts']

    def in_region(a):
        return any(s <= a < e for s, e in regions)
    entries, headers, code_entries, sub_entries = {}, {}, set(), set()
    owner: dict[int, int] = {}
    for p in pieces:
        if p.role not in ('table', 'subscripts'):
            continue
        if p.label not in banks:
            raise BattleError(f'{p.label}: no bank known for its offsets')
        bank = banks[p.label]
        if len(p.data) % 2:
            raise BattleError(f'{p.label}: an odd size')
        es = []
        for i in range(len(p.data) // 2):
            w = p.data[2 * i] | p.data[2 * i + 1] << 8
            t = bank << 16 | w
            es.append(t if w != 0xFFFF and in_region(t) else None)
            if es[-1] is not None:
                if p.role == 'subscripts':
                    sub_entries.add(t)
                else:
                    headers.setdefault(t, None)
        entries[p.label] = es
    # A table entry is a script when what it points at reads as a header
    # whose thread offsets all lie in the scripts; an entry that does not
    # (unused numbers: past every script region, or at thread code other
    # headers share) is kept as its word, and nothing is decoded from it.
    not_headers = set()
    for h in sorted(headers):
        threads = None
        if all(h + i in known for i in range(4)):
            m1, m2 = known[h] << 8 | known[h + 1], known[h + 2] << 8 | known[h + 3]
            n = bin(m1).count('1') + bin(m2).count('1')
            threads = []
            for k in range(n):
                a = h + 4 + 2 * k
                t = (h & 0xFF0000) | known[a] | known[a + 1] << 8 if a + 1 in known and in_region(a + 1) else None
                if t is None or not in_region(t):
                    threads = None
                    break
                threads.append(t)
        if threads is None:
            not_headers.add(h)
            continue
        headers[h] = (m1, m2, threads)
        code_entries.update(threads)
        for i in range(4 + 2 * len(threads)):
            owner[h + i] = h
    for h in not_headers:
        del headers[h]
    for lab, es in entries.items():
        if lab in banks and any(p.label == lab and p.role == 'table' for p in pieces):
            entries[lab] = [t if t in headers else None for t in es]
    # The threads run from their entries; a subscript runs in the kind of
    # thread that calls it (one no script calls, in every kind). An opcode
    # must come out the same in every kind of thread that reaches it.
    work = []
    for h, (m1, m2, threads) in headers.items():
        for t, a in zip(_thread_numbers(m1, m2), threads):
            if thread_kind(t) is not None:
                work.append((a, thread_kind(t)))
    ops: dict[int, Op] = {}
    kinds: dict[int, dict[str, Op]] = {}

    pending, continued = [], set()      # calls, and those whose callee returns
    into: set[int] = set()              # where a thread runs into a header

    def walk(work):
        while work:
            a, kind = work.pop()
            if kind in kinds.get(a, {}):
                continue
            if not in_region(a):
                raise BattleError(f'an opcode at ${a:06X}, outside the scripts')
            # A thread that runs on into another script's header (after its
            # last opcode, as one of the PC tech scripts does) is not
            # followed there: those bytes are the header.
            if a in owner:
                into.add(a)
                continue
            o = classify(interp, known, a, kind)
            if not all(in_region(a + i) for i in range(o.length)):
                raise BattleError(f'${a:06X} opcode ${o.op:02X}: {o.length} bytes run past the scripts')
            if any(a + i in owner for i in range(o.length)):
                into.add(a)
                continue
            seen = kinds.setdefault(a, {})
            for k2, o2 in seen.items():
                if o2.length != o.length and o.fixed and o2.fixed:
                    raise BattleError(f'${a:06X} opcode ${o.op:02X}: {o.length} bytes in a {kind} thread, '
                                      f'{o2.length} in a {k2} thread')
            seen[kind] = o
            if a in ops:
                m = ops[a]
                if o.fixed and not m.fixed:
                    m.length, m.fixed = o.length, True
                m.stay, m.end, m.stale = m.stay or o.stay, m.end or o.end, m.stale or o.stale
                if o.call is None:
                    m.next = m.next or o.next
                elif m.call is None:
                    m.call = o.call
            else:
                # (a copy: what the kinds add is merged into it, while each
                # kind's own outcome stays in kinds)
                ops[a] = m = Op()
                for k in Op.__slots__:
                    setattr(m, k, getattr(o, k))
                m.inside = list(o.inside)
                if o.call is not None:
                    m.next = False              # until its subscript is seen to return
            if o.call is not None:
                pending.append((a, kind, o))
                work.append((o.call, kind))
            elif o.next:
                work.append((a + o.length, kind))
            work += [(t, kind) for t in o.inside]

    def returns(t, kind) -> bool:
        """Does the subscript at t, in this kind of thread, reach a return?"""
        seen, todo = set(), [t]
        while todo:
            y = todo.pop()
            if y in seen or kind not in kinds.get(y, {}):
                continue
            seen.add(y)
            o = kinds[y][kind]
            if o.end:
                return True
            if o.call is not None:
                todo.append(o.call)
                if (y, kind) in continued:
                    todo.append(y + o.length)
            elif o.next:
                todo.append(y + o.length)
            todo += o.inside
        return False

    # After a call the thread goes on only when the subscript returns (one
    # that ends its thread or the action never comes back).
    first = True
    while work or first:
        walk(work)
        if first:
            called = {o.call for _, _, o in pending}
            work = [(t, k) for t in sorted(sub_entries - called) for k in KINDS]
            first = False
            walk(work)
        work = []
        for a, kind, o in pending:
            if (a, kind) not in continued and returns(o.call, kind):
                continued.add((a, kind))
                ops[a].next = True
                work.append((a + o.length, kind))
    called = {o.call for _, _, o in pending}
    code_entries |= called | sub_entries
    return {'entries': entries, 'headers': headers, 'ops': ops, 'code_entries': code_entries,
            'into_headers': into, 'kinds': kinds}


def _thread_numbers(m1: int, m2: int) -> list[int]:
    """The thread of each offset after a header: the set bits of the first
    mask, bit 15 = thread 0, then the second's."""
    return [t for m in (m1, m2) for t in range(16) if m & 0x8000 >> t]


def _layout(ops: dict[int, Op]) -> tuple[list[int], dict[int, int]]:
    primary, inner, end = [], {}, -1
    for y in sorted(ops):
        if y >= end:
            primary.append(y)
            end = y + ops[y].length
        else:
            inner[y] = primary[-1]
    return primary, inner


def _lab(a: int, header: bool = False) -> str:
    return f'{"S" if header else "L"}_{a:06X}'


HEAD = ('; {title}: battle scripts, disassembled from your own ROM by tools/battle.py (never',
        '; commit it). The build assembles it back into the bytes; the format is in tools/battle.py.',
        '; This file is regenerated by extraction: an edit is lost when it runs again (any change',
        '; to the extracted assets makes it run).')


def render_actions(d: dict, pieces: list[Piece], names: list[str], banks: dict[str, int]) -> str:
    ops, headers = d['ops'], d['headers']
    primary, inner = _layout(ops)
    for y, host in inner.items():
        if not any(p.start <= host < p.stop and p.start <= y < p.stop for p in pieces):
            raise BattleError(f'${y:06X}: an inner opcode across a piece\'s end')
    for y in primary:
        if not any(p.start <= y and y + ops[y].length <= p.stop for p in pieces if p.role == 'scripts'):
            raise BattleError(f'${y:06X}: an opcode across a piece\'s end')
    labels = {t: _lab(t) for t in d['code_entries']}
    labels.update({h: _lab(h, True) for h in headers})
    known = _known(pieces)
    out = [line.format(title='actions') for line in HEAD]
    for p in pieces:
        if p.role in ('table', 'subscripts'):
            out.append(f'@table {p.label} ${banks[p.label]:02X}')
            for i, t in enumerate(d['entries'][p.label]):
                w = p.data[2 * i] | p.data[2 * i + 1] << 8
                out.append(f'@entry {i} ' + (labels[t] if t is not None else 'none' if w == 0xFFFF else f'${w:04X}'))
    inners: dict[int, list[int]] = {}
    for y, host in inner.items():
        inners.setdefault(host, []).append(y)
    covered = set()
    for y in primary:
        covered.update(range(y, y + ops[y].length))
    for h, (_, _, ts) in headers.items():
        covered.update(range(h, h + 4 + 2 * len(ts)))
    prim = set(primary)

    def operands(o: Op) -> list[str]:
        return [f'${known[o.off + i]:02X}' for i in range(1, o.length)]
    for p in pieces:
        if p.role != 'scripts':
            continue
        out.append(f'@region {p.label} ${p.start:06X}')
        y = p.start
        while y < p.stop:
            if y in labels:
                out.append(labels[y] + ':')
            if y in headers:
                m1, m2, ts = headers[y]
                out.append(f'    @threads ${m1:04X} ${m2:04X} ' + ' '.join(labels[t] for t in ts).rstrip())
                y += 4 + 2 * len(ts)
                continue
            if y in prim:
                o = ops[y]
                out.append('    ' + (f'Halt ${o.op:02X}' if o.halt else ' '.join([names[o.op]] + operands(o))))
                for z in sorted(inners.get(y, ())):
                    oz = ops[z]
                    body = f'Halt ${oz.op:02X}' if oz.halt else ' '.join([names[oz.op]] + operands(oz))
                    out.append(f'    @inner +{z - y} {labels.get(z, _lab(z))} {body}')
                y += o.length
                continue
            z = y + 1
            while z < p.stop and z not in covered and z not in labels:
                z += 1
            chunk = bytes(known[a] for a in range(y, z))
            for k in range(0, len(chunk), 16):
                out.append('@bytes ' + ' '.join(f'{b:02X}' for b in chunk[k:k + 16]))
            y = z
    return '\n'.join(out) + '\n'


def _lines(text: str) -> list[tuple[int, list[str]]]:
    out = []
    for no, line in enumerate(text.split('\n'), 1):
        code = line.split(';', 1)[0].strip()
        if code:
            out.append((no, code.split()))
    return out


def _byte(t: str, where: str) -> int:
    if not re.fullmatch(r'\$[0-9A-Fa-f]{1,2}', t):
        raise BattleError(f'{where}: {t!r} is not a $XX byte')
    return int(t[1:], 16)


def assemble_actions(text: str, pieces: dict[str, tuple[str, int, int]], names: list[str],
                     banks: dict[str, int], interp: ActInterp | None = None, name: str = 'actions.bscr',
                     count: int | None = None) -> dict[str, bytes]:
    """{piece label: bytes} of the readable file. `pieces`: {label: (role,
    start, size)} of the unit. Every table entry must name a script header,
    every thread and subscript entry an opcode line; with `interp` each
    opcode line's length is checked against its handler and a data run may
    follow only an opcode that does not go on."""
    opcodes = {n: i for i, n in enumerate(names)}
    count = len(names) if count is None else count
    regions = {k: v for k, v in pieces.items() if v[0] == 'scripts'}
    tables = {k: v for k, v in pieces.items() if v[0] in ('table', 'subscripts')}
    lines = _lines(text)
    # pass 1: where everything is
    labels, kinds = {}, {}
    cur, pos, last = None, None, None
    table_lines: dict[str, list] = {}
    body = []
    for no, w in lines:
        where = f'{name}:{no}'
        if w[0] == '@table':
            if len(w) != 3 or w[1] not in tables:
                raise BattleError(f'{where}: @table LABEL $BB, a table of this unit')
            if w[1] in table_lines:
                raise BattleError(f'{where}: {w[1]} twice')
            cur, pos = ('table', w[1]), None
            table_lines[w[1]] = []
            if _byte(w[2], where) != banks[w[1]]:
                raise BattleError(f'{where}: {w[1]}\'s offsets are in bank ${banks[w[1]]:02X}')
            continue
        if w[0] == '@entry':
            if cur is None or cur[0] != 'table' or len(w) != 3:
                raise BattleError(f'{where}: @entry I TARGET inside a @table')
            if int(w[1]) != len(table_lines[cur[1]]):
                raise BattleError(f'{where}: entry {w[1]} out of order')
            table_lines[cur[1]].append((where, w[2]))
            continue
        if w[0] == '@region':
            if len(w) != 3 or w[1] not in regions:
                raise BattleError(f'{where}: @region LABEL $AAAAAA, a scripts piece of this unit')
            start = regions[w[1]][1]
            if not re.fullmatch(r'\$[0-9A-Fa-f]{6}', w[2]) or int(w[2][1:], 16) != start:
                raise BattleError(f'{where}: {w[1]} starts at ${start:06X}')
            if any(b[1] == w[1] for b in body if b[0] == 'region'):
                raise BattleError(f'{where}: {w[1]} twice')
            cur, pos = ('region', w[1]), start
            body.append(('region', w[1], where))
            continue
        if cur is None or cur[0] != 'region':
            raise BattleError(f'{where}: {w[0]} outside a @region')
        if len(w) == 1 and w[0].endswith(':'):
            lab = w[0][:-1]
            if lab in labels:
                raise BattleError(f'{where}: label {lab} twice')
            labels[lab] = pos
            continue
        if w[0] == '@inner':
            if last is None or len(w) < 4 or not w[1].startswith('+'):
                raise BattleError(f'{where}: @inner +K LABEL OPCODE ... after an opcode')
            if w[2] in labels:
                raise BattleError(f'{where}: label {w[2]} twice')
            labels[w[2]] = last + int(w[1][1:])
            body.append(('inner', w, where, last + int(w[1][1:])))
            continue
        if w[0] == '@threads':
            size = 4 + 2 * (len(w) - 3)
            body.append(('threads', w, where, pos))
        elif w[0] == '@bytes':
            size = len(w) - 1
            body.append(('bytes', w, where, pos))
        else:
            size = len(w)
            body.append(('op', w, where, pos))
            last = pos
        kinds[pos] = body[-1][0]
        pos += size
    # pass 2: the bytes
    image: dict[int, int] = {}
    starts, op_lines, after_op = set(), [], []

    def target(t: str, where: str) -> int:
        if t not in labels:
            raise BattleError(f'{where}: no label {t}')
        return labels[t]

    def encode_op(w: list[str], where: str) -> bytes:
        if w[0] == 'Halt':
            if len(w) != 2 or _byte(w[1], where) < count:
                raise BattleError(f'{where}: Halt $XX takes a byte of ${count:02X} or more (not an opcode)')
            return bytes([_byte(w[1], where)])
        if w[0] not in opcodes:
            raise BattleError(f'{where}: unknown opcode {w[0]}')
        return bytes([opcodes[w[0]]] + [_byte(t, where) for t in w[1:]])
    threads_at = []
    prev_op = None
    for item in body:
        kind = item[0]
        if kind == 'region':
            prev_op = None
            continue
        _, w, where, at = item
        if kind == 'threads':
            if len(w) < 3:
                raise BattleError(f'{where}: @threads $M1 $M2 LABEL ...')
            m = []
            for t in w[1:3]:
                if not re.fullmatch(r'\$[0-9A-Fa-f]{4}', t):
                    raise BattleError(f'{where}: {t!r} is not a $XXXX mask')
                m.append(int(t[1:], 16))
            if bin(m[0]).count('1') + bin(m[1]).count('1') != len(w) - 3:
                raise BattleError(f'{where}: the masks set {bin(m[0]).count("1") + bin(m[1]).count("1")} '
                                  f'threads; the line names {len(w) - 3}')
            b = bytearray([m[0] >> 8, m[0] & 0xFF, m[1] >> 8, m[1] & 0xFF])
            for num, t in zip(_thread_numbers(m[0], m[1]), w[3:]):
                a = target(t, where)
                if a >> 16 != at >> 16:
                    raise BattleError(f'{where}: thread {t} is in another bank')
                b += (a & 0xFFFF).to_bytes(2, 'little')
                if thread_kind(num) is not None:         # threads 5-7 never run
                    threads_at.append((where, t, a))
            prev_op = None
        elif kind == 'bytes':
            b = bytes(int(t, 16) for t in w[1:]) if all(re.fullmatch(r'[0-9A-Fa-f]{2}', t) for t in w[1:]) \
                else None
            if b is None:
                raise BattleError(f'{where}: @bytes takes XX bytes')
            if prev_op is not None:
                after_op.append((where, prev_op))
            prev_op = None
        elif kind == 'op':
            b = encode_op(w, where)
            starts.add(at)
            op_lines.append((where, w[0], at, len(b)))
            prev_op = at
        else:                                       # inner
            b = encode_op(w[3:], where)
            starts.add(at)
            op_lines.append((where, w[3], at, len(b)))
            for i, v in enumerate(b):
                if image.get(at + i, v) != v:
                    raise BattleError(f'{where}: the @inner opcode is not the bytes it shares')
            continue
        for i, v in enumerate(b):
            if at + i in image:
                raise BattleError(f'{where}: overlaps the line before')
            image[at + i] = v
    # the inner lines are checked once every byte is placed
    for item in body:
        if item[0] == 'inner':
            _, w, where, at = item
            b = encode_op(w[3:], where)
            if any(image.get(at + i) != v for i, v in enumerate(b)):
                raise BattleError(f'{where}: the @inner opcode is not the bytes it shares')
    out = {}
    for lab, (role, start, size) in regions.items():
        if not any(b[0] == 'region' and b[1] == lab for b in body):
            raise BattleError(f'{name}: no @region {lab}')
        got = [image.get(start + i) for i in range(size)]
        if None in got or start + size in image and not any(
                s2 == start + size for _, s2, _ in regions.values()):
            raise BattleError(f'{name}: {lab} is not {size} bytes')
        out[lab] = bytes(got)
    for lab, (role, start, size) in tables.items():
        es = table_lines.get(lab)
        if es is None or len(es) != size // 2:
            raise BattleError(f'{name}: {lab} needs {size // 2} @entry lines')
        b = bytearray()
        for where, t in es:
            if t == 'none':
                v = 0xFFFF
            elif re.fullmatch(r'\$[0-9A-Fa-f]{4}', t):
                v = int(t[1:], 16)
                a = banks[lab] << 16 | v
                if kinds.get(a) == 'threads' or (role == 'subscripts' and a in starts):
                    raise BattleError(f'{where}: ${v:04X} is a script line: name its label')
            else:
                a = target(t, where)
                if a >> 16 != banks[lab]:
                    raise BattleError(f'{where}: {t} is not in bank ${banks[lab]:02X}')
                want = 'op' if role == 'subscripts' else 'threads'
                if kinds.get(a) != want and not (want == 'op' and a in starts):
                    raise BattleError(f'{where}: {t} is not {"an opcode" if want == "op" else "a script header"} line')
                v = a & 0xFFFF
            b += v.to_bytes(2, 'little')
        out[lab] = bytes(b)
    for where, t, a in threads_at:
        if a not in starts:
            raise BattleError(f'{where}: thread {t} is not an opcode line')
    if interp is not None:
        # the lines must be what the disassembler derives from these bytes:
        # every opcode a thread or subscript reaches is a line of the length
        # its handler takes there, and nothing else is an opcode line
        ps = [Piece(lab, pieces[lab][0], pieces[lab][1], out[lab]) for lab in pieces]
        d = disassemble_actions(interp, ps, banks)
        lines_at = {at: (where, opname, n) for where, opname, at, n in op_lines}
        for at, (where, opname, n) in sorted(lines_at.items()):
            o = d['ops'].get(at)
            if o is None:
                raise BattleError(f'{where}: no thread reaches this {opname} line (bytes no opcode reaches '
                                  f'are @bytes)')
            if o.length != n:
                raise BattleError(f'{where}: {opname} takes {o.length} bytes here (its handler, as the '
                                  f'disassembler derives it); the line gives {n}')
        for at, o in sorted(d['ops'].items()):
            if at not in lines_at:
                where = max(((a, w) for w, a in after_op if a < at), default=(0, name))[1]
                raise BattleError(f'{where}: the opcode at ${at:06X} ({names[o.op] if not o.halt else "Halt"}) '
                                  f'is reached: those bytes are not data')
        for where, at in after_op:
            # (the check above already refuses this case: the opcode after
            # one that goes on is reached and is no line)
            if at not in d['ops'] or not d['ops'][at].next:
                continue
            raise BattleError(f'{where}: @bytes after {names[d["ops"][at].op]}, which goes on to the next '
                              f'opcode: those bytes are reached')
        heads = {at for at, k in kinds.items() if k == 'threads'}
        if heads != set(d['headers']):
            extra = sorted(heads ^ set(d['headers']))[0]
            raise BattleError(f'{name}: ${extra:06X}: a @threads line must be the header a table entry names')
    return out


# ── The behaviour scripts (records) ───────────────────────────────────────

class AiFormat:
    """What the readers take from the source: the action record lengths,
    the code counts, the delimiters, the fixed scripts."""

    def __init__(self, root: Path = ROOT, image: bytes | None = None, labels: dict | None = None):
        root = Path(root)
        d = defines(root)
        self.block_end, self.part_end = d['BattleAi_BlockEnd'], d['BattleAi_ScriptEnd']
        self.restart = d['BattleAi_ActRestart']             # code 4: BattleAi_ChooseByChance
        self.fixed = [0xCC0000 | d['BattleAi_ScriptUnk8D08'], 0xCC0000 | d['BattleAi_ScriptUnk8D1E']]
        self.tests, self.acts = ai_names(root)
        if image is None:
            image, _, labels = events.code_image(root, root / CACHE_DIR)
        a = labels['BattleFD_AiActLength']
        off = (a >> 16) - 0xC0 << 16 | a & 0xFFFF
        self.lengths = list(image[off:off + len(self.acts)])
        self.lengths[self.restart] = 1           # ChooseByChance: INX past its code, then the actions

    def length(self, code: int) -> int | None:
        if code >= len(self.acts):
            return None
        n = self.lengths[code]
        return n if 0 < n < 0x80 else None


def ai_script(fmt: AiFormat, get, start: int) -> list[tuple[str, int, int]]:
    """The items the readers see from a script's start: [(kind, address,
    size)] with kind test/do/act/data/done/end; raises BattleError when two
    readers would split it differently or a record cannot be read."""
    FE, FF = fmt.block_end, fmt.part_end

    def part(a, limit=None):
        items = []
        while True:
            if limit is not None and a > limit:
                raise over
            if get(a) == FF:
                items.append(('end', a, 1))
                return a + 1, items
            tests = [a] + ([a + 4] if get(a + 4) != FE else [])
            for t in tests:
                if get(t) >= len(fmt.tests):
                    raise BattleError(f'${t:06X}: test code ${get(t):02X} has no handler')
                items.append(('test', t, 4))
            # BattleAi_TestPassed scans for the $FE from the passing test + 1,
            # the first test's too: it must be the one after the last test
            x = tests[0] + 1
            while get(x) != FE:
                x += 1
            if limit is not None and x > limit:
                raise over
            if x != tests[-1] + 4:
                raise BattleError(f'${a:06X}: the tests end at ${x:06X}, not after the records')
            items.append(('do', x, 1))
            y = x + 1
            e = y
            while get(e) != FE:
                e += 1
            if limit is not None and e > limit:
                raise over
            while y < e:
                c = get(y)
                if c >= 0x80:
                    items.append(('data', y, e - y))
                    break
                n = fmt.length(c)
                if n is None:
                    raise BattleError(f'${y:06X}: action code ${c:02X} has no record length')
                if y + n > e:
                    raise BattleError(f'${y:06X}: the action record runs past the $FE at ${e:06X}')
                items.append(('act', y, n))
                y += n
            items.append(('done', e, 1))
            a = e + 1
    split = start
    while get(split) != FF:
        split += 1
    over = BattleError(f'${start:06X}: the main part\'s blocks run past the first $FF (${split:06X}), '
                       f'after which BattleAi_FindReactPart starts the reaction part')
    e1, main = part(start, split)
    if e1 - 1 != split:
        raise over
    _, react = part(e1)
    return main + react


def _getter(data: bytes, base: int):
    def get(a):
        k = a - base
        if not 0 <= k < len(data):
            raise BattleError(f'${a:06X}: the script runs past the piece')
        return data[k]
    return get


def render_ai(fmt: AiFormat, piece: Piece) -> str:
    data, base = piece.data, piece.start
    get = _getter(data, base)
    n = (fmt.fixed[0] - base) // 2
    if fmt.fixed[0] - base != 2 * n or n != 256:
        raise BattleError(f'{piece.label}: the table is not 256 entries up to the first fixed script')
    entries = [0xCC0000 | data[2 * i] | data[2 * i + 1] << 8 for i in range(n)]
    starts = sorted(set(entries) | set(fmt.fixed))
    items: dict[int, tuple[str, int]] = {}
    kept = []
    for s in starts:
        if not base + 2 * n <= s < piece.stop:
            raise BattleError(f'${s:06X}: a script outside the piece')
        try:
            got = ai_script(fmt, get, s)
        except BattleError as e:
            kept.append((s, str(e)))
            continue
        for k, a, size in got:
            if items.setdefault(a, (k, size)) != (k, size):
                raise BattleError(f'${a:06X}: two scripts read it differently')
    out = [line.format(title='enemy') for line in HEAD]
    out.append(f'@enemies {piece.label} ${base:06X}')
    for i, t in enumerate(entries):
        out.append(f'@enemy {i} A_{t & 0xFFFF:04X}')
    for s, why in kept:
        out.append(f'; A_{s & 0xFFFF:04X} is kept as bytes: {why}')
    labs = set(starts)
    a = base + 2 * n
    while a < piece.stop:
        if a in labs:
            out.append(f'A_{a & 0xFFFF:04X}:')
        it = items.get(a)
        if it is not None and it[0] != 'data':
            k, size = it
            b = data[a - base:a - base + size]
            if k == 'test':
                out.append(f'    test {fmt.tests[b[0]]} ' + ' '.join(f'${v:02X}' for v in b[1:]))
            elif k == 'act':
                out.append('    ' + ' '.join([f'act {fmt.acts[b[0]]}'] + [f'${v:02X}' for v in b[1:]]))
            else:
                out.append(f'    {k}')
            a += size
            continue
        z = a + 1
        while z < piece.stop and z not in labs and (z not in items or items[z][0] == 'data'):
            z += 1
        chunk = data[a - base:z - base]
        for k in range(0, len(chunk), 16):
            out.append('@bytes ' + ' '.join(f'{v:02X}' for v in chunk[k:k + 16]))
        a = z
    return '\n'.join(out) + '\n'


def assemble_ai(text: str, fmt: AiFormat, label: str, start: int, size: int, name: str = 'enemy.bscr') -> bytes:
    """The bytes of the behaviour-script piece, checked: every script label
    the table and the fixed scripts name is read by the readers (ai_script)
    exactly as the lines give it, or is kept as bytes; every record line is
    one a reader reads so."""
    tests = {n: i for i, n in enumerate(fmt.tests)}
    acts = {n: i for i, n in enumerate(fmt.acts)}
    lines = _lines(text)
    if not lines or lines[0][1][:2] != ['@enemies', label] or len(lines[0][1]) != 3 \
            or lines[0][1][2] != f'${start:06X}':
        raise BattleError(f'{name}: the first line is @enemies {label} ${start:06X}')
    entries, labels, kinds = [], {}, {}
    out = bytearray()
    body = lines[1:]
    k = 0
    while k < len(body) and body[k][1][0] == '@enemy':
        no, w = body[k]
        if len(w) != 3 or int(w[1]) != len(entries):
            raise BattleError(f'{name}:{no}: @enemy I LABEL, in order')
        entries.append((no, w[2]))
        k += 1
    out += bytes(2 * len(entries))
    for no, w in body[k:]:
        where = f'{name}:{no}'
        at = start + len(out)
        if len(w) == 1 and w[0].endswith(':'):
            if w[0][:-1] in labels:
                raise BattleError(f'{where}: label {w[0][:-1]} twice')
            labels[w[0][:-1]] = at
            continue
        if w[0] == 'test':
            if len(w) != 5 or w[1] not in tests:
                raise BattleError(f'{where}: test NAME $b1 $b2 $b3, a BattleAi_TestTable name')
            b = bytes([tests[w[1]]] + [_byte(t, where) for t in w[2:]])
        elif w[0] == 'act':
            if len(w) < 2 or w[1] not in acts:
                raise BattleError(f'{where}: act NAME $.., a BattleAi_RunTable name')
            b = bytes([acts[w[1]]] + [_byte(t, where) for t in w[2:]])
            n = fmt.length(acts[w[1]])
            if n != len(b):
                raise BattleError(f'{where}: {w[1]} records are {n} bytes (BattleFD_AiActLength); the line '
                                  f'gives {len(b)}')
        elif w[0] in ('do', 'done', 'end') and len(w) == 1:
            b = bytes([fmt.part_end if w[0] == 'end' else fmt.block_end])
        elif w[0] == '@bytes':
            if not all(re.fullmatch(r'[0-9A-Fa-f]{2}', t) for t in w[1:]):
                raise BattleError(f'{where}: @bytes takes XX bytes')
            b = bytes(int(t, 16) for t in w[1:])
        else:
            raise BattleError(f'{where}: unknown line {w[0]}')
        kinds[at] = (w[0], len(b), where)
        out += b
    if len(out) != size:
        raise BattleError(f'{name}: {len(out)} bytes; {label} is {size}')
    for i, (no, t) in enumerate(entries):
        if t not in labels:
            raise BattleError(f'{name}:{no}: no label {t}')
        out[2 * i:2 * i + 2] = (labels[t] & 0xFFFF).to_bytes(2, 'little')
    if len(entries) != 256:
        raise BattleError(f'{name}: {len(entries)} @enemy lines; the table has 256')
    data = bytes(out)
    get = _getter(data, start)
    read: dict[int, tuple[str, int]] = {}
    for s in sorted({labels[t] for _, t in entries} | set(fmt.fixed)):
        try:
            got = ai_script(fmt, get, s)
        except BattleError:
            if kinds.get(s, ('@bytes',))[0] != '@bytes':
                raise BattleError(f'{name}: the script at A_{s & 0xFFFF:04X} cannot be read as its lines say '
                                  f'(keep it as @bytes)') from None
            continue
        for kind, a, n in got:
            if kind == 'data':
                continue
            line = kinds.get(a)
            if line is None or line[0] == '@bytes' or line[0] != kind or line[1] != n:
                where = line[2] if line else name
                raise BattleError(f'{where}: the readers read a {kind} record of {n} bytes at ${a:06X} here')
            read[a] = (kind, n)
    for at, (kind, n, where) in kinds.items():
        if kind != '@bytes' and at not in read:
            raise BattleError(f'{where}: no script reaches this {kind} line')
    return data


def ai_record_reads(fmt: AiFormat, image: bytes, mask: bytearray, labels: dict, piece: Piece,
                    root: Path = ROOT) -> tuple[dict, list[str]]:
    """The absint cross-check of the action record lengths: for one record
    of each code the scripts use, BattleAi_RunTable's and
    BattleAi_ChooseTable's handlers are run on it (!Battle_UnkB1D2 = its
    address, the scripts known, all else unknown). ({code: (length, the
    record bytes they read)}, problems: a read past the record)."""
    d = defines(root)
    b1d2 = 0x7E0000 | d['Battle_UnkB1D2']
    known = {piece.start + i: v for i, v in enumerate(piece.data)}
    get = _getter(piece.data, piece.start)
    n = (fmt.fixed[0] - piece.start) // 2
    starts = sorted({0xCC0000 | piece.data[2 * i] | piece.data[2 * i + 1] << 8 for i in range(n)} | set(fmt.fixed))
    sample = {}
    for st in starts:
        try:
            items = ai_script(fmt, get, st)
        except BattleError:
            continue
        for kind, a, _ in items:
            if kind == 'act':
                sample.setdefault(get(a), a)
    m = absint.Machine(image, mask, max_steps=300000, callee_steps=20000)
    out, problems = {}, []
    for table in ('BattleAi_RunTable', 'BattleAi_ChooseTable'):
        t = labels[table]
        off = (t >> 16) - 0xC0 << 16 | t & 0xFFFF
        for code, a in sorted(sample.items()):
            s = absint.State()
            s.pc = (t & 0xFF0000) | image[off + 2 * code] | image[off + 2 * code + 1] << 8
            s.a, s.b, s.x, s.y, s.d, s.db = code * 2, 0, code * 2, None, 0, 0x7E
            s.m, s.xf = True, False
            s.c = s.z = s.n = s.v = None
            s.sp, s.spt, s.memt = [], [], {}
            s.mem = {b1d2: a & 0xFF, b1d2 + 1: a >> 8 & 0xFF}
            s.at = s.xt = s.yt = s.ft = absint.E
            s.depth = 0
            try:
                m.run(s, known)
            except absint.Unresolved:
                continue                # (not followed: no evidence either way)
            reads = sorted(x - a for x in m.reads)
            n_ = fmt.length(code)
            out.setdefault(code, (n_, set()))[1].update(reads)
            bad = [k for k in reads if not 0 < k < n_]
            if bad:
                problems.append(f'{table} handler of action ${code:02X} reads byte {bad[0]} of a '
                                f'{n_}-byte record')
    return out, problems


# ── Units, extraction, checks ──────────────────────────────────────────────

def unit_pieces(pieces: list[dict], unit: str) -> list[dict]:
    return [p for p in pieces if p['piece'] == 'battle' and p['param'].split('/')[0] == unit]


def _pieces_of(rom: bytes, manifest: list[dict], unit: str) -> list[Piece]:
    return [Piece(p['label'], p['param'].split('/')[1], 0xC00000 + p['offset'], rom[p['offset']:p['stop']])
            for p in unit_pieces(manifest, unit)]


def extract_unit(unit: str, rom: bytes, manifest: list[dict], interp: ActInterp | None, fmt: AiFormat | None,
                 root: Path = ROOT) -> str:
    """The readable file of a unit, checked to assemble back to the ROM's
    bytes; raises BattleError when it cannot be."""
    ps = _pieces_of(rom, manifest, unit)
    if unit == 'actions':
        banks = _banks(root)
        d = disassemble_actions(interp, ps, banks)
        text = render_actions(d, ps, interp.names, banks)
        back = assemble_actions(text, {p.label: (p.role, p.start, len(p.data)) for p in ps}, interp.names,
                                banks, interp)
    else:
        if len(ps) != 1:
            raise BattleError('the enemy unit is one piece')
        text = render_ai(fmt, ps[0])
        back = {ps[0].label: assemble_ai(text, fmt, ps[0].label, ps[0].start, len(ps[0].data))}
    for p in ps:
        if back.get(p.label) != p.data:
            raise BattleError(f'{p.label}: the {unit} disassembly does not assemble back to its bytes')
    return text


def assemble_unit(unit: str, text: str, manifest: list[dict], interp: ActInterp | None, fmt: AiFormat | None,
                  root: Path = ROOT) -> dict[str, bytes]:
    ps = unit_pieces(manifest, unit)
    if unit == 'actions':
        return assemble_actions(text, {p['label']: (p['param'].split('/')[1], 0xC00000 + p['offset'],
                                                    p['stop'] - p['offset']) for p in ps},
                                interp.names, _banks(root), interp, f'{unit}.bscr')
    p = ps[0]
    return {p['label']: assemble_ai(text, fmt, p['label'], 0xC00000 + p['offset'], p['stop'] - p['offset'],
                                    f'{unit}.bscr')}


def stats(unit: str, text: str) -> dict:
    """{'data': bytes in @bytes lines, 'kept': of those, bytes of scripts
    kept as bytes (enemy unit), 'threads'/'scripts' counts}."""
    data = sum(len(w) - 1 for _, w in _lines(text) if w[0] == '@bytes')
    kept = 0
    if unit == 'enemy':
        kept_labels = set(re.findall(r'^; (A_[0-9A-F]{4}) is kept as bytes', text, re.M))
        cur = None
        for _, w in _lines(text):
            if len(w) == 1 and w[0].endswith(':'):
                cur = w[0][:-1]
            elif w[0] == '@bytes' and cur in kept_labels:
                kept += len(w) - 1
            elif w[0] != '@bytes':
                cur = None
    ops = sum(1 for _, w in _lines(text) if re.match(r'^Op[0-9A-F]{2}_', w[0]) or w[0] in ('Halt', 'test', 'act')
              or (w[0] == '@inner'))
    return {'data': data, 'kept': kept, 'lines': ops}


# What the real scripts are known to hold (DATA_PLAN.md): the opcodes whose
# pointer comes from RAM (returns) and those that advance by a length an
# earlier opcode left (stale). A change in either set is a change in how
# the interpreter reads the handlers, and check() reports it.
RETURNS = {0x1F, 0x21}
STALES = {0x18, 0x98, 0x99}


def exits_check(rom: bytes, manifest: list[dict], interp: ActInterp, root: Path = ROOT) -> list[str]:
    ps = _pieces_of(rom, manifest, 'actions')
    if not ps:
        return []
    d = disassemble_actions(interp, ps, _banks(root))
    ends = {o.op for per in d['kinds'].values() for o in per.values() if o.end}
    stales = {o.op for per in d['kinds'].values() for o in per.values() if o.stale}
    out = []
    if ends != RETURNS:
        out.append(f'actions: the opcodes classed end (returns) are {sorted(map(hex, ends))}, '
                   f'not {sorted(map(hex, RETURNS))}')
    if stales != STALES:
        out.append(f'actions: the opcodes classed stale are {sorted(map(hex, stales))}, '
                   f'not {sorted(map(hex, STALES))}')
    return out


def check(rom: bytes, root: Path = ROOT, quiet: bool = True) -> list[str]:
    import extract_data
    manifest = extract_data.read_manifest()
    interp = ActInterp(root)
    interp.load(root)
    fmt = AiFormat(root, interp.image, interp.labels)
    problems = []
    beh = _pieces_of(rom, manifest, 'enemy')
    if beh:
        reads, bad = ai_record_reads(fmt, interp.image, interp.mask, interp.labels, beh[0], root)
        problems += [f'enemy: {b}' for b in bad]
        if not quiet:
            print(f'battle: enemy: {len(reads)} action codes\' handlers read inside their records '
                  f'(BattleFD_AiActLength)')
    problems += exits_check(rom, manifest, interp, root)
    for unit in UNITS:
        try:
            text = extract_unit(unit, rom, manifest, interp, fmt, root)
            assemble_unit(unit, text, manifest, interp, fmt, root)
        except BattleError as e:
            problems.append(f'{unit}: {e}')
            continue
        if not quiet:
            st = stats(unit, text)
            print(f'battle: {unit}: {st["lines"]:,} opcode or record lines, {st["data"]:,} B of data'
                  + (f' ({st["kept"]:,} B of scripts kept as bytes)' if st['kept'] else ''))
    interp.save(root)
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    import extract_data
    try:
        problems = check(extract_data.read_rom(), quiet=False)
    except (BattleError, extract_data.DataError) as e:
        print(f'battle: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'battle: {p}', file=sys.stderr)
    if problems:
        return 1
    print('OK: every battle script disassembles and assembles back byte-exact, checked against its readers')
    return 0


if __name__ == '__main__':
    sys.exit(main())
