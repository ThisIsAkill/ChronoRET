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

; --- Bank $C7 (audio) ---

org $C70004
Audio_ProcessEntry:                     ; JSL: run the APU command block !Sfx_Command..!Sfx_Param2

; --- Bank $CD (battle messages / per-frame service) ---

org $CD0009
BattleSys_FrameTickVec:                 ; JSL vector: per-frame service tick (BattleMenu_RefreshIfDirtyAndTick)

org $CD0036
BattleSys_IdleVecCD0036:                ; JSL vector (JMP $CD:04A6 -> JSR $CD:3E44): called over and over while
                                        ; BattleSys_PumpFrames waits; not analysed

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
