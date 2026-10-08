#!/usr/bin/env python3
"""
callers.py — Generate the "; Callers" block of every routine header.

Who calls a routine is a fact about the whole ROM, and it changes whenever
new code is matched. So the block is generated from tools/xref.py, never
written or reviewed by hand, and it is left out of the routine's source
hash (tools/asm_source.py): regenerating it never voids a review.

The block lists every CONFIRMED JSR/JSL/JMP/JML/BRL site that xref finds
for the routine, outside the routine itself (and outside its sub-entries
and parent: that is its own flow). Each site is named by the matched
routine that contains it, or `unmatched`, with its address, plus the count:

    ; Callers (4 JSR sites): BattleMenu_ChooseAttack ($C1:12B0),
    ;   BattleMenu_TechConfirm ($C1:1379), BattleMenu_ItemConfirm ($C1:14C5) and
    ;   unmatched ($C1:5561).

When the sites are of more than one kind, each address carries its kind
(`Name (JSR $C0:1234, JMP $C0:1240)`) and the count is split
(`5 sites: 4 JSR, 1 JMP`). A sub-entry (`; header: see <Parent>`) gets no
block of its own; its sites are listed in the parent's header, one
`; Callers of <Sub-entry> (...)` line group each. A routine with no
confirmed site has no block.

Anything a person needs to add (a doubtful or data-decoded site, a table
that dispatches to the routine, a fall-in) goes on a separate line that
this tool leaves alone and the reviewer judges:

    ; Callers note: also reached through C2Script_OpTable (entry $1C).

When --update replaces a hand-written block, whatever the new block does
not say (names, addresses, words other than counts and call kinds) is
kept, verbatim, on a `Callers note` line in its place.

Usage:
    python3 tools/callers.py --update        rewrite every block that differs
    python3 tools/callers.py --check         list the routines whose block differs
    python3 tools/callers.py --show NAME     print the block NAME should have
"""

import argparse
import re
import sys
import textwrap
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asm_source  # noqa: E402

ASM_GLOB = 'asm/bank*/*.asm'
KINDS = ('JSR', 'JSL', 'JMP', 'JML', 'BRL')
WIDTH = 100
SEE_PARENT = re.compile(r'\bheader:\s*see\s+([A-Za-z_][A-Za-z0-9_]*)')
ENTRY_LINE = re.compile(r'^; ?(On entry|Entry(/Exit)?)\b[^:]{0,60}:')
BLOCK_START = asm_source.CALLERS_START
BLOCK_CONT = asm_source.CALLERS_CONT

# Hand-written blocks from before this tool (only used when replacing one).
OLD_START = re.compile(r'^;\s?Callers?(?=[\s:(,])(?!\s+note\b)')
OLD_KEY = re.compile(r'^;\s?(On entry|Entry|Exit|Callees?\b|Calls\b|No\b|[-=~]{3}|header:|'
                     r'Direct-page|Callers?\b)', re.I)
FILLER = set('''
callers caller callers' jsr jsl jmp jml brl jsrs jmps site sites call and its only the from in at
unmatched code routine routines twice three four five six times once both all e g eg also by of
across bank via tail plus a an each one two entry point by
'''.split())


def fmt(off: int) -> str:
    return f'${0xC0 + (off >> 16):02X}:{off & 0xFFFF:04X}'


# ── What the block should say ────────────────────────────────────────────────

def site_list(xr, target: int, own: set[str]) -> list:
    """CONFIRMED call sites of target outside the routine's own family."""
    return sorted((h for h in xr.xref(target)
                   if h.status == 'CONFIRMED' and h.kind in KINDS and h.routine not in own),
                  key=lambda h: h.offset)


def render(sites: list, of: str = '') -> list[str]:
    """The comment lines for one list of sites (empty when there is none)."""
    if not sites:
        return []
    kinds = Counter(h.kind for h in sites)
    if len(kinds) == 1:
        kind, n = next(iter(kinds.items()))
        count = f'{n} {kind} site{"s" if n != 1 else ""}'
    else:
        count = f'{len(sites)} sites: ' + ', '.join(f'{kinds[k]} {k}' for k in KINDS if kinds[k])
    mixed = len(kinds) > 1
    groups, order = defaultdict(list), []
    for h in sites:
        key = h.routine or ''
        if key not in groups:
            order.append(key)
        groups[key].append(h)
    order = [k for k in order if k] + ([''] if '' in groups else [])
    items = []
    for key in order:
        addrs = ', '.join((f'{h.kind} ' if mixed else '') + fmt(h.offset) for h in groups[key])
        items.append(f'{key or "unmatched"} ({addrs})')
    text = items[0] if len(items) == 1 else ', '.join(items[:-1]) + ' and ' + items[-1]
    head = f'; Callers{" of " + of if of else ""} ({count}): '
    lines = textwrap.wrap(head + text + '.', WIDTH, subsequent_indent=';   ',
                          break_long_words=False, break_on_hyphens=False)
    return lines


class Generator:
    """Expected blocks for every region, from one xref instance."""

    def __init__(self, xr=None):
        if xr is None:
            import xref
            xr = xref.Xref(deep=True)
        self.xr = xr

    def family(self, regions):
        parent_of = {}
        for r in regions:
            m = SEE_PARENT.search('\n'.join(r.header_comments()))
            if m:
                parent_of[r.name] = m.group(1)
        children = defaultdict(list)
        for r in regions:                       # file order
            if r.name in parent_of:
                children[parent_of[r.name]].append(r.name)
        return parent_of, children

    def expected(self, regions) -> dict[str, list[str]]:
        """Region name -> the block lines its header must carry."""
        parent_of, children = self.family(regions)
        names = {r.name for r in regions}
        out = {}
        for r in regions:
            if r.name in parent_of and parent_of[r.name] in names:
                out[r.name] = []             # listed in the parent's header
                continue
            own = {r.name, *children[r.name]}
            lines = []
            for i, name in enumerate([r.name, *children[r.name]]):
                if name not in self.xr.labels:
                    continue
                sites = site_list(self.xr, self.xr.labels[name], own)
                lines += render(sites, of=name if i else '')
            out[r.name] = lines
        return out


def actual(region) -> list[str]:
    return [region.lines[i] for i in asm_source.callers_block_lines(region)]


# ── Rewriting ────────────────────────────────────────────────────────────────

def old_blocks(region) -> list[tuple[int, int]]:
    """[(first, end)] line spans of every Callers block in the header,
    hand-written or generated."""
    spans, i = [], region.start
    gen = set(asm_source.callers_block_lines(region))
    while i < region.label:
        line = region.lines[i]
        if i in gen:
            j = i + 1
            while j < region.label and j in gen and not BLOCK_START.match(region.lines[j]):
                j += 1
            spans.append((i, j))
            i = j
            continue
        if OLD_START.match(line):
            j = i + 1
            while j < region.label:
                t = region.lines[j]
                if not t.startswith(';') or not t[1:].strip():
                    break
                body = t[1:]
                if len(body) - len(body.lstrip()) < 2 and OLD_KEY.match(t):
                    break
                j += 1
            spans.append((i, j))
            i = j
            continue
        i += 1
    return spans


def leftover(text: str, new_lines: list[str], own: set[str] = frozenset()) -> list[str]:
    """Words of an old block that the new block does not say (the routine's
    own name and its sub-entries' count as said)."""
    new = ' '.join(new_lines)
    new_addrs = {a.replace(':', '').upper()[-6:] for a in re.findall(r'\$[0-9A-Fa-f:]{6,7}', new)}
    new_words = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', new)) | set(own)
    body = re.sub(r'^;\s*Callers?\b', '', text, flags=re.I)
    rest = []
    for tok in re.findall(r'\$[0-9A-Fa-f]{2}:[0-9A-Fa-f]{4}|\$[0-9A-Fa-f]+|[A-Za-z_][A-Za-z0-9_]*|\d+',
                          body):
        if tok.startswith('$'):
            hexd = tok[1:].replace(':', '').upper()
            if len(hexd) <= 2:
                continue                      # a bank number
            if len(hexd) == 6 and hexd in new_addrs:
                continue
            if len(hexd) == 4 and any(a.endswith(hexd) for a in new_addrs):
                continue
            rest.append(tok)
        elif tok.isdigit() or tok.lower() in FILLER or tok in new_words:
            continue
        else:
            rest.append(tok)
    return rest


def as_note(lines: list[str]) -> list[str]:
    first = re.sub(r'^(;\s*)Callers?\b', r'\1Callers note', lines[0], count=1, flags=re.I)
    return [first] + lines[1:]


# A block already in the generated form is replaced without a note. The
# one-time conversion of the hand-written blocks set this to False, so that
# hand-written blocks that happened to be in that form kept every word.
TRUST_GENERATED = True


def is_generated(lines: list[str]) -> bool:
    return TRUST_GENERATED and bool(lines) and BLOCK_START.match(lines[0]) is not None \
        and all(BLOCK_START.match(l) or BLOCK_CONT.match(l) for l in lines)


def rewrite_region(region, want: list[str], own: set[str] = frozenset()) -> list[str] | None:
    """New header lines for the region, or None if nothing changes."""
    if actual(region) == want and not any(
            not is_generated(region.lines[a:b]) for a, b in old_blocks(region)):
        return None
    lines = region.lines
    spans = old_blocks(region)
    out, placed, i = [], False, region.start
    span_at = {a: b for a, b in spans}
    while i <= region.label:
        if i in span_at:
            old = lines[i:span_at[i]]
            if not placed:
                out += want
                placed = True
            if not is_generated(old) and leftover(' '.join(old), want, own):
                out += as_note(old)
            i = span_at[i]
            continue
        # Without an old block: before the Entry line, else before the label.
        if not placed and want and not spans and (ENTRY_LINE.match(lines[i]) or i == region.label):
            out += want
            placed = True
        out.append(lines[i])
        i += 1
    return out


def update_file(path: Path, gen: Generator) -> list[str]:
    regions = asm_source.file_regions(path)
    want = gen.expected(regions)
    lines = regions[0].lines if regions else []
    changed, new, prev = [], [], 0
    parent_of, children = gen.family(regions)
    for r in regions:
        top = parent_of.get(r.name, r.name)
        repl = rewrite_region(r, want[r.name], {top, *children[top]})
        if repl is None:
            continue
        new += lines[prev:r.start] + repl
        prev = r.label + 1
        changed.append(r.name)
    if changed:
        new += lines[prev:]
        path.write_text('\n'.join(new) + '\n')
    return changed


def differing(gen: Generator) -> list[tuple[str, str]]:
    out = []
    for path in sorted(Path('.').glob(ASM_GLOB)):
        regions = asm_source.file_regions(path)
        want = gen.expected(regions)
        out += [(str(path), r.name) for r in regions if actual(r) != want[r.name]]
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--update', action='store_true')
    g.add_argument('--check', action='store_true')
    g.add_argument('--show', metavar='NAME')
    args = ap.parse_args()

    import generated
    if not generated.can_generate():
        print('callers.py needs the ROM (roms/chrono_trigger.sfc) and asar.', file=sys.stderr)
        return 2
    gen = Generator()

    if args.show:
        for path in sorted(Path('.').glob(ASM_GLOB)):
            regions = asm_source.file_regions(path)
            if any(r.name == args.show for r in regions):
                lines = gen.expected(regions)[args.show]
                print('\n'.join(lines) if lines else '(no block: no confirmed call site, or a '
                                                      'sub-entry listed in its parent)')
                return 0
        print(f'callers.py: no routine named {args.show}', file=sys.stderr)
        return 1

    if args.check:
        diff = differing(gen)
        for path, name in diff:
            print(f'{path}: {name}: Callers block differs; run tools/callers.py --update')
        return 1 if diff else 0

    total = 0
    for path in sorted(Path('.').glob(ASM_GLOB)):
        changed = update_file(path, gen)
        total += len(changed)
        for name in changed:
            print(f'{path}: {name}')
    print(f'{total} header(s) rewritten.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
