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
; ROM outside it, apart from the bytes of its calls inside the packed
; data (their headers name the module's call sites, found by unpacking
; it; those addresses are in WRAM bank $7E and are not checked by any
; tool).
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
;   C2Scene_LoadExtraPalette ($C2:7B9A), C2Scene_LoadUnkC600 ($C2:7BBF), Menu_SprLoad ($C2:F542),
;   C6Scene_UnpackObjPackA ($C6:E048), C6Scene_UnpackPalPackA ($C6:E06D), C6Scene_UnpackObjPackB
;   ($C6:E66A), C6Scene_UnpackPalPackB ($C6:E68F), BattleFx_LoadBgSet ($D1:ED38, $D1:EDB4) and
;   BankFF_BuildScreenMap ($FF:F690).
; Callers of BankC3_Entry0008 (13 sites: 2 JSR, 11 JSL): Field_HookWinGrow0 (JSL $C0:225C),
;   Field_HookWinShrink0 (JSL $C0:22B7), Field_HookWinGrow1 (JSL $C0:237D), Field_HookWinShrink1
;   (JSL $C0:23DD), Field_HookWinFixedA (JSL $C0:2579), Field_HookWinFixedB (JSL $C0:25FE),
;   Field_WinPulseDraw (JSL $C0:2748), C2Scene_Win1Step (JSL $C2:7952), C2Scene_Win2Step (JSL
;   $C2:79B0), C6Scene_EllipseBuild (JSL $C6:E3D2), C6Scene_CapsuleBuild (JSL $C6:E4FB) and
;   unmatched (JSR $C3:D16C, JSR $C3:DE5C).
; Callers of BankC3_Entry000E (2 JSL sites): Field_HookWinC3E ($C0:22FA) and C6Scene_WipeWinStep
;   ($C6:E27E).
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
;        C3Mod_Code's address), X = C3_BootNmi's address when
;        C3_BootIrqOn (bit 7) of the argument is clear, else
;        Scene_VIrqLine ($00D3, from the VTIMEL write; so with
;        Field_HookLeaveToBankC3's $85), Y as on entry; C3_EntryArg =
;        the argument; Decomp_OutLen = the module's length ($857F).
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
; WinFx_FillAllBytes: $1C3 bytes, so 3 bytes past a 224-line table). Else a midpoint-circle walk (x from r down, y
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
; that first row is above line $DF). The lower fill overwrites the last
; mirrored row, except in mode 1 with an even r (rows Yc .. Yc + r/2 - 1
; are mirrored, the fill starts at Yc + r/2). For an even table address
; the upper fill overwrites the walk's top row (Yc - r - 1, see the
; quirks). With an odd address the Xc +- y rows are written through
; (RowPtr >> 1 - x) * 2, an even address, so one byte low: each left
; edge lands in the right-edge byte of the row above and each right
; edge in the left-edge byte of its row (the entries straddle two rows,
; and the upper fill overwrites part of the top one). Nothing limits the rows to the table:
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
; per line; C6Scene_WipeWinStep calls it the same way and sends the
; result to window 1's right edge, WH1; the module's C3Mod_Prog3WipeTask
; to WH2). Works on a line array of WinFx_Lines bytes at
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
; length (TAY) is $0303 or more: that run lasts to the end of the line
; array.
; The first-frame fill is in its own bank by WinFx_C3ETableBank bit 0
; ($7E/$7F: STA.l + MVN), the steps read and write with DB =
; WinFx_C3ETableBank and WMADDH = it (so it must be $7E or $7F).
; Callers (1 JMP site): BankC3_Entry000E ($C3:000E).
; Callers note: the unpacked module JSLs here directly (from $7E:6844,
;   C3Mod_Prog3WipeTask, a task: M=0, DB=$00).
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
; seed, C3_FrameCount, the H counter (OPHCT; the counters are latched
; by the CMP that reads SLHV, and that CMP's carry, A against the
; open-bus value SLHV returns, goes into this ADC), minus the V counter
; (OPVCT), the seed again, C3_ScratchF0, C3_ScratchF2 (EOR),
; C3_ScratchF4, and minus the V counter again are added or subtracted
; in, each with the carry of the step before, and the result stored
; back. Which byte each counter read gives is not fixed: OPHCT and
; OPVCT each return the low byte or bit 8 (with open bus in bits 1-7)
; by a flip-flop that every read toggles and only a STAT78 read clears,
; and nothing on this path reads STAT78 (the module's one read, at
; $7E:9AB3, is elsewhere). At M=1 OPHCT is read once a call, so it
; alternates from call to call (bit 8 and open bus every other call),
; and OPVCT twice, keeping the phase it had (low then high from a clear
; flip-flop); at M=0 the word reads also take the next register
; (OPHCT's read takes OPVCT, OPVCT's STAT77), so H is read once and V
; three times a call, and both alternate.
; Callers (1 JSL site): WinFx_StepWipe ($C3:024A).
; Callers note: the unpacked module also JSLs here, from
;   C3Mod_KernelRandom ($7E:3443), whose twelve JSR sites
;   tools/c3module.py's trace reaches: M=1 at seven, M=0 at $7F85,
;   $7FA0, $80D3, $98E3 and $98EE.
; Entry: M=1 or M=0 (WinFx_StepWipe and seven of the module's calls
;        have M=1; with M=0 every add is 16-bit: X is used whole, each
;        read takes the next register or byte as its high byte, and the
;        seed is written as a word, $0386-$0387, the module's callers
;        masking the result with an AND), X any (only its low byte is
;        used at M=1), DP any (none used), DB = $00 or a bank that maps
;        both low WRAM and the PPU registers (all operands are
;        absolute).
; Exit:  M as on entry; A = C3_RandSeed = the new value (a word at
;        M=0); flags from the last SBC; X, Y, DP, DB unchanged.
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
    ADC.w !C3_ScratchF0
    EOR.w !C3_ScratchF2
    ADC.w !C3_ScratchF4
    SBC.w OPVCT
    STA.w !C3_RandSeed
    RTL

; ============================================================
; Services of the unpacked module: bitmap scaler ($C3:0307–$C3:0528)
; ============================================================

; $C3:0307 — C3_ScaleBitmap (546 bytes, $0307–$0528)
; Draws a scaled copy of a bitmap (one byte per pixel, bits 0-3 used,
; 64-byte source rows from C3Scale_SrcBase) into rows of 4-bitplane
; bytes, 32 bytes per output row from C3Scale_Dest. For each output row
; (C3Scale_Rows - 1 of them) C3Scale_Acc += C3Scale_YStep picks the
; source row ((Acc >> 1) AND $FFC0 bytes in; it stops early once that
; reaches C3Scale_SrcLimit); a source row that repeats the last one is
; copied from the output row before (MVN, 32 bytes). Else, for
; C3Scale_Groups groups of 16 pixels, the source position X steps by
; C3Scale_XStep (8.8 fixed point; X's high byte is the pixel), and each
; 8 pixels become 4 bytes: byte k holds bit k of the 8 pixels, the
; first pixel in bit 7 (the bit planes of an SNES tile row, here 4 in a
; row). At the end, if the image is shorter than the last one
; (C3Scale_PrevEnd), the bytes from the new end on are zeroed, through
; the old end or one byte past it (see the quirks); C3Scale_PrevEnd =
; the new end.
; Purpose inferred from the arithmetic only: probably the scaled
; sprites of the module (the bank $C3 module is the jet-bike race: its
; staff text is BankC3_StaffText). The module sets C3Scale_Groups to 4
; (64 pixels) right before the calls at $7E:82A0 and $7E:897F; at
; $7E:520D it comes from a 14-byte MVN copy of a record at $1400 or
; $140E into $1F-$2C, whose first word the module sets to 4
; ($7E:502A) and 3 ($7E:50B6) respectively (other writes to those
; words, at $7E:9B2B, $7E:8BA5 and $7E:9E15, not traced to this use).
; Quirks (carries not set or cleared first):
;   - the first C3Scale_Acc add takes the caller's carry; later ones get
;     C=0 from the CLC/ADC that steps C3Scale_Dest;
;   - each new source row's first step is C3Scale_XStep + 1 when the
;     row address went up (C from the CMP with the last row);
;   - the closing clear (a 16-bit STZ at the new end, then an MVN of
;     A + 1 bytes from there to one byte on, A = old end - new end - 1
;     + C) zeroes the new end through the old end when the row count
;     ran out (C=0 from that same CLC/ADC), and through the old end + 1
;     when the source ran out (C=1 from the CMP with C3Scale_SrcLimit);
;     with C=0 and a difference of 1 nothing is cleared.
; Callers note: no caller in ROM; the unpacked module JSLs it (from
;   $7E:520D, $7E:82A0 and $7E:897F), with M=0 and DB=$7F (PEA/PLB).
; Entry: M=0, X=0 (16-bit throughout), DP = the module's (the
;        C3Scale_* direct-page bytes; 0 at $7E:520D, C3Mod_ScaleJob,
;        run from C3Mod_Start's idle loop; the other two sites' not
;        traced), DB = the bank of the source and the output ($7F at
;        all three sites: STA abs,Y and MVN $7F,$7F).
; Exit:  M=0, X=0, DB as on entry (the MVNs set it to $7F, the bank it
;        already is at the call sites); A, X, Y changed; C3Scale_Acc, Rows,
;        Dest, DestPos, SrcRow, GroupsLeft, PrevEnd, the Pixels bytes
;        and the byte after them changed.
; No calls.
C3_ScaleBitmap:
    STZ.b !C3Scale_Acc
.row:
    DEC.b !C3Scale_Rows
    BEQ .finish
    LDA.b !C3Scale_Acc
    ADC.b !C3Scale_YStep                ; no CLC (see the header)
    STA.b !C3Scale_Acc
    LSR A
    AND.w #!C3Scale_SrcRowMask
    CMP.b !C3Scale_SrcLimit
    BMI .src_row
.finish:
    LDA.b !C3Scale_PrevEnd
    SBC.b !C3Scale_Dest                 ; no SEC (see the header)
    BMI .no_clear
    BEQ .no_clear
    LDX.b !C3Scale_Dest
    STZ.w !Eng_PtrBase,X
    TXY
    INY
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
.no_clear:
    LDA.b !C3Scale_Dest
    STA.b !C3Scale_PrevEnd
    RTL
.src_row:
    CLC
    ADC.b !C3Scale_SrcBase
    CMP.b !C3Scale_SrcRow
    BNE .new_row
    LDA.b !C3Scale_Dest                 ; the same source row: copy the row above
    TAY
    SEC
    SBC.w #!C3Scale_RowBytes
    TAX
    LDA.w #!C3Scale_RowBytes-1
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    JMP .next_row
.new_row:
    STA.b !C3Scale_SrcRow
    LDX.w #$0000
    LDA.b !C3Scale_Groups
    STA.b !C3Scale_GroupsLeft
.group:
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+1
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+2
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+3
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+4
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+5
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+6
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+7
    LDY.b !C3Scale_DestPos
    SEP #$20
    LSR.b !C3Scale_Pixels
    ROL A
    LSR.b !C3Scale_Pixels+1
    ROL A
    LSR.b !C3Scale_Pixels+2
    ROL A
    LSR.b !C3Scale_Pixels+3
    ROL A
    LSR.b !C3Scale_Pixels+4
    ROL A
    LSR.b !C3Scale_Pixels+5
    ROL A
    LSR.b !C3Scale_Pixels+6
    ROL A
    LSR.b !C3Scale_Pixels+7
    ROL A
    STA.w !Eng_PtrBase,Y
    LSR.b !C3Scale_Pixels
    ROL A
    LSR.b !C3Scale_Pixels+1
    ROL A
    LSR.b !C3Scale_Pixels+2
    ROL A
    LSR.b !C3Scale_Pixels+3
    ROL A
    LSR.b !C3Scale_Pixels+4
    ROL A
    LSR.b !C3Scale_Pixels+5
    ROL A
    LSR.b !C3Scale_Pixels+6
    ROL A
    LSR.b !C3Scale_Pixels+7
    ROL A
    STA.w !Eng_PtrBase+1,Y
    LSR.b !C3Scale_Pixels
    ROL A
    LSR.b !C3Scale_Pixels+1
    ROL A
    LSR.b !C3Scale_Pixels+2
    ROL A
    LSR.b !C3Scale_Pixels+3
    ROL A
    LSR.b !C3Scale_Pixels+4
    ROL A
    LSR.b !C3Scale_Pixels+5
    ROL A
    LSR.b !C3Scale_Pixels+6
    ROL A
    LSR.b !C3Scale_Pixels+7
    ROL A
    STA.w !Eng_PtrBase+2,Y
    LSR.b !C3Scale_Pixels
    ROL A
    LSR.b !C3Scale_Pixels+1
    ROL A
    LSR.b !C3Scale_Pixels+2
    ROL A
    LSR.b !C3Scale_Pixels+3
    ROL A
    LSR.b !C3Scale_Pixels+4
    ROL A
    LSR.b !C3Scale_Pixels+5
    ROL A
    LSR.b !C3Scale_Pixels+6
    ROL A
    LSR.b !C3Scale_Pixels+7
    ROL A
    STA.w !Eng_PtrBase+3,Y
    REP #$20
    TYA
    CLC
    ADC.w #$0004
    STA.b !C3Scale_DestPos
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+1
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+2
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+3
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+4
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+5
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+6
    TXA
    ADC.b !C3Scale_XStep
    TAX
    XBA
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b (!C3Scale_SrcRow),Y
    STA.b !C3Scale_Pixels+7
    LDY.b !C3Scale_DestPos
    SEP #$20
    LSR.b !C3Scale_Pixels
    ROL A
    LSR.b !C3Scale_Pixels+1
    ROL A
    LSR.b !C3Scale_Pixels+2
    ROL A
    LSR.b !C3Scale_Pixels+3
    ROL A
    LSR.b !C3Scale_Pixels+4
    ROL A
    LSR.b !C3Scale_Pixels+5
    ROL A
    LSR.b !C3Scale_Pixels+6
    ROL A
    LSR.b !C3Scale_Pixels+7
    ROL A
    STA.w !Eng_PtrBase,Y
    LSR.b !C3Scale_Pixels
    ROL A
    LSR.b !C3Scale_Pixels+1
    ROL A
    LSR.b !C3Scale_Pixels+2
    ROL A
    LSR.b !C3Scale_Pixels+3
    ROL A
    LSR.b !C3Scale_Pixels+4
    ROL A
    LSR.b !C3Scale_Pixels+5
    ROL A
    LSR.b !C3Scale_Pixels+6
    ROL A
    LSR.b !C3Scale_Pixels+7
    ROL A
    STA.w !Eng_PtrBase+1,Y
    LSR.b !C3Scale_Pixels
    ROL A
    LSR.b !C3Scale_Pixels+1
    ROL A
    LSR.b !C3Scale_Pixels+2
    ROL A
    LSR.b !C3Scale_Pixels+3
    ROL A
    LSR.b !C3Scale_Pixels+4
    ROL A
    LSR.b !C3Scale_Pixels+5
    ROL A
    LSR.b !C3Scale_Pixels+6
    ROL A
    LSR.b !C3Scale_Pixels+7
    ROL A
    STA.w !Eng_PtrBase+2,Y
    LSR.b !C3Scale_Pixels
    ROL A
    LSR.b !C3Scale_Pixels+1
    ROL A
    LSR.b !C3Scale_Pixels+2
    ROL A
    LSR.b !C3Scale_Pixels+3
    ROL A
    LSR.b !C3Scale_Pixels+4
    ROL A
    LSR.b !C3Scale_Pixels+5
    ROL A
    LSR.b !C3Scale_Pixels+6
    ROL A
    LSR.b !C3Scale_Pixels+7
    ROL A
    STA.w !Eng_PtrBase+3,Y
    REP #$20
    TYA
    CLC
    ADC.w #$0004
    STA.b !C3Scale_DestPos
    DEC.b !C3Scale_GroupsLeft
    BEQ .next_row
    JMP .group
.next_row:
    LDA.b !C3Scale_Dest
    CLC
    ADC.w #!C3Scale_RowBytes
    STA.b !C3Scale_Dest
    STA.b !C3Scale_DestPos
    JMP .row

; $C3:0529 — C3_BootIrq (31 bytes, $0529–$0547)
; IRQ handler of the bank $C3 module, during its unpacking and after:
; C3_BootModule points the IRQ trampoline here, and no write to the
; trampolines ($0500-$0507) was found in the unpacked module, which
; turns the V-count IRQ on itself (NMITIMEN = $A1 at $7E:3017), so this
; stays its IRQ handler as far as traced. Acknowledges
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
; marker, and the packs of the C2SceneRom_* tables (graphics,
; palettes, maps, lists and scripts) to results of $13 to $3000 bytes;
; most end right where the next pack begins, but not Obj pack 13 (ends
; at $C6:1E70, the next starts at $C6:2411) nor the last pack before a
; bank boundary):
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
; WMADDH, and the back-references are MVNs inside that bank; any 16-bit
; Decomp_Dest works, so C3_BootModule's bank byte $00 with Dest $3000
; writes $7E:3000 on). After each MVN, WMADD is set again from Y
; (WMADDL/M; WMADDH is not rewritten).
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
; Services of the unpacked module: its NMI frame, multiply, copies,
; song request, code builder and pad ($C3:08B3–$C3:0AFE)
; ============================================================

; $C3:08B3 — C3_ModuleNmi (22 bytes, $08B3–$08C8)
; The module's NMI handler (C3_ModuleFrame points the NMI trampoline
; here when it ends): saves A, X, Y, DP and DB, runs one frame
; (C3_ModuleFrame), sends a pending song request (C3_SongCheck), and
; returns from the interrupt.
; Callers note: reached through !NmiTrampoline only (C3_ModuleFrame
;   writes its address there).
; Entry: interrupt: M, X, DP, DB any (REP #$30 here; the callee sets DP
;        and DB)
; Exit:  RTI: P restored; A, X, Y (16-bit), DP and DB restored.
; Calls: C3_ModuleFrame (JSL), C3_SongCheck.
C3_ModuleNmi:
    REP #$30
    PHA
    PHX
    PHY
    PHD
    PHB
    JSL C3_ModuleFrame
    JSR C3_SongCheck
    REP #$30
    PLB
    PLD
    PLY
    PLX
    PLA
    RTI

; $C3:08C9 — C3_NmiBusy (7 bytes, $08C9–$08CF)
; NMI handler while C3_ModuleFrame runs (it points the NMI trampoline
; here first): acknowledges the NMI (RDNMI) and returns, so a frame
; that overruns is not re-entered.
; Callers note: reached through !NmiTrampoline only.
; Entry: interrupt: M, X, DP any; DB any (the read is long)
; Exit:  RTI: P restored; A's low byte, X, Y, DP, DB untouched (the
;        CMP only sets flags).
C3_NmiBusy:
    SEP #$20
    CMP.l RDNMI
    RTI

; $C3:08D0 — C3_ModuleFrame (117 bytes, $08D0–$0944)
; One frame of the module, from its NMI: DP = DB = 0, acknowledges the
; NMI, HDMA off, the NMI trampoline to C3_NmiBusy, interrupts on again
; if C3_EntryArg has C3_BootIrqOn, forced blank; then, unless
; C3_Paused, the module's NMI tasks (C3Mod_RunNmiTasks, the list at
; C3_NmiTaskList); HDMAEN = C3_HdmaEnable and INIDISP =
; C3_Brightness ($80, forced blank, when it is 0); C3_FrameCount + 1;
; the task list C3_TaskList is copied to C3_TaskRun (32 bytes, MVN);
; the pad (C3_ReadPad); then if C3_Paused, INIDISP = C3_Brightness / 2
; (forced blank when that is 0) and no task runs, else the tasks run
; (C3Mod_RunTasks, from C3_TaskRun); last the NMI trampoline back to
; C3_ModuleNmi.
; Callers (1 JSL site): C3_ModuleNmi ($C3:08BA).
; Callers note: the unpacked module also JSLs it once at its start
;   ($7E:3013), before it turns the NMI on.
; Entry: M any (SEP #$20 here), X=0 (16-bit LDX of the handler
;        addresses), DP any and DB any (set to 0 here, not restored).
; Exit:  M=1, X=0, DP=0, DB=0; A, X, Y changed (Y = C3_TaskRun + $20
;        after the MVN; the module's tasks may change more).
; Calls: C3Mod_RunNmiTasks, C3Mod_RunTasks (JSL, in the unpacked
;   module), C3_ReadPad.
C3_ModuleFrame:
    SEP #$20
    PEA.w !DP_C3Zero
    PLD
    TDC
    PHA
    PLB
    CMP.w RDNMI                         ; acknowledge
    STZ.w HDMAEN
    LDX.w #C3_NmiBusy
    STX.w !NmiTrampoline+1
    LDA.w !C3_EntryArg
    BIT.b #!C3_BootIrqOn
    BEQ .blank
    CLI
.blank:
    LDA.b #FORCED_BLANK
    STA.w INIDISP
    LDA.w !C3_Paused
    BNE .show
    JSL !C3Mod_RunNmiTasks
.show:
    SEP #$20
    LDA.w !C3_HdmaEnable
    STA.w HDMAEN
    LDA.w !C3_Brightness
    BNE .set_bright
    LDA.b #FORCED_BLANK
.set_bright:
    STA.w INIDISP
    REP #$20
    INC.b !C3_FrameCount
    LDX.w #!C3_TaskList
    LDY.w #!C3_TaskRun
    LDA.w #!C3_TaskListBytes-1
    MVN $00,$00                         ; lint-ok: MVN operands are bank bytes (low WRAM)
    SEP #$20
    JSR C3_ReadPad
    LDA.w !C3_Paused
    BEQ .run_tasks
    SEP #$20
    LDA.w !C3_Brightness
    LSR A
    BNE .set_dim
    LDA.b #FORCED_BLANK
.set_dim:
    STA.w INIDISP
    REP #$20
    BRA .done
.run_tasks:
    JSL !C3Mod_RunTasks
.done:
    SEP #$20
    LDX.w #C3_ModuleNmi
    STX.w !NmiTrampoline+1
    RTL

; $C3:0945 — C3_IrqAck (7 bytes, $0945–$094B)
; An IRQ handler that only acknowledges the IRQ (TIMEUP) and returns.
; No reference to its address was found, in the kernel or in the
; unpacked module (searched for the bytes $45 $09).
; Entry: interrupt: M, X, DP any; DB any (the read is long)
; Exit:  RTI: P restored; registers untouched.
C3_IrqAck:
    SEP #$20
    CMP.l TIMEUP
    RTI

; $C3:094C — C3_MulSigned (80 bytes, $094C–$099B)
; Signed multiply with the CPU multiplier: C3_MulA (16-bit) x C3_MulB
; (8-bit) into C3_MulProduct, signed. Multiplies the magnitudes (|MulB|
; x low byte, then x high byte, added at +1) and negates the 32-bit
; result when the signs of MulA's high byte and MulB differ.
; Quirk: it is not a 32-bit product. The add at +1 is 16-bit (M=0), so
; ADC C3_MulProduct+1 also adds the byte left at +2 ($F6, which nothing
; clears: only +3 is zeroed), and the carry out of that byte is lost.
; Only the low word ($F4-$F5) is exact; the module's eight sites read
; only that word.
; Callers note: no caller in ROM; the unpacked module JSLs it (from
;   $7E:4D5C, $7E:4D6F, $7E:4D87, $7E:4D9A, $7E:4DBD, $7E:4DCF, $7E:4DEA
;   and $7E:4DFC).
; Entry: M any (P saved; SEP #$20 here), X=0 (the 16-bit LDX of the
;        first partial product), DP = 0 (C3_MulA.. are direct page;
;        0 at all eight module sites: C3Mod_ProjectBike and
;        C3Mod_ProjectRival, under a task), DB = a bank with the CPU registers
;        ($00-$3F, $80-$BF; WRMPYA.. are absolute).
; Exit:  P restored; A changed; X = |MulB| x the low byte of |MulA|; Y
;        unchanged; C3_MulProduct written.
; No calls.
C3_MulSigned:
    PHP
    SEP #$20
    LDA.b !C3_MulA+1
    EOR.b !C3_MulB
    PHP                                 ; N = the result's sign
    LDA.b !C3_MulB
    BPL .b_pos
    EOR.b #!Eng_Invert8
    INC A
.b_pos:
    STA.w WRMPYA
    REP #$20
    LDA.b !C3_MulA
    BPL .a_pos
    EOR.w #!Eng_Invert16
    INC A
.a_pos:
    SEP #$20
    STA.w WRMPYB                        ; x the low byte
    STZ.b !C3_MulProduct+3
    XBA
    LDX.w RDMPYL
    STA.w WRMPYB                        ; x the high byte
    STX.b !C3_MulProduct
    REP #$21
    LDA.w RDMPYL
    ADC.b !C3_MulProduct+1
    STA.b !C3_MulProduct+1
    PLP
    BPL .done
    REP #$21
    LDA.b !C3_MulProduct
    EOR.w #!Eng_Invert16
    ADC.w #$0001
    STA.b !C3_MulProduct
    LDA.b !C3_MulProduct+2
    EOR.w #!Eng_Invert16
    ADC.w #$0000
    STA.b !C3_MulProduct+2
.done:
    PLP
    RTL

; $C3:099C — C3_CopyFEto7E (4 bytes, $099C–$099F)
; MVN from ROM bank $FE (C3Rom_PackPtrs' bank) to WRAM bank $7E, then
; RTL: copies A + 1 bytes from $FE:X to $7E:Y.
; Callers note: no caller in ROM; the unpacked module JSLs it (from
;   $7E:36C5), with A = the length - 1.
; Entry: M any (MVN takes the whole 16-bit A), X=0 (16-bit X and Y), DP
;        any, DB any; A = count - 1, X = source, Y = destination
; Exit:  A = $FFFF; X, Y past the copied bytes; DB = $7E (MVN).
C3_CopyFEto7E:
    MVN !Bank7E,!C3Rom_PackBank         ; lint-ok: MVN operands are bank bytes (as asar orders them)
    RTL

; $C3:09A0 — C3_CopyFEto7F (4 bytes, $09A0–$09A3)
; As C3_CopyFEto7E, to WRAM bank $7F.
; Callers note: the unpacked module JSLs it (from $7E:36BC); the site
;   at $C3:17D2 is that call's bytes inside BankC3_PackedModule (a
;   literal of the packed stream), not code that runs from ROM.
; Callers (1 JSL site): unmatched ($C3:17D2).
; Entry: M any, X=0, DP any, DB any; A = count - 1, X = source, Y =
;        destination
; Exit:  A = $FFFF; X, Y past the copied bytes; DB = $7F (MVN).
C3_CopyFEto7F:
    MVN !Bank7F,!C3Rom_PackBank         ; lint-ok: MVN operands are bank bytes (as asar orders them)
    RTL

; $C3:09A4 — C3_SongCheck (53 bytes, $09A4–$09D8)
; Sends a song change to the sound driver: unless C3_SongBusy is set
; or C3_EntryArg has bit 5 (C3_EntryNoSong), and if C3_SongReq differs
; from C3_SongCur, it copies the request to C3_SongCur and sends
; Audio_CmdPlayMusic with the song in Audio_CmdArg0 and $FFFF in
; Audio_CmdArg1/Arg2 (Audio_DriverCommand), C3_SongBusy set around the
; call.
; Callers (1 JSR site): C3_ModuleNmi ($C3:08BE).
; Entry: M any (SEP #$20 here), X=0 (16-bit STX of $FFFF), DP any,
;        DB=$00 (all absolute; C3_ModuleFrame leaves it)
; Exit:  M=1, X=0; A changed; X = $FFFF when a song was sent, else
;        unchanged; Y unchanged (and what Audio_DriverCommand changes).
; Calls: Audio_DriverCommand (JSL).
C3_SongCheck:
    SEP #$20
    LDA.w !C3_SongBusy
    BNE .done
    LDA.w !C3_EntryArg
    BIT.b #!C3_EntryNoSong
    BNE .done
    LDA.w !C3_SongReq
    CMP.w !C3_SongCur
    BEQ .done
    STA.w !C3_SongCur
    INC.w !C3_SongBusy
    LDA.b #!Audio_CmdPlayMusic
    STA.w !Audio_CmdId
    LDA.w !C3_SongReq
    STA.w !Audio_CmdArg0
    LDX.w #!C3_SongArgs
    STX.w !Audio_CmdArg1
    JSL Audio_DriverCommand
    STZ.w !C3_SongBusy
.done:
    RTS

; $C3:09D9 — C3_CopyCodeOrder (16 bytes, $09D9–$09E8)
; Eight source offsets for C3_BuildCopyCode's outer passes: $000,
; $200, $100, $300, $400, $600, $500, $700 (16-bit, indexed by the
; pass x 2).
C3_CopyCodeOrder:
    dw $0000,$0200,$0100,$0300,$0400,$0600,$0500,$0700

; $C3:09E9 — C3_BuildCopyCode (165 bytes, $09E9–$0A8D)
; Writes a routine through WMDATA (WMADD set by the caller): 1,024
; pairs LDA abs / STA dp (each a 16-bit word, so the routine runs with
; M=0), with LDA #page / TCD before every 128 pairs, and a final RTS.
; The stores go to consecutive words from X (the direct page starts at
; X's high byte and moves up one page every 128 words: $800 bytes in
; all). Word n's source is Y + C3_CopyCodeOrder[p] + 4i + 2j + $20k for
; the passes p (0-7) > i (0-7) > j (0-1) > k (0-7), k fastest. With
; C3_ScaleBitmap's 32-byte rows as the source that is, per 8-row band
; (in the order of C3_CopyCodeOrder) and per 8-pixel column i, the
; words of bit planes 0-1 for rows 0-7, then planes 2-3: the layout of
; SNES 4bpp tiles. The module builds it at $7E:B574 with X = $0C00 and
; Y = $0200 and JSRs $B574 right after C3_ScaleBitmap, so it probably
; turns the scaled image into tiles (inferred from the arithmetic; the
; module's use is not traced further).
; Callers note: no caller in ROM; the unpacked module JSLs it (from
;   $7E:3CFB, $7E:799D and $7E:8569).
; Entry: M any (REP #$20 here), X=0; DP any and DB any (set to 0 here,
;        not restored); X = the destination (low byte 0), Y = the
;        source base; WMADDL/M/H = where the code goes.
; Exit:  M=1, X=0, DP=0, DB=0; A = $60; X = the destination + $800; Y =
;        $0010; C3_GenOrder..C3_GenPage ($F0-$FB) changed.
; No calls.
C3_BuildCopyCode:
    REP #$20
    LDA.w #$0000
    TCD
    STX.b !C3_GenDest
    STY.b !C3_GenSrc
    TAY                                 ; Y = the pass x 2
    STA.b !C3_GenOrder
    STA.b !C3_GenI
    STA.b !C3_GenJ
    STA.b !C3_GenK
    SEP #$20
    PHA
    PLB
.pass:
    REP #$20
    PHX
    TYX
    LDA.l C3_CopyCodeOrder,X
    STA.b !C3_GenOrder
    PLX
    SEP #$20
    PHY
    STZ.b !C3_GenI
    LDY.w #$0008
.loop_i:
    PHY
    STZ.b !C3_GenJ
    LDY.w #$0002
.loop_j:
    PHY
    STZ.b !C3_GenK
    LDY.w #$0008
.loop_k:
    TXA
    BNE .no_page
    LDA.b #!Op_LdaImm                   ; LDA #page<<8 / TCD
    STA.w WMDATA
    TDC
    STA.w WMDATA
    LDA.b !C3_GenPage
    STA.w WMDATA
    INC.b !C3_GenPage
    LDA.b #!Op_Tcd
    STA.w WMDATA
.no_page:
    LDA.b #!Op_LdaAbs
    STA.w WMDATA
    REP #$20
    LDA.b !C3_GenOrder
    CLC
    ADC.b !C3_GenI
    CLC
    ADC.b !C3_GenJ
    CLC
    ADC.b !C3_GenK
    CLC
    ADC.b !C3_GenSrc
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b #!Op_StaDp
    STA.w WMDATA
    TXA
    STA.w WMDATA
    INX
    INX
    LDA.b !C3_GenK
    CLC
    ADC.b #!C3_GenKStep
    STA.b !C3_GenK
    DEY
    BNE .loop_k
    PLY
    INC.b !C3_GenJ
    INC.b !C3_GenJ
    DEY
    BNE .loop_j
    PLY
    LDA.b !C3_GenI
    CLC
    ADC.b #$04
    STA.b !C3_GenI
    DEY
    BNE .loop_i
    PLY
    INY
    INY
    CPY.w #!C3_CopyCodePasses*2
    BEQ .end
    JMP .pass
.end:
    LDA.b #!Op_Rts
    STA.w WMDATA
    RTL

; $C3:0A8E — C3_ReadPad (113 bytes, $0A8E–$0AFE)
; The module's pad handling, once a frame: waits for the auto-joypad
; read, keeps JOY1 in C3_Pad; L+R+Select+Start alone
; (C3_PadSoftReset) resets the game (forced blank, NMI and HDMA off,
; JML Reset) unless C3_NoSoftReset is set. If C3_PauseAllowed is set,
; a Start press (C3_PadStartHi) toggles C3_Paused once per press
; (C3_PauseHeld) and sends a sound command to the module's driver
; routine C3Mod_AudioCommand: $F2 on pausing, $18 with arguments $44,
; $80 on resuming (probably the music pause and resume; not traced).
; Callers (1 JSR site): C3_ModuleFrame ($C3:091F).
; Entry: M any (SEP #$20 here), X=0 (C3Mod_AudioCommand loads X with
;        16 bits), DP=0 (C3_Pad is direct page), DB=$00 (the CPU
;        registers and the module's bytes are absolute; C3_ModuleFrame
;        sets both).
; Exit:  the soft reset does not return; else M=0; A changed; X
;        changed when C3Mod_AudioCommand was called (it counts X down),
;        else unchanged; Y unchanged.
; Calls: C3Mod_AudioCommand (JSL, in the unpacked module).
C3_ReadPad:
    SEP #$20
.wait:
    LDA.w HVBJOY
    BIT.b #!C3_PadAutoReadBusy
    BNE .wait
    REP #$20
    LDA.w JOY1L
    STA.b !C3_Pad
    CMP.w #!C3_PadSoftReset
    BNE .pause
    SEP #$20
    LDA.w !C3_NoSoftReset
    BNE .pause
    LDA.b #FORCED_BLANK
    STA.w INIDISP
    STZ.w NMITIMEN
    STZ.w HDMAEN
    JML Reset&!Eng_AddrMask16           ; Reset's bank-$00 mirror ($00:FF00)
.pause:
    REP #$20
    LDA.w !C3_PauseAllowed
    BEQ .done
    LDA.b !C3_Pad+1
    BIT.w #!C3_PadStartHi
    BEQ .released
    LDA.w !C3_PauseHeld
    BNE .done
    INC.w !C3_PauseHeld
    LDA.w !C3_Paused
    INC A
    AND.w #$0001
    STA.w !C3_Paused
    BEQ .resume
    LDA.w #!C3_SndPause
    STA.w !Audio_CmdId
    JSL !C3Mod_AudioCommand
    BRA .done
.resume:
    LDA.w #!C3_SndResume
    STA.w !Audio_CmdId
    LDA.w #!C3_SndResumeArg
    STA.w !Audio_CmdArg1
    JSL !C3Mod_AudioCommand
    BRA .done
.released:
    STZ.w !C3_PauseHeld
.done:
    REP #$20
    RTS

; ============================================================
; Services of the unpacked module: the script interpreter and its
; task lists ($C3:0AFF–$C3:0D0D)
; ============================================================

; $C3:0AFF — C3_RunScript (441 bytes, $0AFF–$0CB7)
; Runs a script of the module from C3Script_Ptr until an opcode yields.
; All C3Script_* bytes are direct page: each script has its own page
; (the module calls it with DP = $0A00 and $0B00). An opcode is a word
; read at the pointer (only its low byte counts) and the pointer moves
; on by one; operands follow:
;   $00-$7F  variable n = bits 0-3 (C3Script_Vars + 2n):
;            bits 4-7 = $0: var = word w; $2: var = var m (a byte, m x 2
;            in bits 1-4); other values with bit 5 clear: var += word
;            w; with bit 5 set: var += var m
;   $80-$8F  loop on counter n (C3Script_Counters + 2n), word limit,
;            word target: while the counter (0 at first) is 0 or below
;            the limit, it goes up by one and the script jumps to the
;            target; at the limit the counter is cleared and the script
;            goes on after the operands. $90-$9F the same, then yields.
;   $A0-$FF  by bits 0-3 (bits 4-6 are ignored), 
;            0 call module routine w (C3Mod_CallW with w in
;            C3_ScratchF0: LDX #0 / JSR ($00F0,X) / RTL at $7E:37F3,
;            so w is a $7E address, e.g. $7E:7EE8); 1 poke byte
;            b at bank-$00 address w; 2 poke word; 3 call w (the return
;            point goes to C3Script_Ret); 4 return; 5 wait until APUIO2's
;            low nibble reaches byte b (else yield and retry the opcode
;            next time); 6 driver command w1 to Audio_CmdId/Arg0, w2 to
;            Arg1/Arg2 (Audio_DriverCommand, skipped while C3_SongBusy);
;            7 / 8 remove / add w in C3_NmiTaskList; 9 / A the same in
;            C3_TaskList; B write byte b to PPU register $2100 + byte r;
;            C yield; D jump to w and yield; E jump to w; F end: sets
;            C3_ExitFlag and yields without moving on (the module's main
;            loop waits for that flag).
; Quirks: C3Script_Ret is also loop counter 7; the bytes at $C3:0BEF-
; $C3:0C18 (an APUIO0-3 send loop like the module's C3Mod_AudioCommand)
; are reached by nothing (opcode 6 jumps over them to .skip2).
; Callers note: the unpacked module JSLs it (from $7E:374F with DP =
;   $0A00, and $7E:375A with DP = $0B00; both after PHK/PLB, so DB =
;   $7E); the site at $C3:185C is one of those calls' bytes inside
;   BankC3_PackedModule (a literal of the packed stream).
; Callers (1 JSL site): unmatched ($C3:185C).
; Entry: M=0, X=0 (16-bit opcodes, operands and indexes), DP = the
;        script's page, DB = the script's bank ($7E; the pointer is
;        16-bit, DP-indirect).
; Exit:  M=0, X=0; A, X changed; Y as Audio_DriverCommand and opcode
;        0's module routine leave it; DP and DB unchanged by this
;        routine itself, but an opcode 0 routine (module code, not
;        checked here; $7E:7EE8's MVNs set DB to $7E) may change them,
;        and the X flag (M is set again by the REP #$20 after it);
;        C3Script_Ptr at the next opcode (or at the same
;        one for opcodes 5 and F).
; Calls: C3Mod_CallW (JSL, in the unpacked module),
;   Audio_DriverCommand (JSL), C3_TaskListAdd/Remove,
;   C3_NmiListAdd/Remove.
C3_RunScript:
    JSR .run
    RTL
.run:
    LDA.b (!C3Script_Ptr)
    INC.b !C3Script_Ptr
    BIT.w #!C3Script_OpFlow
    BNE .flow
    PHA
    AND.w #!C3Script_NibbleMask
    ASL A
    STA.b !C3Script_Tmp
    TDC
    ADC.b !C3Script_Tmp                 ; the variable's address (C=0 from the ASL)
    STA.b !C3Script_Tmp
    PLA
    AND.w #!C3Script_KindMask
    BIT.w #!C3Script_FromVar
    BNE .from_var
    CMP.w #$0000
    BNE .add_word
    LDA.b (!C3Script_Ptr)
    BRA .store_skip2
.add_word:
    LDA.b (!C3Script_Tmp)
    CLC
    ADC.b (!C3Script_Ptr)
    BRA .store_skip2
.from_var:
    CMP.w #!C3Script_FromVar
    BNE .add_var
    LDA.b (!C3Script_Ptr)
    AND.w #!C3Script_VarIndexMask
    TAX
    LDA.b !C3Script_Vars,X
    BRA .store_skip1
.add_var:
    LDA.b (!C3Script_Ptr)
    AND.w #!C3Script_VarIndexMask
    TAX
    LDA.b (!C3Script_Tmp)
    CLC
    ADC.b !C3Script_Vars,X
    BRA .store_skip1
.store_skip2:
    INC.b !C3Script_Ptr
.store_skip1:
    INC.b !C3Script_Ptr
    STA.b (!C3Script_Tmp)
    BRA .run
.flow:
    STA.b !C3Script_Tmp
    AND.w #!C3Script_KindMask
    CMP.w #!C3Script_OpLoop
    BNE .not_loop
    JMP .op_loop
.not_loop:
    CMP.w #!C3Script_OpLoopYield
    BNE .table_op
    JMP .op_loop_yield
.table_op:
    LDA.b !C3Script_Tmp
    AND.w #!C3Script_NibbleMask
    ASL A
    TAX
    JMP (.op_table,X)
.op_table:                              ; C3Script opcodes $A0-$FF by bits 0-3
    dw .op_call_w           ; 0
    dw .op_poke8            ; 1
    dw .op_poke16           ; 2
    dw .op_call             ; 3
    dw .op_return           ; 4
    dw .op_wait_apu         ; 5
    dw .op_driver           ; 6
    dw .op_nmi_remove       ; 7
    dw .op_nmi_add          ; 8
    dw .op_task_remove      ; 9
    dw .op_task_add         ; A
    dw .op_ppu              ; B
    dw .op_yield            ; C
    dw .op_jump_yield       ; D
    dw .op_jump             ; E
    dw .op_end              ; F
    db $DB                              ; a stray byte after the table: no entry or branch reaches it
.op_end:
    DEC.b !C3Script_Ptr                 ; stay on this opcode
    LDA.w #$0001
    STA.l !C3_ExitFlag
    RTS
.op_jump:
    LDA.b (!C3Script_Ptr)
    STA.b !C3Script_Ptr
    JMP .run
.op_jump_yield:
    LDA.b (!C3Script_Ptr)
    STA.b !C3Script_Ptr
.op_yield:
    RTS
.op_task_add:
    LDA.b (!C3Script_Ptr)
    TAX
    JSR C3_TaskListAdd
.skip2:
    REP #$20
    INC.b !C3Script_Ptr
.skip1:
    REP #$20
    INC.b !C3Script_Ptr
    JMP .run
.op_task_remove:
    LDA.b (!C3Script_Ptr)
    TAX
    JSR C3_TaskListRemove
    BRA .skip2
.op_nmi_add:
    LDA.b (!C3Script_Ptr)
    TAX
    JSR C3_NmiListAdd
    BRA .skip2
.op_nmi_remove:
    LDA.b (!C3Script_Ptr)
    TAX
    JSR C3_NmiListRemove
    BRA .skip2
.op_driver:
    LDA.b (!C3Script_Ptr)
    STA.w !Audio_CmdId
    INC.b !C3Script_Ptr
    INC.b !C3Script_Ptr
    LDA.b (!C3Script_Ptr)
    STA.w !Audio_CmdArg1
    SEP #$20
    LDA.w !C3_SongBusy
    BNE .skip2
    JSL Audio_DriverCommand
    BRA .skip2
.dead_send:                             ; never reached (see the header)
    LDX.w #!C3_ApuTimeout
    LDA.w !Audio_CmdArg2
    STA.l APUIO3
    LDA.w !Audio_CmdArg1
    STA.l APUIO2
    LDA.w !Audio_CmdArg0
    STA.l APUIO1
    LDA.w !Audio_CmdId
    STA.l APUIO0
.dead_wait:
    CMP.l APUIO0
    BEQ .skip2
    DEX
    BNE .dead_wait
    BRA .dead_send
.op_poke8:
    LDA.b (!C3Script_Ptr)
    TAX
    INC.b !C3Script_Ptr
    INC.b !C3Script_Ptr
    SEP #$20
    LDA.b (!C3Script_Ptr)
    STA.l !Eng_PtrBase,X
.to_skip1:
    BRA .skip1
.op_wait_apu:
    SEP #$20
    LDA.l APUIO2
    CMP.l APUIO2
    BNE .op_wait_apu                    ; until two reads agree
    AND.b #!C3Script_NibbleMask
    CMP.b (!C3Script_Ptr)
    BPL .to_skip1
    REP #$20
    DEC.b !C3Script_Ptr                 ; back to the opcode: retried next time
    RTS
.op_poke16:
    LDA.b (!C3Script_Ptr)
    TAX
    INC.b !C3Script_Ptr
    INC.b !C3Script_Ptr
    LDA.b (!C3Script_Ptr)
    STA.l !Eng_PtrBase,X
    JMP .skip2
.op_call_w:
    REP #$20
    LDA.b (!C3Script_Ptr)
    STA.w !C3_ScratchF0
    JSL !C3Mod_CallW
    JMP .skip2
.op_ppu:
    SEP #$20
    LDA.b (!C3Script_Ptr)
    PHA
    REP #$20
    INC.b !C3Script_Ptr
    LDA.b (!C3Script_Ptr)
    AND.w #!Eng_LowByteMask
    CLC
    ADC.w #!DP_PPU
    TAX
    SEP #$20
    PLA
    STA.l !Eng_PtrBase,X
    JMP .skip1
.op_call:
    LDA.b !C3Script_Ptr
    INC A
    INC A
    STA.b !C3Script_Ret
    JMP .op_jump
.op_return:
    LDA.b !C3Script_Ret
    STA.b !C3Script_Ptr
    JMP .run
.op_loop:
    JSR .op_loop_yield
    JMP .run
.op_loop_yield:
    LDA.b !C3Script_Tmp
    AND.w #!C3Script_NibbleMask
    ASL A
    TAX
    LDA.b !C3Script_Counters,X
    BEQ .loop_again
    CMP.b (!C3Script_Ptr)
    BMI .loop_again
    STZ.b !C3Script_Counters,X          ; the limit: go on
    LDA.b !C3Script_Ptr
    CLC
    ADC.w #$0004
    STA.b !C3Script_Ptr
    RTS
.loop_again:
    INC A
    STA.b !C3Script_Counters,X
    INC.b !C3Script_Ptr
    INC.b !C3Script_Ptr
    LDA.b (!C3Script_Ptr)
    STA.b !C3Script_Ptr
    RTS

; $C3:0CB8 — C3_TaskListRemove (21 bytes, $0CB8–$0CCC)
; Clears the first word of C3_TaskList equal to X. There is no bound: a
; value that is not in the list is searched for past its end.
; Callers (1 JSR site): C3_RunScript ($C3:0BBF).
; Entry: M any (P saved; REP #$20 here), X=0 (16-bit), DP any, DB = a
;        bank that maps low WRAM ($00 or $7E; the list is absolute); X =
;        the value.
; Exit:  P restored; A = the value; X = its offset in the list; Y
;        unchanged.
C3_TaskListRemove:
    PHP
    REP #$20
    TXA
    LDX.w #$0000
.find:
    CMP.w !C3_TaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    STZ.w !C3_TaskList,X
    PLP
    RTS

; $C3:0CCD — C3_NmiListRemove (21 bytes, $0CCD–$0CE1)
; As C3_TaskListRemove, for C3_NmiTaskList.
; Callers (1 JSR site): C3_RunScript ($C3:0BCF).
; Entry: M any (P saved), X=0, DP any, DB = $00 or $7E; X = the value.
; Exit:  P restored; A = the value; X = its offset; Y unchanged.
C3_NmiListRemove:
    PHP
    REP #$20
    TXA
    LDX.w #$0000
.find:
    CMP.w !C3_NmiTaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    STZ.w !C3_NmiTaskList,X
    PLP
    RTS

; $C3:0CE2 — C3_TaskListAdd (22 bytes, $0CE2–$0CF7)
; Stores X in the first zero word of C3_TaskList (no bound: a full
; list is searched past its end).
; Callers (1 JSR site): C3_RunScript ($C3:0BAE).
; Entry: M any (P saved; REP #$20 here), X=0 (pushed and pulled as a
;        word), DP any, DB = $00 or $7E; X = the value (a task address
;        in the module, run by C3Mod_RunTasks).
; Exit:  P restored; A = the value; X = its offset in the list; Y
;        unchanged.
C3_TaskListAdd:
    PHP
    PHX
    LDX.w #$0000
    REP #$20
.find:
    LDA.w !C3_TaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    PLA
    STA.w !C3_TaskList,X
    PLP
    RTS

; $C3:0CF8 — C3_NmiListAdd (22 bytes, $0CF8–$0D0D)
; As C3_TaskListAdd, for C3_NmiTaskList (run by C3Mod_RunNmiTasks).
; Callers (1 JSR site): C3_RunScript ($C3:0BC7).
; Entry: M any (P saved), X=0, DP any, DB = $00 or $7E; X = the value.
; Exit:  P restored; A = the value; X = its offset; Y unchanged.
C3_NmiListAdd:
    PHP
    PHX
    LDX.w #$0000
    REP #$20
.find:
    LDA.w !C3_NmiTaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    PLA
    STA.w !C3_NmiTaskList,X
    PLP
    RTS

; ============================================================
; Services of the unpacked module: sprites, a divide search, staff
; text ($C3:0D0E–$C3:0EF9)
; ============================================================

; $C3:0D0E — C3_SprListSmall (80 bytes, $0D0E–$0D5D)
; Adds a list of small sprites to the OAM shadow: the list (in bank
; $7E at A, read through WMDATA) is a byte n + 1, then n records of
; tile, attribute, X, Y. X and Y get C3_SprBaseX / C3_SprBaseY added
; (8-bit, wrapping); each sprite goes to Oam_LowTable + C3_OamPos, and
; its high-table byte (at C3_OamHiPtr, the next one after every 4
; sprites) is shifted right by 2 when nonzero, so the new sprite's two
; bits are 0 (X bit 8 clear, small size).
; Callers note: no caller in ROM; the unpacked module JSLs it (from
;   $7E:3A78, $7E:5155, $7E:5D0C, $7E:5D1B, $7E:5D2D, $7E:5D9A, $7E:5E2B
;   and $7E:5E37).
; Entry: M=0 (A stored to WMADDL/M as a word), X=0 (16-bit X/Y), DP =
;        the module's (C3_OamPos.. are direct page; 0 at $7E:3A78,
;        $7E:5155 and the six program-2 sites $7E:5D0C-$7E:5E37, in four
;        tasks), DB =
;        a bank that maps the I/O registers and low WRAM ($00-$3F or
;        $80-$BF: WMADDL/WMADDH/WMDATA and the OAM shadow are absolute;
;        with DB=$7E the port accesses would hit WRAM $7E:2180-$2183
;        instead). The site at $7E:3A78 has DB=$00 (PEA $007E, PLB,
;        PLB), and $7E:5155 (C3Mod_DrawHud) and the program-2 sites
;        too, all under a task. A = the list's address.
; Exit:  M=0, X=0; A changed; X = C3_OamHiPtr, Y = C3_OamPos (both
;        advanced); C3_SprLeft = 0; WMADD after the list.
C3_SprListSmall:
    STA.w WMADDL
    SEP #$20
    LDY.b !C3_OamPos
    LDX.b !C3_OamHiPtr
    STZ.w WMADDH                        ; bank $7E
    LDA.w WMDATA
    STA.b !C3_SprLeft
.next:
    DEC.b !C3_SprLeft
    BEQ .done
    LDA.w WMDATA
    STA.w !Oam_LowTable+2,Y             ; tile
    LDA.w WMDATA
    STA.w !Oam_LowTable+3,Y             ; attribute
    LDA.w WMDATA
    CLC
    ADC.b !C3_SprBaseX
    STA.w !Oam_LowTable,Y
    LDA.w WMDATA
    CLC
    ADC.b !C3_SprBaseY
    STA.w !Oam_LowTable+1,Y
    LDA.w !Eng_PtrBase,X
    BEQ .hi_done
    LSR A
    LSR A
    STA.w !Eng_PtrBase,X
.hi_done:
    INY
    INY
    INY
    INY
    TYA
    AND.b #!C3_OamGroupMask
    BNE .next
    INX
    BRA .next
.done:
    REP #$20
    STX.b !C3_OamHiPtr
    STY.b !C3_OamPos
    RTL

; $C3:0D5E — C3_SprListLarge (94 bytes, $0D5E–$0DBB)
; As C3_SprListSmall for large sprites with a 9-bit X: X = byte +
; C3_SprBaseX (16-bit); from $100 up it is replaced by $101 (off
; screen, through the word C3_OffscreenX: low byte $01, bit 15 set);
; a negative X keeps its low byte and gets bit 8 set. The high-table
; byte is always shifted right by 2 with size = 1 and X bit 8 put in.
; Callers note: no caller in ROM; the unpacked module JSLs it (from
;   $7E:5042, $7E:50CE, $7E:514E, $7E:56F8, $7E:5D3F, $7E:8245, $7E:88A0,
;   $7E:88B4 and $7E:9A07).
; Entry: as C3_SprListSmall: M=0, X=0, DP = the module's (0 at
;        $7E:5042, $7E:50CE, $7E:514E, $7E:56F8 and $7E:5D3F, the others
;        not traced), DB = a bank that maps the I/O registers and low
;        WRAM ($00-$3F or $80-$BF: WMADDL/H, WMDATA and the OAM shadow
;        are absolute; $00 at those five, under a task; the other
;        sites' not traced); A = the list's address.
; Exit:  M=0, X=0; A changed; X = C3_OamHiPtr, Y = C3_OamPos (both
;        advanced); C3_SprLeft = 0; WMADD after the list.
C3_SprListLarge:
    STA.w WMADDL
    SEP #$20
    LDY.b !C3_OamPos
    LDX.b !C3_OamHiPtr
    STZ.w WMADDH
    LDA.w WMDATA
    STA.b !C3_SprLeft
.next:
    DEC.b !C3_SprLeft
    BEQ .done
    LDA.w WMDATA
    STA.w !Oam_LowTable+2,Y
    LDA.w WMDATA
    STA.w !Oam_LowTable+3,Y
    LDA.w WMDATA
    REP #$21
    AND.w #!Eng_LowByteMask
    ADC.b !C3_SprBaseX
    CMP.w #!C3_ScreenRight
    BMI .x_ok
    LDA.w #!C3_OffscreenX
.x_ok:
    STA.w !Oam_LowTable,Y               ; (the high byte is replaced by Y below)
    ASL A                               ; C = X bit 8 (bit 15)
    SEP #$20
    LDA.w !Eng_PtrBase,X
    ROR A
    SEC
    ROR A                               ; top bits: size 1, X bit 8
    STA.w !Eng_PtrBase,X
    LDA.w WMDATA
    CLC
    ADC.b !C3_SprBaseY
    STA.w !Oam_LowTable+1,Y
    INY
    INY
    INY
    INY
    TYA
    AND.b #!C3_OamGroupMask
    BNE .next
    INX
    BRA .next
.done:
    REP #$20
    STX.b !C3_OamHiPtr
    STY.b !C3_OamPos
    RTL

; $C3:0DBC — C3_SprOneSmall (55 bytes, $0DBC–$0DF2)
; Adds one small sprite from a 4-byte record in bank $7E at X (tile,
; attribute, X, Y; X and Y + C3_SprBaseX / C3_SprBaseY, 8-bit) at
; C3_OamPos; its high-table byte (through C3_OamHiPtr) is shifted right
; by 2 when nonzero; after every 4 sprites C3_OamHiPtr moves on.
; Callers note: no caller in ROM; the unpacked module JSLs it (from
;   $7E:5111, $7E:5137 and $7E:6629).
; Entry: M=0 (the tile and attribute are moved as a word), X=0, DP =
;        the module's (0 at all three, under a task), DB = $00 or $7E
;        ($00 at all three); X = the record.
; Exit:  P restored; A changed; Y = the new C3_OamPos; X unchanged.
C3_SprOneSmall:
    PHP
    LDY.b !C3_OamPos
    LDA.l !Bank7E<<16,X
    STA.w !Oam_LowTable+2,Y             ; tile, attribute
    SEP #$20
    LDA.l (!Bank7E<<16)+2,X
    CLC
    ADC.b !C3_SprBaseX
    STA.w !Oam_LowTable,Y
    LDA.l (!Bank7E<<16)+3,X
    CLC
    ADC.b !C3_SprBaseY
    STA.w !Oam_LowTable+1,Y
    LDA.b (!C3_OamHiPtr)
    BEQ .hi_done
    LSR A
    LSR A
    STA.b (!C3_OamHiPtr)
.hi_done:
    INY
    INY
    INY
    INY
    TYA
    AND.b #!C3_OamGroupMask
    BNE .store
    INC.b !C3_OamHiPtr
.store:
    STY.b !C3_OamPos
    PLP
    RTL

; $C3:0DF3 — C3_SprOneLarge (54 bytes, $0DF3–$0E28)
; As C3_SprOneSmall for a large sprite: the high-table byte is always
; shifted right by 2 with size = 1 and X bit 8 = 0. No reference to its
; address was found in the kernel or in the unpacked module.
; Entry: M=0, X=0, DP = the module's (probably 0), DB = $00 or $7E; X =
;        the record.
; Exit:  P restored; A changed; Y = the new C3_OamPos; X unchanged.
C3_SprOneLarge:
    PHP
    LDY.b !C3_OamPos
    LDA.l !Bank7E<<16,X
    STA.w !Oam_LowTable+2,Y
    SEP #$20
    LDA.l (!Bank7E<<16)+2,X
    CLC
    ADC.b !C3_SprBaseX
    STA.w !Oam_LowTable,Y
    LDA.l (!Bank7E<<16)+3,X
    CLC
    ADC.b !C3_SprBaseY
    STA.w !Oam_LowTable+1,Y
    LDA.b (!C3_OamHiPtr)
    LSR A
    SEC
    ROR A
    STA.b (!C3_OamHiPtr)
    INY
    INY
    INY
    INY
    TYA
    AND.b #!C3_OamGroupMask
    BNE .store
    INC.b !C3_OamHiPtr
.store:
    STY.b !C3_OamPos
    PLP
    RTL

; $C3:0E29 — C3_FindDivisor (13 bytes, $0E29–$0E35)
; Counts the divisor up until the quotient falls below C3_ScratchF4:
; each pass waits two NOPs, adds 1 to X, reads the quotient of the
; division running (RDDIVL) and starts the next one with WRDIVB = X;
; it stops when that quotient is below C3_ScratchF4. So on return A =
; the first quotient below it (for divisor X - 1) and a division by X
; has been started. The caller sets the dividend and the first divisor.
; Callers note: no caller in ROM; the unpacked module JSLs it (from
;   $7E:4F1C, with DP = $4200 and 8-bit X after SEP #$10).
; Entry: M=0 (16-bit quotient), X=1 (8-bit divisor), DP = DP_CPU (the
;        divider registers are direct page), DB = $00 or $7E
;        (C3_ScratchF4 is absolute).
; Exit:  M=0, X=1; A = the quotient; X = the divisor + 1; C=0.
C3_FindDivisor:
    NOP
    NOP
    INX
    LDA.b RDDIVL-!DP_CPU
    STX.b WRDIVB-!DP_CPU
    CMP.w !C3_ScratchF4
    BCS C3_FindDivisor
    RTL

; $C3:0E36 — BankC3_StaffText (196 bytes, $0E36–$0EF9)
; ASCII, lines ended by $0A (the text starts with a $0A, so its first
; line is empty): the staff of the jet-bike race (the module), as in
; the ROM ("JONNY" spelt so). No reader was found in the
; kernel or the unpacked module (no reference to $0E36).
BankC3_StaffText:
    db $0A,"-- JET BIKE RACE --",$0A
    db "BIKE OBJECT  :MAMI KAWAI",$0A
    db "JONNY OBJECT :TAYZO INUKAI",$0A
    db "MODE7 ROAD   :KANAME TANAKA",$0A
    db "BACK GROUND  :AKANE HARUKI",$0A
    db "PANEL & FONT :HIROTO YAMAMOTO",$0A
    db "THANK YOU FOR 5(!) GRAPHIC DESIGNERS.",$0A

; ============================================================
; Window tables: the quadrilateral ($C3:0EFA–$C3:10BF)
; ============================================================

; $C3:0EFA — WinFx_BuildQuad (263 bytes, $0EFA–$1000)
; Writes a window table (2 bytes per line: left edge, right edge) for
; the four-sided shape through WinFx_QuadPoints (X, Y bytes of points
; 0-3, in order) at WinFx_QuadTablePtr in bank WinFx_QuadTableBank
; (bit 0: $7E/$7F). It starts from the point with the smallest Y (the
; last one on a tie: CMP/BCC also switches when equal; WinFx_QuadTopY),
; then draws the four edges in
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
; reached by BEQ): X0 goes to row Y0 and X1 to row Y0 + 1 (two INYs:
; the next row, same byte column) when the 8-bit X0 - X1 has bit 7 set,
; else the other way round. That puts the smaller X first only while
; the two are close; quirk (CMP then BMI, a signed test): the larger X
; goes first when X1 - X0 >= $81 or X0 - X1 >= $80.
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
; ASCII "CODE END C3" right after the kernel's last RTL ($C3:10BF,
; WinFx_QuadExit's, where WinFx_QuadEdge and WinFx_BuildQuad end),
; probably left by the build to mark the end of the code. Followed by
; $00 fill up to the packed block at $C3:1200 (not emitted here).
org $C310C0
BankC3_EndMarker:
    db "CODE END C3"

; ============================================================
; The packed module ($C3:1313–$C3:7A2B)
; ============================================================

; $C3:1313 — BankC3_PackedModule (26,393 bytes, $1313–$7A2B)
; The bank $C3 module (65816 code and its data, the jet-bike race
; program), packed in Decomp_ToWram's format (12-bit mode), which
; C3_BootModule unpacks to C3Mod_Code ($7E:3000-$7E:B57E, $857F bytes)
; and jumps to. Pointed to by C3Rom_PackPtrs entry 1 ($FE:0003). Its
; source is the unpacked module, asm/bankC3/packed/module.asm, which
; tools/c3pack.py assembles and packs with the original packer's rules
; (Okumura's LZSS, its docstring has the details) to
; build/c3pack/module.lz, the exact bytes in ROM. $C3:1200-$C3:1312
; before it is another pack (C3Rom_PackPtrs entry 0; $400 bytes
; unpacked; user not traced), kept as ROM bytes.
org $C31313
BankC3_PackedModule:
    incbin "../../build/c3pack/module.lz"
