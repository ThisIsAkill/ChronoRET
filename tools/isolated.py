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

The file-open check needs strace (Linux). Where strace is missing (macOS,
Windows) or cannot trace, the assembly still runs isolated (the copy, the
placeholders, symlinks refused, asar errors failing) and one warning says
the file-open check was skipped, and the figures made are marked
unchecked (run_mode() 'none': progress.json's "file_check", verify.py's
report). The lint's FILEREAD rule reduces the risk but cannot close it
(asar can build a file read from text in ways no text rule sees): the
strace check is the guarantee. Set CHRONORET_REQUIRE_STRACE=1 to make the check
mandatory (CI's match job does, and installs strace).
"""

import os
import re
import shutil
import subprocess
import sys
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


REQUIRE_ENV = 'CHRONORET_REQUIRE_STRACE'
_warned = []
_modes = set()          # 'strace' / 'none': how this process's isolated runs were checked
_probe = []


def expected_mode() -> str:
    """'strace' when the file-open check can run here (strace present and
    able to trace), else 'none'. Probed once per process."""
    if not _probe:
        ok = False
        if shutil.which('strace') is not None:
            try:
                ok = subprocess.run(['strace', '-qq', '-o', os.devnull, 'true'],
                                    capture_output=True, timeout=30).returncode == 0
            except (OSError, subprocess.SubprocessError):
                ok = False
        _probe.append('strace' if ok else 'none')
    return _probe[0]


def run_mode() -> str:
    """How the isolated runs of this process were checked: 'strace' only if
    every one had the file-open check, 'none' if any ran without it (and
    expected_mode() before any has run). Figures made under 'none' are
    unchecked: the lint's text rules reduce the risk of ROM bytes counted
    as source but do not close it."""
    if not _modes:
        return expected_mode()
    return 'strace' if _modes == {'strace'} else 'none'


def strace_required() -> bool:
    return os.environ.get(REQUIRE_ENV, '') not in ('', '0')


def _without_strace(args, tree, why) -> subprocess.CompletedProcess:
    """The isolated assembly without the file-open check: refused when the
    environment requires the check, else run with one warning."""
    if strace_required():
        raise IsolationError(f'{why}, and {REQUIRE_ENV} requires the file-open check '
                             f'(apt-get install strace)')
    _modes.add('none')
    if not _warned:
        _warned.append(True)
        print(f'warning: {why}: the isolated assembly ran without its check of the files asar '
              f'opens, so the figures are UNCHECKED (file_check "none"; the lint\'s FILEREAD rule '
              f'reduces the risk but does not close it; set {REQUIRE_ENV}=1 to require the '
              f'check, as CI does)', file=sys.stderr)
    r = subprocess.run(['asar', *args], cwd=tree, capture_output=True, text=True)
    if r.returncode != 0:
        raise IsolationError(f'asar failed in the isolated tree:\n{r.stdout}{r.stderr}')
    return r


def run_asar(args: list[str], tree: Path, allowed: Path) -> subprocess.CompletedProcess:
    """Run asar with `args` in `tree` under strace; raise IsolationError when
    it fails or opens a file outside `allowed` (and the system libraries).
    Without strace (or ptrace), see _without_strace."""
    if shutil.which('strace') is None:
        return _without_strace(args, tree, 'strace is not installed')
    allowed = Path(os.path.realpath(allowed))
    with tempfile.TemporaryDirectory() as tmp:
        log = Path(tmp) / 'strace.txt'
        r = subprocess.run(['strace', '-f', '-qq', '-e', 'trace=open,openat,openat2,creat',
                            '-o', str(log), 'asar', *args], cwd=tree, capture_output=True, text=True)
        trace = log.read_text(errors='replace').splitlines() if log.exists() else []
    if not trace:                       # strace could not trace (no ptrace here): asar did not run
        return _without_strace(args, tree, f'strace could not trace asar ({r.stderr.strip()[:120]})')
    if r.returncode != 0:
        raise IsolationError(f'asar failed in the isolated tree:\n{r.stdout}{r.stderr}')
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
    _modes.add('strace')
    return r
