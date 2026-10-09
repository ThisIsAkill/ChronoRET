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

The source hash covers the whole region except the generated Callers block
of the header (tools/callers.py): the lines in exactly the form that tool
writes, `; Callers (<count>): ...` or `; Callers of <Sub-entry> (<count>):
...` and the `;   ...` lines continuing it. The lint fails unless those
lines are exactly what tools/callers.py generates, so nothing hand-written
escapes the hash. A `; Callers note: ...` line is hand-written and hashed.
"""

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

ASM_GLOB = 'bank*/*.asm'
GLOBAL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):')

# Version 1 hashed the whole region; version 2 leaves out the generated
# Callers block. Review rows carry the hash of the version they were
# recorded under (rows from version 1 were migrated when it changed).
HASH_VERSION = 2
_COUNT = (r'(?:\d+ (?:JSR|JSL|JMP|JML|BRL) sites?'
          r'|\d+ sites: \d+ (?:JSR|JSL|JMP|JML|BRL)(?:, \d+ (?:JSR|JSL|JMP|JML|BRL))+)')
CALLERS_START = re.compile(rf'^; Callers(?: of [A-Za-z_][A-Za-z0-9_]*)? \({_COUNT}\): \S')
CALLERS_CONT = re.compile(r'^;   \S')


def callers_block_lines(region) -> list[int]:
    """Line indices of the generated Callers block(s) in the region's header."""
    out, i = [], region.start
    while i < region.label:
        if CALLERS_START.match(region.lines[i]):
            out.append(i)
            i += 1
            while i < region.label and CALLERS_CONT.match(region.lines[i]):
                out.append(i)
                i += 1
            continue
        i += 1
    return out


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

    def header_comments(self, hand_written: bool = False) -> list[str]:
        """Comment text of the header (the part after ';'), one per line;
        with hand_written=True, without the generated Callers block."""
        out = []
        skip = set(callers_block_lines(self)) if hand_written else set()
        for n, line in enumerate(self.header_lines, self.start):
            if n in skip:
                continue
            idx = line.find(';')
            if idx >= 0:
                out.append(line[idx + 1:])
        return out

    @property
    def kind(self) -> str:
        """'data' when the body (label through last code line) emits only
        through data directives (db/dw/dl/dd/fill/incbin...), else 'code'.

        A body with any instruction, or any line this cannot place (a
        macro call, say), is code; mixed code and data counts as code.
        """
        has_data = False
        for line in self.body_lines:
            word = line_word(line)
            if word is None or word in NON_EMITTING:
                continue
            if word in DATA_DIRECTIVES:
                has_data = True
                continue
            return 'code'
        return 'data' if has_data else 'code'

    @property
    def source_hash(self) -> str:
        skip = set(callers_block_lines(self))
        body = '\n'.join(l.rstrip() for i, l in enumerate(self.lines[self.start:self.end], self.start)
                         if i not in skip).strip()
        return hashlib.sha256(f'v{HASH_VERSION}\n{body}'.encode()).hexdigest()[:12]


DATA_DIRECTIVES = {'db', 'dw', 'dl', 'dd', 'fill', 'fillbyte', 'incbin', 'pad', 'padbyte', 'skip'}
# Assembler lines that emit nothing (a body made of these and data is data).
NON_EMITTING = {'org', 'base', 'warnpc', 'assert', 'print', 'namespace', 'table', 'cleartable',
                'pushpc', 'pullpc', 'pushbase', 'pullbase', 'optimize', 'check', 'math', 'arch',
                'freespacebyte', 'error', 'warn', 'undef'}
_LABEL_PREFIX = re.compile(r'^(?:[A-Za-z_.][A-Za-z0-9_.]*:|[+\-]+:?)\s*')


def line_word(line: str):
    """The lower-cased first word a line emits through (mnemonic without its
    .b/.w/.l suffix, or directive), or None for a blank, comment, label-only
    or define line."""
    s = line.split(';', 1)[0].strip()
    while True:
        m = _LABEL_PREFIX.match(s)
        if not m or not m.group(0):
            break
        s = s[m.end():]
    if not s or s.startswith('!') or s.startswith('{') or s.startswith('}'):
        return None
    word = s.split()[0].lower()
    return word.split('.', 1)[0] if word not in ('db', 'dw', 'dl', 'dd') else word


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
