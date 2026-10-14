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
