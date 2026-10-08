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

org $C0EC60
Sub_EC60:           ; frame wait: INC $0152, then spin until the NMI clears it (after Field_EndOfFrame)

org $C0EA63
NmiHandler:         ; real NMI handler; InstallNMI points the RAM trampoline here
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
org $C059D9
Vblank_Unk59D9:     ; Field_EndOfFrame step; runs with DP=$1000, reads $7F:2000
org $C05A46
Vblank_ReadScanlineCounters: ; Field_EndOfFrame step; latches and reads OPVCT via SLHV/STAT78
org $C05F6E
Evt_UnusedOpcode:   ; event opcode handler shared by the unused opcodes (Evt_OpcodeTable's end);
                    ; LDX #$1639, BRL LoadSavePath. Also Field_EventHookTable entries 15-16
org $C05D6E
Evt_OpcodeTable:    ; word jump table of event-script opcode handlers (JSR (table,X) in
                    ; Evt_RunObj0Func1 / Evt_RunObjInit); opcode $00 ends a function
org $C06F9A
Obj_Unk6F9A:        ; JSR (table $C0:6FA7, x Obj_Unk1100) unless Obj_Unk1100 bit 7; run when an object
                    ; enters the view window (Obj_UpdateInView, Obj_ActivateIfInView; not traced)
org $C07056
Obj_Unk7056:        ; Obj_UpdateInView's drop step: frees the object's $0B88 entry (index
                    ; Obj_TileRecOfs >> 5) when it holds Obj_Cur; C=1 then (not traced)
org $C07170
Obj_Unk7170:        ; JSR (table $C0:7181, x Obj_Unk1100) unless Field_Unk54 or Obj_Unk1100 bit 7;
                    ; with Obj_Unk6F9A on entering the view window (not traced)
org $C072B4
Obj_Unk72B4:        ; FieldBtl_SaveObj, for an object with Obj_Unk1A81 bit 7 set; writes its
                    ; $0B00/$0B80 entries and Obj_OamAttr palette bits, copies $E4 colours (not traced)
org $C0734C
Obj_Unk734C:        ; FieldBtl_RestoreObj's removal, for Obj_Unk1A81 bit 7 set; undoes Obj_Unk72B4's
                    ; $0B00/$0B80 links (probably; not traced)

; --- Other banks, called from bank $C0 ---

org $C10000
EngCall_BattleMain: ; JSL target that enters the battle engine (bank $C1 calls it Battle_Main)
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
org $FDC1EE
Hdma_InitChannelsFD: ; DP=$4300; writes DMAP0-7 / BBAD (HDMA channel setup)
org $FDC2C1
EngFD_UnkC2C1:      ; called with 8-bit X once a frame; dispatches via table $FD:C2E5 on dp $26
                    ; unless dp $53 bit 0 is set (earlier notes guessed an audio tick; unverified)
org $FDC124
EngFD_UnkC124:      ; DB=$7F; ORs Map_TilemapVram4.. bytes into HDMA table bytes from $7F:14F0 (not traced)
org $FDFFF4
FdVec_FFF4:         ; bank $FD service vector: JMP $E292 (runs with DP=$0500)
org $FDFFF7
FdVec_FFF7:         ; bank $FD service vector: JMP $E39C (runs with DP=$0500)
org $FDFFFA
FdVec_FFFA:         ; bank $FD service vector: JMP $DE98 (runs with DP=$0500)
