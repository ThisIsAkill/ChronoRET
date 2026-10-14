; ============================================================
; Bank $C3 — the bank $C3 kernel (decompressor, module boot, window effects)
; File offset 0x030000 (bank $C3 = ROM offset $30000)
;
; $C3:0000-$C3:10BF is 65816 code, closed by the ASCII marker "CODE END
; C3" ($C3:10C0-$C3:10CA). Other banks enter it only through the vector
; table at $C3:0000-$C3:0013 (BankC3_Entry0000, Decomp_ToWramVec,
; BankC3_Entry0008/000E/0011). The rest of the bank is data and stays as
; ROM bytes: $00 fill to $C3:11FF, two packed blocks in Decomp_ToWram's
; format at $C3:1200 and $C3:1313 (the second is the module
; C3_BootModule unpacks to $7E:3000 and runs; see BankC3_PackedModule in
; include/unmatched.asm), then scene and graphics data (C2Scene_SetAnim
; reads $C3:E000).
;
; The unpacked module calls back into this bank with JSL: the kernel
; routines in $C3:0307-$C3:0528 and $C3:08B3-$C3:0EF9 have no caller in
; ROM outside it (their headers name the module's call sites, found by
; unpacking it; those addresses are in WRAM bank $7E and are not checked
; by any tool).
; ============================================================

arch snes.cpu
hirom

incsrc "../hardware.inc"

; ============================================================
; Entry vectors ($C3:0000–$C3:0013)
; ============================================================

; $C3:0000 — BankC3_Entry0000 (20 bytes, $0000–$0013): the bank's entry
; vectors, reached from other banks by JML/JSL:
;   $0000 BankC3_Entry0000 → C3_BootModule (JML from
;         Field_HookLeaveToBankC3 and Evt_OpFF_Misc; never returns)
;   $0002 Decomp_ToWramVec → Decomp_ToWram (JSL)
;   $0008 BankC3_Entry0008 → WinFx_BuildCircle (JSL)
;   $000E BankC3_Entry000E → WinFx_StepFade (JSL)
;   $0011 BankC3_Entry0011 → WinFx_BuildQuad (JSL)
; $0005-$0007 and $000B-$000D hold the bytes $CE,$DE,$C2: not a JMP (no
; vector there; no reference to them was found), kept as data.
; Callers (2 JML sites): Field_HookLeaveToBankC3 ($C0:264B) and Evt_OpFF_Misc ($C0:3FE0).
; Callers of Decomp_ToWramVec (42 JSL sites): LocLoad_Unk09DD ($C0:0A0F), LocLoad_Unk0A14
;   ($C0:0A4A), Evt_Op82_InitWramSprite ($C0:46BC), Evt_Op83_InitEnemySprite ($C0:4825),
;   LocLoad_Unk56D4 ($C0:56FF), LocLoad_UploadPack ($C0:6D5D), LocLoad_UnpackPacks67 ($C0:6D93,
;   $C0:6DCA), LocLoad_Unk6DCF ($C0:6E03), Credits_LoadGfx ($C0:6E3D), LocLoad_UnkA33B ($C0:A366),
;   BattleAct_LoadCommon ($C1:4880), C2Scene_LoadObjGfx ($C2:27A2), C2Scene_LoadUnkC800 ($C2:27D9),
;   C2Scene_LoadBgGfx ($C2:280C), C2Scene_LoadBg3Gfx ($C2:284F), C2Scene_LoadBg3Map ($C2:287D),
;   C2Scene_LoadPalettes ($C2:28AB, $C2:28CC), C2Scene_LoadUnkB800 ($C2:292B), C2Scene_LoadUnkC000
;   ($C2:2959), C2Scene_LoadMetatiles ($C2:2987), C2Scene_LoadBgMaps ($C2:29B5), C2Scene_LoadUnk7000
;   ($C2:29E3), C2Scene_LoadUnk7200 ($C2:2A11), C2Scene_LoadScript ($C2:2A3F), C2Scene_LoadLists
;   ($C2:2A6D), C2Scene_LoadPartyGfx ($C2:2B7C), C2Scene_DialUnpack ($C2:721B), C2Scene_UnpackBgPack
;   ($C2:7B1B), C2Scene_UnpackBg3MapPack ($C2:7B3F), C2Scene_LoadExtraObjPack ($C2:7B7A),
;   C2Scene_LoadExtraPalette ($C2:7B9A), C2Scene_LoadUnkC600 ($C2:7BBF), Menu_SprLoad ($C2:F542) and
;   unmatched ($C6:E048, $C6:E06D, $C6:E66A, $C6:E68F, $D1:ED38, $D1:EDB4, $FF:F690).
; Callers of BankC3_Entry0008 (13 sites: 2 JSR, 11 JSL): Field_HookWinGrow0 (JSL $C0:225C),
;   Field_HookWinShrink0 (JSL $C0:22B7), Field_HookWinGrow1 (JSL $C0:237D), Field_HookWinShrink1
;   (JSL $C0:23DD), Field_HookWinFixedA (JSL $C0:2579), Field_HookWinFixedB (JSL $C0:25FE),
;   Field_WinPulseDraw (JSL $C0:2748), C2Scene_Win1Step (JSL $C2:7952), C2Scene_Win2Step (JSL
;   $C2:79B0) and unmatched (JSR $C3:D16C, JSR $C3:DE5C, JSL $C6:E3D2, JSL $C6:E4FB).
; Callers of BankC3_Entry000E (2 JSL sites): Field_HookWinC3E ($C0:22FA) and unmatched ($C6:E27E).
; Callers of BankC3_Entry0011 (1 JSL site): Field_HookWinQuad ($C0:24A3).
; Callers note: the unpacked module JSLs $C3:000E (from $7E:3D72); it calls
;   Decomp_ToWram and the window routines by their own addresses. The JSR
;   patterns at $C3:D16C and $C3:DE5C lie in the scene data after the
;   packed module, not in code (probably data that decodes as JSR $0008).
; Entry: M, X, DP and DB any for the jump itself (BRA/JMP touch no
;        register); each target states what it needs.
; Exit:  does not return here: the target's own exit applies.
org $C30000
BankC3_Entry0000:
    BRA C3_BootModule
Decomp_ToWramVec:               ; header: see BankC3_Entry0000
    JMP Decomp_ToWram
.filler05:
    db $CE,$DE,$C2              ; never executed
BankC3_Entry0008:               ; header: see BankC3_Entry0000
    JMP WinFx_BuildCircle
.filler0B:
    db $CE,$DE,$C2              ; never executed
BankC3_Entry000E:               ; header: see BankC3_Entry0000
    JMP WinFx_StepFade
BankC3_Entry0011:               ; header: see BankC3_Entry0000
    JMP WinFx_BuildQuad

; ============================================================
; Module boot and its interrupt handlers ($C3:0014–$C3:0076,
; $C3:0529–$C3:0556)
; ============================================================

; $C3:0014 — C3_BootModule (99 bytes, $0014–$0076)
; Leaves the field for the program packed at $C3:1313 (the bank $C3
; module): points the NMI and IRQ trampolines at C3_BootNmi and
; C3_BootIrq, keeps the caller's A in C3_EntryArg, unpacks the module
; with Decomp_ToWram to $7E:3000 (C3Mod_Code) and jumps there. Only the
; low word of the pack pointer C3Rom_PackPtrs entry 1 ($FE:0003) is read;
; the bank is the constant $C3. With C3_BootIrqOn (bit 7) in A it also
; turns the screen on at full brightness, HDMA off, NMI plus the V-count
; IRQ at line 211 and interrupts on, so the picture stays up while it
; unpacks (C3_BootNmi / C3_BootIrq: shown down to line 211, blanked
; below); without it, interrupts stay off (SEI) and NMITIMEN keeps only
; the auto-joypad read. The module's code reads C3_EntryArg (bits 0-4
; pick its program, from the module's own table; how is not traced here).
; Callers note: reached only from BankC3_Entry0000 (BRA).
; Entry: M=1 (8-bit A), X=0 (16-bit X: the trampoline addresses),
;        DP any (no direct-page operand), DB=$00 (the trampolines, the
;        PPU/CPU registers and Decomp_Src.. are absolute); A = the
;        argument: Field_HookLeaveToBankC3 passes BankC3_HookArg ($85),
;        Evt_OpFF_Misc the event's sub $00-$7F; both set S = StackTop.
; Exit:  never returns: JML C3Mod_Code with M=1, X=0, DP and DB as on
;        entry, A = $30C3 (the bank byte and the low byte of
;        C3Mod_Code's address), X = C3_BootNmi's address, Y as on
;        entry; C3_EntryArg = the argument; Decomp_OutLen = the module's
;        length ($857F).
; Calls: Decomp_ToWram.
C3_BootModule:
    SEI
    PHA
    LDA.b #!Op_JML
    STA.w !NmiTrampoline
    STA.w !IrqTrampoline
    LDX.w #C3_BootIrq
    STX.w !IrqTrampoline+1
    LDX.w #C3_BootNmi
    STX.w !NmiTrampoline+1
    LDA.b #bank(C3_BootNmi)
    STA.w !NmiTrampoline+3
    STA.w !IrqTrampoline+3
    LDA.b #AUTOJOY_ENABLE
    STA.w NMITIMEN
    PLA
    STA.w !C3_EntryArg
    BIT.b #!C3_BootIrqOn
    BEQ .unpack
    LDA.b #!Fade_BrightnessMax
    STA.w INIDISP
    STZ.w HDMAEN
    LDA.b #!Nmi_Nmitimen
    STA.w NMITIMEN
    LDX.w #!Scene_VIrqLine
    STX.w VTIMEL
    LDA.w TIMEUP                        ; clear a pending IRQ before CLI
    CLI
.unpack:
    REP #$20
    LDA.l !C3Rom_PackPtrs+3             ; entry 1's address ($1313); its bank byte is not read
    STA.w !Decomp_Src
    LDA.w #!C3Mod_Code&$FFFF
    STA.w !Decomp_Dest
    SEP #$20
    STZ.w !Decomp_DestBank              ; bank $00: bit 0 clear, so WRAM bank $7E
    LDA.b #bank(BankC3_Entry0000)
    STA.w !Decomp_SrcBank
    JSL Decomp_ToWram
    JML !C3Mod_Code

; $C3:0529 — C3_BootIrq (31 bytes, $0529–$0547)
; IRQ handler while the module is unpacked (C3_BootModule points the
; IRQ trampoline here; the module later installs its own). Acknowledges
; the timer IRQ (TIMEUP), waits for the end of the current H-blank and
; the start of the next one, and forces blank (INIDISP = $80, brightness
; 0): with the V-count IRQ at line 211, the picture is cut off from
; there to the bottom of each frame; C3_BootNmi turns it back on.
; Callers note: reached only through !IrqTrampoline (JML set by
;   C3_BootModule).
; Entry: interrupt: M, X, DP, DB any (sets M=1 itself; the stores are
;        long)
; Exit:  RTI: P (so M and X) restored; A restored (its low byte pushed
;        and pulled; the high byte is not touched at M=1); X, Y, DP, DB
;        untouched.
org $C30529
C3_BootIrq:
    SEP #$20
    PHA
    LDA.l TIMEUP
.wait_hblank_end:
    LDA.l HVBJOY
    BIT.b #!HVBJOY_HBlank
    BNE .wait_hblank_end
.wait_hblank:
    LDA.l HVBJOY
    BIT.b #!HVBJOY_HBlank
    BEQ .wait_hblank
    LDA.b #FORCED_BLANK
    STA.l INIDISP
    PLA
    RTI

; $C3:0548 — C3_BootNmi (15 bytes, $0548–$0556)
; NMI handler while the module is unpacked: acknowledges the NMI (RDNMI)
; and sets INIDISP to full brightness, display on, ending the forced
; blank C3_BootIrq set at line 211 of the frame before.
; Callers note: reached only through !NmiTrampoline (JML set by
;   C3_BootModule).
; Entry: interrupt: M, X, DP, DB any (sets M=1 itself; the stores are
;        long)
; Exit:  RTI: P restored; A restored (low byte pushed and pulled); X, Y,
;        DP, DB untouched.
C3_BootNmi:
    SEP #$20
    PHA
    LDA.l RDNMI
    LDA.b #!Fade_BrightnessMax
    STA.l INIDISP
    PLA
    RTI

; ============================================================
; The decompressor ($C3:0557–$C3:08B2)
; ============================================================

; $C3:0557 — Decomp_ToWram (860 bytes, $0557–$08B2)
; Unpacks the data at Decomp_SrcBank:Decomp_Src into WRAM from
; Decomp_Dest, writing through WMDATA, and stores the number of bytes
; written in Decomp_OutLen. The format (an LZ77 variant; checked by a
; Python transcription of this routine, which unpacks the module at
; $C3:1313, 26,393 bytes, to $857F bytes ending exactly on its last end
; marker, and the C2SceneRom_* graphics, palette and map packs to
; $2000/$1000/$800/$100/$3000-byte results, each pack ending where the
; next begins):
;   +0  16-bit W: segment 1's items run from +2 to +2+W-1; its end
;       marker is at +2+W.
;   Items come in groups. Each group starts with a control byte c:
;   - c = 0: 8 literal bytes follow, copied as they are.
;   - else: one item per bit of c from bit 0 up, Decomp_GroupLeft of
;     them (8, except after a segment change): a 0 bit is one literal
;     byte; a 1 bit a back-reference, 16-bit v (low byte first) that
;     copies, from (output position - distance), byte by byte forward
;     (a distance shorter than the length repeats the bytes):
;       12-bit mode: distance = v AND $0FFF, length = (v >> 12) + 3
;       11-bit mode: distance = v AND $07FF, length = (v >> 11) + 3
;   - the end marker is checked only between groups, when the source
;     offset equals the segment's end: a byte m then a 16-bit offset.
;     m AND $3F = 0: the end (the offset is not read). Else the next
;     segment's end marker is at Src + offset (from the start, not +2),
;     its items start right after the 3-byte record, and the next
;     group with a nonzero control byte has only m AND $3F items. The
;     packs seen all have at most two segments, the second holding just
;     the last, partial group (1-7 items).
;   - bits 6-7 of the FIRST end marker pick the mode: 0 = 12-bit
;     offsets (4-bit lengths), nonzero = 11-bit offsets (5-bit lengths);
;     later markers' bits 6-7 are not read.
; The routine is four copies of the same loop, one per mode and WRAM
; bank (Decomp_DestBank bit 0: 0 = $7E, 1 = $7F; the bank byte goes to
; WMADDH, and the back-references are MVNs inside that bank, so bank
; $00 acts as $7E and only low WRAM is reachable that way). After each
; MVN, WMADD is set again from Y (WMADDL/M; WMADDH is not rewritten).
; Callers (2 sites: 1 JSL, 1 JMP): Decomp_ToWramVec (JMP $C3:0002) and C3_BootModule (JSL $C3:006F).
; Callers note: the other callers go through Decomp_ToWramVec (listed in
;   BankC3_Entry0000's header); the unpacked module also JSLs here
;   directly (from $7E:36A4).
; Entry: M, X any (saved; REP #$30 set here); DP any and DB any (both
;        saved; DP = DP_Decomp, DB = Decomp_SrcBank inside); B any;
;        Decomp_Src/SrcBank = the packed data, Decomp_Dest/DestBank =
;        where it goes in WRAM.
; Exit:  P, DP, DB, and A, X and Y (all 16 bits) restored;
;        Decomp_OutLen = bytes written (the end Y - Decomp_Dest, 16-bit);
;        Decomp_SegEnd, Decomp_GroupLeft, Decomp_CtrlBits,
;        Decomp_CopyLen (with $0310 = 0) and Decomp_SrcSave changed;
;        WMADDL/WMADDM = the end of the output (the WRAM port is left
;        there).
; No calls.
Decomp_ToWram:
    PHB
    PHD
    PHP
    REP #$30
    PHA
    PHX
    PHY
    LDA.w #!DP_Decomp
    TCD
    LDA.b !Decomp_Src-!DP_Decomp
    INC A
    INC A
    TAX                                 ; X = the first group
    CLC
    ADC.b [!Decomp_Src-!DP_Decomp]      ; + W
    STA.b !Decomp_SegEnd-!DP_Decomp
    LDA.b !Decomp_Dest-!DP_Decomp
    STA.l WMADDL                        ; WMADDL and WMADDM
    TAY                                 ; Y = the output position
    SEP #$20
    STZ.b !Decomp_CopyLen+1-!DP_Decomp
    LDA.b !Decomp_SrcBank-!DP_Decomp
    PHA
    PLB                                 ; DB = the source bank
    LDA.b (!Decomp_SegEnd-!DP_Decomp)   ; the first end marker: the mode
    AND.b #!Decomp_ModeMask
    BNE .mode11
    LDA.b !Decomp_DestBank-!DP_Decomp
    STA.l WMADDH
    LSR A
    BCC .m12_7E_group
    JMP .m12_7F_group
.mode11:
    LDA.b !Decomp_DestBank-!DP_Decomp
    STA.l WMADDH
    LSR A
    BCC .to_m11_7E
    JMP .m11_7F_group
.to_m11_7E:
    JMP .m11_7E_group

; --- 12-bit offsets, bank $7E ---
.m12_7E_run8:
    LDA.w !Decomp_In+1,X
    STA.l WMDATA
    LDA.w !Decomp_In+2,X
    STA.l WMDATA
    LDA.w !Decomp_In+3,X
    STA.l WMDATA
    LDA.w !Decomp_In+4,X
    STA.l WMDATA
    LDA.w !Decomp_In+5,X
    STA.l WMDATA
    LDA.w !Decomp_In+6,X
    STA.l WMDATA
    LDA.w !Decomp_In+7,X
    STA.l WMDATA
    LDA.w !Decomp_In+8,X
    STA.l WMDATA
    REP #$21
    TXA
    ADC.w #!Decomp_RunBytes+1           ; the control byte and 8 literals
    TAX
    TYA
    ADC.w #!Decomp_RunBytes
    TAY
    SEP #$20
    BRA .m12_7E_next
.m12_7E_group:
    LDA.b #!Decomp_GroupSize
    STA.b !Decomp_GroupLeft-!DP_Decomp
.m12_7E_next:
    CPX.b !Decomp_SegEnd-!DP_Decomp
    BEQ .m12_7E_marker
    LDA.w !Decomp_In,X                       ; control byte
    BEQ .m12_7E_run8
    INX
    LSR A
    STA.b !Decomp_CtrlBits-!DP_Decomp
    BCS .m12_7E_ref
    LDA.w !Decomp_In,X
    STA.l WMDATA
    INY
    INX
.m12_7E_item_done:
    DEC.b !Decomp_GroupLeft-!DP_Decomp
    BEQ .m12_7E_group
    LSR.b !Decomp_CtrlBits-!DP_Decomp
    BCS .m12_7E_ref
    LDA.w !Decomp_In,X
    STA.l WMDATA
    INY
    INX
    BRA .m12_7E_item_done
.m12_7E_ref:
    LDA.w !Decomp_In+1,X
    LSR A
    LSR A
    LSR A
    LSR A
    INC A
    INC A                               ; length - 1
    STA.b !Decomp_CopyLen-!DP_Decomp
    REP #$20
    LDA.w !Decomp_In,X
    AND.w #!Decomp_Offset12Mask
    STA.b !Decomp_SrcSave-!DP_Decomp    ; (the distance, for the SBC)
    TYA
    SEC
    SBC.b !Decomp_SrcSave-!DP_Decomp
    STX.b !Decomp_SrcSave-!DP_Decomp
    TAX                                 ; X = output - distance
    LDA.b !Decomp_CopyLen-!DP_Decomp
    PHB
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; Y advances by the length
    PLB
    TYA
    STA.l WMADDL
    SEP #$20
    LDX.b !Decomp_SrcSave-!DP_Decomp
    INX
    INX
    BRA .m12_7E_item_done
.m12_7E_marker:
    LDA.w !Decomp_In,X
    AND.b #!Decomp_MarkerCountMask
    BEQ .m12_7E_end
    STA.b !Decomp_GroupLeft-!DP_Decomp
    REP #$21
    LDA.w !Decomp_In+1,X
    ADC.b !Decomp_Src-!DP_Decomp
    STA.b !Decomp_SegEnd-!DP_Decomp
    INX
    INX
    INX
    SEP #$20
    BRA .m12_7E_next
.m12_7E_end:
    JMP .done

; --- 12-bit offsets, bank $7F ---
.m12_7F_run8:
    LDA.w !Decomp_In+1,X
    STA.l WMDATA
    LDA.w !Decomp_In+2,X
    STA.l WMDATA
    LDA.w !Decomp_In+3,X
    STA.l WMDATA
    LDA.w !Decomp_In+4,X
    STA.l WMDATA
    LDA.w !Decomp_In+5,X
    STA.l WMDATA
    LDA.w !Decomp_In+6,X
    STA.l WMDATA
    LDA.w !Decomp_In+7,X
    STA.l WMDATA
    LDA.w !Decomp_In+8,X
    STA.l WMDATA
    REP #$21
    TXA
    ADC.w #!Decomp_RunBytes+1
    TAX
    TYA
    ADC.w #!Decomp_RunBytes
    TAY
    SEP #$20
    BRA .m12_7F_next
.m12_7F_group:
    LDA.b #!Decomp_GroupSize
    STA.b !Decomp_GroupLeft-!DP_Decomp
.m12_7F_next:
    CPX.b !Decomp_SegEnd-!DP_Decomp
    BEQ .m12_7F_marker
    LDA.w !Decomp_In,X
    BEQ .m12_7F_run8
    INX
    LSR A
    STA.b !Decomp_CtrlBits-!DP_Decomp
    BCS .m12_7F_ref
    LDA.w !Decomp_In,X
    STA.l WMDATA
    INY
    INX
.m12_7F_item_done:
    DEC.b !Decomp_GroupLeft-!DP_Decomp
    BEQ .m12_7F_group
    LSR.b !Decomp_CtrlBits-!DP_Decomp
    BCS .m12_7F_ref
    LDA.w !Decomp_In,X
    STA.l WMDATA
    INY
    INX
    BRA .m12_7F_item_done
.m12_7F_ref:
    LDA.w !Decomp_In+1,X
    LSR A
    LSR A
    LSR A
    LSR A
    INC A
    INC A
    STA.b !Decomp_CopyLen-!DP_Decomp
    REP #$20
    LDA.w !Decomp_In,X
    AND.w #!Decomp_Offset12Mask
    STA.b !Decomp_SrcSave-!DP_Decomp
    TYA
    SEC
    SBC.b !Decomp_SrcSave-!DP_Decomp
    STX.b !Decomp_SrcSave-!DP_Decomp
    TAX
    LDA.b !Decomp_CopyLen-!DP_Decomp
    PHB
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    PLB
    TYA
    STA.l WMADDL
    SEP #$20
    LDX.b !Decomp_SrcSave-!DP_Decomp
    INX
    INX
    BRA .m12_7F_item_done
.m12_7F_marker:
    LDA.w !Decomp_In,X
    AND.b #!Decomp_MarkerCountMask
    BEQ .m12_7F_end
    STA.b !Decomp_GroupLeft-!DP_Decomp
    REP #$21
    LDA.w !Decomp_In+1,X
    ADC.b !Decomp_Src-!DP_Decomp
    STA.b !Decomp_SegEnd-!DP_Decomp
    INX
    INX
    INX
    SEP #$20
    BRA .m12_7F_next
.m12_7F_end:
    JMP .done

; --- 11-bit offsets, bank $7E ---
.m11_7E_run8:
    LDA.w !Decomp_In+1,X
    STA.l WMDATA
    LDA.w !Decomp_In+2,X
    STA.l WMDATA
    LDA.w !Decomp_In+3,X
    STA.l WMDATA
    LDA.w !Decomp_In+4,X
    STA.l WMDATA
    LDA.w !Decomp_In+5,X
    STA.l WMDATA
    LDA.w !Decomp_In+6,X
    STA.l WMDATA
    LDA.w !Decomp_In+7,X
    STA.l WMDATA
    LDA.w !Decomp_In+8,X
    STA.l WMDATA
    REP #$21
    TXA
    ADC.w #!Decomp_RunBytes+1
    TAX
    TYA
    ADC.w #!Decomp_RunBytes
    TAY
    SEP #$20
    BRA .m11_7E_next
.m11_7E_group:
    LDA.b #!Decomp_GroupSize
    STA.b !Decomp_GroupLeft-!DP_Decomp
.m11_7E_next:
    CPX.b !Decomp_SegEnd-!DP_Decomp
    BEQ .m11_7E_marker
    LDA.w !Decomp_In,X
    BEQ .m11_7E_run8
    INX
    LSR A
    STA.b !Decomp_CtrlBits-!DP_Decomp
    BCS .m11_7E_ref
    LDA.w !Decomp_In,X
    STA.l WMDATA
    INY
    INX
.m11_7E_item_done:
    DEC.b !Decomp_GroupLeft-!DP_Decomp
    BEQ .m11_7E_group
    LSR.b !Decomp_CtrlBits-!DP_Decomp
    BCS .m11_7E_ref
    LDA.w !Decomp_In,X
    STA.l WMDATA
    INY
    INX
    BRA .m11_7E_item_done
.m11_7E_ref:
    LDA.w !Decomp_In+1,X
    LSR A
    LSR A
    LSR A
    INC A
    INC A
    STA.b !Decomp_CopyLen-!DP_Decomp
    REP #$20
    LDA.w !Decomp_In,X
    AND.w #!Decomp_Offset11Mask
    STA.b !Decomp_SrcSave-!DP_Decomp
    TYA
    SEC
    SBC.b !Decomp_SrcSave-!DP_Decomp
    STX.b !Decomp_SrcSave-!DP_Decomp
    TAX
    LDA.b !Decomp_CopyLen-!DP_Decomp
    PHB
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes
    PLB
    TYA
    STA.l WMADDL
    SEP #$20
    LDX.b !Decomp_SrcSave-!DP_Decomp
    INX
    INX
    BRA .m11_7E_item_done
.m11_7E_marker:
    LDA.w !Decomp_In,X
    AND.b #!Decomp_MarkerCountMask
    BEQ .m11_7E_end
    STA.b !Decomp_GroupLeft-!DP_Decomp
    REP #$21
    LDA.w !Decomp_In+1,X
    ADC.b !Decomp_Src-!DP_Decomp
    STA.b !Decomp_SegEnd-!DP_Decomp
    INX
    INX
    INX
    SEP #$20
    BRA .m11_7E_next
.m11_7E_end:
    JMP .done

; --- 11-bit offsets, bank $7F ---
.m11_7F_run8:
    LDA.w !Decomp_In+1,X
    STA.l WMDATA
    LDA.w !Decomp_In+2,X
    STA.l WMDATA
    LDA.w !Decomp_In+3,X
    STA.l WMDATA
    LDA.w !Decomp_In+4,X
    STA.l WMDATA
    LDA.w !Decomp_In+5,X
    STA.l WMDATA
    LDA.w !Decomp_In+6,X
    STA.l WMDATA
    LDA.w !Decomp_In+7,X
    STA.l WMDATA
    LDA.w !Decomp_In+8,X
    STA.l WMDATA
    REP #$21
    TXA
    ADC.w #!Decomp_RunBytes+1
    TAX
    TYA
    ADC.w #!Decomp_RunBytes
    TAY
    SEP #$20
    BRA .m11_7F_next
.m11_7F_group:
    LDA.b #!Decomp_GroupSize
    STA.b !Decomp_GroupLeft-!DP_Decomp
.m11_7F_next:
    CPX.b !Decomp_SegEnd-!DP_Decomp
    BEQ .m11_7F_marker
    LDA.w !Decomp_In,X
    BEQ .m11_7F_run8
    INX
    LSR A
    STA.b !Decomp_CtrlBits-!DP_Decomp
    BCS .m11_7F_ref
    LDA.w !Decomp_In,X
    STA.l WMDATA
    INY
    INX
.m11_7F_item_done:
    DEC.b !Decomp_GroupLeft-!DP_Decomp
    BEQ .m11_7F_group
    LSR.b !Decomp_CtrlBits-!DP_Decomp
    BCS .m11_7F_ref
    LDA.w !Decomp_In,X
    STA.l WMDATA
    INY
    INX
    BRA .m11_7F_item_done
.m11_7F_ref:
    LDA.w !Decomp_In+1,X
    LSR A
    LSR A
    LSR A
    INC A
    INC A
    STA.b !Decomp_CopyLen-!DP_Decomp
    REP #$20
    LDA.w !Decomp_In,X
    AND.w #!Decomp_Offset11Mask
    STA.b !Decomp_SrcSave-!DP_Decomp
    TYA
    SEC
    SBC.b !Decomp_SrcSave-!DP_Decomp
    STX.b !Decomp_SrcSave-!DP_Decomp
    TAX
    LDA.b !Decomp_CopyLen-!DP_Decomp
    PHB
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    PLB
    TYA
    STA.l WMADDL
    SEP #$20
    LDX.b !Decomp_SrcSave-!DP_Decomp
    INX
    INX
    BRA .m11_7F_item_done
.m11_7F_marker:
    LDA.w !Decomp_In,X
    AND.b #!Decomp_MarkerCountMask
    BEQ .done
    STA.b !Decomp_GroupLeft-!DP_Decomp
    REP #$21
    LDA.w !Decomp_In+1,X
    ADC.b !Decomp_Src-!DP_Decomp
    STA.b !Decomp_SegEnd-!DP_Decomp
    INX
    INX
    INX
    SEP #$20
    BRA .m11_7F_next
.done:
    REP #$20
    TYA
    SEC
    SBC.b !Decomp_Dest-!DP_Decomp
    STA.b !Decomp_OutLen-!DP_Decomp
    PLY
    PLX
    PLA
    PLP
    PLD
    PLB
    RTL

; ============================================================
; End of the kernel ($C3:10C0–$C3:10CA)
; ============================================================

; $C3:10C0 — BankC3_EndMarker (11 bytes, $10C0–$10CA)
; ASCII "CODE END C3" right after the kernel's last RTL (WinFx_BuildQuad),
; probably left by the build to mark the end of the code. Followed by
; $00 fill up to the packed block at $C3:1200 (not emitted here).
org $C310C0
BankC3_EndMarker:
    db "CODE END C3"
