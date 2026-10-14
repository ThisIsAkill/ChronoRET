; ============================================================
; unmatched_battle.asm — Names for routines that the matched battle
; code calls but that are not matched yet (in bank $C1 or elsewhere).
;
; Same format as unmatched.asm: label-only `org` stubs, no bytes. When a
; routine gets matched, delete its stub here; the real label takes over.
; Names come from the reference disassembly / earlier session notes;
; the comment says what the call site expects.
; ============================================================

; --- Long targets of bank $C1's entry block and service 0 (EngCall_BattleMain,
;     BattleSys_SceneSetup, BattleSys_Service6; none analysed) ---
org $CFFB65
BattleCF_EnterBattle:                   ; JML from $C1:001B: clears battle RAM and JMLs to $C1:8000
org $CFFBE5
BattleCF_UnkFBE5:                       ; JML from $C1:001F (BattleSys_ExitVec's way out of the battle)
org $CFE300
BattleCF_UnkE300:                       ; JML from $C1:0076 (vector $C1:0009)
org $CFE58A
BattleCF_UnkE58A:                       ; JML from $C1:007A (vector $C1:000C)
org $CFFE20
BattleCF_UnkFE20:                       ; JSL from BattleSys_Service6
org $CD0003
BattleSys_VecCD0003:                    ; JSL vector (JMP $CD:0399) from BattleSys_SceneSetup
org $CD000C
BattleSys_VecCD000C:                    ; JSL vector (JMP $CD:04FD) from BattleSys_SceneSetup
org $CD0012
BattleSys_VecCD0012:                    ; JSL vector (JMP $CD:0534): BattleSys_SceneSetup repeats it while Z is clear

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

org $CD0033
BattleMsg_UnkVecCD0033:                 ; JSL vector (JMP $CD:0295): A = a non-zero script byte (!Battle_UnkB3C7);
                                        ; run by the enemy-script run handlers; a battle message, probably; not analysed

org $CD0021
BattleSys_UnkVecCD0021:                 ; JSL vector: BattleSys_Main's !Battle_Unk99CD end, A = 8; BattleSys_UnkB967
                                        ; after a tech, A = 3 or $0D; not analysed

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
