#!/usr/bin/env python3
"""
asm_source.py — Where each routine's source starts and ends in the bank files.

Shared by tools/progress.py (source hash, header note) and
tools/lint_readability.py (header rules), so both agree on what a routine's
header is.

A routine is a global label in asm/bank*/*.asm. It owns everything after the
previous routine's last code line (its header comments, org, local defines)
through its own last code line. The header is the part of that region up to
and including the label line.
"""

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

ASM_GLOB = 'bank*/*.asm'
GLOBAL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):')


@dataclass
class Region:
    name: str
    file: str
    lines: list          # every line of the file (shared)
    start: int           # first line of the region (0-based)
    label: int           # the label line
    end: int             # one past the routine's last code line

    @property
    def header_lines(self) -> list[str]:
        return self.lines[self.start:self.label + 1]

    @property
    def body_lines(self) -> list[str]:
        return self.lines[self.label:self.end]

    def header_comments(self) -> list[str]:
        """Comment text of the header (the part after ';'), one per line."""
        out = []
        for line in self.header_lines:
            idx = line.find(';')
            if idx >= 0:
                out.append(line[idx + 1:])
        return out

    @property
    def source_hash(self) -> str:
        body = '\n'.join(l.rstrip() for l in self.lines[self.start:self.end]).strip()
        return hashlib.sha256(body.encode()).hexdigest()[:12]


def _is_code(line: str) -> bool:
    # An instruction or data line (indented, not a comment) or a label.
    s = line.strip()
    return bool(s) and not s.startswith(';') and (line[:1].isspace() or s.endswith(':')
                                                  or GLOBAL.match(line) is not None)


def file_regions(path: Path) -> list[Region]:
    lines = path.read_text().splitlines()
    starts = [i for i, l in enumerate(lines) if GLOBAL.match(l)]

    def last_code(lo: int, hi: int) -> int:
        for j in range(hi - 1, lo - 1, -1):
            if _is_code(lines[j]) and not lines[j].strip().lower().startswith('org'):
                return j
        return lo

    regions, prev_end = [], 0
    for n, i in enumerate(starts):
        nxt = starts[n + 1] if n + 1 < len(starts) else len(lines)
        end = last_code(i, nxt) + 1
        regions.append(Region(GLOBAL.match(lines[i]).group(1), str(path), lines, prev_end, i, end))
        prev_end = end
    return regions


def regions(root: Path = Path('asm')) -> dict[str, Region]:
    """Every global label in the bank files, by name, in file order."""
    found = {}
    for path in sorted(root.glob(ASM_GLOB)):
        for r in file_regions(path):
            found[r.name] = r
    return found
