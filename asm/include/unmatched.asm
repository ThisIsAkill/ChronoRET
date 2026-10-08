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

org $C0034B
Field_Unk034B:      ; Scene_Unk024C's no-battle path: sets Field_Unk7F03FE from the party slots, may BRL Field_IdleFrame
org $C0038F
Field_Unk038F:      ; Scene_Unk024C's battle path: JSR $039B/$041A/$04ED, BRL $066D; fills $7E:29xx/$7E:2Cxx
org $C00617
Field_Unk0617:      ; 8-bit X/Y: lists objects of kind 5/6 ($1100,X) near the screen tile origin in dp $9D.. (max 12, $80 ends)
org $C00283
Scene_Unk0283:      ; scene post-init from DefaultHandler; starts JSR $B262, JSR Field_RestoreSaveBlock
org $C0092B
LocLoad_Unk092B:    ; location-load step 1 (LoadLocation); multiplies dp $00 by 14 via WRMPYA/B
org $C00960
LocLoad_Unk0960:    ; location-load step; reads byte 1 of the $F6:0000 location record (index dp $FE)
org $C009DD
LocLoad_Unk09DD:    ; location-load step; reads byte 1 of the location record, table $F6:2100
org $C00A14
LocLoad_Unk0A14:    ; location-load step; skipped when dp $BB != 0; table $F6:21C0
org $C01B53
LocLoad_AudioSetup: ; fills the $1E00 audio command block and JSLs Audio_DriverCommand
org $C01F87
Field_Unk1F87:      ; per-frame JSL target (GameLoop_FrameBody); dispatches on dp $29 countdown, RTL
org $C0286C
Scene_ReloadStep:   ; long chain of scene re-init JSRs (TileAnimList_ApplyAll, $0A50, $6F79, ...)
org $C028AA
TileAnimList_Clear: ; fills the 16-word list at $7F:1CC8 with $8080 (empty)
org $C028C0
TileAnimList_AddCurrent: ; adds dp $5B to the $7F:1CC8 list unless already present
org $C028E1
TileAnimList_ApplyAll: ; for each non-empty $7F:1CC8 entry, applies it through $28F9 ($7E:3000 table)
org $C056A6
Scene_PostLoadInit: ; sets dp $69/$6B, clears $09A0, runs object/entity init incl. Evt_RunObj0Func1
org $C056D4
LocLoad_Unk56D4:    ; location-load step; reads byte 8 of the location record, table $FC:F9F0
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
org $C06DCF
LocLoad_Unk6DCF:    ; location-load step; reads byte 2 of the location record, table $F6:2220
org $C07084
LocLoad_Unk7084:    ; location-load step; reads byte 3 of the location record (x $D2 records)
org $C074D4
Field_Unk74D4:      ; DP=$1D00; clears dp $99/$87/$89 then JSR $7F9A
org $C074E8
Field_Unk74E8:      ; DP=$1D00; clears dp $9B/$8B/$8D then shares Field_Unk74D4's tail
org $C074F7
Field_Unk74F7:      ; DP=$1D00; clears dp $9D/$8F/$91 then shares Field_Unk74D4's tail
org $C087F1
Field_Unk87F1:      ; DP=$1D00 finalizer after the $C800 builders (DefaultHandler)
org $C08A6D
Map_Unk8A6D:        ; Field_FrameUpdate, X/Y 8-bit, when Field_Unk20 is set (DP=$1D00)
org $C0A33B
LocLoad_UnkA33B:    ; location-load step; reads byte 4 of the location record, table $F6:1E00
org $C0A810
Vblank_UnkA810:     ; Field_EndOfFrame step; reads $7F:2000
org $C0AF4E
Field_UnkAF4E:      ; acts on dp $44 bits 0/1 with $F0 = $3000/$3040 ...

; --- Other banks, called from bank $C0 ---

org $C10000
EngCall_BattleMain: ; JSL target that enters the battle engine (bank $C1 calls it Battle_Main)
org $C18003
BankC1_Entry8003:   ; JSL vector (JMP $CFC2): saves P/X/DP/DB, DB=$7E, DP=0, runs service A (table
                    ; $C1:D126, 6 entries) with argument Y; 1 = add item Y ($C1:D005), 4 = add Y gold
                    ; ($C1:D0A2); returns a result in A
org $C203EF
C2Scene_Unk03EF:    ; scene-mode boot step (BankC2_SceneBoot); also JSR from $C2:2560/$25F0
org $C21DB5
C2Scene_Unk1DB5:    ; scene-mode boot step (BankC2_SceneBoot)
org $C223A8
C2Scene_Main:       ; scene-mode main (JMP from BankC2_SceneBoot): sets C2Scene_NmiFlags, NMI on,
                    ; then dispatches on $027C
org $C2034D
C2Scene_Unk034D:    ; per-frame NMI step; stores $E0 (an off-screen Y?) into OAM shadow bytes
org $C2051D
C2Scene_Unk051D:    ; per-frame NMI step; walks $40-byte records at $0B30-$1B2F, calling each
                    ; non-zero one's handler
org $C20C4D
C2Scene_Unk0C4D:    ; per-frame NMI step (DB=$7E; builds $7E:B000-$B5xx)
org $C20CEA
C2Scene_Unk0CEA:    ; per-frame NMI step
org $C257DF
TextWin_Init:       ; JSL via BankC2_Entry0003/0006 (DP=$0200)
org $C25823
TextWin_Step:       ; JSL via BankC2_Entry0009/000C (DP=$0200)
org $C28000
BankC2_Entry8000:   ; JSL with A = a mode value before InitHW (callers say "set BG mode"; unverified)
org $C28002
BankC2_Entry8002:   ; JSL: joypad read (BRA to JSR $84D2; RTL); also from the scene NMI
org $C28004
BankC2_Entry8004:   ; JSL with A = a command; 15 JSL sites (GameLoop passes !BankC2_BootArg, at boot and on each $C0:02CA re-entry)
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
org $FDFFF4
FdVec_FFF4:         ; bank $FD service vector: JMP $E292 (runs with DP=$0500)
org $FDFFF7
FdVec_FFF7:         ; bank $FD service vector: JMP $E39C (runs with DP=$0500)
org $FDFFFA
FdVec_FFFA:         ; bank $FD service vector: JMP $DE98 (runs with DP=$0500)
