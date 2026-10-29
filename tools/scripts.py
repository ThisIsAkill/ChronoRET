#!/usr/bin/env python3
"""
scripts.py — Two more script languages as readable text, extracted from
your own ROM into the ignored build/assets/, and an assembler that rebuilds
their exact bytes (DATA_PLAN.md, step 7):

  scene  the scene scripts (C2SceneRom_ScriptPacks: 8 packs unpacked to
         C2Scene_ScriptBuf, $7F:0400), run by C2Scene_TaskRunScript through
         C2Script_OpTable ($00-$52). One file per pack, build/assets/scene/
         <label>.scn; the build assembles it to the unpacked bytes and packs
         them as before.
  fx     the battle layer-effect channel scripts (BattleRom_FxScriptPtrs at
         $D1:646C and the scripts after it), run by BattleCD_RunFxScript: a
         byte below $80 is a tile page (a step ends on it), $7F a step with
         no page, $FF the end, $80-$F9 an opcode through BattleCD_FxOpTable
         (BattleCD_RunFxOp). One file, build/assets/fx/fx.bfx.

No script is ever committed (README, "Legal"); this tool holds only how the
interpreters read them, and takes even that from the matched source:

  * Every opcode's operand bytes and where the script goes on are what its
    handler does with the bytes it is given: tools/absint.py runs the
    handler's assembled code (an assembly of asm/main.asm, not the ROM) as
    the interpreter calls it, with the script bytes known and other RAM
    unknown, both ways of every branch on an unknown value. The operands are
    the bytes it reads; every way it returns leaves the script position:
      next    moved on by a constant (the length), or by a count read from
              its own bytes, as far as it reads;
      stay    the same opcode again (a wait, or the end of the script);
      jump    a position computed from operand bytes: their encoding (a word
              in the script's bank, or a signed byte from the opcode) is
              found by changing the bytes and watching the target move;
      call    the same, with the place after the operands kept in RAM;
      return  the position from the return slot (C2Scene_Task.ScriptReturn,
              !Battle_FxReturnPtr), which the trace fills with a mark;
      done    the task or channel ends (scene opcode $52, fx $FF);
      ram     a position from other RAM no script byte sets (fx opcodes
              $84/$86 going back to their loop's start, the switches $D0/
              $D1 picking from a list by a variable): not followed, and
              not a return.
    The scene's opcodes $09/$43 hand an operand address to
    C2Scene_TaskSpawnScript(Low): those are script entry points too.
    A routine the interpreter cannot follow is refused, unless it is one
    of TRUST, each with its reason (see there; check() asserts the list).
  * A scene pack's entries are its start and the script addresses of the
    scene's lists (C2Scene_ListD: C2Scene_GetListBScript) that lie in the
    pack; the scene is the one whose header (C2SceneRom_HeaderTable)
    names the pack. The build takes them from its own inputs and the
    @entry lines must name exactly them. An fx script's entry is its
    table entry + 1: what BattleCD_StartFxChannel stores (the first byte
    is the period); a table word inside the scripts names a @head label.
  * After a call the script goes on only when the called part can return.
    Bytes no opcode reaches are data.

The readable forms:

  scene                                fx
    @scene LABEL $7F0400                 @table LABEL $D1646C
    @entry L_0E96                        @entry I F_D17466 (or $XXXX)
    @jump NAME word J C | byte J S C     @jump NAME word J C | byte J S C
    LABEL:                               F_D17466:
        Op1C_IfTaskByteZero $05 ->L_0430     @head $03
        Op09_SpawnScript ->L_0500 $7F    L_D17467:
    @bytes ...                               Page $12 / NoPage / End
                                             Op91_Call ->L_D17500
                                         @bytes ...

The assembler re-derives the structure from the bytes it makes and refuses
any line that differs (an opcode of another length, one nothing reaches,
reached bytes written as data, a jump label that does not match its
operand's encoding).

    python3 tools/scripts.py check     disassemble every scene pack and the
                                       fx scripts afresh and assemble them
                                       back: byte-exact?
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
import battle  # noqa: E402
import events  # noqa: E402

CACHE_DIR = Path('build/scripts')          # the code image and the traces
BANK_C2 = ROOT / 'asm' / 'bankC2' / 'bankC2.asm'
BANK_CD = ROOT / 'asm' / 'bankCD' / 'bankCD.asm'
SCENE_BUF = 0x7F0400                       # C2Scene_ScriptBuf
SCENE_PACKS = 'C2SceneRom_ScriptPacks'
FX_TABLE = 'BattleRom_FxScriptPtrs'
SENTINEL = 0x5A5A                          # the mark put in a return slot
SPAWN = 0x1000001                          # memory keys of marks (no address)


class ScriptsError(Exception):
    pass


def _int(t: str, where: str) -> int:
    if not re.fullmatch(r'-?[0-9]+', t):
        raise ScriptsError(f'{where}: {t!r} is not a number')
    return int(t)


def _byte(t: str, where: str) -> int:
    try:
        return battle._byte(t, where)
    except battle.BattleError as e:
        raise ScriptsError(str(e)) from None


# ── The interpreters, from the source ─────────────────────────────────────

class _Machine(absint.Machine):
    """absint's machine, noting the script address and bank each call of a
    spawn routine is given (scene opcodes $09/$43)."""
    spawn_at: set = set()

    def step(self, s, base_depth):
        if s.pc in self.spawn_at:
            self.spawns.add((s.x, s.a, tuple(sorted(s.xt)), tuple(sorted(s.at))))
        return super().step(s, base_depth)


class Lang:
    """The common part: traces cached by the bytes that matter, as in
    tools/battle.py."""
    name = ''

    def __init__(self, root: Path = ROOT):
        root = Path(root)
        self.root = root
        self.image, self.mask, self.labels = events.code_image(root, root / CACHE_DIR)
        self.code_key = hashlib.sha256(self.image + bytes(self.mask)).hexdigest()
        self.d = battle.defines(root)
        self.machine = _Machine(self.image, self.mask, max_steps=6000000, callee_steps=2000000)
        self.machine.spawns = set()
        self.cache: dict = {}
        self.specs: dict = {}
        self.dirty = False

    def table(self, label: str, n: int) -> list[int]:
        a = self.labels[label]
        off = (a >> 16) - 0xC0 << 16 | a & 0xFFFF
        return [(a & 0xFF0000) | self.image[off + 2 * i] | self.image[off + 2 * i + 1] << 8 for i in range(n)]

    def run(self, known: dict, ptr: int) -> dict:
        op = known[ptr]
        for pattern, by_values in self.cache.get(op, {}).items():
            places = [k if absolute else ptr + k for absolute, k in pattern]
            if all(p in known for p in places):
                out = by_values.get(tuple(known[p] for p in places))
                if out is not None:
                    return out
        out = self._trace(known, ptr)
        keys = set(out['control']) | set(out['reads'])
        for x in out['outs']:
            if x[0] in ('pos', 'spawn'):
                keys |= set(x[3])
        pattern = tuple(sorted((False, k) if 0 <= k < 64 else (True, ptr + k) for k in keys))
        values = tuple(known.get(k if absolute else ptr + k) for absolute, k in pattern)
        if None not in values:
            self.cache.setdefault(op, {}).setdefault(pattern, {})[values] = out
            self.dirty = True
        return out

    def _run(self, s, known, ptr, reads, control, opaque):
        m = self.machine
        m.spawns = set()
        try:
            ends = m.run(s, known)
        except absint.Unresolved as e:
            return None, str(e)
        reads |= {a - ptr for a in m.reads}
        control |= {a - ptr for a in m.control}
        opaque |= m.opaque
        self.chains |= m.opaque_chains
        return ends, None

    @staticmethod
    def _saved_return(st, ptr, avoid, entry):
        """Where a handler that moves the pointer by its operands saved a
        return: a word it stored that is the opcode's address + k. A word
        that was in memory from the start (the task's address, say) is
        not one, whatever it happens to equal."""
        for k in range(1, 16):
            r = ptr + k
            for a, v in st.mem.items():
                if a in avoid or a >= 0x1000000 or v != (r & 0xFF):
                    continue
                if (entry.get(a), entry.get(a + 1)) == (v, st.mem.get(a + 1)):
                    continue
                if st.mem.get(a + 1) == (r >> 8 & 0xFF) and a + 1 not in avoid:
                    return k
        return None

    # The traces are kept in build/scripts/<lang>.json (plain JSON), keyed by
    # the source's and this section's hash, with the file's sha256 in
    # <lang>.key: tamper-evident, not tamper-proof. CI never has the file and
    # traces afresh; every script still has to assemble back to its bytes.
    def _trace_files(self, root: Path):
        h = hashlib.sha256(self.code_key.encode())
        me = (ROOT / 'tools' / 'scripts.py').read_text()
        h.update(me[me.index('# ── The interpreters'):me.index('\ndef classify(')].encode())
        for tool in ('events.py', 'battle.py', 'absint.py', 'disasm.py'):
            h.update((ROOT / 'tools' / tool).read_bytes())
        return root / CACHE_DIR / f'{self.name}.json', root / CACHE_DIR / f'{self.name}.key', h.hexdigest()

    def load(self, root: Path | None = None) -> None:
        data_f, key_f, key = self._trace_files(Path(root or self.root))
        if not (data_f.exists() and key_f.exists()):
            return
        want, _, digest = key_f.read_text().partition(' ')
        if want != key:
            return
        raw = data_f.read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest.strip():
            raise ScriptsError(f'{data_f} is not what tools/scripts.py wrote (changed by hand?); '
                               f'delete it and {key_f.name} to trace the handlers again')
        try:
            j = json.loads(raw.decode())
            self.cache = {op: {tuple(tuple(k) for k in pat): {tuple(v): _out_from(o) for v, o in by}
                               for pat, by in pats} for op, pats in j['cache']}
            self.specs = {op: tuple(s) for op, s in j['specs']}
        except (ValueError, KeyError, TypeError, IndexError) as e:
            raise ScriptsError(f'{data_f}: not a trace file ({e}); delete it to trace again') from None
        self.dirty = False

    def save(self, root: Path | None = None) -> None:
        if not self.dirty:
            return
        data_f, key_f, key = self._trace_files(Path(root or self.root))
        raw = json.dumps({'cache': [[op, [[[list(k) for k in pat], [[list(v), _out_to(o)] for v, o in by.items()]]
                                          for pat, by in pats.items()]] for op, pats in self.cache.items()],
                          'specs': [[op, list(s)] for op, s in self.specs.items()]},
                         separators=(',', ':')).encode()
        data_f.parent.mkdir(parents=True, exist_ok=True)
        data_f.write_bytes(raw)
        key_f.write_text(f'{key} {hashlib.sha256(raw).hexdigest()}')
        self.dirty = False

    @staticmethod
    def _state():
        s = absint.State()
        s.c = s.z = s.n = s.v = None
        s.sp, s.spt, s.mem, s.memt = [], [], {}, {}
        s.at = s.xt = s.yt = s.ft = absint.E
        s.depth = 0
        return s


class SceneLang(Lang):
    """C2Scene_TaskRunScript: the handler runs with M=0, A = X = the opcode
    * 2, C2Script_Ptr (DP $58) on the opcode, C2Scene_TaskCur (DP $4E) a
    task record; it returns Z=0 with the bytes to add to C2Script_Ptr in A,
    or Z=1 to stop (C=1 also ends the task)."""
    name = 'scene'
    count_label = 'C2Script_OpTable'

    def __init__(self, root: Path = ROOT):
        super().__init__(root)
        names = battle.table_handlers('C2Script_OpTable', Path(root) / 'asm' / 'bankC2' / 'bankC2.asm')
        self.count = len(names)
        self.names = [f'Op{op:02X}_{h.removeprefix("C2Script_")}' for op, h in enumerate(names)]
        self.handlers = self.table('C2Script_OpTable', self.count)
        self.ptr = self.d['C2Script_Ptr']
        self.task = self.d['C2Scene_TaskRecords'] + 4 * self.d['C2Scene_TaskSize']   # record 4
        self.ret_slot = self.task + 5                       # C2Scene_Task.ScriptReturn (+$05)
        self.machine.spawn_at = {self.labels['C2Scene_TaskSpawnScript'], self.labels['C2Scene_TaskSpawnScriptLow']}
        mw = absint._wram(0x7E0000 | self.d['C2Scene_MemberWords'])
        self.slots = [mw + 2 * k for k in range(3)]          # one word per party position
        self.ret_bias = 0

    def _trace(self, known: dict, ptr: int) -> dict:
        op = known[ptr]
        reads, control, opaque, outs = set(), set(), set(), set()
        self.chains = set()
        if op >= self.count:
            return {'reads': [], 'control': [], 'outs': [('bad', f'opcode ${op:02X} has no handler')], 'opaque': []}
        s = self._state()
        s.pc = self.handlers[op]
        s.a, s.b, s.x, s.y = (op * 2) & 0xFF, (op * 2) >> 8, op * 2, None
        s.d, s.db, s.m, s.xf = 0, 0x00, False, False
        s.c = False                                     # from the runner's ASL of the opcode
        p, t = self.ptr, self.task
        s.mem.update({p: ptr & 0xFF, p + 1: ptr >> 8 & 0xFF, p + 2: ptr >> 16,
                      0x7E0000 | self.d['C2Scene_TaskCur']: t & 0xFF, 0x7E0001 | self.d['C2Scene_TaskCur']: t >> 8,
                      0x7E0000 | t + 7: ptr & 0xFF, 0x7E0000 | t + 8: ptr >> 8 & 0xFF, 0x7E0000 | t + 9: ptr >> 16,
                      0x7E0000 | self.ret_slot: SENTINEL & 0xFF, 0x7E0000 | self.ret_slot + 1: SENTINEL >> 8})
        s.mem = {absint._wram(k if k > 0xFFFF else 0x7E0000 | k): v for k, v in s.mem.items()}
        entry = dict(s.mem)
        ends, err = self._run(s, known, ptr, reads, control, opaque)
        if ends is None:
            return {'reads': [], 'control': [], 'outs': [('bad', err)], 'opaque': []}
        for x, a, xt, at in self.machine.spawns:
            outs.add(('spawn', x, a, tuple(sorted(k - ptr for k in set(xt) | set(at))),
                      tuple(sorted(k - ptr for k in xt)), tuple(sorted(k - ptr for k in at))))
        pw = absint._wram(0x7E0000 | p)
        for st, how in ends:
            # a word of the operands stored in C2Scene_MemberWords: the
            # leader's and members' script (C2Scene_LeaderScriptStart and
            # C2Scene_MemberScriptStart run it in the buffer's bank)
            for slot in self.slots:
                t0, t1 = st.memt.get(slot, absint.E), st.memt.get(slot + 1, absint.E)
                if t0 and t0 == t1 and len(t0) == 2 and max(t0) == min(t0) + 1:
                    j = min(t0) - ptr
                    outs.add(('spawn', None, None, (j, j + 1), (j, j + 1), ()))
            if how != 'rts':
                outs.add(('bad', f'returns with {how}'))
                continue
            if st.z is None:
                outs.add(('ram', bool(self.machine.opaque)))
                continue
            if st.z:
                outs.add(('done',) if st.c else ('pos', 0, False, (), None, None))
                continue
            base = [st.mem.get(pw + i) for i in range(2)]
            if None in base or st.a is None or st.b is None:
                outs.add(('ram', bool(self.machine.opaque)))
                continue
            taint = st.memt.get(pw, absint.E) | st.memt.get(pw + 1, absint.E) | st.at
            new = (base[0] | base[1] << 8) + (st.a | st.b << 8) & 0xFFFF
            if new == SENTINEL and not taint:
                outs.add(('return',))
                continue
            new |= ptr & 0xFF0000
            ret = self._saved_return(st, ptr, {pw, pw + 1, pw + 2}, entry) if taint else None
            outs.add(('pos', new - ptr, bool(taint), tuple(sorted(a - ptr for a in taint)), ret,
                      new if taint else None))
        return {'reads': sorted(k for k in reads if k > 0), 'control': sorted(control),
                'outs': sorted(outs, key=str), 'opaque': sorted(opaque), 'chains': sorted(self.chains)}


class FxLang(Lang):
    """BattleCD_RunFxScript: a byte below $80 or $FF is read by the runner
    itself (one step); $80-$F9 run through BattleCD_RunFxOp with DP $40 on
    the opcode, and the runner goes on at DP $40 + 1."""
    name = 'fx'

    def __init__(self, root: Path = ROOT):
        super().__init__(root)
        names = battle.table_handlers('BattleCD_FxOpTable', Path(root) / 'asm' / 'bankCD' / 'bankCD.asm')
        self.first = 0x80
        self.count = self.first + len(names)                 # $80-$F9
        self.names = [None] * 256
        for i, h in enumerate(names):
            self.names[self.first + i] = f'Op{self.first + i:02X}_{h.removeprefix("BattleCD_FxOp").removeprefix("BattleCD_")}'
        self.no_page, self.end = self.d['BattleCD_FxNoPage'], self.d['BattleCD_FxEnd']
        self.ptr = 0x7E0000 | self.d['BattleCD_FxScriptPtr']
        self.chan = 0x7E0000 | self.d['Battle_FxChannels']
        self.ret_slot = 0x7E0000 | self.d['Battle_FxReturnPtr']
        self.ret_bias = 1                                    # the runner's INY after the op

    def _trace(self, known: dict, ptr: int) -> dict:
        op = known[ptr]
        reads, control, opaque, outs = set(), set(), set(), set()
        self.chains = set()
        s = self._state()
        s.d, s.db, s.m, s.xf = 0, 0x7E, True, False
        s.x, s.y = 0, None                                   # channel 0
        if op < self.first or op == self.end:
            # the runner itself (it returns after a page byte, $7F or $FF)
            s.pc = self.labels['BattleCD_RunFxScript']
            s.a, s.b = None, 0
            s.mem.update({self.chan + 3: ptr & 0xFF, self.chan + 4: ptr >> 8 & 0xFF, self.chan + 5: ptr >> 16,
                          self.chan: 1})
            ends, err = self._run(s, known, ptr, reads, control, opaque)
            if ends is None:
                return {'reads': [], 'control': [], 'outs': [('bad', err)], 'opaque': []}
            for st, how in ends:
                if how != 'rts':
                    outs.add(('bad', f'returns with {how}'))
                elif st.mem.get(self.chan) == 0:
                    outs.add(('done',))
                else:
                    v = [st.mem.get(self.chan + 3 + i) for i in range(3)]
                    if None in v:
                        outs.add(('ram', bool(self.machine.opaque)))
                    else:
                        outs.add(('pos', (v[0] | v[1] << 8 | v[2] << 16) - ptr, False, (), None, None))
        elif op >= self.count:
            return {'reads': [], 'control': [], 'outs': [('bad', f'opcode ${op:02X} has no handler')], 'opaque': []}
        else:
            s.pc = self.labels['BattleCD_RunFxOp']
            s.a, s.b = op, 0
            s.mem.update({self.ptr: ptr & 0xFF, self.ptr + 1: ptr >> 8 & 0xFF, self.ptr + 2: ptr >> 16,
                          self.ret_slot: SENTINEL & 0xFF, self.ret_slot + 1: SENTINEL >> 8})
            entry = dict(s.mem)
            ends, err = self._run(s, known, ptr, reads, control, opaque)
            if ends is None:
                return {'reads': [], 'control': [], 'outs': [('bad', err)], 'opaque': []}
            for st, how in ends:
                if how != 'rts':
                    outs.add(('bad', f'returns with {how}'))
                    continue
                v = [st.mem.get(self.ptr + i) for i in range(3)]
                if None in v:
                    outs.add(('ram', bool(self.machine.opaque)))
                    continue
                taint = absint.E
                for i in range(2):
                    taint |= st.memt.get(self.ptr + i, absint.E)
                w = v[0] | v[1] << 8
                if w == SENTINEL and not taint:
                    outs.add(('return',))
                    continue
                new = (ptr & 0xFF0000) | (w + 1) & 0xFFFF
                ret = self._saved_return(st, ptr, {self.ptr, self.ptr + 1, self.ptr + 2}, entry) if taint else None
                outs.add(('pos', new - ptr, bool(taint), tuple(sorted(a - ptr for a in taint)),
                          None if ret is None else ret + self.ret_bias, new if taint else None))
        return {'reads': sorted(k for k in reads if k > 0), 'control': sorted(control),
                'outs': sorted(outs, key=str), 'opaque': sorted(opaque), 'chains': sorted(self.chains)}

    def head(self) -> int:
        """The bytes before a script's first step: where
        BattleCD_StartFxChannel puts the pointer, from the table entry."""
        s = self._state()
        s.pc = self.labels['BattleCD_StartFxChannel']
        s.a, s.b, s.x, s.y = 0, 0, 0, 0
        s.d, s.db, s.m, s.xf = 0, 0x7E, True, False
        t = self.d[FX_TABLE]
        known = {t: 0x34, t + 1: 0x12}
        ends = self.machine.run(s, known)
        got = set()
        for st, how in ends:
            v = [st.mem.get(self.chan + 3 + i) for i in range(2)]
            if None not in v:
                got.add((v[0] | v[1] << 8) - 0x1234)
        if len(got) != 1:
            raise ScriptsError('BattleCD_StartFxChannel: no one start offset')
        return got.pop()


def _out_to(o: dict) -> dict:
    return {'reads': list(o['reads']), 'control': list(o['control']), 'opaque': [list(x) for x in o['opaque']],
            'chains': [list(x) for x in o.get('chains', ())],
            'outs': [[x[0], x[1], x[2], list(x[3]), x[4], x[5]] if x[0] == 'pos'
                     else [x[0], x[1], x[2], list(x[3]), list(x[4]), list(x[5])] if x[0] == 'spawn' else list(x)
                     for x in o['outs']]}


def _out_from(o: dict) -> dict:
    return {'reads': o['reads'], 'control': o['control'], 'opaque': [tuple(x) for x in o['opaque']],
            'chains': [tuple(x) for x in o['chains']],
            'outs': [(x[0], x[1], x[2], tuple(x[3]), x[4], x[5]) if x[0] == 'pos'
                     else (x[0], x[1], x[2], tuple(x[3]), tuple(x[4]), tuple(x[5])) if x[0] == 'spawn' else tuple(x)
                     for x in o['outs']]}


def classify(lang: Lang, known: dict, ptr: int) -> 'Op':
    """The opcode at ptr, from its handler (see the docstring)."""
    o = Op()
    o.off, o.op = ptr, known[ptr]
    res = lang.run(known, ptr)
    where = f'${ptr:06X} byte ${o.op:02X} ({op_name(lang, o.op)})'
    bad = [x for x in res['outs'] if x[0] == 'bad']
    if bad:
        raise ScriptsError(f'{where}: {bad[0][1]}')
    o.trusted = set()
    for chain in res.get('chains', ()):
        t = trusted_by(lang, chain, known, ptr)
        if t is None:
            why = sorted({r for c, r in res['opaque'] if c == chain[-1]}) or ['?']
            raise ScriptsError(f'{where}: it calls ${chain[-1]:06X}, which the interpreter cannot follow '
                               f'({why[0]}), and no reason in TRUST says it leaves the script alone')
        o.trusted.add(t)
    if any(x[0] == 'ram' and x[1] for x in res['outs']):
        raise ScriptsError(f'{where}: where it goes on depends on a callee the interpreter cannot follow '
                           f'({res["opaque"][0][1] if res["opaque"] else "?"})')
    reads = res['reads']
    poss = [x for x in res['outs'] if x[0] == 'pos']
    static = sorted({x[1] for x in poss if not x[2] and x[1] > 0})
    calls = sorted({(x[5], x[4]) for x in poss if x[2] and x[4] is not None})
    jumps = [x for x in poss if x[2] and x[4] is None]
    # A position computed from its bytes is a jump when it follows an
    # encoding of them (jump_spec); else, when it is just past the bytes it
    # reads, a count of its own length (as battle opcode $80).
    counted, spec = [], None
    if jumps or calls:
        try:
            spec = jump_spec(lang, known, ptr, res)
        except ScriptsError:
            if calls or not all(reads and x[1] == 1 + max(reads) for x in jumps):
                raise
            counted, jumps = sorted({x[1] for x in jumps}), []
    o.inside = []
    if len(static) > 1 and not counted and not calls:
        o.inside = [ptr + d for d in static[:-1]]
        static = static[-1:]
    lengths = set(static) | set(counted) | {k for _, k in calls}
    if len(lengths) > 1:
        raise ScriptsError(f'{where}: it goes on at +{" and +".join(map(str, sorted(lengths)))}')
    o.fixed = bool(lengths)
    o.length = lengths.pop() if lengths else 1 + max(reads, default=0)
    o.next = bool(static or counted)
    o.stay = any(x[1] == 0 and not x[2] for x in poss)
    o.done = any(x[0] == 'done' for x in res['outs'])
    o.ret = any(x[0] == 'return' for x in res['outs'])
    o.ram = any(x[0] == 'ram' for x in res['outs'])
    o.call = calls[0][0] if calls else None
    if len(calls) > 1:
        raise ScriptsError(f'{where}: two call targets')
    o.jumps, o.spec = [], None
    if jumps or calls:
        o.spec = spec
        target = spec_target(o.spec, known, ptr)
        if calls:
            o.call = target
        else:
            o.jumps = [target]
    o.spawns = []
    for x in res['outs']:
        if x[0] == 'spawn':
            o.spawn_spec = spawn_spec(x)
            if o.spawn_spec is None:
                raise ScriptsError(f'{where}: a spawn whose address is no operand word')
            j, bj = o.spawn_spec
            bank = known[ptr + bj] if bj >= 0 else SCENE_BUF >> 16
            t = bank << 16 | known[ptr + j] | known[ptr + j + 1] << 8
            if t not in o.spawns:
                o.spawns.append(t)
    return o


def op_name(lang: Lang, op: int) -> str:
    if isinstance(lang, FxLang):
        if op < lang.first:
            return 'NoPage' if op == lang.no_page else 'Page'
        if op == lang.end:
            return 'End'
    n = lang.names[op] if op < len(lang.names) else None
    return n or f'Bad_{op:02X}'


class Op:
    __slots__ = ('off', 'op', 'length', 'fixed', 'next', 'stay', 'done', 'ret', 'ram', 'call', 'jumps', 'spec',
                 'spawns', 'spawn_spec', 'inside', 'trusted')


def spawn_spec(x) -> tuple[int, int] | None:
    """(operand of the address word, operand of the bank) of a spawn, from
    the bytes its X and A were computed from."""
    xs, bs = sorted(k for k in x[4] if k > 0), sorted(k for k in x[5] if k > 0)
    if len(xs) != 2 or xs[1] != xs[0] + 1 or len(bs) > 1 or not bs and x[5]:
        return None
    return xs[0], bs[0] if bs else -1               # -1: the buffer's bank (a member word)


def spec_target(spec: tuple, known: dict, ptr: int) -> int:
    kind, j, a, c = spec
    if kind == 'word':
        return (ptr & 0xFF0000) | (known[ptr + j] | known[ptr + j + 1] << 8) + c & 0xFFFF
    b = known[ptr + j]
    b = b - 256 if a == 'sext' and b >= 0x80 else b
    sign = -1 if a == 'neg' else 1
    return (ptr & 0xFF0000) | (ptr + c + sign * b) & 0xFFFF


def jump_spec(lang: Lang, known: dict, ptr: int, res: dict) -> tuple:
    """How the opcode's jump or call target comes from its operands:
    ('word', J, -, C): the word at operand J + C, in the script's bank;
    ('byte', J, 'sext'|'neg'|'add', C): the opcode's place + C plus (or
    minus) byte J. Found by changing the bytes and watching the target."""
    op = known[ptr]
    if op in lang.specs:
        return lang.specs[op]
    poss = [x for x in res['outs'] if x[0] == 'pos' and x[2]]
    taint = sorted({k for x in poss for k in x[3] if k > 0})
    base = sorted({ptr + x[1] for x in poss})
    if len(base) != 1:
        raise ScriptsError(f'${ptr:06X} opcode ${op:02X}: {len(base)} computed targets')

    def target_with(changes):
        k2 = dict(known)
        for j, v in changes.items():
            k2[ptr + j] = v & 0xFF
        r = lang._trace(k2, ptr)
        t = sorted({ptr + x[1] for x in r['outs'] if x[0] == 'pos' and x[2]})
        return t[0] if len(t) == 1 else None
    cands = []
    for j in taint:
        if j + 1 in taint:
            cands.append(('word', j, '-', base[0] - (ptr & 0xFF0000) - (known[ptr + j] | known[ptr + j + 1] << 8)))
        for a in ('sext', 'add', 'neg'):
            b = known[ptr + j]
            bb = b - 256 if a == 'sext' and b >= 0x80 else b
            cands.append(('byte', j, a, (base[0] - ptr - (-bb if a == 'neg' else bb)) & 0xFFFF))
    for spec in cands:
        kind, j, a, c = spec
        spec = (kind, j, a, c if kind == 'word' else (c - 0x10000 if c >= 0x8000 else c))
        # (changes that make the byte 0 are left out: an offset of 0 waits)
        ok, tried = True, 0
        for delta in (1, 2, 3, 0x40, 0x41):
            if (known[ptr + j] + delta) & 0xFF == 0 or tried == 3:
                continue
            tried += 1
            t = target_with({j: known[ptr + j] + delta})
            k2 = dict(known)
            k2[ptr + j] = (known[ptr + j] + delta) & 0xFF
            if t is None or t != spec_target(spec, k2, ptr):
                ok = False
                break
        if ok and spec_target(spec, known, ptr) == base[0]:
            lang.specs[op] = spec
            lang.dirty = True
            return spec
    raise ScriptsError(f'${ptr:06X} opcode ${op:02X}: its target is no word or byte of its operands')


# ── Disassembly ────────────────────────────────────────────────────────────

def disassemble(lang: Lang, known: dict, regions: list[tuple[int, int]], entries: set[int],
                heads: dict[int, int] | None = None) -> dict:
    """{'ops' {addr: Op}, 'entries', 'heads'}: what the entries reach.
    `heads`: {script start: bytes before its first step} (fx)."""
    def in_region(a):
        return any(s <= a < e for s, e in regions)
    heads = heads or {}
    owner = {h + i for h, n in heads.items() for i in range(n)}
    ops: dict[int, Op] = {}
    pending, continued = [], set()
    spawned, off_end = set(), set()

    def walk(work):
        while work:
            a = work.pop()
            if a in ops:
                continue
            if not in_region(a):
                # a script whose last opcode goes on past the end of its
                # region (the bytes after an unpacked pack are no part of it)
                if any(a == e for _, e in regions):
                    off_end.add(a)
                    continue
                raise ScriptsError(f'an opcode at ${a:06X}, outside the scripts')
            if a in owner:
                raise ScriptsError(f'${a:06X}: a script runs into a script\'s head')
            o = classify(lang, known, a)
            if not all(in_region(a + i) for i in range(o.length)):
                raise ScriptsError(f'${a:06X} byte ${o.op:02X}: {o.length} bytes run past the scripts')
            ops[a] = o
            if o.call is not None:
                pending.append(o)
                work.append(o.call)
            if o.next:
                work.append(a + o.length)
            work += o.jumps + o.inside
            for t in o.spawns:
                if in_region(t):
                    spawned.add(t)
                    work.append(t)

    def returns(t) -> bool:
        seen, todo = set(), [t]
        while todo:
            y = todo.pop()
            if y in seen or y not in ops:
                continue
            seen.add(y)
            o = ops[y]
            if o.ret:
                return True
            if o.call is not None:
                todo.append(o.call)
                if y in continued:
                    todo.append(y + o.length)
            if o.next:
                todo.append(y + o.length)
            todo += o.jumps + o.inside
        return False
    work = sorted(entries)
    while True:
        walk(work)
        work = []
        for o in pending:
            if o.off not in continued and returns(o.call):
                continued.add(o.off)
                work.append(o.off + o.length)
        if not work:
            break
    for o in pending:
        o.next = o.off in continued
    return {'ops': ops, 'entries': set(entries), 'heads': heads, 'spawned': spawned, 'off_end': off_end}


def _layout(ops: dict) -> tuple[list[int], dict[int, int]]:
    primary, inner, end = [], {}, -1
    for y in sorted(ops):
        if y >= end:
            primary.append(y)
            end = y + ops[y].length
        else:
            inner[y] = primary[-1]
    return primary, inner


# ── The readable form ─────────────────────────────────────────────────────

HEAD = ('; {title}: {what}, disassembled from your own ROM by tools/scripts.py (never commit it).',
        '; The build assembles it back into the bytes; the format is in tools/scripts.py. This file',
        '; is regenerated by extraction: an edit is lost when it runs again.')


def _lab(lang: Lang, a: int) -> str:
    return f'L_{a & 0xFFFF:04X}' if lang.name == 'scene' else f'L_{a:06X}'


def render_body(lang: Lang, d: dict, known: dict, regions: list[tuple[str, int, int]],
                labels: dict[int, str]) -> list[str]:
    """The lines of the regions: labels, opcode lines, inner lines, data."""
    ops = d['ops']
    primary, inner = _layout(ops)
    inners: dict[int, list[int]] = {}
    for y, host in inner.items():
        inners.setdefault(host, []).append(y)
    for o in ops.values():
        for t in o.jumps + ([o.call] if o.call is not None else []) + o.inside:
            labels.setdefault(t, _lab(lang, t))
        for t in o.spawns:
            if t in ops:
                labels.setdefault(t, _lab(lang, t))
    for y in inner:
        labels.setdefault(y, _lab(lang, y))
    covered = set()
    for y in primary:
        covered.update(range(y, y + ops[y].length))
    for h, n in d['heads'].items():
        covered.update(range(h, h + n))
    out = []

    def line(o: Op) -> str:
        n = op_name(lang, o.op)
        if n in ('Page',):
            return f'Page ${o.op:02X}'
        if n in ('NoPage', 'End'):
            return n
        args = [f'${known[o.off + i]:02X}' for i in range(1, o.length)]
        ref = o.call if o.call is not None else (o.jumps[0] if o.jumps else None)
        if o.spec is not None and ref is not None:
            kind, j, _, _ = o.spec
            args[j - 1] = '->' + labels[ref]
            if kind == 'word':
                args[j] = None
        if o.spawns and o.spawns[0] in labels:
            j, _ = o.spawn_spec
            args[j - 1] = '->' + labels[o.spawns[0]]
            args[j] = None
        return ' '.join([n] + [a for a in args if a is not None])
    prim = set(primary)
    for label, start, stop in regions:
        out.append(f'@region {label} ${start:06X}')
        y = start
        while y < stop:
            if y in labels and y not in inner:
                out.append(labels[y] + ':')
            if y in d['heads']:
                out.append('    @head ' + ' '.join(f'${known[y + i]:02X}' for i in range(d['heads'][y])))
                y += d['heads'][y]
                continue
            if y in prim:
                o = ops[y]
                out.append('    ' + line(o))
                for z in sorted(inners.get(y, ())):
                    out.append(f'    @inner +{z - y} {labels[z]} ' + line(ops[z]))
                y += o.length
                continue
            z = y + 1
            while z < stop and z not in covered and z not in labels:
                z += 1
            chunk = bytes(known[a] for a in range(y, z))
            for k in range(0, len(chunk), 16):
                out.append('@bytes ' + ' '.join(f'{b:02X}' for b in chunk[k:k + 16]))
            y = z
    return out


def render_specs(lang: Lang, d: dict) -> list[str]:
    out = []
    for op in sorted({o.op for o in d['ops'].values() if o.spec is not None}):
        kind, j, a, c = lang.specs[op]
        out.append(f'@jump {op_name(lang, op)} {kind} {j} {a} {c}')
    for op, (j, bj) in sorted({(o.op, o.spawn_spec) for o in d['ops'].values() if o.spawns}):
        out.append(f'@spawn {op_name(lang, op)} {j} {bj}')
    return out


def assemble_body(lang: Lang, lines: list[tuple[str, list[str]]], regions: dict[str, tuple[int, int]],
                  name: str) -> tuple[dict[int, int], dict, dict, list]:
    """(image {addr: byte}, labels, kinds {addr: line kind}, op lines)."""
    names = {op_name(lang, op): op for op in range(256)
             if op_name(lang, op) not in ('Page',) and not op_name(lang, op).startswith('Bad_')}
    specs, spawns = {}, {}
    for where, w in lines:
        if w[0] == '@jump':
            if len(w) != 6 or w[1] not in names or w[2] not in ('word', 'byte'):
                raise ScriptsError(f'{where}: @jump NAME word|byte J A C')
            specs[names[w[1]]] = (w[2], _int(w[3], where), w[4], _int(w[5], where))
        elif w[0] == '@spawn':
            if len(w) != 4 or w[1] not in names:
                raise ScriptsError(f'{where}: @spawn NAME J B')
            spawns[names[w[1]]] = (_int(w[2], where), _int(w[3], where))
    labels, kinds, cur, pos, last = {}, {}, None, None, None
    body = []
    for where, w in lines:
        if w[0] in ('@jump', '@spawn', '@entry', '@scene', '@table'):
            continue
        if w[0] == '@region':
            if len(w) != 3 or w[1] not in regions or w[2] != f'${regions[w[1]][0]:06X}':
                raise ScriptsError(f'{where}: @region LABEL $AAAAAA, a piece of this unit at its address')
            cur, pos = w[1], regions[w[1]][0]
            continue
        if cur is None:
            raise ScriptsError(f'{where}: {w[0]} outside a @region')
        if len(w) == 1 and w[0].endswith(':'):
            if w[0][:-1] in labels:
                raise ScriptsError(f'{where}: label {w[0][:-1]} twice')
            labels[w[0][:-1]] = pos
            continue
        if w[0] == '@inner':
            if last is None or len(w) < 4:
                raise ScriptsError(f'{where}: @inner +K LABEL OPCODE ...')
            if not w[1].startswith('+'):
                raise ScriptsError(f'{where}: @inner +K LABEL OPCODE ...')
            if w[2] in labels:
                raise ScriptsError(f'{where}: label {w[2]} twice')
            labels[w[2]] = last + _int(w[1][1:], where)
            body.append(('inner', w[3:], where, last + _int(w[1][1:], where)))
            continue
        if w[0] == '@bytes':
            size = len(w) - 1
            body.append(('bytes', w, where, pos))
        elif w[0] == '@head':
            size = len(w) - 1
            body.append(('head', w, where, pos))
        else:
            op = names.get(w[0])
            size = 1 + sum(2 if t.startswith('->') and (specs.get(op, ('',))[0] == 'word' or op in spawns)
                           else 1 for t in w[1:]) if w[0] not in ('Page', 'NoPage', 'End') else 1
            body.append(('op', w, where, pos))
            last = pos
        kinds[pos] = body[-1][0]
        pos += size
    image, op_lines = {}, []

    def target(t, where):
        if t not in labels:
            raise ScriptsError(f'{where}: no label {t}')
        return labels[t]

    def encode(w, at, where):
        """(the line's bytes, the operands written as ->LABEL)"""
        if w[0] == 'Page':
            v = _byte(w[1], where) if len(w) == 2 else -1
            if not 0 <= v < lang.no_page:
                raise ScriptsError(f'{where}: Page $XX takes a page byte below ${lang.no_page:02X}')
            return bytes([v]), set()
        if w[0] in ('NoPage', 'End'):
            if len(w) != 1:
                raise ScriptsError(f'{where}: {w[0]} takes no operand')
            return bytes([lang.no_page if w[0] == 'NoPage' else lang.end]), set()
        if w[0] not in names:
            raise ScriptsError(f'{where}: unknown opcode {w[0]}')
        op = names[w[0]]
        out, refd = bytearray([op]), set()
        for t in w[1:]:
            if t.startswith('->'):
                refd.add(len(out))
                a = target(t[2:], where)
                if op in spawns:
                    if len(out) != spawns[op][0]:
                        raise ScriptsError(f'{where}: {w[0]}\'s script address is operand {spawns[op][0]}')
                    out += (a & 0xFFFF).to_bytes(2, 'little')
                    continue
                if op not in specs:
                    raise ScriptsError(f'{where}: {w[0]} has no @jump line')
                kind, j, sa, c = specs[op]
                if len(out) != j:
                    raise ScriptsError(f'{where}: {w[0]}\'s target is operand {j}')
                if a >> 16 != at >> 16:
                    raise ScriptsError(f'{where}: {t[2:]} is in another bank')
                if kind == 'word':
                    out += ((a - c) & 0xFFFF).to_bytes(2, 'little')
                else:
                    rel = ((a - at - c + 0x8000) & 0xFFFF) - 0x8000
                    v = -rel if sa == 'neg' else rel
                    if not (-128 <= v < 128 if sa == 'sext' else 0 <= v < 256):
                        raise ScriptsError(f'{where}: {t[2:]} is out of the jump\'s reach')
                    out.append(v & 0xFF)
            else:
                out.append(_byte(t, where))
        return bytes(out), refd
    for kind, w, where, at in body:
        if kind == 'inner':
            continue
        if kind == 'bytes':
            if not all(re.fullmatch(r'[0-9A-Fa-f]{2}', t) for t in w[1:]):
                raise ScriptsError(f'{where}: @bytes takes XX bytes')
            b = bytes(int(t, 16) for t in w[1:])
        elif kind == 'head':
            b = bytes(_byte(t, where) for t in w[1:])
        else:
            b, refd = encode(w, at, where)
            op_lines.append((where, w[0], at, len(b), refd))
        for i, v in enumerate(b):              # (each line's size is its encoding's: no overlap)
            image[at + i] = v
    for kind, w, where, at in body:
        if kind == 'inner':
            b, refd = encode(w, at, where)
            if any(image.get(at + i) != v for i, v in enumerate(b)):
                raise ScriptsError(f'{where}: the @inner opcode is not the bytes it shares')
            op_lines.append((where, w[0], at, len(b), refd))
    return image, labels, kinds, op_lines, (specs, spawns)


def check_structure(lang: Lang, d: dict, op_lines: list, kinds: dict, specs: tuple, name: str) -> None:
    """The lines must be what the disassembler derives from the bytes."""
    specs, spawns = specs
    lines_at = {at: (where, opname, n) for where, opname, at, n, _ in op_lines}
    refs = {at: refd for _, _, at, _, refd in op_lines}
    for at, o in sorted(d['ops'].items()):
        if o.spec is not None and specs.get(o.op) != o.spec:
            raise ScriptsError(f'{lines_at.get(at, (name,))[0]}: {op_name(lang, o.op)}\'s @jump line is not its '
                               f'encoding {o.spec}')
    for at, (where, opname, n) in sorted(lines_at.items()):
        o = d['ops'].get(at)
        if o is None:
            raise ScriptsError(f'{where}: nothing reaches this {opname} line (bytes nothing reaches are @bytes)')
        if o.length != n:
            raise ScriptsError(f'{where}: {opname} takes {o.length} bytes here (its handler, as the '
                               f'disassembler derives it); the line gives {n}')
    for at, o in sorted(d['ops'].items()):
        if at not in lines_at:
            raise ScriptsError(f'{name}: the byte at ${at:06X} ({op_name(lang, o.op)}) is reached: it is no data')
        if o.spawns and spawns.get(o.op) != o.spawn_spec:
            raise ScriptsError(f'{lines_at[at][0]}: {op_name(lang, o.op)}\'s @spawn line is not where its '
                               f'script address is {o.spawn_spec}')
        # a target in the scripts is written as its label, so that it
        # follows an edit (a plain word would keep pointing where it did)
        if o.spec is not None and o.spec[1] not in refs[at]:
            raise ScriptsError(f'{lines_at[at][0]}: {op_name(lang, o.op)}\'s target is written as bytes: '
                               f'write ->LABEL')
        if o.spawns and o.spawns[0] in d['ops'] and o.spawn_spec[0] not in refs[at]:
            raise ScriptsError(f'{lines_at[at][0]}: {op_name(lang, o.op)}\'s script address is written as '
                               f'bytes: write ->LABEL')


# ── Scene packs ───────────────────────────────────────────────────────────

def scene_entries(rom_or_lists: dict[int, bytes], pack: int, size: int) -> set[int]:
    """The pack's start and its scene's C2Scene_ListD script addresses in
    the pack. `rom_or_lists`: {pack index: the unpacked list pack of the
    scene whose header names it}."""
    out = {SCENE_BUF}
    lists = rom_or_lists.get(pack)
    if lists:
        k = 0
        for size_ in (7, 3, 3):                      # C2Scene_LoadLists: A, B, C
            n = lists[k]
            k += 1 + n * size_
        n = lists[k]
        k += 1
        for i in range(n):
            a = 0x7F0000 | lists[k + 2 * i] | lists[k + 2 * i + 1] << 8
            if SCENE_BUF <= a < SCENE_BUF + size:
                out.add(a)
    return out


def render_scene(lang: SceneLang, label: str, data: bytes, entries: set[int]) -> str:
    known = {SCENE_BUF + i: b for i, b in enumerate(data)}
    region = (SCENE_BUF, SCENE_BUF + len(data))
    d = disassemble(lang, known, [region], entries)
    labels = {a: _lab(lang, a) for a in entries}
    out = [line.format(title=label, what='a scene script') for line in HEAD]
    out.append(f'@scene {label} ${SCENE_BUF:06X}')
    body = render_body(lang, d, known, [(label, *region)], labels)
    out += render_specs(lang, d)
    out += [f'@entry {_lab(lang, a)}' for a in sorted(entries) if a != SCENE_BUF]
    return '\n'.join(out + body) + '\n'


def assemble_scene(lang: SceneLang, text: str, label: str, size: int, entries_want: set[int],
                   name: str = '<scene>') -> bytes:
    """The pack's bytes from its text. entries_want: where the scene's
    lists start scripts in it (scene_entries), which the @entry lines must
    name exactly."""
    lines = [(f'{name}:{no}', w) for no, w in battle._lines(text)]
    if not lines or lines[0][1] != ['@scene', label, f'${SCENE_BUF:06X}']:
        raise ScriptsError(f'{name}: the first line is @scene {label} ${SCENE_BUF:06X}')
    image, labels, kinds, op_lines, specs = assemble_body(lang, lines, {label: (SCENE_BUF, size)}, name)
    if len(image) != size or not all(SCENE_BUF + i in image for i in range(size)):
        raise ScriptsError(f'{name}: {len(image)} bytes; {label} is {size}')
    data = bytes(image[SCENE_BUF + i] for i in range(size))
    entries = {SCENE_BUF}
    for where, w in lines:
        if w[0] == '@entry':
            if len(w) != 2 or w[1] not in labels:
                raise ScriptsError(f'{where}: @entry LABEL, a label of the pack')
            entries.add(labels[w[1]])
    if entries != entries_want:
        names = {a: n for n, a in labels.items()}
        miss = [names.get(a, f'${a:06X}') for a in sorted(entries_want - entries)]
        extra = [names.get(a, f'${a:06X}') for a in sorted(entries - entries_want)]
        raise ScriptsError(f'{name}: the @entry lines must name where the scene\'s lists start scripts'
                           + (f'; missing {", ".join(miss)}' if miss else '')
                           + (f'; not one: {", ".join(extra)}' if extra else ''))
    known = {SCENE_BUF + i: b for i, b in enumerate(data)}
    d = disassemble(lang, known, [(SCENE_BUF, SCENE_BUF + size)], entries)
    check_structure(lang, d, op_lines, kinds, specs, name)
    return data


# ── The fx scripts ────────────────────────────────────────────────────────

def render_fx(lang: FxLang, label: str, start: int, data: bytes) -> str:
    known = {start + i: b for i, b in enumerate(data)}
    head = lang.head()
    n = 0
    first = None
    while first is None or start + 2 * n < first:
        w = data[2 * n] | data[2 * n + 1] << 8
        t = (start & 0xFF0000) | w
        first = t if first is None else min(first, t)
        n += 1
    table = [(start & 0xFF0000) | data[2 * i] | data[2 * i + 1] << 8 for i in range(n)]
    if start + 2 * n != first:
        raise ScriptsError(f'{label}: the table does not end where the first script starts')
    region = (start + 2 * n, start + len(data))
    scripts = sorted({t for t in table if region[0] <= t < region[1]})
    d = disassemble(lang, known, [region], {t + head for t in scripts}, {t: head for t in scripts})
    labels = {t: f'F_{t:06X}' for t in scripts}
    labels.update({t + head: _lab(lang, t + head) for t in scripts})
    out = [line.format(title=label, what='the battle layer-effect scripts') for line in HEAD]
    out.append(f'@table {label} ${start:06X}')
    out += render_specs(lang, d)
    for i, t in enumerate(table):
        out.append(f'@entry {i} ' + (labels[t] if t in labels else f'${t & 0xFFFF:04X}'))
    out += render_body(lang, d, known, [(label + '_Scripts', *region)], labels)
    return '\n'.join(out) + '\n'


def assemble_fx(lang: FxLang, text: str, label: str, start: int, size: int, name: str = 'fx.bfx') -> bytes:
    lines = [(f'{name}:{no}', w) for no, w in battle._lines(text)]
    if not lines or lines[0][1] != ['@table', label, f'${start:06X}']:
        raise ScriptsError(f'{name}: the first line is @table {label} ${start:06X}')
    entries = [(where, w) for where, w in lines if w[0] == '@entry']
    n = len(entries)
    rstart = start + 2 * n
    image, labels, kinds, op_lines, specs = assemble_body(lang, lines, {label + '_Scripts': (rstart, size - 2 * n)},
                                                          name)
    head = lang.head()
    table = bytearray()
    heads = {}
    for i, (where, w) in enumerate(entries):
        if len(w) != 3 or w[1] != str(i):
            raise ScriptsError(f'{where}: @entry I TARGET, in order')
        t = w[2]
        if re.fullmatch(r'\$[0-9A-Fa-f]{4}', t):
            a = (start & 0xFF0000) | int(t[1:], 16)
            if rstart <= a < start + size:
                raise ScriptsError(f'{where}: {t} is inside the scripts: an entry there must name a script\'s '
                                   f'label (a @head line)')
        else:
            if t not in labels:
                raise ScriptsError(f'{where}: no label {t}')
            a = labels[t]
            if kinds.get(a) != 'head':
                raise ScriptsError(f'{where}: {t} is not a script (a @head line)')
            heads[a] = head
        table += (a & 0xFFFF).to_bytes(2, 'little')
    for at, k in kinds.items():
        if k == 'head' and at not in heads:
            raise ScriptsError(f'{name}: ${at:06X}: a @head line no entry names')
    if len(image) != size - 2 * n or not all(rstart + i in image for i in range(size - 2 * n)):
        raise ScriptsError(f'{name}: the scripts are {len(image)} bytes; they are {size - 2 * n}')
    data = bytes(table) + bytes(image[rstart + i] for i in range(size - 2 * n))
    known = {start + i: b for i, b in enumerate(data)}
    d = disassemble(lang, known, [(rstart, start + size)], {h + head for h in heads}, heads)
    check_structure(lang, d, op_lines, kinds, specs, name)
    return data


# ── Units, figures, checks ────────────────────────────────────────────────

def stats(text: str) -> dict:
    data = sum(len(w) - 1 for _, w in battle._lines(text) if w[0] == '@bytes')
    ops = sum(1 for _, w in battle._lines(text) if not w[0].startswith('@') and not w[0].endswith(':'))
    return {'data': data, 'lines': ops}


def _pairs(headers: bytes, base: int, list_pack, root: Path) -> dict[int, bytes]:
    """{script pack index: the unpacked list pack of the scene whose header
    names it}, from the bytes of C2SceneRom_HeaderTable (at `base`): its
    words, as C2Scene_GetHeaderPtr reads them, up to the first header one
    points at (the words after that are header bytes, though
    C2Scene_LocIdMask lets 16 scenes be asked for), and each header's
    C2Scene_HdrLists / C2Scene_HdrScript bytes. list_pack(i): the
    unpacked list pack i of C2SceneRom_ListPacks, or None."""
    d = battle.defines(root)
    n, first, out = 0, None, {}
    while first is None or base + 2 * n < first:
        if 2 * n + 1 >= len(headers):
            raise ScriptsError('C2SceneRom_HeaderTable: no header inside the table piece')
        w = (base & 0xFF0000) | headers[2 * n] | headers[2 * n + 1] << 8
        first = w if first is None else min(first, w)
        n += 1
    for i in range(n):
        h = (base & 0xFF0000) | headers[2 * i] | headers[2 * i + 1] << 8
        off = h - base
        if not 0 <= off <= len(headers) - 1 - max(d['C2Scene_HdrLists'], d['C2Scene_HdrScript']):
            raise ScriptsError(f'C2SceneRom_HeaderTable: scene {i}\'s header ${h:06X} is not in the table piece')
        li, si = headers[off + d['C2Scene_HdrLists']], headers[off + d['C2Scene_HdrScript']]
        if li & 0x80 or si & 0x80:
            continue                                # bit 7: no pack
        data = list_pack(li)
        if data is not None:
            out.setdefault(si, data)
    return out


def scene_pairs(rom: bytes, root: Path = ROOT) -> dict[int, bytes]:
    """_pairs from the ROM (the list packs unpacked from it)."""
    import c3pack
    d = battle.defines(root)
    F = lambda a: a - 0xC00000      # noqa: E731
    tab, lp = d['C2SceneRom_HeaderTable'], d['C2SceneRom_ListPacks']

    import extract_data
    pieces = {p['label']: p for p in extract_data.read_manifest()}

    def list_pack(i):
        if i >= int(pieces['C2SceneRom_ListPacks']['size']) // 3:
            return None
        p = rom[F(lp) + 3 * i] | rom[F(lp) + 3 * i + 1] << 8 | rom[F(lp) + 3 * i + 2] << 16
        return c3pack.unpack(rom, F(p))[0] if p else None
    piece = pieces['C2SceneRom_HeaderTable']
    return _pairs(rom[piece['offset']:piece['stop']], tab, list_pack, root)


def scene_pairs_built(root: Path = ROOT) -> dict[int, bytes]:
    """_pairs from the build's own inputs, no ROM: the header table's
    asset, C2SceneRom_ListPacks as the source names its packs, and those
    packs' unpacked assets."""
    import extract_data
    root = Path(root)
    pieces = {p['label']: p for p in extract_data.read_manifest()}
    hp = pieces['C2SceneRom_HeaderTable']
    lp = pieces['C2SceneRom_ListPacks']
    try:
        src = (root / 'asm' / 'data' / f'bank{int(lp["start"][1:3], 16):02X}.asm').read_text()
    except OSError as e:
        raise ScriptsError(f'C2SceneRom_ListPacks: {e}') from None
    m = re.search(r'^C2SceneRom_ListPacks:\n((?:\s+dl .*\n)+)', src, re.M)
    if not m:
        raise ScriptsError('asm/data: no C2SceneRom_ListPacks table')
    names = [ln.split()[1] for ln in m.group(1).splitlines()]

    def list_pack(i):
        if i >= len(names) or names[i].startswith('$'):
            return None
        p = pieces.get(names[i])
        if p is None or p['piece'] != 'packed':
            raise ScriptsError(f'C2SceneRom_ListPacks entry {i}: {names[i]} is not a packed piece')
        try:
            return (root / extract_data.ASSETS / p['asset']).read_bytes()
        except OSError as e:
            raise ScriptsError(f'{names[i]}: {e}') from None
    try:
        headers = (root / extract_data.ASSETS / hp['asset']).read_bytes()
    except OSError as e:
        raise ScriptsError(f'C2SceneRom_HeaderTable: {e}') from None
    return _pairs(headers, int(hp['start'][1:3], 16) << 16 | int(hp['start'][4:], 16), list_pack, root)


FX_ROWS = {'$D1:646C'}          # BattleRom_FxScriptPtrs and the scripts after it (one piece)

# What the scripts are known to hold (DATA_PLAN.md): the opcodes classed
# return, ram (a position from other RAM) and done over the real data. A
# change in any of them is a change in how the interpreter reads the
# handlers, and check() reports it.
EXITS = {'scene': {'ret': {0x37}, 'ram': set(), 'done': {0x52}},
         'fx': {'ret': {0x92}, 'ram': {0x84, 0x86, 0xD0}, 'done': {0xFF}}}


# Callees the interpreter cannot follow (an indirect jump through RAM or a
# table it is not given, a block move of unknown size, a wait on the APU).
# Where it goes on after one is the place after the call, with memory as it
# was at the call: an outcome taken that way is only right if the callee
# leaves alone what the outcome is read from (the script pointer, the
# return slot, the member words) and starts no script. classify() refuses
# every such callee but these, each trusted on the reason given, from its
# code; check() asserts that the real scripts need exactly these (for the
# opcodes listed), and, in each one's code followed statically from it
# (the tables named included; any other indirect jump fails), that no
# store names those bytes directly and no spawn routine is called. The
# reasons cover the indexed stores, which no static look can place.
# {lang: {routine: (opcodes, ((table or entry, entries or 0, M=1?), ...),
#                   RAM vectors its indirect jumps go through, reason)}}
TRUST = {
    'scene': {
        'C2Anim_Run': ({0x31, 0x39, 0x3F, 0x40}, (('C2Anim_OpTable', 8, False),), (),
                       'it runs the task\'s animation script through C2Anim_OpTable, by the animation opcode (other '
                       'data). The eight handlers write the task record through C2Scene_TaskCur (timer, sprite and '
                       'position words; ops 0-2 the record byte their operand names, which an animation script could '
                       'aim at the record\'s script pointer: not checked), C2Anim_Ptr (DP $52-$54), '
                       'C2Scene_SprFramePtr (DP $55-$57), the sprite list (C2Scene_SprAdd) and the VRAM queue (DP '
                       '$5E-$6x, by its end); none writes C2Script_Ptr (DP $58-$5A) or starts a script. Each of '
                       'the four opcodes then returns TDC/CLC itself: stay.'),
        **{n: ({op}, (), (),
               'it sets Decomp_Src/Dest and jumps to Decomp_ToWram, which runs with DP = DP_Decomp ($0300, '
               'restored) and writes only its DP block, WMADD and its output (WMDATA from Decomp_Dest on, and '
               'MVNs inside it). The destinations the traces show are $7E:C600 and $7F:8C00-$7F:F000 (one '
               'with its high byte from RAM), clear of DP $58-$5A, the task records, C2Scene_MemberWords '
               'and the script buffer at $7F:0400, as long as the pack fits before the bank\'s end (not '
               'checked). It starts no script.')
           for n, op in (('C2Scene_LoadBgGfx', 0x34), ('C2Scene_LoadExtraObjPack', 0x34),
                         ('C2Scene_LoadUnkC600', 0x34), ('C2Scene_UnpackBg3MapPack', 0x34),
                         ('C2Scene_UnpackBgPack', 0x34), ('C6Scene_UnpackObjPackA', 0x4E),
                         ('C6Scene_UnpackObjPackB', 0x4E), ('C6Scene_UnpackPalPackA', 0x4E),
                         ('C6Scene_UnpackPalPackB', 0x4E))},
        **{n: ({op}, (), (),
               'it builds a window table with the $C3 window routines (DP = DP_WinFx inside, restored): the '
               'table at WinFx_TablePtr/Bank ($7E:8B56, $8DF6, $9176 or $9416 in the traces) filled with MVNs '
               'inside that bank, the '
               'WinFx DP block, $7E:8A21-$8A27 (the HDMA table pointers) and the task\'s window state; none of '
               'DP $58-$5A, the return slot, the member words or the script buffer. It starts no script.')
           for n, op in (('C2Scene_Win1Step', 0x34), ('C2Scene_Win2Step', 0x34),
                         ('C6Scene_Win1EllipseStep', 0x4E), ('C6Scene_Win2EllipseStep', 0x4E),
                         ('C6Scene_Win1CapsuleStep', 0x4E), ('C6Scene_Win2CapsuleStep', 0x4E))},
        'C2Scene_ZoneSoundAtEntry': ({0x34}, (('Audio_SongCmdTable', 8, True),), (),
                                     'it picks the zone\'s song (C2Scene_GetSoundZone) and sends it through '
                                     'Audio_DriverCommand, which waits on the APU ports (not followed) and runs '
                                     'with DP = $1E00 (the command block, restored): it writes that block, the '
                                     'APU ports, the multiplier and $02AE; nothing of the scene task, its script '
                                     'or the buffer. It starts no script.'),
    },
    'fx': {
        'BattleCD_FxOpDrawShape': ({0x8B}, (('BattleCD_FxShapeTable', 6, True),
                                            ('BattleCE_CopyWordsToLines', 0, False)), ('BattleCE_CopyEntry',),
                                   'it reads its operand (the shape slot) and goes on in BattleCD_FxDrawShape, '
                                   'which jumps through BattleCD_FxShapeTable by the slot\'s kind (RAM). The '
                                   'shape builders and copies write DP $45-$52, !Battle_FxShapeSlot, the line '
                                   'buffers at $7E:B800-$B9FF, the two window tables and WMADD/WMDATA, as their '
                                   'Exits say; never DP $40-$42 (the pointer) or the return slot. So it is one '
                                   'operand byte, as its header says.'),
        'BattleCE_RunCopyWords': ({0xB5}, (('BattleCE_CopyWordsToLines', 0, False),), ('BattleCE_CopyEntry',),
                                  'BattleCD_FxCopyLines puts an entry of the unrolled BattleCE_CopyWordsToLines '
                                  'in BattleCE_CopyEntry (DP $4B) and calls this, whose JMP through it is not '
                                  'followed; the copy stores only the window table words at DB:X + 4n.'),
    },
}
CALL_VIA = {'C2Script_CallNear_call': 2, 'C2Script_CallLong_call': 3}   # target: the operand's 2 or 3 bytes


def trusted_by(lang: 'Lang', chain: tuple, known: dict, ptr: int) -> str | None:
    """The TRUST routine a callee not followed is inside, or None."""
    trust = {lang.labels[n]: n for n in TRUST[lang.name] if n in lang.labels}
    via = {lang.labels[n]: k for n, k in CALL_VIA.items() if n in lang.labels}
    if chain and chain[0] in via:
        b = [known.get(ptr + 1 + i) for i in range(via[chain[0]])]
        if None in b:
            return None
        return trust.get((b[2] if len(b) == 3 else 0xC2) << 16 | b[0] | b[1] << 8)
    for f in chain:
        if f in trust:
            return trust[f]
    return None


def _code_closure(lang: 'Lang', seeds: list[tuple[int, bool]]) -> list[tuple[int, str, str, int]]:
    """Every instruction reached from the seeds (address, M=1?) by direct
    flow, calls into other banks included: (address, mnemonic, mode,
    operand)."""
    import disasm
    ds: dict[int, disasm.Disassembler] = {}
    work, done = list(seeds), set()
    while work:
        a, m = work.pop()
        if (a, m) in done:
            continue
        done.add((a, m))
        d = ds.get(a >> 16)
        if d is None:
            d = ds[a >> 16] = disasm.Disassembler(lang.image, a >> 16)
        d.trace([a & 0xFFFF], disasm.CPUState(m=m, x=False, e=False))
        for at, (raw, mn, _, _) in list(d.insns.items()):
            if mn in ('JSL', 'JML') and len(raw) == 4:
                t = raw[1] | raw[2] << 8 | raw[3] << 16
                if t >> 16 != a >> 16:
                    work.append((t, d.visited[at].m))
    out = []
    for bank, d in ds.items():
        for at, (raw, mn, _, _) in d.insns.items():
            mode = disasm._OPCODES[raw[0]][1]
            out.append((bank << 16 | at, mn, mode, int.from_bytes(raw[1:], 'little')))
    return out


STORES = {'STA', 'STX', 'STY', 'STZ', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR', 'TSB', 'TRB'}


def trust_check(lang: 'Lang') -> list[str]:
    """The machine-checkable part of each TRUST reason (see there)."""
    out = []
    if lang.name == 'scene':
        guard = {lang.ptr + i & 0xFFFF for i in range(3)} | {a & 0xFFFF for s in lang.slots for a in (s, s + 1)}
        never = {lang.labels['C2Scene_TaskSpawnScript'], lang.labels['C2Scene_TaskSpawnScriptLow']}
    else:
        guard = ({lang.ptr + i & 0xFFFF for i in range(3)} | {lang.ret_slot & 0xFFFF, lang.ret_slot + 1 & 0xFFFF}
                 | {lang.chan + i & 0xFFFF for i in (0, 3, 4, 5)})
        never = set()
    for name, (_, tables, vectors, _) in TRUST[lang.name].items():
        seeds = [(lang.labels[name], True)]
        through = set()
        for t, n, m in tables:
            seeds += [(x, m) for x in (lang.table(t, n) if n else [lang.labels[t]])]
            if n:
                through.add(lang.labels[t] & 0xFFFF)
        vec = {lang.d[v] & 0xFFFF for v in vectors}
        for at, mn, mode, op in _code_closure(lang, seeds):
            where = f'{name}: ${at:06X} {mn}'
            if mode in ('abs_ind', 'abs_x_ind', 'abs_ind_long') and op not in through | vec:
                out.append(f'{where}: an indirect jump through ${op:04X}, not a table or vector its reason names')
            if (mn in STORES and mode in ('dp', 'abs') and op in guard
                    or mn in STORES and mode == 'long' and absint._wram(op) & 0xFFFF in guard
                    and absint._wram(op) >> 16 == 0x7E):
                out.append(f'{where} ${op:04X}: a store to the bytes it is trusted to leave alone')
            if mn in ('JSR', 'JSL', 'JMP', 'JML') and mode in ('abs', 'long') and (
                    (op if mode == 'long' else at & 0xFF0000 | op) in never):
                out.append(f'{where}: it can start a script')
    return out


def langs(root: Path = ROOT) -> tuple[SceneLang, FxLang]:
    scene, fx = SceneLang(root), FxLang(root)
    scene.load(root)
    fx.load(root)
    return scene, fx


def piece_index(label: str) -> int:
    return int(label.rsplit('_', 1)[1])


def _fx_disassembly(lang: FxLang, start: int, data: bytes) -> dict:
    head = lang.head()
    n, first = 0, None
    while first is None or start + 2 * n < first:
        t = (start & 0xFF0000) | data[2 * n] | data[2 * n + 1] << 8
        first = t if first is None else min(first, t)
        n += 1
    region = (start + 2 * n, start + len(data))
    tab = sorted({(start & 0xFF0000) | data[2 * k] | data[2 * k + 1] << 8 for k in range(n)} & set(range(*region)))
    known = {start + k: b for k, b in enumerate(data)}
    return disassemble(lang, known, [region], {t + head for t in tab}, {t: head for t in tab})


def extract_all(rom: bytes, pieces: list[dict], root: Path = ROOT, problems: list | None = None):
    """(piece, readable text) of every scene and fx piece, each checked to
    assemble back to its bytes; what fails goes to `problems`."""
    import extract_data
    problems = [] if problems is None else problems
    todo = [p for p in pieces if p['piece'] in ('scene', 'fx')]
    if not todo:
        return
    scene, fx = langs(root)
    pairs = scene_pairs(rom, root)
    try:
        for p in todo:
            try:
                if p['piece'] == 'scene':
                    data, why = extract_data.unpack_piece(rom, p)
                    if data is None:
                        problems.append(why)
                        continue
                    text = render_scene(scene, p['label'], data, scene_entries(pairs, piece_index(p['label']),
                                                                               len(data)))
                    back = assemble_scene(scene, text, p['label'], len(data),
                                          scene_entries(pairs, piece_index(p['label']), len(data)), p['label'])
                else:
                    data = rom[p['offset']:p['stop']]
                    text = render_fx(fx, p['label'], 0xC00000 + p['offset'], data)
                    back = assemble_fx(fx, text, p['label'], 0xC00000 + p['offset'], len(data))
            except ScriptsError as e:
                problems.append(f'{p["label"]}: {e}')
                continue
            if back != data:
                problems.append(f'{p["label"]}: does not assemble back to its bytes')
                continue
            yield p, text
    finally:
        scene.save(root)
        fx.save(root)


def assemble_piece(lang: Lang, text: str, p: dict, pairs: dict[int, bytes] | None = None) -> bytes:
    """A piece's bytes from its text; a scene's entries from `pairs`
    (scene_pairs_built when not given)."""
    import extract_data
    if p['piece'] == 'scene':
        size = int(extract_data.PACK_PARAM.match(p['param']).group(2))
        if pairs is None:
            pairs = scene_pairs_built(lang.root)
        return assemble_scene(lang, text, p['label'], size, scene_entries(pairs, piece_index(p['label']), size),
                              p['label'])
    return assemble_fx(lang, text, p['label'], 0xC00000 + p['offset'], int(p['size']), p['label'])


def exits_check(rom: bytes, pieces: list[dict], root: Path = ROOT) -> list[str]:
    import extract_data
    scene, fx = langs(root)
    pairs = scene_pairs(rom, root)
    got = {'scene': {k: set() for k in EXITS['scene']}, 'fx': {k: set() for k in EXITS['fx']}}
    trusted = {'scene': {}, 'fx': {}}
    for p in pieces:
        if p['piece'] == 'scene':
            data, _ = extract_data.unpack_piece(rom, p)
            known = {SCENE_BUF + k: b for k, b in enumerate(data)}
            d = disassemble(scene, known, [(SCENE_BUF, SCENE_BUF + len(data))],
                            scene_entries(pairs, piece_index(p['label']), len(data)))
            lang = 'scene'
        elif p['piece'] == 'fx':
            d = _fx_disassembly(fx, 0xC00000 + p['offset'], rom[p['offset']:p['stop']])
            lang = 'fx'
        else:
            continue
        for o in d['ops'].values():
            for k in got[lang]:
                if getattr(o, k):
                    got[lang][k].add(o.op)
            for t in o.trusted:
                trusted[lang].setdefault(t, set()).add(o.op)
    out = []
    for lang, want in TRUST.items():
        w = {n: v[0] for n, v in want.items()}
        if trusted[lang] != w:
            out.append(f'{lang}: the routines trusted (TRUST) are '
                       f'{ {n: sorted(map(hex, v)) for n, v in sorted(trusted[lang].items())} }, '
                       f'not { {n: sorted(map(hex, v)) for n, v in sorted(w.items())} }')
    out += trust_check(scene) + trust_check(fx)
    for lang, want in EXITS.items():
        for k, v in want.items():
            if got[lang][k] != v:
                out.append(f'{lang}: the opcodes classed {k} are {sorted(map(hex, got[lang][k]))}, '
                           f'not {sorted(map(hex, v))}')
    return out


def check(rom: bytes, root: Path = ROOT, quiet: bool = True) -> list[str]:
    import extract_data
    pieces = extract_data.read_manifest()
    problems = []
    n = 0
    for p, text in extract_all(rom, pieces, root, problems):
        n += 1
        if not quiet:
            st = stats(text)
            print(f'scripts: {p["label"]}: {st["lines"]:,} lines, {st["data"]:,} B nothing reaches')
    problems += exits_check(rom, pieces, root)
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    import extract_data
    try:
        problems = check(extract_data.read_rom(), quiet=False)
    except (ScriptsError, extract_data.DataError) as e:
        print(f'scripts: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'scripts: {p}', file=sys.stderr)
    if problems:
        return 1
    print('OK: every scene and layer-effect script disassembles and assembles back byte-exact, checked '
          'against its handlers')
    return 0


if __name__ == '__main__':
    sys.exit(main())
