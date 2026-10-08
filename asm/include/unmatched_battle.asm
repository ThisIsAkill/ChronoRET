; ============================================================
; unmatched_battle.asm — Names for routines that the matched battle
; code calls but that are not matched yet (in bank $C1 or elsewhere).
;
; Same format as unmatched.asm: label-only `org` stubs, no bytes. When a
; routine gets matched, delete its stub here; the real label takes over.
; Names come from the reference disassembly / earlier session notes;
; the comment says what the call site expects.
; ============================================================

; --- Bank $C1 (battle engine, not matched yet) ---

org $C10045
BattleSys_RunService:                   ; JSR: A = service number; saves A, X, Y and calls entry A of the table at
                                        ; $C1:0051 (also reached through JMP at $C1:0003)

org $C10003
BattleSys_RunServiceVec:                ; JSR: JMP $0045 (BattleSys_RunService), A = service number
org $C10006
BattleSys_ExitVec:                      ; JMP from BattleSys_Main's end: JMP $001F -> JML $CF:FBE5 (not analysed)
org $C18461
BattleSys_Unk8461:                      ; JSR from BattleSys_Main while !Battle_UnkAF25 is set; also entry 12 of
                                        ; BattleSys_ListHandlerTable; not analysed
org $C1895B
BattleSys_Unk895B:                      ; JSR from BattleSys_Main (A = !Battle_EndUnk895BArg); not analysed
org $C18C09
BattleSys_Unk8C09:                      ; JSR from BattleSys_Main after the shuffles; not analysed
org $C1B093
BattleSys_UnkB093:                      ; JSR from BattleSys_Main / Battle_SetupBattle with X = PC slot * $80; not analysed
org $C1B0B6
BattleSys_UnkB0B6:                      ; JSR from BattleSys_Main with X = Y * $80, Y = 0-9; not analysed
org $C1B223
BattleSys_UnkB223:                      ; JSR from each BattleSys_Main pass; not analysed
org $C1B3BB
BattleSys_UnkB3BB:                      ; JSR from BattleSys_Main's end paths; not analysed
org $C1B3D2
BattleSys_UnkB3D2:                      ; JSR from BattleSys_Main's !Battle_Unk2989 bit 5 end; not analysed
org $C1B3F9
BattleSys_UnkB3F9:                      ; JSR from BattleSys_Main's wait-mode path, X = PC slot, A = its !Battler_UnkAF0A; not analysed
org $C1B442
BattleSys_UnkB442:                      ; JSR from BattleSys_Main's end paths; not analysed
org $C1B4E9
BattleSys_UnkB4E9:                      ; JSR from BattleSys_Main's end paths; not analysed
org $C1B7F2
BattleSys_UnkB7F2:                      ; JSR from BattleSys_Main's end paths; not analysed
org $C1B92D
BattleSys_ListHandlerTable:             ; 13 words: handler per turn list (BattleSys_Main JSR (T,X)); entry 12 is
                                        ; BattleSys_Unk8461
org $C1B947
BattleSys_ListOffsetTable:              ; 13 words: !Battle_ListFlags + list * 11 (BattleSys_Main)
org $C1BC60
BattleSys_UnkBC60:                      ; JSR from BattleSys_Main's debug win with !Battle_UnkB18B = PC slot; not analysed
org $C1C96A
BattleSys_UnkC96A:                      ; JSR from Battle_SetupBattle for PCs 0-2 (PC in DP $06); not analysed
org $C1CA1A
BattleSys_UnkCA1A:                      ; JSR from Battle_SetupBattle for PCs 0-2 (PC in DP $06); not analysed
org $C1CCCB
BattleSys_UnkCCCB:                      ; JSR from Battle_SetupBattle for PCs 0-2 (PC in DP $06); not analysed
org $C1CDFF
BattleSys_UnkCDFF:                      ; JSR from Battle_SetupBattle; not analysed
org $C1CE3A
BattleSys_UnkCE3A:                      ; JSR from Battle_SetupBattle for PCs 0-2 (PC in DP $02); not analysed
org $C1CF15
BattleSys_UnkCF15:                      ; JSR from Battle_SetupBattle with arguments in DP $06, $08, $0A; not analysed
org $C1CFC2
BankC1_RunService:                      ; JMP from BankC1_Entry8003: saves P/X/DP/DB, DB=$7E, DP=0, runs entry A of the
                                        ; table at $C1:D126 (6 entries) with argument Y; returns a result in A
org $C1D005
BankC1_AddItem:                         ; BankC1_RunService service 1: add one of item Y to the inventory
org $C1D0A2
BankC1_AddGold:                         ; BankC1_RunService service 4: add Y to the gold sum
org $C1EA9D
BattleSys_UnkEA9D:                      ; JSR from BattleSys_Main's end paths; not analysed
org $C1EAE8
BattleSys_UnkEAE8:                      ; JSR from BattleSys_Main's end paths; not analysed
org $C1F93E
BattleSys_UnkF93E:                      ; JSR from BattleSys_Main's victory path after the gold; not analysed

; --- Bank $C3 ---

org $C30002
Decomp_ToWramVec:                       ; JSL vector (JMP $C3:0557): unpacks the data at the long address in
                                        ; !Battle_DecompSrc.. into WRAM at !Battle_DecompDest.. through WMADD/WMDATA
                                        ; (inferred: a decompressor, from its header-driven copy loops); not analysed

; --- Bank $C7 (audio) ---

org $C70004
Audio_ProcessEntry:                     ; JSL: run the APU command block !Sfx_Command..!Sfx_Param2

; --- Bank $CC (battle support, called from the action code) ---

org $CCF06B
BattleAct_ResetState:                   ; JSL: clears the action state ($5D80-$5E0C, $A124-$A1A7, $A1A8-$A1E7,
                                        ; !Battle_ActScriptDone, !Battle_ActFrameHold and more); sets
                                        ; !Battle_ActBattlers and $A437 to $FF

org $CCF102
BattleAct_ResetFxApplied:               ; JSL: sets !Battler_FxApplied of all 11 slots to $55

org $CCF110
Battle_BuildOccupiedCellMap:            ; JSL: copies !Battle_CellMap to $7CFD and marks the cell of each present
                                        ; battler there with $40 (only enemies when $7E2989 bit 2 is set)

org $CCF156
BattleAct_BuildBattlerList:             ; JSL: builds !Battle_ActBattlers and !Battle_ActTargets from the action
                                        ; block ($AE91, $AE95, $AE97-$AE99)

org $CCF1E7
BattleAct_StepPalettes:                 ; JSL: steps up to 4 palette sequences from the list at bank $CD + the
                                        ; offset in $9882, copying colours from $D1:4100/$D1:4400 into
                                        ; !Battle_PaletteLive (not analysed further)

org $CCF278
BattleAct_TickUnkA1A8:                  ; JSL: counts the timers of the 8 !Battle_ActUnkA1A8 entries down and runs
                                        ; $CC:F2A9 for each that is set and at 0

; --- Bank $CD (battle messages / per-frame service) ---

org $CD0009
BattleSys_FrameTickVec:                 ; JSL vector: per-frame service tick (BattleMenu_RefreshIfDirtyAndTick)

org $CD0036
BattleSys_IdleVecCD0036:                ; JSL vector (JMP $CD:04A6 -> JSR $CD:3E44): called over and over while
                                        ; BattleSys_PumpFrames waits; not analysed

org $CD0015
BattleAnim_LoadGfx4Vec:                 ; JSL vector (JMP $CD:1323): A = graphics set; loads sets A..A+3 as parts
                                        ; 0-3 through the $7E:2D00 buffer, $400 bytes each (inferred; not analysed)

org $CD002A
BattleAnim_LoadGfx2Vec:                 ; JSL vector (JMP $CD:1314): A = graphics set; the same for sets A, A+1
                                        ; as parts 4-5

org $CD001B
BattleAct_UnkVecCD001B:                 ; JSL vector (JMP $CD:003E, which calls $D1:F67A): run by opcode $80 after
                                        ; it copied its bytes to !Battle_ActOp80Args; not analysed

org $CD0018
BattleAnim_UnkVecCD0018:                ; JSL vector (JMP $CD:0D28): A = !Battle_ActUnkArg987C; zeroes
                                        ; !Battle_Unk5D9B and starts something by that number; not analysed

org $CD0027
BattleMsg_ShowFromTableCC3A09Vec:       ; JSL vector: info panel for the tech under the cursor (A = tech id)

org $CD002D
BattleMsg_ShowMsg0BIfKeyChangedVec:     ; JSL vector: battle message / info panel (A = key, $FF = none)

org $CD0030
BattleMsg_UnkVecCD0030:                 ; JSL vector: sibling of $CD002D, used for enemy targets; not analysed

org $CD0021
BattleSys_UnkVecCD0021:                 ; JSL vector: BattleSys_Main's !Battle_Unk99CD end, A = 8; not analysed

; --- Bank $FD (called from BattleSys_Main and Battle_SetupBattle; not analysed) ---

org $FDA982
BattleFD_UnkA982:                       ; JSL: first call of BattleSys_Main
org $FDAA98
BattleFD_UnkAA98:                       ; JSL: BattleSys_Main's !Battle_Unk99CD end
org $FDAAB0
BattleFD_UnkAAB0:                       ; JSL: last call of BattleSys_Main before BattleSys_ExitVec
org $FDACFD
BattleFD_UnkACFD:                       ; JSL: each BattleSys_Main pass, after the upkeep service
org $FDAD17
BattleFD_UnkAD17:                       ; JSL: BattleSys_Main's victory end
org $FDB201
BattleFD_UnkB201:                       ; JSL: BattleSys_Main's victory end, before the gold

org $FDB2DE
BattleFD_UnkB2DE:                       ; JSL from Battle_SetupBattle
org $FDB22E
BattleFD_UnkB22E:                       ; JSL from Battle_SetupBattle
org $FDB438
BattleFD_UnkB438:                       ; JSL from Battle_SetupBattle
org $FDB121
BattleFD_UnkB121:                       ; JSL from Battle_SetupBattle
org $FDAE52
BattleFD_UnkAE52:                       ; JSL from Battle_SetupBattle
org $FDB3FE
BattleFD_UnkB3FE:                       ; JSL from Battle_SetupBattle
org $FDAE99
BattleFD_UnkAE99:                       ; JSL from Battle_SetupBattle
org $FDAD09
BattleFD_UnkAD09:                       ; JSL from Battle_SetupBattle
org $FDAEF2
BattleFD_UnkAEF2:                       ; JSL from Battle_SetupBattle
org $FDACEE
BattleFD_UnkACEE:                       ; JSL from Battle_SetupBattle
org $FDB14D
BattleFD_UnkB14D:                       ; JSL from Battle_SetupBattle
org $FDB0D5
BattleFD_UnkB0D5:                       ; JSL from Battle_SetupBattle
org $FDB4E7
BattleFD_UnkB4E7:                       ; JSL from Battle_SetupBattle
org $FDB7EB
BattleFD_UnkB7EB:                       ; JSL from Battle_SetupBattle
org $FDB555
BattleFD_UnkB555:                       ; JSL from Battle_SetupBattle
org $FDB732
BattleFD_UnkB732:                       ; JSL from Battle_SetupBattle
org $FDB363
BattleFD_UnkB363:                       ; JSL from Battle_SetupBattle
org $FDB223
BattleFD_UnkB223:                       ; JSL from Battle_SetupBattle
org $FDAEC4
BattleFD_UnkAEC4:                       ; JSL from Battle_SetupBattle

; --- Bank $CF (battle support) ---

org $CFFAE2
Battle_MergePendingEntries1580:         ; JSL: called first every frame by BattleMenu_ProcessInput

org $CFFD02
Battle_QueueVramUpload_0CC0:            ; JSL: queue the status-bar map ($0CC0) for VRAM upload

org $CFFD36
Battle_QueueVramUpload_A6E1:            ; JSL: queue the tech window map ($A6E1) for VRAM upload

org $CFFD6A
Battle_QueueVramUpload_0E80:            ; JSL: queue the item list map ($0E80) for VRAM upload

org $CFFD9E
BattleFx_SetPtrA2FromTable:             ; JSL: A = PC slot; loads a per-slot pointer (name from the reference)
