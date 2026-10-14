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
;   $000E BankC3_Entry000E → WinFx_StepWipe (JSL)
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
    JMP WinFx_StepWipe
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

; ============================================================
; Window tables: the circle, the line wipe ($C3:0077–$C3:0306)
; ============================================================

; $C3:0077 — WinFx_BuildCircle (335 bytes, $0077–$01C5)
; Writes a window table for a circle: one 2-byte entry per line (left
; edge, right edge; WinFx_EmptyEntry = nothing on that line) at
; WinFx_TablePtr, in bank $7F if WinFx_TableBank bit 0 is set, else $7E.
; Centre (WinFx_ArgX, WinFx_ArgY) = (Xc, Yc), radius WinFx_ArgSize = r.
; Radius 0 empties the whole table (WinFx_FillEmpty with
; WinFx_FillAllBytes). Else a midpoint-circle walk (x from r down, y
; from 0 up, while x >= the previous y) writes the rows above the
; centre: row Yc - x with Xc - y .. Xc + y, and row Yc - 1 - y with
; Xc - x .. Xc + x (left edges kept >= 0, right edges <= $FF). Then by
; the mode in A (bits 0-6): 0 mirrors rows Yc-1, Yc-2, .. to Yc, Yc+1,
; .. (r + 1 rows); 1 copies every second row instead ((r + 1) / 2
; rows: the lower half at half height); any other value keeps only the
; upper half and returns. Unless mode bit 7 (WinFx_CircKeepRest) is
; set, modes 0 and 1 then empty the rows from Yc + r (mode 1: Yc + r/2)
; to line $DF, and the rows from 0 to Yc - r - 1 (none when Yc - r <= 1;
; with Yc - r = 1 row 0 is left as it was; the lower part only when
; that first row is above line $DF), so the last mirrored row and the
; walk's top row are overwritten. Nothing limits the rows to the table:
; a circle that reaches above line 0 writes before WinFx_TablePtr.
; Quirks (adds and subtracts with no CLC/SEC before them, which take the
; carry the instruction before left; traced, kept):
;   - d starts at 2 - 2r, not 3 - 2r ($C3:00B3: C=0 from the ASL).
;   - the first pass writes row Yc - r - 1, not Yc - r, when the table
;     address is even ($C3:00CA: C = bit 0 of it from the LSR); later
;     passes have C=1 there.
;   - right edges of the Xc +- y rows are Xc + y + 1 when 0 < y <= Xc
;     ($C3:00DE: C from the ADC before); the left edge of the next row
;     is Xc - x + 1 when that right edge reached $FF ($C3:00FE: C from
;     the clamp's CMP).
;   - the step when d >= 0, with v = y - x - 1 + c (c = 1 when the
;     second right edge reached $FF, from its CMP): 4v + 10 for v >= 0,
;     else 4v + 11 (C=1 out of the two ASLs), and one more when v is -1
;     or -2 (the carry out of ADC #$000A reaches ADC WinFx_CircD). The
;     d < 0 step 4y + 6 is exact.
; Callers (1 JMP site): BankC3_Entry0008 ($C3:0008).
; Callers of WinFx_Exit (3 JMP sites): WinFx_StepWipe ($C3:023F, $C3:02AB, $C3:02DA).
; Callers note: the unpacked module JSLs here directly (from $7E:7338,
;   $7E:734F and $7E:7FDE).
; Entry: M, X any (P saved; REP #$30 here); DP any (saved; DP_WinFx
;        inside); DB any (saved; the table bank inside); A = the mode
;        (low byte; WinFx_Mode0/1/80 from the field hooks);
;        WinFx_ArgX/ArgY/ArgSize, WinFx_TablePtr/TableBank set.
; Exit:  P, DP, DB and A, X, Y (16-bit) restored; WinFx_ArgXHi,
;        WinFx_ArgYHi, WinFx_ArgSizeHi = 0; WinFx_Tmp, WinFx_CircD,
;        WinFx_CircRowPtr, WinFx_CircHalfPtr changed (radius 0: only
;        WinFx_Tmp).
; WinFx_Exit (sub-entry, $C3:01BD): the shared exit (REP #$30, pull Y,
;   X, A, P, DP, DB, RTL), also jumped to by WinFx_StepWipe.
; Calls: WinFx_FillEmpty, WinFx_FillEmptyFrom.
WinFx_BuildCircle:
    PHB
    PHD
    PHP
    REP #$30
    PHA
    PHX
    PHY
    AND.w #!Eng_LowByteMask
    PHA                                 ; the mode
    LDA.w #!DP_WinFx
    TCD
    SEP #$20
    STZ.b !WinFx_ArgXHi-!DP_WinFx
    STZ.b !WinFx_ArgYHi-!DP_WinFx
    STZ.b !WinFx_ArgSizeHi-!DP_WinFx
    LDA.b !WinFx_TableBank-!DP_WinFx
    LSR A
    BCS .bank7F
    LDA.b #!Bank7E
    BRA .set_bank
.bank7F:
    LDA.b #!Bank7F
.set_bank:
    PHA
    PLB
    REP #$20
    LDA.b !WinFx_ArgSize-!DP_WinFx
    BNE .circle
    PLA
    LDA.w #!WinFx_FillAllBytes
    JSR WinFx_FillEmpty
    JMP WinFx_Exit
.circle:
    TAX                                 ; X = x = r
    ASL A
    STA.b !WinFx_CircD-!DP_WinFx
    LDA.w #$0003
    SBC.b !WinFx_CircD-!DP_WinFx        ; no SEC: C=0 (ASL of r < $100), so d = 2 - 2r
    STA.b !WinFx_CircD-!DP_WinFx
    LDY.w #$0000                        ; Y = y = 0
    LDA.b !WinFx_ArgY-!DP_WinFx
    ASL A
    CLC
    ADC.b !WinFx_TablePtr-!DP_WinFx
    STA.b !WinFx_CircRowPtr-!DP_WinFx   ; the centre row's entry
    PHA
    LSR A
    STA.b !WinFx_CircHalfPtr-!DP_WinFx
.step:
    STX.b !WinFx_Tmp-!DP_WinFx
    LDA.b !WinFx_CircHalfPtr-!DP_WinFx
    SBC.b !WinFx_Tmp-!DP_WinFx          ; no SEC: first pass C = bit 0 of the row address (row Yc-x-1
                                        ; for an even table), later C=1 from the CPX (row Yc-x)
    ASL A
    TAX
    TYA
    EOR.w #!Eng_Invert16
    INC A
    ADC.b !WinFx_ArgX-!DP_WinFx         ; Xc - y (C=0 from the ASL)
    BPL .left1_ok
    LDA.w #$0000
.left1_ok:
    STA.w !Eng_PtrBase,X
    TYA
    ADC.b !WinFx_ArgX-!DP_WinFx         ; no CLC: + 1 when 0 < y <= Xc
    CMP.w #!WinFx_EdgeMax
    BMI .right1_ok
    LDA.w #!WinFx_EdgeMax
.right1_ok:
    SEP #$20
    STA.w !Eng_PtrBase+1,X
    REP #$20
    LDX.b !WinFx_Tmp-!DP_WinFx          ; X = x
    STY.b !WinFx_Tmp-!DP_WinFx          ; WinFx_Tmp = y
    LDY.b !WinFx_CircRowPtr-!DP_WinFx
    DEY
    DEY
    STY.b !WinFx_CircRowPtr-!DP_WinFx   ; row Yc - 1 - y
    TXA
    EOR.w #!Eng_Invert16
    INC A
    ADC.b !WinFx_ArgX-!DP_WinFx         ; no CLC: C from the CMP above (1 if that edge reached $FF)
    BPL .left2_ok
    LDA.w #$0000
.left2_ok:
    STA.w !Eng_PtrBase,Y
    TXA
    CLC
    ADC.b !WinFx_ArgX-!DP_WinFx
    CMP.w #!WinFx_EdgeMax
    BMI .right2_ok
    LDA.w #!WinFx_EdgeMax
.right2_ok:
    SEP #$20
    STA.w !Eng_PtrBase+1,Y
    REP #$20
    LDY.b !WinFx_Tmp-!DP_WinFx          ; Y = y
    LDA.b !WinFx_CircD-!DP_WinFx
    BPL .step_diag
    TYA
    ASL A
    ASL A
    ADC.w #$0006                        ; d += 4y + 6
    BRA .step_add
.step_diag:
    TYA
    STX.b !WinFx_Tmp-!DP_WinFx
    DEX                                 ; x - 1
    SBC.b !WinFx_Tmp-!DP_WinFx          ; no SEC: C from the CMP above
    ASL A
    ASL A
    ADC.w #!WinFx_CircStepDiag          ; C from the second ASL
.step_add:
    ADC.b !WinFx_CircD-!DP_WinFx
    STA.b !WinFx_CircD-!DP_WinFx
    STY.b !WinFx_Tmp-!DP_WinFx
    INY
    CPX.b !WinFx_Tmp-!DP_WinFx
    BPL .step                           ; while x >= the old y
    PLY                                 ; Y = X = the centre row's entry
    TYX
    LDA.b !WinFx_ArgSize-!DP_WinFx
    INC A
    STA.b !WinFx_Tmp-!DP_WinFx          ; r + 1 rows
    PLA
    STA.b !WinFx_CircMode-!DP_WinFx
    AND.w #!WinFx_CircModeMask
    BEQ .mirror
    CMP.w #!WinFx_Mode1
    BNE WinFx_Exit                      ; other modes: the upper half only
    LSR.b !WinFx_Tmp-!DP_WinFx
    LDA.b !WinFx_Tmp-!DP_WinFx
    BMI WinFx_Exit
    BEQ WinFx_Exit
.mirror_half:
    DEX
    DEX
    DEX
    DEX
    LDA.w !Eng_PtrBase,X
    STA.w !Eng_PtrBase,Y
    INY
    INY
    DEC.b !WinFx_Tmp-!DP_WinFx
    BNE .mirror_half
    LDA.b !WinFx_CircMode-!DP_WinFx
    BIT.w #!WinFx_CircKeepRest
    BNE WinFx_Exit
    LDA.b !WinFx_ArgSize-!DP_WinFx
    LSR A                               ; r / 2 rows below the centre
    BRA .clear_below
.mirror:
    DEX
    DEX
    LDA.w !Eng_PtrBase,X
    STA.w !Eng_PtrBase,Y
    INY
    INY
    DEC.b !WinFx_Tmp-!DP_WinFx
    BNE .mirror
    LDA.b !WinFx_CircMode-!DP_WinFx
    BIT.w #!WinFx_CircKeepRest
    BNE WinFx_Exit
    LDA.b !WinFx_ArgSize-!DP_WinFx
.clear_below:
    CLC
    ADC.b !WinFx_ArgY-!DP_WinFx
    CMP.w #!WinFx_LastLine
    BPL .clear_above
    STA.b !WinFx_Tmp-!DP_WinFx
    ASL A
    CLC
    ADC.b !WinFx_TablePtr-!DP_WinFx
    TAX
    LDA.w #!WinFx_Lines
    SEC
    SBC.b !WinFx_Tmp-!DP_WinFx
    DEC A
    ASL A
    DEC A                               ; 2 x ($DF - row) - 1: through line $DF
    STA.b !WinFx_Tmp-!DP_WinFx
    JSR WinFx_FillEmptyFrom
.clear_above:
    LDA.b !WinFx_ArgY-!DP_WinFx
    SEC
    SBC.b !WinFx_ArgSize-!DP_WinFx
    CMP.w #$0001
    BMI WinFx_Exit
    BEQ WinFx_Exit                      ; Yc - r = 1: row 0 is not touched
    DEC A
    ASL A
    DEC A                               ; rows 0 to Yc - r - 1
    JSR WinFx_FillEmpty
WinFx_Exit:                             ; header: see WinFx_BuildCircle
    REP #$30
    PLY
    PLX
    PLA
    PLP
    PLD
    PLB
    RTL

; $C3:01C6 — WinFx_FillEmpty (30 bytes, $01C6–$01E3)
; Fills window-table entries with WinFx_EmptyEntry: stores it at X and
; copies it forward with an MVN of WinFx_Tmp + 1 bytes into X + 2 on
; (the bank by WinFx_TableBank bit 0). WinFx_FillEmpty starts at
; WinFx_TablePtr with A = the count (bytes after the first entry - 1);
; WinFx_FillEmptyFrom (sub-entry, $C3:01CA) starts at X with the count
; already in WinFx_Tmp.
; Callers (2 JSR sites): WinFx_BuildCircle ($C3:00A6, $C3:01BA).
; Callers of WinFx_FillEmptyFrom (1 JSR site): WinFx_BuildCircle ($C3:01A8).
; Entry: M=0 (16-bit A: the entry is stored as a word, A is the MVN
;        count), X=0, DP=DP_WinFx (WinFx_Tmp, WinFx_TablePtr and
;        WinFx_TableBank are direct page), DB = the table's bank (the
;        STA is absolute).
; Exit:  M=0, X=0; DB = the table's bank (MVN sets it to the same); A =
;        $FFFF (MVN); X, Y past the copied bytes; WinFx_Tmp = the count.
WinFx_FillEmpty:
    STA.b !WinFx_Tmp-!DP_WinFx
    LDX.b !WinFx_TablePtr-!DP_WinFx
WinFx_FillEmptyFrom:                    ; header: see WinFx_FillEmpty
    TXY
    INY
    INY
    LDA.w #!WinFx_EmptyEntry
    STA.w !Eng_PtrBase,X
    LDA.b !WinFx_TableBank-!DP_WinFx
    LSR A
    BCS .bank7F
    LDA.b !WinFx_Tmp-!DP_WinFx
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes
    RTS
.bank7F:
    LDA.b !WinFx_Tmp-!DP_WinFx
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    RTS

; $C3:01E4 — WinFx_StepWipe (249 bytes, $01E4–$02DC)
; One frame of a per-line wipe, run while WinFx_C3EMode is nonzero
; (Field_HookWinC3E calls it once a frame through BankC3_Entry000E and
; uses the result as HDMA data for window 2, probably one window edge
; per line). Works on a line array of WinFx_Lines bytes at
; WinFx_C3ETablePtr + WinFx_WipeWorkOfs in bank WinFx_C3ETableBank, and
; writes it out each frame through WMDATA to one of two buffers: the
; table itself on odd frames, + WinFx_Lines on even ones.
;   - first call (WinFx_WipeFrame = 0): every line set to 0 (mode 1) or
;     WinFx_WipeFillMode2 (any other mode), then the step below;
;   - each call adds 1 to WinFx_WipeFrame; while it stays below
;     WinFx_WipeFrames, each line moves by a random step: the lines go in runs of 3-34
;     (random byte bits 0-4 + 3), each run with a step of 8-11 (next
;     random byte bits 0-1 + 8). Mode 1 adds (to at most $FF), mode 2
;     (WinFx_C3EMode2) subtracts (to at least 0);
;   - when the count reaches WinFx_WipeFrames, WinFx_C3EMode (so
;     WinFx_Busy) and WinFx_WipeFrame are cleared and nothing is
;     written: Field_HookWinC3E sees the end that way.
; The random bytes walk RandomTable: WinFx_NoisePtr starts at the entry
; C3_RandomByte picks and each byte read is the index of the next.
; Quirks (no SEC before the SBC, and a carry left by the CMP of the
; mode): in mode 2 every line loses step + 1, i.e. 9-12 (C=0 there:
; from the ADC #$08 of a run reload or from the CPX of the loop), and
; the first run is 4-35 lines long (its ADC #$03 gets C=1 from the CMP
; that found mode 2); mode 1 is exact. Once a value clamps to 0, the
; TDC used for it leaves B = $03 (DP's high byte), so the next run
; length (TAY) is $0303 or more: that run lasts to the end of the line.
; The first-frame fill is in its own bank by WinFx_C3ETableBank bit 0
; ($7E/$7F: STA.l + MVN), the steps read and write with DB =
; WinFx_C3ETableBank and WMADDH = it (so it must be $7E or $7F).
; Callers (1 JMP site): BankC3_Entry000E ($C3:000E).
; Callers note: the unpacked module JSLs here directly (from $7E:6844).
; Entry: M, X any (P saved; REP #$30 here); DP any and DB any (saved;
;        DP_WinFx inside); WinFx_C3EMode, WinFx_C3ETablePtr/TableBank
;        set; C3_RandomByte needs DB=$00 or another bank that maps the
;        PPU registers and low WRAM (Field_HookWinC3E has $00).
; Exit:  through WinFx_Exit: P, DP, DB and A, X, Y (16-bit) restored;
;        WinFx_WipeFrame stepped (or 0 with WinFx_C3EMode at the end);
;        WinFx_Tmp, WinFx_WipeStep, WinFx_WipeEnd, WinFx_NoisePtr and
;        C3_RandSeed changed; WMADD left after the buffer written.
; Calls: C3_RandomByte.
WinFx_StepWipe:
    PHB
    PHD
    PHP
    REP #$30
    PHA
    PHX
    PHY
    LDA.w #!DP_WinFx
    TCD
    SEP #$20
    LDA.b !WinFx_C3EMode-!DP_WinFx
    BEQ .stop
    LDA.b !WinFx_WipeFrame-!DP_WinFx
    BNE .count
    STZ.b !WinFx_Tmp-!DP_WinFx          ; first frame: fill the line array
    LDA.b !WinFx_C3EMode-!DP_WinFx
    CMP.b #!WinFx_C3EMode1
    BEQ .fill
    LDA.b #!WinFx_WipeFillMode2
    STA.b !WinFx_Tmp-!DP_WinFx
.fill:
    REP #$21
    LDA.b !WinFx_C3ETablePtr-!DP_WinFx
    ADC.w #!WinFx_WipeWorkOfs
    TAX
    TXY
    INY
    PHB
    LDA.b !WinFx_C3ETableBank-!DP_WinFx
    LSR A
    BCC .fill_7E
    LDA.b !WinFx_Tmp-!DP_WinFx
    STA.l !Bank7F<<16,X
    LDA.w #!WinFx_Lines-2
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    BRA .filled
.fill_7E:
    LDA.b !WinFx_Tmp-!DP_WinFx
    STA.l !Bank7E<<16,X
    LDA.w #!WinFx_Lines-2
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes
.filled:
    PLB
    SEP #$20
    TDC                                 ; A = 0 (DP's low byte)
.count:
    INC A
    STA.b !WinFx_WipeFrame-!DP_WinFx
    CMP.b #!WinFx_WipeFrames
    BMI .run
.stop:
    STZ.b !WinFx_WipeFrame-!DP_WinFx
    STZ.b !WinFx_C3EMode-!DP_WinFx
    JMP WinFx_Exit
.run:
    LDA.b #bank(RandomTable)
    STA.b !WinFx_NoisePtr+2-!DP_WinFx
    LDA.b #RandomTable>>8&$FF
    STA.b !WinFx_NoisePtr+1-!DP_WinFx
    JSL C3_RandomByte
    STA.b !WinFx_NoisePtr-!DP_WinFx
    REP #$20
    LDA.b !WinFx_C3ETablePtr-!DP_WinFx
    CLC
    ADC.w #!WinFx_WipeWorkOfs
    TAX                                 ; X = the line array
    CLC
    ADC.w #!WinFx_Lines
    STA.b !WinFx_WipeEnd-!DP_WinFx
    LDA.b !WinFx_WipeFrame-!DP_WinFx
    LSR A                               ; odd frame: the first buffer
    LDA.b !WinFx_C3ETablePtr-!DP_WinFx
    BCS .set_out
    ADC.w #!WinFx_Lines
.set_out:
    STA.w WMADDL
    SEP #$20
    LDA.b !WinFx_C3ETableBank-!DP_WinFx
    STA.w WMADDH
    PHA
    PLB
    TDC
    XBA                                 ; B = 0 (DP's low byte), for the TAYs
    LDY.w #$0001
    LDA.b !WinFx_C3EMode-!DP_WinFx
    CMP.b #!WinFx_C3EMode2
    BEQ .lower_line
.raise_line:
    DEY
    BNE .raise
    LDA.b [!WinFx_NoisePtr-!DP_WinFx]
    STA.b !WinFx_NoisePtr-!DP_WinFx
    AND.b #!WinFx_WipeRunMask
    ADC.b #$03
    TAY                                 ; the run length
    LDA.b [!WinFx_NoisePtr-!DP_WinFx]
    STA.b !WinFx_NoisePtr-!DP_WinFx
    AND.b #$03
    ADC.b #$08
    STA.b !WinFx_WipeStep-!DP_WinFx
.raise:
    LDA.w !Eng_PtrBase,X
    ADC.b !WinFx_WipeStep-!DP_WinFx
    BCC .raised
    LDA.b #!WinFx_EdgeMax
.raised:
    STA.l WMDATA
    STA.w !Eng_PtrBase,X
    INX
    CPX.b !WinFx_WipeEnd-!DP_WinFx
    BNE .raise_line
    JMP WinFx_Exit
.lower_line:
    DEY
    BNE .lower
    LDA.b [!WinFx_NoisePtr-!DP_WinFx]
    STA.b !WinFx_NoisePtr-!DP_WinFx
    AND.b #!WinFx_WipeRunMask
    ADC.b #$03                          ; first run: C=1 from the CMP (+ 1)
    TAY
    LDA.b [!WinFx_NoisePtr-!DP_WinFx]
    STA.b !WinFx_NoisePtr-!DP_WinFx
    AND.b #$03
    ADC.b #$08
    STA.b !WinFx_WipeStep-!DP_WinFx
.lower:
    LDA.w !Eng_PtrBase,X
    SBC.b !WinFx_WipeStep-!DP_WinFx     ; no SEC: C=0 here, so step + 1
    BPL .lowered
    BCS .lowered
    TDC                                 ; 0 (and B = $03: see the header)
.lowered:
    STA.l WMDATA
    STA.w !Eng_PtrBase,X
    INX
    CPX.b !WinFx_WipeEnd-!DP_WinFx
    BNE .lower_line
    JMP WinFx_Exit

; $C3:02DD — C3_RandomByte (42 bytes, $02DD–$0306)
; Returns a new pseudo-random byte in A and keeps it in C3_RandSeed: A
; (with C rotated in) plus C3_RandSeed, stored; then X's low byte, the
; seed, C3_FrameCount, the H and V counters (latched by reading SLHV;
; the CMP's result is not used), the seed again, C3_MixF0, C3_MixF2 (EOR)
; and C3_MixF4 are added or subtracted in, each with the carry of the
; step before, and the result stored back.
; Callers (1 JSL site): WinFx_StepWipe ($C3:024A).
; Callers note: the unpacked module also JSLs here (from $7E:3443).
; Entry: M=1 (8-bit adds; WinFx_StepWipe has it, the module's site is
;        not traced), X any (only its low byte is used), DP any (none
;        used), DB = $00 or a bank that maps both low WRAM and the PPU
;        registers (all operands are absolute).
; Exit:  M as on entry; A = C3_RandSeed = the new value; flags from the
;        last SBC; X, Y, DP, DB unchanged.
C3_RandomByte:
    ROL A
    ADC.w !C3_RandSeed
    STA.w !C3_RandSeed
    TXA
    ADC.w !C3_RandSeed
    ADC.w !C3_FrameCount
    CMP.w SLHV                          ; read for the latch
    ADC.w OPHCT
    SBC.w OPVCT
    ADC.w !C3_RandSeed
    ADC.w !C3_MixF0
    EOR.w !C3_MixF2
    ADC.w !C3_MixF4
    SBC.w OPVCT
    STA.w !C3_RandSeed
    RTL

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
; Window tables: the quadrilateral ($C3:0EFA–$C3:10BF)
; ============================================================

; $C3:0EFA — WinFx_BuildQuad (263 bytes, $0EFA–$1000)
; Writes a window table (2 bytes per line: left edge, right edge) for
; the four-sided shape through WinFx_QuadPoints (X, Y bytes of points
; 0-3, in order) at WinFx_QuadTablePtr in bank WinFx_QuadTableBank
; (bit 0: $7E/$7F). It starts from the point with the smallest Y (the
; first one on a tie; WinFx_QuadTopY), then draws the four edges in
; point order with WinFx_QuadEdge, through a chain of four blocks
; (.from_p0-.from_p3, one per start point; entered with JMP
; (WinFx_Tmp), the last block branches back to the first). Edges going
; down write the left byte; the first edge going up switches to the
; right byte (WinFx_QuadTablePtr + 1) and its start Y is the bottom
; (WinFx_QuadBottomY). After the fourth edge the return address of its
; JSR is dropped (PLA) and the rows outside are emptied
; (WinFx_EmptyEntry): row 0, the bottom row and the rows after it up
; to $FF, and rows 1 to the top Y (so the top row too) unless the top Y
; is 0.
; Quirks: WinFx_QuadTablePtr is moved back by one at the end even when
; no edge went up (all four Y equal): it is then left one lower. The
; BEQ on the fill count can never be taken (2 x ($FF - bottom) - 1 is
; odd), and a bottom at line $FF would make it $FFFF, a 64 KB MVN; the
; callers' points are not checked here.
; Callers (1 JMP site): BankC3_Entry0011 ($C3:0011).
; Callers note: the unpacked module JSLs here directly (from $7E:9A4F).
; Entry: M any (SEP #$20 here), X=0 (16-bit LDY of the chain entry),
;        DP any and DB any (both saved; DP_WinFx inside; the table is
;        written long, WinFx_QuadEdge sets its own DB);
;        WinFx_QuadPoints, WinFx_QuadTablePtr/TableBank set.
; Exit:  through WinFx_QuadExit: P, DB, DP restored; A = $0003 (TDC/XBA
;        with DP_WinFx); X, Y changed; WinFx_QuadTopY,
;        WinFx_QuadBottomY, WinFx_QuadX0..Y1, WinFx_Tmp,
;        WinFx_QuadRows/EdgesLeft/LeftSide/Dx/Dy/Err changed.
; Calls: WinFx_QuadEdge (JSL).
org $C30EFA
WinFx_BuildQuad:
    PHD
    PHB
    PHP
    SEP #$20
    PEA.w !DP_WinFx
    PLD
    STZ.b !WinFx_QuadTopY+1-!DP_WinFx
    LDY.w #.from_p0
    STY.b !WinFx_QuadLeftSide-!DP_WinFx ; nonzero: still on the left side
    LDA.b !WinFx_QuadPoints+1-!DP_WinFx
    CMP.b !WinFx_QuadPoints+3-!DP_WinFx
    BCC .min1
    LDY.w #.from_p1
    LDA.b !WinFx_QuadPoints+3-!DP_WinFx
.min1:
    CMP.b !WinFx_QuadPoints+5-!DP_WinFx
    BCC .min2
    LDY.w #.from_p2
    LDA.b !WinFx_QuadPoints+5-!DP_WinFx
.min2:
    CMP.b !WinFx_QuadPoints+7-!DP_WinFx
    BCC .min3
    LDY.w #.from_p3
    LDA.b !WinFx_QuadPoints+7-!DP_WinFx
.min3:
    STA.b !WinFx_QuadTopY-!DP_WinFx
    REP #$20
    LDA.w #$0004
    STA.b !WinFx_QuadEdgesLeft-!DP_WinFx
    STY.b !WinFx_Tmp-!DP_WinFx
    JMP (!WinFx_Tmp)
.from_p0:
    LDA.b !WinFx_QuadPoints-!DP_WinFx
    STA.b !WinFx_QuadX0-!DP_WinFx
    LDA.b !WinFx_QuadPoints+1-!DP_WinFx
    STA.b !WinFx_QuadY0-!DP_WinFx
    LDA.b !WinFx_QuadPoints+2-!DP_WinFx
    STA.b !WinFx_QuadX1-!DP_WinFx
    LDA.b !WinFx_QuadPoints+3-!DP_WinFx
    STA.b !WinFx_QuadY1-!DP_WinFx
    JSR .edge
.from_p1:
    LDA.b !WinFx_QuadPoints+2-!DP_WinFx
    STA.b !WinFx_QuadX0-!DP_WinFx
    LDA.b !WinFx_QuadPoints+3-!DP_WinFx
    STA.b !WinFx_QuadY0-!DP_WinFx
    LDA.b !WinFx_QuadPoints+4-!DP_WinFx
    STA.b !WinFx_QuadX1-!DP_WinFx
    LDA.b !WinFx_QuadPoints+5-!DP_WinFx
    STA.b !WinFx_QuadY1-!DP_WinFx
    JSR .edge
.from_p2:
    LDA.b !WinFx_QuadPoints+4-!DP_WinFx
    STA.b !WinFx_QuadX0-!DP_WinFx
    LDA.b !WinFx_QuadPoints+5-!DP_WinFx
    STA.b !WinFx_QuadY0-!DP_WinFx
    LDA.b !WinFx_QuadPoints+6-!DP_WinFx
    STA.b !WinFx_QuadX1-!DP_WinFx
    LDA.b !WinFx_QuadPoints+7-!DP_WinFx
    STA.b !WinFx_QuadY1-!DP_WinFx
    JSR .edge
.from_p3:
    LDA.b !WinFx_QuadPoints+6-!DP_WinFx
    STA.b !WinFx_QuadX0-!DP_WinFx
    LDA.b !WinFx_QuadPoints+7-!DP_WinFx
    STA.b !WinFx_QuadY0-!DP_WinFx
    LDA.b !WinFx_QuadPoints-!DP_WinFx
    STA.b !WinFx_QuadX1-!DP_WinFx
    LDA.b !WinFx_QuadPoints+1-!DP_WinFx
    STA.b !WinFx_QuadY1-!DP_WinFx
    JSR .edge
    BRA .from_p0
.edge:
    LDA.w #!Eng_HighByteMask
    TRB.b !WinFx_QuadY0-!DP_WinFx       ; (the 16-bit loads took the next point's X)
    TRB.b !WinFx_QuadY1-!DP_WinFx
    LDA.b !WinFx_QuadY1-!DP_WinFx
    CMP.b !WinFx_QuadY0-!DP_WinFx
    BPL .draw
    LDA.b !WinFx_QuadLeftSide-!DP_WinFx
    BEQ .draw
    INC.b !WinFx_QuadTablePtr-!DP_WinFx ; the first edge going up: right edges from here
    LDA.b !WinFx_QuadY0-!DP_WinFx
    STA.b !WinFx_QuadBottomY-!DP_WinFx
    STZ.b !WinFx_QuadLeftSide-!DP_WinFx
.draw:
    JSL WinFx_QuadEdge
    DEC.b !WinFx_QuadEdgesLeft-!DP_WinFx
    BEQ .edges_done
    RTS
.edges_done:
    PLA                                 ; drop the last block's return address
    LDA.b !WinFx_QuadTableBank-!DP_WinFx
    LSR A
    PHP                                 ; C = bank $7F
    DEC.b !WinFx_QuadTablePtr-!DP_WinFx
    LDA.w #!WinFx_QuadTableRows
    CLC
    SBC.b !WinFx_QuadBottomY-!DP_WinFx  ; $FF - bottom
    ASL A
    DEC A
    STA.b !WinFx_Tmp-!DP_WinFx
    LDA.b !WinFx_QuadBottomY-!DP_WinFx
    ASL A
    CLC
    ADC.b !WinFx_QuadTablePtr-!DP_WinFx
    TAY
    TAX                                 ; X = Y = the bottom row
    LDA.w #!WinFx_EmptyEntry
    STA.b [!WinFx_QuadTablePtr-!DP_WinFx] ; row 0
    PLP
    BCC .fill_7E
    STA.l !Bank7F<<16,X
    INY
    INY
    LDA.b !WinFx_Tmp-!DP_WinFx
    BEQ .filled                         ; never taken (the count is odd)
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes; rows after the bottom
    LDX.b !WinFx_QuadTablePtr-!DP_WinFx
    TXY
    INY
    INY
    LDA.b !WinFx_QuadTopY-!DP_WinFx
    BEQ .filled
    ASL A
    DEC A
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes; rows 1 to the top Y
    BRA .filled
.fill_7E:
    STA.l !Bank7E<<16,X
    INY
    INY
    LDA.b !WinFx_Tmp-!DP_WinFx
    BEQ .filled                         ; never taken
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes
    LDX.b !WinFx_QuadTablePtr-!DP_WinFx
    TXY
    INY
    INY
    LDA.b !WinFx_QuadTopY-!DP_WinFx
    BEQ .filled
    ASL A
    DEC A
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes
.filled:
    JMP WinFx_QuadExit
WinFx_QuadEdgeFlat:                     ; header: see WinFx_QuadEdge
    REP #$20
    LDA.b !WinFx_QuadY0-!DP_WinFx
    AND.w #!Eng_LowByteMask
    ASL A
    TAY
    SEP #$20
    LDA.b !WinFx_QuadX0-!DP_WinFx
    CMP.b !WinFx_QuadX1-!DP_WinFx
    BMI .x0_first
    LDA.b !WinFx_QuadX1-!DP_WinFx
    STA.b [!WinFx_QuadTablePtr-!DP_WinFx],Y
    LDA.b !WinFx_QuadX0-!DP_WinFx
    BRA .second
.x0_first:
    STA.b [!WinFx_QuadTablePtr-!DP_WinFx],Y
    LDA.b !WinFx_QuadX1-!DP_WinFx
.second:
    INY
    INY
    STA.b [!WinFx_QuadTablePtr-!DP_WinFx],Y ; the next row
    JMP WinFx_QuadExit

; $C3:1025 — WinFx_QuadEdge (155 bytes, $1025–$10BF)
; Draws one edge of WinFx_BuildQuad's shape into the table byte column
; WinFx_QuadTablePtr points at (left bytes, or right bytes once it was
; moved up by one): from (WinFx_QuadX0, WinFx_QuadY0) to (WinFx_QuadX1,
; WinFx_QuadY1), swapped first so that Y0 <= Y1; for each row Y0 to
; Y1 - 1 it stores the X of a DDA walk (error WinFx_QuadErr, steps by
; WinFx_QuadDx and WinFx_QuadDy). Rightward the error starts at dx - dy;
; per row, while it is >= 0, X moves one right and dy is taken off,
; then dx is added. Leftward the same with X moving left and |dx| added,
; but the error starts at dy - |dx| - 1 (quirk: the sign is the reverse
; of the rightward start, and there is no SEC: C=0 from the borrow of
; X1 - X0).
; A flat edge (Y0 = Y1) is WinFx_QuadEdgeFlat (sub-entry, $C3:1001,
; reached by BEQ): the smaller X goes to row Y0 and the larger to row
; Y0 + 1 (two INYs: the next row, same byte column).
; WinFx_QuadExit (sub-entry, $C3:10BA): TDC, XBA, then P, DB, DP pulled
; and RTL; WinFx_BuildQuad ends there too.
; Callers note: the JSR pattern at $C3:A153 lies in the data after the
;   packed module (probably data, not a call of WinFx_QuadEdgeFlat).
; Callers (1 JSL site): WinFx_BuildQuad ($C3:0F9C).
; Callers of WinFx_QuadEdgeFlat (1 JSR site): unmatched ($C3:A153).
; Callers of WinFx_QuadExit (1 JMP site): WinFx_BuildQuad ($C3:0FFE).
; Entry: M, X any (P saved; SEP #$20 here, X=0 assumed: 16-bit LDX/LDY
;        of the points; WinFx_BuildQuad has X=0), DP any and DB any
;        (both saved; DP_WinFx and DB = WinFx_QuadTableBank inside).
; Exit:  P, DB, DP restored; A = $0003; X, Y changed; WinFx_QuadX0..Y1
;        (high bytes cleared, maybe swapped), WinFx_QuadRows, Dx, Dy,
;        Err changed; the rows written.
WinFx_QuadEdge:
    PHD
    PHB
    PHP
    SEP #$20
    PEA.w !DP_WinFx
    PLD
    LDA.b !WinFx_QuadTableBank-!DP_WinFx
    PHA
    PLB
    STZ.b !WinFx_QuadX0+1-!DP_WinFx
    STZ.b !WinFx_QuadX1+1-!DP_WinFx
    STZ.b !WinFx_QuadY0+1-!DP_WinFx
    STZ.b !WinFx_QuadY1+1-!DP_WinFx
    STZ.b !WinFx_QuadDy+1-!DP_WinFx
    LDA.b !WinFx_QuadY1-!DP_WinFx
    SEC
    SBC.b !WinFx_QuadY0-!DP_WinFx
    BEQ WinFx_QuadEdgeFlat
    BCS .down
    LDY.b !WinFx_QuadX1-!DP_WinFx       ; going up: swap the ends
    LDX.b !WinFx_QuadX0-!DP_WinFx
    STY.b !WinFx_QuadX0-!DP_WinFx
    STX.b !WinFx_QuadX1-!DP_WinFx
    LDY.b !WinFx_QuadY1-!DP_WinFx
    LDX.b !WinFx_QuadY0-!DP_WinFx
    STY.b !WinFx_QuadY0-!DP_WinFx
    STX.b !WinFx_QuadY1-!DP_WinFx
    TXA
    SEC
    SBC.b !WinFx_QuadY0-!DP_WinFx
.down:
    STA.b !WinFx_QuadDy-!DP_WinFx
    STA.b !WinFx_QuadRows-!DP_WinFx
    REP #$20
    LDA.b !WinFx_QuadY0-!DP_WinFx
    ASL A
    CLC
    ADC.b !WinFx_QuadTablePtr-!DP_WinFx
    TAY                                 ; Y = row Y0's byte
    LDX.b !WinFx_QuadX0-!DP_WinFx
    LDA.b !WinFx_QuadX1-!DP_WinFx
    SEC
    SBC.b !WinFx_QuadX0-!DP_WinFx
    BMI .leftward
    STA.b !WinFx_QuadDx-!DP_WinFx
    SEC
    SBC.b !WinFx_QuadDy-!DP_WinFx
    STA.b !WinFx_QuadErr-!DP_WinFx
.right_row:
    LDA.b !WinFx_QuadErr-!DP_WinFx
    BMI .right_add
.right_step:
    INX
    SBC.b !WinFx_QuadDy-!DP_WinFx
    BPL .right_step
.right_add:
    ADC.b !WinFx_QuadDx-!DP_WinFx
    STA.b !WinFx_QuadErr-!DP_WinFx
    TXA
    SEP #$20
    STA.w !Eng_PtrBase,Y
    INY
    INY
    DEC.b !WinFx_QuadRows-!DP_WinFx
    REP #$20
    BNE .right_row
    BRA WinFx_QuadExit
.leftward:
    EOR.w #!Eng_Invert16
    INC A
    STA.b !WinFx_QuadDx-!DP_WinFx
    LDA.b !WinFx_QuadDy-!DP_WinFx
    SBC.b !WinFx_QuadDx-!DP_WinFx       ; no SEC: C=0, so dy - |dx| - 1
    STA.b !WinFx_QuadErr-!DP_WinFx
.left_row:
    LDA.b !WinFx_QuadErr-!DP_WinFx
    BMI .left_add
.left_step:
    DEX
    SBC.b !WinFx_QuadDy-!DP_WinFx
    BPL .left_step
.left_add:
    ADC.b !WinFx_QuadDx-!DP_WinFx
    STA.b !WinFx_QuadErr-!DP_WinFx
    TXA
    SEP #$20
    STA.w !Eng_PtrBase,Y
    INY
    INY
    DEC.b !WinFx_QuadRows-!DP_WinFx
    REP #$20
    BNE .left_row
WinFx_QuadExit:                         ; header: see WinFx_QuadEdge
    TDC
    XBA
    PLP
    PLB
    PLD
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
