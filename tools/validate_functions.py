#!/usr/bin/env python3
"""
validate_functions.py — Check symbols/functions.csv and the review log.

functions.csv is generated and not tracked: with the ROM and asar it is
regenerated first when stale (tools/generated.py). Without them (the CI
readability job) only the review log is checked.

  - functions.csv: known columns, addresses `$BB:AAAA` strictly ascending,
    kind code/data, status one of matched/readable/verified, notes on one line (<= 200 chars);
  - the review log, symbols/reviews/ (tools/review_log.py): files named
    legacy.csv or rNNN.csv only, each with the known header line; rows with
    ISO dates, a reviewer, verdict approved or changes and a 12-hex
    source_hash; rows naming a routine that has since been renamed or
    removed are kept as history and count for nothing. The old single
    symbols/reviews.csv must not come back;
  - symbols/spc700_functions.csv (the SPC700 driver's routines, generated
    beside functions.csv): known columns, ARAM addresses `$AAAA` strictly
    ascending with their ROM addresses `$C7:AAAA`, kind, status and notes
    as above. Review rows name these routines like any other;
  - every `verified` function (of either table) has an approved review of
    its current source_hash, and no function is `verified` without one.
"""

import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generated  # noqa: E402
import review_log  # noqa: E402

FUNCTIONS = Path('symbols/functions.csv')
SPC700 = Path('symbols/spc700_functions.csv')
S_COLS = ['address', 'end', 'size', 'rom', 'rom_end', 'name', 'kind', 'status', 'source_hash', 'notes']
ARAM = re.compile(r'^\$[0-9A-F]{4}$')
OLD_REVIEWS = Path('symbols/reviews.csv')
F_COLS = ['address', 'end', 'size', 'name', 'bank', 'subsystem', 'kind', 'status', 'source_hash', 'notes']
R_COLS = review_log.R_COLS
ADDR = re.compile(r'^\$[0-9A-F]{2}:[0-9A-F]{4}$')


def addr_key(a: str) -> int:
    return int(a[1:3], 16) << 16 | int(a[4:], 16)


def main() -> int:
    errors = []
    functions = []
    spc_rows = []
    have_functions = generated.ensure() and FUNCTIONS.exists()
    if have_functions:
        with FUNCTIONS.open() as f:
            reader = csv.DictReader(f)
            if reader.fieldnames != F_COLS:
                errors.append(f'{FUNCTIONS}: columns {reader.fieldnames}, expected {F_COLS}')
            functions = list(reader)
        if SPC700.exists():
            with SPC700.open() as f:
                reader = csv.DictReader(f)
                if reader.fieldnames != S_COLS:
                    errors.append(f'{SPC700}: columns {reader.fieldnames}, expected {S_COLS}')
                spc_rows = list(reader)
        else:
            errors.append(f'{SPC700} is missing; run tools/progress.py --update')
    else:
        print(f'{FUNCTIONS} cannot be generated here (needs the ROM and asar): '
              f'checking the review log only.')
    last = -1
    for n, row in enumerate(functions, 2):
        where = f'{FUNCTIONS}:{n} {row.get("name")}'
        if not ADDR.match(row['address'] or ''):
            errors.append(f'{where}: bad address {row["address"]!r}')
            continue
        if addr_key(row['address']) <= last:
            errors.append(f'{where}: addresses must be strictly ascending')
        last = addr_key(row['address'])
        if row['status'] not in ('matched', 'readable', 'verified'):
            errors.append(f'{where}: unknown status {row["status"]!r}')
        if row['kind'] not in ('code', 'data'):
            errors.append(f'{where}: unknown kind {row["kind"]!r}')
        if '\n' in row['notes'] or len(row['notes']) > 200:
            errors.append(f'{where}: notes must be one line, 200 characters at most')

    last = -1
    for n, row in enumerate(spc_rows, 2):
        where = f'{SPC700}:{n} {row.get("name")}'
        if not ARAM.match(row['address'] or '') or not ADDR.match(row['rom'] or ''):
            errors.append(f'{where}: bad address {row["address"]!r} / {row["rom"]!r}')
            continue
        if int(row['address'][1:], 16) <= last:
            errors.append(f'{where}: addresses must be strictly ascending')
        last = int(row['address'][1:], 16)
        if row['status'] not in ('matched', 'readable', 'verified'):
            errors.append(f'{where}: unknown status {row["status"]!r}')
        if row['kind'] not in ('code', 'data'):
            errors.append(f'{where}: unknown kind {row["kind"]!r}')
        if '\n' in row['notes'] or len(row['notes']) > 200:
            errors.append(f'{where}: notes must be one line, 200 characters at most')
    clash = {r['name'] for r in functions} & {r['name'] for r in spc_rows}
    errors += [f'{SPC700}: {name} is also a row of {FUNCTIONS}' for name in sorted(clash)]

    if OLD_REVIEWS.exists():
        errors.append(f'{OLD_REVIEWS}: the review log is one file per round now; move its rows '
                      f'to {review_log.REVIEWS_DIR}/rNNN.csv (tools/review_log.py)')
    for path in review_log.stray_files():
        errors.append(f'{path}: not a review file name (legacy.csv or rNNN.csv)')
    for path in review_log.review_files():
        with path.open(newline='') as f:
            cols = next(csv.reader(f), None)
        if cols != R_COLS:
            errors.append(f'{path}: header {cols}, expected {R_COLS}')
    reviews = review_log.read_rows()
    names = {row['name']: row for row in functions + spc_rows}
    latest = {}
    historical = 0
    for path, n, _, row in reviews:
        where = f'{path}:{n} {row.get("name")}'
        # A row naming a routine that no longer exists (renamed or removed)
        # stays as history; it just can't make anything verified.
        if have_functions and row['name'] not in names:
            historical += 1
        if not re.match(r'^\d{4}-\d{2}-\d{2}$', row['date'] or ''):
            errors.append(f'{where}: date must be YYYY-MM-DD')
        if not (row['reviewer'] or '').strip():
            errors.append(f'{where}: reviewer is required')
        if row['verdict'] not in ('approved', 'changes'):
            errors.append(f'{where}: verdict must be approved or changes')
        if not re.match(r'^[0-9a-f]{12}$', row['source_hash'] or ''):
            errors.append(f'{where}: source_hash must be the 12-hex hash from {FUNCTIONS}')
        latest[row['name']] = row

    for name, row in names.items():
        review = latest.get(name)
        current = bool(review and review['verdict'] == 'approved'
                       and review['source_hash'] == row['source_hash'])
        if row['status'] == 'verified' and not current:
            errors.append(f'{FUNCTIONS}: {name} is verified without a current approved review')
        if row['status'] == 'readable' and current:
            errors.append(f'{FUNCTIONS}: {name} has a current approval; run tools/progress.py --update')

    for e in errors:
        print(e)
    if errors:
        print(f'FAIL: {len(errors)} problem(s) in symbols/.')
        return 1
    if not have_functions:
        print(f'symbols/ review log valid: {len(reviews)} review row(s).')
        return 0
    print(f'symbols/ valid: {len(functions)} functions, {len(spc_rows)} SPC700 routines, '
          f'{len(reviews)} review row(s)'
          f' ({historical} for routines since renamed or removed).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
