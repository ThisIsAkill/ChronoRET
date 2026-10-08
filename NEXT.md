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

1. Bank $C1 from `$C1:49FF`: `BattleAct_CheckReach` (`$C1:49FF`-`$C1:4A70`, sets `!Battle_ActNear`;
   calls `$C1:4A71`), then onward in address order. (`$C1:007E` and `$C1:283D`-`$C1:49FE` are
   matched; service 4, `BattleSys_RunAction`, and its loaders end at `$C1:49FE`.) Open from
   service 4: the script threads (`BattleAct_RunThreads` at `$C1:4BBE`, per thread `$C1:4C9E`;
   `!Battle_ActScriptDone` is set at `$C1:4D00`), `BattleAct_RunCalc` (`$C1:762E`, table
   `$C1:79D3`), the 4-word `BattleAct_LoaderTable` at `$C1:7A63` (still original bytes), the bank
   $CC action helpers `$CC:F06B`-`$CC:F2A9` (`bankCC.asm` so far holds only `Battle_Mul8CC`), and
   the code at `$C1:ACF0` that fills the action block `$AE91`-`$AE9B`. Open from the movers: the
   stepper at `$CF:F978` (`!Enemy_Stepping`), and who writes `!Enemy_TargetWanted` (`$5E15`).
2. Done: the main loop's per-frame calls (`Field_FrameUpdate` $C0:881E–$C0:8901,
   `Field_ActionButton` $C0:1AAC, the event-hook window effects $C0:21E1–$C0:274C,
   `Field_ServiceUnk54` $C0:274D) and the first of their callees: `Field_FindObjInFront` and
   `Field_CheckTileInFront` ($C0:1CFC–$C0:1F23), `Evt_StartTargetFunc1` ($C0:5AC5–$C0:5B1E),
   `Field_DpadHandlerTable` and the D-pad handlers ($C0:8902–$C0:8A6C), `Map_ClearBufC800`
   ($C0:75A0–$C0:75E8), and the step limits `Map_Unk9175`, `Map_Unk99DE` and the
   `Map_LeaderPast*` / `Map_StepStop*` tests ($C0:9175–$C0:91AB, $C0:99DE–$C0:9AA0,
   $C0:5B63–$C0:5B8C). Also done: the layer scroll, `Map_Unk91AC` and `Map_Unk93E1` with
   its 16 steppers and 8 edge dispatchers ($C0:91AC–$C0:9922), and the 16 edge builders
   `Map_BuildRow*`/`Map_BuildCol*` ($C0:8243–$C0:8444). Next, in reach order:
   `Map_Unk8A6D` ($C0:8A6D–$C0:9174, 1,800 B in one piece; Field_FrameUpdate runs it when
   Field_Unk20 is set; it copies the leader's Obj_PosX/Y into $1D62–$1D68, may zero the
   camera steps Map_Unk1D2E/1D30, and calls `$C0:9923`, `$C0:9AA1`, `$C0:9AD3`, `$C0:9C37`, `$C0:9C5C`, all unmatched; $C0:8A9E–$C0:8AB4
   is reached only by JSR from inside it); `Sub_C07F9A` (419 B, Map_Unk93E1's tail, also
   called by Field_Unk74D4); the six row / column writers `Map_WriteRow1/2/3`,
   `Map_WriteCol1/2/3` ($C0:7612, $C0:77E4, $C0:79CF, $C0:7BA9, $C0:7D66, $C0:7E60; the
   `Field_BuildC800Mode*` redraws call them too); who sets `Map_ScrollToMode`,
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
