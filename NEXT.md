# Next

The queue, in order. Take the first item and run it to the end (CONTRIBUTING.md,
"Definition of done").

## Readability burn-down (first)

1. Bank $C1: every routine in `tools/readability_baseline.txt` up to STYLE.md, re-verified
   (`make gate`), then independently reviewed (`symbols/reviews.csv`).
2. Bank $C0: the same, cluster by cluster.
3. Reviews for the routines that are already readable (banks $00, $FD and the clean $C1 ones).

## Matching

0. Quick wins from `tools/find_duplicates.py` (byte-identical copies of verified routines):
   `Battle_Mul8` again at `$CC:F365`; the two wave tables again at `$FF:F759` and `$FF:F799`.
   A relocation-tolerant mode (masking absolute JSR/JMP/JSL operands) should find more.
1. `$C1:1C4A–$C1:1F78`: the gap between `BattleMenu_LoadCommandWindowMap` and
   `BattleMenu_BuildTargetList`.
2. `$C1:106E–$C1:10E2`: service 3 of the $C10045 API (periodic/idle check). Needs stubs for
   `BattleSys_PumpFrames`, `Battle_TickPcSlots`, `Battle_TickStatusEffectVisuals`,
   `Battle_CacheBattlerCoordsAll`.
3. Bank $C1 past `$C1:283D`: enemy logic, battle animation (scouted in session 33).
4. `$C0:881E` and the per-frame calls `$1AAC`, `$21E1`, `$274D` from the main loop.

## Tables

`make tables-scan BANK=C0` (or `C1`, `CC`) lists these with more; `tools/tables.py emit` drafts
the source. Lengths are drafts: check each against its dispatcher before matching. All the
dispatch sites below were checked by hand to be `TAX` ... `JSR (table,X)` sequences.

1. Read by matched code, still original bytes: `$C0:F300` `!BattleRom_AngleTable`
   (Battle_CalcAngle), `$C0:F900` `!BattleRom_SineTable` (1024 B, Battle_SinLookup; ends where
   BitReverseTable begins), and the 24 `!BattleRom_*` tables at `$CC:F38C–$CC:FB8D` read by the
   battle menu (they need a `bankCC.asm`).
2. `$C1:0051`, 10 words: the $C10045 service dispatcher's table (`JSR (T,X)` at `$C1:004A`);
   services 1, 2 and 7 are matched, the rest need stubs.
3. `$C0:5D6E` `Evt_OpcodeTable`, 256 words (`JSR (T,X)` at `$C0:5977` in Evt_RunObj0Func1, and
   Evt_RunObjInit); ends at `$C0:5F6E`, the shared handler for unused opcodes. Needs a name per
   handler first.
4. Dispatch tables right after (or near) their dispatcher, bank $C0: `$C0:400E` (16 words,
   `$C0:4009`), `$C0:21EE` (~16, `$C0:21EA`), `$C0:7181` (12, `$C0:717D`), `$C0:6477` (8,
   `$C0:633D`), `$C0:9FF7` (65, `$C0:9ECD`).
5. Bank $C1: `$C1:2D81` (~21 words, `$C1:29AE`, the closest to matched code), `$C1:3216` (15,
   `$C1:30B2`), `$C1:3760` (9, `$C1:375C`), `$C1:B80D` (157, `$C1:874E`), `$C1:FA61` (21,
   `$C1:EB45`), `$C1:D126` (6, `$C1:CFE1`), `$C1:DA31` (4, `$C1:D783`).
