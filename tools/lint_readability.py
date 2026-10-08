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
  CALLERS the header's generated Callers block (`; Callers (N JSR sites):
         ...`, see tools/callers.py) is exactly what tools/callers.py
         generates from tools/xref.py's CONFIRMED call sites: no block when
         there is none, and nothing hand-written in it. The block is left
         out of the source hash, so this is what keeps it honest; it cannot
         be opted out of. Hand-written caller remarks go on a
         `; Callers note:` line, which is hashed and reviewed. Needs the
         ROM and asar; skipped without them.

  SIZE   a header claim `Name (N bytes, $XXXX–$YYYY)` (or `(N bytes, $XXXX–
         $YYYY)` about the routine itself) agrees with the assembled
         layout (symbols/functions.csv): the routine's start, end and size,
         or those of the routine with its `header: see` sub-entries. Needs
         the ROM and asar; skipped without them.

A line can opt out of one finding with `; lint-ok: <reason>` (the reason is
mandatory and is what review checks); for HEADER that line is the label
line. CALLERS cannot be opted out of.

Each finding is attributed to its enclosing global label (the function).
Functions not yet brought up to the standard are listed in
tools/readability_baseline.txt; that list may only shrink. A finding of a
rule added after its routine was verified (SIZE, UNMATCHED, DPDB) can be
grandfathered alone with a `path:Function RULE` line: every other rule
still applies, and tools/progress.py keeps the routine readable.

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
_XREF = []      # one tools/xref.py instance per run (or [None] without ROM/asar)


def _xref():
    if not _XREF:
        import generated
        if generated.can_generate():
            # Brings symbols/functions.csv up to date first (inside
            # tools/progress.py this is a no-op: the layout is already known).
            generated.ensure()
    if not _XREF:
        xr = None
        if Path('roms/chrono_trigger.sfc').exists() and shutil.which('asar'):
            import xref
            xr = xref.Xref(deep=True)     # the same verdicts tools/callers.py uses
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
    comments = region.header_comments(hand_written=True)
    return any(ENTRY_LINE.match(c) for c in comments) and any(EXIT_LINE.match(c) for c in comments)


# ── Header claims checked against the layout (SIZE, UNMATCHED, DPDB) ─────────

SIZE_CLAIM = re.compile(r'(?:\b([A-Za-z_][A-Za-z0-9_]*)\s+)?\((\d[\d,]*) bytes?, '
                        r'\$(?:([0-9A-Fa-f]{2}):)?([0-9A-Fa-f]{4})'
                        r'(?:\s*[–-]\s*\$?(?:([0-9A-Fa-f]{2}):)?([0-9A-Fa-f]{4}))?')
LONG_ADDR = re.compile(r'\$([0-9A-Fa-f]{2}):?([0-9A-Fa-f]{4})(?![0-9A-Fa-f])((?:/[0-9A-Fa-f]{4}(?![0-9A-Fa-f]))*)')
UNMATCHED_WORD = re.compile(r'\bunmatched\b', re.I)
BEFORE_LIST = re.compile(r'((?:\$[0-9A-Fa-f]{2}:[0-9A-Fa-f]{4}(?:/[0-9A-Fa-f]{4})*'
                         r'(?:,\s*|\s+and\s+|\s+or\s+)?)+)\s*\(\s*$')
STATE_DP = re.compile(r'\bDP\b|\bD\s*=|direct page', re.I)
STATE_DB = re.compile(r'\bDB\b|data bank', re.I)
STRICT_ENTRY = re.compile(r'^\s?(On entry|Entry(/Exit)?)\b[^:]{0,60}:\s')
KEY_LINE = re.compile(r'^\s?(?:[A-Z][\w /()-]{0,30}:\s|[-=~]{3})')
REFERS = re.compile(r'\bas\b|\bsee\b|\bsame\b|banner|above|below', re.I)


class Layout:
    """Matched routines from symbols/functions.csv (tools/generated.py)."""

    def __init__(self, rows):
        def off(a):
            return (int(a[1:3], 16) - 0xC0) << 16 | int(a[4:], 16)
        self.spans = sorted((off(r['address']), off(r['end']), r['name']) for r in rows)
        self.by_name = {n: (s, e) for s, e, n in self.spans}
        self.starts = [s for s, _, _ in self.spans]

    def owner(self, o):
        import bisect
        i = bisect.bisect_right(self.starts, o) - 1
        if i >= 0 and self.spans[i][0] <= o <= self.spans[i][1]:
            return self.spans[i][2]
        return None


_LAYOUT = []


def _layout():
    if not _LAYOUT:
        rows = []
        import generated
        if generated.can_generate():
            rows = generated.function_rows()
        _LAYOUT.append(Layout(rows) if rows else None)
    return _LAYOUT[0]


def _fmt(o: int) -> str:
    return f'${0xC0 + (o >> 16):02X}:{o & 0xFFFF:04X}'


def size_findings(r, lay, family_end):
    """SIZE: `Name (N bytes, $XXXX–$YYYY)` agrees with the assembled layout."""
    out = []
    for m in SIZE_CLAIM.finditer(' '.join(r.header_comments(hand_written=True))):
        name = m.group(1) if m.group(1) in lay.by_name else r.name
        if name not in lay.by_name:
            continue
        start, end = lay.by_name[name]
        size = int(m.group(2).replace(',', ''))
        bank = start >> 16
        cs = (int(m.group(3), 16) - 0xC0 if m.group(3) else bank) << 16 | int(m.group(4), 16)
        ce = None
        if m.group(6):
            ce = (int(m.group(5), 16) - 0xC0 if m.group(5) else cs >> 16) << 16 | int(m.group(6), 16)
        real = [(start, end)]
        if family_end.get(name, end) != end:
            real.append((start, family_end[name]))       # the routine with its sub-entries
        if any(cs == s and size == e - s + 1 and ce in (None, e) for s, e in real):
            continue
        claim = f'({m.group(2)} bytes, ${m.group(4).upper()}' + \
            (f'–${m.group(6).upper()})' if ce is not None else ')')
        out.append(f'{r.name}: header says {name} {claim}, but the layout has '
                   f'{end - start + 1} bytes, {_fmt(start)}–{_fmt(end)}')
    return out


def unmatched_findings(r, lay):
    """UNMATCHED: no header text calls an address inside matched code unmatched."""
    text = ' '.join(c.strip() for c in r.header_comments(hand_written=True))
    out, seen = [], set()
    for m in UNMATCHED_WORD.finditer(text):
        # The clause after the word (to the next ';' or sentence end), and the
        # list of addresses right before "(unmatched".
        # In "(unmatched...)" the clause ends at the parenthesis.
        inside = text[:m.start()].rstrip().endswith('(')
        after = re.split(r';|\.\s|\.$' + (r'|\)' if inside else ''),
                         text[m.end():m.end() + 160])[0]
        before = BEFORE_LIST.search(text[max(0, m.start() - 200):m.start()])
        spans = [after] + ([before.group(1)] if before else [])
        for chunk in spans:
            for a in LONG_ADDR.finditer(chunk):
                bank = int(a.group(1), 16)
                if bank < 0xC0:
                    continue
                offs = [(bank - 0xC0) << 16 | int(a.group(2), 16)]
                offs += [offs[0] & ~0xFFFF | int(c, 16) for c in a.group(3).split('/')[1:]]
                for o in offs:
                    who = lay.owner(o)
                    if who and o not in seen:
                        seen.add(o)
                        out.append(f'{r.name}: header calls {_fmt(o)} unmatched, but it is inside '
                                   f'matched {who}')
    return out


def dpdb_findings(r):
    """DPDB: every Entry line states DP and DB (or points to text in this
    header that does)."""
    comments = r.header_comments(hand_written=True)
    out = []
    strict = [i for i, c in enumerate(comments) if STRICT_ENTRY.match(c)]
    for i in strict or [i for i, c in enumerate(comments) if ENTRY_LINE.match(c)]:
        c = comments[i]
        block = [c]          # the Entry line and the lines continuing it
        for d in comments[i + 1:]:
            if not d.strip() or ENTRY_LINE.match(d) or EXIT_LINE.match(d) or KEY_LINE.match(d):
                break
            block.append(d)
        text = ' '.join(block)
        missing = [n for n, rx in (('DP', STATE_DP), ('DB', STATE_DB)) if not rx.search(text)]
        if missing and REFERS.search(text):
            rest = [d for d in comments if d not in block]
            if any(STATE_DP.search(d) and STATE_DB.search(d) for d in rest):
                missing = []
        if missing:
            out.append(f'{r.name}: the Entry line does not state {" or ".join(missing)} '
                       f'({c.strip()[:60]!r})')
    return out


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
        elif not re.search(rf'\b{name}\b', ' '.join(by_name[parent].header_comments(hand_written=True))):
            report(by_name[name], 'HEADER', f'{name}: the header of {parent} does not mention '
                                            f'this sub-entry')

    if 'DPDB' in CLAIM_RULES:
        EVALUATED.add('DPDB')
        for r in regions:
            if not is_table(r) and r.name not in parent_of:
                for text in dpdb_findings(r):
                    report(r, 'DPDB', text)
    lay = _layout()
    if lay is not None:
        EVALUATED.update(CLAIM_RULES & {'SIZE', 'UNMATCHED'})
        family_end = {}
        for r in regions:
            top = parent_of.get(r.name, r.name)
            if r.name in lay.by_name and top in lay.by_name:
                family_end[top] = max(family_end.get(top, lay.by_name[top][1]),
                                      lay.by_name[r.name][1])
        for r in regions:
            if 'SIZE' in CLAIM_RULES:
                for text in size_findings(r, lay, family_end):
                    report(r, 'SIZE', text)
            if 'UNMATCHED' in CLAIM_RULES:
                for text in unmatched_findings(r, lay):
                    report(r, 'UNMATCHED', text)

    xr = _xref()
    if xr is None:
        return findings
    import callers
    want = callers.Generator(xr).expected(regions)
    for r in regions:
        # Not suppressible: the block is outside the source hash.
        if callers.actual(r) != want[r.name]:
            findings.append((r.name, r.label + 1, 'CALLERS',
                             f'{r.name}: the Callers block is not what tools/callers.py generates '
                             f'from the confirmed call sites: run tools/callers.py --update'))
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


# Rules added after routines were already verified. A routine can be
# grandfathered for one of them alone (`path:Function RULE` in the baseline),
# so an old finding does not void its review, while every other rule still
# applies to it in full. A whole-function entry (`path:Function`) exempts it
# from every rule but keeps it at `matched` (tools/progress.py).
PER_RULE = ('SIZE', 'UNMATCHED', 'DPDB')
CLAIM_RULES = {'SIZE'}
EVALUATED = set()       # the per-rule checks this run could make (no ROM: no SIZE/UNMATCHED)


def read_baseline():
    """(whole-function entries, {function: rules grandfathered one by one},
    malformed lines)."""
    whole, by_rule, bad = set(), defaultdict(set), []
    if BASELINE.exists():
        for line in BASELINE.read_text().splitlines():
            parts = line.split()
            if not parts or line.startswith('#'):
                continue
            if len(parts) == 1:
                whole.add(parts[0])
            elif len(parts) == 2 and parts[1] in PER_RULE:
                by_rule[parts[0]].add(parts[1])
            else:
                bad.append(line)
    return whole, by_rule, bad


def blocking(grouped, by_rule=None):
    """The findings that count, without the per-rule grandfathered ones."""
    if by_rule is None:
        by_rule = read_baseline()[1]
    out = {}
    for key, items in grouped.items():
        left = [f for f in items if f[1] not in by_rule.get(key, ())]
        if left:
            out[key] = left
    return out


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

    whole, by_rule, bad = (set(), {}, []) if args.strict else read_baseline()
    counted = blocking(grouped, by_rule)
    failing = sorted(k for k in counted if k not in whole)
    stale = sorted(k for k in whole if k not in grouped)
    # A rule this run could not check (no ROM) cannot show an entry stale.
    stale += sorted(f'{k} {r}' for k, rules in by_rule.items() for r in rules
                    if r in EVALUATED and not any(f[1] == r for f in grouped.get(k, ())))

    for key in failing:
        for no, rule, text in counted[key][:10]:
            print(f'{key.split(":")[0]}:{no}: {rule}: {text}')
        if len(counted[key]) > 10:
            print(f'  ... {len(counted[key]) - 10} more in {key}')
    if failing:
        print(f'FAIL: {len(failing)} function(s) not at the readability standard '
              f'(and not in {BASELINE}).')
    if stale:
        print('FAIL: these baseline entries are now clean or gone; remove them from '
              f'{BASELINE}:\n  ' + '\n  '.join(stale))
    if bad:
        print(f'FAIL: malformed lines in {BASELINE} (`path:Function`, or `path:Function RULE` '
              f'with RULE one of {", ".join(PER_RULE)}):\n  ' + '\n  '.join(bad))
    if failing or stale or bad:
        return 1
    n_rule = sum(len(r) for r in by_rule.values())
    print(f'READABLE: no new findings ({len(whole)} grandfathered function(s) and {n_rule} '
          f'grandfathered single-rule finding(s) left in baseline).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
