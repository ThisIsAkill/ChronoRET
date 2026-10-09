; ============================================================
; unmatched.asm — Names for routines that matched code calls but that
; are not matched yet.
;
; Each entry is a label-only `org` stub: it emits no bytes, it only gives
; the call site a name instead of an address. When a routine gets
; matched, delete its stub here; the real label in the bank file takes
; over and every call site keeps working unchanged.
;
; Keeping these out of the bank files is deliberate: game code holds
; only game code (see tools/lint_readability.py, rule PLUMB).
; ============================================================

; --- Bank $C0 ---

org $C00AFF
AudioDrvSync:       ; JSL re-entry: force 2 audio driver ticks, restore DB/DP; RTL

org $C01BAB
MusicCueDispatch:   ; JSL re-entry: SPC start ($14) or fade ($70) per $7E2A1F bit 6; RTL

org $C01BE6
AudioFadeDispatch:  ; JSL re-entry: conditional SPC fade/start via $7F01EC counter; RTL

org $C02C41
ScrollStepAccum:    ; JSL re-entry: accumulate $7F341x scroll deltas into $7F341D/E; RTL

org $C0ECCC
IrqHandler:         ; real IRQ handler; InstallIRQ points the RAM trampoline here

; --- Bank $C0 field/scene callees (names from observed behavior; Unk
; --- where the body has not been read closely enough to say more) ---

org $C01F87
Field_Unk1F87:      ; per-frame JSL target (GameLoop_FrameBody); dispatches on dp $29 countdown, RTL
org $C028AA
TileAnimList_Clear: ; fills the 16-word list at $7F:1CC8 with $8080 (empty)
org $C028C0
TileAnimList_AddCurrent: ; adds dp $5B to the $7F:1CC8 list unless already present
org $C028E1
TileAnimList_ApplyAll: ; for each non-empty $7F:1CC8 entry, applies it through $28F9 ($7E:3000 table)

; --- Other banks, called from bank $C0 ---

org $C10000
EngCall_BattleMain: ; JSL target that enters the battle engine (bank $C1 calls it Battle_Main)
org $C22273
C2Scene_Unk2273:    ; JSL from C2Scene_ObjBMateAim: probably the cosine of direction A (0-255): adds $40
                    ; and runs into C2Scene_Unk2277 (not matched)
org $C22277
C2Scene_Unk2277:    ; JSL: probably the sine of direction A from Rom_SineTable256 (sign-extended; $0080 and
                    ; $FF80 at $40 and $C0) through DB $00 (not matched)
org $C2229D
C2Scene_Unk229D:    ; JSR from C2Scene_ObjBMateAim: probably the direction (0-255) between the points
                    ; (C2Tmp_08, $0A) and (C2Tmp_0C, $0E) on the wrapping map, through the angle table at
                    ; $C0:F300 (DB $00); X = the table index, 0 within 4 pixels (not matched)
org $C2631F
C2Scene_Unk631F:    ; JSR from C2Scene_Mode6: BG mode 7, OBSEL, clears VRAM and the tasks, loads from bank $C6,
                    ; spawns task $C2:666C and script $C2:69F8, then runs frames until C2Scene_Mode is not 6
org $C26A34
C2Scene_Unk6A34:    ; JSR from C2Scene_Mode8: starts with C2Scene_ClearVram (not traced further)
org $C2800E
BankC2_MenuEntry:   ; BRA from BankC2_Entry8000: SEI, native mode, saves DP/DB/P, stores A at $0A00 and X
                    ; at $0A01, forced blank, then the menu (not matched)
org $C28C36
Menu_Unk8C36:       ; JSR from BankC2_CommandLong (the BankC2_Entry8004 vector), A = a command
org $C6E74E
BankC6_UnkE74E:     ; JSL from C2Scene_ObjBFly: C2Tmp_06 = 0 when the tile (C2Tmp_00, $01) is inside
                    ; columns C2Tmp_04 to $05 - 1 and rows C2Tmp_02 to $03 - 1, else bits 0-3 for
                    ; left / right / above / below (not matched)
org $C6E797
BankC6_UnkE797:     ; JSL from C2Scene_ObjAFly before object A comes down: takes the task's 8x8 tile
                    ; and dispatches on Loc_Id - $1F0 through a table at $C6:E7BA; C=1 keeps it up
org $C30000
BankC3_Entry0000:   ; JML target (Field_HookLeaveToBankC3, A = $85): reinstalls the NMI/IRQ
                    ; trampolines into bank $C3, unpacks code via $C3:0557 from a $FE:0003 pointer
                    ; to $7E:3000 and JMLs there; never returns to the field
org $C30008
BankC3_Entry0008:   ; JSL vector (JMP $0077): builds a window table from $0350-$0358 (WinFx_Arg*),
                    ; A = mode; runs with DP=$0300, saves P/DP/DB (shape not traced)
org $C3000E
BankC3_Entry000E:   ; JSL vector (JMP $01E4): DP=$0300; while $0350 != 0 steps a $20-frame effect,
                    ; then clears $0350 (Field_HookWinC3E)
org $C30011
BankC3_Entry0011:   ; JSL vector (JMP $0EFA): window table from 4 points at $0360-$0367
                    ; (Field_HookWinQuad); starts from the point with the smallest Y
org $C70000
Audio_DriverInit:   ; sound driver bank $C7: init, from GameLoop (at boot and on each $C0:02CA re-entry)
org $C70004
Audio_DriverCommand: ; sound driver bank $C7: send the command block at $1E00-$1E03
org $FDC2EB
EngFD_UnkC2EB:      ; EngFD_UnkC2C1Table1 entry 0 (Field_Unk26 = 0, Field_Unk53 bit 0 set); not analysed
org $FDC995
EngFD_UnkC995:      ; EngFD_UnkC2C1Table1 entry 1; not analysed
org $FDCFCF
EngFD_UnkCFCF:      ; EngFD_UnkC2C1Table1 entry 2; not analysed
org $FDC847
EngFD_UnkC847:      ; EngFD_UnkC2C1Table0 entry 0 (Field_Unk53 bit 0 clear); not analysed
org $FDCD0C
EngFD_UnkCD0C:      ; EngFD_UnkC2C1Table0 entry 1; not analysed
org $FDD27E
EngFD_UnkD27E:      ; EngFD_UnkC2C1Table0 entry 2; not analysed
org $FDFFE5
FdVec_FFE5:         ; JMP $FD:DB1D; JML target of Evt_OpFF_Misc for $FF $83-$8F
org $FDFFE8
FdVec_FFE8:         ; JMP $FD:DABE; JML target of Evt_OpFF_Misc for $FF $82
org $FDFFEB
FdVec_FFEB:         ; JMP $FD:DA5F; JML target of Evt_OpFF_Misc for $FF $81
org $FDFFF1
FdVec_FFF1:         ; JMP $FD:DA00; JML target of Evt_OpFF_Misc for $FF $80
org $FDE39C
EngFD_UnkE39C:      ; FdVec_FFF7's routine, run every frame by Field_EndOfFrame; works on the FieldAnimB
                    ; records at $0520 (not analysed)
