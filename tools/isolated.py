#!/usr/bin/env python3
"""
isolated.py — Assemble the source where it cannot read the ROM.

"Emitted by source" (tools/verify.py for the bank files, tools/c3pack.py's
source_bytes() for the packed $C3 module) is decided by assembling the
source twice onto images of two different fills: the bytes that agree are
the source's. That holds only if nothing in the source reads bytes from a
file that does not change with the fill: the ROM, the ROM's unpacked module
in build/c3pack/, or any other copy. The lint bans such reads by text
(lint_readability.py, FILEREAD); this module makes them impossible to pass
off, whatever the text:

  - the assembly runs in a temporary copy of asm/ only, with no roms/ and no
    build/ beside it (a caller supplies placeholders made of the fill byte
    for the generated files the source reads: build/c3pack/module.lz,
    build/c3pack/rom_module.bin);
  - a symlink anywhere under asm/ is refused (the copy keeps symlinks as
    links, so none could lead out);
  - asar runs under strace, and every file it opens must be inside the
    temporary directory (the copy, the placeholders, its output) or a system
    library; any other open (an absolute path, a path out of the copy) fails
    the run, and so does any asar error (a file not found included).

strace is required (`sudo apt-get install strace`; CI's match job installs
it); without it these checks refuse to run rather than trust the text.
"""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

SYSTEM_PREFIXES = ('/etc/ld.so.', '/lib/', '/lib64/', '/usr/lib/', '/usr/lib64/', '/usr/local/lib/',
                   '/proc/', '/dev/null', '/sys/')
OPEN = re.compile(r'^(?:\[pid\s+)?\d*\]?\s*(open|openat|openat2|creat)\((?:AT_FDCWD|\d+), "((?:[^"\\]|\\.)*)"'
                  r'.*\)\s+=\s+(-?\d+)')
OPEN_NO_DIRFD = re.compile(r'^\d*\s*(open|creat)\("((?:[^"\\]|\\.)*)".*\)\s+=\s+(-?\d+)')
UNFINISHED = re.compile(r'(open|openat|openat2|creat)\((?:(?:AT_FDCWD|\d+), )?"((?:[^"\\]|\\.)*)".*<unfinished')


class IsolationError(RuntimeError):
    pass


def make_tree(root: Path, dest: Path) -> Path:
    """Copy root/asm to dest/asm, refusing any symlink under it; returns dest."""
    src = Path(root) / 'asm'
    if src.is_symlink():
        raise IsolationError(f'{src} is a symlink')
    for dirpath, dirnames, filenames in os.walk(src):
        for name in dirnames + filenames:
            p = Path(dirpath) / name
            if p.is_symlink():
                raise IsolationError(f'symlink under asm/: {p} (the source may not link to files '
                                     f'outside it)')
    shutil.copytree(src, Path(dest) / 'asm', symlinks=True)
    return Path(dest)


def run_asar(args: list[str], tree: Path, allowed: Path) -> subprocess.CompletedProcess:
    """Run asar with `args` in `tree` under strace; raise IsolationError when
    it fails or opens a file outside `allowed` (and the system libraries)."""
    if shutil.which('strace') is None:
        raise IsolationError('strace is needed to check that the source reads no file outside it '
                             '(sudo apt-get install strace)')
    allowed = Path(os.path.realpath(allowed))
    with tempfile.TemporaryDirectory() as tmp:
        log = Path(tmp) / 'strace.txt'
        r = subprocess.run(['strace', '-f', '-qq', '-e', 'trace=open,openat,openat2,creat',
                            '-o', str(log), 'asar', *args], cwd=tree, capture_output=True, text=True)
        trace = log.read_text(errors='replace').splitlines() if log.exists() else []
    if r.returncode != 0:
        raise IsolationError(f'asar failed in the isolated tree:\n{r.stdout}{r.stderr}')
    if not trace:
        raise IsolationError('strace recorded nothing (is ptrace allowed here?)')
    outside = set()
    for line in trace:
        if 'open' not in line and 'creat' not in line:
            continue
        m = OPEN.match(line) or OPEN_NO_DIRFD.match(line)
        if m and int(m.group(3)) < 0:
            continue                        # the open failed: nothing read
        if not m:
            # An open split by strace (`<unfinished ...>`): check its path
            # whatever came of it; a `resumed` line carries no path.
            u = UNFINISHED.search(line)
            if u:
                m = u
            elif 'resumed>' in line:
                continue
            else:
                outside.add(f'(unparsed) {line.strip()}')
                continue
        path = m.group(2).encode().decode('unicode_escape')
        real = Path(os.path.realpath(os.path.join(tree, path)))
        if real == allowed or allowed in real.parents:
            continue
        if str(real).startswith(SYSTEM_PREFIXES):
            continue
        outside.add(str(real))
    if outside:
        raise IsolationError('the source read file(s) from outside itself (only asm/ and the '
                             'generated placeholders may be read): ' + ', '.join(sorted(outside)))
    return r
