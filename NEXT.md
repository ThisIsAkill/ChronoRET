# Next

The queue, in order. Take the first item and run it to the end (CONTRIBUTING.md,
"Definition of done").

## Matching

0. Quick wins from `tools/find_duplicates.py`. The byte-identical copies (`Battle_Mul8CC`,
   `ScrollWaveFF_A/B`) are matched. Relocation-tolerant (`make duplicates-reloc`: absolute/long operands masked, fragments of
   6+ instructions, at most 3 operands differing, outside matched code), ranked by size; all
   checked by disassembly to be code. "part" = a run inside the source routine, not all of it.
   1. `$CF:FDC8` 78 B: `BattleMsg_FormatNumberDigits` (part, routine 85 B); 3 differ (digit
      table `$CC:F903` -> `$CC:F90D`)
   2. `$C0:2848` 36 B: `Field_FadeInAfterReload` (whole); 1 differs (`JSR Field_EndOfFrameShort`
      -> `JSR Field_EndOfFrame`): the sibling routine right after it
   3. `$C0:58FD` 33 B: `Evt_RunObjInit+$10` (part); 0 differ
   4. `$C2:0073` 32 B: `MainInit+$60` (part, PPU write-twice register clears): matched, inside
      `BankC2_InitHwRegs`
   5. `$C2:9445` 32 B: `MainInit+$60` (part, same): matched, inside `Menu_InitPpuAndRam`
   6. `$CC:F365` 30 B: `Battle_Mul8` (whole, byte-identical); 0 differ
   7. `$C1:6699` 26 B: `Battle_CalcAngle+$1A` (part); 0 differ
   8. `$C0:2DD9` 24 B: `ClearRAMDMA+$15` (part, DMA channel 7 setup tail); 0 differ
   9. `$CF:F9FB` 24 B: `Battle_SinLookup` (part, routine 41 B); 0 differ
   10. `$FD:C0FE` 24 B: `MainInit+$60` (part); 0 differ
   11. `$C1:4A11` 24 B: `BattleTgt_AreaLine+$F` (part); 1 differs (`JSR Battle_CalcAngle` ->
       `JSR $C1:2AE3`)
   12. `$C0:0304` 24 B: `Field_RestoreState+$F` (part); 3 differ (call targets)
   13. `$C0:5A46` 23 B: `Field_ProcessAnimQueue+$C` (part); 0 differ
   14. `$C0:B1B8` 22 B: `Spr_LoadLargeObj+$6C` (part); 0 differ
   More of the same shape (22 B and down) in the full `make duplicates-reloc` output; also
   `$C1:656F`/`$C1:65E4` (`Battle_CalcAngle+$1A`), `$C2:225E` (`Battle_SinLookup+$4`, ends RTL).

1. Bank $C1 from `$C1:5ADB`: the action script's opcode handlers, in address order (opcodes
   $50-$55 share `$C1:5ADB`-`$C1:5CF0`, which sets `!Battle_ActUnkA3D1` at `$C1:5AE0` and clears it
   at `$C1:5CE9`; then $5D `$C1:5CF1`, $5E `$C1:5D12`, $5F `$C1:5D18`, $60 `$C1:5D1D`, $61-$64
   `$C1:5D93`, $65-$68 `$C1:5DC1`, $69 `$C1:5DD3`, ...; $47/$48 are `$C1:623C`). Matched so far:
   `$C1:007E`, `$C1:283D`-`$C1:5ADA` (service 4, its loaders, the reach check and path search, the
   thread runner and opcodes $00-$4F but $47/$48: moves, curving moves, path walks, place, follow,
   subscripts, waits, battler flags and the script variables `!Battle_ActVars`),
   `BattleAct_CalcMoveStep` `$C1:65BA` and `BattleAct_AdvanceScript` `$C1:75BB`. The handler table
   `BattleAct_OpcodeTable` (`$C1:7A6B`, 224 words, 115 distinct handlers) is still original bytes:
   match it once its handlers have names (stubs for the rest), together with the 4-word
   `BattleAct_LoaderTable` at `$C1:7A63`. Some verified headers still call now-matched sites
   "unmatched" (BattleAct_FindPath: `$C1:5479`/`$C1:549B`, now BattleAct_PathToPoint;
   BattleAct_OpLoopAnim: `$C1:57A5`/`$C1:57C8`/`$C1:57F2`, now BattleAct_OpShowAnimEntry;
   BattleAct_OpEndThread: `$C1:577A`, now BattleAct_OpEndIfNoTarget): fix them at their next
   edit. Leads: `BattleAct_Op70Body` (`$C1:5FC3`) is used by opcode $03; the movers that step
   `!Battle_ActorMoving` actors are in bank $CF (`$CF:EFC4`, straight mover `$CF:F040`, kind table
   `$CF:F01E`, curving mover kind 7 `$CF:F405`), the path walk stepper is `$CF:EC78` and the
   object follower `$CF:ECC2`, all out of this bank. Still open from service 4:
   `BattleAct_RunCalc` (`$C1:762E`, table `$C1:79D3`), the bank $CC action helpers
   `$CC:F06B`-`$CC:F2A9` (object lists stepped at `$CC:F278`), and the code at `$C1:ACF0` that
   fills the action block `$AE91`-`$AE9B`. Open from the movers: the stepper at `$CF:F978`
   (`!Enemy_Stepping`), and who writes `!Enemy_TargetWanted` (`$5E15`).
2. Done: the main loop's per-frame calls (`Field_FrameUpdate` $C0:881E–$C0:8901,
   `Field_ActionButton` $C0:1AAC, the event-hook window effects $C0:21E1–$C0:274C,
   `Field_ServiceUnk54` $C0:274D) and the first of their callees: `Field_FindObjInFront` and
   `Field_CheckTileInFront` ($C0:1CFC–$C0:1F23), `Evt_StartTargetFunc1` ($C0:5AC5–$C0:5B1E),
   `Field_DpadHandlerTable` and the D-pad handlers ($C0:8902–$C0:8A6C), `Map_ClearBufC800`
   ($C0:75A0–$C0:75E8), and the step limits `Map_Unk9175`, `Map_Unk99DE` and the
   `Map_LeaderPast*` / `Map_StepStop*` tests ($C0:9175–$C0:91AB, $C0:99DE–$C0:9AA0,
   $C0:5B63–$C0:5B8C). Also done: the layer scroll, `Map_Unk91AC` and `Map_Unk93E1` with
   its 16 steppers and 8 edge dispatchers ($C0:91AC–$C0:9922), and the 16 edge builders
   `Map_BuildRow*`/`Map_BuildCol*` ($C0:8243–$C0:8444); and the whole block before them,
   $C0:75E9–$C0:8242: the redraws `Field_BuildC800Mode1/2/4`, the six row / column writers
   `Map_WriteRow1/2/3`, `Map_WriteCol1/2/3`, the `Map_UploadBuf*` VRAM uploads ($C0:7F58),
   `LocLoad_ClearPage1D00`, `Sub_C07F9A` and its four `Bg_*Span64x32` helpers. Also done: the leader collision `Map_Unk8A6D` ($C0:8A6D–$C0:9174) with its
   probes `Map_ProbeHitsObj` ($C0:9923), `Map_ProbeTileAttrs`/`Map_ProbeTileAttrsAny`,
   `Map_ProbeTileLevel` (+ the `Map_Slope*` tables), `Map_ProbeLevelBlocked` and the commit
   `Map_StepTileEffects` ($C0:9AA1–$C0:9DC2). Field_FrameUpdate's header still says
   Map_Unk8A6D is unmatched and could name it better once its review is redone. Next, in reach
   order: the sibling at `$C0:9DC3` (reached by BRL from `$C0:5926`; it calls
   `Map_ProbeTileAttrsAny` at `$C0:9DEA` and `Map_ProbeTileLevel` at `$C0:9DF5`, probably the
   same tile effects for another object); who reads `Map_Unk1D34` and who sets
   `Map_ExitRec0` ($1D04) and the `Map_TileAttrA/B` / `Map_TileExitIdx` planes ($7E:7000-$70BF);
   the NMI side that reads `Map_EdgeVram*` /
   `Map_EdgeSize*` and the `Map_Built*` bits (then `Sub_C07F9A` can take a real name; it is
   left `Sub_` because Map_Unk93E1 branches to it by that name); the callers of the uploads
   (`$C0:0A80`–`$C0:0AF4`, the NMI at `$C0:EAE1`–`$C0:EB5E`), `Field_Unk74D4/74E8/74F7` and
   `Field_Unk87F1`; who sets the writers' masks `Map_ColMask1`–`Map_RowMask3` ($1D1E–$1D23),
   `Map_Unk0BCF`–`0BD5` and the map tables `Map_Layer*Tiles` / `Map_Meta12*` / `Map_Meta3*`; who sets `Map_ScrollToMode`,
   `Map_OwnStepFlags`, `Map_Drift*`/`Map_DriftTimer` and `Map_Unk0BC9`; and the
   treasure-record setters (`Map_TreasureRec0` $1D06, `Map_TreasureLocRecs` $1D08) and the
   scroll limits `Map_Unk1D1A`-`1D1D`. Once Field_Unk885A's review can be redone,
   `Map_Unk91AC` / `Map_Unk93E1` could take real names (the layer scroll accumulate / apply).
3. Bank $C2: matched are the entry vectors ($C2:0000, $C2:8000-$800D), the scene boot, NMI and
   setup steps, the VRAM queue, the task system ($C2:0454-$C2:0555), the sprite list
   ($C2:0B53-$C2:0E1C), `C2Scene_Main` with its mode table and idle mode ($C2:23A8-$C2:2401),
   the setup steps around it ($C2:232D, $C2:26A8-$C2:274C), the text-window entries and status
   dispatch ($C2:57DF-$C2:58B1), the pad reader and play-time clock ($C2:84D2-$C2:85D5), and
   `Menu_InitPpuAndRam` with the new-game data init ($C2:940D-$C2:960A). Next, in reach order:
   the last setup step `C2Scene_Unk2C1D` ($C2:2C1D-$C2:2C92, calls `$C2:09C5`, the BG scroll
   builder from `C2Scene_BgTileX/Y`, and `$C2:274D`); the script task `C2Scene_TaskRunScript`
   ($C2:0F63, opcode table at `$C2:0F91`) and the sprite-adding caller at `$C2:0ED6`; the scene
   modes `C2Scene_Mode2`-`C2Scene_Mode8` ($C2:2402-$C2:26A7); the text decoder states
   `TextWin_State0`-`TextWin_State3` ($C2:58B2 on) and the glyph drawer `$C2:5DC4`; the menu's
   own NMI ($C2:8410-$C2:84D1, which also calls `Menu_PollPad` and `Menu_TickPlayTime`) and
   `BankC2_MenuEntry` ($C2:800E); `Menu_Unk8C36`, the command handler behind
   `BankC2_Entry8004`.

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
   `$C0:4009`), `$C0:7181` (12, `$C0:717D`), `$C0:6477` (8,
   `$C0:633D`), `$C0:9FF7` (65, `$C0:9ECD`).
5. Bank $C1 (`$C1:2D81`, `$C1:3216` and `$C1:3760` are matched as BattlePos_ModeTable,
   Battle_FxHandlerTable and Battle_EnemyMoverTable): `$C1:B80D` (157, `$C1:874E`), `$C1:FA61` (21,
   `$C1:EB45`), `$C1:D126` (6, `$C1:CFE1`), `$C1:DA31` (4, `$C1:D783`).
