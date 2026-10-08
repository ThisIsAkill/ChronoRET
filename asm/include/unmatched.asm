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

org $C02E1E
LoadSavePath:       ; entry for mode >= $01FF (load/save/transition)

org $C0EC60
Sub_EC60:           ; frame wait: INC $0152, then spin until the NMI clears it (after Field_EndOfFrame)

org $C0EA63
NmiHandler:         ; real NMI handler; InstallNMI points the RAM trampoline here
org $C0ECCC
IrqHandler:         ; real IRQ handler; InstallIRQ points the RAM trampoline here

; --- Bank $C0 field/scene callees (names from observed behavior; Unk
; --- where the body has not been read closely enough to say more) ---

org $C0024C
Scene_Unk024C:      ; scene-state probe from DefaultHandler; C=1 quick clear, C=0 full init
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
org $C01AAC
Field_Unk1AAC:      ; per-frame (GameLoop_FrameBody); tests $00F6 bit 7, counts dp $34
org $C01B53
LocLoad_AudioSetup: ; fills the $1E00 audio command block and JSLs Audio_DriverCommand
org $C01F87
Field_Unk1F87:      ; per-frame JSL target (GameLoop_FrameBody); dispatches on dp $29 countdown, RTL
org $C021E1
Field_EventHookDispatch: ; per-frame; if dp $39 != 0, JSR through table $C0:21EE[dp $39 - 1]
org $C0274D
Field_Unk274D:      ; per-frame; tests dp $54 bits 2-5 against $1D0A/$1D0C/$1D0E
org $C02848
Scene_SettleFrames: ; Scene_ReloadStep once; if it returns 0, raises Fade_Brightness (dp $19) one step
                    ; per frame (frame update, Field_EndOfFrame, frame wait) until it reaches $0F
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
org $C075E9
Field_BuildC800Mode1: ; writes a buffer at WRAM $7E:C800 through WMDATA (DefaultHandler mode 1/3)
org $C078EC
Field_BuildC800Mode2: ; as above, mode 2/3 variant
org $C07CB5
Field_BuildC800Mode4: ; as above, mode 4 variant
org $C07F7E
LocLoad_ClearPage1D00: ; ClearRAMDMA of $7E:1D00-$1DFF
org $C087F1
Field_Unk87F1:      ; DP=$1D00 finalizer after the $C800 builders (DefaultHandler)
org $C0881E
Field_FrameUpdate:  ; per-frame update with DP=$1D00 (sets $01EB=$80, calls $88E5/$88EE/...)
org $C0885A
Field_Unk885A:      ; DP=$1D00; dispatches on $0138 (DefaultHandler fade path)
org $C0A33B
LocLoad_UnkA33B:    ; location-load step; reads byte 4 of the location record, table $F6:1E00
org $C0A810
Vblank_UnkA810:     ; Field_EndOfFrame step; reads $7F:2000
org $C0AF4E
Field_UnkAF4E:      ; acts on dp $44 bits 0/1 with $F0 = $3000/$3040 ...

; --- Bank $C0 data tables read by matched code ---

org $C0FD00
BitReverseTable:    ; 256 bytes: each index with its 8 bits reversed (verified against the ROM);
                    ; Spr_CopyTileFlipped mirrors tile rows through it (read as $00:FD00, DB=$00)

; --- Other banks, called from bank $C0 ---

org $C10000
EngCall_BattleMain: ; JSL target that enters the battle engine (bank $C1 calls it Battle_Main)
org $C20000
BankC2_Entry0000:   ; JML target for game mode >= $01F0 (GameLoop_Main)
org $C28000
BankC2_Entry8000:   ; JSL with A = a mode value before InitHW (callers say "set BG mode"; unverified)
org $C28004
BankC2_Entry8004:   ; JSL with A = a command; 15 JSL sites (GameLoop passes !BankC2_BootArg, at boot and on each $C0:02CA re-entry)
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
