; ============================================================
; unmatched_battle.asm — Names for routines that the matched battle
; code calls but that are not matched yet (in bank $C1 or elsewhere).
;
; Same format as unmatched.asm: label-only `org` stubs, no bytes. When a
; routine gets matched, delete its stub here; the real label takes over.
; Names come from the reference disassembly / earlier session notes;
; the comment says what the call site expects.
; ============================================================

; --- Bank $CD after the matched part ($CD:16B5 on; helpers of the matched code) ---

org $CD16B5
BattleCD_FxOpTable:                     ; 122 words: the layer-effect script's opcode handlers $80-$F9
                                        ; (JSR (T,X) in BattleCD_RunFxOp); the handlers are at $CD:17A9 on
org $CD3B5F
BattleCD_PlayPendingSfx:                ; JSR: when !Battle_SfxPending is set, clears it and runs
                                        ; BattleCD_ApuCmd18 with A = $CD24, X = $CD25
org $CD3B71
BattleCD_ApuCmd18:                      ; JSR: APU command !Sfx_CmdUnk18 with !Sfx_Param1 = A and !Sfx_Param2 = X's low
                                        ; byte (Audio_ProcessEntry): a sound, probably
org $CD3B82
BattleCD_Unk3B82:                       ; JSR from BattleCD_NmiMain with A = $40; not analysed
org $CD3E3B
BattleCD_WaitFrames:                    ; JSR: A frames of BattleCD_WaitFrameRefresh (A = 0 at the end)
org $CD3E44
BattleCD_PauseWait:                     ; JSR: while !Battle_Paused is set, sends APU command $F5 and waits until it
                                        ; is cleared (frame by frame through $CA20); returns at once otherwise
org $CD3E75
BattleCD_WaitFrameRefresh:              ; JSR: BattleCD_WaitFrame, then BankC1_VecRefreshMenu (A kept)
org $CD3E7D
BattleCD_WaitFrame:                     ; JSR: waits until $CA20 is cleared (BattleCD_PauseWait meanwhile), then
                                        ; BattleCD_StepText; A kept (PHA/PLA)
org $CD3E8E
BattleCD_DmaToVram:                     ; JSR/JMP: DMA channel 7 (DB = $00 inside) from A:X to VRAM word address Y,
                                        ; DP $45 bytes
org $CD3EB4
BattleCD_RunQueuedDma:                  ; JSR from the NMI: runs the upload BattleCD_QueueVramDma queued ($CA26-$CA2D)
org $CD3ED2
BattleCD_QueueVramDma:                  ; JSR: queues A:X to VRAM word address Y, DP $53 bytes, and waits frames until
                                        ; the NMI has sent it all (in pieces); !Battle_DmaQueueBusy meanwhile

; --- Bank $D1 battle code (called from bank $CD; none analysed) ---

org $D1E8D9
BattleD1_UploadPage:                    ; JSL from BattleCD_NmiUploadText: A:X = a tilemap page, DP $45 = a VRAM address
org $D1EA4B
BattleD1_UnkEA4B:                       ; JSL from BattleCD_NmiMain (with !Battle_Unk2A21 bit 0)
org $D1ECF3
BattleD1_UnkECF3:                       ; JSL from BattleCD_FrameTick, A = !Battle_UnkCD45
org $D1F1B0
BattleD1_InitBattle:                    ; JSL from BattleCD_EnterBattle: sets DB=$7E, DP=0, the NMI/IRQ trampolines
                                        ; and many bank-$CD variables
org $D1F426
BattleD1_UnkF426:                       ; JSL from BattleCD_NmiMain and BattleCD_NmiSetup
org $D1F4C0
BattleD1_NmiExit:                       ; the NMI trampoline's target BattleCD_ExitBattle installs (JML at $0500)
org $D1F67A
BattleD1_ActOp80:                       ; JSL from BattleCD_ActOp80 (action opcode $80)

; --- Bank $CE battle code (called from bank $CD; none analysed) ---

org $CEE18E
BattleCE_UnkE18E:                       ; JSL from BattleCD_NmiMain (with !Battle_Unk2A21 bit 0)
org $CEEE6E
BattleCE_UnkEE6E:                       ; JSL from BattleCD_StepWipe at an opening wipe's start, A = !Battle_UnkCA22
org $CEF066
BattleCE_UnkF066:                       ; JSL from BattleCD_NmiMain unless !Battle_UnkCD2D / !Battle_UnkA028
