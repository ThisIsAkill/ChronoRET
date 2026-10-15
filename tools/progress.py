#!/usr/bin/env python3
"""
progress.py — The single source of every number about this project.

Builds the source, proves which bytes it emits (tools/verify.py's two-base
method), reads label addresses from asar, applies the readability lint and
the review log, and writes:

  symbols/functions.csv         one row per function: where, how big, kind, status
  symbols/spc700_functions.csv  the same for the SPC700 sound driver (asm/spc700/),
                                by ARAM and ROM address
  symbols/progress.json         totals, per bank, per 4 KB address-map slice, and the
                                SPC700 driver's figure apart (key "spc700")
  symbols/progress_history.csv  one row per working day (--update-history)

The SPC700 driver is counted apart from the 65816 code: its routines are
rows of spc700_functions.csv (never of functions.csv), its share is taken
of the driver's code bytes (tools/spc700.py, CODE_RANGES), and neither the
65816 figure nor its denominator (symbols/code_survey.csv) includes it; the
driver block's emitted bytes are left out of the banks' and slices'
emitted_bytes too (they are spc700.emitted_bytes). Its
statuses work the same way: the lint's SPC700 rules (tools/lint_spc700.py)
and the same review log, keyed by routine name and source_hash.

functions.csv, spc700_functions.csv and progress.json are not tracked: every tool that reads them
regenerates them when they are stale (tools/generated.py), and the docs
carry no generated numbers. Run `--update` to have them on disk (the wiki
sync reads them from here). Never type a count or percentage by hand.

A function's kind is `data` when its source body (label through last
code line) emits only through data directives (db/dw/dl/dd/fill/incbin...)
and `code` otherwise, mixed bodies included (tools/asm_source.py). Every
"share of game code" counts code bytes only; data bytes are reported beside.

A function's status (each level includes the previous):
  matched    every byte from its label to the next is emitted by source
             and equals the ROM
  readable   ...and it has no findings from tools/lint_readability.py
             (a finding grandfathered for its rule alone in
             tools/readability_baseline.txt does not count)
  verified   ...and the review log (symbols/reviews/*.csv, one file per
             round) holds an independent approval of its current source
             (the review's source_hash still matches)

Usage:
    python3 tools/progress.py                   print the summary
    python3 tools/progress.py --update          write symbols/functions.csv, progress.json
    python3 tools/progress.py --update-history  also record today's row
    python3 tools/progress.py --check           fail if a generated file is tracked or a
                                                doc carries a generated block
"""

import argparse
import csv
import datetime as dt
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asm_source  # noqa: E402
import c3pack  # noqa: E402
import generated  # noqa: E402
import lint_readability  # noqa: E402
import review_log  # noqa: E402
import spc700  # noqa: E402
import verify  # noqa: E402

ROM_PATH = Path('roms/chrono_trigger.sfc')
MAIN_ASM = Path('asm/main.asm')
SYMBOLS = Path('symbols')
FUNCTIONS_CSV = generated.FUNCTIONS_CSV
SPC700_CSV = generated.SPC700_CSV
SPC700_SOURCE = Path('asm/spc700/driver.asm')
PROGRESS_JSON = generated.PROGRESS_JSON
HISTORY_CSV = SYMBOLS / 'progress_history.csv'
# Docs that once carried generated blocks; --check keeps them out.
DOCS = [Path('README.md'), Path('CONTRIBUTING.md'), Path('STATUS.md')]
GENERATED_BLOCK = re.compile(r'<!-- (progress|status):start -->')

# Code-byte denominators: symbols/code_survey.csv, one row per bank, written
# by tools/code_survey.py (matched code, plus unmatched code found by a flow
# trace from matched code and the vectors, plus an allowance for code reached
# only through indirect jumps; SPC700 and compressed code are counted apart).
# They change only when the survey is re-run, not as code gets matched. A bank
# fully covered by source needs no survey: its code bytes are those of its
# routines whose kind is code. A bank whose matched code outgrows its survey
# is reported against the matched figure and flagged "survey low"; the total
# moves by the same differences.
CODE_SURVEY = SYMBOLS / 'code_survey.csv'


def read_code_survey(path: Path = CODE_SURVEY) -> dict[str, int]:
    """65816 code bytes per bank ('$C0': n, ...) from the survey ('#' lines are comments)."""
    with path.open() as f:
        return {r['bank']: int(r['code_bytes'])
                for r in csv.DictReader(line for line in f if not line.startswith('#'))}


# progress.json: 2 had bytes per level; 3 splits them into code_bytes and
# data_bytes, adds surveyed_code_bytes and per-bank survey_low.
SCHEMA = 3
SLICE = 0x1000
LEVELS = ('matched', 'readable', 'verified')

SUBSYSTEMS = [
    ('BattleTgt', 'Battle targeting'), ('BattleMenu', 'Battle menu'),
    ('BattleUI', 'Battle status bar'), ('BattleMsg', 'Battle text & numbers'),
    ('BattleSys', 'Battle system'), ('Battle', 'Battle engine'),
    ('Obj_', 'Sprites & objects'), ('Sprite', 'Sprites & objects'),
    ('Sub_', 'Engine (unnamed)'), ('MainInit', 'Boot'), ('Reset', 'Boot'),
    ('NMI', 'Boot'), ('IRQ', 'Boot'), ('BRK', 'Boot'),
    ('Rom', 'ROM header'), ('ROMTitle', 'ROM header'),
]


def subsystem(name: str) -> str:
    return next((label for prefix, label in SUBSYSTEMS if name.startswith(prefix)), 'Engine')


def snes_to_offset(bank: int, addr: int):
    if bank >= 0xC0:
        return (bank - 0xC0) * 0x10000 + addr
    if bank < 0x40 and addr >= 0x8000:
        return bank * 0x10000 + addr
    return None


def offset_to_snes(off: int) -> str:
    return f'${0xC0 + (off >> 16):02X}:{off & 0xFFFF:04X}'


def pct(n: int, d: int) -> str:
    return f'{100 * n / d:.2f}%'


# ── Source ───────────────────────────────────────────────────────────────────

def source_functions() -> dict[str, dict]:
    """Global labels in bank files: file, header note, hash of their source.

    A routine owns everything after the previous routine's last code line
    (its header comments, org, local defines) through its own last code
    line, so editing its header voids its review too (tools/asm_source.py).
    """
    return {name: {'file': r.file, 'note': header_note(r.lines, r.label, name),
                   'source_hash': r.source_hash, 'kind': r.kind}
            for name, r in asm_source.regions().items()}


def header_note(lines: list[str], i: int, name: str) -> str:
    """First descriptive sentence of the comment block above a label.

    The block may open with a title naming the routine, as
    `Name ($C0:005D): text`, `Name ($C1224B–$C1225E, 20 bytes): text` or
    `$C2:0000 — Name (15 bytes, $0000–$000E; then ...): text`, its
    parenthesis possibly running onto the next line. The title is dropped
    and the note is the first sentence of what follows it, up to the
    Entry/Exit/Callers lines.
    """
    block, j = [], i - 1
    while j >= 0:
        line = lines[j].strip()
        if lines[j].startswith(';'):
            block.append(lines[j][1:].strip())
        elif not line:
            if block:
                break
        elif not (line.lower().startswith('org') or line.startswith('!')):
            break
        j -= 1
    text = []
    for line in reversed(block):
        if not line or set(line) <= set('=-~ '):
            if strip_title(' '.join(text), name):
                break
            continue        # nothing but the title yet: the description follows
        if re.match(r'^(?:(?:On entry|Entry|Exit|Callees|Callers?|In|Out)\b|header:)', line):
            break
        title = strip_title(' '.join(text), name)
        if (len(text) == 1 and title and title != text[0] and not title.endswith(('.', ':', ';', ','))
                and re.match(r'[A-Z][a-z]+ ', line)):
            break           # a one-line title summary with no full stop; a sentence follows
        text.append(line)
    return shorten(first_sentence(strip_title(' '.join(text), name)))


def strip_title(text: str, name: str) -> str:
    """Drop a leading `[$BB:AAAA — ]Name [(...)][:|—]` title from a note."""
    m = re.match(r'(?:\$[0-9A-F]{2}:[0-9A-F]{4}\s*[—–-]\s*)?' + re.escape(name) + r'\b\s*', text)
    if not m:
        return text
    rest = text[m.end():]
    if rest.startswith('('):
        depth = 0
        for k, ch in enumerate(rest):
            depth += {'(': 1, ')': -1}.get(ch, 0)
            if depth == 0:
                rest = rest[k + 1:]
                break
        else:
            return ''
    return re.sub(r'^\s*(?:[:—–-]\s*)?', '', rest)


NOTE_MAX = 200  # tools/validate_functions.py's limit for the notes column


def shorten(note: str) -> str:
    """A note of at most NOTE_MAX characters, cut at a word with '...' when longer."""
    if len(note) <= NOTE_MAX:
        return note
    cut = note[:NOTE_MAX - 3]
    if ' ' in cut:
        cut = cut[:cut.rindex(' ')]
    return cut.rstrip(' ,;:-—(') + '...'


def first_sentence(text: str) -> str:
    """Text up to the first sentence end (a full stop not inside a parenthesis)."""
    depth = 0
    for k, ch in enumerate(text):
        depth += {'(': 1, ')': -1}.get(ch, 0)
        if ch in '.!?' and depth <= 0 and (k + 1 == len(text) or text[k + 1] == ' '):
            return text[:k + 1]
    return text


def read_reviews() -> dict[str, dict]:
    """Latest review row per function name (tools/review_log.py)."""
    return review_log.latest()


# ── Build ────────────────────────────────────────────────────────────────────

def build_facts(work: Path) -> tuple[set[int], dict[str, int], dict[str, int]]:
    rom = ROM_PATH.read_bytes()
    lo = verify.assemble_onto(0x00, work)
    hi = verify.assemble_onto(0xFF, work)
    emitted = {i for i in range(len(lo)) if lo[i] == hi[i] and lo[i] == rom[i]}

    rom_copy, sym = work / 'sym.sfc', work / 'out.sym'
    shutil.copy(ROM_PATH, rom_copy)
    subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', '--symbols=wla',
                    f'--symbols-path={sym}', str(MAIN_ASM), str(rom_copy)],
                   check=True, capture_output=True)
    addrs, aram = {}, {}
    for line in sym.read_text().splitlines():
        m = re.match(r'^([0-9A-F]{2}):([0-9A-F]{4}) (\S+)$', line)
        if m:
            off = snes_to_offset(int(m.group(1), 16), int(m.group(2), 16))
            if off is not None:
                addrs[m.group(3)] = off
            elif m.group(1) == '00':
                aram[m.group(3)] = int(m.group(2), 16)     # SPC700 labels: ARAM addresses
    return emitted, addrs, aram


def spc700_functions(emitted: set[int], aram: dict[str, int]) -> list[dict]:
    """Rows for the SPC700 driver's labels (asm/spc700/driver.asm), as
    analyse() makes them for the 65816 code: from each label, the bytes the
    source emits, up to the next label."""
    if not SPC700_SOURCE.exists():
        return []
    rom = ROM_PATH.read_bytes()
    first, base, size = spc700.driver_block(rom)
    source = {r.name: r for r in asm_source.file_regions(SPC700_SOURCE)}
    starts = sorted((a, n) for n, a in aram.items() if n in source and base <= a < base + size)
    code = {a for lo, hi in spc700.CODE_RANGES for a in range(lo, hi + 1)}
    data = {a for lo, hi in spc700.DATA_RANGES for a in range(lo, hi + 1)}
    rows = []
    for idx, (start, name) in enumerate(starts):
        off = first + start - base
        if off not in emitted:
            continue
        nxt = starts[idx + 1][0] if idx + 1 < len(starts) else base + size
        end = start
        while end < nxt and first + end - base in emitted:
            end += 1
        r = source[name]
        rows.append({
            'address': f'${start:04X}', 'end': f'${end - 1:04X}', 'size': end - start,
            'rom': offset_to_snes(off), 'rom_end': offset_to_snes(off + end - 1 - start),
            # by the whole row: 'mixed' (rejected by validate_functions.py) when
            # it runs across the code / data ranges
            'name': name, 'kind': ('code' if set(range(start, end)) <= code
                                   else 'data' if set(range(start, end)) <= data else 'mixed'),
            'status': 'matched', 'source_hash': r.source_hash,
            'notes': header_note(r.lines, r.label, name), 'file': r.file,
        })
    return rows


def analyse() -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        emitted, addrs, aram = build_facts(Path(tmp))
    source = source_functions()
    spc_rows = spc700_functions(emitted, aram)
    # The 65816 figures leave the driver block out: its bytes are counted
    # under "spc700" only (the block is the length word and the program).
    first, _, size = spc700.driver_block(ROM_PATH.read_bytes())
    spc_block = set(range(spc700.DRIVER_ROM, first + size))
    spc_emitted = len(emitted & spc_block)
    emitted = emitted - spc_block
    # The packed $C3 module is counted apart too (under "c3module"): its
    # packed bytes, BankC3_PackedModule, are built from the unpacked source
    # in asm/bankC3/packed/ (tools/c3pack.py).
    pack_block = set(range(c3pack.MODULE_ROM, c3pack.MODULE_ROM + c3pack.MODULE_PACKED_SIZE))
    pack_emitted = len(emitted & pack_block)
    emitted = emitted - pack_block
    module = c3pack.module_figures()

    starts = sorted((off, name) for name, off in addrs.items() if name in source)
    functions = []
    for idx, (start, name) in enumerate(starts):
        if start not in emitted:
            continue
        nxt = starts[idx + 1][0] if idx + 1 < len(starts) else start + 0x10000
        end = start
        while end < nxt and end in emitted:
            end += 1
        functions.append({
            'address': offset_to_snes(start), 'end': offset_to_snes(end - 1), 'size': end - start,
            'name': name, 'bank': f'${0xC0 + (start >> 16):02X}', 'subsystem': subsystem(name),
            'kind': source[name]['kind'], 'status': 'matched', 'source_hash': source[name]['source_hash'],
            'notes': source[name]['note'], '_start': start,
        })

    # The layout is known now; the lint's caller checks read it from here.
    with generated.generating([dict(f) for f in functions], [dict(f) for f in spc_rows]):
        lint = lint_readability.blocking(lint_readability.by_function(lint_readability.collect()))
    reviews = read_reviews()
    for f in spc_rows:
        if f'{f["file"]}:{f["name"]}' not in lint:
            f['status'] = 'readable'
            review = reviews.get(f['name'])
            if review and review['verdict'] == 'approved' and review['source_hash'] == f['source_hash']:
                f['status'] = 'verified'
        del f['file']
    for f in functions:
        src = source[f['name']]
        if f'{src["file"]}:{f["name"]}' not in lint:
            f['status'] = 'readable'
            review = reviews.get(f['name'])
            if review and review['verdict'] == 'approved' and review['source_hash'] == src['source_hash']:
                f['status'] = 'verified'

    def level_totals(rows):
        out = {}
        for level in LEVELS:
            reached = [f for f in rows if LEVELS.index(f['status']) >= LEVELS.index(level)]
            code = sum(f['size'] for f in reached if f['kind'] == 'code')
            data = sum(f['size'] for f in reached if f['kind'] == 'data')
            out[level] = {'functions': len(reached), 'bytes': code + data,
                          'code_bytes': code, 'data_bytes': data}
        return out

    survey = read_code_survey()
    banks = sorted({f'${0xC0 + (o >> 16):02X}' for o in emitted})
    bank_rows = []
    for b in banks:
        rows = [f for f in functions if f['bank'] == b]
        levels = level_totals(rows)
        surveyed = survey.get(b)
        matched_code = levels['matched']['code_bytes']
        emitted_b = sum(1 for o in emitted if f'${0xC0 + (o >> 16):02X}' == b)
        if emitted_b == 0x10000:
            code = matched_code                 # fully covered: counted, not surveyed
        elif surveyed is not None:
            code = max(surveyed, matched_code)
        else:
            code = None
        bank_rows.append({'bank': b, 'code_bytes': code,
                          'surveyed_code_bytes': surveyed,
                          'survey_low': surveyed is not None and matched_code > surveyed,
                          'emitted_bytes': emitted_b,
                          **levels})

    slices = []
    for b in banks:
        base = (int(b[1:], 16) - 0xC0) << 16
        for s in range(base, base + 0x10000, SLICE):
            slices.append({
                'bank': b, 'start': offset_to_snes(s), 'end': offset_to_snes(s + SLICE - 1),
                'emitted_bytes': sum(1 for i in range(s, s + SLICE) if i in emitted),
                'functions': [f['name'] for f in functions if s <= f['_start'] < s + SLICE],
            })
    for f in functions:
        del f['_start']
    # A bank fully covered by source is counted, and a surveyed bank whose
    # matched code outgrows its survey was surveyed low: its share is taken
    # against the matched code. The total moves by the same differences.
    surveyed_total = sum(survey.values())
    moved = sum(b['code_bytes'] - b['surveyed_code_bytes'] for b in bank_rows
                if b['code_bytes'] is not None and b['surveyed_code_bytes'] is not None)
    return {'emitted_bytes': len(emitted), 'code_bytes': surveyed_total + moved,
            'surveyed_code_bytes': surveyed_total,
            'totals': level_totals(functions), 'banks': bank_rows,
            'slices': slices, 'functions': functions,
            'spc700': {'emitted_bytes': spc_emitted,
                       'code_bytes': sum(hi - lo + 1 for lo, hi in spc700.CODE_RANGES),
                       'data_bytes': sum(hi - lo + 1 for lo, hi in spc700.DATA_RANGES),
                       'totals': level_totals(spc_rows)},
            'spc700_functions': spc_rows,
            'c3module': {'emitted_bytes': pack_emitted, **module}}


# ── Outputs ──────────────────────────────────────────────────────────────────

CSV_COLS = ['address', 'end', 'size', 'name', 'bank', 'subsystem', 'kind', 'status', 'source_hash',
            'notes']


def render_functions_csv(result) -> str:
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=CSV_COLS, lineterminator='\n')
    w.writeheader()
    w.writerows(result['functions'])
    return buf.getvalue()


SPC700_COLS = ['address', 'end', 'size', 'rom', 'rom_end', 'name', 'kind', 'status', 'source_hash',
               'notes']


def render_spc700_csv(result) -> str:
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=SPC700_COLS, lineterminator='\n')
    w.writeheader()
    w.writerows(result['spc700_functions'])
    return buf.getvalue()


def render_progress_json(result) -> str:
    # "spc700" (added beside schema 3's keys; nothing else changed): the
    # driver's code and data bytes and its totals per level, apart from the
    # 65816 figures. "c3module" likewise for the packed $C3 module: its
    # packed bytes emitted, and of its unpacked bytes those from source.
    data = {k: result[k] for k in ('emitted_bytes', 'code_bytes', 'surveyed_code_bytes', 'totals',
                                   'banks', 'slices', 'spc700', 'c3module')}
    return json.dumps({'schema': SCHEMA, **data}, indent=2) + '\n'


def render_summary(result) -> str:
    """The local numbers, as a plain table for the terminal.

    Shares count code bytes only; data bytes (tables, fill) are listed beside.
    """
    t, code = result['totals'], result['code_bytes']
    lines = [f'{"":<10}{"Functions":>10}{"Code bytes":>12}{"Data bytes":>12}'
             f'  Share of 65816 code in ROM ({code:,} code bytes)']
    for level in LEVELS:
        lines.append(f'{level.capitalize():<10}{t[level]["functions"]:>10}'
                     f'{t[level]["code_bytes"]:>12,}{t[level]["data_bytes"]:>12,}'
                     f'  {pct(t[level]["code_bytes"], code)}')
    lines += ['', f'{"Bank":<6}{"Code bytes":>14}' + ''.join(f'{l.capitalize() + " code":>22}' for l in LEVELS)
              + f'{"Matched data":>14}']
    flags = []
    for b in result['banks']:
        code_b = f'{b["code_bytes"]:,}' if b['code_bytes'] else 'not surveyed'
        if b['survey_low']:
            code_b += '*'
            flags.append(f'* {b["bank"]}: survey low ({b["surveyed_code_bytes"]:,} code bytes surveyed, '
                         f'{b["code_bytes"]:,} matched); shares use the matched figure')
        cells = []
        for level in LEVELS:
            cell = f'{b[level]["code_bytes"]:,}'
            if b['code_bytes']:
                cell += f' ({pct(b[level]["code_bytes"], b["code_bytes"])})'
            cells.append(f'{cell:>22}')
        lines.append(f'{b["bank"]:<6}{code_b:>14}' + ''.join(cells) + f'{b["matched"]["data_bytes"]:>14,}')
    return '\n'.join(lines + flags)


def render_status_line(result) -> str:
    t, code = result['totals'], result['code_bytes']
    return (f'{t["matched"]["code_bytes"]:,} of {code:,} bytes of 65816 code in ROM (the SPC700 driver and the '
            f'packed $C3 module counted apart) are matched byte-exact '
            f'({pct(t["matched"]["code_bytes"], code)}, {t["matched"]["functions"]} functions, '
            f'plus {t["matched"]["data_bytes"]:,} bytes of data); '
            f'{t["readable"]["functions"]} of those meet the readability standard and '
            f'{t["verified"]["functions"]} are verified by independent review.')


def render_spc700_line(result) -> str:
    s = result['spc700']
    t, code = s['totals'], s['code_bytes']
    return (f'SPC700 sound driver (counted apart): {t["matched"]["code_bytes"]:,} of {code:,} code bytes '
            f'matched byte-exact ({pct(t["matched"]["code_bytes"], code)}, {t["matched"]["functions"]} '
            f'routines, plus {t["matched"]["data_bytes"]:,} of {s["data_bytes"]:,} bytes of data); '
            f'{t["readable"]["functions"]} of those meet the readability standard and '
            f'{t["verified"]["functions"]} are verified by independent review.')


def render_c3module_line(result) -> str:
    s = result['c3module']
    return (f'packed $C3 module (counted apart): {s["source_bytes"]:,} of {s["unpacked_bytes"]:,} unpacked '
            f'bytes from source, the rest incbin\'d from the ROM\'s module; the build packs it back to '
            f'the {s["emitted_bytes"]:,} packed bytes in ROM.')


def write_generated(result) -> None:
    """Write symbols/functions.csv, spc700_functions.csv and progress.json
    (tools/generated.py)."""
    generated.write_outputs({FUNCTIONS_CSV: render_functions_csv(result),
                             SPC700_CSV: render_spc700_csv(result),
                             PROGRESS_JSON: render_progress_json(result)})


def check() -> int:
    """Generated files stay out of git, and the docs carry no generated numbers."""
    problems = []
    tracked = subprocess.run(['git', 'ls-files', '--', *map(str, generated.OUTPUTS)],
                             capture_output=True, text=True).stdout.split()
    problems += [f'{p} is tracked; it is generated (git rm --cached {p})' for p in tracked]
    for path in DOCS:
        if path.exists() and GENERATED_BLOCK.search(path.read_text()):
            problems.append(f'{path} carries a generated progress block; numbers live on the '
                            f'Kajar site and in `python3 tools/progress.py`')
    for p in problems:
        print(p)
    if problems:
        return 1
    if ROM_PATH.exists():
        generated.ensure()
    print('Progress files are generated, untracked and current.')
    return 0


def history_rows(result) -> list[dict]:
    rows = []
    if HISTORY_CSV.exists():
        with HISTORY_CSV.open() as f:
            rows = list(csv.DictReader(f))
    today = dt.date.today().isoformat()
    t = result['totals']
    row = {'date': today, 'matched_bytes': t['matched']['bytes'],
           'matched_code_bytes': t['matched']['code_bytes'],
           'matched_data_bytes': t['matched']['data_bytes'],
           'code_bytes': result['code_bytes'],
           'matched_functions': t['matched']['functions'],
           'readable_functions': t['readable']['functions'],
           'verified_functions': t['verified']['functions']}
    rows = [r for r in rows if r['date'] != today] + [row]
    return sorted(rows, key=lambda r: r['date'])


# matched_bytes counts every matched byte, code and data alike (the only
# figure rows before 2026-10-09 carry); matched_code_bytes / code_bytes is
# the share of game code, and matched_data_bytes the tables and fill beside.
HISTORY_COLS = ['date', 'matched_bytes', 'matched_code_bytes', 'matched_data_bytes', 'code_bytes',
                'matched_functions', 'readable_functions', 'verified_functions']


def render_history(rows) -> str:
    buf = io.StringIO()
    cols = HISTORY_COLS
    w = csv.DictWriter(buf, fieldnames=cols, lineterminator='\n')
    w.writeheader()
    w.writerows({c: r.get(c, '') for c in cols} for r in rows)
    return buf.getvalue()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--update', action='store_true')
    ap.add_argument('--update-history', action='store_true')
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()

    if args.check:
        return check()
    if not ROM_PATH.exists():
        print(f'No ROM at {ROM_PATH}; progress needs a build. Skipping.')
        return 2

    result = analyse()
    write_generated(result)
    if args.update_history:
        HISTORY_CSV.write_text(render_history(history_rows(result)))
    if args.update or args.update_history:
        print('Updated: ' + ', '.join(str(p) for p in generated.OUTPUTS)
              + (f', {HISTORY_CSV}' if args.update_history else ''))
    print(render_summary(result))
    print()
    print(render_status_line(result))
    print(render_spc700_line(result))
    print(render_c3module_line(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
