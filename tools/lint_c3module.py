#!/usr/bin/env python3
"""
lint_c3module.py — The readability lint's rules for the packed $C3 module.

The module's source (asm/bankC3/packed/module.asm, its unpacked form at
$7E:3000-$7E:B57E) is 65816 code like the bank files, but it is assembled
on its own and its addresses are in WRAM, so the rules that read the ROM
layout or tools/xref.py do not apply as they are. tools/lint_readability.py
runs these and reports them the same way (a finding keeps the routine at
`matched` in symbols/c3module_functions.csv and fails the gate):

  ADDR, CALL, CONST, WIDTH, OPCODE, PLUMB
         the instruction rules, exactly as for the bank files
         (lint_readability.lint_file).
  HEADER, DPDB
         as for the bank files: an Entry and an Exit line (or `header: see
         <Parent>` naming a routine of the file whose header names it;
         tables exempt), and the Entry line states DP and DB.
  SIZE   a claim `Name (N bytes, $XXXX–$YYYY)` (module addresses, $7E:
         implied or written) agrees with symbols/c3module_functions.csv:
         the routine alone or with its `header: see` sub-entries. Needs
         the ROM and asar.
  CALLERS until a generator exists the callers are hand-written: every
         JSR, JSL, JMP, JML or BRL to the routine or its sub-entries from
         outside them that tools/c3module.py's trace of the module finds
         (in matched code or not) is named by its address ($XXXX) on the
         header's `Callers note:` lines (or the lines continuing them).
         Needs the ROM. Cannot be opted out of.
  KERNEL the module is assembled apart from asm/main.asm, so it reaches
         kernel and engine labels through defines named after them
         (module.inc, `!C3_ModuleFrame = $C308D0`), and the kernel reaches
         module routines through defines in asm/include/ram_engine.inc
         (`!C3Mod_RunTasks = $7E398A`). Each such define whose name is a
         label on the other side holds that label's address. Needs the
         ROM and asar.

  ROMBYTES the bytes not matched yet come from the ROM's module only
         through %C3ModRomBytes: no incbin (or readfile..()) anywhere in
         asm/bankC3/packed/ but the one in that macro's body in module.inc.
         Cannot be opted out of. (lint_readability.py's PLUMB rule does the
         same for the bank files, and for module.asm too.)

A label whose body is only %C3ModRomBytes (a block not matched yet, kept as
the ROM's bytes) is not a routine: no rule applies to it.

Opt out of one finding with `; lint-ok: <reason>` on the line (the label
line for header rules), as for the bank files.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asm_source  # noqa: E402

SOURCE_FILES = ('asm/bankC3/packed/module.asm',)   # routines (module.inc: names; unmatched.asm: stubs)
MODULE_INC = Path('asm/bankC3/packed/module.inc')
RAM_ENGINE = Path('asm/include/ram_engine.inc')
ROM_BYTES = re.compile(r'^\s*%C3ModRomBytes\(')
SIZE_CLAIM = re.compile(r'(?:\b([A-Za-z_][A-Za-z0-9_]*)\s+)?\((\d[\d,]*) bytes?, '
                        r'\$(?:7E:)?([0-9A-Fa-f]{4})\s*[–-]\s*\$(?:7E:)?([0-9A-Fa-f]{4})\)')
SITE = re.compile(r'\$([0-9A-Fa-f]{4})(?![0-9A-Fa-f:])')
CALLERS_NOTE = re.compile(r'^\s?Callers note:')
CONTINUED = re.compile(r'^\s{2,}\S')
DEFINE = re.compile(r'^!([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$([0-9A-Fa-f]{6})\b')


def _ok(line: str) -> bool:
    i = line.find(';')
    return i >= 0 and re.search(r'lint-ok:\s*\S', line[i:]) is not None


def is_placeholder(region) -> bool:
    """A block not matched yet: its body is the ROM's bytes only."""
    body = [l for l in region.body_lines[1:] if l.strip() and not l.strip().startswith(';')]
    return bool(body) and all(ROM_BYTES.match(l) for l in body)


def callers_notes(region) -> list[str]:
    out, inside = [], False
    for c in region.header_comments(hand_written=True):
        if CALLERS_NOTE.match(c):
            inside = True
        elif not CONTINUED.match(c):
            inside = False
        if inside:
            out.append(c)
    return out


def num(text: str) -> int:
    return int(text.lstrip('$').split(':')[-1], 16)


def header_findings(path: Path, rows=None, sites=None):
    """(function, line, rule, text) for HEADER, DPDB, SIZE and CALLERS."""
    import lint_readability as L
    regions = [r for r in asm_source.file_regions(path) if not is_placeholder(r)]
    by_name = {r.name: r for r in regions}
    out = []

    def report(r, rule, text):
        if rule == 'CALLERS' or not _ok(r.lines[r.label]):
            out.append((r.name, r.label + 1, rule, text))

    parent_of = {}
    for r in regions:
        m = L.SEE_PARENT.search('\n'.join(r.header_comments()))
        if m:
            parent_of[r.name] = m.group(1)
    ok = set()
    for r in regions:
        if L.is_table(r) or r.name in parent_of:
            continue
        if L._has_entry_exit(r):
            ok.add(r.name)
            for text in L.dpdb_findings(r):
                report(r, 'DPDB', text)
        else:
            report(r, 'HEADER', f'{r.name}: header has no Entry/Exit line '
                                f'(or `header: see <Parent>` for a sub-entry)')
    for name, parent in parent_of.items():
        if parent not in ok:
            report(by_name[name], 'HEADER', f'{name}: `header: see {parent}` names no routine '
                                            f'in this file with an Entry/Exit header')
        elif not re.search(rf'\b{name}\b', ' '.join(by_name[parent].header_comments(hand_written=True))):
            report(by_name[name], 'HEADER', f'{name}: its parent {parent} does not name it')

    if rows is None:
        return out
    lay = {r['name']: r for r in rows}
    children = {}
    for name, parent in parent_of.items():
        children.setdefault(parent, []).append(name)

    def span(name):
        names = [n for n in [name] + children.get(name, []) if n in lay]
        return (min(num(lay[n]['address']) for n in names), max(num(lay[n]['end']) for n in names))

    for r in regions:
        if r.name not in lay:
            continue
        text = re.sub(r'\s+', ' ', ' '.join(r.header_comments(hand_written=True)))
        for m in SIZE_CLAIM.finditer(text):
            who = m.group(1) if m.group(1) in lay else r.name
            if who != r.name and who not in children.get(r.name, []):
                continue                                # a claim about another routine
            n, lo, hi = int(m.group(2).replace(',', '')), int(m.group(3), 16), int(m.group(4), 16)
            row = lay[who]
            alone = (num(row['address']), num(row['end']))
            fam = span(who) if who == r.name else alone
            if (lo, hi) not in (alone, fam) or n != hi - lo + 1:
                report(r, 'SIZE', f'{who}: claims {n} bytes, ${lo:04X}–${hi:04X}; the layout has '
                                  f'${alone[0]:04X}–${alone[1]:04X} ({alone[1] - alone[0] + 1} bytes)'
                                  + (f', ${fam[0]:04X}–${fam[1]:04X} with its sub-entries'
                                     if fam != alone else ''))

    if sites is None:
        return out
    for r in regions:
        if r.name not in lay or r.name in parent_of or L.is_table(r):
            continue
        lo, hi = span(r.name)
        named = {int(x, 16) for x in SITE.findall(' '.join(callers_notes(r)))}
        members = [n for n in [r.name] + children.get(r.name, []) if n in lay]
        missing = sorted(s for n in members for s in sites.get(num(lay[n]['address']), [])
                         if not lo <= s <= hi and s not in named)
        if missing:
            report(r, 'CALLERS', f'{r.name}: the header does not name the call site(s) '
                                 + ', '.join(f'${s:04X}' for s in missing))
    return out


def kernel_findings(module_labels, rom_labels):
    """KERNEL: the defines that stand for labels across the two assemblies.
    module_labels: {name: $7Exxxx}; rom_labels: {name: SNES address}."""
    out = []
    for path, other, side in ((MODULE_INC, rom_labels, 'kernel'),
                              (RAM_ENGINE, module_labels, 'module')):
        if not path.exists():
            continue
        for no, line in enumerate(path.read_text().splitlines(), 1):
            m = DEFINE.match(line)
            if not m or m.group(1) not in other or _ok(line):
                continue
            value, want = int(m.group(2), 16), other[m.group(1)]
            if value != want:
                out.append((str(path), '<defines>', no, 'KERNEL',
                            f'!{m.group(1)} = ${value:06X}, but the {side} label {m.group(1)} is at '
                            f'${want:06X}'))
    return out


ROMBYTES_LINE = 'incbin "!C3Mod_RomImage":<start>-!C3Mod_Code..<end>-!C3Mod_Code'


def rombytes_findings(root: Path = Path('asm/bankC3/packed')):
    """ROMBYTES: (path, function, line, rule, text) for every file read in
    the module's source but the one in %C3ModRomBytes."""
    import lint_readability as L
    out = []
    for path in sorted(root.glob('*')):
        if path.suffix not in ('.asm', '.inc'):
            continue
        macro = None
        for no, raw in enumerate(path.read_text().splitlines(), 1):
            code = L.split_comment(raw)[0].strip()
            if code.lower().startswith('macro '):
                macro = code.split()[1].split('(')[0]
            elif code.lower() == 'endmacro':
                macro = None
            if not (code.lower().startswith('incbin') or L.READS_FILE.search(code)):
                continue
            if path.name == 'module.inc' and macro == 'C3ModRomBytes' and code == ROMBYTES_LINE:
                continue
            out.append((str(path), '<file>', no, 'ROMBYTES',
                        f'bytes read from a file outside %C3ModRomBytes: {code}'))
    return out


def module_sites():
    """{target: [site, ...]} from tools/c3module.py's trace, or None without the ROM."""
    import c3module
    import c3pack
    if not c3pack.ROM_PATH.exists():
        return None
    insns, _ = c3module.trace(c3module.module_bytes())
    return c3module.call_sites(insns)


def rom_labels():
    """{name: SNES address} of the main build's matched routines (functions.csv)."""
    import generated
    out = {}
    for row in generated.function_rows():
        a = row['address']
        out[row['name']] = int(a[1:3], 16) << 16 | int(a[4:], 16)
    return out


def findings(rows=None, sites=None, labels=None):
    """(path, function, line, rule, text) for the module's source."""
    import lint_readability as L
    out = []
    for name in SOURCE_FILES:
        path = Path(name)
        if not path.exists():
            continue
        found = L.lint_file(path) + header_findings(path, rows, sites)
        out += [(str(path), f, no, rule, text) for f, no, rule, text in found]
    out += rombytes_findings()
    if labels is not None:
        out += kernel_findings(*labels)
    return out


def collect():
    """findings() with the layout, the call sites and the labels when they can be had."""
    import c3pack
    import generated
    if not generated.can_generate():
        return findings()
    rows = generated.c3module_rows()
    labels = (c3pack.module_labels(), rom_labels())
    return findings(rows, module_sites(), labels)


if __name__ == '__main__':
    found = collect()
    for path, function, no, rule, text in found:
        print(f'{path}:{no}: {rule}: {text}')
    print(f'{len(found)} finding(s).')
    sys.exit(1 if found else 0)
