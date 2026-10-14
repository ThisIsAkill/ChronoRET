#!/usr/bin/env python3
"""
lint_spc700.py — The readability lint's rules for the SPC700 sound driver.

tools/lint_readability.py applies these to asm/spc700/*.asm (the 65816
rules read asm/bank*/*.asm only) and reports them the same way, so a
finding keeps the routine at `matched` in symbols/spc700_functions.csv and
fails the gate like any other. The rules follow STYLE.md's, translated:

  ADDR   memory operands are named (a !Spc_/!SPC_/!DSP_ define or a label),
         never a raw $address.
  CALL   branch, CALL and JMP targets are labels, never raw addresses.
  CONST  immediates above 8 are named constants (`lint-ok:` for a literal
         whose value is the point, as for the 65816 rule).
  WIDTH  every instruction with a named direct-page or absolute operand
         says .b or .w (branches, CALL, JMP, PCALL, TCALL and the MOV1-style
         bit instructions, which have one encoding each, are exempt).
  OPCODE no `db` standing in for an instruction.
  PLUMB  no print/assert/warnpc/error.
  HEADER every routine has an Entry and an Exit line, or `header: see
         <Parent>` naming a routine of the file whose header names it
         (tables exempt), as for the 65816 rule.
  STATE  the Entry line (with the lines continuing it) states P, the
         direct-page flag (`P=0`, `P any`, ...): the SPC700's counterpart of
         DPDB.
  SIZE   a claim `Name (N bytes, $XXXX–$YYYY; ROM $C7:xxxx–$yyyy)` agrees
         with symbols/spc700_functions.csv: start, end and size of the
         routine (alone or with its `header: see` sub-entries) in ARAM, and
         the ROM range when given. Needs the ROM and asar.
  CALLERS until a generator exists the callers are hand-written: every
         CALL, JMP or PCALL to the routine or its sub-entries from outside
         them (found by tools/spc700.py's trace of the whole driver, matched
         or not) is named by its ARAM address ($XXXX) somewhere in the
         header. Needs the ROM.

Opt out of one finding with `; lint-ok: <reason>` on the line (the label
line for header rules), as for the 65816 rules.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asm_source  # noqa: E402
import spc700  # noqa: E402

GLOB = 'asm/spc700/*.asm'
SOURCE_FILES = ('asm/spc700/driver.asm',)      # the files with routines (the rest: names, stubs)

MNEMONICS = {m for m, _, _ in spc700.OPCODES.values()}
BRANCHES = {'bra', 'beq', 'bne', 'bcc', 'bcs', 'bmi', 'bpl', 'bvc', 'bvs'}
FLOW = BRANCHES | {'call', 'jmp', 'pcall', 'tcall'}
TARGET_LAST = {'bbs', 'bbc', 'cbne', 'dbnz'}    # memory operand(s), then a branch target
ONE_FORM = {'mov1', 'and1', 'or1', 'eor1', 'not1'}
REGISTERS = {'a', 'x', 'y', 'ya', 'sp', 'p', 'c', 'psw'}
PLUMBING = {'print', 'assert', 'warnpc', 'error'}

GLOBAL_LABEL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):(.*)$')
LOCAL_LABEL = re.compile(r'^(\.[A-Za-z0-9_]+|[+-]+):(.*)$')
INSTR = re.compile(r'^([A-Za-z][A-Za-z0-9]*)(\.[bwBW])?(?:\s+(.*))?$')
RAW_HEX = re.compile(r'(?<![A-Za-z0-9_!.])\$[0-9A-Fa-f]+')
NAME = re.compile(r'(?<![A-Za-z0-9_.$])[A-Za-z_][A-Za-z0-9_]*')
STATE_P = re.compile(r'\bP\b')
SIZE_CLAIM = re.compile(r'(?:\b([A-Za-z_][A-Za-z0-9_]*)\s+)?\((\d[\d,]*) bytes?, '
                        r'\$([0-9A-Fa-f]{4})\s*[–-]\s*\$([0-9A-Fa-f]{4})'
                        r'(?:; ROM \$C7:([0-9A-Fa-f]{4})\s*[–-]\s*\$([0-9A-Fa-f]{4}))?')
SITE = re.compile(r'\$([0-9A-Fa-f]{4})(?![0-9A-Fa-f])')


def _split(line: str):
    i = line.find(';')
    return (line, '') if i < 0 else (line[:i], line[i + 1:])


def _ok(comment: str) -> bool:
    return re.search(r'lint-ok:\s*\S', comment) is not None


def _literal(text: str):
    m = re.match(r'^\$([0-9A-Fa-f]+)$|^%([01_]+)$|^(\d+)$', text.strip())
    if not m:
        return None
    if m.group(1):
        return int(m.group(1), 16)
    if m.group(2):
        return int(m.group(2).replace('_', ''), 2)
    return int(m.group(3))


def _memory_parts(mnemonic: str, operand: str) -> list[str]:
    """The operand parts that address memory (immediates, registers and
    branch targets left out)."""
    parts = [p.strip() for p in operand.split(',')]
    if mnemonic in TARGET_LAST:
        parts = parts[:-1]
    out = []
    for p in parts:
        if not p or p.startswith('#') or p.lower() in REGISTERS:
            continue
        if re.fullmatch(r'\((x\+?|y)\)', p.lower()):
            continue
        out.append(p)
    return out


def body_findings(path: Path):
    """(function, line, rule, text) for the instruction rules."""
    out, function = [], '<file-top>'
    in_macro = False
    for no, raw in enumerate(path.read_text().splitlines(), 1):
        code, comment = _split(raw)
        s = code.strip()
        if not s:
            continue

        def report(rule):
            if not _ok(comment):
                out.append((function, no, rule, raw.strip()))

        if not raw[:1].isspace():
            m = GLOBAL_LABEL.match(s)
            if m:
                function = m.group(1)
                s = m.group(2).strip()
                if not s:
                    continue
        m = LOCAL_LABEL.match(s)
        if m:
            s = m.group(2).strip()
            if not s:
                continue
        word = s.split()[0].lower()
        if word == 'macro':
            in_macro = True
            continue
        if word == 'endmacro':
            in_macro = False
            continue
        if in_macro:
            continue
        if word in PLUMBING:
            report('PLUMB')
            continue
        if word in ('db', 'dw', 'dl', 'dd'):
            first = comment.strip().split()[:1]
            if first and first[0].lower() in MNEMONICS:
                report('OPCODE')
            continue
        m = INSTR.match(s)
        if not m or m.group(1).lower() not in MNEMONICS:
            continue
        mnemonic, width, operand = m.group(1).lower(), m.group(2), (m.group(3) or '').strip()
        if not operand:
            continue
        for imm in re.findall(r'#([^,]+)', operand):
            value = _literal(imm)
            if value is not None and value > 8:
                report('CONST')
        rest = re.sub(r'#[^,]+', '', operand)
        if RAW_HEX.search(rest):
            report('CALL' if mnemonic in FLOW or mnemonic in TARGET_LAST else 'ADDR')
        if mnemonic in FLOW or mnemonic in ONE_FORM or width:
            continue
        if any('!' in p or NAME.search(p) for p in _memory_parts(mnemonic, operand)):
            report('WIDTH')
    return out


def is_table(region) -> bool:
    """A label whose body has no SPC700 instruction and no macro call."""
    for raw in region.body_lines:
        code = _split(raw)[0].strip()
        m = GLOBAL_LABEL.match(code) or LOCAL_LABEL.match(code)
        if m:
            code = m.group(2).strip()
        if not code:
            continue
        m = INSTR.match(code)
        if code.startswith('%') or (m and m.group(1).lower() in MNEMONICS):
            return False
    return True


def _entry_blocks(comments):
    """The Entry line(s) of a header with the lines continuing them."""
    import lint_readability as L
    strict = [i for i, c in enumerate(comments) if L.STRICT_ENTRY.match(c)]
    blocks = []
    for i in strict or [i for i, c in enumerate(comments) if L.ENTRY_LINE.match(c)]:
        block = [comments[i]]
        for d in comments[i + 1:]:
            if not d.strip() or L.ENTRY_LINE.match(d) or L.EXIT_LINE.match(d) or L.KEY_LINE.match(d):
                break
            block.append(d)
        blocks.append(' '.join(block))
    return blocks


def driver_sites():
    """{target ARAM: [site ARAM, ...]} for every CALL, JMP and PCALL the
    trace of the driver finds, or None without the ROM."""
    if not spc700.ROM_PATH.exists():
        return None
    rom = spc700.ROM_PATH.read_bytes()
    first, base, size = spc700.driver_block(rom)
    mem = rom[first:first + size]
    sites = {}
    for ins in spc700.trace(mem, base, spc700.driver_entries(mem, base)).values():
        t = ins.jump_target()
        if t is not None:
            sites.setdefault(t, []).append(ins.pc)
    return sites


def header_findings(path: Path, rows=None, sites=None):
    """(function, line, rule, text) for HEADER, STATE, SIZE and CALLERS.

    rows: the layout (spc700_functions.csv rows) or None to skip SIZE and
    CALLERS; sites: driver_sites() or None to skip CALLERS."""
    import lint_readability as L
    regions = asm_source.file_regions(path)
    by_name = {r.name: r for r in regions}
    out = []

    def report(r, rule, text):
        if not _ok(_split(r.lines[r.label])[1]):
            out.append((r.name, r.label + 1, rule, text))

    parent_of = {}
    for r in regions:
        m = L.SEE_PARENT.search('\n'.join(r.header_comments()))
        if m:
            parent_of[r.name] = m.group(1)
    ok = set()
    for r in regions:
        if is_table(r) or r.name in parent_of:
            continue
        comments = r.header_comments(hand_written=True)
        if L._has_entry_exit(r):
            ok.add(r.name)
            if not any(STATE_P.search(b) for b in _entry_blocks(comments)):
                report(r, 'STATE', f'{r.name}: the Entry line does not state P (the direct-page flag)')
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
    num = lambda t: int(t.lstrip('$').split(':')[-1], 16)  # noqa: E731
    children = {}
    for name, parent in parent_of.items():
        children.setdefault(parent, []).append(name)

    def span(name):
        """(start, end) of the routine with its sub-entries, in ARAM."""
        names = [n for n in [name] + children.get(name, []) if n in lay]
        return (min(num(lay[n]['address']) for n in names), max(num(lay[n]['end']) for n in names))

    for r in regions:
        if r.name not in lay:
            continue
        text = ' '.join(r.header_comments(hand_written=True))
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
                continue
            if m.group(5):
                shift = num(row['rom']) - num(row['address'])
                if (int(m.group(5), 16), int(m.group(6), 16)) != (lo + shift, hi + shift):
                    report(r, 'SIZE', f'{who}: ROM range ${m.group(5)}–${m.group(6)} is not '
                                      f'${lo + shift:04X}–${hi + shift:04X}')

    if sites is None:
        return out
    for r in regions:
        if r.name not in lay or r.name in parent_of or is_table(r):
            continue
        lo, hi = span(r.name)
        named = {int(x, 16) for x in SITE.findall(' '.join(r.header_comments(hand_written=True)))}
        members = [n for n in [r.name] + children.get(r.name, []) if n in lay]
        missing = sorted(s for n in members for s in sites.get(num(lay[n]['address']), [])
                         if not lo <= s <= hi and s not in named)
        if missing:
            report(r, 'CALLERS', f'{r.name}: the header does not name the call site(s) '
                                 + ', '.join(f'${s:04X}' for s in missing))
    return out


def findings(rows=None, sites=None):
    """(path, function, line, rule, text) for every SPC700 source file."""
    out = []
    for path in sorted(Path('.').glob(GLOB)):
        found = body_findings(path)
        if str(path) in SOURCE_FILES:
            found += header_findings(path, rows, sites)
        out += [(str(path), f, no, rule, text) for f, no, rule, text in found]
    return out


def collect():
    """findings() with the layout and the call sites when they can be had."""
    import generated
    rows = generated.spc700_rows() if generated.can_generate() else None
    return findings(rows or None, driver_sites() if rows else None)


if __name__ == '__main__':
    found = collect()
    for path, function, no, rule, text in found:
        print(f'{path}:{no}: {rule}: {text}')
    print(f'{len(found)} finding(s).')
    sys.exit(1 if found else 0)
