# Chrono Trigger (SNES) — Matching Decompilation

An in-progress matching decompilation of the original 1995 SNES release of
Chrono Trigger. The goal is to reconstruct labeled, human-readable 65816
assembly (and eventually C, where feasible) that reassembles to a
byte-identical ROM.

This is **not** a remake and **not** a fan translation project — it's a
1:1 reconstruction of the original game's code, for preservation, modding,
and as a foundation for future native ports (in the spirit of Ship of
Harkinian for Ocarina of Time, or the Chrono Cross decomp already underway).

## Status

**In progress.** ~1247 bytes matched byte-exact across banks $00, $C0, and $FD.
Matched routines include the full engine spine: reset vectors, hardware init,
game loop, VBlank handler, per-frame state init, and OAM culling.
See `docs/PROGRESS.md` for the function-level breakdown.

## You need your own ROM

This project ships **tools only**, never the game itself. To build or
verify anything you must supply your own legally-dumped ROM.

Expected file: `chrono_trigger.sfc` (or `.smc` — see `tools/strip_header.py`)
placed in `roms/` (gitignored, not included).

```
sha256sum roms/chrono_trigger.sfc
```
Put the hash in `docs/ROM_HASH.md` once confirmed so contributors know
which release/region the project targets (US 1.0, JP, or PAL — code
differs between them).

## Requirements

- `asar` (65816 assembler) — used to reassemble matched code
- Python 3.10+
- A SNES emulator with a debugger for tracing (bsnes-hd or Mesen-S recommended)
- `make`

## Layout

```
asm/            Disassembled 65816 source, organized by ROM bank
  bank00/       Bank $00 — boot, core engine
  bank01/       Bank $01 — (TBD once mapped)
  bank02/       Bank $02 — (TBD once mapped)
  data/         Non-code data: graphics, compressed blobs, tables
src/            Matched/reorganized code once patterns are established
tools/          Build scripts, diffing tools, ROM utilities
build/          Build output (gitignored)
docs/           Notes, bank maps, function catalogs, matching progress
```

## Workflow

1. Pick an unmatched region (see `docs/PROGRESS.md` once it exists)
2. Disassemble it if not already split out (`tools/split_bank.py`)
3. Label it — figure out what it does, name the routine and its locals
4. Reassemble with `make` and diff against the original ROM
   (`tools/diff_rom.py`) to confirm a byte-exact match
5. Commit the matched `.asm` file with a description of what the routine does

## Why 65816, not C

Most modern decomp projects (N64, GameCube) target C because MIPS/PowerPC
compilers of that era produce fairly predictable, matchable output from
handwritten C. SNES-era games were largely **hand-written in 65816
assembly**, not compiled from C — so "decompilation" here really means
**disassembly + labeling + verified reassembly**, not C recovery. A C layer
may be layered on top later for tooling/readability, but matching happens
at the assembly level.

## Legal

Tools and disassembly notes only. No copyrighted assets, no ROM data, no
compressed graphics or music are stored in this repository. Contributors
must own a legal copy of the game.
