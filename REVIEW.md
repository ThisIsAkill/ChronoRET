# Review

How a routine goes from **readable** to **verified**. The reviewer is someone
(or some session) that did not write the routine. They get the source, the ROM,
STYLE.md and this file, nothing else. A verdict is a row in
`symbols/reviews.csv`, and it holds only for the exact source it read: the row
carries the routine's `source_hash`, and any later edit to the routine, header
included, sends it back for review.

## What the tools already check

Don't spend review time on these. If one is wrong, the gate is wrong; report it.

| Check | Tool |
|---|---|
| The source assembles to the ROM, byte for byte | `make diff` |
| Every byte the source claims is really emitted by it | `tools/verify.py` |
| Named operands, calls and constants; explicit widths; no plumbing | `tools/lint_readability.py` |
| Every header has an Entry and an Exit line | lint rule `HEADER` |
| Every confirmed caller is accounted for in the header | lint rule `CALLERS` (uses `tools/xref.py`) |

To check a caller claim by hand, use `python3 tools/xref.py $BB:AAAA`. Don't
write a new scanner: raw byte searches find false hits inside other
instructions' operands.

## Packets

A packet is one subsystem cluster: all the routines of one system that were
matched or changed together, such as the target modes, the position queries,
or the sprite builders. It is never a scattered list. A reviewer who reads a
whole cluster knows its variables and conventions after the first few
routines, and can check the rest faster and more thoroughly. Split a cluster
only when it is too large for one sitting, and split it along its own
seams.

## Outside sources

Community documents (RAM maps, data-format notes, other disassemblies) are
leads, not evidence. A name or meaning taken from one is accepted only once
the code shows it, through the values written, what reads them, or what the
player sees. Until then it is hedged and the header names the source. A
reviewer treats an unsupported claim that came from a source like any other
unsupported claim.

## What the reviewer checks

Approve only if all four hold. Otherwise the verdict is `changes`, with the
concrete fix.

1. **Every claim is true.** Each comment, name and header line is checked
   against the ROM. That covers what the code does, the values in tables, byte
   ranges, side effects and quirks.
2. **The CPU state is right.** The Entry and Exit lines exist (the lint checks
   that), and they are correct:
   - M, X, DP and DB, wherever the code depends on them. A routine that uses
     `.b` direct-page operands or `TDC` to load zero depends on DP. A routine
     with `.w` absolute operands depends on DB. State them in each header, not
     only in a bank banner.
   - Registers and direct-page bytes left changed, including those changed by
     callees.
   - Flags that callers branch on, for example "C=1: nothing drawn" or
     "Z set iff ready".
   - A register that is preserved, when a caller relies on that.
3. **Names don't mislead.**
   - No labels made of raw addresses (`CODE_C10C46`, `.e952_loop`).
   - `Sub_xxxx` is allowed only if the header says the purpose is unknown.
   - A name doesn't keep a meaning the header itself says is wrong (the old
     `PV_` prefix, "primary/secondary").
4. **Unknowns are hedged.** A meaning that isn't established is either called
   unknown (`Unk` names) or hedged ("probably", "looks like"), and the header
   says what the guess rests on.

## Not reasons for `changes`

- Wording you would merely prefer.
- A missing clobber that nothing depends on, when the Exit line is otherwise
  right and nothing surprising is changed.
- A name that is vague but not false, when the header explains it.

Put these in the notes as optional, so the next edit can pick them up.

## Writing the verdict

```
address,name,date,reviewer,verdict,source_hash,notes
```

- `source_hash` is copied from the packet (`symbols/functions.csv`), not
  recomputed.
- The notes are one quoted line of 200 characters at most:
  - For `changes`: what is wrong and the fix.
  - For `approved`: what was checked.

## Decisions

Standing rules from past rounds. Apply them every time.

| Decision | Since |
|---|---|
| Each routine header states DP and DB itself; a bank banner doesn't cover them. | 2026-10-08 |
| A widely used helper may give its callers as a count with examples ("20 JSR sites, e.g. $C1:1CBE"). | 2026-10-08 |
| The `$C10003`/`$C10045` service table is reached only from inside bank $C1; don't call it cross-bank. | 2026-10-08 |
| Jump and call instructions are exempt from the explicit-width rule (STYLE.md). | 2026-10-08 |
| A quirk of the original (dead code, a redundant instruction, an apparent bug) is kept and documented, never "fixed". | always |
