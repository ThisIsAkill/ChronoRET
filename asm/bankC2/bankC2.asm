; ============================================================
; Bank $C2 — (mostly unmatched)
; File offset 0x020000 (bank $C2 = ROM offset $20000)
;
; The menu/scene bank. Other banks enter it only through fixed vectors:
;   $C2:0000-$000E  BankC2_Entry0000 and four more JMPs: the scene mode
;                   (JML from GameLoop_Main for Loc_Id $01F0-$81EF) and
;                   the text-window calls TextWin_Init / TextWin_Step
;   $C2:8000-$8005  BankC2_Entry8000/8002/8004: three BRAs to the menu
;                   entry, the pad reader and the command dispatcher
; Both modes run with DP=$0000 and give the direct page and low WRAM a
; layout of their own: names in include/ram_menu.inc and
; include/constants_menu.inc (prefixes Menu, C2Scene, TextWin); a few
; shared engine names (pad bytes, OAM shadow, trampolines) come from
; ram_engine.inc.
; ============================================================

arch snes.cpu
hirom

incsrc "../hardware.inc"

; ============================================================
; Entry vectors and scene-mode boot ($C2:0000–$C2:0042)
; ============================================================

; $C2:0000 — BankC2_Entry0000 (15 bytes, $0000–$000E): the bank's entry
; vectors, five JMPs reached from other banks by JML/JSL:
;   $0000 BankC2_Entry0000 → BankC2_SceneBoot (JML from GameLoop_Main
;         for Loc_Id $01F0-$81EF; it never returns)
;   $0003 BankC2_Entry0003 and $0006 BankC2_Entry0006 → TextWin_Init
;   $0009 BankC2_Entry0009 and $000C BankC2_Entry000C → TextWin_Step
; ($0006 and $000C have no callers found; they duplicate the vector
; before them.) TextWin_Init and TextWin_Step end in RTL, so the
; $0003/$0009 vectors are JSL targets.
; Callers: BankC2_Entry0000: JML from GameLoop_Main ($C0:006E).
;   BankC2_Entry0003 (JSL, all unmatched): $C0:2121, $C2:F91F, $C2:F9E4,
;   $C2:FA3F, $C2:FA99 and $CD:0278. BankC2_Entry0009 (JSL, all
;   unmatched): $C0:2172, $C2:F928, $C2:FAB2, $CD:0282 and $CD:04E9.
; Entry/Exit: those of the routine each vector jumps to.
org $C20000
BankC2_Entry0000:
    JMP BankC2_SceneBoot
BankC2_Entry0003:               ; header: see BankC2_Entry0000
    JMP TextWin_Init
BankC2_Entry0006:               ; header: see BankC2_Entry0000
    JMP TextWin_Init
BankC2_Entry0009:               ; header: see BankC2_Entry0000
    JMP TextWin_Step
BankC2_Entry000C:               ; header: see BankC2_Entry0000
    JMP TextWin_Step

; $C2:000F — BankC2_SceneBoot (52 bytes, $000F–$0042)
; Starts the bank's scene mode (inferred name: GameLoop_Main sends Loc_Id
; $01F0-$81EF here; what those locations show is not traced). Interrupts
; off, NMI/auto-joypad, DMA and HDMA off, forced blank at full
; brightness, FastROM; DB=$00, DP=$0000; then the PPU registers
; (BankC2_InitHwRegs), the direct page and its PPU shadows
; (C2Scene_ClearDp), the NMI/IRQ trampolines (C2Scene_InstallInterrupts)
; and two unmatched setup steps, and jumps into C2Scene_Main, which does
; not come back here.
; Callers: JMP from BankC2_Entry0000 ($C2:0000).
; Entry: M=1, X=0 (as GameLoop_Main leaves them; set again here), DP any,
;        DB=$00 (the first stores, to NMITIMEN and on, are absolute;
;        GameLoop_Main's InitHW sets it)
; Exit:  never returns; continues in C2Scene_Main with M=1, X=0, DP=$0000,
;        DB=$00 (as far as the callees leave them)
; Calls: BankC2_InitHwRegs, C2Scene_ClearDp, C2Scene_InstallInterrupts,
;   C2Scene_Unk03EF and C2Scene_Unk1DB5.
BankC2_SceneBoot:
    SEI
    SEP #$20
    REP #$10
    LDA.b #$00
    STA.w NMITIMEN
    STA.w MDMAEN
    STA.w HDMAEN
    LDA.b #FORCED_BLANK|BRIGHTNESS_MASK
    STA.w INIDISP
    LDA.b #!MEMSEL_FastRom
    STA.w MEMSEL
    LDA.b #!Bank00
    PHA
    PLB                         ; DB = $00
    XBA                         ; B = $00
    LDA.b #$00
    TCD                         ; DP = $0000
    JSR BankC2_InitHwRegs
    JSR C2Scene_ClearDp
    JSR C2Scene_InstallInterrupts
    JSR C2Scene_Unk03EF
    JSR C2Scene_Unk1DB5
    JMP C2Scene_Main

; ============================================================
; Hardware setup ($C2:0043–$C2:010F)
; ============================================================

; $C2:0043 — BankC2_InitHwRegs (205 bytes, $0043–$010F)
; Writes the PPU registers from OBSEL to SETINI (all but INIDISP and the
; data ports OAMDATA, VMDATAL/H and CGDATA) and the CPU registers
; WRIO-VTIMEH with fixed values, through DP=$2100 and then DP=$4200 (PEA /
; PLD), the way MainInit ($FD:C000) does at reset, but with this bank's
; own layout: mode 1 with BG3 on top, 16x16/32x32 sprites with tiles at
; $0000, 64x32 maps at $6000 (BG1), $6800 (BG2) and $7800 (BG3 and BG4),
; BG1/BG2 tiles at $2000 and BG3/BG4 at $7000, BG1-3 and OBJ on the main
; screen and BG1, BG2 and OBJ on the sub screen, color math on BG3
; adding the sub screen and halving, fixed color black. Windows, scroll, VRAM and OAM
; addresses are 0 and the Mode 7 matrix is the identity. The scroll
; clears ($C2:0073–$C2:0092) and the CPU register stores from $C2:00FC
; on are the same bytes as MainInit's. INIDISP is not written
; (BankC2_SceneBoot has already set forced blank).
; Callers (2 JSR sites): BankC2_SceneBoot ($C2:0031; it has run SEI,
;   NMI/DMA off, forced blank, DB=$00 and DP=$0000 first) and $C2:2557
;   (unmatched).
; Entry: M=1 (8-bit A: the register values are 8-bit immediates), X=0
;        (16-bit X: the LDX.w #$0000 / STX.b pairs clear two registers
;        at once), DP any (saved and restored), DB any (all stores are
;        direct page)
; Exit:  M=1, X=0, DP restored, DB unchanged; A = 0, X = 0, Y unchanged
; No calls.
org $C20043
BankC2_InitHwRegs:
    PHD
    PEA.w !DP_PPU
    PLD                         ; DP = $2100: two-byte register stores
    LDA.b #!OBSEL_Size16And32_Base0000
    STA.b OBSEL-!DP_PPU
    LDX.w #$0000
    STX.b OAMADDL-!DP_PPU       ; OAMADDL and OAMADDH
    LDA.b #BG_MODE_1|BG3_HIGH_PRIO
    STA.b BGMODE-!DP_PPU
    LDA.b #$00
    STA.b MOSAIC-!DP_PPU
    LDA.b #!BG1SC_6000_64x32
    STA.b BG1SC-!DP_PPU
    LDA.b #!BG2SC_6800_64x32
    STA.b BG2SC-!DP_PPU
    LDA.b #!BG3SC_7800_64x32
    STA.b BG3SC-!DP_PPU
    LDA.b #!BG4SC_7800_64x32
    STA.b BG4SC-!DP_PPU
    LDA.b #!BG12NBA_Both2000
    STA.b BG12NBA-!DP_PPU
    LDA.b #!BG34NBA_Both7000
    STA.b BG34NBA-!DP_PPU
    LDA.b #$00
    ; Scroll registers are write-twice (low byte, then high byte).
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG3HOFS-!DP_PPU
    STA.b BG3HOFS-!DP_PPU
    STA.b BG3VOFS-!DP_PPU
    STA.b BG3VOFS-!DP_PPU
    STA.b BG4HOFS-!DP_PPU
    STA.b BG4HOFS-!DP_PPU
    STA.b BG4VOFS-!DP_PPU
    STA.b BG4VOFS-!DP_PPU
    LDA.b #!VMAIN_IncAfterHigh
    STA.b VMAIN-!DP_PPU
    LDX.w #$0000
    STX.b VMADDL-!DP_PPU        ; VMADDL and VMADDH
    ; Mode 7 matrix to identity: each element is write-twice (low, then
    ; high), so A = D = $0100 (1.0) and B = C = 0, centre (0,0).
    LDA.b #$00
    STA.b M7SEL-!DP_PPU
    STA.b M7A-!DP_PPU
    LDA.b #$01
    STA.b M7A-!DP_PPU
    LDA.b #$00
    STA.b M7B-!DP_PPU
    STA.b M7B-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7D-!DP_PPU
    LDA.b #$01
    STA.b M7D-!DP_PPU
    LDA.b #$00
    STA.b M7X-!DP_PPU
    STA.b M7X-!DP_PPU
    STA.b M7Y-!DP_PPU
    STA.b M7Y-!DP_PPU
    STA.b CGADD-!DP_PPU
    ; Windows off.
    STA.b W12SEL-!DP_PPU
    STA.b W34SEL-!DP_PPU
    STA.b WOBJSEL-!DP_PPU
    STA.b WH0-!DP_PPU
    STA.b WH1-!DP_PPU
    STA.b WH2-!DP_PPU
    STA.b WH3-!DP_PPU
    STA.b WBGLOG-!DP_PPU
    STA.b WOBJLOG-!DP_PPU
    LDA.b #!TM_Bg123Obj
    STA.b TM-!DP_PPU
    LDA.b #!TS_Bg1Bg2Obj
    STA.b TS-!DP_PPU
    LDA.b #$00
    STA.b TMW-!DP_PPU
    STA.b TSW-!DP_PPU
    LDA.b #!CGWSEL_AddSubscreen
    STA.b CGWSEL-!DP_PPU
    LDA.b #!CGADSUB_HalfAddBg3
    STA.b CGADSUB-!DP_PPU
    LDA.b #!COLDATA_AllZero
    STA.b COLDATA-!DP_PPU
    LDA.b #$00
    STA.b SETINI-!DP_PPU
    PEA.w !DP_CPU
    PLD                         ; DP = $4200
    LDA.b #!WRIO_AllHigh
    STA.b WRIO-!DP_CPU
    LDA.b #$00
    STA.b WRMPYA-!DP_CPU
    STA.b WRMPYB-!DP_CPU
    STA.b WRDIVL-!DP_CPU
    STA.b WRDIVH-!DP_CPU
    STA.b WRDIVB-!DP_CPU
    STA.b HTIMEL-!DP_CPU
    STA.b HTIMEH-!DP_CPU
    STA.b VTIMEL-!DP_CPU
    STA.b VTIMEH-!DP_CPU
    PLD
    RTS

; ============================================================
; Scene mode: interrupts and the per-frame upload ($C2:0110–$C2:0453)
; ============================================================

; $C2:0110 — C2Scene_InstallInterrupts (31 bytes, $0110–$012E)
; Writes JML C2Scene_NmiHandler and JML C2Scene_IrqHandler into the WRAM
; trampolines that the native NMI and IRQ stubs in bank $00 jump through,
; as InstallNMI/InstallIRQ ($C0:0B64/$0B75) do for the field engine.
; Callers (2 JSR sites): BankC2_SceneBoot ($C2:0037) and $C2:255A
;   (unmatched).
; Entry: M=1 (8-bit A), X=0 (16-bit X), DP any (not used), DB a bank
;        that maps low WRAM (absolute stores to $0500-$0507;
;        BankC2_SceneBoot has DB=$00)
; Exit:  M=1, X=0; A = bank(C2Scene_IrqHandler), X = its address; Y, DP
;        and DB unchanged
; No calls.
C2Scene_InstallInterrupts:
    LDA.b #!Op_JML
    STA.w !NmiTrampoline
    STA.w !IrqTrampoline
    LDX.w #C2Scene_NmiHandler
    STX.w !NmiTrampoline+1
    LDX.w #C2Scene_IrqHandler
    STX.w !IrqTrampoline+1
    LDA.b #bank(C2Scene_NmiHandler)
    STA.w !NmiTrampoline+3
    LDA.b #bank(C2Scene_IrqHandler)
    STA.w !IrqTrampoline+3
    RTS

; $C2:012F — C2Scene_ClearDp (47 bytes, $012F–$015D)
; Zeroes the direct page $00-$EF (an STZ of the first word, then an
; overlapping MVN), then sets the PPU shadows that C2Scene_NmiHandler
; copies out to their starting values: forced blank, mode 1 with BG3 on
; top, the Mode 7 matrix A = D = 1.0, WH0 = WH2 = 1, BG1-3 and OBJ on the
; main screen, BG1, BG2 and OBJ on the sub screen (the same layer setup
; as BankC2_InitHwRegs). Everything else, C2Scene_NmiFlags included,
; starts at 0.
; Callers (1 JSR site): BankC2_SceneBoot ($C2:0034).
; Entry: M=1 (8-bit A; REP/SEP around the clear), X=0 (16-bit X and Y),
;        DP=$0000 (the shadows are direct page), DB any (saved; the MVN
;        sets it to $00)
; Exit:  M=1, X=0, DB restored; A = TS_Bg1Bg2Obj, X = $00EF, Y = $00F0
; No calls.
C2Scene_ClearDp:
    PHB
    REP #$20
    STZ.b !C2Scene_DpClearStart
    LDX.w #!C2Scene_DpClearStart
    LDY.w #!C2Scene_DpClearStart+1
    LDA.w #!C2Scene_DpClearCount
    MVN !Bank00,!Bank00         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    SEP #$20
    PLB
    LDA.b #FORCED_BLANK
    STA.b !C2Scene_InidispShadow
    LDA.b #!C2Scene_InitBgMode
    STA.b !C2Scene_BgModeShadow
    LDA.b #$01
    STA.b !C2Scene_M7A+1        ; high byte: 1.0
    STA.b !C2Scene_M7D+1
    INC.b !C2Scene_WH0Shadow
    INC.b !C2Scene_WH2Shadow
    LDA.b #!TM_Bg123Obj
    STA.b !C2Scene_TmShadow
    LDA.b #!TS_Bg1Bg2Obj
    STA.b !C2Scene_TsShadow
    RTS

; $C2:015E — C2Scene_NmiHandler (487 bytes, $015E–$0344)
; The scene mode's NMI (reached through !NmiTrampoline, installed by
; C2Scene_InstallInterrupts). Always: acknowledge the NMI (read RDNMI)
; and count the frame (C2Scene_FrameCounter). Only when
; C2Scene_NmiFlags bit 0 is set: forced blank and HDMA off; OAM from
; Oam_LowTable ($0700, $220 B, both tables); the 512 B palette
; C2Scene_PaletteBuf when bit 1 is set; clear the flags; copy every PPU
; shadow on the direct page to its register (BGMODE to TSW, color math
; and the fixed color); copy C2Scene_HdmaValues and C2Scene_HdmaValueA916
; into their tables; flush the VRAM queue (C2Scene_VramQFlush); read the
; joypad (BankC2_Entry8002, the menu's pad reader); restore INIDISP from
; its shadow and brightness and HDMAEN from its shadow; four unmatched
; per-frame steps; and set bit 0 again.
; Callers: none (an interrupt handler, entered through the trampoline).
; Entry: an NMI in native mode, any M/X/DP/DB (A, X, Y saved 16-bit, DP
;        and DB saved; then M=0/1 as needed, X=0, DP=$0000, DB=$00)
; Exit:  RTI with A, X, Y, DP, DB and P as they were
; Calls: C2Scene_VramQFlush, BankC2_Entry8002 (JSL), C2Scene_Unk0C4D,
;   C2Scene_Unk034D, C2Scene_Unk051D and C2Scene_Unk0CEA.
C2Scene_NmiHandler:
    REP #$30
    PHA
    PHX
    PHY
    PHD
    PHB
    LDA.w #$0000
    TCD                         ; DP = $0000
    SEP #$20
    PHA
    PLB                         ; DB = $00
    LDA.w RDNMI                 ; acknowledge the NMI
    INC.b !C2Scene_FrameCounter
    LDA.b !C2Scene_NmiFlags
    BIT.b #!C2Scene_NmiUpdate
    BNE .update
    JMP .exit
.update:
    LDA.b #FORCED_BLANK
    STA.w INIDISP
    TDC                         ; A = 0
    STA.w HDMAEN
    LDX.w #$0000
    STX.w OAMADDL               ; OAMADDL and OAMADDH
    STZ.w DMAP0
    LDA.b #!BBAD_OAMDATA
    STA.w BBAD0
    LDX.w #!Oam_LowTable
    STX.w A1T0L
    STZ.w A1B0
    LDX.w #!C2Scene_OamBytes
    STX.w DAS0L
    LDA.b #DMA_CH0
    STA.w MDMAEN
    LDA.b !C2Scene_NmiFlags
    BIT.b #!C2Scene_NmiPalette
    BEQ .no_palette
    TDC                         ; A = 0
    STA.w CGADD
    STA.w DMAP0
    LDA.b #!BBAD_CGDATA
    STA.w BBAD0
    LDX.w #!C2Scene_PaletteBuf
    STX.w A1T0L
    STZ.w A1B0
    LDX.w #!C2Scene_PaletteBytes
    STX.w DAS0L
    LDA.b #DMA_CH0
    STA.w MDMAEN
.no_palette:
    STZ.b !C2Scene_NmiFlags
    LDA.b !C2Scene_BgModeShadow
    STA.w BGMODE
    LDA.b !C2Scene_MosaicShadow
    STA.w MOSAIC
    ; Scroll and Mode 7 registers are write-twice: low byte, then high.
    LDA.b !C2Scene_Bg1HScroll
    STA.w BG1HOFS
    LDA.b !C2Scene_Bg1HScroll+1
    STA.w BG1HOFS
    LDA.b !C2Scene_Bg1VScroll
    STA.w BG1VOFS
    LDA.b !C2Scene_Bg1VScroll+1
    STA.w BG1VOFS
    LDA.b !C2Scene_Bg2HScroll
    STA.w BG2HOFS
    LDA.b !C2Scene_Bg2HScroll+1
    STA.w BG2HOFS
    LDA.b !C2Scene_Bg2VScroll
    STA.w BG2VOFS
    LDA.b !C2Scene_Bg2VScroll+1
    STA.w BG2VOFS
    LDA.b !C2Scene_Bg3HScroll
    STA.w BG3HOFS
    LDA.b !C2Scene_Bg3HScroll+1
    STA.w BG3HOFS
    LDA.b !C2Scene_Bg3VScroll
    STA.w BG3VOFS
    LDA.b !C2Scene_Bg3VScroll+1
    STA.w BG3VOFS
    LDA.b !C2Scene_M7A
    STA.w M7A
    LDA.b !C2Scene_M7A+1
    STA.w M7A
    LDA.b !C2Scene_M7B
    STA.w M7B
    LDA.b !C2Scene_M7B+1
    STA.w M7B
    LDA.b !C2Scene_M7C
    STA.w M7C
    LDA.b !C2Scene_M7C+1
    STA.w M7C
    LDA.b !C2Scene_M7D
    STA.w M7D
    LDA.b !C2Scene_M7D+1
    STA.w M7D
    LDA.b !C2Scene_M7X
    STA.w M7X
    LDA.b !C2Scene_M7X+1
    STA.w M7X
    LDA.b !C2Scene_M7Y
    STA.w M7Y
    LDA.b !C2Scene_M7Y+1
    STA.w M7Y
    LDA.b !C2Scene_W12SelShadow
    STA.w W12SEL
    LDA.b !C2Scene_W34SelShadow
    STA.w W34SEL
    LDA.b !C2Scene_WObjSelShadow
    STA.w WOBJSEL
    LDA.b !C2Scene_WH0Shadow
    STA.w WH0
    LDA.b !C2Scene_WH1Shadow
    STA.w WH1
    LDA.b !C2Scene_WH2Shadow
    STA.w WH2
    LDA.b !C2Scene_WH3Shadow
    STA.w WH3
    LDA.b !C2Scene_WBgLogShadow
    STA.w WBGLOG
    LDA.b !C2Scene_WObjLogShadow
    STA.w WOBJLOG
    LDA.b !C2Scene_TmShadow
    STA.w TM
    LDA.b !C2Scene_TsShadow
    STA.w TS
    LDA.b !C2Scene_TmwShadow
    STA.w TMW
    LDA.b !C2Scene_TswShadow
    STA.w TSW
    LDA.b !C2Scene_CgwselShadow
    STA.w CGWSEL
    LDA.b !C2Scene_CgadsubShadow
    STA.w CGADSUB
    LDA.b !C2Scene_FixedBlue
    ORA.b #!COLDATA_Blue
    STA.w COLDATA
    LDA.b !C2Scene_FixedGreen
    ORA.b #!COLDATA_Green
    STA.w COLDATA
    LDA.b !C2Scene_FixedRed
    ORA.b #!COLDATA_Red
    STA.w COLDATA
    REP #$20
    LDA.l !C2Scene_HdmaValues
    STA.l C2Scene_HdmaTable[0].Value0
    LDA.l !C2Scene_HdmaValues+2
    STA.l C2Scene_HdmaTable[0].Value1
    LDA.l !C2Scene_HdmaValues+4
    STA.l C2Scene_HdmaTable[1].Value0
    LDA.l !C2Scene_HdmaValues+6
    STA.l C2Scene_HdmaTable[1].Value1
    LDA.l !C2Scene_HdmaValues+8
    STA.l C2Scene_HdmaTable[2].Value0
    LDA.l !C2Scene_HdmaValues+10
    STA.l C2Scene_HdmaTable[2].Value1
    LDA.l !C2Scene_HdmaValues+12
    STA.l C2Scene_HdmaTable[3].Value0
    LDA.l !C2Scene_HdmaValues+14
    STA.l C2Scene_HdmaTable[3].Value1
    LDA.l !C2Scene_HdmaValues+16
    STA.l C2Scene_HdmaTable[4].Value0
    LDA.l !C2Scene_HdmaValues+18
    STA.l C2Scene_HdmaTable[4].Value1
    LDA.l !C2Scene_HdmaValueA916
    STA.l !C2Scene_HdmaTableA918+1
    STA.l !C2Scene_HdmaTableA918+4
    STA.l !C2Scene_HdmaTableA918+7
    STA.l !C2Scene_HdmaTableA918+10
    SEP #$20
    JSR C2Scene_VramQFlush
    JSL BankC2_Entry8002
    LDA.b !C2Scene_InidispShadow
    ORA.b !C2Scene_Brightness
    STA.w INIDISP
    LDA.b !C2Scene_HdmaenShadow
    STA.w HDMAEN
    JSR C2Scene_Unk0C4D
    STZ.b !C2Scene_Unk4D
    JSR C2Scene_Unk034D
    JSR C2Scene_Unk051D
    JSR C2Scene_Unk0CEA
    LDA.b #!C2Scene_NmiUpdate
    TSB.b !C2Scene_NmiFlags
.exit:
    REP #$20
    PLB
    PLD
    PLY
    PLX
    PLA
    RTI

; $C2:0345 — C2Scene_IrqHandler (1 byte): the scene mode's IRQ, an RTI
; (installed by C2Scene_InstallInterrupts; nothing here enables IRQs).
; Entry: an IRQ, any state
; Exit:  RTI, nothing changed
C2Scene_IrqHandler:
    RTI

; $C2:0346 — C2Scene_WaitFrame (7 bytes, $0346–$034C)
; Waits until the next NMI: spins until C2Scene_FrameCounter changes.
; Callers (2 sites, unmatched): JSR at $C2:0455 and JMP at $C2:046E.
; Entry: M=1 (8-bit compare), X any, DP=$0000, DB any; NMI enabled
; Exit:  M=1; A = the counter before the change; X, Y unchanged
; No calls.
C2Scene_WaitFrame:
    LDA.b !C2Scene_FrameCounter
.wait:
    CMP.b !C2Scene_FrameCounter
    BEQ .wait
    RTS

; $C2:0405 — C2Scene_VramQFlush (79 bytes, $0405–$0453)
; Runs the queued VRAM uploads: for each 8-byte C2Scene_VramQ entry up to
; C2Scene_VramQEnd, one DMA on channel 0 (word writes to VMDATAL/H) from
; .Bank:.Src, .Size bytes, to VRAM word .Dest with VMAIN = .Vmain. Then
; empties the queue and points C2Scene_VramQBufPtr back at
; C2Scene_VramQBuf ($7E:F000). Does nothing while C2Scene_VramQLock is
; set or the queue is empty.
; The value 1 written to DMAP0 (DMAP_TwoRegs) is also what starts the
; transfer: the same A goes to MDMAEN (channel 0).
; Callers (1 JSR site): C2Scene_NmiHandler ($C2:0318).
; Entry: M=1 (8-bit A), X=0, DP=$0000 (queue on the direct page), DB=$00
;        (absolute DMA and PPU registers)
; Exit:  M=1, X=0 (SEP #$10 for the loop, REP #$10 after); after a flush
;        A = bank(C2Scene_VramQBuf) and X = its address; Y, DP and DB
;        unchanged
; No calls.
org $C20405
C2Scene_VramQFlush:
    LDA.b !C2Scene_VramQLock
    BEQ .unlocked
    RTS
.unlocked:
    LDA.b !C2Scene_VramQEnd
    BNE .flush
    RTS
.flush:
    SEP #$10
    LDX.b #$00
.loop:
    REP #$20
    LDA.b C2Scene_VramQ.Src,X
    STA.w A1T0L
    LDA.b C2Scene_VramQ.Dest,X
    STA.w VMADDL
    LDA.b C2Scene_VramQ.Size,X
    STA.w DAS0L
    SEP #$20
    LDA.b C2Scene_VramQ.Bank,X
    STA.w A1B0
    LDA.b C2Scene_VramQ.Vmain,X
    STA.w VMAIN
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD0
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP0
    STA.w MDMAEN                ; 1 = DMA_CH0 as well
    TXA
    CLC
    ADC.b #!C2Scene_VramQEntrySize
    TAX
    CPX.b !C2Scene_VramQEnd
    BNE .loop
    STZ.b !C2Scene_VramQEnd
    REP #$10
    LDX.w #!C2Scene_VramQBuf
    STX.b !C2Scene_VramQBufPtr
    LDA.b #bank(!C2Scene_VramQBuf)
    STA.b !C2Scene_VramQBufPtr+2
    RTS

; ============================================================
; Trigonometry ($C2:225A–$C2:2272)
; ============================================================

; $C2:225A — Trig_Cos1024 (25 bytes with Trig_Sin1024, $225A–$2272)
; Signed sine or cosine of a 16-bit angle with 1024 steps per turn,
; read from !Rom_SineTable: A = sin(angle) × 255 (−255..+255; the table
; holds |sin| as one byte per step, negated for the second half turn).
; Trig_Cos1024 adds a quarter turn and falls into the sub-entry
; Trig_Sin1024 ($C2:225E).
; Trig_Sin1024 is a long-call copy of Battle_SinLookup ($C1:01F9) from
; its AND on, minus the scale multiply: the same index mask, the same
; table and the same negate, but the angle is used as given (no × 4) and
; the signed value is returned in A instead of being multiplied.
; Callers (JSL): Trig_Cos1024 from $C2:6752, $C2:6D10, $C2:704F,
;   $C2:711D and $C6:E9FF; Trig_Sin1024 from $C2:673B, $C2:6D17,
;   $C2:7062, $C2:712D, $C2:76CB, $C2:77D9, $C2:7D33, $C2:7DB9 and
;   $C6:EA17 (all unmatched; e.g. $C2:6D10/6D17 take the cosine and the
;   sine of the same angle).
; Entry (both): M=0 (16-bit A, set by the caller; the immediates carry
;        an explicit .w), X=0 (16-bit: TAX / CPX.w take the whole index),
;        DP any (no direct page), DB any (table read with .l); A = angle
;        (only bits 0-9 count)
; Exit (both):  M=0, X=0; A = signed sine; X = table index (angle, plus
;        $100 for the cosine, AND $3FF); Y, DP and DB unchanged
; No calls.
org $C2225A
Trig_Cos1024:
    CLC
    ADC.w #!Trig_QuarterTurn    ; cos(a) = sin(a + 90 degrees)
Trig_Sin1024:                   ; header: see Trig_Cos1024
    AND.w #!Trig_IndexMask
    TAX                         ; X = table byte index
    LDA.l !Rom_SineTable,X
    AND.w #!Eng_LowByteMask     ; keep this entry (the 16-bit read also took the next)
    CPX.w #!Trig_HalfTable      ; second half turn → negative
    BCC .done
    EOR.w #!Eng_Invert16
    INC A                       ; two's complement negate (EOR + INC)
.done:
    RTL

; ============================================================
; Menu setup: PPU and RAM init, DMA fill/copy helpers, new-game
; data ($C2:940D–$C2:960A)
; ============================================================

; $C2:940D — Menu_InitPpuAndRam (259 bytes, $940D–$950F)
; Puts the PPU and CPU registers into the menu's starting state, then
; clears all of VRAM and most of bank $7E with DMA. Through DP=$2100:
; forced blank; 8x8/16x16 sprites with tiles at $4000; mode 1 with BG3 on
; top; 32x64 maps at $5800 (BG1), $6000 (BG2) and $6800 (BG3), BG4 map
; and BG1/BG2/BG4 tiles at 0, BG3 tiles at $7000; scroll, mosaic,
; windows, layer enables (TM/TS = 0: every layer off), color math and
; SETINI all 0, the fixed color black, VRAM address 0 stepping after the
; high byte, the Mode 7 matrix the identity. The scroll clears from
; $C2:9445 on are the same bytes as MainInit's ($FD:C060). Through
; DP=$4200: NMI, IRQ, auto-joypad, DMA and HDMA off, H/V timers 0,
; FastROM on.
; Then, with DMA channel 0 and the zero word Menu_DmaZeroWord as a fixed
; source: VRAM bytes $0000-$FFFE (Menu_VramClearBytes: the last byte is
; left), and through Menu_DmaClearWram the WRAM blocks $7E:0C00-$1DFF,
; $7E:2E00-$FFFF and $7E:0000-$00FF. Left alone: $0100-$0BFF (the field
; direct page, the stack up to $09FF, BankC2_MenuEntry's saved stack
; pointer at $0920 and its arguments at $0A00) and $1E00-$2DFF (the
; audio command block at $1E00 and, from $2600 on, Menu_CharRecords,
; Menu_PartyOrder and Menu_Config).
; Quirk: X=0 is also stored to $4216-$4219 (RDMPYL/H and JOY1L/H), which
; are read-only; the stores do nothing.
; Callers (1 JSR site, unmatched): $C2:80F0 in Menu_InitSystems.
; Entry: M any, X any (P saved; sets M=1, X=0 itself), DP any and DB any
;        (both saved, then DP=$2100/$4200 and DB=$00)
; Exit:  P, DP and DB restored; A, X and Y clobbered (X = Menu_DmaZeroWord,
;        Y = Menu_ClearDpSize, from the last Menu_DmaClearWram)
; Calls: Menu_DmaClearWram (3 times).
org $C2940D
Menu_InitPpuAndRam:
    PHB
    PHD
    PHP
    REP #$10
    SEP #$20
    PEA.w !Bank00<<8|!Bank00
    PLB
    PLB                         ; DB = $00: the DMA registers below are absolute
    PEA.w !DP_PPU
    PLD                         ; DP = $2100
    LDA.b #FORCED_BLANK
    STA.b INIDISP-!DP_PPU
    LDA.b #!OBSEL_Size8And16_Base4000
    STA.b OBSEL-!DP_PPU
    LDA.b #BG_MODE_1|BG3_HIGH_PRIO
    STA.b BGMODE-!DP_PPU
    LDA.b #!BG1SC_5800_32x64
    STA.b BG1SC-!DP_PPU
    LDA.b #!BG2SC_6000_32x64
    STA.b BG2SC-!DP_PPU
    LDA.b #!BG3SC_6800_32x64
    STA.b BG3SC-!DP_PPU
    LDA.b #$00
    STA.b BG4SC-!DP_PPU
    LDA.b #$00
    STA.b BG12NBA-!DP_PPU
    LDA.b #!BG34NBA_Bg3At7000
    STA.b BG34NBA-!DP_PPU
    LDA.b #$00
    STA.b MOSAIC-!DP_PPU
    ; Scroll registers are write-twice (low byte, then high byte).
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG3HOFS-!DP_PPU
    STA.b BG3HOFS-!DP_PPU
    STA.b BG3VOFS-!DP_PPU
    STA.b BG3VOFS-!DP_PPU
    STA.b BG4HOFS-!DP_PPU
    STA.b BG4HOFS-!DP_PPU
    STA.b BG4VOFS-!DP_PPU
    STA.b BG4VOFS-!DP_PPU
    LDA.b #!VMAIN_IncAfterHigh
    STA.b VMAIN-!DP_PPU
    LDX.w #$0000
    STX.b VMADDL-!DP_PPU        ; VMADDL and VMADDH
    ; Mode 7 matrix to identity: A = D = $0100 (1.0), B = C = 0, centre
    ; (0,0); each element is write-twice.
    LDA.b #$00
    STA.b M7SEL-!DP_PPU
    STA.b M7A-!DP_PPU
    LDA.b #$01
    STA.b M7A-!DP_PPU
    LDA.b #$00
    STA.b M7B-!DP_PPU
    STA.b M7B-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7D-!DP_PPU
    LDA.b #$01
    STA.b M7D-!DP_PPU
    LDA.b #$00
    STA.b M7X-!DP_PPU
    STA.b M7X-!DP_PPU
    STA.b M7Y-!DP_PPU
    STA.b M7Y-!DP_PPU
    STA.b CGADD-!DP_PPU
    ; Windows, layer enables and color math off.
    STA.b W12SEL-!DP_PPU
    STA.b W34SEL-!DP_PPU
    STA.b WOBJSEL-!DP_PPU
    STA.b WH0-!DP_PPU
    STA.b WH1-!DP_PPU
    STA.b WH2-!DP_PPU
    STA.b WH3-!DP_PPU
    STA.b WBGLOG-!DP_PPU
    STA.b WOBJLOG-!DP_PPU
    STA.b TM-!DP_PPU
    STA.b TS-!DP_PPU
    STA.b TMW-!DP_PPU
    STA.b TSW-!DP_PPU
    STA.b CGWSEL-!DP_PPU
    STA.b CGADSUB-!DP_PPU
    STA.b SETINI-!DP_PPU
    LDA.b #!COLDATA_AllZero
    STA.b COLDATA-!DP_PPU
    PEA.w !DP_CPU
    PLD                         ; DP = $4200
    LDX.w #$0000
    TXA
    STA.b NMITIMEN-!DP_CPU
    STX.b HTIMEL-!DP_CPU        ; HTIMEL and HTIMEH
    STX.b VTIMEL-!DP_CPU        ; VTIMEL and VTIMEH
    STA.b MDMAEN-!DP_CPU
    STA.b HDMAEN-!DP_CPU
    LDA.b #!MEMSEL_FastRom
    STA.b MEMSEL-!DP_CPU
    LDX.w #$0000
    STX.b RDMPYL-!DP_CPU        ; read-only registers: no effect (see header)
    STX.b JOY1L-!DP_CPU
    ; VRAM clear: DMA channel 0, fixed source, word writes to VMDATAL/H.
    LDX.w #(!BBAD_VMDATAL<<8)|!DMAP_FixedSource|!DMAP_TwoRegs
    STX.w DMAP0                 ; DMAP0 and BBAD0
    LDX.w #!Menu_VramClearBytes
    STX.w DAS0L
    LDX.w #Menu_DmaZeroWord
    STX.w A1T0L
    LDA.b #bank(Menu_DmaZeroWord)
    STA.w A1B0
    LDA.b #DMA_CH0
    STA.w MDMAEN
    LDX.w #!Menu_ClearMidStart
    LDY.w #!Menu_ClearMidSize
    JSR Menu_DmaClearWram
    LDX.w #!Menu_ClearHighStart
    LDY.w #!Menu_ClearHighSize
    JSR Menu_DmaClearWram
    LDX.w #$0000
    LDY.w #!Menu_ClearDpSize
    JSR Menu_DmaClearWram
    PLP
    PLD
    PLB
    RTS

; $C2:9510 — Menu_DmaZeroWord (2 bytes): the fixed DMA source of
; Menu_InitPpuAndRam's VRAM clear and of Menu_DmaClearWram.
Menu_DmaZeroWord:
    dw $0000

; $C2:9512 — Menu_DmaClearWram (48 bytes, $9512–$9541)
; Zeroes Y bytes of bank $7E from address X with DMA channel 0 (fixed
; source Menu_DmaZeroWord, one register: WMDATA). HDMA is switched off
; first; WMADDH is set to 0, so the block is always in bank $7E.
; Callers (5 JSR sites): Menu_InitPpuAndRam ($C2:94F7, $C2:9500,
;   $C2:9509), and $C2:97A1 and $C2:981F (unmatched).
; Entry: M any (P saved; sets M=1), X=0 (16-bit X and Y), DP any (not
;        used), DB any (saved, then $00); X = WRAM address, Y = byte count
;        (0 = 64 KiB)
; Exit:  P and DB restored; X = Menu_DmaZeroWord, low byte of A = DMA_CH0;
;        Y, DP unchanged
; No calls.
Menu_DmaClearWram:
    PHB
    PHP
    SEP #$20
    PEA.w !Bank00<<8|!Bank00
    PLB
    PLB                         ; DB = $00
    STZ.w HDMAEN
    STX.w WMADDL                ; WMADDL and WMADDM
    LDA.b #$00
    STA.w WMADDH
    STY.w DAS0L
    LDX.w #(!BBAD_WMDATA<<8)|!DMAP_FixedSource
    STX.w DMAP0                 ; DMAP0 and BBAD0
    LDX.w #Menu_DmaZeroWord
    STX.w A1T0L
    LDA.b #bank(Menu_DmaZeroWord)
    STA.w A1B0
    LDA.b #DMA_CH0
    STA.w MDMAEN
    PLP
    PLB
    RTS

; $C2:9542 — Menu_DmaCopyFFToWram (44 bytes, $9542–$956D)
; Copies Y bytes from bank $FF (MenuRom_DmaCopyBank), address A, to bank
; $7E at address X with DMA channel 0 (stepping source, one register:
; WMDATA). Unlike Menu_DmaClearWram it leaves HDMAEN alone.
; Callers (2 JSR sites, unmatched): $C2:9698 and $C2:96A4.
; Entry: M any, X any (P saved; sets M=0, X=0, then M=1), DP any (not
;        used), DB any (saved, then $00); A (16-bit) = source address in
;        bank $FF, X = WRAM address, Y = byte count
; Exit:  P and DB restored; low byte of A = DMA_CH0; X = $8000
;        (BBAD_WMDATA<<8, the DMAP0/BBAD0 value); Y unchanged
; No calls.
Menu_DmaCopyFFToWram:
    PHB
    PHP
    REP #$30
    PEA.w !Bank00<<8|!Bank00
    PLB
    PLB                         ; DB = $00
    STA.w A1T0L
    STX.w WMADDL                ; WMADDL and WMADDM
    STY.w DAS0L
    LDX.w #!BBAD_WMDATA<<8
    STX.w DMAP0                 ; DMAP0 = 0 (A to B, stepping), BBAD0 = WMDATA
    SEP #$20
    LDA.b #$00
    STA.w WMADDH
    LDA.b #!MenuRom_DmaCopyBank
    STA.w A1B0
    LDA.b #DMA_CH0
    STA.w MDMAEN
    PLP
    PLB
    RTS

; $C2:956E — Menu_InitNewGameData (77 bytes, $956E–$95BA)
; Sets up the data of a new game (inferred from what it fills). The call
; at $C2:8048 runs only while Menu_DataInitDone is 0 in mode 0; the
; other two are not guarded by that flag: $C2:8D7E runs it when none of
; three JSL $FF:F9C4 slot checks returns 0, then clears the flag, and
; $C2:E65D runs it and then sets the flag to 1. It: runs
; Menu_ClearConfigAndFlags, zeroes Menu_Unk2400 ($2400-$25FF), copies the
; $280 B of MenuRom_CharRecordInit ($CC:0000) to Menu_CharRecords
; ($2600), zeroes $2C53-$2C55, marks all 9 Menu_PartyOrder entries empty
; ($80), sets Menu_Unk29AF to $0080 and zeroes $2C7C-$2C99.
; Each zero or $80 fill stores the first word, then an overlapping MVN
; (source = destination - 2, or - 1 for the party list) copies it on.
; Callers (3 JSR sites, unmatched): $C2:8048 in BankC2_MenuEntry, $C2:8D7E
;   and $C2:E65D.
; Entry: M any, X any (P saved; sets M=0, X=0), DP any (not used), DB=$7E
;        (absolute stores; the MVNs also leave DB=$7E)
; Exit:  P restored; DB=$7E; A = $FFFF, X and Y past the last MVN
; Calls: Menu_ClearConfigAndFlags.
Menu_InitNewGameData:
    PHP
    REP #$30
    JSR Menu_ClearConfigAndFlags
    STZ.w !Menu_Unk2400
    LDX.w #!Menu_Unk2400
    LDY.w #!Menu_Unk2400+2
    LDA.w #!Menu_Unk2400Size-3  ; MVN count - 1: the rest after the first word
    MVN !Bank7E,!Bank7E         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!MenuRom_CharRecordInit
    LDY.w #!Menu_CharRecords
    LDA.w #!Menu_CharRecordInitSize-1
    MVN !Bank7E,bank(!MenuRom_CharRecordInit) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    STZ.w !Menu_Unk2C53
    STZ.w !Menu_Unk2C53+1
    LDA.w #!Menu_PartyEmpty
    STA.w !Menu_PartyOrder      ; $80, then $00 (overwritten by the MVN)
    STA.w !Menu_Unk29AF
    LDX.w #!Menu_PartyOrder
    LDY.w #!Menu_PartyOrder+1
    LDA.w #!Menu_PartyOrderSize-2 ; MVN count - 1: entries 1-8
    MVN !Bank7E,!Bank7E         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    STZ.w !Menu_Unk2C7C
    LDX.w #!Menu_Unk2C7C
    LDY.w #!Menu_Unk2C7C+2
    LDA.w #!Menu_Unk2C7CSize-3
    MVN !Bank7E,!Bank7E         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLP
    RTS

; $C2:95BB — Menu_ClearConfigAndFlags (80 bytes, $95BB–$960A)
; Zeroes Menu_FlagBlock7F ($7F:0000-$01FF), the page $7E:0400-$04FF
; (Menu_PlayTime and what follows) and Menu_Config ($2990-$29AF), then
; copies MenuRom_DefaultConfig (12 B) to Menu_Config and the 9 B from
; MenuRom_DefaultButtonMap to Menu_Unk0408. The two sources overlap:
; MenuRom_DefaultButtonMap is MenuRom_DefaultConfig+3, so Menu_Unk0408
; gets the same default button map as Menu_ButtonMap ($2993-$299B).
; Fills as in Menu_InitNewGameData (first word, then an overlapping MVN).
; PHB/PLB keep DB across the bank-$7F fill only; the later MVNs leave
; DB=$7E.
; Callers (2 JSR sites, unmatched): $C2:8D85 and $C2:9571 in
;   Menu_InitNewGameData.
; Entry: M any, X any (P saved; sets M=0, X=0), DP any (not used), DB=$7E
;        (STZ Menu_PlayTime is absolute, after the PLB)
; Exit:  P restored; DB=$7E; A = $FFFF, X and Y past the last MVN
; No calls.
Menu_ClearConfigAndFlags:
    PHP
    REP #$30
    PHB
    LDA.w #$0000
    STA.l !Menu_FlagBlock7F
    LDX.w #!Menu_FlagBlock7F
    LDY.w #!Menu_FlagBlock7F+2
    LDA.w #!Menu_FlagBlock7FSize-3
    MVN !Bank7F,!Bank7F         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    STZ.w !Menu_PlayTime
    LDX.w #!Menu_PlayTime
    LDY.w #!Menu_PlayTime+2
    LDA.w #!Menu_Page04Size-3
    MVN !Bank7E,!Bank7E         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    STZ.w !Menu_Config
    LDX.w #!Menu_Config
    LDY.w #!Menu_Config+2
    LDA.w #!Menu_ConfigSize-3
    MVN !Bank7E,!Bank7E         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!MenuRom_DefaultConfig
    LDY.w #!Menu_Config
    LDA.w #!Menu_DefaultConfigSize-1
    MVN !Bank7E,bank(!MenuRom_DefaultConfig) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!MenuRom_DefaultButtonMap
    LDY.w #!Menu_Unk0408
    LDA.w #!Menu_Unk0408Size-1
    MVN !Bank7E,bank(!MenuRom_DefaultButtonMap) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLP
    RTS
