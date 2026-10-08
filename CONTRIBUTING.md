# Contributing

This project is early enough that the most valuable contributions right
now are structural, not just function-matching:

## Ways to help

- **Bank mapping** — identifying what lives where in ROM, even roughly,
  before anything is matched
- **Function matching** — the core loop: disassemble → label → verify
  byte-exact reassembly (see README "Workflow")
- **Tooling** — better diffing, automated progress tracking, CI
- **Data/graphics cataloging** — identifying compressed blobs, tile data,
  and their formats (separate from code matching, but needed eventually)

## Ground rules

- **No ROM data, headers, or extracted assets in commits.** Ever. Tools
  and source only. If in doubt, don't commit it.
- **Verified and readable, or not on main.** See "The main-branch gate"
  below.
- **Byte-exact means byte-exact.** A function that "looks equivalent" but
  doesn't reassemble identically isn't matched yet — logically-equivalent
  but differently-encoded assembly is common on 65816 and needs to be
  resolved before marking something done.
- **Cite your reasoning in labels/comments.** When you name a routine or
  variable, leave a short comment on how you inferred its purpose (trace
  output, cross-reference, etc.) so others can verify or correct it.
- **One PR per logical unit** — a bank section, a routine, a tooling
  change. Keeps review sane.

## The main-branch gate: verified AND readable

A function only reaches `main` when it is both:

1. **Verified** — `make diff` matches, and `make verify` proves every byte
   the source emits equals the ROM (it assembles onto blank bases, so a
   routine that silently fails to emit can't hide behind original bytes).
2. **Readable** — it reads like well-named code, not like a hex dump:
   - **Named structures instead of raw offsets.** Memory operands use a
     name from `asm/include/ram_*.inc`: a variable (`!ActivePcSlot`), a
     per-slot array (`!Battler_Present,X`), or a struct field for repeated
     records (`PcStats[1].Status`). Unknown-purpose locations still get a
     name (`!Battle_Unk9F38`) plus a comment on what's been observed.
   - **Named calls instead of addresses.** Every `JSR`/`JSL`/`JMP`/`BRL`/
     branch and jump-table entry targets a label. Routines not matched yet
     get a label-only stub in `asm/include/unmatched.asm`.
   - **Named constants.** Immediates above 8 are named in
     `asm/include/constants*.inc` (`!TargetMode_AllFlag`,
     `!NumBattlers`). `REP`/`SEP` masks are exempt.
   - **Explicit widths.** Any instruction using a define or struct field
     states `.b`/`.w`/`.l` — defines are textual, so the encoding must not
     depend on how a value happens to be written.
   - **No test plumbing in game code.** No `print`/`assert`/`warnpc`, no
     label-only stubs, no hand-encoded opcodes (`db $A9,$7F`) — use a
     named macro from `asm/include/macros.inc` if an encoding really needs
     one.

`make lint` checks the mechanical part (`tools/lint_readability.py`; a
line may opt out of one finding with `; lint-ok: <reason>`). Naming
quality — is the name *right*, is the comment's inference honest — is
checked by an independent review before merge.

Functions written before the gate are listed in
`tools/readability_baseline.txt` and are being brought up to standard
first, each re-verified and independently reviewed. The list may only
shrink: the hook fails if a function outside it has findings, or if an
entry in it is already clean. `make gate` runs all three checks.

## Getting started

1. `python3 tools/check_env.py` to confirm your toolchain
2. Check `docs/PROGRESS.md` for open areas
3. Drop your own legally-dumped ROM in `roms/` (never committed)
4. `make diff` should report a 100% match against a completely empty
   `asm/main.asm` — that's the correct starting state before you've
   matched anything
