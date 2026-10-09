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





org $C0F05E
Irq_UnkF05E:        ; JSR from Irq_UploadTileAnim while Field_Unk63 is not negative (the message
                    ; choice cursor, probably); not analysed

; --- Bank $C0 field/scene callees (names from observed behavior; Unk
; --- where the body has not been read closely enough to say more) ---


; --- Other banks, called from bank $C0 ---

org $C10000
EngCall_BattleMain: ; JSL target that enters the battle engine (bank $C1 calls it Battle_Main)
org $C293A8
Menu_Unk93A8:       ; JSR from Menu_ListEquipItems with Menu_ItemId set: A = 0 leaves the item out of
                    ; the list (probably "the current character cannot equip it"; not matched)
org $C292F4
Menu_Unk92F4:       ; JSR from Menu_InitSystems (not matched)
org $C2D156
Menu_UnkD156:       ; JSR from Menu_InitSystems (not matched)
org $C2E91B
Menu_UnkE91B:       ; thread 3, started by Menu_RunThreads (not matched)
org $C2F3CA
Menu_UnkF3CA:       ; JSR from Menu_InitSystems (not matched)
org $C2F5ED
Menu_UnkF5ED:       ; JSR from Menu_Unk834D, A = a character id: returns X = $4B00 + 6 x a byte the
                    ; character picks (via $CD:6CEC) and A = 5, the MVN source and count (not matched)
org $FFF9BB
BankFF_CharBits:    ; 8 B read by Menu_CmdJoin: $80 >> character id, the character's Menu_Unk29AF bit
org $FFF9C4
BankFF_UnkF9C4:     ; JSL from Menu_CmdBootCheckSaves with DP=$0400: A = 0 or not for slot
                    ; Menu_SaveSlot ($0479); probably checks a save slot in SRAM (not analysed)
org $C29137
Menu_Unk9137:       ; JSR from Menu_RefreshAllChars after Menu_LoadCharRec (also from three other
                    ; menu sites): works on Menu_CurCharRec, probably the character's derived stats
                    ; (not analysed)
org $FFF813
BankFF_UnkF813:     ; JSL from Menu_BuildItemTables (not analysed)
org $FFF958
BankFF_UnkF958:     ; JSL from Menu_Unk834D (not analysed)
org $C299CA
Menu_Mode00List:    ; Menu_ModeLists entries: lists of handler addresses (not matched)
org $C29C29
Menu_Mode01List:
org $C2AA34
Menu_Mode02List:
org $C2B353
Menu_Mode03List:
org $C2BF35
Menu_Mode04List:
org $C2C621
Menu_Mode05List:
org $C2CED4
Menu_Mode06List:
org $C2C7A6
Menu_Mode07List:
org $C2D4F0
Menu_Mode0BList:
org $C2D519
Menu_Mode0CList:
org $C2E1E3
Menu_Mode0DList:
org $C2E60B
Menu_Mode0EList:
org $C2FE0A
Menu_Mode0FList:
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
org $FDFFFD
FdVec_FFFD:         ; JMP $FD:E022; JSL from IrqHandler on the frames Field_Unk53 bit 0 is set
                    ; (not analysed)
org $FDFFF1
FdVec_FFF1:         ; JMP $FD:DA00; JML target of Evt_OpFF_Misc for $FF $80
org $FDE39C
EngFD_UnkE39C:      ; FdVec_FFF7's routine, run every frame by Field_EndOfFrame; works on the FieldAnimB
                    ; records at $0520 (not analysed)
