# ChronoRET — Chrono Trigger (SNES) Matching Decompilation

A personal side project for learning 65816 assembly and SNES reverse engineering.
I started this to understand how the game actually works at the machine level —
it's just me working through the code as I go, not a professional or team effort.  I am also using claude AI for the commit descriptions, I felt like it's one less thing I can stop worrying about.  That is all the AI is going yo be used for.

The goal is a byte-exact matching decompilation of the 1995 US SNES release:
labeled, human-readable 65816 assembly that reassembles to an identical ROM.

This is **not** a remake and **not** a fan translation project — it's a 1:1
reconstruction of the original code, for preservation and as a foundation for
future study or modding. In spirit similar to the Chrono Cross decomp and the
Ship of Harkinian project for Ocarina of Time, but strictly one person learning.

## Status

**In progress.** ~10,184 bytes matched byte-exact across banks $00, $C0, and $FD
(36 functions, ~0.24% of the 4 MB ROM).

Matched regions so far include the full engine spine — reset vectors, hardware
init, game loop, VBlank handler, per-frame state init, OAM culling — plus the
complete sprite subsystem (render dispatch, all type/state init helpers, OAM
packing) and the per-frame state machine through its mode handler cluster.

Progress notes and function-level breakdown live in a companion wiki
(not yet public).

## You need your own ROM

This project ships **tools only**, never the game itself. To build or verify
anything you must supply your own legally-dumped ROM:

```
roms/chrono_trigger.sfc   ← place it here (gitignored, never committed)
```

Target: US 1.0. SHA-256 is documented in the wiki's ROM_HASH page.

## Requirements

- `asar` 1.91 (65816 assembler)
- Python 3.10+
- A SNES emulator with a debugger for tracing (bsnes-hd or Mesen-S recommended)
- `make`

## Repo layout

```
asm/        65816 source, organized by bank
  bank00/   Bank $00 — boot, vectors, wave tables, ROM header
  bankFD/   Bank $FD — MainInit (hardware init from reset)
  bankC0/   Bank $C0 — core engine (game loop, sprite system, per-frame SM)
  data/     Non-code data: tables, compressed blobs
src/        (future) matched/reorganized code once patterns stabilize
tools/      Build scripts, diff tools, disassembler, session helpers
build/      Build output (gitignored)
```

The wiki (PROGRESS.md, BANK_MAP.md, ARCHITECTURE.md, devlog) lives in a
separate repository at `../chrono-trigger-wiki/` and is not bundled here.

## Workflow

1. Pick an unmatched region from BANK_MAP.md in the wiki
2. Disassemble it (`tools/disasm.py`)
3. Label it — figure out what it does, name the routine and its locals
4. Reassemble with `make` and diff against the original ROM (`tools/diff_rom.py`)
   to confirm a byte-exact match
5. Commit the matched `.asm` file

## Why assembly, not C

Most modern decomps (N64, GameCube) target C because MIPS/PowerPC compilers of
that era produce predictable, matchable output. SNES-era games were largely
**hand-written in 65816 assembly**, not compiled from C — so "decompilation"
here means **disassembly + labeling + verified reassembly**, not C recovery.
A C layer may come later for tooling purposes, but matching happens at the asm level.

## Legal

Tools and source only. No ROM data, no copyrighted assets, no compressed
graphics or music are stored here. Contributors must own a legal copy of the game.
