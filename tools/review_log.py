#!/usr/bin/env python3
"""
review_log.py — The review log: one CSV file per review round.

    symbols/reviews/legacy.csv   rows recorded before rounds were numbered
    symbols/reviews/r047.csv     round 47 (three digits or more)

Every file has the same header line:

    address,name,date,reviewer,verdict,source_hash,notes

A new round is always a new file, so two branches recording different
rounds never touch the same file. The files are read in order (legacy.csv,
then the rounds by number, each file top to bottom); for each routine the
last row read is its current verdict.

Shared by tools/progress.py and tools/validate_functions.py.
"""

import csv
import re
from pathlib import Path

REVIEWS_DIR = Path('symbols/reviews')
R_COLS = ['address', 'name', 'date', 'reviewer', 'verdict', 'source_hash', 'notes']
ROUND_FILE = re.compile(r'^r(\d{3,})\.csv$')
LEGACY = 'legacy.csv'


def file_key(path: Path):
    """Sort key of a review file, or None if the name is not a valid one."""
    if path.name == LEGACY:
        return (-1,)
    m = ROUND_FILE.match(path.name)
    return (int(m.group(1)),) if m else None


def review_files() -> list[Path]:
    """The valid review files, in reading order."""
    if not REVIEWS_DIR.is_dir():
        return []
    files = [p for p in REVIEWS_DIR.iterdir() if p.is_file() and file_key(p) is not None]
    return sorted(files, key=file_key)


def stray_files() -> list[Path]:
    """Files in symbols/reviews/ that are not named like a review file."""
    if not REVIEWS_DIR.is_dir():
        return []
    return sorted(p for p in REVIEWS_DIR.iterdir() if file_key(p) is None)


def read_rows() -> list[tuple[Path, int, list, dict]]:
    """(file, line number, header columns, row) for every row, in reading order."""
    out = []
    for path in review_files():
        with path.open(newline='') as f:
            reader = csv.DictReader(f)
            for n, row in enumerate(reader, 2):
                out.append((path, n, reader.fieldnames, row))
    return out


def latest() -> dict[str, dict]:
    """The current (last read) review row per routine name."""
    return {row['name']: row for _, _, _, row in read_rows()}
