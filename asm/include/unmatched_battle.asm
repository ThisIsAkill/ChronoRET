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
; --- Enemy script handlers (tables BattleAi_TestTable, BattleAi_ChooseTable,
;     BattleAi_RunTable, BattleAi_TargetTable at $C1:B80D-$C1:B92C; not analysed) ---
org $C18EAB
BattleAi_Test01:                        ; BattleAi_TestTable entry $01
org $C18F11
BattleAi_Test02:                        ; BattleAi_TestTable entry $02
org $C18F87
BattleAi_Test03:                        ; BattleAi_TestTable entry $03
org $C18FDA
BattleAi_Test04:                        ; BattleAi_TestTable entry $04
org $C19013
BattleAi_Test05:                        ; BattleAi_TestTable entry $05
org $C19045
BattleAi_Test06:                        ; BattleAi_TestTable entry $06
org $C19082
BattleAi_Test07:                        ; BattleAi_TestTable entry $07
org $C190BE
BattleAi_Test08:                        ; BattleAi_TestTable entry $08
org $C19130
BattleAi_Test09:                        ; BattleAi_TestTable entry $09
org $C1918E
BattleAi_Test0A:                        ; BattleAi_TestTable entry $0A
org $C191F9
BattleAi_Test0B:                        ; BattleAi_TestTable entry $0B
org $C1925D
BattleAi_Test0C:                        ; BattleAi_TestTable entry $0C
org $C192A3
BattleAi_Test0D:                        ; BattleAi_TestTable entry $0D
org $C19314
BattleAi_Test0E:                        ; BattleAi_TestTable entry $0E
org $C1938D
BattleAi_Test0F:                        ; BattleAi_TestTable entry $0F
org $C193E6
BattleAi_Test10:                        ; BattleAi_TestTable entry $10
org $C1942A
BattleAi_Test11:                        ; BattleAi_TestTable entry $11
org $C19474
BattleAi_Test12:                        ; BattleAi_TestTable entry $12
org $C194D2
BattleAi_Test13:                        ; BattleAi_TestTable entry $13
org $C19514
BattleAi_Test14:                        ; BattleAi_TestTable entry $14
org $C1959A
BattleAi_Test15:                        ; BattleAi_TestTable entry $15
org $C195D6
BattleAi_Test16:                        ; BattleAi_TestTable entry $16
org $C195DA
BattleAi_Test17:                        ; BattleAi_TestTable entry $17
org $C195FA
BattleAi_Test18:                        ; BattleAi_TestTable entries $18, $23, $24, $25, $26, $27, $28
org $C19652
BattleAi_Test19:                        ; BattleAi_TestTable entry $19
org $C19656
BattleAi_Test1A:                        ; BattleAi_TestTable entry $1A
org $C196A5
BattleAi_Test1B:                        ; BattleAi_TestTable entry $1B
org $C196D4
BattleAi_Test1C:                        ; BattleAi_TestTable entry $1C
org $C19728
BattleAi_Test1D:                        ; BattleAi_TestTable entry $1D
org $C1975C
BattleAi_Test1E:                        ; BattleAi_TestTable entry $1E
org $C19765
BattleAi_Test1F:                        ; BattleAi_TestTable entry $1F
org $C197AB
BattleAi_Test20:                        ; BattleAi_TestTable entry $20
org $C197C0
BattleAi_Test21:                        ; BattleAi_TestTable entry $21
org $C197D5
BattleAi_Test22:                        ; BattleAi_TestTable entry $22
org $C19810
BattleAi_Choose00:                      ; BattleAi_ChooseTable entry $00
org $C1983A
BattleAi_Choose01:                      ; BattleAi_ChooseTable entries $01, $02
org $C198C4
BattleAi_Choose03:                      ; BattleAi_ChooseTable entry $03
org $C198C5
BattleAi_Choose04:                      ; BattleAi_ChooseTable entry $04
org $C19960
BattleAi_Choose05:                      ; BattleAi_ChooseTable entry $05
org $C19961
BattleAi_Choose06:                      ; BattleAi_ChooseTable entry $06
org $C19962
BattleAi_Choose07:                      ; BattleAi_ChooseTable entry $07
org $C19966
BattleAi_Choose08:                      ; BattleAi_ChooseTable entry $08
org $C19967
BattleAi_Choose09:                      ; BattleAi_ChooseTable entry $09
org $C19978
BattleAi_Choose0A:                      ; BattleAi_ChooseTable entry $0A
org $C19979
BattleAi_Choose0B:                      ; BattleAi_ChooseTable entry $0B
org $C1997D
BattleAi_Choose0C:                      ; BattleAi_ChooseTable entry $0C
org $C1997E
BattleAi_Choose0D:                      ; BattleAi_ChooseTable entry $0D
org $C1997F
BattleAi_Choose0E:                      ; BattleAi_ChooseTable entry $0E
org $C19980
BattleAi_Choose0F:                      ; BattleAi_ChooseTable entry $0F
org $C19981
BattleAi_Choose10:                      ; BattleAi_ChooseTable entries $10, $16
org $C199B4
BattleAi_Choose11:                      ; BattleAi_ChooseTable entries $11, $12, $13, $14, $15
org $C199B8
BattleAi_Run00:                         ; BattleAi_RunTable entry $00
org $C199BE
BattleAi_Run01:                         ; BattleAi_RunTable entry $01
org $C19A39
BattleAi_Run02:                         ; BattleAi_RunTable entry $02
org $C19B46
BattleAi_Run03:                         ; BattleAi_RunTable entry $03
org $C19B47
BattleAi_Run04:                         ; BattleAi_RunTable entry $04
org $C19B48
BattleAi_Run05:                         ; BattleAi_RunTable entry $05
org $C19B8C
BattleAi_Run06:                         ; BattleAi_RunTable entry $06
org $C19B8D
BattleAi_Run07:                         ; BattleAi_RunTable entry $07
org $C19C6E
BattleAi_Run08:                         ; BattleAi_RunTable entry $08
org $C19C6F
BattleAi_Run09:                         ; BattleAi_RunTable entry $09
org $C19CB3
BattleAi_Run0A:                         ; BattleAi_RunTable entry $0A
org $C19D1B
BattleAi_Run0B:                         ; BattleAi_RunTable entry $0B
org $C19D72
BattleAi_Run0C:                         ; BattleAi_RunTable entry $0C
org $C19DCE
BattleAi_Run0D:                         ; BattleAi_RunTable entry $0D
org $C19E62
BattleAi_Run0E:                         ; BattleAi_RunTable entry $0E
org $C19E63
BattleAi_Run0F:                         ; BattleAi_RunTable entry $0F
org $C19E78
BattleAi_Run10:                         ; BattleAi_RunTable entry $10
org $C19F5A
BattleAi_Run11:                         ; BattleAi_RunTable entry $11
org $C19FD2
BattleAi_Run12:                         ; BattleAi_RunTable entry $12
org $C1A14E
BattleAi_Run13:                         ; BattleAi_RunTable entry $13
org $C1A188
BattleAi_Run14:                         ; BattleAi_RunTable entry $14
org $C1A20B
BattleAi_Run15:                         ; BattleAi_RunTable entry $15
org $C1A396
BattleAi_Run16:                         ; BattleAi_RunTable entry $16
org $C1A3F6
BattleAi_Target00:                      ; BattleAi_TargetTable entry $00
org $C1A3F7
BattleAi_Target01:                      ; BattleAi_TargetTable entry $01
org $C1A411
BattleAi_Target02:                      ; BattleAi_TargetTable entry $02
org $C1A42E
BattleAi_Target03:                      ; BattleAi_TargetTable entry $03
org $C1A43D
BattleAi_Target04:                      ; BattleAi_TargetTable entry $04
org $C1A452
BattleAi_Target05:                      ; BattleAi_TargetTable entry $05
org $C1A4AF
BattleAi_Target06:                      ; BattleAi_TargetTable entry $06
org $C1A4E0
BattleAi_Target07:                      ; BattleAi_TargetTable entry $07
org $C1A508
BattleAi_Target08:                      ; BattleAi_TargetTable entry $08
org $C1A541
BattleAi_Target09:                      ; BattleAi_TargetTable entry $09
org $C1A54B
BattleAi_Target0A:                      ; BattleAi_TargetTable entry $0A
org $C1A555
BattleAi_Target0B:                      ; BattleAi_TargetTable entry $0B
org $C1A55F
BattleAi_Target0C:                      ; BattleAi_TargetTable entry $0C
org $C1A569
BattleAi_Target0D:                      ; BattleAi_TargetTable entry $0D
org $C1A573
BattleAi_Target0E:                      ; BattleAi_TargetTable entry $0E
org $C1A5A3
BattleAi_Target0F:                      ; BattleAi_TargetTable entry $0F
org $C1A5D3
BattleAi_Target10:                      ; BattleAi_TargetTable entry $10
org $C1A603
BattleAi_Target11:                      ; BattleAi_TargetTable entry $11
org $C1A633
BattleAi_Target12:                      ; BattleAi_TargetTable entry $12
org $C1A663
BattleAi_Target13:                      ; BattleAi_TargetTable entry $13
org $C1A693
BattleAi_Target14:                      ; BattleAi_TargetTable entry $14
org $C1A6C3
BattleAi_Target15:                      ; BattleAi_TargetTable entry $15
org $C1A6ED
BattleAi_Target16:                      ; BattleAi_TargetTable entry $16
org $C1A709
BattleAi_Target17:                      ; BattleAi_TargetTable entry $17
org $C1A737
BattleAi_Target18:                      ; BattleAi_TargetTable entry $18
org $C1A765
BattleAi_Target19:                      ; BattleAi_TargetTable entry $19
org $C1A7A9
BattleAi_Target1A:                      ; BattleAi_TargetTable entry $1A
org $C1A7E5
BattleAi_Target1B:                      ; BattleAi_TargetTable entry $1B
org $C1A819
BattleAi_Target1C:                      ; BattleAi_TargetTable entry $1C
org $C1A855
BattleAi_Target1D:                      ; BattleAi_TargetTable entry $1D
org $C1A889
BattleAi_Target1E:                      ; BattleAi_TargetTable entry $1E
org $C1A8C5
BattleAi_Target1F:                      ; BattleAi_TargetTable entry $1F
org $C1A8F9
BattleAi_Target20:                      ; BattleAi_TargetTable entry $20
org $C1A935
BattleAi_Target21:                      ; BattleAi_TargetTable entry $21
org $C1A971
BattleAi_Target22:                      ; BattleAi_TargetTable entry $22
org $C1A9AD
BattleAi_Target23:                      ; BattleAi_TargetTable entry $23
org $C1A9E9
BattleAi_Target24:                      ; BattleAi_TargetTable entry $24
org $C1AA25
BattleAi_Target25:                      ; BattleAi_TargetTable entry $25
org $C1AA61
BattleAi_Target26:                      ; BattleAi_TargetTable entry $26
org $C1AAAB
BattleAi_Target27:                      ; BattleAi_TargetTable entry $27
org $C1AAB6
BattleAi_Target28:                      ; BattleAi_TargetTable entry $28
org $C1AAC1
BattleAi_Target29:                      ; BattleAi_TargetTable entry $29
org $C1AACC
BattleAi_Target2A:                      ; BattleAi_TargetTable entry $2A
org $C1AAD7
BattleAi_Target2B:                      ; BattleAi_TargetTable entry $2B
org $C1AAE2
BattleAi_Target2C:                      ; BattleAi_TargetTable entry $2C
org $C1AAED
BattleAi_Target2D:                      ; BattleAi_TargetTable entry $2D
org $C1AAF8
BattleAi_Target2E:                      ; BattleAi_TargetTable entry $2E
org $C1AB03
BattleAi_Target2F:                      ; BattleAi_TargetTable entry $2F
org $C1AB4E
BattleAi_Target30:                      ; BattleAi_TargetTable entry $30
org $C1AB59
BattleAi_Target31:                      ; BattleAi_TargetTable entry $31
org $C1AB64
BattleAi_Target32:                      ; BattleAi_TargetTable entry $32
org $C1AB6F
BattleAi_Target33:                      ; BattleAi_TargetTable entry $33
org $C1AB7A
BattleAi_Target34:                      ; BattleAi_TargetTable entry $34
org $C1AB85
BattleAi_Target35:                      ; BattleAi_TargetTable entry $35
org $C1AB90
BattleAi_Target36:                      ; BattleAi_TargetTable entry $36
org $C1AB9B
BattleAi_Target37:                      ; BattleAi_TargetTable entry $37
org $C1ABC9
BattleAi_Target38:                      ; BattleAi_TargetTable entry $38
org $C1D221
BattleSys_Effect00:                     ; BattleSys_EffectTable entry $00; not analysed
org $C1D23E
BattleSys_Effect01:                     ; ... entry $01; not analysed
org $C1D267
BattleSys_Effect02:                     ; ... entry $02; not analysed
org $C1D2DE
BattleSys_Effect03:                     ; ... entry $03; not analysed
org $C1D370
BattleSys_Effect04:                     ; ... entry $04 (an RTS, probably: one byte before $C1:D371)
org $C1D371
BattleSys_Effect05:                     ; ... entry $05; not analysed
org $C1D3BF
BattleSys_Effect06:                     ; ... entry $06; not analysed
org $C1D3F4
BattleSys_Effect07:                     ; ... entry $07; not analysed
org $C1D431
BattleSys_Effect08:                     ; ... entry $08; not analysed
org $C1DA37
BattleSys_UnkDA37:                      ; JSR from BattleSys_Effect29/2A and $C1:D221-$C1:D48E; not analysed
org $C1DB5E
BattleSys_UnkDB5E:                      ; JSR from BattleSys_Effect2A and $C1:D221-$C1:D48E; not analysed
org $C1DBAA
BattleSys_UnkDBAA:                      ; JSR from BattleSys_Effect2B and $C1:D221-$C1:D48E; not analysed
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
BattleSys_UnkVecCD0021:                 ; JSL vector: BattleSys_Main's !Battle_Unk99CD end, A = 8; BattleSys_UnkB967
                                        ; after a tech, A = 3 or $0D; not analysed

; --- Bank $FD (called from BattleSys_UnkB575 and BattleSys_UnkB967; not analysed) ---

org $FDA8A5
BattleFD_UnkA8A5:                       ; JSL from BattleSys_UnkB967, A = a PC slot taking part; leaves !Battle_UnkB3EA
org $FDA93C
BattleFD_UnkA93C:                       ; JSL from BattleSys_UnkB967 when !Battle_UnkB3EA is non-zero
org $FDA95F
BattleFD_UnkA95F:                       ; JSL from BattleSys_UnkB575 after it set !Battle_CmdPcs


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
