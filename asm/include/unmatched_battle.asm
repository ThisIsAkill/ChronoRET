; ============================================================
; unmatched_battle.asm — Names for routines that the matched battle
; code calls but that are not matched yet (in bank $C1 or elsewhere).
;
; Same format as unmatched.asm: label-only `org` stubs, no bytes. When a
; routine gets matched, delete its stub here; the real label takes over.
; Names come from the reference disassembly / earlier session notes;
; the comment says what the call site expects.
; ============================================================

; --- Bank $CD after the matched part (script opcode handlers and the code they call) ---
org $CD2433
BattleCD_ClampCalcPair:                 ; JSR: clamps the two points at !Battle_ActCalcResult+X to the screen (X kept)
org $CD2436
BattleCD_ClampCalcPair01:               ; JSR: the same for entries 0 and 1 (X = 0 inside; X kept)
org $CD2460
BattleCD_FxOpBeam:                      ; script opcode $AC handler (BattleCD_FxOpTable)
org $CD2466
BattleCD_FxOpBeamQuad:                  ; JMP from BattleCD_FxOpBeamFromPair: the rest of script opcode $AC
org $CD24F3
BattleCD_FxOpAB:                        ; script opcode $AB handler (BattleCD_FxOpTable)
org $CD2518
BattleCD_FxOpA9:                        ; script opcode $A9 handler (BattleCD_FxOpTable)
org $CD253B
BattleCD_FxOp8F:                        ; script opcode $8F handler (BattleCD_FxOpTable)
org $CD2660
BattleCD_FxOpA7:                        ; script opcode $A7 handler (BattleCD_FxOpTable)
org $CD2687
BattleCD_FxOp87:                        ; script opcode $87 handler (BattleCD_FxOpTable)
org $CD2690
BattleCD_FxOpA5:                        ; script opcode $A5 handler (BattleCD_FxOpTable)
org $CD26C0
BattleCD_FxOpA6:                        ; script opcode $A6 handler (BattleCD_FxOpTable)
org $CD26E0
BattleCD_FxOpA4:                        ; script opcode $A4 handler (BattleCD_FxOpTable)
org $CD2717
BattleCD_FxOpA3:                        ; script opcode $A3 handler (BattleCD_FxOpTable)
org $CD278E
BattleCD_FxOpA2:                        ; script opcode $A2 handler (BattleCD_FxOpTable)
org $CD27CA
BattleCD_FxOpA8:                        ; script opcode $A8 handler (BattleCD_FxOpTable)
org $CD2952
BattleCD_FxOpA1:                        ; script opcode $A1 handler (BattleCD_FxOpTable)
org $CD2958
BattleCD_FxOp8C:                        ; script opcode $8C handler (BattleCD_FxOpTable)
org $CD2999
BattleCD_FxOp8D:                        ; script opcode $8D handler (BattleCD_FxOpTable)
org $CD29DA
BattleCD_FxOp88:                        ; script opcode $88 handler (BattleCD_FxOpTable)
org $CD29E3
BattleCD_FxOp8E:                        ; script opcode $8E handler (BattleCD_FxOpTable)
org $CD2A4A
BattleCD_FxOp80:                        ; script opcode $80 handler (BattleCD_FxOpTable)
org $CD2DCB
BattleCD_FxOp81:                        ; script opcode $81 handler (BattleCD_FxOpTable)
org $CD2DD6
BattleCD_FxOp82:                        ; script opcode $82 handler (BattleCD_FxOpTable)
org $CD2E13
BattleCD_FxAddScrollY:                  ; JSR/JMP: the channel ($43)'s !Battle_FxScrollAddY + the word at DP $45 (opcode $82's helper)
org $CD2E3C
BattleCD_FxSubScrollX:                  ; JMP: the channel's !Battle_FxScrollAddX - the word at DP $45
org $CD2E4D
BattleCD_FxAddScrollX:                  ; JMP: the channel's !Battle_FxScrollAddX + the word at DP $45
org $CD2E78
BattleCD_FxSubScrollY:                  ; JSR: the channel's !Battle_FxScrollAddY - the word at DP $45
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
org $CD367C
BattleCD_FillTriangle:                  ; JSR/JMP: fills the triangle of the three points in DP $12-$17 for object
                                        ; !Battle_FxTriObject, probably (it sorts them by y first, with DB = $00; not analysed)
org $CD38E5
BattleCD_Unk38E5:                       ; JSR from BattleCD_FxOpTriCentre (DB = $00): DP $0B/$0C two y, DP $0D an x distance;
                                        ; returns a slope in Y, probably
org $CD3924
BattleCD_Unk3924:                       ; JSR from BattleCD_FxOp3924 (script opcode $B8) with A = the operand

; --- Bank $D1 battle code (called from bank $CD; none analysed) ---
org $D1E70A
BattleD1_UnkE70A:                       ; JSL from BattleCD_FxOpD1E70A (script opcode $E1)
org $D1E8D9
BattleD1_UploadPage:                    ; JSL from BattleCD_NmiUploadText: A:X = a tilemap page, DP $45 = a VRAM address
org $D1EA4B
BattleD1_UnkEA4B:                       ; JSL from BattleCD_NmiMain (with !Battle_Unk2A21 bit 0)
org $D1EBFF
BattleD1_UnkEBFF:                       ; JSL from BattleCD_FxOpD1EBFF (script opcode $F4)
org $D1ECF3
BattleD1_UnkECF3:                       ; JSL from BattleCD_FrameTick, A = !Battle_UnkCD45
org $D1EDCD
BattleD1_UnkEDCD:                       ; JSL from BattleCD_FxOpD1EDCD (script opcode $EE)
org $D1EEA5
BattleD1_UnkEEA5:                       ; JSL from BattleCD_FxOpD1EEA5 (script opcode $EC)
org $D1EEC4
BattleD1_UnkEEC4:                       ; JSL from BattleCD_FxOpD1EEC4 (script opcode $ED)
org $D1EFD0
BattleD1_UnkEFD0:                       ; JSL from BattleCD_FxOpD1EFD0 (script opcode $F3)
org $D1EFE3
BattleD1_UnkEFE3:                       ; JSL from BattleCD_FxOpD1EFE3 (script opcode $EB)
org $D1F1B0
BattleD1_InitBattle:                    ; JSL from BattleCD_EnterBattle: sets DB=$7E, DP=0, the NMI/IRQ trampolines
                                        ; and many bank-$CD variables
org $D1F426
BattleD1_UnkF426:                       ; JSL from BattleCD_NmiMain and BattleCD_NmiSetup
org $D1F47C
BattleD1_UnkF47C:                       ; JSL from BattleCD_FxOpD1F47C (script opcode $DF)
org $D1F4C0
BattleD1_NmiExit:                       ; the NMI trampoline's target BattleCD_ExitBattle installs (JML at $0500)
org $D1F559
BattleD1_UnkF559:                       ; JSL from BattleCD_FxOpD1F559 (script opcode $CE)
org $D1F5CD
BattleD1_UnkF5CD:                       ; JSL from BattleCD_FxOpD1F5CD (script opcode $DD)
org $D1F5F5
BattleD1_UnkF5F5:                       ; JSL from BattleCD_FxOpD1F5F5 (script opcode $DB)
org $D1F67A
BattleD1_ActOp80:                       ; JSL from BattleCD_ActOp80 (action opcode $80)
org $D1FB68
BattleD1_UnkFB68:                       ; JSL from BattleCD_FxOpD1FB68 (script opcode $E9)
org $D1FB72
BattleD1_UnkFB72:                       ; JSL from BattleCD_FxOpD1FB72 (script opcode $E8)
org $D1FD7E
BattleD1_UnkFD7E:                       ; JSL from BattleCD_FxOpD1FD7E (script opcode $CF)

; --- Bank $CE battle code (called from bank $CD; none analysed) ---
org $CEE000
BattleCE_UnkE000:                       ; JSL from BattleCD_FxOpCEE000 (script opcode $B2)
org $CEE18E
BattleCE_UnkE18E:                       ; JSL from BattleCD_NmiMain (with !Battle_Unk2A21 bit 0)
org $CEE7CF
BattleCE_UnkE7CF:                       ; JSL from BattleCD_CalcAngle: two points in DP $23-$26; leaves an angle in DP $45, probably
org $CEEE6E
BattleCE_UnkEE6E:                       ; JSL from BattleCD_StepWipe at an opening wipe's start, A = !Battle_UnkCA22
org $CEF066
BattleCE_UnkF066:                       ; JSL from BattleCD_NmiMain unless !Battle_UnkCD2D / !Battle_UnkA028
