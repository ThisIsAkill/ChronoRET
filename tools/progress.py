#!/usr/bin/env python3
"""
progress.py — The single source of every number about this project.

Builds the source, proves which bytes it emits (tools/verify.py's two-base
method), reads label addresses from asar, applies the readability lint and
the review log, and writes:

  symbols/functions.csv         one row per function: where, how big, status
  symbols/progress.json         totals, per bank, per 4 KB address-map slice
  symbols/progress_history.csv  one row per working day (--update-history)

functions.csv and progress.json are not tracked: every tool that reads them
regenerates them when they are stale (tools/generated.py), and the docs
carry no generated numbers. Run `--update` to have them on disk (the wiki
sync reads them from here). Never type a count or percentage by hand.

A function's status (each level includes the previous):
  matched    every byte from its label to the next is emitted by source
             and equals the ROM
  readable   ...and it has no findings from tools/lint_readability.py
  verified   ...and symbols/reviews.csv holds an independent approval of
             its current source (the review's source_hash still matches)

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
import generated  # noqa: E402
import lint_readability  # noqa: E402
import verify  # noqa: E402

ROM_PATH = Path('roms/chrono_trigger.sfc')
MAIN_ASM = Path('asm/main.asm')
SYMBOLS = Path('symbols')
FUNCTIONS_CSV = generated.FUNCTIONS_CSV
REVIEWS_CSV = SYMBOLS / 'reviews.csv'
PROGRESS_JSON = generated.PROGRESS_JSON
HISTORY_CSV = SYMBOLS / 'progress_history.csv'
# Docs that once carried generated blocks; --check keeps them out.
DOCS = [Path('README.md'), Path('CONTRIBUTING.md'), Path('STATUS.md')]
GENERATED_BLOCK = re.compile(r'<!-- (progress|status):start -->')

# Code-byte denominators: re-surveyed only when the code/data boundary is.
CODE_BYTES_TOTAL = 359278
CODE_BYTES = {'$C0': 61779, '$C1': 63904}
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
                   'source_hash': r.source_hash}
            for name, r in asm_source.regions().items()}


def header_note(lines: list[str], i: int, name: str) -> str:
    """First descriptive sentence of the comment block above a label."""
    block, j = [], i - 1
    while j >= 0 and (lines[j].startswith(';') or lines[j].strip().lower().startswith('org')
                      or not lines[j].strip()):
        if lines[j].startswith(';'):
            block.append(lines[j][1:].strip())
        elif not lines[j].strip() and block:
            break
        j -= 1
    text = []
    for line in reversed(block):
        if not line or set(line) <= set('=-~ '):
            if text:
                break
            continue
        if name in line and '(' in line and not text:
            continue
        if re.match(r'^(?:(?:On entry|Entry|Exit|Callees|Callers?|In|Out)\b|header:)', line):
            break
        line = re.sub(r'^\$[0-9A-F]{2}:[0-9A-F]{4}\s*[—-]\s*' + re.escape(name) + r'\b[^A-Za-z]*', '', line)
        if line:
            text.append(line)
    note = re.split(r'(?<=[.!?])\s', ' '.join(text), maxsplit=1)[0]
    return note[:200]


def read_reviews() -> dict[str, dict]:
    """Latest review row per function name."""
    if not REVIEWS_CSV.exists():
        return {}
    with REVIEWS_CSV.open() as f:
        return {row['name']: row for row in csv.DictReader(f)}


# ── Build ────────────────────────────────────────────────────────────────────

def build_facts(work: Path) -> tuple[set[int], dict[str, int]]:
    rom = ROM_PATH.read_bytes()
    lo = verify.assemble_onto(0x00, work)
    hi = verify.assemble_onto(0xFF, work)
    emitted = {i for i in range(len(lo)) if lo[i] == hi[i] and lo[i] == rom[i]}

    rom_copy, sym = work / 'sym.sfc', work / 'out.sym'
    shutil.copy(ROM_PATH, rom_copy)
    subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', '--symbols=wla',
                    f'--symbols-path={sym}', str(MAIN_ASM), str(rom_copy)],
                   check=True, capture_output=True)
    addrs = {}
    for line in sym.read_text().splitlines():
        m = re.match(r'^([0-9A-F]{2}):([0-9A-F]{4}) (\S+)$', line)
        if m:
            off = snes_to_offset(int(m.group(1), 16), int(m.group(2), 16))
            if off is not None:
                addrs[m.group(3)] = off
    return emitted, addrs


def analyse() -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        emitted, addrs = build_facts(Path(tmp))
    source = source_functions()

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
            'status': 'matched', 'source_hash': source[name]['source_hash'],
            'notes': source[name]['note'], '_start': start,
        })

    # The layout is known now; the lint's caller checks read it from here.
    with generated.generating([dict(f) for f in functions]):
        lint = lint_readability.by_function(lint_readability.collect())
    reviews = read_reviews()
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
            out[level] = {'functions': len(reached), 'bytes': sum(f['size'] for f in reached)}
        return out

    banks = sorted({f'${0xC0 + (o >> 16):02X}' for o in emitted} | set(CODE_BYTES))
    bank_rows = []
    for b in banks:
        rows = [f for f in functions if f['bank'] == b]
        bank_rows.append({'bank': b, 'code_bytes': CODE_BYTES.get(b),
                          'emitted_bytes': sum(1 for o in emitted if f'${0xC0 + (o >> 16):02X}' == b),
                          **level_totals(rows)})

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
    return {'emitted_bytes': len(emitted), 'code_bytes': CODE_BYTES_TOTAL,
            'totals': level_totals(functions), 'banks': bank_rows,
            'slices': slices, 'functions': functions}


# ── Outputs ──────────────────────────────────────────────────────────────────

CSV_COLS = ['address', 'end', 'size', 'name', 'bank', 'subsystem', 'status', 'source_hash', 'notes']


def render_functions_csv(result) -> str:
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=CSV_COLS, lineterminator='\n')
    w.writeheader()
    w.writerows(result['functions'])
    return buf.getvalue()


def render_progress_json(result) -> str:
    data = {k: result[k] for k in ('emitted_bytes', 'code_bytes', 'totals', 'banks', 'slices')}
    return json.dumps({'schema': 2, **data}, indent=2) + '\n'


def render_summary(result) -> str:
    """The local numbers, as a plain table for the terminal."""
    t, code = result['totals'], result['code_bytes']
    lines = [f'{"":<10}{"Functions":>10}{"Bytes":>10}  Share of game code ({code:,} bytes surveyed)']
    for level in LEVELS:
        lines.append(f'{level.capitalize():<10}{t[level]["functions"]:>10}{t[level]["bytes"]:>10,}'
                     f'  {pct(t[level]["bytes"], code)}')
    lines += ['', f'{"Bank":<6}{"Code bytes":>14}' + ''.join(f'{l.capitalize():>20}' for l in LEVELS)]
    for b in result['banks']:
        code_b = f'{b["code_bytes"]:,}' if b['code_bytes'] else 'not surveyed'
        cells = []
        for level in LEVELS:
            cell = f'{b[level]["bytes"]:,}'
            if b['code_bytes']:
                cell += f' ({pct(b[level]["bytes"], b["code_bytes"])})'
            cells.append(f'{cell:>20}')
        lines.append(f'{b["bank"]:<6}{code_b:>14}' + ''.join(cells))
    return '\n'.join(lines)


def render_status_line(result) -> str:
    t, code = result['totals'], result['code_bytes']
    return (f'{t["matched"]["bytes"]:,} of {code:,} bytes of game code are matched byte-exact '
            f'({pct(t["matched"]["bytes"], code)}, {t["matched"]["functions"]} functions); '
            f'{t["readable"]["functions"]} of those meet the readability standard and '
            f'{t["verified"]["functions"]} are verified by independent review.')


def write_generated(result) -> None:
    """Write symbols/functions.csv and progress.json (tools/generated.py)."""
    generated.write_outputs({FUNCTIONS_CSV: render_functions_csv(result),
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
           'matched_functions': t['matched']['functions'],
           'readable_functions': t['readable']['functions'],
           'verified_functions': t['verified']['functions']}
    rows = [r for r in rows if r['date'] != today] + [row]
    return sorted(rows, key=lambda r: r['date'])


def render_history(rows) -> str:
    buf = io.StringIO()
    cols = ['date', 'matched_bytes', 'matched_functions', 'readable_functions', 'verified_functions']
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
    return 0


if __name__ == '__main__':
    sys.exit(main())
