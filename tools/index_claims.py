#!/usr/bin/env python3
"""
index_claims.py — The lint's INDEX rule: an Exit claim that X or Y is kept
must survive the X flag.

A header Exit line that says X or Y is unchanged (kept, preserved, intact,
untouched, restored, as on entry, ...) is false for a caller that enters
with X=0 (16-bit index registers) when some path through the routine, or
through a routine it calls, sets the X flag (SEP #$10/#$30, a PLP restoring
X=1, a callee that returns with X=1) and does not bring the register back at
16 bits: the high byte is zeroed. This rule finds those claims. It does not
check value changes (an INY, a TAY): only the high byte lost to the X flag.

How (needs the ROM and asar, through tools/xref.py):

  * Each routine is decoded from its label under the M/X entry states whose
    instructions all fall on the source's instruction lines (asar's
    address-to-line map, as tools/xref.py validates start states), and
    consistent with the M and X its Entry line declares. An Entry line that
    declares X=1 is analysed with X=1, where nothing can be lost.
  * Paths are followed through branches, JMP/JML/BRL, fall-through into the
    next label, and JMP (a,X) through a matched word table. JSR, JSL and
    JSR (a,X) through a matched table are summarised recursively (per entry
    width) and composed at the call site.
  * Each byte of A, X and Y carries a tag: which entry byte it still holds,
    'Z' (zeroed by the X flag), None (anything else) or '?' (not followed).
    PHA/PHX/PHY and PLA/PLX/PLY carry the tags, so a save and restore at 16
    bits brings the high byte back, and one done at 8 bits does not. PLP
    restores the flags, not the bytes. Transfers (TAX, TXY, ...), loads and
    stores of a fixed address (dp/abs/long) and LDA/STA d,S carry tags too.
  * Code it cannot follow gives no finding: JMP (a)/(a,X) through an
    unmatched table, TCS/TXS (thread switches), RTI, XCE, a pull past the
    routine's own frame (return-address tricks), recursion.

What counts as a claim, and what qualifies it (then no finding):

  * The Exit paragraph (the Exit line and the lines continuing it). A list
    of registers before the verb ("A, X and Y unchanged", "X/Y kept"); "X"
    is the flag, not the register, when the same list names M or P ("M=1,
    X, DP and DB unchanged").
  * Wording that already says what happens to the bytes: the register
    named with "low byte"/"high byte" ("Y's low byte kept, high byte
    cleared"), or an X=1 qualifier ("with X=1 at entry", "X=1 callers
    only").
  * A claim limited to some paths ("..., else X unchanged", "Y unchanged on
    the bit-7 path", "no bit: X unchanged") is reported only when no exit
    keeps the register whole.

A finding names the SEP (or PLP) site and the chain of calls to it.

Only the routines whose headers make such a claim are analysed (with
their callees), which takes a few seconds; the findings are cached in
build/index_lint.json under a hash of asm/, the ROM and the analysing tools,
so a run on an unchanged tree skips it. tools/lint_readability.py runs this
rule wherever it has the ROM and asar (the pre-commit and pre-push hooks,
make gate, CI's ROM job), like CALLERS.

    python3 tools/index_claims.py              findings (cached)
    python3 tools/index_claims.py --no-cache   recompute
    python3 tools/index_claims.py --explain NAME   what it concluded for one routine
"""

import argparse
import bisect
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asm_source  # noqa: E402

sys.setrecursionlimit(max(sys.getrecursionlimit(), 20000))

CACHE = Path('build/index_lint.json')
CACHE_VERSION = 1
TOOLS = ('index_claims.py', 'xref.py', 'disasm.py', 'asm_source.py', 'generated.py')

# ── Per-byte register tracking ───────────────────────────────────────────────

REG = ('A0', 'A1', 'X0', 'X1', 'Y0', 'Y1')
A0, A1, X0, X1, Y0, Y1 = range(6)
BUDGET = 20000        # states per routine walk
MAXSTACK = 40         # bytes pushed in one frame
MAXEXITS = 24         # distinct exit shapes kept per entry width
MAXDEPTH = 400        # nested summaries

COND = {0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0}
ALU_A = {'LDA', 'ADC', 'SBC', 'AND', 'ORA', 'EOR'}
SHIFT = {'ASL', 'LSR', 'ROL', 'ROR', 'INC', 'DEC'}
RMW_MEM = SHIFT | {'TSB', 'TRB'}
DIRECT = ('dp', 'abs', 'long')
STATES = ((True, False), (False, False), (True, True), (False, True))


def why_str(w) -> str:
    """A reason chain (nested (call, reason) tuples) as 'JSR A at .. -> SEP .. in B'."""
    parts = []
    while isinstance(w, tuple):
        parts.append(w[0])
        w = w[1]
    if w:
        parts.append(w)
    return ' -> '.join(parts)


class Summary:
    """What a routine entered with (M, X) does to A, X and Y.

    exits: {(M, X) at the return: {tags: reasons}}, one entry per distinct
    shape of the six byte tags. bad: the decode under this entry state leaves
    the source's instruction lines (the state is not a real entry state).
    unk: why some path could not be followed."""
    __slots__ = ('exits', 'unk', 'memw', 'bad')

    def __init__(self):
        self.exits = {}
        self.unk = []
        self.memw = set()
        self.bad = None

    def note(self, reason):
        if len(self.unk) < 30 and reason not in self.unk:
            self.unk.append(reason)

    def add_exit(self, mx, regs, whys):
        d = self.exits.setdefault(mx, {})
        t = tuple(regs)
        if t in d:
            return
        if len(d) < MAXEXITS:
            d[t] = tuple(whys)
            return
        # Too many shapes: fold into the last one; a byte that differs
        # becomes the non-entry tag (never a false 'kept').
        last = list(d)[-1]
        lw = list(d.pop(last))
        nt = list(last)
        for i in range(6):
            if nt[i] != t[i] and (nt[i] in REG or nt[i] == '?'):
                nt[i], lw[i] = (t[i] if t[i] not in REG else None), (whys[i] or lw[i])
        d[tuple(nt)] = tuple(lw)


class Analyzer:
    """Register-byte summaries over the ROM, from a tools/xref.py Xref."""

    def __init__(self, xr):
        from disasm import _OPCODES
        import xref
        self.xr = xr
        self.rom = xr.rom
        self.ops = _OPCODES
        self.lens = xref._LEN
        self.fmt = xref.fmt
        self.to_offset = xref.to_offset
        self.memo = {}
        self.busy = set()
        self.bounds = sorted(xr.boundaries)
        self.row_by_name = {n: (s, e) for s, e, n in xr.rows}

    # ── helpers ──
    def label(self, o):
        return self.xr.name_at(o) or self.fmt(o)

    def next_boundary(self, o):
        i = bisect.bisect_right(self.bounds, o)
        return self.bounds[i] if i < len(self.bounds) else None

    def is_table(self, start):
        b = self.xr.boundaries.get(start)
        return b is not None and not b[2]

    def entry_states(self, start):
        """The (M, X) entry states whose decode stays on the source lines."""
        return [(m, x) for m, x in STATES if not self.summarize(start, m, x).bad]

    def summarize(self, target, m, x) -> Summary:
        key = (target, m, x)
        if key in self.memo:
            return self.memo[key]
        if key in self.busy or len(self.busy) > MAXDEPTH:
            s = Summary()
            s.note(f'recursion into {self.label(target)}' if key in self.busy else 'call depth')
            return s
        self.busy.add(key)
        s = Summary()
        try:
            self._walk(s, target, m, x)
        finally:
            self.busy.discard(key)
        self.memo[key] = s
        return s

    # ── the walk ──
    def _walk(self, s, start, m0, x0):
        xr, rom, fmt = self.xr, self.rom, self.fmt
        regs0 = ('A0', 'A1', 'X0', 'Z' if x0 else 'X1', 'Y0', 'Z' if x0 else 'Y1')
        work = [(start, m0, x0, (), regs0, (), (None,) * 6, False)]
        seen = set()
        while work:
            o, m, x, stk, regs, mem, whys, amb = work.pop()
            key = (o, m, x, stk, regs, mem)
            if key in seen:
                continue
            if len(seen) > BUDGET:
                s.note(f'state budget exceeded in {self.label(start)}')
                return
            seen.add(key)
            if o is None or o >= len(rom):
                s.note('jump outside ROM')
                continue
            row = xr.routine_at(o)
            b = xr.boundaries.get(o)
            if row and not (b and b[2]):
                if amb:
                    continue    # a callee exit width this path cannot have had
                s.bad = s.bad or f'decode under M={int(m)} X={int(x)} reaches {fmt(o)} off the source lines'
                return
            op = rom[o]
            mn, mode = self.ops[op]
            ln = self.lens[(m, x)][op]
            end = o + ln
            if (end - 1) >> 16 != o >> 16:
                s.note(f'runs off bank at {fmt(o)}')
                continue
            if row:
                nb = self.next_boundary(o)
                if nb is not None and (end > nb or (end < nb and xr.routine_at(end))):
                    if amb:
                        continue
                    s.bad = s.bad or (f'decode under M={int(m)} X={int(x)}: instruction at '
                                      f'{fmt(o)} ends inside another')
                    return
            bank = o & ~0xFFFF
            opnd = int.from_bytes(rom[o + 1:end], 'little') if ln > 1 else 0
            regs, whys, stk, memd = list(regs), list(whys), list(stk), dict(mem)
            where = f'{fmt(o)} in {row or "unmatched code"}'

            def setr(i, tag, why):
                if tag == 'Z' and regs[i] == 'Z':
                    return          # still zero: keep the reason it was zeroed
                regs[i] = tag
                whys[i] = None if tag == REG[i] else why

            def x_set(why):
                for i in (X1, Y1):
                    if regs[i] != 'Z':
                        setr(i, 'Z', why)

            def pop(n):
                if len(stk) < n:
                    return None
                return [stk.pop() for _ in range(n)]

            def store(cls, addr, tags):
                for k, t in enumerate(tags):
                    if t in REG:
                        memd[(cls, addr + k)] = t
                    else:
                        memd.pop((cls, addr + k), None)
                    s.memw.add((cls, addr + k))

            def load(cls, addr, n):
                return [memd.get((cls, addr + k)) for k in range(n)]

            nexts, falls, abort, exit_here = [], True, None, False
            nm, nx = m, x
            why = f'{mn} at {where}'

            if op == 0xE2:                                    # SEP
                nm, nx = m or bool(opnd & 0x20), x or bool(opnd & 0x10)
                if nx and not x:
                    x_set(f'SEP #${opnd:02X} at {where}')
            elif op == 0xC2:                                  # REP
                nm, nx = m and not opnd & 0x20, x and not opnd & 0x10
            elif op == 0x08:                                  # PHP
                stk.append(('P', m, x))
            elif op == 0x28:                                  # PLP
                p = pop(1)
                if not p or not isinstance(p[0], tuple):
                    abort = f'PLP of a P not pushed in this frame at {where}'
                else:
                    _, nm, nx = p[0]
                    if nx and not x:
                        x_set(f'PLP (restoring X=1) at {where}')
            elif op in (0x48, 0xDA, 0x5A):                    # PHA PHX PHY
                base, wide = {0x48: (A0, not m), 0xDA: (X0, not x), 0x5A: (Y0, not x)}[op]
                stk.extend((regs[base + 1], regs[base]) if wide else (regs[base],))
            elif op in (0x68, 0xFA, 0x7A):                    # PLA PLX PLY
                base, wide = {0x68: (A0, not m), 0xFA: (X0, not x), 0x7A: (Y0, not x)}[op]
                p = pop(2 if wide else 1)
                if p is None:
                    abort = f'{mn} pulls past the routine\'s own stack frame at {where}'
                else:
                    setr(base, p[0] if not isinstance(p[0], tuple) else None, why)
                    if wide:
                        setr(base + 1, p[1] if not isinstance(p[1], tuple) else None, why)
                    elif base != A0:
                        setr(base + 1, 'Z', why)
            elif op in (0x8B, 0x4B):                          # PHB PHK
                stk.append(None)
            elif op in (0x0B, 0xF4, 0xD4, 0x62):              # PHD PEA PEI PER
                stk.extend((None, None))
            elif op in (0xAB, 0x2B):                          # PLB PLD
                if pop(1 if op == 0xAB else 2) is None:
                    abort = f'{mn} pulls past the routine\'s own stack frame at {where}'
            elif op in (0x1B, 0x9A, 0xFB, 0x00, 0x02, 0xDB, 0x42, 0x40):
                abort = f'{mn} at {where}'                    # TCS TXS XCE BRK COP STP WDM RTI
            elif op in (0xAA, 0xA8):                          # TAX TAY
                base = X0 if op == 0xAA else Y0
                setr(base, regs[A0], why)
                setr(base + 1, 'Z' if x else regs[A1], why)
            elif op in (0x8A, 0x98):                          # TXA TYA
                src = X0 if op == 0x8A else Y0
                setr(A0, regs[src], why)
                if not m:
                    setr(A1, regs[src + 1], why)
            elif op in (0x9B, 0xBB):                          # TXY TYX
                src, dst = (X0, Y0) if op == 0x9B else (Y0, X0)
                setr(dst, regs[src], why)
                setr(dst + 1, 'Z' if x else regs[src + 1], why)
            elif op == 0xEB:                                  # XBA
                regs[A0], regs[A1] = regs[A1], regs[A0]
                whys[A0], whys[A1] = whys[A1], whys[A0]
            elif op in (0x7B, 0x3B):                          # TDC TSC
                setr(A0, None, why)
                setr(A1, None, why)
            elif op == 0xBA:                                  # TSX
                setr(X0, None, why)
                setr(X1, 'Z' if x else None, why)
            elif op in (0x54, 0x44):                          # MVN MVP
                for i in range(6):
                    setr(i, 'Z' if x and i in (X1, Y1) else None, why)
            elif mn in ('LDX', 'LDY', 'INX', 'INY', 'DEX', 'DEY'):
                base = X0 if mn[-1] == 'X' else Y0
                t = load(mode, opnd, 1 if x else 2) if mode in DIRECT and mn[:2] == 'LD' else [None, None]
                setr(base, t[0], why)
                setr(base + 1, 'Z' if x else t[1], why)
            elif mn in ('STA', 'STX', 'STY', 'STZ') and mode in DIRECT:
                src = {'STA': A0, 'STX': X0, 'STY': Y0}.get(mn)
                wide = (not m) if mn in ('STA', 'STZ') else (not x)
                tags = [None, None] if src is None else [regs[src], regs[src + 1]]
                store(mode, opnd, tags[:2 if wide else 1])
            elif op == 0x83:                                  # STA d,S
                for k, t in enumerate([regs[A0]] + ([] if m else [regs[A1]])):
                    i = len(stk) - (opnd + k)
                    if 0 <= i < len(stk):
                        stk[i] = t
            elif op == 0xA3:                                  # LDA d,S
                vals = []
                for k in range(1 if m else 2):
                    i = len(stk) - (opnd + k)
                    v = stk[i] if 0 <= i < len(stk) else None
                    vals.append(None if isinstance(v, tuple) else v)
                setr(A0, vals[0], why)
                if not m:
                    setr(A1, vals[1], why)
            elif mn in ALU_A or (mn in SHIFT and mode == 'A'):
                t = load(mode, opnd, 1 if m else 2) if mn == 'LDA' and mode in DIRECT else [None, None]
                setr(A0, t[0], why)
                if not m:
                    setr(A1, t[1], why)
            elif mn in RMW_MEM and mode in DIRECT:
                for k in range(1 if m else 2):
                    memd.pop((mode, opnd + k), None)
                    s.memw.add((mode, opnd + k))

            # Control flow.
            if op in COND or op == 0x80:
                rel = rom[o + 1] - (256 if rom[o + 1] >= 128 else 0)
                nexts.append(bank | (end + rel) & 0xFFFF)
                falls = op != 0x80
            elif op == 0x82:                                  # BRL
                nexts.append(bank | (end + opnd) & 0xFFFF)
                falls = False
            elif op == 0x4C:                                  # JMP abs
                nexts.append(bank | opnd)
                falls = False
            elif op == 0x5C:                                  # JML
                t = self.to_offset(opnd >> 16, opnd & 0xFFFF)
                if t is None:
                    abort = f'JML to non-ROM at {where}'
                nexts.append(t)
                falls = False
            elif op == 0x7C:                                  # JMP (a,X)
                tg = xr._table_targets(bank | opnd)
                if not tg:
                    abort = f'JMP (${opnd:04X},X) through an unknown table at {where}'
                nexts.extend(tg)
                falls = False
            elif op in (0x6C, 0xDC):                          # JMP (a), JML [a]
                abort = f'{mn} indirect at {where}'
            elif op in (0x60, 0x6B):                          # RTS RTL
                falls, exit_here = False, True

            if abort:
                s.note(abort)
                continue
            if len(stk) > MAXSTACK:
                s.note(f'stack deeper than {MAXSTACK} at {where}')
                continue
            frozen = tuple(sorted(memd.items()))
            if exit_here:
                if stk:
                    s.note(f'{mn} at {where} with {len(stk)} byte(s) still pushed')
                else:
                    s.add_exit((nm, nx), regs, whys)
                continue
            for t in nexts:
                work.append((t, nm, nx, tuple(stk), tuple(regs), frozen, tuple(whys), amb))
            if not falls:
                continue

            calls = ()
            if op == 0x20:
                calls = ((bank | opnd, 'JSR'),)
            elif op == 0x22:
                calls = ((self.to_offset(opnd >> 16, opnd & 0xFFFF), 'JSL'),)
            elif op == 0xFC:
                calls = tuple((t, 'JSR') for t in xr._table_targets(bank | opnd)) or ((None, 'JSR'),)
            if not calls:
                work.append((end, nm, nx, tuple(stk), tuple(regs), frozen, tuple(whys), amb))
                continue

            cont = []
            for t, kind in calls:
                if t is None:
                    s.note(f'{kind} to an unknown target at {where}')
                    cont.append((nm, nx, ['?'] * 6, [f'unknown call target at {where}'] * 6))
                    continue
                cs = self.summarize(t, nm, nx)
                if cs.bad:
                    continue        # this width cannot reach the callee: infeasible path
                pre = f'{kind} {self.label(t)} at {fmt(o)}'
                if cs.unk:
                    s.note((pre, cs.unk[0]))
                for k in cs.memw:
                    memd.pop(k, None)
                s.memw |= cs.memw
                if not cs.exits and cs.unk:
                    cont.append((nm, nx, ['?'] * 6, [(pre, cs.unk[0])] * 6))
                for (em, ex), shapes in cs.exits.items():
                    for cregs, cwhys in shapes.items():
                        nr, nw = [], []
                        for i in range(6):
                            tg = cregs[i]
                            if nx and i in (X1, Y1) and tg == 'Z' and regs[i] == 'Z':
                                nr.append(regs[i])      # entered with X=1: already zero
                                nw.append(whys[i])
                            elif tg in REG:
                                j = REG.index(tg)
                                nr.append(regs[j])
                                nw.append(whys[j])
                            else:
                                nr.append(tg)
                                nw.append((pre, cwhys[i]))
                        if ex and not nx:
                            for i in (X1, Y1):
                                if nr[i] != 'Z':
                                    nr[i], nw[i] = 'Z', (pre, 'returns with X=1')
                        cont.append((em, ex, nr, nw))
            frozen = tuple(sorted(memd.items()))
            namb = amb or len({(c[0], c[1]) for c in cont}) > 1
            for em, ex, nr, nw in cont:
                work.append((end, em, ex, tuple(stk), tuple(nr), frozen, tuple(nw), namb))


# ── Claims in the header ─────────────────────────────────────────────────────

VERB = (r'(?:unchanged|kept|preserved|intact|untouched|unaffected|not touched|not modified'
        r'|saved and restored|restored|as on entry|as passed|as given)')
EXIT = re.compile(r'^\s*(?:On exit|Exit|Entry/Exit|Exit/Entry)\b[^:]{0,60}:', re.I)
ENTRY = re.compile(r'^\s*(?:On entry|Entry(?:/Exit)?)\b[^:]{0,60}:', re.I)
SECTION = re.compile(r'^\s*(?:Callers|On entry|Entry|Notes?|Calls|Callees?|Uses|Inputs?|Outputs?'
                     r'|Effects?|Side effects|Clobbers|Called|Reached|See|Size|Quirk|Why'
                     r'|Inferred|Stack|Returns|Format|Layout|Table|Data)\b[^:]{0,30}:')
STOP = re.compile(r'^\s*(?:=+|-{3,}|~{3,})\s*$')
REGTOK = re.compile(r'^(?:A|B|C|X|Y|M|P|D|DP|DB|S|DBR|flags|X/Y|Y/X|A/X/Y|X/Y/A|A/X|A/Y'
                    r'|[MX]=[01]|(?:the |both )?index registers)$', re.I)
# A claim limited to some paths or conditions.
CONDITION = re.compile(r'\b(?:unless|when|whenever|otherwise|else|if|for the|without|on the'
                       r'|on later|on a|on an|except)\b|^[^:]{1,40}:\s', re.I)
ELSE_KEPT = re.compile(r'(?<![\w/=])([XY])\s*=\s*[^;=]{1,80}?[,(]\s*(?:or\s+)?(?:else|otherwise)\s+' + VERB,
                       re.I)
X1_QUALIFIER = re.compile(r'\b(?:with|for|when|if)\s+X\s*=\s*1\b|\bX\s*=\s*1\s+(?:at|on)\s+entry\b'
                          r'|\bX\s*=\s*1\s+callers?\b|\bX\s*=\s*1\b[^;.]{0,20}\bonly\b', re.I)


def exit_paragraphs(region):
    """[(line index in the file, text)] for each Exit paragraph of the header."""
    out, cur = [], None
    generated = set(asm_source.callers_block_lines(region))
    for n, line in enumerate(region.header_lines, region.start):
        if n in generated:
            continue
        idx = line.find(';')
        if idx < 0:
            cur = None
            continue
        c = line[idx + 1:]
        if EXIT.match(c):
            cur = [n, [c.strip()], [n]]
            out.append(cur)
            continue
        if cur is not None:
            if not c.strip() or STOP.match(c) or SECTION.match(c):
                cur = None
                continue
            cur[1].append(c.strip())
            cur[2].append(n)
    return [(first, ' '.join(text), lines) for first, text, lines in out]


def claims(text):
    """[(registers, clause, conditional)] for the clauses saying X and/or Y
    is kept. conditional: a condition comes before the claim in its clause
    ("else X unchanged", "no bit: X unchanged") or right after it, before
    the next comma ("Y unchanged on the bit-7 path", "X unchanged if ...");
    not one attached to an alternative ("Y as on entry, or 0 when ...")."""
    res = []
    # "Y = <value> when ... (else unchanged)": the register is the subject.
    for m in ELSE_KEPT.finditer(text):
        res.append(({m.group(1)}, m.group(0).strip(' ,;('), True))
    flat = re.sub(r'\([^()]*\)', '', re.sub(r'\([^()]*\)', '', text))
    pieces = re.split(r';|\.\s', flat)
    for inner in re.findall(r'\(([^()]*)\)', text):
        pieces += inner.split(';')
    for clause in pieces:
        for m in re.finditer(r'\s+(?:(?:are|is|also|all|both)\s+)*' + VERB, clause, re.I):
            if re.match(r'\s*restored\s+(?:from|to)', clause[m.start():m.end() + 6], re.I):
                continue
            toks = re.split(r'\s*,\s*|\s+and\s+|\s+', clause[:m.start()].strip())
            regs = []
            for tok in reversed(toks):
                if not tok:
                    continue
                if not REGTOK.match(tok):
                    break
                regs.append(tok.upper())
            if not regs:
                continue
            flag_list = any(r in ('M', 'P') or r.startswith('M=') for r in regs)
            got = set()
            for r in regs:
                if r == 'Y' or (r == 'X' and not flag_list):
                    got.add(r)
                elif '/' in r:
                    got |= {p for p in r.split('/') if p in ('X', 'Y')}
                elif 'INDEX' in r:
                    got |= {'X', 'Y'}
            if got:
                after = clause[m.end():].split(',')[0]
                cond = bool(CONDITION.search(clause[:m.start()]) or CONDITION.search(after))
                res.append((got, clause.strip(), cond))
    return res


def byte_qualified(text, reg):
    """The paragraph already says what happens to reg's bytes."""
    return bool(re.search(rf"\b{reg}\b[^;.]{{0,40}}\b(?:low|high) bytes?\b", text)
                or re.search(rf"\b(?:low|high) bytes? of (?:\w+ ){{0,3}}{reg}\b", text)
                or re.search(r"index registers'? (?:low|high) bytes?", text, re.I))


def entry_text(region):
    lines = region.header_comments(hand_written=True)
    out, on = [], False
    for c in lines:
        if ENTRY.match(c):
            on = True
            out.append(re.split(r'\bExit\b', c)[0] if c.strip().lower().startswith('entry/exit') else c)
            continue
        if on:
            if not c.strip() or EXIT.match(c) or SECTION.match(c) or STOP.match(c):
                on = False
                continue
            out.append(c)
    return ' '.join(s.strip() for s in out)


def entry_width(text, flag):
    """True (8-bit), False (16-bit) or None: the width the Entry text declares."""
    if flag == 'X':
        if re.search(r'\bX\s*(?:any|=\s*any|either|0 or 1|1 or 0)|\bM,\s*X any\b', text, re.I):
            return None
        zero = re.search(r'\bX\s*=\s*0|X/Y\s*(?:=\s*)?16|16-bit X|16-bit index|X 16-bit|X\s*16\b', text)
        one = re.search(r'\bX\s*=\s*1|X/Y\s*(?:=\s*)?8\b|X/Y 8-bit|8-bit X|8-bit index|X 8-bit', text)
    else:
        if re.search(r'\bM\s*(?:any|=\s*any|either|0 or 1|1 or 0)|\bM,\s*X any\b', text, re.I):
            return None
        zero = re.search(r'\bM\s*=\s*0|16-bit A|A 16-bit', text)
        one = re.search(r'\bM\s*=\s*1|8-bit A|A 8-bit', text)
    if zero and not one:
        return False
    if one and not zero:
        return True
    return None


def judge(an, start, states, reg):
    """(loss reason or None, some exit keeps reg whole) over the entry states."""
    lo, hi = REG.index(reg + '0'), REG.index(reg + '1')
    loss, keeps = None, False
    for m, x in states:
        sm = an.summarize(start, m, x)
        for shapes in sm.exits.values():
            for tags, whys in shapes.items():
                tlo, thi = tags[lo], tags[hi]
                if tlo == reg + '0' and thi == 'Z':
                    if loss is None:
                        loss = why_str(whys[hi])
                elif tlo in (reg + '0', '?') and thi in (reg + '1', '?'):
                    keeps = True
        if sm.unk:
            keeps = True        # a path not followed may keep it
    return loss, keeps


def routine_findings(an, region, explain=None):
    """[(line index, text)] of INDEX findings for one routine's header."""
    if region.name not in an.row_by_name:
        return []
    start = an.row_by_name[region.name][0]
    if an.is_table(start):
        return []
    paras = exit_paragraphs(region)
    found = [(first, text, lines, claims(EXIT.sub('', text, count=1)))
             for first, text, lines in paras]
    found = [f for f in found if f[3]]
    if not found:
        return []
    ent = entry_text(region)
    if entry_width(ent, 'X') is True:
        if explain:
            explain('Entry line declares X=1: nothing to lose')
        return []
    em = entry_width(ent, 'M')
    states = [(m, x) for m, x in an.entry_states(start) if not x]
    if em is not None and any(m == em for m, _ in states):
        states = [(m, x) for m, x in states if m == em]
    if not states:
        if explain:
            explain('no X=0 entry state decodes on the source lines')
        return []
    out = []
    for first, text, lines, cl in found:
        if any(re.search(r'lint-ok:\s*\S', region.lines[n]) for n in lines + [region.label]):
            continue
        if X1_QUALIFIER.search(text):
            if explain:
                explain(f'X=1 qualifier in: {text}')
            continue
        for reg in ('X', 'Y'):
            mine = [(c, cond) for regs, c, cond in cl if reg in regs]
            if not mine:
                continue
            if byte_qualified(text, reg):
                if explain:
                    explain(f'{reg}: the paragraph names its low/high byte')
                continue
            loss, keeps = judge(an, start, states, reg)
            conditional = all(cond for _, cond in mine)
            if explain:
                explain(f'{reg}: claim {mine!r}; loss: {loss}; some exit keeps it: {keeps}; '
                        f'conditional: {conditional}; states {states}')
            if loss is None or (conditional and keeps):
                continue
            out.append((first, f'{region.name}: the Exit line says {reg} is kept ("{mine[0][0]}"), '
                               f'but with X=0 at entry its high byte is cleared by {loss}'))
    return out


def analyze(xr, regions=None, explain_name=None):
    """INDEX findings for every routine: [(path, function, line number, text)]."""
    regions = regions if regions is not None else asm_source.regions()
    an = Analyzer(xr)
    out = []
    order = sorted((an.row_by_name[n][0], n) for n in regions if n in an.row_by_name)
    for _, name in order:
        r = regions[name]
        explain = (lambda s: print(f'  {s}')) if name == explain_name else None
        for line, text in routine_findings(an, r, explain):
            out.append((r.file, name, line + 1, text))
    return out


# ── Cache ────────────────────────────────────────────────────────────────────

def cache_key() -> str:
    h = hashlib.sha256(f'index v{CACHE_VERSION}\0'.encode())
    tools = Path(__file__).resolve().parent
    files = sorted(p for p in Path('asm').rglob('*') if p.is_file())
    files += [tools / t for t in TOOLS]
    for p in files:
        h.update(str(p.name if p.is_absolute() else p).encode() + b'\0')
        h.update(hashlib.sha256(p.read_bytes()).digest())
    rom = Path('roms/chrono_trigger.sfc')
    if rom.exists():
        h.update(b'rom\0' + hashlib.sha256(rom.read_bytes()).digest())
    return h.hexdigest()


def findings(get_xref, use_cache=True):
    """INDEX findings, from build/index_lint.json when the source is unchanged.
    get_xref() builds (or returns) the Xref; it is only called on a miss.
    None when the ROM or asar is missing."""
    key = cache_key()
    if use_cache and CACHE.exists():
        try:
            data = json.loads(CACHE.read_text())
            if data.get('key') == key:
                return [tuple(f) for f in data['findings']]
        except (OSError, ValueError, KeyError):
            pass
    xr = get_xref()
    if xr is None:
        return None
    res = analyze(xr)
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps({'key': key, 'findings': res}, indent=1) + '\n')
    except OSError:
        pass
    return res


def _default_xref():
    import shutil
    import generated
    if not (generated.can_generate() and shutil.which('asar')):
        return None
    generated.ensure()
    import xref
    return xref.Xref()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--no-cache', action='store_true')
    ap.add_argument('--explain', metavar='NAME')
    args = ap.parse_args()
    if args.explain:
        xr = _default_xref()
        if xr is None:
            print('needs roms/chrono_trigger.sfc and asar')
            return 2
        regs = asm_source.regions()
        if args.explain not in regs:
            print(f'no routine {args.explain}')
            return 2
        print(args.explain)
        for path, fn, no, text in analyze(xr, {args.explain: regs[args.explain]}, args.explain):
            print(f'{path}:{no}: INDEX: {text}')
        return 0
    res = findings(_default_xref, use_cache=not args.no_cache)
    if res is None:
        print('INDEX: skipped (needs roms/chrono_trigger.sfc and asar)')
        return 0
    for path, fn, no, text in res:
        print(f'{path}:{no}: INDEX: {text}')
    print(f'INDEX: {len(res)} finding(s)')
    return 1 if res else 0


if __name__ == '__main__':
    sys.exit(main())
