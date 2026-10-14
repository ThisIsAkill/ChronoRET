; ============================================================
; unmatched_battle.asm — Names for routines that the matched battle
; code calls but that are not matched yet (in bank $C1 or elsewhere).
;
; Same format as unmatched.asm: label-only `org` stubs, no bytes. When a
; routine gets matched, delete its stub here; the real label takes over.
; Names come from the reference disassembly / earlier session notes;
; the comment says what the call site expects.
; ============================================================

; --- Long targets of BattleSys_SceneSetup (service 0; none analysed) ---
org $CD0003
BattleSys_VecCD0003:                    ; JSL vector (JMP $CD:0399) from BattleSys_SceneSetup
org $CD000C
BattleSys_VecCD000C:                    ; JSL vector (JMP $CD:04FD) from BattleSys_SceneSetup
org $CD0012
BattleSys_VecCD0012:                    ; JSL vector (JMP $CD:0534): BattleSys_SceneSetup repeats it while Z is clear

; --- Bank $CD vectors called from bank $CF (none analysed) ---
org $CD0000
BattleSys_VecCD0000:                    ; JSL vector (JMP $CD:0039): BattleCF_EnterBattle, before it clears battle RAM
org $CD0006
BattleSys_VecCD0006:                    ; JSL vector (JMP $CD:03B4): BattleCF_ExitBattle, just before it returns
org $CD0024
BattleSys_VecCD0024:                    ; JSL vector (JMP $CD:0043): BattleCF_RemoveMarkedEnemies, A = the enemy's
                                        ; battler slot, after it moved the enemy to the special palette

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

; --- Bank $CD/$CE routines called from bank $D1 (the battle-effect code; none analysed) ---
; Direct JSL targets inside bank $CD/$CE rather than vectors; the names keep the
; BattleSys_VecCDxxxx form of the stubs above.
org $CD09CE
BattleSys_VecCD09CE:                    ; JSL from BattleFx_NmiAlt: DMA of $200 bytes from $7E:2200 to CGRAM
                                        ; (channel 7; absolute register stores, so DB must map I/O)
org $CD0235
BattleSys_VecCD0235:                    ; JSL from BattleFx_Init: zeroes eight $80-byte blocks from $7E:B480
org $CD0C89
BattleSys_VecCD0C89:                    ; JSL from BattleFx_Nmi / Init / NmiAlt: JSL $C0:0002 (ScrollStepAccum)
                                        ; with DB, DP and P saved, then TDC
org $CD0C95
BattleSys_VecCD0C95:                    ; JSL from BattleFx_Nmi: the NMI work, JSR ($CD:0C83,X) by DP $7E
org $CD0C9D
BattleSys_VecCD0C9D:                    ; JSL from BattleFx_Init: copies FieldBtlPpu bytes to $7E:BC85-
org $CD38B2
BattleSys_VecCD38B2:                    ; JSL from BattleFx_RasterQuad: A = line; points WMADD at that line
                                        ; of the window table picked by the frame and !BattleFx_QuadSlot
org $CD3ECE
BattleSys_VecCD3ECE:                    ; JSL from BattleFx_LoadBgSet: queues a VRAM upload (X = source,
                                        ; A = its bank, Y = VRAM word address, DP $53 = bytes)
org $CEEE6E
BattleSys_VecCEEE6E:                    ; JSL from BattleFx_Init / ReloadLayerSet: A = set; copies records
                                        ; from bank $CE to $7E:C867 and on
