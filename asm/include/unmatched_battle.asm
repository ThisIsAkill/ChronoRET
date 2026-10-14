; ============================================================
; unmatched_battle.asm — Names for routines that the matched battle
; code calls but that are not matched yet (in bank $C1 or elsewhere).
;
; Same format as unmatched.asm: label-only `org` stubs, no bytes. When a
; routine gets matched, delete its stub here; the real label takes over.
; Names come from the reference disassembly / earlier session notes;
; the comment says what the call site expects.
; ============================================================

; --- Bank $CD after the matched part (script opcode handlers and the code the matched $CD/$D1 code calls) ---

org $CD2A4A
BattleCD_FxOp80:                        ; script opcode $80 handler (BattleCD_FxOpTable)
org $CD2DCB
BattleCD_FxOp81:                        ; script opcode $81 handler (BattleCD_FxOpTable)
org $CD2DD6
BattleCD_FxOp82:                        ; script opcode $82 handler (BattleCD_FxOpTable)
org $CD2E13
BattleCD_FxAddScrollY:                  ; JSR/JMP: the channel ($43)'s !BattleFx_BounceOut + the word at DP $45 (opcode $82's helper)
org $CD2E3C
BattleCD_FxSubScrollX:                  ; JMP: the channel's !Battle_FxScrollAddX - the word at DP $45
org $CD2E4D
BattleCD_FxAddScrollX:                  ; JMP: the channel's !Battle_FxScrollAddX + the word at DP $45
org $CD2E78
BattleCD_FxSubScrollY:                  ; JSR: the channel's !BattleFx_BounceOut - the word at DP $45
org $CD2EA2
BattleCD_FxOp83:                        ; script opcode $83 handler (BattleCD_FxOpTable)
org $CD2EB5
BattleCD_FxOp84:                        ; script opcode $84 handler (BattleCD_FxOpTable)
org $CD2EC8
BattleCD_FxOp85:                        ; script opcode $85 handler (BattleCD_FxOpTable)
org $CD2EDE
BattleCD_FxOp86:                        ; script opcode $86 handler (BattleCD_FxOpTable)
org $CD2EF7
BattleCD_FxOp90:                        ; script opcode $90 handler (BattleCD_FxOpTable)
org $CD2F4E
BattleCD_FxOp91:                        ; script opcode $91 handler (BattleCD_FxOpTable)
org $CD2F61
BattleCD_FxOp92:                        ; script opcode $92 handler (BattleCD_FxOpTable)
org $CD2F6E
BattleCD_FxOp93:                        ; script opcode $93 handler (BattleCD_FxOpTable)
org $CD2F8B
BattleCD_FxOp94:                        ; script opcode $94 handler (BattleCD_FxOpTable)
org $CD2FAB
BattleCD_FxOp95:                        ; script opcode $95 handler (BattleCD_FxOpTable)
org $CD2FB1
BattleCD_FxOp96:                        ; script opcode $96 handler (BattleCD_FxOpTable)
org $CD2FB7
BattleCD_FxOp8B:                        ; script opcode $8B handler (BattleCD_FxOpTable)
org $CD2FBC
BattleCD_FxOp89:                        ; script opcode $89 handler (BattleCD_FxOpTable)
org $CD2FED
BattleCD_FxOp8A:                        ; script opcode $8A handler (BattleCD_FxOpTable)
org $CD3017
BattleCD_FxOpA0:                        ; script opcode $A0 handler (BattleCD_FxOpTable)
org $CD3020
BattleCD_FxOp9F:                        ; script opcode $9F handler (BattleCD_FxOpTable)
org $CD3029
BattleCD_FxOp9E:                        ; script opcode $9E handler (BattleCD_FxOpTable)
org $CD3032
BattleCD_FxOp9D:                        ; script opcode $9D handler (BattleCD_FxOpTable)
org $CD303B
BattleCD_FxOp9C:                        ; script opcode $9C handler (BattleCD_FxOpTable)
org $CD3083
BattleCD_FxOp9B:                        ; script opcode $9B handler (BattleCD_FxOpTable)
org $CD308C
BattleCD_FxOp9A:                        ; script opcode $9A handler (BattleCD_FxOpTable)
org $CD3092
BattleCD_FxOp98:                        ; script opcode $98 handler (BattleCD_FxOpTable)
org $CD30B8
BattleCD_FxOp99:                        ; script opcode $99 handler (BattleCD_FxOpTable)
org $CD30BE
BattleCD_FxOp97:                        ; script opcode $97 handler (BattleCD_FxOpTable)
org $CD35A5
BattleCD_Unk35A5:                       ; JSR from BattleCD_FxOpWindowBand after it fills !Battle_FxWinLines
org $CD3657
BattleCD_Unk3657:                       ; JSR from BattleCD_FxOp3657 (script opcode $A1) with A = the operand
org $CD367C
BattleCD_FillTriangle:                  ; JSR/JMP: fills the triangle of the three points in DP $12-$17 for object
                                        ; !BattleFx_QuadSlot, probably (it sorts them by y first, with DB = $00; not analysed)
org $CD38B2
BattleCD_Unk38B2:                       ; JSL from BattleFx_RasterQuad: A = line; points WMADD at that line
                                        ; of the window table picked by the frame and !BattleFx_QuadSlot
org $CD38E5
BattleCD_Unk38E5:                       ; JSR from BattleCD_FxOpTriCentre (DB = $00): DP $0B/$0C two y, DP $0D an x distance;
                                        ; returns a slope in Y, probably
org $CD3924
BattleCD_Unk3924:                       ; JSR from BattleCD_FxOp3924 (script opcode $B8) with A = the operand

; --- Bank $CE battle code (called from banks $CD and $D1; none analysed) ---

org $CEE000
BattleCE_UnkE000:                       ; JSL from BattleCD_FxOpCEE000 (script opcode $B2)
org $CEE18E
BattleCE_UnkE18E:                       ; JSL from BattleCD_NmiMain (with !Battle_Unk2A21 bit 0)
org $CEE7CF
BattleCE_UnkE7CF:                       ; JSL from BattleCD_CalcAngle: two points in DP $23-$26; leaves an angle in DP $45, probably
org $CEEE6E
BattleCE_UnkEE6E:                       ; JSL from BattleCD_StepWipe at an opening wipe's start, A = !BattleFx_CeSet,
                                        ; and from BattleFx_Init / BattleFx_ReloadCeSet (A = the set); copies records
                                        ; from bank $CE to $7E:C867 and on
org $CEF066
BattleCE_UnkF066:                       ; JSL from BattleCD_NmiMain unless !Battle_UnkCD2D / !Battle_UnkA028
