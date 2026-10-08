#!/usr/bin/env python3
"""
validate_functions.py — Check symbols/functions.csv and symbols/reviews.csv.

functions.csv is generated and not tracked: with the ROM and asar it is
regenerated first when stale (tools/generated.py). Without them (the CI
readability job) only the review log is checked.

  - functions.csv: known columns, addresses `$BB:AAAA` strictly ascending,
    status one of matched/readable/verified, notes on one line (<= 200 chars);
  - reviews.csv: known columns, ISO dates, a reviewer, verdict approved or
    changes and a 12-hex source_hash; rows naming a routine that has since
    been renamed or removed are kept as history and count for nothing;
  - every `verified` function has an approved review of its current
    source_hash, and no function is `verified` without one.
"""

import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generated  # noqa: E402

FUNCTIONS = Path('symbols/functions.csv')
REVIEWS = Path('symbols/reviews.csv')
F_COLS = ['address', 'end', 'size', 'name', 'bank', 'subsystem', 'status', 'source_hash', 'notes']
R_COLS = ['address', 'name', 'date', 'reviewer', 'verdict', 'source_hash', 'notes']
ADDR = re.compile(r'^\$[0-9A-F]{2}:[0-9A-F]{4}$')


def addr_key(a: str) -> int:
    return int(a[1:3], 16) << 16 | int(a[4:], 16)


def main() -> int:
    errors = []
    functions = []
    have_functions = generated.ensure() and FUNCTIONS.exists()
    if have_functions:
        with FUNCTIONS.open() as f:
            reader = csv.DictReader(f)
            if reader.fieldnames != F_COLS:
                errors.append(f'{FUNCTIONS}: columns {reader.fieldnames}, expected {F_COLS}')
            functions = list(reader)
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
        if '\n' in row['notes'] or len(row['notes']) > 200:
            errors.append(f'{where}: notes must be one line, 200 characters at most')

    reviews = []
    if REVIEWS.exists():
        with REVIEWS.open() as f:
            reader = csv.DictReader(f)
            if reader.fieldnames != R_COLS:
                errors.append(f'{REVIEWS}: columns {reader.fieldnames}, expected {R_COLS}')
            reviews = list(reader)
    names = {row['name']: row for row in functions}
    latest = {}
    historical = 0
    for n, row in enumerate(reviews, 2):
        where = f'{REVIEWS}:{n} {row.get("name")}'
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
    print(f'symbols/ valid: {len(functions)} functions, {len(reviews)} review row(s)'
          f' ({historical} for routines since renamed or removed).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
