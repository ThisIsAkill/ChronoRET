# Contributing

Current numbers are published on the [Kajar site](https://thisisakill.github.io/Kajar-site/); for local numbers, run `python3 tools/progress.py`.

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
- **Matched, readable and reviewed, or not on main.** See "Definition of
  done" below.
- **Byte-exact means byte-exact.** A function that "looks equivalent" but
  doesn't reassemble identically isn't matched yet — logically-equivalent
  but differently-encoded assembly is common on 65816 and needs to be
  resolved before marking something done.
- **Cite your reasoning in labels/comments.** When you name a routine or
  variable, leave a short comment on how you inferred its purpose (trace
  output, cross-reference, etc.) so others can verify or correct it.
- **One PR per logical unit** — a bank section, a routine, a tooling
  change. Keeps review sane.

## Definition of done

A routine goes to `main` only when it is **matched, readable and reviewed**. Its status in
`symbols/functions.csv` is computed by `tools/progress.py`, never set by hand; each level
includes the one before. (`functions.csv` and `progress.json` are generated and not tracked:
every tool that reads them regenerates them when they are stale, and
`python3 tools/progress.py --update` writes them on disk.)

| Status | Means |
|---|---|
| `matched` | every byte from its label to the next is emitted by the source and equals the ROM (`make diff`, and `make verify`, which assembles onto blank bases so a routine can't hide behind original bytes) |
| `readable` | it follows [STYLE.md](STYLE.md): `tools/lint_readability.py` finds nothing in it |
| `verified` | an independent reviewer approved its current source (a row in the review log, `symbols/reviews/`) |

- **Readable:** named RAM, structs, calls and constants; explicit widths; no hand-encoded
  opcodes or test plumbing (STYLE.md). A literal transcription is fine on your work branch; it
  never goes to `main`. Routines matched before this rule are listed in
  `tools/readability_baseline.txt`; that list may only shrink, and the hook fails if it grows or
  still lists a routine that is already clean.
- **Reviewed:** before a routine counts as `verified`, someone who did not write it checks that
  the names and comments are right — the bytes are already proven, so review is about whether
  the code tells the truth. The approval is a row in the review log, one CSV file per review
  round: `symbols/reviews/r047.csv` for round 47 (`legacy.csv` holds the rows from before
  rounds were numbered). Each file starts with the header line
  `address,name,date,reviewer,verdict,source_hash,notes`; `verdict` is `approved` or `changes`,
  and `source_hash` is copied from the routine's row in `symbols/functions.csv`. A new round is
  always a new file, never an append to an old one, so rounds recorded on different branches
  never conflict. The files are read in round order; a routine's last row is its verdict.
  Editing the routine changes its hash, so the approval stops counting until it is reviewed
  again. `tools/validate_functions.py` checks the files in the hook and in CI.
- **Generated numbers:** no doc carries counts or percentages; they are published on the
  [Kajar site](https://thisisakill.github.io/Kajar-site/) and printed locally by
  `python3 tools/progress.py`. Never type one by hand, and never commit `symbols/functions.csv`
  or `symbols/progress.json` (the hook refuses them; `tools/progress.py --check` fails if one is
  tracked).

`make gate` runs the diff, the coverage proof and the lint in one go.

## Workflow tools

- `make draft ADDR=C1:3714` (`tools/draft.py`) starts a match from source instead of raw
  bytes. It disassembles the routine from that address until it ends (every path has returned
  or jumped away and no branch of its own reaches further; `END=C1:373A` fixes the end),
  tracking M/X, DP and DB, and writes `build/draft_C13714.asm`: asar source with a header
  skeleton (Entry state, widths at the return, the generated Callers block, callees), `.loc_XXXX`
  labels, and every operand the project already has a name for (RAM and DP defines, struct
  fields, registers, matched labels and stubs, constants used in the same context elsewhere),
  with explicit widths. It then assembles the draft in place of the region in a temporary copy
  of the tree, confirms `make diff` and that every byte of the region is emitted, and prints
  what the lint still finds. The default entry state is M=1, X=0, DP=0, DB=$7E; pass another
  with `DRAFT_ARGS="--x 1 --dp 0100 --db 00"`. What is left is the matcher's: every `TODO`
  (purpose, literals with no name yet, constants it would not guess, the stubs it lists for
  unknown targets, direct-page aliases), and a check of every name it chose — it names by
  address and by use elsewhere, not by meaning. Where M/X becomes unknown (a `PLP` without a
  matching `PHP`, paths that disagree) it stops and says so. `python3 tools/draft.py ADDR
  --compare` drafts an already matched routine and compares it with the hand-written source.
- `make xref ADDR=C100D7` (also `$C1:00D7` quoted, or a label; `tools/xref.py`) lists every
  `JSR`/`JMP` (same bank), `JSL`/`JML` (any mirror) and `BRL` to an address, plus 8-bit branches
  with `XREF_FLAGS=--branches` and machine output with `--json`. Each hit is CONFIRMED (on an
  instruction boundary) or DOUBTFUL (inside another instruction's operand, or in data), and
  names the matched routine that contains it. Matched code is judged from the assembled source
  (asar's address-to-line map); unmatched code by decoding forward from the 64 bytes before
  the hit under each M/X start state and voting. The vote is a heuristic: read a CONFIRMED hit
  in unmatched code before you rely on it.
- `python3 tools/callers.py --update` rewrites the `; Callers (...)` block of every header from
  xref's CONFIRMED sites (`--show NAME` prints one, `--check` lists the ones that differ). Run
  it after matching code and after merging `origin/main`: new routines change other routines'
  blocks (a site that was `unmatched` gets its routine's name). The block is generated, not
  reviewed, and left out of the source hash, so this never voids a review. Hand-written remarks
  about callers go on a `; Callers note:` line.
- `make lint` also checks routine headers (`HEADER`, `CALLERS`, see STYLE.md): Entry and Exit
  lines, and that every Callers block is exactly what `tools/callers.py` generates.

- Data tables next to matched code (jump tables,
pointer tables, lookup tables) are the cheapest bytes to match:
  - `make tables-scan BANK=C1` ranks candidate tables in the bank's unmatched bytes, with the
  instruction that reads each one (`JSR (T,X)` at ...) and a confidence.
- `python3 tools/tables.py emit '$C1:1FF8' --count 33 --kind words` prints a table as source:
  header, then `dw`/`dl`/`db` lines whose pointers use existing label names (`; TODO name` where
  the target has none). `--kind bytes` and `--kind records:SIZE` give aligned hex rows.
- The draft still needs what any routine needs: a real header (what it holds, how it is
  indexed), names for its targets, and `make gate`.

## Keeping a branch up to date

Bring a feature branch up to date with `main` by merging, never by rebasing:

```sh
git fetch origin
git merge origin/main
```

Then run `python3 tools/callers.py --update` (code matched on `main` changes other headers'
Callers blocks) and `make gate`. Nothing generated is committed, so a merge only conflicts
where two branches really edited the same lines: `symbols/functions.csv` and `progress.json` are not tracked (the tools
regenerate them), the docs carry no generated numbers, and each review round is its own file
under `symbols/reviews/`. A conflict inside a generated Callers block is resolved by taking
either side and rerunning `tools/callers.py --update`. The pre-push hook checks the identity and messages of every commit
the push would publish, and skips commits already on `origin` (such as GitHub's merge commits
brought in by the merge).

**Changing the standard.** A change to STYLE.md or to the lint's rules is its own commit, approved
by the maintainer and logged under "Decisions" in STATUS.md. It never rides along inside a code
revision, so no routine is ever judged by a rule its own author just wrote.

## Getting started

1. `python3 tools/check_env.py` to confirm your toolchain
2. Check [NEXT.md](NEXT.md) for the queue and [STATUS.md](STATUS.md) for where things stand
3. Drop your own legally-dumped ROM in `roms/` (never committed)
4. `make diff` should report a 100% match against a completely empty
   `asm/main.asm` — that's the correct starting state before you've
   matched anything
