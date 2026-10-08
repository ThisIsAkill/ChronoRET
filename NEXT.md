# Next

The queue, in order. Take the first item and run it to the end (CONTRIBUTING.md,
"Definition of done").

## Readability burn-down (first)

1. Bank $C1: every routine in `tools/readability_baseline.txt` up to STYLE.md, re-verified
   (`make gate`), then independently reviewed (`symbols/reviews.csv`).
2. Bank $C0: the same, cluster by cluster.
3. Reviews for the routines that are already readable (banks $00, $FD and the clean $C1 ones).

## Matching

1. `$C1:1C4A–$C1:1F78`: the gap between `BattleMenu_LoadCommandWindowMap` and
   `BattleMenu_BuildTargetList`.
2. `$C1:106E–$C1:10E2`: service 3 of the $C10045 API (periodic/idle check). Needs stubs for
   `BattleSys_PumpFrames`, `Battle_TickPcSlots`, `Battle_TickStatusEffectVisuals`,
   `Battle_CacheBattlerCoordsAll`.
3. Bank $C1 past `$C1:283D`: enemy logic, battle animation (scouted in session 33).
4. `$C0:881E` and the per-frame calls `$1AAC`, `$21E1`, `$274D` from the main loop.
