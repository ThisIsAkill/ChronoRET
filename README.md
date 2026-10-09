# ChronoRET — Chrono Trigger (SNES) Matching Decompilation

A personal side project for learning 65816 assembly and SNES reverse engineering.
I started this to understand how the game actually works at the machine level —
it's just me working through the code as I go, not a professional or team effort.

The goal is a byte-exact matching decompilation of the 1995 US SNES release:
labeled, human-readable 65816 assembly that reassembles to an identical ROM.

This is **not** a remake and **not** a fan translation project — it's a 1:1
reconstruction of the original code, for preservation and as a foundation for
future study or modding. In spirit similar to the Chrono Cross decomp and the
Ship of Harkinian project for Ocarina of Time, but strictly one person learning.

## Status

Work in progress. Every number (bytes and functions matched, readable and
verified, per bank) is generated from the source, never typed into a doc: see
the [Progress page](https://thisisakill.github.io/Kajar-site/PROGRESS/) on the
Kajar site, or run `make progress` (`python3 tools/progress.py`) locally. The
banks being worked on are listed under "Repo layout" below.

Progress notes, the address map, the devlog and a function-level breakdown
live in the companion wiki, **[Kajar](https://thisisakill.github.io/Kajar-site/)**.

Where things stand right now and what's next: [STATUS.md](STATUS.md) and
[NEXT.md](NEXT.md). Every function and its status: `symbols/functions.csv`, written by
`python3 tools/progress.py --update` (generated, not tracked).

## You need your own ROM

This project ships **tools only**, never the game itself. To build or verify
anything you must supply your own legally-dumped ROM:

```
roms/chrono_trigger.sfc   ← place it here (gitignored, never committed)
```

Target: US 1.0, unheadered, 4 MiB. SHA-256:
`06d1c2b06b716052c5596aaa0c2e5632a027fee1a9a28439e509f813c30829a9`
(also in `rom.sha256`, which CI checks; `sha256sum -c rom.sha256` checks yours)

## Requirements

- `asar` 1.91 (65816 assembler)
- Python 3.10+
- A SNES emulator with a debugger for tracing (bsnes-hd or Mesen-S recommended)
- `make`

## Repo layout

```
asm/        65816 source, organized by bank; main.asm includes them all
  bank00/   Bank $00 — boot page: reset entry, vectors, wave tables, ROM header
  bankC0/   Bank $C0 — core engine (game loop, VBlank, sprites, field,
            event script, map scrolling)
  bankC1/   Bank $C1 — battle engine (math, status bar, command menu,
            targeting, action scripts)
  bankC2/   Bank $C2 — menu/scene bank (entry vectors, scene engine and its
            script, text windows)
  bankCC/   Bank $CC — battle helpers (a copy of the 8×8 multiply so far)
  bankCF/   Bank $CF — battle support (a sine lookup, number formatting)
  bankFD/   Bank $FD — MainInit (hardware init from reset), battle setup helpers
  bankFF/   Bank $FF — a copy of the bank $00 wave tables so far
  hardware.inc  SNES register names
  include/  Shared names: RAM (ram_*.inc), constants, macros, unmatched-routine labels
symbols/    review log (reviews/, one file per round) and progress history
            (tracked); functions.csv (every function and its status) and
            progress.json are generated on demand by tools/progress.py and
            never committed
tools/      Build, diff and verify scripts, lint, drafting and xref tools,
            git hooks, session helpers
rom.sha256  SHA-256 of the target ROM (checked by CI)
roms/       Your own ROM goes here (gitignored)
build/      Build output (gitignored)
```

Documentation (progress, bank map, architecture, devlog) is published as
[Kajar](https://thisisakill.github.io/Kajar-site/) and is not bundled here.

## Workflow

1. Pick the next target from [NEXT.md](NEXT.md).
2. Draft it (`make draft ADDR=C1:3714`, see CONTRIBUTING.md "Workflow tools") and work out what
   it does.
3. Write it readable from the start ([STYLE.md](STYLE.md)): named RAM, calls
   and constants. A literal transcription is fine on a work branch, never on
   `main`.
4. `make gate`: byte-exact (`make diff`), every emitted byte proven
   (`make verify`), readable (`make lint`).
5. Independent review, recorded as a new round file in `symbols/reviews/`; then
   `tools/progress.py --update` marks the function `verified`.
6. Session end: `tools/end_session.sh`.

See [CONTRIBUTING.md](CONTRIBUTING.md), "Definition of done".

## Why assembly, not C

Most modern decomps (N64, GameCube) target C because MIPS/PowerPC compilers of
that era produce predictable, matchable output. SNES-era games were largely
**hand-written in 65816 assembly**, not compiled from C — so "decompilation"
here means **disassembly + labeling + verified reassembly**, not C recovery.
A C layer may come later for tooling purposes, but matching happens at the asm level.

## Legal

Tools and source only. No ROM data, no copyrighted assets, no compressed
graphics or music are stored here. Contributors must own a legal copy of the game.

This code is MIT-licensed (see `LICENSE`). The ROM and its assets are **not
included** and remain the property of their copyright holders — supply your
own legally obtained ROM (see "You need your own ROM" above). Symbol and
label credit: dscotton/ct_disassembly (public domain), used as a starting
point for labels and boundaries where not yet independently verified here.
