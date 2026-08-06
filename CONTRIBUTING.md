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
- **Byte-exact means byte-exact.** A function that "looks equivalent" but
  doesn't reassemble identically isn't matched yet — logically-equivalent
  but differently-encoded assembly is common on 65816 and needs to be
  resolved before marking something done.
- **Cite your reasoning in labels/comments.** When you name a routine or
  variable, leave a short comment on how you inferred its purpose (trace
  output, cross-reference, etc.) so others can verify or correct it.
- **One PR per logical unit** — a bank section, a routine, a tooling
  change. Keeps review sane.

## Getting started

1. `python3 tools/check_env.py` to confirm your toolchain
2. Check `docs/PROGRESS.md` for open areas
3. Drop your own legally-dumped ROM in `roms/` (never committed)
4. `make diff` should report a 100% match against a completely empty
   `asm/main.asm` — that's the correct starting state before you've
   matched anything
