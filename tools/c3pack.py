#!/usr/bin/env python3
"""
c3pack.py — Decomp_ToWram's packed format: unpack, pack, and the build of the
packed $C3 module.

The bank $C3 module (BankC3_PackedModule, $C3:1313-$C3:7A2B, 26,393 bytes)
is stored packed; C3_BootModule unpacks it with Decomp_ToWram to $7E:3000-
$7E:B57E ($857F bytes) and jumps there. Its source is matched in unpacked
form (asm/bankC3/packed/), and the build packs it back to the exact bytes in
ROM with the packer below.

The format (Decomp_ToWram's header in asm/bankC3/bankC3.asm has the details):
  +0  16-bit W, the length of segment 1's items (they start at +2), then
  groups: a control byte, one item per bit from bit 0 (0 = a literal byte,
  1 = a 16-bit back-reference: distance and length-3 in 12/4 or 11/5 bits;
  a control byte $00 is eight literals), and at a segment's end an end
  marker: m, then a 16-bit offset from the pack's start to the next marker
  when m AND $3F (the next segment's item count) is nonzero; m = 0 ends. The
  first marker's bits 6-7 pick the mode (0: 12-bit distances, else 11-bit).

The original packer, found by experiment (every one of the 60 packs that
C3Rom_PackPtrs points to and Decomp_ToWram can read, both modes, the module
included, is rebuilt byte for byte; `check` below repeats it):
  - It is Haruhiko Okumura's LZSS (LZSS.C, 1989): a binary search tree over
    a ring buffer of N bytes with look-ahead F (N = 4096, F = 18 in 12-bit
    mode; N = 2048, F = 34 in 11-bit mode), threshold 2 (a match of 3 bytes
    or more becomes a reference), greedy, no lazy matching. Which of several
    equal-length matches it picks comes from the tree (InsertNode keeps the
    first longer match on its path and, at length F, replaces the old node),
    so the rule is the algorithm itself: neither nearest nor farthest.
  - Changed from LZSS.C: the ring buffer starts zeroed with the first byte at
    position 0 (r = 0, s = F), and no position before the data is put in the
    tree (LZSS.C fills N-F spaces and inserts the F positions before r);
    a reference stores the distance (r - match) AND (N-1), not the buffer
    position; flag bit 1 means a reference (LZSS.C: a literal).
  - Framing: every complete group of 8 items in segment 1; when items are
    left over (1-7), segment 1's marker is (count | mode) and the offset of
    the final marker, and segment 2 is that last group with its unused
    control bits set to 1; then the final marker, the mode bits alone.

Usage:
    python3 tools/c3pack.py unpack [ADDR] -o OUT    unpack the pack at ADDR (default
                                                    $C3:1313) from the ROM
    python3 tools/c3pack.py pack IN -o OUT [--mode 11]
    python3 tools/c3pack.py check                   rebuild every pack C3Rom_PackPtrs
                                                    points to, byte for byte
    python3 tools/c3pack.py build                   the module's build (make build)

`build` (also c3pack.ensure_built(), called by every tool that assembles
asm/main.asm): unpacks the ROM's module to build/c3pack/rom_module.bin (the
bytes the source does not cover yet are incbin'd from it, as unmatched ROM
bytes are left in place elsewhere), assembles asm/bankC3/packed/module.asm on
its own (base $7E:3000) to build/c3pack/module.bin, checks that the source
writes every byte, and packs it to build/c3pack/module.lz, which bankC3.asm
incbins at $C3:1313. Nothing is rebuilt when the inputs are unchanged.
"""

import argparse
import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROM_PATH = Path('roms/chrono_trigger.sfc')

MODULE_ROM = 0x031313          # file offset of BankC3_PackedModule ($C3:1313)
MODULE_PACKED_SIZE = 26393     # $C3:1313-$C3:7A2B
MODULE_SIZE = 0x857F           # unpacked, $7E:3000-$7E:B57E
MODULE_BASE = 0x7E3000
PACK_PTRS = 0x3E0000           # C3Rom_PackPtrs ($FE:0000), 3 bytes per entry
PACK_PTR_COUNT = 73

MODULE_SOURCE = Path('asm/bankC3/packed/module.asm')
BUILD_DIR = Path('build/c3pack')
ROM_MODULE = BUILD_DIR / 'rom_module.bin'      # the ROM's module, unpacked
MODULE_BIN = BUILD_DIR / 'module.bin'          # the source's module, unpacked
MODULE_SYM = BUILD_DIR / 'module.sym'          # its labels (asar --symbols=wla)
MODULE_LZ = BUILD_DIR / 'module.lz'            # packed: what bankC3.asm incbins
STAMP = BUILD_DIR / '.inputs'

MODES = {12: (4096, 18), 11: (2048, 34)}       # mode -> ring size N, look-ahead F
THRESHOLD = 2
GROUP = 8
MODE_BITS = 0xC0
COUNT_MASK = 0x3F


class PackError(ValueError):
    pass


# ── Unpacking (a transcription of Decomp_ToWram) ─────────────────────────────

def unpack(src: bytes, start: int = 0) -> tuple[bytes, int, int]:
    """(unpacked bytes, offset just past the final marker, mode) of the pack at
    src[start:]. Raises PackError on a stream Decomp_ToWram would misread."""
    try:
        w = src[start] | src[start + 1] << 8
        x = start + 2
        seg_end = x + w
        mode = 11 if src[seg_end] & MODE_BITS else 12
        dist_mask = (1 << mode) - 1
        out = bytearray()
        left = GROUP
        while True:
            if x == seg_end:
                m = src[x]
                if m & COUNT_MASK == 0:
                    return bytes(out), x + 1, mode
                left = m & COUNT_MASK
                seg_end = start + (src[x + 1] | src[x + 2] << 8)
                x += 3
                continue
            if x > seg_end:
                raise PackError(f'items run past the end marker at +${seg_end - start:04X}')
            c = src[x]
            if c == 0:                              # eight literals; the count is not used
                out += src[x + 1:x + 9]
                x += 9
                continue
            x += 1
            for i in range(left):
                if c >> i & 1:
                    v = src[x] | src[x + 1] << 8
                    dist, length = v & dist_mask, (v >> mode) + 3
                    p = len(out) - dist
                    if p < 0 or dist == 0:
                        raise PackError(f'reference before the start at output ${len(out):04X}')
                    for k in range(length):         # byte by byte: overlaps repeat
                        out.append(out[p + k])
                    x += 2
                else:
                    out.append(src[x])
                    x += 1
            left = GROUP
    except IndexError:
        raise PackError('the stream runs off the end of the data') from None


# ── Packing (Okumura's LZSS, as the original packer ran it) ──────────────────

def lzss_items(data: bytes, mode: int = 12) -> list[tuple]:
    """The item sequence: ('L', byte) or ('R', distance, length)."""
    n, f = MODES[mode]
    nil = n
    text = bytearray(n + f - 1)
    lson = [nil] * (n + 1)
    rson = [nil] * (n + 257)
    dad = [nil] * (n + 1)
    match = [0, 0]                  # position, length

    def insert(r):
        cmp, p = 1, n + 1 + text[r]
        rson[r] = lson[r] = nil
        match[1] = 0
        while True:
            if cmp >= 0:
                if rson[p] != nil:
                    p = rson[p]
                else:
                    rson[p], dad[r] = r, p
                    return
            else:
                if lson[p] != nil:
                    p = lson[p]
                else:
                    lson[p], dad[r] = r, p
                    return
            i = 1
            while i < f:
                cmp = text[r + i] - text[p + i]
                if cmp:
                    break
                i += 1
            if i > match[1]:
                match[0], match[1] = p, i
                if i >= f:
                    break
        dad[r], lson[r], rson[r] = dad[p], lson[p], rson[p]
        dad[lson[p]] = dad[rson[p]] = r
        if rson[dad[p]] == p:
            rson[dad[p]] = r
        else:
            lson[dad[p]] = r
        dad[p] = nil

    def delete(p):
        if dad[p] == nil:
            return
        if rson[p] == nil:
            q = lson[p]
        elif lson[p] == nil:
            q = rson[p]
        else:
            q = lson[p]
            if rson[q] != nil:
                while rson[q] != nil:
                    q = rson[q]
                rson[dad[q]] = lson[q]
                dad[lson[q]] = dad[q]
                lson[q] = lson[p]
                dad[lson[p]] = q
            rson[q] = rson[p]
            dad[rson[p]] = q
        dad[q] = dad[p]
        if rson[dad[p]] == p:
            rson[dad[p]] = q
        else:
            lson[dad[p]] = q
        dad[p] = nil

    items = []
    r, s = 0, f
    length = min(f, len(data))
    text[:length] = data[:length]
    nxt = length
    if not length:
        return items
    insert(r)
    while length > 0:
        mlen = min(match[1], length)
        if mlen <= THRESHOLD:
            mlen = 1
            items.append(('L', text[r]))
        else:
            items.append(('R', (r - match[0]) & (n - 1), mlen))
        i = 0
        while i < mlen and nxt < len(data):
            c = data[nxt]
            nxt += 1
            delete(s)
            text[s] = c
            if s < f - 1:
                text[s + n] = c
            s, r = (s + 1) & (n - 1), (r + 1) & (n - 1)
            insert(r)
            i += 1
        while i < mlen:
            i += 1
            delete(s)
            s, r = (s + 1) & (n - 1), (r + 1) & (n - 1)
            length -= 1
            if length:
                insert(r)
    return items


def frame(items: list[tuple], mode: int = 12) -> bytes:
    """The packed bytes for an item sequence (see the module docstring)."""
    mode_bits = 0 if mode == 12 else 0x40
    groups = []
    for g in range(0, len(items), GROUP):
        chunk = items[g:g + GROUP]
        ctrl, body = 0, bytearray()
        for i, it in enumerate(chunk):
            if it[0] == 'L':
                body.append(it[1])
            else:
                ctrl |= 1 << i
                v = it[1] | (it[2] - 3) << mode
                body += bytes([v & 0xFF, v >> 8])
        ctrl |= (0xFF << len(chunk)) & 0xFF         # unused bits of a partial group
        groups.append(bytes([ctrl]) + body)
    rest = len(items) % GROUP
    full = b''.join(groups[:-1] if rest else groups)
    out = bytearray([len(full) & 0xFF, len(full) >> 8]) + full
    if rest:
        final = len(out) + 3 + len(groups[-1])
        out += bytes([rest | mode_bits, final & 0xFF, final >> 8]) + groups[-1]
    out.append(mode_bits)
    return bytes(out)


def pack(data: bytes, mode: int = 12) -> bytes:
    if len(data) > 0xFFFF:
        raise PackError('more than $FFFF bytes')
    packed = frame(lzss_items(data, mode), mode)
    if len(packed) > 0x10000:
        raise PackError('the packed stream does not fit 16-bit offsets')
    return packed


# ── The ROM's packs ──────────────────────────────────────────────────────────

def snes_to_offset(addr: int) -> int:
    return addr - 0xC00000


def pack_pointers(rom: bytes) -> list[int]:
    """File offsets of C3Rom_PackPtrs' entries (the $000000 terminator left out)."""
    out = []
    for i in range(PACK_PTR_COUNT):
        o = PACK_PTRS + 3 * i
        out.append(snes_to_offset(rom[o] | rom[o + 1] << 8 | rom[o + 2] << 16))
    return out


def check_rom(rom: bytes) -> tuple[list[int], list[int], list[int]]:
    """(packs rebuilt byte for byte, packs not, entries Decomp_ToWram cannot read)."""
    same, differ, raw = [], [], []
    for i, off in enumerate(pack_pointers(rom)):
        try:
            data, end, mode = unpack(rom, off)
        except PackError:
            raw.append(i)
            continue
        (same if pack(data, mode) == rom[off:end] else differ).append(i)
    return same, differ, raw


# ── The module's build ───────────────────────────────────────────────────────

def _inputs_hash(root: Path) -> str:
    h = hashlib.sha256(b'c3pack v1\0')
    files = sorted((root / MODULE_SOURCE.parent).rglob('*'))
    files += [root / 'asm/include', root / 'asm/hardware.inc', Path(__file__)]
    for p in files:
        for q in ([p] if p.is_file() else sorted(p.rglob('*')) if p.is_dir() else []):
            if q.is_file():
                h.update(str(q.relative_to(root) if q.is_relative_to(root) else q.name).encode() + b'\0')
                h.update(hashlib.sha256(q.read_bytes()).digest())
    rom = root / ROM_PATH
    if rom.exists():
        h.update(hashlib.sha256(rom.read_bytes()).digest())
    return h.hexdigest()


def _assemble(root: Path, fill: int, out: Path, sym: Path | None = None,
              image: Path | None = None) -> None:
    """Assemble the module onto a $857F-byte image of `fill`; `image` replaces
    the ROM's module as the source of the bytes not matched yet."""
    out.write_bytes(bytes([fill]) * MODULE_SIZE)
    cmd = ['asar', '--no-title-check', '--fix-checksum=off']
    if image is not None:
        cmd.append(f'-DC3Mod_RomImage={image.resolve()}')
    if sym is not None:
        cmd += ['--symbols=wla', f'--symbols-path={sym.resolve()}']
    r = subprocess.run(cmd + [str(MODULE_SOURCE), str(out.resolve())],
                       cwd=root, capture_output=True, text=True)
    if r.returncode != 0:
        raise PackError(f'asar failed on {MODULE_SOURCE}:\n{r.stdout}{r.stderr}')
    if out.stat().st_size != MODULE_SIZE:
        raise PackError(f'{MODULE_SOURCE} writes past $7E:{(MODULE_BASE + MODULE_SIZE - 1) & 0xFFFF:04X}')


def build(root: Path = Path('.'), quiet: bool = True) -> Path:
    """Build build/c3pack/module.lz from the module's source (see the
    docstring); returns its path. Raises PackError when it cannot."""
    root = Path(root)
    bdir = root / BUILD_DIR
    key = _inputs_hash(root)
    stamp = root / STAMP
    if (stamp.exists() and stamp.read_text() == key and (root / MODULE_LZ).exists()
            and (root / MODULE_BIN).exists()):
        return root / MODULE_LZ
    rom_path = root / ROM_PATH
    if not rom_path.exists():
        raise PackError(f'no ROM at {rom_path}: the module source incbins the bytes it does not cover')
    rom = rom_path.read_bytes()
    bdir.mkdir(parents=True, exist_ok=True)
    original, end, _ = unpack(rom, MODULE_ROM)
    if len(original) != MODULE_SIZE or end - MODULE_ROM != MODULE_PACKED_SIZE:
        raise PackError('the ROM\'s module is not the expected one')
    (root / ROM_MODULE).write_bytes(original)
    with tempfile.TemporaryDirectory() as tmp:
        lo, hi = Path(tmp) / 'lo.bin', Path(tmp) / 'hi.bin'
        _assemble(root, 0x00, lo, root / MODULE_SYM)
        _assemble(root, 0xFF, hi)
        a, b = lo.read_bytes(), hi.read_bytes()
    gaps = [i for i in range(MODULE_SIZE) if a[i] != b[i]]
    if gaps:
        raise PackError(f'{MODULE_SOURCE} leaves {len(gaps)} byte(s) unwritten, the first at '
                        f'$7E:{(MODULE_BASE + gaps[0]) & 0xFFFF:04X}')
    (root / MODULE_BIN).write_bytes(a)
    (root / MODULE_LZ).write_bytes(pack(a))
    if a != original and not quiet:
        first = next(i for i in range(MODULE_SIZE) if a[i] != original[i])
        print(f'c3pack: the module differs from the ROM\'s from $7E:{(MODULE_BASE + first) & 0xFFFF:04X} '
              f'(unpacked); the packed bytes will not match', file=sys.stderr)
    stamp.write_text(key)
    return root / MODULE_LZ


def source_bytes(root: Path = Path('.')) -> list[int]:
    """Offsets into the module of the bytes its source writes itself (not
    incbin'd from the ROM's module): the source assembled twice, with the
    image and the ROM's module all $00 and all $FF; the bytes that agree."""
    ensure_built(root)
    with tempfile.TemporaryDirectory() as tmp:
        built = []
        for fill in (0x00, 0xFF):
            image, out = Path(tmp) / f'image{fill:02x}.bin', Path(tmp) / f'out{fill:02x}.bin'
            image.write_bytes(bytes([fill]) * MODULE_SIZE)
            _assemble(Path(root), fill, out, image=image)
            built.append(out.read_bytes())
    return [i for i in range(MODULE_SIZE) if built[0][i] == built[1][i]]


def module_labels(root: Path = Path('.')) -> dict[str, int]:
    """{label: $7Exxxx} of the module's source (asar's symbol file)."""
    ensure_built(root)
    out = {}
    for line in (Path(root) / MODULE_SYM).read_text().splitlines():
        m = re.match(r'^([0-9A-Fa-f]{2}):([0-9A-Fa-f]{4}) (\S+)$', line)
        if m:
            out[m.group(3)] = int(m.group(1), 16) << 16 | int(m.group(2), 16)
    return out


def ensure_built(root: Path = Path('.')) -> None:
    """build(), for the tools that assemble asm/main.asm: exits with the
    reason when the module cannot be built."""
    try:
        build(root)
    except PackError as e:
        raise SystemExit(f'c3pack: {e}') from None


# ── Command line ─────────────────────────────────────────────────────────────

def parse_addr(text: str) -> int:
    t = text.replace('$', '').replace(':', '')
    return snes_to_offset(int(t, 16)) if len(t) > 4 else int(t, 16)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    u = sub.add_parser('unpack', help='unpack a pack from the ROM')
    u.add_argument('addr', nargs='?', default='C31313')
    u.add_argument('-o', '--output', required=True)
    p = sub.add_parser('pack', help='pack a file')
    p.add_argument('input')
    p.add_argument('-o', '--output', required=True)
    p.add_argument('--mode', type=int, choices=(11, 12), default=12)
    sub.add_parser('check', help='rebuild every pack C3Rom_PackPtrs points to')
    sub.add_parser('build', help='build build/c3pack/module.lz from the source')
    args = ap.parse_args()

    try:
        if args.cmd == 'pack':
            Path(args.output).write_bytes(pack(Path(args.input).read_bytes(), args.mode))
            return 0
        if args.cmd == 'build':
            out = build(quiet=False)
            same = out.read_bytes() == ROM_PATH.read_bytes()[MODULE_ROM:MODULE_ROM + MODULE_PACKED_SIZE]
            print(f'{out}: {out.stat().st_size:,} bytes, '
                  + ('the ROM\'s bytes' if same else 'DIFFERENT from the ROM\'s bytes'))
            return 0
        if not ROM_PATH.exists():
            print(f'No ROM at {ROM_PATH}', file=sys.stderr)
            return 2
        rom = ROM_PATH.read_bytes()
        if args.cmd == 'unpack':
            data, end, mode = unpack(rom, parse_addr(args.addr))
            Path(args.output).write_bytes(data)
            print(f'{len(data):#x} bytes, {mode}-bit mode, pack ends at file offset {end:#x}')
            return 0
        same, differ, raw = check_rom(rom)
        print(f'{len(same)} packs rebuilt byte for byte; not rebuilt: {differ or "none"}; '
              f'not in the format (raw blocks): entries {raw}')
        return 1 if differ else 0
    except PackError as e:
        print(f'c3pack: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
