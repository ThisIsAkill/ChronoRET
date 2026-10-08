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

1. Bank $C1 from `$C1:6CF3`: the action script's opcode handlers, in address order ($C0 `$C1:6CF3`,
   $C1 `$C1:6F31`, $C2 `$C1:6F53`, $C3 `$C1:6F75`, $C4 `$C1:6F9A`, $C5 `$C1:6FEF`, $D0 `$C1:6FFC`,
   $D1 `$C1:702B`, $D2 `$C1:705A` (calls `BattleAct_CalcMidpointSteps`), $D3 `$C1:720E`, $D4
   `$C1:7349`, $D6 `$C1:7364`, $D5 `$C1:73AD`, $D7 `$C1:740B`, $D8 `$C1:74B4`, $D9 `$C1:753A`, $DA
   `$C1:7579`). Matched so far: `$C1:007E`, `$C1:283D`-`$C1:6CF2` (service 4, its loaders, the reach
   check and path search, the thread runner and opcodes $00-$A9: moves, curving moves, path walks,
   place, follow, subscripts, waits, battler flags, the script variables `!Battle_ActVars`, the hit
   numbers, palettes, object counters, facing, object links, headings, sounds, calc selection, the
   arc moves $98-$9D (mover kind 1), the heading moves $A2/$A8/$A9 (mover kind 2) and the position
   history $A4/$A5), `BattleAct_AdvanceScript` `$C1:75BB` and `BattleAct_ProbeBoxOverlap`
   `$C1:7C2B` (right after the opcode table). Movers to read for the new opcodes, all in bank $CF:
   the arc mover `$CF:F087`, the heading mover `$CF:F194` (and its edge test `$CF:FADD`), the
   position-history recorder `$CF:ED1D` (who draws the history, and the readers of
   `!Battler_PosHistUnkAB7D/AB88`, are not found). The handler table
   `BattleAct_OpcodeTable` (`$C1:7A6B`, 224 words, 115 distinct handlers) is still original bytes:
   match it once its handlers have names (stubs for the rest), together with the 4-word
   `BattleAct_LoaderTable` at `$C1:7A63`. Some verified headers still call now-matched sites
   "unmatched" (BattleAct_CalcMoveStep: `$C1:62F5`/`$C1:6436`, now BattleAct_OpArcToCalc;
   BattleAct_FindPath: `$C1:5479`/`$C1:549B`, now BattleAct_PathToPoint;
   BattleAct_OpLoopAnim: `$C1:57A5`/`$C1:57C8`/`$C1:57F2`, now BattleAct_OpShowAnimEntry;
   BattleAct_OpEndThread: `$C1:577A`, now BattleAct_OpEndIfNoTarget): fix them at their next
   edit. Small open helpers next to the handlers: `BattleAct_CalcFacing` (`$C1:75CC`, table
   `$C1:79A1`, handlers `$C1:75D7` on, result `!Battle_ActFacingOut`). Open readers of what the
   new opcodes set, all in bank $CF: the hit-number bounce `$CF:E781` and the sprites' use at
   `$CF:EEA5`, the colour rotation `$CF:E600`, the object links at `$CF:EDD4`/`$CF:F81D`; and
   `BattleAct_StepPalettes` `$CC:F1E7` in bank $CC. Leads: the movers that step
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
   `Map_StepTileEffects` ($C0:9AA1–$C0:9DC2). Also done: `Map_InitEntryTile` ($C0:9DC3, the
   location-load sibling of the tile effects) and the location map setup: `LocLoad_UnkA33B`
   ($C0:A33B, unpacks `MapProps` and sets the layer sizes `Map_Unk0BCB`–`0BD5`, `Map_Unk0BC9`,
   `Map_Unk0BCA`, the own steps and `Ppu_Unk0BD7`/`0BD8`/`0BDF`) with `Map_InitMasksAndLimits`
   ($C0:7399, the masks `Map_ColMask1`–`RowMask3` and the limits `Map_Unk1D1A`–`1D1D` from
   `LocRom`), `Map_UnpackTilePlanes`, `Map_LoadExitTiles` (`Map_ExitRec0`),
   `LocLoad_EmptyStep`, `Ppu_ApplyMapScreens`, `Map_LoadTreasureTiles` (`Map_TreasureRec0`,
   `Map_TreasureLocRecs`), `Map_TreasureTaken` and `Obj_ResetFrameState` ($C0:A33B–$C0:A80F);
   `LocLoad_DrawMap` ($C0:0A50–$C0:0AFE), `Map_InitOrigin` / `Map_InitOriginX/Y` and
   `Field_Unk74D4/74E8/74F7` ($C0:74A6–$C0:759F), and `Field_Unk87F1` ($C0:87F1).
   Also done: the location-load steps `LocLoad_Unk092B`/`0960`/`09DD`/`0A14` ($C0:092B–$C0:0A4F),
   `LocLoad_UploadPack`, `LocLoad_UnpackPacks67`, `LocLoad_Unk6DCF` ($C0:6D2F–$C0:6E26) and
   `LocLoad_Unk7084` ($C0:7084; `LocRom.Tileset12`/`Tileset3`/`Palette`/`Events` named, with the
   bank-$F6 tables `LocGfx_*` / `LocPal_Rom`); the event data and object init `Scene_PostLoadInit`,
   `LocLoad_Unk56D4`, `Evt_InitObjects` (the object loop that ends in the BRL at $C0:5926),
   `Evt_ClearUnk0920` ($C0:56A6–$C0:595B), `LocLoad_CheckEvtData`, `LocLoad_InitUnk7F3700` and its
   table ($C0:5CC7–$C0:5D6D); and `Scene_ReloadStep` ($C0:286C) with `Scene_ResumeNmi` ($C0:0B28),
   `Field_UploadUnk1F00` (+ table), `Field_UploadUnk1D00`/`1C00`/`0000`/`57E0`,
   `Field_ResetUnk0B88`/`0B80`, `Pal_LoadUnkRow0`, `Pal_UploadCgram` ($C0:6E5C–$C0:6F99,
   $C0:70E9–$C0:716F), `Obj_ResetDrawLists` and `Oam_HideFirst4` ($C0:B204–$C0:B270).
   Stale now (verified headers, fix on their next review): Field_FrameUpdate's header says
   Map_Unk8A6D is unmatched; `Map_ProbeTileAttrsAny` / `Map_ProbeTileLevel` list $C0:9DEA /
   $C0:9DF5 as unmatched (now Map_InitEntryTile); `Sub_C07F9A` lists $C0:74D1 / $C0:74E3 and
   `Map_BuildColXInc1` $C0:87FA as unmatched; `VramDma_Upload` calls $C0:6D61, $C0:6E1E,
   $C0:6E84/6E9C/6EC7/6EED/6F08-6F57 "unmatched"; `ClearRAMDMA` ($C0:5717/58B9/58CA),
   `Sys_HaltWithColor` ($C0:5CDA/5CE8), `Map_InitEntryTile` ($C0:5926) and
   `Obj_ResetFrameState` ($C0:287E/56C2) name now-matched callers as unmatched; LoadLocation's,
   Field_RestoreState's and Field_FadeInAfterReload's Exit lines still hedge on "unmatched"
   steps. Next, in reach order: `Scene_Unk0283` ($C0:0283–$C0:034A, the third caller of the
   location-load steps) and the rest of Scene_ReloadStep's callees: `Field_UnkB0E6` (calls
   $C0:A9CD, $C0:AB45), `Field_Unk29F7` and `Field_Unk2B78` (JSL, RTL); `LocLoad_AudioSetup`
   ($C0:1B53); the NMI handler's upload calls ($C0:EA9E–$C0:EB86, which also call the
   Field_Upload* routines and Pal_UploadCgram); the `Evt_Unk0920` list code at $C0:5C90 and the
   halts at $C0:5CB3; `Vblank_ReadScanlineCounters` ($C0:5A46, walks the `ObjQ_Unk74` list
   through `Obj_Unk1080`). Open questions: who reads `LocGfx_Unk7F6000`/`7F7000`,
   `Field_Unk7EF000`, `Map_Unk7F3700` (its seed bytes look like scripts), `Field_Unk0B80`/`0B88`,
   `Map_Unk1D34`, `ObjX_Unk7F0C00`-`7F0D80` and `Field_Unk0BE9`; the NMI side that reads
   `Map_EdgeVram*` / `Map_EdgeSize*` and the `Map_Built*` bits (then `Sub_C07F9A` can take a real
   name; it is left `Sub_` because Map_Unk93E1 branches to it by that name); the upload callers
   in the NMI at `$C0:EAE1`–`$C0:EB5E`; who sets `Map_ScrollToMode`, `Map_Drift*`/`Map_DriftTimer`.
   Once Field_Unk885A's review can be redone, `Map_Unk91AC` / `Map_Unk93E1` could take real
   names (the layer scroll accumulate / apply), and once their callers' reviews can be redone,
   `LocLoad_UnkA33B` (the map-properties loader), the other `LocLoad_Unk*` steps (graphics,
   metatiles, palette, event data), `Field_Unk74D4/74E8/74F7` (reset layer 1/2/3 scroll),
   `Field_Unk87F1` (right-edge columns) and `Field_UnkBB` (no layer 3) could too;
   `Map_Unk0BCB`–`0BD5` look like the layer widths / heights in metatiles.
3. Bank $C2: matched are the entry vectors ($C2:0000, $C2:8000-$800D), the scene boot, NMI and
   setup steps, the VRAM queue, the task system ($C2:0454-$C2:0567, with the BG layer tables),
   the BG layer redraw `C2Scene_DrawBgLayer` ($C2:09C5-$C2:0B52), the sprite list
   ($C2:0B53-$C2:0E1C), `C2Scene_Main` with its mode table and idle mode ($C2:23A8-$C2:2401),
   the setup steps around it ($C2:232D, $C2:26A8-$C2:274C), the scene loader
   `C2Scene_LoadScene` with its pack loaders, VRAM upload, `C2Scene_ReloadScene` and
   `C2Scene_SaveState`/`RestoreState` ($C2:274D-$C2:2EC0, $C2:7B5A-$C2:7BC3), the text-window
   entries and status dispatch ($C2:57DF-$C2:58B1), the pad reader and play-time clock
   ($C2:84D2-$C2:85D5), and `Menu_InitPpuAndRam` with the new-game data init
   ($C2:940D-$C2:960A), the animation scripts `C2Anim_Run` with their 8 ops and
   `C2Scene_TaskMove` ($C2:0E1D-$C2:0F62), the script interpreter `C2Scene_TaskRunScript`
   with `C2Script_OpTable` and ops $00-$32, $4C, $4D, $51 ($C2:0F63-$C2:17D1), and the motion
   helpers `C2Scene_NegateXVel`/`NegateYVel`, `C2Scene_WrapTaskPos`, `C2Scene_SetAnim`
   ($C2:1C84-$C2:1CF4). Next, in reach order: the rest of the script ops, $C2:17D2-$C2:1C83
   (stubs `C2Script_QueueVram` ... `C2Script_End` in unmatched.asm; the sound ops call
   `$C2:2ED9`, and `C2Script_SetListBit7`/`ClearListBit7` have a 3-word table at `$C2:1A70`);
   the task handlers the ops start (`C2Scene_TaskUnk1CF5`, `C2Scene_TaskUnk1DD4`,
   `$C2:20A2`, `$C2:2105`, `$C2:2194`, `$C2:21F8`) and the layer scrolls `C2Scene_Unk0568` /
   `C2Scene_Unk066C` that `C2Script_ScrollFrames` calls; the scene modes
   `C2Scene_Mode2`-`C2Scene_Mode8` ($C2:2402-$C2:26A7; they call C2Scene_SaveState,
   C2Scene_RestoreState and C2Scene_ReloadScene); `C2Scene_Unk5775` ($C2:5775-$C2:57DE, with
   `$C2:5798` and the data before `TextWin_Init`); the text decoder states
   `TextWin_State0`-`TextWin_State3` ($C2:58B2 on) and the glyph drawer `$C2:5DC4`; the menu's
   own NMI ($C2:8410-$C2:84D1, which also calls `Menu_PollPad` and `Menu_TickPlayTime`) and
   `BankC2_MenuEntry` ($C2:800E); `Menu_Unk8C36`, the command handler behind
   `BankC2_Entry8004`. Open in the loader: what the `Unk` packs ($7E:7000, $7E:7200, $7E:B800,
   $7E:C000, $7E:C600, $7E:C800) and the four lists `C2Scene_ListA`-`D` hold; the code at
   `$C2:0568` (also reads the BG layer tables).

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
