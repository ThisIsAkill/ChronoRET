#!/usr/bin/env python3
"""
sync_progress.py — Generate the wiki's progress data from the code.

Every number the wiki shows comes from here; nothing is typed by hand.
It assembles the source (via tools/verify.py's two-base method), reads the
label addresses asar reports, and writes into the wiki repo:

  docs/data/progress.json          totals, per bank, per slice
  docs/data/functions.csv          one row per function (status, notes)
  docs/data/progress_history.json  verified bytes/functions per working day

A function is *verified* when every byte from its label to the next label
(within source-emitted code) is emitted by source and matches the ROM, and
*readable* when it is not in tools/readability_baseline.txt.

Usage:
    python3 tools/sync_progress.py [--wiki ../chrono-trigger-wiki] [--no-history]
"""

import argparse
import csv
import datetime as dt
import io
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify  # noqa: E402

ROM_PATH = Path('roms/chrono_trigger.sfc')
MAIN_ASM = Path('asm/main.asm')
BASELINE = Path('tools/readability_baseline.txt')

# Code-byte denominators (re-surveyed only when the code/data boundary is;
# see the wiki's Bank Map). Banks without a survey report matched bytes only.
CODE_BYTES_TOTAL = 359278
CODE_BYTES = {'$C0': 61779, '$C1': 63904}
SLICE = 0x1000

SUBSYSTEMS = [
    ('BattleTgt', 'Battle targeting'), ('BattleMenu', 'Battle menu'),
    ('BattleUI', 'Battle status bar'), ('BattleMsg', 'Battle text & numbers'),
    ('BattleSys', 'Battle system'), ('Battle', 'Battle engine'),
    ('Obj_', 'Sprites & objects'), ('Sprite', 'Sprites & objects'),
    ('Sub_', 'Engine (unnamed)'), ('MainInit', 'Boot'), ('Reset', 'Boot'),
    ('NMI', 'Boot'), ('IRQ', 'Boot'), ('BRK', 'Boot'),
]


def subsystem(name: str) -> str:
    for prefix, label in SUBSYSTEMS:
        if name.startswith(prefix):
            return label
    return 'Engine'


def snes_to_offset(bank: int, addr: int) -> int | None:
    if bank >= 0xC0:
        return (bank - 0xC0) * 0x10000 + addr
    if bank < 0x40 and addr >= 0x8000:
        return bank * 0x10000 + addr
    return None


def offset_to_snes(off: int) -> str:
    return f'${0xC0 + (off >> 16):02X}:{off & 0xFFFF:04X}'


def source_labels(root: Path) -> dict[str, tuple[str, str]]:
    """Global labels defined in bank files -> (file, header note)."""
    found = {}
    for path in sorted((root / 'asm').glob('bank*/*.asm')):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):', line)
            if m:
                found[m.group(1)] = (str(path.relative_to(root)), header_note(lines, i, m.group(1)))
    return found


def header_note(lines: list[str], i: int, name: str) -> str:
    """First descriptive sentence of the comment block above a label."""
    block = []
    j = i - 1
    while j >= 0 and (lines[j].startswith(';') or lines[j].strip().lower().startswith('org')
                      or not lines[j].strip()):
        if lines[j].startswith(';'):
            block.append(lines[j][1:].strip())
        elif not lines[j].strip() and block:
            break
        j -= 1
    block.reverse()
    text = []
    for line in block:
        if not line or set(line) <= set('=-~ '):
            if text:
                break
            continue
        if name in line and '(' in line and not text:
            continue  # the "Name ($addr–$addr, N bytes)" title line
        if re.match(r'^(On entry|Entry|Exit|Callees|In|Out)\b', line):
            break
        line = re.sub(r'^\$[0-9A-F]{2}:[0-9A-F]{4}\s*[—-]\s*' + re.escape(name) + r'\b[^A-Za-z]*', '', line)
        if line:
            text.append(line)
    note = ' '.join(text)
    note = re.split(r'(?<=[.!?])\s', note, maxsplit=1)[0]
    return note[:200]


def label_addresses(root: Path, workdir: Path) -> dict[str, int]:
    rom_copy = workdir / 'sym.sfc'
    shutil.copy(root / ROM_PATH, rom_copy)
    sym = workdir / 'out.sym'
    subprocess.run(['asar', '--no-title-check', '--fix-checksum=off', '--symbols=wla',
                    f'--symbols-path={sym}', str(MAIN_ASM), str(rom_copy)],
                   cwd=root, check=True, capture_output=True)
    out = {}
    for line in sym.read_text().splitlines():
        m = re.match(r'^([0-9A-F]{2}):([0-9A-F]{4}) (\S+)$', line)
        if m:
            off = snes_to_offset(int(m.group(1), 16), int(m.group(2), 16))
            if off is not None:
                out[m.group(3)] = off
    return out


def emitted_set(root: Path, workdir: Path) -> tuple[set[int], bytes]:
    rom = (root / ROM_PATH).read_bytes()
    here = Path.cwd()
    try:
        import os
        os.chdir(root)
        lo = verify.assemble_onto(0x00, workdir)
        hi = verify.assemble_onto(0xFF, workdir)
    finally:
        os.chdir(here)
    emitted = {i for i in range(len(lo)) if lo[i] == hi[i] and lo[i] == rom[i]}
    return emitted, rom


def analyse(root: Path) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        emitted, _ = emitted_set(root, work)
        addrs = label_addresses(root, work)
    labels = source_labels(root)
    baseline = set()
    if (root / BASELINE).exists():
        baseline = {l.strip() for l in (root / BASELINE).read_text().splitlines()
                    if l.strip() and not l.startswith('#')}

    starts = sorted((off, name) for name, off in addrs.items() if name in labels)
    functions = []
    for idx, (start, name) in enumerate(starts):
        if start not in emitted:
            continue  # label-only or outside matched code
        nxt = starts[idx + 1][0] if idx + 1 < len(starts) else start + 0x10000
        end = start
        while end < nxt and end in emitted:
            end += 1
        file, note = labels[name]
        bank = f'${0xC0 + (start >> 16):02X}'
        functions.append({
            'address': offset_to_snes(start), 'end': offset_to_snes(end - 1),
            'size': end - start, 'name': name, 'bank': bank,
            'subsystem': subsystem(name), 'status': 'verified',
            'readable': 'no' if f'{file}:{name}' in baseline else 'yes',
            'notes': note, '_start': start,
        })

    banks = {}
    for off in emitted:
        b = f'${0xC0 + (off >> 16):02X}'
        banks[b] = banks.get(b, 0) + 1
    bank_rows = []
    for b in sorted(set(banks) | set(CODE_BYTES)):
        fns = [f for f in functions if f['bank'] == b]
        bank_rows.append({
            'bank': b, 'code_bytes': CODE_BYTES.get(b), 'verified_bytes': banks.get(b, 0),
            'functions': len(fns), 'readable_functions': sum(f['readable'] == 'yes' for f in fns),
        })

    slices = []
    for b in [r['bank'] for r in bank_rows]:
        base = (int(b[1:], 16) - 0xC0) << 16
        for s in range(base, base + 0x10000, SLICE):
            names = [f['name'] for f in functions if s <= f['_start'] < s + SLICE]
            slices.append({
                'bank': b, 'start': offset_to_snes(s), 'end': offset_to_snes(s + SLICE - 1),
                'verified_bytes': sum(1 for i in range(s, s + SLICE) if i in emitted),
                'functions': names,
            })

    for f in functions:
        del f['_start']
    return {
        'totals': {
            'verified_bytes': len(emitted), 'code_bytes': CODE_BYTES_TOTAL,
            'functions': len(functions),
            'readable_functions': sum(f['readable'] == 'yes' for f in functions),
        },
        'banks': bank_rows, 'slices': slices, 'functions': functions,
    }


def history(repo: Path) -> list[dict]:
    """Verified bytes/functions at the last commit of each working day."""
    log = subprocess.run(['git', 'log', '--format=%H %ad', '--date=short', 'HEAD'],
                         cwd=repo, capture_output=True, text=True, check=True).stdout
    last_of_day = {}
    for line in log.splitlines():
        sha, day = line.split()
        last_of_day.setdefault(day, sha)  # log is newest-first
    days = []
    for day in sorted(last_of_day):
        with tempfile.TemporaryDirectory() as tmp:
            tree = Path(tmp) / 'tree'
            subprocess.run(['git', 'worktree', 'add', '-q', '--detach', str(tree), last_of_day[day]],
                           cwd=repo, check=True, capture_output=True)
            try:
                (tree / 'roms').mkdir(exist_ok=True)
                shutil.copy(repo / ROM_PATH, tree / ROM_PATH)
                result = analyse(tree)
                days.append({'date': day, 'commit': last_of_day[day][:7],
                             'verified_bytes': result['totals']['verified_bytes'],
                             'functions': result['totals']['functions']})
            except subprocess.CalledProcessError:
                pass  # a day whose tree doesn't assemble standalone is skipped
            finally:
                subprocess.run(['git', 'worktree', 'remove', '--force', str(tree)],
                               cwd=repo, capture_output=True)
    return days


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--wiki', default='../chrono-trigger-wiki')
    ap.add_argument('--no-history', action='store_true')
    args = ap.parse_args()

    root = Path.cwd()
    result = analyse(root)
    out = Path(args.wiki) / 'docs' / 'data'
    out.mkdir(parents=True, exist_ok=True)
    head = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], capture_output=True,
                          text=True).stdout.strip()

    progress = {'schema': 1, 'generated': dt.date.today().isoformat(), 'commit': head,
                'totals': result['totals'], 'banks': result['banks'], 'slices': result['slices']}
    (out / 'progress.json').write_text(json.dumps(progress, indent=2) + '\n')

    buf = io.StringIO()
    cols = ['address', 'end', 'size', 'name', 'bank', 'subsystem', 'status', 'readable', 'notes']
    w = csv.DictWriter(buf, fieldnames=cols, lineterminator='\n')
    w.writeheader()
    w.writerows(result['functions'])
    (out / 'functions.csv').write_text(buf.getvalue())

    if not args.no_history:
        (out / 'progress_history.json').write_text(json.dumps(history(root), indent=2) + '\n')

    t = result['totals']
    print(f'{t["verified_bytes"]:,} verified bytes, {t["functions"]} functions '
          f'({t["readable_functions"]} readable) -> {out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
