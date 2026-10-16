#!/usr/bin/env python3
"""
events.py — The location event scripts (Evt_PackPtrs) as a readable
disassembly, extracted from your own ROM into the ignored
build/assets/events/, and an assembler that rebuilds the exact unpacked
bytes, which tools/build_rom.py then packs (DATA_PLAN.md, step 7).

No script is ever committed (README, "Legal"); this tool holds only how
the interpreter reads them, and takes even that from the matched source:

  * The opcode table is Evt_OpcodeTable, read from an assembly of
    asm/main.asm (not from the ROM): each opcode's handler and its name.
  * Each opcode's operand bytes and where the script goes on are what the
    handler itself does with the bytes it is given: tools/absint.py runs
    the handler's assembled code with Y = the opcode's offset and the
    script bytes in Evt_Data ($7F:2001) known, everything else unknown,
    following both ways of every branch on an unknown value. Its operands
    are the script bytes it reads after the opcode (a block move's source
    included: opcode $4E's inline data); every way it returns gives X, the
    next opcode, which is classed as:
      next   the opcode after the operands (X = Y + length, not computed
             from a script byte),
      stay   the same opcode again (X = Y: a wait or retry),
      jump   a position computed from an operand byte (a jump; its
             encoding, which byte and how, is found by changing that byte),
      end    an unknown X (opcode $00 returns to a saved position).
    A handler that cannot be followed that way (an X that is unknown on a
    path that is not opcode $00, a jump that is not a function of one
    operand) makes its script unresolved: the script stays a raw block.

The data of a pack (unpacked to Evt_ObjCount, $7F:2000): the object count,
then 16 function offsets per object (Evt_Data + object x 32), then the
scripts. Entry points are every function offset and, after each object's
function 0, the opcode after the $00 it stops at (Evt_RunObjInit: where
the object's script goes on). Opcodes reached from those through next and
jump are code; bytes never reached are data, kept as bytes.

The readable form, one file per pack (build/assets/events/<label>.evt):

  ; comments
  @objects N
  @func O F LABEL           function F of object O starts at LABEL
  @jump NAME I S C          opcode NAME's jump: operand byte I, the
                            target is (opcode's offset + C) + S x byte
  LABEL:                    a label (the opcode or data after it)
      Op12_IfVarByte $05 $01 $00 ->L_0040
                            an opcode by its handler's name and its
                            operand bytes; ->LABEL for a jump operand;
                            OpB8_SetMsgPtr alone takes a data label
                            (LABEL or LABEL+$off) for its pointer. The
                            assembler checks each line's length against
                            the handler (see assemble())
  @bytes 01 02 ...          bytes no opcode reaches (data)

    python3 tools/events.py check      disassemble every event pack afresh
                                       and assemble it back, every opcode
                                       line checked against its handler:
                                       byte-exact, and no non-empty pack
                                       left as bytes?
"""

import argparse
import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import absint  # noqa: E402

CODE_DIR = Path('build/events')                 # the code image cache (relative to the root)
EVT_COUNT = 0x7F2000                            # Evt_ObjCount: where a pack unpacks
EVT_DATA = 0x7F2001                             # Evt_Data: offsets are relative to it
FUNCS = 16                                      # function offsets per object
ENTRY_DP = 0x0100                               # handlers run with DP = $0100
ROM_SIZE = 0x400000


class EventsError(Exception):
    pass


# ── The interpreter, from the source ────────────────────────────────────────

def _asm_hash(root: Path) -> str:
    h = hashlib.sha256()
    for p in sorted((root / 'asm').rglob('*')):
        if p.is_file() and p.suffix in ('.asm', '.inc') and 'data' not in p.relative_to(root / 'asm').parts[:1]:
            h.update(str(p.relative_to(root)).encode())
            h.update(p.read_bytes())
    return h.hexdigest()


def code_image(root: Path = ROOT) -> tuple[bytes, bytearray, dict[str, int]]:
    """(image, emitted mask, {label: SNES address}) of asm/main.asm
    assembled onto blank images (cached in build/events/ by a hash of
    asm/)."""
    import c3pack
    root = Path(root)
    cache = root / CODE_DIR
    key = _asm_hash(root)
    files = [cache / n for n in ('code.bin', 'code.mask', 'code.sym', 'code.key')]

    def stamp(image: bytes, mask: bytes, sym: str) -> str:
        # the asm/ hash, then the sha256 of what was written: a cached image
        # changed by hand no longer matches and is assembled again
        return key + ' ' + hashlib.sha256(image + b'\0' + mask + b'\0' + sym.encode()).hexdigest()

    cached = all(f.exists() for f in files)
    if cached:
        image, mask, sym = files[0].read_bytes(), bytearray(files[1].read_bytes()), files[2].read_text()
        cached = files[3].read_text() == stamp(image, bytes(mask), sym)
    if not cached:
        cwd = os.getcwd()
        os.chdir(root)
        try:
            c3pack.ensure_built(Path('.'))
            images = []
            with tempfile.TemporaryDirectory() as tmp:
                for fill in (0x00, 0xFF):
                    out, symf = Path(tmp) / f'{fill}.sfc', Path(tmp) / f'{fill}.sym'
                    out.write_bytes(bytes([fill]) * ROM_SIZE)
                    r = subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', '--symbols=wla',
                                        f'--symbols-path={symf}', 'asm/main.asm', str(out)],
                                       capture_output=True, text=True)
                    if r.returncode != 0:
                        raise EventsError(f'asar failed on asm/main.asm:\n{r.stdout}{r.stderr}')
                    images.append(out.read_bytes())
                    sym = symf.read_text()
        finally:
            os.chdir(cwd)
        image = images[0]
        mask = bytearray(a == b for a, b in zip(images[0], images[1]))
        cache.mkdir(parents=True, exist_ok=True)
        files[0].write_bytes(image)
        files[1].write_bytes(bytes(mask))
        files[2].write_text(sym)
        files[3].write_text(stamp(image, bytes(mask), sym))
    labels, section = {}, None
    for line in sym.splitlines():
        if line.startswith('['):
            section = line.strip()
            continue
        m = re.match(r'^([0-9A-Fa-f]{2}):([0-9A-Fa-f]{4}) ([A-Za-z_][A-Za-z0-9_]*)$', line)
        if section == '[labels]' and m:
            labels.setdefault(m.group(3), int(m.group(1), 16) << 16 | int(m.group(2), 16))
    return image, mask, labels


class Interpreter:
    """The event opcodes as the matched handlers run them."""

    def __init__(self, root: Path = ROOT):
        self.image, self.mask, self.labels = code_image(root)
        self.code_key = hashlib.sha256(self.image + bytes(self.mask)).hexdigest()
        self.dirty = False
        names = {}
        for name, a in self.labels.items():
            names.setdefault(a, name)
        table = self.labels.get('Evt_OpcodeTable')
        if table is None:
            raise EventsError('no Evt_OpcodeTable in the source')
        off = (table >> 16) - 0xC0 << 16 | table & 0xFFFF
        self.handlers = []
        for op in range(256):
            a = (table & 0xFF0000) | self.image[off + 2 * op] | self.image[off + 2 * op + 1] << 8
            self.handlers.append((a, names.get(a, f'Evt_Handler_{a:06X}')))
        self.machine = absint.Machine(self.image, self.mask, max_steps=400000)
        # op -> the bytes that matter (pattern) -> their values -> result
        self.cache: dict[int, dict[tuple, dict[tuple, dict]]] = {}
        self.specs: dict[int, tuple[int, int, int]] = {}     # op -> its jump's encoding (jump_spec)

    def name(self, op: int) -> str:
        n = self.handlers[op][1]
        return n[4:] if n.startswith('Evt_') else n

    def run(self, data: bytes, y0: int) -> dict:
        """What opcode data[y0 + 1] (an Evt_Data offset y0) does: {'reads':
        sorted operand offsets (relative), 'outs': [(kind, value)]}."""
        op = data[1 + y0]
        for pattern, by_values in self.cache.get(op, {}).items():
            places = [1 + (k if absolute else y0 + k) for absolute, k in pattern]
            if all(0 <= p < len(data) for p in places):
                out = by_values.get(tuple(data[p] for p in places))
                if out is not None:
                    return out
        out = self._trace(data, y0)
        # The result holds for every opcode with the same bytes where the
        # handler let a script byte decide something (a branch, an index,
        # a length) or compute the next position; the others it only moves.
        keys = set(out['control'])
        for x in out['outs']:
            if x[0] == 'pos':
                keys |= set(x[3])
        # (bytes of the opcode's own operands by their place after it, the
        # rest, such as Evt_ObjCount, by their place in the data)
        pattern = tuple((False, k) if 0 <= k < 64 else (True, y0 + k) for k in sorted(keys))
        values = tuple(data[1 + (k if absolute else y0 + k)] for absolute, k in pattern)
        self.cache.setdefault(op, {}).setdefault(pattern, {})[values] = out
        self.dirty = True
        return out

    # The results are kept between runs (build/events/traces.*): by the
    # tools' and the source's hash, with the sha256 of the results, so a
    # changed file is refused, never used.
    def _trace_files(self, root: Path) -> tuple[Path, Path, str]:
        h = hashlib.sha256(self.code_key.encode())
        for tool in ('events.py', 'absint.py', 'disasm.py'):
            h.update((ROOT / 'tools' / tool).read_bytes())
        return root / CODE_DIR / 'traces.pickle', root / CODE_DIR / 'traces.key', h.hexdigest()

    def load(self, root: Path = ROOT) -> None:
        import pickle
        data_f, key_f, key = self._trace_files(Path(root))
        if not (data_f.exists() and key_f.exists()):
            return
        want, _, digest = key_f.read_text().partition(' ')
        if want != key:
            return                                  # other tools or source: start afresh
        raw = data_f.read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest.strip():
            raise EventsError(f'{data_f} is not what tools/events.py wrote (changed by hand?); '
                              f'delete it and {key_f.name} to trace the handlers again')
        self.cache, self.specs = pickle.loads(raw)
        self.dirty = False

    def save(self, root: Path = ROOT) -> None:
        import pickle
        if not self.dirty:
            return
        data_f, key_f, key = self._trace_files(Path(root))
        raw = pickle.dumps((self.cache, self.specs))
        data_f.parent.mkdir(parents=True, exist_ok=True)
        data_f.write_bytes(raw)
        key_f.write_text(f'{key} {hashlib.sha256(raw).hexdigest()}')
        self.dirty = False

    def _trace(self, data: bytes, y0: int) -> dict:
        op = data[1 + y0]
        s = absint.State()
        s.pc = self.handlers[op][0]
        s.a, s.b = (op * 2) & 0xFF, (op * 2) >> 8
        s.x, s.y = op * 2, y0
        s.d, s.db = ENTRY_DP, None
        s.m, s.xf = True, False
        s.c = s.z = s.n = s.v = None
        s.sp, s.spt, s.mem, s.memt = [], [], {}, {}
        s.at = s.xt = s.yt = s.ft = absint.E
        s.depth = 0
        known = {EVT_COUNT + i: b for i, b in enumerate(data)}
        try:
            ends = self.machine.run(s, known)
        except absint.Unresolved as e:
            return {'reads': [], 'control': [], 'outs': [('unresolved', str(e))]}

        def rel(addrs):
            return tuple(sorted(a - EVT_DATA - y0 for a in addrs))
        reads = sorted({a - EVT_DATA - y0 for a in self.machine.reads if a - EVT_DATA > y0})
        outs = set()
        for st, how in ends:
            if how == 'stack':
                outs.add(('end', None))
            elif how != 'rts':
                outs.add(('unresolved', f'returns with {how}'))
            elif st.x is None:
                outs.add(('end', None))
            else:
                outs.add(('pos', st.x - y0, bool(st.xt), rel(st.xt)))
        return {'reads': reads, 'control': rel(self.machine.control), 'outs': sorted(outs, key=str),
                'opaque': sorted(self.machine.opaque)}


# ── Disassembly ─────────────────────────────────────────────────────────────

class Op:
    __slots__ = ('off', 'op', 'length', 'next', 'stay', 'jumps', 'end', 'peeks')


def classify(interp: Interpreter, data: bytes, y0: int) -> Op:
    """The opcode at Evt_Data offset y0, from its handler (see the
    docstring); raises EventsError when the handler cannot be followed."""
    res = interp.run(data, y0)
    o = Op()
    o.off, o.op = y0, data[1 + y0]
    poss = [x[:3] for x in res['outs'] if x[0] == 'pos']
    bad = [x for x in res['outs'] if x[0] == 'unresolved']
    if bad:
        raise EventsError(f'${y0:04X} opcode ${o.op:02X} ({interp.name(o.op)}): {bad[0][1]}')
    static = sorted({d for _, d, t in poss if not t and d > 0})
    if len(static) > 1:
        raise EventsError(f'${y0:04X} opcode ${o.op:02X} ({interp.name(o.op)}): it goes on at +'
                          f'{" and +".join(map(str, static))}')
    # The length is where the handler goes on when it does not compute the
    # place from a script byte; without such a path (a block move's inline
    # data, an unconditional jump), the bytes it reads.
    o.length = static[0] if static else 1 + max(res['reads'], default=0)
    o.peeks = [k for k in res['reads'] if k >= o.length]
    o.next = o.stay = o.end = False
    o.jumps = []
    for x in res['outs']:
        if x[0] == 'end':
            o.end = True
            continue
        _, d, t = x[:3]
        if d == o.length:
            o.next = True
        elif d == 0 and not t:
            o.stay = True
        elif t:
            o.jumps.append(y0 + d)
        else:
            raise EventsError(f'${y0:04X} opcode ${o.op:02X} ({interp.name(o.op)}): it goes on at +{d}, '
                              f'which is neither its length {o.length} nor a jump')
    return o


def jump_spec(interp: Interpreter, data: bytes, o: Op) -> tuple[int, int, int]:
    """(operand byte I, sign S, constant C) with every jump target of the
    opcode = (offset + C) + S x byte I: found by changing each operand
    byte the handler reads and watching the target move."""
    res = interp.run(data, o.off)
    base = sorted(o.jumps)
    known = interp.specs.get(o.op)
    if known is not None and len(base) == 1:
        j, sign, c = known
        if 0 < j < o.length and base[0] == o.off + c + sign * data[1 + o.off + j]:
            return known                    # the encoding found before holds here too
    for j in res['reads']:
        moved = []
        for step in (1, 2):
            d2 = bytearray(data)
            d2[1 + o.off + j] = (d2[1 + o.off + j] + step) & 0xFF
            r2 = interp._trace(bytes(d2), o.off)
            targets = sorted(o.off + x[1] for x in r2['outs'] if x[0] == 'pos' and x[2])
            moved.append(targets)
        if len(base) != 1 or any(len(m) != 1 for m in moved) or moved[0] == base:
            continue
        b = data[1 + o.off + j]
        for sign in (1, -1):
            if all(t == base[0] + sign * ((b + step) & 0xFF) - sign * b for t, step in zip((m[0] for m in moved), (1, 2))):
                spec = (j, sign, base[0] - o.off - sign * b)
                interp.specs.setdefault(o.op, spec)
                interp.dirty = True
                return spec
    raise EventsError(f'${o.off:04X} opcode ${o.op:02X} ({interp.name(o.op)}): its jump is no function of one '
                      f'operand byte')


def disassemble(interp: Interpreter, data: bytes) -> dict:
    """The structure of a pack: {'objects', 'funcs' [(o, f, offset)],
    'ops' {offset: Op}, 'specs' {opcode: (I, S, C)}}; raises EventsError
    when a reached opcode cannot be followed or two opcodes overlap."""
    if not data:
        raise EventsError('an empty pack')
    n = data[0]
    head = n * 2 * FUNCS
    if 1 + head > len(data):
        raise EventsError(f'{n} objects need {head} header bytes; the pack has {len(data) - 1}')
    size = len(data) - 1
    funcs = []
    for o in range(n):
        for f in range(FUNCS):
            k = 1 + o * 2 * FUNCS + 2 * f
            funcs.append((o, f, data[k] | data[k + 1] << 8))
    ops: dict[int, Op] = {}
    owner = [None] * size
    for i in range(head):
        owner[i] = -1
    specs: dict[int, tuple] = {}
    entries = {off for _, _, off in funcs if head <= off < size}
    done_init = set()
    while True:
        work = sorted(entries - set(ops))
        while work:
            y = work.pop()
            if y in ops:
                continue
            if not head <= y < size:
                raise EventsError(f'an opcode at ${y:04X}, outside the scripts')
            o = classify(interp, data, y)
            if y + o.length > size:
                raise EventsError(f'${y:04X} opcode ${o.op:02X}: {o.length} bytes run past the pack')
            if any(owner[i] == -1 for i in range(y, y + o.length)):
                raise EventsError(f'${y:04X} opcode ${o.op:02X} overlaps the header')
            ops[y] = o                  # opcodes may share bytes (a jump into an operand): see layout()
            if o.jumps:
                spec = jump_spec(interp, data, o)
                if specs.setdefault(o.op, spec) != spec:
                    raise EventsError(f'opcode ${o.op:02X}: two jump encodings')
            succ = ([y + o.length] if o.next else []) + o.jumps
            work += [t for t in succ if t not in ops]
        # after each function 0, the opcode after the $00 it stops at
        more = set()
        for ob, f, off in funcs:
            if f or off in done_init or off not in ops:
                continue
            done_init.add(off)
            seen, todo = set(), [off]
            while todo:
                y = todo.pop()
                if y in seen or y not in ops:
                    continue
                seen.add(y)
                o = ops[y]
                if o.op == 0:
                    if y + 1 < size:
                        more.add(y + 1)
                    continue
                todo += ([y + o.length] if o.next else []) + o.jumps
        if more <= set(ops):
            break
        entries |= more
    return {'objects': n, 'funcs': funcs, 'ops': ops, 'specs': specs, 'size': size, 'head': head,
            'entries': entries}


def layout(d: dict) -> tuple[list[int], dict[int, int]]:
    """(the opcodes written out, in order: each starts after the one before
    ends; {opcode inside another's bytes: the written opcode it is in}).
    An opcode a jump reaches inside another's operands shares its bytes:
    it is written as an @inner line of the one it is in."""
    primary, inner, end = [], {}, -1
    for y in sorted(d['ops']):
        if y >= end:
            primary.append(y)
            end = y + d['ops'][y].length
        else:
            inner[y] = primary[-1]
    return primary, inner


# ── The readable form ───────────────────────────────────────────────────────

BANK_C0 = ROOT / 'asm' / 'bankC0' / 'bankC0.asm'
TEXT_POINTER_OPS = {'OpB8_SetMsgPtr'}      # a 3-byte long pointer to a message table


def opcode_names(path: Path = BANK_C0) -> list[str]:
    """The name of each opcode: its handler's in Evt_OpcodeTable (source),
    without Evt_; a handler several opcodes share gets the opcode added."""
    lines = path.read_text().splitlines()
    try:
        i = lines.index('Evt_OpcodeTable:')
    except ValueError:
        raise EventsError(f'{path}: no Evt_OpcodeTable') from None
    handlers = []
    for line in lines[i + 1:]:
        m = re.match(r'^\s+dw\s+([A-Za-z_][A-Za-z0-9_]*)', line)
        if not m:
            break
        handlers.append(m.group(1))
    if len(handlers) != 256:
        raise EventsError(f'Evt_OpcodeTable has {len(handlers)} entries')
    out = []
    for op, h in enumerate(handlers):
        n = h[4:] if h.startswith('Evt_') else h
        out.append(n if handlers.count(h) == 1 else f'{n}_{op:02X}')
    return out


def _label(off: int) -> str:
    return f'L_{off:04X}'


def render(d: dict, data: bytes, names: list[str], pieces: list[tuple[str, int, int]], title: str) -> str:
    """The readable file of a disassembled pack. `pieces`: (label, start,
    end) SNES addresses of the data pieces a text pointer may name."""
    ops, size, head = d['ops'], d['size'], d['head']
    primary, inner = layout(d)
    covered = bytearray(size)
    for y in primary:
        covered[y:y + ops[y].length] = b'\x01' * ops[y].length
    targets = set(d['entries']) | {j for o in ops.values() for j in o.jumps}
    targets |= {off for _, _, off in d['funcs'] if head <= off < size}
    labels = {t for t in targets if t not in inner}

    def ref(t: int) -> str:
        if t in inner:
            return _label(t)
        return _label(t) if head <= t < size else f'${t & 0xFFFF:04X}'

    def operands(o: Op) -> list[str]:
        raw = data[1 + o.off + 1:1 + o.off + o.length]
        out = [f'${b:02X}' for b in raw]
        spec = d['specs'].get(o.op)
        if spec and o.jumps:
            out[spec[0] - 1] = '->' + ref(o.jumps[0])
        if names[o.op] in TEXT_POINTER_OPS and len(raw) == 3:
            ptr = raw[0] | raw[1] << 8 | raw[2] << 16
            for name, start, end in pieces:
                if start <= ptr < end:
                    out = [name if ptr == start else f'{name}+${ptr - start:X}']
                    break
        return out

    out = [f'; {title}: a location event script, disassembled from your own ROM by tools/events.py',
           '; (never commit it). The build assembles it back into the bytes; the format is in',
           '; tools/events.py. This file is regenerated by extraction: an edit is lost when it',
           '; runs again (any change to the extracted assets makes it run).',
           f'@objects {d["objects"]}']
    for op in sorted(d['specs']):
        i, sign, c = d['specs'][op]
        out.append(f'@jump {names[op]} {i} {"+" if sign > 0 else "-"} {c}')
    for o, f, off in d['funcs']:
        out.append(f'@func {o} {f} {ref(off)}')
    inners: dict[int, list[int]] = {}
    for y, host in inner.items():
        inners.setdefault(host, []).append(y)
    y = head
    while y < size:
        if y in labels:
            out.append(_label(y) + ':')
        if y in ops and covered[y] and (y in primary):
            o = ops[y]
            out.append('    ' + ' '.join([names[o.op]] + operands(o)))
            for z in sorted(inners.get(y, ())):
                oz = ops[z]
                out.append(f'    @inner +{z - y} {_label(z)} ' + ' '.join([names[oz.op]] + operands(oz)))
            y += o.length
            continue
        z = y + 1
        while z < size and not covered[z] and z not in labels:
            z += 1
        chunk = data[1 + y:1 + z]
        for k in range(0, len(chunk), 16):
            out.append('@bytes ' + ' '.join(f'{b:02X}' for b in chunk[k:k + 16]))
        y = z
    return '\n'.join(out) + '\n'


def assemble(text: str, names: list[str], pieces: dict[str, int], name: str = '<events>',
             interp: 'Interpreter | None' = None) -> bytes:
    """The unpacked bytes of a readable file. `pieces`: {label: SNES
    address} a text pointer may name. With `interp`, every opcode line is
    checked against its handler: the bytes the line gives must be the
    length the handler takes for them (classify(), as the disassembler
    derives it), so operands cannot be moved from one line to another."""
    opcodes = {n: i for i, n in enumerate(names)}
    if re.search(r'^@raw\b', text, re.M):
        return bytes(int(t, 16) for line in text.split('\n') if line.startswith('@bytes ')
                     for t in line.split()[1:])
    lines = []
    for no, line in enumerate(text.split('\n'), 1):
        code = line.strip()
        if code and not code.startswith(';'):
            lines.append((no, code))
    objects, specs, funcs = None, {}, {}
    body = []
    for no, code in lines:
        where = f'{name}:{no}'
        w = code.split()
        if w[0] == '@objects':
            objects = int(w[1])
        elif w[0] == '@jump':
            if w[1] not in opcodes or w[3] not in '+-':
                raise EventsError(f'{where}: @jump NAME I +|- C')
            specs[opcodes[w[1]]] = (int(w[2]), 1 if w[3] == '+' else -1, int(w[4]))
        elif w[0] == '@func':
            funcs[(int(w[1]), int(w[2]))] = w[3]
        else:
            body.append((where, w))
    if objects is None:
        raise EventsError(f'{name}: no @objects')
    head = objects * 2 * FUNCS

    def size_of(w: list[str]) -> int:
        if w[0] == '@bytes':
            return len(w) - 1
        if w[0] == '@inner' or w[0].endswith(':'):
            return 0
        return 1 + sum(3 if not (t.startswith('$') or t.startswith('->')) else 1 for t in w[1:])

    labels, pos, last = {}, head, None
    for where, w in body:
        if w[0].endswith(':') and len(w) == 1:
            if w[0][:-1] in labels:
                raise EventsError(f'{where}: label {w[0][:-1]} twice')
            labels[w[0][:-1]] = pos
            continue
        if w[0] == '@inner':
            if last is None:
                raise EventsError(f'{where}: @inner before an opcode')
            labels[w[2]] = last + int(w[1])
            continue
        if w[0] != '@bytes':
            last = pos
        pos += size_of(w)

    def target(t: str, where: str) -> int:
        if t in labels:
            return labels[t]
        if re.fullmatch(r'\$[0-9A-Fa-f]{1,4}', t):
            return int(t[1:], 16)
        raise EventsError(f'{where}: no label {t}')

    def encode_op(w: list[str], at: int, where: str) -> bytes:
        if w[0] not in opcodes:
            raise EventsError(f'{where}: unknown opcode {w[0]}')
        op = opcodes[w[0]]
        out = bytearray([op])
        for i, t in enumerate(w[1:], 1):
            if t.startswith('->'):
                if op not in specs or specs[op][0] != len(out):
                    raise EventsError(f'{where}: {w[0]} has no jump operand there (@jump)')
                _, sign, c = specs[op]
                v = (target(t[2:], where) - at - c) * sign
                if not 0 <= v < 256:
                    raise EventsError(f'{where}: {t[2:]} is out of the jump\'s reach')
                out.append(v)
            elif t.startswith('$'):
                v = int(t[1:], 16)
                if not 0 <= v < 256:
                    raise EventsError(f'{where}: {t} is not a byte')
                out.append(v)
            else:
                if names[op] not in TEXT_POINTER_OPS or len(w) != 2:
                    raise EventsError(f'{where}: {t!r}: only {", ".join(sorted(TEXT_POINTER_OPS))} takes a '
                                      f'data label (its one 3-byte operand); write operands as $XX bytes')
                base, _, off = t.partition('+')
                if base not in pieces:
                    raise EventsError(f'{where}: no data label {base}')
                ptr = pieces[base] + (int(off[1:], 16) if off else 0)
                out += ptr.to_bytes(3, 'little')
        return bytes(out)

    out = bytearray([objects]) + bytearray(head)
    for o in range(objects):
        for f in range(FUNCS):
            if (o, f) not in funcs:
                raise EventsError(f'{name}: no @func {o} {f}')
            t = target(funcs[(o, f)], name)
            k = 1 + o * 2 * FUNCS + 2 * f
            out[k:k + 2] = t.to_bytes(2, 'little')
    checks, lines_at = [], []
    last = None
    for where, w in body:
        if w[0].endswith(':') and len(w) == 1:
            continue
        if w[0] == '@bytes':
            out += bytes(int(t, 16) for t in w[1:])
        elif w[0] == '@inner':
            checks.append((where, w[3:], last + int(w[1])))
        else:
            last = len(out) - 1
            b = encode_op(w, last, where)
            out += b
            lines_at.append((where, w[0], last, len(b)))
    for where, w, at in checks:
        b = encode_op(w, at, where)
        if bytes(out[1 + at:1 + at + len(b)]) != b:
            raise EventsError(f'{where}: the @inner opcode is not the bytes it shares')
        lines_at.append((where, w[0], at, len(b)))
    if interp is not None:
        for where, opname, at, n in lines_at:
            o = classify(interp, bytes(out), at)
            if o.length != n:
                raise EventsError(f'{where}: {opname} takes {o.length} bytes here (its handler, as the '
                                  f'disassembler derives it); the line gives {n}')
    return bytes(out)


def render_raw(data: bytes, title: str, why: str) -> str:
    """A pack the disassembler cannot follow (or an empty one), as bytes."""
    out = [f'; {title}: a location event script, extracted from your own ROM by tools/events.py',
           '; (never commit it), kept as bytes: ' + why,
           '; This file is regenerated by extraction: an edit is lost when it runs again.', '@raw']
    for k in range(0, len(data), 16):
        out.append('@bytes ' + ' '.join(f'{b:02X}' for b in data[k:k + 16]))
    return '\n'.join(out) + '\n'


def stats(text: str) -> dict:
    """{'code', 'data', 'raw'}: unpacked bytes in opcodes and the header,
    in @bytes the interpreter never reaches, and in raw packs."""
    data = sum(len(line.split()) - 1 for line in text.split('\n') if line.startswith('@bytes '))
    if re.search(r'^@raw\b', text, re.M):
        return {'code': 0, 'data': 0, 'raw': data}
    return {'code': None, 'data': data, 'raw': 0}


def extract_pack(interp: Interpreter, names: list[str], data: bytes, title: str,
                 pieces: list[tuple[str, int, int]]) -> str:
    """The readable file of one pack: the disassembly when it assembles back
    to the bytes, else the bytes (with the reason)."""
    if not data:
        return render_raw(data, title, 'an empty pack')
    try:
        d = disassemble(interp, data)
        text = render(d, data, names, pieces, title)
    except EventsError as e:
        return render_raw(data, title, str(e))
    try:
        back = assemble(text, names, {n: a for n, a, _ in pieces}, title, interp)
    except EventsError as e:
        return render_raw(data, title, f'the disassembly does not assemble: {e}')
    if back != data:
        return render_raw(data, title, 'the disassembly does not assemble to the same bytes')
    return text


def is_raw(text: str) -> bool:
    return bool(re.search(r'^@raw\b', text, re.M))


def check(rom: bytes, root: Path = ROOT, quiet: bool = True) -> list[str]:
    """Disassemble every events piece afresh and assemble it back, checked
    against the handlers: the problems (a pack that is not byte-exact, a
    non-empty pack left as bytes, an opcode line of the wrong length)."""
    import extract_data
    pieces = extract_data.read_manifest()
    texts = [(p['label'], 0xC00000 + p['offset'], 0xC00000 + p['stop'])
             for p in pieces if p['piece'] == 'text']
    addrs = {n: a for n, a, _ in texts}
    names = opcode_names()
    interp = Interpreter(root)
    interp.load(root)
    problems, n = [], 0
    for p in pieces:
        if p['piece'] != 'events':
            continue
        data, why = extract_data.unpack_piece(rom, p)
        if data is None:
            problems.append(why)
            continue
        text = extract_pack(interp, names, data, p['label'], texts)
        if data and is_raw(text):
            problems.append(f'{p["label"]}: kept as bytes: {text.splitlines()[1][2:]}')
            continue
        try:
            if assemble(text, names, addrs, p['label'], interp) != data:
                problems.append(f'{p["label"]}: does not assemble back to its bytes')
        except EventsError as e:
            problems.append(str(e))
        n += 1
    interp.save(root)
    if not quiet:
        print(f'events: {n} packs disassembled and assembled back')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check',))
    ap.parse_args()
    sys.path.insert(0, str(ROOT / 'tools'))
    import extract_data
    try:
        problems = check(extract_data.read_rom(), quiet=False)
    except (EventsError, extract_data.DataError) as e:
        print(f'events: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'events: {p}', file=sys.stderr)
    if problems:
        return 1
    print('OK: every event script disassembles and assembles back byte-exact, checked against its '
          'handlers')
    return 0


if __name__ == '__main__':
    sys.exit(main())
