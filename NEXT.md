# Next

The queue, in order. Take the first item and run it to the end (CONTRIBUTING.md,
"Definition of done").

## Matching

0. Quick wins from `tools/find_duplicates.py`. The byte-identical copies (`Battle_Mul8CC`,
   `ScrollWaveFF_A/B`) are matched. Relocation-tolerant (`make duplicates-reloc`: absolute/long operands masked, fragments of
   6+ instructions, at most 3 operands differing, outside matched code), ranked by size; all
   checked by disassembly to be code. "part" = a run inside the source routine, not all of it.
   1. `$CF:FDC8` 78 B: `BattleMsg_FormatNumberDigits` (part, routine 85 B): matched, inside
      `BattleMsg_FormatNumber4Digits`
   2. `$C0:2848` 36 B: `Field_FadeInAfterReload` (whole); 1 differs (`JSR Field_EndOfFrameShort`
      -> `JSR Field_EndOfFrame`): the sibling routine right after it
   3. `$C0:58FD` 33 B: `Evt_RunObjInit+$10` (part); 0 differ
   4. `$C2:0073` 32 B: `MainInit+$60` (part, PPU write-twice register clears): matched, inside
      `BankC2_InitHwRegs`
   5. `$C2:9445` 32 B: `MainInit+$60` (part, same): matched, inside `Menu_InitPpuAndRam`
   6. `$CC:F365` 30 B: `Battle_Mul8` (whole, byte-identical); 0 differ
   7. `$C1:6699` 26 B: `Battle_CalcAngle+$1A` (part); 0 differ
   8. `$C0:2DD9` 24 B: `ClearRAMDMA+$15` (part, DMA channel 7 setup tail); 0 differ
   9. `$CF:F9FB` 24 B: `Battle_SinLookup` (part, routine 41 B): matched (`Battle_SinLookupCF`)
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
   `BattleSys_ListHandlerTable` / `BattleSys_ListOffsetTable` (`$C1:B92D`-`$C1:B960`). Also
   matched: the enemy behaviour-script core (`BattleAi_*`): `BattleAi_TestPassed` /
   `BattleAi_EnemyTurn` / `BattleAi_Test00` (`$C1:8C3E`-`$C1:8EAA`), the target and action-block
   helpers `$C1:AC14`-`$C1:AF21` (`BattleAi_ReadTargets`, `ClearTargets`, `SetMainMask`,
   `SetTargetMask`, `TargetsByPcByte`, `PickPcTarget`, `PickMarkedTarget`, `AddPcByByte`,
   `NoteFirstTest`, `FillActBlock`, `SetCmdBits`, `ArgToDp0E`, the unreferenced `BattleAi_UnkAED3`,
   and `BattleSys_UnkAC57`/`AC5E`/`AC85`), `BattleAi_RunMainPart` (`$C1:AFD2`),
   `BattleAi_FindReactPart` / `BattleAi_PickScript` (`$C1:B488`-`$C1:B4E8`), the four handler
   tables `BattleAi_TestTable` / `ChooseTable` / `RunTable` / `TargetTable` (`$C1:B80D`-`$C1:B92C`:
   41 + 23 + 23 + 57 words), and the hit records `Battle_HitEntryOffset` (`$C1:E89F`) and
   `Battle_RecordHit` / `Battle_ClearCancelledHits` / `Battle_ApplyHits` (`$C1:EBF8`-`$C1:ED88`).
   Also matched (this batch): the PC command runner `$C1:B961`-`$C1:C029`
   (`BattleSys_RemoveReadyLong`; `BattleSys_UnkB967`, which runs a committed attack / item / tech
   from the PC's BattleCmd record, reached through `!BattleRom_CmdPtr` `$FD:A849` as the
   `BattleCmdRec` struct; `BattleSys_UnkBC60`, which returns at its first instruction;
   `BattleSys_UnkBCE1` with `_ClearRecords` / `_Done`; `BattleSys_UnkBD6F`;
   `BattleSys_ResetTechUsers`; `BattleSys_UnkBF46`/`BF79`/`BF81`/`BFA4`; `BattleSys_RunPcAttack`),
   the turn helpers `$C1:B4E9`-`$C1:B80C` (`BattleSys_UnkB4E9` item list back to the inventory,
   `BattleSys_UnkB575` command groups, `BattleSys_RefundItem`, `BattleSys_UnkB70E`/`B725` the
   bit-5 battle's fixed commands, `BattleSys_UnkB762`, `BattleSys_UnkB7F2`), the battler checks
   `$C1:B093`-`$C1:B487` (`BattleSys_UnkB093` low HP, `BattleSys_UnkB0B6` turn-list take-part
   bits, `BattleSys_UnkB223` / `BattleSys_UpdateKo` the KO check and one-time revive,
   `BattleSys_UnkB3BB`/`B3D2` FieldBtlObj flags, `BattleSys_UnkB3F9`, `BattleSys_UnkB442`), the
   tech menu builders and MP costs `$C1:C96A`-`$C1:CB47` / `$C1:CB48`-`$C1:CCCA` /
   `$C1:CCCB`-`$C1:CDFE` (`BattleSys_UnkC96A`/`CA1A`/`CCCB`, `BattleSys_TechMpCost1-3`,
   `BattleSys_LoadTechUsers`, `BattleSys_StoreMpCost`/`10`/`18`, `BattleSys_AdjustMpCost`,
   `BattleSys_PayTechMp`) and the setup helpers `$C1:CDFF`-`$C1:CFBD` (`BattleSys_UnkCDFF`,
   `BattleSys_UnkCE36`/`CE3A`, `BattleSys_UnkCF15`, `BattleSys_UnkCF52`, `BattleSys_UnkCF69`).
   Also matched (the action-effect batch): the fixed-fraction scalers `Battle_Scale*`
   (`$C1:C02A`-`$C1:C1DC`), the target resolution `BattleSys_UnkC1DD` with
   `BattleSys_MapEmptyTarget` and `BattleSys_AreaParamTable` (`$C1:C1DD`-`$C1:C90A`, `$C1:C95C`),
   the effect-record loaders `BattleSys_EffRec*` (`$C1:D132`-`$C1:D1D2`) and item-record loaders
   `BattleSys_LoadEffectArg*` (`$C1:D1D3`-`$C1:D220`), the effect types `BattleSys_Effect00`-`08`,
   `EffectNone` and `Effect29`-`2C` with `BattleSys_StoreTargetCmd` (`$C1:D221`-`$C1:D522`), the
   tech part runner `BattleSys_RunTechParts`, `BattleSys_CheckTechMp` and the enemy runners
   `BattleSys_UnkD7C4`/`D8D1` (`$C1:D523`-`$C1:D9D6`), `BattleSys_EffectTable` /
   `BattleSys_TechMpCostTable` (`$C1:D9D7`-`$C1:DA36`), and the helpers `BattleSys_CasterHitOffset`,
   `BattleSys_RecordMiss`, `BattleSys_UnkE976`, `BattleSys_LoadCasterStats`/`LoadTargetStats`
   (`$C1:E8C0`-`$C1:E9D4`), `BattleSys_CopyEffectBytes78` (`$C1:EB0E`) and `Battle_SumHitSets`
   (`$C1:EB68`). Also matched (the effect-arithmetic batch): `$C1:DA37`-`$C1:E89E`
   (`BattleSys_RestoreHpMp`, `CureStatus`, `SetStatus`, `RollHit`, `ApplyDamage`,
   `TestEnemyUnk46`, `AdjustHit`, `AdjustEvade`, `ArmStatusList`, `CalcDamage`, `WakeTarget`,
   `AdjustDefence`, `RollUpTo1A`, `DrainHpMp`), `BattleSys_StealItem` / `RunUnkB2CCHandlers`
   (`$C1:E9D5`-`$C1:EA9C`), `BattleSys_RunUnkB2CCHandler` (`$C1:EB1C`) with
   `BattleSys_HitModTable` (`$C1:FA61`, was `BattleSys_UnkB2CCHandlerTable`), and `$C1:CFBE`-`$C1:D131`
   (`BattleAi_EnemyTurnJsr`, `BankC1_RunService`, the six inventory / gold services and
   `BankC1_ServiceTable`). Also matched (the hit-modifier / experience batch): the 21 hit modifiers
   `BattleSys_HitMod*` (`$C1:ED89`-`$C1:F204`, the B2CC handlers: damage scalers, chance statuses,
   HP cuts, the element-like `.Unk6C` scale, the steal roll), the unreferenced `BattleSys_AddBattleItem`
   (`$C1:EFD3`) and `BattleSys_ReviveHeal` (`$C1:EB49`), `Battle_RandRangeAlt` (`$C1:AF79`, the
   `!Battle_UnkB3E6` stream), the battle-end clears `BattleSys_ClearPcStatuses` / `ClearPcKo`
   (`$C1:EA9D`-`$C1:EB0D`), and the experience and tech points `$C1:F205`-`$C1:FA60`
   (`BattleSys_AwardExpAndTp`, was `UnkF93E`, with `AddExp`, `LevelUpStep`, `ApplyExpStep`,
   `GrowHpMp`, `AwardReserveExp`, `AwardTechPoints`, `BuildComboMasks`, `SpendTechPoints`,
   `TryNextTech`, `LearnSingleTech`, `LearnComboTechs`). Open from it: what the `!BattleRom_UnkCC2A05`
   records stand for (which techs / weapons use which modifier), `BattlerStats.Unk46` bit 7, `.Unk47`,
   `.Unk6C` (element resistances, probably) and `!Battle_UnkB190`'s bits, `!Battle_Unk7F01E0` (who
   sets it; magic, probably), the double counting of tech points in `BattleSys_SpendTechPoints`
   (a quirk as the code reads; worth a check in an emulator), and who reads `!Battle_SavedTargetMasks`.
   Headers edited by it (back to review): BattleSys_Main (the renamed calls), BattleSys_RunUnkB2CCHandler,
   BattleSys_HitModTable (renamed), BattleSys_RollUpTo1A, RandomTableFD and BattleFD_UnkAD17. Also matched (the
   script-handler batch): the test handlers `$C1:8EAB`-`$C1:980F` (`BattleAi_TestHpHalfOrLess` ...
   `BattleAi_TestUnkB158`, BattleAi_TestTable entries $01-$28), the choose handlers
   `$C1:9810`-`$C1:99B7` (`BattleAi_ChooseAnimTarget`, `ChooseTarget`, `ChooseByChance`,
   `ChooseActId`, `ChooseIfGoneEnemy`, the `ChooseClear*` / `ChooseNop*` ones) and the run handlers
   `$C1:99B8`-`$C1:A3F5` (`BattleAi_RunAttack`, `RunTech`, `RunSwapInEnemy`, `RunLeave`, `RunKoSelf`,
   `RunRestoreEnemies`, the stat-byte setters, `RunRestoreAndSetStats`, `BattleAi_AddStatByteAtY`);
   each header keeps its table index. Headers edited by it (back to review): BattleAi_TestPassed
   (`.pick_action` label, names), BattleAi_ReadTargets, ClearTargets, ArgToDp0E, PickMarkedTarget,
   NoteFirstTest, SetCmdBits, FillActBlock, SetTargetMask, RunMainPart (Exit line), the
   TestTable / ChooseTable / RunTable headers, BattleSys_MapEmptyTarget and
   BattleFD_RestoreEnemies. Open from it: what `$CD:0033` shows (`BattleMsg_UnkVecCD0033`, a
   message by `!Battle_UnkB3C7`, probably), `!Battle_UnkB19E`'s 4-byte records (tests $11-$15),
   `!Battle_UnkB320`, `!Battle_UnkB158`, what the action codes 5 / 7 left in `!BattleAi_ActCode`
   by run handlers $07 / $09 do later, and the many quirks recorded in the headers (tests
   $01, $0D, $0E, $14, $18, $1C; run handlers $0D, $12, $15). Also matched (the target-handler batch): the 57 target handlers
   `$C1:A3F6`-`$C1:AC13` (`BattleAi_TargetNone`, `TargetPcs`, `TargetAll`, `TargetSelf`, the random /
   nearest / farthest / lowest- and highest-HP picks, the stat-byte lists `TargetPc*` / `TargetEnemy*`
   / `TargetOtherEnemy*` through BattleAi_AddPcByByte, the fixed `TargetEnemy0-7` / `TargetSlot0-6`);
   the entry block `$C1:0000`-`$C1:007D` (`EngCall_BattleMain` and its vectors, `BattleSys_SceneSetup`
   = service 0, `BattleSys_RunService` with `BattleSys_ServiceTable`, `BankC1_LongDispatch`,
   `BattleSys_Service6`, the JMLs); the bank-$FD callees `$FD:A8A5`-`$FD:A981` (`BattleFD_UnkA8A5`
   the can-act check, `BattleFD_DropPcCommand`, `BattleFD_DropLatchedPcCommand`, `BattleFD_UnkA93C`,
   `BattleFD_UnkA95F`); and the bank's end `$C1:FDD3`-`$C1:FFFF` (`BankC1_OldBuildTail`, old-build
   leftovers, and `BankC1_DebugFlag`). Bank $C1 is now matched in full. Headers edited by it (back to
   review): BattleAi_ReadTargets, TargetsByPcByte, PickPcTarget, AddPcByByte, BattleSys_UpdateKo,
   the TargetTable header, Battle_CacheBattlerCoordsAll, BattleSys_UnkAC57, UnkAC5E,
   RemoveReadyLong, UnkBFA4, UnkB575, UnkB967. Open from it: the quirks recorded in target handlers
   $05 (endless loop with !Battle_Unk2989 bit 5), $08 (PC 0 never compared), $1F (STA for STX),
   $2F (entry numbers, not slots), $38 (one-entry clear); whether !Battle_UnkB252 + 3 and
   !Battle_UnkB18B always name the same enemy; what the bank-$CC/$CD/$CF callees of service 0 and
   the vectors do (stubs `BattleSys_VecCD00xx`; the bank-$CF ones are matched, item 7, and the bank-$CC ones, item 8). Open in the scripts: what the action codes and `!BattleAi_RunMode` values do
   (`!BattleRom_AiActLength` `$FD:BA4A` gives lengths $FF for codes 4/5), what the fixed scripts
   `$CC:8D08`/`$CC:8D1E` stand for (BattleAi_PickScript's BattlerStats bits;
   BattleSys_UnkB0B6 sets `!BattleAi_ChosenBlock` to $FF when Status2 bit 2 changes), and the
   hang in BattleAi_PickPcTarget's marked scan (a quirk, or never reached). Open: which status each turn list stands for (lists 0-5, 8-10 look like timed
   statuses; 6, 7 and 11 are empty), who fills `!Battle_ListRuns`/`!Battle_ListReload` and sets a
   list's flags, what `!Battle_UnkAF24`'s script results and the `!Battle_UnkB24A`/`B263`/`B2B6`
   indexing in Unk8461 (by list position, by enemy in Unk8C09) mean; what `!Battle_Unk24`, `!Battle_Unk99CD`,
   `!Battle_Unk2989` bit 5 (a battle with fixed commands, BattleSys_UnkB725; a demo, probably)
   and `PcStatBlk`'s fields mean; the `$CC:0262` table the setup's dead X looks meant for. From
   this batch: what `!Battle_UnkB18C` indexes for an attack (`!BattleRom_PcAttackNum`), the
   `!Battle_UnkB1FC` bit 1 readers, `!Battle_UnkB3BF`/`B3C8` (set in unmatched code), what
   service 6 does with `!Battle_UnkAEB3` (the defeated enemies' exit, probably), whether
   BattleAct_LoadKind3 is the item loader (B967's item path uses kind 3 with id - $BC; its
   verified header still says unknown), and why BattleSys_ResetTechUsers' first user divides
   by a stale `!Battle_MathB`. Open from the effect-arithmetic batch: what the BattlerStats
   fields the formulas read stand for (.Unk3F, .Unk63-.Unk70, .Unk4C+n; community stat names are
   leads only), the status bits (.Status2 bits 0-2, 7; the timed lists: 0/1/2/8 time .Status2
   bits 7/6/5/4, 3/4 .Unk4C+1 bits 7/6, 5/9 .Unk4C+2 bits 6/5, per BattleSys_ArmStatusList; lists
   6/7 would time .Unk4C bits 7/6 but that code is dead), `!Battle_UnkB1F8` (read by
   CalcDamage kinds 7/8, never written in matched code), `!Battle_UnkB1FC` bits 0 and 6 (who sets
   them), `!Battle_UnkAE51`, effect bytes 7/8 (`!Battle_UnkAE4D`/`AE4E` bits), and what the B2CC
   handlers do (DP $1A for BattleSys_StealItem). Headers edited by this batch (back to review):
   BattleSys_Effect00-03, 05, 06, 29, 2A, 2B, BattleSys_UnkE976, BattleSys_EffRecArgsUnk66 and
   BattleSys_LoadEffectArgs (banners), BattleSys_RunTechParts, BattleSys_UnkD7C4,
   BattleSys_UnkBF46 (Exit lines), Battle_ScaleByte20 (banner), BankC1_Entry8003, BankC1_AddItemLong,
   BattleAi_EnemyTurn (Callers note) and Evt_Op33_SetPalette (the bank $C0 item / gold banner).
   Open from the action-effect batch: what the effect record bytes stand for, `!Battle_UnkB200` (bit 7 after a
   miss stops a tech's parts with the `$7E:B1F5` read, probably meant as BattleRom_TechRec.Flags),
   the bytes read long at `$00:00FA`/`$00:00FB` by target mode 9 (whose roll is compared through
   a restored `!Battle_MathLo`, a quirk), `!Battle_UnkAE6D` (BattleSys_MapEmptyTarget's
   replacement slots), `!Battle_UnkAE4D`'s bits, and the enemy record tables' true base
   (`!BattleRom_UnkCC6FCB` - 2). Headers edited by that batch (back to review): BattleSys_LoadTechUsers
   (Callers note), BattleSys_UnkBF46, BattleSys_UnkBF79, BattleAi_EnemyTurn. Stale from the PC-command batch (verified headers, fix at their
   next edit): Battle_SetupBattle's header calls the `$C1:C96A`-`$C1:CF15` group "not analysed"
   (now matched); Battle_Mul16's example sites `$C1:B329`/`$C1:B455`/`$C1:B4BC` are now in
   BattleSys_UpdateKo / BattleSys_UnkB442 / BattleAi_PickScript. Stale after an earlier batch (verified headers, fix at their next
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
   the thread banner before BattleAct_RunThreads still calls `BattleAct_OpcodeTable` unmatched;
   the "Actions: service 4" banner before BattleSys_RunAction says the script interpreter (the
   threads BattleAct_RunThreads runs) "is not matched yet", though it is.
   The bank-$CF readers of the action state are matched now (item 7: the movers, position
   history, path walk, object follower, hit-number bounce, colour rotation, object links and
   the attribute values), and so are the bank-$CC readers, `BattleAct_StepPalettes` and the
   action helpers `$CC:F06B`-`$CC:F364` (item 8; the attribute values are filled at
   `$CC:E3FC`). Not found: who draws the position history and who reads
   `!Battler_PosHistUnkAB7D/AB88`, `!Battler_UnkA5D8` and the battlers' `!Battle_ActorCircleX/Y`.
   Still open from service 4: the code at `$C1:ACF0` that fills the action block
   `$AE91`-`$AE9B`. Open: who writes `!Enemy_TargetWanted` (`$5E15`).
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
   Field_ResetUnk0B80/0B88 (now aliases of `Obj_PalSlot` / `Obj_TileSlot`); and the comments on
   `!NmiTrampoline` / `!IrqTrampoline` in ram_engine.inc cite the RTI stores at `$C0:2E4B` without
   naming them (inside Sys_HaltWithColor).
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
   test reads as "the object's message is up"). Also done (branch match-c0-evtops2): the event
   opcodes $C0:326C-$C0:353E ($D9 `Evt_OpD9_PartyWalkToTiles`, $DA `Evt_OpDA_PartyGather`: the
   `Map_Unk7F3700` blocks are event scripts, block 0 = `Evt_RedirectPos`, 1-3 the walk-to-tile
   blocks, the fifth `Evt_PushScriptPos`) and $C0:3711-$C0:4866: $33 (palette), the items /
   gold / characters / battle opcodes $C7-$D8 (bank $C1 services 0-5 and the bank $C2
   `Menu_RunCommand` commands 0-8, $0A, $0C, now matched), the
   locations / control / sound / fade / map opcodes $DC-$FA, the credits and layer-3 opcodes
   $29-$2C, $2F, $32 with `Credits_LoadGfx` ($C0:6E27), the window effects $FE and $FF with
   `Evt_OpFFTable` ($C0:400E, 20 words: sub-ops $90-$9F, $A0-$A3 unused), the character opcodes
   $57/$5C/$62/$68/$6A/$6C/$6D and $80, and the sprite opcodes $81-$83 (`Evt_LoadSpriteRec`,
   `Evt_InitWramSprite`, `RomE4_SprRec` / `RomE4_EnemySprRec`). Quirks recorded: the doubled
   ObjX_Unk7F0C00/0D00 stores in $D9/$DA, $D4's move-up with no member 2, the handlers with no
   SEC that end the run ($D0, $D1, $D3, $D5, $F8-$FA), $2C's dead STZ, the ADD of 0 to
   Obj_PalSrc, the 16-bit `Obj_TileSlot` stores of the character opcodes, the unbounded $FF
   sub-op. Verified headers edited (back to review with this batch): Field_UnkAF4E,
   Field_EventHookDispatch, VramDma_Upload, MainInit (bank $FD), Spr_LoadLargeObj,
   Evt_FindOrAddUnk0920 (their "unmatched" caller notes). Stale, not edited (fix at their next
   edit): Field_HookWinC3E ("other code must" clear Field_EventHook: the $FF $92-$95 opcodes
   do). Open from these: what `Field_Unk0BE9`, `ObjX_Unk7F0F00`, `Field54_Unk80`,
   `FadeFlag_Unk10`, `Ppu_Unk0BE0` and the `FieldBtlObj[0-2].GfxOfs` stores of $82 are read
   by; the bank $C2 command $0A; the bank-$FD vectors `FdVec_FFE5/E8/EB/F1` ($FF $80-$8F);
   whether the $2600 records' words +3/+5 are HP (commands 6/7).
   Also done (branch match-c0-evtops3): the last event opcode handlers $C0:4867-$C0:4D05 ($84
   `Evt_Op84_SetUnk1B01`, $87 script period, $88 / $2E palette animations into free
   `FieldAnimB` records with `Evt_FindFreeAnimB` ($C0:4B2C) or straight colour copies into
   `Pal_Buf` / `Pal_CgramBuf`, $89/$8A speed, $8B/$8C place on a tile, $8D position, $8E
   `Obj_OamFlags`, $90/$91/$7E/$7C/$7D `Obj_Unk1A81` with the shared tail `Evt_Op90_Store`) and
   `Evt_OpcodeTable` ($C0:5D6E, 256 words, 32 unused opcodes); the party control callees
   $C0:9E29-$C0:A33A: the leader's step log (`PartyLog_*` rings in bank $7F at
   `Field_UnkAB`/`AC`/`AD`), `Party_LeaderAnim`, `Party_Member2Anim`/`3Anim`,
   `Party_FollowerHoldAnim`, `Party_AnimTable` ($C0:9FF7, 65 words; the 65th unreachable) with
   its 16 facing handlers and the row tails `Party_AnimWalk`/`Run`/`Idle`/`RowUnk19`/`RowUnk1B`,
   and the followers `Party_UnkA26B`/`A2CE` (names kept for Evt_OpB0; better
   `Party_LeaderStep`, `Party_FollowMember2/3`); the message window `Field_Unk1F87` ($C0:1F87,
   better `Field_MessageStep`) with `Field_MsgClearBuf`/`MsgStart`/`MsgStep` (the text window
   status codes 0/3/5-$C/$10 read from what the field does with them); `TileAnimList_*`
   ($C0:28AA-$C0:29F6); `ScrollStepAccum` ($C0:2C41, the `LayerDrift_*` layer 2/3 steps copied to
   `FieldBtlPpu.Scroll2`); the `ReentryVectors` services `Field_RefreshHdmaLong` ($C0:0AFF, was
   the stub `AudioDrvSync`: no sound in it; ReentryVectors edited for the rename, back to
   review), `MusicCueDispatch` / `AudioFadeDispatch` ($C0:1BAB-$C0:1CFB, the battle music cues);
   and the field IRQ `IrqHandler` / `Irq_UploadTileAnim` ($C0:ECCC-$C0:F05D). Quirks recorded:
   Evt_Op87's unmasked countdown, Evt_Op8B/8C/8D/8E's Map_TileAttrA -> Obj_PrioHigh (the other
   way round from Obj_SetVelocityChecked), Evt_Op8C leaving Obj_PosX's low byte, the
   `ObjX_PalAnimRec` left 0 at load (record 0 for an object never given one), Evt_FindFreeAnimB
   searching only 8 of the 12 records, Party_Unk9E29's dead LDA, the dead CMP #$18 before
   Party_AnimRowUnk1B, Party_UnkA2CE's second Obj_VelX/Y zeroing, Field_Unk1F87's LDA #$29 / DEC
   open target, AudioFadeDispatch's PLB/PLD in the wrong order (DB and D scrambled unless the
   caller has D = 0 and DB = 0) and its dead DEC, ScrollStepAccum's zero test on layer 2 X only,
   TileAnimList_ApplyOne writing $E7 to the $E6 column's upper tile where the IRQ draws metatile
   $1E5, IrqHandler's dead RTS. Also done (branch match-c0-tail): bank $C0 is
   now fully matched. `Irq_DrawChoiceCursor` ($C0:F05E, was the stub `Irq_UnkF05E`; the
   IrqHandler banner and Irq_UploadTileAnim edited for it, back to review) draws a 2x2 picture
   (tiles $0FC-$0FF) at choice row `Field_Unk63` (0-3) of the $1C00 tilemap and puts
   Field_Unk2B78's grid entries back in the other rows (`Irq_ChoiceCursorClearRow0-3`,
   $C0:F110-$C0:F16F); 4 or more clears all four rows and sets `Field_Unk63` idle. The data
   after it: `BankC0_OldBuildLeftovers` ($C0:F170-$C0:F2FF: tails of earlier builds of that code,
   no reference found, then $FF fill), `Rom_AngleTable` ($C0:F300), `Rom_DirToFacing`
   ($C0:F700), `Rom_SineTable256` ($C0:F800) and `Rom_SineTable` ($C0:F900-$C0:FCFF), labelled
   with the readers of their defines. Open from it: what tiles $0FC-$0FF show (the hand cursor,
   probably) and which BG layer uses the $1C00 tilemap; the readers of the tables in unmatched
   code ($CE:E85B, $CF:FAA7, $CF:F47F, $CF:F910). Next near here: `FdVec_FFFD` (bank $FD, JMP
   $FD:E022, the IRQ's other phase). Open from this batch: what reads `Audio_Unk1E10`,
   `Field_Unk33`, `LayerDrift_*` writers, the sound commands $11/$14/$70, who sets
   `Field_Unk0F` bit 7 (the IRQ does nothing then), `Field_Unk53Bit7`'s readers (now known:
   FieldHdma_BuildPlainA/B), the FieldAnimB record fields (mostly traced by PalAnim_TickAll; kinds
   4 and 6 open), and whether the $E6 column's upper tile really
   starts at $E4. Stale, not edited (fix at their next edit): Map_InitEntryTile calls
   `ObjX_Unk7F0C00`-`7F0D80` "per-object tables ... not established" (they are the `PartyLog_*`
   rings); the banners before Evt_OpB1_Yield ($C0:353F), Evt_Op7A_ArcToTile ($C0:4D06) and
   Evt_UnusedOpcode ($C0:5F6E) still call `Evt_OpcodeTable` unmatched, and Evt_Op7F's callers
   note describes the table's bytes; the banner before Evt_OpB1 says Field_Unk1F87 is "not
   traced". Open from it: who clears
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
   `C2Scene_GetMapCell`. Also matched (branch match-c2-objects): all of $C2:42DD-$C2:5774:
   object A's task `C2Scene_ObjATask` with its 9 states (rest, wait for the party, rise, fly with
   the D-pad scrolling BG1/BG2, step, land, after mode 8, own script, wait to empty), its helpers
   (`C2Scene_ObjAFaceAnim`, `C2Scene_ObjAJump`, `C2Scene_ObjAOverlap`/`ObjBOverlap`, the boxes,
   `C2Scene_ObjASound`, `C2Scene_ObjAGetProps`), `C2Scene_ObjAMarkTask`, `C2Scene_ObjASpotWatch`
   and its scripts (`C2Scene_ObjAScrGo1DD`, `ScrLeave`, `ScrArrive`, the velocity and dash
   subroutines, `ScrTrail`, the unreferenced `ScrUnk4C6F`, `ScrSpot`) ($C2:42DD-$C2:4CC4); object
   B's task `C2Scene_ObjBTask` (6 states), `C2Scene_ObjBMarkTask`, the two mates
   `C2Scene_ObjBMateTask` / `C2Scene_ObjBMateMarkTask` (party slots 1-2, `C2Scene_FollowTask.Slot`)
   with their aim, glide, clamp, spot and facing helpers ($C2:4CC5-$C2:5627); and the label task
   `C2Scene_LabelTask` (draws string `C2Scene_Unk1B58` of `$C6:F400` with `TextWin_Init/Step` into
   `$7E:8621`, uploads it to VRAM $1E00/$1F00 and shows it as the sprite frame at
   `C2Scene_Unk8604`) ($C2:5628-$C2:5774). None of the task handlers has a reference in the bank
   (probably started from scene data, as the party tasks). Re-review needed (verified headers
   edited because the new code made their notes false): `C2Scene_QueueSoundCmd`,
   `C2Scene_OnTrigTiles`, `C2Scene_Unk5775`, `TextWin_Init`, `TextWin_Step`, `C2Anim_Run`,
   `C2Scene_TaskMove`, `C2Scene_SetAnim` (stale "unmatched"/"doubtful" caller notes). Quirks
   recorded: `C2Scene_ObjAAfterMode8` leaves X = $0C08 for Loc_Id $1F2 (copies $0C1C/$0C20 into
   `C2Scene_ObjAX/Y`); `C2Scene_ObjBMateClampVel` wraps X by 1024 instead of 1536;
   `C2Scene_ObjBMateFollow` reads absolute $0028 for .PrevFacing; `C2Scene_ObjASound` loads the
   same song either way. Stubs added: `C2Scene_Unk2273`/`Unk2277` (probably cos/sin of a
   256-step direction) and `C2Scene_Unk229D` (probably the direction between two points), in the
   unmatched $C2:2273-$C2:232C; `BankC6_UnkE74E` (tile-in-rectangle test) and `BankC6_UnkE797`
   (per-location landing check of object A; both matched since the C6 batch, item 13, names kept). Also matched (branch match-c2-modes2): the map
   view of mode 6, `C2Scene_MapView` with its picture builders (`C2Scene_MapViewBuild`,
   `MapTileColors`, `MapDrawPixels`, `MapCellPixels`, `MapFilterColor`, `MapBuildTilemap`), the
   zoom task `C2Scene_TaskMapZoom` and its states and matrix (`C2Scene_MapZoomMatrix`/
   `MapZoomDivide`), the three marker tasks, the gradient and label set-up and their
   scripts/animations ($C2:631F-$C2:6A33); the dial of mode 8, `C2Scene_Dial` with
   `C2Scene_TaskDial` (pick one of seven locations, `C2Scene_DialLocs`; the result goes to
   `C2Scene_ObjANextLoc`, which object A's `C2Scene_ObjAAfterMode8` reads), the hand rasterizer
   `C2Scene_DialDrawHand` (window 1 by HDMA), `C2Scene_TaskSwirl` (per-line mode-7 matrix by
   HDMA), the marker tasks, the loader `C2Scene_DialLoad` and its helpers and scripts
   ($C2:6A34-$C2:754C); the menu's NMI `Menu_Nmi`, `Menu_Irq`, `Menu_NmiPad` and
   `Menu_RepeatDelays` ($C2:840E-$C2:84D1). That batch renamed `C2Scene_Unk631F`/`Unk6A34` to
   `C2Scene_MapView`/`C2Scene_Dial` and so edited the verified C2Scene_Mode6 and C2Scene_Mode8,
   and fixed now-false caller notes in C2Scene_WaitOneFrame, Trig_Cos1024, TextWin_Init,
   TextWin_Step, Menu_PollPad and Menu_TickPlayTime; merging it with match-c2-objects also
   edited the verified `C2Scene_ObjAAfterMode8` header and the object A banner (the dial now
   proven to set `C2Scene_ObjANextLoc`): all need review again. Open: who sets
   `C2Scene_ObjAFlag5`, `C2Scene_SpotX/Y`, the mates' `.Slot`; who starts the object, mark,
   mate and label tasks; what objects A and B are; what sound commands $86 and $18 (with
   $AC-$AE, $C8) do; `C2Scene_Unk7F00CC/CD`; what the label strings ($C6:F400 table, numbers
   $6A-$6F) and the dial's pack data show; what `C2Scene_MapFilterColor`'s hidden colours are;
   `C2Scene_DialFlagBit2`; `Menu_Unk83` and `Menu_NmiTimer`. Open in the loader: what the `Unk` packs ($7E:7000, $7E:7200, $7E:B800,
   $7E:C000, $7E:C600, $7E:C800) and the four lists `C2Scene_ListA`-`D` hold; the code at
   `$C2:0568` (also reads the BG layer tables).
   Also matched (branch match-c2-after-dial): the direction helpers `C2Scene_Unk2273`/`Unk2277`
   (cos / sin of a 256-step direction, x128) and `C2Scene_Unk229D` (direction between two points
   on the wrapping map, with its dead tail $C2:232A) ($C2:2273-$C2:232C; better names
   `C2Scene_Cos256`/`Sin256`/`DirToPoint` once `C2Scene_ObjBMateAim` is next edited); the scene
   screen effects and script routines $C2:754D-$C2:7DE3 (called by script op $34 or started by op
   $35 from the bank $C3 scene scripts: placement and velocity helpers, the BG3 drift / slide /
   wave tasks, the window tables through `BankC3_Entry0008`, the ROM-noise and BG2 line waves on
   HDMA, party save / restore, flag setters, `C2Scene_BuildPatternTiles`) and the $FF fill to
   $C2:8000 (`BankC2_FreeSpace7DE4`); the menu's entry and thread scheduler $C2:800E-$C2:840D
   (`BankC2_MenuEntry`, `Menu_InitSystems`, `Menu_BuildPartyLists`, `Menu_RunThreads` with
   `Menu_ThreadEnd`/`Yield`/`YieldFrames`, `Menu_StartThread`, `Menu_KillThreads`,
   `Menu_MainThread` and `Menu_ModeLists`, `Menu_Exit`, `Menu_ExitToGame`, the VRAM queue adders,
   `Menu_Fade`, `Menu_InterruptVectors`); `Menu_FlushVramQueue`, `Menu_UploadPalette`,
   `Menu_BuildGradient`, the inventory (`Menu_AddItem`/`RemoveItem`/`FindItem`), the character
   record loaders, `Menu_ItemCategory`, `Menu_ItemDataPtrA/B`, `Menu_CountEquippedBy`,
   `Menu_ListEquipItems` ($C2:8663-$C2:89E3); the cursor threads and list arrows
   ($C2:89E4-$C2:8C35) and `Menu_CursorRecOffset` ($C2:EA27). Quirks recorded: the missing CLCs in
   `C2Scene_PlaceBelowView` (no effect), `Menu_RunThreads` (no effect: the carry is always clear, S = $0A3F + 64 x slot) and
   `Menu_ListArrowsThread`; `C2Scene_TaskBg3LineWave`'s stale X (its phase lives at $01E2);
   `C2Scene_NoiseInit`'s MVN one byte long; `Menu_CursorStepD` calling `Menu_CursorPosAB` with
   M=0; dead code at $C2:232A and $C2:8A96. Re-review needed (verified headers edited):
   `C2Scene_Random`, `Trig_Cos1024`, `BankC2_Entry8000`, `Menu_InitPpuAndRam`,
   `Menu_InitNewGameData`; merging match-c2-modes2 also edited the verified `Menu_Nmi` and
   `Menu_Irq` headers and their banner (the vector JMLs and `BankC2_MenuEntry` are matched now) and
   the `Trig_Cos1024` / `C2Scene_Random` caller notes, and took main's names for shared RAM
   (`Menu_FrameReady`, `Menu_InidispShadow`, `Menu_NmiFrames`, `C2Scene_HandBufA/B`,
   `C2Scene_SwirlCosA/B`, `C2Scene_HdmaHalfBytes/BufBytes`). Stubs added: the `Menu_Init*` callees `Menu_Unk968D`/`D156`/`984A`/`92F4`/`F3CA`/`9875`,
   `Menu_UnkE91B` (thread 3), `Menu_UnkF5ED`, `Menu_Unk93A8`, `BankFF_UnkF958` and the mode lists
   `Menu_Mode00List`-`0FList`. Open: who fills `Menu_GradSpec` and `Menu_CursorPos`; what
   `Menu_Unk82E1`'s values $AE-$B2 are; what the `C2Scene_PatternTiles` are for.
   Also matched (branch match-c2-menu-cmds): the menu NMI's upload `Menu_NmiUpload` ($C2:85D6,
   falls into `Menu_FlushVramQueue`); the `BankC2_Entry8004` dispatcher `Menu_RunCommand` with
   `Menu_CommandTable` and its 12 handlers (party order, record refills, `Menu_CmdEquip`, the boot
   save-slot check `Menu_CmdBootCheckSaves`, item count; $C2:8C36-$C2:8E2C); every
   `Menu_InitSystems` callee: `Menu_LoadGraphics` with the tile helpers ($C2:960B-$C2:9849),
   the window style tiles/palette (`Menu_LoadWindowGfx` $C2:C511, `Menu_LoadWindowPal`
   $C2:ED08), the VRAM lists at $C2:FC6F, `Menu_ClearOam`, `Menu_BuildItemTables` with
   `Menu_CleanInventory`/`Menu_RefreshAllChars` ($C2:984A-$C2:99C9), the save slot summaries
   `Menu_LoadSlotSummaries` ($C2:D156-$C2:D32B) with `Menu_DrawText` ($C2:F90C),
   `Menu_UnpackConfig`/`Menu_PackConfig`, `Menu_CanEquip`, `Menu_PageScroll`
   ($C2:92F4-$C2:940C), the character stats `Menu_CharRecalc` and its formulas
   ($C2:9137-$C2:92F3), the sprite objects `Menu_InitSprites` ... `Menu_SprUploadTiles` with
   `Menu_WeaponRecSrc` ($C2:F3CA-$C2:F870); thread 3 `Menu_MainCursorThread` ($C2:E91B-$C2:E97B);
   mode 0, the main menu (`Menu_Mode00List`, `Menu_MainMenuInit`/`Loop`,
   `Menu_ReturnToMainMenu`, $C2:99CA-$C2:9C28), and the handler lists of modes 1-7, $0B-$0F
   (handlers stubbed as `Menu_ModeNNHk`). Found: `Menu_Unk29AF` is a joined-character bit set,
   `Menu_ItemEquipChars` the per-item equip mask, `Menu_ItemSortKeys` weapon power / armour
   values, `Menu_Unk2C53` probably the gold; `Menu_InitSystems` returns with M=1 (so
   `BankC2_MenuEntry` stores only Menu_EntryX's low byte). Quirks recorded: `Menu_RunCommand`'s
   LDA #$00/XBA decoding as LDA #$EB00 after the M=0 handlers; `Menu_LoadWindowGfx` copies $281
   bytes; the dead byte in `Menu_ReadSlotSummary`; the dead INC in `Menu_SprAnimEnd`;
   `Menu_SprAnimate`'s frame data running past the page for .TileCount 6.
   Also matched (branch match-c2-menu-modes): the pad and cursor code $C2:E97C-$C2:ED07
   (`Menu_PadInput`, was `Menu_UnkE984`, with `Menu_CursorMove` and the per-direction neighbour
   steps, now `Menu_CursorPos.Up/Down/Left/Right`; `Menu_ListCursorEdge`, `Menu_ListPageSetup`; the
   sound senders `Menu_PlaySound`/`PlaySound0` (was `Menu_UnkEAC2`)/`PlaySound1`/`SendSound`, at most one
   command per 3 frames through `Menu_NmiTimer`; the list smooth scroll `Menu_ListScrollInit`/`Step`;
   `Menu_DrawPortrait`, the attribute helpers, `Menu_LoadSlotWindowStyle`); the draw lists and text
   $C2:ED31-$C2:F3C9 (`Menu_RunDrawList`, was `Menu_UnkED31`, with its 11 commands; window frame and
   inside, block copy/swap; `Menu_DrawString` with control codes $01-$0C; decimal (BCD) and hex
   numbers; `Menu_DrawClock`, was `Menu_UnkF28D`; `Menu_DrawItemName`, `Menu_DrawDescText`);
   `Menu_SprPlaceOam` ($C2:F871, was `Menu_UnkF871`); and mode 1, the equipment screen (slot names
   "Weapon/Helmet/Armor/Accessory" at $C2:A3BA), $C2:9C31-$C2:A4AE: `Menu_Mode01H0`-`H3`,
   `Menu_Icon0Preview`/`Redraw` (were `Menu_UnkA051`/`A101`), the member list and its row scroll,
   the slot list and the item list set-up. Found: $0D83 (`Menu_NmiDp`+`Menu_Unk83`) forces the cancel
   bit; dp $C1/$C9 bumps are thread 2/3 `.Wait`; `Menu_ItemNamePtrs` holds bank-$CC addresses of
   11-byte strings; `Menu_Unk51` is used as a zero start index (`Menu_BinToBcd`,
   `Menu_DimPalette`). Quirks recorded: `Menu_CursorMove` loses the record offset's high byte
   (records 43 on); `Menu_ListScrollStep`'s SBC of entry 0 instead of ,X; `Menu_CopyDrawArgsUnused`
   and `Menu_DeadF362` unreached; `Menu_FillWindowInside` not testing a height of 0;
   `Menu_TextCopyTile`'s uncounted 0; `Menu_EquipClearCharFlag` indexing by the cursor row alone;
   `Menu_EquipItemsOpen` reading `Menu_EquipList[$25]`; `Menu_SprPlaceOam` placing more than 4
   sprites into the next objects' entries; the second REP #$20 in `Menu_DrawClock`. Re-review
   needed (verified headers edited): `Menu_MainMenuLoop`, `Menu_ReturnToMainMenu`,
   `Menu_MainMenuIcons`, `Menu_MainPreviewTable`, `Menu_MainRedrawTable`, `Menu_Mode01List`,
   `Menu_SprThread`, `Menu_SprResetChars`. Open: what the draw lists in bank $FF draw, the
   mode 1 HDMA tables ($7E:9300) and HDMAEN values, who writes `Menu_Unk85` and `Menu_CursorHold`,
   what `Menu_DrawDescText`'s strings at $CC:2EB1 are; the 7 bytes $C2:F905 (an entry into
   `Menu_DrawText` with A=$81).
   Also matched (branch match-c2-menu-tail): the mode 1 helpers $C2:A4AF-$C2:AA33 (the slot and
   item window slides with their HDMA band tables `Menu_EquipSlotsSlideIn/Out`,
   `Menu_EquipItemsSlideIn/Out` and steps, `Menu_PutHdmaEntry`, `Menu_MemberListHdma`; the item
   list `Menu_DrawEquipList`/`Menu_DrawEquipItem`; `Menu_EquipPreviewItem` with
   `Menu_EquipCompareStats`/`Menu_EquipCompareOfs`; `Menu_EquipItemsClose`; `Menu_DrawEquipNames`);
   mode 2, the item screen, $C2:AA40-$C2:B352 (handlers `Menu_Mode02H0`-`H5`, `Menu_Icon1Preview`/
   `Redraw`, `Menu_Mode02Init`, the list cursor and scroll, `Menu_SortInventory` with its group
   tables, the equipment info, the item use `Menu_UseItem` with `Menu_UseKindTable`, the heal, full,
   random ($C9) and stat ($CD/$CE ...) items, `Menu_AfterItemUse`); and the item use's effect
   $C2:8E2D-$C2:9136 (`Menu_ApplyHeal`, `Menu_HealHp/Mp`, `Menu_CalcHealAmounts`, the rising
   numbers `Menu_ShowHealNumbers` / `Menu_HealNumbersThread` / `Menu_HealBounce` /
   `Menu_HealNumberSprites`, `Menu_StashInventory`/`Menu_UnstashInventory`). With them
   $C2:0000-$C2:B35C is all from source. Renamed stubs: `Menu_UnkA4AF/A569/A59A/A5C3/A64D/A6F0/
   A71E/A85C/AD50/ADC3/90FC/9121`; sub-entry `Menu_CalcUnk0D38` ($C2:813C) added in
   `Menu_InitSystems`. Quirks recorded: `Menu_EquipSlotsSlideOut`'s 16-bit DEC of
   `Menu_ArrowsOff`, `Menu_EquipSlotsBackStep`'s unused bands, `Menu_ItemListCursor` leaving
   `Menu_CursorYOfs` $FF00 when the scroll frames are skipped going up, `Menu_UseLeave`'s never-taken
   BVC, `Menu_UseKindTable` entries pointing at an RTS, `Menu_StatCountOfs` read from - 1 (entry 0
   is the RTS before), `Menu_CalcHealAmounts`' unreachable negation and RandomTable read past its
   end, the dead INY in `Menu_SortInventory`, the unread last bytes of `Menu_EquipCompareOfs`,
   `Menu_SortGroupCount` and `Menu_RandomItemOdds`. Re-review needed (verified headers or sources
   edited): `Menu_InitSystems`, `Menu_MainPreviewTable`, `Menu_MainRedrawTable`, `Menu_Mode02List`,
   `Menu_Mode01H1`, `H2`, `H3`, `Menu_EquipItemIdle`, `Menu_Icon0Redraw`, `Menu_Mode01Init`,
   `Menu_DrawMemberStatus`, `Menu_EquipSlotsClose`, `Menu_EquipItemsOpen`, `Menu_EquipListSetup`.
   Stubs added: `Menu_UnkB83E` (the HP / MP item's member cursor, in mode 3's range),
   `Menu_VramRecBg3Rows62` ($C2:FC37), `Menu_VramRecDigits` ($C2:FC5A). Open: which register the
   slide HDMA tables feed; what `Menu_ItemInfo0` bit 3, the `$FF:B310` strings, record bytes
   $2F-$34 (`.StatCounts`) and `Menu_Unk0D7E` mean.
   Also matched (branch match-c2-modes34): mode 3, the tech screen, $C2:B35D-$BF34 (handlers
   `Menu_Mode03H0`-`H4`, `Menu_Mode03Init`, `Menu_Icon2Preview`/`Redraw` (were `Menu_UnkB8DA`/
   `B960`); the member window with its scroll `Menu_TechMemberScroll`/`ScrollAnim` and page
   (`Menu_TechPage`, Left / Right: tech bytes 0-6, 7-21, 22-36 of `Menu_TechShown` by
   `Menu_TechPages`, probably single / double / triple); the list `Menu_TechBuildList`
   (`Menu_TechListBytes`, `Menu_TechListIds`, `Menu_TechFirstIds`), its rows, scroll and names
   (`$CC:15C4`, 11 bytes); the MP cost `Menu_TechMpCost` (`$CC:253B`, combos through the bytes
   `BankFF_UnkF813` builds at `Menu_TechMenuArea`) with `Menu_TechCostCut` (accessories $A2 halve,
   $A3 quarter it); the combo partners `Menu_TechPartners`; the description through
   `Menu_TechDescText`; the use of a tech with `Menu_TechInfo` (= `Menu_ItemInfo0` by tech id) bit 7
   as the items' HP / MP restore (`$CC:2140` 12-byte records, `$CC:1ACB` target bit, the caster's
   `.Derived+3` as the amount, the caster's copy object 7 animating), and `Menu_UseTargetCursor` /
   `Menu_UseTargetCheck` (was the stub `Menu_UnkB83E`, shared with the items)); mode 4, the
   settings screen, $C2:BF3D-$C510 (handlers `Menu_Mode04H0`-`H3`, `Menu_Mode04Init`,
   `Menu_Icon3Preview`/`Redraw` (were `Menu_UnkC2FF`/`C397`), `Menu_CfgEntryRun` with
   `Menu_CfgEntryTable` and its 12 entry routines over `Menu_CfgA3`-`Menu_CfgBMid`, the button map
   editor `Menu_CfgMapCursor`/`Assign`/`Set`/`Swap`/`FixPages` with its clash lists, the marks,
   selectors and entry icon); and $C2:F943-$FC6E: the text threads (`Menu_CfgEntryText` with
   `Menu_CfgTextThread`/`Menu_CfgValueThread`, `Menu_StartDescText` (was `Menu_UnkFA49`) with
   `Menu_DescTextThread`, the step loop `Menu_TextStepLoop` and `Menu_TextUpload`), the tile word
   writers `Menu_PutTextTiles`/`Menu_PutTextTilesAttr` and all 23 VRAM records there (the stubs
   `Menu_VramRecClock` ... `Menu_VramRecDigits` are real labels now). Found: slot 2 is the text
   thread (`Menu_TextSlotBit`); `$0D18` in mode 3 is `Menu_RepeatFast`; `Menu_Unk0DC9`/`0DCC`/
   `0DD0` are the text steps per frame, the text rows' VRAM address and size; `Menu_CfgButtonMap`
   (`Menu_Unk0408`) is the map `Menu_CfgA4` selects. Quirks recorded: `Menu_TechDrawMembers` draws
   the empty rows as many times as the rows drawn (not 3 minus them); `Menu_TechTargetRows` reads
   `Menu_Unk0D38` by member row, not character; `Menu_TechMpCost` stores a word on pages 1-2;
   `Menu_TechFirstIds`' last end is `Menu_TechPages`' first byte; `Menu_CfgMapClashPtrs` has 7
   pointers for 8 lists, so an index of 7 reads `$C2:0107` (`Menu_CfgMapClash7` unreferenced);
   `Menu_CfgToggleInvert`'s 11th byte is only a word's high byte; `Menu_VramRecTechLow`'s last byte
   is an opcode. Re-review needed (verified headers or sources edited): `Menu_MainPreviewTable`,
   `Menu_MainRedrawTable` (the icon 2/3 names), `Menu_UseItem`, `Menu_UseHealItem` with
   `Menu_UseTargets` (the `Menu_UseTargetCursor` name), `Menu_DrawDescText` (the
   `Menu_StartDescText` name; its Entry DP is $0000, needed by `Menu_StartThread`) and
   `BankFF_CharBits` (two readers now matched). Stubs added: `Menu_UnkC54F` (its first byte is
   `Menu_WindowVramRec`'s last: the map applied to `Menu_ButtonMap` and drawn), `Menu_UnkC57A`,
   `Menu_UnkC5C7`. Open: what the settings bytes do in the game, sound command $F3
   (`Menu_SoundCmdF3`, also sent by the load screen; probably stereo / mono), `Menu_CfgEntryByte`
   entry 5 ($0D91), `Menu_TechUnk0F4E/0F51/0F73`, the draw lists of modes 3 and 4, `MenuRom_TechData`'s other bytes, the unreferenced VRAM records' users.
   Also matched (branch match-c2-modes0b): menu modes $0B-$0E, $C2:D4F0-$C2:E913. Mode $0B
   (`Menu_Mode0BH0`/`H1`; handlers 2-3 are mode 6's) is mode 6's save screen with a cancel that
   leaves the menu, probably a save point's. Mode $0C is the shop ($C2:D52B-$C2:E1E2:
   `Menu_Mode0CH0`-`H8`, `Menu_ShopInit`, the buy / sell lists
   `Menu_ShopBuyOpen`/`SellOpen`/`BuyMove`/`SellMove`/`SellBuild`/`*DrawRow(s)`/`ShiftMap`, the
   count window `Menu_ShopQtyOpen`/`QtyStep`/`QtyRight` (with `QtyLeft`/`Up`/`Down`)/`QtyClose`, the
   member info `Menu_ShopMemberInfo`/`MemberNums`/`NumPair`, and a built-in equip view
   `Menu_ShopEquipOpen`/`EquipNext`/`SlotRows`/`TryItem`/`Compare`). Mode $0D is the name entry
   ($C2:E1ED-$C2:E60A: `Menu_Mode0DH0`-`H4`, `Menu_NameInit`, the grid steps, `Menu_NameFinish` with
   `Menu_NameTrim`/`NameTaken`, and the choice before the first name,
   `Menu_NameChoiceInit`/`ChoiceText`). Mode $0E is the title's load screen ($C2:E613-$C2:E913:
   `Menu_Mode0EH0`-`H3`, `Menu_LoadInit`, `Menu_LoadCursor`, `Menu_LoadAskSlot`, the erase question
   `Menu_LoadEraseOpen`/`EraseSlot`). Found: the `Menu_ItemInfo1` word is probably the price (sell
   price half of it rounded up; buy price x `Menu_PriceFactor` / 256 rounded up, 1-65000);
   `Menu_Unk2C53` is the gold (the 9,999,999 cap at $C2:FDDF); `Menu_ItemInfo0` bit 2 keeps an item
   off the sell list; `Menu_EquipChars`/`Menu_EquipFlags` are the shop's member list; $0D0B is
   BG2VOFS' high byte (`Menu_ScrollShadow`+7); `Menu_Unk0D4C` is row 3's validity on the load
   screen; `Menu_NamedOnce` (Menu_Config+$0F) is zero only before the first name entry, whose first
   choice sets or clears Menu_Config bit 6 (probably the battle mode); pad 2 holding Select and
   Start on the load screen erases a slot; `Menu_SramUnk7FE2` enables a second choice on the load
   screen's row 3 that loads part of a slot before a new game (probably New Game+). Quirks recorded:
   `Menu_LoadEraseOpen`'s never-taken BCS; `Menu_ShopMemberSprites`' always-taken BCC and 16-bit
   read of `Menu_CurMember` with $0072; `Menu_NameFinish` leaving the old name's first byte 0 when a
   name is refused; `Menu_ShopShiftMap` reading the step's sign as bit 15 of the word at
   `Menu_ScrollStep`-1; `Menu_ShopSellDrawRow`'s word store of `Menu_ItemId` (zeroes `Menu_Unk04CA`)
   and its cut 16-bit ADC; `Menu_ShopQtyLeft`'s limit test that cannot fail; `Menu_ShopMemberInfo`'s
   word store to `Menu_EquipSlotIdx`; `Menu_ShopQtyClose` setting `Menu_ShopLast` from the A an MVN
   leaves; `Menu_NameInit`'s second `Menu_DrawString` from past the end of the grid text;
   `Menu_ShopInit` filling 11 words of `Menu_Unk5D42` (icon 0 fills 12). Re-review needed (verified
   headers edited, "not analysed" now false): `Menu_Mode0BList`, `Menu_Mode0CList`,
   `Menu_Mode0DList`, `Menu_Mode0EList`. Stubs added: `Menu_Mode06H1Confirm` ($CF0A),
   `Menu_UnkCFA2`, `Menu_UnkCFFB`, `Menu_UnkD0E5`, `Menu_DrawSlotWindows` ($D10D), `Menu_UnkD32C`,
   `Menu_UnkD36C` (in the remaining $D32C-$D4EF), the shop's
   `Menu_ShopBuyQtyInit`/`SellQtyInit`/`GainGold`/`PayGold` and `Menu_UnkFD58`/`FD68` ($FCB2-$FE09).
   The tile strip writers and nine VRAM records this branch had as stubs are matched by
   match-c2-modes34, and the merge points the calls at those labels: `Menu_DrawTileStrip`/`Attr` are
   `Menu_PutTextTiles`/`Attr`;
   `Menu_VramRecBg1Map`/`Bg1Row16`/`Bg1Row24`/`Bg2Row2`/`Bg3Row3`/`Labels`/`Tiles1800`/`RomEB88` are
   `Menu_VramRecBg1Big`/`Bg1Rows16`/`Bg1Rows24`/`Bg2Rows2`/`Bg3Rows3`/`UnkFC53`/`UnkFC61`/`RomTiles`
   (`Menu_VramRecBg3Full` kept its name); `Menu_VramRecBg3Rows0` is `Menu_VramRecBg3Rows62` and
   `Menu_UnkFA49` is `Menu_StartDescText`; the defines
   `Menu_NameTextBuf`/`NameTextBytes`/`NameTextVram`/`LoadSoundCmd` are
   `Menu_TextGfxA`/`TextGfxBytes`/`TextTileDestA`/`SoundCmdF3`. Re-review needed after the merge
   (verified headers edited, their loaders now named): `Menu_VramRecUnkFC53`, `Menu_VramRecUnkFC61`.
   Open: what cursor C on record `Menu_ShopRecCursorC` marks; who sets `Menu_PriceFactor`;
   readers of `Menu_NameUnk0F0A`/`0F0B`; the shop's and name screen's draw lists and HDMA bits.
   Also matched (branch match-c2-modes57): the rest of bank $C2, which is now all from source.
   Mode 4's button map rows $C2:C54F-$C620 (`Menu_UnkC54F` applies the map: `MenuRom_DefaultButtonMap`,
   or `Menu_CfgButtonMap` with `Menu_CfgA4`; `Menu_UnkC57A` draws the six rows' letters through
   `Menu_ButtonLetter` (font letters A X L R B Y S at `MenuRom_ButtonLetters`, $FF:D554) and
   `Menu_CfgMapRowOfs`; `Menu_UnkC5C7` marks the rows the edit changes); `Menu_WindowVramRec` is 7
   bytes now (its old 8th byte is `Menu_UnkC54F`'s JSR opcode). Modes 5 and 7, the party order
   ($C2:C621-$CED3: `Menu_Mode05H0`-`H2`, `Menu_Mode07H0`/`H1`, the picks `Menu_XchgFirstFree`/
   `PickFirst`/`ClearPicks`/`Swap`/`BlockPos`, the cursor `Menu_XchgCursor`/`Edge`/`Skip`, the reserve
   list scroll `Menu_XchgScroll`/`ShiftSprites`, the rows `Menu_XchgBuildRows`/`PlaceSprites`/
   `AddSprite`/`PlaceAll`/`PlaceOne`/`HideSprites`/`Poses`/`DimLocked`/`DimChar` with
   `Menu_XchgRowMaps`/`SprPos`, icon 4's preview and redraw `Menu_UnkC9E5`/`CAE6` with
   `Menu_XchgPreviewTable`/`PreviewA`/`PreviewB`, `Menu_XchgInit`, mode 7's music
   `Menu_XchgMusic`/`MusicThread`/`SendSound`/`Sound81`/`Leave` and screen `Menu_XchgScreenMap`/
   `StartWave`/`WaveThread`); `Menu_DrawText4bpp` ($C2:F905, mode $81 into `Menu_DrawText`'s new
   `.mode`). Mode 6, the save screen ($C2:CEDC-$D155: `Menu_Mode06H0`-`H3` with
   `Menu_Mode06H1Confirm`, `Menu_SaveRedraw`, `Menu_SaveToSlot`, `Menu_Mode06Leave`,
   `Menu_SaveAskBack`; the slot cursor `Menu_UnkCFA2` and highlight `Menu_UnkCFFB` with
   `Menu_SlotHiliteData`; icon 5's preview and redraw `Menu_UnkD065`/`D0DB`; `Menu_UnkD0E5`;
   `Menu_DrawSlotWindows`/`DrawSlotWindow`) and the slot windows and details ($C2:D32C-$D4EF:
   `Menu_UnkD32C` frame, `Menu_UnkD36C` details, `Menu_SlotMemberIcon` with `Menu_SlotIconTiles`,
   `Menu_SaveAskOpen`/`Close`, `Menu_SlotEraVramRec`); `Menu_VramRecUnkE914` ($C2:E914, no
   reference); `MenuRom_DefaultConfig`/`DefaultButtonMap` as labels ($C2:FCA6; the `!` defines now
   name them); the shop's arithmetic $C2:FCB2-$FE09 (`Menu_ShopBuyQtyInit`/`SellQtyInit`,
   `Menu_ShopDivide` (24 by 16 bits), `Menu_UnkFD58`/`FD68` (multiply), `Menu_ShopGainGold`/
   `PayGold`, `Menu_ShopCapGold`); and `BankC2_OldBuildLeftovers` ($C2:FE0C-$FFFF: three tails of the
   shop code from earlier builds, then 277 bytes not in the current code; the old-build routines
   in `BankFF_OldBuildLeftovers` call $C2:FE92 / $C2:FED9, inside the copy at $C2:FE8A, so the two
   are probably of the same earlier builds). The stub names kept their
   `Unk` names (`Menu_UnkC54F`/`C57A`/`C5C7`/`C9E5`/`CAE6`/`CFA2`/`CFFB`/`D065`/`D0DB`/`D0E5`/`D32C`/
   `D36C`/`FD58`/`FD68`) because verified headers name them; better names once those are next edited:
   `Menu_CfgMapApply`/`CfgMapDraw`/`CfgMapMarks`, `Menu_Icon4Preview`/`Redraw`, `Menu_SaveCursor`,
   `Menu_SlotHilite`, `Menu_Icon5Preview`/`Redraw`, `Menu_SaveInit`, `Menu_DrawSlotFrame`,
   `Menu_DrawSlotDetails`, `Menu_ShopMul16`/`Mul8`. Found: icon 4 (mode 5) and BankC2_MenuEntry
   argument 5 (mode 7) are the party order screen: `Menu_Unk0D36` non-zero (`$FFFF` from
   `Menu_BuildItemTables`, so always in mode 5; mode 7 takes the entry's X) shows only the party
   (probably the in-menu reorder), mode 7 with X = 0 the reserve too (probably an event's party
   exchange; it plays song $3E and resumes `Menu_XchgSong` with `Audio_Cmd11`); `Menu_Unk7F01DF` has
   the `BankFF_CharBits` of characters that cannot be moved; object n of `Menu_SprPages` is
   character n; `Menu_Unk0D34` / object busy bits (`C2Scene_Unk0294`/`0299`/`ObjBFlags` bit 6) refuse
   the save screen; the slot details show the play time, a string per location nibble
   (`MenuRom_SlotEraNibbles`/`SlotEraStrings`, probably the era) and the members with 2 x 2 icons;
   `Menu_Unk2C53` is capped at 9,999,999 (`Menu_GoldMax`). Quirks recorded: `Menu_XchgBuildRows`' dead
   `LDA #$40` (BEQ after BNE); `Menu_XchgSwap`'s absolute stores to `Menu_DrawArg2`; the redundant MVN
   in `Menu_UnkC9E5` (overwritten by `Menu_DimPalette`); `Menu_XchgPoses` reading
   `Menu_PartyOrder + $40` with no row to pick; `Menu_UnkD36C`'s 16-bit STZ of $25 zeroing
   `Menu_SlotTextWidth` after the question's path; `Menu_DrawSlotWindows`' absolute INC of $0062;
   `Menu_UnkFD58` losing a carry in its second pass; `Menu_ShopPayGold` turning a borrow into $98xxxx;
   `Menu_ShopGainGold`'s never-taken carry; `Menu_ShopSellQtyInit`'s overwritten STZ;
   `Menu_Mode06H3` probably unreached (nothing sets handler 3). Re-review needed (verified headers or
   sources edited): `Menu_LoadWindowGfx` (banner range), `Menu_WindowVramRec` (7 bytes),
   `Menu_Mode05List`, `Menu_Mode06List`, `Menu_Mode07List` ("not analysed" gone),
   `Menu_MainPreviewTable`, `Menu_MainRedrawTable` (icons 4 and 5 named), `Menu_CfgEntry8` and
   `Menu_CfgMapAssign` (Exit lines), `Menu_DrawText` (the `.mode` label and its banner),
   `Menu_DrawClock` (the D3AA caller), `Menu_VramRecBg1Big` (the banner's loader note),
   `C2Script_IfRamByteNe` (its $FFB4 note) and `BankFF_CharBits` (its $CD59 reader), and the bank
   header line of bank $C2 (now "all from source") and the menu setup banner before
   `Menu_Expand3bppTiles`. After merging main (with the round-158 fixes) these were fixed as well
   and need review again: `Menu_Mode0BH0` (its preview and `Menu_UnkD0E5` no longer "not matched"),
   `Menu_LoadCursor` (`Menu_UnkCFFB`), `Menu_Mode03List` and `Menu_Mode04List` ("not analysed"
   gone), `Menu_VramRecUnkFC53` (its $C2:D071 loader named), `BankC2_OldBuildLeftovers` (its xref
   note: the JSRs inside it are data now), `C2Scene_Mode3` (the scene mode banner: who sets each
   mode), `C2Scene_Mode4` (`C2Scene_TrigListC` sets mode 4), `C2Scene_TrigListA` ("not traced"
   for "not matched"), `TextWin_StateTable` (its states named) and, in bank $C0,
   `Scene_PostLoadInit` (command $0B is `Menu_RunCommand`'s RTS: only `Menu_Unk834D` runs). Open:
   what `Menu_XchgUnk0F12`, `Menu_Unk04FB` and `C2Scene_Unk0299` are; what the strings of
   `MenuRom_NameStrings` 4/5 and `MenuRom_SlotEraStrings` say; what `Menu_UnkCFFB`'s HDMA table
   drives; who calls `$C2:FF00` (a JSL at $C9:6E49, unmatched bank) and what the 277 leftover bytes
   were; who loads `Menu_VramRecBg1High`, `Bg3Rows4`, `Bg3Rows16` and `Menu_VramRecUnkE914` (no
   loader in bank $C2).

4. Bank $FD: matched are the battle helpers `$FD:A982`-`$FD:B956` (every `BattleFD_*` callee of
   BattleSys_Main, Battle_SetupBattle and the turn lists, plus the gap routines between them:
   `BattleFD_RestoreEnemies`, `BattleFD_LoadUnkB18E/2`, `BattleFD_AddEnemyRewards`,
   `BattleFD_AddItemEntry`, `BattleFD_ItemRecOffset`, `BattleFD_ApplyRecBoost`, `BattleFD_UnkB33F`,
   `BattleFD_UnkB3EB`, `BattleFD_ZeroStatBlock`, `BattleFD_UnkB655`) with the JSR/RTL veneers
   `$C1:FDBF`-`$C1:FDD2` (`Battle_Mul16Long`, `BankC1_AddItemLong`, `BattleSys_RunPcAttackLong`,
   `Battle_RandRangeLong`, `BattleSys_RefundItemLong`); the field HDMA set-up `EngFD_UnkC124`,
   `Hdma_InitChannelsFD`, `EngFD_UnkC2C1` with its two handler tables (`$FD:C124`-`$FD:C2EA`) and
   `EngFD_UnkD52D`; the HDMA table builders behind its tables, `FieldHdma_*` (`$FD:C2EB`-`$FD:D52C`:
   plain screen, top band and bottom band for each table set, the channel 2/7 helpers, the data
   fill with the BG3 wave, the wave run adders); the palette animation ticker `PalAnim_TickAll`
   (`$FD:E39C`-`$FD:EAA5`: all eight kinds, the seven darkening scalers `PalAnim_Scale*` and the
   seven lightening ones `PalAnim_Whiten*` of kinds 4/6, `PalAnim_FadeWhite`/`PalAnim_PulseWhite`);
   the location animation set-up `FieldFD_LoadAnimSetA` (`$FD:DE98`) and `FieldFD_LoadAnimSetB`
   (`$FD:E292`), the field IRQ's tile-animation upload `FieldFD_UploadTileAnims` (`$FD:E022`) and
   `PalAnim_StopAll` (`$FD:E275`); the Mode 7 scene of event `$FF $80-$8F` (`M7Scene_*`,
   `$FD:DA00`-`$FD:DE97` and `$FD:EAA6`-`$FD:F28F`: the four run loops, init, own NMI/IRQ, iris
   window, per-line Mode 7 scale, ray-drawn sprite bitmap, palette cycling); and all the vectors
   `FdVec_FFE5`-`FdVec_FFFD`. The `BattleFD_Unk*`
   and `EngFD_Unk*` routines keep their names because verified code calls them by name; better names
   once those callers are re-reviewed: `BattleFD_UnkA982` ClearWorkRam, `UnkAA98` KoAllEnemies,
   `UnkACFD` ClearUnkB328, `UnkAD09` ClearTechEntries, `UnkAD17` ShowEndMessages, `UnkAE52`
   CopyCharRecord, `UnkB0D5` InitListFlags, `UnkB22E` InitBattlerIds, `UnkB438` InitEnemyStats,
   `UnkB4E7` InitListTimers, `UnkB732` ClearBattleState, `UnkB7EB` InitFirstTurns. Found on the way:
   `!Battle_UnkB1BE` is the character id -> PC slot map (BattleFD_UnkB22E), `!Battle_ListRuns` are
   first set (to 10) by BattleFD_UnkB0D5, `!Battle_UnkB158` is list 12's `!Battle_ListReload`
   entry, and `!Battle_EnemyCount` is always 8 after BattleFD_UnkB22E. Stale after this batch
   (verified headers, fix at their next edit): Battle_SetupBattle ("callees that are not analysed
   (bank $FD ...)"), LoadLocation ("the two bank-$FD vectors are unmatched"), Scene_ResumeNmi
   ("the bank-$FD callees are not matched"), and RandomTableFD needs a new review (its region changed with the
   code matched before it). Re-review needed from the HDMA/palette batch (verified headers
   edited): `EngFD_UnkC2C1` and its two tables (handlers renamed, "not analysed" removed),
   `FdVec_FFF7`, `FieldFD_LoadAnimSetA` (its banner), `Evt_Op84_SetUnk1B01` (the bank $C0 banner
   over the palette-animation opcodes) and `ScrollWaveA` (its readers named). Quirks recorded: the
   missing CLC in FieldHdma_FillDataA/B (carry in = Hdma_Unk7F0351 bit 0, then each line's carry
   out), the band builders' extra 41-n TM run and the TM table ending at the band when
   Field_Unk27 = 1, PalAnim_Pulse's level 0 (black) where 256 was meant, PalAnim_Fade storing
   .Unk5 as the level when it is $80 or more. Better names once the verified callers are
   re-reviewed: `EngFD_UnkC2C1` FieldHdma_RunFrame. Re-review needed from the palette/Mode 7
   batch (verified headers edited): `PalAnim_TickAll` (banner and dispatch names), `FdVec_FFF4`
   (its "three JMPs" text), `FieldFD_LoadAnimSetA` (banner: the $05B0 records are now traced),
   `Evt_OpFF_Misc` and `IrqHandler` ("unmatched" vectors). Quirks recorded there: kind 4/6's
   `PalAnim_WhitenR`/`WhitenB` write one byte of the colour (the other stays as Pal_CgramBuf had
   it), `WhitenRG` drops blue and `WhitenGB` drops red; `M7Scene_Init` fills window buffer 1 twice;
   `M7Scene_IrisRadii` has 31 entries (entry 31 is the next table's 0); `M7Scene_UpdateScroll`'s
   dead BG colour rotation. Open: which scene `$FF $80-$8F` is, and who calls `FdVec_FFEE`
   (`$C3:4D46` looks like a JSL in unmatched code). Also matched (the FD-rest batch, all data):
   the battle tables `$FD:B957`-`$FD:BA60` (`BattleFD_FixedCmdPtrs` / `FixedCmds`, the bit-5
   battle's three fixed BattleCmd sets; `BattleFD_FixedPartyPtrs` / `FixedParty`, BattleFD_UnkB2DE's
   four words per character record, probably HP / max HP / MP / max MP; `BattleFD_AiActLength`),
   `BankFD_RandomTableTail` (`$FD:BB61`-`$BFFF`: 6 old-build bytes of the random table, then $00
   fill), `FieldHdma_OldBuildLeftovers` (`$FD:D5D4`-`$D9FF`: never-run old copies of the end of
   FieldHdma_BuildBottomBandB and of EngFD_UnkD52D, then $00 fill), and the location animation
   lists `$FD:F290`-`$FD:FFE4` (`FieldAnimListAPtrs` / `FieldAnimListA` for FieldFD_LoadAnimSetA,
   `FieldAnimListBPtrs` / `FieldAnimListB` for FieldFD_LoadAnimSetB, and `FieldAnimListBOldTail`,
   an unread copy of B's last $BC bytes). With them `$FD:A8A5`-`$FD:FFFF` is all from source.
   Quirks recorded there: BattleFD_FixedParty's sets are 7 entries apart but read for 8 records
   (record 7 takes the next set's first entry; set 2's takes BattleFD_AiActLength's first 8
   bytes); the three $01 bytes after the `$8B,$38,$04,$08` palette records read as empty records.
   Back to review from it: `RandomTableFD` (its "left unmatched" note now names
   BankFD_RandomTableTail). Still unmatched in bank $FD: `$FD:0000`-`$FD:A8A4`, all data: the
   packed credits graphics (`!Credits_GfxPack`, `$FD:0000`), the staff credits text
   (`!Credits_Text`, `$FD:A000`-`$A7D0`, then $00 to `$A7FF`) and the battle tables at
   `$FD:A800`-`$A8A4` (`!BattleRom_PcStatBlock` `$A80B`, also read at `$A811` by
   BattleFD_UnkB7EB; `!BattleRom_CmdPtr` `$A849`; `!BattleRom_TechEntryPtr` `$A84F`;
   `!BattleRom_CharFirstTech` `$A89D`; `$A800`-`$A80A`, `$A821`-`$A848` and `$A855`-`$A89C` have
   no named reader yet). Those tables are the next cheap step; the credits need a text/graphics
   format, not hand-written db. Survey note: no unmatched $FD byte is code; the 481 bytes the
   earlier survey counted over the matched code were its allowance for bytes since matched as data
   (the old-build leftovers, animation lists and tables). Re-surveyed 2026-10-14 (see "Code
   survey" below): $FD's code bytes are its 15,668 matched. Next in bank $FD: who writes `Hdma_Unk7F0351`, `Hdma_Unk7F22C0` and
   `LayerDrift_L1X/Y`; the battle code before `$FD:A982` (`$FD:A8CE`/`$A8FE` and the routines that call
   BattleSys_RefundItemLong at `$FD:A8D8`/`$A910`, among the `$FD:A8A5`-`$A95F` callees of B575/B967);
   which LocRom.Palette values occur (FieldAnimListBPtrs is taken as 88 entries because the lists start
   there); who sets `!Battle_Unk29AC` and `!Menu_Config+28` for the bit-5 battle. Open: what the BattleRom_EnemyReward `.Unk0`/`.Unk6`
   sums, the end messages 4-7 and their bits (`!Battle_UnkB2B0`/`B2B3`), the `BattlerStats.Unk57`
   values ($A0/$A1/$A9/$AB/$B3) and the PcStatBlk stats mean; who fills BattleEnemyInit ($29C4) and
   reads `!Battle_Unk7F01EE`; which records of the $7F:14F0 block the HDMA tables use.

5. Bank $C7 (sound driver, 65816 side; new file `asm/bankC7/bankC7.asm`): matched are
   `$C7:0000`-`$C7:0E10`: the entry block `Audio_DriverInit` with the vectors
   `Audio_DriverCommand` (`$C7:0004`; the battle code's name `Audio_ProcessEntry` is kept as
   `Audio_ProcessEntry = $C70004`, since asar cannot alias a label and the tools want one label
   per address), `Audio_VecLoadNewSamples` and `Audio_VecSendSampleDir` (no
   caller); the boot tables `Audio_BootBlockPtrs` / `Audio_BootBlockAram` and the unread
   `Audio_TableDirectory` (`$0010`-`$0037`); all the 65816 code (`$0038`-`$0A97`): the IPL boot
   `Audio_Boot`, `Audio_RunCommand` (with `_Dispatch` and the common exit `Audio_CommandDone`), the
   song load `Audio_CmdLoadSong` -> `Audio_LoadNewSamples` -> `Audio_SendSampleDir` ->
   `Audio_SendSongData`, `Audio_CmdSend` (commands $18-$2F, $80-$FF), `Audio_UploadSample`,
   `Audio_CmdSongAlias` ($30-$3F), `Audio_AdjustSongCmd`, `Audio_CmdSwapSample` ($71),
   `Audio_CmdBlockVariant` ($70), `Audio_UploadBlock2F00`, the port helpers `Audio_SendSeq` /
   `Audio_AbortXfer`, `Audio_SetEchoDelay`, `Audio_DropEchoSlots` and `Audio_StartSong`; and the
   tables it reads (`$0A98`-`$0E10`: `Audio_SongAliasTable`, the empty `Audio_SongBit2List`,
   `Audio_SongCmdTable`, `Audio_SongCount`, the 62-sample `Audio_SampleTable` / `SampleLoop` /
   `SampleParamA` / `SampleParamB` and the 83-song `Audio_SongTable`). The `$1E00` page is named
   in ram_engine.inc (`!DP_Audio`, used as `!Name-!DP_Audio`), the commands, port protocol, ARAM
   addresses and the ROM data after `$0E10` (`!AudioRom_*`) in constants_engine.inc. Quirks
   recorded: Audio_SendSampleDir's slot search over 32 words (into Audio_SlotLen) and its
   parameter reads for unused list entries landing in bank $C8 ($C8:0C1E / $C8:0C9A),
   Audio_SendSongData's BPL step loop sending 1-3 bytes past the song data, Audio_AdjustSongCmd's
   empty list (no effect), Audio_CmdSend's give-up test on Audio_CmdId that only an outside writer
   could pass, Audio_DropEchoSlots clearing through $1E81 (Audio_SlotAram has 17 entries), and
   the two mid-load vectors at $C7:0008/$000C that would unbalance the stack if called. Headers
   edited by this batch (verified before, back to review: the "(unmatched)" / "(not matched yet)"
   / "(not traced)" remarks on what the driver changes): LocLoad_AudioSetup,
   Audio_PlaySfxAtLeader, Audio_PlayTileSfxB, Evt_OpE8_SoundCmd18, Evt_OpEA_PlayMusic,
   Evt_OpEB_SoundCmds81To83, Evt_OpEC_SoundCmd, Battle_PlaySfx0, BattleMenu_EnqueueReadyBattler,
   BattleMenu_TargetSelectInput, BattleTgt_EnemyLineFromCaster, C2Scene_WaitFrames,
   C2Scene_ZoneSoundAtEntry. Stale, not edited (fix at their next edit): BattleSys_RunService
   counts service 1's Audio_ProcessEntry among the code "not analysed" (it is matched: A, X, Y,
   P, DP and DB come back as they were); the banner over C2Scene_ZoneSoundAtEntry calls command
   $10 "probably play song" (Audio_CmdLoadSong loads the song in Arg0). Open: everything on the
   SPC700 side (the meaning of the transfer modes 2/3/5/7, the step that Audio_AbortXfer sends,
   APUIO1 bit 7 after a song command in Audio_StartSong, what commands $10/$11/$14/$15 and
   $18-$2F/$80-$FF do there); what `!AudioRom_SongExtra` (36 bytes per song to ARAM $F120),
   `AudioRom_SongEcho` byte 1 (sent as Arg1) and `Audio_SampleParamA` mean; whether
   `Audio_SampleParamB` really is the ADSR pair and `Audio_EchoDelay` the DSP's EDL; and who
   reads `Audio_FreeAram`, `Audio_SampleBase`, `Audio_Unk1EFA`/`1EFB`, `Audio_Unk1E0A` (none in
   bank $C7). Next in bank $C7: the tables `$0E11`-`$24C2` (`!AudioRom_SongSamples`,
   `SongExtra`, `SongEcho`) are plain data read only by this code and could be labelled the same
   way; from `$24C3` on (the SPC700 program, the upload blocks, the samples) is the SPC700 track.

6. Bank $C3: the kernel `$C3:0000`-`$C3:10CA` is matched (vectors, `C3_BootModule` and its
   NMI/IRQ handlers, the decompressor `Decomp_ToWram` with its packed format in the header, the
   window builders `WinFx_BuildCircle`/`WinFx_StepWipe`/`WinFx_BuildQuad`, `C3_RandomByte`, and the
   services of the packed module: `C3_ScaleBitmap`, `C3_ModuleNmi`/`C3_ModuleFrame`, the script
   interpreter `C3_RunScript` and its task lists, the sprite builders, `C3_BuildCopyCode`,
   `C3_ReadPad`, `C3_MulSigned`, `C3_FindDivisor`, the staff text, the "CODE END C3" marker).
   The pack at `$C3:1200` and the scene data after the module stay ROM bytes. The module,
   `BankC3_PackedModule` (`$C3:1313`-`$7A2B`, the jet-bike race program, unpacked to
   `$7E:3000`-`$B57E`), is built from source: `asm/bankC3/packed/module.asm` is the unpacked
   module, assembled on its own at base `$7E:3000` by `tools/c3pack.py build` (run by `make
   build` and by every tool that assembles `asm/main.asm`), packed with the original packer's
   rules (Okumura's LZSS with a zeroed ring buffer; the tool's docstring has them, and it rebuilds
   all 60 packs of C3Rom_PackPtrs in the format byte for byte) to `build/c3pack/module.lz`, which
   bankC3.asm incbins. What the source does not cover yet is incbin'd from the ROM's module
   (`%C3ModRomBytes`, from `build/c3pack/rom_module.bin`), as unmatched bytes stay ROM bytes
   elsewhere; it is counted apart like the SPC700 driver (`tools/progress.py`'s "packed $C3
   module" line, rows in `symbols/c3module_functions.csv`, rules in `tools/lint_c3module.py`;
   the module's code bytes are what `tools/c3module.py`'s trace reaches plus the matched code).
   Matched so far (first batch, to review): the start and setup `$3000`-`$31BE`
   (`C3Mod_Start`, `C3Mod_ProgramTable`, `C3Mod_Init` with `C3Mod_Return`, `C3Mod_SoundReset`,
   `C3Mod_WaitVblank`), the sound port and row copies `$377A`-`$37F9` (`C3Mod_AudioCommand`,
   `C3Mod_AudioSend`, `C3Mod_DoubleRows`, `C3Mod_SpaceRows`, `C3Mod_CallW`),
   `C3Mod_HideSprites` (`$3843`), `C3Mod_UploadPalette` (`$388B`) and the task runners
   `$398A`-`$39F4` (`C3Mod_RunTasks` with `C3Mod_TaskNext`, `C3Mod_TaskEnd`,
   `C3Mod_TaskReplace`, `C3Mod_RunNmiTasks` with `C3Mod_NmiTaskNext`, `C3Mod_NmiTaskEnd`,
   `C3Mod_NmiTaskReplace`; quirk: the last one branches back into the frame-task loop). The
   kernel's `!C3Mod_*` defines now name matched routines (the lint's KERNEL rule checks them).
   Next: the rest of the module, `C3Mod_Rest*` blocks; the trace (6.8 KB of code from the
   entries and the program table) misses code reached through the task lists and
   C3_ScratchF0, so add entries to `tools/c3module.py` as they are found (the programs at
   `C3Mod_Prog*` set tasks up: their `LDA #addr` / `STA C3_TaskList,X` stores give the task
   entries; `$31BF` (a multiply/divide pair), `$3870` and `$37FA` are code no trace reaches
   yet). Open: what `$C3:1200` (`C3Rom_PackPtrs` entry 0)
   unpacks to and who reads it; the module's DP at the calls of `C3_MulSigned`, `C3_ScaleBitmap`
   and the sprite builders (hedged "probably 0" / "the module's"); C3_EntryArg bits 0-4 and 5 as
   the module reads them. Re-review needed (verified headers edited by this batch):
   `C2Scene_LoadUnkC800`, `C2Scene_UnpackBgPack`, `C2Scene_UnpackBg3MapPack`, `C2Scene_Win1Init`,
   `C2Scene_Win2Step` (exit registers now known) and `Field_HookWinGrow0` (the window-hook banner
   over it). Quirks recorded: the circle's carry-in adds (start value, first row, edge +1s, the
   d >= 0 step), the wipe's mode-2 extra 1 and B = $03 after a clamp, the quad's leftward error
   start and its unbounded fill when the bottom is line $FF, the scaler's carry-ins, the stray
   `$DB` after the script opcode table and the unreachable APU loop in `C3_RunScript`.

7. Bank $CF: `$CF:E300`-`$CF:FFFF` is matched (the CF battle batch): all of the bank's code
   and the data around it, 7,424 bytes from source. `$CF:0000`-`$CF:E2FF` is data and stays as
   ROM bytes (not looked at). By cluster:
   - `BattleCF_VblankUploads` (`$CF:E300`, vector `$C1:0009`): the DMA uploads (OAM, the queued
     window map, the command window, CGRAM, the battlers' frame tiles in four graphics steps,
     the decoded frame of `!Battle_FrameSlot`).
   - `BattleCF_FrameUpdate` (`$CF:E58A`, vector `$C1:000C`) with `BattleCF_BounceHitNumbers`
     and `BattleCF_StepFxColourCycle`: blink toggle, cursor glow, frame counter, the colour
     rotation of opcode `$6B` (`$CF:E600` on), the demo battle's restart, L+R hold, then the
     movers, path walks, object follow, position history, enemy parts and the sprite build;
     it clears `!Battle_FramePending`.
   - The sprite builder `BattleCF_BuildSprites` (`$CF:E83A`, D = `$1D00`) and its callees
     (`BattleCF_DrawPosHistory`/`DrawPosHistRecord`, `DrawUnkA5D8Sprite`, `DrawBattler`,
     `CopySprTiles`, `DrawFrontLayer`, `DrawBackObjects`, `DrawFxOverlay`, `DrawHitNumbers`,
     `DrawActObj`), `BattleCF_StepPathWalks`, `BattleCF_FollowObjects`,
     `BattleCF_RecordPosHistory`.
   - The movers: `BattleCF_RunMovers` with `BattleCF_MoverTable` / `BattleCF_ObjMoverTable`
     (`$CF:F01E`/`$F02E`), the eight battler movers (`BattleCF_Move*`, `BattleCF_ShakeStep`),
     the seven object movers (`BattleCF_ObjMove*`), `BattleCF_PointsNear`,
     `BattleCF_StepEnemies` (the enemy movers' 8-pixel stepper), `BattleCF_PlaceEnemyParts`,
     `BankCF_DeadShift3` (4 unreached bytes), `Battle_SinLookupCF` with its new sub-entry
     `Battle_Mul8x16CF`, `Battle_CalcAngleCF`, `BattleCF_PixelToCell`.
   - `Battle_MergePendingEntries1580`, `BattleCF_EnterBattle` (`$C1:001B`),
     `BattleCF_ExitBattle` (`$C1:001F`), `BattleCF_PixelToTile`, `BattleCF_WaitFrame`, the
     three `Battle_QueueVramUpload_*`, `BattleFx_SetPtrA2FromTable`,
     `BattleCF_RemoveMarkedEnemies` (service 6), `BankCF_EndFill` and
     `BattleCF_ActForceBytes` (`$CF:FFFD`-`$FFFF`).
   Renamed stubs: `BattleCF_UnkE300` -> `BattleCF_VblankUploads`, `BattleCF_UnkE58A` ->
   `BattleCF_FrameUpdate`, `BattleCF_UnkFBE5` -> `BattleCF_ExitBattle`, `BattleCF_UnkFE20` ->
   `BattleCF_RemoveMarkedEnemies`; the callers' names `Battle_MergePendingEntries1580`,
   `Battle_QueueVramUpload_*` and `BattleFx_SetPtrA2FromTable` are kept. New stubs:
   `BattleSys_VecCD0000`, `BattleSys_VecCD0006`, `BattleSys_VecCD0024`.
   Found on the way: the battlers' sprites are drawn at `!Battler_ScreenX/Y` plus the signed
   display offsets `!Battler_UnkA4A4/A4AF` (what the circle, shake and arc movers write) plus
   the per-sprite offset words in `!Battler_FrameExtra`; `!Battler_UnkA5CD` non-zero draws the
   battler in front of the others; `!Battle_ActObjLinks` bit 7 = object in front of its
   battler, bit 6 = behind; `!Battler_PosHistUnkAB7D/AB88` time the position history's
   drawing; `!Battler_UnkA5D8` puts a tile-2 sprite over the battler; `!Battler_Palette` holds
   OAM palette bits (palette * 2).
   Quirks recorded: `BattleCF_FrameUpdate`'s background rotation (one pass past the last row;
   65535 moves when the first colour is 15), `BattleCF_StepFxColourCycle`'s 16-bit Y after the
   special-palette skip, `BattleCF_MoveKind4`'s dead -h store, the object table's kind 6 being
   the battlers' shake mover, `BattleCF_PointsNear`'s signed-byte distance,
   `BattleCF_StepEnemies` ending only at exactly 8, `Battle_CalcAngleCF`'s 16-bit index store
   over `!Battle_HitNumActive` (`$AC5A`), `Battle_MergePendingEntries1580` with an empty
   record or a full list, `BattleCF_EnterBattle`'s clear starting at `$2D01`,
   `BattleCF_BuildSprites` with no battler, `BattleCF_DrawHitNumbers`' whole high-table byte.
   Back to review (verified headers or code lines edited): `EngCall_BattleMain` (header and
   `BankC1_ExitBattleJml`'s JML), `BankC1_JmlCCE000` (header and its sub-entries' JMLs),
   `BattleSys_RunService`, `BattleSys_Service6`, `BattleSys_UnkAC5E`, `BankC1_BattleStartVec`,
   `BattleMenu_UpdateWindows`, `BattleMenu_UpdateMainWindow`, `BattleMenu_DrawTechCursorRow`,
   `BattleMenu_ProcessInput`, `BattleMenu_ConfirmCommand`, `BattleMenu_OpenItemList`,
   `Battle_FxReset` (the effect handlers' banner), `Battle_TickEnemyMovers`,
   `BattleAct_OpMoveTo`, `BattleAct_OpCurveTo`, `BattleAct_OpPathTo`, `BattleAct_OpFollow`,
   `BattleAct_OpStartPalCycle`, `BattleAct_OpArcToCalc`, `BattleAct_OpMoveAlongHeading`,
   `BattleAct_OpCircleToCalc`, `BattleAct_OpEllipseToCalc`, `BattleAct_OpMoveKind4ToCalc`,
   `BattleAct_OpShake`, `Rom_AngleTable`, `Rom_DirToFacing` and `Battle_SinLookupCF` (header:
   the sub-entry, the Callers note).
   Stale, not edited (verified headers, fix at their next edit): `BattleSys_PumpFrames` still
   calls the `$CF:E77B` clear of `!Battle_FramePending` "inferred, not proven" (it is
   `BattleCF_FrameUpdate`'s end); `BattleAct_OpClearUnkA4A4` (opcode `$2B`) says the
   `!Battler_UnkA4A4/A4AF` meaning is not known (they are display offsets); `BattleMsg_FormatNumber4Digits`'
   Callers note calls `$C1:5BB9` unmatched; `BattleAct_OpLinkObjBit7`'s "what the link does is
   not traced (read at `$CF:EDD4` and `$CF:F81D`)": bit 7 / bit 6 draw the object in front of /
   behind the battler (`BattleCF_DrawFrontLayer`, `BattleCF_DrawBackObjects`).
   Found by the bank-$CC batch (item 8): the battle set-up (`Battle_InitScene`,
   `Battle_InitSceneGfx`) fills `!Battler_FrameDma*`, `!Battler_SprBytes`, the OAM helper tables
   `!Battle_OamHighIdx`/`XBit`/`XClear`, the `Battle_SprRec` records at `$11B0`,
   `!Battle_PartsAnchor`/`!Enemy_PartOfs*` with `!Battle_EnemyPartsOn` and `!Battle_UnkA113`;
   `BattleAct_StepObjAnim` sets `!Battle_ActObjFrame`; `!Battle_InitUploadStage` (`$98CA`, which
   `BattleCF_EnterBattle` zeroes) is `Battle_InitUploadStep`'s stage counter. Whether anything
   rewrites those during the battle is not traced.
   Open: `!Battle_DemoQuitTimer` (`$BB00`); who sets `!Battle_UnkA101` and `!Battle_UnkE5`; what
   the bank-$CD vectors `$CD:0000`/`0006`/`0024` do (the last after an enemy is moved to the
   special palette: a fade-out, probably); the meaning of `!Battle_Unk9F`, `!Battle_UnkB9`,
   `!Battle_UnkA0A6`, `!Battle_UnkBB80`. Next in this bank: the data `$CF:0000`-`$CF:E2FF`
   (what reads it is not traced).

8. Bank $CC code (branch match-cc-ff): `$CC:E000`-`$CC:F382` is matched in full. The battle
   set-up: `Battle_InitUploadStep` (was `BattleCC_UnkE000`; the three staged VRAM uploads, run from
   the JSL at `$CD:0AB4` through `$C1:000F`), `Battle_InitUploadObjTiles` with the unreached
   `Battle_InitUploadObjTilesDead`, `Battle_InitScene` (was `BattleCC_UnkE2E4`: RAM start state,
   names, tech lists, PC and enemy positions and sprite pointers, enemy kinds and name lines),
   `Battle_InitSceneGfx` (was `BattleCC_UnkED87`: sprite records, tiles, OAM, colours, the
   `!Battler_FrameDmaSrcA` words, then the upload wait), `Battle_ReencodeText`; the action helpers
   `BattleAct_ResetState`, `ResetFxApplied`, `Battle_BuildOccupiedCellMap`,
   `BattleAct_BuildBattlerList`, `StepPalettes`, `TickUnkA1A8` and `BattleAct_StepObjAnim`
   (`$CC:F2A9`). Quirks recorded: the dead tail of `Battle_InitUploadObjTiles`; the unused
   duration stride and the unbounded enemy-name lines in `Battle_InitScene`; the BRA to the next
   instruction in `Battle_ReencodeText`; the 11-entry scan from slot 3 in
   `Battle_BuildOccupiedCellMap`; the facing stored back into itself in `BattleAct_StepObjAnim`.
   Merged with the bank-$CF batch (item 7), which reads much of what the set-up writes: the RAM
   names were unified to one each (`!Battler_FrameDma*` was `!Battler_UnkA654`.., also
   `!Battle_CursorGlowStep`, `!Battle_FrameCount8`, `!Battle_EnemyPartsOn`, `!Battle_PartsAnchor`,
   `!Enemy_PartOfsX/Y`, `!Battler_SprBytes`, `!Battle_OamHighIdx`/`XBit`/`XClear`,
   `!Battle_ActObjFrame`; bank $CF's `!Battle_Unk98CA` and `!Battle_MenuMem*` are now
   `!Battle_InitUploadStage`, `Battle_SavedCursor` and `!Battle_SavedItemScroll`/`Row`).
   Open: what most of the bytes set at set-up mean (`!Battle_Unk9842`, `!Battle_Unk9919`,
   `!Battler_UnkA5C2`, `!Enemy_Unk988B`, `!Battle_Unk0B24`, `!Enemy_SprFlags` bits,
   `!Battle_UnkE4`), which layers the VRAM uploads feed, the `!BattleRom_EnemyKindList` kinds other
   than 3 and 4, why a large enemy's sprite rows cover the next enemy entries, and who reads
   `!Battle_OamHighXClear` (bank $CF's sprite builder reads only `Idx`/`XBit`). The rest of bank $CC ($CC:0000-$DFFF,
   $CC:F383 on) is data, still ROM bytes. Headers edited (back to review): EngCall_BattleMain,
   BattleSys_SceneSetup, BankC1_LongDispatch, BankC1_JmlCCE000, BattleAct_OpLoopAnim,
   BattleAct_OpResetSpeed; in the merge with the bank-$CF batch also BattleSys_RunService (the
   service-0 note), BattleCF_EnterBattle (`!Battle_InitUploadStage`) and BattleCF_ExitBattle
   (`Battle_SavedCursor`, `!Battle_SavedItemScroll`/`Row`).

9. Bank $FF code (branch match-cc-ff): `$FF:F548`-`$FF:FC66` is matched (with the wave tables
   already matched): `BankFF_BuildTileSets`, `BankFF_LoadE4Palette`, `BankFF_BuildScreenMap`,
   `BankFF_StepWave`, `BankFF_WidenTiles`, `BankFF_UnkF813` (tech data for the menu),
   `BankFF_UnkF958` (combo availability in `Menu_Unk04A4`), `BankFF_UnkF9C4` (save-slot check),
   `BankFF_SaveSlot`, `BankFF_LoadSlot`, `BankFF_LoadSlotPart` (partial load with the starting
   equipment put back; probably a new game from a save), `BankFF_SetSlotOfs`,
   `BankFF_SlotChecksum`, `BankFF_BuildGradHdma`, and the tables between them
   (`BankFF_ScreenMapTiles`, `BankFF_ScreenColoursA/B`, `BankFF_TechStepLimit`, `BankFF_CharBits`,
   `BankFF_SaveRecords`, `BankFF_PartRecords`, `BankFF_EquipOffsets`, `BankFF_SlotSramOfs`,
   `BankFF_GradValues`). Callers of most are unmatched bank-$C2 code, so their entry states are
   read from the routines (hedged in the headers). Open: what the tile sets of
   `BankFF_BuildTileSets` / `WidenTiles` and the `$7E:1640` bytes of `BankFF_UnkF813` show, the
   `Menu_ItemInfo0` entries it marks, `BankFF_UnkF9C4` writing its result to `$0400` under
   `Menu_CmdBootCheckSaves`, and which registers HDMA channel 1 feeds. Not matched: `$FF:F540`-
   `$F547` (8 data bytes before the code). Headers edited (back to review): Menu_CmdBootCheckSaves,
   Menu_InitNewGameData, Menu_BuildItemTables, Menu_LoadSlotSummaries (the slot-layout note above
   it). Since the C6 batch (item 13) `$FF:FC67`-`$FFFF` is matched as data,
   `BankFF_OldBuildLeftovers` (921 bytes of db in named segments): xref finds no call or jump into
   it from code; it holds two layers of older assemblies (a copy of the end of BankFF_GradValues,
   older copies of BankFF_SlotChecksum's end and of BankFF_BuildGradHdma with its table, a start-up
   fragment ending JML $00:0500, routines that copy from bank $E4 and call $C2:FE92 / $C2:FED9,
   and two routines on DP $54/$F4 no matched code resembles). Survey note: the earlier survey counted
   640 of these bytes ($FF:FC80-$FFDF, allowance blocks) as code; they are data. Re-surveyed
   2026-10-14 (see "Code survey" below): $FF's code bytes are its 1,563 matched. Stale (verified
   header, fix at its next edit): BankFF_OldBuildLeftovers' last note line, "symbols/code_survey.csv
   counts part of these bytes as code"; the survey counts none of them now. Header edited by it (back to review):
   BankFF_BuildTileSets (the bank banner above it, which said these bytes stay as ROM bytes).

10. Bank $CD (new file `asm/bankCD/bankCD.asm`; the survey puts code at `$CD:0000`-`$3FE5` with
   tables inside, data from `$CD:4000`): `$CD:0000`-`$CD:3FFF` is matched in full (three batches).
   First `$CD:0000`-`$CD:16B4` (the CD battle batch):
   - the entry block (19 JMP vectors; the names the callers used are kept: `BattleSys_VecCD0000`
     ... `BattleSys_IdleVecCD0036`; new `BattleSys_VecCD000F`, `BattleSys_VecCD001E`, no caller
     found for either) and `BattleCD_EnterBattle` / `BattleCD_ActOp80` (JSLs into bank $D1);
   - an enemy's exit `BattleCD_EnemyDissolve` (+ `BattleCD_EnemyDissolveFx`, JSL'd mid-routine)
     with `BattleCD_DissolveStep`: a pixel dissolve of the enemy's decoded frame, or a layer
     effect ($38/$40);
   - the messages: `BattleCD_ShowMessage` (vector $0021; waits, button skips), `ShowMessageTimed`
     ($001E), `ShowScriptMessage` ($0033), the info panels `ShowEnemyInfo` / `ShowTargetInfo`
     ($0030/$002D) and `ShowTechInfo` ($0027), on bank $C2's text window (`BattleCD_StartText`,
     `ShowText`, `StepText`, `ClearTextGfx`, `GetMsgTime` with `BattleCD_MsgTimeTable`: the
     message-speed setting, config byte $2991 bits 3-5);
   - `BattleCD_PadRepeat` (pad auto-repeat into `!Battle_PadEdgeButtons`), `BattleCD_SetNmiMode1`,
     `BattleCD_ApuCmd81`, the battle's end `BattleCD_ExitBattle` (closing wipe, end effects $84/$87
     by `FieldBtl_Result`, NMI switched to `$D1:F4C0`, AudioFadeDispatch with P/D/DB saved),
     `BattleCD_WaitNmiAck`, `BattleCD_FrameTick` (vector $0009), `BattleCD_IdleTick` ($0036);
   - the window wipe: `BattleCD_StartOpenWipe` / `StartCloseWipe` / `WipeRunning` / `StepWipe` /
     `WipeStepOpen` / `WipeStepClose` (line counts of the nine indirect HDMA tables at `$C867`);
   - the NMI work: `BattleCD_NmiDispatch` (from the bank-$D1 NMI handler, by `!Battle_NmiMode`,
     `BattleCD_NmiTable`), `BattleCD_NmiSetup` (HDMA channels 0-6), `BattleCD_NmiMain`,
     `NmiUploadText` (text halves, tilemap pages), `UploadCgram`, `SetWh0Table`, the scroll data
     `NmiLayerScroll` / `BattleCD_ScrollModeTable` / `ScrollPlain` (+ `ScrollFill`) /
     `ScrollFxBg3` / `ScrollWaves` / `ScrollWavesBg3`, the screen shake `BattleCD_StepShake`
     (+ the palette-animation record copies) with `BattleCD_RandByte`, `ClampPalAnims` (FieldAnimB
     records 8-11), `TickCDC9`, `ScrollStepL`, `InitHdmaData` (+ `RestoreScreen`) and its `L`
     wrapper;
   - the layer effects (layer-3 background animations: tech effects, the enemy exits, the battle
     end): `BattleCD_StartLayerFx` (vector $0018), `RunLayerFx`, `RunEndFx`, `LayerFx84/87`,
     `WaitLayerFxIdle`, `EndLayerFx`, `LayerFxSetsScreen`, `LoadLayerFx` with `LoadFxRecord`,
     `LoadFxTiles` and the 2bpp tile copiers (`TileCopy2`, `TileHFlip2` + `TileReverse2`,
     `TileVFlip2`, `TileVHFlip2`, `BattleCD_TileHandlers2`), `FillFxTilemaps`, `BuildFxTilemap`,
     `RestorePalRows`, `FxRecSetup`, `LoadFxPalA` (+ `LoadFxPalB`); the script channels
     `StartFxChannels` / `StartFxChannel` / `StepFxChannels` / `RunFxScript` / `RunFxOp`;
   - the action graphics `BattleCD_LoadFxGfx2` (+ `LoadFxGfx4`; vectors $002A/$0015) with
     `ConvertFxGfx`, `PickPlaneBits` / `BattleCD_FieldShifts` / `ShiftField6` (+ 4/2/0), the 4bpp
     builders `Tile4Copy`, `Tile4Planes`, `Tile4HFlip` (+ `TileReverse4`), `Tile4VFlip`,
     `Tile4VHFlip`, `BattleCD_TileHandlers4`, `BattleCD_PlaneMasks`, `BattleCD_FxGfxVram`; and the
     small tables `BattleCD_TileUploadVram`, `BattleCD_ZeroWord`.
   Found on the way: `$BB00` (`!Battle_DemoQuitTimer`) is the INIDISP brightness the NMI writes
   (`!Battle_Brightness`), so the demo's quit count is a fade; `$0580`-`$05AF` are FieldAnimB
   palette-animation records 8-11 the battle fills; `$5D9B` is set while a layer effect's channels
   run; `$C867` holds nine indirect HDMA tables whose line data are at `$BC85` (BG1SC-BG4SC),
   `$BC89`/`$BD09`/`$BD89` (layer scroll), `$BE89` (TM-TSW), `$BE91` (CGWSEL-SETINI), `$BE99`.
   Quirks recorded: `BattleCD_ShowScriptMessage` counts `!Battle_ScriptMsgUp` up even when it
   shows nothing; the info panels test it as a word (with `$CD1E`); `BattleCD_StepShake`'s x draw
   passes a stale A to `BattleCD_RandByte`; `BattleCD_LoadFxRecord`'s dead store to the channel
   block; `BattleCD_DissolveStep`'s slot-6 layout case; the paused screen is always dimmed (the
   ROM byte `$CD:3FFF` is 0).
   New stubs: the bank-$CD helpers past `$16B4` (`BattleCD_FxOpTable` `$CD:16B5`,
   `BattleCD_PlayPendingSfx` `$3B5F`, `ApuCmd18` `$3B71`, `Unk3B82`, `WaitFrames` `$3E3B`,
   `PauseWait` `$3E44`, `WaitFrameRefresh` `$3E75`, `WaitFrame` `$3E7D`, `DmaToVram` `$3E8E`,
   `RunQueuedDma` `$3EB4`, `QueueVramDma` `$3ED2`; matched in batch 2 below), bank $D1 (seven;
   gone since the merge with
   the bank-$D1 batch, item 11, which matched them) and bank $CE (`BattleCE_UnkE18E`,
   `UnkEE6E`, `UnkF066`; gone since the merge with the bank-$CE batch, item 12, which matched
   them under those names).
   Back to review (verified headers edited): `AudioFadeDispatch` (bank $C0), `BattleCF_VblankUploads`,
   `BattleCF_FrameUpdate`, `BattleCF_RemoveMarkedEnemies`, `BattleSys_SceneSetup`,
   `BattleSys_Service6`, `BattleSys_PumpFrames`, `BattleMenu_RefreshIfDirtyAndTick`,
   `BattleMenu_ChooseAttack`, `BattleMenu_UpdateCursorOverlay`, `BattleAi_RunMessage`.
   CD battle batch 2 (branch match-cd-battle2): matched `$CD:16B5`-`$CD:2A49` and
   `$CD:3B5F`-`$CD:3FFF`:
   - the helpers: `BattleCD_PlayPendingSfx`, `ApuCmd18`, `BattleCD_WaitScanline` (was
     `BattleCD_Unk3B82`: busy-waits for a scanline; its NMI argument `!BattleCD_NmiWaitLine`, was
     `!BattleCD_Unk3B82Arg`), `BattleCD_Div16`, `Mul8x16`, the sine products `BattleCD_CosMul` /
     `SinMul`, `CosMulStart` / `SinMulStart`, `HalfSinMul`, `HalfSinMul2` (on `!BattleRom_AbsSine`
     `$CE:F48E`), `BattleCD_Rotate3d`, the unreferenced `BattleCD_Mul8Unused`, `WaitFrames`,
     `PauseWait`, `WaitFrameRefresh`, `WaitFrame`, `DmaToVram`, `RunQueuedDma`, `QueueVramDma`
     (+ `QueueVramDmaL`, JSL'd from bank $D1; was the stub `BattleCD_Unk3ECE`), and
     `BattleCD_OldBuildLeftovers` (`$3F9E`-`$3FFF`:
     the tail of an older `QueueVramDma`, `$FF` fill, `!BattleRom_DebugSlowMo`);
   - the layer-effect script's opcode table `BattleCD_FxOpTable` (122 words, `$80`-`$F9`) and the
     handlers `$CD:17A9`-`$CD:2A41` (94 of the 121 handler addresses, 95 opcodes; a banner before
     the table: operand conventions, branches, the shared action variables), with their helpers
     and tables:
     `BattleCD_FxBranchBack2`, `ClampCalcAngle` (+ `CalcAngle`), `ClampX/Y`, `ClampCalcPair`
     (+ `01`), `SinMul45`, `ScrollToCalc`, `FxCircleRadii` / `FxCircleFromTable` (+ `FxCircleStep`),
     `FxDrawModel`, `FxRotateVertex` (models `BattleFx_FxModels` `$D1:EC5F`, was `!BattleRom_FxModels`), `FxWaveStoreX/Y`,
     `ScaleToCentre`, `NormaliseDiv`, `FxObjSaveOfs`, `FxRing3dTriangle`, `FxRingVertex`,
     `FxEllipseTriangle`, `FxRegToWorkTable` / `FxWorkToRegTable` with their eight handlers,
     `FxPalAnimRecs`. Groups: variables and `!Battle_FxValues` tests/branches, jumps and switches,
     sounds, palette and colour sets, layer-3 scroll (to a point, circles, drift, waves), the screen
     shake, and two "objects" (0/1: centre, depth, three angles, scale, phases, radii) drawn as
     filled triangles from 3D models, rings, beams, wedges and the PCs' positions.
   New sub-entry in a verified routine: `BattleCD_LoadLayerFx_colours` (`$CD:1004`, opcodes $B9/$D2
   jump there). Quirks recorded: opcode $F9 steps DP $40 one byte short; `BattleCD_FxOpWaveTable`
   reads an operand it overwrites; `BattleCD_ScaleToCentre`'s 16-bit multiplier path (writes
   WRDIVL, reads JOY1L); `BattleCD_Mul8x16`'s 16-bit WRMPYB store; `BattleCD_FxOpDrift` adds DP $45
   with a stale $46; `BattleCD_FxOpCircleGrow` negates only the scroll's low bytes and with k = 0
   overwrites its growing radii; opcode $CC run through the table takes its points from
   `!Battle_ActCalcResult+$98`; `BattleCD_Mul8Unused`'s double REP; opcodes $FA-$FE have no entry.
   New stubs: the handlers `$2A4A` on (`BattleCD_FxOp80`-`86`, `89`-`8B`, `90`-`A0`, by opcode),
   `BattleCD_FxAddScrollY` / `SubScrollX` / `AddScrollX` / `SubScrollY` (`$2E13`-`$2E78`, opcode
   $82's), `BattleCD_FillTriangle` `$367C`, `Unk35A5`, `Unk38E5`, `Unk3657`, `Unk3924`; bank $CE
   `UnkE000`, `UnkE7CF` (gone since the merge with item 12: opcode $B2's handler
   `BattleCD_FxOpCEE000` calls `BattleCE_CopyWindowEdges`, `BattleCD_CalcAngle` calls
   `BattleCE_CalcAngle` and names its DP arguments `!BattleCE_AngleAX`-`BY` / `!BattleCE_Angle`;
   headers edited in that merge: this batch's `BattleCD_FxOpCEE000`, `ClampCalcAngle`,
   `FxOpWedge`, `FxOpBeam` (not yet reviewed), and, back to review, bank $CE's
   `BattleCE_CopyWindowEdges` and `BattleCE_CalcAngle` (their callers named and entry states
   traced from them)). The sixteen bank-$D1 stubs this batch had (`$D1:E70A`, `EBFF`, `EDCD`,
   `EEA5`, `EEC4`, `EFD0`, `EFE3`, `F47C`, `F559`, `F5CD`, `F5F5`, `F9AF`, `FB68`, `FB72`, `FBCE`,
   `FD7E`) are gone since the merge with item 11: the handlers call the matched `BattleFx_*`
   routines (`SwapObjPalettes`, `SwayQuad`, `GrowBand`, `RampWin2`, `WaveWindowA`, `WaveWindowB`
   (+ `_ByFrame`), `RandomShake`, `StepBounce`, `SaveCalcPoints`, `CopyWin1ToWin2`, `DrawQuad`,
   `AddBoxInset`, `GrowBox`, `FillWindow`, `MirrorWin1ToWin2`). In that merge the RAM both
   batches named got one name each (the bank-$D1 batch's where it had one, e.g.
   `!BattleFx_ShakeX/Y`, `!BattleFx_BounceOut`, `!BattleFx_RecOfs`, `!BattleFx_QuadSlot`,
   `!BattleFx_BounceDir/Base`, `!BattleFx_FrameWait`, `!BattleRom_AbsSine`; this batch's
   `!Battle_DmaQueueReq` for `$CA26`); `!Battle_FxQuadX0-Y3`, `!Battle_FxTriX0-Y2` and the bounce
   words are now fields of `!BattleFx_Quads`, `!BattleFx_CalcCopy` and `!Battle_FxChanWork`.
   Also in that merge: the one-line handlers are named after their callees
   (`BattleCD_FxOpSwayQuad`, `GrowBand`, `RampWin2`, `WaveWindowA/B`, `WaveWindowBByFrame`,
   `GrowBox`, `AddBoxInset`, `RandomShake`, `SaveCalcPoints`, `CopyWin1ToWin2`,
   `MirrorWin1ToWin2`, `StepBounce`, `SwapObjPalettes`, `FillWindow`; were `FxOpD1xxxx`),
   `FxOpCallD1ECF3` / `WaitD1ECF3` are `FxOpRequestBgSet` / `WaitBgSet`, `FxOpSetupCD` is
   `FxOpSetupBounce` (it sets up `BattleFx_StepBounce`), `FxOpSetCFFF` is `FxOpSetHoldAnims`
   (`$CFFF` is `!BattleFx_HoldAnims`, was also `!Battle_ActUnkCFFF`), and the models
   `!BattleRom_FxModels` are the label `BattleFx_FxModels` (was `BattleFx_UnkTableEC5F`). Back
   to review (verified headers edited in the merge): `BattleAct_OpSetUnkCFFF`,
   `BattleAct_OpClearUnkCFFF`, `BattleSys_RunService` (bank $C1); `BattleSys_VecCD0000`,
   `BattleCD_NmiMain`, `BattleCD_LoadLayerFx`, `BattleCD_RunFxOp` (this batch's edits); and in
   bank $D1 the callees of the handlers (their Callers notes and entry hedges: `BattleFx_SwapObjPalettes`,
   `SwayQuad`, `GrowBand`, `RampWin2`, `WaveWindowA`, `WaveWindowB`, `RandomShake`, `StepBounce`,
   `SaveCalcPoints`, `CopyWin1ToWin2`, `DrawQuad`, `AddBoxInset`, `GrowBox`, `FillWindow`,
   `MirrorWin1ToWin2`), `BattleFx_Nmi` (who waits on `!BattleFx_FrameWait`), `BattleFx_FxModels`,
   `BattleFx_LoadBgSet` (its Exit), `BattleFx_AddLineOffsets` (`$0A00`) and `BattleFx_Init`
   (`!Battle_DmaQueueReq`).
   Back to review (verified headers edited in batch 2): `BattleSys_VecCD0000` (the bank banner it
   carries), `BattleCD_NmiMain` (the rename), `BattleCD_LoadLayerFx` (the sub-entry),
   `BattleCD_RunFxOp`, and in bank $C1 `EngCall_BattleMain` (Callers note: `$CD:3E78`),
   `BattleSys_PumpFrames` (PauseWait no longer unmatched) and `BattleSys_RunService` (its list of
   unmatched addresses each service reaches: none since the merge with item 11, which
   matched the last two, `$D1:ECF3` and `$D1:F67A`).
   CD battle batch 3 (branch match-cd-battle3): matched `$CD:2A4A`-`$CD:3B5E`, so bank $CD's
   `$CD:0000`-`$CD:3FFF` is now matched in full:
   - script opcode $80 (`BattleCD_FxOpMisc`, was the stub `BattleCD_FxOp80`) with its 29-word
     `BattleCD_FxMiscTable` and sub-handlers `BattleCD_FxMisc*` (colour bands `!Battle_FxBandsBlue`/
     `Green`/`Red` in `!BattleFx_UnkBB05`, fading by `!Battle_UnkCD04`; object 0's triangle presets;
     OAM entries 4-19 from `!Battle_FxSprTemplate`; a sine into `!Battle_WaveOffsets` for
     `BattleFx_AddLineOffsets`; the `!BattleFx_WaveBaseX` words `BattleFx_WaveWindowA` reads,
     zeroed and lowered at random through `!BattleFx_WaveMoving`; the bob steps
     `!BattleRom_FxBobSteps`; and JSLs into bank $D1);
   - the handlers of opcodes $81-$86, $89-$8B and $90-$A0, renamed by what they do (was
     `BattleCD_FxOpNN`): period, scroll step (+ `BattleCD_FxScrollDirTable` and its eight
     helpers, four of them the old stubs `BattleCD_FxAddScrollY` / `SubScrollX` / `AddScrollX` /
     `SubScrollY`), loops (`!Battle_FxLoopPtr` / `LoopCount`, the page loop on the channel's page
     base), call / return (`!Battle_FxReturnPtr`), mosaic, the window and colour-math registers
     (TM/TS/TMW/TSW and CGADSUB masked by `!BattleFx_UnkCD46`), COLDATA steps, the window shapes
     ($89-$8B) and the half-plane window ($97, `BattleCD_FxOpHalfPlane`, with
     `BattleCD_FxLineDeltas` and `!BattleRom_HalfPlaneEdge`);
   - the window shapes: `BattleCD_FxDrawShape` / `BattleCD_FxShapeTable` (six kinds), the circle
     half widths `BattleCD_FxCircleHalfWidths` (`!Battle_FxHalfWidths`), the builders
     `BattleCD_FxBuildCircle` / `BuildDome` / `BuildWide`, the copies `BattleCD_FxCopyShape` (was
     `BattleCD_Unk35A5`) / `CopyShapeTall` / `CopyShapeDome` / `CopyShapeHanging` and
     `BattleCD_FxCopyLines` (`$CD:3616`, which runs `BattleCE_RunCopyWords`);
   - the filled triangles: `BattleCD_FillObjTriangle` (was `BattleCD_Unk3657`) falling into
     `BattleCD_FillTriangle`, `BattleCD_FillHangingTriangle` (was `BattleCD_Unk3924`) with
     `BattleCD_AimWinTopFill`, `BattleCD_WinLineBases`, `BattleCD_AimWinLine` and its JSL entry
     `BattleCD_AimWinLineL` (was `BattleCD_Unk38B2`), `BattleCD_EdgeSlope` (was
     `BattleCD_Unk38E5`; DP `!BattleCD_SlopeTo/From/Div`, were `SlopeEndY/StartY/Dx`).
   Also renamed: the opcode $A1/$B8 handlers `BattleCD_FxOpFillObjTriangle` /
   `BattleCD_FxOpFillHangingTriangle` (were `FxOp3657` / `FxOp3924`). Found: `!BattleFx_UnkCD46` is
   a layer mask; `!Battle_FxObjUnkD1` is the shape kind; `!Battle_FxChanReg`'s two bytes are opcode
   $97's angles; every opcode handler returns M=1, X=0. Quirks recorded: the colour bands' dead
   TXA; random marks past the 212 `!BattleFx_WaveMoving` words; the copies' end tests after the
   copy (a hanging shape with centre y 0 would run through the bank); the bottom cut of
   `BattleCD_FxCopyShape` reckoned before the top cut; opcode $97's dead TDC/TAX; the triangles'
   word stores to WMDATA-1 (APU port 3) and carry chaining, as in bank $D1. Open: whether any
   script uses opcode $80 sub-ops past $1C or shape kinds past 5; B after opcode $97 (and so a
   page byte right after it or after $88); who fills `!Battle_FxSprTemplate`, who reads
   `!Battle_Unk5D9A`, `!Battle_UnkC151`-`C157`, the colour bands and `!Battle_FxWaveTable`
   (which HDMA channels); what DP $20 (`!BattleCD_TriUnk20`) is for (zeroed, never read here).
   Back to review (verified headers edited in batch 3): `BattleSys_VecCD0000` (the bank
   banner), `BattleCD_StepFxChannels`, `BattleCD_RunFxScript`, `BattleCD_RunFxOp`,
   `BattleCD_FxOpTable` (the banner before it), `BattleCD_FxOpWedge`, `FxOpDrift`,
   `FxOpScrollYToEnemy`, `FxOpSetObjD1`, `FxOpFillHangingTriangle` (was `FxOp3924`),
   `FxOpWindowBand`, `FxOpFillTriangle`, `FxOpTriCentre`, `FxOpFillObjTriangle` (was `FxOp3657`);
   in bank $CE `BattleCE_CopyWindowEdges` (the bank banner), `CopyWordsToLines`, `RunCopyWords`,
   `DrawHalfPlane`; in bank $D1 `BattleFx_WhitenRows`, `MoveBgRowsUp`, `LoadBgRows2To4`,
   `WaveWindowA`, `AddLineOffsets`, `DrawQuad`, `RasterQuad` (the rename of `BattleCD_Unk38B2`).

11. Bank $D1 code (branch match-d1-battle; new file `asm/bankD1/bankD1.asm`): `$D1:E70A`-`$D1:FFFF`
   is matched (the code `$E70A`-`$FEF3` with its tables, and the `$FF` fill `BankD1_EndFill`).
   It is code that works with the battle code in bank $CD (`BattleFx_*`): the battle's NMI and
   IRQ handlers `BattleFx_Nmi` / `BattleFx_Irq` (pause on Start, the frame count, a debug slow
   motion gated by `$CD:3FFF`, 0 in this ROM; `BattleFx_RestoreMathRegs`), the second NMI
   handler `BattleFx_NmiAlt` (installed by `$CD:041E`), the set-up `BattleFx_Init` (vector
   `$CD:0000`), palette moves (`BattleFx_SwapObjPalettes`, `WhitenRows`, `MoveBgRowsUp`,
   `LoadBgRows2To4`, `HoldAnimsTick`), the gradient that follows battler 3's HP
   (`BattleFx_HpGradientTick`), background set loads (`BattleFx_LoadBgSet`), the window-table
   shapes (bands, boxes, waves, fills, copies, and the quad rasteriser `BattleFx_DrawQuad` /
   `RasterQuad`), random shakes and bounces, and opcode $80's settings (`BattleFx_Op80*`).
   New RAM names (`!BattleFx_*`, many `Unk` ones only zeroed or set by `BattleFx_Init`) are in
   their own block of `ram_battle.inc`; constants likewise in `constants_battle.inc`.
   Merged with the bank-$CD batch (item 10): the calls both ways use the matched labels
   (`BattleCD_UploadCgram`, `ClearTextGfxL`, `ScrollStepL`, `NmiDispatch`, `InitHdmaDataL`;
   `BattleFx_Init`, `Op80Dispatch`, `NmiAlt`, `UploadMapBlock`, `HpGradientTick`, `LoadBgSet`,
   `HoldAnimsTick`); the stubs left are `BattleCD_Unk38B2` (`$CD:38B2`), `BattleCD_Unk3ECE`
   (`$CD:3ECE`) and `BattleCE_UnkEE6E` (since the merge with CD battle batch 2, item 10,
   `$CD:3ECE` is the matched `BattleCD_QueueVramDmaL`; `BattleCD_Unk38B2` is matched by CD battle
   batch 3 as `BattleCD_AimWinLineL`;
   `BattleCE_UnkEE6E` is matched by item 12). The bytes both banks use got one name each (the
   bank-$CD names where they said more, e.g. `!Battle_Paused`, `!Battle_MsgTimer`,
   `!Battle_ShakeXOn`..., the bank-$D1 ones otherwise, e.g. `!BattleFx_CeSetWant`,
   `!BattleFx_GradStart`); opcode $80's groups are the screen shake (`!Battle_ShakeXOn` on) and
   palette-animation records 8/9 (`!Battle_PalAnimRecs89`), and `$D1:EE99` is the message sound
   table (`BattleFx_MsgSfx`, was `!BattleRom_MsgSfx`). Most remaining callers were then unmatched
   bank-$CD script command handlers (`$CD:17A9` on: one-line JSL, RTS; matched since by CD
   battle batch 2, item 10), so entry states are read from the routines and hedged (B = 0 is assumed where a TAX takes it in). Quirks recorded: the carry chaining (no CLC) in
   `BattleFx_AddLineOffsets` and `BattleFx_RandomByte`; the second store of 9 in `BattleFx_Init`;
   the dead `LDA` in `BattleFx_GrowBox`; `BattleFx_EdgeSlope` not checking a zero line count.
   Open: which HDMA channels read the window tables and `!BattleFx_GradHdmaA-D`; the
   `BattleCE_UnkEE6E` sets; the meaning of the `!BattleFx_Unk*` bytes, `!Battle_Unk2A21` (who
   sets it), `$7E:E500` and `$7E:0A00` (who fills them: since CD battle batch 3, item 10, script
   opcode $80's sub-ops $15/$16 and $0C), and the table `BattleFx_UnkTableEC5F`
   (read by bank $CD past `$16B4` only; since CD battle batch 2 `BattleFx_FxModels`, the
   layer-effect objects' 3D models). Bank $CD is matched in full since CD battle batch 3: its
   callers' entry states can replace the remaining hedges here. `$D1:0000`-`$D1:E709` is data, still ROM bytes.
   Headers edited (back to review): Field_RefreshHdmaLong and MusicCueDispatch (their Callers
   notes now name `BattleFx_NmiAlt` / `BattleFx_Init`); in the merge with bank $CD also these
   bank-$CD headers (the bank-$D1 code named as matched, or the shared bytes renamed):
   BattleSys_VecCD0000, BattleCD_EnterBattle, ActOp80, GetMsgTime, ShowMessage, ClearTextGfxL,
   ShowText, ShowEnemyInfo, ShowTargetInfo, ShowTechInfo, ExitBattle, WaitNmiAck, FrameTick,
   StartCloseWipe, StepWipe, NmiUploadText, ScrollFxBg3, ScrollWaves, NmiMain, UploadCgram,
   NmiSetup, TickCDC9, ScrollStepL, NmiDispatch, InitHdmaDataL, LayerFx84, RestorePalRows,
   LoadLayerFx.

12. Bank $CE code (branch match-ce-battle; new file `asm/bankCE/bankCE.asm`): `$CE:E000`-`$CE:EF10`
   and `$CE:F066`-`$CE:F0E5` are matched (code, with the wave table `BattleCE_WaveTable` inside).
   All of it is called by JSL from banks $CD and $D1 only: `BattleCE_CopyWindowEdges` (opcode $B2:
   one window's pair copied from the other window table, 216 lines), `BattleCE_UnkE18E` (the layer-2
   wave: a sliding window of `BattleCE_WaveTable` into `!BattleCE_Bg2WaveLines` `$7E:CD47`, which
   channel 2's tables point at with `!Battle_Unk2A21` bit 0), `BattleCE_CopyWordsToLines` (256
   unrolled LDA/STA pairs entered at `$E7C7` - 6n) with its JSL entry `BattleCE_RunCopyWords` (JMP
   through DP $4B), `BattleCE_CalcAngle` (opcode $CC: Battle_CalcAngle with snapped points and
   rounding), `BattleCE_PresetWinEdges` and `BattleCE_DrawHalfPlane` (opcode $97: the half of the
   screen on one side of a line through the centre, point-symmetric), `BattleCE_UnkEE6E` (loads an
   HDMA set: the first 30 bytes of the nine tables at `!Battle_HdmaTables` from
   `!BattleRom_HdmaSetOfs` / `!BattleRom_HdmaSetRecs`) and `BattleCE_UnkF066` (parks sprites 4-127).
   The three stub names are kept (matched bank-$CD code calls them by those names; better names
   would be e.g. `BattleCE_StepBg2Wave`, `BattleCE_LoadHdmaSet`, `BattleCE_ParkSprites`, for a
   change that may edit bank $CD's JSL lines). Entry states of the two entries called from
   unmatched bank-$CD code (`$CD:2A4A`-`$CD:3B5E`: RunCopyWords, DrawHalfPlane) are read from the
   routines and hedged (B = 0 traced for DrawHalfPlane's TAY to `$CD:30FC`); since the merge with
   CD battle batch 2 (item 10) CopyWindowEdges' and CalcAngle's are traced from their matched
   callers `BattleCD_FxOpCEE000` (opcode $B2) and `BattleCD_CalcAngle` (opcode $CC's handler).
   Quirks recorded: CalcAngle's snap changes the difference by 256 when the second point wraps
   below 0, and its index runs past a row for differences of 252 or more;
   DrawHalfPlane's STZ that clears the right edges of lines 0 on when the line ends at x = 0, and
   angle 0 leaving the upper half's left edges unwritten; CopyWindowEdges' 8-bit X wraps for script
   bytes over $4A. Headers edited (back to review): Rom_AngleTable (bank $C0, the `$CE:E85B` reader
   named), BattleSys_VecCD0000 (bank $CD's file banner), BattleCD_StepWipe (the call and its Exit
   line), BattleFx_ReloadCeSet (what the sets are). Open (the bank-$CD callers, opcode $97's
   `BattleCD_FxOpHalfPlane` and the word copier's `BattleCD_FxCopyLines`, are matched since CD
   battle batch 3, item 10, and the entry states here read from them): what opcode $B2's byte
   and the copier's counts are in practice;
   which sets `!BattleFx_CeSetBase` picks (0, 2, 8, $0C, $0E); who sets `!Battle_Unk2A21` bit 0.
   Not matched in $CE: the data, i.e. `$CE:0000`-`$CE:DFFF` (scripts, object records),
   `$CE:EF11`-`$CE:F065` (`!BattleRom_MsgStrings`, the dissolve and layer-effect tables read by
   bank $CD, still defines) and `$CE:F0E6`-`$CE:FFFF` (opcode $80's tables, `$CE:F24E` /
   `$CE:F28E` / `$CE:F58E` and the HDMA tables, `!BattleRom_AbsSine`). These could become labelled
   data once bank $CD's readers can use labels.

13. Bank $C6 code (branch match-ff-tail; new file `asm/bankC6/bankC6.asm`): `$C6:E000`-`$C6:EE42`
   is matched (code, with two small tables inside), and the $00 fill after it
   (`BankC6_CodeEndFill`, `$EE43`-`$EFFF`); the rest of the bank is data, left as ROM bytes. Two
   entries are JSL targets from bank $C2 and keep their stub names because verified bank-$C2 code
   calls them so: `BankC6_UnkE74E` (tile outside a rectangle: bits left/right/above/below; better
   `C6Scene_TileOutsideRect`) and `BankC6_UnkE797` (object A's landing check by Loc_Id $1F0-$1F7
   rectangles; better `C6Scene_ObjANoLandHere`). All the others are scene script routines called
   by op $4E (C2Script_CallLong): their sites were found by unpacking the scene scripts
   (C2SceneRom_ScriptPacks entries 0-7 with a Python copy of Decomp_ToWram's format) and
   searching for `$4E lo hi $C6`; each header cites "pack n +$offset". Matched: the HDMA set-ups
   `C6Scene_Win1HdmaOn` (+ byte-identical copies `Win1HdmaOnB`/`C`), `Win2HdmaOn` (+ copy
   `Win2HdmaOnB`); the window shapes built with WinFx_BuildCircle and reshaped in place
   (`C6Scene_Win1/Win2EllipseStep` + `EllipseBuild`: the circle squeezed to half height;
   `C6Scene_Win1/Win2CapsuleStep` + `CapsuleBuild`: the circle cut at its middle line and stretched)
   and the WH1 wipe through WinFx_StepWipe (`C6Scene_WipeWinInit`/`WipeWinStep`); the COLDATA
   gradients (`C6Scene_FadeGradInit`/`FadeGradStep`, a white fade that climbs the screen;
   `C6Scene_Grad2Init`/`Grad2Ramp`); a BG1 vertical line wave (`C6Scene_Bg1WaveInit`/`Bg1WaveStep`,
   HDMA channel 3); the unpacks `C6Scene_UnpackObjPackA/B`, `UnpackPalPackA/B`; the moves
   `C6Scene_Bg3Accel`, `AddYAccel`, `PlaceOnEdgeRandom`, `PlaceInViewRandom`, `NudgeRandomDir`,
   the unreferenced `Bg2VNudge`; the flag routines `GetFlagF2Bits`, `ClearUnk7F0062`,
   `Set/ClearUnk7F01ED`, `SetUnk7F00CD`, `ClearUnk7F01F5Bit0`; and pack 0's Mode 7 view:
   `C6Scene_MapPicture` with `C6Scene_MapCellPixels` (the map picture as C2Scene_MapDrawPixels
   draws it, whole, without the colour filter) and the per-line Mode 7 matrix
   `C6Scene_PerspInit`/`PerspStep` (HDMA channels 2-5 to M7A-M7D), the quadrant fills
   `C6Scene_PerspQuad0-3` with `C6Scene_PerspTail`, `C6Scene_PerspDivide`, the tables
   `C6Scene_PerspQuadrants` / `C6Scene_PerspTiltSteps`, and `C6Scene_AddAngle`; the task fields
   are the struct `C6Scene_PerspTask`. New names are `C6Scene_*` (defines in their own blocks of
   `constants_menu.inc` / `ram_menu.inc`; `!BBAD_WH1` and `!BBAD_BG1VOFS` in hardware.inc), so they
   cannot collide with the bank-$C2 branches' `C2Scene_*` names. Quirks recorded: the missing CLCs
   before the line-address ADCs (carry from an ASL, 0 on screen) and in PlaceInViewRandom (as
   C2Scene_PlaceBelowView); the ellipse loops' 16-bit count (r below 2 runs them 65,536 times) and
   the capsule's unchecked MVN counts (n below 2); Grad2Init's MVNs one byte long; Bg1WaveStep's
   -256 at sine index $200; PerspInit's HDMA words overwritten by the step it falls into; the
   tail's unused `.Unk2E` read; BankC6_UnkE797's unchecked Loc_Id; PerspStep's STA.w to C2Tmp_00.
   Entry states come from op $4E (M=1, X=0) inside C2Scene_TaskRunAll (DP=$0000, DB=$00); the
   script values (.Var22/.Var24 counts and radii) were not traced. Survey note: the earlier survey put
   the code at `$C6:E000`-`$EE3F` with 2,673 code bytes; it ends at `$EE42` (3,619 matched), and
   the re-survey of 2026-10-14 (see "Code survey" below) says so. Headers edited: none verified in bank $C6 (all
   new); the generated Callers blocks of Trig_Cos1024, C2Scene_Unk2273, BankC3_Entry0000 and
   Audio_DriverInit changed (not hashed). Open: what the scenes are (pack 0's Mode 7 flight, pack
   4's window and gradient effects), who reads `!C6Scene_Unk7F0062`, `!C2Scene_Unk7F00CD`, the
   `C6Scene_PerspTiltSteps` values' origin, and what `.Unk2E` was meant for. Not matched in $C6:
   the data, `$C6:0000`-`$DFFF` and `$C6:F000`-`$FFFF` (packs, headers, the tables the bank-$C2
   code reads by define).
14. Lint: the SIZE rule now checks combined claims `Name (N bytes with A and B, $XXXX–$YYYY)`
    (wrapped or not; 39 in the tree): N is the range's size, the range starts at the routine, ends
    on a row boundary of the layout, and every row inside is named or a `header: see` sub-entry.
    One was wrong: `Menu_CfgTextThread` said 149 bytes for `$F9B2–$FA48` (151; the range was
    right). Re-review needed (verified header edited): `Menu_CfgTextThread`.
15. The SPC700 sound driver (branch match-c7-spc700; new files `asm/spc700/spc700.inc`,
    `driver.asm` and `unmatched.asm`, included from `asm/main.asm`; `tools/spc700.py`). The plan,
    then the first batch.

    **(a) What is code.** Boot block 0 (`Audio_BootBlockPtrs`) is the length word $1BEF at
    `$C7:24C3` and the program `$C7:24C5`-`$40B3`, sent to ARAM `$0200`-`$1DEE`; the IPL ROM
    jumps to `$0200`. ROM = ARAM + $22C5. Traced from `$0200`, the six dispatch tables and the
    two pushed return addresses (`$0768`, `$1029`) (`spc700.DISPATCH_TABLES` / `DRIVER_ENTRIES`;
    the driver dispatches with PUSH, PUSH, RET only, there is no `JMP (abs+X)`), it splits into:

    | ARAM | ROM | | Bytes | Content |
    |---|---|---|---|---|
    | `$0200`-`$1543` | `$C7:24C5`-`$3808` | code | 4,932 | start, main loop, track stepping, commands, transfers, echo |
    | `$1544`-`$1721` | `$C7:3809`-`$39E6` | data | 478 | `$1544` transfer modes (8 words, APUIO1 & 7, read at `$105D`); `$1554` sequence commands $C4-$FF (60 words, `$0743`), `$15CC` their operand counts (60 bytes), `$1608` their second handlers (60 words, 0 = none); `$1680` CPU commands $10-$1F, `$16A0` run-first handlers, `$16C0` commands $80-$8F/$F0-$FF (16 + 16 + 32 words); `$1700` the 17 shadowed DSP registers, `$1711` their sources |
    | `$1722`-`$1D6C` | `$C7:39E7`-`$4031` | code | 1,611 | sequence command handlers, helpers |
    | `$1D6D`-`$1DEE` | `$C7:4032`-`$40B3` | data | 130 | `$1D6D` pitch table (13 words, read at `$06C9`), tables read at `$1D87+Y` (`$057A`), `$1D92+Y` (`$1844`; FIR sets, by their look) and `$1DB3+Y` (`$051C`); `$1DC2` the built-in BRR sample (directory entry $10, set by Spc_Start; `$1DCB` is rewritten each pass by `$0B5C`) |

    The trace reaches every byte of the code ranges and none of the data ranges (6,543 + 608 =
    7,151 bytes; `tools/test_spc700.py` pins it). Four branches land inside other instructions
    (`$03BA`, `$0DB2`, `$129B`, `$192C`: a skipped `mov a,#imm` whose operand is the target
    opcode). The other boot blocks are data: block 1 (`$C7:4309` -> `$2F00`, $1800 bytes) starts
    with the sound-effect table (4 bytes per effect: two track pointers, read by Spc_StartSfx),
    block 2 (`$40B4` -> `$4700`) is BRR sample blocks, 3-5 the directory and parameter words.
    ARAM as the driver uses it: direct page `$00`-`$EF` (P=0 throughout; tracks indexed X = track
    x 2), page 1 (`$0150`-`$018F` per track, the stack from `$01FF`), the driver `$0200`-`$1DEE`,
    directory `$1E00`, ParamA/B `$1F00`/`$1F80`, song `$2000`, effects `$2F00`, samples from
    `$4700`, the echo buffer below `$F100`, probably (`!Audio_EchoTopPage`), work area `$F100`-`$F7FF` (group volumes
    `$F160`, the command queue `$F172`-`$F1B1`, per-track arrays `$F200`-`$F5xx`), and
    `$F800`-`$FF8F`, where Spc_SaveSong keeps a song aside (`$13A9`).

    **(b) Assembly.** asar's `arch spc700` with `base`: `%SpcOrg(aram)` in driver.asm does `base
    off`, `org` the ROM address, `base aram`, so labels take ARAM values (the symbol file lists
    them as `00:0200`, below $8000 in bank 0, which progress, xref and tables already drop as not
    ROM) while the bytes and asar's address-to-line map use ROM addresses. `.b`/`.w` on every
    direct-page and absolute operand. asar's syntax: `(x+)`, `(dp+x)`, `(dp)+y`, `or1 c,!m.b`
    (not `/m.b`), `bbs.b dp.bit,label`; the tree assembles with left-to-right math, so expressions
    in defines need parentheses. Unmatched driver bytes stay ROM bytes (not emitted); the length
    word too until the last batch (then `dw` of the block's labels). Prototype: the whole block,
    printed by `python3 tools/spc700.py`, reassembles to the ROM (`--check`), and `make gate`
    passes with the batch below.

    **(c) Tooling.** Done: `tools/spc700.py` (all 256 opcodes; recursive descent from the known
    entries or `--linear`; labelled asar source; `--check` reassembles and compares;
    `tools/disasm.py --spc700` runs it), `tools/test_spc700.py` in `make test-tools` (every opcode
    against asar, the code/data split, the round trip); xref and tables leave the lines of
    `asm/spc700/` out of the 65816 instruction starts (otherwise SPC700 instructions would count as
    65816 ones in xref's verdicts and in code_survey's opcode statistics; the survey's numbers are
    unchanged). The review path (added after the maintainer's
    go-ahead): `tools/progress.py` writes `symbols/spc700_functions.csv` (generated, untracked:
    ARAM and ROM range, size, kind, status, source_hash) and prints a separate SPC700 line
    (`"spc700"` in progress.json), leaving the 65816 figure, its denominator and code_survey as
    they were; `tools/lint_spc700.py` (run by the lint) applies ADDR, CALL, CONST, WIDTH, OPCODE,
    PLUMB, HEADER and SIZE, STATE (the Entry line states P) for DPDB, and checks that each header
    names every CALL/JMP/PCALL site the driver trace finds; review rows in `symbols/reviews/`
    verify SPC700 routines by name and source_hash like the 65816 ones
    (`tools/validate_functions.py` checks both tables); `tools/test_lint_spc700.py` tests the
    rules. Still open: a generated Callers block, a split of code_survey's `spc700_bytes` (7,153
    with the length word) into code 6,543 / data 608, and a `make spc-draft` that names operands
    from `spc700.inc` the way draft.py does (now `tools/spc700.py START END` prints labelled
    source with raw operands).

    **(d) Header convention** (driver.asm's banner and STYLE.md, "SPC700 (the sound driver)"):
    title `$ARAM — Name (N bytes, $XXXX–$YYYY; ROM
    $C7:xxxx–$yyyy)`; `Entry:`/`Exit:` state P (direct page $00xx or $01xx), A, X, Y (YA for word
    results), SP when moved, and the PSW flags callers branch on; `DSP:` the S-DSP registers
    written; `Ports:` what goes through CPUIO0-3 and its 65816 counterpart (Audio_*);
    `Callers note:` hand-written until a generator exists; `Callees:`. Names: `!SPC_*` I/O
    registers, `!DSP_*` DSP registers, `!Spc_*` RAM, `!SpcCmd_*` / `!SpcSong_*` values, `Spc_*`
    labels; data and code not matched yet are label-only in `asm/spc700/unmatched.asm`.

    **Matched (first batch, 1,022 bytes):** `$0200`-`$0376` (`Spc_Start`, `Spc_MainLoop`),
    `$07A3`-`$07AE` (`Spc_WriteDsp`, `Spc_ClearPorts01`) and `$0B96`-`$0E10` (the CPU-port side:
    `Spc_PollCommand` / `Spc_RunCommand`, the song commands `Spc_CmdSong14`/`10`/`15`/`11`,
    `Spc_StartSong`, `Spc_InitTrack`, `Spc_CmdSongCheck`, the effect commands
    `Spc_CmdSfx18`/`19`, `Spc_StartSfx`, `Spc_RunHighCommand`). What it settles from item 5's
    open list: a song command's APUIO1 answer is the song, or $FF when that song is already
    playing (Spc_CmdSongCheck; then the 65816 skips the load); `!Audio_ResetKick0/1` is command
    $FF with Arg0 $F0, which returns the driver to the IPL ROM (`$12CC`); $10/$11 start the
    header's first or second set of 8 track pointers, $14/$15 first keep the playing song aside
    (Spc_SaveSong) and a later request for it resumes it with a fade-in; $18/$19 start effect
    (Arg0) on voices 7-6 / 5-4, Arg1 into each track's `$F281`; $FC sets the echo delay, $FD writes
    DSP register Arg0 = Arg1, $FE takes the transfers; $12/$13/$16/$17 and $1A-$1F run a bare RET
    and are never echoed. Does the 65816 send $1A-$1F (Audio_CmdSend would pass them on)? Every
    store to `!Audio_CmdId` / `!Sfx_Command` in matched code was read (banks $C0, $C1, $C2, $C3,
    $CD; $C7's own `Audio_CmdSongAlias` writes $10): the constant ones are $10, $11, $14, $18,
    $19, $70, $80, $81, $82, $83, $86, $F2 (`!C3_SndPause`), $F3 and $F5
    (`!BattleCD_ApuCmdPause`), none in $1A-$1F; the battle sound opcodes $78-$7B send $18/$19 only; Menu_ and
    C2Scene_ senders use named constants of the same set. Three senders take the id from script
    data and were not scanned (the scripts are packed or need their own parsers): event opcode
    $EC (`Evt_OpEC_SoundCmd`, from `!Evt_Data`), scene op $4B (`C2Script_SoundCmd`, through
    `C2Scene_QueueSoundCmd`) and the `$C3` module's script op 6 (`C3_RunScript .op_driver`). So
    no code path sends $1A-$1F; whether any script byte does is open (headers unchanged). Each
    pass the driver writes APUIO0 = 0, APUIO1 = the song's fade steps left, APUIO2/3 status bits
    (unless `!Spc_Flags88` bit 7 is set: command $FF with Arg0 = 1 and Arg1 nonzero sets it);
    commands other than $10-$17 and $FE that arrive while tracks are stepped are queued (16) and run
    after the pass. Open in
    the batch: most direct-page bytes are `Unk` names with what was observed (`!Spc_Unk24`/`25`,
    `!Spc_Flags87`/`88`, the `$F2xx`-`$F4xx` track arrays); the callees are stubs.

    **Second batch (branch match-c7-spc700-2, 1,342 bytes):** `$0E11`-`$12DD`, every handler of
    Spc_CmdTable80 and the transfer receiver, and the command queue `$0892`-`$0902`
    (`Spc_QueueCommand`, `Spc_RunQueue`). The commands: $80-$83 fade the three `!Spc_GroupVol`
    volumes (Arg0 steps, Arg1 target; `Spc_StartFade`, `Spc_FadeDelta`); $86 / $87 fade a signed
    tempo / song pitch adjustment ($85 both, probably: their readers `$0377` and `$0A78` are not
    matched), $89 the effect pitch of tracks 14-15; $88 sets `!Spc_SongCond`, which sequence
    commands compare to choose a branch; $8E doubles the echo volume and sets MVOL $7F (else $40);
    $F0 / $F1 / $F2 stop all / the song / one effect group (tracks pointed at a lone sequence
    command $EB at `$1DC1`); $F3 mono; $F4 / $F8 / $F9 set / clear / add `!Spc_Mute` voices; $F5
    pause (envelopes held through GAIN, volumes 0, `!Spc_Flags87` bit 4) and resume; $F6 a fast
    timer 0 (125 us passes, tempo bypassed); $FF reset to the IPL ROM (Arg0 $F0) or the port
    report flag (Arg0 1); $84, $8A-$8D, $8F, $F7, $FA, $FB do nothing. The transfers (`$FE` and
    every song load): after the command, a header per block (address in APUIO2/3, mode in
    APUIO1, `$E0` ends the load), then steps until a value with bit 7 set; `$FF` with APUIO1 `$F0`
    resets even mid-transfer. Modes: 1 bytes, 2 words, 3 triples, 5 triples while the song keeps
    playing (`$0415` runs on timer 0), 7 moves; 0, 4, 6 and any block below `$1E00` are taken and
    dropped (the driver protects itself), a block in `$2Fxx` first stops both effect groups.
    Quirks: the stores of modes 2, 3 and 5 and the copies of mode 7 rewrite their own operands
    (labels `.store1`-`3`, `.page_load` ...); mode 3/5 echo a step after reading APUIO1 but before
    APUIO2/3 (a timing assumption); `Spc_XferNextStep` returns C=0 by branching into the operand
    of `mov y,#$60` (`clrc`); command $81 marks voices 0-6 (`$7F`) for a volume rewrite, leaving
    voice 7 out; a full command queue keeps overwriting its last entry. Mode 5 on the 65816 side:
    only `Audio_CmdSwapSample` ($71) and `Audio_UploadBlock2F00` when `Audio_CmdId` is $70 send it
    (the same routine sends mode 3 inside a song load, from `Audio_SendSongData`); every other
    header uses `!Audio_XferWords`, `!Audio_XferTriples` or `!Audio_XferMove`, and mode 1 is never
    sent. Verified headers edited (back to review): `Spc_Start` (the banner's matched list, now
    pointing at `symbols/spc700_functions.csv`), `Spc_MainLoop` and `Spc_StartSong` (callees
    renamed from `Spc_Unk0892`/`08CD`/`100E`, `!Spc_UnkD2` -> `!Spc_SongCond`), `Spc_WriteDsp`,
    `Spc_ClearPorts01` and `Spc_PollCommand` (callers and callee names).

    For the next edit of these approved headers (review round 173 nits not yet applied; the
    fourth batch applied the `Spc_MainLoop`, `Spc_StepSongFades` and `Spc_CmdFadeSong` ones):
    `Spc_TrackEffects`: the vibrato offset uses the high byte of phase x 2 (the ASL/ROL of the
    phase word), not the phase's high byte x 2 / 256; `Spc_AnimateBuiltin`: skipped while
    !Spc_Flags87 bit 4 pauses Spc_MainLoop, and at the last step only byte 1's high nibble ($70)
    is flipped; `Spc_CmdTimer`: 125 us is timer 0's tick, not a pass; `Spc_StepTracks`: a voice is
    cleared from !Spc_Unk24 (25) even when an effect holds it (only the key-off is skipped);
    `Spc_TrackSlides`: a pitch slide with 0 steps runs as 256 (the count wraps); `Spc_CmdMono`'s
    second sentence is one overlong line.

    **Fourth batch (branch match-c7-spc700-4): the rest of the driver.** `$12DE`-`$1543` (echo:
    `Spc_SetEchoDelay`, `Spc_StartEchoChange`, `Spc_WaitTimer1`, `Spc_CountTimer1`,
    `Spc_EchoWritesOn`, `Spc_CmdSetEchoDelay`; `Spc_SaveSong` / `Spc_RestoreSong`;
    `Spc_ReportLevels`; `Spc_StepGroupFades`; `Spc_AddSigned`; `Spc_CmdWriteDsp`), the sequence
    command handlers `$1722`-`$1D6C` (every command $C4-$FF and its look-ahead handler), the tables
    `$1544`-`$1721` and `$1D6D`-`$1DEE`, and the length word at `$C7:24C3` (`dw Spc_DriverEnd -
    !AudioAram_Driver`): the whole block is emitted from source and `asm/spc700/unmatched.asm` is
    gone. Findings: the sequence commands, by number: $C4/$C5 volume / slide, $C6/$C7 pan / slide
    (song tracks), $C8 pitch slide, $C9/$CA vibrato on / off, $CB/$CC tremolo, $CD/$CE pan LFO,
    $CF noise clock, $D0-$D5 noise, pitch modulation and echo on / off, $D6-$D8 octave, $D9/$DA
    transpose, $DB fine tune, $DC sample, $DD-$E1 ADSR fields, $E2/$E3 loop start / end (four
    slots per track: `!Spc_TrackUnk27` is the loop stack's slot), $E4/$E6 legato-like flags ($E5,
    $E7 null), $E8 next length, $E9/$EA continue with an effect's track, $EB-$EF/$FE/$FF end of
    track, $F0/$F1 tempo, $F2/$F3 echo volume, $F4 song volume (`!Spc_Unk4D`), $F5 a jump on a
    loop pass, $F6 jump, $F7 EFB, $F8 FIR set (`Spc_FirSets`), $F9 a marker shown in CPUIO2's low
    nibble, $FA a branch on `!Spc_SongCond` (command $88: the game steers the song), $FB/$FC drum
    mode, $FD the track's volume scale. Jump addresses are relative to the song's origin
    (`!Spc_Scratch00` holds the move for the whole song). The port report (command $FF, Arg0 1) is
    a level meter of four voices at a time, probably. Quirks: `Spc_LfoStart` branches into the
    operand of `mov y,#$DD` (`mov a,y`) and takes Z from its caller's load; `Spc_SeqPanFade` on an
    effect track stores the steps but no step; `Spc_EndTrack` clears the song's `!Spc_Unk5E` for an
    effect track; `Spc_SeqEfbFade` has no same-value exit; `Spc_UpdateNoise` never gives effect
    voice 0 noise; effect voices 6 and 4 never get pitch modulation; the pitch table's 13th word
    is never read. The per-track defines named by address (`!Spc_TrackF240` ...) keep their names
    (not every routine using them was edited). Verified headers edited (back to review): those
    that named the stubs now matched or called "unmatched" code now matched: `Spc_Start` (banner),
    `Spc_MainLoop`, `Spc_LivePass`, `Spc_TrackStep`, `Spc_RunSeqCommand`, `Spc_StepSongFades`,
    `Spc_WriteVoice`, `Spc_WriteDsp`, `Spc_QueueCommand`, `Spc_RunQueue`, `Spc_StartSong`,
    `Spc_CmdFadeSong`, `Spc_FadeDelta`, `Spc_CmdStopSong`, `Spc_CmdStopSfx`, `Spc_StopSfxB`,
    `Spc_XferReceive`, `Spc_XferHeader`, `Spc_CmdControl`.

    **What is left of the SPC700 track:** review; renaming the address-named per-track defines at
    the next edit of every routine that uses them; splitting `code_survey`'s `spc700_bytes` (7,153)
    into code 6,543 / data 608; a generated Callers block for SPC700 headers; and the verified
    bankC7 headers that still say the SPC700 side is not traced (`bankC7.asm`'s banner,
    Audio_Boot, Audio_StartSong), to fix at their next edit.

## Code survey

Re-run 2026-10-14 (`python3 tools/code_survey.py --write`) once all known 65816 code was
matched. The method did not change (data rows, the `*OldBuildLeftovers` among them, were already
kept out of code); the tool only gained a method label for banks where the trace and the
allowance add nothing, current per-bank notes, an exit check, and the packed module's true end
(below). Exit check (`python3 tools/code_survey.py` prints it, with the 19 odd exits, and
`symbols/code_survey.csv`'s header records it): of the 12,661 exits of matched code routines (counted once per routine, target and M/X widths, under the entry states that decode on the routine's own source lines), 12,642 land on matched instruction starts, none on unmatched bytes, and 19 (18 mid-instruction, 1 in matched data) are fall-throughs after an instruction decoded under the wrong width. Two
routines decode under no single entry state, BattleSys_ApplyDamage and C2Scene_ObjAFly, so
their exits are not counted; an independent review (PR #106) found every target in their source
to be a matched label. So the trace reaches no unmatched byte, no code-like block is joined to
code, and each bank's code bytes are its matched code: 249,251 in all (was 239,779, low 232,629, high
262,780). The banks that changed: `$C1` 63,058 -> 62,682, `$C2` 56,791 -> 60,695, `$C3` 3,032
-> 4,076, `$C6` 2,673 -> 3,619, `$C7` 2,526 -> 2,672, `$CC` 4,440 -> 4,995, `$CD` 14,533 ->
15,824, `$CE` 3,075 -> 3,729, `$CF` 6,117 -> 7,013, `$D1` 4,733 -> 5,858, `$FD` 16,149 ->
15,668, `$FF` 1,795 -> 1,563 (`$C0` 60,857 unchanged). The progress share is 100.00% of the
reachable 65816 code in ROM: the old-build leftovers (the `*OldBuild*` rows, 4,694 bytes, partly
routines) are matched as data, since no code reaches them, and the SPC700 driver (7,153 bytes)
and the packed `$C3` module (26,393 bytes, unpacking to $857F bytes at `$7E:3000`, about half of
it code-like per the PR #106 review) are counted apart and are not in it. No bank is "survey low" any more.

By construction the method returns the matched total once every exit of matched code lands in
matched code, so that result alone is no evidence that nothing is left. The evidence is the
checks beside it: the exit check above (repeatable with the tool), the per-block reading of the
high bound below, and these, from an independent review (PR #106): the unpacked `$C3` module's
real JSL/JML into ROM all land on matched instruction starts; 171 of the 172 op-`$4E`
(C2Script_CallLong) patterns in the unpacked scene scripts land on matched `$C6` starts (the
other is an op `$1A` operand); the 73 entries of C3Rom_PackPtrs (`$FE:0000`; entry 73 is
$000000, entries 58-72 point into `$FD:0000`-`$58E1`, the credits graphics): apart from entry 1
(the module), 13 raw blocks (not in pack format, e.g. `$FE:4B9A`, `$FE:8D15`, `$FE:F91E`) and 2
packs that unpack to 0 bytes, all unpack to data, graphics and tile maps (pack 71 at `$FD:57F0`
scores 60 of 63 blocks code-like, but it is a `$10 $00` tile map; pack 61 at `$FD:055C` 10 of
84, 4bpp graphics; pack 0 at `$C3:1200` 0 of 31); and a search for
routine-shaped instruction runs over all unmatched ROM bytes finds none longer than 19
instructions, all noise. Held-out calibration (`--calibrate`): hiding `$C0` -2.4%, `$C1`
-2.5%, `$C2` -20.5%, `$FD` -0.8% (recall 97.0%, 96.8%, 78.9%, 94.7%).

What is left is the high bound, 268,398 (+19,147): isolated code-like 32-byte blocks (score >=
-0.5, not joined to code), all in unmatched ROM bytes outside the SPC700 driver, the packed
module and the sound data. In banks with code they add `$C3` 192, `$C6` 256, `$CC` 384, `$CD`
672, `$CE` 998, `$CF` 1,824, `$D1` 1,376, `$FD` 69, `$FF` 288; the other 13,088 are in banks
with no code ($C4-$C5, $D0, $D2-$FC, $FE), at the scorer's rate on data (under 1% of blocks).
Assessment, bank by bank (checked with xref's byte-pattern index and the matched data rows):
no JSR/JMP/JSL/JML from an instruction of matched code and no word or long pointer in a matched
table points into any of them (the few pattern hits are operand bytes of matched code, which the
trace would otherwise have followed, or words in `*OldBuildLeftovers`), so all are survey noise:

- `$C3`: `$1280` lies in pack 0 (`$C3:1200`-`$1312`, packed bytes); `$C1E0`, `$DCE0`, `$E1C0`,
  `$EE60`, `$FE60` in the data after the packed module.
- `$C6`: `$1B20`, `$2120`, `$3A60`, `$C9A0`, `$CB40`, `$D020` in the data before the code;
  `$F400`-`$F43F` is a word table ($F000, $F001, $F00A, ...) in the data after it.
- `$CC`: `$18E0`, `$2BE0` (small counts $10-$60), `$2EC0`-`$2EFF`, `$4040`, `$8C20`, `$CC20`,
  `$DCC0`-`$DD1F` in the battle tables `$0000`-`$DFFF`; `$F700`, `$F800` in the tables after
  the code.
- `$CD`: `$6080` (word table $849D, $84B5, ...), `$6500`-`$6A7F` (the pointer tables at
  `$CD:66F0`, $F077, $F079, ...), `$B620`, `$D0C0`: data of `$CD:4000`-`$FFFF`.
- `$CE`: fourteen blocks in the scripts and object records `$CE:0000`-`$DFFF`; `$F060`-`$F065`
  (the last 6 bytes of the tables `$CE:EF11`-`$F065`, before BattleCE_UnkF066); the rest in
  `$CE:F820`-`$FFBF`, inside the tables after the code (repeating `$BD $A0 $89` records).
- `$CF`: 31 runs in `$CF:5560`-`$DE9F`, inside the data `$CF:0000`-`$E2FF` (tile words such as
  `$2996 $2998 ...` at `$8E80`; a 256-byte run of equal scores at `$A4C0`, a table).
- `$D1`: 36 runs in the window maps `$D1:0000`-`$E709` (`$DA60`-`$DB1F` is `$22 $20` tile
  pairs, `$DFE0` repeats `$4A $0A`).
- `$FD`: `$1E00`, `$3120` in the packed credits graphics; `$A8A0`-`$A8A4`, the last bytes of
  the battle tables before BattleFD_UnkA8A5 (counted isolated because a block that holds code
  never joins itself).
- `$FF`: `$0AE0`, `$5220`, `$8400` (word table $844E, $8474, ...), `$9680`, `$9740`,
  `$B440`-`$B47F`, `$C4A0`, `$C860`: data of `$FF:0000`-`$F547`.

Not in the code total: the packed module `$C3:1313`-`$7A2B` and the SPC700 driver, both counted
apart. The other entries of C3Rom_PackPtrs (pack 0 at `$C3:1200`, the
packs in `$FE` and `$FD`) unpack to data or are raw or empty (PR #106 review, above; the 73
entries and entries 58-72 in `$FD` checked again from the ROM). The module's size is now taken to its last end marker: the earlier
survey stopped at `$7A21` (the length word + 2, which is segment 1 only) and counted 26,383
bytes; Decomp_ToWram's format puts segment 1's end marker at `$7A22` ($04, next marker at
`$C3:1313` + $6718) and the final $00 at `$7A2B`, so 26,393 bytes, as
`asm/include/unmatched.asm` and Decomp_ToWram's header say. The survey checks it
(`pack_end`).

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
3. Done: `$C0:5D6E` `Evt_OpcodeTable` (256 words) and `$C0:9FF7` `Party_AnimTable` (65 words).
4. Done in bank $C0: `$C0:400E` Evt_OpFFTable and `$C0:7181` Obj_PalSlotHandlers are matched.
5. Bank $C1 (`$C1:2D81`, `$C1:3216` and `$C1:3760` are matched as BattlePos_ModeTable,
   Battle_FxHandlerTable and Battle_EnemyMoverTable): `$C1:B80D` (157, `$C1:874E`), `$C1:FA61` (21,
   `$C1:EB45`), `$C1:D126` (6, `$C1:CFE1`), `$C1:DA31` (4, `$C1:D783`).
