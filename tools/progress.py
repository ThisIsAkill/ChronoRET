#!/usr/bin/env python3
"""
progress.py — Auto-generate docs/PROGRESS.md stats from asm/ source.

Scans asm/bank*/*.asm for `org` directives and explicit byte/data
definitions to compute how many ROM bytes are covered by matched source,
then updates (or prints) the progress table.

Usage:
    python3 tools/progress.py [--update]

    --update   Overwrite docs/PROGRESS.md with fresh stats (default: dry-run)
"""

import re
import sys
import struct
from pathlib import Path

ROM_PATH     = Path('roms/chrono_trigger.sfc')
ASM_DIR      = Path('asm')
PROGRESS_MD  = Path('docs/PROGRESS.md')
ROM_SIZE     = 0x400000   # 4 MB unheadered


def load_rom() -> bytes:
    data = ROM_PATH.read_bytes()
    if len(data) % 1024 == 512 and len(data) > 512:
        rem = len(data) - 512
        if rem in (0x80000, 0x100000, 0x200000, 0x300000, 0x400000):
            data = data[512:]
    return data


def hirom_to_offset(pc: int) -> int | None:
    """Convert a 24-bit asar PC (HiROM) to a file offset."""
    bank = (pc >> 16) & 0xFF
    addr = pc & 0xFFFF
    if bank >= 0xC0:
        return (bank - 0xC0) * 0x10000 + addr
    if 0x00 <= bank <= 0x3F:
        if addr < 0x8000:
            return None
        return bank * 0x10000 + addr
    if 0x80 <= bank <= 0xBF:
        if addr < 0x8000:
            return None
        return (bank - 0x80) * 0x10000 + addr
    return None


# Patterns we recognise in .asm source
_ORG_RE    = re.compile(r'^\s*org\s+\$([0-9A-Fa-f]{2,6})', re.IGNORECASE)
_DB_RE     = re.compile(r'^\s*db\b',  re.IGNORECASE)
_DW_RE     = re.compile(r'^\s*dw\b',  re.IGNORECASE)
_DL_RE     = re.compile(r'^\s*dl\b',  re.IGNORECASE)
_SKIP_RE   = re.compile(r'^\s*skip\s+(\d+)', re.IGNORECASE)
_COMMENT   = re.compile(r';.*$')
_DIRECTIVE = re.compile(r'^\s*(arch|hirom|lorom|incsrc|incbin|namespace|pushns|pullns)\b', re.IGNORECASE)


def count_db_bytes(line: str) -> int:
    """Count how many bytes a 'db ...' line emits."""
    line = _COMMENT.sub('', line)
    after = re.sub(r'^[^,]*db\s*', '', line, flags=re.IGNORECASE)
    total = 0
    # quoted strings contribute their character count, not 1
    for part in re.split(r'(?<=["\'])\s*,\s*|,\s*(?=["\'])|(?<=["\'])\s*$|^\s*(?=["\'])', after):
        part = part.strip().strip(',').strip()
        if not part:
            continue
        if part.startswith('"') or part.startswith("'"):
            # count string chars (ignoring quotes and escape sequences for now)
            inner = part.strip('"\'')
            total += len(inner)
        else:
            # comma-separated non-string items
            items = [p.strip() for p in part.split(',') if p.strip()]
            total += len(items)
    return total


def count_dw_bytes(line: str) -> int:
    line = _COMMENT.sub('', line)
    after = re.sub(r'^[^,]*dw\s*', '', line, flags=re.IGNORECASE)
    parts = [p.strip() for p in after.split(',') if p.strip()]
    return len(parts) * 2


def count_dl_bytes(line: str) -> int:
    line = _COMMENT.sub('', line)
    after = re.sub(r'^[^,]*dl\s*', '', line, flags=re.IGNORECASE)
    parts = [p.strip() for p in after.split(',') if p.strip()]
    return len(parts) * 3


def scan_asm_file(path: Path) -> set[int]:
    """
    Return a set of ROM file offsets that this .asm file explicitly defines.
    Tracks org position and advances it for each instruction-like line.
    This is a conservative approximation — it counts lines that look like
    they emit bytes, not a full assembler pass.
    """
    covered: set[int] = set()
    cur_pc: int | None = None

    with open(path) as f:
        for raw_line in f:
            line = raw_line.rstrip()

            # org directive — update current PC
            m = _ORG_RE.match(line)
            if m:
                cur_pc = int(m.group(1), 16)
                # Expand short forms: if < 6 hex chars, it's fine as a PC
                if cur_pc < 0x8000:
                    cur_pc = None  # address in system area, not ROM
                continue

            if cur_pc is None:
                continue

            # skip directive
            m = _SKIP_RE.match(line)
            if m:
                cur_pc = (cur_pc + int(m.group(1))) & 0xFFFFFF
                continue

            # Directives that don't emit bytes
            if _DIRECTIVE.match(line):
                continue

            # Comments and blank lines
            stripped = _COMMENT.sub('', line).strip()
            if not stripped:
                continue

            # Data directives
            if _DB_RE.match(line):
                n = count_db_bytes(line)
                off = hirom_to_offset(cur_pc)
                if off is not None:
                    for i in range(n):
                        covered.add(off + i)
                cur_pc = (cur_pc + n) & 0xFFFFFF
                continue
            if _DW_RE.match(line):
                n = count_dw_bytes(line)
                off = hirom_to_offset(cur_pc)
                if off is not None:
                    for i in range(n):
                        covered.add(off + i)
                cur_pc = (cur_pc + n) & 0xFFFFFF
                continue
            if _DL_RE.match(line):
                n = count_dl_bytes(line)
                off = hirom_to_offset(cur_pc)
                if off is not None:
                    for i in range(n):
                        covered.add(off + i)
                cur_pc = (cur_pc + n) & 0xFFFFFF
                continue

            # Anything else that looks like an instruction (starts with a mnemonic)
            # We can't know byte length without a full assembler, so we skip counting
            # those here — only data/org directives are tracked for now.

    return covered


def scan_all_asm() -> tuple[set[int], dict[str, set[int]]]:
    """Scan all bank asm files; return (all_covered, per_bank_covered)."""
    all_covered: set[int] = set()
    per_bank: dict[str, set[int]] = {}

    for bank_dir in sorted(ASM_DIR.glob('bank*/')):
        bank_name = bank_dir.name  # e.g. 'bank00'
        bank_covered: set[int] = set()
        for asm_file in bank_dir.glob('*.asm'):
            covered = scan_asm_file(asm_file)
            bank_covered.update(covered)
        per_bank[bank_name] = bank_covered
        all_covered.update(bank_covered)

    return all_covered, per_bank


def format_stats(total_covered: set[int], per_bank: dict[str, set[int]]) -> str:
    total_bytes = ROM_SIZE
    matched = len(total_covered)
    pct = 100.0 * matched / total_bytes

    lines = [
        '# Matching Progress',
        '',
        f'Overall: **{matched:,} / {total_bytes:,} bytes matched ({pct:.4f}%)**',
        '(data bytes counted by script; instruction bytes verified via `make diff`)',
        '',
        '| Bank | Description | Status | Notes |',
        '|------|-------------|--------|-------|',
    ]

    # Known bank descriptions
    desc = {
        'bank00': 'Boot / core engine',
        'bank01': 'TBD',
        'bank02': 'TBD',
        'bankFD': 'Main init + engine core',
    }

    # Banks that have source with instructions (not just data bytes).
    # progress.py counts explicit db/dw/dl only; instruction-only banks
    # still count as Partial if they have any org-bearing .asm files.
    def has_asm_content(bank_dir: Path) -> bool:
        for f in bank_dir.glob('*.asm'):
            if re.search(r'^\s*org\b', f.read_text(), re.IGNORECASE | re.MULTILINE):
                return True
        return False

    all_banks = sorted(set(list(per_bank.keys()) + list(desc.keys())))
    for b in all_banks:
        n = len(per_bank.get(b, set()))
        bnum = b.replace('bank', '$').upper()
        bdesc = desc.get(b, 'TBD')
        bank_dir = ASM_DIR / b
        if n > 0:
            status = 'Partial'
            note = f'{n} data bytes'
        elif bank_dir.exists() and has_asm_content(bank_dir):
            status = 'Partial'
            note = 'instructions only (see asm/)'
        else:
            status = 'Unmapped'
            note = ''
        lines.append(f'| {bnum} | {bdesc} | {status} | {note} |')

    lines += [
        '',
        '## Legend',
        '',
        '- **Unmapped** — haven\'t identified what lives here yet',
        '- **Partial** — some functions matched, bank not complete',
        '- **Matched** — entire bank reassembles byte-identical',
        '',
        '## Next steps',
        '',
        '1. Trace `MainInit` at `$FD:C000` — real hardware init',
        '2. Map RAM-resident NMI/IRQ handlers (loaded to $000500/$000504)',
        '3. Label data tables at `$00:FF20–$00:FF2F` (bit-mask LUT)',
        '4. Sweep bank $FD once `MainInit` is matched',
    ]

    return '\n'.join(lines) + '\n'


def main() -> int:
    update = '--update' in sys.argv

    all_covered, per_bank = scan_all_asm()
    output = format_stats(all_covered, per_bank)

    if update:
        PROGRESS_MD.write_text(output)
        print(f'Updated {PROGRESS_MD}')
    else:
        print(output)
        print(f'(dry run — pass --update to write to {PROGRESS_MD})')

    total = ROM_SIZE
    matched = len(all_covered)
    pct = 100.0 * matched / total
    print(f'\nSummary: {matched:,} / {total:,} bytes ({pct:.4f}%)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
