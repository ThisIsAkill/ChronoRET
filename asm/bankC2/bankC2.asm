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
; Callers (1 JML site): GameLoop_Main ($C0:006E).
; Callers of BankC2_Entry0003 (6 JSL sites): unmatched ($C0:2121, $C2:F91F, $C2:F9E4, $C2:FA3F,
;   $C2:FA99, $CD:0278).
; Callers of BankC2_Entry0009 (5 JSL sites): unmatched ($C0:2172, $C2:F928, $C2:FAB2, $CD:0282,
;   $CD:04E9).
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
; (C2Scene_ClearDp), the NMI/IRQ trampolines (C2Scene_InstallInterrupts),
; an empty VRAM queue (C2Scene_VramQInit) and a black palette
; (C2Scene_ClearPalette), and jumps into C2Scene_Main, which does not
; come back here.
; Callers (1 JMP site): BankC2_Entry0000 ($C2:0000).
; Entry: M=1, X=0 (as GameLoop_Main leaves them; set again here), DP any,
;        DB=$00 (the first stores, to NMITIMEN and on, are absolute;
;        GameLoop_Main's InitHW sets it)
; Exit:  never returns; continues in C2Scene_Main with M=1, X=0, DP=$0000,
;        DB=$00 (as far as the callees leave them)
; Calls: BankC2_InitHwRegs, C2Scene_ClearDp, C2Scene_InstallInterrupts,
;   C2Scene_VramQInit and C2Scene_ClearPalette.
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
    JSR C2Scene_VramQInit
    JSR C2Scene_ClearPalette
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
; Callers (2 JSR sites): BankC2_SceneBoot ($C2:0031) and C2Scene_Mode5 ($C2:2557).
; Callers note (2 JSR sites): BankC2_SceneBoot ($C2:0031; it has run SEI,
;   NMI/DMA off, forced blank, DB=$00 and DP=$0000 first) and
;   C2Scene_Mode5 ($C2:2557).
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
; Callers (2 JSR sites): BankC2_SceneBoot ($C2:0037) and C2Scene_Mode5 ($C2:255A).
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
; its shadow and brightness and HDMAEN from its shadow; then rebuild the
; sprites: empty the sprite list (C2Scene_SprResetLists), zero
; C2Scene_OamNext, hide every sprite (C2Scene_HideAllSprites), run the
; tasks (C2Scene_TaskRunAll, which add sprite nodes) and draw the list
; into the OAM shadow (C2Scene_SprDrawList), for the next NMI's DMA; and
; set bit 0 again. C2Scene_SprResetLists returns with M=0, so the STZ of
; C2Scene_OamNext is a 16-bit store that zeroes $4E (C2Scene_TaskCur)
; as well.
; Callers note: none (an interrupt handler, entered through the trampoline).
; Entry: an NMI in native mode, any M/X/DP/DB (A, X, Y saved 16-bit, DP
;        and DB saved; then M=0/1 as needed, X=0, DP=$0000, DB=$00)
; Exit:  RTI with A, X, Y, DP, DB and P as they were
; Calls: C2Scene_VramQFlush, BankC2_Entry8002 (JSL), C2Scene_SprResetLists,
;   C2Scene_HideAllSprites, C2Scene_TaskRunAll and C2Scene_SprDrawList.
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
    JSR C2Scene_SprResetLists
    STZ.b !C2Scene_OamNext
    JSR C2Scene_HideAllSprites
    JSR C2Scene_TaskRunAll
    JSR C2Scene_SprDrawList
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
; Callers (3 sites: 2 JSR, 1 JMP): C2Scene_WaitFrames (JSR $C2:0455), C2Scene_WaitOneFrame (JMP
;   $C2:046E) and C2Scene_Mode3 (JSR $C2:2465).
; Entry: M=1 (8-bit compare), X any, DP=$0000, DB any; NMI enabled
; Exit:  M=1; A = the counter before the change; X, Y unchanged
; No calls.
C2Scene_WaitFrame:
    LDA.b !C2Scene_FrameCounter
.wait:
    CMP.b !C2Scene_FrameCounter
    BEQ .wait
    RTS

; $C2:034D — C2Scene_HideAllSprites (162 bytes, $034D–$03EE)
; Parks all 128 sprites of the OAM shadow below the screen: Y =
; Oam_HiddenY in every low-table entry, and the high table zeroed (small
; size, X bit 8 clear). Each pass of the loop hides 8 sprites in each
; quarter of the table (32 unrolled stores), from the last 8 of each
; quarter down to the first. Run by the NMI every frame before the tasks
; and C2Scene_SprDrawList fill the table again.
; Callers (1 JSR site): C2Scene_NmiHandler ($C2:0330).
; Entry: M, X any (SEP #$30 here), DP any, DB with low WRAM at $0000-$1FFF
;        ($00 from the NMI)
; Exit:  M=1, X=0; A low byte = $E0, X = $00E0, Y high byte cleared (by
;        the SEP #$10); DP and DB unchanged
; No calls.
C2Scene_HideAllSprites:
    SEP #$30
    LDX.b #(3*!C2Scene_HidePassBytes)
.pass:
    LDA.b #!Oam_HiddenY
    STA.w !Oam_LowTable+(4*0)+1,X
    STA.w !Oam_LowTable+(4*1)+1,X
    STA.w !Oam_LowTable+(4*2)+1,X
    STA.w !Oam_LowTable+(4*3)+1,X
    STA.w !Oam_LowTable+(4*4)+1,X
    STA.w !Oam_LowTable+(4*5)+1,X
    STA.w !Oam_LowTable+(4*6)+1,X
    STA.w !Oam_LowTable+(4*7)+1,X
    STA.w !Oam_LowTable+(4*32)+1,X
    STA.w !Oam_LowTable+(4*33)+1,X
    STA.w !Oam_LowTable+(4*34)+1,X
    STA.w !Oam_LowTable+(4*35)+1,X
    STA.w !Oam_LowTable+(4*36)+1,X
    STA.w !Oam_LowTable+(4*37)+1,X
    STA.w !Oam_LowTable+(4*38)+1,X
    STA.w !Oam_LowTable+(4*39)+1,X
    STA.w !Oam_LowTable+(4*64)+1,X
    STA.w !Oam_LowTable+(4*65)+1,X
    STA.w !Oam_LowTable+(4*66)+1,X
    STA.w !Oam_LowTable+(4*67)+1,X
    STA.w !Oam_LowTable+(4*68)+1,X
    STA.w !Oam_LowTable+(4*69)+1,X
    STA.w !Oam_LowTable+(4*70)+1,X
    STA.w !Oam_LowTable+(4*71)+1,X
    STA.w !Oam_LowTable+(4*96)+1,X
    STA.w !Oam_LowTable+(4*97)+1,X
    STA.w !Oam_LowTable+(4*98)+1,X
    STA.w !Oam_LowTable+(4*99)+1,X
    STA.w !Oam_LowTable+(4*100)+1,X
    STA.w !Oam_LowTable+(4*101)+1,X
    STA.w !Oam_LowTable+(4*102)+1,X
    STA.w !Oam_LowTable+(4*103)+1,X
    TXA
    SEC
    SBC.b #!C2Scene_HidePassBytes
    TAX
    BPL .pass                   ; X = $60, $40, $20, $00, then $E0 ends it
    REP #$30
    STZ.w !Oam_HighTable
    STZ.w !Oam_HighTable+2
    STZ.w !Oam_HighTable+4
    STZ.w !Oam_HighTable+6
    STZ.w !Oam_HighTable+8
    STZ.w !Oam_HighTable+10
    STZ.w !Oam_HighTable+12
    STZ.w !Oam_HighTable+14
    STZ.w !Oam_HighTable+16
    STZ.w !Oam_HighTable+18
    STZ.w !Oam_HighTable+20
    STZ.w !Oam_HighTable+22
    STZ.w !Oam_HighTable+24
    STZ.w !Oam_HighTable+26
    STZ.w !Oam_HighTable+28
    STZ.w !Oam_HighTable+30
    SEP #$20
    RTS

; $C2:03EF — C2Scene_VramQInit (22 bytes, $03EF–$0404)
; Empties and unlocks the VRAM upload queue: clears C2Scene_VramQLock and
; C2Scene_VramQEnd, points C2Scene_VramQBufPtr at C2Scene_VramQBuf
; ($7E:F000) and zeroes all 16 C2Scene_VramQ entries (dp $60-$DF).
; Callers (6 JSR sites): BankC2_SceneBoot ($C2:003A), C2Scene_Mode5 ($C2:2560), C2Scene_Mode6
;   ($C2:25F0), C2Scene_Mode8 ($C2:265B) and unmatched ($C2:6331, $C2:6A37).
; Entry: M=1 (8-bit bank store), X=0 (16-bit pointer store and loop
;        count), DP=$0000, DB any
; Exit:  M=1, X=0; A = bank(C2Scene_VramQBuf), X = $FFFF; Y, DP and DB
;        unchanged
; No calls.
C2Scene_VramQInit:
    STZ.b !C2Scene_VramQLock
    STZ.b !C2Scene_VramQEnd
    LDX.w #!C2Scene_VramQBuf
    STX.b !C2Scene_VramQBufPtr
    LDA.b #bank(!C2Scene_VramQBuf)
    STA.b !C2Scene_VramQBufPtr+2
    LDX.w #(16*!C2Scene_VramQEntrySize)-1
.clear:
    STZ.b C2Scene_VramQ.Src,X   ; one byte at a time, $DF down to $60
    DEX
    BPL .clear
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
; Scene timing and tasks ($C2:0454–$C2:0555)
; ============================================================
; The scene mode runs its moving parts as tasks: 64 records of 64 bytes
; (C2Scene_Task, at C2Scene_TaskRecords) whose first word is a handler
; address. The NMI calls each live handler once per frame
; (C2Scene_TaskRunAll); a handler ends its task by returning C=1.

; $C2:0454 — C2Scene_WaitFrames (26 bytes, $0454–$046D)
; Waits X frames (C2Scene_WaitFrame each time). After each frame, if a
; sound command is pending (C2Scene_SoundCmdState non-zero) it is sent
; with Audio_DriverCommand, the state marked C2Scene_SoundCmdSending
; meanwhile and cleared after.
; Callers (9 JSR sites): C2Scene_Mode5 ($C2:2532, $C2:2582), C2Scene_Mode6 ($C2:25A1, $C2:2612),
;   C2Scene_Mode8 ($C2:2631, $C2:269D) and unmatched ($C2:63C7, $C2:6A99, $C2:6AB1).
; Entry: M=1 (8-bit flag loads), X=0 with X = the number of frames (0
;        waits 65536), DP=$0000, DB with low WRAM at $0000-$1FFF; NMI on
; Exit:  M=1, X=0, X = 0; A clobbered; Y, DP and DB as Audio_DriverCommand
;        leaves them (not traced)
; Calls: C2Scene_WaitFrame, Audio_DriverCommand (JSL).
C2Scene_WaitFrames:
    PHX
    JSR C2Scene_WaitFrame
    LDA.w !C2Scene_SoundCmdState
    BEQ .next
    LDA.b #!C2Scene_SoundCmdSending
    STA.w !C2Scene_SoundCmdState
    JSL Audio_DriverCommand
    STZ.w !C2Scene_SoundCmdState
.next:
    PLX
    DEX
    BNE C2Scene_WaitFrames
    RTS

; $C2:046E — C2Scene_WaitOneFrame (3 bytes, $046E–$0470)
; A JMP to C2Scene_WaitFrame: waits for the next NMI without sending a
; pending sound command.
; Callers (3 JSR sites): C2Scene_MainLoop ($C2:23CF) and unmatched ($C2:63BA, $C2:6A9C).
; Callers note (3 JSR sites): C2Scene_Main ($C2:23CF, in C2Scene_MainLoop);
;   unmatched: $C2:63BA and $C2:6A9C.
; Entry/Exit: those of C2Scene_WaitFrame.
C2Scene_WaitOneFrame:
    JMP C2Scene_WaitFrame

; $C2:0471 — C2Scene_TaskClearAll (25 bytes, $0471–$0489)
; Frees all 64 task records (zeroes each .Handler) and points
; C2Scene_TaskCur at the first record, so that tasks spawned before any
; task runs copy their parameters from record 0.
; Callers (3 JSR sites): C2Scene_Main ($C2:23B1) and unmatched ($C2:6334, $C2:6A3A).
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB with low WRAM at
;        $0000-$1FFF
; Exit:  M=1, X=0; A = C2Scene_TaskRecordsEnd (16-bit), X = the same, Y =
;        0; DP and DB unchanged
; No calls.
C2Scene_TaskClearAll:
    LDX.w #!C2Scene_TaskRecords
    STX.b !C2Scene_TaskCur
    LDY.w #!C2Scene_TaskCount
    REP #$20
.free:
    STZ.w C2Scene_Task.Handler,X
    TXA
    CLC
    ADC.w #!C2Scene_TaskSize
    TAX
    DEY
    BNE .free
    SEP #$20
    RTS

; $C2:048A — C2Scene_TaskSpawn (67 bytes, $048A–$04CC)
; Starts a task with handler X in the first free record from record 4
; on (records 0-3 are left to C2Scene_TaskSpawnLow, which enters at
; C2Scene_TaskSpawn_Search with its own range). The new record gets
; .Handler = X, .Frames = 0 and .Unk02 = 0, and its bytes +$05-$3F
; (.Params on) are copied from the record C2Scene_TaskCur points at:
; the running task, when a task spawns another.
; If no record is free nothing is written.
; Callers (13 JSR sites): C2Scene_TaskSpawnScript ($C2:04E0), C2Script_SpawnUnk1CF5 ($C2:10C4),
;   C2Script_SpawnUnk1DD4 ($C2:10F7), C2Script_SpawnUnk20A2 ($C2:1590), C2Script_SpawnUnk2105
;   ($C2:159E), C2Script_SpawnUnk21F8 ($C2:15AC), C2Script_SpawnUnk2194 ($C2:15BA),
;   C2Script_SpawnTask ($C2:183F), C2Scene_TaskUnk1DD4 ($C2:1DE2) and unmatched ($C2:63A6, $C2:7417,
;   $C2:742D, $C2:7441).
; Entry: M any, X=0 with X = the handler address, DP=$0000, DB with low
;        WRAM at $0000-$1FFF (the MVN copies in bank $00 and leaves DB
;        as it was)
; Exit:  M=1, X=0. Spawned: X = the new record + $40 (the MVN leaves it
;        there; callers subtract C2Scene_TaskSize), Y = the same, A =
;        $FFFF. None free: X = the end of the searched range (here
;        C2Scene_TaskRecordsEnd), A = the same (16-bit), Y = 0.
;        C2Tmp_08 = the handler. DP and DB unchanged.
; No calls.
!C2Scene_SpawnHandler = !C2Tmp_08
C2Scene_TaskSpawn:
    STX.b !C2Scene_SpawnHandler
    REP #$20
    LDX.w #!C2Scene_TaskRecords+(!C2Scene_TaskLowSlots*!C2Scene_TaskSize)
    LDY.w #!C2Scene_TaskCount-!C2Scene_TaskLowSlots
C2Scene_TaskSpawn_Search:       ; header: see C2Scene_TaskSpawn
    LDA.w C2Scene_Task.Handler,X
    BEQ .found
    TXA
    CLC
    ADC.w #!C2Scene_TaskSize
    TAX
    DEY
    BNE C2Scene_TaskSpawn_Search
    SEP #$20
    RTS
.found:
    LDA.b !C2Scene_SpawnHandler
    STA.w C2Scene_Task.Handler,X
    STZ.w C2Scene_Task.Frames,X
    SEP #$20
    STZ.w C2Scene_Task.Unk02,X
    PHB
    REP #$20
    CLC
    TXA
    ADC.w #!C2Scene_TaskCopyStart
    TAY                         ; destination: the new record + 5
    CLC
    LDA.b !C2Scene_TaskCur
    ADC.w #!C2Scene_TaskCopyStart
    TAX                         ; source: the current task + 5
    LDA.w #!C2Scene_TaskCopyCount
    MVN !Bank00,!Bank00         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    TYX
    SEP #$20
    PLB
    RTS

; $C2:04CD — C2Scene_TaskSpawnLow (12 bytes, $04CD–$04D8)
; C2Scene_TaskSpawn over records 0-3 only: the same search and setup
; (it branches into C2Scene_TaskSpawn_Search).
; Callers (2 JSR sites): C2Scene_TaskSpawnScriptLow ($C2:0502) and C2Script_SpawnTaskLow ($C2:1A49).
; Entry: as C2Scene_TaskSpawn
; Exit:  as C2Scene_TaskSpawn; when no record is free, X = record 4's
;        address (C2Scene_TaskRecords + 4 * C2Scene_TaskSize)
; No calls.
C2Scene_TaskSpawnLow:
    STX.b !C2Scene_SpawnHandler
    REP #$20
    LDX.w #!C2Scene_TaskRecords
    LDY.w #!C2Scene_TaskLowSlots
    BRA C2Scene_TaskSpawn_Search

; $C2:04D9 — C2Scene_TaskSpawnScript (34 bytes, $04D9–$04FA)
; Spawns a C2Scene_TaskRunScript task (C2Scene_TaskSpawn, records 4-63)
; and gives it a script: .ScriptPtr = X, .ScriptBank = A, .Unk0A = 0.
; (Inferred from C2Scene_TaskRunScript, which reads one byte at that
; 24-bit address and dispatches on it.)
; Quirk, kept: there is no check that a record was free. Then X comes
; back as C2Scene_TaskRecordsEnd and the three fields are written into
; the last record (63), whatever runs there.
; Callers (22 sites: 20 JSR, 2 JMP): C2Script_SpawnScript (JSR $C2:1203), C2Scene_Mode3 (JSR
;   $C2:242E, JSR $C2:2459), C2Scene_Mode5 (JSR $C2:2527, JSR $C2:256B), C2Scene_Mode6 (JSR
;   $C2:2596, JSR $C2:25FB), C2Scene_Mode8 (JSR $C2:2626, JSR $C2:2676), C2Scene_LoadScene (JMP
;   $C2:2C90), C2Scene_ObjWatchIdle (JSR $C2:3154), C2Scene_TrigListB (JSR $C2:33B2),
;   C2Scene_TrigListAB (JSR $C2:33DF) and unmatched (JSR $C2:4479, JSR $C2:452C, JSR $C2:63AE, JSR
;   $C2:66DF, JSR $C2:66FF, JSR $C2:6AAB, JSR $C2:741F, JSR $C2:7427, JMP $C2:7457).
; Entry: M=1 with A = the script bank, X=0 with X = the script address,
;        DP=$0000, DB with low WRAM at $0000-$1FFF
; Exit:  M=1, X=0; X = the new record, A = the bank; Y as
;        C2Scene_TaskSpawn leaves it; C2Tmp_01, C2Tmp_08 and C2Tmp_0A
;        changed; DP and DB unchanged
; Calls: C2Scene_TaskSpawn.
!C2Scene_SpawnBank = !C2Tmp_01
!C2Scene_SpawnPtr = !C2Tmp_0A
C2Scene_TaskSpawnScript:
    STA.b !C2Scene_SpawnBank
    STX.b !C2Scene_SpawnPtr
    LDX.w #C2Scene_TaskRunScript
    JSR C2Scene_TaskSpawn
    REP #$20
    TXA
    SEC
    SBC.w #!C2Scene_TaskSize
    TAX
    LDA.b !C2Scene_SpawnPtr
    STA.w C2Scene_Task.ScriptPtr,X
    SEP #$20
    LDA.b !C2Scene_SpawnBank
    STA.w C2Scene_Task.ScriptBank,X
    STZ.w C2Scene_Task.Unk0A,X
    RTS

; $C2:04FB — C2Scene_TaskSpawnScriptLow (34 bytes, $04FB–$051C)
; C2Scene_TaskSpawnScript in records 0-3 (C2Scene_TaskSpawnLow).
; Quirk, kept: as there, no check that a record was free; then the
; fields are written into record 3.
; Callers (1 JSR site): C2Script_SpawnScriptLow ($C2:1A3A).
; Entry/Exit: as C2Scene_TaskSpawnScript
; Calls: C2Scene_TaskSpawnLow.
C2Scene_TaskSpawnScriptLow:
    STA.b !C2Scene_SpawnBank
    STX.b !C2Scene_SpawnPtr
    LDX.w #C2Scene_TaskRunScript
    JSR C2Scene_TaskSpawnLow
    REP #$20
    TXA
    SEC
    SBC.w #!C2Scene_TaskSize
    TAX
    LDA.b !C2Scene_SpawnPtr
    STA.w C2Scene_Task.ScriptPtr,X
    SEP #$20
    LDA.b !C2Scene_SpawnBank
    STA.w C2Scene_Task.ScriptBank,X
    STZ.w C2Scene_Task.Unk0A,X
    RTS

; $C2:051D — C2Scene_TaskRunAll (54 bytes, $051D–$0552)
; Runs every live task once (from the NMI, each frame): for each record
; of C2Scene_TaskRecords with a non-zero .Handler, sets C2Scene_TaskCur
; to it and calls the handler (C2Scene_TaskCallHandler) with X = the
; record and M=1. A handler that returns C=1 is done: its .Handler is
; zeroed. On C=0 the record's .Frames goes up by one.
; Callers (1 JSR site): C2Scene_NmiHandler ($C2:0333).
; Entry: M any (REP #$20 at the loop head), X=0, DP=$0000, DB with low
;        WRAM at $0000-$1FFF ($00 from the NMI)
; Exit:  M=1, X=0; X = C2Scene_TaskRecordsEnd; A, Y and the rest as the
;        handlers leave them; C2Scene_TaskCur = the last task run
; Calls: C2Scene_TaskCallHandler (each task's handler).
C2Scene_TaskRunAll:
    LDX.w #!C2Scene_TaskRecords
.check:
    REP #$20
    LDA.w C2Scene_Task.Handler,X
    BNE .run
.next:
    TXA
    CLC
    ADC.w #!C2Scene_TaskSize
    TAX
    CPX.w #!C2Scene_TaskRecordsEnd
    BNE .check
    SEP #$20
    RTS
.run:
    LDA.w C2Scene_Task.Handler,X
    STA.b !C2Scene_TaskHandler
    SEP #$20
    STX.b !C2Scene_TaskCur
    JSR C2Scene_TaskCallHandler
    LDX.b !C2Scene_TaskCur
    BCC .alive
    REP #$20
    STZ.w C2Scene_Task.Handler,X
    BRA .next
.alive:
    REP #$20
    INC.w C2Scene_Task.Frames,X
    BRA .next

; $C2:0553 — C2Scene_TaskCallHandler (3 bytes, $0553–$0555)
; JMP (C2Scene_TaskHandler): a JSR here calls the task's handler, which
; returns to C2Scene_TaskRunAll.
; Callers (1 JSR site): C2Scene_TaskRunAll ($C2:053E).
; Entry: as C2Scene_TaskRunAll sets it up: M=1, X=0 with X = the record,
;        DP=$0000, C2Scene_TaskHandler = the handler
; Exit:  the handler's; C=1 frees the task
C2Scene_TaskCallHandler:
    JMP (!C2Scene_TaskHandler)

; $C2:0556 — C2Scene_LayerMetatiles (3 words, $0556–$055B)
; Per BG layer 1-3 (index (layer - 1) * 2): where its metatile
; definitions are in bank $7E. Read by C2Scene_DrawBgLayer,
; C2Scene_Unk0568 ($C2:0576) and C2Scene_Unk066C ($C2:067A). Layer 1's set is the one
; C2Scene_LoadMetatiles unpacks at C2Scene_Metatiles; layer 2's follows it
; $800 bytes on (256 metatiles of 8 bytes), so the same pack probably
; holds both. Layer 3's entry, like its other two, is not explained.
C2Scene_LayerMetatiles:
    dw $3000                    ; 1: C2Scene_Metatiles
    dw $3800                    ; 2
    dw $4000                    ; 3

; $C2:055C — C2Scene_LayerMaps (3 words, $055C–$0561)
; Per layer: where its map (96 x 64 metatile numbers, C2Scene_MapBytes)
; is in bank $7E. Layer 1's is C2Scene_BgMaps (C2Scene_LoadBgMaps); layer
; 2's follows it at +$1800. Read by C2Scene_DrawBgLayer, C2Scene_Unk0568
; ($C2:057C), C2Scene_Unk066C ($C2:0680) and C2Script_SetMapCell
; ($C2:1176).
C2Scene_LayerMaps:
    dw $4000                    ; 1: C2Scene_BgMaps
    dw $5800                    ; 2
    dw $7000                    ; 3

; $C2:0562 — C2Scene_LayerVramMaps (3 words, $0562–$0567)
; Per layer: the VRAM word address of its tilemap. 1 and 2 are the BG1SC
; and BG2SC bases BankC2_InitHwRegs sets ($6000, $6800); 3's $7000 is
; where the BG3 tiles go, not the BG3 map ($7800), so layer 3 is probably
; not drawn this way. Read by C2Scene_DrawBgLayer, C2Scene_Unk0568
; ($C2:0582) and C2Scene_Unk066C ($C2:0686).
C2Scene_LayerVramMaps:
    dw $6000                    ; 1: BG1 map
    dw $6800                    ; 2: BG2 map
    dw $7000                    ; 3

; ============================================================
; Scene BG layer scroll ($C2:0568–$C2:09C4)
; ============================================================
; C2Scene_Unk0568 and C2Scene_Unk066C move one BG layer's scroll a pixel
; at a time and keep its tile position C2Scene_BgTileX/Y in step. Each
; time the scroll crosses a tile boundary, the tile column (X) or row
; (Y) that has just come into reach is built from the layer's map and
; metatiles into the buffer at C2Scene_VramQBufPtr and queued for VRAM
; (C2Scene_VramQ, sent by the NMI): the edge builders below. A layer's
; scroll wraps at the map's 1536 x 1024 pixels and its tile position at
; 192 x 128 tiles; the hardware tilemap is 64 x 32 tiles, so the edges
; are written where they wrap into it.
;
; Direct-page work area of the cluster (DP=$0000):
!C2Scene_ScrollLayer = !C2Tmp_00        ; in: the layer, 1-3 (16-bit read, AND C2Scene_LayerMask)
!C2Scene_ScrollPx = !C2Tmp_01           ; in: signed pixels to move (8-bit)
!C2Scene_EdgeMapPtr = !C2Tmp_02         ; 16-bit: the map + the column (column) or + row * 96 (row)
!C2Scene_EdgeMapOfs = !C2Tmp_04         ; 16-bit: map byte offset added to it, stepped per metatile
!C2Scene_EdgeBuf = !C2Tmp_06            ; 16-bit: C2Scene_VramQBufPtr's address (bank $7E)
!C2Scene_EdgeCol = !C2Tmp_08            ; 16-bit; in to a builder: the metatile column; in to a
                                        ; queuer: the edge's BG pixel X; out: its VRAM address
!C2Scene_EdgeHalf = !C2Tmp_08           ; 16-bit, in a builder: bit 0 picks the metatile half
!C2Scene_EdgeRow = !C2Tmp_0A            ; 16-bit; in to a builder: the metatile row; in to a row
                                        ; queuer: the edge's BG pixel Y; out: the right screen's VRAM address
!C2Scene_EdgeBufPos = !C2Tmp_0A         ; 16-bit, in a builder: byte offset in the buffer
!C2Scene_ScrollLeft = !C2Tmp_0C         ; 16-bit pixels still to move
!C2Scene_ScrollSlot = !C2Tmp_0E         ; 16-bit (layer - 1) * 2: word index of the layer's variables
!C2Scene_ScrollMetatiles = !C2Tmp_10    ; 16-bit address (bank $7E) of the layer's metatiles
!C2Scene_ScrollMap = !C2Tmp_13          ; 16-bit address (bank $7E) of the layer's map
!C2Scene_ScrollVramMap = !C2Tmp_16      ; 16-bit VRAM word address of the layer's tilemap
!C2Scene_EdgeTilesLeft = !C2Tmp_19      ; 16-bit tiles still to build (also row * 64 in the setups)

; $C2:0568 — C2Scene_Unk0568 (260 bytes, $0568–$066B)
; Scrolls BG layer C2Scene_ScrollLayer horizontally by C2Scene_ScrollPx
; pixels (signed: negative moves the view left), one pixel per pass.
; Each pass moves the scroll shadow (C2Scene_Bg1HScroll + slot) by one,
; wrapping in 0-$5FF, and the tile X (C2Scene_BgTileX + slot) whenever
; the scroll leaves a tile boundary to the left or reaches one to the
; right, wrapping in 0-191. When the new scroll is on a tile boundary,
; the tile column that has come into reach is built and queued:
; - left: tile BgTileX - 1, at pixel X scroll - 8 (just off the left
;   edge);
; - right: tile BgTileX + 32, at pixel X scroll + 256 (just off the
;   right edge);
; from the metatile column tile / 2, starting at tile row BgTileY - 1
; (C2Scene_EdgeColLeft for an even tile, C2Scene_EdgeColRight for an
; odd one; then C2Scene_QueueEdgeCol). The name stays Unk until its
; callers are next edited (C2Script_ScrollFrames' header guesses this
; use).
; Quirk, kept: a layer number of 0 (or 4, 8, ...) ends in an endless
; loop (.hang), as in C2Scene_DrawBgLayer. 0 pixels does nothing.
; Callers (12 JSR sites): C2Script_ScrollFrames ($C2:168A, $C2:1691), C2Script_ScrollLayerFrames
;   ($C2:173C) and unmatched ($C2:3702, $C2:3709, $C2:38FB, $C2:3902, $C2:468A, $C2:4691, $C2:4F93,
;   $C2:4F9A, $C2:785B).
; Callers note (12 JSR sites): C2Script_ScrollFrames ($C2:168A, $C2:1691),
;   C2Script_ScrollLayerFrames ($C2:173C); unmatched: $C2:3702, $C2:3709,
;   $C2:38FB, $C2:3902, $C2:468A, $C2:4691, $C2:4F93, $C2:4F9A and
;   $C2:785B (xref rates $38FB and $3902 doubtful; they are real calls).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (work area; TDC for 0),
;        DB=$00 (absolute C2Scene_BgTileX and the VRAM queue);
;        C2Scene_ScrollLayer and C2Scene_ScrollPx set
; Exit:  M=1, X=0, DB unchanged; A, X, Y clobbered; C2Tmp_02-$1A changed
;        (C2Tmp_0C = 0 after a move); the layer's scroll and tile X,
;        C2Scene_VramQ entries, C2Scene_VramQEnd/Lock and
;        C2Scene_VramQBufPtr changed when a column is queued
; Calls: C2Scene_EdgeColLeft, C2Scene_EdgeColRight, C2Scene_QueueEdgeCol.
C2Scene_Unk0568:
    REP #$20
    LDA.b !C2Scene_ScrollLayer
    AND.w #!C2Scene_LayerMask
    BEQ .hang
    DEC A
    ASL A
    STA.b !C2Scene_ScrollSlot
    TAX
    LDA.l C2Scene_LayerMetatiles,X
    STA.b !C2Scene_ScrollMetatiles
    LDA.l C2Scene_LayerMaps,X
    STA.b !C2Scene_ScrollMap
    LDA.l C2Scene_LayerVramMaps,X
    STA.b !C2Scene_ScrollVramMap
    SEP #$20
    LDA.b !C2Scene_ScrollPx
    BEQ .done
    BPL .right
    JSR .left
    BRA .moved
.right:
    JSR .go_right
.moved:
    SEP #$20
.done:
    RTS
.hang:
    BRA .hang
.left:
    REP #$20
    ORA.w #!Eng_HighByteMask
    EOR.w #!Eng_Invert16
    INC A                       ; pixels = -C2Scene_ScrollPx
    STA.b !C2Scene_ScrollLeft
.left_px:
    LDX.b !C2Scene_ScrollSlot
    LDA.b !C2Scene_Bg1HScroll,X
    AND.w #!C2Scene_PxInTileMask
    BNE .left_scroll            ; leaving a tile boundary: one tile left
    LDA.w !C2Scene_BgTileX,X
    DEC A
    BPL .left_tile
    LDA.w #!C2Scene_MapTilesX-1
.left_tile:
    STA.w !C2Scene_BgTileX,X
.left_scroll:
    LDA.b !C2Scene_Bg1HScroll,X
    DEC A
    BPL .left_set
    LDA.w #!C2Scene_MapWidthPx-1
.left_set:
    STA.b !C2Scene_Bg1HScroll,X
    AND.w #!C2Scene_PxInTileMask
    BEQ .left_edge
.left_next:
    DEC.b !C2Scene_ScrollLeft
    BNE .left_px
    RTS
.left_edge:
    LDA.w !C2Scene_BgTileX,X    ; the column one tile left of BgTileX
    DEC A
    BPL .left_col
    LDA.w #!C2Scene_MapTilesX-1
.left_col:
    LSR A
    STA.b !C2Scene_EdgeCol
    LDA.w !C2Scene_BgTileY,X    ; from one tile above BgTileY
    DEC A
    BPL .left_row
    LDA.w #!C2Scene_MapTilesY-1
.left_row:
    LSR A
    STA.b !C2Scene_EdgeRow
    LDA.b !C2Scene_Bg1HScroll,X
    AND.w #!C2Scene_TilePx
    BNE .left_odd               ; tile X odd: column X - 1 is even (left halves)
    JSR C2Scene_EdgeColRight
    BRA .left_queue
.left_odd:
    JSR C2Scene_EdgeColLeft
.left_queue:
    LDX.b !C2Scene_ScrollSlot
    LDA.b !C2Scene_Bg1HScroll,X
    SEC
    SBC.w #!C2Scene_TilePx
    STA.b !C2Scene_EdgeCol
    JSR C2Scene_QueueEdgeCol
    BRA .left_next
.go_right:
    REP #$20
    AND.w #!Eng_LowByteMask
    STA.b !C2Scene_ScrollLeft
.right_px:
    LDX.b !C2Scene_ScrollSlot
    LDA.b !C2Scene_Bg1HScroll,X
    INC A
    CMP.w #!C2Scene_MapWidthPx
    BCC .right_set
    TDC                         ; A = DP = 0: wrap to 0
.right_set:
    STA.b !C2Scene_Bg1HScroll,X
    AND.w #!C2Scene_PxInTileMask
    BEQ .right_edge
.right_next:
    DEC.b !C2Scene_ScrollLeft
    BNE .right_px
    RTS
.right_edge:
    LDA.w !C2Scene_BgTileX,X    ; reached a tile boundary: one tile right
    INC A
    CMP.w #!C2Scene_MapTilesX
    BCC .right_tile
    TDC
.right_tile:
    STA.w !C2Scene_BgTileX,X
    CLC                         ; the column 32 tiles right of BgTileX
    ADC.w #!C2Scene_EdgeAheadCols
    CMP.w #!C2Scene_MapTilesX
    BCC .right_col
    SEC
    SBC.w #!C2Scene_MapTilesX
.right_col:
    LSR A
    STA.b !C2Scene_EdgeCol
    LDA.w !C2Scene_BgTileY,X
    DEC A
    BPL .right_row
    LDA.w #!C2Scene_MapTilesY-1
.right_row:
    LSR A
    STA.b !C2Scene_EdgeRow
    LDA.b !C2Scene_Bg1HScroll,X
    AND.w #!C2Scene_TilePx
    BNE .right_odd              ; tile X odd: column X + 32 is odd (right halves)
    JSR C2Scene_EdgeColLeft
    BRA .right_queue
.right_odd:
    JSR C2Scene_EdgeColRight
.right_queue:
    LDX.b !C2Scene_ScrollSlot
    LDA.b !C2Scene_Bg1HScroll,X
    CLC
    ADC.w #!C2Scene_EdgeRightPx
    STA.b !C2Scene_EdgeCol
    JSR C2Scene_QueueEdgeCol
    BRA .right_next

; $C2:066C — C2Scene_Unk066C (263 bytes, $066C–$0772)
; C2Scene_Unk0568 for the vertical: scrolls the layer's
; C2Scene_Bg1VScroll + slot by C2Scene_ScrollPx pixels (negative: up),
; wrapping in 0-$3FF, with its tile Y (C2Scene_BgTileY + slot) in
; 0-127. On a tile boundary it builds and queues the tile row that has
; come into reach:
; - up: tile row BgTileY - 1, at pixel Y scroll - 8;
; - down: tile row BgTileY + 28, at pixel Y scroll + 224 (just below
;   the 224-line screen);
; from the metatile row tile / 2, starting at tile column BgTileX - 1
; (C2Scene_EdgeRowTop for an even row, C2Scene_EdgeRowBottom for an odd
; one; then C2Scene_QueueEdgeRow).
; Quirk, kept: a layer number of 0 (or 4, 8, ...) loops for good
; (.hang). 0 pixels does nothing.
; Callers (11 JSR sites): C2Script_ScrollFrames ($C2:16C7, $C2:16CE), C2Script_ScrollLayerFrames
;   ($C2:1751) and unmatched ($C2:3717, $C2:371E, $C2:385B, $C2:3862, $C2:469F, $C2:46A6, $C2:4FA8,
;   $C2:4FAF).
; Callers note (11 JSR sites): C2Script_ScrollFrames ($C2:16C7, $C2:16CE),
;   C2Script_ScrollLayerFrames ($C2:1751); unmatched: $C2:3717, $C2:371E,
;   $C2:385B, $C2:3862, $C2:469F, $C2:46A6, $C2:4FA8 and $C2:4FAF (xref
;   rates $385B and $3862 doubtful; they are real calls).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (work area; TDC for 0),
;        DB=$00 (absolute C2Scene_BgTileY and the VRAM queue);
;        C2Scene_ScrollLayer and C2Scene_ScrollPx set
; Exit:  M=1, X=0, DB unchanged; A, X, Y clobbered; C2Tmp_02-$1A changed
;        (C2Tmp_0C = 0 after a move); the layer's VScroll and tile Y,
;        C2Scene_VramQ entries, C2Scene_VramQEnd/Lock and
;        C2Scene_VramQBufPtr changed when a row is queued
; Calls: C2Scene_EdgeRowTop, C2Scene_EdgeRowBottom, C2Scene_QueueEdgeRow.
C2Scene_Unk066C:
    REP #$20
    LDA.b !C2Scene_ScrollLayer
    AND.w #!C2Scene_LayerMask
    BEQ .hang
    DEC A
    ASL A
    STA.b !C2Scene_ScrollSlot
    TAX
    LDA.l C2Scene_LayerMetatiles,X
    STA.b !C2Scene_ScrollMetatiles
    LDA.l C2Scene_LayerMaps,X
    STA.b !C2Scene_ScrollMap
    LDA.l C2Scene_LayerVramMaps,X
    STA.b !C2Scene_ScrollVramMap
    SEP #$20
    LDA.b !C2Scene_ScrollPx
    BEQ .done
    BPL .down
    JSR .up
    BRA .moved
.down:
    JSR .go_down
.moved:
    SEP #$20
.done:
    RTS
.hang:
    BRA .hang
.up:
    REP #$20
    ORA.w #!Eng_HighByteMask
    EOR.w #!Eng_Invert16
    INC A                       ; pixels = -C2Scene_ScrollPx
    STA.b !C2Scene_ScrollLeft
.up_px:
    LDX.b !C2Scene_ScrollSlot
    LDA.b !C2Scene_Bg1VScroll,X
    AND.w #!C2Scene_PxInTileMask
    BNE .up_scroll              ; leaving a tile boundary: one tile up
    LDA.w !C2Scene_BgTileY,X
    DEC A
    BPL .up_tile
    LDA.w #!C2Scene_MapTilesY-1
.up_tile:
    STA.w !C2Scene_BgTileY,X
.up_scroll:
    LDA.b !C2Scene_Bg1VScroll,X
    DEC A
    BPL .up_set
    LDA.w #!C2Scene_MapHeightMask
.up_set:
    STA.b !C2Scene_Bg1VScroll,X
    AND.w #!C2Scene_PxInTileMask
    BEQ .up_edge
.up_next:
    DEC.b !C2Scene_ScrollLeft
    BNE .up_px
    RTS
.up_edge:
    LDA.w !C2Scene_BgTileX,X    ; from one tile left of BgTileX
    DEC A
    BPL .up_col
    LDA.w #!C2Scene_MapTilesX-1
.up_col:
    LSR A
    STA.b !C2Scene_EdgeCol
    LDA.w !C2Scene_BgTileY,X    ; the row one tile above BgTileY
    DEC A
    BPL .up_row
    LDA.w #!C2Scene_MapTilesY-1
.up_row:
    LSR A
    STA.b !C2Scene_EdgeRow
    LDA.b !C2Scene_Bg1VScroll,X
    AND.w #!C2Scene_TilePx
    BNE .up_odd                 ; tile Y odd: row Y - 1 is even (top halves)
    JSR C2Scene_EdgeRowBottom
    BRA .up_queue
.up_odd:
    JSR C2Scene_EdgeRowTop
.up_queue:
    LDX.b !C2Scene_ScrollSlot
    LDA.b !C2Scene_Bg1VScroll,X
    SEC
    SBC.w #!C2Scene_TilePx
    STA.b !C2Scene_EdgeRow
    JSR C2Scene_QueueEdgeRow
    BRA .up_next
.go_down:
    REP #$20
    AND.w #!Eng_LowByteMask
    STA.b !C2Scene_ScrollLeft
.down_px:
    LDX.b !C2Scene_ScrollSlot
    LDA.b !C2Scene_Bg1VScroll,X
    INC A
    CMP.w #!C2Scene_MapHeightPx
    BCC .down_set
    TDC                         ; A = DP = 0: wrap to 0
.down_set:
    STA.b !C2Scene_Bg1VScroll,X
    AND.w #!C2Scene_PxInTileMask
    BEQ .down_edge
.down_next:
    DEC.b !C2Scene_ScrollLeft
    BNE .down_px
    RTS
.down_edge:
    LDA.w !C2Scene_BgTileY,X    ; reached a tile boundary: one tile down
    INC A
    CMP.w #!C2Scene_MapTilesY
    BCC .down_tile
    TDC
.down_tile:
    STA.w !C2Scene_BgTileY,X
    LDA.w !C2Scene_BgTileX,X
    DEC A
    BPL .down_col
    LDA.w #!C2Scene_MapTilesX-1
.down_col:
    LSR A
    STA.b !C2Scene_EdgeCol
    LDA.w !C2Scene_BgTileY,X    ; the row 28 tiles below BgTileY
    CLC
    ADC.w #!C2Scene_EdgeAheadRows
    CMP.w #!C2Scene_MapTilesY
    BCC .down_row
    SEC
    SBC.w #!C2Scene_MapTilesY
.down_row:
    LSR A
    STA.b !C2Scene_EdgeRow
    LDA.b !C2Scene_Bg1VScroll,X
    AND.w #!C2Scene_TilePx
    BNE .down_odd               ; tile Y odd: row Y + 28 is odd (bottom halves)
    JSR C2Scene_EdgeRowTop
    BRA .down_queue
.down_odd:
    JSR C2Scene_EdgeRowBottom
.down_queue:
    LDX.b !C2Scene_ScrollSlot
    LDA.b !C2Scene_Bg1VScroll,X
    CLC
    ADC.w #!C2Scene_EdgeBottomPx
    STA.b !C2Scene_EdgeRow
    JSR C2Scene_QueueEdgeRow
    BRA .down_next

; $C2:0773 — C2Scene_EdgeColLeft (79 bytes, $0773–$07C1)
; Builds one tile column of a layer edge into the buffer at
; C2Scene_VramQBufPtr: C2Scene_EdgeColTiles (30) tiles from the left
; half of metatile column C2Scene_EdgeCol, starting at metatile row
; C2Scene_EdgeRow (C2Scene_EdgeColSetup). Each metatile gives two tiles,
; .TopLeft then .BottomLeft; the first is skipped when the layer's tile Y
; is even (the column starts at tile row BgTileY - 1, an odd row). The
; map row steps down by 96 bytes, wrapping at the map's end, and the
; buffer offset by one word, wrapping within the 32 words.
; Note: 30 of the 32 buffer words are written; the two others
; keep what the buffer held and are sent to VRAM with them
; (C2Scene_QueueEdgeCol sends 32), which falls in the two rows not on
; screen.
; Callers (2 JSR sites): C2Scene_Unk0568 ($C2:05F5, $C2:0655).
; Entry: M=0, X=0, DP=$0000, DB=$00 (set to $7E for the map and buffer
;        and restored); C2Scene_EdgeCol/Row, C2Scene_ScrollSlot,
;        C2Scene_ScrollMap and C2Scene_ScrollMetatiles set
; Exit:  M=0, X=0, DB unchanged; A, X, Y clobbered; C2Tmp_02-$0A and $19
;        changed
; Calls: C2Scene_EdgeColSetup.
C2Scene_EdgeColLeft:
    JSR C2Scene_EdgeColSetup
    SEP #$20
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDA.w #!C2Scene_EdgeColTiles
    STA.b !C2Scene_EdgeTilesLeft
.tile:
    LDY.b !C2Scene_EdgeMapOfs
    LDA.b (!C2Scene_EdgeMapPtr),Y
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A                       ; * 8 bytes per metatile (C = 0)
    ADC.b !C2Scene_ScrollMetatiles
    TAX
    LDY.b !C2Scene_EdgeBufPos
    LDA.b !C2Scene_EdgeHalf
    LSR A
    BCS .bottom
    LDA.w C2Scene_Metatile.TopLeft,X
    STA.b (!C2Scene_EdgeBuf),Y
    BRA .next
.bottom:
    LDA.w C2Scene_Metatile.BottomLeft,X
    STA.b (!C2Scene_EdgeBuf),Y
    CLC
    LDA.b !C2Scene_EdgeMapOfs
    ADC.w #!C2Scene_MapCols
    CMP.w #!C2Scene_MapBytes
    BCC .row_set
    TDC                         ; A = DP = 0: wrap to row 0
.row_set:
    STA.b !C2Scene_EdgeMapOfs
.next:
    TYA
    INC A
    INC A
    AND.w #!C2Scene_ColBufMask
    STA.b !C2Scene_EdgeBufPos
    INC.b !C2Scene_EdgeHalf
    DEC.b !C2Scene_EdgeTilesLeft
    BNE .tile
    PLB
    RTS

; $C2:07C2 — C2Scene_EdgeColRight (79 bytes, $07C2–$0810)
; C2Scene_EdgeColLeft for the right half of the metatiles: .TopRight
; and .BottomRight.
; Callers (2 JSR sites): C2Scene_Unk0568 ($C2:05F0, $C2:065A).
; Entry: M=0, X=0, DP=$0000, DB=$00 (set to $7E for the map and buffer
;        and restored); C2Scene_EdgeCol/Row, C2Scene_ScrollSlot,
;        C2Scene_ScrollMap and C2Scene_ScrollMetatiles set
; Exit:  M=0, X=0, DB unchanged; A, X, Y clobbered; C2Tmp_02-$0A and $19
;        changed
; Calls: C2Scene_EdgeColSetup.
C2Scene_EdgeColRight:
    JSR C2Scene_EdgeColSetup
    SEP #$20
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDA.w #!C2Scene_EdgeColTiles
    STA.b !C2Scene_EdgeTilesLeft
.tile:
    LDY.b !C2Scene_EdgeMapOfs
    LDA.b (!C2Scene_EdgeMapPtr),Y
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A                       ; * 8 bytes per metatile (C = 0)
    ADC.b !C2Scene_ScrollMetatiles
    TAX
    LDY.b !C2Scene_EdgeBufPos
    LDA.b !C2Scene_EdgeHalf
    LSR A
    BCS .bottom
    LDA.w C2Scene_Metatile.TopRight,X
    STA.b (!C2Scene_EdgeBuf),Y
    BRA .next
.bottom:
    LDA.w C2Scene_Metatile.BottomRight,X
    STA.b (!C2Scene_EdgeBuf),Y
    CLC
    LDA.b !C2Scene_EdgeMapOfs
    ADC.w #!C2Scene_MapCols
    CMP.w #!C2Scene_MapBytes
    BCC .row_set
    TDC                         ; A = DP = 0: wrap to row 0
.row_set:
    STA.b !C2Scene_EdgeMapOfs
.next:
    TYA
    INC A
    INC A
    AND.w #!C2Scene_ColBufMask
    STA.b !C2Scene_EdgeBufPos
    INC.b !C2Scene_EdgeHalf
    DEC.b !C2Scene_EdgeTilesLeft
    BNE .tile
    PLB
    RTS

; $C2:0811 — C2Scene_EdgeColSetup (50 bytes, $0811–$0842)
; Sets up a column build: C2Scene_EdgeMapOfs = C2Scene_EdgeRow * 96 (the
; row's offset in the map), C2Scene_EdgeMapPtr = the layer's map +
; C2Scene_EdgeCol, C2Scene_EdgeBuf = C2Scene_VramQBufPtr's address;
; C2Scene_EdgeHalf = 1 when the layer's tile Y is even, else 0; and
; C2Scene_EdgeBufPos = ((VScroll - 8) AND $F8) / 4, the buffer word of
; the tile row one above the scroll (32 rows of the tilemap).
; Callers (2 JSR sites): C2Scene_EdgeColLeft ($C2:0773) and C2Scene_EdgeColRight ($C2:07C2).
; Entry: M=0, X=0, DP=$0000, DB=$00 (C2Scene_VramQBufPtr and
;        C2Scene_BgTileY read absolute)
; Exit:  M=0, X=0; A = the buffer offset; X = C2Scene_ScrollSlot; Y
;        unchanged; C2Tmp_02-$0A and $19 changed
; No calls.
C2Scene_EdgeColSetup:
    LDA.b !C2Scene_EdgeRow
    XBA
    LSR A
    LSR A
    STA.b !C2Scene_EdgeTilesLeft ; row * 64
    LSR A                       ; row * 32 (C = 0)
    ADC.b !C2Scene_EdgeTilesLeft
    STA.b !C2Scene_EdgeMapOfs   ; row * 96
    LDA.b !C2Scene_ScrollMap
    CLC
    ADC.b !C2Scene_EdgeCol
    STA.b !C2Scene_EdgeMapPtr
    LDA.w !C2Scene_VramQBufPtr
    STA.b !C2Scene_EdgeBuf
    LDX.b !C2Scene_ScrollSlot
    STZ.b !C2Scene_EdgeHalf
    LDA.w !C2Scene_BgTileY,X
    LSR A
    BCS .odd
    INC.b !C2Scene_EdgeHalf     ; tile Y even: start on a bottom half
.odd:
    LDA.b !C2Scene_Bg1VScroll,X
    SEC
    SBC.w #!C2Scene_TilePx
    AND.w #!C2Scene_PxTileRowMask
    LSR A
    LSR A
    STA.b !C2Scene_EdgeBufPos
    RTS

; $C2:0843 — C2Scene_EdgeRowTop (76 bytes, $0843–$088E)
; Builds one tile row of a layer edge into the buffer at
; C2Scene_VramQBufPtr: C2Scene_EdgeRowTiles (34) tiles from the top half
; of metatile row C2Scene_EdgeRow, starting at metatile column
; C2Scene_EdgeCol (C2Scene_EdgeRowSetup). Each metatile gives .TopLeft
; then .TopRight; the first is skipped when the layer's tile X is even
; (the row starts at tile column BgTileX - 1, an odd column). The map
; column steps right, wrapping at 96, and the buffer offset by one word,
; wrapping within the 64 words of the row.
; Note: 34 of the 64 buffer words are written; the other 30 keep
; what the buffer held and C2Scene_QueueEdgeRow sends all 64 (they fall
; off screen).
; Callers (2 JSR sites): C2Scene_Unk066C ($C2:06F9, $C2:075C).
; Entry: M=0, X=0, DP=$0000, DB=$00 (set to $7E for the map and buffer
;        and restored); C2Scene_EdgeCol/Row, C2Scene_ScrollSlot,
;        C2Scene_ScrollMap and C2Scene_ScrollMetatiles set
; Exit:  M=0, X=0, DB unchanged; A, X, Y clobbered; C2Tmp_02-$0A and $19
;        changed
; Calls: C2Scene_EdgeRowSetup.
C2Scene_EdgeRowTop:
    JSR C2Scene_EdgeRowSetup
    SEP #$20
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDA.w #!C2Scene_EdgeRowTiles
    STA.b !C2Scene_EdgeTilesLeft
.tile:
    LDY.b !C2Scene_EdgeMapOfs
    LDA.b (!C2Scene_EdgeMapPtr),Y
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A                       ; * 8 bytes per metatile (C = 0)
    ADC.b !C2Scene_ScrollMetatiles
    TAX
    LDY.b !C2Scene_EdgeBufPos
    LDA.b !C2Scene_EdgeHalf
    LSR A
    BCS .right
    LDA.w C2Scene_Metatile.TopLeft,X
    STA.b (!C2Scene_EdgeBuf),Y
    BRA .next
.right:
    LDA.w C2Scene_Metatile.TopRight,X
    STA.b (!C2Scene_EdgeBuf),Y
    LDA.b !C2Scene_EdgeMapOfs
    INC A
    CMP.w #!C2Scene_MapCols
    BCC .col_set
    TDC                         ; A = DP = 0: wrap to column 0
.col_set:
    STA.b !C2Scene_EdgeMapOfs
.next:
    TYA
    INC A
    INC A
    AND.w #!C2Scene_RowBufMask
    STA.b !C2Scene_EdgeBufPos
    INC.b !C2Scene_EdgeHalf
    DEC.b !C2Scene_EdgeTilesLeft
    BNE .tile
    PLB
    RTS

; $C2:088F — C2Scene_EdgeRowBottom (76 bytes, $088F–$08DA)
; C2Scene_EdgeRowTop for the bottom half of the metatiles: .BottomLeft
; and .BottomRight.
; Callers (2 JSR sites): C2Scene_Unk066C ($C2:06F4, $C2:0761).
; Entry: M=0, X=0, DP=$0000, DB=$00 (set to $7E for the map and buffer
;        and restored); C2Scene_EdgeCol/Row, C2Scene_ScrollSlot,
;        C2Scene_ScrollMap and C2Scene_ScrollMetatiles set
; Exit:  M=0, X=0, DB unchanged; A, X, Y clobbered; C2Tmp_02-$0A and $19
;        changed
; Calls: C2Scene_EdgeRowSetup.
C2Scene_EdgeRowBottom:
    JSR C2Scene_EdgeRowSetup
    SEP #$20
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDA.w #!C2Scene_EdgeRowTiles
    STA.b !C2Scene_EdgeTilesLeft
.tile:
    LDY.b !C2Scene_EdgeMapOfs
    LDA.b (!C2Scene_EdgeMapPtr),Y
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A                       ; * 8 bytes per metatile (C = 0)
    ADC.b !C2Scene_ScrollMetatiles
    TAX
    LDY.b !C2Scene_EdgeBufPos
    LDA.b !C2Scene_EdgeHalf
    LSR A
    BCS .right
    LDA.w C2Scene_Metatile.BottomLeft,X
    STA.b (!C2Scene_EdgeBuf),Y
    BRA .next
.right:
    LDA.w C2Scene_Metatile.BottomRight,X
    STA.b (!C2Scene_EdgeBuf),Y
    LDA.b !C2Scene_EdgeMapOfs
    INC A
    CMP.w #!C2Scene_MapCols
    BCC .col_set
    TDC                         ; A = DP = 0: wrap to column 0
.col_set:
    STA.b !C2Scene_EdgeMapOfs
.next:
    TYA
    INC A
    INC A
    AND.w #!C2Scene_RowBufMask
    STA.b !C2Scene_EdgeBufPos
    INC.b !C2Scene_EdgeHalf
    DEC.b !C2Scene_EdgeTilesLeft
    BNE .tile
    PLB
    RTS

; $C2:08DB — C2Scene_EdgeRowSetup (50 bytes, $08DB–$090C)
; Sets up a row build: C2Scene_EdgeMapOfs = C2Scene_EdgeCol (the column),
; C2Scene_EdgeMapPtr = the layer's map + C2Scene_EdgeRow * 96,
; C2Scene_EdgeBuf = C2Scene_VramQBufPtr's address; C2Scene_EdgeHalf = 1
; when the layer's tile X is even, else 0; and C2Scene_EdgeBufPos =
; ((HScroll - 8) AND $1F8) / 4, the buffer word of the tile column one
; left of the scroll (64 columns of the tilemap).
; Callers (2 JSR sites): C2Scene_EdgeRowTop ($C2:0843) and C2Scene_EdgeRowBottom ($C2:088F).
; Entry: M=0, X=0, DP=$0000, DB=$00 (C2Scene_VramQBufPtr and
;        C2Scene_BgTileX read absolute)
; Exit:  M=0, X=0; A = the buffer offset; X = C2Scene_ScrollSlot; Y
;        unchanged; C2Tmp_02-$0A and $19 changed
; No calls.
C2Scene_EdgeRowSetup:
    LDA.b !C2Scene_EdgeCol
    STA.b !C2Scene_EdgeMapOfs
    LDA.b !C2Scene_EdgeRow
    XBA
    LSR A
    LSR A
    STA.b !C2Scene_EdgeTilesLeft ; row * 64
    LSR A                       ; row * 32 (C = 0)
    ADC.b !C2Scene_EdgeTilesLeft ; row * 96
    CLC
    ADC.b !C2Scene_ScrollMap
    STA.b !C2Scene_EdgeMapPtr
    LDA.w !C2Scene_VramQBufPtr
    STA.b !C2Scene_EdgeBuf
    LDX.b !C2Scene_ScrollSlot
    STZ.b !C2Scene_EdgeHalf
    LDA.w !C2Scene_BgTileX,X
    LSR A
    BCS .odd
    INC.b !C2Scene_EdgeHalf     ; tile X even: start on a right half
.odd:
    LDA.b !C2Scene_Bg1HScroll,X
    SEC
    SBC.w #!C2Scene_TilePx
    AND.w #!C2Scene_PxTileColMask
    LSR A
    LSR A
    STA.b !C2Scene_EdgeBufPos
    RTS

; $C2:090D — C2Scene_QueueEdgeCol (84 bytes, $090D–$0960)
; Queues the column built at C2Scene_VramQBufPtr for VRAM: one
; C2Scene_VramQ entry of C2Scene_ColBufHalf bytes from bank $7E, VMAIN
; stepping 32 words, to tile column (C2Scene_EdgeCol / 8) AND 63 of the
; layer's tilemap (columns 32-63 in the second screen, as
; C2Scene_UploadBgColumn). The queue is locked (C2Scene_VramQLock) while
; the entry is written; C2Scene_VramQBufPtr then moves past the column.
; There is no check that the queue has room.
; Callers (2 JSR sites): C2Scene_Unk0568 ($C2:0602, $C2:0667).
; Entry: M=0, X=0, DP=$0000, DB=$00 (the queue, absolute);
;        C2Scene_EdgeCol = the column's BG pixel X, C2Scene_ScrollVramMap
;        set
; Exit:  M=0, X=0; A = the new buffer pointer; X = the entry's offset; Y
;        unchanged; C2Scene_EdgeCol = the VRAM address
; No calls.
C2Scene_QueueEdgeCol:
    LDA.b !C2Scene_EdgeCol
    LSR A
    LSR A
    LSR A
    AND.w #!C2Scene_TileColMask
    CMP.w #!C2Scene_MapScreenCols
    BCC .left_screen
    CLC
    ADC.w #!C2Scene_MapScreen2Skip
.left_screen:
    CLC
    ADC.b !C2Scene_ScrollVramMap
    STA.b !C2Scene_EdgeCol
    SEP #$30
    INC.w !C2Scene_VramQLock
    LDX.w !C2Scene_VramQEnd
    LDA.b #!Bank7E
    STA.w C2Scene_VramQ.Bank,X
    LDA.b #!VMAIN_IncAfterHigh|VRAM_INC_32
    STA.w C2Scene_VramQ.Vmain,X
    REP #$20
    LDA.w !C2Scene_VramQBufPtr
    STA.w C2Scene_VramQ.Src,X
    LDA.b !C2Scene_EdgeCol
    STA.w C2Scene_VramQ.Dest,X
    LDA.w #!C2Scene_ColBufHalf
    STA.w C2Scene_VramQ.Size,X
    SEP #$20
    TXA
    CLC
    ADC.b #!C2Scene_VramQEntrySize
    STA.w !C2Scene_VramQEnd
    STZ.w !C2Scene_VramQLock
    REP #$30
    CLC
    LDA.w !C2Scene_VramQBufPtr
    ADC.w #!C2Scene_ColBufHalf
    STA.w !C2Scene_VramQBufPtr
    RTS

; $C2:0961 — C2Scene_QueueEdgeRow (100 bytes, $0961–$09C4)
; Queues the row built at C2Scene_VramQBufPtr for VRAM as two
; C2Scene_VramQ entries of C2Scene_RowBufHalf bytes from bank $7E, VMAIN
; stepping one word: the buffer's first half to tile row
; (C2Scene_EdgeRow AND $F8) / 8 of the layer's left screen, its second
; half to the same row of the right screen ($400 words on). Locked and
; advanced as in C2Scene_QueueEdgeCol (by both halves).
; Callers (2 JSR sites): C2Scene_Unk066C ($C2:0706, $C2:076E).
; Entry: M=0, X=0, DP=$0000, DB=$00 (the queue, absolute);
;        C2Scene_EdgeRow = the row's BG pixel Y, C2Scene_ScrollVramMap set
; Exit:  M=0, X=0; A = the new buffer pointer; X = the first entry's
;        offset; Y unchanged; C2Scene_EdgeCol / C2Scene_EdgeRow = the two
;        VRAM addresses
; No calls.
C2Scene_QueueEdgeRow:
    LDA.b !C2Scene_EdgeRow
    AND.w #!C2Scene_PxTileRowMask
    ASL A
    ASL A                       ; tile row * 32 words
    ADC.b !C2Scene_ScrollVramMap
    STA.b !C2Scene_EdgeCol
    CLC
    ADC.w #!Bg_ScreenWords
    STA.b !C2Scene_EdgeRow
    SEP #$30
    INC.w !C2Scene_VramQLock
    LDX.w !C2Scene_VramQEnd
    LDA.b #!Bank7E
    STA.w C2Scene_VramQ.Bank,X
    STA.w C2Scene_VramQ[1].Bank,X
    LDA.b #!VMAIN_IncAfterHigh
    STA.w C2Scene_VramQ.Vmain,X
    STA.w C2Scene_VramQ[1].Vmain,X
    REP #$20
    LDA.w #!C2Scene_RowBufHalf
    STA.w C2Scene_VramQ.Size,X
    STA.w C2Scene_VramQ[1].Size,X
    LDA.w !C2Scene_VramQBufPtr
    STA.w C2Scene_VramQ.Src,X
    CLC
    ADC.w #!C2Scene_RowBufHalf
    STA.w C2Scene_VramQ[1].Src,X
    LDA.b !C2Scene_EdgeCol
    STA.w C2Scene_VramQ.Dest,X
    LDA.b !C2Scene_EdgeRow
    STA.w C2Scene_VramQ[1].Dest,X
    SEP #$20
    TXA
    CLC
    ADC.b #(2*!C2Scene_VramQEntrySize)
    STA.w !C2Scene_VramQEnd
    STZ.w !C2Scene_VramQLock
    REP #$30
    CLC
    LDA.w !C2Scene_VramQBufPtr
    ADC.w #2*!C2Scene_RowBufHalf
    STA.w !C2Scene_VramQBufPtr
    RTS

; ============================================================
; Scene BG layer redraw ($C2:09C5–$C2:0B52)
; ============================================================
; A BG layer's tilemap is built from 16x16 metatiles: the layer's map
; (C2Scene_LayerMaps) holds a metatile number per cell, and each
; metatile (C2Scene_LayerMetatiles) is four tile words. A redraw builds
; the tilemap column by column in the buffer at C2Scene_VramQBufPtr and
; DMAs each column to VRAM straight away, so it needs forced blank or
; vblank (its callers are the scene setup, under forced blank, and
; script op C2Script_DrawLayer at $C2:1950).

; $C2:09C5 — C2Scene_DrawBgLayer (167 bytes, $09C5–$0A6B)
; Redraws the visible part of BG layer C2Scene_DrawLayer (1 or 2; the
; value is taken AND C2Scene_LayerMask) from the layer's tile position
; C2Scene_BgTileX/Y (word (layer - 1)):
; - the layer's scroll shadows (C2Scene_Bg1HScroll/VScroll + 2 * (layer -
;   1)) = the tile position * 8;
; - starting at the metatile that holds the left edge of the screen, or
;   the one before it when the edge is on a metatile boundary (the X
;   tile is even), and likewise for the top edge, it draws
;   C2Scene_DrawCols columns of C2Scene_DrawRows metatiles
;   (C2Scene_BuildBgColumn, C2Scene_UploadBgColumn), wrapping at the
;   map's 96 columns and 64 rows and at the tilemap's 64 x 32 tiles.
; Quirks, kept: a layer number of 0 (or 4, 8, ...) ends in an endless
; loop (.hang). Layer 3 would read its X from C2Scene_BgTileY's first word
; and its Y from dp $EB, past C2Scene_BgTileY, and its table entries do
; not fit the BG3 layout (see C2Scene_LayerVramMaps); no known caller
; passes 3 (C2Scene_LoadScene and C2Scene_ReloadScene pass 1 and 2;
; C2Script_DrawLayer passes a script byte).
; Callers (5 sites: 4 JSR, 1 JMP): C2Script_DrawLayer (JSR $C2:1950), C2Scene_LoadScene (JSR
;   $C2:2C81, JSR $C2:2C88) and C2Scene_ReloadScene (JSR $C2:2CB7, JMP $C2:2CBE).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (direct-page work area;
;        TDC for 0), DB any (set to $7E for the buffers and restored);
;        C2Tmp_00 = the layer; forced blank or vblank (VRAM DMA)
; Exit:  M=1, X=0, DB restored; A, X, Y clobbered; C2Tmp_00-$1B changed
;        (C2Tmp_00 = 0); the layer's scroll shadows set; DMA channel 7
;        registers changed
; Calls: C2Scene_BuildBgColumn, C2Scene_UploadBgColumn.
!C2Scene_DrawLayer = !C2Tmp_00          ; in: the layer, 1-3 (C2Scene_BuildBgColumn reuses it)
!C2Scene_DrawColsLeft = !C2Tmp_02       ; 16-bit columns still to draw
!C2Scene_DrawMapRowOfs = !C2Tmp_04      ; 16-bit map byte offset of the current row (row * 96)
!C2Scene_DrawBufPos = !C2Tmp_06         ; 16-bit byte offset in the column buffer
!C2Scene_DrawMapCol = !C2Tmp_08         ; 16-bit map column 0-95
!C2Scene_DrawMapRow = !C2Tmp_0A         ; 16-bit map row 0-63 of the top metatile
!C2Scene_DrawColX = !C2Tmp_0C           ; 16-bit BG pixel X of the column (wraps at 512)
!C2Scene_DrawColY = !C2Tmp_0E           ; 16-bit BG pixel Y of the top metatile (wraps at 256)
!C2Scene_DrawVramMap = !C2Tmp_10        ; 16-bit VRAM word address of the layer's tilemap
!C2Scene_DrawVramCol = !C2Tmp_12        ; 16-bit VRAM word address of the column
!C2Scene_DrawMetatiles = !C2Tmp_14      ; 16-bit address (bank $7E) of the layer's metatiles
!C2Scene_DrawMap = !C2Tmp_16            ; 16-bit address (bank $7E) of the layer's map
!C2Scene_DrawMapColPtr = !C2Tmp_18      ; 16-bit: the map + the column (row 0)
!C2Scene_DrawRow64 = !C2Tmp_1A          ; 16-bit: row * 64, on the way to row * 96
org $C209C5
C2Scene_DrawBgLayer:
    SEP #$20
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDA.b !C2Scene_DrawLayer
    AND.w #!C2Scene_LayerMask
    BNE .layer
    JMP .hang
.layer:
    DEC A
    ASL A
    TAX                         ; X = (layer - 1) * 2
    LDA.b !C2Scene_BgTileX,X
    ASL A
    ASL A
    ASL A
    STA.b !C2Scene_Bg1HScroll,X
    LDA.b !C2Scene_BgTileY,X
    ASL A
    ASL A
    ASL A
    STA.b !C2Scene_Bg1VScroll,X
    LDA.l C2Scene_LayerMetatiles,X
    STA.b !C2Scene_DrawMetatiles
    LDA.l C2Scene_LayerMaps,X
    STA.b !C2Scene_DrawMap
    LDA.l C2Scene_LayerVramMaps,X
    STA.b !C2Scene_DrawVramMap
    LDA.b !C2Scene_BgTileX,X    ; first column: the metatile under the edge,
    LSR A                       ; or the one before when the tile X is even
    BCS .col_set
    DEC A
    BPL .col_set
    LDA.w #!C2Scene_MapCols-1
.col_set:
    STA.b !C2Scene_DrawMapCol
    LDA.b !C2Scene_BgTileY,X
    LSR A
    BCS .row_set
    DEC A
    BPL .row_set
    LDA.w #!C2Scene_MapRows-1
.row_set:
    STA.b !C2Scene_DrawMapRow
    LDA.b !C2Scene_Bg1HScroll,X ; the same columns in pixels
    BIT.w #!C2Scene_TilePx
    BEQ .x_even
    SEC
    SBC.w #!C2Scene_TilePx
    BRA .x_set
.x_even:
    SEC
    SBC.w #!C2Scene_MetatilePx
.x_set:
    AND.w #!C2Scene_BgXMask
    STA.b !C2Scene_DrawColX
    LDA.b !C2Scene_Bg1VScroll,X
    BIT.w #!C2Scene_TilePx
    BEQ .y_even
    SEC
    SBC.w #!C2Scene_TilePx
    BRA .y_set
.y_even:
    SEC
    SBC.w #!C2Scene_MetatilePx
.y_set:
    AND.w #!C2Scene_BgYMask
    STA.b !C2Scene_DrawColY
    LDA.w #!C2Scene_DrawCols
    STA.b !C2Scene_DrawColsLeft
.column:
    JSR C2Scene_BuildBgColumn
    JSR C2Scene_UploadBgColumn
    LDA.b !C2Scene_DrawMapCol
    INC A
    CMP.w #!C2Scene_MapCols
    BCC .next_col
    TDC                         ; A = DP = 0: wrap to column 0
.next_col:
    STA.b !C2Scene_DrawMapCol
    LDA.b !C2Scene_DrawColX
    CLC
    ADC.w #!C2Scene_MetatilePx
    AND.w #!C2Scene_BgXMask
    STA.b !C2Scene_DrawColX
    DEC.b !C2Scene_DrawColsLeft
    BNE .column
    SEP #$20
    PLB
    RTS
.hang:
    BRA .hang

; $C2:0A6C — C2Scene_BuildBgColumn (66 bytes, $0A6C–$0AAD)
; Builds one tilemap column pair (two tile columns of 32 words) in the
; buffer at C2Scene_VramQBufPtr: C2Scene_DrawRows metatiles of map column
; C2Scene_DrawMapCol from row C2Scene_DrawMapRow down (wrapping at 64
; rows), each put by C2Scene_DrawMetatile at the buffer row that its
; screen Y (C2Scene_DrawColY) falls on, wrapping at 32 tiles.
; Callers (1 JSR site): C2Scene_DrawBgLayer ($C2:0A46).
; Entry: M=0, X=0, DP=$0000 (TDC for 0), DB=$7E; C2Scene_DrawMapCol,
;        C2Scene_DrawMapRow, C2Scene_DrawColY, C2Scene_DrawMap and
;        C2Scene_DrawMetatiles set (C2Scene_DrawBgLayer)
; Exit:  M=0, X=0; A, X, Y clobbered; C2Tmp_00 (the row count, here
;        C2Scene_DrawLayer's slot) = 0; C2Tmp_04, $06, $18 and $1A changed
; Calls: C2Scene_DrawMetatile.
!C2Scene_DrawRowsLeft = !C2Tmp_00       ; 16-bit metatiles still to draw in the column
C2Scene_BuildBgColumn:
    LDA.w #!C2Scene_DrawRows
    STA.b !C2Scene_DrawRowsLeft
    LDA.b !C2Scene_DrawMapCol
    CLC
    ADC.b !C2Scene_DrawMap
    STA.b !C2Scene_DrawMapColPtr
    LDA.b !C2Scene_DrawMapRow
    XBA                         ; row * 256
    LSR A
    LSR A
    STA.b !C2Scene_DrawRow64    ; row * 64
    LSR A                       ; row * 32 (C = 0: bit 0 of row * 64)
    ADC.b !C2Scene_DrawRow64
    STA.b !C2Scene_DrawMapRowOfs ; row * 96: C2Scene_MapCols bytes per row
    LDA.b !C2Scene_DrawColY
    AND.w #!C2Scene_PxMetaRowMask
    LSR A
    LSR A                       ; metatile row on the tilemap * 4
    STA.b !C2Scene_DrawBufPos
.row:
    JSR C2Scene_DrawMetatile
    LDA.b !C2Scene_DrawMapRowOfs
    CLC
    ADC.w #!C2Scene_MapCols
    CMP.w #!C2Scene_MapBytes
    BCC .next_row
    TDC                         ; A = DP = 0: wrap to row 0
.next_row:
    STA.b !C2Scene_DrawMapRowOfs
    LDA.b !C2Scene_DrawBufPos
    CLC
    ADC.w #!C2Scene_ColRowStep
    AND.w #!C2Scene_ColBufMask
    STA.b !C2Scene_DrawBufPos
    DEC.b !C2Scene_DrawRowsLeft
    BNE .row
    RTS

; $C2:0AAE — C2Scene_DrawMetatile (46 bytes, $0AAE–$0ADB)
; Puts one metatile into the column buffer: the map byte at
; C2Scene_DrawMapColPtr + C2Scene_DrawMapRowOfs selects an 8-byte
; C2Scene_Metatile record; its .TopLeft and .BottomLeft go to the left
; tile column (buffer + C2Scene_DrawBufPos, + 2) and .TopRight and
; .BottomRight to the right one (+ C2Scene_ColBufHalf, + 2). The
; pointers are 16-bit, so both the map and the buffer are read in bank
; DB ($7E).
; Callers (1 JSR site): C2Scene_BuildBgColumn ($C2:0A8D).
; Entry: M=0, X=0, DP=$0000, DB=$7E; set up as C2Scene_BuildBgColumn
;        leaves it
; Exit:  M=0, X=0; A = .BottomRight; X = the metatile's address; Y =
;        C2Scene_DrawBufPos + C2Scene_ColBufHalf + 2
; No calls.
C2Scene_DrawMetatile:
    LDY.b !C2Scene_DrawMapRowOfs
    LDA.b (!C2Scene_DrawMapColPtr),Y
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A                       ; * 8 bytes per metatile (C = 0)
    ADC.b !C2Scene_DrawMetatiles
    TAX
    LDY.b !C2Scene_DrawBufPos
    LDA.w C2Scene_Metatile.TopLeft,X
    STA.b (!C2Scene_VramQBufPtr),Y
    INY
    INY
    LDA.w C2Scene_Metatile.BottomLeft,X
    STA.b (!C2Scene_VramQBufPtr),Y
    TYA
    CLC
    ADC.w #!C2Scene_ColBufHalf-2
    TAY
    LDA.w C2Scene_Metatile.TopRight,X
    STA.b (!C2Scene_VramQBufPtr),Y
    INY
    INY
    LDA.w C2Scene_Metatile.BottomRight,X
    STA.b (!C2Scene_VramQBufPtr),Y
    RTS

; $C2:0ADC — C2Scene_UploadBgColumn (119 bytes, $0ADC–$0B52)
; DMAs the two tile columns built by C2Scene_BuildBgColumn to VRAM on
; channel 7, with VMAIN stepping 32 words (one tilemap row) per word: the
; left column to tile column C2Scene_DrawColX / 8 of the layer's tilemap
; (C2Scene_DrawVramMap; columns 32-63 are in the second 32x32 screen,
; $400 words on) and the right column to the next word address.
; Quirk, kept: the second column's bank is stored with 16-bit A, so the
; byte after the pointer (dp $E3, C2Scene_BgTileX's low byte) also goes to
; DAS7L; the count is written again right after.
; Callers (1 JSR site): C2Scene_DrawBgLayer ($C2:0A49).
; Entry: M=0, X=0, DP=$0000 (TDC for 0), DB any (saved; $00 for the
;        registers); forced blank or vblank
; Exit:  M=0, X=0, DB unchanged; A clobbered, X = C2Scene_ColBufHalf; Y
;        unchanged; C2Scene_DrawVramCol set; DMA channel 7 registers
;        changed
; No calls.
C2Scene_UploadBgColumn:
    LDA.b !C2Scene_DrawColX
    LSR A
    LSR A
    LSR A                       ; tile column 0-63
    CMP.w #!C2Scene_MapScreenCols
    BCC .left_screen
    CLC
    ADC.w #!C2Scene_MapScreen2Skip
.left_screen:
    CLC
    ADC.b !C2Scene_DrawVramMap
    STA.b !C2Scene_DrawVramCol
    TAX
    SEP #$20
    PHB
    TDC                         ; A = DP = 0
    PHA
    PLB
    STX.w VMADDL
    LDA.b #!VMAIN_IncAfterHigh|VRAM_INC_32
    STA.w VMAIN
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.b !C2Scene_VramQBufPtr
    STX.w A1T7L
    LDA.b !C2Scene_VramQBufPtr+2
    STA.w A1B7
    LDX.w #!C2Scene_ColBufHalf
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    REP #$20
    LDA.b !C2Scene_DrawVramCol
    INC A
    STA.w VMADDL
    LDA.b !C2Scene_VramQBufPtr
    CLC
    ADC.w #!C2Scene_ColBufHalf
    STA.w A1T7L
    LDA.b !C2Scene_VramQBufPtr+2
    STA.w A1B7                  ; 16-bit: DAS7L's low byte too (rewritten below)
    SEP #$20
    LDA.b #!VMAIN_IncAfterHigh|VRAM_INC_32
    STA.w VMAIN
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C2Scene_ColBufHalf
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    REP #$20
    PLB
    RTS


; ============================================================
; Scene sprite list ($C2:0B53–$C2:0E1C)
; ============================================================
; Sprites are drawn from a doubly linked list of 64 16-byte nodes
; (C2Scene_SprNode at C2Scene_SprNodes, bank $7E). Every frame the NMI
; puts all nodes back on the free list (C2Scene_SprResetLists), the
; tasks add what they show (C2Scene_SprAdd), and C2Scene_SprDrawList
; turns the active list into OAM entries, first node first.

org $C20B53
; $C2:0B53 — C2Scene_SprAdd (163 bytes, $0B53–$0BF5)
; Takes the first node off the free list and fills it from the running
; task (C2Scene_TaskCur): .X = .SprX, .Y = .SprY, .Tile = .SprTile, .Attr
; = .SprAttr, .Frame = C2Scene_SprFramePtr. Then links it into the active
; list (C2Scene_SprActiveHead):
; - .Attr bit 0 (C2Scene_SprAttrFront): after the front nodes already
;   there, so these stay first, in the order added;
; - else .Tile bit 15 (high byte bit 7): at the end;
; - else after the front nodes, before the first node whose .Y is
;   smaller than its own, so the larger .Y is drawn first (on top).
; Quirk, kept: there is no check that the free list is empty; a 65th
; node in one frame would unlink the free head itself.
; Callers (1 JSR site): C2Anim_OpShowFrame ($C2:0ED6).
; Entry: M any (SEP #$20 here), X=0, DP=$0000, DB any (set to $7E and
;        restored); C2Scene_SprFramePtr = the frame
; Exit:  M=0 (16-bit A: the REP #$20 before the insert is never undone),
;        X=0; X = the new node, Y = the node after it, A = X; DP and DB
;        unchanged
; No calls.
C2Scene_SprAdd:
    SEP #$20
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDY.w #!C2Scene_SprFreeHead
    LDX.w C2Scene_SprNode.Next,Y    ; X = first free node
    LDY.w C2Scene_SprNode.Prev,X    ; unlink it
    LDA.w C2Scene_SprNode.Next,X
    STA.w C2Scene_SprNode.Next,Y
    TAY
    LDA.w C2Scene_SprNode.Prev,X
    STA.w C2Scene_SprNode.Prev,Y
    LDY.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,Y
    STA.w C2Scene_SprNode.X,X
    LDA.w C2Scene_Task.SprY,Y
    STA.w C2Scene_SprNode.Y,X
    LDA.b !C2Scene_SprFramePtr
    STA.w C2Scene_SprNode.Frame,X
    LDA.w C2Scene_Task.SprTile,Y
    STA.w C2Scene_SprNode.Tile,X
    SEP #$20
    LDA.b !C2Scene_SprFramePtr+2
    STA.w C2Scene_SprNode.Frame+2,X
    LDA.w C2Scene_Task.SprAttr,Y
    STA.w C2Scene_SprNode.Attr,X
    LDY.w #!C2Scene_SprActiveHead
    LDA.w C2Scene_SprNode.Attr,X
    BIT.b #!C2Scene_SprAttrFront
    BEQ .sorted
    REP #$20
.skip_front:
    LDA.w C2Scene_SprNode.Next,Y
    TAY
    CPY.w #!C2Scene_SprActiveHead
    BEQ .insert
    LDA.w C2Scene_SprNode.Attr,Y
    BIT.w #!C2Scene_SprAttrFront
    BNE .skip_front
    BRA .insert
.sorted:
    LDA.w C2Scene_SprNode.Tile+1,X
    REP #$20
    BMI .insert                 ; .Tile bit 15: before the head, i.e. last
.find:
    LDA.w C2Scene_SprNode.Next,Y
    TAY
    CPY.w #!C2Scene_SprActiveHead
    BEQ .insert
    LDA.w C2Scene_SprNode.Attr,Y
    BIT.w #!C2Scene_SprAttrFront
    BNE .find
    LDA.w C2Scene_SprNode.Y,X
    CMP.w C2Scene_SprNode.Y,Y
    BEQ .find
    BCC .find
.insert:
    ; link X in before Y: after Y's .Prev
    LDA.w C2Scene_SprNode.Prev,Y
    TAY
    LDA.w C2Scene_SprNode.Next,Y
    STA.w C2Scene_SprNode.Next,X
    TXA
    STA.w C2Scene_SprNode.Next,Y
    LDY.w C2Scene_SprNode.Next,X
    LDA.w C2Scene_SprNode.Prev,Y
    STA.w C2Scene_SprNode.Prev,X
    TXA
    STA.w C2Scene_SprNode.Prev,Y
    PLB
    RTS

; $C2:0BF6 — C2Scene_SprInitLinks (87 bytes, $0BF6–$0C4C)
; Builds C2Scene_SprLinkInit, the .Prev/.Next pair of each node on a free
; list in address order: node 0's .Prev is C2Scene_SprFreeHead, node n's
; .Prev is node n-1 and its .Next node n+1, and node 63's .Next is
; C2Scene_SprFreeHead again. C2Scene_SprResetLists copies it into the
; nodes every frame.
; Callers (1 JSR site): C2Scene_Main ($C2:23AE).
; Entry: M=1 (8-bit bank push), X=0, DP=$0000, DB any (set to $7E and
;        restored)
; Exit:  M=0 (16-bit A; not restored), X=0; X = the address of entry
;        63's .Next, Y = 0, A = C2Scene_SprFreeHead; C2Tmp_08 changed; DP
;        and DB unchanged
; No calls.
!C2Scene_LinkNode = !C2Tmp_08
C2Scene_SprInitLinks:
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDX.w #!C2Scene_SprLinkInit
    LDA.w #!C2Scene_SprFreeHead
    STA.w C2Scene_SprNode.Prev,X
    INX
    INX
    INX
    INX
    LDA.w #!C2Scene_SprNodes
    STA.b !C2Scene_LinkNode
    LDY.w #!C2Scene_SprNodeCount-1
.prev:
    LDA.b !C2Scene_LinkNode
    STA.w C2Scene_SprNode.Prev,X
    INX
    INX
    INX
    INX
    CLC
    LDA.b !C2Scene_LinkNode
    ADC.w #!C2Scene_SprNodeSize
    STA.b !C2Scene_LinkNode
    DEY
    BNE .prev
    LDX.w #!C2Scene_SprLinkInit+2
    LDA.w #!C2Scene_SprNodes+!C2Scene_SprNodeSize
    STA.b !C2Scene_LinkNode
    LDY.w #!C2Scene_SprNodeCount-1
.next:
    LDA.b !C2Scene_LinkNode
    STA.w C2Scene_SprNode.Prev,X    ; X is 2 past the entry: its .Next
    INX
    INX
    INX
    INX
    CLC
    LDA.b !C2Scene_LinkNode
    ADC.w #!C2Scene_SprNodeSize
    STA.b !C2Scene_LinkNode
    DEY
    BNE .next
    LDA.w #!C2Scene_SprFreeHead
    STA.w C2Scene_SprNode.Prev,X
    PLB
    RTS

; $C2:0C4D — C2Scene_SprResetLists (157 bytes, $0C4D–$0CE9)
; Empties the sprite list for the new frame (from the NMI): the active
; head points at itself, the free head at node 0 (.Next) and node 63
; (.Prev), and every node gets its .Prev/.Next back from
; C2Scene_SprLinkInit (8 passes of 8 nodes, unrolled). The rest of each
; node is left as it was.
; Callers (1 JSR site): C2Scene_NmiHandler ($C2:032B).
; Entry: M=1 (8-bit bank push), X=0, DP=$0000, DB any (set to $7E and
;        restored)
; Exit:  M=0 (16-bit A; the NMI's next STZ.b C2Scene_OamNext is then a
;        16-bit store), X=0; X, Y past the copied ranges, A = Y;
;        C2Tmp_08 = 0; DP and DB unchanged
; No calls.
!C2Scene_ResetPasses = !C2Tmp_08
C2Scene_SprResetLists:
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDX.w #!C2Scene_SprActiveHead
    TXA
    STA.w C2Scene_SprNode.Prev,X
    STA.w C2Scene_SprNode.Next,X
    LDX.w #!C2Scene_SprFreeHead
    LDA.w #!C2Scene_SprNodes+((!C2Scene_SprNodeCount-1)*!C2Scene_SprNodeSize)
    STA.w C2Scene_SprNode.Prev,X
    LDA.w #!C2Scene_SprNodes
    STA.w C2Scene_SprNode.Next,X
    LDX.w #!C2Scene_SprLinkInit
    LDY.w #!C2Scene_SprNodes
    LDA.w #!C2Scene_SprNodeCount/!C2Scene_SprResetGroup
    STA.b !C2Scene_ResetPasses
.pass:
    LDA.w C2Scene_SprNode[0].Prev,X
    STA.w C2Scene_SprNode[0].Prev,Y
    LDA.w C2Scene_SprNode[0].Next,X
    STA.w C2Scene_SprNode[0].Next,Y
    LDA.w C2Scene_SprNode[0].Prev+(1*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[1].Prev,Y
    LDA.w C2Scene_SprNode[0].Next+(1*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[1].Next,Y
    LDA.w C2Scene_SprNode[0].Prev+(2*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[2].Prev,Y
    LDA.w C2Scene_SprNode[0].Next+(2*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[2].Next,Y
    LDA.w C2Scene_SprNode[0].Prev+(3*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[3].Prev,Y
    LDA.w C2Scene_SprNode[0].Next+(3*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[3].Next,Y
    LDA.w C2Scene_SprNode[0].Prev+(4*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[4].Prev,Y
    LDA.w C2Scene_SprNode[0].Next+(4*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[4].Next,Y
    LDA.w C2Scene_SprNode[0].Prev+(5*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[5].Prev,Y
    LDA.w C2Scene_SprNode[0].Next+(5*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[5].Next,Y
    LDA.w C2Scene_SprNode[0].Prev+(6*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[6].Prev,Y
    LDA.w C2Scene_SprNode[0].Next+(6*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[6].Next,Y
    LDA.w C2Scene_SprNode[0].Prev+(7*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[7].Prev,Y
    LDA.w C2Scene_SprNode[0].Next+(7*!C2Scene_SprLinkSize),X
    STA.w C2Scene_SprNode[7].Next,Y
    TXA
    CLC
    ADC.w #(!C2Scene_SprResetGroup*!C2Scene_SprLinkSize)
    TAX
    TYA
    CLC
    ADC.w #(!C2Scene_SprResetGroup*!C2Scene_SprNodeSize)
    TAY
    DEC.b !C2Scene_ResetPasses
    BNE .pass
    PLB
    RTS

; $C2:0CEA — C2Scene_SprDrawList (30 bytes, $0CEA–$0D07)
; Draws the active sprite list (from the NMI, after the tasks): calls
; C2Scene_SprDrawNode for each node from C2Scene_SprActiveHead's .Next
; until the walk comes back to the head.
; Callers (1 JSR site): C2Scene_NmiHandler ($C2:0336).
; Entry: M=1 (8-bit bank push), X=0, DP=$0000, DB any (set to $7E and
;        restored); C2Scene_OamNext = the first OAM slot to fill
; Exit:  M=1, X=0; X = C2Scene_SprActiveHead, Y = the last node (or the
;        head); A, C2Tmp_10 and the rest as C2Scene_SprDrawNode leaves
;        them; DP and DB unchanged
; Calls: C2Scene_SprDrawNode.
!C2Scene_DrawCur = !C2Tmp_10
C2Scene_SprDrawList:
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    LDY.w #!C2Scene_SprActiveHead
    LDX.w C2Scene_SprNode.Next,Y
.node:
    CPX.w #!C2Scene_SprActiveHead
    BEQ .done
    STX.b !C2Scene_DrawCur
    JSR C2Scene_SprDrawNode
    LDY.b !C2Scene_DrawCur
    LDX.w C2Scene_SprNode.Next,Y
    BRA .node
.done:
    PLB
    RTS

; $C2:0D08 — C2Scene_SprDrawNode (261 bytes, $0D08–$0E0C)
; Writes the OAM entries of one sprite-list node X. Its frame
; (.Frame) is a count byte, then that many 4-byte pieces: signed X and Y
; offsets (one byte each) and a tile word. For each piece: position =
; the node's .X/.Y (minus the BG2 scroll, wrapped into -$300..$2FF and
; -$200..$1FF, when .Attr has C2Scene_SprAttrScroll) + the offsets; a
; piece with X outside -15..255 or Y outside -15..223 is skipped. Else
; OAM slot C2Scene_OamNext (low 7 bits) gets X and Y (low bytes) and the
; tile word + .Tile bits 0-13, ORed with .Attr bits 1-5 (palette and
; priority); its high-table bits get X bit 8 and the size
; (C2Scene_SprTileLarge), through C2Scene_OamHiBitsTable; and
; C2Scene_OamNext goes up by one.
; Quirks, kept: the count is checked only after a piece, so a count of 0
; would run 65536 pieces; the high-table byte is C2Scene_OamNext / 4
; without the 7-bit mask, so past 128 sprites in one frame it would OR
; bits into the bytes after Oam_HighTable (C2Scene_PaletteBuf); the INC
; of C2Scene_OamNext is 16-bit (M=0), so it also carries into
; C2Scene_TaskCur.
; Callers (1 JSR site): C2Scene_SprDrawList ($C2:0CFC).
; Entry: M=1, X=0 with X = the node, DP=$0000, DB=$7E (the node and the
;        OAM shadow are read and written absolute)
; Exit:  M=1, X=0; A, X, Y clobbered; C2Tmp_00-$16 and
;        C2Scene_SprFramePtr changed; DP and DB unchanged
; No calls.
!C2Scene_PieceCount = !C2Tmp_00     ; 16-bit (high byte 0)
!C2Scene_PieceAttr = !C2Tmp_02      ; 16-bit: .Attr bits 1-5 at OAM bits 9-13
!C2Scene_PieceX = !C2Tmp_04         ; 16-bit piece X
!C2Scene_PieceXHi = !C2Tmp_05       ; its high byte: bit 0 = X bit 8
!C2Scene_PieceTile = !C2Tmp_06      ; 16-bit .Tile bits 0-13
!C2Scene_PieceXY = !C2Tmp_08        ; piece X low byte, then (C2Tmp_09) Y low byte
!C2Scene_NodeX = !C2Tmp_0C          ; 16-bit node X on screen
!C2Scene_NodeY = !C2Tmp_0E          ; 16-bit node Y on screen
!C2Scene_PieceSize = !C2Tmp_13      ; 0 or 1: the OAM size bit
!C2Scene_PieceSizeTmp = !C2Tmp_16   ; copy of it shifted out for the table index
C2Scene_SprDrawNode:
    LDY.w C2Scene_SprNode.Frame,X
    STY.b !C2Scene_SprFramePtr
    LDA.w C2Scene_SprNode.Frame+2,X
    STA.b !C2Scene_SprFramePtr+2
    LDA.b [!C2Scene_SprFramePtr]
    STA.b !C2Scene_PieceCount
    STZ.b !C2Scene_PieceCount+1
    LDY.w #$0000
    LDA.w C2Scene_SprNode.Tile+1,X
    BIT.b #!C2Scene_SprTileLarge
    BEQ .small
    INY
.small:
    STY.b !C2Scene_PieceSize
    REP #$20
    INC.b !C2Scene_SprFramePtr  ; past the count byte
    LDA.w C2Scene_SprNode.Attr,X
    XBA
    AND.w #!C2Scene_SprAttrOamMask
    STA.b !C2Scene_PieceAttr
    LDA.w C2Scene_SprNode.Tile,X
    AND.w #!C2Scene_SprTileMask
    STA.b !C2Scene_PieceTile
    LDA.w C2Scene_SprNode.X,X
    STA.b !C2Scene_NodeX
    LDA.w C2Scene_SprNode.Y,X
    STA.b !C2Scene_NodeY
    LDA.w C2Scene_SprNode.Attr,X
    BIT.w #!C2Scene_SprAttrScroll
    BEQ .piece
    SEC
    LDA.b !C2Scene_NodeX
    SBC.b !C2Scene_Bg2HScroll
    BPL .x_positive
    CMP.w #-(!C2Scene_SprWrapW/2)
    BCS .x_done
    ADC.w #!C2Scene_SprWrapW
    BRA .x_done
.x_positive:
    CMP.w #(!C2Scene_SprWrapW/2)
    BCC .x_done
    SBC.w #!C2Scene_SprWrapW
.x_done:
    STA.b !C2Scene_NodeX
    SEC
    LDA.b !C2Scene_NodeY
    SBC.b !C2Scene_Bg2VScroll
    BPL .y_positive
    CMP.w #-(!C2Scene_SprWrapH/2)
    BCS .y_done
    ADC.w #!C2Scene_SprWrapH
    BRA .y_done
.y_positive:
    CMP.w #(!C2Scene_SprWrapH/2)
    BCC .y_done
    SBC.w #!C2Scene_SprWrapH
.y_done:
    STA.b !C2Scene_NodeY
.piece:
    LDA.b [!C2Scene_SprFramePtr]    ; signed X offset
    AND.w #!Eng_LowByteMask
    BIT.w #!C2Scene_ByteSignBit
    BEQ .dx_positive
    ORA.w #!Eng_HighByteMask
.dx_positive:
    CLC
    ADC.b !C2Scene_NodeX
    STA.b !C2Scene_PieceXY
    STA.b !C2Scene_PieceX
    CLC
    ADC.w #!C2Scene_SprClipMargin
    CMP.w #!C2Scene_SprClipW
    BCS .next_piece
    LDY.w #1
    LDA.b [!C2Scene_SprFramePtr],Y  ; signed Y offset
    AND.w #!Eng_LowByteMask
    BIT.w #!C2Scene_ByteSignBit
    BEQ .dy_positive
    ORA.w #!Eng_HighByteMask
.dy_positive:
    CLC
    ADC.b !C2Scene_NodeY
    STA.b !C2Scene_PieceXY+1
    CLC
    ADC.w #!C2Scene_SprClipMargin
    CMP.w #!C2Scene_SprClipH
    BCS .next_piece
    INY
    LDA.b [!C2Scene_SprFramePtr],Y  ; tile word
    CLC
    ADC.b !C2Scene_PieceTile
    ORA.b !C2Scene_PieceAttr
    TAY
    LDA.b !C2Scene_OamNext
    AND.w #!C2Scene_OamSlotMask
    ASL A
    ASL A
    TAX
    LDA.b !C2Scene_PieceXY
    STA.w !Oam_LowTable,X
    TYA
    STA.w !Oam_LowTable+2,X
    SEP #$30
    LDA.b !C2Scene_PieceSize
    STA.b !C2Scene_PieceSizeTmp
    LDA.b !C2Scene_OamNext
    AND.b #3
    LSR.b !C2Scene_PieceSizeTmp
    ROL A
    LSR.b !C2Scene_PieceXHi
    ROL A
    TAX                         ; (slot AND 3) * 4 + size * 2 + X bit 8
    LDA.b !C2Scene_OamNext
    LSR A
    LSR A
    TAY
    LDA.l C2Scene_OamHiBitsTable,X
    ORA.w !Oam_HighTable,Y
    STA.w !Oam_HighTable,Y
    REP #$30
    INC.b !C2Scene_OamNext
.next_piece:
    CLC
    LDA.b !C2Scene_SprFramePtr
    ADC.w #4
    STA.b !C2Scene_SprFramePtr
    DEC.b !C2Scene_PieceCount
    BEQ .done
    JMP .piece
.done:
    SEP #$20
    RTS

; $C2:0E0D — C2Scene_OamHiBitsTable (16 bytes, $0E0D–$0E1C)
; The OAM high-table bits of one sprite, indexed by (slot AND 3) * 4 +
; size * 2 + X bit 8: the 2-bit value size:Xbit8 shifted to the slot's
; place in its byte (C2Scene_SprDrawNode).
C2Scene_OamHiBitsTable:
    db $00,$01,$02,$03
    db $00,$04,$08,$0C
    db $00,$10,$20,$30
    db $00,$40,$80,$C0

; ============================================================
; Scene sprite animation scripts and task motion ($C2:0E1D–$C2:0F62)
; ============================================================
; A task that shows a sprite runs a small byte-code script of its own,
; probably its animation: .AnimPtr/.AnimBank point into it (C2Scene_SetAnim
; starts one from C2SceneRom_AnimTable), and each call of C2Anim_Run carries
; out ops until one of them ends the frame, usually by adding the current
; frame to the sprite list. Each op is an opcode byte and its arguments;
; its handler (C2Anim_OpTable) returns the number of bytes to advance in
; A, or Z=1 to stop for this frame without advancing.

org $C20E1D
; $C2:0E1D — C2Anim_Run (45 bytes, $0E1D–$0E49)
; Runs the running task's animation script (.AnimPtr, .AnimBank) from
; where it stopped: calls the handler of each op from C2Anim_OpTable with
; C2Anim_Ptr on the opcode. A handler that returns Z=0 gives in A the
; bytes to advance, and the next op runs at once; Z=1 ends the call, and
; only then is the pointer stored back in .AnimPtr. The carry the last
; handler returned comes back: C=1 from C2Anim_OpEnd, C=0 from the
; others that stop.
; Inferred to be the sprite's animation from C2Anim_OpShowFrame, which
; adds a frame to the sprite list for a number of frames, and from the
; script ops that start one (C2Scene_SetAnim) before moving the task.
; Callers (58 JSR sites): C2Script_MoveFrames ($C2:1643), C2Script_WaitAnimating ($C2:18AC),
;   C2Script_MoveToX ($C2:19B6), C2Script_MoveToY ($C2:1A1F) and unmatched ($C2:3444, $C2:35E0,
;   $C2:36E2, $C2:3731, $C2:38C0, $C2:3915, $C2:3B3F, $C2:3CD5, $C2:3D36, $C2:3D97, $C2:3E76,
;   $C2:3EDA, $C2:4340, $C2:4382, $C2:43D2, $C2:445C, $C2:447C, $C2:450B, $C2:46B9, $C2:4700,
;   $C2:4723, $C2:481E, $C2:4852, $C2:4870, $C2:4894, $C2:49CA, $C2:4D14, $C2:4D32, $C2:4D3E,
;   $C2:4D96, $C2:4F73, $C2:4FC2, $C2:5008, $C2:5032, $C2:508A, $C2:510B, $C2:516F, $C2:51E8,
;   $C2:523E, $C2:525D, $C2:5285, $C2:5553, $C2:55A2, $C2:55CC, $C2:55E2, $C2:5600, $C2:5770,
;   $C2:6834, $C2:6883, $C2:68DD, $C2:719A, $C2:71A9, $C2:71C7, $C2:71D8).
; Callers note (57 JSR sites, all unmatched except those named): e.g.
;   C2Script_MoveFrames ($C2:1643), C2Script_WaitAnimating ($C2:18AC),
;   C2Script_MoveToX ($C2:19B6), C2Script_MoveToY ($C2:1A1F), $C2:3444,
;   $C2:35E0 and $C2:6834; $C2:4E1B and $C2:55A2 are
;   doubtful byte patterns.
; Entry: M any (SEP #$20 here), X=0, DP=$0000, DB with low WRAM at
;        $0000-$1FFF; C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; A, Y clobbered; C as the last handler
;        left it; C2Anim_Ptr = where the script stopped; whatever the
;        handlers change (C2Scene_SprAdd, the VRAM queue)
; Calls: the C2Anim_OpTable handlers.
C2Anim_Run:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.AnimBank,X
    STA.b !C2Anim_Ptr+2
    REP #$20
    LDA.w C2Scene_Task.AnimPtr,X
    STA.b !C2Anim_Ptr
.op:
    LDA.b [!C2Anim_Ptr]
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    JSR (C2Anim_OpTable,X)
    BEQ .stop
    CLC
    ADC.b !C2Anim_Ptr
    STA.b !C2Anim_Ptr
    BRA .op
.stop:
    LDX.b !C2Scene_TaskCur
    LDA.b !C2Anim_Ptr
    STA.w C2Scene_Task.AnimPtr,X
    SEP #$20
    RTS

; $C2:0E4A — C2Anim_OpTable (8 words, $0E4A–$0E59)
; The handler of each animation opcode 0-7 (C2Anim_Run: JSR (T,X) with
; X = the opcode * 2). There is no range check: a larger opcode would
; jump through the code after the table.
C2Anim_OpTable:
    dw C2Anim_OpClearByte       ; 0
    dw C2Anim_OpIncByte         ; 1
    dw C2Anim_OpDecByte         ; 2
    dw C2Anim_OpJumpBack        ; 3
    dw C2Anim_OpShowFrame       ; 4
    dw C2Anim_OpWait            ; 5
    dw C2Anim_OpQueueVram       ; 6
    dw C2Anim_OpEnd             ; 7

; $C2:0E5A — C2Anim_OpClearByte (17 bytes, $0E5A–$0E6A)
; Animation op 0, 2 bytes: zeroes the task's byte at offset arg 1
; (any of the 64 record bytes, through C2Scene_TaskCur).
; Callers note: none direct (C2Anim_OpTable).
; Entry: as C2Anim_Run calls it: M=0, X=0, DP=$0000, DB with low WRAM
;        at $0000-$1FFF ($00 from the NMI), C2Anim_Ptr on the opcode
; Exit:  M=0, X=0; A = 2 (advance, Z=0); Y = the offset
; No calls.
C2Anim_OpClearByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Anim_Ptr],Y
    TAY
    TDC                         ; A = DP = 0
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #2
    RTS

; $C2:0E6B — C2Anim_OpIncByte (19 bytes, $0E6B–$0E7D)
; Animation op 1, 2 bytes: adds 1 to the task's byte at offset arg 1.
; Callers note: none direct (C2Anim_OpTable).
; Entry/Exit: as C2Anim_OpClearByte
; No calls.
C2Anim_OpIncByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Anim_Ptr],Y
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    INC A
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #2
    RTS

; $C2:0E7E — C2Anim_OpDecByte (19 bytes, $0E7E–$0E90)
; Animation op 2, 2 bytes: subtracts 1 from the task's byte at offset
; arg 1.
; Callers note: none direct (C2Anim_OpTable).
; Entry/Exit: as C2Anim_OpClearByte
; No calls.
C2Anim_OpDecByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Anim_Ptr],Y
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    DEC A
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #2
    RTS

; $C2:0E91 — C2Anim_OpJumpBack (18 bytes, $0E91–$0EA2)
; Animation op 3, 2 bytes: moves the script by the signed byte arg 1,
; counted from the opcode: A = the offset sign-extended.
; Quirk, kept: only a negative offset works. For 0-$7F the BIT leaves
; Z=1 and the ORA that would clear it is skipped, so C2Anim_Run stops
; for this frame without moving, and the same op stops it again every
; frame after: the script stays there for good. So it is a loop back
; (the name says so).
; Callers note: none direct (C2Anim_OpTable).
; Entry: as C2Anim_OpClearByte
; Exit:  M=0, X=0; A = the offset; C=0; Z=1 when it is 0-$7F; Y = 1
; No calls.
C2Anim_OpJumpBack:
    LDY.w #1
    LDA.b [!C2Anim_Ptr],Y
    AND.w #!Eng_LowByteMask
    BIT.w #!C2Scene_ByteSignBit
    BEQ .positive
    ORA.w #!Eng_HighByteMask
.positive:
    CLC
    RTS

; $C2:0EA3 — C2Anim_OpShowFrame (57 bytes, $0EA3–$0EDB)
; Animation op 4, 4 bytes: shows the sprite frame at arg 1-2 (an
; address in the script's bank) for arg 3 frames. Each call adds that
; frame to the sprite list (C2Scene_SprAdd: the task's position, tile
; and attributes) and stops for this frame. .AnimTimer counts: 0 on the
; first call loads it with arg 3; then each call takes 1 off, and when it
; reaches 0 the op advances (4, C=0) without drawing, so the next op
; runs in the same call.
; While .SprAttr has C2Scene_SprAttrHold (bit 6) the timer is neither
; loaded nor counted: the frame is drawn every call and the script holds.
; Quirk, kept: arg 3 = 0 is loaded as 0, so the next call loads it again:
; the frame then stays for good.
; Callers note: none direct (C2Anim_OpTable).
; Entry: as C2Anim_OpClearByte
; Exit:  advance: M=0, X=0, A = 4, C=0; X = the task. Drawn: M=0 (as
;        C2Scene_SprAdd leaves it), X=0, A = 0 (Z=1), C=0; X, Y as
;        C2Scene_SprAdd leaves them; C2Scene_SprFramePtr = the frame
; Calls: C2Scene_SprAdd.
C2Anim_OpShowFrame:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprAttr,X
    BIT.b #!C2Scene_SprAttrHold
    BNE .draw
    LDA.w C2Scene_Task.AnimTimer,X
    BNE .count
    LDY.w #3
    LDA.b [!C2Anim_Ptr],Y
    STA.w C2Scene_Task.AnimTimer,X
    BRA .draw
.count:
    DEC.w C2Scene_Task.AnimTimer,X
    BNE .draw
    REP #$20
    LDA.w #4
    CLC
    RTS
.draw:
    LDA.b !C2Anim_Ptr+2
    STA.b !C2Scene_SprFramePtr+2
    REP #$20
    LDY.w #1
    LDA.b [!C2Anim_Ptr],Y
    STA.b !C2Scene_SprFramePtr
    JSR C2Scene_SprAdd
    TDC                         ; A = 0, Z=1: stop for this frame
    CLC
    RTS

; $C2:0EDC — C2Anim_OpWait (36 bytes, $0EDC–$0EFF)
; Animation op 5, 2 bytes: waits arg 1 calls without drawing, counting
; in .AnimTimer as C2Anim_OpShowFrame does (0 loads it, then -1 per call;
; at 0 it advances 2 at once). Arg 1 = 0 waits for good.
; Callers note: none direct (C2Anim_OpTable).
; Entry: as C2Anim_OpClearByte
; Exit:  M=0, X=0; X = the task; C=0; A = 2 (advance) or 0 (Z=1, wait)
; No calls.
C2Anim_OpWait:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.AnimTimer,X
    BNE .count
    LDY.w #1
    LDA.b [!C2Anim_Ptr],Y
    STA.w C2Scene_Task.AnimTimer,X
    BRA .wait
.count:
    DEC.w C2Scene_Task.AnimTimer,X
    BNE .wait
    REP #$20
    LDA.w #2
    CLC
    RTS
.wait:
    REP #$20
    TDC
    CLC
    RTS

; $C2:0F00 — C2Anim_OpQueueVram (53 bytes, $0F00–$0F34)
; Animation op 6, 8 bytes: adds a VRAM DMA to the queue the NMI flushes
; (C2Scene_VramQ at C2Scene_VramQEnd): .Bank = arg 1, .Src = arg 2-3,
; .Dest = arg 4-5, .Size = arg 6-7, .Vmain = VMAIN_IncAfterHigh; probably
; the frame's tiles. C2Scene_VramQLock is held while the entry is written,
; so a flush in between skips it. Script op $33 (C2Script_QueueVram) is
; the same code for the main script.
; Quirk, kept: no check that the queue has room.
; Callers note: none direct (C2Anim_OpTable).
; Entry: as C2Anim_OpClearByte
; Exit:  M=0, X=0 (REP #$30); A = 8 (advance); X = the entry's offset, Y
;        = 6; C2Scene_VramQEnd + 8; C2Scene_VramQLock = 0
; No calls.
C2Anim_OpQueueVram:
    SEP #$30
    LDX.b !C2Scene_VramQEnd
    INC.b !C2Scene_VramQLock
    LDY.b #1
    LDA.b [!C2Anim_Ptr],Y
    STA.w C2Scene_VramQ.Bank,X
    LDA.b #!VMAIN_IncAfterHigh
    STA.b C2Scene_VramQ.Vmain,X
    REP #$20
    LDY.b #2
    LDA.b [!C2Anim_Ptr],Y
    STA.b C2Scene_VramQ.Src,X
    LDY.b #4
    LDA.b [!C2Anim_Ptr],Y
    STA.b C2Scene_VramQ.Dest,X
    LDY.b #6
    LDA.b [!C2Anim_Ptr],Y
    STA.b C2Scene_VramQ.Size,X
    SEP #$20
    TXA
    CLC
    ADC.b #!C2Scene_VramQEntrySize
    STA.b !C2Scene_VramQEnd
    STZ.b !C2Scene_VramQLock
    REP #$30
    LDA.w #8
    RTS

; $C2:0F35 — C2Anim_OpEnd (3 bytes, $0F35–$0F37)
; Animation op 7: stops (A = 0, Z=1) with C=1 and does not advance, so
; every later call stops here again. A task handler that returns this
; carry ends its task (C2Scene_TaskRunAll); C2Script_MoveFrames and the
; other script ops that call C2Anim_Run drop it.
; Callers note: none direct (C2Anim_OpTable).
; Entry: as C2Anim_OpClearByte
; Exit:  M=0, X=0; A = 0, C=1
; No calls.
C2Anim_OpEnd:
    TDC
    SEC
    RTS

; $C2:0F38 — C2Scene_TaskMove (43 bytes, $0F38–$0F62)
; Moves the running task by its velocity, in 16.16 fixed point:
; .XFrac/.SprX += .XVelFrac/.XVel and .YFrac/.SprY += .YVelFrac/.YVel
; (inferred from the carry chain: the fraction words are added first and
; carry into the whole ones). No wrap here; C2Scene_WrapTaskPos does that.
; Callers (22 JSR sites): C2Script_MoveFrames ($C2:163D), C2Script_ScrollFrames ($C2:167C),
;   C2Script_ScrollLayerFrames ($C2:172B) and unmatched ($C2:36F1, $C2:383B, $C2:38C9, $C2:3D02,
;   $C2:3D63, $C2:3E23, $C2:3E87, $C2:4454, $C2:4679, $C2:4D90, $C2:4F82, $C2:5002, $C2:5166,
;   $C2:5235, $C2:5254, $C2:554D, $C2:55DC, $C2:7734, $C2:7824).
; Callers note (21 JSR sites, all unmatched except those listed): e.g.
;   C2Script_MoveFrames ($C2:163D), C2Script_ScrollFrames ($C2:167C),
;   C2Script_ScrollLayerFrames ($C2:172B), $C2:36F1 and $C2:7824;
;   $C2:46FA and $C2:5254 are doubtful byte patterns.
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB with low WRAM at
;        $0000-$1FFF; C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .SprY; Y unchanged
; No calls.
C2Scene_TaskMove:
    REP #$20
    LDX.b !C2Scene_TaskCur
    CLC
    LDA.w C2Scene_Task.XFrac,X
    ADC.w C2Scene_Task.XVelFrac,X
    STA.w C2Scene_Task.XFrac,X
    LDA.w C2Scene_Task.SprX,X
    ADC.w C2Scene_Task.XVel,X
    STA.w C2Scene_Task.SprX,X
    CLC
    LDA.w C2Scene_Task.YFrac,X
    ADC.w C2Scene_Task.YVelFrac,X
    STA.w C2Scene_Task.YFrac,X
    LDA.w C2Scene_Task.SprY,X
    ADC.w C2Scene_Task.YVel,X
    STA.w C2Scene_Task.SprY,X
    RTS

; ============================================================
; Scene script interpreter ($C2:0F63–$C2:1036)
; ============================================================
; A scene's tasks are driven by byte-code scripts: C2Scene_LoadScene
; starts one on C2Scene_ScriptBuf, and ops start more
; (C2Script_SpawnScript). Each op is an opcode byte and its arguments;
; its handler (C2Script_OpTable, named C2Script_*) runs with
; C2Script_Ptr on the opcode and returns, like the animation ops
; (C2Anim_Run), Z=0 with the bytes to advance in A, or Z=1 to stop for
; this frame and run the same op again next frame. That is how the waits
; work: a timed op counts in .ScriptWait, and a conditional branch whose
; offset is 0 waits until its condition fails. C=1 from a handler ends
; the task when C2Scene_TaskRunScript is its handler.

org $C20F63
; $C2:0F63 — C2Scene_TaskRunScript (46 bytes, $0F63–$0F90)
; Task handler of the script tasks (C2Scene_TaskSpawnScript and
; C2Scene_TaskSpawnScriptLow install it); also called by other handlers.
; Runs the task's script from .ScriptPtr/.ScriptBank: calls the handler
; of each op from C2Script_OpTable with C2Script_Ptr on the opcode. On
; Z=0 it adds A to the pointer, stores it back in .ScriptPtr, zeroes
; .OpState (16-bit, so +$33 too) for the next op and goes on; Z=1 ends
; the call with the pointer where it is (.ScriptBank is never written).
; Callers (5 JSR sites): unmatched ($C2:378B, $C2:37A1, $C2:3DBA, $C2:3DC1, $C2:4823).
; Callers note (5 JSR sites, unmatched): $C2:378B, $C2:37A1, $C2:3DBA,
;   $C2:3DC1 and $C2:4823; as a task handler, C2Scene_TaskRunAll
;   (C2Scene_TaskCallHandler).
; Entry: M any (SEP #$20 / REP #$20 here), X=0, DP=$0000, DB with low
;        WRAM at $0000-$1FFF ($00 from the NMI; the RAM ops read and
;        write absolute addresses through it); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C as the last handler left it (C=1: the task is done);
;        A, X, Y clobbered; C2Script_Ptr = the op it stopped on; and
;        whatever the handlers change
; Calls: the C2Script_OpTable handlers.
C2Scene_TaskRunScript:
    LDX.b !C2Scene_TaskCur
    SEP #$20
    LDA.w C2Scene_Task.ScriptBank,X
    STA.b !C2Script_Ptr+2
    REP #$20
    LDA.w C2Scene_Task.ScriptPtr,X
    STA.b !C2Script_Ptr
.op:
    LDA.b [!C2Script_Ptr]
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    JSR (C2Script_OpTable,X)
    BEQ .stop
    CLC
    ADC.b !C2Script_Ptr
    STA.b !C2Script_Ptr
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_Task.ScriptPtr,X
    STZ.w C2Scene_Task.OpState,X
    BRA .op
.stop:
    SEP #$20
    RTS

; $C2:0F91 — C2Script_OpTable (83 words, $0F91–$1036)
; The handler of each script opcode $00-$52 (C2Scene_TaskRunScript: JSR
; (T,X) with X = the opcode * 2); a larger opcode is not checked for and
; would jump through the code after the table. Opcodes are listed in table
; order; the handlers are not in opcode order in the ROM ($4C and $4D sit
; among the branches, $51 after $32). Operand bytes follow the opcode
; ("arg 1" is the byte after it).
C2Script_OpTable:
    dw C2Script_ResetTask       ; $00
    dw C2Script_SetSprPalette   ; $01
    dw C2Script_SetSprPriority  ; $02
    dw C2Script_SpawnUnk1CF5    ; $03
    dw C2Script_SpawnUnk1DD4    ; $04
    dw C2Script_GoToLocation    ; $05
    dw C2Script_Halt            ; $06
    dw C2Script_SetMapCell      ; $07
    dw C2Script_SetMemberWord   ; $08
    dw C2Script_SpawnScript     ; $09
    dw C2Script_ClearTaskByte   ; $0A
    dw C2Script_IncTaskByte     ; $0B
    dw C2Script_DecTaskByte     ; $0C
    dw C2Script_SetTaskByte     ; $0D
    dw C2Script_OrTaskByte      ; $0E
    dw C2Script_ClearTaskBits   ; $0F
    dw C2Script_ClearRamByte    ; $10
    dw C2Script_IncRamByte      ; $11
    dw C2Script_DecRamByte      ; $12
    dw C2Script_SetRamByte      ; $13
    dw C2Script_OrRamByte       ; $14
    dw C2Script_ClearRamBits    ; $15
    dw C2Script_TaskByteToRam   ; $16
    dw C2Script_RamByteToTask   ; $17
    dw C2Script_CopyTaskByte    ; $18
    dw C2Script_CopyRamByte     ; $19
    dw C2Script_Jump            ; $1A
    dw C2Script_LoopTaskByte    ; $1B
    dw C2Script_IfTaskByteZero  ; $1C
    dw C2Script_IfTaskByteNonZero ; $1D
    dw C2Script_IfTaskByteNe    ; $1E
    dw C2Script_IfTaskByteEq    ; $1F
    dw C2Script_IfTaskBitsSet   ; $20
    dw C2Script_IfTaskBitsClear ; $21
    dw C2Script_IfRamByteZero   ; $22
    dw C2Script_IfRamByteNonZero ; $23
    dw C2Script_IfRamByteNe     ; $24
    dw C2Script_IfRamByteEq     ; $25
    dw C2Script_IfRamBitsSet    ; $26
    dw C2Script_IfRamBitsClear  ; $27
    dw C2Script_SpawnUnk20A2    ; $28
    dw C2Script_SpawnUnk2105    ; $29
    dw C2Script_SpawnUnk21F8    ; $2A
    dw C2Script_SpawnUnk2194    ; $2B
    dw C2Script_SetPosition     ; $2C
    dw C2Script_Skip1           ; $2D
    dw C2Script_SetXVelocity    ; $2E
    dw C2Script_SetYVelocity    ; $2F
    dw C2Script_SetAnim         ; $30
    dw C2Script_MoveFrames      ; $31
    dw C2Script_ScrollFrames    ; $32
    dw C2Script_QueueVram       ; $33
    dw C2Script_CallNear        ; $34
    dw C2Script_SpawnTask       ; $35
    dw C2Script_Call            ; $36
    dw C2Script_Return          ; $37
    dw C2Script_Wait            ; $38
    dw C2Script_WaitAnimating   ; $39
    dw C2Script_StopIfOlder     ; $3A
    dw C2Script_SoundCmd18      ; $3B
    dw C2Script_PlaySfx         ; $3C
    dw C2Script_SoundCmd10IfClear ; $3D
    dw C2Script_DrawLayer       ; $3E
    dw C2Script_MoveToX         ; $3F
    dw C2Script_MoveToY         ; $40
    dw C2Script_Halt2           ; $41
    dw C2Script_SpawnTaskLow    ; $42
    dw C2Script_SpawnScriptLow  ; $43
    dw C2Script_SetListBit7     ; $44
    dw C2Script_ClearListBit7   ; $45
    dw C2Script_AddTaskByte     ; $46
    dw C2Script_SubTaskByte     ; $47
    dw C2Script_AddRamByte      ; $48
    dw C2Script_SubRamByte      ; $49
    dw C2Script_SoundCmd10      ; $4A
    dw C2Script_SoundCmd        ; $4B
    dw C2Script_IfRamByteLess   ; $4C
    dw C2Script_IfRamByteGe     ; $4D
    dw C2Script_CallLong        ; $4E
    dw C2Script_CopyMapBlock    ; $4F
    dw C2Script_DrawMetatile    ; $50
    dw C2Script_ScrollLayerFrames ; $51
    dw C2Script_End             ; $52

; ============================================================
; Scene script ops $00-$32, $4C, $4D, $51 ($C2:1037–$C2:17D1)
; ============================================================
; Every handler is entered from C2Scene_TaskRunScript with M=0, X=0
; (X = the opcode * 2, which none of them uses), DP=$0000, DB with low
; WRAM at $0000-$1FFF ($00 from the NMI) and C2Script_Ptr on the opcode,
; and returns as that routine reads it: Z=0 and A = the bytes to advance,
; or Z=1 to stop. "Task byte n" is byte n of the running task's record
; (C2Scene_TaskCur), reached with (dp),Y; "RAM byte a" is the byte at
; the 16-bit address a through DB, so with DB=$00 low WRAM or an I/O
; register. The conditional branches move the script by a signed byte
; counted from the opcode (sign-extended into A); an offset of 0 stops
; on the op, so it waits until the condition fails.

; $C2:1037 — C2Script_ResetTask (90 bytes, $1037–$1090)
; Op $00, 1 byte: zeroes the task's record from +$05 on, except the
; script fields +$07-$0A: .ScriptReturn, the animation, the sprite fields,
; position and velocity and all words up to +$3F (16-bit STZs at +$05,
; +$0B, +$0D, +$0E and every even offset $10-$3E, so +$0E is cleared twice).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  M=0, X=0; A = 1; X = the task
; No calls.
C2Script_ResetTask:
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_Task.ScriptReturn,X
    STZ.w C2Scene_Task.AnimPtr,X
    STZ.w C2Scene_Task.AnimBank,X
    STZ.w C2Scene_Task.AnimTimer,X  ; and .SprAttr
    STZ.w C2Scene_Task.SprTile,X
    STZ.w C2Scene_Task.XFrac,X
    STZ.w C2Scene_Task.SprX,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.YVel+2,X     ; +$22-$31: no names yet
    STZ.w C2Scene_Task.YVel+4,X
    STZ.w C2Scene_Task.YVel+6,X
    STZ.w C2Scene_Task.YVel+8,X
    STZ.w C2Scene_Task.YVel+10,X
    STZ.w C2Scene_Task.YVel+12,X
    STZ.w C2Scene_Task.YVel+14,X
    STZ.w C2Scene_Task.YVel+16,X
    STZ.w C2Scene_Task.OpState,X
    STZ.w C2Scene_Task.OpTarget,X   ; and .Unk35 low byte
    STZ.w C2Scene_Task.Unk35+1,X    ; +$36-$37
    STZ.w C2Scene_Task.Unk37+1,X    ; +$38-$3F
    STZ.w C2Scene_Task.Unk37+3,X
    STZ.w C2Scene_Task.Unk37+5,X
    STZ.w C2Scene_Task.Unk37+7,X
    LDA.w #1
    RTS

; $C2:1091 — C2Script_SetSprPalette (23 bytes, $1091–$10A7)
; Op $01, 2 bytes: .SprAttr = .SprAttr AND $F1 OR arg 1: replaces bits
; 1-3, which C2Scene_SprDrawNode puts in the OAM palette bits.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 2; X = the task, Y = 1
; No calls.
C2Script_SetSprPalette:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDY.w #1
    LDA.w C2Scene_Task.SprAttr,X
    AND.b #!C2Scene_SprAttrKeepPal
    ORA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.SprAttr,X
    REP #$20
    LDA.w #2
    RTS

; $C2:10A8 — C2Script_SetSprPriority (23 bytes, $10A8–$10BE)
; Op $02, 2 bytes: .SprAttr = .SprAttr AND $4F OR arg 1: replaces bits 4
; and 5 (the OAM priority bits) and bit 7 (C2Scene_SprAttrScroll).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 2; X = the task, Y = 1
; No calls.
C2Script_SetSprPriority:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDY.w #1
    LDA.w C2Scene_Task.SprAttr,X
    AND.b #!C2Scene_SprAttrKeepPrio
    ORA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.SprAttr,X
    REP #$20
    LDA.w #2
    RTS

; $C2:10BF — C2Script_SpawnUnk1CF5 (14 bytes, $10BF–$10CC)
; Op $03, 10 bytes: starts a C2Scene_TaskUnk1CF5 task (C2Scene_TaskSpawn,
; records 4-63), which copies this task's record, and advances 10. The op
; reads none of its 9 argument bytes itself: probably the new task reads
; them through the .ScriptPtr it copied, which still points at this op
; (C2Scene_TaskRunScript stores the pointer only after the op).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  M=0, X=0; A = 10; X, Y as C2Scene_TaskSpawn leaves them;
;        C2Tmp_08 changed
; Calls: C2Scene_TaskSpawn.
C2Script_SpawnUnk1CF5:
    SEP #$20
    LDX.w #C2Scene_TaskUnk1CF5
    JSR C2Scene_TaskSpawn
    REP #$20
    LDA.w #!C2Script_SpawnUnk1CF5Len
    RTS

; $C2:10CD — C2Script_SpawnUnk1DD4 (51 bytes, $10CD–$10FF)
; Op $04, 6 bytes: puts its arguments in this task's record, .Unk35 = arg
; 1-2, .Unk37 = arg 3, .OpState = arg 4 (high byte 0), .OpTarget = arg 5,
; and starts a C2Scene_TaskUnk1DD4 task, which copies them (what it does
; with them is not traced). This task's .OpState is zeroed again when
; C2Scene_TaskRunScript advances.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  M=0, X=0; A = 6; X, Y as C2Scene_TaskSpawn leaves them;
;        C2Tmp_08 changed
; Calls: C2Scene_TaskSpawn.
C2Script_SpawnUnk1DD4:
    LDX.b !C2Scene_TaskCur
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.Unk35,X
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.Unk37,X
    LDY.w #4
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.OpState,X
    STZ.w C2Scene_Task.OpState+1,X
    LDY.w #5
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.OpTarget,X
    LDX.w #C2Scene_TaskUnk1DD4
    JSR C2Scene_TaskSpawn
    REP #$20
    LDA.w #6
    RTS

; $C2:1100 — C2Script_GoToLocation (105 bytes, $1100–$1168)
; Op $05, 5 bytes: sets up a location change in the field's location
; block (DP_Field) and selects scene mode C2Scene_ModeUnk2:
; - Loc_ReturnId = the current Loc_Id; Loc_ReturnX = BG2's tile X
;   (C2Scene_BgTileX word 1) + 16, less 192 if that reaches 192;
;   Loc_ReturnY = BG2's tile Y + 16, AND $7F; Loc_ReturnFacing = the new
;   entry facing turned around (C2SceneRom_TurnAround). The id, X and Y
;   are also copied to C2Scene_SavedReturnId/X/Y;
; - Loc_Id = arg 1-2 AND C2Scene_LocIdMask (bits 0-8), Loc_EntryFacing =
;   arg 2 / 2 (the word's bits 9-15; the turn-around takes bits 9-10),
;   Loc_EntryX = arg 3, Loc_EntryY = arg 4.
; The +16 is half the screen width in tiles for X but not half its height
; for Y (C2Scene_SetStartScroll uses 14 there): probably the tile under
; the camera's center, or near it.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner); DB=$00
;        (absolute DP_Field block and $04FC)
; Exit:  M=0, X=0; A = 5; X = the facing AND 3, Y = 4
; No calls.
C2Script_GoToLocation:
    LDA.w !DP_Field+!Loc_Id
    STA.w !DP_Field+!Loc_ReturnId
    STA.w !C2Scene_SavedReturnId
    LDA.b !C2Scene_BgTileX+2
    CLC
    ADC.w #!C2Scene_ReturnTileOfs
    CMP.w #!C2Scene_MapTilesX
    BCC .x_ok
    SBC.w #!C2Scene_MapTilesX
.x_ok:
    STA.w !DP_Field+!Loc_ReturnX    ; 16-bit: Loc_ReturnY is written below
    STA.w !C2Scene_SavedReturnX
    LDA.b !C2Scene_BgTileY+2
    CLC
    ADC.w #!C2Scene_ReturnTileOfs
    AND.w #!C2Scene_MapTilesY-1
    SEP #$20
    STA.w !DP_Field+!Loc_ReturnY
    STA.w !C2Scene_SavedReturnY
    REP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    AND.w #!C2Scene_LocIdMask
    STA.w !DP_Field+!Loc_Id
    SEP #$20
    INY
    LDA.b [!C2Script_Ptr],Y         ; arg 2 again: the bits above the location
    LSR A
    STA.w !DP_Field+!Loc_EntryFacing
    INY
    LDA.b [!C2Script_Ptr],Y
    STA.w !DP_Field+!Loc_EntryX
    INY
    LDA.b [!C2Script_Ptr],Y
    STA.w !DP_Field+!Loc_EntryY
    TDC
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #3
    TAX
    LDA.l !C2SceneRom_TurnAround,X
    STA.w !DP_Field+!Loc_ReturnFacing
    LDA.b #!C2Scene_ModeUnk2
    STA.w !C2Scene_Mode
    REP #$20
    LDA.w #5
    RTS

; $C2:1169 — C2Script_Halt (2 bytes, $1169–$116A)
; Op $06: stops (A = 0, Z=1) without advancing, every frame: the script
; ends there but its task stays (C as C2Scene_TaskRunScript left it, 0
; from its ASL). Op $41 (C2Script_Halt2) is the same code.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  M=0, X=0; A = 0
; No calls.
C2Script_Halt:
    TDC
    RTS

; $C2:116B — C2Script_SetMapCell (71 bytes, $116B–$11B1)
; Op $07, 5 bytes: writes metatile number arg 4 into BG layer arg 1's
; map (C2Scene_LayerMaps, bank $7E) at column arg 2, row arg 3 (row * 96
; + column, with the hardware multiplier). It only changes the map: what
; is on screen is redrawn elsewhere (e.g. C2Script_DrawLayer).
; Quirk, kept: the layer is not checked; 0 gives index $1FE and reads a
; word far past C2Scene_LayerMaps.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner): DP=$0000; DB=$00
;        (WRMPYA/WRMPYB/RDMPYL)
; Exit:  M=0, X=0; A = 5; X = (layer - 1) * 2, Y = 4; C2Tmp_10-$12 = the
;        cell's address
; No calls.
!C2Script_CellPtr = !C2Tmp_10   ; 24-bit: the map cell
C2Script_SetMapCell:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    DEC A
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    LDA.l C2Scene_LayerMaps,X
    STA.b !C2Script_CellPtr
    SEP #$20
    LDA.b #!Bank7E
    STA.b !C2Script_CellPtr+2
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    STA.w WRMPYA
    LDA.b #!C2Scene_MapCols
    STA.w WRMPYB
    REP #$20
    CLC
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    AND.w #!Eng_LowByteMask
    ADC.w RDMPYL
    CLC
    ADC.b !C2Script_CellPtr
    STA.b !C2Script_CellPtr
    TDC
    SEP #$20
    LDY.w #4
    LDA.b [!C2Script_Ptr],Y
    STA.b [!C2Script_CellPtr]
    REP #$20
    LDA.w #5
    RTS

; $C2:11B2 — C2Script_SetMemberWord (68 bytes, $11B2–$11F5)
; Op $08, 4 bytes: stores the word arg 1-2 for character arg 3: at
; C2Scene_Unk1B41 for character 7, else at the C2Scene_MemberWords word
; of the party position (Party_Members) that holds that character;
; nothing if none does. With C2Scene_Unk1B41 that makes four words at
; $1B3B-$1B42; what they mean is not traced.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 4; X = the word when one was stored; Y = 3;
;        C2Tmp_08 = the word
; No calls.
!C2Script_MemberWord = !C2Tmp_08
C2Script_SetMemberWord:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_MemberWord
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    CMP.b #7
    BNE .member0
    LDX.b !C2Script_MemberWord
    STX.w !C2Scene_Unk1B41
    BRA .done
.member0:
    CMP.l !Party_Members
    BNE .member1
    LDX.b !C2Script_MemberWord
    STX.w !C2Scene_MemberWords
    BRA .done
.member1:
    CMP.l !Party_Members+1
    BNE .member2
    LDX.b !C2Script_MemberWord
    STX.w !C2Scene_MemberWords+2
    BRA .done
.member2:
    CMP.l !Party_Members+2
    BNE .done
    LDX.b !C2Script_MemberWord
    STX.w !C2Scene_MemberWords+4
.done:
    REP #$20
    LDA.w #4
    RTS

; $C2:11F6 — C2Script_SpawnScript (22 bytes, $11F6–$120B)
; Op $09, 4 bytes: starts another script task (C2Scene_TaskSpawnScript,
; records 4-63) on the script at arg 1-2 in bank arg 3.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  M=0, X=0; A = 4; X = the new record; Y as C2Scene_TaskSpawn
;        leaves it; C2Tmp_01, C2Tmp_08 and C2Tmp_0A changed
; Calls: C2Scene_TaskSpawnScript.
C2Script_SpawnScript:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    JSR C2Scene_TaskSpawnScript
    REP #$20
    LDA.w #4
    RTS

; $C2:120C — C2Script_ClearTaskByte (17 bytes, $120C–$121C)
; Op $0A, 2 bytes: task byte arg 1 = 0.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 2; Y = arg 1
; No calls.
C2Script_ClearTaskByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAY
    TDC                         ; A = DP = 0
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #2
    RTS

; $C2:121D — C2Script_IncTaskByte (19 bytes, $121D–$122F)
; Op $0B, 2 bytes: task byte arg 1 + 1.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_ClearTaskByte; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IncTaskByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    INC A
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #2
    RTS

; $C2:1230 — C2Script_DecTaskByte (19 bytes, $1230–$1242)
; Op $0C, 2 bytes: task byte arg 1 - 1.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_ClearTaskByte; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_DecTaskByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    DEC A
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #2
    RTS

; $C2:1243 — C2Script_SetTaskByte (20 bytes, $1243–$1256)
; Op $0D, 3 bytes: task byte arg 1 = arg 2.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 3; X = Y = arg 1
; No calls.
C2Script_SetTaskByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    INY
    LDA.b [!C2Script_Ptr],Y
    TXY
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #3
    RTS

; $C2:1257 — C2Script_OrTaskByte (22 bytes, $1257–$126C)
; Op $0E, 3 bytes: task byte arg 1 OR= arg 2 (sets those bits).
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_SetTaskByte; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_OrTaskByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    INY
    LDA.b [!C2Script_Ptr],Y
    TXY
    ORA.b (!C2Scene_TaskCur),Y
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #3
    RTS

; $C2:126D — C2Script_ClearTaskBits (24 bytes, $126D–$1284)
; Op $0F, 3 bytes: task byte arg 1 AND= NOT arg 2 (clears those bits).
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_SetTaskByte; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_ClearTaskBits:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    INY
    LDA.b [!C2Script_Ptr],Y
    EOR.b #!Eng_Invert8
    TXY
    AND.b (!C2Scene_TaskCur),Y
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #3
    RTS

; $C2:1285 — C2Script_ClearRamByte (17 bytes, $1285–$1295)
; Op $10, 3 bytes: RAM byte at arg 1-2 = 0.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner): DP=$0000; DB = the
;        bank of the RAM bytes ($00 from the NMI)
; Exit:  M=0, X=0; A = 3; X = the address, Y = 1
; No calls.
C2Script_ClearRamByte:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    STZ.w !Eng_PtrBase,X
    REP #$20
    LDA.w #3
    RTS

; $C2:1296 — C2Script_IncRamByte (17 bytes, $1296–$12A6)
; Op $11, 3 bytes: RAM byte at arg 1-2 + 1.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_ClearRamByte; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IncRamByte:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    INC.w !Eng_PtrBase,X
    REP #$20
    LDA.w #3
    RTS

; $C2:12A7 — C2Script_DecRamByte (17 bytes, $12A7–$12B7)
; Op $12, 3 bytes: RAM byte at arg 1-2 - 1.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_ClearRamByte; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_DecRamByte:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    DEC.w !Eng_PtrBase,X
    REP #$20
    LDA.w #3
    RTS

; $C2:12B8 — C2Script_SetRamByte (22 bytes, $12B8–$12CD)
; Op $13, 4 bytes: RAM byte at arg 1-2 = arg 3.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Script_ClearRamByte: DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 4; X = the address, Y = 3
; No calls.
C2Script_SetRamByte:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    STA.w !Eng_PtrBase,X
    REP #$20
    LDA.w #4
    RTS

; $C2:12CE — C2Script_OrRamByte (25 bytes, $12CE–$12E6)
; Op $14, 4 bytes: RAM byte at arg 1-2 OR= arg 3.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_SetRamByte; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_OrRamByte:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    ORA.w !Eng_PtrBase,X
    STA.w !Eng_PtrBase,X
    REP #$20
    LDA.w #4
    RTS

; $C2:12E7 — C2Script_ClearRamBits (27 bytes, $12E7–$1301)
; Op $15, 4 bytes: RAM byte at arg 1-2 AND= NOT arg 3.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_SetRamByte; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_ClearRamBits:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    EOR.b #!Eng_Invert8
    AND.w !Eng_PtrBase,X
    STA.w !Eng_PtrBase,X
    REP #$20
    LDA.w #4
    RTS

; $C2:1302 — C2Script_TaskByteToRam (26 bytes, $1302–$131B)
; Op $16, 4 bytes: RAM byte at arg 2-3 = task byte arg 1.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Script_ClearRamByte: DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 4; X = the address, Y = arg 1
; No calls.
C2Script_TaskByteToRam:
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    TAX
    DEY
    LDA.b [!C2Script_Ptr],Y
    AND.w #!Eng_LowByteMask
    TAY
    SEP #$20
    LDA.b (!C2Scene_TaskCur),Y
    STA.w !Eng_PtrBase,X
    REP #$20
    LDA.w #4
    RTS

; $C2:131C — C2Script_RamByteToTask (26 bytes, $131C–$1335)
; Op $17, 4 bytes: task byte arg 1 = RAM byte at arg 2-3.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_TaskByteToRam; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_RamByteToTask:
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    TAX
    DEY
    LDA.b [!C2Script_Ptr],Y
    AND.w #!Eng_LowByteMask
    TAY
    SEP #$20
    LDA.w !Eng_PtrBase,X
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #4
    RTS

; $C2:1336 — C2Script_CopyTaskByte (26 bytes, $1336–$134F)
; Op $18, 3 bytes: task byte arg 1 = task byte arg 2.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 3; X = the byte, Y = arg 1
; No calls.
C2Script_CopyTaskByte:
    SEP #$20
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    TAX
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAY
    TXA
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #3
    RTS

; $C2:1350 — C2Script_CopyRamByte (26 bytes, $1350–$1369)
; Op $19, 5 bytes: RAM byte at arg 1-2 = RAM byte at arg 3-4.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Script_ClearRamByte: DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 5; X = the source, Y = the destination
; No calls.
C2Script_CopyRamByte:
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    TAX
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAY
    SEP #$20
    LDA.w !Eng_PtrBase,X
    STA.w !Eng_PtrBase,Y
    REP #$20
    LDA.w #5
    RTS

; $C2:136A — C2Script_Jump (11 bytes, $136A–$1374)
; Op $1A, 3 bytes: C2Script_Ptr = arg 1-2 (an address in the script's
; bank), then advance 1, so the script goes on at arg 1-2 + 1. Unlike
; C2Script_Call, which subtracts 1 before advancing, the target is not
; arg 1-2 itself: the script's addresses are probably written one less
; (not traced).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 1; Y = 1
; No calls.
C2Script_Jump:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_Ptr
    LDA.w #1
    RTS

; $C2:1375 — C2Script_LoopTaskByte (35 bytes, $1375–$1397)
; Op $1B, 3 bytes: task byte arg 1 - 1; while it is not 0, branch by arg
; 2; at 0, advance 3 (a counted loop).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 3, or the offset with C=0 (Z=1 for 0); Y = arg 1
;        or 2
; No calls.
C2Script_LoopTaskByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    DEC A
    STA.b (!C2Scene_TaskCur),Y
    BEQ .done
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    REP #$20                    ; high byte 0 (from the opcode * 2)
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.done:
    REP #$20
    LDA.w #3
    RTS

; $C2:1398 — C2Script_IfTaskByteZero (32 bytes, $1398–$13B7)
; Op $1C, 3 bytes: if task byte arg 1 is 0, branch by arg 2; else
; advance 3.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 3, or the offset with C=0; Y = arg 1 or 2
; No calls.
C2Script_IfTaskByteZero:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    BNE .next
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #3
    RTS

; $C2:13B8 — C2Script_IfTaskByteNonZero (32 bytes, $13B8–$13D7)
; Op $1D, 3 bytes: if task byte arg 1 is not 0, branch by arg 2; else
; advance 3.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfTaskByteZero; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfTaskByteNonZero:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    BEQ .next
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #3
    RTS

; $C2:13D8 — C2Script_IfTaskByteNe (36 bytes, $13D8–$13FB)
; Op $1E, 4 bytes: if task byte arg 1 is not arg 2, branch by arg 3;
; else advance 4.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 4, or the offset with C=0; X = arg 1; Y = arg 1
;        or 3
; No calls.
C2Script_IfTaskByteNe:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    INY
    LDA.b [!C2Script_Ptr],Y
    TXY
    CMP.b (!C2Scene_TaskCur),Y
    BEQ .next
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #4
    RTS

; $C2:13FC — C2Script_IfTaskByteEq (36 bytes, $13FC–$141F)
; Op $1F, 4 bytes: if task byte arg 1 is arg 2, branch by arg 3; else
; advance 4.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfTaskByteNe; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfTaskByteEq:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    INY
    LDA.b [!C2Script_Ptr],Y
    TXY
    CMP.b (!C2Scene_TaskCur),Y
    BNE .next
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #4
    RTS

; $C2:1420 — C2Script_IfTaskBitsSet (36 bytes, $1420–$1443)
; Op $20, 4 bytes: if task byte arg 1 AND arg 2 is not 0, branch by arg
; 3; else advance 4.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfTaskByteNe; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfTaskBitsSet:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    INY
    LDA.b [!C2Script_Ptr],Y
    TXY
    AND.b (!C2Scene_TaskCur),Y
    BEQ .next
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #4
    RTS

; $C2:1444 — C2Script_IfTaskBitsClear (37 bytes, $1444–$1468)
; Op $21, 4 bytes: if task byte arg 1 AND arg 2 is 0, branch by arg 3;
; else advance 4. (Its TDC clears a high byte that is already 0.)
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfTaskByteNe; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfTaskBitsClear:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    INY
    LDA.b [!C2Script_Ptr],Y
    TXY
    AND.b (!C2Scene_TaskCur),Y
    BNE .next
    TDC
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #4
    RTS

; $C2:1469 — C2Script_IfRamByteZero (34 bytes, $1469–$148A)
; Op $22, 4 bytes: if the RAM byte at arg 1-2 is 0, branch by arg 3; else
; advance 4.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Script_ClearRamByte: DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 4, or the offset with C=0; X = the address; Y = 1
;        or 3
; No calls.
C2Script_IfRamByteZero:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    TDC                         ; clear the high byte for the offset
    SEP #$20
    LDA.w !Eng_PtrBase,X
    BNE .next
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #4
    RTS

; $C2:148B — C2Script_IfRamByteNonZero (34 bytes, $148B–$14AC)
; Op $23, 4 bytes: if the RAM byte at arg 1-2 is not 0, branch by arg 3;
; else advance 4.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfRamByteZero; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfRamByteNonZero:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    TDC
    SEP #$20
    LDA.w !Eng_PtrBase,X
    BEQ .next
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #4
    RTS

; $C2:14AD — C2Script_IfRamByteNe (37 bytes, $14AD–$14D1)
; Op $24, 5 bytes: if the RAM byte at arg 1-2 is not arg 3, branch by
; arg 4; else advance 5.
; Callers (1 JSR site): unmatched ($C2:FFB4).
; Callers note: none direct (C2Script_OpTable). xref's CONFIRMED JSR at
;   $C2:FFB4 is not a call: those bytes are the operand of REP #$20 at
;   $C2:FFB3 and the LDA $1814 after it (unmatched code).
; Entry: as C2Script_ClearRamByte: DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 5, or the offset with C=0; X = the address; Y = 3
;        or 4
; No calls.
C2Script_IfRamByteNe:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    CMP.w !Eng_PtrBase,X
    BEQ .next
    TDC                         ; clear the high byte for the offset
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #5
    RTS

; $C2:14D2 — C2Script_IfRamByteEq (37 bytes, $14D2–$14F6)
; Op $25, 5 bytes: if the RAM byte at arg 1-2 is arg 3, branch by arg 4;
; else advance 5.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfRamByteNe; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfRamByteEq:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    CMP.w !Eng_PtrBase,X
    BNE .next
    TDC
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #5
    RTS

; $C2:14F7 — C2Script_IfRamBitsSet (37 bytes, $14F7–$151B)
; Op $26, 5 bytes: if the RAM byte at arg 1-2 AND arg 3 is not 0, branch
; by arg 4; else advance 5.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfRamByteNe; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfRamBitsSet:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    AND.w !Eng_PtrBase,X
    BEQ .next
    TDC
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #5
    RTS

; $C2:151C — C2Script_IfRamBitsClear (37 bytes, $151C–$1540)
; Op $27, 5 bytes: if the RAM byte at arg 1-2 AND arg 3 is 0, branch by
; arg 4; else advance 5.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfRamByteNe; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfRamBitsClear:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    AND.w !Eng_PtrBase,X
    BNE .next
    TDC
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #5
    RTS

; $C2:1541 — C2Script_IfRamByteLess (37 bytes, $1541–$1565)
; Op $4C, 5 bytes: if the RAM byte at arg 1-2 is below arg 3 (unsigned),
; branch by arg 4; else advance 5. (It reads a word and compares the low
; byte.)
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfRamByteNe; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfRamByteLess:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    LDY.w #3
    LDA.w !Eng_PtrBase,X
    SEP #$20
    CMP.b [!C2Script_Ptr],Y
    BCS .next
    TDC
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #5
    RTS

; $C2:1566 — C2Script_IfRamByteGe (37 bytes, $1566–$158A)
; Op $4D, 5 bytes: if the RAM byte at arg 1-2 is arg 3 or more
; (unsigned), branch by arg 4; else advance 5.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_IfRamByteNe; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_IfRamByteGe:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    LDY.w #3
    LDA.w !Eng_PtrBase,X
    SEP #$20
    CMP.b [!C2Script_Ptr],Y
    BCC .next
    TDC
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    BPL .branch
    ORA.w #!Eng_HighByteMask
.branch:
    CLC
    RTS
.next:
    REP #$20
    LDA.w #5
    RTS

; $C2:158B — C2Script_SpawnUnk20A2 (14 bytes, $158B–$1598)
; Op $28, 2 bytes: starts a C2Scene_TaskUnk20A2 task (C2Scene_TaskSpawn),
; which copies this record (and so this op's .ScriptPtr: probably it
; reads arg 1 from there; not traced).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  M=0, X=0; A = 2; X, Y as C2Scene_TaskSpawn leaves them;
;        C2Tmp_08 changed
; Calls: C2Scene_TaskSpawn.
C2Script_SpawnUnk20A2:
    SEP #$20
    LDX.w #C2Scene_TaskUnk20A2
    JSR C2Scene_TaskSpawn
    REP #$20
    LDA.w #2
    RTS

; $C2:1599 — C2Script_SpawnUnk2105 (14 bytes, $1599–$15A6)
; Op $29, 2 bytes: as C2Script_SpawnUnk20A2 with C2Scene_TaskUnk2105.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_SpawnUnk20A2
; Calls: C2Scene_TaskSpawn.
C2Script_SpawnUnk2105:
    SEP #$20
    LDX.w #C2Scene_TaskUnk2105
    JSR C2Scene_TaskSpawn
    REP #$20
    LDA.w #2
    RTS

; $C2:15A7 — C2Script_SpawnUnk21F8 (14 bytes, $15A7–$15B4)
; Op $2A, 3 bytes: as C2Script_SpawnUnk20A2 with C2Scene_TaskUnk21F8.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Script_SpawnUnk20A2
; Exit:  as C2Script_SpawnUnk20A2, A = 3
; Calls: C2Scene_TaskSpawn.
C2Script_SpawnUnk21F8:
    SEP #$20
    LDX.w #C2Scene_TaskUnk21F8
    JSR C2Scene_TaskSpawn
    REP #$20
    LDA.w #3
    RTS

; $C2:15B5 — C2Script_SpawnUnk2194 (14 bytes, $15B5–$15C2)
; Op $2B, 3 bytes: as C2Script_SpawnUnk20A2 with C2Scene_TaskUnk2194.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Script_SpawnUnk20A2
; Exit:  as C2Script_SpawnUnk20A2, A = 3
; Calls: C2Scene_TaskSpawn.
C2Script_SpawnUnk2194:
    SEP #$20
    LDX.w #C2Scene_TaskUnk2194
    JSR C2Scene_TaskSpawn
    REP #$20
    LDA.w #3
    RTS

; $C2:15C3 — C2Script_SetPosition (28 bytes, $15C3–$15DE)
; Op $2C, 5 bytes: .SprX = arg 1-2 and .SprY = arg 3-4, both fractions
; 0.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 5; X = the task, Y = 3
; No calls.
C2Script_SetPosition:
    LDX.b !C2Scene_TaskCur
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.SprX,X
    STZ.w C2Scene_Task.XFrac,X
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.YFrac,X
    LDA.w #5
    RTS

; $C2:15DF — C2Script_Skip1 (4 bytes, $15DF–$15E2)
; Op $2D, 2 bytes: does nothing and advances 2 (the byte after the opcode
; is skipped).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  M=0, X=0; A = 2
; No calls.
C2Script_Skip1:
    LDA.w #2
    RTS

; $C2:15E3 — C2Script_SetXVelocity (22 bytes, $15E3–$15F8)
; Op $2E, 5 bytes: .XVelFrac = arg 1-2, .XVel = arg 3-4.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_SetPosition; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_SetXVelocity:
    LDX.b !C2Scene_TaskCur
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.XVelFrac,X
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.XVel,X
    LDA.w #5
    RTS

; $C2:15F9 — C2Script_SetYVelocity (22 bytes, $15F9–$160E)
; Op $2F, 5 bytes: .YVelFrac = arg 1-2, .YVel = arg 3-4.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_SetPosition; on entry DP=$0000, DB=$00 (low WRAM)
; No calls.
C2Script_SetYVelocity:
    LDX.b !C2Scene_TaskCur
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.YVelFrac,X
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.YVel,X
    LDA.w #5
    RTS

; $C2:160F — C2Script_SetAnim (14 bytes, $160F–$161C)
; Op $30, 2 bytes: starts animation script arg 1 (C2Scene_SetAnim).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner):
;        DP=$0000, DB=$00 (low WRAM)
; Exit:  M=0, X=0; A = 2; X = the task, Y = 1
; Calls: C2Scene_SetAnim.
C2Script_SetAnim:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    JSR C2Scene_SetAnim
    REP #$20
    LDA.w #2
    RTS

; $C2:161D — C2Script_MoveFrames (46 bytes, $161D–$164A)
; Op $31, 2 bytes: for arg 1 frames, each frame moves the task by its
; velocity (C2Scene_TaskMove), wraps the position into the map
; (C2Scene_WrapTaskPos), runs its animation (C2Anim_Run) and stops for
; the frame. .ScriptWait counts: 0 loads it with arg 1 (and that frame
; moves), then -1 per frame; when it reaches 0 the op advances 2 without
; moving. So arg 1 = n moves n times; 0 never ends.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  advance: M=0, X=0, A = 2, X = the task. Moved: M=0, X=0, A = 0
;        (Z=1), C=0 (the animation's carry is dropped); X, Y as
;        C2Anim_Run leaves them
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Anim_Run.
C2Script_MoveFrames:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.ScriptWait,X
    BNE .count
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.ScriptWait,X
    BRA .move
.count:
    DEC.w C2Scene_Task.ScriptWait,X
    BNE .move
    REP #$20
    LDA.w #2
    RTS
.move:
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    REP #$20
    TDC
    CLC
    RTS

; $C2:164B — C2Script_ScrollFrames (175 bytes, $164B–$16F9)
; Op $32, 2 bytes: scrolls BG layers 1 and 2 (and BG3) by the task's
; velocity for arg 1 frames, counted in .ScriptWait as C2Script_MoveFrames
; does. The first frame also zeroes the position (.XFrac-.SprY), which
; then serves as an accumulator: each frame
; C2Script_PanKeepFraction drops the whole pixels of the last frame,
; C2Scene_TaskMove adds the velocity, and when that makes at least one
; whole pixel in X (C2Script_PanTakeX) the layers are moved by that many
; pixels (C2Tmp_01, signed) with C2Scene_Unk0568 for layer 1 and then
; 2; likewise in Y (C2Script_PanTakeY, C2Scene_Unk066C; the two are
; probably the horizontal and vertical layer scrolls, which redraw the
; edge they uncover: not traced). BG3's scroll shadow takes the same
; pixels unless any of three flag bits is set in C2Scene_FlagTailCopy
; (bytes 0, 3 and 8: the copy of $7F:01F0-$01FF; what they stand for is
; not traced).
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  advance: M=0, X=0, A = 2, X = the task. Scrolled: M=0, X=0, A =
;        0 (Z=1), C=0; X, Y clobbered; C2Tmp_00/$01 and whatever the
;        scroll calls change
; Calls: C2Script_PanKeepFraction, C2Scene_TaskMove, C2Script_PanTakeX,
;   C2Script_PanTakeY, C2Scene_Unk0568, C2Scene_Unk066C.
!C2Script_PanLayer = !C2Tmp_00  ; in for C2Scene_Unk0568/066C: the layer (as C2Scene_DrawLayer)
!C2Script_PanStep = !C2Tmp_01   ; signed pixels to move, from C2Script_PanTakeX/Y
C2Script_ScrollFrames:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.ScriptWait,X
    BNE .count
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.ScriptWait,X
    REP #$20
    STZ.w C2Scene_Task.XFrac,X
    STZ.w C2Scene_Task.SprX,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.SprY,X
    BRA .scroll
.count:
    DEC.w C2Scene_Task.ScriptWait,X
    BNE .scroll
    REP #$20
    LDA.w #2
    RTS
.scroll:
    REP #$20
    JSR C2Script_PanKeepFraction
    JSR C2Scene_TaskMove
    JSR C2Script_PanTakeX
    BCC .y
    SEP #$20
    LDA.b #1
    STA.b !C2Script_PanLayer
    JSR C2Scene_Unk0568
    LDA.b #2
    STA.b !C2Script_PanLayer
    JSR C2Scene_Unk0568
    LDA.w !C2Scene_FlagTailCopy
    BIT.b #!C2Scene_NoBg3PanBit0
    BNE .y
    LDA.w !C2Scene_FlagTailCopy+3
    BIT.b #!C2Scene_NoBg3PanBit3
    BNE .y
    LDA.w !C2Scene_FlagTailCopy+8
    BIT.b #!C2Scene_NoBg3PanBit8
    BNE .y
    TDC
    LDA.b !C2Script_PanStep
    REP #$20
    BPL .x_add
    ORA.w #!Eng_HighByteMask
.x_add:
    CLC
    ADC.b !C2Scene_Bg3HScroll
    STA.b !C2Scene_Bg3HScroll
.y:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Script_PanTakeY
    BCC .done
    SEP #$20
    LDA.b #1
    STA.b !C2Script_PanLayer
    JSR C2Scene_Unk066C
    LDA.b #2
    STA.b !C2Script_PanLayer
    JSR C2Scene_Unk066C
    LDA.w !C2Scene_FlagTailCopy
    BIT.b #!C2Scene_NoBg3PanBit0
    BNE .done
    LDA.w !C2Scene_FlagTailCopy+3
    BIT.b #!C2Scene_NoBg3PanBit3
    BNE .done
    LDA.w !C2Scene_FlagTailCopy+8
    BIT.b #!C2Scene_NoBg3PanBit8
    BNE .done
    TDC
    LDA.b !C2Script_PanStep
    REP #$20
    BPL .y_add
    ORA.w #!Eng_HighByteMask
.y_add:
    CLC
    ADC.b !C2Scene_Bg3VScroll
    STA.b !C2Scene_Bg3VScroll
.done:
    REP #$20
    TDC
    CLC
    RTS

; $C2:16FA — C2Script_ScrollLayerFrames (95 bytes, $16FA–$1758)
; Op $51, 3 bytes: C2Script_ScrollFrames for one layer, arg 1 (passed to
; C2Scene_Unk0568/066C as is), for arg 2 frames, and without BG3.
; Callers note: none direct (C2Script_OpTable).
; Entry: as C2Scene_TaskRunScript calls the ops (see the banner)
; Exit:  advance: M=0, X=0, A = 3, X = the task. Scrolled: as
;        C2Script_ScrollFrames
; Calls: C2Script_PanKeepFraction, C2Scene_TaskMove, C2Script_PanTakeX,
;   C2Script_PanTakeY, C2Scene_Unk0568, C2Scene_Unk066C.
C2Script_ScrollLayerFrames:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.ScriptWait,X
    BNE .count
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.ScriptWait,X
    REP #$20
    STZ.w C2Scene_Task.XFrac,X
    STZ.w C2Scene_Task.SprX,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.SprY,X
    BRA .scroll
.count:
    DEC.w C2Scene_Task.ScriptWait,X
    BNE .scroll
    REP #$20
    LDA.w #3
    RTS
.scroll:
    REP #$20
    JSR C2Script_PanKeepFraction
    JSR C2Scene_TaskMove
    JSR C2Script_PanTakeX
    BCC .y
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_PanLayer
    JSR C2Scene_Unk0568
.y:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Script_PanTakeY
    BCC .done
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_PanLayer
    JSR C2Scene_Unk066C
.done:
    REP #$20
    TDC
    CLC
    RTS

; $C2:1759 — C2Script_PanKeepFraction (43 bytes, $1759–$1783)
; Drops the whole pixels from the task's position, keeping the fraction
; as a value in -1..+1: .SprX = -1 if it was negative with a non-zero
; .XFrac, else 0; the same for .SprY with .YFrac. (The fraction words
; are left as they are.)
; Callers (2 JSR sites): C2Script_ScrollFrames ($C2:1679) and C2Script_ScrollLayerFrames ($C2:1728).
; Entry: M=0, X=0 with X = the task, DP any, DB with low WRAM at
;        $0000-$1FFF
; Exit:  M=0, X=0; A clobbered; X, Y unchanged
; No calls.
C2Script_PanKeepFraction:
    LDA.w C2Scene_Task.SprX,X
    BPL .x_zero
    LDA.w C2Scene_Task.XFrac,X
    BEQ .x_zero
    LDA.w #!C2Scene_WholeMinus1
    STA.w C2Scene_Task.SprX,X
    BRA .y
.x_zero:
    STZ.w C2Scene_Task.SprX,X
.y:
    LDA.w C2Scene_Task.SprY,X
    BPL .y_zero
    LDA.w C2Scene_Task.YFrac,X
    BEQ .y_zero
    LDA.w #!C2Scene_WholeMinus1
    STA.w C2Scene_Task.SprY,X
    BRA .done
.y_zero:
    STZ.w C2Scene_Task.SprY,X
.done:
    RTS

; $C2:1784 — C2Script_PanTakeX (39 bytes, $1784–$17AA)
; Tells whether the X accumulator (.XFrac/.SprX) holds at least one whole
; pixel either way: C=1 with C2Tmp_01 = the low byte of .SprX (signed
; pixels), else C=0. A negative value is negated as 32 bits (only the
; high word is kept, for the test), so -1 plus a fraction counts as less
; than a pixel.
; Callers (2 JSR sites): C2Script_ScrollFrames ($C2:167F) and C2Script_ScrollLayerFrames ($C2:172E).
; Entry: M=0, X=0 with X = the task, DP=$0000, DB with low WRAM at
;        $0000-$1FFF
; Exit:  M=0, X=0; C as above; A clobbered; C2Tmp_01 set when C=1; X, Y
;        unchanged
; No calls.
C2Script_PanTakeX:
    LDA.w C2Scene_Task.SprX,X
    BPL .test
    CLC
    LDA.w C2Scene_Task.XFrac,X
    EOR.w #!Eng_Invert16
    ADC.w #1                    ; only the carry is kept
    LDA.w C2Scene_Task.SprX,X
    EOR.w #!Eng_Invert16
    ADC.w #0
.test:
    BEQ .none
    SEP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Script_PanStep
    REP #$20
    SEC
    RTS
.none:
    CLC
    RTS

; $C2:17AB — C2Script_PanTakeY (39 bytes, $17AB–$17D1)
; C2Script_PanTakeX for .YFrac/.SprY.
; Callers (2 JSR sites): C2Script_ScrollFrames ($C2:16BC) and C2Script_ScrollLayerFrames ($C2:1743).
; Entry/Exit: as C2Script_PanTakeX
; No calls.
C2Script_PanTakeY:
    LDA.w C2Scene_Task.SprY,X
    BPL .test
    CLC
    LDA.w C2Scene_Task.YFrac,X
    EOR.w #!Eng_Invert16
    ADC.w #1
    LDA.w C2Scene_Task.SprY,X
    EOR.w #!Eng_Invert16
    ADC.w #0
.test:
    BEQ .none
    SEP #$20
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Script_PanStep
    REP #$20
    SEC
    RTS
.none:
    CLC
    RTS

; ============================================================
; Scene script ops $33-$50, $52 ($C2:17D2–$C2:1C83)
; ============================================================
; The rest of the C2Script_OpTable handlers, in ROM order: VRAM queue,
; calls, spawns, waits, sound commands, the layer redraw, moves to a
; point, the list flags, byte arithmetic and the map block copy. They
; are entered and return as the ops before them (see the banner at
; C2Script_ResetTask); each header states its own entry state.

; $C2:17D2 — C2Script_QueueVram (53 bytes, $17D2–$1806)
; Op $33, 8 bytes: C2Anim_OpQueueVram's code on the script pointer: adds
; a VRAM DMA to the queue the NMI flushes (C2Scene_VramQ at
; C2Scene_VramQEnd): .Bank = arg 1, .Src = arg 2-3, .Dest = arg 4-5,
; .Size = arg 6-7, .Vmain = VMAIN_IncAfterHigh, with C2Scene_VramQLock
; held while the entry is written.
; Quirk, kept: no check that the queue has room.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$30 here), DP=$0000 (the queue is direct page),
;        DB=$00 (low WRAM: the .Bank byte is stored absolute through
;        DB); C2Script_Ptr on the opcode
; Exit:  M=0, X=0 (REP #$30); A = 8 (advance); X = the entry's offset, Y
;        = 6; C2Scene_VramQEnd + 8; C2Scene_VramQLock = 0
; No calls.
C2Script_QueueVram:
    SEP #$30
    LDX.b !C2Scene_VramQEnd
    INC.b !C2Scene_VramQLock
    LDY.b #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_VramQ.Bank,X
    LDA.b #!VMAIN_IncAfterHigh
    STA.b C2Scene_VramQ.Vmain,X
    REP #$20
    LDY.b #2
    LDA.b [!C2Script_Ptr],Y
    STA.b C2Scene_VramQ.Src,X
    LDY.b #4
    LDA.b [!C2Script_Ptr],Y
    STA.b C2Scene_VramQ.Dest,X
    LDY.b #6
    LDA.b [!C2Script_Ptr],Y
    STA.b C2Scene_VramQ.Size,X
    SEP #$20
    TXA
    CLC
    ADC.b #!C2Scene_VramQEntrySize
    STA.b !C2Scene_VramQEnd
    STZ.b !C2Scene_VramQLock
    REP #$30
    LDA.w #8
    RTS

; $C2:1807 — C2Script_CallNear (21 bytes, $1807–$181B)
; Op $34, 3 bytes: calls the routine at arg 1-2 in bank $C2 (JSR to
; .call, a JMP (C2Script_CallVec)) with M=1, then advances 3. The
; routine returns with RTS; its carry and registers are dropped.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000 (C2Script_CallVec, C2Script_Ptr), DB any
;        for this code (the called routine may need more); C2Script_Ptr
;        on the opcode
; Exit:  M=0, X=0; A = 3; X, Y and the rest as the called routine leaves
;        them; C2Script_CallVec = arg 1-2
; Calls: the routine at arg 1-2 (JMP (abs)).
C2Script_CallNear:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_CallVec
    SEP #$20
    JSR .call
    REP #$20
    LDA.w #3
    RTS
.call:
    JMP (!C2Script_CallVec)

; $C2:181C — C2Script_CallLong (29 bytes, $181C–$1838)
; Op $4E, 4 bytes: calls the routine at the long address arg 1-3 (JSL to
; .call, a JML [C2Script_CallVec]) with M=1; it returns with RTL. Then
; advances 4.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000 (C2Script_CallVec, C2Script_Ptr), DB any
;        for this code; C2Script_Ptr on the opcode
; Exit:  M=0, X=0; A = 4; X, Y and the rest as the called routine leaves
;        them; C2Script_CallVec = arg 1-3
; Calls: the routine at arg 1-3 (JML [abs]).
C2Script_CallLong:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_CallVec
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_CallVec+2
    JSL .call
    REP #$20
    LDA.w #4
    RTS
.call:
    JML [!C2Script_CallVec]

; $C2:1839 — C2Script_SpawnTask (15 bytes, $1839–$1847)
; Op $35, 3 bytes: starts a task with handler arg 1-2 (an address in bank
; $C2) in records 4-63 (C2Scene_TaskSpawn), which copies this task's
; record from +$05 on.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000, DB=$00 (low WRAM: the task records);
;        C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  M=0, X=0; A = 3; X, Y as C2Scene_TaskSpawn leaves them;
;        C2Tmp_08 = the handler
; Calls: C2Scene_TaskSpawn.
C2Script_SpawnTask:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    JSR C2Scene_TaskSpawn
    REP #$20
    LDA.w #3
    RTS

; $C2:1848 — C2Script_Call (23 bytes, $1848–$185E)
; Op $36, 3 bytes: a subroutine call in the script: .ScriptReturn = the
; address of the next op, and the script continues at arg 1-2 (same
; bank): C2Script_Ptr = arg - 1 and A = 1, which C2Scene_TaskRunScript
; adds. There is one return slot, so calls do not nest.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000, DB=$00 (low WRAM: the task record);
;        C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  M=0, X=0; A = 1; X = the task, Y = 1; C2Script_Ptr = arg - 1
; No calls.
C2Script_Call:
    LDX.b !C2Scene_TaskCur
    LDA.b !C2Script_Ptr
    CLC
    ADC.w #3
    STA.w C2Scene_Task.ScriptReturn,X
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    DEC A
    STA.b !C2Script_Ptr
    LDA.w #1
    RTS

; $C2:185F — C2Script_Return (12 bytes, $185F–$186A)
; Op $37, 1 byte: returns from C2Script_Call: the script continues at
; .ScriptReturn (C2Script_Ptr = it - 1, A = 1).
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000, DB=$00 (low WRAM: the task record);
;        C2Scene_TaskCur = the task
; Exit:  M=0, X=0; A = 1; X = the task
; No calls.
C2Script_Return:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.ScriptReturn,X
    DEC A
    STA.b !C2Script_Ptr
    LDA.w #1
    RTS

; $C2:186B — C2Script_Wait (35 bytes, $186B–$188D)
; Op $38, 2 bytes: waits arg 1 frames, counted in .ScriptWait as
; C2Script_MoveFrames counts: 0 loads it with arg 1 and stops, then -1
; per frame; at 0 it advances 2. Arg 1 = 0 waits for good.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000, DB=$00 (low WRAM: the task record);
;        C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = 2 (advance) or 0 (Z=1, C=0: wait)
; No calls.
C2Script_Wait:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.ScriptWait,X
    BNE .count
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.ScriptWait,X
    BRA .wait
.count:
    DEC.w C2Scene_Task.ScriptWait,X
    BNE .wait
    REP #$20
    LDA.w #2
    RTS
.wait:
    REP #$20
    TDC
    CLC
    RTS

; $C2:188E — C2Script_WaitAnimating (38 bytes, $188E–$18B3)
; Op $39, 2 bytes: C2Script_Wait, running the task's animation
; (C2Anim_Run) on each frame it waits.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000, DB=$00 (low WRAM: the task record);
;        C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  advance: M=0, X=0, A = 2, X = the task. Wait: M=0, X=0, A = 0
;        (Z=1), C=0 (the animation's carry is dropped); X, Y as
;        C2Anim_Run leaves them
; Calls: C2Anim_Run.
C2Script_WaitAnimating:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.ScriptWait,X
    BNE .count
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.ScriptWait,X
    BRA .wait
.count:
    DEC.w C2Scene_Task.ScriptWait,X
    BNE .wait
    REP #$20
    LDA.w #2
    RTS
.wait:
    JSR C2Anim_Run
    REP #$20
    TDC
    CLC
    RTS

; $C2:18B4 — C2Script_StopIfOlder (19 bytes, $18B4–$18C6)
; Op $3A, 3 bytes: compares arg 1-2 with the task's age (.Frames, +1
; per frame it has run). While .Frames <= arg it advances 3 at once;
; once .Frames > arg it stops here (A = 0). The task still returns C=0,
; so C2Scene_TaskRunAll keeps adding 1 to the 16-bit .Frames; it stays
; stopped until .Frames wraps to 0, and then advances. Why a script would want this is not
; traced.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000, DB=$00 (low WRAM: the task record);
;        C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task, Y = 1; A = 3 (advance) or 0 (Z=1, C=0)
; No calls.
C2Script_StopIfOlder:
    LDX.b !C2Scene_TaskCur
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    CMP.w C2Scene_Task.Frames,X
    BCC .stop
    LDA.w #3
    RTS
.stop:
    TDC
    CLC
    RTS

; $C2:18C7 — C2Script_SoundCmd18 (9 bytes, $18C7–$18CF)
; Op $3B, 3 bytes: C2Script_PlaySfx with sound command C2Scene_SoundCmd18
; instead of Audio_CmdPlaySfx: it sets the command byte and branches to
; C2Script_PlaySfx_SetArgs.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_PlaySfx (M=0, X=0, DP=$0000, DB=$00)
; Calls: C2Scene_QueueSoundCmd (through C2Script_PlaySfx_SetArgs).
C2Script_SoundCmd18:
    SEP #$20
    LDA.b #!C2Scene_SoundCmd18
    STA.w !C2Scene_SoundCmdBuf
    BRA C2Script_PlaySfx_SetArgs

; $C2:18D0 — C2Script_PlaySfx (33 bytes, $18D0–$18F0)
; Op $3C, 3 bytes: queues sound command Audio_CmdPlaySfx with arg 1 and
; arg 2 as its first two argument bytes (the third is left as it was) at
; rank 0 (C2Scene_QueueSoundCmd: it replaces any queued command unless
; one is being sent; the refusal is not checked). C2Script_SoundCmd18
; enters at the sub-entry C2Script_PlaySfx_SetArgs with its own command
; byte.
; Callers note: none direct (C2Script_OpTable); C2Script_PlaySfx_SetArgs: BRA
;   from C2Script_SoundCmd18 ($C2:18CE).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Script_Ptr), DB=$00 (low
;        WRAM: the sound buffer and the driver block); C2Script_Ptr on
;        the opcode. C2Script_PlaySfx_SetArgs: the same with M=1 and the
;        command byte stored
; Exit:  M=0, X=0; A = 3; Y = 2; C as C2Scene_QueueSoundCmd leaves it;
;        C2Scene_SoundCmdBuf bytes 0-2 and C2Scene_SoundCmdPrio = 0 set
; Calls: C2Scene_QueueSoundCmd.
C2Script_PlaySfx:
    SEP #$20
    LDA.b #!Audio_CmdPlaySfx
    STA.w !C2Scene_SoundCmdBuf
C2Script_PlaySfx_SetArgs:       ; header: see C2Script_PlaySfx
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w !C2Scene_SoundCmdBuf+1
    INY
    LDA.b [!C2Script_Ptr],Y
    STA.w !C2Scene_SoundCmdBuf+2
    STZ.w !C2Scene_SoundCmdPrio
    JSR C2Scene_QueueSoundCmd
    REP #$20
    LDA.w #3
    RTS

; $C2:18F1 — C2Script_SoundCmd10IfClear (8 bytes, $18F1–$18F8)
; Op $3D, 2 bytes: C2Script_SoundCmd10 unless C2Scene_Unk7F01ED is
; non-zero: then it branches to C2Script_SoundCmd10_Done, which only
; advances 2. Otherwise it falls into C2Script_SoundCmd10.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000, DB=$00 (low WRAM; the flag
;        is read long); C2Script_Ptr on the opcode
; Exit:  as C2Script_SoundCmd10 (skipped: M=0, X=0, A = 2)
; Calls: C2Scene_QueueSoundCmd (through C2Script_SoundCmd10).
C2Script_SoundCmd10IfClear:
    SEP #$20
    LDA.l !C2Scene_Unk7F01ED
    BNE C2Script_SoundCmd10_Done

; $C2:18F9 — C2Script_SoundCmd10 (38 bytes, $18F9–$191E)
; Op $4A, 2 bytes: queues sound command C2Scene_SoundCmd10 with arg 1
; and C2Scene_SoundArgUnused ($FF) as its other two argument bytes, at
; rank 0 (C2Scene_QueueSoundCmd), and also stores arg 1 in
; C2Scene_Unk02AE (which C2Scene_LoadScene fills from Menu_Config+$1E:
; probably the scene's current music, unverified). The sub-entry
; C2Script_SoundCmd10_Done (the advance) is where
; C2Script_SoundCmd10IfClear skips to.
; Callers note: none direct (C2Script_OpTable); C2Script_SoundCmd10_Done:
;   BNE from C2Script_SoundCmd10IfClear ($C2:18F7).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Script_Ptr), DB=$00 (low
;        WRAM: the sound buffer and the driver block); C2Script_Ptr on
;        the opcode. C2Script_SoundCmd10_Done: M=1
; Exit:  M=0, X=0; A = 2; Y = 1 (not when skipped); C as
;        C2Scene_QueueSoundCmd leaves it
; Calls: C2Scene_QueueSoundCmd.
C2Script_SoundCmd10:
    SEP #$20
    LDA.b #!C2Scene_SoundCmd10
    STA.w !C2Scene_SoundCmdBuf
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w !C2Scene_SoundCmdBuf+1
    STA.w !C2Scene_Unk02AE
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !C2Scene_SoundCmdBuf+2
    STA.w !C2Scene_SoundCmdBuf+3
    STZ.w !C2Scene_SoundCmdPrio
    JSR C2Scene_QueueSoundCmd
C2Script_SoundCmd10_Done:       ; header: see C2Script_SoundCmd10
    REP #$20
    LDA.w #2
    RTS

; $C2:191F — C2Script_SoundCmd (40 bytes, $191F–$1946)
; Op $4B, 5 bytes: queues the sound command arg 1 with argument bytes arg
; 2-4, at rank 0 (C2Scene_QueueSoundCmd).
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Script_Ptr), DB=$00 (low
;        WRAM: the sound buffer and the driver block); C2Script_Ptr on
;        the opcode
; Exit:  M=0, X=0; A = 5; Y = 4; C as C2Scene_QueueSoundCmd leaves it
; Calls: C2Scene_QueueSoundCmd.
C2Script_SoundCmd:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w !C2Scene_SoundCmdBuf
    INY
    LDA.b [!C2Script_Ptr],Y
    STA.w !C2Scene_SoundCmdBuf+1
    INY
    LDA.b [!C2Script_Ptr],Y
    STA.w !C2Scene_SoundCmdBuf+2
    INY
    LDA.b [!C2Script_Ptr],Y
    STA.w !C2Scene_SoundCmdBuf+3
    STZ.w !C2Scene_SoundCmdPrio
    JSR C2Scene_QueueSoundCmd
    REP #$20
    LDA.w #5
    RTS

; $C2:1947 — C2Script_DrawLayer (18 bytes, $1947–$1958)
; Op $3E, 2 bytes: redraws BG layer arg 1 from its map
; (C2Scene_DrawBgLayer), e.g. after C2Script_SetMapCell. That redraw
; DMAs straight to VRAM, so it relies on running in vblank (the script
; tasks run from the NMI).
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Scene_DrawBgLayer's work
;        area), DB=$00 (low WRAM; C2Scene_DrawBgLayer sets and restores
;        its own); C2Script_Ptr on the opcode; vblank
; Exit:  M=0, X=0; A = 2; X, Y clobbered; C2Tmp_00-$1B changed, the
;        layer's scroll shadows set, DMA channel 7 registers changed
;        (C2Scene_DrawBgLayer)
; Calls: C2Scene_DrawBgLayer.
C2Script_DrawLayer:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Scene_DrawLayer
    JSR C2Scene_DrawBgLayer
    REP #$20
    LDA.w #2
    RTS

; $C2:1959 — C2Script_MoveToX (105 bytes, $1959–$19C1)
; Op $3F, 5 bytes: moves the task along X until .SprX = arg 1-2, at the
; speed of its X velocity. The first frame (.OpState 0, then 1) stores
; the target in .OpTarget, turns the velocity toward it (C2Scene_NegateXVel
; when its sign points away: negative for a target left of .SprX,
; positive otherwise) and starts animation arg 3 (going left) or arg 4
; (going right) (C2Scene_SetAnim). Each frame, the first included: if
; .SprX equals the target it advances 5; else .XFrac/.SprX += the
; velocity, C2Scene_WrapTaskPos, C2Anim_Run, and it stops for the frame.
; Quirk, kept: only an exact hit ends it. A speed that steps past the
; target keeps going, around the wrapped map, until some step lands on
; it, and a velocity of 0 never arrives.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000, DB=$00 (low WRAM: the task
;        record); C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  arrived: M=0, X=0, A = 5, X = the task. Moving: M=0, X=0, A = 0
;        (Z=1), C=0; X, Y as C2Anim_Run leaves them
; Calls: C2Scene_NegateXVel, C2Scene_SetAnim, C2Scene_WrapTaskPos,
;   C2Anim_Run.
C2Script_MoveToX:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.OpState,X
    BNE .step
    INC.w C2Scene_Task.OpState,X
    REP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.OpTarget,X
    CMP.w C2Scene_Task.SprX,X
    BCS .right
    LDA.w C2Scene_Task.XVel,X
    BMI .anim_left
    JSR C2Scene_NegateXVel
.anim_left:
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    JSR C2Scene_SetAnim
    BRA .step
.right:
    LDA.w C2Scene_Task.XVel,X
    BPL .anim_right
    JSR C2Scene_NegateXVel
.anim_right:
    LDY.w #4
    LDA.b [!C2Script_Ptr],Y
    JSR C2Scene_SetAnim
.step:
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    CMP.w C2Scene_Task.OpTarget,X
    BEQ .arrived
    CLC
    LDA.w C2Scene_Task.XFrac,X
    ADC.w C2Scene_Task.XVelFrac,X
    STA.w C2Scene_Task.XFrac,X
    LDA.w C2Scene_Task.SprX,X
    ADC.w C2Scene_Task.XVel,X
    STA.w C2Scene_Task.SprX,X
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    REP #$20
    TDC
    CLC
    RTS
.arrived:
    LDA.w #5
    RTS

; $C2:19C2 — C2Script_MoveToY (105 bytes, $19C2–$1A2A)
; Op $40, 5 bytes: C2Script_MoveToX along Y: target .SprY = arg 1-2,
; C2Scene_NegateYVel, animation arg 3 when going up (target above .SprY)
; and arg 4 when going down; .YFrac/.SprY += the Y velocity. The same
; exact-hit quirk.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000, DB=$00 (low WRAM: the task
;        record); C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  arrived: M=0, X=0, A = 5, X = the task. Moving: M=0, X=0, A = 0
;        (Z=1), C=0; X, Y as C2Anim_Run leaves them
; Calls: C2Scene_NegateYVel, C2Scene_SetAnim, C2Scene_WrapTaskPos,
;   C2Anim_Run.
C2Script_MoveToY:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.OpState,X
    BNE .step
    INC.w C2Scene_Task.OpState,X
    REP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    STA.w C2Scene_Task.OpTarget,X
    CMP.w C2Scene_Task.SprY,X
    BCS .down
    LDA.w C2Scene_Task.YVel,X
    BMI .anim_up
    JSR C2Scene_NegateYVel
.anim_up:
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    JSR C2Scene_SetAnim
    BRA .step
.down:
    LDA.w C2Scene_Task.YVel,X
    BPL .anim_down
    JSR C2Scene_NegateYVel
.anim_down:
    LDY.w #4
    LDA.b [!C2Script_Ptr],Y
    JSR C2Scene_SetAnim
.step:
    REP #$20
    LDA.w C2Scene_Task.SprY,X
    CMP.w C2Scene_Task.OpTarget,X
    BEQ .arrived
    CLC
    LDA.w C2Scene_Task.YFrac,X
    ADC.w C2Scene_Task.YVelFrac,X
    STA.w C2Scene_Task.YFrac,X
    LDA.w C2Scene_Task.SprY,X
    ADC.w C2Scene_Task.YVel,X
    STA.w C2Scene_Task.SprY,X
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    REP #$20
    TDC
    CLC
    RTS
.arrived:
    LDA.w #5
    RTS

; $C2:1A2B — C2Script_Halt2 (2 bytes, $1A2B–$1A2C)
; Op $41, 1 byte: the same code as C2Script_Halt (op $06): stops (A = 0,
; Z=1) without advancing, every frame; the task stays.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000 (TDC loads 0), DB any (no data accesses)
; Exit:  M=0, X=0; A = 0
; No calls.
C2Script_Halt2:
    TDC
    RTS

; $C2:1A2D — C2Script_SpawnScriptLow (22 bytes, $1A2D–$1A42)
; Op $43, 4 bytes: C2Script_SpawnScript in records 0-3: starts a script
; task (C2Scene_TaskSpawnScriptLow) on the script at arg 1-2 in bank
; arg 3.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000, DB=$00 (low WRAM: the task records);
;        C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  M=0, X=0; A = 4; X = the new record; Y as C2Scene_TaskSpawn
;        leaves it; C2Tmp_01, C2Tmp_08 and C2Tmp_0A changed
; Calls: C2Scene_TaskSpawnScriptLow.
C2Script_SpawnScriptLow:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    JSR C2Scene_TaskSpawnScriptLow
    REP #$20
    LDA.w #4
    RTS

; $C2:1A43 — C2Script_SpawnTaskLow (15 bytes, $1A43–$1A51)
; Op $42, 3 bytes: C2Script_SpawnTask in records 0-3
; (C2Scene_TaskSpawnLow): handler arg 1-2.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000, DB=$00 (low WRAM: the task records);
;        C2Script_Ptr on the opcode, C2Scene_TaskCur = the task
; Exit:  M=0, X=0; A = 3; X, Y as C2Scene_TaskSpawnLow leaves them;
;        C2Tmp_08 = the handler
; Calls: C2Scene_TaskSpawnLow.
C2Script_SpawnTaskLow:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    JSR C2Scene_TaskSpawnLow
    REP #$20
    LDA.w #3
    RTS

; $C2:1A52 — C2Script_SetListBit7 (30 bytes, $1A52–$1A6F)
; Op $44, 3 bytes: sets C2Scene_ListEntryBit7 in the first byte of entry
; arg 2 of list arg 1 (0 = C2Scene_ListA, 1 = ListB, 2 = ListC: the
; helper in C2Script_ListEntryTable leaves the entry's address in
; C2Tmp_10/$11; this adds bank $7E). What the bit means is not traced.
; Quirk, kept: the list number is not checked; 3 or more jumps through
; the code after the table.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Tmp_00, C2Tmp_10-$12),
;        DB any (the entry is reached long); C2Script_Ptr on the opcode;
;        A's high byte 0 (the helpers use the entry number as 16 bits:
;        true from C2Scene_TaskRunScript, whose A is the opcode * 2)
; Exit:  M=0, X=0; A = 3; X = list * 2, Y = 2; C2Tmp_00/$01 = the entry
;        number, C2Tmp_10-$12 = the entry's address
; Calls: C2Script_ListAEntry, C2Script_ListBEntry or C2Script_ListCEntry
;   (JSR (C2Script_ListEntryTable,X)).
!C2Script_ListIndex = !C2Tmp_00         ; 16-bit entry number (the helpers' scratch)
!C2Script_ListEntry = !C2Tmp_10         ; 24-bit address of the entry
C2Script_SetListBit7:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    ASL A
    TAX
    JSR (C2Script_ListEntryTable,X)
    SEP #$20
    LDA.b #!Bank7E
    STA.b !C2Script_ListEntry+2
    LDA.b [!C2Script_ListEntry]
    ORA.b #!C2Scene_ListEntryBit7
    STA.b [!C2Script_ListEntry]
    REP #$20
    LDA.w #3
    RTS

; $C2:1A70 — C2Script_ListEntryTable (3 words, $1A70–$1A75)
; The helper per list number (C2Script_SetListBit7 and
; C2Script_ClearListBit7: JSR (T,X) with X = the list * 2).
C2Script_ListEntryTable:
    dw C2Script_ListAEntry      ; 0: C2Scene_ListA
    dw C2Script_ListBEntry      ; 1: C2Scene_ListB
    dw C2Script_ListCEntry      ; 2: C2Scene_ListC

; $C2:1A76 — C2Script_ListAEntry (20 bytes, $1A76–$1A89)
; C2Tmp_10/$11 = the 16-bit address of entry arg 2 of C2Scene_ListA
; (entry * 7, as entry * 8 - entry, + the list).
; Callers note: none direct (C2Script_ListEntryTable).
; Entry: M=1, X=0, DP=$0000, DB any; Y = 1 (on arg 1), C2Script_Ptr on
;        the opcode; A's high byte 0
; Exit:  M=0, X=0; A = the address; Y = 2; C2Tmp_00/$01 = the entry
;        number; X unchanged
; No calls.
C2Script_ListAEntry:
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    STA.b !C2Script_ListIndex
    ASL A
    ASL A
    ASL A
    SEC
    SBC.b !C2Script_ListIndex
    CLC
    ADC.w #!C2Scene_ListA&$FFFF
    STA.b !C2Script_ListEntry
    RTS

; $C2:1A8A — C2Script_ListBEntry (17 bytes, $1A8A–$1A9A)
; C2Tmp_10/$11 = the address of entry arg 2 of C2Scene_ListB (entry * 3
; + the list).
; Callers note: none direct (C2Script_ListEntryTable).
; Entry/Exit: as C2Script_ListAEntry (M=1, X=0, DP=$0000, DB any on
;        entry; M=0, X=0 on exit)
; No calls.
C2Script_ListBEntry:
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    STA.b !C2Script_ListIndex
    ASL A
    ADC.b !C2Script_ListIndex
    CLC
    ADC.w #!C2Scene_ListB&$FFFF
    STA.b !C2Script_ListEntry
    RTS

; $C2:1A9B — C2Script_ListCEntry (17 bytes, $1A9B–$1AAB)
; C2Tmp_10/$11 = the address of entry arg 2 of C2Scene_ListC (entry * 3
; + the list).
; Callers note: none direct (C2Script_ListEntryTable).
; Entry/Exit: as C2Script_ListAEntry (M=1, X=0, DP=$0000, DB any on
;        entry; M=0, X=0 on exit)
; No calls.
C2Script_ListCEntry:
    INY
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    STA.b !C2Script_ListIndex
    ASL A
    ADC.b !C2Script_ListIndex
    CLC
    ADC.w #!C2Scene_ListC&$FFFF
    STA.b !C2Script_ListEntry
    RTS

; $C2:1AAC — C2Script_ClearListBit7 (30 bytes, $1AAC–$1AC9)
; Op $45, 3 bytes: C2Script_SetListBit7, clearing the bit instead.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Tmp_00, C2Tmp_10-$12),
;        DB any (the entry is reached long); C2Script_Ptr on the opcode;
;        A's high byte 0 (as C2Script_SetListBit7)
; Exit:  as C2Script_SetListBit7
; Calls: C2Script_ListAEntry, C2Script_ListBEntry or C2Script_ListCEntry
;   (JSR (C2Script_ListEntryTable,X)).
C2Script_ClearListBit7:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    ASL A
    TAX
    JSR (C2Script_ListEntryTable,X)
    SEP #$20
    LDA.b #!Bank7E
    STA.b !C2Script_ListEntry+2
    LDA.b [!C2Script_ListEntry]
    AND.b #!C2Scene_ListEntryBit7^$FF
    STA.b [!C2Script_ListEntry]
    REP #$20
    LDA.w #3
    RTS

; $C2:1ACA — C2Script_AddTaskByte (23 bytes, $1ACA–$1AE0)
; Op $46, 3 bytes: task byte arg 1 += arg 2 (8-bit, wrapping).
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Scene_TaskCur), DB=$00
;        (low WRAM: (C2Scene_TaskCur),Y reaches the record through DB);
;        B=0 (A = the opcode x 2 from C2Scene_TaskRunScript; the TAX/TXY
;        copy all 16 bits); C2Script_Ptr on the opcode, C2Scene_TaskCur =
;        the task
; Exit:  M=0, X=0; A = 3; X = Y = arg 1
; No calls.
C2Script_AddTaskByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    INY
    LDA.b [!C2Script_Ptr],Y
    TXY
    CLC
    ADC.b (!C2Scene_TaskCur),Y
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #3
    RTS

; $C2:1AE1 — C2Script_SubTaskByte (26 bytes, $1AE1–$1AFA)
; Op $47, 3 bytes: task byte arg 1 -= arg 2 (8-bit, wrapping).
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Scene_TaskCur), DB=$00
;        (low WRAM: (C2Scene_TaskCur),Y reaches the record through DB);
;        B=0 (A = the opcode x 2 from C2Scene_TaskRunScript; the TAX/TAY
;        copy all 16 bits); C2Script_Ptr on the opcode, C2Scene_TaskCur =
;        the task
; Exit:  M=0, X=0; A = 3; X = Y = arg 1
; No calls.
C2Script_SubTaskByte:
    SEP #$20
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    TAY
    LDA.b (!C2Scene_TaskCur),Y
    LDY.w #2
    SEC
    SBC.b [!C2Script_Ptr],Y
    TXY
    STA.b (!C2Scene_TaskCur),Y
    REP #$20
    LDA.w #3
    RTS

; $C2:1AFB — C2Script_AddRamByte (26 bytes, $1AFB–$1B14)
; Op $48, 4 bytes: RAM byte at arg 1-2 (through DB) += arg 3.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000 (C2Script_Ptr), DB=$00 (the address is
;        absolute: low WRAM or I/O); C2Script_Ptr on the opcode
; Exit:  M=0, X=0; A = 4; X = arg 1-2, Y = 3
; No calls.
C2Script_AddRamByte:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    SEP #$20
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    CLC
    ADC.w !Eng_PtrBase,X
    STA.w !Eng_PtrBase,X
    REP #$20
    LDA.w #4
    RTS

; $C2:1B15 — C2Script_SubRamByte (26 bytes, $1B15–$1B2E)
; Op $49, 4 bytes: RAM byte at arg 1-2 (through DB) -= arg 3.
; Callers note: none direct (C2Script_OpTable).
; Entry/Exit: as C2Script_AddRamByte (M=0, X=0, DP=$0000, DB=$00 on
;        entry; M=0, X=0, A = 4, X = arg 1-2, Y = 3 on exit)
; No calls.
C2Script_SubRamByte:
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    TAX
    LDY.w #3
    SEP #$20
    LDA.w !Eng_PtrBase,X
    SEC
    SBC.b [!C2Script_Ptr],Y
    STA.w !Eng_PtrBase,X
    REP #$20
    LDA.w #4
    RTS

; $C2:1B2F — C2Script_CopyMapBlock (177 bytes, $1B2F–$1BDF)
; Op $4F, 9 bytes: copies a block of metatile numbers from one BG layer
; map to another place (C2Scene_BgMaps, bank $7E; 96 bytes per row):
; source layer arg 1 at column arg 2, row arg 3; destination layer arg 4
; at column arg 5, row arg 6; arg 7 bytes wide, arg 8 rows high. Layer 1
; is C2Scene_BgMaps, any other value layer 2's map after it (it does not
; use C2Scene_LayerMaps). Rows are read through C2Tmp_10 (long) and
; written through WMADD/WMDATA. Only the maps change; the screen is
; redrawn elsewhere (C2Script_DrawLayer).
; Quirk, kept: a width or height of 0 copies 256 (DEC/BNE). No wrap at
; the map's edge: a block past column 95 runs into the next row.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Tmp_00-$15), DB=$00
;        (WRMPYA/WRMPYB/RDMPYL, WMADD/WMDATA); C2Script_Ptr on the
;        opcode
; Exit:  M=0, X=0; A = 9; X = the last row's destination, Y = the width;
;        C2Tmp_00-$02 and C2Tmp_10-$15 changed; WMADD changed
; No calls.
!C2Script_BlockWidth = !C2Tmp_00        ; bytes per row (arg 7)
!C2Script_BlockRows = !C2Tmp_01         ; rows left (arg 8)
!C2Script_BlockCount = !C2Tmp_02        ; bytes left in this row
!C2Script_BlockSrc = !C2Tmp_10          ; 24-bit source row (bank $7E)
!C2Script_BlockDest = !C2Tmp_13         ; 16-bit destination row (bank $7E, by WMADD; +2 is set to $7E but unused)
C2Script_CopyMapBlock:
    SEP #$20
    TDC
    LDA.b #!Bank7E
    STA.b !C2Script_BlockSrc+2
    STA.b !C2Script_BlockDest+2
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    CMP.b #1
    BNE .src_layer2
    LDX.w #!C2Scene_BgMaps&$FFFF
    BRA .src
.src_layer2:
    LDX.w #(!C2Scene_BgMaps&$FFFF)+!C2Scene_MapBytes
.src:
    STX.b !C2Script_BlockSrc
    LDY.w #3
    LDA.b [!C2Script_Ptr],Y
    STA.w WRMPYA
    LDA.b #!C2Scene_MapCols
    STA.w WRMPYB
    DEY
    CLC
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    ADC.w RDMPYL
    CLC
    ADC.b !C2Script_BlockSrc
    STA.b !C2Script_BlockSrc
    SEP #$20
    TDC
    LDY.w #4
    LDA.b [!C2Script_Ptr],Y
    CMP.b #1
    BNE .dest_layer2
    LDX.w #!C2Scene_BgMaps&$FFFF
    BRA .dest
.dest_layer2:
    LDX.w #(!C2Scene_BgMaps&$FFFF)+!C2Scene_MapBytes
.dest:
    STX.b !C2Script_BlockDest
    LDY.w #6
    LDA.b [!C2Script_Ptr],Y
    STA.w WRMPYA
    LDA.b #!C2Scene_MapCols
    STA.w WRMPYB
    DEY
    CLC
    LDA.b [!C2Script_Ptr],Y
    REP #$20
    ADC.w RDMPYL
    CLC
    ADC.b !C2Script_BlockDest
    STA.b !C2Script_BlockDest
    SEP #$20
    TDC
    LDY.w #7
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_BlockWidth
    INY
    LDA.b [!C2Script_Ptr],Y
    STA.b !C2Script_BlockRows
.row:
    LDA.b !C2Script_BlockWidth
    STA.b !C2Script_BlockCount
    LDX.b !C2Script_BlockDest
    STX.w WMADDL
    LDA.b #!Bank7E
    STA.w WMADDH
    LDY.w #0
.byte:
    LDA.b [!C2Script_BlockSrc],Y
    STA.w WMDATA
    INY
    DEC.b !C2Script_BlockCount
    BNE .byte
    REP #$20
    CLC
    LDA.b !C2Script_BlockSrc
    ADC.w #!C2Scene_MapCols
    STA.b !C2Script_BlockSrc
    CLC
    LDA.b !C2Script_BlockDest
    ADC.w #!C2Scene_MapCols
    STA.b !C2Script_BlockDest
    TDC
    SEP #$20
    DEC.b !C2Script_BlockRows
    BNE .row
    REP #$20
    LDA.w #!C2Script_CopyMapBlockLen
    RTS

; $C2:1BE0 — C2Script_DrawMetatile (161 bytes, $1BE0–$1C80)
; Op $50, 5 bytes: draws metatile arg 4 at cell (column arg 2, row arg
; 3) of BG layer arg 1's tilemap in VRAM, by queuing two VRAM DMAs of
; C2Scene_MetatileRowBytes each (C2Scene_VramQ): the metatile's top row
; (two tile words) to the cell's tilemap address and its bottom row to
; the tilemap row below. The source is the layer's metatile set in bank
; $7E (C2Scene_Metatiles, + C2Scene_MetatileSetBytes for layer 2) + the
; metatile * 8; the destination is the BG1 or BG2 map
; (C2Scene_Bg1MapVram / Bg2MapVram) + (row * 2 AND $1F) * 32 + (column *
; 2 AND $1F), + Bg_ScreenWords when column * 2 has bit 5 set (the right
; 32x32 screen). Layer 1 picks the BG1 set, any other value BG2. The map
; bytes are not changed (C2Script_SetMapCell does that).
; Quirk, kept: no check that the queue has room.
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0 (SEP #$20 here), DP=$0000 (C2Tmp_00-$02, C2Tmp_10-$14,
;        the queue), DB=$00 (low WRAM: the entries' .Bank bytes are stored
;        absolute through DB); C2Script_Ptr on the opcode
; Exit:  M=0, X=0 (REP #$30); A = 5; X = the first entry's offset, Y =
;        4; C2Scene_VramQEnd + 16; C2Scene_VramQLock = 0; C2Tmp_00-$03,
;        C2Tmp_10/$11 and C2Tmp_13/$14 changed
; No calls.
!C2Script_TileCol = !C2Tmp_00           ; 16-bit tile column 0-63 (column * 2 AND $3F)
!C2Script_ScreenCol = !C2Tmp_02         ; 16-bit tile column within the screen
!C2Script_TileSrc = !C2Tmp_10           ; 16-bit address of the metatile (bank $7E)
!C2Script_TileVram = !C2Tmp_13          ; 16-bit VRAM word address of the cell
C2Script_DrawMetatile:
    SEP #$20
    TDC
    LDY.w #1
    LDA.b [!C2Script_Ptr],Y
    CMP.b #1
    BNE .layer2
    LDX.w #!C2Scene_Metatiles&$FFFF
    LDY.w #!C2Scene_Bg1MapVram
    BRA .cell
.layer2:
    LDX.w #(!C2Scene_Metatiles&$FFFF)+!C2Scene_MetatileSetBytes
    LDY.w #!C2Scene_Bg2MapVram
.cell:
    STX.b !C2Script_TileSrc
    STY.b !C2Script_TileVram
    LDY.w #2
    LDA.b [!C2Script_Ptr],Y
    ASL A
    AND.b #!C2Scene_TileColMask
    STA.b !C2Script_TileCol
    STZ.b !C2Script_TileCol+1
    AND.b #!C2Scene_ScreenTileMask
    STA.b !C2Script_ScreenCol
    STZ.b !C2Script_ScreenCol+1
    INY
    LDA.b [!C2Script_Ptr],Y
    ASL A
    AND.b #!C2Scene_ScreenTileMask
    REP #$20
    ASL A                       ; row * 32 (C=0 after: the value is < $400)
    ASL A
    ASL A
    ASL A
    ASL A
    ADC.b !C2Script_TileVram
    CLC
    ADC.b !C2Script_ScreenCol
    STA.b !C2Script_TileVram
    LDA.b !C2Script_TileCol
    BIT.w #!C2Scene_MapScreenCols
    BEQ .left_screen
    CLC
    LDA.b !C2Script_TileVram
    ADC.w #!Bg_ScreenWords
    STA.b !C2Script_TileVram
.left_screen:
    INY
    LDA.b [!C2Script_Ptr],Y
    AND.w #!Eng_LowByteMask
    ASL A                       ; metatile * 8 (C=0 after)
    ASL A
    ASL A
    ADC.b !C2Script_TileSrc
    STA.b !C2Script_TileSrc
    SEP #$30
    LDX.b !C2Scene_VramQEnd
    INC.b !C2Scene_VramQLock
    LDA.b #!Bank7E
    STA.w C2Scene_VramQ.Bank,X
    STA.w C2Scene_VramQ[1].Bank,X
    LDA.b #!VMAIN_IncAfterHigh
    STA.b C2Scene_VramQ.Vmain,X
    STA.b C2Scene_VramQ[1].Vmain,X
    REP #$20
    LDA.b !C2Script_TileSrc
    STA.b C2Scene_VramQ.Src,X
    CLC
    ADC.w #!C2Scene_MetatileRowBytes
    STA.b C2Scene_VramQ[1].Src,X
    LDA.b !C2Script_TileVram
    STA.b C2Scene_VramQ.Dest,X
    CLC
    ADC.w #!C2Scene_TileRowWords
    STA.b C2Scene_VramQ[1].Dest,X
    LDA.w #!C2Scene_MetatileRowBytes
    STA.b C2Scene_VramQ.Size,X
    STA.b C2Scene_VramQ[1].Size,X
    SEP #$20
    TXA
    CLC
    ADC.b #(2*!C2Scene_VramQEntrySize)
    STA.b !C2Scene_VramQEnd
    STZ.b !C2Scene_VramQLock
    REP #$30
    LDA.w #5
    RTS

; $C2:1C81 — C2Script_End (3 bytes, $1C81–$1C83)
; Op $52, 1 byte: stops (A = 0, Z=1) with C=1, which ends the task when
; C2Scene_TaskRunScript is its handler (C2Scene_TaskRunAll frees it).
; Callers note: none direct (C2Script_OpTable).
; Entry: M=0, X=0, DP=$0000 (TDC loads 0), DB any (no data accesses)
; Exit:  M=0, X=0; A = 0, C=1
; No calls.
C2Script_End:
    TDC
    SEC
    RTS

; ============================================================
; Scene task motion helpers ($C2:1C84–$C2:1CF4)
; ============================================================
; Used by the script ops (C2Script_MoveFrames, C2Script_MoveToX/Y) and by
; other task handlers on the running task's record (C2Scene_TaskCur).

org $C21C84
; $C2:1C84 — C2Scene_NegateXVel (26 bytes, $1C84–$1C9D)
; Negates the task's X velocity as one 32-bit value (.XVelFrac/.XVel:
; invert both words and add 1 with the carry), turning it around.
; Callers (4 JSR sites): C2Script_MoveToX ($C2:1979, $C2:198B) and unmatched ($C2:52D0, $C2:5429).
; Entry: M=0, X=0 with X = the task, DP any, DB with low WRAM at
;        $0000-$1FFF
; Exit:  M=0, X=0; A = the new .XVel; X, Y unchanged
; No calls.
C2Scene_NegateXVel:
    LDA.w C2Scene_Task.XVelFrac,X
    EOR.w #!Eng_Invert16
    CLC
    ADC.w #1
    STA.w C2Scene_Task.XVelFrac,X
    LDA.w C2Scene_Task.XVel,X
    EOR.w #!Eng_Invert16
    ADC.w #0
    STA.w C2Scene_Task.XVel,X
    RTS

; $C2:1C9E — C2Scene_NegateYVel (26 bytes, $1C9E–$1CB7)
; C2Scene_NegateXVel for .YVelFrac/.YVel.
; Callers (4 JSR sites): C2Script_MoveToY ($C2:19E2, $C2:19F4) and unmatched ($C2:5319, $C2:5436).
; Entry/Exit: as C2Scene_NegateXVel (A = the new .YVel)
; No calls.
C2Scene_NegateYVel:
    LDA.w C2Scene_Task.YVelFrac,X
    EOR.w #!Eng_Invert16
    CLC
    ADC.w #1
    STA.w C2Scene_Task.YVelFrac,X
    LDA.w C2Scene_Task.YVel,X
    EOR.w #!Eng_Invert16
    ADC.w #0
    STA.w C2Scene_Task.YVel,X
    RTS

; $C2:1CB8 — C2Scene_WrapTaskPos (34 bytes, $1CB8–$1CD9)
; Wraps the task's position into the scene map: .SprX gets
; C2Scene_MapWidthPx (1536, the 96 metatile columns) added when it is
; negative or taken off when it is that or more (once, so it assumes the
; position moved by less than a map width); .SprY is taken AND
; C2Scene_MapHeightMask (the 64 rows: 1024 pixels).
; Callers (23 sites: 22 JSR, 1 JMP): C2Script_MoveFrames (JSR $C2:1640), C2Script_MoveToX (JSR
;   $C2:19B3), C2Script_MoveToY (JSR $C2:1A1C) and unmatched (JSR $C2:36F4, JSR $C2:383E, JSR
;   $C2:38CC, JSR $C2:3D05, JSR $C2:3D66, JSR $C2:3E26, JSR $C2:3E8A, JSR $C2:4457, JSR $C2:467C,
;   JSR $C2:46FD, JMP $C2:48E5, JSR $C2:4D93, JSR $C2:4F85, JSR $C2:5005, JSR $C2:5169, JSR
;   $C2:5238, JSR $C2:5257, JSR $C2:5550, JSR $C2:55C9, JSR $C2:55DF).
; Callers note (22 call sites, JSR and JMP, all unmatched except those
;   named): e.g. C2Script_MoveFrames ($C2:1640), C2Script_MoveToX
;   ($C2:19B3), C2Script_MoveToY ($C2:1A1C), $C2:36F4, JMP at $C2:48E5,
;   and $C2:55DF; $C2:5257 is a doubtful byte pattern.
; Entry: M=0, X=0, DP=$0000, DB with low WRAM at $0000-$1FFF;
;        C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .SprY; Y unchanged
; No calls.
C2Scene_WrapTaskPos:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,X
    BPL .not_negative
    CLC
    ADC.w #!C2Scene_MapWidthPx
    BRA .store_x
.not_negative:
    CMP.w #!C2Scene_MapWidthPx
    BCC .store_x
    SBC.w #!C2Scene_MapWidthPx
.store_x:
    STA.w C2Scene_Task.SprX,X
    LDA.w C2Scene_Task.SprY,X
    AND.w #!C2Scene_MapHeightMask
    STA.w C2Scene_Task.SprY,X
    RTS

; $C2:1CDA — C2Scene_SetAnim (27 bytes, $1CDA–$1CF4)
; Starts animation script A (low byte) on the running task: .AnimPtr =
; entry A of C2SceneRom_AnimTable, .AnimBank = C2SceneRom_AnimBank (the
; table's own bank), .AnimTimer = 0. The next C2Anim_Run starts it.
; Callers (37 sites: 34 JSR, 3 JMP): C2Script_SetAnim (JSR $C2:1614), C2Script_MoveToX (JSR
;   $C2:1981, JSR $C2:1993), C2Script_MoveToY (JSR $C2:19EA, JSR $C2:19FC) and unmatched (JSR
;   $C2:35CD, JMP $C2:397C, JMP $C2:39A7, JSR $C2:3CA7, JSR $C2:3CC7, JSR $C2:4336, JSR $C2:433D,
;   JSR $C2:4439, JSR $C2:45A0, JSR $C2:470F, JSR $C2:4747, JSR $C2:483B, JSR $C2:499C, JSR
;   $C2:4D11, JSR $C2:4D2F, JSR $C2:4D76, JSR $C2:4DC1, JSR $C2:4E9B, JSR $C2:4F1A, JSR $C2:501E,
;   JSR $C2:5087, JSR $C2:50EB, JSR $C2:5149, JSR $C2:51E5, JMP $C2:5488, JSR $C2:54BC, JSR
;   $C2:550B, JSR $C2:556A, JSR $C2:559F, JSR $C2:68D3, JSR $C2:7197, JSR $C2:71C4).
; Callers note (34 call sites, JSR and JMP, all unmatched except those
;   named): e.g. C2Script_SetAnim ($C2:1614), C2Script_MoveToX
;   ($C2:1981, $C2:1993), C2Script_MoveToY ($C2:19EA, $C2:19FC), JMP at $C2:397C and $C2:39A7, $C2:7197 and $C2:71C4; xref
;   also lists doubtful byte patterns at $C2:470F, $C2:48BB, $C2:48C2,
;   $C2:49B5, $C2:501E and $C2:559F.
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB with low WRAM at
;        $0000-$1FFF; A = the animation number; C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; A = C2SceneRom_AnimBank; Y unchanged
; No calls.
C2Scene_SetAnim:
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    LDA.l !C2SceneRom_AnimTable,X
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_Task.AnimPtr,X
    SEP #$20
    LDA.b #!C2SceneRom_AnimBank
    STA.w C2Scene_Task.AnimBank,X
    STZ.w C2Scene_Task.AnimTimer,X
    RTS

; ============================================================
; Scene tile upload task ($C2:1CF5–$C2:1DB4)
; ============================================================
; Started by script op $03 (C2Script_SpawnUnk1CF5). It reads the op's 9
; argument bytes through the script pointer it copied from the spawner
; (the pointer still on the op) and uploads a block to VRAM through the
; queue (C2Scene_VramQ), a part per frame. Its record is laid out as
; C2Scene_UploadTask.

; $C2:1CF5 — C2Scene_TaskUnk1CF5 (13 bytes, $1CF5–$1D01)
; Task handler: runs the state in .State (C2Scene_UploadTask; the record's
; .Unk02, 0 from C2Scene_TaskSpawn) through C2Scene_UploadTileStates: 0
; C2Scene_UploadTilesStart, 1 C2Scene_UploadTilesStep.
; Callers note: none direct; the handler C2Script_SpawnUnk1CF5 installs
;   (C2Scene_TaskRunAll calls it).
; Entry: M=1 (REP #$20 here), X=0 with X = the task, DP=$0000, DB=$00
;        (low WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  the state's (M=0, X=0; C=1 when the upload is done, which ends
;        the task)
; Calls: C2Scene_UploadTilesStart or C2Scene_UploadTilesStep (JMP
;   (C2Scene_UploadTileStates,X)).
C2Scene_TaskUnk1CF5:
    REP #$20
    LDA.w C2Scene_UploadTask.State,X
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    JMP (C2Scene_UploadTileStates,X)

; $C2:1D02 — C2Scene_UploadTileStates (2 words, $1D02–$1D05)
; The state handlers of C2Scene_TaskUnk1CF5 (JMP (T,X) with X = .State * 2).
C2Scene_UploadTileStates:
    dw C2Scene_UploadTilesStart     ; 0
    dw C2Scene_UploadTilesStep      ; 1

; $C2:1D06 — C2Scene_UploadTilesStart (70 bytes, $1D06–$1D4B)
; State 0: sets .State to 1 (a 16-bit INC, so +$03 would take a carry; it
; never does), then copies op $03's arguments from the spawning op
; (.OpPtr): .Src = arg 1-2, .SrcBank = arg 3, .Dest = arg 4-5 (a VRAM
; word address), .PerFrame = arg 6-7 and .Left = arg 8-9 (both in 32-byte
; units: probably 8x8 4-bit tiles). .PerFrame 0 means all at once
; (.PerFrame = .Left). Then falls into C2Scene_UploadTilesStep, so the
; first part goes this frame.
; Callers note: none direct (C2Scene_UploadTileStates).
; Entry: M=0, X=0, DP=$0000 (C2Tmp_10-$12), DB=$00 (low WRAM: the task
;        record); C2Scene_TaskCur = the task
; Exit:  as C2Scene_UploadTilesStep; C2Tmp_10-$12 = the op's address
; Calls: none (falls into C2Scene_UploadTilesStep).
!C2Scene_UploadOp = !C2Tmp_10           ; 24-bit address of the spawning op $03
C2Scene_UploadTilesStart:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_UploadTask.State,X
    LDA.w C2Scene_UploadTask.OpPtr,X
    STA.b !C2Scene_UploadOp
    SEP #$20
    LDA.w C2Scene_UploadTask.OpPtr+2,X
    STA.b !C2Scene_UploadOp+2
    LDY.w #3
    LDA.b [!C2Scene_UploadOp],Y
    STA.w C2Scene_UploadTask.SrcBank,X
    REP #$20
    LDY.w #1
    LDA.b [!C2Scene_UploadOp],Y
    STA.w C2Scene_UploadTask.Src,X
    LDY.w #4
    LDA.b [!C2Scene_UploadOp],Y
    STA.w C2Scene_UploadTask.Dest,X
    LDY.w #6
    LDA.b [!C2Scene_UploadOp],Y
    STA.w C2Scene_UploadTask.PerFrame,X
    LDY.w #8
    LDA.b [!C2Scene_UploadOp],Y
    STA.w C2Scene_UploadTask.Left,X
    LDA.w C2Scene_UploadTask.PerFrame,X
    BNE C2Scene_UploadTilesStep
    LDA.w C2Scene_UploadTask.Left,X
    STA.w C2Scene_UploadTask.PerFrame,X

; $C2:1D4C — C2Scene_UploadTilesStep (105 bytes, $1D4C–$1DB4)
; State 1, each frame: queues the next part, min(.PerFrame, .Left) units
; of 32 bytes, as one VRAM DMA (C2Scene_VramQ: .Bank = .SrcBank, .Src =
; .Src, .Dest = .Dest, .Size = units * 32, VMAIN_IncAfterHigh), with
; C2Scene_VramQLock held. Then .Left -= the units; at 0 it returns C=1
; (the task ends); else .Src += the bytes, .Dest += the bytes / 2 (VRAM
; words) and C=0.
; Quirk, kept: no check that the queue has room; and .Left = 0 from the
; op still queues a part, of size 0 (which the DMA hardware takes as
; 65536 bytes if the flush passes it on as is), then ends.
; Callers note: none direct (C2Scene_UploadTileStates; C2Scene_UploadTilesStart
;   branches (BNE at $C2:1D44) or falls into it).
; Entry: M=0, X=0, DP=$0000 (the queue, C2Tmp_08/$0A), DB=$00 (low WRAM:
;        the task record); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task, Y = the task; C=1 done, C=0 more to go;
;        A clobbered; C2Tmp_08 = the units, C2Tmp_0A = the bytes;
;        C2Scene_VramQEnd + 8, C2Scene_VramQLock = 0
; No calls.
!C2Scene_UploadUnits = !C2Tmp_08        ; 16-bit units in this part
!C2Scene_UploadBytes = !C2Tmp_0A        ; 16-bit bytes in this part
C2Scene_UploadTilesStep:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_UploadTask.PerFrame,X
    CMP.w C2Scene_UploadTask.Left,X
    BCC .units
    LDA.w C2Scene_UploadTask.Left,X
.units:
    STA.b !C2Scene_UploadUnits
    TXY
    LDA.b !C2Scene_VramQEnd
    AND.w #!Eng_LowByteMask
    TAX
    SEP #$20
    INC.b !C2Scene_VramQLock
    LDA.w C2Scene_UploadTask.SrcBank,Y
    STA.b C2Scene_VramQ.Bank,X
    LDA.b #!VMAIN_IncAfterHigh
    STA.b C2Scene_VramQ.Vmain,X
    REP #$20
    LDA.w C2Scene_UploadTask.Src,Y
    STA.b C2Scene_VramQ.Src,X
    LDA.w C2Scene_UploadTask.Dest,Y
    STA.b C2Scene_VramQ.Dest,X
    LDA.b !C2Scene_UploadUnits
    ASL A                       ; units * 32 bytes
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b C2Scene_VramQ.Size,X
    STA.b !C2Scene_UploadBytes
    SEP #$20
    TXA
    CLC
    ADC.b #!C2Scene_VramQEntrySize
    STA.b !C2Scene_VramQEnd
    STZ.b !C2Scene_VramQLock
    TYX
    REP #$20
    LDA.w C2Scene_UploadTask.Left,X
    SEC
    SBC.b !C2Scene_UploadUnits
    BEQ .done
    STA.w C2Scene_UploadTask.Left,X
    LDA.b !C2Scene_UploadBytes
    CLC
    ADC.w C2Scene_UploadTask.Src,X
    STA.w C2Scene_UploadTask.Src,X
    LDA.b !C2Scene_UploadBytes
    LSR A
    CLC
    ADC.w C2Scene_UploadTask.Dest,X
    STA.w C2Scene_UploadTask.Dest,X
    CLC
    RTS
.done:
    SEC
    RTS

; ============================================================
; Scene boot step ($C2:1DB5–$C2:1DD3)
; ============================================================

org $C21DB5
; $C2:1DB5 — C2Scene_ClearPalette (31 bytes, $1DB5–$1DD3)
; Zeroes C2Scene_PaletteBuf (512 B, $0920-$0B1F: every color black) and
; the 16 bytes after it, C2Scene_Unk0B20 ($0B20-$0B2F), a word at a time.
; Callers (1 JSR site): BankC2_SceneBoot ($C2:003D).
; Entry: M any (REP #$20 here), X=0, DP any, DB with low WRAM at
;        $0000-$1FFF ($00 from the boot)
; Exit:  M=1, X=0; X = C2Scene_Unk0B20Size; A (never written), Y, DP and
;        DB unchanged
; No calls.
C2Scene_ClearPalette:
    REP #$20
    LDX.w #$0000
.palette:
    STZ.w !C2Scene_PaletteBuf,X
    INX
    INX
    CPX.w #!C2Scene_PaletteBytes
    BNE .palette
    LDX.w #$0000
.unk0B20:
    STZ.w !C2Scene_Unk0B20,X
    INX
    INX
    CPX.w #!C2Scene_Unk0B20Size
    BNE .unk0B20
    SEP #$20
    RTS

org $C21DD4
; ============================================================
; Scene palette load and fade tasks ($C2:1DD4–$C2:20A1)
; ============================================================
; Script op $04 (C2Script_SpawnUnk1DD4) leaves its arguments in the
; spawner's record (.ArgPalette, .ArgRate, .ArgSrc, .ArgBank of
; C2Scene_PalTask) and starts C2Scene_TaskUnk1DD4, which copies the 16 new
; colors into the palette at once or starts C2Scene_TaskPalFade to fade
; them in. Both count themselves in C2Scene_Unk0B20 (one byte per
; palette) while they work, and a fade gives up when another task works
; on its palette. A fade takes C2Scene_PalFadeSteps steps: per color and
; channel (red, green, blue: BGR555) the difference to the new color is
; spread over the 32 steps by a count byte per channel
; (C2Scene_PalFadePlanColor), stepped by C2Scene_PalFadeStepColor.

; $C2:1DD4 — C2Scene_TaskUnk1DD4 (100 bytes, $1DD4–$1E37)
; Task handler (palette load). First frame (.State 0): with .ArgRate
; non-zero it starts a C2Scene_TaskPalFade task (C2Scene_TaskSpawn, which
; copies this record and so the arguments) and ends (C=1). With .ArgRate
; 0 it counts itself in C2Scene_Unk0B20 for palette .ArgPalette, copies
; the 16 colors at .ArgSrc/.ArgBank into that palette of
; C2Scene_PaletteBuf (WMADD/WMDATA) and asks the NMI to upload the
; palettes (C2Scene_NmiPalette); .State = 1. Second frame: takes itself
; out of C2Scene_Unk0B20 and ends.
; Callers note: none direct; the handler C2Script_SpawnUnk1DD4 installs
;   (C2Scene_TaskRunAll calls it).
; Entry: M=1, X=0 with X = the task, DP=$0000 (TDC loads 0; C2Tmp_10-$12,
;        C2Scene_NmiFlags), DB=$00 (low WRAM: the task record,
;        C2Scene_Unk0B20; WMADD/WMDATA); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C=1 the task ends (fade started, or second frame), C=0
;        colors copied; A, X, Y clobbered; spawning: C2Tmp_08 changed;
;        copy: C2Tmp_10-$12 = the source, WMADD changed
; Calls: C2Scene_TaskSpawn.
!C2Scene_PalSrc = !C2Tmp_10             ; 24-bit address of the new colors
C2Scene_TaskUnk1DD4:
    TDC
    LDA.w C2Scene_PalTask.State,X
    BNE .finish
    LDA.w C2Scene_PalTask.ArgRate,X
    BEQ .copy
    LDX.w #C2Scene_TaskPalFade
    JSR C2Scene_TaskSpawn
    SEC
    RTS
.copy:
    TXY
    INC.w C2Scene_PalTask.State,X
    LDX.w C2Scene_PalTask.ArgPalette,Y
    INC.w !C2Scene_Unk0B20,X
    TYX
    LDA.w C2Scene_PalTask.ArgPalette,X
    REP #$20
    ASL A                       ; palette * 32 bytes (C=0 after)
    ASL A
    ASL A
    ASL A
    ASL A
    ADC.w #!C2Scene_PaletteBuf
    STA.w WMADDL
    LDA.w C2Scene_PalTask.ArgSrc,X
    STA.b !C2Scene_PalSrc
    TDC
    SEP #$20
    LDA.b #0                    ; WRAM bank $7E
    STA.w WMADDH
    LDA.w C2Scene_PalTask.ArgBank,X
    STA.b !C2Scene_PalSrc+2
    LDY.w #0
    LDX.w #!C2Scene_PalColors
.color:
    LDA.b [!C2Scene_PalSrc],Y
    STA.w WMDATA
    INY
    LDA.b [!C2Scene_PalSrc],Y
    STA.w WMDATA
    INY
    DEX
    BNE .color
    LDA.b #!C2Scene_NmiPalette
    TSB.b !C2Scene_NmiFlags
    CLC
    RTS
.finish:
    LDA.w C2Scene_PalTask.ArgPalette,X
    TAX
    DEC.w !C2Scene_Unk0B20,X
    SEC
    RTS

; $C2:1E38 — C2Scene_TaskPalFade (9 bytes, $1E38–$1E40)
; Task handler (palette fade, started by C2Scene_TaskUnk1DD4): runs
; .State through C2Scene_PalFadeStates: 0 C2Scene_PalFadeStart, 1
; C2Scene_PalFadeStep, 2 C2Scene_PalFadeEnd.
; Callers note: none direct (C2Scene_TaskRunAll calls the handler).
; Entry: M=1, X=0 with X = the task, DP=$0000 (TDC loads 0), DB=$00 (low
;        WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  the state's (M=1, X=0; C=1 when the fade is over)
; Calls: the C2Scene_PalFadeStates handlers (JMP (abs,X)).
C2Scene_TaskPalFade:
    TDC
    LDA.w C2Scene_PalTask.State,X
    ASL A
    TAX
    JMP (C2Scene_PalFadeStates,X)

; $C2:1E41 — C2Scene_PalFadeStates (3 words, $1E41–$1E46)
; The state handlers of C2Scene_TaskPalFade (X = .State * 2).
C2Scene_PalFadeStates:
    dw C2Scene_PalFadeStart     ; 0
    dw C2Scene_PalFadeStep      ; 1
    dw C2Scene_PalFadeEnd       ; 2

; $C2:1E47 — C2Scene_PalFadeStart (63 bytes, $1E47–$1E85)
; State 0: .State = 1; counts itself in C2Scene_Unk0B20 for .ArgPalette;
; copies the arguments to .Palette, .Rate, .Src and .SrcBank (the step
; arrays will overwrite them); .Timer = 0, .Steps = 0; .Colors = the
; palette's address in C2Scene_PaletteBuf; then plans the fade
; (C2Scene_PalFadePlan).
; Callers note: none direct (C2Scene_PalFadeStates).
; Entry: M=1, X=0, DP=$0000, DB=$00 (low WRAM: the task record,
;        C2Scene_PaletteBuf, C2Scene_Unk0B20); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C=0; X = the task + $3F (the last .BlueStep byte,
;        left by C2Scene_PalFadePlanColor), Y = the palette; A clobbered;
;        C2Tmp_00, C2Tmp_08-$0C, C2Tmp_0E-$1B changed (C2Scene_PalFadePlan)
; Calls: C2Scene_PalFadePlan.
C2Scene_PalFadeStart:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_PalTask.State,X
    LDY.w C2Scene_PalTask.ArgPalette,X
    TYX
    INC.w !C2Scene_Unk0B20,X
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_PalTask.ArgRate,X
    STA.w C2Scene_PalTask.Rate,X
    LDA.w C2Scene_PalTask.ArgBank,X
    STA.w C2Scene_PalTask.SrcBank,X
    REP #$20
    TYA
    STA.w C2Scene_PalTask.Palette,X
    LDA.w C2Scene_PalTask.ArgSrc,X
    STA.w C2Scene_PalTask.Src,X
    STZ.w C2Scene_PalTask.Timer,X
    STZ.w C2Scene_PalTask.Steps,X
    LDA.w C2Scene_PalTask.Palette,X
    ASL A                       ; palette * 32 bytes (C=0 after)
    ASL A
    ASL A
    ASL A
    ASL A
    ADC.w #!C2Scene_PaletteBuf
    STA.w C2Scene_PalTask.Colors,X
    JSR C2Scene_PalFadePlan
    CLC
    RTS

; $C2:1E86 — C2Scene_PalFadeStep (47 bytes, $1E86–$1EB4)
; State 1, each frame: if C2Scene_Unk0B20 for the palette is not 1
; (another palette task has started on it) it goes to C2Scene_PalFadeEnd
; (BNE into it) and the fade stops where it is. Else once .Timer (the
; record's .Frames, which C2Scene_TaskRunAll counts up) reaches .Rate it
; takes one step (C2Scene_PalFadeApply), zeroes .Timer's low byte, asks
; the NMI to upload the palettes, and after the C2Scene_PalFadeSteps-th
; step sets .State to 2.
; Callers note: none direct (C2Scene_PalFadeStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_NmiFlags), DB=$00 (low WRAM: the
;        task record, C2Scene_PaletteBuf, C2Scene_Unk0B20);
;        C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C=0 (or as C2Scene_PalFadeEnd); X = the task; A, Y
;        clobbered; after a step as C2Scene_PalFadeApply
; Calls: C2Scene_PalFadeApply.
C2Scene_PalFadeStep:
    LDX.b !C2Scene_TaskCur
    LDY.w C2Scene_PalTask.Palette,X
    LDA.w !C2Scene_Unk0B20,Y
    CMP.b #1
    BNE C2Scene_PalFadeEnd
    LDA.w C2Scene_PalTask.Timer,X
    CMP.w C2Scene_PalTask.Rate,X
    BCC .wait
    JSR C2Scene_PalFadeApply
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_PalTask.Timer,X
    LDA.b #!C2Scene_NmiPalette
    TSB.b !C2Scene_NmiFlags
    INC.w C2Scene_PalTask.Steps,X
    LDA.w C2Scene_PalTask.Steps,X
    CMP.b #!C2Scene_PalFadeSteps
    BNE .wait
    INC.w C2Scene_PalTask.State,X
.wait:
    CLC
    RTS

; $C2:1EB5 — C2Scene_PalFadeEnd (11 bytes, $1EB5–$1EBF)
; State 2 (and C2Scene_PalFadeStep's give-up): takes the task out of
; C2Scene_Unk0B20 for its palette and ends it (C=1).
; Callers note: none direct (C2Scene_PalFadeStates; BNE from
;   C2Scene_PalFadeStep at $C2:1E90).
; Entry: M=1, X=0, DP=$0000, DB=$00 (low WRAM: the task record,
;        C2Scene_Unk0B20); C2Scene_TaskCur = the task; A's high byte 0
;        (TAX takes 16 bits: true on both ways in)
; Exit:  M=1, X=0; C=1; X = the palette; A clobbered
; No calls.
C2Scene_PalFadeEnd:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_PalTask.Palette,X
    TAX
    DEC.w !C2Scene_Unk0B20,X
    SEC
    RTS

; $C2:1EC0 — C2Scene_PalFadePlan (81 bytes, $1EC0–$1F10)
; Plans a fade: for each of the 16 colors, from the palette's current
; color (.Colors, through DB) to the new one (.Src/.SrcBank, long), sets
; the color's red, green and blue count bytes in .RedStep, .GreenStep and
; .BlueStep (C2Scene_PalFadePlanColor).
; Callers (1 JSR site): C2Scene_PalFadeStart ($C2:1E81).
; Entry: M any (REP #$20 here), X=0 with X = the task, DP=$0000
;        (C2Tmp_00-$1B), DB=$00 (low WRAM: the task record and
;        C2Scene_PaletteBuf); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; A, X, Y clobbered; C2Tmp_00 = 0, C2Tmp_08-$0C,
;        C2Tmp_0E-$1B changed
; Calls: C2Scene_PalFadePlanColor.
!C2Scene_FadeLeft = !C2Tmp_00           ; colors left
!C2Scene_FadeCur = !C2Tmp_08            ; 16-bit current color
!C2Scene_FadeNew = !C2Tmp_0A            ; 16-bit new color
!C2Scene_FadeTmp = !C2Tmp_0C            ; the current color's channel
!C2Scene_FadeColorPtr = !C2Tmp_0E       ; 16-bit address of the current color
!C2Scene_FadeRedPtr = !C2Tmp_10         ; 16-bit address of the color's .RedStep byte
!C2Scene_FadeGreenPtr = !C2Tmp_13       ; 16-bit address of its .GreenStep byte
!C2Scene_FadeBluePtr = !C2Tmp_16        ; 16-bit address of its .BlueStep byte
!C2Scene_FadeSrcPtr = !C2Tmp_19         ; 24-bit: the new color (plan), the current color (apply)
C2Scene_PalFadePlan:
    REP #$20
    LDA.b !C2Scene_TaskCur
    CLC
    ADC.w #C2Scene_PalTask.RedStep
    STA.b !C2Scene_FadeRedPtr
    CLC
    ADC.w #!C2Scene_PalColors
    STA.b !C2Scene_FadeGreenPtr
    CLC
    ADC.w #!C2Scene_PalColors
    STA.b !C2Scene_FadeBluePtr
    LDA.w C2Scene_PalTask.Colors,X
    STA.b !C2Scene_FadeColorPtr
    LDA.w C2Scene_PalTask.Src,X
    STA.b !C2Scene_FadeSrcPtr
    SEP #$20
    LDA.w C2Scene_PalTask.SrcBank,X
    STA.b !C2Scene_FadeSrcPtr+2
    LDA.b #!C2Scene_PalColors
    STA.b !C2Scene_FadeLeft
.color:
    REP #$20
    LDA.b (!C2Scene_FadeColorPtr)
    STA.b !C2Scene_FadeCur
    LDA.b [!C2Scene_FadeSrcPtr]
    STA.b !C2Scene_FadeNew
    SEP #$20
    JSR C2Scene_PalFadePlanColor
    REP #$20
    INC.b !C2Scene_FadeRedPtr
    INC.b !C2Scene_FadeGreenPtr
    INC.b !C2Scene_FadeBluePtr
    INC.b !C2Scene_FadeColorPtr
    INC.b !C2Scene_FadeColorPtr
    INC.b !C2Scene_FadeSrcPtr
    INC.b !C2Scene_FadeSrcPtr
    SEP #$20
    DEC.b !C2Scene_FadeLeft
    BNE .color
    RTS

; $C2:1F11 — C2Scene_PalFadePlanColor (116 bytes, $1F11–$1F84)
; For one color: per channel (red: bits 0-4, green: bits 5-9, blue: bits
; 10-14), d = new - current (-31..31) gives the count byte: 0 when equal,
; d when rising, or C2Scene_FadeDownFlag OR (-d + C2Scene_FadeDownBias)
; when falling; stored at the channel's pointer (through DB). See
; C2Scene_PalFadeStepColor for how the count spreads the steps.
; Callers (1 JSR site): C2Scene_PalFadePlan ($C2:1EF7).
; Entry: M=1, X=0, DP=$0000 (TDC loads 0; C2Tmp_08-$0C, C2Tmp_10-$17),
;        DB=$00 (low WRAM: the task record); C2Scene_FadeCur/New = the
;        two colors, the three channel pointers set
; Exit:  M=1, X=0; X = C2Scene_FadeBluePtr; A = the blue count;
;        C2Tmp_0C changed; Y unchanged
; No calls.
C2Scene_PalFadePlanColor:
    LDA.b !C2Scene_FadeCur
    AND.b #!C2Scene_ColorRedMask
    STA.b !C2Scene_FadeTmp
    LDA.b !C2Scene_FadeNew
    AND.b #!C2Scene_ColorRedMask
    SEC
    SBC.b !C2Scene_FadeTmp
    BEQ .red_same
    BCS .red_store
    EOR.b #!Eng_Invert8
    INC A
    CLC
    ADC.b #!C2Scene_FadeDownBias
    ORA.b #!C2Scene_FadeDownFlag
    BRA .red_store
.red_same:
    TDC
.red_store:
    LDX.b !C2Scene_FadeRedPtr
    STA.w !Eng_PtrBase,X
    REP #$20
    LDA.b !C2Scene_FadeCur
    AND.w #!C2Scene_ColorGreenMask
    STA.b !C2Scene_FadeTmp
    LDA.b !C2Scene_FadeNew
    AND.w #!C2Scene_ColorGreenMask
    SEC
    SBC.b !C2Scene_FadeTmp
    PHP                         ; keep Z and C of the difference
    ASL A                       ; high byte = the difference / 32
    ASL A
    ASL A
    XBA
    PLP
    SEP #$20
    BEQ .green_same
    BCS .green_store
    EOR.b #!Eng_Invert8
    INC A
    CLC
    ADC.b #!C2Scene_FadeDownBias
    ORA.b #!C2Scene_FadeDownFlag
    BRA .green_store
.green_same:
    TDC
.green_store:
    LDX.b !C2Scene_FadeGreenPtr
    STA.w !Eng_PtrBase,X
    LDA.b !C2Scene_FadeCur+1
    AND.b #!C2Scene_ColorBlueHiMask
    LSR A
    LSR A
    STA.b !C2Scene_FadeTmp
    LDA.b !C2Scene_FadeNew+1
    AND.b #!C2Scene_ColorBlueHiMask
    LSR A
    LSR A
    SEC
    SBC.b !C2Scene_FadeTmp
    BEQ .blue_same
    BCS .blue_store
    EOR.b #!Eng_Invert8
    INC A
    CLC
    ADC.b #!C2Scene_FadeDownBias
    ORA.b #!C2Scene_FadeDownFlag
    BRA .blue_store
.blue_same:
    TDC
.blue_store:
    LDX.b !C2Scene_FadeBluePtr
    STA.w !Eng_PtrBase,X
    RTS

; $C2:1F85 — C2Scene_PalFadeApply (71 bytes, $1F85–$1FCB)
; Takes one fade step on all 16 colors of the palette at .Colors: each
; color is read, stepped (C2Scene_PalFadeStepColor) and written back
; (through DB).
; Callers (1 JSR site): C2Scene_PalFadeStep ($C2:1E9A).
; Entry: M any (REP #$20 here), X=0 with X = the task, DP=$0000
;        (C2Tmp_00, C2Tmp_08/$09, C2Tmp_10-$1A), DB=$00 (low WRAM: the
;        task record and C2Scene_PaletteBuf); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; A, X, Y clobbered; C2Tmp_00 = 0, C2Tmp_08/$09,
;        C2Tmp_10-$1A changed
; Calls: C2Scene_PalFadeStepColor.
C2Scene_PalFadeApply:
    REP #$20
    LDA.b !C2Scene_TaskCur
    CLC
    ADC.w #C2Scene_PalTask.RedStep
    STA.b !C2Scene_FadeRedPtr
    CLC
    ADC.w #!C2Scene_PalColors
    STA.b !C2Scene_FadeGreenPtr
    CLC
    ADC.w #!C2Scene_PalColors
    STA.b !C2Scene_FadeBluePtr
    LDA.w C2Scene_PalTask.Colors,X
    STA.b !C2Scene_FadeSrcPtr
    SEP #$20
    LDA.b #!C2Scene_PalColors
    STA.b !C2Scene_FadeLeft
.color:
    REP #$20
    LDA.b (!C2Scene_FadeSrcPtr)
    STA.b !C2Scene_FadeCur
    TDC
    SEP #$20
    JSR C2Scene_PalFadeStepColor
    REP #$20
    LDX.b !C2Scene_FadeSrcPtr
    LDA.b !C2Scene_FadeCur
    STA.w !Eng_PtrBase,X
    INC.b !C2Scene_FadeRedPtr
    INC.b !C2Scene_FadeGreenPtr
    INC.b !C2Scene_FadeBluePtr
    INC.b !C2Scene_FadeSrcPtr
    INC.b !C2Scene_FadeSrcPtr
    SEP #$20
    DEC.b !C2Scene_FadeLeft
    BNE .color
    RTS

; $C2:1FCC — C2Scene_PalFadeStepColor (150 bytes, $1FCC–$2061)
; One fade step of one color (C2Scene_FadeCur): for each channel's count
; byte c (red, green, blue): 0 leaves the channel; a rising count moves
; the channel up one when C2Scene_PalFadeStepTable[c] is 1 (c >= 32) and
; then counts c up; a falling one (C2Scene_FadeDownFlag) moves it down
; one when the table entry for c AND C2Scene_FadeCountMask is 1, then
; counts c down. So over the 32 steps a rise of d comes in the last d
; steps (c runs d..d+31) and a drop of d in the first d steps (c runs
; d+31 down to d), and each channel ends on the new color.
; Callers (1 JSR site): C2Scene_PalFadeApply ($C2:1FAF).
; Entry: M=1, X=0, DP=$0000 (C2Tmp_08/$09, the channel pointers), DB=$00
;        (low WRAM: the task record); A's high byte 0 (TAX takes 16
;        bits); C2Scene_FadeCur = the color
; Exit:  M=1, X=0; C2Scene_FadeCur stepped; the count bytes moved; A, X,
;        Y clobbered
; No calls.
C2Scene_PalFadeStepColor:
    LDY.b !C2Scene_FadeRedPtr
    LDA.w !Eng_PtrBase,Y
    BEQ .green
    BMI .red_down
    TAX
    LDA.l C2Scene_PalFadeStepTable,X
    BEQ .red_up_count
    INC.b !C2Scene_FadeCur
.red_up_count:
    TYX
    INC.w !Eng_PtrBase,X
    BRA .green
.red_down:
    AND.b #!C2Scene_FadeCountMask
    TAX
    LDA.l C2Scene_PalFadeStepTable,X
    BEQ .red_down_count
    DEC.b !C2Scene_FadeCur
.red_down_count:
    TYX
    DEC.w !Eng_PtrBase,X
.green:
    LDY.b !C2Scene_FadeGreenPtr
    LDA.w !Eng_PtrBase,Y
    BEQ .blue
    BMI .green_down
    TAX
    LDA.l C2Scene_PalFadeStepTable,X
    BEQ .green_up_count
    REP #$20
    LDA.b !C2Scene_FadeCur
    CLC
    ADC.w #!C2Scene_ColorGreenUnit
    STA.b !C2Scene_FadeCur
    TDC
    SEP #$20
.green_up_count:
    TYX
    INC.w !Eng_PtrBase,X
    BRA .blue
.green_down:
    AND.b #!C2Scene_FadeCountMask
    TAX
    LDA.l C2Scene_PalFadeStepTable,X
    BEQ .green_down_count
    REP #$20
    LDA.b !C2Scene_FadeCur
    SEC
    SBC.w #!C2Scene_ColorGreenUnit
    STA.b !C2Scene_FadeCur
    TDC
    SEP #$20
.green_down_count:
    TYX
    DEC.w !Eng_PtrBase,X
.blue:
    LDY.b !C2Scene_FadeBluePtr
    LDA.w !Eng_PtrBase,Y
    BEQ .done
    BMI .blue_down
    TAX
    LDA.l C2Scene_PalFadeStepTable,X
    BEQ .blue_up_count
    LDA.b !C2Scene_FadeCur+1
    CLC
    ADC.b #!C2Scene_ColorBlueHiUnit
    STA.b !C2Scene_FadeCur+1
.blue_up_count:
    TYX
    INC.w !Eng_PtrBase,X
    BRA .done
.blue_down:
    AND.b #!C2Scene_FadeCountMask
    TAX
    LDA.l C2Scene_PalFadeStepTable,X
    BEQ .blue_down_count
    LDA.b !C2Scene_FadeCur+1
    SEC
    SBC.b #!C2Scene_ColorBlueHiUnit
    STA.b !C2Scene_FadeCur+1
.blue_down_count:
    TYX
    DEC.w !Eng_PtrBase,X
.done:
    RTS

; $C2:2062 — C2Scene_PalFadeStepTable (64 bytes, $2062–$20A1)
; Indexed by a fade count 0-63 (C2Scene_PalFadeStepColor): 1 = move the
; channel this step (counts 32-63), 0 = not yet (0-31).
C2Scene_PalFadeStepTable:
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01

; ============================================================
; Scene screen fade and mosaic tasks ($C2:20A2–$C2:2259)
; ============================================================
; Started by script ops $28-$2B (C2Script_SpawnUnk20A2 ... 2194), each
; reads its op's arguments through the script pointer it copied from the
; spawner (still on the op; C2Scene_FxTask.OpPtr) and steps once every
; .Rate frames, timed by its own .Frames (.Timer), which
; C2Scene_TaskRunAll counts up after each frame the task lives. Rate 0
; does the whole effect at once. The two fades mark themselves in
; C2Scene_Unk1BF6 (C2Scene_FadeInBusy / C2Scene_FadeOutBusy).

; $C2:20A2 — C2Scene_TaskUnk20A2 (9 bytes, $20A2–$20AA)
; Task handler (fade out, op $28): runs .State through
; C2Scene_FadeOutStates: 0 C2Scene_FadeOutStart, 1 C2Scene_FadeOutStep.
; Callers note: none direct; the handler C2Script_SpawnUnk20A2 installs
;   (C2Scene_TaskRunAll calls it).
; Entry: M=1, X=0 with X = the task, DP=$0000 (TDC loads 0), DB=$00 (low
;        WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  the state's (M=1, X=0; C=1 when done)
; Calls: the C2Scene_FadeOutStates handlers (JMP (abs,X)).
C2Scene_TaskUnk20A2:
    TDC
    LDA.w C2Scene_FxTask.State,X
    ASL A
    TAX
    JMP (C2Scene_FadeOutStates,X)

; $C2:20AB — C2Scene_FadeOutStates (2 words, $20AB–$20AE)
; The state handlers of C2Scene_TaskUnk20A2 (X = .State * 2).
C2Scene_FadeOutStates:
    dw C2Scene_FadeOutStart     ; 0
    dw C2Scene_FadeOutStep      ; 1

; $C2:20AF — C2Scene_FadeOutStart (48 bytes, $20AF–$20DE)
; State 0: if a fade-out already runs (C2Scene_FadeOutBusy) the task just
; ends. Else it marks one, sets .State = 1 and reads op $28's arg 1, the
; frames per brightness step: 0 blanks the screen at once (forced blank,
; C2Scene_Brightness = 0) and ends, leaving C2Scene_FadeOutBusy set
; (quirk, kept: no later fade-out runs until something clears it).
; Otherwise .Rate = arg 1, .Timer's low byte = 0, and it falls into
; C2Scene_FadeOutStep.
; Callers note: none direct (C2Scene_FadeOutStates).
; Entry: M=1, X=0, DP=$0000 (C2Tmp_10-$12, the PPU shadows), DB=$00 (low
;        WRAM: the task record, C2Scene_Unk1BF6); C2Scene_TaskCur = the
;        task
; Exit:  ended: M=1, X=0, C=1. Else as C2Scene_FadeOutStep. C2Tmp_10-$12
;        = the op's address; Y = 1
; No calls (falls into C2Scene_FadeOutStep).
!C2Scene_FxOp = !C2Tmp_10               ; 24-bit address of the spawning op
C2Scene_FadeOutStart:
    LDA.w !C2Scene_Unk1BF6
    BIT.b #!C2Scene_FadeOutBusy
    BNE .end
    LDA.b #!C2Scene_FadeOutBusy
    TSB.w !C2Scene_Unk1BF6
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_FxTask.State,X
    LDY.w C2Scene_FxTask.OpPtr,X
    STY.b !C2Scene_FxOp
    LDA.w C2Scene_FxTask.OpPtr+2,X
    STA.b !C2Scene_FxOp+2
    LDY.w #1
    LDA.b [!C2Scene_FxOp],Y
    BNE .timed
    LDA.b #FORCED_BLANK
    STA.b !C2Scene_InidispShadow
    STZ.b !C2Scene_Brightness
.end:
    SEC
    RTS
.timed:
    STA.w C2Scene_FxTask.Rate,X
    STZ.w C2Scene_FxTask.Timer,X

; $C2:20DF — C2Scene_FadeOutStep (38 bytes, $20DF–$2104)
; State 1, each frame: once .Timer reaches .Rate it zeroes .Timer's low
; byte and takes C2Scene_Brightness down one. At brightness 0 (already,
; or after the step) it turns on forced blank, clears
; C2Scene_FadeOutBusy and ends (C=1).
; Callers note: none direct (C2Scene_FadeOutStates; C2Scene_FadeOutStart falls
;   into it).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (the PPU shadows), DB=$00
;        (low WRAM: the task record, C2Scene_Unk1BF6); C2Scene_TaskCur =
;        the task
; Exit:  M=1, X=0; X = the task; C=1 done, C=0 not yet; A clobbered
; No calls.
C2Scene_FadeOutStep:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.Timer,X
    CMP.w C2Scene_FxTask.Rate,X
    BCS .step
    CLC
    RTS
.step:
    STZ.w C2Scene_FxTask.Timer,X
    LDA.b !C2Scene_Brightness
    BEQ .blank
    DEC.b !C2Scene_Brightness
    BEQ .blank
    CLC
    RTS
.blank:
    LDA.b #FORCED_BLANK
    STA.b !C2Scene_InidispShadow
    LDA.b #!C2Scene_FadeOutBusy
    TRB.w !C2Scene_Unk1BF6
    SEC
    RTS

; $C2:2105 — C2Scene_TaskUnk2105 (9 bytes, $2105–$210D)
; Task handler (fade in, op $29): runs .State through
; C2Scene_FadeInStates: 0 C2Scene_FadeInStart, 1 C2Scene_FadeInUnblank,
; 2 C2Scene_FadeInStep, 3 C2Scene_FadeInEnd.
; Callers note: none direct; the handler C2Script_SpawnUnk2105 installs
;   (C2Scene_TaskRunAll calls it).
; Entry: M=1, X=0 with X = the task, DP=$0000 (TDC loads 0), DB=$00 (low
;        WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  the state's (M=1, X=0; C=1 when done)
; Calls: the C2Scene_FadeInStates handlers (JMP (abs,X)).
C2Scene_TaskUnk2105:
    TDC
    LDA.w C2Scene_FxTask.State,X
    ASL A
    TAX
    JMP (C2Scene_FadeInStates,X)

; $C2:210E — C2Scene_FadeInStates (4 words, $210E–$2115)
; The state handlers of C2Scene_TaskUnk2105 (X = .State * 2).
C2Scene_FadeInStates:
    dw C2Scene_FadeInStart      ; 0
    dw C2Scene_FadeInUnblank    ; 1
    dw C2Scene_FadeInStep       ; 2
    dw C2Scene_FadeInEnd        ; 3

; $C2:2116 — C2Scene_FadeInStart (60 bytes, $2116–$2151)
; State 0: if any fade runs (C2Scene_Unk1BF6 non-zero) it ends through
; C2Scene_FadeInEnd. Else it marks C2Scene_FadeInBusy and reads op $29's
; arg 1, the frames per step: 0 turns forced blank off at full
; brightness (Fade_BrightnessMax) at once and sets .State to
; C2Scene_FadeInDone (it ends next frame). Otherwise .Rate = arg 1 and
; .State = 1 (C2Scene_FadeInUnblank) when C2Scene_Brightness is 0, else
; 2 (C2Scene_FadeInStep, from the brightness it has); .Timer's low byte =
; 0.
; Quirk, kept: a second fade-in started while one runs ends through
; C2Scene_FadeInEnd and so clears the running one's C2Scene_FadeInBusy.
; Callers note: none direct (C2Scene_FadeInStates).
; Entry: M=1, X=0, DP=$0000 (C2Tmp_10-$12, the PPU shadows), DB=$00 (low
;        WRAM: the task record, C2Scene_Unk1BF6); C2Scene_TaskCur = the
;        task
; Exit:  M=1, X=0; C=0 (or as C2Scene_FadeInEnd); X = the task, Y = 1;
;        C2Tmp_10-$12 = the op's address
; No calls.
C2Scene_FadeInStart:
    LDA.w !C2Scene_Unk1BF6
    BNE C2Scene_FadeInEnd
    LDA.b #!C2Scene_FadeInBusy
    TSB.w !C2Scene_Unk1BF6
    LDX.b !C2Scene_TaskCur
    LDY.w C2Scene_FxTask.OpPtr,X
    STY.b !C2Scene_FxOp
    LDA.w C2Scene_FxTask.OpPtr+2,X
    STA.b !C2Scene_FxOp+2
    LDY.w #1
    LDA.b [!C2Scene_FxOp],Y
    BNE .timed
    STZ.b !C2Scene_InidispShadow
    LDA.b #!Fade_BrightnessMax
    STA.b !C2Scene_Brightness
    LDA.b #!C2Scene_FadeInDone
    STA.w C2Scene_FxTask.State,X
    CLC
    RTS
.timed:
    STA.w C2Scene_FxTask.Rate,X
    INC.w C2Scene_FxTask.State,X
    LDA.b !C2Scene_Brightness
    BEQ .from_blank
    INC.w C2Scene_FxTask.State,X
.from_blank:
    STZ.w C2Scene_FxTask.Timer,X
    CLC
    RTS

; $C2:2152 — C2Scene_FadeInUnblank (29 bytes, $2152–$216E)
; State 1: ends (C2Scene_FadeInEnd) if a fade-out has started. Once .Timer
; reaches .Rate: .State = 2, .Timer's low byte = 0, forced blank off and
; C2Scene_Brightness + 1 (the first step).
; Callers note: none direct (C2Scene_FadeInStates).
; Entry: M=1, X=0, DP=$0000 (the PPU shadows), DB=$00 (low WRAM: the task
;        record, C2Scene_Unk1BF6); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C=0 (or as C2Scene_FadeInEnd); X = the task; A
;        clobbered
; No calls.
C2Scene_FadeInUnblank:
    LDA.w !C2Scene_Unk1BF6
    BIT.b #!C2Scene_FadeOutBusy
    BNE C2Scene_FadeInEnd
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.Timer,X
    CMP.w C2Scene_FxTask.Rate,X
    BCC .wait
    INC.w C2Scene_FxTask.State,X
    STZ.w C2Scene_FxTask.Timer,X
    STZ.b !C2Scene_InidispShadow
    INC.b !C2Scene_Brightness
.wait:
    CLC
    RTS

; $C2:216F — C2Scene_FadeInStep (30 bytes, $216F–$218C)
; State 2: ends (C2Scene_FadeInEnd) if a fade-out has started. Once .Timer
; reaches .Rate: .Timer's low byte = 0 and C2Scene_Brightness + 1; at
; Fade_BrightnessMax it ends (C2Scene_FadeInEnd).
; Quirk, kept: a fade-in started at full brightness steps past it (16,
; 17, ...: the NMI ORs the byte into INIDISP, so the high bits spill into
; forced blank) and ends only when the byte wraps round to 15 again.
; Callers note: none direct (C2Scene_FadeInStates).
; Entry: M=1, X=0, DP=$0000 (the PPU shadows), DB=$00 (low WRAM: the task
;        record, C2Scene_Unk1BF6); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C=0 (or as C2Scene_FadeInEnd); X = the task; A
;        clobbered
; No calls.
C2Scene_FadeInStep:
    LDA.w !C2Scene_Unk1BF6
    BIT.b #!C2Scene_FadeOutBusy
    BNE C2Scene_FadeInEnd
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.Timer,X
    CMP.w C2Scene_FxTask.Rate,X
    BCC .wait
    STZ.w C2Scene_FxTask.Timer,X
    INC.b !C2Scene_Brightness
    LDA.b !C2Scene_Brightness
    CMP.b #!Fade_BrightnessMax
    BEQ C2Scene_FadeInEnd
.wait:
    CLC
    RTS

; $C2:218D — C2Scene_FadeInEnd (7 bytes, $218D–$2193)
; State 3, and where the other fade-in states end: clears
; C2Scene_FadeInBusy and ends the task (C=1).
; Callers note: none direct (C2Scene_FadeInStates; BNE from
;   C2Scene_FadeInStart ($C2:2119), C2Scene_FadeInUnblank ($C2:2157) and
;   C2Scene_FadeInStep ($C2:2174); BEQ from C2Scene_FadeInStep
;   ($C2:2189)).
; Entry: M=1, X any, DP any, DB=$00 (low WRAM: C2Scene_Unk1BF6)
; Exit:  M=1; C=1; A = C2Scene_FadeInBusy; X, Y unchanged
; No calls.
C2Scene_FadeInEnd:
    LDA.b #!C2Scene_FadeInBusy
    TRB.w !C2Scene_Unk1BF6
    SEC
    RTS

; $C2:2194 — C2Scene_TaskUnk2194 (15 bytes, $2194–$21A2)
; Task handler (mosaic shrink, op $2B): runs .State through
; C2Scene_MosaicOutStates: 0 C2Scene_MosaicOutStart, 1
; C2Scene_MosaicOutStep.
; Callers note: none direct; the handler C2Script_SpawnUnk2194 installs
;   (C2Scene_TaskRunAll calls it).
; Entry: M=1 (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low
;        WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  the state's (M=1, X=0; C=1 when done)
; Calls: the C2Scene_MosaicOutStates handlers (JMP (abs,X)).
C2Scene_TaskUnk2194:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.State,X
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    JMP (C2Scene_MosaicOutStates,X)

; $C2:21A3 — C2Scene_MosaicOutStates (2 words, $21A3–$21A6)
; The state handlers of C2Scene_TaskUnk2194 (X = .State * 2).
C2Scene_MosaicOutStates:
    dw C2Scene_MosaicOutStart   ; 0
    dw C2Scene_MosaicOutStep    ; 1

; $C2:21A7 — C2Scene_MosaicOutStart (47 bytes, $21A7–$21D5)
; State 0: .State = 1; ORs op $2B's arg 1 into C2Scene_MosaicShadow (the
; BGs to apply it to, bits 0-3); arg 2 is the frames per step: 0 sets
; the size to 0 at once (keeping the BG bits) and ends. Otherwise .Rate =
; arg 2, .Timer's low byte = 0, and it falls into C2Scene_MosaicOutStep.
; Callers note: none direct (C2Scene_MosaicOutStates).
; Entry: M=0, X=0, DP=$0000 (C2Tmp_10-$12, the PPU shadows), DB=$00 (low
;        WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  ended: M=1, X=0, C=1. Else as C2Scene_MosaicOutStep. Y = 2;
;        C2Tmp_10-$12 = the op's address
; No calls (falls into C2Scene_MosaicOutStep).
C2Scene_MosaicOutStart:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.OpPtr,X
    STA.b !C2Scene_FxOp
    SEP #$20
    LDA.w C2Scene_FxTask.OpPtr+2,X
    STA.b !C2Scene_FxOp+2
    INC.w C2Scene_FxTask.State,X
    LDY.w #1
    LDA.b !C2Scene_MosaicShadow
    ORA.b [!C2Scene_FxOp],Y
    STA.b !C2Scene_MosaicShadow
    LDY.w #2
    LDA.b [!C2Scene_FxOp],Y
    BNE .timed
    LDA.b !C2Scene_MosaicShadow
    AND.b #!C2Scene_MosaicBgMask
    STA.b !C2Scene_MosaicShadow
    SEC
    RTS
.timed:
    STA.w C2Scene_FxTask.Rate,X
    STZ.w C2Scene_FxTask.Timer,X

; $C2:21D6 — C2Scene_MosaicOutStep (34 bytes, $21D6–$21F7)
; State 1: once .Timer reaches .Rate, .Timer's low byte = 0 and the
; mosaic size (C2Scene_MosaicShadow bits 4-7) goes down one; when it is
; already 0 the task ends (C=1) instead.
; Callers note: none direct (C2Scene_MosaicOutStates; C2Scene_MosaicOutStart
;   falls into it).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (the PPU shadows), DB=$00
;        (low WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; C=1 done, C=0 not yet; A clobbered
; No calls.
C2Scene_MosaicOutStep:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.Timer,X
    CMP.w C2Scene_FxTask.Rate,X
    BCS .step
    CLC
    RTS
.step:
    STZ.w C2Scene_FxTask.Timer,X
    LDA.b !C2Scene_MosaicShadow
    AND.b #!C2Scene_MosaicSizeMask
    BEQ .done
    LDA.b !C2Scene_MosaicShadow
    SEC
    SBC.b #!C2Scene_MosaicSizeStep
    STA.b !C2Scene_MosaicShadow
    CLC
    RTS
.done:
    SEC
    RTS

; $C2:21F8 — C2Scene_TaskUnk21F8 (13 bytes, $21F8–$2204)
; Task handler (mosaic grow, op $2A): runs .State through
; C2Scene_MosaicInStates: 0 C2Scene_MosaicInStart, 1 C2Scene_MosaicInStep.
; Callers note: none direct; the handler C2Script_SpawnUnk21F8 installs
;   (C2Scene_TaskRunAll calls it).
; Entry: M=1 (REP #$20 here), X=0 with X = the task, DP=$0000, DB=$00
;        (low WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  the state's (M=1, X=0; C=1 when done)
; Calls: the C2Scene_MosaicInStates handlers (JMP (abs,X)).
C2Scene_TaskUnk21F8:
    REP #$20
    LDA.w C2Scene_FxTask.State,X
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    JMP (C2Scene_MosaicInStates,X)

; $C2:2205 — C2Scene_MosaicInStates (2 words, $2205–$2208)
; The state handlers of C2Scene_TaskUnk21F8 (X = .State * 2).
C2Scene_MosaicInStates:
    dw C2Scene_MosaicInStart    ; 0
    dw C2Scene_MosaicInStep     ; 1

; $C2:2209 — C2Scene_MosaicInStart (47 bytes, $2209–$2237)
; State 0: as C2Scene_MosaicOutStart (op $2A's arg 1 ORed into
; C2Scene_MosaicShadow, arg 2 the frames per step), but rate 0 sets the
; size to the largest (C2Scene_MosaicSizeMask: 16x16 blocks) at once.
; Callers note: none direct (C2Scene_MosaicInStates).
; Entry: M=0, X=0, DP=$0000 (C2Tmp_10-$12, the PPU shadows), DB=$00 (low
;        WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  ended: M=1, X=0, C=1. Else as C2Scene_MosaicInStep. Y = 2;
;        C2Tmp_10-$12 = the op's address
; No calls (falls into C2Scene_MosaicInStep).
C2Scene_MosaicInStart:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.OpPtr,X
    STA.b !C2Scene_FxOp
    SEP #$20
    LDA.w C2Scene_FxTask.OpPtr+2,X
    STA.b !C2Scene_FxOp+2
    INC.w C2Scene_FxTask.State,X
    LDY.w #1
    LDA.b !C2Scene_MosaicShadow
    ORA.b [!C2Scene_FxOp],Y
    STA.b !C2Scene_MosaicShadow
    LDY.w #2
    LDA.b [!C2Scene_FxOp],Y
    BNE .timed
    LDA.b !C2Scene_MosaicShadow
    ORA.b #!C2Scene_MosaicSizeMask
    STA.b !C2Scene_MosaicShadow
    SEC
    RTS
.timed:
    STA.w C2Scene_FxTask.Rate,X
    STZ.w C2Scene_FxTask.Timer,X

; $C2:2238 — C2Scene_MosaicInStep (34 bytes, $2238–$2259)
; State 1: once .Timer reaches .Rate, .Timer's low byte = 0 and the
; mosaic size goes up one; when that makes it the largest ($F0) the task
; ends (C=1).
; Quirk, kept: the step is added to the whole byte, so a size already
; at the largest overflows into 0 (and the carry is lost) and the
; growth goes round again, ending only at the next $F0.
; Callers note: none direct (C2Scene_MosaicInStates; C2Scene_MosaicInStart
;   falls into it).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (the PPU shadows), DB=$00
;        (low WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; C=1 done, C=0 not yet; A clobbered
; No calls.
C2Scene_MosaicInStep:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.Timer,X
    CMP.w C2Scene_FxTask.Rate,X
    BCS .step
    CLC
    RTS
.step:
    STZ.w C2Scene_FxTask.Timer,X
    LDA.b !C2Scene_MosaicShadow
    CLC
    ADC.b #!C2Scene_MosaicSizeStep
    STA.b !C2Scene_MosaicShadow
    AND.b #!C2Scene_MosaicSizeMask
    CMP.b #!C2Scene_MosaicSizeMask
    BEQ .done
    CLC
    RTS
.done:
    SEC
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
; Callers (5 JSL sites): unmatched ($C2:6752, $C2:6D10, $C2:704F, $C2:711D, $C6:E9FF).
; Callers of Trig_Sin1024 (9 JSL sites): unmatched ($C2:673B, $C2:6D17, $C2:7062, $C2:712D,
;   $C2:76CB, $C2:77D9, $C2:7D33, $C2:7DB9, $C6:EA17).
; Callers note (JSL): Trig_Cos1024 from $C2:6752, $C2:6D10, $C2:704F,
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
; Scene setup steps ($C2:232D–$C2:2335, $C2:26A8–$C2:274C)
; ============================================================

org $C2232D
; $C2:232D — C2Scene_ClearUnk1B30 (9 bytes, $232D–$2335)
; Zeroes the two bytes right after the task records, C2Scene_Unk1B30 and
; C2Scene_Unk1B31 (their use is not traced).
; Callers (1 JSR site): C2Scene_Main ($C2:23AB).
; Entry: M any (SEP #$20 here), X any, DP any, DB with low WRAM at
;        $0000-$1FFF ($00 from the boot)
; Exit:  M=1; A, X, Y, DP and DB unchanged
; No calls.
C2Scene_ClearUnk1B30:
    SEP #$20
    STZ.w !C2Scene_Unk1B30
    STZ.w !C2Scene_Unk1B31
    RTS

; ============================================================
; Scene helpers: random byte, box overlap ($C2:2336–$C2:23A7)
; ============================================================

; $C2:2336 — C2Scene_Random (15 bytes, $2336–$2344)
; Returns the next byte of RandomTable ($C0:FE00): the one at index
; C2Scene_Unk1B30, which then goes up by one (wrapping at 256).
; Callers (7 JSR sites): unmatched ($C2:7575, $C2:7598, $C2:79E0, $C2:7A0C, $C2:7A1F, $C2:7A31,
;   $C2:7A44).
; Callers note (7 JSR sites, all unmatched): $C2:7575, $C2:7598, $C2:79E0,
;   $C2:7A0C, $C2:7A1F, $C2:7A31 and $C2:7A44 (xref also finds a doubtful
;   one at $C2:754D).
; Entry: M, X any (SEP #$30 here), DP any, DB with low WRAM at
;        $0000-$1FFF (C2Scene_Unk1B30 is read absolute)
; Exit:  M=1, X=0; A = the random byte; X = the index used (8-bit, so
;        its high byte is 0); Y unchanged; C2Scene_Unk1B30 + 1
; No calls.
C2Scene_Random:
    SEP #$30
    LDX.w !C2Scene_Unk1B30
    LDA.l RandomTable,X
    INC.w !C2Scene_Unk1B30
    REP #$10
    RTS

; $C2:2345 — C2Scene_BoxesOverlap (99 bytes, $2345–$23A7)
; Tests whether two boxes overlap. Box A is centred on (C2Scene_BoxAX,
; C2Scene_BoxAY) and box B on (C2Scene_BoxBX, C2Scene_BoxBY); each has
; four 16-bit extents at its long pointer (C2Scene_BoxAPtr,
; C2Scene_BoxBPtr): +0 left, +2 right, +4 up, +6 down (inferred from
; which extent is used on which side). .test_x takes the X distance
; between the centres less A's extent towards B and B's extent towards
; A; a negative result means they overlap on that axis (C=1), 0 or more
; is a gap (C=0). The same for Y in .test_y.
; Equal centres count as overlapping on that axis; boxes that just
; touch (a result of exactly 0) do not.
; Quirk, kept: the SEC before the last RTS is redundant (C is already 1
; when .test_y returns there).
; Callers (5 JSR sites): C2Scene_ObjWatchIdle ($C2:3118, $C2:317D) and unmatched ($C2:490E,
;   $C2:493D, $C2:4A03).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (the C2Tmp block holds the
;        centres and pointers), DB any (all reads are direct page or long
;        indirect)
; Exit:  M=0, X=0; C=1: the boxes overlap, C=0: they do not; A clobbered;
;        Y = 2 (decided in .test_x) or 4 (in .test_y), the last extent
;        offset used; X and DP unchanged
; Calls: .test_x, .test_y (internal JSRs).
!C2Scene_BoxAX = !C2Tmp_08              ; in: box A's centre X (16-bit)
!C2Scene_BoxAY = !C2Tmp_0A              ; in: box A's centre Y
!C2Scene_BoxBX = !C2Tmp_0C              ; in: box B's centre X
!C2Scene_BoxBY = !C2Tmp_0E              ; in: box B's centre Y
!C2Scene_BoxAPtr = !C2Tmp_10            ; in: 24-bit pointer to box A's extents ($10-$12)
!C2Scene_BoxBPtr = !C2Tmp_13            ; in: 24-bit pointer to box B's extents ($13-$15)
C2Scene_BoxesOverlap:
    REP #$20
    JSR .test_x
    BCC .done
    JSR .test_y
    BCC .done
    SEC
.done:
    RTS
.test_x:
    LDY.w #2
    LDA.b !C2Scene_BoxBX
    SEC
    SBC.b !C2Scene_BoxAX
    BEQ .x_hit
    BCC .b_left
    SEC                         ; B right of A: minus A's right, B's left
    SBC.b [!C2Scene_BoxAPtr],Y
    SEC
    SBC.b [!C2Scene_BoxBPtr]
    BMI .x_hit
    CLC
    RTS
.b_left:
    EOR.w #!Eng_Invert16
    INC A                       ; |distance|: minus B's right, A's left
    SEC
    SBC.b [!C2Scene_BoxBPtr],Y
    SEC
    SBC.b [!C2Scene_BoxAPtr]
    BMI .x_hit
    CLC
    RTS
.x_hit:
    SEC
    RTS
.test_y:
    SEC
    LDA.b !C2Scene_BoxBY
    SBC.b !C2Scene_BoxAY
    BEQ .y_hit
    BCC .b_above
    LDY.w #6                    ; B below A: minus A's down, B's up
    SEC
    SBC.b [!C2Scene_BoxAPtr],Y
    LDY.w #4
    SEC
    SBC.b [!C2Scene_BoxBPtr],Y
    BMI .y_hit
    CLC
    RTS
.b_above:
    EOR.w #!Eng_Invert16
    INC A                       ; |distance|: minus B's down, A's up
    LDY.w #6
    SEC
    SBC.b [!C2Scene_BoxBPtr],Y
    LDY.w #4
    SEC
    SBC.b [!C2Scene_BoxAPtr],Y
    BMI .y_hit
    CLC
    RTS
.y_hit:
    SEC
    RTS

; ============================================================
; Scene main loop ($C2:23A8–$C2:2401)
; ============================================================

; $C2:23A8 — C2Scene_Main (51 bytes, $23A8–$23DA, with the sub-entry
; C2Scene_MainLoop at $C2:23CF)
; The scene mode's main program, entered once from BankC2_SceneBoot.
; Setup: VRAM cleared (C2Scene_ClearVram), C2Scene_ClearUnk1B30, the
; sprite list's links (C2Scene_SprInitLinks), the tasks
; (C2Scene_TaskClearAll), no sound command pending
; (C2Scene_SoundCmdState), C2Scene_Unk1BF6 = 0, a copy of the end of the
; flag block (C2Scene_SaveFlagTail), the start position and scroll from
; the field's entry tile (C2Scene_SetStartPos, C2Scene_SetStartScroll),
; and C2Scene_LoadScene (it loads the scene and spawns its script task);
; then both NMI flags
; (update and palette upload) and NMI with auto-joypad on.
; C2Scene_MainLoop then waits for the next frame (C2Scene_WaitOneFrame)
; and jumps through C2Scene_ModeTable on C2Scene_Mode. The handlers come
; back to C2Scene_MainLoop by JMP or BRA; the per-frame work itself is in
; the NMI (C2Scene_NmiHandler).
; Callers (1 JMP site): BankC2_SceneBoot ($C2:0040).
; Callers of C2Scene_MainLoop (4 JMP sites): C2Scene_Mode3 ($C2:244F), C2Scene_Mode5 ($C2:258A),
;   C2Scene_Mode6 ($C2:261A) and C2Scene_Mode8 ($C2:26A5).
; Callers note: JMP from BankC2_SceneBoot ($C2:0040). C2Scene_MainLoop: from
;   C2Scene_ModeIdle and the mode handlers C2Scene_Mode3 (JMP at
;   $C2:244F), C2Scene_Mode5 ($C2:258A), C2Scene_Mode6 ($C2:261A) and
;   C2Scene_Mode8 ($C2:26A5).
; Entry: M=1, X=0, DP=$0000, DB=$00 (as BankC2_SceneBoot leaves them;
;        the dispatch reads C2Scene_Mode absolute and uses TDC for a zero
;        high byte)
; Exit:  never returns (each handler is entered with M=1, X=0, A = the
;        mode * 2, X = the same)
; Calls: C2Scene_ClearVram, C2Scene_ClearUnk1B30, C2Scene_SprInitLinks,
;   C2Scene_TaskClearAll, C2Scene_SaveFlagTail, C2Scene_SetStartPos,
;   C2Scene_SetStartScroll, C2Scene_LoadScene, C2Scene_WaitOneFrame.
org $C223A8
C2Scene_Main:
    JSR C2Scene_ClearVram
    JSR C2Scene_ClearUnk1B30
    JSR C2Scene_SprInitLinks
    JSR C2Scene_TaskClearAll
    STZ.w !C2Scene_SoundCmdState
    STZ.w !C2Scene_Unk1BF6
    JSR C2Scene_SaveFlagTail
    JSR C2Scene_SetStartPos
    JSR C2Scene_SetStartScroll
    JSR C2Scene_LoadScene
    LDA.b #!C2Scene_NmiUpdate|!C2Scene_NmiPalette
    TSB.b !C2Scene_NmiFlags
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
C2Scene_MainLoop:               ; header: see C2Scene_Main
    JSR C2Scene_WaitOneFrame
    TDC                         ; A = DP = 0: clears the high byte
    LDA.w !C2Scene_Mode
    ASL A
    TAX
    JMP (C2Scene_ModeTable,X)

; $C2:23DB — C2Scene_ModeTable (10 words, $23DB–$23EE)
; C2Scene_MainLoop's handler for each C2Scene_Mode value 0-9. Modes 0, 1
; and 7 only send a pending sound command (C2Scene_ModeIdle). The others
; have their own handlers, C2Scene_Mode2-C2Scene_Mode6 and
; C2Scene_Mode8, mode 9 sharing C2Scene_Mode5's (the scene mode handlers
; below).
C2Scene_ModeTable:
    dw C2Scene_ModeIdle         ; 0
    dw C2Scene_ModeIdle         ; 1
    dw C2Scene_Mode2            ; 2
    dw C2Scene_Mode3            ; 3
    dw C2Scene_Mode4            ; 4
    dw C2Scene_Mode5            ; 5
    dw C2Scene_Mode6            ; 6
    dw C2Scene_ModeIdle         ; 7
    dw C2Scene_Mode8            ; 8
    dw C2Scene_Mode5            ; 9

; $C2:23EF — C2Scene_ModeIdle (19 bytes, $23EF–$2401)
; C2Scene_Mode 0, 1 and 7: if a sound command is pending
; (C2Scene_SoundCmdState), sends it with Audio_DriverCommand as
; C2Scene_WaitFrames does; then back to C2Scene_MainLoop.
; Callers note: none direct (C2Scene_ModeTable).
; Entry: M=1, X=0, DP=$0000, DB with low WRAM at $0000-$1FFF ($00)
; Exit:  continues at C2Scene_MainLoop, M=1, X=0
; Calls: Audio_DriverCommand (JSL).
C2Scene_ModeIdle:
    LDA.w !C2Scene_SoundCmdState
    BEQ C2Scene_MainLoop
    LDA.b #!C2Scene_SoundCmdSending
    STA.w !C2Scene_SoundCmdState
    JSL Audio_DriverCommand
    STZ.w !C2Scene_SoundCmdState
    BRA C2Scene_MainLoop

; ============================================================
; Scene mode handlers ($C2:2402–$C2:26A7)
; ============================================================
; C2Scene_MainLoop jumps to one of these through C2Scene_ModeTable when
; C2Scene_Mode is 2-6, 8 or 9 (who sets the mode is mostly unmatched;
; script op $05 sets 2). Each runs to its end inside one pass of the
; loop: the ones that come back set C2Scene_ModeIdle1 and JMP to
; C2Scene_MainLoop; modes 2 and 4 never come back. All are entered with
; M=1, X=0, DP=$0000, DB=$00 (C2Scene_Main's state), A = X = the mode *
; 2, and need DB=$00 for their absolute register and low-WRAM accesses.

; $C2:2402 — C2Scene_Mode3 (211 bytes, $2402–$24D4)
; Mode 3: acts on the C2Scene_ListA entry at byte offset
; C2Scene_Unk1B32 (probably an exit the player has reached):
; - its .Loc is C2Scene_ListANoLoc: starts the script whose address is
;   word .EntryX of C2Scene_ListD (bank $7F, the scene script's bank),
;   keeps that address in C2Scene_Unk1B45, zeroes C2Scene_MemberWords
;   and C2Scene_Unk1B43, sets C2Scene_Unk0280 = 1 and goes back to the
;   loop in mode C2Scene_ModeIdle1;
; - otherwise it fades out (C2Scene_ScrFadeOut; it waits
;   C2Scene_FadeOutWaitFrames frames with C2Scene_WaitFrame, so no queued
;   sound is sent meanwhile), turns NMI off and sets up the location
;   change as script op $05 does (C2Script_GoToLocation: the return
;   location, X and Y from the current location and BG2's tile
;   position, also copied to C2Scene_SavedReturnId/X/Y), here with the
;   entry's .Loc, .EntryX and .EntryY. The entry facing is .Loc's high
;   byte shifted right once (bits 9-15), and the return facing is that
;   facing turned around (C2Scene_TurnAround[facing AND 3]), as op $05
;   does; then falls into C2Scene_Mode2,
;   which leaves the scene.
; Callers note: none direct (C2Scene_ModeTable entry 3).
; Entry: M=1, X=0, DP=$0000 (TDC for 0), DB=$00 (absolute registers,
;        DP_Field and low WRAM); C2Scene_Unk1B32 = the entry's offset
; Exit:  a script started: continues at C2Scene_MainLoop with M=1, X=0;
;        A, X, Y clobbered. Leaving: never returns (C2Scene_Mode2)
; Calls: C2Scene_TaskSpawnScript, C2Scene_WaitFrame; falls into
;   C2Scene_Mode2.
C2Scene_Mode3:
    TDC                         ; A = DP = 0
    STA.w NMITIMEN
    REP #$20
    LDX.w !C2Scene_Unk1B32
    LDA.l C2Scene_ListAEntry.Loc,X
    AND.w #!C2Scene_LocIdMask
    CMP.w #!C2Scene_ListANoLoc
    BNE .leave
    LDA.l C2Scene_ListAEntry.EntryX,X
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    LDA.l !C2Scene_ListD,X
    STA.w !C2Scene_Unk1B45
    SEP #$20
    LDA.b #bank(!C2Scene_ScriptBuf)
    LDX.w !C2Scene_Unk1B45
    JSR C2Scene_TaskSpawnScript
    LDX.w #$0000
    STX.w !C2Scene_MemberWords
    STX.w !C2Scene_MemberWords+2
    STX.w !C2Scene_MemberWords+4
    STZ.w !C2Scene_Unk1B43
    LDA.b #1
    STA.w !C2Scene_Unk0280
    LDA.b #!C2Scene_ModeIdle1
    STA.w !C2Scene_Mode
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
    JMP C2Scene_MainLoop
.leave:
    SEP #$20
    LDA.b #bank(C2Scene_ScrFadeOut)
    LDX.w #C2Scene_ScrFadeOut
    JSR C2Scene_TaskSpawnScript
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
    LDX.w #!C2Scene_FadeOutWaitFrames
.wait:
    PHX
    JSR C2Scene_WaitFrame
    PLX
    DEX
    BNE .wait
    TDC
    STA.w NMITIMEN
    REP #$20
    LDA.w !DP_Field+!Loc_Id
    STA.w !DP_Field+!Loc_ReturnId
    STA.w !C2Scene_SavedReturnId
    LDA.b !C2Scene_BgTileX+2
    CLC
    ADC.w #!C2Scene_ReturnTileOfs
    CMP.w #!C2Scene_MapTilesX
    BCC .x_ok
    SBC.w #!C2Scene_MapTilesX
.x_ok:
    STA.w !DP_Field+!Loc_ReturnX ; 16-bit: Loc_ReturnY is written below
    STA.w !C2Scene_SavedReturnX
    LDA.b !C2Scene_BgTileY+2
    CLC
    ADC.w #!C2Scene_ReturnTileOfs
    AND.w #!C2Scene_MapTilesY-1
    SEP #$20
    STA.w !DP_Field+!Loc_ReturnY
    STA.w !C2Scene_SavedReturnY
    LDX.w !C2Scene_Unk1B32
    REP #$20
    LDA.l C2Scene_ListAEntry.Loc,X
    AND.w #!C2Scene_LocIdMask
    STA.w !DP_Field+!Loc_Id
    SEP #$20
    LDA.l C2Scene_ListAEntry.Loc+1,X ; the bits above the location
    LSR A
    STA.w !DP_Field+!Loc_EntryFacing
    LDA.l C2Scene_ListAEntry.EntryX,X
    STA.w !DP_Field+!Loc_EntryX
    LDA.l C2Scene_ListAEntry.EntryY,X
    STA.w !DP_Field+!Loc_EntryY
    TDC
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #3
    TAX
    LDA.l C2Scene_TurnAround,X
    STA.w !DP_Field+!Loc_ReturnFacing

; $C2:24D5 — C2Scene_Mode2 (52 bytes, $24D5–$2508)
; Mode 2 (set by script op $05) and the end of C2Scene_Mode3: leaves the
; scene. Interrupts, NMI, DMA and HDMA off; the flag tail copied back to
; $7F:01F0 (C2Scene_RestoreFlagTail); sound commands C2Scene_SoundCmd82
; and C2Scene_SoundCmd83 (arguments 0, $FF; not traced) sent straight
; to the driver; then JML to ReentryVectors ($C0:0000), which restarts
; the field's game loop with the location block DP_Field as set up.
; Callers note: none direct (C2Scene_ModeTable entry 2; C2Scene_Mode3 falls
;   in).
; Entry: M=1, X=0, DP=$0000 (TDC for 0), DB=$00 (absolute registers and
;        the driver block)
; Exit:  never returns
; Calls: C2Scene_RestoreFlagTail, Audio_DriverCommand (JSL), JML
;   ReentryVectors.
C2Scene_Mode2:
    SEI
    TDC
    STA.w NMITIMEN
    STA.w MDMAEN
    STA.w HDMAEN
    JSR C2Scene_RestoreFlagTail
    LDA.b #!C2Scene_SoundCmd82
    STA.w !Audio_CmdId
    STZ.w !Audio_CmdArg0
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !Audio_CmdArg1
    JSL Audio_DriverCommand
    LDA.b #!C2Scene_SoundCmd83
    STA.w !Audio_CmdId
    STZ.w !Audio_CmdArg0
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !Audio_CmdArg1
    JSL Audio_DriverCommand
    JML ReentryVectors

; $C2:2509 — C2Scene_TurnAround (4 bytes, $2509–$250C)
; Facing 0-3 -> the opposite facing (the facing EOR 1). Read by
; C2Script_GoToLocation (as C2SceneRom_TurnAround) and C2Scene_Mode3.
C2Scene_TurnAround:
    db $01,$00,$03,$02

; $C2:250D — C2Scene_Mode4 (17 bytes, $250D–$251D)
; Mode 4: interrupts, NMI, DMA and HDMA off, the flag tail copied back
; (C2Scene_RestoreFlagTail), and again, for good: it never leaves
; (probably waits for a reset; who sets mode 4 is not matched).
; Callers note: none direct (C2Scene_ModeTable entry 4); its own JMP at
;   $C2:251B.
; Entry: M=1, X=0, DP=$0000 (TDC for 0), DB=$00 (absolute registers)
; Exit:  never returns
; Calls: C2Scene_RestoreFlagTail.
C2Scene_Mode4:
    SEI
    TDC
    STA.w NMITIMEN
    STA.w MDMAEN
    STA.w HDMAEN
    JSR C2Scene_RestoreFlagTail
    JMP C2Scene_Mode4

; $C2:251E — C2Scene_Mode5 (111 bytes, $251E–$258C)
; Modes 5 (C2Scene_ModeMenu) and 9: run the menu over the scene. Fades
; out (C2Scene_ScrFadeOut, C2Scene_FadeWaitFrames frames), turns
; interrupts, NMI, DMA and HDMA (and its shadow) off, saves the scene
; (C2Scene_SaveState) and calls BankC2_Entry8000 with A =
; C2Scene_MenuArgMenu for mode 5 or ExitMenu_Mode5 for mode 9 (the
; values the field passes at $C0:1960 and $C0:19CE). Then it sets the
; scene back up: registers (BankC2_InitHwRegs), interrupt vectors
; (C2Scene_InstallInterrupts), C2Scene_RestoreState, the VRAM queue
; (C2Scene_VramQInit) and the graphics (C2Scene_ReloadScene); fades in
; (C2Scene_ScrFadeIn), adds one to C2Scene_Unk1B59 when C2Scene_Unk1B58
; is set, turns the NMI updates and NMI on, waits
; C2Scene_FadeWaitFrames frames and goes back to the loop in mode
; C2Scene_ModeIdle1.
; Callers note: none direct (C2Scene_ModeTable entries 5 and 9).
; Entry: M=1, X=0, DP=$0000, DB=$00 (absolute registers and low WRAM)
; Exit:  continues at C2Scene_MainLoop with M=1, X=0; A, X, Y clobbered
; Calls: C2Scene_TaskSpawnScript, C2Scene_WaitFrames, C2Scene_SaveState,
;   BankC2_Entry8000 (JSL), BankC2_InitHwRegs, C2Scene_InstallInterrupts,
;   C2Scene_RestoreState, C2Scene_VramQInit, C2Scene_ReloadScene.
C2Scene_Mode5:
    TDC
    STA.w NMITIMEN
    LDA.b #bank(C2Scene_ScrFadeOut)
    LDX.w #C2Scene_ScrFadeOut
    JSR C2Scene_TaskSpawnScript
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
    LDX.w #!C2Scene_FadeWaitFrames
    JSR C2Scene_WaitFrames
    SEI
    TDC
    STA.w NMITIMEN
    STA.w MDMAEN
    STA.w HDMAEN
    STA.b !C2Scene_HdmaenShadow
    JSR C2Scene_SaveState
    LDA.w !C2Scene_Mode
    CMP.b #!C2Scene_ModeMenu
    BNE .mode9
    LDA.b #!C2Scene_MenuArgMenu
    BRA .call
.mode9:
    LDA.b #!ExitMenu_Mode5
.call:
    JSL BankC2_Entry8000
    SEI
    JSR BankC2_InitHwRegs
    JSR C2Scene_InstallInterrupts
    JSR C2Scene_RestoreState
    JSR C2Scene_VramQInit
    JSR C2Scene_ReloadScene
    LDA.b #bank(C2Scene_ScrFadeIn)
    LDX.w #C2Scene_ScrFadeIn
    JSR C2Scene_TaskSpawnScript
    LDA.w !C2Scene_Unk1B58
    BEQ .resume
    INC.w !C2Scene_Unk1B59
.resume:
    LDA.b #!C2Scene_NmiUpdate|!C2Scene_NmiPalette
    TSB.b !C2Scene_NmiFlags
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
    LDX.w #!C2Scene_FadeWaitFrames
    JSR C2Scene_WaitFrames
    LDA.b #!C2Scene_ModeIdle1
    STA.w !C2Scene_Mode
    JMP C2Scene_MainLoop

; $C2:258D — C2Scene_Mode6 (144 bytes, $258D–$261C)
; Mode 6: runs C2Scene_Unk631F (it sets BG mode 7 and runs its own
; tasks until the mode changes from 6: probably a mode-7 view) between a
; mosaic fade out and in. Starts C2Scene_ScrMosaicFadeOut and waits
; C2Scene_Mode6OutFrames frames; interrupts, NMI, DMA and HDMA (and its
; shadow) off; copies dp $00-$EF to C2Scene_SaveDp and the 64 task
; records to C2Scene_SaveLowRam ($7F:2800: not where C2Scene_SaveState
; puts them), runs C2Scene_Unk631F, copies both back; then the VRAM
; queue and graphics (C2Scene_VramQInit, C2Scene_ReloadScene),
; C2Scene_ScrMosaicFadeIn, C2Scene_Unk1B59 + 1 when C2Scene_Unk1B58 is
; set, NMI updates and NMI on, C2Scene_Mode6InFrames frames, mode
; C2Scene_ModeIdle1 and back to the loop.
; Callers note: none direct (C2Scene_ModeTable entry 6).
; Entry: M=1, X=0, DP=$0000, DB=$00 (absolute registers and low WRAM)
; Exit:  continues at C2Scene_MainLoop with M=1, X=0, DB=$00; A, X, Y
;        clobbered
; Calls: C2Scene_TaskSpawnScript, C2Scene_WaitFrames, C2Scene_Unk631F,
;   C2Scene_VramQInit, C2Scene_ReloadScene.
C2Scene_Mode6:
    TDC
    STA.w NMITIMEN
    LDA.b #bank(C2Scene_ScrMosaicFadeOut)
    LDX.w #C2Scene_ScrMosaicFadeOut
    JSR C2Scene_TaskSpawnScript
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
    LDX.w #!C2Scene_Mode6OutFrames
    JSR C2Scene_WaitFrames
    SEI
    TDC
    STA.w NMITIMEN
    STA.w MDMAEN
    STA.w HDMAEN
    STA.b !C2Scene_HdmaenShadow
    REP #$20
    PHB
    LDX.w #!C2Scene_DpClearStart
    LDY.w #!C2Scene_SaveDp&$FFFF
    LDA.w #!C2Scene_SaveDpBytes-1
    MVN bank(!C2Scene_SaveDp),!Bank00 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_TaskRecords
    LDY.w #!C2Scene_SaveLowRam&$FFFF
    LDA.w #!C2Scene_TaskRecordsEnd-!C2Scene_TaskRecords-1
    MVN bank(!C2Scene_SaveLowRam),!Bank00 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    JSR C2Scene_Unk631F
    REP #$20
    PHB
    LDX.w #!C2Scene_SaveDp&$FFFF
    LDY.w #!C2Scene_DpClearStart
    LDA.w #!C2Scene_SaveDpBytes-1
    MVN !Bank00,bank(!C2Scene_SaveDp) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_SaveLowRam&$FFFF
    LDY.w #!C2Scene_TaskRecords
    LDA.w #!C2Scene_TaskRecordsEnd-!C2Scene_TaskRecords-1
    MVN !Bank00,bank(!C2Scene_SaveLowRam) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    JSR C2Scene_VramQInit
    JSR C2Scene_ReloadScene
    LDA.b #bank(C2Scene_ScrMosaicFadeIn)
    LDX.w #C2Scene_ScrMosaicFadeIn
    JSR C2Scene_TaskSpawnScript
    LDA.w !C2Scene_Unk1B58
    BEQ .resume
    INC.w !C2Scene_Unk1B59
.resume:
    LDA.b #!C2Scene_NmiUpdate|!C2Scene_NmiPalette
    TSB.b !C2Scene_NmiFlags
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
    LDX.w #!C2Scene_Mode6InFrames
    JSR C2Scene_WaitFrames
    LDA.b #!C2Scene_ModeIdle1
    STA.w !C2Scene_Mode
    JMP C2Scene_MainLoop

; $C2:261D — C2Scene_Mode8 (139 bytes, $261D–$26A7)
; Mode 8: runs C2Scene_Unk6A34 (not matched; it clears VRAM and the
; tasks itself) over a saved scene. Fades out (C2Scene_ScrFadeOut,
; C2Scene_FadeOutWaitFrames frames), turns interrupts, NMI, DMA and HDMA
; (and its shadow) off,
; sends C2Scene_SoundCmd82 (arguments 0, $FF) straight to the driver,
; saves the scene (C2Scene_SaveState), runs C2Scene_Unk6A34, restores
; (C2Scene_RestoreState) and resets the VRAM queue. Then, unless
; $7F:01F4 AND $0A or $7F:01F5 AND $02 is non-zero (two flag bytes of
; Menu_FlagBlock7F; who sets them is not traced), it
; reloads the graphics (C2Scene_ReloadScene) and fades in
; (C2Scene_ScrFadeIn, C2Scene_Unk1B59 + 1 when C2Scene_Unk1B58 is set).
; NMI updates and NMI on either way; with the flags clear it waits
; C2Scene_FadeWaitFrames frames and sets mode C2Scene_ModeIdle1, with
; them set it goes back to the loop at once, in whatever mode was set
; while C2Scene_Unk6A34 ran (it loops at $C2:6A9C-$C2:6AA4 until
; C2Scene_Mode is no longer 8, and C2Scene_RestoreState does not
; restore it).
; Callers note: none direct (C2Scene_ModeTable entry 8).
; Entry: M=1, X=0, DP=$0000, DB=$00 (absolute registers and low WRAM)
; Exit:  continues at C2Scene_MainLoop with M=1, X=0; A, X, Y clobbered
; Calls: C2Scene_TaskSpawnScript, C2Scene_WaitFrames, Audio_DriverCommand
;   (JSL), C2Scene_SaveState, C2Scene_Unk6A34, C2Scene_RestoreState,
;   C2Scene_VramQInit, C2Scene_ReloadScene.
C2Scene_Mode8:
    TDC
    STA.w NMITIMEN
    LDA.b #bank(C2Scene_ScrFadeOut)
    LDX.w #C2Scene_ScrFadeOut
    JSR C2Scene_TaskSpawnScript
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
    LDX.w #!C2Scene_FadeOutWaitFrames
    JSR C2Scene_WaitFrames
    SEI
    TDC
    STA.w NMITIMEN
    STA.w MDMAEN
    STA.w HDMAEN
    STA.b !C2Scene_HdmaenShadow
    LDA.b #!C2Scene_SoundCmd82
    STA.w !Audio_CmdId
    STZ.w !Audio_CmdArg0
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !Audio_CmdArg1
    JSL Audio_DriverCommand
    JSR C2Scene_SaveState
    JSR C2Scene_Unk6A34
    JSR C2Scene_RestoreState
    JSR C2Scene_VramQInit
    LDA.l !C2Scene_Unk7F01F4
    BIT.b #!C2Scene_Unk7F01F4Bits
    BNE .resume
    LDA.l !C2Scene_Unk7F01F5
    BIT.b #!C2Scene_Unk7F01F5Bit1
    BNE .resume
    JSR C2Scene_ReloadScene
    LDA.b #bank(C2Scene_ScrFadeIn)
    LDX.w #C2Scene_ScrFadeIn
    JSR C2Scene_TaskSpawnScript
    LDA.w !C2Scene_Unk1B58
    BEQ .resume
    INC.w !C2Scene_Unk1B59
.resume:
    LDA.b #!C2Scene_NmiUpdate|!C2Scene_NmiPalette
    TSB.b !C2Scene_NmiFlags
    LDA.b #!NMITIMEN_NmiJoy
    STA.w NMITIMEN
    LDA.l !C2Scene_Unk7F01F4
    BIT.b #!C2Scene_Unk7F01F4Bits
    BNE .back
    LDA.l !C2Scene_Unk7F01F5
    BIT.b #!C2Scene_Unk7F01F5Bit1
    BNE .back
    LDX.w #!C2Scene_FadeWaitFrames
    JSR C2Scene_WaitFrames
    LDA.b #!C2Scene_ModeIdle1
    STA.w !C2Scene_Mode
.back:
    JMP C2Scene_MainLoop

org $C226A8
; $C2:26A8 — C2Scene_ClearVram (44 bytes, $26A8–$26D3)
; Zeroes all of VRAM with one DMA on channel 7: word writes to
; VMDATAL/H from the fixed source C2Scene_ZeroWord, VRAM address 0, a
; byte count of 0 (= 65536 bytes). Needs forced blank, which the boot has
; set.
; Callers (3 JSR sites): C2Scene_Main ($C2:23A8) and unmatched ($C2:632E, $C2:6A34).
; Entry: M=1 (8-bit register values), X=0 (16-bit address and count
;        stores), DP any, DB=$00 (absolute register stores)
; Exit:  M=1, X=0; A = MDMAEN_Ch7, X = 0; Y, DP and DB unchanged
; No calls.
C2Scene_ClearVram:
    LDX.w #$0000
    STX.w VMADDL
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDA.b #!DMAP_FixedSource|!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #C2Scene_ZeroWord
    STX.w A1T7L
    LDA.b #bank(C2Scene_ZeroWord)
    STA.w A1B7
    LDX.w #$0000                ; 0 = 65536 bytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

; $C2:26D4 — C2Scene_ZeroWord (2 bytes, $26D4–$26D5)
; The fixed DMA source of C2Scene_ClearVram.
C2Scene_ZeroWord:
    dw $0000

; $C2:26D6 — C2Scene_SaveFlagTail (26 bytes, $26D6–$26EF)
; Copies the last 16 bytes of Menu_FlagBlock7F ($7F:01F0-$01FF) to
; C2Scene_FlagTailCopy and its first byte (Eng_Unk7F0000) to
; C2Scene_Flag0Copy. C2Scene_RestoreFlagTail copies the 16 bytes back.
; Callers (1 JSR site): C2Scene_Main ($C2:23BA).
; Entry: M any (REP #$20 here), X=0, DP any, DB any (saved around the
;        MVN; the last store is absolute, so DB with low WRAM at
;        $0000-$1FFF: $00 from the boot)
; Exit:  M=1, X=0; A = the flag byte (B = $FF from the MVN), X = $0200,
;        Y = C2Scene_FlagTailCopy + 16; DP and DB unchanged
; No calls.
C2Scene_SaveFlagTail:
    REP #$20
    PHB
    LDX.w #!Menu_FlagBlock7F+!Menu_FlagBlock7FSize-!C2Scene_FlagTailSize
    LDY.w #!C2Scene_FlagTailCopy
    LDA.w #!C2Scene_FlagTailSize-1
    MVN !Bank00,!Bank7F         ; $7F:01F0 → $00:1BA7  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    LDA.l !Eng_Unk7F0000
    STA.w !C2Scene_Flag0Copy
    RTS

; $C2:26F0 — C2Scene_RestoreFlagTail (19 bytes, $26F0–$2702)
; Copies C2Scene_FlagTailCopy (16 bytes) back to $7F:01F0-$01FF, the end
; of Menu_FlagBlock7F (C2Scene_Flag0Copy is not written back).
; Callers (2 JSR sites): C2Scene_Mode2 ($C2:24E0) and C2Scene_Mode4 ($C2:2518).
; Entry: M any (REP #$20 here), X=0, DP any, DB any (saved around the
;        MVN)
; Exit:  M=1, X=0; A = $FFFF, X = C2Scene_FlagTailCopy + 16, Y = $0200;
;        DP and DB unchanged
; No calls.
C2Scene_RestoreFlagTail:
    REP #$20
    PHB
    LDX.w #!C2Scene_FlagTailCopy
    LDY.w #!Menu_FlagBlock7F+!Menu_FlagBlock7FSize-!C2Scene_FlagTailSize
    LDA.w #!C2Scene_FlagTailSize-1
    MVN !Bank7F,!Bank00         ; $00:1BA7 → $7F:01F0  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    RTS

; $C2:2703 — C2Scene_SetStartPos (29 bytes, $2703–$271F)
; C2Scene_StartX/Y = the field's entry tile (Loc_EntryX/Y, in the field's
; direct page at $0100) times 8: probably the start position in pixels
; (inferred only from the scaling).
; Callers (1 JSR site): C2Scene_Main ($C2:23BD).
; Entry: M any (REP #$20 here), X any, DP any, DB with low WRAM at
;        $0000-$1FFF ($00 from the boot)
; Exit:  M=1; A = C2Scene_StartY (B = its high byte); X, Y, DP and DB
;        unchanged
; No calls.
C2Scene_SetStartPos:
    REP #$20
    LDA.w !DP_Field+!Loc_EntryX
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    STA.w !C2Scene_StartX
    LDA.w !DP_Field+!Loc_EntryY
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    STA.w !C2Scene_StartY
    SEP #$20
    RTS

; $C2:2720 — C2Scene_SetStartScroll (45 bytes, $2720–$274C)
; Puts the entry tile (Loc_EntryX/Y) in the middle of the screen:
; C2Scene_BgTileX (both words) = Loc_EntryX - 16, plus 192 if that is
; negative; C2Scene_BgTileY (both words) = Loc_EntryY - 14, plus 128 if
; negative. (C2Scene_DrawBgLayer multiplies these by 8 into the BG1/BG2
; scroll shadows; 16 and 14 tiles are half of 256 x 224; 192 x 128 tiles
; are the 96 x 64 metatile maps it draws from.)
; Callers (1 JSR site): C2Scene_Main ($C2:23C0).
; Entry: M any (REP #$20 here), X any, DP=$0000, DB with low WRAM at
;        $0000-$1FFF ($00 from the boot)
; Exit:  M=1; A = the Y scroll tile (B = its high byte); X, Y, DP and DB
;        unchanged
; No calls.
C2Scene_SetStartScroll:
    REP #$20
    LDA.w !DP_Field+!Loc_EntryX
    AND.w #!Eng_LowByteMask
    SEC
    SBC.w #!C2Scene_HalfScreenTilesX
    BPL .x_done
    CLC
    ADC.w #!C2Scene_MapTilesX
.x_done:
    STA.b !C2Scene_BgTileX
    STA.b !C2Scene_BgTileX+2
    LDA.w !DP_Field+!Loc_EntryY
    AND.w #!Eng_LowByteMask
    SEC
    SBC.w #!C2Scene_HalfScreenTilesY
    BPL .y_done
    CLC
    ADC.w #!C2Scene_MapTilesY
.y_done:
    STA.b !C2Scene_BgTileY
    STA.b !C2Scene_BgTileY+2
    SEP #$20
    RTS

; ============================================================
; Scene loading ($C2:274D–$C2:2EC0)
; ============================================================
; Each scene (Loc_Id $01F0 on) has a header in bank $C6
; (C2SceneRom_HeaderTable, pointer in C2Scene_HeaderPtr) whose bytes pick
; packed data from pack tables in bank $C6 (C2SceneRom_*Packs, 3-byte long
; pointers); Decomp_ToWramVec unpacks each into WRAM. Graphics are staged
; at C2Scene_DecompBuf and DMAed to VRAM (C2Scene_LoadVram); the rest
; stays in WRAM. A header byte with bit 7 set loads nothing. What the
; packs contain is inferred from where they go (VRAM tile and map bases
; from BankC2_InitHwRegs; the metatile maps from C2Scene_DrawBgLayer).
;
; All of these run with DP=$0000 and DB=$00 (the scene's state) unless a
; header says otherwise: the header pointer is direct page, and
; Decomp_ToWramVec's parameters (Menu_DecompSrc..) are absolute stores.

; $C2:274D — C2Scene_GetHeaderPtr (27 bytes, $274D–$2767)
; C2Scene_HeaderPtr = $C6:(the word of C2SceneRom_HeaderTable for scene
; (Loc_Id AND C2Scene_LocIdMask) - Loc_FirstBankC2).
; Quirk, kept: there is no range check; Loc_Id bits 9-15 are dropped.
; Callers (1 JSR site): C2Scene_LoadScene ($C2:2C5C).
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB with low WRAM ($00)
;        (absolute read of the field's Loc_Id at $0100)
; Exit:  M=1, X=0; A = C2SceneRom_HeaderBank (B = the address's high
;        byte), X = the scene * 2; Y, DP and DB unchanged
; No calls.
C2Scene_GetHeaderPtr:
    REP #$20
    LDA.w !DP_Field+!Loc_Id
    AND.w #!C2Scene_LocIdMask
    SEC
    SBC.w #!Loc_FirstBankC2
    ASL A
    TAX
    LDA.l !C2SceneRom_HeaderTable,X
    STA.b !C2Scene_HeaderPtr
    SEP #$20
    LDA.b #!C2SceneRom_HeaderBank
    STA.b !C2Scene_HeaderPtr+2
    RTS

; $C2:2768 — C2Scene_LoadObjGfx (84 bytes, $2768–$27BB)
; Unpacks the scene's C2Scene_ObjPackCount sprite graphics packs (header
; bytes C2Scene_HdrObjGfx..+3, C2SceneRom_ObjPacks) into C2Scene_DecompBuf,
; C2Scene_PackSlotSize bytes apart (C2Scene_LoadVram DMAs all four to
; the sprite tiles at VRAM $0000). A pack number with bit 7 set leaves
; its slot as it was.
; Callers (1 JSR site): C2Scene_LoadVram ($C2:2CC1).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=0 (the loop ends 16-bit), X=0; A = 4, X and Y clobbered;
;        C2Tmp_08 = 4, C2Tmp_10-$12 = the header + C2Scene_HdrObjGfx;
;        Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
!C2Scene_PackIdx = !C2Tmp_08            ; 16-bit loop count / header byte index
!C2Scene_PackList = !C2Tmp_10           ; 24-bit pointer to the header bytes being read
C2Scene_LoadObjGfx:
    LDA.b !C2Scene_HeaderPtr+2
    STA.b !C2Scene_PackList+2
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    REP #$20
    CLC
    LDA.b !C2Scene_HeaderPtr
    ADC.w #!C2Scene_HdrObjGfx
    STA.b !C2Scene_PackList
    LDA.w #!C2Scene_DecompBuf&$FFFF
    STA.w !Menu_DecompDest
    STZ.b !C2Scene_PackIdx
.pack:
    SEP #$20
    LDY.b !C2Scene_PackIdx
    TDC                         ; A = DP = 0: B = 0 for the TAX
    LDA.b [!C2Scene_PackList],Y
    BMI .next
    ASL A
    ADC.b [!C2Scene_PackList],Y ; * C2Scene_PackEntrySize
    TAX
    REP #$20
    LDA.l !C2SceneRom_ObjPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_ObjPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.next:
    REP #$20
    CLC
    LDA.w !Menu_DecompDest
    ADC.w #!C2Scene_PackSlotSize
    STA.w !Menu_DecompDest
    INC.b !C2Scene_PackIdx
    LDA.b !C2Scene_PackIdx
    CMP.w #!C2Scene_ObjPackCount
    BNE .pack
    RTS

; $C2:27BC — C2Scene_LoadUnkC800 (34 bytes, $27BC–$27DD)
; Unpacks entry C2Scene_UnkC800Pack of C2SceneRom_ObjPacks (the same for
; every scene) to C2Scene_UnkC800 ($7E:C800); what it holds is not
; traced.
; Callers (1 JMP site): C2Scene_LoadVram ($C2:2D6D).
; Entry: M=1, X=0, DP any, DB=$00
; Exit:  M=1, X=0; A, X, Y as Decomp_ToWramVec leaves them (not traced);
;        Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadUnkC800:
    LDX.w #!C2Scene_UnkC800&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_UnkC800)
    STA.w !Menu_DecompDestBank
    REP #$20
    LDA.l !C2SceneRom_ObjPacks+(!C2Scene_UnkC800Pack*!C2Scene_PackEntrySize)
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_ObjPacks+(!C2Scene_UnkC800Pack*!C2Scene_PackEntrySize)+2
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTS

; $C2:27DE — C2Scene_LoadBgGfx (72 bytes, $27DE–$2825)
; Unpacks the scene's C2Scene_BgPackCount BG graphics packs (header bytes
; C2Scene_HdrBgGfx..+6, C2SceneRom_BgPacks) into C2Scene_DecompBuf,
; C2Scene_PackSlotSize bytes apart ($7F:9000-$FFFF; C2Scene_LoadVram DMAs
; them to the BG1/BG2 tiles at VRAM $2000). Bit 7 set: slot left as it
; was.
; Callers (2 JSR sites): C2Scene_LoadVram ($C2:2CDF) and unmatched ($C2:63DF).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=0, X=0; A = 7, X and Y clobbered; C2Tmp_08 = 7;
;        Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadBgGfx:
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    STZ.b !C2Scene_PackIdx
    STZ.b !C2Scene_PackIdx+1
.pack:
    SEP #$20
    LDY.b !C2Scene_PackIdx
    TDC                         ; A = DP = 0: B = 0 for the TAX
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .next
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_BgPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_BgPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.next:
    REP #$20
    CLC
    LDA.w !Menu_DecompDest
    ADC.w #!C2Scene_PackSlotSize
    STA.w !Menu_DecompDest
    INC.b !C2Scene_PackIdx
    LDA.b !C2Scene_PackIdx
    CMP.w #!C2Scene_BgPackCount
    BNE .pack
    RTS

; $C2:2826 — C2Scene_LoadBg3Gfx (46 bytes, $2826–$2853)
; Unpacks header byte C2Scene_HdrBg3Gfx's C2SceneRom_BgPacks entry into
; C2Scene_DecompBuf (C2Scene_LoadVram DMAs it to the BG3 tiles at VRAM
; $7000).
; Callers (1 JSR site): C2Scene_LoadVram ($C2:2CEE).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadBg3Gfx:
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrBg3Gfx
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_BgPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_BgPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:2854 — C2Scene_LoadBg3Map (46 bytes, $2854–$2881)
; Unpacks header byte C2Scene_HdrBg3Map's C2SceneRom_Bg3MapPacks entry
; into C2Scene_DecompBuf (C2Scene_LoadVram DMAs it to the BG3 tilemap at
; VRAM $7800).
; Callers (1 JSR site): C2Scene_LoadVram ($C2:2CFF).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadBg3Map:
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDY.w #!C2Scene_HdrBg3Map
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_Bg3MapPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_Bg3MapPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:2882 — C2Scene_LoadPalettes (107 bytes, $2882–$28EC)
; Unpacks the scene's palettes (header byte C2Scene_HdrPalettes,
; C2SceneRom_PalettePacks) into C2Scene_PaletteStage, then the party
; palettes (entry C2Scene_PartyPalPack) into C2Scene_PartyPalSrc, and
; copies the palette of each party member (Party_Members, the
; first C2Scene_PartyPalSize bytes of its 32) to C2Scene_PartyPalDest +
; 32 * the member's position: sprite palettes 4, 5 and 6 of the staged
; CGRAM image. Inferred: C2Scene_LoadVram uploads that image to CGRAM.
; The third copy is C2Scene_CopyPartyPalette entered by falling in.
; Callers (1 JSR site): C2Scene_LoadVram ($C2:2D10).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=0, X=0; DB unchanged; A = $FFFF, X and Y past the third copy
;        (MVN); Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL), C2Scene_CopyPartyPalette.
C2Scene_LoadPalettes:
    LDX.w #!C2Scene_PaletteStage&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_PaletteStage)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrPalettes
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .party
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_PalettePacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_PalettePacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.party:
    REP #$20
    LDA.l !C2SceneRom_PalettePacks+(!C2Scene_PartyPalPack*!C2Scene_PackEntrySize)
    STA.w !Menu_DecompSrc
    LDA.w #!C2Scene_PartyPalSrc&$FFFF
    STA.w !Menu_DecompDest
    SEP #$20
    LDA.l !C2SceneRom_PalettePacks+(!C2Scene_PartyPalPack*!C2Scene_PackEntrySize)+2
    STA.w !Menu_DecompSrcBank
    LDA.b #bank(!C2Scene_PartyPalSrc)
    STA.w !Menu_DecompDestBank
    JSL Decomp_ToWramVec
    REP #$20
    LDA.l !Party_Members
    LDY.w #!C2Scene_PartyPalDest&$FFFF
    JSR C2Scene_CopyPartyPalette
    LDA.l !Party_Members+1
    LDY.w #(!C2Scene_PartyPalDest&$FFFF)+!C2Scene_PartyPalStride
    JSR C2Scene_CopyPartyPalette
    LDA.l !Party_Members+2
    LDY.w #(!C2Scene_PartyPalDest&$FFFF)+(2*!C2Scene_PartyPalStride)
    ; falls into C2Scene_CopyPartyPalette

; $C2:28ED — C2Scene_CopyPartyPalette (21 bytes, $28ED–$2901)
; Copies C2Scene_PartyPalSize bytes of character A's palette
; (C2Scene_PartyPalSrc + 32 * A) to Y in bank $7F.
; Quirk, kept: an empty slot ($80, Menu_PartyEmpty) is not skipped; it
; copies from C2Scene_PartyPalSrc + $1000, in C2Scene_DecompBuf.
; Callers (2 JSR sites): C2Scene_LoadPalettes ($C2:28D9, $C2:28E3).
; Callers note (2 JSR sites): C2Scene_LoadPalettes ($C2:28D9, $C2:28E3; it
;   also falls in for the third member).
; Entry: M=0, X=0, DP any, DB any (saved around the MVN); A low byte = the
;        character id, Y = the destination address (bank $7F)
; Exit:  M=0, X=0, DB unchanged; A = $FFFF, X and Y past the copied bytes
; No calls.
C2Scene_CopyPartyPalette:
    PHB
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A                       ; * C2Scene_PartyPalStride (C = 0)
    ADC.w #!C2Scene_PartyPalSrc&$FFFF
    TAX
    LDA.w #!C2Scene_PartyPalSize-1
    MVN !Bank7F,!Bank7F         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTS

; $C2:2902 — C2Scene_LoadUnkB800 (46 bytes, $2902–$292F)
; Unpacks header byte C2Scene_HdrUnkB800's C2SceneRom_BgPacks entry into
; C2Scene_UnkB800 ($7E:B800); what it holds is not traced.
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C74) and C2Scene_ReloadScene ($C2:2CAD).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadUnkB800:
    LDX.w #!C2Scene_UnkB800&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_UnkB800)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrUnkB800
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_BgPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_BgPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:2930 — C2Scene_LoadUnkC000 (46 bytes, $2930–$295D)
; Unpacks header byte C2Scene_HdrUnkC000's C2SceneRom_PalettePacks entry
; into C2Scene_UnkC000 ($7E:C000); what it holds is not traced (probably
; more palettes, from the table it uses).
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C77) and C2Scene_ReloadScene ($C2:2CB0).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadUnkC000:
    LDX.w #!C2Scene_UnkC000&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_UnkC000)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrUnkC000
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_PalettePacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_PalettePacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:295E — C2Scene_LoadMetatiles (46 bytes, $295E–$298B)
; Unpacks header byte C2Scene_HdrMetatiles's C2SceneRom_MetatilePacks
; entry into C2Scene_Metatiles ($7E:3000), the metatile set of layer 1
; (and probably of layer 2 at $7E:3800; see C2Scene_LayerMetatiles).
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C62) and C2Scene_ReloadScene ($C2:2CA7).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadMetatiles:
    LDX.w #!C2Scene_Metatiles&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_Metatiles)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrMetatiles
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_MetatilePacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_MetatilePacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:298C — C2Scene_LoadBgMaps (46 bytes, $298C–$29B9)
; Unpacks header byte C2Scene_HdrMaps's C2SceneRom_MapPacks entry into
; C2Scene_BgMaps ($7E:4000), layer 1's metatile map (and probably layer
; 2's at $7E:5800; see C2Scene_LayerMaps).
; Callers (1 JSR site): C2Scene_LoadScene ($C2:2C65).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadBgMaps:
    LDX.w #!C2Scene_BgMaps&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_BgMaps)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrMaps
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_MapPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_MapPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:29BA — C2Scene_LoadUnk7000 (46 bytes, $29BA–$29E7)
; Unpacks header byte C2Scene_HdrUnk7000's C2SceneRom_Unk7000Packs entry
; into C2Scene_Unk7000 ($7E:7000), which is where C2Scene_LayerMaps puts
; layer 3's map; what it holds is not traced.
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C68) and C2Scene_ReloadScene ($C2:2CAA).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadUnk7000:
    LDX.w #!C2Scene_Unk7000&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_Unk7000)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrUnk7000
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_Unk7000Packs,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_Unk7000Packs+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:29E8 — C2Scene_LoadUnk7200 (46 bytes, $29E8–$2A15)
; Unpacks header byte C2Scene_HdrUnk7200's C2SceneRom_Unk7200Packs entry
; into C2Scene_Unk7200 ($7E:7200); what it holds is not traced.
; Callers (1 JSR site): C2Scene_LoadScene ($C2:2C6B).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadUnk7200:
    LDX.w #!C2Scene_Unk7200&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_Unk7200)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrUnk7200
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_Unk7200Packs,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_Unk7200Packs+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:2A16 — C2Scene_LoadScript (46 bytes, $2A16–$2A43)
; Unpacks header byte C2Scene_HdrScript's C2SceneRom_ScriptPacks entry
; into C2Scene_ScriptBuf ($7F:0400), over the list data
; C2Scene_LoadLists has already split up. Inferred to be the scene's
; script: C2Scene_LoadScene starts a C2Scene_TaskRunScript task at that
; address right after.
; Callers (1 JSR site): C2Scene_LoadScene ($C2:2C71).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadScript:
    LDX.w #!C2Scene_ScriptBuf&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_ScriptBuf)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrScript
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .done
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_ScriptPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_ScriptPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.done:
    RTS

; $C2:2A44 — C2Scene_LoadLists (285 bytes, $2A44–$2B60)
; Unpacks header byte C2Scene_HdrLists's C2SceneRom_ListPacks entry into
; C2Scene_ListPack ($7F:0400), then splits it into four lists through
; WMADD/WMDATA (bank $7E): a count byte, then that many 7-byte entries
; to C2Scene_ListA; a count, 3-byte entries to C2Scene_ListB; a count,
; 3-byte entries to C2Scene_ListC; a count, 2-byte entries to
; C2Scene_ListD. The first three counts are kept (C2Scene_ListACount,
; ListBCount, ListCCount). What the entries mean is not traced. With bit
; 7 set in the header byte nothing is unpacked, but the split still runs
; on whatever is at $7F:0400.
; Quirk, kept: a count of 0 is not special-cased: the DEY/BNE loops then
; copy 65536 entries.
; Callers (1 JSR site): C2Scene_LoadScene ($C2:2C6E).
; Entry: M=1, X=0, DP=$0000, DB=$00 (absolute stores to Menu_Decomp*, the
;        counts and WMADD/WMDATA); C2Scene_HeaderPtr set
; Exit:  M=1, X=0; A = the last byte copied, X = the offset past the
;        data, Y = 0; Menu_Decomp* and WMADD changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadLists:
    LDX.w #!C2Scene_ListPack&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_ListPack)
    STA.w !Menu_DecompDestBank
    LDY.w #!C2Scene_HdrLists
    TDC
    LDA.b [!C2Scene_HeaderPtr],Y
    BMI .split
    ASL A
    ADC.b [!C2Scene_HeaderPtr],Y
    TAX
    REP #$20
    LDA.l !C2SceneRom_ListPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_ListPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
.split:
    LDX.w #!C2Scene_ListA&$FFFF
    STX.w WMADDL
    LDA.b #bank(!C2Scene_ListA) ; bit 0 clear: bank $7E
    STA.w WMADDH
    REP #$20
    LDA.l !C2Scene_ListPack
    AND.w #!Eng_LowByteMask
    TAY
    SEP #$20
    STA.w !C2Scene_ListACount
    LDX.w #1
.list_a:
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    DEY
    BNE .list_a
    LDY.w #!C2Scene_ListB&$FFFF
    STY.w WMADDL
    LDA.b #bank(!C2Scene_ListB)
    STA.w WMADDH
    REP #$20
    LDA.l !C2Scene_ListPack,X
    INX
    AND.w #!Eng_LowByteMask
    TAY
    SEP #$20
    STA.w !C2Scene_ListBCount
.list_b:
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    DEY
    BNE .list_b
    LDY.w #!C2Scene_ListC&$FFFF
    STY.w WMADDL
    LDA.b #bank(!C2Scene_ListC)
    STA.w WMADDH
    REP #$20
    LDA.l !C2Scene_ListPack,X
    INX
    AND.w #!Eng_LowByteMask
    TAY
    SEP #$20
    STA.w !C2Scene_ListCCount
.list_c:
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    DEY
    BNE .list_c
    LDY.w #!C2Scene_ListD&$FFFF
    STY.w WMADDL
    LDA.b #bank(!C2Scene_ListD)
    STA.w WMADDH
    REP #$20
    LDA.l !C2Scene_ListPack,X
    INX
    AND.w #!Eng_LowByteMask
    TAY
    SEP #$20
.list_d:
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    LDA.l !C2Scene_ListPack,X
    STA.w WMDATA
    INX
    DEY
    BNE .list_d
    RTS

; $C2:2B61 — C2Scene_LoadPartyGfx (91 bytes, $2B61–$2BBB)
; Unpacks the party graphics (C2SceneRom_ObjPacks entry
; C2Scene_PartyObjPack, the same for every scene) into C2Scene_DecompBuf,
; then builds C2Scene_PartyGfx from it: for each party member
; (Party_Members, position n), C2Scene_CopyPartyGfx copies the
; character's C2Scene_PartyGfxSize bytes to C2Scene_PartyGfx + $400 * n
; and C2Scene_CopyPartyGfxB its two $40-byte blocks to C2Scene_PartyGfxB
; + $40 * n (and $200 further). C2Scene_LoadVram DMAs the result to VRAM
; $1000, in the sprite tiles; probably the party's sprites (inferred from
; the per-member copies only).
; Callers (1 JSR site): C2Scene_LoadVram ($C2:2CD0).
; Entry: M=1, X=0, DP=$0000, DB=$00
; Exit:  M=0, X=0; DB unchanged; A = $FFFF, X and Y past the last copy;
;        C2Tmp_08-$0B changed; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL), C2Scene_CopyPartyGfx,
;   C2Scene_CopyPartyGfxB.
C2Scene_LoadPartyGfx:
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDA.l !C2SceneRom_ObjPacks+(!C2Scene_PartyObjPack*!C2Scene_PackEntrySize)+2
    STA.w !Menu_DecompSrcBank
    REP #$20
    LDA.l !C2SceneRom_ObjPacks+(!C2Scene_PartyObjPack*!C2Scene_PackEntrySize)
    STA.w !Menu_DecompSrc
    JSL Decomp_ToWramVec
    LDA.l !Party_Members
    LDY.w #!C2Scene_PartyGfx&$FFFF
    JSR C2Scene_CopyPartyGfx
    LDA.l !Party_Members
    LDY.w #!C2Scene_PartyGfxB&$FFFF
    JSR C2Scene_CopyPartyGfxB
    LDA.l !Party_Members+1
    LDY.w #(!C2Scene_PartyGfx&$FFFF)+!C2Scene_PartyGfxSize
    JSR C2Scene_CopyPartyGfx
    LDA.l !Party_Members+1
    LDY.w #(!C2Scene_PartyGfxB&$FFFF)+!C2Scene_PartyGfxBSize
    JSR C2Scene_CopyPartyGfxB
    LDA.l !Party_Members+2
    LDY.w #(!C2Scene_PartyGfx&$FFFF)+(2*!C2Scene_PartyGfxSize)
    JSR C2Scene_CopyPartyGfx
    LDA.l !Party_Members+2
    LDY.w #(!C2Scene_PartyGfxB&$FFFF)+(2*!C2Scene_PartyGfxBSize)
    JMP C2Scene_CopyPartyGfxB

; $C2:2BBC — C2Scene_CopyPartyGfx (19 bytes, $2BBC–$2BCE)
; Copies C2Scene_PartyGfxSize bytes of character A's graphics
; (C2Scene_DecompBuf + $400 * A) to Y in bank $7F.
; Quirk, kept: an empty slot ($80) is not skipped; its offset wraps
; ($80 * $400 = $20000) and the character-0 graphics are copied.
; Callers (3 JSR sites): C2Scene_LoadPartyGfx ($C2:2B87, $C2:2B9B, $C2:2BAF).
; Entry: M=0, X=0, DP any, DB any (saved around the MVN); A low byte = the
;        character id, Y = the destination (bank $7F)
; Exit:  M=0, X=0, DB unchanged; A = $FFFF, X and Y past the copy
; No calls.
C2Scene_CopyPartyGfx:
    PHB
    AND.w #!Eng_LowByteMask
    XBA
    ASL A
    ASL A                       ; * C2Scene_PartyGfxSize ($400; C = 0 for ids below $40)
    ADC.w #!C2Scene_DecompBuf&$FFFF
    TAX
    LDA.w #!C2Scene_PartyGfxSize-1
    MVN !Bank7F,!Bank7F         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTS

; $C2:2BCF — C2Scene_CopyPartyGfxB (44 bytes, $2BCF–$2BFA)
; Copies character A's two C2Scene_PartyGfxBSize-byte blocks
; (C2Scene_PartyGfxSrcB + $40 * A, and C2Scene_PartyGfxBGap bytes
; further) to Y and Y + C2Scene_PartyGfxBGap in bank $7F.
; Callers (3 sites: 2 JSR, 1 JMP): C2Scene_LoadPartyGfx (JSR $C2:2B91, JSR $C2:2BA5, JMP $C2:2BB9).
; Entry: M=0, X=0, DP=$0000 (scratch), DB any (saved around the MVNs);
;        A low byte = the character id, Y = the destination (bank $7F)
; Exit:  M=0, X=0, DB unchanged; A = $FFFF, X and Y past the second
;        block; C2Tmp_08 = the first source, C2Tmp_0A = the first
;        destination
; No calls.
!C2Scene_PartyBSrc = !C2Tmp_08          ; 16-bit first source block
!C2Scene_PartyBDest = !C2Tmp_0A         ; 16-bit first destination block
C2Scene_CopyPartyGfxB:
    PHB
    AND.w #!Eng_LowByteMask
    XBA
    LSR A
    LSR A                       ; * C2Scene_PartyGfxBSize ($40)
    CLC
    ADC.w #!C2Scene_PartyGfxSrcB&$FFFF
    STA.b !C2Scene_PartyBSrc
    STY.b !C2Scene_PartyBDest
    TAX
    LDA.w #!C2Scene_PartyGfxBSize-1
    MVN !Bank7F,!Bank7F         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    CLC
    LDA.b !C2Scene_PartyBSrc
    ADC.w #!C2Scene_PartyGfxBGap
    TAX
    CLC
    LDA.b !C2Scene_PartyBDest
    ADC.w #!C2Scene_PartyGfxBGap
    TAY
    LDA.w #!C2Scene_PartyGfxBSize-1
    MVN !Bank7F,!Bank7F         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTS

; $C2:2BFB — C2Scene_ClearHdmaArea (34 bytes, $2BFB–$2C1C)
; Zeroes C2Scene_HdmaArea ($7E:8621-$8E20, 2048 bytes) through
; WMADD/WMDATA, with DP = $2100 for the register stores. The area holds
; C2Scene_HdmaValues and C2Scene_HdmaTable.
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C7A) and C2Scene_ReloadScene ($C2:2C96).
; Entry: M=1, X=0, DP any (saved; $2100 here), DB any (all register
;        stores direct page)
; Exit:  M=1, X=0; A = 0 (B = $21), X = 0; Y, DP and DB unchanged; WMADD
;        changed
; No calls.
C2Scene_ClearHdmaArea:
    PHD
    LDA.b #!DP_PPU>>8
    XBA
    LDA.b #0
    TCD                         ; DP = $2100
    LDX.w #!C2Scene_HdmaArea&$FFFF
    STX.b WMADDL-!DP_PPU
    LDA.b #bank(!C2Scene_HdmaArea)
    STA.b WMADDH-!DP_PPU
    LDX.w #!C2Scene_HdmaAreaPasses
    LDA.b #0
.clear:
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    DEX
    BNE .clear
    PLD
    RTS

; $C2:2C1D — C2Scene_LoadScene (118 bytes, $2C1D–$2C92)
; The last setup step of C2Scene_Main: loads the scene and starts its
; script. Zeroes C2Scene_Mode, C2Scene_Unk027D, the fixed color
; (C2Scene_FixedBlue/Red/Green), C2Scene_Unk0280 (3 bytes),
; C2Scene_Unk1B58/1B59, C2Scene_Unk1BF7 and C2Scene_Unk02B1 (3 bytes);
; sets the three C2Scene_Unk1B32 words to $FFFF; copies Menu_Config1E to
; C2Scene_Unk02AE and clears bit 2 of C2Scene_Unk0294. Then: the header
; pointer (C2Scene_GetHeaderPtr), the VRAM and palette loads
; (C2Scene_LoadVram), the WRAM loads (metatiles, maps, the Unk7000/7200
; packs, the lists, the script, the UnkB800/C000 packs), the HDMA area
; cleared, BG layers 1 and 2 drawn (C2Scene_DrawBgLayer), and a
; C2Scene_TaskRunScript task spawned on C2Scene_ScriptBuf
; (C2Scene_TaskSpawnScript, which returns for it).
; Callers (1 JSR site): C2Scene_Main ($C2:23C3).
; Entry: M=1, X=0, DP=$0000, DB=$00 (as C2Scene_Main runs); forced blank
;        (VRAM and CGRAM DMA)
; Exit:  as C2Scene_TaskSpawnScript: M=1, X=0; X = the new task record, A
;        = bank(C2Scene_ScriptBuf); Y clobbered; C2Tmp_00-$1B,
;        Menu_Decomp*, DMA channel 7 and WMADD changed; DP and DB
;        unchanged
; Calls: C2Scene_GetHeaderPtr, C2Scene_LoadVram, C2Scene_LoadMetatiles,
;   C2Scene_LoadBgMaps, C2Scene_LoadUnk7000, C2Scene_LoadUnk7200,
;   C2Scene_LoadLists, C2Scene_LoadScript, C2Scene_LoadUnkB800,
;   C2Scene_LoadUnkC000, C2Scene_ClearHdmaArea, C2Scene_DrawBgLayer,
;   C2Scene_TaskSpawnScript (JMP).
C2Scene_LoadScene:
    STZ.w !C2Scene_Mode
    STZ.w !C2Scene_Unk027D
    STZ.b !C2Scene_FixedBlue
    STZ.b !C2Scene_FixedRed
    STZ.b !C2Scene_FixedGreen
    STZ.w !C2Scene_Unk0280
    STZ.w !C2Scene_Unk0280+1
    STZ.w !C2Scene_Unk0280+2
    STZ.w !C2Scene_Unk1B58
    STZ.w !C2Scene_Unk1B59
    STZ.w !C2Scene_Unk1BF7
    STZ.w !C2Scene_Unk02B1
    STZ.w !C2Scene_Unk02B1+1
    STZ.w !C2Scene_Unk02B1+2
    LDX.w #!C2Scene_Unk1B32Init
    STX.w !C2Scene_Unk1B32
    STX.w !C2Scene_Unk1B32+2
    STX.w !C2Scene_Unk1B32+4
    LDA.l !Menu_Config1E
    STA.w !C2Scene_Unk02AE
    LDA.b #!C2Scene_Unk0294Bit2
    TRB.w !C2Scene_Unk0294
    JSR C2Scene_GetHeaderPtr
    JSR C2Scene_LoadVram
    JSR C2Scene_LoadMetatiles
    JSR C2Scene_LoadBgMaps
    JSR C2Scene_LoadUnk7000
    JSR C2Scene_LoadUnk7200
    JSR C2Scene_LoadLists
    JSR C2Scene_LoadScript
    JSR C2Scene_LoadUnkB800
    JSR C2Scene_LoadUnkC000
    JSR C2Scene_ClearHdmaArea
    LDA.b #1
    STA.b !C2Scene_DrawLayer
    JSR C2Scene_DrawBgLayer
    LDA.b #2
    STA.b !C2Scene_DrawLayer
    JSR C2Scene_DrawBgLayer
    LDX.w #!C2Scene_ScriptBuf&$FFFF
    LDA.b #bank(!C2Scene_ScriptBuf)
    JMP C2Scene_TaskSpawnScript

; $C2:2C93 — C2Scene_ReloadScene (46 bytes, $2C93–$2CC0)
; Loads the scene's graphics again (scene modes 5 and 8 call it after
; C2Scene_RestoreState and C2Scene_VramQInit; mode 8 skips it when
; $7F:01F4 AND $0A or $7F:01F5 AND $02 is non-zero ($C2:265E); mode 6
; calls it too): C2Scene_Unk5775, the HDMA area cleared and
; C2Scene_HdmaValueA916 = C2Scene_HdmaValueA916Init, then the VRAM and
; palette loads (C2Scene_LoadVram), the metatiles, the Unk7000, UnkB800
; and UnkC000 packs, and BG layers 1 and 2 redrawn. The maps and lists
; are not reloaded: C2Scene_SaveState keeps them, and the header pointer
; with the direct page.
; Callers (3 JSR sites): C2Scene_Mode5 ($C2:2563), C2Scene_Mode6 ($C2:25F3) and C2Scene_Mode8
;   ($C2:266E).
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_HeaderPtr set; forced blank
; Exit:  as C2Scene_DrawBgLayer: M=1, X=0; A, X, Y clobbered;
;        C2Tmp_00-$1B, Menu_Decomp*, DMA channel 7 and WMADD changed
; Calls: C2Scene_Unk5775, C2Scene_ClearHdmaArea, C2Scene_LoadVram,
;   C2Scene_LoadMetatiles, C2Scene_LoadUnk7000, C2Scene_LoadUnkB800,
;   C2Scene_LoadUnkC000, C2Scene_DrawBgLayer (the second by JMP).
C2Scene_ReloadScene:
    JSR C2Scene_Unk5775
    JSR C2Scene_ClearHdmaArea
    REP #$20
    LDA.w #!C2Scene_HdmaValueA916Init
    STA.l !C2Scene_HdmaValueA916
    SEP #$20
    JSR C2Scene_LoadVram
    JSR C2Scene_LoadMetatiles
    JSR C2Scene_LoadUnk7000
    JSR C2Scene_LoadUnkB800
    JSR C2Scene_LoadUnkC000
    LDA.b #1
    STA.b !C2Scene_DrawLayer
    JSR C2Scene_DrawBgLayer
    LDA.b #2
    STA.b !C2Scene_DrawLayer
    JMP C2Scene_DrawBgLayer

; $C2:2CC1 — C2Scene_LoadVram (175 bytes, $2CC1–$2D6F)
; Fills VRAM and CGRAM for the scene, each pack staged at
; C2Scene_DecompBuf and DMAed with C2Scene_DmaToVram:
; - the four sprite packs (C2Scene_LoadObjGfx) to VRAM $0000 ($4000 B);
; - the party graphics (C2Scene_LoadPartyGfx) to VRAM $1000 ($1000 B);
; - the seven BG packs (C2Scene_LoadBgGfx) to VRAM $2000 ($7000 B);
; - the BG3 tiles (C2Scene_LoadBg3Gfx) to VRAM $7000 and the BG3 map
;   (C2Scene_LoadBg3Map) to VRAM $7800 ($1000 B each);
; - the palettes (C2Scene_LoadPalettes) into C2Scene_PaletteStage, whose
;   first four sprite colors become black and three grays
;   (C2Scene_ObjPal0); the stage is copied to C2Scene_PaletteBuf and
;   C2SceneRom_LastPalRow over its colors $F0-$FF, and the stage itself
;   (without that row) DMAed to CGRAM on channel 7;
; then C2Scene_LoadLocExtraGfx and C2Scene_LoadUnkC800 (JMP).
; Quirk, kept: both MVN counts are the byte count, not the count - 1, so
; each copy moves one byte more: $00:0B20 (C2Scene_Unk0B20's first byte)
; is written twice, last with byte 33 of C2SceneRom_LastPalRow.
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C5F) and C2Scene_ReloadScene ($C2:2CA4).
; Entry: M=1, X=0, DP=$0000, DB=$00 (absolute register stores);
;        C2Scene_HeaderPtr set; forced blank
; Exit:  as C2Scene_LoadUnkC800: M=1, X=0; A, X, Y clobbered; DB
;        unchanged; C2Tmp_08-$12, Menu_Decomp* and DMA channel 7 changed
; Calls: C2Scene_LoadObjGfx, C2Scene_DmaToVram, C2Scene_LoadPartyGfx,
;   C2Scene_LoadBgGfx, C2Scene_LoadBg3Gfx, C2Scene_LoadBg3Map,
;   C2Scene_LoadPalettes, C2Scene_LoadLocExtraGfx, C2Scene_LoadUnkC800
;   (JMP).
C2Scene_LoadVram:
    JSR C2Scene_LoadObjGfx      ; returns M=0
    LDX.w #!C2Scene_DecompBuf&$FFFF
    LDY.w #!C2Scene_VramObj
    LDA.w #!C2Scene_ObjGfxBytes
    JSR C2Scene_DmaToVram       ; returns M=1
    JSR C2Scene_LoadPartyGfx    ; returns M=0
    LDX.w #!C2Scene_PartyGfx&$FFFF
    LDY.w #!C2Scene_VramPartyGfx
    LDA.w #!C2Scene_PartyGfxBytes
    JSR C2Scene_DmaToVram
    JSR C2Scene_LoadBgGfx       ; returns M=0
    LDX.w #!C2Scene_DecompBuf&$FFFF
    LDY.w #!C2Scene_VramBgGfx
    LDA.w #!C2Scene_BgGfxBytes
    JSR C2Scene_DmaToVram
    JSR C2Scene_LoadBg3Gfx
    REP #$20
    LDX.w #!C2Scene_DecompBuf&$FFFF
    LDY.w #!C2Scene_VramBg3Gfx
    LDA.w #!C2Scene_PackBytes
    JSR C2Scene_DmaToVram
    JSR C2Scene_LoadBg3Map
    REP #$20
    LDX.w #!C2Scene_DecompBuf&$FFFF
    LDY.w #!C2Scene_VramBg3Map
    LDA.w #!C2Scene_PackBytes
    JSR C2Scene_DmaToVram
    JSR C2Scene_LoadPalettes    ; returns M=0
    TDC                         ; A = DP = 0: black
    STA.l !C2Scene_ObjPal0
    LDA.w #!C2Scene_Gray1
    STA.l !C2Scene_ObjPal0+2
    LDA.w #!C2Scene_Gray2
    STA.l !C2Scene_ObjPal0+4
    LDA.w #!C2Scene_Gray3
    STA.l !C2Scene_ObjPal0+6
    PHB
    LDX.w #!C2Scene_PaletteStage&$FFFF
    LDY.w #!C2Scene_PaletteBuf
    LDA.w #!C2Scene_PaletteBytes ; MVN moves this + 1
    MVN !Bank00,bank(!C2Scene_PaletteStage) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2SceneRom_LastPalRow&$FFFF
    LDY.w #!C2Scene_LastPalRowDest
    LDA.w #!C2Scene_PalRowBytes ; MVN moves this + 1
    MVN !Bank00,bank(!C2SceneRom_LastPalRow) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    LDA.b #0
    STA.w CGADD
    LDX.w #!BBAD_CGDATA<<8      ; DMAP7 = 0 (one register), BBAD7 = CGDATA
    STX.w DMAP7
    LDX.w #!C2Scene_PaletteStage&$FFFF
    STX.w A1T7L
    LDA.b #bank(!C2Scene_PaletteStage)
    STA.w A1B7
    LDX.w #!C2Scene_PaletteBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    JSR C2Scene_LoadLocExtraGfx
    JMP C2Scene_LoadUnkC800

; $C2:2D70 — C2Scene_DmaToVram (33 bytes, $2D70–$2D90)
; DMAs A bytes from X in bank $7F to VRAM word address Y on channel 7
; (word writes to VMDATAL/H, VMAIN stepping after the high byte).
; Callers (9 JSR sites): C2Scene_LoadVram ($C2:2CCD, $C2:2CDC, $C2:2CEB, $C2:2CFC, $C2:2D0D) and
;   C2Scene_LoadLocExtraGfx ($C2:2DBF, $C2:2DDB, $C2:2E01, $C2:2E1D).
; Entry: M=0 (16-bit count store), X=0, DP any, DB=$00 (absolute register
;        stores); X = the source, Y = the VRAM address, A = the count;
;        forced blank or vblank
; Exit:  M=1, X=0; A = MDMAEN_Ch7 (B = the count's high byte), X =
;        $1801 (the DMAP7/BBAD7 word); Y, DP and DB unchanged
; No calls.
C2Scene_DmaToVram:
    STX.w A1T7L
    STY.w VMADDL
    STA.w DAS7L
    SEP #$20
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #(!BBAD_VMDATAL<<8)|!DMAP_TwoRegs
    STX.w DMAP7
    LDA.b #!Bank7F
    STA.w A1B7
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

; $C2:2D91 — C2Scene_LoadLocExtraGfx (146 bytes, $2D91–$2E22)
; Once Eng_Unk7F0000 has reached C2Scene_ExtraGfxFlagMin, four scenes get
; extra graphics: C2Scene_LoadExtraObjPack, then C2Scene_ExtraObjBytes of
; it DMAed to VRAM $0C00 (Loc_Id $01F0-$01F2) or $0000 (Loc_Id $01F6),
; and for $01F0-$01F2 a palette (C2Scene_LoadExtraPalette) into
; C2Scene_PaletteBuf: colors $90-$9F (C2Scene_ExtraPalA) for $01F0 and
; $01F2; for $01F1 colors $B0-$BF (C2Scene_ExtraPalB), or $A0-$AF
; (C2Scene_ExtraPalC) when bit 7 of C2Scene_FlagTailByte1 is set; then
; C2Scene_LoadUnkC600 (JMP). Other scenes, or a lower flag byte: nothing.
; (Eng_Unk7F0000 is probably a story-progress byte; unverified.)
; Callers (1 JSR site): C2Scene_LoadVram ($C2:2D6A).
; Entry: M=1, X=0, DP any, DB=$00 (absolute Loc_Id and register stores);
;        forced blank
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* and DMA channel 7
;        changed when anything is loaded
; Calls: C2Scene_LoadExtraObjPack, C2Scene_DmaToVram,
;   C2Scene_LoadExtraPalette, C2Scene_LoadUnkC600 (JMP).
C2Scene_LoadLocExtraGfx:
    LDA.l !Eng_Unk7F0000
    CMP.b #!C2Scene_ExtraGfxFlagMin
    BCC .done
    LDX.w !DP_Field+!Loc_Id
    CPX.w #!Loc_FirstBankC2
    BEQ .loc_1F0
    CPX.w #!Loc_FirstBankC2+1
    BEQ .loc_1F1
    CPX.w #!Loc_FirstBankC2+2
    BEQ .loc_1F2
    CPX.w #!Loc_FirstBankC2+6
    BEQ .loc_1F6
.done:
    RTS
.loc_1F0:
    JSR C2Scene_LoadExtraObjPack
    REP #$20
    LDX.w #!C2Scene_DecompBuf&$FFFF
    LDY.w #!C2Scene_VramExtraObj
    LDA.w #!C2Scene_ExtraObjBytes
    JSR C2Scene_DmaToVram
    LDA.b #!Bank00
    LDX.w #!C2Scene_ExtraPalA
    JSR C2Scene_LoadExtraPalette
    JMP C2Scene_LoadUnkC600
.loc_1F1:
    JSR C2Scene_LoadExtraObjPack
    REP #$20
    LDX.w #!C2Scene_DecompBuf&$FFFF
    LDY.w #!C2Scene_VramExtraObj
    LDA.w #!C2Scene_ExtraObjBytes
    JSR C2Scene_DmaToVram
    LDX.w #!C2Scene_ExtraPalB
    LDA.w !C2Scene_FlagTailByte1
    BIT.b #!C2Scene_FlagTailBit7
    BEQ .pal_1F1
    LDX.w #!C2Scene_ExtraPalC
.pal_1F1:
    LDA.b #!Bank00
    JSR C2Scene_LoadExtraPalette
    JMP C2Scene_LoadUnkC600
.loc_1F2:
    JSR C2Scene_LoadExtraObjPack
    REP #$20
    LDX.w #!C2Scene_DecompBuf&$FFFF
    LDY.w #!C2Scene_VramExtraObj
    LDA.w #!C2Scene_ExtraObjBytes
    JSR C2Scene_DmaToVram
    LDA.b #!Bank00
    LDX.w #!C2Scene_ExtraPalA
    JSR C2Scene_LoadExtraPalette
    JMP C2Scene_LoadUnkC600
.loc_1F6:
    JSR C2Scene_LoadExtraObjPack
    REP #$20
    LDX.w #!C2Scene_DecompBuf&$FFFF
    LDY.w #!C2Scene_VramObj
    LDA.w #!C2Scene_ExtraObjBytes
    JSR C2Scene_DmaToVram
    JMP C2Scene_LoadUnkC600

; $C2:2E23 — C2Scene_SaveState (79 bytes, $2E23–$2E71)
; Copies the scene's state to bank $7F with MVN: dp $00-$EF to
; C2Scene_SaveDp; $0700-$1DFF (with C2Scene_PaletteBuf and the task
; records) to C2Scene_SaveLowRam; the sprite nodes, link table and list
; heads ($7E:B000-$B507) to C2Scene_SaveSprNodes; the two BG maps
; ($7E:4000-$6FFF) to C2Scene_SaveBgMaps; $7E:7200-$7DFF to
; C2Scene_SaveUnk7200; the four lists ($7E:7E00-$85FF) to
; C2Scene_SaveLists. C2Scene_RestoreState copies them back; what the
; state is not kept for (metatiles, the $7E:7000, $7E:B800, $7E:C000 and
; $7E:C800 packs, the $7E:C600 pack of the extra-graphics scenes,
; graphics) is what C2Scene_ReloadScene loads again. Inferred
; from the callers: scene modes 5 and 8 save, do something
; else and restore; mode 5 then reloads, mode 8 only when the flag test
; at $C2:265E passes.
; Callers (2 JSR sites): C2Scene_Mode5 ($C2:2542) and C2Scene_Mode8 ($C2:2652).
; Entry: M any (REP #$20 here), X=0, DP any, DB any (saved around the
;        MVNs)
; Exit:  M=1, X=0; A = $FFFF, X = $8600, Y = C2Scene_SaveLists + $800
;        (16-bit); DP and DB unchanged
; No calls.
C2Scene_SaveState:
    REP #$20
    PHB
    LDX.w #!C2Scene_DpClearStart
    LDY.w #!C2Scene_SaveDp&$FFFF
    LDA.w #!C2Scene_SaveDpBytes-1
    MVN bank(!C2Scene_SaveDp),!Bank00 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_SaveLowStart
    LDY.w #!C2Scene_SaveLowRam&$FFFF
    LDA.w #!C2Scene_SaveLowBytes-1
    MVN bank(!C2Scene_SaveLowRam),!Bank00 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_SprNodes&$FFFF
    LDY.w #!C2Scene_SaveSprNodes&$FFFF
    LDA.w #!C2Scene_SaveSprBytes-1
    MVN bank(!C2Scene_SaveSprNodes),bank(!C2Scene_SprNodes) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_BgMaps&$FFFF
    LDY.w #!C2Scene_SaveBgMaps&$FFFF
    LDA.w #!C2Scene_SaveMapBytes-1
    MVN bank(!C2Scene_SaveBgMaps),bank(!C2Scene_BgMaps) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_Unk7200&$FFFF
    LDY.w #!C2Scene_SaveUnk7200&$FFFF
    LDA.w #!C2Scene_SaveUnk7200Bytes-1
    MVN bank(!C2Scene_SaveUnk7200),bank(!C2Scene_Unk7200) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_ListA&$FFFF
    LDY.w #!C2Scene_SaveLists&$FFFF
    LDA.w #!C2Scene_SaveListBytes-1
    MVN bank(!C2Scene_SaveLists),bank(!C2Scene_ListA) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    RTS

; $C2:2E72 — C2Scene_RestoreState (79 bytes, $2E72–$2EC0)
; The reverse of C2Scene_SaveState: copies the six saved blocks from bank
; $7F back where they came from (the direct page $00-$EF included).
; Callers (2 JSR sites): C2Scene_Mode5 ($C2:255D) and C2Scene_Mode8 ($C2:2658).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (the copy rewrites dp
;        $00-$EF, so it must be the scene's), DB any (saved around the
;        MVNs)
; Exit:  M=1, X=0; A = $FFFF, X = C2Scene_SaveLists + $800, Y = $8600
;        (16-bit); DP and DB unchanged; dp $00-$EF as saved
; No calls.
C2Scene_RestoreState:
    REP #$20
    PHB
    LDX.w #!C2Scene_SaveDp&$FFFF
    LDY.w #!C2Scene_DpClearStart
    LDA.w #!C2Scene_SaveDpBytes-1
    MVN !Bank00,bank(!C2Scene_SaveDp) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_SaveLowRam&$FFFF
    LDY.w #!C2Scene_SaveLowStart
    LDA.w #!C2Scene_SaveLowBytes-1
    MVN !Bank00,bank(!C2Scene_SaveLowRam) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_SaveSprNodes&$FFFF
    LDY.w #!C2Scene_SprNodes&$FFFF
    LDA.w #!C2Scene_SaveSprBytes-1
    MVN bank(!C2Scene_SprNodes),bank(!C2Scene_SaveSprNodes) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_SaveBgMaps&$FFFF
    LDY.w #!C2Scene_BgMaps&$FFFF
    LDA.w #!C2Scene_SaveMapBytes-1
    MVN bank(!C2Scene_BgMaps),bank(!C2Scene_SaveBgMaps) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_SaveUnk7200&$FFFF
    LDY.w #!C2Scene_Unk7200&$FFFF
    LDA.w #!C2Scene_SaveUnk7200Bytes-1
    MVN bank(!C2Scene_Unk7200),bank(!C2Scene_SaveUnk7200) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_SaveLists&$FFFF
    LDY.w #!C2Scene_ListA&$FFFF
    LDA.w #!C2Scene_SaveListBytes-1
    MVN bank(!C2Scene_ListA),bank(!C2Scene_SaveLists) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    RTS

; ============================================================
; Mode scripts ($C2:2EC1–$C2:2ED8)
; ============================================================
; Short scene scripts (C2Scene_TaskRunScript, ops C2Script_OpTable) that
; the mode handlers start with C2Scene_TaskSpawnScript. Each op is its
; byte and its arguments; the effect tasks read their arguments from
; the op (C2Scene_FxTask.OpPtr).

; $C2:2EC1 — C2Scene_ScrFadeOut (3 bytes, $2EC1–$2EC3)
; Fade out at 1 frame per step (op $28, C2Scene_TaskUnk20A2), then end.
; Started by C2Scene_Mode3, C2Scene_Mode5 and C2Scene_Mode8.
C2Scene_ScrFadeOut:
    db $28,$01                  ; C2Script_SpawnUnk20A2 (fade out), 1 frame per step
    db $52                      ; C2Script_End

; $C2:2EC4 — C2Scene_ScrFadeIn (3 bytes, $2EC4–$2EC6)
; Fade in at 1 frame per step (op $29, C2Scene_TaskUnk2105), then end.
; Started by C2Scene_Mode5 and C2Scene_Mode8.
C2Scene_ScrFadeIn:
    db $29,$01                  ; C2Script_SpawnUnk2105 (fade in), 1 frame per step
    db $52                      ; C2Script_End

; $C2:2EC7 — C2Scene_ScrMosaicFadeOut (9 bytes, $2EC7–$2ECF)
; Started by C2Scene_Mode6: clears the task's fields (op $00), starts a
; mosaic grow (op $2A) on BG1-3 (arg 1 = 7) at 2 frames per step, waits
; 16 frames, fades out at 1 frame per step, ends.
C2Scene_ScrMosaicFadeOut:
    db $00                      ; C2Script_ResetTask
    db $2A,$07,$02              ; C2Script_SpawnUnk21F8 (mosaic grow): BG1-3, 2 frames per step
    db $38,$10                  ; C2Script_Wait, 16 frames
    db $28,$01                  ; C2Script_SpawnUnk20A2 (fade out), 1 frame per step
    db $52                      ; C2Script_End

; $C2:2ED0 — C2Scene_ScrMosaicFadeIn (9 bytes, $2ED0–$2ED8)
; Started by C2Scene_Mode6 on the way back: clears the task's fields,
; fades in at 1 frame per step, waits 8 frames, starts a mosaic shrink
; (op $2B) on BG1-3 at 2 frames per step, ends.
C2Scene_ScrMosaicFadeIn:
    db $00                      ; C2Script_ResetTask
    db $29,$01                  ; C2Script_SpawnUnk2105 (fade in), 1 frame per step
    db $38,$08                  ; C2Script_Wait, 8 frames
    db $2B,$07,$02              ; C2Script_SpawnUnk2194 (mosaic shrink): BG1-3, 2 frames per step
    db $52                      ; C2Script_End

; ============================================================
; Scene sound command queue ($C2:2ED9–$C2:2F0E)
; ============================================================

org $C22ED9
; $C2:2ED9 — C2Scene_QueueSoundCmd (54 bytes, $2ED9–$2F0E)
; Queues the sound command in C2Scene_SoundCmdBuf (command byte and three
; argument bytes) for the frame loop to send: copies it to the driver
; block Audio_CmdId-Audio_CmdArg2, keeps its rank C2Scene_SoundCmdPrio in
; C2Scene_SoundCmdPendPrio and sets C2Scene_SoundCmdState to 1
; (C2Scene_WaitFrames and C2Scene_MainLoop then send it with
; Audio_DriverCommand). Refused (C=1, nothing written) while a command
; is being sent (state C2Scene_SoundCmdSending, tested as negative), or
; when one is already queued with a lower pending rank than the new one;
; an equal or higher pending rank is replaced (so rank 0, which every
; matched caller passes, always replaces a queued command).
; Callers (10 JSR sites): C2Script_PlaySfx_SetArgs ($C2:18E8), C2Script_SoundCmd10 ($C2:1916),
;   C2Script_SoundCmd ($C2:193E), C2Scene_ZoneSoundAtView ($C2:2F88), C2Scene_ZoneSoundWatch
;   ($C2:2FCD, $C2:3031), C2Scene_ZoneSoundResume ($C2:306A), C2Scene_ZoneSoundQueue ($C2:3092) and
;   unmatched ($C2:4395, $C2:4A4C).
; Callers note (10 JSR sites): C2Script_PlaySfx ($C2:18E8),
;   C2Script_SoundCmd10 ($C2:1916), C2Script_SoundCmd ($C2:193E),
;   C2Scene_ZoneSoundAtView ($C2:2F88), C2Scene_ZoneSoundWatch ($C2:2FCD,
;   $C2:3031), C2Scene_ZoneSoundResume ($C2:306A), C2Scene_ZoneSoundQueue
;   ($C2:3092); unmatched: $C2:4395 and $C2:4A4C.
; Entry: M=1, X any (no index use), DP any (no direct page), DB=$00 (low
;        WRAM: the buffer, the state and the driver block)
; Exit:  M=1, X unchanged; C=0 queued, C=1 refused; A clobbered; X, Y,
;        DP and DB unchanged
; No calls.
C2Scene_QueueSoundCmd:
    LDA.w !C2Scene_SoundCmdState
    BEQ .queue
    BMI .refuse
    LDA.w !C2Scene_SoundCmdPendPrio
    CMP.w !C2Scene_SoundCmdPrio
    BCC .refuse
.queue:
    LDA.w !C2Scene_SoundCmdBuf
    STA.w !Audio_CmdId
    LDA.w !C2Scene_SoundCmdBuf+1
    STA.w !Audio_CmdArg0
    LDA.w !C2Scene_SoundCmdBuf+2
    STA.w !Audio_CmdArg1
    LDA.w !C2Scene_SoundCmdBuf+3
    STA.w !Audio_CmdArg2
    LDA.w !C2Scene_SoundCmdPrio
    STA.w !C2Scene_SoundCmdPendPrio
    LDA.b #!C2Scene_SoundCmdQueued
    STA.w !C2Scene_SoundCmdState
    CLC
    RTS
.refuse:
    SEC
    RTS

; ============================================================
; Scene sound zones ($C2:2F0F–$C2:309D)
; ============================================================
; The scene's $7E:7200 pack (C2Scene_Unk7200) starts with a map of 4-bit
; zone numbers, one per metatile of the 96 x 64 layer map (48 bytes per
; row, the even column in the high nibble; C2Scene_GetSoundZone).
; C2Scene_ZoneSounds gives each zone the argument of sound command
; C2Scene_SoundCmd10, which these routines send when the zone changes,
; keeping the last one in C2Scene_Unk02AE as script ops $3D/$4A do. The
; command is probably "play song" and the zones the music areas of the
; scene (not traced into the sound driver). While C2Scene_Unk7F01ED is
; set they send Menu_Config1E's byte instead (as op $3D skips its
; command then).
!C2Scene_ZoneCol = !C2Tmp_00            ; in for C2Scene_GetSoundZone: the metatile column (0-95)
!C2Scene_ZoneRow = !C2Tmp_01            ; and row (0-63)

; $C2:2F0F — C2Scene_ZoneSoundAtEntry (63 bytes, $2F0F–$2F4D)
; Sends C2Scene_SoundCmd10 straight to the driver (Audio_DriverCommand)
; with the zone sound of the field's entry tile: metatile column
; Loc_EntryX / 2, row Loc_EntryY / 2 (C2Scene_GetSoundZone,
; C2Scene_ZoneSounds), or with Menu_Config1E's byte while
; C2Scene_Unk7F01ED is set; argument bytes 2-3 C2Scene_SoundArgUnused
; and C2Scene_SoundArg80. The argument is also kept in C2Scene_Unk02AE.
; Callers note: none found by xref (perhaps reached through a pointer; not
;   traced).
; Entry: M=1 (8-bit loads), X=0, DP=$0000 (C2Tmp_00/$01), DB=$00
;        (DP_Field, low WRAM and the driver block, absolute)
; Exit:  M=1, X=0; A, X, Y as Audio_DriverCommand leaves them (not
;        traced); C2Tmp_00/$01 and $10-$12 changed when the zone is
;        looked up
; Calls: C2Scene_GetSoundZone, Audio_DriverCommand (JSL).
C2Scene_ZoneSoundAtEntry:
    LDA.l !C2Scene_Unk7F01ED
    BNE .config
    LDA.w !DP_Field+!Loc_EntryX
    LSR A
    STA.b !C2Scene_ZoneCol
    LDA.w !DP_Field+!Loc_EntryY
    LSR A
    STA.b !C2Scene_ZoneRow
    JSR C2Scene_GetSoundZone
    TAX                         ; B = 0
    LDA.w !C2Scene_ZoneSounds,X
    STA.w !Audio_CmdArg0
    STA.w !C2Scene_Unk02AE
    BRA .send
.config:
    LDA.l !Menu_Config1E
    STA.w !Audio_CmdArg0
    STA.w !C2Scene_Unk02AE
.send:
    LDA.b #!C2Scene_SoundCmd10
    STA.w !Audio_CmdId
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !Audio_CmdArg1
    LDA.b #!C2Scene_SoundArg80
    STA.w !Audio_CmdArg2
    JSL Audio_DriverCommand
    RTS

; $C2:2F4E — C2Scene_ZoneSoundAtView (70 bytes, $2F4E–$2F93)
; Queues (C2Scene_QueueSoundCmd) C2Scene_SoundCmd10 with the zone sound
; of the metatile at the middle of BG1's view: column BgTileX / 2 + 8,
; row (BgTileY / 2 + 7) AND 63; or with Menu_Config1E's byte while
; C2Scene_Unk7F01ED is set. Argument bytes 2-3 as
; C2Scene_ZoneSoundAtEntry. When it is queued (C=0) the argument goes to
; C2Scene_Unk02AE.
; Quirks, kept: the rank C2Scene_SoundCmdPrio is not set (whatever the
; last queuer left, 0 for every matched one); and the column is not
; wrapped at 96, so near the right edge of the map (BgTileX 176 or more)
; it reads the next row's first zones.
; Callers (1 JSR site): unmatched ($C2:45A6).
; Entry: M=1 (8-bit loads and adds), X=0, DP=$0000 (C2Scene_BgTileX/Y,
;        C2Tmp_00/$01), DB=$00 (low WRAM)
; Exit:  M=1, X=0; C as C2Scene_QueueSoundCmd leaves it (0 queued, 1
;        refused); A, X clobbered; Y = the column / 2 (C2Scene_GetSoundZone's
;        TAY) when the zone is looked up, else unchanged; C2Tmp_00/$01
;        and $10-$12 changed when the zone is looked up
; Calls: C2Scene_GetSoundZone, C2Scene_QueueSoundCmd.
C2Scene_ZoneSoundAtView:
    LDA.l !C2Scene_Unk7F01ED
    BNE .config
    LDA.b !C2Scene_BgTileX
    LSR A
    CLC
    ADC.b #!C2Scene_ViewMidCol
    STA.b !C2Scene_ZoneCol
    LDA.b !C2Scene_BgTileY
    LSR A
    CLC
    ADC.b #!C2Scene_ViewMidRow
    AND.b #!C2Scene_MapRows-1
    STA.b !C2Scene_ZoneRow
    JSR C2Scene_GetSoundZone
    TAX                         ; B = 0
    LDA.w !C2Scene_ZoneSounds,X
    STA.w !C2Scene_SoundCmdBuf+1
    BRA .queue
.config:
    LDA.l !Menu_Config1E
    STA.w !C2Scene_SoundCmdBuf+1
.queue:
    LDA.b #!C2Scene_SoundCmd10
    STA.w !C2Scene_SoundCmdBuf
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !C2Scene_SoundCmdBuf+2
    LDA.b #!C2Scene_SoundArg80
    STA.w !C2Scene_SoundCmdBuf+3
    JSR C2Scene_QueueSoundCmd
    BCS .done
    LDA.w !C2Scene_SoundCmdBuf+1
    STA.w !C2Scene_Unk02AE
.done:
    RTS

; $C2:2F94 — C2Scene_TaskZoneSound (9 bytes, $2F94–$2F9C)
; Task handler: runs .State through C2Scene_ZoneSoundStates. It follows
; the zone under C2Scene_StartX/Y (probably the player's position) and,
; when the zone's sound differs from the last one sent, sends
; C2Scene_SoundCmd81 with $0C,$00 (probably a fade out), waits
; C2Scene_ZoneFadeFrames frames, sends the new zone's
; C2Scene_SoundCmd10 and then C2Scene_SoundCmd81 with $00,$FF (probably
; full volume back). It never ends (every state returns C=0).
; Callers note: none found (no spawn of this address is in matched code or
;   found by a byte search; probably a script op $35 in scene data).
; Entry: M=1, X=0 with X = the task, DP=$0000 (TDC loads 0), DB=$00 (low
;        WRAM: the task record); C2Scene_TaskCur = the task
; Exit:  the state's (M=1, X=0; C=0)
; Calls: the C2Scene_ZoneSoundStates handlers (JMP (abs,X)).
C2Scene_TaskZoneSound:
    TDC
    LDA.w C2Scene_FxTask.State,X
    ASL A
    TAX
    JMP (C2Scene_ZoneSoundStates,X)

; $C2:2F9D — C2Scene_ZoneSoundStates (4 words, $2F9D–$2FA4)
; C2Scene_TaskZoneSound's handler for each .State.
C2Scene_ZoneSoundStates:
    dw C2Scene_ZoneSoundInit    ; 0
    dw C2Scene_ZoneSoundWatch   ; 1
    dw C2Scene_ZoneSoundWait    ; 2
    dw C2Scene_ZoneSoundResume  ; 3

; $C2:2FA5 — C2Scene_ZoneSoundInit (9 bytes, $2FA5–$2FAD)
; State 0: .State = 1, C2Scene_SoundZone = C2Scene_ZoneNone; falls into
; C2Scene_ZoneSoundWatch.
; Callers note: none direct (C2Scene_ZoneSoundStates).
; Entry: M=1, X=0, DP=$0000, DB=$00 (low WRAM: the task record);
;        C2Scene_TaskCur = the task
; Exit:  as C2Scene_ZoneSoundWatch
; No calls (falls into C2Scene_ZoneSoundWatch).
C2Scene_ZoneSoundInit:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_FxTask.State,X
    LDA.b #!C2Scene_ZoneNone
    STA.b !C2Scene_SoundZone

; $C2:2FAE — C2Scene_ZoneSoundWatch (142 bytes, $2FAE–$303B)
; State 1, every frame:
; - while C2Scene_Unk7F01ED is set: queues C2Scene_SoundCmd10 with
;   Menu_Config1E's byte at rank 0 (again each frame; C2Scene_Unk02AE
;   takes it when queued);
; - else, only in an idle mode (C2Scene_Mode 0, C2Scene_ModeIdle1 or
;   C2Scene_ModeIdle7) and with C2Scene_Unk027E clear: looks up the zone
;   at metatile column StartX / 16, row StartY / 16 - 1
;   (C2Scene_GetSoundZone) into C2Scene_SoundZone; if its sound
;   (C2Scene_ZoneSounds) is not C2Scene_Unk02AE, .State = 2, .Timer =
;   0 and C2Scene_SoundCmd81 is queued with C2Scene_SoundFadeArg, 0 and
;   C2Scene_SoundArgUnused at rank 0;
; - in any other mode, or with C2Scene_Unk027E set: C2Scene_SoundZone =
;   C2Scene_ZoneNone.
; Callers note: none direct (C2Scene_ZoneSoundStates; C2Scene_ZoneSoundInit
;   falls in).
; Entry: M=1, X=0, DP=$0000 (C2Tmp_00/$01, C2Scene_SoundZone), DB=$00
;        (low WRAM); C2Scene_TaskCur = the task
; Exit:  M=1, X=0, C=0 (the task goes on); A, X clobbered; Y = the
;        column / 2 (C2Scene_GetSoundZone's TAY) when the zone is looked
;        up, else unchanged; C2Tmp_00-$02 (the 16-bit store to
;        C2Scene_ZoneRow writes $02 too) and $10-$12 changed when the
;        zone is looked up
; Calls: C2Scene_QueueSoundCmd, C2Scene_GetSoundZone.
C2Scene_ZoneSoundWatch:
    LDA.l !C2Scene_Unk7F01ED
    BEQ .zone
    LDA.l !Menu_Config1E
    STA.w !C2Scene_SoundCmdBuf+1
    LDA.b #!C2Scene_SoundCmd10
    STA.w !C2Scene_SoundCmdBuf
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !C2Scene_SoundCmdBuf+2
    LDA.b #!C2Scene_SoundArg80
    STA.w !C2Scene_SoundCmdBuf+3
    STZ.w !C2Scene_SoundCmdPrio
    JSR C2Scene_QueueSoundCmd
    BCS .config_done
    LDA.w !C2Scene_SoundCmdBuf+1
    STA.w !C2Scene_Unk02AE
.config_done:
    CLC
    RTS
.zone:
    LDA.w !C2Scene_Mode
    BEQ .idle
    CMP.b #!C2Scene_ModeIdle1
    BEQ .idle
    CMP.b #!C2Scene_ModeIdle7
    BNE .none
.idle:
    LDA.w !C2Scene_Unk027E
    BNE .none
    REP #$20
    LDA.w !C2Scene_StartX
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_ZoneCol      ; 16-bit: C2Scene_ZoneRow is written next
    LDA.w !C2Scene_StartY
    LSR A
    LSR A
    LSR A
    LSR A
    DEC A
    STA.b !C2Scene_ZoneRow
    JSR C2Scene_GetSoundZone    ; returns M=1
    STA.b !C2Scene_SoundZone
    AND.b #!Eng_LowByteMask     ; no effect with 8-bit A (B = 0 already)
    TAX
    LDA.w !C2Scene_ZoneSounds,X
    CMP.w !C2Scene_Unk02AE
    BEQ .same
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_FxTask.State,X
    STZ.w C2Scene_FxTask.Timer,X
    STZ.w C2Scene_FxTask.Timer+1,X
    LDA.b #!C2Scene_SoundCmd81
    STA.w !C2Scene_SoundCmdBuf
    LDA.b #!C2Scene_SoundFadeArg
    STA.w !C2Scene_SoundCmdBuf+1
    STZ.w !C2Scene_SoundCmdBuf+2
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !C2Scene_SoundCmdBuf+3
    STZ.w !C2Scene_SoundCmdPrio
    JSR C2Scene_QueueSoundCmd
.same:
    CLC
    RTS
.none:
    LDA.b #!C2Scene_ZoneNone
    STA.b !C2Scene_SoundZone
    CLC
    RTS

; $C2:303C — C2Scene_ZoneSoundWait (19 bytes, $303C–$304E)
; State 2: once .Timer's low byte (zeroed by C2Scene_ZoneSoundWatch,
; then one more each frame from C2Scene_TaskRunAll) reaches
; C2Scene_ZoneFadeFrames: .State = 3 and the new zone's sound is queued
; (C2Scene_ZoneSoundQueue).
; Callers note: none direct (C2Scene_ZoneSoundStates).
; Entry: M=1, X=0, DP=$0000, DB=$00 (low WRAM: the task record);
;        C2Scene_TaskCur = the task
; Exit:  M=1, X=0, C=0; A, X clobbered; Y unchanged
; Calls: C2Scene_ZoneSoundQueue.
C2Scene_ZoneSoundWait:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FxTask.Timer,X
    CMP.b #!C2Scene_ZoneFadeFrames
    BCC .wait
    LDA.b #3
    STA.w C2Scene_FxTask.State,X
    JSR C2Scene_ZoneSoundQueue
.wait:
    CLC
    RTS

; $C2:304F — C2Scene_ZoneSoundResume (39 bytes, $304F–$3075)
; State 3: unless a command is being sent (C2Scene_SoundCmdState
; negative), queues C2Scene_SoundCmd81 with 0, C2Scene_SoundArgUnused,
; C2Scene_SoundArgUnused at rank 0 and sets .State back to 1 (whether
; the queue took the command or not).
; Callers note: none direct (C2Scene_ZoneSoundStates).
; Entry: M=1, X=0, DP=$0000 (TDC for 0), DB=$00 (low WRAM);
;        C2Scene_TaskCur = the task
; Exit:  M=1, X=0, C=0; A, X clobbered; Y unchanged
; Calls: C2Scene_QueueSoundCmd.
C2Scene_ZoneSoundResume:
    LDA.w !C2Scene_SoundCmdState
    BMI .busy
    LDA.b #!C2Scene_SoundCmd81
    STA.w !C2Scene_SoundCmdBuf
    TDC                         ; A = DP = 0
    STA.w !C2Scene_SoundCmdBuf+1
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !C2Scene_SoundCmdBuf+2
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !C2Scene_SoundCmdBuf+3
    STZ.w !C2Scene_SoundCmdPrio
    JSR C2Scene_QueueSoundCmd
    LDX.b !C2Scene_TaskCur
    LDA.b #1
    STA.w C2Scene_FxTask.State,X
.busy:
    CLC
    RTS

; $C2:3076 — C2Scene_ZoneSoundQueue (40 bytes, $3076–$309D)
; Queues C2Scene_SoundCmd10 with the sound of zone C2Scene_SoundZone
; (C2Scene_ZoneSounds), argument bytes 2-3 C2Scene_SoundArgUnused and
; C2Scene_SoundArg80, at rank 0; when queued, the sound goes to
; C2Scene_Unk02AE.
; Callers (1 JSR site): C2Scene_ZoneSoundWait ($C2:304A).
; Entry: M=1, X=0, DP=$0000 (TDC for 0, C2Scene_SoundZone), DB=$00 (low
;        WRAM)
; Exit:  M=1, X=0; C as C2Scene_QueueSoundCmd leaves it; A, X clobbered;
;        Y unchanged
; Calls: C2Scene_QueueSoundCmd.
C2Scene_ZoneSoundQueue:
    TDC                         ; A = DP = 0: clears the high byte
    LDA.b !C2Scene_SoundZone
    TAX
    LDA.w !C2Scene_ZoneSounds,X
    STA.w !C2Scene_SoundCmdBuf+1
    LDA.b #!C2Scene_SoundCmd10
    STA.w !C2Scene_SoundCmdBuf
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !C2Scene_SoundCmdBuf+2
    LDA.b #!C2Scene_SoundArg80
    STA.w !C2Scene_SoundCmdBuf+3
    STZ.w !C2Scene_SoundCmdPrio
    JSR C2Scene_QueueSoundCmd
    BCS .done
    LDA.w !C2Scene_SoundCmdBuf+1
    STA.w !C2Scene_Unk02AE
.done:
    RTS

; ============================================================
; Scene objects and tile triggers ($C2:309E–$C2:3403)
; ============================================================
; Two per-frame watchers, each a state machine that returns C=0 (as a
; task handler that never ends). No reference to either entry is in the
; bank's code or found by a byte search, so they are probably started
; from scene data (script op $35, C2Script_SpawnTask, or called by op
; $34, C2Script_CallNear; not traced). Both read the party's position
; as C2Scene_StartX/Y (C2Scene_TaskZoneSound follows the same words).
;
; C2Scene_ObjWatch (state C2Scene_Unk027E) watches two objects, A
; ($0290-$0294, $029F) and B ($029A-$029E): when the button held in
; Pad_Unk00F8 bit 7 (A with the default button map) is down and the
; party's box overlaps an active object's, it selects that object and
; waits until as many party members are counted in the object's flags
; as are in the party, then until the object's busy bit clears, then
; until its count is back to 0. That looks like the party getting into
; something and out again, but what the objects are is not traced.
;
; C2Scene_TrigWatch (state C2Scene_Unk0280) looks the party's 16-pixel
; tile up in C2Scene_ListA, ListB and ListC (entries whose bit 7 is set)
; when C2Scene_TrigFlags asks it to, and acts on what it finds: a ListA
; entry (an exit, as C2Scene_Mode3 uses it) sets the current task's
; .Unk02; a ListB entry starts its C2Scene_ListD script once (clearing
; its bit 7) and waits for C2Scene_Unk1B43; a ListC entry selects the
; scene mode C2Scene_ModeHalt.

; $C2:309E — C2Scene_ObjWatch (35 bytes, $309E–$30C0)
; While C2Scene_Mode is 0 or 1 and C2Scene_TrigWatch is in its check
; state (C2Scene_Unk0280 = 0): copies C2Scene_Unk027E to
; C2Scene_Unk027F and runs its state through C2Scene_ObjWatchStates.
; Otherwise returns C=0 at once.
; Callers note: none found (see the banner).
; Entry: M=1, X=0, DP=$0000 (TDC for 0), DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0 (M=0 from C2Scene_ObjWatchIdle when the button is
;        up); the state's changes; A, X clobbered when a state runs
; Calls: a C2Scene_ObjWatchStates handler (JMP (abs,X)).
C2Scene_ObjWatch:
    LDA.w !C2Scene_Mode
    CMP.b #!C2Scene_ModeIdle1
    BEQ .mode_ok
    CMP.b #0
    BEQ .mode_ok
    CLC
    RTS
.mode_ok:
    LDA.w !C2Scene_Unk0280
    BEQ .step
    CLC
    RTS
.step:
    LDA.w !C2Scene_Unk027E
    STA.w !C2Scene_Unk027F
    TDC                         ; A = DP = 0: clears the high byte
    LDA.w !C2Scene_Unk027E
    ASL A
    TAX
    JMP (C2Scene_ObjWatchStates,X)

; $C2:30C1 — C2Scene_ObjWatchStates (6 words, $30C1–$30CC)
; C2Scene_ObjWatch's handler for each C2Scene_Unk027E state 0-5.
; Nothing in this code sets state 1.
C2Scene_ObjWatchStates:
    dw C2Scene_ObjWatchIdle     ; 0 (C2Scene_ObjWatchStIdle)
    dw C2Scene_ObjWatchNone     ; 1
    dw C2Scene_ObjWatchBusyA    ; 2 (C2Scene_ObjWatchStBusyA)
    dw C2Scene_ObjWatchBusyB    ; 3 (C2Scene_ObjWatchStBusyB)
    dw C2Scene_ObjWatchFull     ; 4 (C2Scene_ObjWatchStFull)
    dw C2Scene_ObjWatchEmpty    ; 5 (C2Scene_ObjWatchStEmpty)

; $C2:30CD — C2Scene_ObjWatchIdle (219 bytes, $30CD–$31A7)
; State 0. Does nothing unless Pad_Unk00F8 bit 7 is set. Then box A of
; C2Scene_BoxesOverlap is C2Scene_PartyBox at (C2Scene_StartX,
; C2Scene_StartY), and:
; - object A, if C2Scene_Unk0294 has C2Scene_ObjActive and the current
;   Loc_Id AND C2Scene_LocIdMask equals the word C2Scene_ObjALoc: box B is
;   C2Scene_ObjABox at (C2Scene_ObjAX, C2Scene_ObjAY). On an overlap,
;   with C2Scene_Flag0Copy = C2Scene_Flag0ObjAScript it selects scene
;   mode C2Scene_ModeIdle7 and starts the script C2Scene_ScrGoToLoc1D8
;   (which leaves for location $1D8); otherwise C2Scene_ObjSel =
;   C2Scene_ObjSelA and state C2Scene_ObjWatchStFull;
; - if A is not active, elsewhere, or not overlapped, object B the same
;   way, if C2Scene_ObjBFlags has C2Scene_ObjActive and Loc_Id is
;   C2Scene_ObjBLocId: C2Scene_ObjBBox at (C2Scene_ObjBX, C2Scene_ObjBY);
;   on an overlap C2Scene_ObjSel = C2Scene_ObjSelB and state
;   C2Scene_ObjWatchStFull.
; Selecting an object also zeroes C2Scene_Unk1B58/1B59,
; C2Scene_TrigFound and C2Scene_TrigFlags, and sets the three
; C2Scene_Unk1B32 words to C2Scene_Unk1B32Init.
; Quirks, kept: when the button is up it returns with M=0 (the JMP to
; .done comes before the SEP). Object B's Loc_Id is compared unmasked
; (bits 9-15 must be clear too), and the AND #$FF before that CPX does
; nothing (A is not used after it).
; Callers note: none direct (C2Scene_ObjWatchStates).
; Entry: M=1, X=0, DP=$0000 (the C2Scene_Box* temporaries), DB=$00
;        (Pad_Unk00F8, DP_Field and low WRAM absolute)
; Exit:  C=0; M=0 (button up) or M=1, X=0; A, X, Y clobbered;
;        C2Tmp_08-$15 set for the box test; C2Scene_TaskSpawnScript's
;        temporaries when the script starts
; Calls: C2Scene_BoxesOverlap, C2Scene_TaskSpawnScript.
C2Scene_ObjWatchIdle:
    REP #$20
    LDA.w !Pad_Unk00F8
    BIT.w #!Pad_Unk00F8Bit7
    BNE .pressed
    JMP .done
.pressed:
    SEP #$20
    LDX.w !C2Scene_StartX
    STX.b !C2Scene_BoxAX
    LDX.w !C2Scene_StartY
    STX.b !C2Scene_BoxAY
    LDX.w #C2Scene_PartyBox
    STX.b !C2Scene_BoxAPtr
    LDA.b #bank(C2Scene_PartyBox)
    STA.b !C2Scene_BoxAPtr+2
    LDA.w !C2Scene_Unk0294
    BPL .try_b                  ; not C2Scene_ObjActive
    REP #$20
    LDA.w !DP_Field+!Loc_Id
    AND.w #!C2Scene_LocIdMask
    CMP.w !C2Scene_ObjALoc
    SEP #$20
    BNE .try_b
    LDX.w !C2Scene_ObjAX
    STX.b !C2Scene_BoxBX
    LDX.w !C2Scene_ObjAY
    STX.b !C2Scene_BoxBY
    LDX.w #C2Scene_ObjABox
    STX.b !C2Scene_BoxBPtr
    LDA.b #bank(C2Scene_ObjABox)
    STA.b !C2Scene_BoxBPtr+2
    REP #$20
    JSR C2Scene_BoxesOverlap
    SEP #$20
    BCC .try_b
    LDA.w !C2Scene_Flag0Copy
    CMP.b #!C2Scene_Flag0ObjAScript
    BEQ .script
    LDA.b #!C2Scene_ObjSelA
    STA.w !C2Scene_ObjSel
    LDA.b #!C2Scene_ObjWatchStFull
    STA.w !C2Scene_Unk027E
    STZ.w !C2Scene_Unk1B58
    STZ.w !C2Scene_Unk1B59
    LDX.w #!C2Scene_Unk1B32Init
    STX.w !C2Scene_Unk1B32
    STX.w !C2Scene_Unk1B32+2
    STX.w !C2Scene_Unk1B32+4
    STZ.w !C2Scene_TrigFound
    STZ.w !C2Scene_TrigFlags
    BRA .done
.script:
    LDA.b #!C2Scene_ModeIdle7
    STA.w !C2Scene_Mode
    LDA.b #bank(C2Scene_ScrGoToLoc1D8)
    LDX.w #C2Scene_ScrGoToLoc1D8
    JSR C2Scene_TaskSpawnScript
    CLC
    RTS
.try_b:
    LDA.w !C2Scene_ObjBFlags
    BPL .done                   ; not C2Scene_ObjActive
    LDX.w !DP_Field+!Loc_Id
    AND.b #!Eng_LowByteMask     ; quirk: no effect (see the header)
    CPX.w #!C2Scene_ObjBLocId
    BNE .done
    LDX.w !C2Scene_ObjBX
    STX.b !C2Scene_BoxBX
    LDX.w !C2Scene_ObjBY
    STX.b !C2Scene_BoxBY
    LDX.w #C2Scene_ObjBBox
    STX.b !C2Scene_BoxBPtr
    LDA.b #bank(C2Scene_ObjBBox)
    STA.b !C2Scene_BoxBPtr+2
    REP #$20
    JSR C2Scene_BoxesOverlap
    SEP #$20
    BCC .done
    STZ.w !C2Scene_Unk1B58
    STZ.w !C2Scene_Unk1B59
    LDX.w #!C2Scene_Unk1B32Init
    STX.w !C2Scene_Unk1B32
    STX.w !C2Scene_Unk1B32+2
    STX.w !C2Scene_Unk1B32+4
    STZ.w !C2Scene_TrigFound
    STZ.w !C2Scene_TrigFlags
    LDA.b #!C2Scene_ObjSelB
    STA.w !C2Scene_ObjSel
    LDA.b #!C2Scene_ObjWatchStFull
    STA.w !C2Scene_Unk027E
.done:
    CLC
    RTS

; $C2:31A8 — C2Scene_ScrGoToLoc1D8 (10 bytes, $31A8–$31B1)
; Scene script (C2Scene_TaskRunScript) started by C2Scene_ObjWatchIdle:
; fade out, wait, then leave for location $1D8 (op $05 argument word
; $03D8: Loc_Id $1D8, entry facing 1) at tile (7, 8).
C2Scene_ScrGoToLoc1D8:
    db $28,$01                  ; C2Script_SpawnUnk20A2 (fade out), 1 frame per step
    db $38,$12                  ; C2Script_Wait, 18 frames
    db $05,$D8,$03,$07,$08      ; C2Script_GoToLocation: $03D8, X 7, Y 8
    db $52                      ; C2Script_End

; $C2:31B2 — C2Scene_ObjWatchNone (2 bytes, $31B2–$31B3)
; State 1, and C2Scene_ObjSel 0 and 1 in C2Scene_ObjFullTable and
; C2Scene_ObjEmptyTable (shared label): nothing; C=0.
; Callers note: none direct (C2Scene_ObjWatchStates; the two tables).
; Entry: M=1 (any), X any, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_ObjWatchNone:
    CLC
    RTS

; $C2:31B4 — C2Scene_ObjWatchBusyA (14 bytes, $31B4–$31C1, with
; C2Scene_ObjWatchBusyB at $C2:31C2, 14 bytes)
; States 2 and 3: wait until object A's (C2Scene_Unk0294) or object
; B's (C2Scene_ObjBFlags) C2Scene_ObjBusy bit is clear, then state
; C2Scene_ObjWatchStEmpty.
; Callers note: none direct (C2Scene_ObjWatchStates).
; Entry: M=1, X=0, DP any, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1; A = the flags byte, or C2Scene_ObjWatchStEmpty
C2Scene_ObjWatchBusyA:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjBusy
    BNE .wait
    LDA.b #!C2Scene_ObjWatchStEmpty
    STA.w !C2Scene_Unk027E
.wait:
    CLC
    RTS

C2Scene_ObjWatchBusyB:          ; header: see C2Scene_ObjWatchBusyA
    LDA.w !C2Scene_ObjBFlags
    BIT.b #!C2Scene_ObjBusy
    BNE .wait
    LDA.b #!C2Scene_ObjWatchStEmpty
    STA.w !C2Scene_Unk027E
.wait:
    CLC
    RTS

; $C2:31D0 — C2Scene_ObjWatchFull (34 bytes, $31D0–$31F1)
; State 4: counts the party members in C2Scene_PartyCount (each
; Party_Members byte with bit 7 clear; bit 7 is taken to mean an empty
; slot) and runs C2Scene_ObjSel through C2Scene_ObjFullTable: for the
; selected object, when its count (flags AND C2Scene_ObjCountMask)
; equals the party count, state C2Scene_ObjWatchStBusyA or
; C2Scene_ObjWatchStBusyB.
; Callers note: none direct (C2Scene_ObjWatchStates).
; Entry: M=1, X=0, B=0 (the 16-bit TAX of the doubled C2Scene_ObjSel;
;        from C2Scene_ObjWatch's TDC), DP=$0000 (C2Scene_PartyCount),
;        DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; A, X clobbered; C2Scene_PartyCount set
; Calls: a C2Scene_ObjFullTable handler (JMP (abs,X)).
!C2Scene_PartyCount = !C2Tmp_00         ; 8-bit: party members counted by C2Scene_ObjWatchFull
C2Scene_ObjWatchFull:
    STZ.b !C2Scene_PartyCount
    LDA.l !Party_Members
    BMI .member2
    INC.b !C2Scene_PartyCount
.member2:
    LDA.l !Party_Members+1
    BMI .member3
    INC.b !C2Scene_PartyCount
.member3:
    LDA.l !Party_Members+2
    BMI .counted
    INC.b !C2Scene_PartyCount
.counted:
    LDA.w !C2Scene_ObjSel
    ASL A
    TAX
    JMP (C2Scene_ObjFullTable,X)

; $C2:31F2 — C2Scene_ObjFullTable (4 words, $31F2–$31F9)
; C2Scene_ObjWatchFull's handler for C2Scene_ObjSel 0-3.
C2Scene_ObjFullTable:
    dw C2Scene_ObjFullNone      ; 0
    dw C2Scene_ObjFullNone      ; 1
    dw C2Scene_ObjFullA         ; 2 (C2Scene_ObjSelA)
    dw C2Scene_ObjFullB         ; 3 (C2Scene_ObjSelB)

; $C2:31FA — C2Scene_ObjFullNone (2 bytes, $31FA–$31FB)
; No object selected: nothing; C=0.
; Callers note: none direct (C2Scene_ObjFullTable).
; Entry: M=1 (any), X any, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_ObjFullNone:
    CLC
    RTS

; $C2:31FC — C2Scene_ObjFullA (16 bytes, $31FC–$320B, with
; C2Scene_ObjFullB at $C2:320C, 16 bytes)
; Object A's (C2Scene_Unk0294) or B's (C2Scene_ObjBFlags) count equal to
; C2Scene_PartyCount: state C2Scene_ObjWatchStBusyA or
; C2Scene_ObjWatchStBusyB.
; Callers note: none direct (C2Scene_ObjFullTable).
; Entry: M=1, X=0, DP=$0000 (C2Scene_PartyCount), DB=$00 (low WRAM
;        absolute)
; Exit:  C=0; M=1; A = the count or the new state
C2Scene_ObjFullA:
    LDA.w !C2Scene_Unk0294
    AND.b #!C2Scene_ObjCountMask
    CMP.b !C2Scene_PartyCount
    BNE .wait
    LDA.b #!C2Scene_ObjWatchStBusyA
    STA.w !C2Scene_Unk027E
.wait:
    CLC
    RTS

C2Scene_ObjFullB:               ; header: see C2Scene_ObjFullA
    LDA.w !C2Scene_ObjBFlags
    AND.b #!C2Scene_ObjCountMask
    CMP.b !C2Scene_PartyCount
    BNE .wait
    LDA.b #!C2Scene_ObjWatchStBusyB
    STA.w !C2Scene_Unk027E
.wait:
    CLC
    RTS

; $C2:321C — C2Scene_ObjWatchEmpty (8 bytes, $321C–$3223)
; State 5: runs C2Scene_ObjSel through C2Scene_ObjEmptyTable: when the
; selected object's count is 0, back to state C2Scene_ObjWatchStIdle
; with no object selected.
; Callers note: none direct (C2Scene_ObjWatchStates).
; Entry: M=1, X=0, B=0 (the 16-bit TAX; from C2Scene_ObjWatch's TDC),
;        DP any, DB=$00 (low WRAM absolute)
; Exit:  the handler's: C=0; M=1, X=0; A, X clobbered
; Calls: a C2Scene_ObjEmptyTable handler (JMP (abs,X)).
C2Scene_ObjWatchEmpty:
    LDA.w !C2Scene_ObjSel
    ASL A
    TAX
    JMP (C2Scene_ObjEmptyTable,X)

; $C2:3224 — C2Scene_ObjEmptyTable (4 words, $3224–$322B)
; C2Scene_ObjWatchEmpty's handler for C2Scene_ObjSel 0-3.
C2Scene_ObjEmptyTable:
    dw C2Scene_ObjEmptyNone     ; 0
    dw C2Scene_ObjEmptyNone     ; 1
    dw C2Scene_ObjEmptyA        ; 2 (C2Scene_ObjSelA)
    dw C2Scene_ObjEmptyB        ; 3 (C2Scene_ObjSelB)

; $C2:322C — C2Scene_ObjEmptyNone (2 bytes, $322C–$322D)
; No object selected: nothing; C=0.
; Callers note: none direct (C2Scene_ObjEmptyTable).
; Entry: M=1 (any), X any, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_ObjEmptyNone:
    CLC
    RTS

; $C2:322E — C2Scene_ObjEmptyA (15 bytes, $322E–$323C, with
; C2Scene_ObjEmptyB at $C2:323D, 15 bytes)
; Object A's (C2Scene_Unk0294) or B's (C2Scene_ObjBFlags) count at 0:
; C2Scene_Unk027E = C2Scene_ObjWatchStIdle and C2Scene_ObjSel = 0.
; Callers note: none direct (C2Scene_ObjEmptyTable).
; Entry: M=1, X any, DP any, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1; A = the count
C2Scene_ObjEmptyA:
    LDA.w !C2Scene_Unk0294
    AND.b #!C2Scene_ObjCountMask
    BNE .wait
    STZ.w !C2Scene_Unk027E
    STZ.w !C2Scene_ObjSel
.wait:
    CLC
    RTS

C2Scene_ObjEmptyB:              ; header: see C2Scene_ObjEmptyA
    LDA.w !C2Scene_ObjBFlags
    AND.b #!C2Scene_ObjCountMask
    BNE .wait
    STZ.w !C2Scene_Unk027E
    STZ.w !C2Scene_ObjSel
.wait:
    CLC
    RTS

; $C2:324C — C2Scene_PartyBox (4 words, $324C–$3253)
; C2Scene_BoxesOverlap extents (left, right, up, down) of the party in
; C2Scene_ObjWatchIdle: 8 each way.
C2Scene_PartyBox:
    dw 8,8,8,8

; $C2:3254 — C2Scene_ObjABox (4 words, $3254–$325B)
; Extents of object A: only 8 down from its position.
C2Scene_ObjABox:
    dw 0,0,0,8

; $C2:325C — C2Scene_ObjBBox (4 words, $325C–$3263)
; Extents of object B: the same as object A's.
C2Scene_ObjBBox:
    dw 0,0,0,8

; $C2:3264 — C2Scene_TrigWatch (17 bytes, $3264–$3274)
; Copies its state C2Scene_Unk0280 to C2Scene_Unk0281 and runs it
; through C2Scene_TrigWatchStates (0: C2Scene_TrigWatchCheck,
; C2Scene_TrigStWait: C2Scene_TrigWatchWait).
; Callers note: none found (see the banner).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (TDC for 0), DB=$00 (low
;        WRAM absolute)
; Exit:  the state's: C=0; M=1, X=0
; Calls: a C2Scene_TrigWatchStates handler (JMP (abs,X)).
C2Scene_TrigWatch:
    SEP #$20
    LDA.w !C2Scene_Unk0280
    STA.w !C2Scene_Unk0281
    TDC                         ; A = DP = 0: clears the high byte
    LDA.w !C2Scene_Unk0280
    ASL A
    TAX
    JMP (C2Scene_TrigWatchStates,X)

; $C2:3275 — C2Scene_TrigWatchStates (2 words, $3275–$3278)
; C2Scene_TrigWatch's handler for each C2Scene_Unk0280 state.
C2Scene_TrigWatchStates:
    dw C2Scene_TrigWatchCheck   ; 0
    dw C2Scene_TrigWatchWait    ; 1 (C2Scene_TrigStWait)

; $C2:3279 — C2Scene_TrigWatchCheck (62 bytes, $3279–$32B6)
; State 0. When C2Scene_TrigFlags has C2Scene_TrigRecheck it clears it,
; takes the party's tile (C2Scene_StartX / 16, C2Scene_StartY / 16),
; finds the list entries there (C2Scene_FindTrigEntries) and acts on
; them (C2Scene_TrigDispatch). Then, unless C2Scene_TrigFlags has
; C2Scene_TrigKeep, it forgets them again: C2Scene_Unk1B58 = 0 and the
; three C2Scene_Unk1B32 words = C2Scene_Unk1B32Init (also when nothing
; was looked up).
; Callers note: none direct (C2Scene_TrigWatchStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TrigTile), DB=$00 (low WRAM
;        absolute)
; Exit:  C=0; M=1, X=0; A, X, Y clobbered when it looked up (and what
;        C2Scene_TrigDispatch's action changes)
; Calls: C2Scene_FindTrigEntries, C2Scene_TrigDispatch.
!C2Scene_TrigTile = !C2Tmp_00           ; 16-bit: the party's tile X (low byte), tile Y (high byte)
C2Scene_TrigWatchCheck:
    LDA.w !C2Scene_TrigFlags
    BIT.b #!C2Scene_TrigRecheck
    BEQ .forget
    LDA.b #!C2Scene_TrigRecheck
    TRB.w !C2Scene_TrigFlags
    REP #$20
    LDA.w !C2Scene_StartX
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_TrigTile     ; tile X in $00 (its high byte is overwritten next)
    LDA.w !C2Scene_StartY
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_TrigTile+1   ; tile Y in $01
    JSR C2Scene_FindTrigEntries
    JSR C2Scene_TrigDispatch
.forget:
    LDA.w !C2Scene_TrigFlags
    BIT.b #!C2Scene_TrigKeep
    BNE .done
    STZ.w !C2Scene_Unk1B58
    LDX.w #!C2Scene_Unk1B32Init
    STX.w !C2Scene_Unk1B32
    STX.w !C2Scene_Unk1B32+2
    STX.w !C2Scene_Unk1B32+4
.done:
    CLC
    RTS

; $C2:32B7 — C2Scene_TrigWatchWait (22 bytes, $32B7–$32CC)
; State C2Scene_TrigStWait (set when a ListB script starts): once
; C2Scene_Unk1B43 is non-zero, back to state 0 with the three
; C2Scene_Unk1B32 words at C2Scene_Unk1B32Init.
; Callers note: none direct (C2Scene_TrigWatchStates).
; Entry: M=1, X=0, DP any, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = C2Scene_Unk1B32Init when it ends the wait
C2Scene_TrigWatchWait:
    LDA.w !C2Scene_Unk1B43
    BEQ .done
    STZ.w !C2Scene_Unk0280
    LDX.w #!C2Scene_Unk1B32Init
    STX.w !C2Scene_Unk1B32
    STX.w !C2Scene_Unk1B32+2
    STX.w !C2Scene_Unk1B32+4
.done:
    CLC
    RTS

; $C2:32CD — C2Scene_FindTrigEntries (124 bytes, $32CD–$3348)
; For C2Scene_ListA, ListB and ListC in turn: the byte offset of the
; first entry that has C2Scene_ListEntryBit7 set and whose first word
; AND C2Scene_ListTileMask equals C2Scene_TrigTile, or C2Scene_NoEntry,
; into C2Scene_Unk1B32 (ListA), C2Scene_Unk1B32+2 (ListB) and
; C2Scene_Unk1B32+4 (ListC).
; Quirk, kept: a list count of 0 is not special-cased: the DEY/BNE loop
; then runs 65536 times (reading far past the list).
; Callers (1 JSR site): C2Scene_TrigWatchCheck ($C2:3299).
; Entry: M=0, X=0, DP=$0000 (C2Scene_TrigTile), DB=$00 (the counts and
;        C2Scene_Unk1B32 absolute)
; Exit:  M=0, X=0; X = ListC's result; A clobbered; Y = 0 when the last
;        search ran out, else the entries left
; No calls.
C2Scene_FindTrigEntries:
    LDA.w !C2Scene_ListACount
    AND.w #!Eng_LowByteMask
    TAY
    LDX.w #0
.next_a:
    LDA.l C2Scene_ListAEntry.Flags,X
    BIT.w #!C2Scene_ListEntryBit7
    BEQ .skip_a
    AND.w #!C2Scene_ListTileMask
    CMP.b !C2Scene_TrigTile
    BEQ .found_a
.skip_a:
    TXA
    CLC
    ADC.w #!C2Scene_ListAEntrySize
    TAX
    DEY
    BNE .next_a
    LDX.w #!C2Scene_NoEntry
.found_a:
    STX.w !C2Scene_Unk1B32
    LDA.w !C2Scene_ListBCount
    AND.w #!Eng_LowByteMask
    TAY
    LDX.w #0
.next_b:
    LDA.l C2Scene_ListBEntry.Flags,X
    BIT.w #!C2Scene_ListEntryBit7
    BEQ .skip_b
    AND.w #!C2Scene_ListTileMask
    CMP.b !C2Scene_TrigTile
    BEQ .found_b
.skip_b:
    TXA
    CLC
    ADC.w #!C2Scene_ListBCEntrySize
    TAX
    DEY
    BNE .next_b
    LDX.w #!C2Scene_NoEntry
.found_b:
    STX.w !C2Scene_Unk1B32+2
    LDA.w !C2Scene_ListCCount
    AND.w #!Eng_LowByteMask
    TAY
    LDX.w #0
.next_c:
    LDA.l !C2Scene_ListC,X
    BIT.w #!C2Scene_ListEntryBit7
    BEQ .skip_c
    AND.w #!C2Scene_ListTileMask
    CMP.b !C2Scene_TrigTile
    BEQ .found_c
.skip_c:
    TXA
    CLC
    ADC.w #!C2Scene_ListBCEntrySize
    TAX
    DEY
    BNE .next_c
    LDX.w #!C2Scene_NoEntry
.found_c:
    STX.w !C2Scene_Unk1B32+4
    RTS

; $C2:3349 — C2Scene_TrigDispatch (53 bytes, $3349–$337D)
; Zeroes C2Scene_Unk1B58, builds C2Scene_TrigFound from which of the
; three C2Scene_Unk1B32 words is not C2Scene_NoEntry (bit 7 of the high
; byte clear): C2Scene_TrigFoundA (ListA), C2Scene_TrigFoundC (ListC),
; C2Scene_TrigFoundB (ListB), and runs that mask through
; C2Scene_TrigActions.
; Callers (1 JSR site): C2Scene_TrigWatchCheck ($C2:329C).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Scene_TrigMask; TDC
;        for 0), DB=$00 (low WRAM absolute)
; Exit:  the action's: M=1, X=0; A, X (and Y) clobbered
; Calls: a C2Scene_TrigActions handler (JMP (abs,X)).
!C2Scene_TrigMask = !C2Tmp_00           ; 8-bit: the mask being built
C2Scene_TrigDispatch:
    SEP #$20
    STZ.w !C2Scene_Unk1B58
    STZ.b !C2Scene_TrigMask
    LDA.w !C2Scene_Unk1B32+1
    BMI .no_a
    LDA.b !C2Scene_TrigMask
    ORA.b #!C2Scene_TrigFoundA
    STA.b !C2Scene_TrigMask
.no_a:
    LDA.w !C2Scene_Unk1B32+5
    BMI .no_c
    LDA.b !C2Scene_TrigMask
    ORA.b #!C2Scene_TrigFoundC
    STA.b !C2Scene_TrigMask
.no_c:
    LDA.w !C2Scene_Unk1B32+3
    BMI .no_b
    LDA.b !C2Scene_TrigMask
    ORA.b #!C2Scene_TrigFoundB
    STA.b !C2Scene_TrigMask
.no_b:
    LDA.b !C2Scene_TrigMask
    STA.w !C2Scene_TrigFound
    TDC                         ; A = DP = 0: clears the high byte
    LDA.b !C2Scene_TrigMask
    ASL A
    TAX
    JMP (C2Scene_TrigActions,X)

; $C2:337E — C2Scene_TrigActions (8 words, $337E–$338D)
; C2Scene_TrigDispatch's action for each C2Scene_TrigFound mask: ListB
; wins over ListA's task byte, ListA over ListC's mode.
C2Scene_TrigActions:
    dw C2Scene_TrigNone         ; none
    dw C2Scene_TrigListA        ; A
    dw C2Scene_TrigListC        ; C
    dw C2Scene_TrigListA        ; A + C
    dw C2Scene_TrigListB        ; B
    dw C2Scene_TrigListAB       ; A + B
    dw C2Scene_TrigListB        ; B + C
    dw C2Scene_TrigListAB       ; A + B + C

; $C2:338E — C2Scene_TrigNone (1 byte, $338E)
; No entry at the tile: nothing.
; Callers note: none direct (C2Scene_TrigActions).
; Entry: M=1, X=0, DP and DB any (no accesses)
; Exit:  nothing changed
C2Scene_TrigNone:
    RTS

; $C2:338F — C2Scene_TrigListA (11 bytes, $338F–$3399)
; A ListA entry (and no ListB one): the current task's .Unk02
; (C2Scene_TaskCur) = C2Scene_TrigTaskState1, and the entry's .Unk02
; to C2Scene_Unk1B58 (C2Scene_GetListAUnk02). What reads that task
; byte is not matched.
; Callers note: none direct (C2Scene_TrigActions).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (the task record
;        and C2Scene_Unk1B32 absolute)
; Exit:  M=1, X=0; A = the entry byte; X = C2Scene_Unk1B32
; Calls: C2Scene_GetListAUnk02.
C2Scene_TrigListA:
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_TrigTaskState1
    STA.w C2Scene_Task.Unk02,X
    JSR C2Scene_GetListAUnk02
    RTS

; $C2:339A — C2Scene_TrigListC (16 bytes, $339A–$33A9)
; A ListC entry only: the current task's .Unk02 =
; C2Scene_TrigTaskState1, a ListC byte to C2Scene_Unk1B47
; (C2Scene_GetListCUnk03), and scene mode C2Scene_ModeHalt
; (C2Scene_Mode4, which never leaves).
; Callers note: none direct (C2Scene_TrigActions).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute)
; Exit:  M=1, X=0; A = C2Scene_ModeHalt; X = C2Scene_Unk1B32+4's offset
; Calls: C2Scene_GetListCUnk03.
C2Scene_TrigListC:
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_TrigTaskState1
    STA.w C2Scene_Task.Unk02,X
    JSR C2Scene_GetListCUnk03
    LDA.b #!C2Scene_ModeHalt
    STA.w !C2Scene_Mode
    RTS

; $C2:33AA — C2Scene_TrigListB (42 bytes, $33AA–$33D3)
; A ListB entry (and no ListA one): starts its C2Scene_ListD script
; (C2Scene_GetListBScript; bank $7F, as C2Scene_Mode3 does), zeroes
; C2Scene_MemberWords, clears the entry's C2Scene_ListEntryBit7 (so it
; fires once) and puts C2Scene_TrigWatch in C2Scene_TrigStWait. Unlike
; C2Scene_TrigListAB and C2Scene_Mode3 it leaves C2Scene_Unk1B43 as it
; is.
; Callers note: none direct (C2Scene_TrigActions).
; Entry: M=1, X=0, B=0 (for C2Scene_GetListBScript's TAX; from
;        C2Scene_TrigDispatch's TDC), DP=$0000, DB=$00 (low WRAM)
; Exit:  M=1, X=0; A = C2Scene_TrigStWait; X = the ListB offset; Y and
;        C2Tmp_01/$08/$0A as C2Scene_TaskSpawnScript leaves them
; Calls: C2Scene_GetListBScript, C2Scene_TaskSpawnScript.
C2Scene_TrigListB:
    JSR C2Scene_GetListBScript
    LDA.b #bank(!C2Scene_ScriptBuf)
    LDX.w !C2Scene_Unk1B45
    JSR C2Scene_TaskSpawnScript
    LDX.w #0
    STX.w !C2Scene_MemberWords
    STX.w !C2Scene_MemberWords+2
    STX.w !C2Scene_MemberWords+4
    LDX.w !C2Scene_Unk1B32+2
    LDA.l C2Scene_ListBEntry.Flags,X
    AND.b #!C2Scene_ListEntryBit7^$FF
    STA.l C2Scene_ListBEntry.Flags,X
    LDA.b #!C2Scene_TrigStWait
    STA.w !C2Scene_Unk0280
    RTS

; $C2:33D4 — C2Scene_TrigListAB (48 bytes, $33D4–$3403)
; A ListA and a ListB entry: the ListA entry's .Unk02 to
; C2Scene_Unk1B58 (C2Scene_GetListAUnk02), then as C2Scene_TrigListB,
; and C2Scene_Unk1B43 = 0. The task byte C2Scene_TrigListA sets is not
; set here.
; Callers note: none direct (C2Scene_TrigActions).
; Entry: M=1, X=0, B=0 (from C2Scene_TrigDispatch's TDC), DP=$0000,
;        DB=$00 (low WRAM), as C2Scene_TrigListB
; Exit:  as C2Scene_TrigListB
; Calls: C2Scene_GetListAUnk02, C2Scene_GetListBScript,
;   C2Scene_TaskSpawnScript.
C2Scene_TrigListAB:
    JSR C2Scene_GetListAUnk02
    JSR C2Scene_GetListBScript
    LDA.b #bank(!C2Scene_ScriptBuf)
    LDX.w !C2Scene_Unk1B45
    JSR C2Scene_TaskSpawnScript
    LDX.w #0
    STX.w !C2Scene_MemberWords
    STX.w !C2Scene_MemberWords+2
    STX.w !C2Scene_MemberWords+4
    LDX.w !C2Scene_Unk1B32+2
    LDA.l C2Scene_ListBEntry.Flags,X
    AND.b #!C2Scene_ListEntryBit7^$FF
    STA.l C2Scene_ListBEntry.Flags,X
    LDA.b #!C2Scene_TrigStWait
    STA.w !C2Scene_Unk0280
    STZ.w !C2Scene_Unk1B43
    RTS

; ============================================================
; Text window entries ($C2:57DF–$C2:58B1)
; ============================================================
; A text box drawn into a buffer one step at a time, called from other
; banks through BankC2_Entry0003 (TextWin_Init) and BankC2_Entry0009
; (TextWin_Step). Both work on the block at $0200 (DP=$0200), which the
; caller fills first: the field ($C0:20F4-$C0:2121) sets the string
; number, the string table, the output buffer ($7E:F000) and the mode,
; and before each step the character count. The text decoder itself
; (TextWin_StateTable's handlers) is not matched.

org $C257DF
; $C2:57DF — TextWin_Init (68 bytes, $57DF–$5822)
; Starts string TextWin_StrIndex: TextWin_TextPtr = the 16-bit entry
; TextWin_StrIndex of the table at TextWin_StrTable, in the table's bank;
; state 0 (TextWin_State), status TextWin_StatusStart, TextWin_Unk17 = 0,
; TextWin_Unk3D = $00:0200 (use not traced), and the pen X
; (TextWin_PenX) at TextWin_PenXLeft, or 0 when TextWin_Mode is
; TextWin_ModeUnk2 or has bit 7 set.
; Callers (4 sites: 2 JSL, 2 JMP): BankC2_Entry0003 (JMP $C2:0003), BankC2_Entry0006 (JMP $C2:0006)
;   and unmatched (JSL $C2:5695, JSL $C2:69BB).
; Callers note: JMP from BankC2_Entry0003 ($C2:0003) and BankC2_Entry0006
;   ($C2:0006), the cross-bank JSL vectors; JSL (unmatched) from $C2:5695
;   and $C2:69BB.
; Entry: M any, X=0 (16-bit X/Y: the LDX #$0200 and the TAY of the doubled
;        string index need it; P saved), DP any (saved; DP=$0200 here), DB any (all
;        accesses direct page); the block at $0200 filled as above
; Exit:  P and DP restored; A, X (= TextWin_Dp) and Y clobbered; DB
;        unchanged
; No calls.
TextWin_Init:
    PHP
    REP #$20
    PHD
    LDA.w #!TextWin_Dp
    TCD
    LDA.b !TextWin_StrIndex
    AND.w #!Eng_LowByteMask
    ASL A
    TAY
    LDA.b [!TextWin_StrTable],Y
    STA.b !TextWin_TextPtr
    LDA.w #$0000
    SEP #$20
    LDA.b !TextWin_StrTable+2
    STA.b !TextWin_TextPtr+2
    STZ.b !TextWin_State
    LDA.b !TextWin_Mode
    CMP.b #!TextWin_ModeUnk2
    BNE .pen_left
    LDA.b #0
    BRA .set_pen
.pen_left:
    LDA.b #!TextWin_PenXLeft
.set_pen:
    STA.b !TextWin_PenX
    LDA.b !TextWin_Mode
    BPL .start
    STZ.b !TextWin_PenX
.start:
    LDA.b #!TextWin_StatusStart
    STA.b !TextWin_Status
    LDX.w #!TextWin_Dp
    STX.b !TextWin_Unk3D
    LDA.b #0
    STA.b !TextWin_Unk3D+2
    STZ.b !TextWin_Unk17
    PLD
    PLP
    RTL

; $C2:5823 — TextWin_Step (31 bytes, $5823–$5841)
; One step of the text box: TextWin_CheckStatus decides from
; TextWin_Status whether to go on (C=0); if so, the handler of
; TextWin_State in TextWin_StateTable runs. Returns with the high byte
; of A zero.
; Callers (4 sites: 2 JSL, 2 JMP): BankC2_Entry0009 (JMP $C2:0009), BankC2_Entry000C (JMP $C2:000C)
;   and unmatched (JSL $C2:569E, JSL $C2:69C4).
; Callers note: JMP from BankC2_Entry0009 ($C2:0009) and BankC2_Entry000C
;   ($C2:000C), the cross-bank JSL vectors; JSL (unmatched) from $C2:569E
;   and $C2:69C4.
; Entry: any M (P saved), X=0 or 1 (kept for the JSR (abs,X); the
;        16-bit LDA before the SEP leaves B = 0 for the index), DP any
;        (saved; DP=$0200 here), DB as the state handlers need (not
;        traced)
; Exit:  P and DP restored; A = $00 high byte, the old B in the low
;        byte (LDA #0 / XBA); X, Y as the handlers leave them
; Calls: TextWin_CheckStatus, a TextWin_StateTable handler.
TextWin_Step:
    PHP
    REP #$20
    PHD
    LDA.w #!TextWin_Dp
    TCD
    LDA.w #$0000
    SEP #$20
    JSR TextWin_CheckStatus
    BCS .done
    LDA.b !TextWin_State
    ASL A
    TAX
    JSR (TextWin_StateTable,X)
.done:
    LDA.b #0
    XBA
    PLD
    PLP
    RTL

; $C2:5842 — TextWin_StateTable (4 words, $5842–$5849)
; TextWin_Step's handler for each TextWin_State (unmatched). State 0
; reads the next byte of the string at TextWin_TextPtr; $C2:58F6 sets
; state 1 after it points the 24-bit $0237 into a bank-$DE table, which
; state 1 reads from (the meaning of states 2 and 3 is not traced).
TextWin_StateTable:
    dw TextWin_State0
    dw TextWin_State1
    dw TextWin_State2
    dw TextWin_State3

; $C2:584A — TextWin_CheckStatus (7 bytes, $584A–$5850)
; Jumps to TextWin_Status's handler in TextWin_StatusTable, which
; returns C=1 to skip this step's state handler (status 0,
; TextWin_StatusIdle) or C=0 to run it.
; Callers (1 JSR site): TextWin_Step ($C2:5830).
; Entry: M=1, X with B = 0 (TextWin_Step), DP=$0200
; Exit:  the handler's: C=1 skip, C=0 run; M=1
; No calls (a JMP through the table).
TextWin_CheckStatus:
    LDA.b !TextWin_Status
    ASL A
    TAX
    JMP (TextWin_StatusTable,X)

; $C2:5851 — TextWin_StatusTable (33 words, $5851–$5892)
; TextWin_CheckStatus's handler for each TextWin_Status value $00-$20.
TextWin_StatusTable:
    dw TextWin_StatusIdle       ; $00
    dw TextWin_StatusRun        ; $01
    dw TextWin_StatusRun        ; $02
    dw TextWin_StatusRun        ; $03
    dw TextWin_StatusRun        ; $04 (TextWin_StatusStart)
    dw TextWin_StatusPenLeft    ; $05
    dw TextWin_StatusPenIndent  ; $06
    dw TextWin_StatusPenLeft    ; $07
    dw TextWin_StatusPenIndent  ; $08
    dw TextWin_StatusPenLeft    ; $09
    dw TextWin_StatusPenIndent  ; $0A
    dw TextWin_StatusPenLeft    ; $0B
    dw TextWin_StatusPenIndent  ; $0C
    dw TextWin_StatusRun        ; $0D
    dw TextWin_StatusRun        ; $0E
    dw TextWin_StatusRun        ; $0F
    dw TextWin_StatusRun        ; $10 (set by state 0 when TextWin_StepCount runs out)
    dw TextWin_StatusRun        ; $11
    dw TextWin_StatusRun        ; $12
    dw TextWin_StatusRun        ; $13
    dw TextWin_StatusRun        ; $14
    dw TextWin_StatusRun        ; $15
    dw TextWin_StatusRun        ; $16
    dw TextWin_StatusRun        ; $17
    dw TextWin_StatusRun        ; $18
    dw TextWin_StatusRun        ; $19
    dw TextWin_StatusRun        ; $1A
    dw TextWin_StatusRun        ; $1B
    dw TextWin_StatusRun        ; $1C
    dw TextWin_StatusRun        ; $1D
    dw TextWin_StatusRun        ; $1E
    dw TextWin_StatusRun        ; $1F
    dw TextWin_StatusRun        ; $20

; $C2:5893 — TextWin_StatusIdle (2 bytes, $5893–$5894)
; Status 0: nothing to do; C=1 so TextWin_Step skips the state handler.
; Callers note: none direct (TextWin_StatusTable).
; Entry: M=1, DP=$0200 (from TextWin_CheckStatus)
; Exit:  C=1; nothing else changed
TextWin_StatusIdle:
    SEC
    RTS

; $C2:5895 — TextWin_StatusRun (29 bytes, $5895–$58B1, with the
; sub-entries TextWin_StatusPenLeft $C2:5897 and TextWin_StatusPenIndent
; $C2:589B)
; TextWin_StatusRun: C=0, run the state handler. TextWin_StatusPenLeft
; (statuses 5, 7, 9, 11) and TextWin_StatusPenIndent (6, 8, 10, 12) first
; put the pen X back at TextWin_PenXLeft or TextWin_PenXIndent (8 less
; for TextWin_ModeUnk2) and zero TextWin_Unk17, then return C=0 as well.
; What those statuses stand for is not traced (probably new lines, from
; the pen going back to the left).
; Callers note: none direct (TextWin_StatusTable).
; Entry: M=1, DP=$0200 (from TextWin_CheckStatus)
; Exit:  C=0; M=1; the sub-entries change A (the pen X, or
;        TextWin_Mode AND TextWin_ModeMask), TextWin_PenX and
;        TextWin_Unk17
TextWin_StatusRun:
    BRA TextWin_StatusPenIndent_run
TextWin_StatusPenLeft:          ; header: see TextWin_StatusRun
    LDA.b #!TextWin_PenXLeft
    BRA TextWin_StatusPenIndent_set
TextWin_StatusPenIndent:        ; header: see TextWin_StatusRun
    LDA.b #!TextWin_PenXIndent
.set:
    STA.b !TextWin_PenX
    STZ.b !TextWin_Unk17
    LDA.b !TextWin_Mode
    AND.b #!TextWin_ModeMask
    CMP.b #!TextWin_ModeUnk2
    BNE .run
    LDA.b !TextWin_PenX
    SEC
    SBC.b #8
    STA.b !TextWin_PenX
.run:
    CLC
    RTS

; ============================================================
; Text decoder states and control codes ($C2:58B2–$C2:5DC3)
; ============================================================
; TextWin_Step's state handlers (TextWin_StateTable) and the routines
; they use, all on the $0200 block (DP=TextWin_Dp). A string is a run of
; bytes at TextWin_TextPtr:
; - $A0-$FF: a glyph, drawn by TextWin_DrawGlyph (not matched). The
;   digit table TextWin_HexGlyphs gives "0"-"9" as $D4-$DD and "A"-"F"
;   as $A0-$A5, so $A0-$B9 are probably "A"-"Z" and $BA-$D3 "a"-"z"
;   (the ROM names below read as words that way);
; - $21-$9F: a dictionary entry (TextWin_DictPtrs): a sub-string of
;   glyphs drawn in state 1 (TextWin_StateDict);
; - $00-$20: a control code (TextWin_CodeTable): set TextWin_Status, a
;   two-byte glyph, a number (states 2 and 3) or a name (state 1).
; Each glyph drawn takes one of TextWin_StepCount; when it runs out the
; step ends with TextWin_Status = TextWin_StatusStepDone, and the next
; step goes on in the same state. A control code that only sets the
; status ends the step at once.
; Every handler here runs with M=1 and X=0 (16-bit index), DP=$0200,
; and DB with low WRAM at $0000-$1FFF (some stores to the block are
; absolute, e.g. TextWin_Dp+TextWin_SubPtr); B=0 is assumed on entry
; (TextWin_Step loads $0000 before its SEP, and TextWin_DrawGlyph and
; the handlers leave B=0 with LDA #0 / XBA) wherever a byte is
; doubled into a 16-bit index.

; $C2:58B2 — TextWin_State0 (81 bytes, $58B2–$5902, with the sub-entry
; TextWin_State0_Draw at $C2:58BE)
; State 0: reads the next string byte (TextWin_TextPtr + 1):
; - a glyph (TextWin_FirstGlyph or more): TextWin_State0_Draw puts it in
;   TextWin_Glyph (16-bit, with B as the high byte: 0, or the prefix
;   TextWin_CodeWide puts there) and draws it (TextWin_DrawGlyph); then
;   TextWin_StepCount - 1: while not 0 the next byte follows, else
;   TextWin_Status = TextWin_StatusStepDone and return;
; - TextWin_FirstDict-$9F: TextWin_DictCode = the byte; TextWin_SubPtr =
;   entry (byte - $21) of TextWin_DictPtrs in bank $DE; its first byte
;   (the length) to TextWin_SubLeft; state TextWin_StateDict, and on in
;   TextWin_State1;
; - $00-$20: Y = the code, then JMP through TextWin_CodeTable.
; Callers (3 JMP sites): TextWin_State1Resume ($C2:5C39), TextWin_State2Resume ($C2:5C72) and
;   TextWin_State3Resume ($C2:5CBB).
; Callers of TextWin_State0_Draw (1 JMP site): TextWin_CodeWide ($C2:5B11).
; Callers note: none direct (TextWin_StateTable entry 0); TextWin_State0_Draw:
;   JMP from TextWin_CodeWide; TextWin_State0: JMP from
;   TextWin_State1Resume, TextWin_State2Resume and TextWin_State3Resume.
; Entry: M=1, X=0, B=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  M=1, X=0; A, X, Y as the path leaves them; TextWin_TextPtr
;        advanced
; Calls: TextWin_DrawGlyph; continues in TextWin_State1 or a
;   TextWin_CodeTable handler.
TextWin_State0:
    LDA.b [!TextWin_TextPtr]
    REP #$20
    INC.b !TextWin_TextPtr
    SEP #$20
    CMP.b #!TextWin_FirstGlyph
    BCC TextWin_State0_Draw_not_glyph
TextWin_State0_Draw:            ; header: see TextWin_State0
    REP #$20
    STA.b !TextWin_Glyph
    SEP #$20
    JSR TextWin_DrawGlyph
    DEC.b !TextWin_StepCount
    BNE TextWin_State0
    LDA.b #!TextWin_StatusStepDone
    STA.b !TextWin_Status
    RTS
.not_glyph:
    CMP.b #!TextWin_FirstDict
    BCC .control
    STA.b !TextWin_DictCode
    SEC
    SBC.b #!TextWin_FirstDict
    ASL A
    TAX
    REP #$20
    LDA.l !TextWin_DictPtrs,X
    STA.b !TextWin_SubPtr
    LDA.w #$0000
    SEP #$20
    LDA.b #bank(!TextWin_DictPtrs)
    STA.b !TextWin_SubPtr+2
    LDA.b [!TextWin_SubPtr]
    STA.b !TextWin_SubLeft
    REP #$20
    INC.b !TextWin_SubPtr
    SEP #$20
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    JMP TextWin_State1
.control:
    TAY
    ASL A
    TAX
    JMP (TextWin_CodeTable,X)

; $C2:5903 — TextWin_CodeTable (33 words, $5903–$5944)
; TextWin_State0's handler for each control code $00-$20 (Y = the code).
TextWin_CodeTable:
    dw TextWin_CodeSetStatus    ; $00 (status 0: idle, probably the end)
    dw TextWin_CodeWide         ; $01
    dw TextWin_CodeWide         ; $02
    dw TextWin_CodeStatusArg    ; $03
    dw TextWin_CodeSetStatus    ; $04
    dw TextWin_CodeSetStatus    ; $05
    dw TextWin_CodeSetStatus    ; $06
    dw TextWin_CodeSetStatus    ; $07
    dw TextWin_CodeSetStatus    ; $08
    dw TextWin_CodeSetStatus    ; $09
    dw TextWin_CodeSetStatus    ; $0A
    dw TextWin_CodeSetStatus    ; $0B
    dw TextWin_CodeSetStatus    ; $0C
    dw TextWin_CodeNum8         ; $0D
    dw TextWin_CodeNum16        ; $0E
    dw TextWin_CodeNum24        ; $0F
    dw TextWin_CodeNop          ; $10
    dw TextWin_CodeArgName      ; $11
    dw TextWin_CodeExt          ; $12
    dw TextWin_CodeCharName     ; $13
    dw TextWin_CodeCharName     ; $14
    dw TextWin_CodeCharName     ; $15
    dw TextWin_CodeCharName     ; $16
    dw TextWin_CodeCharName     ; $17
    dw TextWin_CodeCharName     ; $18
    dw TextWin_CodeCharName     ; $19
    dw TextWin_CodeName0        ; $1A
    dw TextWin_CodeMemberName   ; $1B
    dw TextWin_CodeMemberName   ; $1C
    dw TextWin_CodeMemberName   ; $1D
    dw TextWin_CodeNadia        ; $1E
    dw TextWin_CodeItemName     ; $1F
    dw TextWin_CodeName7        ; $20

; $C2:5945 — TextWin_CodeStatusArg (10 bytes, $5945–$594E, with the
; sub-entry TextWin_CodeSetStatus at $C2:594F, 4 bytes)
; Code $03: the next string byte to TextWin_Code3Arg, then as
; TextWin_CodeSetStatus. TextWin_CodeSetStatus (codes $00 and $04-$0C):
; TextWin_Status = the code (TextWin_StatusTable: 0 idle, 5-12 the pen
; resets), which ends the step.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP=$0200, DB any (direct page only); Y = the code
; Exit:  M=1; A = the code; TextWin_Status set; X, Y unchanged
TextWin_CodeStatusArg:
    LDA.b [!TextWin_TextPtr]
    STA.b !TextWin_Code3Arg
    REP #$20
    INC.b !TextWin_TextPtr
    SEP #$20
TextWin_CodeSetStatus:          ; header: see TextWin_CodeStatusArg
    TYA
    STA.b !TextWin_Status
    RTS

; $C2:5953 — TextWin_CodeNum8 (50 bytes, $5953–$5984)
; Code $0D: prints the byte at TextWin_Unk3D (which steps on by 1).
; Decimal: TextWin_Dec8's three digits, leading zeros dropped
; (TextWin_TrimZeros3), drawn in state TextWin_StateDec
; (TextWin_StartDec). With TextWin_NumHex set: two hex digit glyphs
; (TextWin_HexByte), drawn in state TextWin_StateHex (TextWin_StartHex).
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State2 or TextWin_State3 (the number's first
;        glyphs drawn this step)
; Calls: TextWin_Dec8, TextWin_TrimZeros3 or TextWin_HexByte; continues
;   in TextWin_StartDec or TextWin_StartHex.
TextWin_CodeNum8:
    LDA.b [!TextWin_Unk3D]
    STA.b !TextWin_NumValue
    REP #$20
    INC.b !TextWin_Unk3D
    SEP #$20
    LDA.b !TextWin_NumHex
    BNE .hex
    JSR TextWin_Dec8
    LDX.b !TextWin_DecDigits
    STX.b !TextWin_Digits
    LDA.b !TextWin_DecDigits+2
    STA.b !TextWin_Digits+2
    JSR TextWin_TrimZeros3
    JMP TextWin_StartDec
.hex:
    REP #$20
    STZ.b !TextWin_HexPos
    LDA.b !TextWin_NumValue
    STA.b !TextWin_HexIn
    JSR TextWin_HexByte
    LDA.w #!TextWin_HexDigitCount8
    SEP #$20
    JMP TextWin_StartHex

; $C2:5985 — TextWin_CodeNum16 (67 bytes, $5985–$59C7)
; Code $0E: as TextWin_CodeNum8 for the 16-bit value at TextWin_Unk3D
; (steps on by 2): five decimal digits (TextWin_Dec16,
; TextWin_TrimZeros5), or four hex digits, high byte first.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State2 or TextWin_State3
; Calls: TextWin_Dec16, TextWin_TrimZeros5 or TextWin_HexByte (twice);
;   continues in TextWin_StartDec or TextWin_StartHex.
TextWin_CodeNum16:
    REP #$20
    LDA.b [!TextWin_Unk3D]
    STA.b !TextWin_NumValue
    INC.b !TextWin_Unk3D
    INC.b !TextWin_Unk3D
    LDA.w #$0000
    SEP #$20
    LDA.b !TextWin_NumHex
    BNE .hex
    JSR TextWin_Dec16
    LDX.b !TextWin_DecDigits
    STX.b !TextWin_Digits
    LDX.b !TextWin_DecDigits+2
    STX.b !TextWin_Digits+2
    LDA.b !TextWin_DecDigits+4
    STA.b !TextWin_Digits+4
    JSR TextWin_TrimZeros5
    JMP TextWin_StartDec
.hex:
    REP #$20
    STZ.b !TextWin_HexPos
    LDA.b !TextWin_NumValue
    XBA
    STA.b !TextWin_HexIn
    JSR TextWin_HexByte
    LDA.b !TextWin_NumValue
    STA.b !TextWin_HexIn
    JSR TextWin_HexByte
    LDA.w #!TextWin_HexDigitCount16
    SEP #$20
    JMP TextWin_StartHex

; $C2:59C8 — TextWin_CodeNum24 (94 bytes, $59C8–$5A25, with the
; sub-entries TextWin_StartDec at $C2:59FC and TextWin_StartHex at
; $C2:5A11, 21 bytes each)
; Code $0F: the 24-bit value at TextWin_Unk3D (steps on by 3) as eight
; decimal digits (TextWin_Dec24, TextWin_TrimZeros8); unlike codes $0D
; and $0E it ignores TextWin_NumHex.
; TextWin_StartDec / TextWin_StartHex: with A = the digit count, set
; TextWin_SubLeft to it and TextWin_SubPtr to TextWin_Digits ($00:0240),
; and go on in state TextWin_StateDec (TextWin_State2) or
; TextWin_StateHex (TextWin_State3) with B=0.
; Callers of TextWin_StartDec (2 JMP sites): TextWin_CodeNum8 ($C2:596F) and TextWin_CodeNum16
;   ($C2:59AA).
; Callers of TextWin_StartHex (2 JMP sites): TextWin_CodeNum8 ($C2:5982) and TextWin_CodeNum16
;   ($C2:59C5).
; Callers note: none direct (TextWin_CodeTable). TextWin_StartDec: JMP from
;   TextWin_CodeNum8 and TextWin_CodeNum16; TextWin_StartHex: the same.
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner);
;        TextWin_StartDec/Hex with A = the count
; Exit:  as TextWin_State2 or TextWin_State3
; Calls: TextWin_Dec24, TextWin_TrimZeros8; continues in TextWin_State2
;   or TextWin_State3.
TextWin_CodeNum24:
    REP #$20
    LDA.b [!TextWin_Unk3D]
    STA.b !TextWin_NumValue
    SEP #$20
    LDY.w #2
    LDA.b [!TextWin_Unk3D],Y
    STA.b !TextWin_NumValue+2
    REP #$20
    LDA.b !TextWin_Unk3D
    CLC
    ADC.w #3
    STA.b !TextWin_Unk3D
    LDA.w #$0000
    SEP #$20
    JSR TextWin_Dec24
    LDX.b !TextWin_DecDigits
    STX.b !TextWin_Digits
    LDX.b !TextWin_DecDigits+2
    STX.b !TextWin_Digits+2
    LDX.b !TextWin_DecDigits+4
    STX.b !TextWin_Digits+4
    LDX.b !TextWin_DecDigits+6
    STX.b !TextWin_Digits+6
    JSR TextWin_TrimZeros8
TextWin_StartDec:               ; header: see TextWin_CodeNum24
    STA.b !TextWin_SubLeft
    LDX.w #!TextWin_Dp+!TextWin_Digits
    STX.b !TextWin_SubPtr
    LDA.b #0
    STA.b !TextWin_SubPtr+2
    LDA.b #!TextWin_StateDec
    STA.b !TextWin_State
    LDA.b #0
    XBA
    JMP TextWin_State2
TextWin_StartHex:               ; header: see TextWin_CodeNum24
    STA.b !TextWin_SubLeft
    LDX.w #!TextWin_Dp+!TextWin_Digits
    STX.b !TextWin_SubPtr
    LDA.b #0
    STA.b !TextWin_SubPtr+2
    LDA.b #!TextWin_StateHex
    STA.b !TextWin_State
    LDA.b #0
    XBA
    JMP TextWin_State3

; $C2:5A26 — TextWin_CodeArgName (38 bytes, $5A26–$5A4B)
; Code $11: the name whose TextWin_CharNamePtrs index is the byte at
; TextWin_Unk3D (which steps on by 1): TextWin_SubPtr at it in bank $7E,
; TextWin_SubLeft = its length (TextWin_CharNameLen), state
; TextWin_StateDict, on in TextWin_State1.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, B=0 (the index is doubled 16-bit), DP=$0200, DB with
;        low WRAM (see the banner)
; Exit:  as TextWin_State1
; Calls: TextWin_CharNameLen; continues in TextWin_State1.
TextWin_CodeArgName:
    LDA.b [!TextWin_Unk3D]
    REP #$20
    INC.b !TextWin_Unk3D
    ASL A
    TAX
    LDA.l TextWin_CharNamePtrs,X
    STA.w !TextWin_Dp+!TextWin_SubPtr
    SEP #$20
    LDA.b #bank(!TextWin_CharNames)
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    JSR TextWin_CharNameLen
    STA.w !TextWin_Dp+!TextWin_SubLeft
    LDA.b #0
    XBA
    JMP TextWin_State1

; $C2:5A4C — TextWin_CodeExt (62 bytes, $5A4C–$5A89)
; Code $12 and the next string byte b: b from TextWin_Code12Dict up is
; dictionary entry TextWin_Code12DictBase + (b - 8) (as TextWin_State0's
; dictionary bytes, also kept in TextWin_DictCode); below that, b
; selects a TextWin_ExtTable handler.
; Quirk, kept: the table has 2 entries but b = 2-7 is not refused; those
; would jump through the code bytes after it.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, B=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State1
; Calls: continues in TextWin_State1 or a TextWin_ExtTable handler.
TextWin_CodeExt:
    LDA.b [!TextWin_TextPtr]
    REP #$20
    INC.b !TextWin_TextPtr
    SEP #$20
    CMP.b #!TextWin_Code12Dict
    BCC .table
    STA.b !TextWin_DictCode
    SEC
    SBC.b #!TextWin_Code12Dict
    REP #$20
    CLC
    ADC.w #!TextWin_Code12DictBase
    ASL A
    TAX
    LDA.l !TextWin_DictPtrs,X
    STA.b !TextWin_SubPtr
    LDA.w #$0000
    SEP #$20
    LDA.b #bank(!TextWin_DictPtrs)
    STA.b !TextWin_SubPtr+2
    LDA.b [!TextWin_SubPtr]
    STA.b !TextWin_SubLeft
    REP #$20
    INC.b !TextWin_SubPtr
    SEP #$20
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    JMP TextWin_State1
.table:
    ASL A
    TAX
    JMP (TextWin_ExtTable,X)

; $C2:5A8A — TextWin_ExtTable (2 words, $5A8A–$5A8D)
; TextWin_CodeExt's handler for b = 0 and 1.
TextWin_ExtTable:
    dw TextWin_ExtTechName      ; 0
    dw TextWin_ExtEnemyName     ; 1

; $C2:5A8E — TextWin_ExtTechName (66 bytes, $5A8E–$5ACF)
; Code $12 $00: name number (the byte at TextWin_Unk3D, which steps on)
; of TextWinRom_TechNames (TextWin_RomNameSize bytes each, by the
; multiplier): TextWin_SubLeft = its length up to the first
; TextWin_NamePad (TextWin_NameLen11); when it starts with
; TextWin_TechIconByte that byte is skipped and the rest counted again
; with TextWin_NameLen10. Then TextWin_StartSubName.
; Callers note: none direct (TextWin_ExtTable).
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State1
; Calls: TextWin_NameLen11, TextWin_NameLen10; continues in
;   TextWin_StartSubName.
TextWin_ExtTechName:
    LDA.b [!TextWin_Unk3D]
    REP #$20
    INC.b !TextWin_Unk3D
    SEP #$20
    STA.l WRMPYA
    LDA.b #!TextWin_RomNameSize
    STA.l WRMPYB
    NOP
    CLC
    REP #$20
    LDA.l RDMPYL
    ADC.w #!TextWinRom_TechNames&$FFFF
    STA.w !TextWin_Dp+!TextWin_SubPtr
    SEP #$20
    LDA.b #bank(!TextWinRom_TechNames)
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    JSR TextWin_NameLen11
    STA.w !TextWin_Dp+!TextWin_SubLeft
    LDA.b [!TextWin_SubPtr]
    CMP.b #!TextWin_TechIconByte
    BNE .counted
    REP #$20
    INC.w !TextWin_Dp+!TextWin_SubPtr
    SEP #$20
    JSR TextWin_NameLen10
    STA.w !TextWin_Dp+!TextWin_SubLeft
.counted:
    BRA TextWin_StartSubName

; $C2:5AD0 — TextWin_ExtEnemyName (54 bytes, $5AD0–$5B05, with the
; sub-entry TextWin_StartSubName at $C2:5AFC)
; Code $12 $01: name number (the byte at TextWin_Unk3D) of
; TextWinRom_EnemyNames, all TextWin_RomNameSize bytes of it (the
; padding is drawn too). TextWin_StartSubName: state TextWin_StateDict,
; B=0, on in TextWin_State1.
; Callers note: none direct (TextWin_ExtTable). TextWin_StartSubName: BRA
;   from TextWin_ExtTechName.
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State1
; Calls: continues in TextWin_State1.
TextWin_ExtEnemyName:
    LDA.b [!TextWin_Unk3D]
    REP #$20
    INC.b !TextWin_Unk3D
    SEP #$20
    STA.l WRMPYA
    LDA.b #!TextWin_RomNameSize
    STA.l WRMPYB
    NOP
    CLC
    REP #$20
    LDA.l RDMPYL
    ADC.w #!TextWinRom_EnemyNames&$FFFF
    STA.w !TextWin_Dp+!TextWin_SubPtr
    SEP #$20
    LDA.b #bank(!TextWinRom_EnemyNames)
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    LDA.b #!TextWin_RomNameSize
    STA.w !TextWin_Dp+!TextWin_SubLeft
TextWin_StartSubName:           ; header: see TextWin_ExtEnemyName
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    LDA.b #0
    XBA
    JMP TextWin_State1

; $C2:5B06 — TextWin_CodeWide (14 bytes, $5B06–$5B13)
; Codes $01 and $02 (TextWin_Wide1/2): the next string byte with the
; code as its high byte is a 16-bit glyph ($01xx or $02xx), drawn by
; TextWin_State0_Draw.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (TextWin_TextPtr is
;        stepped with an absolute INC); Y = the code
; Exit:  as TextWin_State0
; Calls: continues in TextWin_State0_Draw.
TextWin_CodeWide:
    TYA
    XBA
    LDA.b [!TextWin_TextPtr]
    REP #$20
    INC.w !TextWin_Dp+!TextWin_TextPtr
    SEP #$20
    JMP TextWin_State0_Draw

; $C2:5B14 — TextWin_CodeNop (1 byte, $5B14)
; Code $10: nothing; the step ends.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP and DB any (no accesses)
; Exit:  nothing changed
TextWin_CodeNop:
    RTS

; $C2:5B15 — TextWin_CodeCharName (38 bytes, $5B15–$5B3A)
; Codes TextWin_FirstCharName-$19: the name at TextWin_CharNamePtrs
; entry (code - $13), in bank $7E, its length by TextWin_CharNameLen,
; drawn in state TextWin_StateDict.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, B=0, DP=$0200, DB with low WRAM (see the banner);
;        Y = the code
; Exit:  as TextWin_State1
; Calls: TextWin_CharNameLen; continues in TextWin_State1.
TextWin_CodeCharName:
    TYA
    SEC
    SBC.b #!TextWin_FirstCharName
    ASL A
    TAX
    REP #$20
    LDA.l TextWin_CharNamePtrs,X
    STA.w !TextWin_Dp+!TextWin_SubPtr
    SEP #$20
    LDA.b #bank(!TextWin_CharNames)
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    JSR TextWin_CharNameLen
    STA.w !TextWin_Dp+!TextWin_SubLeft
    LDA.b #0
    XBA
    JMP TextWin_State1

; $C2:5B3B — TextWin_CodeName0 (27 bytes, $5B3B–$5B55)
; Code $1A: the first name at TextWin_CharNames (the one
; TextWin_CharNamePtrs entry 0 also points at), as
; TextWin_CodeCharName.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State1
; Calls: TextWin_CharNameLen; continues in TextWin_State1.
TextWin_CodeName0:
    LDX.w #!TextWin_CharNames&$FFFF
    LDA.b #bank(!TextWin_CharNames)
    STX.w !TextWin_Dp+!TextWin_SubPtr
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    JSR TextWin_CharNameLen
    STA.w !TextWin_Dp+!TextWin_SubLeft
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    LDA.b #0
    XBA
    JMP TextWin_State1

; $C2:5B56 — TextWin_CodeNadia (26 bytes, $5B56–$5B6F)
; Code $1E: the TextWin_StrNadiaLen glyphs at TextWin_StrNadia
; ($C2:6146, which spell "Nadia" with $A0 = "A", $BA = "a"), in state
; TextWin_StateDict.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State1
; Calls: continues in TextWin_State1.
TextWin_CodeNadia:
    LDX.w #TextWin_StrNadia
    LDA.b #bank(TextWin_StrNadia)
    STX.w !TextWin_Dp+!TextWin_SubPtr
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    LDA.b #!TextWin_StrNadiaLen
    STA.w !TextWin_Dp+!TextWin_SubLeft
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    LDA.b #0
    XBA
    JMP TextWin_State1

; $C2:5B70 — TextWin_CodeMemberName (43 bytes, $5B70–$5B9A)
; Codes TextWin_FirstMemberName-$1D: the name of the character in party
; position (code - $1B): Party_Members gives the TextWin_CharNamePtrs
; index; then as TextWin_CodeCharName.
; Quirk, kept: an empty position (bit 7 set) is not checked; the 8-bit
; ASL drops bit 7, so the empty value $80 (Menu_PartyEmpty) reads entry
; 0 and prints the first name.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, B=0, DP=$0200, DB with low WRAM (see the banner);
;        Y = the code
; Exit:  as TextWin_State1
; Calls: TextWin_CharNameLen; continues in TextWin_State1.
TextWin_CodeMemberName:
    TYA
    SEC
    SBC.b #!TextWin_FirstMemberName
    TAX
    LDA.l !Party_Members,X
    ASL A
    TAX
    REP #$20
    LDA.l TextWin_CharNamePtrs,X
    STA.w !TextWin_Dp+!TextWin_SubPtr
    SEP #$20
    LDA.b #bank(!TextWin_CharNames)
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    JSR TextWin_CharNameLen
    STA.w !TextWin_Dp+!TextWin_SubLeft
    LDA.b #0
    XBA
    JMP TextWin_State1

; $C2:5B9B — TextWin_CodeItemName (59 bytes, $5B9B–$5BD5)
; Code $1F: the name of item Treasure_ItemId (its low byte) in
; TextWinRom_ItemNames, from its second byte (the first is an icon), up
; to the first TextWin_NamePad (TextWin_NameLen10).
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State1
; Calls: TextWin_NameLen10; continues in TextWin_State1.
TextWin_CodeItemName:
    REP #$20
    LDA.l !Treasure_ItemId
    AND.w #!Eng_LowByteMask
    SEP #$20
    STA.l WRMPYA
    LDA.b #!TextWin_RomNameSize
    STA.l WRMPYB
    NOP
    CLC
    REP #$20
    LDA.l RDMPYL
    ADC.w #!TextWinRom_ItemNames&$FFFF
    INC A                       ; past the icon byte
    STA.w !TextWin_Dp+!TextWin_SubPtr
    SEP #$20
    LDA.b #bank(!TextWinRom_ItemNames)
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    JSR TextWin_NameLen10
    STA.w !TextWin_Dp+!TextWin_SubLeft
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    LDA.b #0
    XBA
    JMP TextWin_State1

; $C2:5BD6 — TextWin_CodeName7 (31 bytes, $5BD6–$5BF4)
; Code $20: the eighth name at TextWin_CharNames ($7E:2C4D, after the
; seven TextWin_CharNamePtrs points at), as TextWin_CodeCharName.
; Callers note: none direct (TextWin_CodeTable).
; Entry: M=1, X=0, DP=$0200, DB with low WRAM (see the banner)
; Exit:  as TextWin_State1
; Calls: TextWin_CharNameLen; continues in TextWin_State1.
TextWin_CodeName7:
    REP #$20
    LDA.w #(!TextWin_CharNames+(7*!TextWin_CharNameSize))&$FFFF
    STA.w !TextWin_Dp+!TextWin_SubPtr
    SEP #$20
    LDA.b #bank(!TextWin_CharNames)
    STA.w !TextWin_Dp+!TextWin_SubPtr+2
    LDA.b #!TextWin_StateDict
    STA.b !TextWin_State
    JSR TextWin_CharNameLen
    STA.w !TextWin_Dp+!TextWin_SubLeft
    LDA.b #0
    XBA
    JMP TextWin_State1

; $C2:5BF5 — TextWin_State1 (51 bytes, $5BF5–$5C27, with the exits
; TextWin_State1End $C2:5C30, TextWin_State1Pause $C2:5C32,
; TextWin_State1Resume $C2:5C37 and TextWin_State1Loop $C2:5C3C)
; State TextWin_StateDict: draws the next glyph of the sub-string at
; TextWin_SubPtr (a TextWin_Wide1/2 byte makes the next byte the low
; byte of a 16-bit glyph). Then TextWin_SubLeft - 1 and
; TextWin_StepCount - 1 pick the exit (TextWin_State1Next):
; - both at 0, TextWin_State1End: state 0, then as TextWin_State1Pause;
; - steps at 0, TextWin_State1Pause: TextWin_Status =
;   TextWin_StatusStepDone, return (the next step goes on here);
; - sub-string done, TextWin_State1Resume: state 0, on with the string
;   (TextWin_State0);
; - neither, TextWin_State1Loop: the next glyph.
; Quirk, kept: a TextWin_SubLeft of 0 is not special-cased (the DEC
; makes it $FF, so 256 glyphs are drawn); and on the two-byte path the
; REP #$20 is done twice.
; Callers (10 JMP sites): TextWin_State0_Draw ($C2:58FA), TextWin_CodeArgName ($C2:5A49),
;   TextWin_CodeExt ($C2:5A82), TextWin_StartSubName ($C2:5B03), TextWin_CodeCharName ($C2:5B38),
;   TextWin_CodeName0 ($C2:5B53), TextWin_CodeNadia ($C2:5B6D), TextWin_CodeMemberName ($C2:5B98),
;   TextWin_CodeItemName ($C2:5BD3) and TextWin_CodeName7 ($C2:5BF2).
; Callers note: TextWin_StateTable entry 1; 10 JMP sites: TextWin_State0
;   ($C2:58FA), TextWin_CodeArgName, TextWin_CodeExt,
;   TextWin_StartSubName, TextWin_CodeCharName, TextWin_CodeName0,
;   TextWin_CodeNadia, TextWin_CodeMemberName, TextWin_CodeItemName and
;   TextWin_CodeName7.
; Entry: M=1, X=0, DP=$0200, DB as TextWin_DrawGlyph needs (not traced;
;        this code is direct page only); B = 0 for a one-byte glyph (its
;        high byte)
; Exit:  M=1, X=0; A, X as the exit leaves them
; Calls: TextWin_DrawGlyph; exits through TextWin_State1Next.
TextWin_State1:
    LDA.b [!TextWin_SubPtr]
    REP #$20
    INC.b !TextWin_SubPtr
    SEP #$20
    CMP.b #!TextWin_Wide1
    BEQ .wide
    CMP.b #!TextWin_Wide2
    BNE .draw
.wide:
    XBA
    LDA.b [!TextWin_SubPtr]
    REP #$20
    INC.b !TextWin_SubPtr
.draw:
    REP #$20
    STA.b !TextWin_Glyph
    SEP #$20
    JSR TextWin_DrawGlyph
    LDA.b #0
    DEC.b !TextWin_SubLeft
    BEQ .sub_done
    ORA.b #1
.sub_done:
    DEC.b !TextWin_StepCount
    BEQ .steps_done
    ORA.b #2
.steps_done:
    ASL A
    TAX
    JMP (TextWin_State1Next,X)

; $C2:5C28 — TextWin_State1Next (4 words, $5C28–$5C2F)
; TextWin_State1's exit by (sub-string left) + 2 * (steps left).
TextWin_State1Next:
    dw TextWin_State1End        ; 0
    dw TextWin_State1Pause      ; 1: sub-string left
    dw TextWin_State1Resume     ; 2: steps left
    dw TextWin_State1Loop       ; 3: both

TextWin_State1End:              ; header: see TextWin_State1
    STZ.b !TextWin_State
TextWin_State1Pause:            ; header: see TextWin_State1
    LDA.b #!TextWin_StatusStepDone
    STA.b !TextWin_Status
    RTS
TextWin_State1Resume:           ; header: see TextWin_State1
    STZ.b !TextWin_State
    JMP TextWin_State0
TextWin_State1Loop:             ; header: see TextWin_State1
    BRA TextWin_State1

; $C2:5C3E — TextWin_State2 (35 bytes, $5C3E–$5C60, with the exits
; TextWin_State2End $C2:5C69, TextWin_State2Pause $C2:5C6B,
; TextWin_State2Resume $C2:5C70 and TextWin_State2Loop $C2:5C75)
; State TextWin_StateDec: draws the next decimal digit at TextWin_SubPtr
; as glyph TextWin_DigitGlyph0 + the digit, then exits as TextWin_State1
; does (TextWin_State2Next).
; Callers (1 JMP site): TextWin_StartDec ($C2:5A0E).
; Callers note: none direct (TextWin_StateTable entry 2); JMP from
;   TextWin_StartDec.
; Entry: M=1, X=0, B=0 (the glyph's high byte), DP=$0200, DB as
;        TextWin_DrawGlyph needs (not traced)
; Exit:  M=1, X=0; A, X as the exit leaves them
; Calls: TextWin_DrawGlyph; exits through TextWin_State2Next.
TextWin_State2:
    LDA.b [!TextWin_SubPtr]
    CLC
    ADC.b #!TextWin_DigitGlyph0
    REP #$20
    STA.b !TextWin_Glyph
    INC.b !TextWin_SubPtr
    SEP #$20
    JSR TextWin_DrawGlyph
    LDA.b #0
    DEC.b !TextWin_SubLeft
    BEQ .sub_done
    ORA.b #1
.sub_done:
    DEC.b !TextWin_StepCount
    BEQ .steps_done
    ORA.b #2
.steps_done:
    ASL A
    TAX
    JMP (TextWin_State2Next,X)

; $C2:5C61 — TextWin_State2Next (4 words, $5C61–$5C68)
; TextWin_State2's exit, as TextWin_State1Next.
TextWin_State2Next:
    dw TextWin_State2End        ; 0
    dw TextWin_State2Pause      ; 1: digits left
    dw TextWin_State2Resume     ; 2: steps left
    dw TextWin_State2Loop       ; 3: both

TextWin_State2End:              ; header: see TextWin_State2
    STZ.b !TextWin_State
TextWin_State2Pause:            ; header: see TextWin_State2
    LDA.b #!TextWin_StatusStepDone
    STA.b !TextWin_Status
    RTS
TextWin_State2Resume:           ; header: see TextWin_State2
    STZ.b !TextWin_State
    JMP TextWin_State0
TextWin_State2Loop:             ; header: see TextWin_State2
    BRA TextWin_State2

; $C2:5C77 — TextWin_State3 (51 bytes, $5C77–$5CA9, with the exits
; TextWin_State3End $C2:5CB2, TextWin_State3Pause $C2:5CB4,
; TextWin_State3Resume $C2:5CB9 and TextWin_State3Loop $C2:5CBE)
; State TextWin_StateHex: the same code as TextWin_State1 (glyph bytes,
; with the two-byte prefixes) with its own exits (TextWin_State3Next);
; the hex digits TextWin_HexByte stored are drawn this way.
; Quirks, kept: as TextWin_State1's.
; Callers (1 JMP site): TextWin_StartHex ($C2:5A23).
; Callers note: none direct (TextWin_StateTable entry 3); JMP from
;   TextWin_StartHex.
; Entry: M=1, X=0, B=0 for a one-byte glyph, DP=$0200, DB as
;        TextWin_DrawGlyph needs (not traced)
; Exit:  M=1, X=0; A, X as the exit leaves them
; Calls: TextWin_DrawGlyph; exits through TextWin_State3Next.
TextWin_State3:
    LDA.b [!TextWin_SubPtr]
    REP #$20
    INC.b !TextWin_SubPtr
    SEP #$20
    CMP.b #!TextWin_Wide1
    BEQ .wide
    CMP.b #!TextWin_Wide2
    BNE .draw
.wide:
    XBA
    LDA.b [!TextWin_SubPtr]
    REP #$20
    INC.b !TextWin_SubPtr
.draw:
    REP #$20
    STA.b !TextWin_Glyph
    SEP #$20
    JSR TextWin_DrawGlyph
    LDA.b #0
    DEC.b !TextWin_SubLeft
    BEQ .sub_done
    ORA.b #1
.sub_done:
    DEC.b !TextWin_StepCount
    BEQ .steps_done
    ORA.b #2
.steps_done:
    ASL A
    TAX
    JMP (TextWin_State3Next,X)

; $C2:5CAA — TextWin_State3Next (4 words, $5CAA–$5CB1)
; TextWin_State3's exit, as TextWin_State1Next.
TextWin_State3Next:
    dw TextWin_State3End        ; 0
    dw TextWin_State3Pause      ; 1: glyphs left
    dw TextWin_State3Resume     ; 2: steps left
    dw TextWin_State3Loop       ; 3: both

TextWin_State3End:              ; header: see TextWin_State3
    STZ.b !TextWin_State
TextWin_State3Pause:            ; header: see TextWin_State3
    LDA.b #!TextWin_StatusStepDone
    STA.b !TextWin_Status
    RTS
TextWin_State3Resume:           ; header: see TextWin_State3
    STZ.b !TextWin_State
    JMP TextWin_State0
TextWin_State3Loop:             ; header: see TextWin_State3
    BRA TextWin_State3

; $C2:5CC0 — TextWin_HexByte (67 bytes, $5CC0–$5D02)
; Appends the two hex digit glyphs of TextWin_HexIn (high digit first,
; from TextWin_HexGlyphs) to TextWin_Digits at TextWin_HexPos, which
; goes up by one per glyph (by two for a TextWin_WideGlyphMin or higher
; entry, stored prefix first; the table has none).
; Note: each store is 16-bit, so the byte after the glyph is zeroed too.
; Callers (3 JSR sites): TextWin_CodeNum8 ($C2:597A) and TextWin_CodeNum16 ($C2:59B6, $C2:59BD).
; Entry: M any (REP #$20 here), X=0, DP=$0200, DB any (long table)
; Exit:  M=0, X=0; A = the low digit's glyph, X = TextWin_HexPos before
;        the last store; TextWin_HexPos advanced; Y unchanged
; No calls.
TextWin_HexByte:
    REP #$20
    LDA.b !TextWin_HexIn
    AND.w #!TextWin_NibbleHi
    LSR A
    LSR A
    LSR A                       ; the high digit * 2
    TAX
    LDA.l TextWin_HexGlyphs,X
    LDX.b !TextWin_HexPos
    CMP.w #!TextWin_WideGlyphMin
    BCC .narrow_hi
    XBA
    STA.b !TextWin_Digits,X
    INC.b !TextWin_HexPos
    INC.b !TextWin_HexPos
    BRA .low
.narrow_hi:
    STA.b !TextWin_Digits,X
    INC.b !TextWin_HexPos
.low:
    LDA.b !TextWin_HexIn
    AND.w #!TextWin_NibbleLo
    ASL A
    TAX
    LDA.l TextWin_HexGlyphs,X
    LDX.b !TextWin_HexPos
    CMP.w #!TextWin_WideGlyphMin
    BCC .narrow_lo
    XBA
    STA.b !TextWin_Digits,X
    INC.b !TextWin_HexPos
    INC.b !TextWin_HexPos
    BRA .done
.narrow_lo:
    STA.b !TextWin_Digits,X
    INC.b !TextWin_HexPos
.done:
    RTS

; $C2:5D03 — TextWin_HexGlyphs (16 words, $5D03–$5D22)
; The glyph of each hex digit 0-F (TextWin_HexByte): "0"-"9" are
; $D4-$DD, "A"-"F" $A0-$A5.
TextWin_HexGlyphs:
    dw $00D4,$00D5,$00D6,$00D7,$00D8,$00D9,$00DA,$00DB
    dw $00DC,$00DD,$00A0,$00A1,$00A2,$00A3,$00A4,$00A5

; $C2:5D23 — TextWin_NameLen10 (17 bytes, $5D23–$5D33)
; A = the number of bytes at TextWin_SubPtr before the first
; TextWin_NamePad, at most 10.
; Callers (2 JSR sites): TextWin_ExtTechName ($C2:5AC8) and TextWin_CodeItemName ($C2:5BC6).
; Entry: M=1, X=0, DP=$0200, DB any
; Exit:  M=1, X=0; A = Y = the count; X unchanged
; No calls.
TextWin_NameLen10:
    LDY.w #0
.next:
    LDA.b [!TextWin_SubPtr],Y
    CMP.b #!TextWin_NamePad
    BEQ .done
    INY
    CPY.w #!TextWin_RomNameSize-1
    BCC .next
.done:
    TYA
    RTS

; $C2:5D34 — TextWin_NameLen11 (17 bytes, $5D34–$5D44)
; As TextWin_NameLen10, at most 11 (a whole TextWinRom name).
; Callers (1 JSR site): TextWin_ExtTechName ($C2:5AB5).
; Entry: M=1, X=0, DP=$0200, DB any
; Exit:  M=1, X=0; A = Y = the count; X unchanged
; No calls.
TextWin_NameLen11:
    LDY.w #0
.next:
    LDA.b [!TextWin_SubPtr],Y
    CMP.b #!TextWin_NamePad
    BEQ .done
    INY
    CPY.w #!TextWin_RomNameSize
    BCC .next
.done:
    TYA
    RTS

; $C2:5D45 — TextWin_CharNameLen (17 bytes, $5D45–$5D55)
; A = the number of bytes at TextWin_SubPtr before the first 0, at most
; TextWin_CharNameMax.
; Callers (5 JSR sites): TextWin_CodeArgName ($C2:5A40), TextWin_CodeCharName ($C2:5B2F),
;   TextWin_CodeName0 ($C2:5B46), TextWin_CodeMemberName ($C2:5B8F) and TextWin_CodeName7
;   ($C2:5BE9).
; Entry: M=1, X=0, DP=$0200, DB any
; Exit:  M=1, X=0; A = Y = the count; X unchanged
; No calls.
TextWin_CharNameLen:
    LDY.w #0
.next:
    LDA.b [!TextWin_SubPtr],Y
    CMP.b #0
    BEQ .done
    INY
    CPY.w #!TextWin_CharNameMax
    BCC .next
.done:
    TYA
    RTS

; $C2:5D56 — TextWin_TrimZeros8 (110 bytes, $5D56–$5DC3, with the
; sub-entries TextWin_TrimZeros5 at $C2:5D91 and TextWin_TrimZeros3 at
; $C2:5DAD)
; Drops the leading zero digits of the 8 (5, 3) digits at
; TextWin_Digits, keeping at least one: while the first is 0, shifts
; the rest down one byte. A = the digits left. The moves copy only the
; digits left; the old last digit byte is not cleared and stays stale.
; Callers (1 JSR site): TextWin_CodeNum24 ($C2:59F9).
; Callers of TextWin_TrimZeros5 (1 JSR site): TextWin_CodeNum16 ($C2:59A7).
; Callers of TextWin_TrimZeros3 (1 JSR site): TextWin_CodeNum8 ($C2:596C).
; Entry: M any for TextWin_TrimZeros8 (SEP #$20 here), M=1 for the
;        sub-entries; X=0, DP=$0200, DB any (direct page only)
; Exit:  M=1, X=0; A = Y = the digit count; X = the last word moved
;        (unchanged when none was)
; No calls.
TextWin_TrimZeros8:
    SEP #$20
    LDY.w #8
    LDA.b !TextWin_Digits
    BNE TextWin_TrimZeros3_done
    LDA.b !TextWin_Digits+1
    STA.b !TextWin_Digits
    LDX.b !TextWin_Digits+2
    STX.b !TextWin_Digits+1
    LDX.b !TextWin_Digits+4
    STX.b !TextWin_Digits+3
    LDX.b !TextWin_Digits+6
    STX.b !TextWin_Digits+5
    DEY
    LDA.b !TextWin_Digits
    BNE TextWin_TrimZeros3_done
    LDX.b !TextWin_Digits+1
    STX.b !TextWin_Digits
    LDX.b !TextWin_Digits+3
    STX.b !TextWin_Digits+2
    LDX.b !TextWin_Digits+5
    STX.b !TextWin_Digits+4
    DEY
    LDA.b !TextWin_Digits
    BNE TextWin_TrimZeros3_done
    LDA.b !TextWin_Digits+1
    STA.b !TextWin_Digits
    LDX.b !TextWin_Digits+2
    STX.b !TextWin_Digits+1
    LDX.b !TextWin_Digits+4
    STX.b !TextWin_Digits+3
TextWin_TrimZeros5:             ; header: see TextWin_TrimZeros8
    LDY.w #5
    LDA.b !TextWin_Digits
    BNE TextWin_TrimZeros3_done
    LDX.b !TextWin_Digits+1
    STX.b !TextWin_Digits
    LDX.b !TextWin_Digits+3
    STX.b !TextWin_Digits+2
    DEY
    LDA.b !TextWin_Digits
    BNE TextWin_TrimZeros3_done
    LDA.b !TextWin_Digits+1
    STA.b !TextWin_Digits
    LDX.b !TextWin_Digits+2
    STX.b !TextWin_Digits+1
TextWin_TrimZeros3:             ; header: see TextWin_TrimZeros8
    LDY.w #3
    LDA.b !TextWin_Digits
    BNE .done
    LDX.b !TextWin_Digits+1
    STX.b !TextWin_Digits
    DEY
    LDA.b !TextWin_Digits
    BNE .done
    LDA.b !TextWin_Digits+1
    STA.b !TextWin_Digits
    DEY
.done:
    TYA
    RTS

; ============================================================
; Tile trigger list readers ($C2:6263–$C2:6290)
; ============================================================
; Read the entries C2Scene_FindTrigEntries found (offsets in the three
; C2Scene_Unk1B32 words) for the C2Scene_TrigActions handlers.

org $C26263
; $C2:6263 — C2Scene_GetListAUnk02 (11 bytes, $6263–$626D)
; C2Scene_Unk1B58 = .Unk02 of the ListA entry at offset C2Scene_Unk1B32.
; Callers (2 JSR sites): C2Scene_TrigListA ($C2:3396) and C2Scene_TrigListAB ($C2:33D4).
; Entry: M=1, X=0, DP any, DB=$00 (C2Scene_Unk1B32 and C2Scene_Unk1B58
;        absolute)
; Exit:  M=1, X=0; A = the byte, X = the offset; Y unchanged
; No calls.
C2Scene_GetListAUnk02:
    LDX.w !C2Scene_Unk1B32
    LDA.l C2Scene_ListAEntry.Unk02,X
    STA.w !C2Scene_Unk1B58
    RTS

; $C2:626E — C2Scene_GetListBScript (24 bytes, $626E–$6285)
; C2Scene_Unk1B45 = the C2Scene_ListD word (a script address in bank
; $7F) picked by .Script of the ListB entry at offset C2Scene_Unk1B32+2.
; Callers (2 JSR sites): C2Scene_TrigListB ($C2:33AA) and C2Scene_TrigListAB ($C2:33D7).
; Entry: M=1, X=0, B=0 (the 16-bit TAX of the doubled index), DP any,
;        DB=$00 (low WRAM absolute)
; Exit:  M=1, X=0; A = the address's high byte, X = the index * 2; Y
;        unchanged
; No calls.
C2Scene_GetListBScript:
    LDX.w !C2Scene_Unk1B32+2
    LDA.l C2Scene_ListBEntry.Script,X
    ASL A
    TAX
    LDA.l !C2Scene_ListD,X
    STA.w !C2Scene_Unk1B45
    LDA.l !C2Scene_ListD+1,X
    STA.w !C2Scene_Unk1B45+1
    RTS

; $C2:6286 — C2Scene_GetListCUnk03 (11 bytes, $6286–$6290)
; C2Scene_Unk1B47 = the byte 3 past the start of the ListC entry at
; offset C2Scene_Unk1B32+4. ListC entries are 3 bytes
; (C2Scene_ListBCEntrySize), so this is the first byte of the next
; entry (or the byte after the list); kept as it is, why is not traced.
; Callers (1 JSR site): C2Scene_TrigListC ($C2:33A1).
; Entry: M=1, X=0, DP any, DB=$00 (low WRAM absolute)
; Exit:  M=1, X=0; A = the byte, X = the offset; Y unchanged
; No calls.
C2Scene_GetListCUnk03:
    LDX.w !C2Scene_Unk1B32+4
    LDA.l !C2Scene_ListC+!C2Scene_ListBCEntrySize,X
    STA.w !C2Scene_Unk1B47
    RTS

; ============================================================
; Scene sound zone lookup ($C2:62ED–$C2:631E)
; ============================================================

org $C262ED
; $C2:62ED — C2Scene_GetSoundZone (50 bytes, $62ED–$631E)
; Returns the 4-bit zone of metatile C2Scene_ZoneCol, C2Scene_ZoneRow
; from the zone map at the start of C2Scene_Unk7200 (bank $7E): byte
; row * 48 + column / 2 (the row product with the hardware multiplier),
; its high nibble for an even column, its low nibble for an odd one.
; The pointer is built in C2Tmp_10-$12. (That this pack is a zone map is
; inferred from these readers: its $C00 bytes are 64 rows of 48.)
; Callers (3 JSR sites): C2Scene_ZoneSoundAtEntry ($C2:2F21), C2Scene_ZoneSoundAtView ($C2:2F66) and
;   C2Scene_ZoneSoundWatch ($C2:3001).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Tmp_00/$01, $10-$12),
;        DB=$00 (WRMPYA/B and RDMPYL, absolute)
; Exit:  M=1, X=0; A = the zone (0-15), B = 0; Y = column / 2; X
;        unchanged; C2Tmp_00 = column / 2 (shifted); C2Tmp_10-$12 = the
;        byte's row pointer
; No calls.
!C2Scene_ZonePtr = !C2Tmp_10            ; 24-bit: the row in the zone map
C2Scene_GetSoundZone:
    SEP #$20
    LDA.b #bank(!C2Scene_Unk7200)
    STA.b !C2Scene_ZonePtr+2
    LDA.b !C2Scene_ZoneRow
    STA.w WRMPYA
    LDA.b #!C2Scene_ZoneRowBytes
    STA.w WRMPYB
    REP #$20
    CLC
    LDA.w #!C2Scene_Unk7200&$FFFF
    ADC.w RDMPYL
    STA.b !C2Scene_ZonePtr
    LDA.b !C2Scene_ZoneCol
    AND.w #!Eng_LowByteMask
    LSR A
    TAY
    SEP #$20
    LDA.b [!C2Scene_ZonePtr],Y
    LSR.b !C2Scene_ZoneCol
    BCS .odd
    LSR A
    LSR A
    LSR A
    LSR A
    RTS
.odd:
    AND.b #!C2Scene_ZoneMask
    RTS

; ============================================================
; Scene extra-graphics loaders ($C2:7B5A–$C2:7BC3)
; ============================================================
; Three fixed-entry pack loaders used only by C2Scene_LoadLocExtraGfx.

org $C27B5A
; $C2:7B5A — C2Scene_LoadExtraObjPack (37 bytes, $7B5A–$7B7E)
; Unpacks entry C2Scene_ExtraObjPack of C2SceneRom_ObjPacks into
; C2Scene_DecompBuf.
; Callers (4 JSR sites): C2Scene_LoadLocExtraGfx ($C2:2DB1, $C2:2DCD, $C2:2DF3, $C2:2E0F).
; Entry: M=1, X=0, DP any, DB=$00 (absolute stores to Menu_Decomp*)
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadExtraObjPack:
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    LDX.w #!C2Scene_ExtraObjPack*!C2Scene_PackEntrySize
    REP #$20
    LDA.l !C2SceneRom_ObjPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_ObjPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTS

; $C2:7B7F — C2Scene_LoadExtraPalette (32 bytes, $7B7F–$7B9E)
; Unpacks entry C2Scene_ExtraPalPack of C2SceneRom_PalettePacks to A:X
; (C2Scene_LoadLocExtraGfx passes bank $00 and an address inside
; C2Scene_PaletteBuf).
; Callers (3 JSR sites): C2Scene_LoadLocExtraGfx ($C2:2DC7, $C2:2DED, $C2:2E09).
; Entry: M=1 with A = the destination bank, X=0 with X = the destination,
;        DP any, DB=$00
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadExtraPalette:
    STX.w !Menu_DecompDest
    STA.w !Menu_DecompDestBank
    LDX.w #!C2Scene_ExtraPalPack*!C2Scene_PackEntrySize
    REP #$20
    LDA.l !C2SceneRom_PalettePacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_PalettePacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTS

; $C2:7B9F — C2Scene_LoadUnkC600 (37 bytes, $7B9F–$7BC3)
; Unpacks entry C2Scene_UnkC600Pack of C2SceneRom_PalettePacks into
; C2Scene_UnkC600 ($7E:C600); what it holds is not traced.
; Callers (4 JMP sites): C2Scene_LoadLocExtraGfx ($C2:2DCA, $C2:2DF0, $C2:2E0C, $C2:2E20).
; Entry: M=1, X=0, DP any, DB=$00
; Exit:  M=1, X=0; A, X, Y clobbered; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_LoadUnkC600:
    LDA.b #bank(!C2Scene_UnkC600)
    STA.w !Menu_DecompDestBank
    LDX.w #!C2Scene_UnkC600&$FFFF
    STX.w !Menu_DecompDest
    LDX.w #!C2Scene_UnkC600Pack*!C2Scene_PackEntrySize
    REP #$20
    LDA.l !C2SceneRom_PalettePacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_PalettePacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTS

; ============================================================
; Menu bank vectors ($C2:8000–$C2:800D)
; ============================================================

org $C28000
; $C2:8000 — BankC2_Entry8000 (6 bytes with BankC2_Entry8002 and
; BankC2_Entry8004, $8000–$8005)
; Three BRAs, the bank's second set of fixed entry points, each reached
; by JSL from other banks:
;   $8000 BankC2_Entry8000 → BankC2_MenuEntry (A = an argument chosen by
;         the caller; the menu side is not matched)
;   $8002 BankC2_Entry8002 → BankC2_ReadPadLong: the joypad reader
;   $8004 BankC2_Entry8004 → BankC2_CommandLong (A = a command)
; Callers (4 JSL sites): Field_SceneChangeTick ($C0:0D18), Field_PauseAndMenuInput ($C0:1960),
;   Field_RunBankC2Mode5 ($C0:19CE) and C2Scene_Mode5 ($C2:2552).
; Callers of BankC2_Entry8002 (5 JSL sites): NmiHandler ($C0:EC15), C2Scene_NmiHandler ($C2:031B)
;   and unmatched ($C1:EE27, $CD:091A, $CD:09C6).
; Callers of BankC2_Entry8004 (15 JSL sites): GameLoop ($C0:0059), Scene_PostLoadInit ($C0:56CF) and
;   unmatched ($C0:3807, $C0:389B, $C0:38CC, $C0:38E1, $C0:38F6, $C0:392B, $C0:39DA, $C0:3A7C,
;   $C0:3E61, $C0:3E67, $FF:FB84, $FF:FB92, $FF:FB98).
; Entry/Exit: those of the routine each vector reaches.
BankC2_Entry8000:
    BRA BankC2_MenuEntry
BankC2_Entry8002:               ; header: see BankC2_Entry8000
    BRA BankC2_ReadPadLong
BankC2_Entry8004:               ; header: see BankC2_Entry8000
    BRA BankC2_CommandLong

; $C2:8006 — BankC2_ReadPadLong (4 bytes, $8006–$8009)
; Menu_ReadPad as a long call (the BankC2_Entry8002 vector).
; Callers note: none direct (BRA from BankC2_Entry8002).
; Entry/Exit: as Menu_ReadPad (everything preserved), returning with RTL
; Calls: Menu_ReadPad.
BankC2_ReadPadLong:
    JSR Menu_ReadPad
    RTL

; $C2:800A — BankC2_CommandLong (4 bytes, $800A–$800D)
; Menu_Unk8C36 as a long call (the BankC2_Entry8004 vector).
; Callers note: none direct (BRA from BankC2_Entry8004).
; Entry/Exit: as Menu_Unk8C36 (not matched), returning with RTL
; Calls: Menu_Unk8C36.
BankC2_CommandLong:
    JSR Menu_Unk8C36
    RTL

; ============================================================
; Joypad reader and play-time clock ($C2:84D2–$C2:85D5)
; ============================================================

org $C284D2
; $C2:84D2 — Menu_ReadPad (26 bytes, $84D2–$84EB)
; The pad reader behind BankC2_Entry8002, run once a frame by the scene
; NMI and by other banks: reads joypad 1 (Menu_PollPad), maps it through
; the button configuration (Menu_MapButtons) and advances the play-time
; clock (Menu_TickPlayTime). Saves and restores everything it touches.
; Callers (1 JSR site): BankC2_ReadPadLong ($C2:8006).
; Entry: any M, X, DP, DB (all saved; the callees set their own)
; Exit:  A, X, Y, P, DP and DB as they were; the pad bytes $00F0-$00FE
;        and Menu_PlayTime updated. (When L+R+Select+Start are held,
;        Menu_PollPad jumps to Reset instead and never returns.)
; Calls: Menu_PollPad, Menu_MapButtons, Menu_TickPlayTime.
Menu_ReadPad:
    PHB
    PHD
    PHX
    PHY
    PHP
    REP #$30
    PHA
    PHP
    JSR Menu_PollPad
    JSR Menu_MapButtons
    JSR Menu_TickPlayTime
    PLP
    PLA
    PLP
    PLY
    PLX
    PLD
    PLB
    RTS

; $C2:84EC — Menu_PollPad (89 bytes, $84EC–$8544)
; Waits for the auto-joypad read to finish and rebuilds the pad words
; from JOY1 (layout as Pad_Pressed: low byte A X L R B Y Select Start,
; high byte Up Down Left Right in bits 3-0):
; - Menu_PadPrevHeld = the last Menu_PadHeld, Menu_PadHeld = now;
; - with exactly L+R+Select+Start held (JOY1 = Menu_PadSoftReset), JML
;   Reset: the soft reset;
; - Pad_Pressed and Menu_PadRepeat = the buttons newly pressed;
; - auto-repeat: while any button stays held, Menu_PadRepeatTimer counts
;   down; at 0 the held buttons are added to Menu_PadRepeat and the timer
;   reloads from Menu_PadRepeatDelay, as it does whenever nothing is
;   held.
; Callers (2 JSR sites): Menu_ReadPad ($C2:84DB) and unmatched ($C2:8487).
; Callers note (2 JSR sites): Menu_ReadPad ($C2:84DB); unmatched: $C2:8487
;   (the menu's own NMI code).
; Entry: M any (SEP #$20 here), X=0 (16-bit X for the held word copy),
;        DP and DB any (set to $0000 and $00 here, not restored)
; Exit:  M=0, X=1; DP=$0000, DB=$00; A = the held buttons that were
;        also held last frame, X = Menu_PadRepeatTimer; Y unchanged
; No calls (JML Reset on the soft-reset buttons).
Menu_PollPad:
    PEA.w !Menu_Dp
    PLD
    PEA.w !Bank00<<8|!Bank00
    PLB
    PLB
    SEP #$20
    LDA.b #!Menu_PadAutoReadBusy
.wait:
    BIT.w HVBJOY
    BNE .wait
    LDX.b !Menu_PadHeld
    STX.b !Menu_PadPrevHeld
    LDA.w JOY1L
    AND.b #!Menu_PadJoy1LMask       ; A X L R in bits 7-4
    STA.b !Menu_PadHeld
    LDA.w JOY1H
    AND.b #!Pad_DpadMask            ; Up Down Left Right in bits 3-0
    STA.b !Menu_PadHeld+1
    LDA.w JOY1H
    LSR A
    LSR A
    LSR A
    LSR A                           ; B Y Select Start into bits 3-0
    TSB.b !Menu_PadHeld
    REP #$30
    LDA.w JOY1L
    CMP.w #!Menu_PadSoftReset
    BNE .no_reset
    JML Reset
.no_reset:
    LDA.b !Menu_PadHeld
    EOR.b !Menu_PadPrevHeld
    AND.b !Menu_PadHeld
    STA.b !Pad_Pressed
    STA.b !Menu_PadRepeat
    SEP #$10
    LDX.b !Menu_PadRepeatTimer
    LDA.b !Menu_PadHeld
    AND.b !Menu_PadPrevHeld
    BEQ .reload
    DEX
    BNE .store
    TSB.b !Menu_PadRepeat
.reload:
    LDX.b !Menu_PadRepeatDelay
.store:
    STX.b !Menu_PadRepeatTimer
    RTS

; $C2:8545 — Menu_MapButtons (105 bytes, $8545–$85AD, with the sub-entry
; Menu_MapButtonsOne at $C2:8555)
; Turns the three pad words into the game's button bytes through the
; configured button map (Menu_ButtonMap, 8 JOY1-layout masks): bit n of
; the result is set when every button of its mask is in the word. Bits
; 7-0 come from Menu_ButtonMap + 0, 2, 7, 6, 1, 4, 3, 5 (with the
; default map, MenuRom_DefaultButtonMap: A, X, L, R, B, Select, B, Y).
; The high byte (the D-pad) is copied as it is. Menu_MapButtonsOne does
; one word, X = 0, 2, 4:
;   Pad_Pressed → Pad_Unk00F6 (mapped) and Pad_Unk00F7 (D-pad);
;   Menu_PadHeld → Pad_Unk00F8 and Pad_Unk00F9;
;   Menu_PadRepeat → Menu_PadRepeatMapped and Menu_PadRepeatDpad.
; Menu_MapButtons calls it twice and falls into it for the third.
; Callers (1 JSR site): Menu_ReadPad ($C2:84DE).
; Callers note (1 JSR site): Menu_ReadPad ($C2:84DE). Menu_MapButtonsOne: JSR
;   from Menu_MapButtons itself ($C2:854F/8552).
; Entry: M, X any (SEP #$30 here), DP=$0000 (Menu_PollPad sets it), DB any
;        (set to $7E here, not restored: the masks are read absolute)
; Exit:  M=1, X=1; DB=$7E; X = 6, Y = 0, A = Menu_PadRepeat's high byte;
;        DP unchanged
; No calls.
Menu_MapButtons:
    SEP #$30
    PEA.w !Bank7E<<8|!Bank7E
    PLB
    PLB
    LDY.b #0
    TYX
    JSR Menu_MapButtonsOne      ; X = 0: the newly pressed buttons
    JSR Menu_MapButtonsOne      ; X = 2: the held buttons
Menu_MapButtonsOne:             ; header: see Menu_MapButtons
    STZ.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed,X
    AND.w !Menu_ButtonMap+5,Y
    CMP.w !Menu_ButtonMap+5,Y   ; C=1 iff every button of the mask is in
    ROR.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed,X
    AND.w !Menu_ButtonMap+3,Y
    CMP.w !Menu_ButtonMap+3,Y
    ROR.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed,X
    AND.w !Menu_ButtonMap+4,Y
    CMP.w !Menu_ButtonMap+4,Y
    ROR.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed,X
    AND.w !Menu_ButtonMap+1,Y
    CMP.w !Menu_ButtonMap+1,Y
    ROR.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed,X
    AND.w !Menu_ButtonMap+6,Y
    CMP.w !Menu_ButtonMap+6,Y
    ROR.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed,X
    AND.w !Menu_ButtonMap+7,Y
    CMP.w !Menu_ButtonMap+7,Y
    ROR.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed,X
    AND.w !Menu_ButtonMap+2,Y
    CMP.w !Menu_ButtonMap+2,Y
    ROR.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed,X
    AND.w !Menu_ButtonMap,Y
    CMP.w !Menu_ButtonMap,Y
    ROR.b !Pad_Unk00F6,X
    LDA.b !Pad_Pressed+1,X
    STA.b !Pad_Unk00F7,X
    INX
    INX
    RTS

; $C2:85AE — Menu_TickPlayTime (34 bytes, $85AE–$85CF)
; Adds one frame to the play-time clock unless Menu_PlayTimePaused is
; set: Menu_PlayTime byte 0 counts up, and each byte that reaches its
; limit in Menu_PlayTimeLimits goes back to 0 and carries into the next.
; When the last one carries too (99:59:59 and 59 frames, with the
; limits as they are) the clock is all zeros again and
; Menu_PlayTimeMaxed is set to 1.
; Callers (2 JSR sites): Menu_ReadPad ($C2:84E1) and unmatched ($C2:8490).
; Callers note (2 JSR sites): Menu_ReadPad ($C2:84E1); unmatched: $C2:8490
;   (the menu's own NMI code).
; Entry: M, X any (SEP #$30 here), DP any (set to $0400 here, not
;        restored), DB any (the limits are read long)
; Exit:  M=1, X=1; DP=$0400; A, X clobbered; Y and DB unchanged
; No calls.
Menu_TickPlayTime:
    SEP #$30
    PEA.w !Menu_PlayTimeDp
    PLD
    LDA.b !Menu_PlayTimePaused-!Menu_PlayTimeDp
    BNE .done
    LDX.b #0
.carry:
    INC.b !Menu_PlayTime-!Menu_PlayTimeDp,X
    LDA.b !Menu_PlayTime-!Menu_PlayTimeDp,X
    CMP.l Menu_PlayTimeLimits,X
    BCC .done
    STZ.b !Menu_PlayTime-!Menu_PlayTimeDp,X
    INX
    CPX.b #!Menu_PlayTimeSize
    BCC .carry
    LDA.b #1
    STA.b !Menu_PlayTimeMaxed-!Menu_PlayTimeDp
.done:
    RTS

; $C2:85D0 — Menu_PlayTimeLimits (6 bytes, $85D0–$85D5)
; The count at which each Menu_PlayTime byte wraps, lowest first:
; frames (60), seconds (60), minutes in two digits (10, then 6) and
; hours in two digits (10, 10).
Menu_PlayTimeLimits:
    db 60, 60, 10, 6, 10, 10

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
; Callers (1 JSR site): unmatched ($C2:80F0).
; Callers note (1 JSR site, unmatched): $C2:80F0 in Menu_InitSystems.
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
; Callers (5 JSR sites): Menu_InitPpuAndRam ($C2:94F7, $C2:9500, $C2:9509) and unmatched ($C2:97A1,
;   $C2:981F).
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
; Callers (2 JSR sites): unmatched ($C2:9698, $C2:96A4).
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
; Callers (3 JSR sites): unmatched ($C2:8048, $C2:8D7E, $C2:E65D).
; Callers note (3 JSR sites, unmatched): $C2:8048 in BankC2_MenuEntry, $C2:8D7E
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
; Callers (2 JSR sites): Menu_InitNewGameData ($C2:9571) and unmatched ($C2:8D85).
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
