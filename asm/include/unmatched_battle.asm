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

org $C15FC3
BattleAct_Op70Body:                     ; JMP: the opcode $70 handler after its STZ $8E ($C1:5FC1): counts
                                        ; !Battle_ActObjUnkA1D8 of the object thread up; advances 1 only when DP $8E is 0

org $C1762E
BattleAct_RunCalc:                      ; JSR: A = handler number; calls entry A of the word table at $C1:79D3, keeping
                                        ; X and Y; the handlers leave results in !Battle_ActCalcOutA/B (not analysed)

org $C17A63
BattleAct_LoaderTable:                  ; 4 words: action loader per !Battle_ActKind (JSR (T,X) in BattleAct_LoadScript)

org $C17A6B
BattleAct_OpcodeTable:                  ; 224 words ($7A6B-$7C2A): handler per script opcode $00-$DA (JSR (T,X) in
                                        ; BattleAct_RunThread), then 5 unreachable entries ($DB-$DF); 75 entries are
                                        ; BattleAct_OpEndScript

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

org $CD0018
BattleAnim_UnkVecCD0018:                ; JSL vector (JMP $CD:0D28): A = !Battle_ActUnkArg987C; zeroes
                                        ; !Battle_Unk5D9B and starts something by that number; not analysed

org $CD0027
BattleMsg_ShowFromTableCC3A09Vec:       ; JSL vector: info panel for the tech under the cursor (A = tech id)

org $CD002D
BattleMsg_ShowMsg0BIfKeyChangedVec:     ; JSL vector: battle message / info panel (A = key, $FF = none)

org $CD0030
BattleMsg_UnkVecCD0030:                 ; JSL vector: sibling of $CD002D, used for enemy targets; not analysed

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
