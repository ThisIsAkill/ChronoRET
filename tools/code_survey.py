#!/usr/bin/env python3
"""
code_survey.py — How many bytes of each bank are 65816 code: symbols/code_survey.csv.

tools/progress.py measures the share of game code against these figures. They
change only when the survey is re-run (deliberately, with --write); matching
more code does not change them.

Per bank, code_bytes = matched + traced + allowance:

  matched     code bytes of matched routines (functions.csv kind `code`).
              Exact. Data routines (db/dw/fill) never count.
  traced      unmatched bytes decoded as instructions by a flow trace that
              starts from every place control leaves matched code (the exits
              tools/xref.py derives, under the M/X widths the source agrees
              with) and from the hardware vectors. It follows branches, JMP,
              JML, JSR, JSL (into any bank), tracks M/X through REP, SEP,
              PHP/PLP and the exit widths of each callee, and follows JMP/JSR
              (a,X) through matched word tables. A second, liberal pass also
              keeps going after a call whose exit widths are unknown (widths
              assumed kept) and reads unmatched (a,X) tables while their words
              decode as code; it drops any path that decodes BRK/COP/WDM/STP or
              an opcode that never occurs in matched code. traced = union.
  allowance   code reached only through indirect jumps the trace cannot
              follow (RAM vectors, pushed return addresses, script opcodes):
              unmatched, untraced bytes in 32-byte blocks whose linear decode
              scores as code (mean log-likelihood of the opcodes against the
              matched source's opcode profile >= 0), counted only when the
              block is joined to matched or traced code of the same bank by a
              chain of such blocks with gaps of at most GAP blocks (192 bytes).
              Code-like blocks not joined to any code are listed as isolated
              and enter only the upper bound.

  code_bytes_low / _high: the allowance at score >= +0.5 / >= -0.5 (the high
              bound also adds the isolated blocks).

Calibration (--calibrate): treat every matched routine of $C0, $C1, $C2 or
$FD as unmatched, run the same survey, and compare with the survey made with
the source. In the re-survey of 2026-10-14 (all of $C0, $C1 and $C2 and
$FD:A8A5-$FFFF from source) the trace reached 78% ($C0), 65% ($C1), 14%
($C2) and 79% ($FD) of the matched code and none of the matched data; with
the allowance the estimate came out low every time: $C0 -2.4% (59,421 for
60,857), $C1 -2.5% (61,140 for 62,682), $FD -0.8% (15,537 for 15,668, recall
95%: trace + allowance count 95% of the matched code bytes) and $C2 -20.5%
(48,235 for 60,695: its code is reached mostly through scene-op tables the
trace cannot follow). So the estimate for unmatched code tends to be LOW,
by a few percent where the trace reaches most of a bank and by much more
where it does not. The block scorer passes 87% of matched code blocks and
under 1% of the blocks of banks that hold no code (sound, graphics), which
is why code-like blocks not joined to any code are left out of code_bytes.

Since all known 65816 code is matched (2026-10-14), every exit of matched
code lands in matched code: the trace adds nothing, no code-like block is
joined to code, and code_bytes equals the matched code of each bank. What
the survey still cannot see is code reached only indirectly that sits in
blocks of data far from any code; the high bound (isolated code-like
blocks: in the banks with code none is reached by a call, jump or pointer
from matched code, and the highest-scoring ones are tables, tile maps and
pointer lists; see NEXT.md, "Code survey") is the room left for it.

Data known to sit inside banks with code (TABLES, e.g. the APU interface
tables $C7:0A98-$0D52) is kept out of the trace and the allowance.

Not 65816 code, reported in their own columns and never in code_bytes:
  spc700_bytes      the sound driver program uploaded to the SPC700 (its
                    length word and ARAM address are in the upload table at
                    $C7:0010/$C7:001C). Includes the driver's own tables.
  compressed_bytes  packed 65816 code: the module at $C3:1313 that $C3:0014
                    unpacks to $7E:3000 (via $C3:0557, the pointer at
                    $FE:0003) and runs with JML $7E:3000. Its size is the
                    packed-length word the decompressor reads, plus that word.

A bank with no matched or traced code gets 0 when no JSL/JML from matched
or traced code reaches it (indirect transfers through RAM vectors are not
ruled out): every JSL/JML byte pattern into the bank
is listed with tools/xref.py's verdict, and the note says how many are
CONFIRMED from matched or traced code (the noise level of the sweep verdict
on data is ~20% of patterns, so a CONFIRMED pattern in data proves nothing).

Usage:
    python3 tools/code_survey.py              print the survey (does not write)
    python3 tools/code_survey.py --write      write symbols/code_survey.csv
    python3 tools/code_survey.py --calibrate  the held-out test on $C0, $C1, $C2 and $FD
"""

import argparse
import collections
import csv
import io
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generated  # noqa: E402
import xref as X  # noqa: E402

SURVEY_CSV = Path('symbols/code_survey.csv')
BANKS = range(0xC0, 0x100)
BLOCK = 32
GAP = 6                       # blocks
TH, TH_HI, TH_LO = 0.0, 0.5, -0.5
COLS = ['bank', 'code_bytes', 'matched_code_bytes', 'traced_bytes', 'allowance_bytes',
        'code_bytes_low', 'code_bytes_high', 'spc700_bytes', 'compressed_bytes', 'method',
        'uncertainty', 'notes']


def off(text: str) -> int:
    """'$C7:24C3' -> file offset."""
    return X.to_offset(int(text[1:3], 16), int(text[4:8], 16))


# Ranges that are not 65816 code in the ROM image, with their evidence.
SPC700 = [('$C7:24C3', '$C7:40B3', 'SPC700 driver: length word $1BEF at $C7:24C3, uploaded to ARAM $0200 '
           '(block 0 of the upload table at $C7:0010/$C7:001C)')]
COMPRESSED = [('$C3:1313', '$C3:7A21', 'packed module: length word $670D at $C3:1313 (read by the '
               'decompressor $C3:0557 as the packed length), unpacked to $7E:3000 by $C3:0014 '
               '(pointer at $FE:0003) and run with JML $7E:3000 at $C3:0073')]
UPLOAD_TABLE = '$C7:0010'
# Sound data: the sample table ($C7:0AEA, 62 long pointers) and the song
# table ($C7:0D18, 83 long pointers); each item starts with its length word.
SAMPLE_TABLE, SAMPLES = '$C7:0AEA', 62
SONG_TABLE, SONGS = '$C7:0D18', 83
# Data inside banks with code, kept out of the allowance (and the trace).
TABLES = [('$C7:0A98', '$C7:0D52', 'APU interface tables: the sample table $C7:0AEA and the song table '
           '$C7:0D18 (read by the unmatched sound driver at $C7:0666/$0773/$050F) and their neighbours')]

# What is known of the content of banks that hold data, for the notes. Each
# claim names its evidence: a reader (in matched code unless said otherwise)
# or a pointer table. The sound tables $C7:0AEA/$C7:0D18 are read by the
# unmatched sound driver ($C7:050F, $0666, $0773), not by matched code.
CONTENT = {
    '$C3': '$C3:0000-$10CA kernel, all from source (ends with the ASCII marker "CODE END C3"); '
           '$C3:1200-$1312 another pack (C3Rom_PackPtrs entry 0, user not traced); the packed '
           'module (compressed_bytes); data after it',
    '$C6': 'code $C6:E000-$EE42 (scene helpers: JSL from bank $C2 and scene op $4E), then $00 fill to '
           '$EFFF; the rest data (packs, headers, scene tables read by matched code)',
    '$C7': '$C7:0000-$0A97 APU interface (65816); $0A98-$0D52 tables, kept out of the allowance (the sample '
           'and song tables $0AEA/$0D18 are read by the unmatched driver at $C7:050F/$0666/$0773); '
           'SPC700 driver $24C3-$40B3; samples from $C7:730D (table $C7:0AEA)',
    '$C8': 'BRR samples (table $C7:0AEA)',
    '$C9': 'BRR samples (table $C7:0AEA)',
    '$CA': 'BRR samples to $CA:8ACB, then song data $CA:8ACC- (tables $C7:0AEA, $C7:0D18): the 2026-09 '
           'survey\'s 30,004 is exactly $CA:8ACC-$FFFF, i.e. it counted song data as code. '
           'The two code-like JML patterns into it ($D1:A87B, $D1:ADDB) lie in $D1\'s '
           'window-map data and point inside a sample ($CA:8A9C)',
    '$CB': 'song data $CB:0000-$F163 (table $C7:0D18): the 2026-09 survey\'s 61,797 matches it, i.e. it '
           'counted song data as code; $CB:F164-$FFFF (3,740 bytes) lies outside both sound tables and is '
           'unexplained (counted as 0 code)',
    '$CC': '$CC:0000-$DFFF tables (320 long data reads from matched battle code); code '
           '$CC:E000-$F382; tables after (115 long reads into $CC:F383 and up)',
    '$CD': 'code $CD:0000-$3F9D with tables inside, $3F9E-$3FFF old-build leftovers (data); '
           '$CD:4000- data (pointer tables at $CD:66F0 score as code but nothing reaches them)',
    '$CE': 'code $CE:E000-$EF10 and $F066-$F0E5 (JSL from $CD and $D1 only); the rest data',
    '$CF': 'code $CF:E300-$FE84 with tables, then data to $FFFF; $CF:0000-$E2FF data',
    '$D1': 'code $D1:E70A-$FEF3 with tables, then $00 fill; $D1:0000-$E709 data (battle window maps)',
    '$DE': 'data read by TextWin_State0_Draw ($DE:FA00); the long pointer table at $E4:234E-$25A3 '
           'points into $DD, $DE and $E3 (and once into $E1)',
    '$E4': 'a word offset table at $E4:0000 (AnimRom, read by six routines, Menu_LoadCharPalettes '
           'among them; palettes are reached through it), sprite records ($E4:F000, '
           'Evt_LoadSpriteRec) and other tables read by matched code (42 long reads)',
    '$E5': 'map tile tables read by Map_StepTileEffects / Map_LoadExitTiles; 29 long pointers '
           'at $F6:2220 (read by LocLoad_UploadPack) point into it',
    '$F5': 'tile data read by Field_CheckTileInFront / Map_LoadTreasureTiles; 37 long pointers '
           'at $F6:1FEF point into it',
    '$F6': 'location tables read by LocLoad_* and Map_InitMasksAndLimits (30 long reads)',
    '$F7': 'starts with a word offset table; no reader found',
    '$F8': '66 long pointers at $FC:FB3D point into it (packed data)',
    '$F9': '59 long pointers at $FC:FC03 point into it (packed data)',
    '$FC': 'pointer tables $FC:F9F0-$FEBB (read by LocLoad_Unk56D4) and the data they index',
    '$FD': '$FD:A8A5-$FFFF from source (code, tables, old-build leftovers $D5D4-$D9FF as data); '
           '$FD:0000-$A8A4 data (packed credits graphics, staff credits text at $FD:A000, battle '
           'tables $A800-$A8A4)',
    '$FE': 'packed data: the pack pointer table at $FE:0000 (its entry $FE:0003 is the $C3:1313 '
           'code module); whether any pack in $FE unpacks to code is not known',
    '$FF': 'code $FF:F548-$FC66 with tables (called from C2 menu code), $FC67-$FFFF old-build '
           'leftovers (data); the rest data',
}

# The 2026-09 survey's figures for the banks where this one finds far less
# code; their notes carry the inbound-reference evidence.
OLD_SURVEY = {'$CA': 30004, '$CB': 61797, '$CC': 27226, '$DE': 290, '$E4': 1810, '$E5': 1026,
              '$F5': 2022, '$F6': 1728, '$F7': 2016, '$F8': 512, '$F9': 394, '$FC': 406,
              '$FE': 218}


# ── Trace ─────────────────────────────────────────────────────────────────────

class Tracer(X.Xref):
    """Xref's flow decoding, run from every matched exit and the vectors."""

    def __init__(self, liberal: bool, hide=()):
        super().__init__(hide=hide)
        self.liberal = liberal
        n = len(self.rom)
        self.matched = bytearray(n)
        for s, e, _ in self.rows:
            self.matched[s:e + 1] = b'\1' * (e - s + 1)
        cnt = collections.Counter(self.rom[o] for o, (_, _, ins) in self.boundaries.items()
                                  if ins and self.matched[o])
        self.never = {op for op in range(256) if not cnt[op]} | set(X.IMPLAUSIBLE)
        self.guessed = {}

    def plausible(self, o, st, n=8):
        for _ in range(n):
            if o >= len(self.rom):
                return False
            if self.matched[o]:
                b = self.boundaries.get(o)
                return bool(b and b[2])
            if self.rom[o] in self.never:
                return False
            d = X.Xref._decode(self, o, st)
            if d is None:
                return False
            ln, st, _, _, falls, _ = d
            if not falls:
                return True
            o += ln
        return True

    def _table_targets(self, table):
        known = super()._table_targets(table)
        if known or not self.liberal:
            return known
        if table not in self.guessed:
            bank, out, o, first_target = table & ~0xFFFF, [], table, None
            while len(out) < 128 and (o + 1) >> 16 == table >> 16 and not self.matched[o]:
                w = self.rom[o] | self.rom[o + 1] << 8
                t = bank | w
                if w < 0x100 or w == 0xFFFF or table <= t < o + 2 or \
                        (first_target is not None and o >= first_target):
                    break
                if not (self.plausible(t, (True, False, ())) or self.plausible(t, (False, False, ()))):
                    break
                out.append(t)
                if t > table:
                    first_target = t if first_target is None else min(first_target, t)
                o += 2
            self.guessed[table] = tuple(out)
        return self.guessed[table]

    def vectors(self):
        """Native and emulation interrupt vectors ($00:FFE4-$FFFF)."""
        out = []
        for a in (0xFFE4, 0xFFE6, 0xFFEA, 0xFFEE, 0xFFFA, 0xFFFC, 0xFFFE):
            w = self.rom[a] | self.rom[a + 1] << 8
            if w >= 0x8000:
                out.append((w, (True, True, ())))
        return out

    def run(self):
        """Bytes decoded as instructions (start or operand), unmatched or not."""
        rom, n = self.rom, len(self.rom)
        hit = bytearray(n)
        seen, work = set(), []
        for s, e, _ in self.rows:
            work.extend(self._row_exits(s, e))
        work.extend(self.vectors())
        while work:
            o, st = work.pop()
            block, nexts, ok = [], [], True
            while True:
                if o is None or o >= n or (o, st) in seen:
                    break
                if self.matched[o]:
                    b = self.boundaries.get(o)
                    ok = bool(b and b[2])
                    break
                if self.liberal and rom[o] in self.never:
                    ok = False
                    break
                d = self._decode(o, st)
                if d is None or any(self.matched[o + 1:o + d[0]]):
                    ok = False
                    break
                ln, nst, jumps, calls, falls, _ = d
                block.append((o, ln, st))
                nexts.extend((j, nst) for j in jumps)
                if calls:
                    nexts.extend((c, (nst[0], nst[1], ())) for c in calls if c >= 0)
                    after = self._after_call(calls, nst)
                    if after is None:
                        if not self.liberal:
                            break
                        after = nst
                    nst = after
                if not falls:
                    break
                if jumps:
                    nexts.append((o + ln, nst))
                    break
                o, st = o + ln, nst
            if not ok:
                continue
            for o2, ln, st2 in block:
                seen.add((o2, st2))
                hit[o2:o2 + ln] = b'\1' * ln
            work.extend(nexts)
        return hit


def trace(hide=()):
    """(strict trace, union of strict and liberal, the strict Tracer)."""
    strict = Tracer(False, hide)
    a = strict.run()
    b = Tracer(True, hide).run()
    return a, bytes(x | y for x, y in zip(a, b)), strict


# ── Code-likeness ─────────────────────────────────────────────────────────────

def block_scores(xr):
    rom = xr.rom
    cnt = collections.Counter(rom[o] for o, (_, _, ins) in xr.boundaries.items() if ins)
    tot = sum(cnt.values())
    ll = [math.log((cnt[op] + 0.5) / (tot + 128) * 256) for op in range(256)]
    scores = []
    for o0 in range(0, len(rom), BLOCK):
        best = -99.0
        for m, x in ((True, False), (False, False), (True, True)):
            p, s, k, bad = o0, 0.0, 0, 0
            while p < o0 + BLOCK:
                op = rom[p]
                bad += op in X.IMPLAUSIBLE
                s += ll[op]
                k += 1
                if op == 0xC2 and p + 1 < len(rom):
                    m, x = m and not rom[p + 1] & 0x20, x and not rom[p + 1] & 0x10
                elif op == 0xE2 and p + 1 < len(rom):
                    m, x = m or bool(rom[p + 1] & 0x20), x or bool(rom[p + 1] & 0x10)
                p += X._LEN[(m, x)][op]
            best = max(best, (s - 8 * bad) / k)
        scores.append(best)
    return scores


# ── Survey ────────────────────────────────────────────────────────────────────

def ranges_mask(n, ranges):
    mask = bytearray(n)
    for s, e, _ in ranges:
        mask[off(s):off(e) + 1] = b'\1' * (off(e) - off(s) + 1)
    return mask


def bank_figures(b, code, data, reached, excl, scores, counted=None):
    """traced, allowance at TH/TH_HI/TH_LO, isolated at TH and TH_LO for bank offset b<<16.
    counted: a bytearray the size of the ROM, set where a byte enters traced + allowance at TH."""
    base, nb = b << 16, 0x10000 // BLOCK
    traced = [0] * nb
    free = [0] * nb
    has = [False] * nb
    for k in range(nb):
        for o in range(base + k * BLOCK, base + (k + 1) * BLOCK):
            if code[o]:
                has[k] = True
            elif data[o] or excl[o]:
                pass
            elif reached[o]:
                traced[k] += 1
                has[k] = True
            else:
                free[k] += 1

    def allowance(th):
        pos = [scores[base // BLOCK + k] >= th and free[k] > 0 for k in range(nb)]
        joined, stack = set(), [k for k in range(nb) if has[k]]
        seen = set(stack)
        while stack:
            k = stack.pop()
            for d in (-1, 1):
                for step in range(1, GAP + 2):
                    j = k + d * step
                    if not 0 <= j < nb:
                        break
                    if pos[j] or has[j]:
                        if j not in seen:
                            seen.add(j)
                            joined.add(j)
                            stack.append(j)
                        break
        inside = sum(free[k] for k in range(nb) if pos[k] and k in joined)
        isolated = sum(free[k] for k in range(nb) if pos[k] and k not in joined)
        if counted is not None and th == TH:
            for o in range(base, base + 0x10000):
                k = (o - base) // BLOCK
                if not (code[o] or data[o] or excl[o]) and (reached[o] or (pos[k] and k in joined)):
                    counted[o] = 1
        return inside, isolated

    al, iso = allowance(TH)
    al_hi, _ = allowance(TH_HI)
    al_lo, iso_lo = allowance(TH_LO)
    return sum(traced), al, al_hi, al_lo, iso, iso_lo


def kinds_masks(n, hide_bank=None):
    code, data = bytearray(n), bytearray(n)
    for r in generated.function_rows():
        if hide_bank and r['bank'] == hide_bank:
            continue
        s, e = off(r['address']), off(r['end'])
        (code if r['kind'] == 'code' else data)[s:e + 1] = b'\1' * (e - s + 1)
    return code, data


def sound_items(rom):
    """(start, end) of every sample and song: long pointer, then a length word."""
    out = []
    for table, count in ((SAMPLE_TABLE, SAMPLES), (SONG_TABLE, SONGS)):
        t = off(table)
        for i in range(count):
            p = rom[t + 3 * i] | rom[t + 3 * i + 1] << 8 | rom[t + 3 * i + 2] << 16
            o = X.to_offset(p >> 16, p & 0xFFFF)
            out.append((o, o + 1 + (rom[o] | rom[o + 1] << 8)))
    return out


def inbound(xr, reached, scores, bank):
    """JSL/JML byte patterns into a bank: (patterns, CONFIRMED, CONFIRMED in matched or
    traced code, CONFIRMED in code-like blocks)."""
    if xr._index is None:
        xr._build_index()
    total = conf = from_code = codey = 0
    for tgt, sites in xr._index.items():
        if tgt >> 16 != bank - 0xC0:
            continue
        for pos, kind in sites:
            if kind not in ('JSL', 'JML'):
                continue
            total += 1
            if xr.classify(pos, kind).status == 'CONFIRMED':
                conf += 1
                if xr.matched[pos] or reached[pos]:
                    from_code += 1
                elif scores[pos // BLOCK] >= TH:
                    codey += 1
    return total, conf, from_code, codey


def upload_blocks(rom):
    """(start, end) of the blocks the APU interface uploads: 6 source words at
    $C7:0010 (bank $C7), each block starting with its length word."""
    t = off(UPLOAD_TABLE)
    out = []
    for i in range(6):
        o = t & ~0xFFFF | rom[t + 2 * i] | rom[t + 2 * i + 1] << 8
        out.append((o, o + 1 + (rom[o] | rom[o + 1] << 8)))
    return out


def exclusions(rom):
    """(SPC700, packed, sound data, union of those and TABLES) masks: bytes that are not 65816 code."""
    n = len(rom)
    spc, packed, tables = ranges_mask(n, SPC700), ranges_mask(n, COMPRESSED), ranges_mask(n, TABLES)
    sound = bytearray(n)
    for s, e in sound_items(rom) + upload_blocks(rom)[1:]:
        sound[s:e + 1] = b'\1' * (e - s + 1)
    excl = bytes(a | b | c | d for a, b, c, d in zip(spc, packed, sound, tables))
    return spc, packed, sound, excl


def survey():
    strict, reached, xr = trace()
    rom, n = xr.rom, len(xr.rom)
    code, data = kinds_masks(n)
    spc, packed, sound, excl = exclusions(rom)
    scores = block_scores(xr)
    rows = []
    for bank in BANKS:
        b = bank - 0xC0
        name = f'${bank:02X}'
        lo, hi = b << 16, (b + 1) << 16
        matched = sum(code[lo:hi])
        traced, al, al_hi, al_lo, iso, iso_lo = bank_figures(b, code, data, reached, excl, scores)
        strict_n = sum(1 for o in range(lo, hi) if strict[o] and not (code[o] or data[o]))
        total = matched + traced + al
        low, high = matched + traced + al_hi, matched + traced + al_lo + iso_lo
        spc_n, packed_n, sound_n = sum(spc[lo:hi]), sum(packed[lo:hi]), sum(sound[lo:hi])
        notes = []
        if matched and not traced and not al and matched + sum(data[lo:hi]) == 0x10000:
            method = 'matched (bank fully covered by source)'
            unc = 'exact'
        elif matched and not traced and not al:
            # Trace and allowance add nothing: only isolated blocks remain (high bound).
            method = 'matched (trace and allowance find no more)'
            unc = f'-0/+{high - total}'
            notes.append(f'isolated code-like {iso} (at score >= -0.5: {iso_lo})')
        elif matched or traced:
            method = 'matched + trace + allowance'
            unc = f'-{total - low}/+{high - total}'
            notes.append(f'trace {strict_n} strict + {traced - strict_n} liberal; '
                         f'allowance {al}; isolated code-like {iso}')
        else:
            total = 0
            method = 'no code found'
            unc = f'+{iso_lo}'
            if name in OLD_SURVEY or iso:
                pats, conf, from_code, codey = inbound(xr, reached, scores, bank)
                notes.append(f'{pats} JSL/JML byte patterns point into the bank: {from_code} CONFIRMED in '
                             f'matched or traced code, {codey} in code-like blocks ({conf} pass the sweep '
                             f'test, the chance rate in data); {iso} bytes in isolated code-like blocks')
        if sound_n:
            notes.append(f'{sound_n} bytes of samples, songs and uploaded SPC700 data')
        if name in CONTENT:
            notes.append(CONTENT[name])
        if name in OLD_SURVEY and total < OLD_SURVEY[name] // 2 and '2026-09 survey' not in CONTENT.get(name, ''):
            notes.append(f'2026-09 survey: {OLD_SURVEY[name]}')
        rows.append({'bank': name, 'code_bytes': total, 'matched_code_bytes': matched,
                     'traced_bytes': traced, 'allowance_bytes': al if method != 'no code found' else 0,
                     'code_bytes_low': low if total else 0, 'code_bytes_high': high if total else iso_lo,
                     'spc700_bytes': spc_n, 'compressed_bytes': packed_n, 'method': method,
                     'uncertainty': unc, 'notes': '; '.join(notes)})
    return rows


HEADER = """\
# 65816 code bytes per bank: the denominators of tools/progress.py.
# Written by `python3 tools/code_survey.py --write` (method in its docstring):
# code_bytes = matched code (exact) + unmatched bytes reached by a flow trace
# from matched code and the vectors + an allowance for code reached only
# through indirect jumps (code-like 32-byte blocks joined to traced code).
# code_bytes_low/high bound the allowance. SPC700 and compressed code are
# counted apart and are not in code_bytes. Re-run only to re-survey.
# Uncertainty: the estimate for unmatched code tends to be LOW (held-out
# tests, --calibrate: hiding $C0 -2.4%, $C1 -2.5%, $C2 -20.5%, $FD -0.8%).
# Every bank's code_bytes is now its matched code: the trace and the
# allowance find no unmatched code. code_bytes_high adds isolated code-like
# blocks; those in the banks with code are data (NEXT.md, "Code survey").
"""


def render(rows) -> str:
    buf = io.StringIO()
    buf.write(HEADER)
    buf.write(f'# Total: {sum(r["code_bytes"] for r in rows):,} code bytes '
              f'(low {sum(r["code_bytes_low"] for r in rows):,}, '
              f'high {sum(r["code_bytes_high"] for r in rows):,}).\n')
    w = csv.DictWriter(buf, fieldnames=COLS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def read_survey(path: Path = SURVEY_CSV) -> list[dict]:
    """The rows of symbols/code_survey.csv (comment lines skipped)."""
    with path.open() as f:
        return list(csv.DictReader(line for line in f if not line.startswith('#')))


CALIBRATE = ('$C0', '$C1', '$C2', '$FD')


def calibrate():
    """Hide the matched routines of each bank in CALIBRATE from the trace and
    compare with the survey made with the source."""
    full = {r['bank']: r for r in survey()}
    for bank in CALIBRATE:
        b = int(bank[1:], 16) - 0xC0
        rows = [r for r in generated.function_rows() if r['bank'] == bank]
        _, reached, xr = trace([off(r['address']) for r in rows])
        n = len(xr.rom)
        truth_code, truth_data = kinds_masks(n)
        code, data = kinds_masks(n, hide_bank=bank)
        lo, hi = b << 16, (b + 1) << 16
        true_code = sum(truth_code[lo:hi])
        hit_code = sum(1 for o in range(lo, hi) if reached[o] and truth_code[o])
        hit_data = sum(1 for o in range(lo, hi) if reached[o] and truth_data[o])
        counted = bytearray(n)
        traced, al, al_hi, al_lo, _, iso_lo = bank_figures(b, code, data, reached, exclusions(xr.rom)[3],
                                                         block_scores(xr), counted)
        found = sum(1 for o in range(lo, hi) if counted[o] and truth_code[o])
        wrong = sum(1 for o in range(lo, hi) if counted[o] and not truth_code[o])
        ref = full[bank]['code_bytes']
        print(f'{bank} hidden: the trace reaches {hit_code:,} of {true_code:,} matched code bytes '
              f'({hit_code / true_code:.1%}) and {hit_data} of {sum(truth_data[lo:hi]):,} matched '
              f'data bytes; estimate {traced + al:,} (low {traced + al_hi:,}, high '
              f'{traced + al_lo + iso_lo:,}) against {ref:,} with the source '
              f'({(traced + al - ref) / ref:+.1%}); trace + allowance count {found:,} of the matched '
              f'code bytes (recall {found / true_code:.1%}) and {wrong:,} other bytes')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--write', action='store_true', help=f'write {SURVEY_CSV}')
    ap.add_argument('--calibrate', action='store_true', help='held-out test on $C0, $C1, $C2 and $FD')
    args = ap.parse_args()
    if not X.ROM_PATH.exists():
        print(f'code_survey: no ROM at {X.ROM_PATH}', file=sys.stderr)
        return 2
    if args.calibrate:
        calibrate()
        return 0
    rows = survey()
    text = render(rows)
    if args.write:
        SURVEY_CSV.write_text(text)
        print(f'Wrote {SURVEY_CSV}')
    total = sum(r['code_bytes'] for r in rows)
    print(f'{"Bank":<5}{"code":>8}{"matched":>9}{"traced":>8}{"allow":>7}{"low-high":>15}'
          f'{"spc700":>8}{"packed":>8}  method')
    for r in rows:
        if r['code_bytes'] or r['spc700_bytes'] or r['compressed_bytes'] or r['code_bytes_high']:
            print(f'{r["bank"]:<5}{r["code_bytes"]:>8,}{r["matched_code_bytes"]:>9,}{r["traced_bytes"]:>8,}'
                  f'{r["allowance_bytes"]:>7,}{r["uncertainty"]:>15}{r["spc700_bytes"]:>8,}'
                  f'{r["compressed_bytes"]:>8,}  {r["method"]}')
    print(f'Total 65816 code bytes: {total:,} (low {sum(r["code_bytes_low"] for r in rows):,}, '
          f'high {sum(r["code_bytes_high"] for r in rows):,}); SPC700 '
          f'{sum(r["spc700_bytes"] for r in rows):,}; compressed {sum(r["compressed_bytes"] for r in rows):,}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
