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
org $CD38B2
BattleCD_Unk38B2:                       ; JSL from BattleFx_RasterQuad: A = line; points WMADD at that line
                                        ; of the window table picked by the frame and !BattleFx_QuadSlot
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
org $CD3ECE
BattleCD_Unk3ECE:                       ; JSL from BattleFx_LoadBgSet: queues a VRAM upload (X = source,
                                        ; A = its bank, Y = VRAM word address, DP $53 = bytes)
org $CD3ED2
BattleCD_QueueVramDma:                  ; JSR: queues A:X to VRAM word address Y, DP $53 bytes, and waits frames until
                                        ; the NMI has sent it all (in pieces); !Battle_DmaQueueBusy meanwhile
