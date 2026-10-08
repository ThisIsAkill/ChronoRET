#!/usr/bin/env python3
"""
lint_readability.py — Enforce the readability standard on game code.

A function only reaches main when it is both verified (tools/verify.py) and
readable. "Readable" is checked mechanically here; naming quality is checked
by review. Rules, applied to asm/bank*/*.asm (definitions live in
asm/include/ and are exempt):

  ADDR   memory operands are named (a RAM define, struct field, hardware
         register or label), never a raw $address.
  CALL   JSR/JSL/JMP/JML/BRL/branch targets and jump-table operands are
         labels, never raw addresses or offsets.
  CONST  immediates above 8 are named constants. REP/SEP flag masks are
         exempt (they are CPU mode switches, read as such).
  WIDTH  an instruction whose operand uses a define (!Name) or struct
         field states its width explicitly (.b/.w/.l). Defines are textual,
         so without a suffix the encoding silently follows however the
         define's value happens to be written.
  OPCODE no hand-encoded instructions (`db` standing in for an opcode); use
         a named macro from asm/include/macros.inc instead.
  PLUMB  no test/scaffolding plumbing in game code: print/assert/warnpc/
         error directives, or label-only `org` stubs (those belong in
         asm/include/unmatched.asm).
  HEADER every routine's header (the comment block tools/asm_source.py
         attributes to its label) has an Entry line and an Exit line: a
         comment line starting `Entry`, `On entry`, `Exit` or `Entry/Exit`,
         followed by `:` (a parenthesis before the colon is fine).
         Exempt: tables (a label whose body is only db/dw/dl/dd data), and
         sub-entries whose header carries `header: see <Parent>`, where
         <Parent> is a routine in the same file whose header passes this
         rule and names the sub-entry.
  CALLERS every CONFIRMED JSR/JSL/JMP/JML/BRL site that tools/xref.py finds
         for the routine is accounted for in its header (for a sub-entry,
         its own or its parent's): by the site address ($BB:AAAA, $BBAAAA,
         $AAAA when in the routine's bank, or a `/AAAA` continuation such
         as `$FD:DA5B/DABA`), by the name of the matched routine that
         contains it, or by a count such as "20 JSR sites" or "19 call
         sites" with N at least the confirmed count. Sites inside the
         routine itself (or its parent and sibling sub-entries) are its own
         flow and need no mention. A routine with no direct references
         (reached only through tables) needs no caller list. Needs the ROM
         and asar; skipped without them.

A line can opt out of one finding with `; lint-ok: <reason>` (the reason is
mandatory and is what review checks); for HEADER and CALLERS that line is the
label line.

Each finding is attributed to its enclosing global label (the function).
Functions not yet brought up to the standard are listed in
tools/readability_baseline.txt; that list may only shrink.

Usage:
    python3 tools/lint_readability.py                  check vs baseline
    python3 tools/lint_readability.py --report         per-function counts
    python3 tools/lint_readability.py --show FUNC      findings for one function
    python3 tools/lint_readability.py --strict         ignore the baseline
    python3 tools/lint_readability.py --write-baseline regenerate baseline
"""

import argparse
import re
import shutil
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asm_source  # noqa: E402

ASM_GLOB = 'asm/bank*/*.asm'
BASELINE = Path('tools/readability_baseline.txt')

MNEMONICS = set('''
ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRA BRK BRL BVC BVS CLC CLD CLI CLV
CMP COP CPX CPY DEC DEX DEY EOR INC INX INY JML JMP JSL JSR LDA LDX LDY LSR
MVN MVP NOP ORA PEA PEI PER PHA PHB PHD PHK PHP PHX PHY PLA PLB PLD PLP PLX
PLY REP ROL ROR RTI RTL RTS SBC SEC SED SEI SEP STA STP STX STY STZ TAX TAY
TCD TCS TDC TRB TSB TSC TSX TXA TXS TXY TYA TYX WAI WDM XBA XCE
'''.split())
FLOW = {'JSR', 'JSL', 'JMP', 'JML', 'BRL', 'BRA', 'BCC', 'BCS', 'BEQ', 'BMI',
        'BNE', 'BPL', 'BVC', 'BVS', 'PER'}
MODE_SWITCH = {'REP', 'SEP'}
PLUMBING = {'print', 'assert', 'warnpc', 'error'}

GLOBAL_LABEL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):(.*)$')
LOCAL_LABEL = re.compile(r'^(\.[A-Za-z0-9_]+|[+-]+):(.*)$')
INSTR = re.compile(r'^([A-Za-z]{3})(\.[bwlBWL])?(?:\s+(.*))?$')
RAW_HEX = re.compile(r'(?<![A-Za-z0-9_!.])\$[0-9A-Fa-f]+')
NUM = re.compile(r'^\$([0-9A-Fa-f]+)$|^%([01_]+)$|^(\d+)$')


def literal_value(text: str):
    m = NUM.match(text.strip())
    if not m:
        return None
    if m.group(1):
        return int(m.group(1), 16)
    if m.group(2):
        return int(m.group(2).replace('_', ''), 2)
    return int(m.group(3))


def split_comment(line: str) -> tuple[str, str]:
    idx = line.find(';')
    return (line, '') if idx < 0 else (line[:idx], line[idx + 1:])


def lint_file(path: Path):
    findings = []          # (function, line_no, rule, text)
    function = '<file-top>'
    pending_stub = None    # (label, line_no) of a label right after org
    emitted_since_org = True

    lines = path.read_text().splitlines()
    for no, raw in enumerate(lines, 1):
        code, comment = split_comment(raw)
        suppressed = re.search(r'lint-ok:\s*\S', comment) is not None
        stripped = code.strip()
        if not stripped:
            continue

        def report(rule: str):
            if not suppressed:
                findings.append((function, no, rule, raw.strip()))

        # Labels (a label may share its line with an instruction).
        if not raw[:1].isspace():
            m = GLOBAL_LABEL.match(stripped)
            if m and not stripped.startswith('.'):
                function = m.group(1)
                if not emitted_since_org and pending_stub is None:
                    pending_stub = (function, no)
                stripped = m.group(2).strip()
                if not stripped:
                    continue
        m = LOCAL_LABEL.match(stripped)
        if m:
            stripped = m.group(2).strip()
            if not stripped:
                continue

        word = stripped.split()[0]
        lower = word.lower()

        if lower == 'org':
            if pending_stub is not None and not emitted_since_org:
                findings.append((pending_stub[0], pending_stub[1], 'PLUMB',
                                 'label-only org stub (move to asm/include/unmatched.asm)'))
            pending_stub = None
            emitted_since_org = False
            continue
        if lower in PLUMBING:
            report('PLUMB')
            continue
        if lower in ('db', 'dw', 'dl', 'dd'):
            emitted_since_org = True
            first = comment.strip().split()[:1]
            if first and first[0].upper() in MNEMONICS:
                report('OPCODE')
            continue
        if stripped.startswith(('!', '%')) or '=' in stripped.split(';')[0] \
                or lower in ('incsrc', 'incbin', 'hirom', 'lorom', 'arch',
                             'if', 'else', 'elseif', 'endif', 'macro',
                             'endmacro', 'struct', 'endstruct', 'skip',
                             'namespace', 'pushpc', 'pullpc', 'base',
                             'fillbyte', 'fill', 'padbyte', 'pad', 'table',
                             'cleartable', 'check', 'math', 'warn'):
            if stripped.startswith('%'):
                emitted_since_org = True
            continue

        m = INSTR.match(stripped)
        if not m or m.group(1).upper() not in MNEMONICS:
            continue
        emitted_since_org = True
        mnemonic = m.group(1).upper()
        operand = (m.group(3) or '').strip()
        if not operand:
            continue

        named = '!' in operand or re.search(r'[A-Za-z_]\w*(\[[^]]*\])?\.[A-Za-z_]', operand)
        if named and mnemonic not in FLOW and not m.group(2):
            report('WIDTH')

        if operand.startswith('#'):
            if mnemonic in MODE_SWITCH:
                continue
            value = literal_value(operand[1:])
            if value is not None and value > 8:
                report('CONST')
            continue

        if RAW_HEX.search(operand):
            report('CALL' if mnemonic in FLOW else 'ADDR')

    if pending_stub is not None and not emitted_since_org:
        findings.append((pending_stub[0], pending_stub[1], 'PLUMB',
                         'label-only org stub (move to asm/include/unmatched.asm)'))
    return findings


# ── Header rules (HEADER, CALLERS) ───────────────────────────────────────────

ENTRY_LINE = re.compile(r'^\s*(on\s+entry|entry(/exit)?)\b[^:]{0,60}:', re.I)
EXIT_LINE = re.compile(r'^\s*(exit|entry/exit)\b[^:]{0,60}:', re.I)
SEE_PARENT = re.compile(r'\bheader:\s*see\s+([A-Za-z_][A-Za-z0-9_]*)')
COUNT = re.compile(r'\b(\d+)\s+(?:(?:JSR|JSL|JMP|JML|BRL|call|jump|caller)s?\s+)?'
                   r'(?:call\s+)?(?:sites?\b|callers\b)', re.I)
ADDRESS = re.compile(r'\$([0-9A-Fa-f]{2}:[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4})'
                     r'(?![0-9A-Fa-f:])((?:/\s*[0-9A-Fa-f]{4}(?![0-9A-Fa-f]))*)')
CALL_KINDS = {'JSR', 'JSL', 'JMP', 'JML', 'BRL'}
_XREF = []      # one tools/xref.py instance per run (or [None] without ROM/asar)
_PARENTS = []


def _xref():
    if not _XREF:
        xr = None
        if Path('roms/chrono_trigger.sfc').exists() and shutil.which('asar') \
                and Path('symbols/functions.csv').exists():
            import xref
            xr = xref.Xref()
        _XREF.append(xr)
    return _XREF[0]


def is_table(region) -> bool:
    """A label whose body emits only data (no instruction or macro line)."""
    for raw in region.body_lines:
        code = split_comment(raw)[0].strip()
        m = GLOBAL_LABEL.match(code) or LOCAL_LABEL.match(code)
        if m:
            code = m.group(2).strip()
        if not code:
            continue
        word = code.split()[0]
        if word.startswith('%') or (INSTR.match(code) and word[:3].upper() in MNEMONICS):
            return False
    return True


def _suppressed(region) -> bool:
    return re.search(r'lint-ok:\s*\S', split_comment(region.lines[region.label])[1]) is not None


def _has_entry_exit(region) -> bool:
    comments = region.header_comments()
    return any(ENTRY_LINE.match(c) for c in comments) and any(EXIT_LINE.match(c) for c in comments)


def _mentioned_offsets(text: str, bank: int, to_offset) -> set[int]:
    found = set()
    for m in ADDRESS.finditer(text):
        tok = m.group(1).replace(':', '')
        b = int(tok[:2], 16) if len(tok) == 6 else None
        addr = int(tok[-4:], 16)
        off = to_offset(b, addr) if b is not None else (bank << 16 | addr)
        if off is None:
            continue
        found.add(off)
        for cont in m.group(2).split('/')[1:]:
            found.add(off & ~0xFFFF | int(cont.strip(), 16))
    return found


def _all_parents() -> dict[str, str]:
    """`header: see <Parent>` declarations across every bank file."""
    if not _PARENTS:
        found = {}
        for path in sorted(Path('.').glob(ASM_GLOB)):
            for r in asm_source.file_regions(path):
                m = SEE_PARENT.search('\n'.join(r.header_comments()))
                if m:
                    found[r.name] = m.group(1)
        _PARENTS.append(found)
    return _PARENTS[0]


def header_findings(path: Path):
    findings = []
    regions = asm_source.file_regions(path)
    by_name = {r.name: r for r in regions}
    parent_of = {}
    for r in regions:
        m = SEE_PARENT.search('\n'.join(r.header_comments()))
        if m:
            parent_of[r.name] = m.group(1)

    def report(r, rule, text):
        if not _suppressed(r):
            findings.append((r.name, r.label + 1, rule, text))

    ok_header = set()
    for r in regions:
        if is_table(r) or r.name in parent_of:
            continue
        if _has_entry_exit(r):
            ok_header.add(r.name)
        else:
            report(r, 'HEADER', f'{r.name}: header has no Entry/Exit line '
                                f'(or `header: see <Parent>` for a sub-entry)')
    for name, parent in parent_of.items():
        if parent not in ok_header:
            report(by_name[name], 'HEADER', f'{name}: `header: see {parent}` names no routine '
                                            f'in this file with an Entry/Exit header')
        elif not re.search(rf'\b{name}\b', ' '.join(by_name[parent].header_comments())):
            report(by_name[name], 'HEADER', f'{name}: the header of {parent} does not mention '
                                            f'this sub-entry')

    xr = _xref()
    if xr is None:
        return findings
    import xref
    family = defaultdict(set)
    for name, parent in parent_of.items():
        family[parent].add(name)
    all_parents = _all_parents()
    for r in regions:
        if is_table(r) or r.name not in xr.labels:
            continue
        target = xr.labels[r.name]
        parent = parent_of.get(r.name)
        own = {r.name} | ({parent} | family[parent] if parent else family[r.name])
        sites = [h for h in xr.xref(target)
                 if h.status == 'CONFIRMED' and h.kind in CALL_KINDS and h.routine not in own]
        if not sites:
            continue
        # Comment lines are joined so a list may wrap (`$FD:DA5B/DABA/` ... `DB19`).
        text = ' '.join(r.header_comments())
        if parent in by_name:
            text += ' ' + ' '.join(by_name[parent].header_comments())
        offsets = _mentioned_offsets(text, target >> 16, xref.to_offset)
        words = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', text))

        def named(h):
            # The routine containing the site, or the parent whose header
            # documents that routine (`header: see <Parent>`).
            return h.routine and (h.routine in words or all_parents.get(h.routine) in words)
        missing = [h for h in sites if h.offset not in offsets and not named(h)]
        if not missing:
            continue
        counts = [int(m.group(1)) for m in COUNT.finditer(text)]
        if counts and max(counts) >= len(sites):
            continue
        listed = ', '.join(f'{h.kind} {h.site}' + (f' ({h.routine})' if h.routine else '')
                           for h in missing[:6]) + (' ...' if len(missing) > 6 else '')
        report(r, 'CALLERS', f'{r.name}: {len(missing)} of {len(sites)} confirmed caller site(s) '
                             f'not in the header: {listed}')
    return findings


def collect():
    findings = []
    for path in sorted(Path('.').glob(ASM_GLOB)):
        for function, no, rule, text in lint_file(path) + header_findings(path):
            findings.append((str(path), function, no, rule, text))
    return findings


def by_function(findings):
    grouped = defaultdict(list)
    for path, function, no, rule, text in findings:
        grouped[f'{path}:{function}'].append((no, rule, text))
    return grouped


def read_baseline() -> set[str]:
    if not BASELINE.exists():
        return set()
    return {l.strip() for l in BASELINE.read_text().splitlines()
            if l.strip() and not l.startswith('#')}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--report', action='store_true')
    ap.add_argument('--show')
    ap.add_argument('--strict', action='store_true')
    ap.add_argument('--write-baseline', action='store_true')
    args = ap.parse_args()

    grouped = by_function(collect())

    if args.write_baseline:
        BASELINE.write_text(
            '# Functions not yet at the readability standard (see\n'
            '# tools/lint_readability.py). This list may only shrink; main is\n'
            '# fully gated when it is empty.\n' + ''.join(f'{k}\n' for k in sorted(grouped)))
        print(f'Wrote {len(grouped)} function(s) to {BASELINE}')
        return 0

    if args.show:
        hits = [(k, v) for k, v in grouped.items() if k.endswith(':' + args.show)]
        for key, items in hits:
            for no, rule, text in items:
                print(f'{key.split(":")[0]}:{no}: {rule}: {text}')
        return 1 if hits else 0

    if args.report:
        rules = defaultdict(int)
        for items in grouped.values():
            for _, rule, _ in items:
                rules[rule] += 1
        for key in sorted(grouped, key=lambda k: -len(grouped[k])):
            print(f'{len(grouped[key]):>5}  {key}')
        print(f'\n{len(grouped)} function(s) with findings; by rule: '
              + ', '.join(f'{r}={n}' for r, n in sorted(rules.items())))
        return 0

    baseline = set() if args.strict else read_baseline()
    failing = sorted(k for k in grouped if k not in baseline)
    stale = sorted(k for k in baseline if k not in grouped)

    for key in failing:
        for no, rule, text in grouped[key][:10]:
            print(f'{key.split(":")[0]}:{no}: {rule}: {text}')
        if len(grouped[key]) > 10:
            print(f'  ... {len(grouped[key]) - 10} more in {key}')
    if failing:
        print(f'FAIL: {len(failing)} function(s) not at the readability standard '
              f'(and not in {BASELINE}).')
    if stale:
        print('FAIL: these baseline entries are now clean or gone; remove them from '
              f'{BASELINE}:\n  ' + '\n  '.join(stale))
    if failing or stale:
        return 1
    remaining = len(baseline)
    print(f'READABLE: no new findings ({remaining} grandfathered function(s) left in baseline).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
