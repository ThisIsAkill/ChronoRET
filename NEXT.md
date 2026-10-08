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

1. Bank $C1 after the opcode handlers: all of `$C1:283D`-`$C1:7FFF` is matched (service 4, its
   loaders, the reach check and path search, the thread runner and every opcode handler $00-$DA,
   the last ones being the circle / ellipse moves $C0-$C3 (mover kinds 3 and 5), the
   `!Battler_UnkA4AF` steppers $C4/$C5, `!Battler_UnkA5D8` $D0/$D1, the kind-4 move $D2 and the
   midpoint move $D3 with their starters $D4-$D6, the point-along $D7, the shake $D8 (kind 6) and
   the attribute values $D9/$DA), plus `$C1:007E`, the facing and point calculations
   `BattleAct_CalcFacing` / `BattleAct_RunCalc` with their handlers and tables
   (`$C1:75CC`-`$C1:7A62`), `BattleAct_LoaderTable` and `BattleAct_OpcodeTable`
   (`$C1:7A63`-`$C1:7C2A`), `BattleAct_ProbeBoxOverlap` `$C1:7C2B`, and
   `BankC1_OldBuildLeftovers` (`$C1:7C3D`-`$C1:7FFF`: no code, the cut-off remains of older
   assemblies of those tables and ProbeBoxOverlap, then $FF fill). From `$C1:8000` on (a new
   part of the bank) matched: `BankC1_BattleStartVec` / `BankC1_Entry8003` and the battle's
   main routine `BattleSys_Main` (`$C1:8000`-`$C1:8460`: setup, shuffles, the per-pass turn
   lists, the victory / defeat / `!Battle_Unk99CD` ends and the dead pad-2 debug win), its
   setup `Battle_SetupBattle` + `Battle_CalcUnk56` (`$C1:FA8B`-`$C1:FDBE`), `Battle_RandRange`
   (`$C1:AF22`) and the DP math `Battle_Mul16` / `Battle_Div32` (`$C1:C90B`-`$C1:C95B`, 109 and
   59 callers). Also matched: the turn-list handlers `$C1:8461`-`$C1:8C3D` (`BattleSys_Unk8461`,
   list 12, the battlers' turns, with `BattleSys_Unk883D` / `BattleSys_ClearUnkB192`;
   `BattleSys_ListHandler0`-`11`; `BattleSys_Unk895B`; `BattleSys_Unk8C09`) and the tables
   `BattleSys_ListHandlerTable` / `BattleSys_ListOffsetTable` (`$C1:B92D`-`$C1:B960`). Next, in
   reach order: the enemy script code `BattleSys_UnkAFD2` (`$C1:AFD2`-`$C1:B092`, reads `$CC:8B08`),
   `BattleSys_UnkB488`/`B4AA` and the script-code table `BattleSys_UnkB80DTable` (`$C1:B80D`,
   157 words, handlers from `$C1:8EA7`), `BattleSys_Unk8CF9` (an enemy's action), `BattleSys_UnkB967`
   (a PC's command), the turn-list hit helpers `BattleSys_UnkE89F`/`EBF8`/`EC7F`, the other callees of
   Unk8461 (`$C1:AC46`/`AC57`/`AC5E`, `B575`, `B70E`, `B725`, `B762`, `BCE1`, `BD6F`) and the small
   per-pass / end callees `BattleSys_UnkB093`/`B0B6`/`B223`/`B3BB`/`B3D2`/`B3F9`/`B442`/`B4E9`/`B7F2`/
   `BC60`/`EA9D`/`EAE8`/`F93E`; the setup's `$C1:C96A`/`CA1A`/`CCCB`/`CDFF`/`CE3A`/`CF15`
   and its many bank-$FD callees (`BattleFD_Unk*`, stubs in unmatched_battle.asm); the vectors
   `$C1:0000`-`$C1:0050` (`BattleSys_RunServiceVec`, `BattleSys_ExitVec`) and service 0
   (`$C1:0023`). Open: which status each turn list stands for (lists 0-5, 8-10 look like timed
   statuses; 6, 7 and 11 are empty), who fills `!Battle_ListRuns`/`!Battle_ListReload` and sets a
   list's flags, what `!Battle_UnkAF24`'s script results and the `!Battle_UnkB24A`/`B263`/`B2B6`
   indexing in Unk8461 (by list position, by enemy in Unk8C09) mean; what `!Battle_Unk24`, `!Battle_Unk99CD`,
   `!Battle_Unk2989` bit 5 and `PcStatBlk`'s fields mean; the `$CC:0262` table the
   setup's dead X looks meant for. Stale after this batch (verified headers, fix at their next
   edit): BattleSys_DefeatPose / BattleSys_VictoryPose call their caller "the unmatched code at
   $C1:815F / $C1:8186" (now BattleSys_Main); BankC1_OldBuildLeftovers calls $C1:8000
   unmatched. Verified headers that
   still call now-matched sites "unmatched" (fix them at their next edit): BattleAct_CalcMoveStep
   (`$C1:62F5`/`$C1:6436`, now BattleAct_OpArcToCalc; `$C1:7261`, now BattleAct_OpMoveToMidpoint;
   `$C1:7468`, now BattleAct_OpPointTowardCalc); BattleAct_StartBattlerMove (`$C1:7231`, now
   BattleAct_OpMoveToMidpoint); BattleAct_CalcMidpointSteps (`$C1:7095`/`$C1:715C`, now
   BattleAct_OpMoveKind4ToCalc); BattleAct_FindPath (`$C1:5479`/`$C1:549B`, now
   BattleAct_PathToPoint); BattleAct_OpLoopAnim (`$C1:57A5`/`$C1:57C8`/`$C1:57F2`, now
   BattleAct_OpShowAnimEntry); BattleAct_OpEndThread (`$C1:577A`, now BattleAct_OpEndIfNoTarget);
   the thread banner before BattleAct_RunThreads still calls `BattleAct_OpcodeTable` unmatched.
   Open readers, all out of this bank: the movers in bank $CF (dispatch `$CF:EFC4`, kind table
   `$CF:F01E`: straight `$CF:F040`, arc `$CF:F087`, heading `$CF:F194` with its edge test
   `$CF:FADD`, circle `$CF:F1F8`, kind 4 `$CF:F23D` with its near test `$CF:F957`, ellipse
   `$CF:F354`, shake `$CF:F39F`, curving `$CF:F405`; the objects' movers read the circle arrays at
   `$CF:F6B6`/`$CF:F858`), the position-history recorder `$CF:ED1D`, the path walk stepper
   `$CF:EC78`, the object follower `$CF:ECC2`, the hit-number bounce `$CF:E781` and the sprites'
   use at `$CF:EEA5`, the attribute values at `$CF:EEF8`/`$CF:FE36` (filled at `$CC:E3FC`), the
   colour rotation `$CF:E600`, the object links at `$CF:EDD4`/`$CF:F81D`, and in bank $CC
   `BattleAct_StepPalettes` `$CC:F1E7` and the action helpers `$CC:F06B`-`$CC:F2A9` (object lists
   stepped at `$CC:F278`). Not found: who draws the position history and who reads
   `!Battler_PosHistUnkAB7D/AB88`, `!Battler_UnkA5D8` and the battlers' `!Battle_ActorCircleX/Y`.
   Still open from service 4: the code at `$C1:ACF0` that fills the action block
   `$AE91`-`$AE9B`. Open from the movers: the stepper at `$CF:F978` (`!Enemy_Stepping`), and who
   writes `!Enemy_TargetWanted` (`$5E15`).
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
   Also done: the field/battle hand-off ($C0:0283–$C0:0904): `Scene_Unk0283` (post-battle
   rebuild, with the `FieldBtl_Result` exits), `Field_Unk034B`, `Field_Unk038F` with
   `FieldBtl_SaveTileAttrs`/`SavePartyPos`/`SaveObjs`/`SaveObj`/`SavePpu`, `Field_Unk0617`,
   `FieldBtl_Restore` with `FieldBtl_RestoreObjs`/`RestoreObj`/`RestoreParty`/`RestorePc` (the
   block is the `FieldBtlPc`/`FieldBtlObj`/`FieldBtlPpu` structs at $7E:29B0-$7E:2C7B);
   `Evt_RedirectObjScript` ($C0:5B1F); the draw-bucket links `Obj_DrawUnlink`/`Obj_DrawLink`
   ($C0:A98A–$C0:AA06); `LocLoad_AudioSetup` ($C0:1B53); and the `Field_Unk7EF000` tilemap
   builders `Field_Unk29F7`/`Field_Unk2B78` ($C0:29F7–$C0:2C40). `Scene_Unk0283`, `Field_Unk034B`/`038F`/`0617` and
   `Field_Unk29F7`/`2B78` keep their names because verified code calls them by name; better
   names once those callers are re-reviewed: `Scene_RebuildAfterBattle`, `FieldBtl_Save`,
   `Field_ListBattleObjs`, `Field_BuildPanelMap`/`Field_BuildGridMap` (probably).
   Also done: the whole $C0:A810–$C0:B191 block (object motion and view culling):
   `Vblank_UnkA810` (the per-frame object pass), `Obj_UpdateInView`, `Obj_FlagInView`,
   `Obj_MoveStep` (+ `Obj_MoveStep_Arc`), `Obj_MoveStepFree`, `Obj_CalcScreenPos`,
   `Obj_CalcDirection`, `Obj_SetVelocity`, `Obj_SetVelocityChecked` (+ `_Probe`),
   `Obj_SetVelocityAxis` (no caller found), the map region copy `Field_UnkAF4E` /
   `Map_CopyRegionPlane`, the load-time pass `Field_UnkB0E6` and `Obj_ActivateIfInView`; and
   `SprBuf_FreeObj` ($C0:EA42). `Vblank_UnkA810`, `Field_UnkAF4E` and `Field_UnkB0E6` keep
   their names because verified callers use them; better names once those are re-reviewed:
   `Obj_FrameUpdateAll`, `Map_CopyRegion`, `Obj_DrawAllAtLoad`.
   Also done (branch match-c0-more): the NMI handler `NmiHandler` ($C0:EA63) with `Field_WaitFrame`
   (the frame wait; keeps its name for its verified callers, better `Field_WaitFrame`),
   `Credits_UploadLine`, `Oam_UploadShadow`, `Field_UploadUnk5800` ($C0:6ECB) and the 12 layer
   edge uploads `Map_UploadRowYInc1`-`Map_UploadColXDec3` with `Map_EdgeDmaRow/Col`
   ($C0:8445-$C0:87F0); the tile-slot allocator `Obj_Unk6F9A` / `Obj_Unk7056` (`Obj_TileSlot`,
   was Field_Unk0B88) and the palette-slot allocator `Obj_Unk7170` / `Obj_Unk72B4` /
   `Obj_Unk734C` with its handlers (`Obj_PalSlot`, was Field_Unk0B80; `Obj_PalPrev/Next`,
   `Obj_PalSrc`) ($C0:6F9A-$C0:7083, $C0:7170-$C0:7398; the Unk names stay for their callers:
   better `Obj_TileSlotAlloc/Free`, `Obj_PalSlotAlloc/AllocBtl/Free`); the event helpers
   `Evt_HasActionTarget`, `Evt_FindSolidObjInFront` with the four in-front tests and
   `Evt_FindOrAddUnk0920` ($C0:5B8D-$C0:5CC6); the object script scheduler `Vblank_Unk59D9`,
   `Vblank_ReadScanlineCounters` and `Evt_RunObjScriptSteps` ($C0:59D9-$C0:5AC4; better
   names `Obj_QueueScripts` / `Obj_RunQueuedScripts`); and the event movement / facing opcodes
   $7A, $7B, $92, $9C, $9D, $96, $9A, $97, $A0, $A1, $94, $9E, $98, $95, $8F, $9F, $99, $0F,
   $17, $1B, $1D, $A6, $A7, $1E, $1F, $25, $26, $A8, $A9 with `Obj_SetMoveAnim` /
   `Obj_SetStandAnim` ($C0:4D06-$C0:56A5). Open from these: the opcodes before them
   ($C0:4CD5-$C0:4D05: $90, $91, $7E, $7C, $7D share a tail at $C0:4CD9); the event code at
   $C0:4626 and $C0:4781 that calls the helpers; who writes `Field_Unk31`/`Field_Unk36` (NMI
   upload to VRAM $5800), the `Field_Unk47` bits 1-2 and the other `ObjX_Unk7F0B00` values
   (Obj_Unk30B3 stores 1); the region-copy event opcode $E4 ($C0:3D97); the meaning of
   `Obj_Unk1100` kinds (0-2 fixed palette slots 5-7, 3/4 tile slots, 5/6 palette slots 1-3).
   Quirks recorded: `Obj_PalSlotFixed`'s shared path writes `Obj_PalSlot` + an object offset
   (kinds 0-2), the missing SEC/CLC in `Evt_InFront*` and `Field_UploadUnk5800`, the kind-0
   head insert in `Vblank_Unk59D9`. Stale headers to fix at their next edit (they still call
   now-matched sites "unmatched" or "not traced"): VramDma_Upload (`$C0:6EED`),
   Map_UploadBufTo7400 (`$C0:EAE1`-`$C0:EB5E`), Field_UploadUnk1F00/1D00/1C00/57E0 and
   Pal_UploadCgram (NMI sites), VramQ_Flush (`$C0:EB8C`), Evt_ClearUnk0920 (`$C0:5C90`),
   Obj_CalcDirection / Obj_SetVelocity / Obj_SetVelocityChecked (their callers are the event
   opcodes now), Obj_UpdateInView / Obj_ActivateIfInView / FieldBtl_SaveObj /
   FieldBtl_RestoreObj (the Obj_Unk* callees are matched), and the `Field_Unk0B80/0B88` uses in
   Field_ResetUnk0B80/0B88 (now aliases of `Obj_PalSlot` / `Obj_TileSlot`).
   Also done (branch match-c0-evtops): the event opcode handlers $C0:5F6E-$C0:6D2E (all of
   $00-$7F there): `Evt_UnusedOpcode`, the return / call opcodes $00, $02-$07 (`Obj_Unk1C00`
   read as a level, saved positions in the `ObjX_Unk7F0580` tables, `ObjX_CallWait`), object
   control $08-$0E, jumps and conditions $10-$1C with `Evt_CmpTable8/16` and the 18 compare
   routines, the party / object queries $20-$28, the button tests $2D-$44 and $47, loads /
   stores / copies $48-$5A (`Evt_Op4E_CopyData`'s MVN), arithmetic and bits $5B-$7F; and in
   $C0:2E67-$C0:3710: the animation and wait opcodes $AA-$BD, the party control $AF/$B0
   (stubs `Party_Unk9E29/A26B/A2CE`, the leader's step log and the members' follow, probably),
   `Obj_Unk305D` / `Obj_Unk30B3` (kept names; better `Obj_StepToTileCentre` /
   `Obj_StepOntoObj`), `Evt_StartTargetFunc2` (touch, function 2 at level 2),
   `Evt_PushTarget`, the yields / endless follows $B1/$B2/$B5/$B6 and the message opcodes
   $B8/$BB/$C0-$C4 (`Field_Unk2A`-`2E`, `Field_Unk30`, `Field_Unk62`-`66` read as a message and
   its choice cursor: inferred, `Field_Unk1F87` not traced). Quirks recorded: Evt_Op00_Return's
   unbounded level search and dead LDX, Evt_Op07's unchecked absent member in its wait,
   Evt_Op22/24's unchecked member, Evt_Op6F's count 0 = 256 shifts, the unmasked comparison
   numbers ($12-$16) and bit numbers ($63-$66), Evt_OpAD/Evt_WaitRuns re-running at once when
   the counter is past n, Evt_OpB6's missing CLC, Obj_Unk305D's dead -$10 Y step,
   Evt_PushTarget's 16-bit WRMPYB store, Evt_OpB0's dead Obj_Facing load. Stale after this
   batch (verified headers, grandfathered `UNMATCHED` in the baseline; fix at their next edit):
   Sys_HaltWithColor (its callers note names $C0:5F71 and $C0:3577-$C0:36E4 unmatched),
   Evt_Op94_WalkToObj ($C0:3548, now Evt_OpB5_FollowObj), Evt_Op95_WalkToPc ($C0:3551, now
   Evt_OpB6_FollowPc), Evt_HasActionTarget ($C0:304F, now Evt_OpB0_PartyControl); the
   `ObjX_LeaveView` define now names its writers (the message opcodes, so Obj_UpdateInView's
   test reads as "the object's message is up"). Next, in reach order: the rest of the event opcode handlers,
   $C0:326C-$C0:353E (opcodes $D9 at $C0:326C, $DA at $C0:345A) and $C0:3711-$C0:4CD4 ($33,
   $C7-$FF, $29-$2F, $32, the one-line group $57/$5C/$62/$68/$6A/$6C/$6D at $C0:41E4, $80-$8E,
   then $90/$91/$7C-$7E at $C0:4CD5), then `Evt_OpcodeTable` ($C0:5D6E) once all have names;
   and the party control callees `Party_Unk9E29` ($C0:9E84 first), `Party_UnkA26B`,
   `Party_UnkA2CE` (with `$C0:9ED1`, `$C0:9F20`, `$C0:9F6F`). Open from it: what Field_Unk1F87
   does with the message bytes (and whether `Field_Unk30` is the window's place), who clears
   `Field54_Push`, what lies at Evt_Data + `Evt_PushScriptPos` / `Evt_RedirectPos`, what
   `Eng_Unk7F0000` and `ObjX_Unk7F0A80` mean beyond the opcodes, and what `Obj_Unk1C80`/`1C81`
   bits beyond 0-1 do. Open from the hand-off: who
   writes `FieldBtl_Result` = 2 and what the battle does with `FieldBtlObj.Flags` (0 removes the
   object), what `Eng_Unk0010` holds (Scene_Unk0283's `BIT $0010` quirk), the readers of
   `FieldBtlPpu`, `FieldBtl_AttrA/B` and `Field_Unk47`, and what
   Audio_CmdUnk81 does. Open questions: who reads `LocGfx_Unk7F6000`/`7F7000`, `Map_Unk7F3700`
   (its seed bytes look like scripts), `Field_Unk0B80`/`0B88`, `Map_Unk1D34`,
   `ObjX_Unk7F0C00`-`7F0D80` and `Field_Unk0BE9`; the NMI side that reads
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
   with `C2Script_OpTable` and all its ops $00-$52 ($C2:0F63-$C2:1C83), the motion
   helpers `C2Scene_NegateXVel`/`NegateYVel`, `C2Scene_WrapTaskPos`, `C2Scene_SetAnim`
   ($C2:1C84-$C2:1CF4), the task handlers the spawn ops start: the tile upload
   `C2Scene_TaskUnk1CF5` (op $03), the palette load `C2Scene_TaskUnk1DD4` (op $04) with its
   fade task `C2Scene_TaskPalFade`, the screen fades `C2Scene_TaskUnk20A2`/`2105` (ops
   $28/$29) and the mosaic tasks `C2Scene_TaskUnk2194`/`21F8` (ops $2B/$2A)
   ($C2:1CF5-$C2:2259, without the matched $C2:1DB5), and the sound command queue
   `C2Scene_QueueSoundCmd` ($C2:2ED9-$C2:2F0E). Also matched: the layer scrolls
   `C2Scene_Unk0568`/`C2Scene_Unk066C` with the edge builders `C2Scene_EdgeCol*`/`EdgeRow*` and
   queuers `C2Scene_QueueEdgeCol/Row` ($C2:0568-$C2:09C4); the scene modes
   `C2Scene_Mode2`-`Mode8` with `C2Scene_TurnAround` ($C2:2402-$C2:26A7); the mode scripts
   `C2Scene_ScrFadeOut/FadeIn/MosaicFadeOut/MosaicFadeIn` ($C2:2EC1-$C2:2ED8); the sound
   zones `C2Scene_ZoneSoundAtEntry/AtView`, the task `C2Scene_TaskZoneSound` with its four
   states and `C2Scene_ZoneSoundQueue` ($C2:2F0F-$C2:309D), and `C2Scene_GetSoundZone`
   ($C2:62ED-$C2:631E; the $7E:7200 pack starts with a 4-bit zone map). Stale after that
   batch (verified headers, fix at their next edit): C2Scene_Main ("unmatched mode
   handlers"), C2Scene_ModeTable ("The others are unmatched"), C2Scene_LayerMetatiles/
   LayerMaps/LayerVramMaps ("unmatched code at $C2:0576 ..."), C2Scene_TaskSpawnScript,
   C2Scene_RestoreFlagTail, C2Scene_SaveState, C2Scene_RestoreState, C2Scene_ReloadScene and
   C2Scene_QueueSoundCmd (callers now in the modes / zone code listed as unmatched). Once
   C2Script_ScrollFrames is next edited, `C2Scene_Unk0568`/`066C` can become
   `C2Scene_ScrollLayerX/Y`. The six task handlers and their spawn ops
   (`C2Script_SpawnUnk1CF5` ... `SpawnUnk2194`) keep their `Unk` names so the spawn ops
   (under review) were not touched; once those are reviewed they can take real names
   (TaskUploadTiles, TaskLoadPalette, TaskFadeOut/FadeIn, TaskMosaicShrink/Grow) and their
   headers can drop "not traced". Also stale after this batch: C2Scene_NegateXVel/YVel,
   C2Scene_TaskSpawn* and C2Scene_DrawBgLayer headers still call their now-matched callers in
   $C2:17D2-$C2:1C83 "unmatched" (fix at their next edit). Open: the other sound-queue callers ($C2:4395, $C2:4A4C); who calls
   `C2Scene_ZoneSoundAtEntry` and spawns `C2Scene_TaskZoneSound` (no reference found;
   probably scene data), who fills `C2Scene_ZoneSounds` ($1B9B) and what sound commands
   $10/$81/$82/$83 do; what C2Scene_Unk7F01ED means. Also matched: the scene helpers `C2Scene_Random` and
   `C2Scene_BoxesOverlap` ($C2:2336-$C2:23A7); the two watchers `C2Scene_ObjWatch` (objects
   A/B at $0290-$029F, state C2Scene_Unk027E) and `C2Scene_TrigWatch` (tile triggers in
   ListA/B/C, state C2Scene_Unk0280; sets C2Scene_Unk1B32 and mode 4) with all their states,
   tables, boxes and the script `C2Scene_ScrGoToLoc1D8` ($C2:309E-$C2:3403), and the list
   readers `C2Scene_GetListAUnk02/GetListBScript/GetListCUnk03` ($C2:6263-$C2:6290); the text
   decoder: `TextWin_State0`-`State3` with their exit tables, `TextWin_CodeTable` and all
   control codes $00-$20 (numbers, names, dictionary, `TextWin_ExtTable`), `TextWin_HexByte`,
   `TextWin_HexGlyphs`, the name-length and zero-trim helpers ($C2:58B2-$C2:5DC3). Neither
   watcher has a reference in the bank (probably started from scene data). Stale after that
   batch (verified headers, fix at their next edit): C2Scene_TaskSpawnScript (calls
   $C2:3154, $C2:33B2, $C2:33DF unmatched), C2Scene_ClearUnk1B30 ("use not traced":
   C2Scene_Random's index), TextWin_StateTable ("unmatched") and the banner in
   TextWin_Init's header ("the text decoder ... is not matched"). Open from it: who sets
   C2Scene_TrigFlags (bits 0/1), C2Scene_ObjBusy and the objects' counts (the code at
   $C2:42FC-$C2:5590 reads $0290-$029F heavily), C2Scene_Unk027E state 1, who reads the task
   byte C2Scene_TrigListA/C set (still open); C2Scene_Unk1B47 and why
   C2Scene_GetListCUnk03 reads ListC + 3; who sets TextWin_NumHex. Also matched: the party
   leader's task `C2Scene_LeaderTask` with its states, steps and tables (D-pad walking in
   8-pixel steps that scroll BG1/BG2 through `C2Scene_Unk0568`/`066C` at $C2:3702-$C2:371E,
   the buttons that set scene modes 3/5/6/9, the idle animation, the ListD member script, and
   walking onto an object) and its helpers (trail, walk/stand animations, tile property
   lookups `C2Scene_GetTileProps`/`GetTileProp` over BG2's map and the $7E:7000 pack, step
   target, object count, `C2Scene_SetEntryTile`) ($C2:3404-$C2:3AE1, $C2:6291-$C2:62EC); the
   other members' follow task `C2Scene_MemberTask` with its route planner
   (`C2Scene_MemberRoute`, `C2Scene_PathBlocked`, `C2Scene_ScanRow/ScanCol`) ($C2:3AE2-$C2:42DC);
   `TextWin_DrawGlyph` with `TextWin_Blit2bpp/4bpp`, their shift tables, the tile offset and
   width tables, `TextWin_CharNamePtrs`, `TextWin_StrNadia` and `TextWin_Dec8/16/24` with their
   division loops ($C2:5DC4-$C2:6262); `C2Scene_Unk5775`, `C2Scene_ClearUnk8621` and the data
   before `TextWin_Init` ($C2:5775-$C2:57DE). Neither party task has a reference (scene data,
   as the watchers). The headers this batch made stale (C2Scene_Unk0568/066C, C2Anim_Run,
   C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_SetAnim, C2Scene_TaskRunScript, TextWin_State0
   and its banner) are fixed and need review again. Still stale: TextWin_State1-3's Entry lines
   ("DB as TextWin_DrawGlyph needs (not traced)"; it takes any DB). Open from it: who
   starts the two party tasks and sets `.Slot` (+$24); what the $7E:7000 property nibbles'
   bit 3 and the other bit 2 uses are; `C2Scene_Unk1BF1/1BF3` and `C2Scene_Unk1BF7` readers;
   what $7E:8600-$861C hold (`C2Scene_Unk8600/8604`) and the unreferenced `C2Scene_Unk57B0` and
   `C2Scene_GetMapCell`. Next, in reach order: the object tasks after the members
   ($C2:42DD on, a state table at $C2:42E6; $C2:42FC-$C2:5590 read objects A/B), the code at
   $C2:5700-$C2:5774 (calls `C2Scene_ClearUnk8621`); the mode sub-programs `C2Scene_Unk631F`
   (mode 6, BG mode 7, $C2:631F on) and `C2Scene_Unk6A34` (mode 8); the menu's
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
   Evt_RunObjInit); ends at `$C0:5F6E`, `Evt_UnusedOpcode`. Needs a name per handler first: 81
   entries still have none ($29-$2C, $2E, $2F, $32, $33, $57, $5C, $62, $68, $6A, $6C, $6D,
   $7C-$7E, $80-$84, $87-$8E, $90, $91, $C7-$DA, $DC-$E8, $EA-$EE, $F0-$F4, $F8-$FA, $FE, $FF).
4. Dispatch tables right after (or near) their dispatcher, bank $C0: `$C0:400E` (16 words,
   `$C0:4009`), `$C0:7181` (12, `$C0:717D`), `$C0:9FF7` (65, `$C0:9ECD`).
5. Bank $C1 (`$C1:2D81`, `$C1:3216` and `$C1:3760` are matched as BattlePos_ModeTable,
   Battle_FxHandlerTable and Battle_EnemyMoverTable): `$C1:B80D` (157, `$C1:874E`), `$C1:FA61` (21,
   `$C1:EB45`), `$C1:D126` (6, `$C1:CFE1`), `$C1:DA31` (4, `$C1:D783`).
