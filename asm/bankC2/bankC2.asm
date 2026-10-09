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
;   C2Scene_TrigListAB (JSR $C2:33DF), C2Scene_ObjARise (JSR $C2:4479), C2Scene_ObjAFly (JSR
;   $C2:452C) and unmatched (JSR $C2:63AE, JSR $C2:66DF, JSR $C2:66FF, JSR $C2:6AAB, JSR $C2:741F,
;   JSR $C2:7427, JMP $C2:7457).
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
;   ($C2:173C), C2Scene_LeaderStep ($C2:3702, $C2:3709), C2Scene_LeaderBoardX ($C2:38FB, $C2:3902),
;   C2Scene_ObjAMove ($C2:468A, $C2:4691), C2Scene_ObjBMove ($C2:4F93, $C2:4F9A) and
;   C2Scene_TaskBg1Pan ($C2:785B).
; Callers note: C2Scene_LeaderStep and C2Scene_LeaderBoardX call it for
;   layers 1 and 2 with the leader's X velocity, so the view follows the
;   walking leader.
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
;   ($C2:1751), C2Scene_LeaderStep ($C2:3717, $C2:371E), C2Scene_LeaderBoardY ($C2:385B, $C2:3862),
;   C2Scene_ObjAMove ($C2:469F, $C2:46A6) and C2Scene_ObjBMove ($C2:4FA8, $C2:4FAF).
; Callers note: C2Scene_LeaderStep and C2Scene_LeaderBoardY call it for
;   layers 1 and 2 with the leader's Y velocity, so the view follows the
;   walking leader.
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
; Callers (59 JSR sites): C2Script_MoveFrames ($C2:1643), C2Script_WaitAnimating ($C2:18AC),
;   C2Script_MoveToX ($C2:19B6), C2Script_MoveToY ($C2:1A1F), C2Scene_LeaderWalk ($C2:3444),
;   C2Scene_LeaderInput ($C2:35E0, $C2:36E2), C2Scene_LeaderStep ($C2:3731), C2Scene_LeaderBoardY
;   ($C2:38C0), C2Scene_LeaderBoardX ($C2:3915), C2Scene_MemberWalk ($C2:3B3F), C2Scene_MemberFollow
;   ($C2:3CD5), C2Scene_MemberMoveX ($C2:3D36), C2Scene_MemberMoveY ($C2:3D97), C2Scene_MemberBoardX
;   ($C2:3E76), C2Scene_MemberBoardY ($C2:3EDA), C2Scene_ObjAInit ($C2:4340, $C2:4382),
;   C2Scene_ObjAWait ($C2:43D2), C2Scene_ObjARise ($C2:445C, $C2:447C), C2Scene_ObjAFly ($C2:450B),
;   C2Scene_ObjAMove ($C2:46B9), C2Scene_ObjALand ($C2:4700, $C2:4723), C2Scene_ObjAAfterMode8
;   ($C2:481E), C2Scene_ObjAScript ($C2:4852, $C2:4870), C2Scene_ObjAWaitEmpty ($C2:4894),
;   C2Scene_ObjAMarkShow ($C2:49CA), C2Scene_ObjBInit ($C2:4D14, $C2:4D32), C2Scene_ObjBWait
;   ($C2:4D3E), C2Scene_ObjBRise ($C2:4D96), C2Scene_ObjBFly ($C2:4E1B, $C2:4F73), C2Scene_ObjBMove
;   ($C2:4FC2), C2Scene_ObjBLand ($C2:5008, $C2:5032), C2Scene_ObjBMarkShow ($C2:508A),
;   C2Scene_ObjBMateInit ($C2:510B), C2Scene_ObjBMateRise ($C2:516F), C2Scene_ObjBMateFollow
;   ($C2:51E8), C2Scene_ObjBMateMove ($C2:523E), C2Scene_ObjBMateLand ($C2:525D, $C2:5285),
;   C2Scene_ObjBMateMarkRise ($C2:5553), C2Scene_ObjBMateMarkFollow ($C2:55A2, $C2:55CC),
;   C2Scene_ObjBMateMarkLand ($C2:55E2, $C2:5600), C2Scene_LabelShow ($C2:5770) and unmatched
;   ($C2:6834, $C2:6883, $C2:68DD, $C2:719A, $C2:71A9, $C2:71C7, $C2:71D8).
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
; Callers (23 JSR sites): C2Script_MoveFrames ($C2:163D), C2Script_ScrollFrames ($C2:167C),
;   C2Script_ScrollLayerFrames ($C2:172B), C2Scene_LeaderStep ($C2:36F1), C2Scene_LeaderBoardY
;   ($C2:383B), C2Scene_LeaderBoardX ($C2:38C9), C2Scene_MemberMoveX ($C2:3D02), C2Scene_MemberMoveY
;   ($C2:3D63), C2Scene_MemberBoardX ($C2:3E23), C2Scene_MemberBoardY ($C2:3E87), C2Scene_ObjARise
;   ($C2:4454), C2Scene_ObjAMove ($C2:4679), C2Scene_ObjALand ($C2:46FA), C2Scene_ObjBRise
;   ($C2:4D90), C2Scene_ObjBMove ($C2:4F82), C2Scene_ObjBLand ($C2:5002), C2Scene_ObjBMateRise
;   ($C2:5166), C2Scene_ObjBMateMove ($C2:5235), C2Scene_ObjBMateLand ($C2:5254),
;   C2Scene_ObjBMateMarkRise ($C2:554D), C2Scene_ObjBMateMarkLand ($C2:55DC), C2Scene_TaskBg3Slide
;   ($C2:7734) and C2Scene_TaskBg3SlideFast ($C2:7824).
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
; C2Scene_TaskSpawnScriptLow install it); also called by other handlers
; (the party leader's and members' script states).
; Runs the task's script from .ScriptPtr/.ScriptBank: calls the handler
; of each op from C2Script_OpTable with C2Script_Ptr on the opcode. On
; Z=0 it adds A to the pointer, stores it back in .ScriptPtr, zeroes
; .OpState (16-bit, so +$33 too) for the next op and goes on; Z=1 ends
; the call with the pointer where it is (.ScriptBank is never written).
; Callers (5 JSR sites): C2Scene_LeaderScriptStart ($C2:378B), C2Scene_LeaderScriptRun ($C2:37A1),
;   C2Scene_MemberScriptStart ($C2:3DBA), C2Scene_MemberScriptRun ($C2:3DC1) and C2Scene_ObjAScript
;   ($C2:4823).
; Callers note: as a task handler, also C2Scene_TaskRunAll
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
; Callers (4 JSR sites): C2Script_MoveToX ($C2:1979, $C2:198B), C2Scene_ObjBMateClampVel ($C2:52D0)
;   and C2Scene_ObjBMateGlideVel ($C2:5429).
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
; Callers (4 JSR sites): C2Script_MoveToY ($C2:19E2, $C2:19F4), C2Scene_ObjBMateClampVel ($C2:5319)
;   and C2Scene_ObjBMateGlideVel ($C2:5436).
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
;   $C2:19B3), C2Script_MoveToY (JSR $C2:1A1C), C2Scene_LeaderStep (JSR $C2:36F4),
;   C2Scene_LeaderBoardY (JSR $C2:383E), C2Scene_LeaderBoardX (JSR $C2:38CC), C2Scene_MemberMoveX
;   (JSR $C2:3D05), C2Scene_MemberMoveY (JSR $C2:3D66), C2Scene_MemberBoardX (JSR $C2:3E26),
;   C2Scene_MemberBoardY (JSR $C2:3E8A), C2Scene_ObjARise (JSR $C2:4457), C2Scene_ObjAMove (JSR
;   $C2:467C), C2Scene_ObjALand (JSR $C2:46FD), C2Scene_ObjAJump (JMP $C2:48E5), C2Scene_ObjBRise
;   (JSR $C2:4D93), C2Scene_ObjBMove (JSR $C2:4F85), C2Scene_ObjBLand (JSR $C2:5005),
;   C2Scene_ObjBMateRise (JSR $C2:5169), C2Scene_ObjBMateMove (JSR $C2:5238), C2Scene_ObjBMateLand
;   (JSR $C2:5257), C2Scene_ObjBMateMarkRise (JSR $C2:5550), C2Scene_ObjBMateMarkFollow (JSR
;   $C2:55C9) and C2Scene_ObjBMateMarkLand (JSR $C2:55DF).
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
; Callers (40 sites: 35 JSR, 5 JMP): C2Script_SetAnim (JSR $C2:1614), C2Script_MoveToX (JSR
;   $C2:1981, JSR $C2:1993), C2Script_MoveToY (JSR $C2:19EA, JSR $C2:19FC), C2Scene_LeaderInput (JSR
;   $C2:35CD), C2Scene_SetWalkAnim (JMP $C2:397C), C2Scene_SetStandAnim (JMP $C2:39A7),
;   C2Scene_MemberFollow (JSR $C2:3CA7, JSR $C2:3CC7), C2Scene_ObjAInit (JSR $C2:4336, JSR
;   $C2:433D), C2Scene_ObjAWait (JSR $C2:4439), C2Scene_ObjAFly (JSR $C2:45A0), C2Scene_ObjALand
;   (JSR $C2:470F), C2Scene_ObjAAfterMode8 (JSR $C2:4747), C2Scene_ObjAScript (JSR $C2:483B),
;   C2Scene_ObjAFaceAnim (JMP $C2:48BB, JMP $C2:48C2), C2Scene_ObjAMarkShow (JSR $C2:499C, JSR
;   $C2:49B5), C2Scene_ObjBInit (JSR $C2:4D11, JSR $C2:4D2F), C2Scene_ObjBWait (JSR $C2:4D76),
;   C2Scene_ObjBRise (JSR $C2:4DC1), C2Scene_ObjBFly (JSR $C2:4E9B, JSR $C2:4F1A), C2Scene_ObjBLand
;   (JSR $C2:501E), C2Scene_ObjBMarkShow (JSR $C2:5087), C2Scene_ObjBMateInit (JSR $C2:50EB),
;   C2Scene_ObjBMateWait (JSR $C2:5149), C2Scene_ObjBMateFollow (JSR $C2:51E5),
;   C2Scene_ObjBMateFaceAnim (JMP $C2:5488), C2Scene_ObjBMateMarkInit (JSR $C2:54BC, JSR $C2:550B),
;   C2Scene_ObjBMateMarkRise (JSR $C2:556A), C2Scene_ObjBMateMarkFollow (JSR $C2:559F) and unmatched
;   (JSR $C2:68D3, JSR $C2:7197, JSR $C2:71C4).
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
; Callers of Trig_Sin1024 (9 JSL sites): C2Scene_TaskBg3Wave ($C2:76CB), C2Scene_TaskBg3LineWave
;   ($C2:77D9), C2Scene_Bg2HWaveStep ($C2:7D33), C2Scene_Bg2VWaveStep ($C2:7DB9) and unmatched
;   ($C2:673B, $C2:6D17, $C2:7062, $C2:712D, $C6:EA17).
; Callers note: $C2:6D10 and $C2:6D17 take the cosine and the sine of
;   the same angle.
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
; Direction helpers ($C2:2273–$C2:232C)
; ============================================================
; Directions here have 256 steps per turn: 0 right, $40 down, $80 left,
; $C0 up (the Rom_DirToFacing convention). The three keep their Unk names
; because verified C2Scene_ObjBMateAim calls them by name; better names
; once it is next edited: C2Scene_Cos256, C2Scene_Sin256 and
; C2Scene_DirToPoint.

; $C2:2273 — C2Scene_Unk2273 (42 bytes with C2Scene_Unk2277, $2273–$229C)
; The cosine of direction A (adds a quarter turn and falls into the
; sub-entry C2Scene_Unk2277, $C2:2277, the sine). The sine is
; Rom_SineTable256's byte (127 x sin) sign-extended to a word, except at
; directions $40 and $C0, which give +128 and -128 ($0080 / $FF80)
; instead of the table's +127 / -127. Only the low byte of the direction
; counts.
; Callers (2 JSL sites): C2Scene_ObjBMateAim ($C2:53A6) and unmatched ($C6:E6EE).
; Callers of C2Scene_Unk2277 (2 JSL sites): C2Scene_ObjBMateAim ($C2:53B1) and unmatched ($C6:E71F).
; Entry (both): M=0 (16-bit A: the .w immediates), X=0 (16-bit index;
;        the index is below $100, so X=1 would read the same),
;        DP any (no direct page), DB=$00 (the table is read absolute
;        through the bank $00 mirror of $C0:F800); A = the direction
; Exit (both):  M=0, X=0; A = the signed value (-128..+128); X = the
;        direction's low byte (unchanged at directions $40 and $C0, which
;        return before the TAX); Y, DP and DB unchanged
; No calls.
C2Scene_Unk2273:
    CLC
    ADC.w #!Dir_QuarterTurn             ; cos(d) = sin(d + a quarter turn)
C2Scene_Unk2277:                        ; header: see C2Scene_Unk2273
    AND.w #!Eng_LowByteMask
    CMP.w #!Dir_QuarterTurn
    BEQ .plus_max
    CMP.w #!Dir_ThreeQuarters
    BEQ .minus_max
    TAX
    LDA.w !Rom_SineTable256,X
    BIT.w #!Dir_HalfTurn                ; the byte's sign bit
    BNE .negative
    AND.w #!Eng_LowByteMask             ; drop the next entry (read with it)
    RTL
.negative:
    ORA.w #!Eng_HighByteMask            ; sign-extend
    RTL
.plus_max:
    LDA.w #!C2Scene_SinMax
    RTL
.minus_max:
    LDA.w #!C2Scene_SinMin
    RTL

; $C2:229D — C2Scene_Unk229D (144 bytes, $229D–$232C)
; The direction (0-255) from the point (C2Tmp_08, C2Tmp_0A) to the point
; (C2Tmp_0C, C2Tmp_0E) on the scene's wrapping map: each difference that
; is half the map or more (Y 512 of 1024, X 768 of 1536 pixels) is taken
; the other way round. The angle comes from Rom_AngleTable at
; (|dy| / 4) x 32 + |dx| / 4, then is turned into the quarter the
; vector lies in.
; The differences are not scaled down (Obj_CalcDirection scales by 1/2
; or 1/4): with |dx| of 128 or more the column runs into the next row,
; and with |dy| of 128 or more the read goes past the 1 KB table (kept;
; C2Scene_ObjBMateAim aims at nearby points).
; A target straight right (angle byte 0) with dy >= 0 gives $0100, not
; 0 (C2Scene_FullTurn - 0); the sine helpers use only the low byte.
; Callers (1 JSR site): C2Scene_ObjBMateAim ($C2:5398).
; Entry: M=0 (16-bit A: the .w immediates and word scratch), X=0 (the
;        16-bit table index), DP=$0000 (C2Tmp_00-$0F), DB=$00 (the table
;        is read absolute through the bank $00 mirror of $C0:F300);
;        C2Tmp_08/0A = the start X/Y, C2Tmp_0C/0E = the target X/Y
; Exit:  M=0, X=0; A = the direction (a word, $0000-$0100 while the read
;        stays in the table); X = the table
;        index, 0 when |dx| and |dy| are both below 4 (the caller's "there"
;        test); C2Tmp_00 = start Y - target Y and C2Tmp_04 = start X -
;        target X (after the wrap), C2Tmp_02 = |dy|, C2Tmp_06 = the
;        table's angle (low byte; the high byte is 0); Y, DP and DB unchanged
; No calls.
!C2Scene_DirFromX = !C2Tmp_08          ; in: the start point
!C2Scene_DirFromY = !C2Tmp_0A
!C2Scene_DirToX = !C2Tmp_0C             ; in: the target point
!C2Scene_DirToY = !C2Tmp_0E
!C2Scene_AimDy = !C2Tmp_00              ; start Y - target Y, signed
!C2Scene_AimAbsDy = !C2Tmp_02           ; |dy|
!C2Scene_AimDx = !C2Tmp_04              ; start X - target X, signed
!C2Scene_AimAbsDx = !C2Tmp_06           ; |dx|, then |dx| / 4, then the table's angle
C2Scene_Unk229D:
    SEC
    LDA.b !C2Scene_DirFromY
    SBC.b !C2Scene_DirToY
    STA.b !C2Scene_AimDy
    BPL .dy_pos
    EOR.w #!Eng_Invert16
    INC A
.dy_pos:
    STA.b !C2Scene_AimAbsDy
    CMP.w #!C2Scene_MapHeightPx/2
    BCC .dy_done
    SEC                                 ; half the map or more: the other way round,
    SBC.w #!C2Scene_MapHeightPx         ; |dy| = height - |dy| and dy negated
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C2Scene_AimAbsDy
    LDA.b !C2Scene_AimDy
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C2Scene_AimDy
.dy_done:
    SEC
    LDA.b !C2Scene_DirFromX
    SBC.b !C2Scene_DirToX
    STA.b !C2Scene_AimDx
    BPL .dx_pos
    EOR.w #!Eng_Invert16
    INC A
.dx_pos:
    STA.b !C2Scene_AimAbsDx
    CMP.w #!C2Scene_MapWidthPx/2
    BCC .dx_done
    SEC                                 ; the same for X
    SBC.w #!C2Scene_MapWidthPx
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C2Scene_AimAbsDx
    LDA.b !C2Scene_AimDx
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C2Scene_AimDx
.dx_done:
    LDA.b !C2Scene_AimAbsDx             ; column: |dx| / 4
    LSR A
    LSR A
    STA.b !C2Scene_AimAbsDx
    LDA.b !C2Scene_AimAbsDy             ; row: |dy| / 4, times 32
    AND.w #!C2Scene_AimRiseMask
    ASL A
    ASL A
    ASL A
    CLC
    ADC.b !C2Scene_AimAbsDx
    TAX
    SEP #$20
    LDA.w !Rom_AngleTable,X             ; 0 (along X) to $40 (along Y)
    STA.b !C2Scene_AimAbsDx
    REP #$20
    LDA.b !C2Scene_AimDy
    EOR.b !C2Scene_AimDx
    BMI .signs_differ
    LDA.b !C2Scene_AimDx
    BMI .right_down
    CLC                                 ; target up-left: $80 + angle
    LDA.w #!Dir_HalfTurn
    ADC.b !C2Scene_AimAbsDx
    RTS
.right_down:
    LDA.b !C2Scene_AimAbsDx             ; target down-right: the angle
    RTS
.signs_differ:
    LDA.b !C2Scene_AimDx
    BMI .right_up
    SEC                                 ; target down-left: $80 - angle
    LDA.w #!Dir_HalfTurn
    SBC.b !C2Scene_AimAbsDx
    RTS
.right_up:
    SEC                                 ; target up-right: $100 - angle
    LDA.w #!C2Scene_FullTurn
    SBC.b !C2Scene_AimAbsDx
    RTS
    LDA.b !C2Scene_AimAbsDx             ; dead: no path reaches these 3 bytes
    RTS                                 ; ($C2:232A-$232C; no reference found)

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
; Callers (8 JSR sites): C2Scene_PlaceBelowView ($C2:754D), C2Scene_PlaceBelowViewAt178 ($C2:7575),
;   C2Scene_RandomVelocity ($C2:7598), C2Scene_NudgeXRandom ($C2:79E0), C2Scene_RandPosA ($C2:7A0C),
;   C2Scene_RandYA ($C2:7A1F), C2Scene_RandPosB ($C2:7A31) and C2Scene_RandYB ($C2:7A44).
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
; Callers (5 JSR sites): C2Scene_ObjWatchIdle ($C2:3118, $C2:317D), C2Scene_ObjAOverlap ($C2:490E),
;   C2Scene_ObjBOverlap ($C2:493D) and C2Scene_ObjASpotWatch ($C2:4A03).
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
; (C2Scene_WaitFrames and C2Scene_ModeIdle then send it with
; Audio_DriverCommand). Refused (C=1, nothing written) while a command
; is being sent (state C2Scene_SoundCmdSending, tested as negative), or
; when one is already queued with a lower pending rank than the new one;
; an equal or higher pending rank is replaced (so rank 0, which every
; matched caller passes, always replaces a queued command).
; Callers (10 JSR sites): C2Script_PlaySfx_SetArgs ($C2:18E8), C2Script_SoundCmd10 ($C2:1916),
;   C2Script_SoundCmd ($C2:193E), C2Scene_ZoneSoundAtView ($C2:2F88), C2Scene_ZoneSoundWatch
;   ($C2:2FCD, $C2:3031), C2Scene_ZoneSoundResume ($C2:306A), C2Scene_ZoneSoundQueue ($C2:3092),
;   C2Scene_ObjAInit ($C2:4395) and C2Scene_ObjASound ($C2:4A4C).
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
; Callers (1 JSR site): C2Scene_ObjAFly ($C2:45A6).
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
; The party leader's task and the walk helpers ($C2:3404–$C2:3AE1)
; ============================================================
; C2Scene_LeaderTask is a task handler (C2Scene_TaskRunAll) for the
; sprite of the first party member: no reference to it is in the bank's
; code, so like the two watchers above it is probably started from scene
; data. It follows both watchers' states: while C2Scene_ObjWatch is idle
; it walks the sprite with the D-pad and keeps the party's position
; (C2Scene_StartX/Y, and Loc_EntryX/Y in tiles) on it, or, while
; C2Scene_TrigWatch waits, runs the script C2Scene_MemberWords[0]
; names. When C2Scene_ObjWatch selects an object it walks the sprite
; onto it and counts itself in, keeps the party's position on the object
; while the object is busy, and on leaving puts the sprite at the
; object's position and counts itself out.
;
; Positions are pixels in the 1536 x 1024 scene map (C2Scene_WrapTaskPos).
; A step is 8 pixels: C2Scene_LeaderInput sets a velocity of one pixel a
; frame, C2Scene_LeaderStep moves the sprite and scrolls BG1 and BG2 by
; the same amount (C2Scene_Unk0568 / C2Scene_Unk066C: the view follows
; the leader) until it reaches C2Scene_WalkTask.TargetX/Y. Before a step
; C2Scene_GetTileProps reads the property nibbles of the four 8x8 tiles
; around the target from C2Scene_Unk7000 (one byte per metatile row of
; two 8x8 tiles, a nibble each, indexed by BG2's metatile numbers): bits
; 0-1 above the point block the step, and bit 2 in both tiles above it
; sets C2Scene_TrigFlags bits 0 and 1 (C2Scene_TrigWatch then looks the
; tile up in the trigger lists).
;
; Direct page work bytes of the helpers:
!C2Scene_AnimChar = !C2Tmp_00          ; in: the leader's character (Party_Members byte)
!C2Scene_AnimNum = !C2Tmp_01           ; the animation number being built
!C2Scene_PropX = !C2Tmp_08             ; 16-bit; in: pixel X; then the 8x8 tile column
!C2Scene_PropY = !C2Tmp_0A             ; 16-bit; in: pixel Y; then the 8x8 tile row
!C2Scene_PropCol = !C2Tmp_00           ; in to C2Scene_GetTileProp: 8x8 tile column (0-191)
!C2Scene_PropRow = !C2Tmp_01           ; and row (0-127)
!C2Scene_PropColBit = !C2Tmp_02        ; column bit 0 (which nibble)
!C2Scene_PropRowBit = !C2Tmp_03        ; 16-bit: row bit 0 (which byte of the pair; high byte $04 = 0)
!C2Scene_PropMap = !C2Tmp_10           ; 24-bit: the metatile map
!C2Scene_PropTable = !C2Tmp_13         ; 24-bit: the property table

; $C2:3404 — C2Scene_LeaderTask (41 bytes, $3404–$342C)
; Task handler. Does nothing while Party_Members[0] has
; C2Scene_PartySlotEmpty set. Otherwise zeroes the task's .State when
; C2Scene_Unk027E differs from C2Scene_Unk027F or C2Scene_Unk0280 from
; C2Scene_Unk0281 (a watcher has changed state since its last step), and
; runs the C2Scene_LeaderStates handler of C2Scene_Unk027E (the
; C2Scene_ObjWatch state).
; Callers note: none found (see the banner).
; Entry: M=1, X=0, X = C2Scene_TaskCur = the task (C2Scene_TaskRunAll),
;        DP=$0000 (TDC for 0), DB=$00 (low WRAM absolute)
; Exit:  C=0 (the task never ends); otherwise as the state's handler
; Calls: a C2Scene_LeaderStates handler (JMP (abs,X)).
C2Scene_LeaderTask:
    LDA.l !Party_Members
    BPL .present                ; not C2Scene_PartySlotEmpty
    CLC
    RTS
.present:
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_Unk027E
    CMP.w !C2Scene_Unk027F
    BEQ .obj_same
    STZ.w C2Scene_WalkTask.State,X
.obj_same:
    LDA.w !C2Scene_Unk0280
    CMP.w !C2Scene_Unk0281
    BEQ .trig_same
    STZ.w C2Scene_WalkTask.State,X
.trig_same:
    TDC                         ; A = DP = 0: B = 0 for the TAX here and in the handlers
    LDA.w !C2Scene_Unk027E
    ASL A
    TAX
    JMP (C2Scene_LeaderStates,X)

; $C2:342D — C2Scene_LeaderStates (6 words, $342D–$3438)
; C2Scene_LeaderTask's handler for each C2Scene_Unk027E state 0-5.
C2Scene_LeaderStates:
    dw C2Scene_LeaderWalk       ; 0 (C2Scene_ObjWatchStIdle)
    dw C2Scene_LeaderNone       ; 1
    dw C2Scene_LeaderOnObjA     ; 2 (C2Scene_ObjWatchStBusyA)
    dw C2Scene_LeaderOnObjB     ; 3 (C2Scene_ObjWatchStBusyB)
    dw C2Scene_LeaderBoard      ; 4 (C2Scene_ObjWatchStFull)
    dw C2Scene_LeaderLeave      ; 5 (C2Scene_ObjWatchStEmpty)

; $C2:3439 — C2Scene_LeaderWalk (36 bytes, $3439–$345C)
; ObjWatch state 0. Unless C2Scene_Mode is 0 or C2Scene_ModeIdle1 it only
; runs the animation (C2Anim_Run). Otherwise it runs entry
; C2Scene_Unk0280 * 4 + .State of C2Scene_LeaderWalkSteps.
; Callers note: none direct (C2Scene_LeaderStates).
; Entry: M=1, X=0, B=0 (the 16-bit TAX; from C2Scene_LeaderTask's TDC),
;        DP=$0000 (C2Tmp_00), DB=$00 (low WRAM absolute)
; Exit:  C=0 and C2Anim_Run's state (other modes), or as the step's
;        handler; C2Tmp_00 = C2Scene_Unk0280 * 8 when a step runs
; Calls: C2Anim_Run, a C2Scene_LeaderWalkSteps handler (JMP (abs,X)).
C2Scene_LeaderWalk:
    LDA.w !C2Scene_Mode
    CMP.b #!C2Scene_ModeIdle1
    BEQ .walk
    CMP.b #0
    BEQ .walk
    JSR C2Anim_Run
    CLC
    RTS
.walk:
    LDA.w !C2Scene_Unk0280
    ASL A                       ; * C2Scene_StepsPerTrigState
    ASL A
    ASL A
    STA.b !C2Tmp_00
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_WalkTask.State,X
    ASL A
    ADC.b !C2Tmp_00             ; no CLC: C = .State bit 7, 0 for steps 0-3
    TAX
    JMP (C2Scene_LeaderWalkSteps,X)

; $C2:345D — C2Scene_LeaderWalkSteps (8 words, $345D–$346C)
; C2Scene_LeaderWalk's handler per C2Scene_Unk0280 state (4 words each)
; and .State. Entries 3 and 7 are 0 (they would jump to $C2:0000); no
; handler sets .State 3 in either state.
C2Scene_LeaderWalkSteps:
    dw C2Scene_LeaderInit       ; state 0 (check), step 0
    dw C2Scene_LeaderInput      ; step 1 (C2Scene_StepInput)
    dw C2Scene_LeaderStep       ; step 2
    dw $0000                    ; step 3: none
    dw C2Scene_LeaderScriptStart ; state C2Scene_TrigStWait, step 0
    dw C2Scene_LeaderScriptRun  ; step 1
    dw C2Scene_LeaderScriptDone ; step 2
    dw $0000                    ; step 3: none

; $C2:346D — C2Scene_LeaderOnObjA (12 bytes, $346D–$3478)
; ObjWatch state 2 (C2Scene_ObjWatchStBusyA): the party's position
; C2Scene_StartX/Y = object A's (C2Scene_ObjAX/Y), every frame; then
; falls into C2Scene_LeaderNone. The sprite itself is not moved.
; Callers note: none direct (C2Scene_LeaderStates).
; Entry: M=1, X=0, DP any, DB=$00 (low WRAM absolute)
; Exit:  C=0; X = C2Scene_ObjAY; A unchanged
; No calls.
C2Scene_LeaderOnObjA:
    LDX.w !C2Scene_ObjAX
    STX.w !C2Scene_StartX
    LDX.w !C2Scene_ObjAY
    STX.w !C2Scene_StartY

; $C2:3479 — C2Scene_LeaderNone (2 bytes, $3479–$347A)
; ObjWatch state 1, and the end of C2Scene_LeaderOnObjA: nothing; C=0.
; Callers note: none direct (C2Scene_LeaderStates).
; Entry: M, X, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_LeaderNone:
    CLC
    RTS

; $C2:347B — C2Scene_LeaderOnObjB (14 bytes, $347B–$3488)
; ObjWatch state 3 (C2Scene_ObjWatchStBusyB): as C2Scene_LeaderOnObjA
; with object B (C2Scene_ObjBX/Y).
; Callers note: none direct (C2Scene_LeaderStates).
; Entry: M=1, X=0, DP any, DB=$00 (low WRAM absolute)
; Exit:  C=0; X = C2Scene_ObjBY; A unchanged
; No calls.
C2Scene_LeaderOnObjB:
    LDX.w !C2Scene_ObjBX
    STX.w !C2Scene_StartX
    LDX.w !C2Scene_ObjBY
    STX.w !C2Scene_StartY
    CLC
    RTS

; $C2:3489 — C2Scene_LeaderBoard (10 bytes, $3489–$3492)
; ObjWatch state 4 (C2Scene_ObjWatchStFull): runs entry .State of
; C2Scene_LeaderBoardSteps (walk to the selected object, then count in).
; Callers note: none direct (C2Scene_LeaderStates).
; Entry: M=1, X=0, B=0 (the 16-bit TAX; from C2Scene_LeaderTask's TDC),
;        DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM absolute)
; Exit:  as the step's handler
; Calls: a C2Scene_LeaderBoardSteps handler (JMP (abs,X)).
C2Scene_LeaderBoard:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_WalkTask.State,X
    ASL A
    TAX
    JMP (C2Scene_LeaderBoardSteps,X)

; $C2:3493 — C2Scene_LeaderBoardSteps (4 words, $3493–$349A)
; C2Scene_LeaderBoard's handler for .State 0-3.
C2Scene_LeaderBoardSteps:
    dw C2Scene_LeaderBoardStart ; 0: aim at the object, start the Y move
    dw C2Scene_LeaderBoardY     ; 1: move in Y
    dw C2Scene_LeaderBoardX     ; 2: move in X, then count in
    dw C2Scene_LeaderBoardDone  ; 3: nothing

; $C2:349B — C2Scene_LeaderLeave (8 bytes, $349B–$34A2)
; ObjWatch state 5 (C2Scene_ObjWatchStEmpty): runs entry C2Scene_ObjSel
; of C2Scene_LeaderLeaveTable.
; Callers note: none direct (C2Scene_LeaderStates).
; Entry: M=1, X=0, B=0 (the 16-bit TAX; from C2Scene_LeaderTask's TDC),
;        DP any, DB=$00 (low WRAM absolute)
; Exit:  as the handler
; Calls: a C2Scene_LeaderLeaveTable handler (JMP (abs,X)).
C2Scene_LeaderLeave:
    LDA.w !C2Scene_ObjSel
    ASL A
    TAX
    JMP (C2Scene_LeaderLeaveTable,X)

; $C2:34A3 — C2Scene_LeaderLeaveTable (4 words, $34A3–$34AA)
; C2Scene_LeaderLeave's handler for C2Scene_ObjSel 0-3.
C2Scene_LeaderLeaveTable:
    dw C2Scene_LeaderLeaveNone  ; 0
    dw C2Scene_LeaderLeaveNone  ; 1
    dw C2Scene_LeaderLeaveA     ; 2 (C2Scene_ObjSelA)
    dw C2Scene_LeaderLeaveB     ; 3 (C2Scene_ObjSelB)

; $C2:34AB — C2Scene_LeaderLeaveNone (2 bytes, $34AB–$34AC)
; No object selected: nothing; C=0.
; Callers note: none direct (C2Scene_LeaderLeaveTable).
; Entry: M, X, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_LeaderLeaveNone:
    CLC
    RTS

; $C2:34AD — C2Scene_LeaderLeaveA (32 bytes, $34AD–$34CC, with
; C2Scene_LeaderLeaveB at $C2:34CD, 43 bytes to $34F7)
; Leaving object A (B): .State = 0, the sprite and C2Scene_StartX/Y at
; the object's position (C2Scene_ObjAX/Y, C2Scene_ObjBX/Y), one off the
; object's flags byte (C2Scene_Unk0294, C2Scene_ObjBFlags: its count,
; C2Scene_ObjCountMask), .Unk26 = 0, Loc_EntryFacing =
; C2Scene_FacingDown and Loc_EntryX/Y from the position
; (C2Scene_SetEntryTile). This runs on every frame of the state, so the
; count drops by one a frame until C2Scene_ObjWatchEmpty sees it at 0.
; Callers note: none direct (C2Scene_LeaderLeaveTable).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (DP_Field and
;        low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A = Loc_EntryY
; Calls: C2Scene_SetEntryTile.
C2Scene_LeaderLeaveA:
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_WalkTask.State,X
    REP #$20
    LDA.w !C2Scene_ObjAX
    STA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_StartX
    LDA.w !C2Scene_ObjAY
    STA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_StartY
    SEP #$20
    DEC.w !C2Scene_Unk0294
    BRA C2Scene_LeaderLeaveB_tail

C2Scene_LeaderLeaveB:           ; header: see C2Scene_LeaderLeaveA
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_WalkTask.State,X
    REP #$20
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_StartX
    LDA.w !C2Scene_ObjBY
    STA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_StartY
    SEP #$20
    DEC.w !C2Scene_ObjBFlags
.tail:
    STZ.w C2Scene_WalkTask.Unk26,X
    LDA.b #!C2Scene_FacingDown
    STA.w !DP_Field+!Loc_EntryFacing
    JSR C2Scene_SetEntryTile
    CLC
    RTS

; $C2:34F8 — C2Scene_LeaderInit (111 bytes, $34F8–$3566)
; Step 0 of TrigWatch state 0: sets the sprite up and falls into
; C2Scene_LeaderInput. .State = 1; .SprAttr = C2Scene_LeaderAttr1F5 at
; Loc_Id C2Scene_Loc1F5, else C2Scene_LeaderAttr; .SprTile = 0; the
; position from C2Scene_StartX/Y; the four velocity words 0;
; Loc_EntryX/Y from the position (C2Scene_SetEntryTile); .Unk26 = 0;
; .Facing = Loc_EntryFacing AND C2Scene_FacingMask (not moving); the
; trail emptied (C2Scene_TrailPos = 0, every entry the start position:
; C2Scene_TrailFill); the stand animation; the tile properties at the
; position (C2Scene_GetTileProps), and C2Scene_TrigRecheck and
; C2Scene_TrigKeep set in C2Scene_TrigFlags when C2Scene_OnTrigTiles
; says so.
; Callers note: none direct (C2Scene_LeaderWalkSteps).
; Entry: M any (SEP #$20 here), X=0, DP=$0000, DB=$00 (DP_Field and low
;        WRAM absolute)
; Exit:  as C2Scene_LeaderInput
; Calls: C2Scene_SetEntryTile, C2Scene_TrailFill, C2Scene_SetStandAnim,
;   C2Scene_GetTileProps, C2Scene_OnTrigTiles; then falls into
;   C2Scene_LeaderInput.
C2Scene_LeaderInit:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_WalkTask.State,X
    LDY.w !DP_Field+!Loc_Id
    CPY.w #!C2Scene_Loc1F5
    BNE .attr_normal
    LDA.b #!C2Scene_LeaderAttr1F5
    BRA .attr_set
.attr_normal:
    LDA.b #!C2Scene_LeaderAttr
.attr_set:
    STA.w C2Scene_Task.SprAttr,X
    REP #$20
    STZ.w C2Scene_Task.SprTile,X
    LDA.w !C2Scene_StartX
    STA.w C2Scene_Task.SprX,X
    LDA.w !C2Scene_StartY
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    JSR C2Scene_SetEntryTile    ; M=1
    STZ.w C2Scene_WalkTask.Unk26,X
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask
    STA.w C2Scene_WalkTask.Facing,X
    STZ.w !C2Scene_TrailPos
    REP #$20
    JSR C2Scene_TrailFill
    LDA.l !Party_Members        ; 16-bit: C2Tmp_01 gets member 2 (unused)
    STA.b !C2Scene_AnimChar
    JSR C2Scene_SetStandAnim
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    JSR C2Scene_OnTrigTiles
    BCC C2Scene_LeaderInput
    LDA.b #!C2Scene_TrigRecheck|!C2Scene_TrigKeep
    TSB.w !C2Scene_TrigFlags

; $C2:3567 — C2Scene_LeaderInput (390 bytes, $3567–$36EC)
; Step 1 of TrigWatch state 0: reads the held buttons (Pad_Unk00F8 and
; the D-pad in Pad_Unk00F9) in scene mode C2Scene_ModeIdle1 only (in
; mode 0 it only animates). In this order:
; - nothing held: idle (below);
; - bit 7 (Pad_Unk00F8Bit7) with a ListA entry found
;   (C2Scene_Unk1B32 not negative): mode C2Scene_ModeListA; without one
;   the button is ignored;
; - bit 6: mode C2Scene_ModeMenu;
; - bit 0, once Eng_Unk7F0000 >= Eng_Unk7F0000Min (the test
;   Field_FadeToBankC2Mode5 makes too): mode C2Scene_ModeMenu9; below
;   it the button is ignored;
; - bit 2: mode C2Scene_ModeMode7;
; - Up, Down, Left, Right (first one held wins): a step (below);
; - anything else: idle.
; A new mode is set and the frame then ends as an idle one.
; Idle: .Facing loses C2Scene_WalkMoving; C2Scene_IdleFrames + 1; below
; C2Scene_IdleAnimAt the stand animation is set again, at it the
; C2Scene_AnimIdle animation once (the count then stays at
; C2Scene_IdleHold/C2Scene_IdleSet); C2Anim_Run.
; Step: the whole-pixel velocity is set to 1 pixel a frame in the
; direction (the other axis 0; the fraction words are left as they are)
; and the walk animation (C2Scene_SetWalkAnim) is started unless it
; already runs for that facing; C2Scene_IdleFrames = 0. The target is the
; position 8 pixels on (C2Scene_SetStepTarget, C2Scene_WrapStepTarget)
; and its tile properties are read (C2Scene_GetTileProps). When
; C2Scene_TileBlocked says so, the step is dropped: not moving, the four
; velocity words 0, the properties read again at the position, the
; stand animation, C2Anim_Run. Otherwise C2Scene_Unk1BF7 = 0, .State = 2
; and it falls into C2Scene_LeaderStep.
; Callers note: none direct (C2Scene_LeaderWalkSteps); C2Scene_LeaderInit
;   falls into it.
; Entry: M=1, X=0, DP=$0000, DB=$00 (Pad_Unk00F8 and low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A, Y and C2Tmp_00-$03, $08-$15
;        clobbered (the helpers); or as C2Scene_LeaderStep
; Calls: C2Scene_SetAnim, C2Scene_SetStandAnim, C2Scene_SetWalkAnim,
;   C2Scene_SetStepTarget, C2Scene_WrapStepTarget, C2Scene_GetTileProps,
;   C2Scene_TileBlocked, C2Anim_Run.
C2Scene_LeaderInput:
    LDA.w !C2Scene_Mode
    CMP.b #!C2Scene_ModeIdle1
    BNE .animate
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !Pad_Unk00F8
    BEQ .idle
    BIT.w #!Pad_Unk00F8Bit7
    BNE .button7
.test_bit6:
    LDA.w !Pad_Unk00F8
    BIT.w #!Pad_Unk00F8Bit6
    BNE .button6
    BIT.w #!Pad_Unk00F8Bit0
    BNE .button0
.test_bit2:
    REP #$20
    LDA.w !Pad_Unk00F8
    BIT.w #!Pad_Unk00F8Bit2
    BNE .button2
    BIT.w #!C2Scene_PadUp
    BEQ .not_up
    JMP .up
.not_up:
    BIT.w #!C2Scene_PadDown
    BEQ .not_down
    JMP .down
.not_down:
    BIT.w #!C2Scene_PadLeft
    BEQ .not_left
    JMP .left
.not_left:
    BIT.w #!C2Scene_PadRight
    BEQ .idle
    JMP .right
.idle:
    SEP #$20
    LDA.w C2Scene_WalkTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    STA.w C2Scene_WalkTask.Facing,X
    INC.w !C2Scene_IdleFrames
    LDA.w !C2Scene_IdleFrames
    CMP.b #!C2Scene_IdleAnimAt
    BCC .stand
    CMP.b #!C2Scene_IdleSet
    BEQ .idle_hold
    LDA.b #!C2Scene_AnimIdle
    JSR C2Scene_SetAnim
.idle_hold:
    LDA.b #!C2Scene_IdleHold
    STA.w !C2Scene_IdleFrames
    BRA .animate
.stand:
    LDA.l !Party_Members
    STA.b !C2Scene_AnimChar
    JSR C2Scene_SetStandAnim
.animate:
    JSR C2Anim_Run
    CLC
    RTS
.button7:
    LDA.w !C2Scene_Unk1B32
    BMI .test_bit6              ; no ListA entry: as if not pressed
    SEP #$20
    LDA.b #!C2Scene_ModeListA
    STA.w !C2Scene_Mode
    BRA .idle
.button6:
    SEP #$20
    LDA.b #!C2Scene_ModeMenu
    STA.w !C2Scene_Mode
    BRA .idle
.button2:
    SEP #$20
    LDA.b #!C2Scene_ModeMode7
    STA.w !C2Scene_Mode
    BRA .idle
.button0:
    SEP #$20
    LDA.l !Eng_Unk7F0000
    CMP.b #!Eng_Unk7F0000Min
    BCS .menu9
    JMP .test_bit2
.menu9:
    LDA.b #!C2Scene_ModeMenu9
    STA.w !C2Scene_Mode
    BRA .idle
.up:
    LDA.w #!C2Scene_WholeMinus1
    STA.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.XVel,X
    SEP #$20
    LDA.w C2Scene_WalkTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    CMP.b #!C2Scene_FacingUp
    BNE .face_up
    LDA.w C2Scene_WalkTask.Facing,X
    BMI .start                  ; already walking up
.face_up:
    LDA.b #!C2Scene_WalkMoving|!C2Scene_FacingUp
    BRA .set_walk
.down:
    LDA.w #1
    STA.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.XVel,X
    SEP #$20
    LDA.w C2Scene_WalkTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    CMP.b #!C2Scene_FacingDown
    BNE .face_down
    LDA.w C2Scene_WalkTask.Facing,X
    BMI .start
.face_down:
    LDA.b #!C2Scene_WalkMoving|!C2Scene_FacingDown
    BRA .set_walk
.left:
    LDA.w #!C2Scene_WholeMinus1
    STA.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVel,X
    SEP #$20
    LDA.w C2Scene_WalkTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    CMP.b #!C2Scene_FacingLeft
    BNE .face_left
    LDA.w C2Scene_WalkTask.Facing,X
    BMI .start
.face_left:
    LDA.b #!C2Scene_WalkMoving|!C2Scene_FacingLeft
    BRA .set_walk
.right:
    LDA.w #1
    STA.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVel,X
    SEP #$20
    LDA.w C2Scene_WalkTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    CMP.b #!C2Scene_FacingRight
    BNE .face_right
    LDA.w C2Scene_WalkTask.Facing,X
    BMI .start
.face_right:
    LDA.b #!C2Scene_WalkMoving|!C2Scene_FacingRight
.set_walk:
    STA.w C2Scene_WalkTask.Facing,X
    LDA.l !Party_Members
    STA.b !C2Scene_AnimChar
    JSR C2Scene_SetWalkAnim
.start:
    STZ.w !C2Scene_IdleFrames
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_SetStepTarget
    JSR C2Scene_WrapStepTarget
    LDA.w C2Scene_WalkTask.TargetX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_WalkTask.TargetY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    JSR C2Scene_TileBlocked
    BCC .go
    LDA.w C2Scene_WalkTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    STA.w C2Scene_WalkTask.Facing,X
    REP #$20
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    LDA.l !Party_Members
    STA.b !C2Scene_AnimChar
    JSR C2Scene_SetStandAnim
    JSR C2Anim_Run
    CLC
    RTS
.go:
    STZ.w !C2Scene_Unk1BF7
    INC.w C2Scene_WalkTask.State,X

; $C2:36ED — C2Scene_LeaderStep (133 bytes, $36ED–$3771)
; Step 2 of TrigWatch state 0, one frame of a step: moves the sprite
; (C2Scene_TaskMove, C2Scene_WrapTaskPos); scrolls BG layers 1 and 2 by
; .XVel pixels across (C2Scene_Unk0568) and by .YVel pixels down
; (C2Scene_Unk066C); C2Scene_Unk1BF1/1BF3 = .XVel/.YVel; C2Anim_Run;
; C2Scene_StartX/Y = the position and Loc_EntryX/Y from it
; (C2Scene_SetEntryTile). At the target (.TargetX/Y) the position goes
; into the trail (C2Scene_TrailPush), .State = C2Scene_StepInput, and
; C2Scene_TrigFlags gets C2Scene_TrigRecheck and C2Scene_TrigKeep set
; when C2Scene_OnTrigTiles says so (the properties C2Scene_LeaderInput
; read for the target), else C2Scene_TrigKeep cleared.
; Callers note: none direct (C2Scene_LeaderWalkSteps); C2Scene_LeaderInput
;   falls into it.
; Entry: M any (REP #$20 here), X=0, DP=$0000 (the scroll arguments),
;        DB=$00 (low WRAM absolute)
; Exit:  C=0; X = the task; still moving: M=0, A = .SprX or .SprY (the
;        word that differs); at the target: M=1, A = the TSB or TRB mask;
;        Y, C2Tmp_00-$1A as the scroll routines leave them
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_Unk0568,
;   C2Scene_Unk066C, C2Anim_Run, C2Scene_SetEntryTile, C2Scene_TrailPush,
;   C2Scene_OnTrigTiles.
C2Scene_LeaderStep:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    SEP #$20
    LDA.w C2Scene_Task.XVel,X
    STA.b !C2Scene_ScrollPx
    LDA.b #1
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk0568
    LDA.b #2
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk0568
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.YVel,X
    STA.b !C2Scene_ScrollPx
    LDA.b #1
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk066C
    LDA.b #2
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk066C
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.XVel,X
    STA.w !C2Scene_Unk1BF1
    LDA.w C2Scene_Task.YVel,X
    STA.w !C2Scene_Unk1BF3
    JSR C2Anim_Run
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_StartX
    LDA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_StartY
    JSR C2Scene_SetEntryTile
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    CMP.w C2Scene_WalkTask.TargetX,X
    BNE .done
    LDA.w C2Scene_Task.SprY,X
    CMP.w C2Scene_WalkTask.TargetY,X
    BNE .done
    JSR C2Scene_TrailPush
    LDA.b #!C2Scene_StepInput
    STA.w C2Scene_WalkTask.State,X
    JSR C2Scene_OnTrigTiles
    BCC .off
    LDA.b #!C2Scene_TrigRecheck|!C2Scene_TrigKeep
    TSB.w !C2Scene_TrigFlags
    BRA .done
.off:
    LDA.b #!C2Scene_TrigKeep
    TRB.w !C2Scene_TrigFlags
.done:
    CLC
    RTS

; $C2:3772 — C2Scene_LeaderScriptStart (47 bytes, $3772–$37A0)
; Step 0 of TrigWatch state C2Scene_TrigStWait: while the first
; C2Scene_MemberWords word is 0, nothing. Then it becomes the task's
; script (.ScriptPtr; .ScriptBank = the scene script's bank $7F,
; .ScriptWait = 0), .State = 1, the script runs for this frame
; (C2Scene_TaskRunScript; its carry is not used) and the tile properties
; at the position are read (C2Scene_GetTileProps). So the first member
; word is probably the address of a script for the leader (set by
; C2Script_SetMemberWord, which the ListD script runs).
; Callers note: none direct (C2Scene_LeaderWalkSteps).
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=0 and A = 0 (no word yet), or M=1 with A, X, Y and
;        C2Tmp_00-$03, $08-$15 clobbered (the script and the lookup)
; Calls: C2Scene_TaskRunScript, C2Scene_GetTileProps.
C2Scene_LeaderScriptStart:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_MemberWords
    BEQ .done
    STA.w C2Scene_Task.ScriptPtr,X
    SEP #$20
    LDA.b #bank(!C2Scene_ScriptBuf)
    STA.w C2Scene_Task.ScriptBank,X
    STZ.w C2Scene_Task.ScriptWait,X
    INC.w C2Scene_WalkTask.State,X
    JSR C2Scene_TaskRunScript
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
.done:
    CLC
    RTS

; $C2:37A1 — C2Scene_LeaderScriptRun (26 bytes, $37A1–$37BA)
; Step 1 of TrigWatch state C2Scene_TrigStWait: runs the script
; (C2Scene_TaskRunScript); when it ends (C=1) .State = 2 instead of the
; task ending. Every frame C2Scene_StartX/Y = the sprite's position.
; Callers note: none direct (C2Scene_LeaderWalkSteps).
; Entry: M any, X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task, Y = .SprY; A and the rest as the
;        script leaves them
; Calls: C2Scene_TaskRunScript.
C2Scene_LeaderScriptRun:
    JSR C2Scene_TaskRunScript
    BCC .running
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_WalkTask.State,X
.running:
    LDX.b !C2Scene_TaskCur
    LDY.w C2Scene_Task.SprX,X
    STY.w !C2Scene_StartX
    LDY.w C2Scene_Task.SprY,X
    STY.w !C2Scene_StartY
    CLC
    RTS

; $C2:37BB — C2Scene_LeaderScriptDone (2 bytes, $37BB–$37BC)
; Step 2 of TrigWatch state C2Scene_TrigStWait (the script has ended):
; nothing until a watcher's state changes; C=0.
; Callers note: none direct (C2Scene_LeaderWalkSteps).
; Entry: M, X, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_LeaderScriptDone:
    CLC
    RTS

; $C2:37BD — C2Scene_LeaderBoardStart (13 bytes, $37BD–$37C9, with the
; sub-entries C2Scene_LeaderBoardSel0 $C2:37D2, C2Scene_LeaderBoardSel1
; $C2:37D6, C2Scene_LeaderBoardObjA $C2:37D8 and C2Scene_LeaderBoardObjB
; $C2:37E8 to $3836, after the table C2Scene_LeaderBoardTargets)
; Step 0 of ObjWatch state 4: the target (.TargetX/Y) = the selected
; object's position (C2Scene_ObjAX/Y or C2Scene_ObjBX/Y, by
; C2Scene_ObjSel through C2Scene_LeaderBoardTargets); the four velocity
; words 0; .YVel = -1 and .Facing = C2Scene_FacingUp when the target is
; above, +1 and C2Scene_FacingDown when below (on the same row both are
; left as they are); .State = 1; the walk animation
; (C2Scene_SetWalkAnim); then it falls into C2Scene_LeaderBoardY.
; Quirks, kept: with C2Scene_ObjSel 0 the target is not set (the last
; one is used); with 1 (never set by the matched code) the LDX of the
; task is skipped too, so X = 2 and the stores and the INC go to
; $00:001C-$002A and $00:0004 instead of the task.
; Callers note: none direct (C2Scene_LeaderBoardSteps).
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  as C2Scene_LeaderBoardY
; Calls: C2Scene_SetWalkAnim; then falls into C2Scene_LeaderBoardY.
C2Scene_LeaderBoardStart:
    REP #$20
    LDA.w !C2Scene_ObjSel
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    JMP (C2Scene_LeaderBoardTargets,X)

; $C2:37CA — C2Scene_LeaderBoardTargets (4 words, $37CA–$37D1)
; C2Scene_LeaderBoardStart's code for C2Scene_ObjSel 0-3.
C2Scene_LeaderBoardTargets:
    dw C2Scene_LeaderBoardSel0  ; 0
    dw C2Scene_LeaderBoardSel1  ; 1
    dw C2Scene_LeaderBoardObjA  ; 2 (C2Scene_ObjSelA)
    dw C2Scene_LeaderBoardObjB  ; 3 (C2Scene_ObjSelB)

C2Scene_LeaderBoardSel0:        ; header: see C2Scene_LeaderBoardStart
    LDX.b !C2Scene_TaskCur
    BRA C2Scene_LeaderBoardObjB_aim

C2Scene_LeaderBoardSel1:        ; header: see C2Scene_LeaderBoardStart
    BRA C2Scene_LeaderBoardObjB_aim ; quirk: X = 2 (see the header)

C2Scene_LeaderBoardObjA:        ; header: see C2Scene_LeaderBoardStart
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_ObjAX
    STA.w C2Scene_WalkTask.TargetX,X
    LDA.w !C2Scene_ObjAY
    STA.w C2Scene_WalkTask.TargetY,X
    BRA C2Scene_LeaderBoardObjB_aim

C2Scene_LeaderBoardObjB:        ; header: see C2Scene_LeaderBoardStart
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_WalkTask.TargetX,X
    LDA.w !C2Scene_ObjBY
    STA.w C2Scene_WalkTask.TargetY,X
.aim:
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    SEC
    LDA.w C2Scene_WalkTask.TargetY,X
    SBC.w C2Scene_Task.SprY,X
    SEP #$20
    BEQ .aimed                  ; flags of the 16-bit difference
    BPL .down
    LDA.b #!C2Scene_WholeMinus1&$FF
    STA.w C2Scene_Task.YVel,X
    STA.w C2Scene_Task.YVel+1,X
    LDA.b #!C2Scene_FacingUp
    STA.w C2Scene_WalkTask.Facing,X
    BRA .aimed
.down:
    LDA.b #1
    STA.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.YVel+1,X
    LDA.b #!C2Scene_FacingDown
    STA.w C2Scene_WalkTask.Facing,X
.aimed:
    INC.w C2Scene_WalkTask.State,X
    LDA.l !Party_Members
    STA.b !C2Scene_AnimChar
    JSR C2Scene_SetWalkAnim

; $C2:3837 — C2Scene_LeaderBoardY (142 bytes, $3837–$38C4)
; Step 1 of ObjWatch state 4: moves the sprite (C2Scene_TaskMove,
; C2Scene_WrapTaskPos); C2Scene_StartX/Y and Loc_EntryX/Y from the
; position (C2Scene_SetEntryTile); BG layers 1 and 2 scrolled by .YVel
; (C2Scene_Unk066C); C2Scene_Unk1BF1/1BF3 = .XVel/.YVel. On the target's
; row: the velocity words 0, .XVel = -1 and .Facing = C2Scene_FacingLeft
; when the target is left, +1 and C2Scene_FacingRight when right (in the
; same column both are left as they are), .State = 2 and the walk
; animation (C2Scene_SetWalkAnim). Then C2Anim_Run.
; Callers note: none direct (C2Scene_LeaderBoardSteps);
;   C2Scene_LeaderBoardStart falls into it.
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A, Y and C2Tmp_00-$1A clobbered
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_SetEntryTile,
;   C2Scene_Unk066C, C2Scene_SetWalkAnim, C2Anim_Run.
C2Scene_LeaderBoardY:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    LDX.b !C2Scene_TaskCur
    LDY.w C2Scene_Task.SprX,X
    STY.w !C2Scene_StartX
    LDY.w C2Scene_Task.SprY,X
    STY.w !C2Scene_StartY
    JSR C2Scene_SetEntryTile
    LDA.w C2Scene_Task.YVel,X
    STA.b !C2Scene_ScrollPx
    LDA.b #1
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk066C
    LDA.b #2
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk066C
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.XVel,X
    STA.w !C2Scene_Unk1BF1
    LDA.w C2Scene_Task.YVel,X
    STA.w !C2Scene_Unk1BF3
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprY,X
    CMP.w C2Scene_WalkTask.TargetY,X
    BNE .animate
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    SEC
    LDA.w C2Scene_WalkTask.TargetX,X
    SBC.w C2Scene_Task.SprX,X
    SEP #$20
    BEQ .aimed                  ; flags of the 16-bit difference
    BPL .right
    LDA.b #!C2Scene_WholeMinus1&$FF
    STA.w C2Scene_Task.XVel,X
    STA.w C2Scene_Task.XVel+1,X
    LDA.b #!C2Scene_FacingLeft
    STA.w C2Scene_WalkTask.Facing,X
    BRA .aimed
.right:
    LDA.b #1
    STA.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.XVel+1,X
    LDA.b #!C2Scene_FacingRight
    STA.w C2Scene_WalkTask.Facing,X
.aimed:
    INC.w C2Scene_WalkTask.State,X
    LDA.l !Party_Members
    STA.b !C2Scene_AnimChar
    JSR C2Scene_SetWalkAnim
.animate:
    JSR C2Anim_Run
    CLC
    RTS

; $C2:38C5 — C2Scene_LeaderBoardX (85 bytes, $38C5–$3919)
; Step 2 of ObjWatch state 4: moves the sprite (C2Scene_TaskMove,
; C2Scene_WrapTaskPos); at the target's X, .State = 3 and the object's
; count goes up by one (C2Scene_ObjCountUp). C2Scene_StartX/Y and
; Loc_EntryX/Y from the position (C2Scene_SetEntryTile); BG layers 1 and
; 2 scrolled by .XVel (C2Scene_Unk0568); C2Scene_Unk1BF1/1BF3 =
; .XVel/.YVel; C2Anim_Run.
; Callers note: none direct (C2Scene_LeaderBoardSteps).
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A, Y and C2Tmp_00-$1A clobbered
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_ObjCountUp,
;   C2Scene_SetEntryTile, C2Scene_Unk0568, C2Anim_Run.
C2Scene_LeaderBoardX:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    LDA.w C2Scene_Task.SprX,X
    CMP.w C2Scene_WalkTask.TargetX,X
    BNE .move
    SEP #$20
    INC.w C2Scene_WalkTask.State,X
    JSR C2Scene_ObjCountUp
.move:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDY.w C2Scene_Task.SprX,X
    STY.w !C2Scene_StartX
    LDY.w C2Scene_Task.SprY,X
    STY.w !C2Scene_StartY
    JSR C2Scene_SetEntryTile
    LDA.w C2Scene_Task.XVel,X
    STA.b !C2Scene_ScrollPx
    LDA.b #1
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk0568
    LDA.b #2
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk0568
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.XVel,X
    STA.w !C2Scene_Unk1BF1
    LDA.w C2Scene_Task.YVel,X
    STA.w !C2Scene_Unk1BF3
    JSR C2Anim_Run
    CLC
    RTS

; $C2:391A — C2Scene_LeaderBoardDone (2 bytes, $391A–$391B)
; Step 3 of ObjWatch state 4 (counted in): nothing; C=0.
; Callers note: none direct (C2Scene_LeaderBoardSteps).
; Entry: M, X, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_LeaderBoardDone:
    CLC
    RTS

; $C2:391C — C2Scene_TrailFill (24 bytes, $391C–$3933)
; Fills all C2Scene_TrailLen entries of C2Scene_TrailX/Y with
; C2Scene_StartX/Y.
; Callers (1 JSR site): C2Scene_LeaderInit ($C2:3540).
; Entry: M=0, X=0, DP any, DB=$00 (low WRAM absolute)
; Exit:  M=0, X=0; A = C2Scene_StartY, X = 2 * C2Scene_TrailLen, Y = 0
; No calls.
C2Scene_TrailFill:
    LDY.w #!C2Scene_TrailLen
    LDX.w #0
.next:
    LDA.w !C2Scene_StartX
    STA.w !C2Scene_TrailX,X
    LDA.w !C2Scene_StartY
    STA.w !C2Scene_TrailY,X
    INX
    INX
    DEY
    BNE .next
    RTS

; $C2:3934 — C2Scene_TrailPush (31 bytes, $3934–$3952)
; Stores the task's .SprX/.SprY at C2Scene_TrailPos in C2Scene_TrailX/Y
; and moves C2Scene_TrailPos one word on (wrapping after 16).
; Callers (1 JSR site): C2Scene_LeaderStep ($C2:3757).
; Entry: M=0, X=0, X = the task, DP any, DB=$00 (low WRAM absolute)
; Exit:  M=1, X=0; A = the new C2Scene_TrailPos (B = 0), Y = the old one
;        + 2; X unchanged
; No calls.
C2Scene_TrailPush:
    LDA.w !C2Scene_TrailPos
    AND.w #!Eng_LowByteMask
    TAY
    LDA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_TrailX,Y
    LDA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_TrailY,Y
    INY
    INY
    TYA
    AND.w #!C2Scene_TrailMask
    SEP #$20
    STA.w !C2Scene_TrailPos
    RTS

; $C2:3953 — C2Scene_SetWalkAnim (44 bytes, $3953–$397E)
; Starts the walk animation of the task's facing: entry .Facing * 2 (bit
; 7 shifted out) + .Unk26 bit 0 of C2Scene_WalkAnims, C2Scene_AltAnimOfs
; further on when C2Scene_AnimChar is C2Scene_AltAnimChar
; (C2Scene_SetAnim, tail call).
; Callers (4 JSR sites): C2Scene_LeaderInput ($C2:3694), C2Scene_LeaderBoardObjB ($C2:3834),
;   C2Scene_LeaderBoardY ($C2:38BD) and C2Scene_MemberWalkAnim ($C2:41B1).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Tmp_00/$01; TDC for
;        0), DB=$00 (low WRAM absolute); C2Scene_AnimChar set;
;        C2Scene_TaskCur = the task
; Exit:  as C2Scene_SetAnim: M=1, X=0; X = the task; Y unchanged;
;        C2Scene_AnimNum = the animation
; Calls: C2Scene_SetAnim (JMP).
C2Scene_SetWalkAnim:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    TDC                         ; B = 0 for the TAX
    LDA.w C2Scene_WalkTask.Facing,X
    ASL A
    STA.b !C2Scene_AnimNum
    LDA.w C2Scene_WalkTask.Unk26,X
    AND.b #1
    CLC
    ADC.b !C2Scene_AnimNum
    TAX
    LDA.l C2Scene_WalkAnims,X
    STA.b !C2Scene_AnimNum
    LDA.b !C2Scene_AnimChar
    CMP.b #!C2Scene_AltAnimChar
    BNE .set
    CLC
    LDA.b !C2Scene_AnimNum
    ADC.b #!C2Scene_AltAnimOfs
    STA.b !C2Scene_AnimNum
.set:
    LDA.b !C2Scene_AnimNum
    JMP C2Scene_SetAnim

; $C2:397F — C2Scene_WalkAnims (8 bytes, $397F–$3986)
; Walk animation numbers (C2Scene_SetAnim), two per facing: up, down,
; left, right. Each sits next to the facing's stand animation in
; C2Scene_StandAnims (stand n, walk n+1 and n+2).
C2Scene_WalkAnims:
    db $04,$05                  ; C2Scene_FacingUp
    db $01,$02                  ; C2Scene_FacingDown
    db $07,$08                  ; C2Scene_FacingLeft
    db $0A,$0B                  ; C2Scene_FacingRight

; $C2:3987 — C2Scene_SetStandAnim (35 bytes, $3987–$39A9)
; Starts the stand animation of the task's facing: entry .Facing AND
; C2Scene_FacingMask of C2Scene_StandAnims, C2Scene_AltAnimOfs further
; on for C2Scene_AltAnimChar, as C2Scene_SetWalkAnim.
; Callers (5 sites: 4 JSR, 1 JMP): C2Scene_LeaderInit (JSR $C2:3549), C2Scene_LeaderInput (JSR
;   $C2:35DD, JSR $C2:36DF), C2Scene_MemberWalk (JSR $C2:3B3C) and C2Scene_MemberStand (JMP
;   $C2:4181).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Tmp_00/$01; TDC for
;        0), DB=$00 (low WRAM absolute); C2Scene_AnimChar set;
;        C2Scene_TaskCur = the task
; Exit:  as C2Scene_SetAnim: M=1, X=0; X = the task; Y unchanged;
;        C2Scene_AnimNum = the animation
; Calls: C2Scene_SetAnim (JMP).
C2Scene_SetStandAnim:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    TDC                         ; B = 0 for the TAX
    LDA.w C2Scene_WalkTask.Facing,X
    AND.b #!C2Scene_FacingMask
    TAX
    LDA.l C2Scene_StandAnims,X
    STA.b !C2Scene_AnimNum
    LDA.b !C2Scene_AnimChar
    CMP.b #!C2Scene_AltAnimChar
    BNE .set
    CLC
    LDA.b !C2Scene_AnimNum
    ADC.b #!C2Scene_AltAnimOfs
    STA.b !C2Scene_AnimNum
.set:
    LDA.b !C2Scene_AnimNum
    JMP C2Scene_SetAnim

; $C2:39AA — C2Scene_StandAnims (4 bytes, $39AA–$39AD)
; Stand animation numbers per facing: up, down, left, right.
C2Scene_StandAnims:
    db $03,$00,$06,$09

; $C2:39AE — C2Scene_OnTrigTiles (21 bytes, $39AE–$39C2)
; C=1 when both upper property nibbles (.PropUL, .PropUR) have bit 2
; set (C2Scene_TilePropTrig); the leader's callers then set
; C2Scene_TrigRecheck and C2Scene_TrigKeep, and C2Scene_ObjBFly does not
; let object B come down there.
; Callers (3 JSR sites): C2Scene_LeaderInit ($C2:355D), C2Scene_LeaderStep ($C2:375F) and
;   C2Scene_ObjBFly ($C2:4E2E).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur), DB=$00
;        (low WRAM absolute); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C as above; X = the task; A = the masked word
; No calls.
C2Scene_OnTrigTiles:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_WalkTask.PropUL,X
    AND.w #!C2Scene_TilePropTrig
    CMP.w #!C2Scene_TilePropTrig
    SEP #$20
    BNE .no
    SEC
    RTS
.no:
    CLC
    RTS

; $C2:39C3 — C2Scene_TileBlocked (18 bytes, $39C3–$39D4)
; C=1 when either upper property nibble (.PropUL, .PropUR) has bit 0 or
; 1 set (C2Scene_TilePropWall): the step is not taken.
; Callers (1 JSR site): C2Scene_LeaderInput ($C2:36B1).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur), DB=$00
;        (low WRAM absolute); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C as above; X = the task; A = the masked word
; No calls.
C2Scene_TileBlocked:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_WalkTask.PropUL,X
    AND.w #!C2Scene_TilePropWall
    SEP #$20
    BEQ .free
    SEC
    RTS
.free:
    CLC
    RTS

; $C2:39D5 — C2Scene_GetTileProps (129 bytes, $39D5–$3A55)
; Reads the property nibbles of the four 8x8 tiles around the pixel point
; (C2Scene_PropX, C2Scene_PropY) into the task's .PropUL-.PropDR
; (C2Scene_GetTileProp, with BG2's metatile map at $7E:5800 and the
; property table C2Scene_Unk7000). The point's 8x8 column and row are
; X / 8 and Y / 8; the tiles are (column - 1, row - 1), (column, row -
; 1), (column - 1, row) and (column, row), with column - 1 wrapping to
; C2Scene_MapTilesX - 1 and row - 1 kept in 0-127.
; Callers (11 JSR sites): C2Scene_LeaderInit ($C2:355A), C2Scene_LeaderInput ($C2:36AE, $C2:36D6),
;   C2Scene_LeaderScriptStart ($C2:379C), C2Scene_ObjAInit ($C2:437C), C2Scene_ObjAWait ($C2:4413),
;   C2Scene_ObjAFly ($C2:4669), C2Scene_ObjAScript ($C2:486A), C2Scene_ObjBWait ($C2:4D59) and
;   C2Scene_ObjBFly ($C2:4F31, $C2:4F70).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Tmp_00-$04, $08-$15),
;        DB=$00 (WRMPYA/B and RDMPYL absolute, for the lookups);
;        C2Scene_PropX/Y set; C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; A = .PropDR; Y as C2Scene_GetTileProp
;        leaves it; C2Scene_PropX/Y = the column and row;
;        C2Scene_PropMap/PropTable set; C2Tmp_00-$04 changed
; Calls: C2Scene_GetTileProp.
C2Scene_GetTileProps:
    REP #$20
    LDA.b !C2Scene_PropX
    LSR A                       ; / C2Scene_TilePx
    LSR A
    LSR A
    STA.b !C2Scene_PropX
    LDA.b !C2Scene_PropY
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_PropY
    SEP #$20
    LDY.w #(!C2Scene_BgMaps+!C2Scene_MapBytes)&$FFFF ; layer 2's map
    STY.b !C2Scene_PropMap
    LDA.b #bank(!C2Scene_BgMaps)
    STA.b !C2Scene_PropMap+2
    LDY.w #!C2Scene_Unk7000&$FFFF
    STY.b !C2Scene_PropTable
    LDA.b #bank(!C2Scene_Unk7000)
    STA.b !C2Scene_PropTable+2
    LDX.b !C2Scene_TaskCur
    REP #$20
    LDA.b !C2Scene_PropX
    DEC A
    BPL .ul_col
    LDA.w #!C2Scene_MapTilesX-1
.ul_col:
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_PropY
    DEC A
    AND.w #!C2Scene_MapTilesY-1
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_WalkTask.PropUL,X
    LDA.b !C2Scene_PropX
    STA.b !C2Scene_PropCol
    REP #$20
    LDA.b !C2Scene_PropY
    DEC A
    AND.w #!C2Scene_MapTilesY-1
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_WalkTask.PropUR,X
    REP #$20
    LDA.b !C2Scene_PropX
    DEC A
    BPL .dl_col
    LDA.w #!C2Scene_MapTilesX-1
.dl_col:
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_PropY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_WalkTask.PropDL,X
    LDA.b !C2Scene_PropX
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_PropY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_WalkTask.PropDR,X
    RTS

; $C2:3A56 — C2Scene_SetStepTarget (57 bytes, $3A56–$3A8E)
; .TargetX/Y = the task's position, moved C2Scene_TilePx (8) pixels in
; the direction of each non-zero whole-pixel velocity (.XVel, .YVel;
; minus for a negative one).
; Callers (3 JSR sites): C2Scene_LeaderInput ($C2:369E), C2Scene_ObjAFly ($C2:4659) and
;   C2Scene_ObjBFly ($C2:4F21).
; Entry: M=0, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; Y = .YVel; A = the Y step or the new
;        .TargetY
; No calls.
C2Scene_SetStepTarget:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,X
    STA.w C2Scene_WalkTask.TargetX,X
    LDA.w C2Scene_Task.SprY,X
    STA.w C2Scene_WalkTask.TargetY,X
    LDA.w #!C2Scene_TilePx
    LDY.w C2Scene_Task.XVel,X
    BEQ .y
    BPL .add_x
    LDA.w #-!C2Scene_TilePx
.add_x:
    CLC
    ADC.w C2Scene_WalkTask.TargetX,X
    STA.w C2Scene_WalkTask.TargetX,X
.y:
    LDA.w #!C2Scene_TilePx
    LDY.w C2Scene_Task.YVel,X
    BEQ .done
    BPL .add_y
    LDA.w #-!C2Scene_TilePx
.add_y:
    CLC
    ADC.w C2Scene_WalkTask.TargetY,X
    STA.w C2Scene_WalkTask.TargetY,X
.done:
    RTS

; $C2:3A8F — C2Scene_WrapStepTarget (34 bytes, $3A8F–$3AB0)
; Wraps .TargetX/Y into the scene map as C2Scene_WrapTaskPos does the
; position: X + or - C2Scene_MapWidthPx (once), Y AND
; C2Scene_MapHeightMask.
; Callers (3 JSR sites): C2Scene_LeaderInput ($C2:36A1), C2Scene_ObjAFly ($C2:465C) and
;   C2Scene_ObjBFly ($C2:4F24).
; Entry: M=0, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .TargetY; Y unchanged
; No calls.
C2Scene_WrapStepTarget:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_WalkTask.TargetX,X
    BPL .not_negative
    CLC
    ADC.w #!C2Scene_MapWidthPx
    BRA .store_x
.not_negative:
    CMP.w #!C2Scene_MapWidthPx
    BCC .store_x
    SBC.w #!C2Scene_MapWidthPx
.store_x:
    STA.w C2Scene_WalkTask.TargetX,X
    LDA.w C2Scene_WalkTask.TargetY,X
    AND.w #!C2Scene_MapHeightMask
    STA.w C2Scene_WalkTask.TargetY,X
    RTS

; $C2:3AB1 — C2Scene_ObjCountUp (9 bytes, $3AB1–$3AB9, with the handlers
; C2Scene_ObjCountUpNone $C2:3AC2, C2Scene_ObjCountUpA $C2:3AC3 and
; C2Scene_ObjCountUpB $C2:3AC7 to $3ACA after the table)
; Adds one to the selected object's flags byte (its count,
; C2Scene_ObjCountMask): C2Scene_Unk0294 for C2Scene_ObjSelA,
; C2Scene_ObjBFlags for C2Scene_ObjSelB, nothing for 0 and 1. A party
; member has got on (C2Scene_ObjWatchFull compares the count with the
; party's).
; Callers (3 JSR sites): C2Scene_LeaderBoardX ($C2:38DC), C2Scene_MemberBoardX ($C2:3E5E) and
;   C2Scene_MemberBoardY ($C2:3EC2).
; Entry: M=1, X=0, DP=$0000 (TDC for 0), DB=$00 (low WRAM absolute)
; Exit:  M=1, X=0; A = C2Scene_ObjSel * 2 (B = 0), X the same
; No calls.
C2Scene_ObjCountUp:
    TDC                         ; B = 0 for the TAX
    LDA.w !C2Scene_ObjSel
    ASL A
    TAX
    JMP (C2Scene_ObjCountUpTable,X)

; $C2:3ABA — C2Scene_ObjCountUpTable (4 words, $3ABA–$3AC1)
; C2Scene_ObjCountUp's handler for C2Scene_ObjSel 0-3.
C2Scene_ObjCountUpTable:
    dw C2Scene_ObjCountUpNone   ; 0
    dw C2Scene_ObjCountUpNone   ; 1
    dw C2Scene_ObjCountUpA      ; 2 (C2Scene_ObjSelA)
    dw C2Scene_ObjCountUpB      ; 3 (C2Scene_ObjSelB)

C2Scene_ObjCountUpNone:         ; header: see C2Scene_ObjCountUp
    RTS

C2Scene_ObjCountUpA:            ; header: see C2Scene_ObjCountUp
    INC.w !C2Scene_Unk0294
    RTS

C2Scene_ObjCountUpB:            ; header: see C2Scene_ObjCountUp
    INC.w !C2Scene_ObjBFlags
    RTS

; $C2:3ACB — C2Scene_SetEntryTile (23 bytes, $3ACB–$3AE1)
; Loc_EntryX/Y = C2Scene_StartX/Y / 8 (the party's 8x8 tile; the inverse
; of C2Scene_SetStartPos). The X store is a word, so it writes
; Loc_EntryY too before the Y store replaces it.
; Callers (5 JSR sites): C2Scene_LeaderLeaveB ($C2:34F3), C2Scene_LeaderInit ($C2:352D),
;   C2Scene_LeaderStep ($C2:3742), C2Scene_LeaderBoardY ($C2:384F) and C2Scene_LeaderBoardX
;   ($C2:38EF).
; Callers note: the C2Scene_LeaderLeaveB site is the tail that C2Scene_LeaderLeaveA
;   branches into, so it serves both.
; Entry: M any (REP #$20 here), X=0, DP any, DB=$00 (DP_Field and low
;        WRAM absolute)
; Exit:  M=1, X=0; A = C2Scene_StartY / 8 (B its high byte); X, Y
;        unchanged
; No calls.
C2Scene_SetEntryTile:
    REP #$20
    LDA.w !C2Scene_StartX
    LSR A
    LSR A
    LSR A
    STA.w !DP_Field+!Loc_EntryX
    LDA.w !C2Scene_StartY
    LSR A
    LSR A
    LSR A
    SEP #$20
    STA.w !DP_Field+!Loc_EntryY
    RTS

; ============================================================
; The other party members' task ($C2:3AE2–$C2:42DC)
; ============================================================
; C2Scene_MemberTask is the task handler of the sprites of party slots 1
; and 2 (C2Scene_FollowTask.Slot); like C2Scene_LeaderTask it has no
; reference in the bank's code. While C2Scene_ObjWatch is idle the
; member follows the leader: every C2Scene_FollowWait frames (when not
; already within 16 or 32 pixels of the party's position) it picks a
; point of the leader's trail (C2Scene_TrailX/Y: the last step for slot
; 1, the one before for slot 2) and walks there in at most two legs, one
; per axis, first trying the order whose straight lines cross no wall
; tile (C2Scene_PathBlocked). While C2Scene_TrigWatch waits it runs its
; C2Scene_MemberWords script; when an object is selected it walks to the
; leader's position and counts itself in, and on leaving it is put at
; the object's position.
;
; Direct page work bytes:
!C2Scene_NearTop = !C2Tmp_00           ; 16-bit: the box C2Scene_LeaderNear16/32 test
!C2Scene_NearBottom = !C2Tmp_02
!C2Scene_NearLeft = !C2Tmp_04
!C2Scene_NearRight = !C2Tmp_06
!C2Scene_NearX = !C2Tmp_08             ; 16-bit: the party's position
!C2Scene_NearY = !C2Tmp_0A
!C2Scene_RouteFromX = !C2Tmp_08        ; 8x8 tile column of the member (C2Scene_PathBlocked's input)
!C2Scene_RouteToX = !C2Tmp_09          ; and of the point it goes to
!C2Scene_RouteFromY = !C2Tmp_0A        ; tile rows
!C2Scene_RouteToY = !C2Tmp_0B
!C2Scene_RouteAbsDX = !C2Tmp_08        ; 16-bit |.DeltaX| (C2Scene_MemberRouteOpen)
!C2Scene_ScanX = !C2Tmp_05             ; C2Scene_ScanRow/ScanCol: the column and row walked along
!C2Scene_ScanY = !C2Tmp_06
!C2Scene_ScanEnd = !C2Tmp_07           ; the column (row) the scan ends at
!C2Scene_PathResult = !C2Tmp_0E        ; C2Scene_PathXYBlocked / C2Scene_PathYXBlocked
!C2Scene_TrailLeft = !C2Tmp_16         ; C2Scene_MemberRouteTrail: trail entries still to try
!C2Scene_TrailIdx = !C2Tmp_19          ; 16-bit byte offset of the trail entry tried
!C2Scene_TrailResult = !C2Tmp_1B       ; its C2Scene_PathBlocked result

; $C2:3AE2 — C2Scene_MemberTask (45 bytes, $3AE2–$3B0E)
; Task handler. Does nothing while the Party_Members byte of .Slot has
; C2Scene_PartySlotEmpty set. Otherwise zeroes .State when a watcher's
; state has changed (as C2Scene_LeaderTask) and runs the
; C2Scene_MemberStates handler of C2Scene_Unk027E.
; Callers note: none found (see the banner).
; Entry: M=1, X=0, X = C2Scene_TaskCur = the task (C2Scene_TaskRunAll),
;        DP=$0000 (TDC for 0), DB=$00 (low WRAM absolute)
; Exit:  C=0 (the task never ends); otherwise as the state's handler
; Calls: a C2Scene_MemberStates handler (JMP (abs,X)).
C2Scene_MemberTask:
    TDC                         ; A = DP = 0: B = 0 for the TAX here and in the handlers
    LDA.w C2Scene_FollowTask.Slot,X
    TAX
    LDA.l !Party_Members,X
    BPL .present                ; not C2Scene_PartySlotEmpty
    CLC
    RTS
.present:
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_Unk027E
    CMP.w !C2Scene_Unk027F
    BEQ .obj_same
    STZ.w C2Scene_FollowTask.State,X
.obj_same:
    LDA.w !C2Scene_Unk0280
    CMP.w !C2Scene_Unk0281
    BEQ .trig_same
    STZ.w C2Scene_FollowTask.State,X
.trig_same:
    LDA.w !C2Scene_Unk027E
    ASL A
    TAX
    JMP (C2Scene_MemberStates,X)

; $C2:3B0F — C2Scene_MemberStates (6 words, $3B0F–$3B1A)
; C2Scene_MemberTask's handler for each C2Scene_Unk027E state 0-5.
C2Scene_MemberStates:
    dw C2Scene_MemberWalk       ; 0 (C2Scene_ObjWatchStIdle)
    dw C2Scene_MemberNone       ; 1
    dw C2Scene_MemberNone       ; 2 (C2Scene_ObjWatchStBusyA)
    dw C2Scene_MemberNone       ; 3 (C2Scene_ObjWatchStBusyB)
    dw C2Scene_MemberBoard      ; 4 (C2Scene_ObjWatchStFull)
    dw C2Scene_MemberLeave      ; 5 (C2Scene_ObjWatchStEmpty)

; $C2:3B1B — C2Scene_MemberWalk (61 bytes, $3B1B–$3B57)
; ObjWatch state 0. Unless C2Scene_Mode is 0 or C2Scene_ModeIdle1: not
; moving (.Facing loses C2Scene_WalkMoving), the member's stand animation
; (C2Scene_SetStandAnim) and C2Anim_Run. Otherwise it runs entry
; C2Scene_Unk0280 * 4 + .State of C2Scene_MemberWalkSteps.
; Callers note: none direct (C2Scene_MemberStates).
; Entry: M=1, X=0, B=0 (the 16-bit TAX; from C2Scene_MemberTask's TDC),
;        DP=$0000 (C2Tmp_00), DB=$00 (low WRAM absolute)
; Exit:  C=0, M=1, X = the task, A, Y clobbered (other modes); or as the
;        step's handler, C2Tmp_00 = C2Scene_Unk0280 * 8
; Calls: C2Scene_SetStandAnim, C2Anim_Run, a C2Scene_MemberWalkSteps
;   handler (JMP (abs,X)).
C2Scene_MemberWalk:
    LDA.w !C2Scene_Mode
    CMP.b #!C2Scene_ModeIdle1
    BEQ .walk
    CMP.b #0
    BEQ .walk
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    STA.w C2Scene_FollowTask.Facing,X
    LDA.w C2Scene_FollowTask.Slot,X
    TAX
    LDA.l !Party_Members,X
    STA.b !C2Scene_AnimChar
    JSR C2Scene_SetStandAnim
    JSR C2Anim_Run
    CLC
    RTS
.walk:
    LDA.w !C2Scene_Unk0280
    ASL A                       ; * C2Scene_StepsPerTrigState
    ASL A
    ASL A
    STA.b !C2Tmp_00
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.State,X
    ASL A
    ADC.b !C2Tmp_00             ; no CLC: C = .State bit 7, 0 for steps 0-3
    TAX
    JMP (C2Scene_MemberWalkSteps,X)

; $C2:3B58 — C2Scene_MemberWalkSteps (8 words, $3B58–$3B67)
; C2Scene_MemberWalk's handler per C2Scene_Unk0280 state (4 words each)
; and .State. Entry 7 is 0 (it would jump to $C2:0000); no handler sets
; .State 3 in state C2Scene_TrigStWait.
C2Scene_MemberWalkSteps:
    dw C2Scene_MemberInit       ; state 0 (check), step 0
    dw C2Scene_MemberFollow     ; step 1
    dw C2Scene_MemberMoveX      ; step 2
    dw C2Scene_MemberMoveY      ; step 3
    dw C2Scene_MemberScriptStart ; state C2Scene_TrigStWait, step 0
    dw C2Scene_MemberScriptRun  ; step 1
    dw C2Scene_MemberScriptDone ; step 2
    dw $0000                    ; step 3: none

; $C2:3B68 — C2Scene_MemberNone (2 bytes, $3B68–$3B69)
; ObjWatch states 1-3: nothing (the member stays where it is while the
; object is busy); C=0.
; Callers note: none direct (C2Scene_MemberStates).
; Entry: M, X, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_MemberNone:
    CLC
    RTS

; $C2:3B6A — C2Scene_MemberBoard (10 bytes, $3B6A–$3B73)
; ObjWatch state 4 (C2Scene_ObjWatchStFull): runs entry .State of
; C2Scene_MemberBoardSteps.
; Callers note: none direct (C2Scene_MemberStates).
; Entry: M=1, X=0, B=0 (the 16-bit TAX; from C2Scene_MemberTask's TDC),
;        DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM absolute)
; Exit:  as the step's handler
; Calls: a C2Scene_MemberBoardSteps handler (JMP (abs,X)).
C2Scene_MemberBoard:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.State,X
    ASL A
    TAX
    JMP (C2Scene_MemberBoardSteps,X)

; $C2:3B74 — C2Scene_MemberBoardSteps (4 words, $3B74–$3B7B)
; C2Scene_MemberBoard's handler for .State 0-3.
C2Scene_MemberBoardSteps:
    dw C2Scene_MemberBoardStart ; 0: aim at the leader
    dw C2Scene_MemberBoardX     ; 1: a leg in X
    dw C2Scene_MemberBoardY     ; 2: a leg in Y
    dw C2Scene_MemberBoardDone  ; 3: counted in

; $C2:3B7C — C2Scene_MemberLeave (8 bytes, $3B7C–$3B83)
; ObjWatch state 5 (C2Scene_ObjWatchStEmpty): runs entry C2Scene_ObjSel
; of C2Scene_MemberLeaveTable.
; Callers note: none direct (C2Scene_MemberStates).
; Entry: M=1, X=0, B=0 (the 16-bit TAX; from C2Scene_MemberTask's TDC),
;        DP any, DB=$00 (low WRAM absolute)
; Exit:  as the handler
; Calls: a C2Scene_MemberLeaveTable handler (JMP (abs,X)).
C2Scene_MemberLeave:
    LDA.w !C2Scene_ObjSel
    ASL A
    TAX
    JMP (C2Scene_MemberLeaveTable,X)

; $C2:3B84 — C2Scene_MemberLeaveTable (4 words, $3B84–$3B8B)
; C2Scene_MemberLeave's handler for C2Scene_ObjSel 0-3. Unlike the
; leader's table, selector 1 is treated as object A.
C2Scene_MemberLeaveTable:
    dw C2Scene_MemberLeaveNone  ; 0
    dw C2Scene_MemberLeaveA     ; 1
    dw C2Scene_MemberLeaveA     ; 2 (C2Scene_ObjSelA)
    dw C2Scene_MemberLeaveB     ; 3 (C2Scene_ObjSelB)

; $C2:3B8C — C2Scene_MemberLeaveNone (2 bytes, $3B8C–$3B8D)
; No object selected: nothing; C=0.
; Callers note: none direct (C2Scene_MemberLeaveTable).
; Entry: M, X, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_MemberLeaveNone:
    CLC
    RTS

; $C2:3B8E — C2Scene_MemberLeaveA (26 bytes, $3B8E–$3BA7)
; Leaving object A: .State = 0, the sprite at C2Scene_ObjAX/Y, one off
; C2Scene_Unk0294 (the object's count), every frame of the state, as
; C2Scene_LeaderLeaveA but without C2Scene_StartX/Y, .Unk26, the facing
; and the entry tile.
; Callers note: none direct (C2Scene_MemberLeaveTable).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A = C2Scene_ObjAY
; No calls.
C2Scene_MemberLeaveA:
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_FollowTask.State,X
    REP #$20
    LDA.w !C2Scene_ObjAX
    STA.w C2Scene_Task.SprX,X
    LDA.w !C2Scene_ObjAY
    STA.w C2Scene_Task.SprY,X
    SEP #$20
    DEC.w !C2Scene_Unk0294
    CLC
    RTS

; $C2:3BA8 — C2Scene_MemberLeaveB (26 bytes, $3BA8–$3BC1)
; C2Scene_MemberLeaveA for object B (C2Scene_ObjBX/Y,
; C2Scene_ObjBFlags).
; Callers note: none direct (C2Scene_MemberLeaveTable).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A = C2Scene_ObjBY
; No calls.
C2Scene_MemberLeaveB:
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_FollowTask.State,X
    REP #$20
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_Task.SprX,X
    LDA.w !C2Scene_ObjBY
    STA.w C2Scene_Task.SprY,X
    SEP #$20
    DEC.w !C2Scene_ObjBFlags
    CLC
    RTS

; $C2:3BC2 — C2Scene_MemberInit (119 bytes, $3BC2–$3C38)
; Step 0 of TrigWatch state 0: sets the sprite up and falls into
; C2Scene_MemberFollow. .State = 1; .SprAttr = C2Scene_MemberAttr1F5 at
; Loc_Id C2Scene_Loc1F5, else C2Scene_MemberAttr, ORed with
; C2Scene_Member1Pal and .SprTile = C2Scene_Member1Tile for slot 1, else
; C2Scene_Member2Pal and C2Scene_Member2Tile; the position at
; C2Scene_StartX/Y with both fractions 0; the four velocity words 0;
; .Frames = 0; .Facing and .PrevFacing = Loc_EntryFacing AND
; C2Scene_FacingMask; .Unk26 = 0; the stand animation
; (C2Scene_MemberStand).
; Callers note: none direct (C2Scene_MemberWalkSteps).
; Entry: M any (SEP #$20 here), X=0, DP=$0000, DB=$00 (DP_Field and low
;        WRAM absolute)
; Exit:  as C2Scene_MemberFollow
; Calls: C2Scene_MemberStand; then falls into C2Scene_MemberFollow.
C2Scene_MemberInit:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_FollowTask.State,X
    LDY.w !DP_Field+!Loc_Id
    CPY.w #!C2Scene_Loc1F5
    BNE .attr_normal
    LDA.b #!C2Scene_MemberAttr1F5
    BRA .attr_set
.attr_normal:
    LDA.b #!C2Scene_MemberAttr
.attr_set:
    STA.w C2Scene_Task.SprAttr,X
    LDA.w C2Scene_FollowTask.Slot,X
    CMP.b #!C2Scene_Slot1
    BNE .slot2
    LDA.b #!C2Scene_Member1Pal
    ORA.w C2Scene_Task.SprAttr,X
    STA.w C2Scene_Task.SprAttr,X
    LDA.b #!C2Scene_Member1Tile
    STA.w C2Scene_Task.SprTile,X
    STZ.w C2Scene_Task.SprTile+1,X
    BRA .place
.slot2:
    LDA.b #!C2Scene_Member2Pal
    ORA.w C2Scene_Task.SprAttr,X
    STA.w C2Scene_Task.SprAttr,X
    LDA.b #!C2Scene_Member2Tile
    STA.w C2Scene_Task.SprTile,X
    STZ.w C2Scene_Task.SprTile+1,X
.place:
    REP #$20
    LDA.w !C2Scene_StartX
    STA.w C2Scene_Task.SprX,X
    STZ.w C2Scene_Task.XFrac,X
    LDA.w !C2Scene_StartY
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    SEP #$20
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask
    STA.w C2Scene_FollowTask.PrevFacing,X
    STA.w C2Scene_FollowTask.Facing,X
    STZ.w C2Scene_FollowTask.Unk26,X
    JSR C2Scene_MemberStand

; $C2:3C39 — C2Scene_MemberFollow (161 bytes, $3C39–$3CD9)
; Step 1 of TrigWatch state 0: decides the next move.
; - Fewer than C2Scene_FollowWait .Frames since the last move started,
;   or the party's position within 16 (slot 1, C2Scene_LeaderNear16) or
;   32 pixels (slot 2, C2Scene_LeaderNear32; .Frames is then zeroed):
;   it stands. Its idle count (C2Scene_IdleFrames + slot) goes up; below
;   C2Scene_IdleAnimAt the stand animation is set again
;   (C2Scene_MemberStand), at it C2Scene_AnimIdle1 (slot 2:
;   C2Scene_AnimIdle2) once, as the leader's; C2Anim_Run.
; - Otherwise: the target is a trail point (C2Scene_MemberTrailTarget),
;   the route is planned (C2Scene_MemberDelta, C2Scene_MemberRoute), the
;   first leg's velocity, facing and walk animation are set
;   (C2Scene_MemberFirstLeg, C2Scene_FaceVelocity,
;   C2Scene_MemberWalkAnim), .Frames = 0, and it goes on in
;   C2Scene_MemberMoveX (.State 2) for a C2Scene_RouteXFirst route, else
;   C2Scene_MemberMoveY (.State 3), this frame.
; Callers (2 JMP sites): C2Scene_MemberMoveX ($C2:3CF7) and C2Scene_MemberMoveY ($C2:3D58).
; Callers note: also reached through C2Scene_MemberWalkSteps, and C2Scene_MemberInit
;   falls into it; the two JMPs are C2Scene_MemberMoveX and C2Scene_MemberMoveY
;   jumping back to it.
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A, Y and C2Tmp_00-$1B clobbered;
;        or as C2Scene_MemberMoveX/MoveY
; Calls: C2Scene_LeaderNear16, C2Scene_LeaderNear32,
;   C2Scene_MemberTrailTarget, C2Scene_MemberDelta, C2Scene_MemberRoute,
;   C2Scene_MemberFirstLeg, C2Scene_FaceVelocity, C2Scene_MemberWalkAnim,
;   C2Scene_SetAnim, C2Scene_MemberStand, C2Anim_Run.
C2Scene_MemberFollow:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.w #!C2Scene_FollowWait
    BCC .stand
    LDA.w C2Scene_FollowTask.Slot,X
    BIT.w #!C2Scene_Slot1
    BEQ .far_box
    JSR C2Scene_LeaderNear16
    BCS .near
    BRA .plan
.far_box:
    JSR C2Scene_LeaderNear32
    BCS .near
.plan:
    JSR C2Scene_MemberTrailTarget
    JSR C2Scene_MemberDelta
    JSR C2Scene_MemberRoute
    JSR C2Scene_MemberFirstLeg
    JSR C2Scene_FaceVelocity
    JSR C2Scene_MemberWalkAnim
    STZ.w C2Scene_Task.Frames,X
    STZ.w C2Scene_Task.Frames+1,X
    LDA.w C2Scene_FollowTask.Route,X
    BIT.b #!C2Scene_RouteXFirst
    BEQ .y_first
    LDA.b #2
    STA.w C2Scene_FollowTask.State,X
    BRA C2Scene_MemberMoveX
.y_first:
    LDA.b #3
    STA.w C2Scene_FollowTask.State,X
    JMP C2Scene_MemberMoveY
.near:
    REP #$20
    STZ.w C2Scene_Task.Frames,X
.stand:
    SEP #$20
    TDC                         ; B = 0 for the TAX/TYX index
    TXY
    LDA.w C2Scene_FollowTask.Slot,Y
    CMP.b #!C2Scene_Slot2
    BEQ .idle2
    INC.w !C2Scene_IdleFrames+1
    LDA.w !C2Scene_IdleFrames+1
    CMP.b #!C2Scene_IdleAnimAt
    BCC .stand1
    CMP.b #!C2Scene_IdleSet
    BEQ .hold1
    LDA.b #!C2Scene_AnimIdle1
    JSR C2Scene_SetAnim
.hold1:
    LDA.b #!C2Scene_IdleHold
    STA.w !C2Scene_IdleFrames+1
    BRA .animate
.stand1:
    TYX
    JSR C2Scene_MemberStand
    BRA .animate
.idle2:
    INC.w !C2Scene_IdleFrames+2
    LDA.w !C2Scene_IdleFrames+2
    CMP.b #!C2Scene_IdleAnimAt
    BCC .stand2
    CMP.b #!C2Scene_IdleSet
    BEQ .hold2
    LDA.b #!C2Scene_AnimIdle2
    JSR C2Scene_SetAnim
.hold2:
    LDA.b #!C2Scene_IdleHold
    STA.w !C2Scene_IdleFrames+2
    BRA .animate
.stand2:
    TYX
    JSR C2Scene_MemberStand
.animate:
    JSR C2Anim_Run
    CLC
    RTS

; $C2:3CDA — C2Scene_MemberMoveX (97 bytes, $3CDA–$3D3A)
; Step 2 of TrigWatch state 0, a leg in X. Once C2Scene_FollowWait frames
; have passed and .SprX is on an 8-pixel boundary, .State = 1 and it
; plans again (JMP C2Scene_MemberFollow). Until .SprX = .TargetX it
; moves (C2Scene_TaskMove, C2Scene_WrapTaskPos). There, with another leg
; left (.Route's count - 1, stored over the whole .Route byte) it turns to
; Y: .State 3, C2Scene_MemberYLeg, C2Scene_FaceVelocity,
; C2Scene_MemberWalkAnim; with none, .State 1 and the stand animation.
; Then C2Anim_Run.
; Callers note: none direct (C2Scene_MemberWalkSteps); C2Scene_MemberFollow
;   branches to it.
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered; or as
;        C2Scene_MemberFollow
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_MemberYLeg,
;   C2Scene_FaceVelocity, C2Scene_MemberWalkAnim, C2Scene_MemberStand,
;   C2Anim_Run.
C2Scene_MemberMoveX:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.w #!C2Scene_FollowWait
    BCC .move
    LDA.w C2Scene_Task.SprX,X
    AND.w #!C2Scene_PxInTileMask
    BNE .move
    SEP #$20
    LDA.b #1
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    JMP C2Scene_MemberFollow
.move:
    LDA.w C2Scene_Task.SprX,X
    CMP.w C2Scene_FollowTask.TargetX,X
    BEQ .arrived
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    BRA .animate
.arrived:
    LDA.w C2Scene_FollowTask.Route,X
    AND.w #!C2Scene_RouteLegs
    DEC A
    BEQ .done
    SEP #$20
    STA.w C2Scene_FollowTask.Route,X
    LDA.b #3
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    JSR C2Scene_MemberYLeg
    JSR C2Scene_FaceVelocity
    JSR C2Scene_MemberWalkAnim
    BRA .animate
.done:
    SEP #$20
    LDA.b #1
    STA.w C2Scene_FollowTask.State,X
    JSR C2Scene_MemberStand
    REP #$20
.animate:
    JSR C2Anim_Run
    CLC
    RTS

; $C2:3D3B — C2Scene_MemberMoveY (97 bytes, $3D3B–$3D9B)
; Step 3 of TrigWatch state 0: C2Scene_MemberMoveX with the axes swapped
; (.SprY, .TargetY; the next leg is in X: .State 2,
; C2Scene_MemberXLeg).
; Callers (1 JMP site): C2Scene_MemberFollow ($C2:3C84).
; Callers note: also reached through C2Scene_MemberWalkSteps.
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered; or as
;        C2Scene_MemberFollow
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_MemberXLeg,
;   C2Scene_FaceVelocity, C2Scene_MemberWalkAnim, C2Scene_MemberStand,
;   C2Anim_Run.
C2Scene_MemberMoveY:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.w #!C2Scene_FollowWait
    BCC .move
    LDA.w C2Scene_Task.SprY,X
    AND.w #!C2Scene_PxInTileMask
    BNE .move
    SEP #$20
    LDA.b #1
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    JMP C2Scene_MemberFollow
.move:
    LDA.w C2Scene_Task.SprY,X
    CMP.w C2Scene_FollowTask.TargetY,X
    BEQ .arrived
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    BRA .animate
.arrived:
    LDA.w C2Scene_FollowTask.Route,X
    AND.w #!C2Scene_RouteLegs
    DEC A
    BEQ .done
    SEP #$20
    STA.w C2Scene_FollowTask.Route,X
    LDA.b #2
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    JSR C2Scene_MemberXLeg
    JSR C2Scene_FaceVelocity
    JSR C2Scene_MemberWalkAnim
    BRA .animate
.done:
    SEP #$20
    LDA.b #1
    STA.w C2Scene_FollowTask.State,X
    JSR C2Scene_MemberStand
    REP #$20
.animate:
    JSR C2Anim_Run
    CLC
    RTS

; $C2:3D9C — C2Scene_MemberScriptStart (37 bytes, $3D9C–$3DC0)
; Step 0 of TrigWatch state C2Scene_TrigStWait: as
; C2Scene_LeaderScriptStart with the member's own word,
; C2Scene_MemberWords + .Slot * 2 (no tile property read here).
; Callers note: none direct (C2Scene_MemberWalkSteps).
; Entry: M=1, X=0, B=0 (the 16-bit TAY; from C2Scene_MemberTask's TDC),
;        DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=0; A = 0 (no word yet), or A, X, Y as the script leaves
;        them
; Calls: C2Scene_TaskRunScript.
C2Scene_MemberScriptStart:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.Slot,X
    ASL A
    TAY
    REP #$20
    LDA.w !C2Scene_MemberWords,Y
    BEQ .done
    STA.w C2Scene_Task.ScriptPtr,X
    SEP #$20
    LDA.b #bank(!C2Scene_ScriptBuf)
    STA.w C2Scene_Task.ScriptBank,X
    STZ.w C2Scene_Task.ScriptWait,X
    INC.w C2Scene_FollowTask.State,X
    JSR C2Scene_TaskRunScript
    REP #$20
.done:
    CLC
    RTS

; $C2:3DC1 — C2Scene_MemberScriptRun (34 bytes, $3DC1–$3DE2)
; Step 1 of TrigWatch state C2Scene_TrigStWait: runs the script; when it
; ends, .State = 2. Every frame the sprite's position goes to the words
; at C2Scene_StartX/Y + the .Slot word * 4 ($0287-$028E for slots 1 and
; 2: probably the members' positions, as C2Scene_StartX/Y is the
; leader's).
; Callers note: none direct (C2Scene_MemberWalkSteps).
; Entry: M any, X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=0, X=0; X = the task; Y = .Slot * 4; A = .SprY
; Calls: C2Scene_TaskRunScript.
C2Scene_MemberScriptRun:
    JSR C2Scene_TaskRunScript
    BCC .running
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_FollowTask.State,X
.running:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.Slot,X
    ASL A
    ASL A
    TAY
    LDA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_StartX,Y
    LDA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_StartY,Y
    CLC
    RTS

; $C2:3DE3 — C2Scene_MemberScriptDone (2 bytes, $3DE3–$3DE4)
; Step 2 of TrigWatch state C2Scene_TrigStWait: nothing; C=0.
; Callers note: none direct (C2Scene_MemberWalkSteps).
; Entry: M, X, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_MemberScriptDone:
    CLC
    RTS

; $C2:3DE5 — C2Scene_MemberBoardStart (50 bytes, $3DE5–$3E16)
; Step 0 of ObjWatch state 4: the target is the party's position on its
; 8x8 tile (C2Scene_MemberLeaderTarget); route, first leg, facing and
; walk animation as C2Scene_MemberFollow plans them; .Frames = 0; then
; C2Scene_MemberBoardX (.State 1) for a C2Scene_RouteXFirst route, else
; C2Scene_MemberBoardY (.State 2), this frame.
; Callers note: none direct (C2Scene_MemberBoardSteps).
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  as C2Scene_MemberBoardX / C2Scene_MemberBoardY
; Calls: C2Scene_MemberLeaderTarget, C2Scene_MemberDelta,
;   C2Scene_MemberRoute, C2Scene_MemberFirstLeg, C2Scene_FaceVelocity,
;   C2Scene_MemberWalkAnim.
C2Scene_MemberBoardStart:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_MemberLeaderTarget
    JSR C2Scene_MemberDelta
    JSR C2Scene_MemberRoute
    JSR C2Scene_MemberFirstLeg
    JSR C2Scene_FaceVelocity
    JSR C2Scene_MemberWalkAnim
    STZ.w C2Scene_Task.Frames,X
    STZ.w C2Scene_Task.Frames+1,X
    LDA.w C2Scene_FollowTask.Route,X
    BIT.b #!C2Scene_RouteXFirst
    BEQ .y_first
    LDA.b #1
    STA.w C2Scene_FollowTask.State,X
    BRA C2Scene_MemberBoardX
.y_first:
    LDA.b #2
    STA.w C2Scene_FollowTask.State,X
    JMP C2Scene_MemberBoardY

; $C2:3E17 — C2Scene_MemberBoardX (100 bytes, $3E17–$3E7A)
; Step 1 of ObjWatch state 4, a leg in X: moves until .SprX = .TargetX.
; There, with another leg left it turns to Y (.State 2,
; C2Scene_MemberYLeg, C2Scene_FaceVelocity, C2Scene_MemberWalkAnim);
; with none, at the party's position (C2Scene_StartX/Y) the object's
; count goes up (C2Scene_ObjCountUp) and .State = 3; elsewhere .State = 0
; (aim again) and the stand animation. Then C2Anim_Run.
; Callers note: none direct (C2Scene_MemberBoardSteps);
;   C2Scene_MemberBoardStart branches to it.
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_MemberYLeg,
;   C2Scene_FaceVelocity, C2Scene_MemberWalkAnim, C2Scene_ObjCountUp,
;   C2Scene_MemberStand, C2Anim_Run.
C2Scene_MemberBoardX:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,X
    CMP.w C2Scene_FollowTask.TargetX,X
    BEQ .arrived
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JMP .animate
.arrived:
    LDA.w C2Scene_FollowTask.Route,X
    AND.w #!C2Scene_RouteLegs
    DEC A
    BEQ .last
    SEP #$20
    STA.w C2Scene_FollowTask.Route,X
    LDA.b #2
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    JSR C2Scene_MemberYLeg
    JSR C2Scene_FaceVelocity
    JSR C2Scene_MemberWalkAnim
    BRA .animate
.last:
    LDA.w C2Scene_Task.SprX,X
    CMP.w !C2Scene_StartX
    BNE .again
    LDA.w C2Scene_Task.SprY,X
    CMP.w !C2Scene_StartY
    BNE .again
    SEP #$20
    JSR C2Scene_ObjCountUp
    LDX.b !C2Scene_TaskCur
    LDA.b #3
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    BRA .animate
.again:
    SEP #$20
    STZ.w C2Scene_FollowTask.State,X
    JSR C2Scene_MemberStand
    REP #$20
.animate:
    JSR C2Anim_Run
    CLC
    RTS

; $C2:3E7B — C2Scene_MemberBoardY (100 bytes, $3E7B–$3EDE)
; Step 2 of ObjWatch state 4: C2Scene_MemberBoardX with the axes swapped
; (.SprY, .TargetY; the next leg is in X: .State 1,
; C2Scene_MemberXLeg).
; Callers (1 JMP site): C2Scene_MemberBoardStart ($C2:3E14).
; Callers note: also reached through C2Scene_MemberBoardSteps.
; Entry: M any (REP #$20 here), X=0, DP=$0000, DB=$00 (low WRAM absolute)
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_MemberXLeg,
;   C2Scene_FaceVelocity, C2Scene_MemberWalkAnim, C2Scene_ObjCountUp,
;   C2Scene_MemberStand, C2Anim_Run.
C2Scene_MemberBoardY:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprY,X
    CMP.w C2Scene_FollowTask.TargetY,X
    BEQ .arrived
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JMP .animate
.arrived:
    LDA.w C2Scene_FollowTask.Route,X
    AND.w #!C2Scene_RouteLegs
    DEC A
    BEQ .last
    SEP #$20
    STA.w C2Scene_FollowTask.Route,X
    LDA.b #1
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    JSR C2Scene_MemberXLeg
    JSR C2Scene_FaceVelocity
    JSR C2Scene_MemberWalkAnim
    BRA .animate
.last:
    LDA.w C2Scene_Task.SprX,X
    CMP.w !C2Scene_StartX
    BNE .again
    LDA.w C2Scene_Task.SprY,X
    CMP.w !C2Scene_StartY
    BNE .again
    SEP #$20
    JSR C2Scene_ObjCountUp
    LDX.b !C2Scene_TaskCur
    LDA.b #3
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    BRA .animate
.again:
    SEP #$20
    STZ.w C2Scene_FollowTask.State,X
    JSR C2Scene_MemberStand
    REP #$20
.animate:
    JSR C2Anim_Run
    CLC
    RTS

; $C2:3EDF — C2Scene_MemberBoardDone (2 bytes, $3EDF–$3EE0)
; Step 3 of ObjWatch state 4 (counted in): nothing; C=0.
; Callers note: none direct (C2Scene_MemberBoardSteps).
; Entry: M, X, DP and DB any (no accesses)
; Exit:  C=0; nothing else changed
C2Scene_MemberBoardDone:
    CLC
    RTS

; $C2:3EE1 — C2Scene_LeaderNear16 (70 bytes, $3EE1–$3F26)
; C=1 when the party's position (C2Scene_StartX/Y) is within
; C2Scene_NearLo16 pixels before and C2Scene_NearHi16 - 1 after the
; member's .SprX/.SprY on both axes (unsigned compares, so the box does
; not wrap at the map's edges).
; Callers (1 JSR site): C2Scene_MemberFollow ($C2:3C4D).
; Entry: M=0, X=0, X = the task, DP=$0000 (C2Tmp_00-$0B), DB=$00 (low
;        WRAM absolute)
; Exit:  M=0, X=0; C as above; A clobbered; C2Scene_NearTop-NearY set;
;        X, Y unchanged
; No calls.
C2Scene_LeaderNear16:
    LDA.w C2Scene_Task.SprY,X
    SEC
    SBC.w #!C2Scene_NearLo16
    STA.b !C2Scene_NearTop
    LDA.w C2Scene_Task.SprY,X
    CLC
    ADC.w #!C2Scene_NearHi16
    STA.b !C2Scene_NearBottom
    LDA.w C2Scene_Task.SprX,X
    SEC
    SBC.w #!C2Scene_NearLo16
    STA.b !C2Scene_NearLeft
    LDA.w C2Scene_Task.SprX,X
    CLC
    ADC.w #!C2Scene_NearHi16
    STA.b !C2Scene_NearRight
    LDA.w !C2Scene_StartX
    STA.b !C2Scene_NearX
    LDA.w !C2Scene_StartY
    STA.b !C2Scene_NearY
    LDA.b !C2Scene_NearY
    CMP.b !C2Scene_NearTop
    BCC .far
    CMP.b !C2Scene_NearBottom
    BCS .far
    LDA.b !C2Scene_NearX
    CMP.b !C2Scene_NearLeft
    BCC .far
    CMP.b !C2Scene_NearRight
    BCS .far
    SEC
    RTS
.far:
    CLC
    RTS

; $C2:3F27 — C2Scene_LeaderNear32 (70 bytes, $3F27–$3F6C)
; C2Scene_LeaderNear16 with C2Scene_NearLo32 / C2Scene_NearHi32 (32
; pixels).
; Callers (1 JSR site): C2Scene_MemberFollow ($C2:3C54).
; Entry: M=0, X=0, X = the task, DP=$0000 (C2Tmp_00-$0B), DB=$00 (low
;        WRAM absolute)
; Exit:  M=0, X=0; C as above; A clobbered; C2Scene_NearTop-NearY set;
;        X, Y unchanged
; No calls.
C2Scene_LeaderNear32:
    LDA.w C2Scene_Task.SprY,X
    SEC
    SBC.w #!C2Scene_NearLo32
    STA.b !C2Scene_NearTop
    LDA.w C2Scene_Task.SprY,X
    CLC
    ADC.w #!C2Scene_NearHi32
    STA.b !C2Scene_NearBottom
    LDA.w C2Scene_Task.SprX,X
    SEC
    SBC.w #!C2Scene_NearLo32
    STA.b !C2Scene_NearLeft
    LDA.w C2Scene_Task.SprX,X
    CLC
    ADC.w #!C2Scene_NearHi32
    STA.b !C2Scene_NearRight
    LDA.w !C2Scene_StartX
    STA.b !C2Scene_NearX
    LDA.w !C2Scene_StartY
    STA.b !C2Scene_NearY
    LDA.b !C2Scene_NearY
    CMP.b !C2Scene_NearTop
    BCC .far
    CMP.b !C2Scene_NearBottom
    BCS .far
    LDA.b !C2Scene_NearX
    CMP.b !C2Scene_NearLeft
    BCC .far
    CMP.b !C2Scene_NearRight
    BCS .far
    SEC
    RTS
.far:
    CLC
    RTS

; $C2:3F6D — C2Scene_MemberTrailTarget (39 bytes, $3F6D–$3F93)
; .TargetX/Y = a trail entry: the last one C2Scene_TrailPush wrote
; (C2Scene_TrailPos - 2) for slot 1 (.Slot bit 0), the one before it
; (- 4) otherwise.
; Callers (2 JSR sites): C2Scene_MemberFollow ($C2:3C59) and C2Scene_MemberRouteTrail ($C2:40B3).
; Entry: M=0, X=0, X = the task, DP any, DB=$00 (low WRAM absolute)
; Exit:  M=0, X=0; A = the target Y; Y = the entry's offset; X unchanged
; No calls.
C2Scene_MemberTrailTarget:
    LDA.w C2Scene_FollowTask.Slot,X
    BIT.w #!C2Scene_Slot1
    BEQ .slot2
    LDA.w !C2Scene_TrailPos
    DEC A
    DEC A
    BRA .entry
.slot2:
    LDA.w !C2Scene_TrailPos
    SEC
    SBC.w #4
.entry:
    AND.w #!C2Scene_TrailMask
    TAY
    LDA.w !C2Scene_TrailX,Y
    STA.w C2Scene_FollowTask.TargetX,X
    LDA.w !C2Scene_TrailY,Y
    STA.w C2Scene_FollowTask.TargetY,X
    RTS

; $C2:3F94 — C2Scene_MemberLeaderTarget (19 bytes, $3F94–$3FA6)
; .TargetX/Y = C2Scene_StartX/Y AND C2Scene_TileSnapMask (the start of
; the party's 8x8 tile).
; Callers (1 JSR site): C2Scene_MemberBoardStart ($C2:3DE9).
; Entry: M=0, X=0, X = the task, DP any, DB=$00 (low WRAM absolute)
; Exit:  M=0, X=0; A = the target Y; X, Y unchanged
; No calls.
C2Scene_MemberLeaderTarget:
    LDA.w !C2Scene_StartX
    AND.w #!C2Scene_TileSnapMask
    STA.w C2Scene_FollowTask.TargetX,X
    LDA.w !C2Scene_StartY
    AND.w #!C2Scene_TileSnapMask
    STA.w C2Scene_FollowTask.TargetY,X
    RTS

; $C2:3FA7 — C2Scene_MemberDelta (21 bytes, $3FA7–$3FBB)
; .DeltaX/Y = .TargetX/Y - .SprX/Y.
; Callers (4 JSR sites): C2Scene_MemberFollow ($C2:3C5C), C2Scene_MemberBoardStart ($C2:3DEC) and
;   C2Scene_MemberRouteTrail ($C2:40B6, $C2:40D9).
; Entry: M=0, X=0, X = the task, DP any, DB=$00 (low WRAM absolute)
; Exit:  M=0, X=0; A = .DeltaY; X, Y unchanged
; No calls.
C2Scene_MemberDelta:
    LDA.w C2Scene_FollowTask.TargetX,X
    SEC
    SBC.w C2Scene_Task.SprX,X
    STA.w C2Scene_FollowTask.DeltaX,X
    LDA.w C2Scene_FollowTask.TargetY,X
    SEC
    SBC.w C2Scene_Task.SprY,X
    STA.w C2Scene_FollowTask.DeltaY,X
    RTS

; $C2:3FBC — C2Scene_MemberRoute (44 bytes, $3FBC–$3FE7, with the table
; C2Scene_MemberRouteTable and the handlers C2Scene_MemberRouteOpen
; $C2:3FF0 (to $404B, with dead code at $4012-$4031),
; C2Scene_MemberRouteYFirst $C2:404C, C2Scene_MemberRouteXFirst $C2:4056
; and C2Scene_MemberRouteTrail $C2:4060 to $40E3)
; Plans .Route from the member's position to its target. The 8x8 tiles of
; both go to C2Scene_PathBlocked (the target is taken as C2Scene_StartX/Y
; here, not .TargetX/Y), and its result picks the handler:
; - 0 (both paths open), C2Scene_MemberRouteOpen: one leg when .DeltaX
;   (Y only: C2Scene_RouteYFirst + 1) or .DeltaY (X only) is 0, else two,
;   along the longer axis first (Y on a tie);
; - C2Scene_PathXYBlocked: Y first, two legs;
; - C2Scene_PathYXBlocked: X first, two legs;
; - both blocked, C2Scene_MemberRouteTrail: walks back through up to
;   C2Scene_TrailLen trail entries from the last one, newest first, for
;   one with a path open from the member; the first found becomes the
;   target (on its 8x8 tile, .DeltaX/Y again) and its result picks the
;   handler (C2Scene_MemberRoute_dispatch). With none, the target is the
;   member's trail point again (C2Scene_MemberTrailTarget,
;   C2Scene_MemberDelta) with result 0.
; Quirk, kept: after C2Scene_MemberRouteOpen's BRA, $4012-$4031 is a
; second copy of its tests with the two-leg results swapped (X first when
; |.DeltaY| >= |.DeltaX|); nothing jumps there.
; Callers (2 JSR sites): C2Scene_MemberFollow ($C2:3C5F) and C2Scene_MemberBoardStart ($C2:3DEF).
; Entry: M=0, X=0, DP=$0000 (C2Tmp_00-$1B), DB=$00 (WRMPYA/B, RDMPYL and
;        low WRAM absolute); C2Scene_TaskCur = the task; .DeltaX/Y set
; Exit:  M=0, X=0; X = the task; A = the handler's last value; Y
;        clobbered; .Route set; C2Tmp_00-$1B as the helpers leave them
; Calls: C2Scene_PathBlocked, C2Scene_MemberTrailTarget,
;   C2Scene_MemberDelta.
C2Scene_MemberRoute:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,X
    LSR A                       ; / C2Scene_TilePx
    LSR A
    LSR A
    STA.b !C2Scene_RouteFromX   ; each store is a word; the next one
    LDA.w !C2Scene_StartX       ; replaces its high byte
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RouteToX
    LDA.w C2Scene_Task.SprY,X
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RouteFromY
    LDA.w !C2Scene_StartY
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RouteToY
    SEP #$20
    JSR C2Scene_PathBlocked     ; B = 0 for the TAX
.dispatch:
    ASL A
    TAX
    JMP (C2Scene_MemberRouteTable,X)

; $C2:3FE8 — C2Scene_MemberRouteTable (4 words, $3FE8–$3FEF)
; C2Scene_MemberRoute's handler for each C2Scene_PathBlocked result 0-3.
C2Scene_MemberRouteTable:
    dw C2Scene_MemberRouteOpen  ; 0
    dw C2Scene_MemberRouteYFirst ; C2Scene_PathXYBlocked
    dw C2Scene_MemberRouteXFirst ; C2Scene_PathYXBlocked
    dw C2Scene_MemberRouteTrail ; C2Scene_PathBothBlocked

C2Scene_MemberRouteOpen:        ; header: see C2Scene_MemberRoute
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.DeltaX,X
    BEQ .y_only
    BPL .abs_x
    EOR.w #!Eng_Invert16
    INC A
.abs_x:
    STA.b !C2Scene_RouteAbsDX
    LDA.w C2Scene_FollowTask.DeltaY,X
    BEQ .x_only
    BPL .abs_y
    EOR.w #!Eng_Invert16
    INC A
.abs_y:
    CMP.b !C2Scene_RouteAbsDX
    BCS .y_first
    BRA .x_first
.dead:                          ; quirk: never reached (see the header)
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.DeltaX,X
    BEQ .y_only
    BPL .dead_abs_x
    EOR.w #!Eng_Invert16
    INC A
.dead_abs_x:
    STA.b !C2Scene_RouteAbsDX
    LDA.w C2Scene_FollowTask.DeltaY,X
    BEQ .x_only
    BPL .dead_abs_y
    EOR.w #!Eng_Invert16
    INC A
.dead_abs_y:
    CMP.b !C2Scene_RouteAbsDX
    BCS .x_first
    BRA .y_first
.y_only:
    LDA.w #!C2Scene_RouteYFirst|1
    BRA .store
.x_only:
    LDA.w #!C2Scene_RouteXFirst|1
    BRA .store
.y_first:
    LDA.w #!C2Scene_RouteYFirst|2
    BRA .store
.x_first:
    LDA.w #!C2Scene_RouteXFirst|2
.store:
    SEP #$20
    STA.w C2Scene_FollowTask.Route,X
    REP #$20
    RTS

C2Scene_MemberRouteYFirst:      ; header: see C2Scene_MemberRoute
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_RouteYFirst|2
    STA.w C2Scene_FollowTask.Route,X
    REP #$20
    RTS

C2Scene_MemberRouteXFirst:      ; header: see C2Scene_MemberRoute
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_RouteXFirst|2
    STA.w C2Scene_FollowTask.Route,X
    REP #$20
    RTS

C2Scene_MemberRouteTrail:       ; header: see C2Scene_MemberRoute
    LDA.b #!C2Scene_TrailLen
    STA.b !C2Scene_TrailLeft
    LDA.w !C2Scene_TrailPos
    DEC A
    DEC A
    AND.b #!C2Scene_TrailMask
    STA.b !C2Scene_TrailIdx
    STZ.b !C2Scene_TrailIdx+1
.try:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDY.b !C2Scene_TrailIdx
    LDA.w C2Scene_Task.SprX,X
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RouteFromX
    LDA.w !C2Scene_TrailX,Y
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RouteToX
    LDA.w C2Scene_Task.SprY,X
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RouteFromY
    LDA.w !C2Scene_TrailY,Y
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RouteToY
    SEP #$20
    JSR C2Scene_PathBlocked
    CMP.b #!C2Scene_PathBothBlocked
    BNE .found
    REP #$20
    LDA.b !C2Scene_TrailIdx
    DEC A
    DEC A
    AND.w #!C2Scene_TrailMask
    STA.b !C2Scene_TrailIdx
    SEP #$20
    DEC.b !C2Scene_TrailLeft
    BNE .try
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_MemberTrailTarget
    JSR C2Scene_MemberDelta
    TDC                         ; result 0
    SEP #$20
    JMP C2Scene_MemberRoute_dispatch
.found:
    STA.b !C2Scene_TrailResult
    REP #$20
    LDY.b !C2Scene_TrailIdx
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_TrailX,Y
    AND.w #!C2Scene_TileSnapMask
    STA.w C2Scene_FollowTask.TargetX,X
    LDA.w !C2Scene_TrailY,Y
    AND.w #!C2Scene_TileSnapMask
    STA.w C2Scene_FollowTask.TargetY,X
    JSR C2Scene_MemberDelta
    TDC                         ; B = 0 for the dispatch's TAX
    SEP #$20
    LDA.b !C2Scene_TrailResult
    JMP C2Scene_MemberRoute_dispatch

; $C2:40E4 — C2Scene_FaceVelocity (65 bytes, $40E4–$4124)
; .PrevFacing = .Facing's direction; .Facing keeps only
; C2Scene_WalkMoving and gets the direction of the whole-pixel velocity:
; left / right for a negative / positive .XVel, else up / down for .YVel.
; Quirk, kept: with both velocities 0 it loops forever (.hang).
; Callers (6 JSR sites): C2Scene_MemberFollow ($C2:3C65), C2Scene_MemberMoveX ($C2:3D22),
;   C2Scene_MemberMoveY ($C2:3D83), C2Scene_MemberBoardStart ($C2:3DF5), C2Scene_MemberBoardX
;   ($C2:3E44) and C2Scene_MemberBoardY ($C2:3EA8).
; Entry: M any (SEP #$20 here), X=0, X = the task, DP any, DB=$00 (low
;        WRAM absolute)
; Exit:  M=0, X=0; A = the new .Facing (B = 0); X, Y unchanged
; No calls.
C2Scene_FaceVelocity:
    SEP #$20
    LDA.w C2Scene_FollowTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    STA.w C2Scene_FollowTask.PrevFacing,X
    LDA.w C2Scene_FollowTask.Facing,X
    AND.b #!C2Scene_WalkMoving
    STA.w C2Scene_FollowTask.Facing,X
    REP #$20
    LDA.w C2Scene_Task.XVel,X
    BEQ .vertical
    BPL .right
    LDA.w #!C2Scene_FacingLeft
    BRA .set
.right:
    LDA.w #!C2Scene_FacingRight
    BRA .set
.vertical:
    LDA.w C2Scene_Task.YVel,X
    BEQ .hang
    BPL .down
    LDA.w #!C2Scene_FacingUp
    BRA .set
.down:
    LDA.w #!C2Scene_FacingDown
.set:
    SEP #$20
    ORA.w C2Scene_FollowTask.Facing,X
    STA.w C2Scene_FollowTask.Facing,X
    REP #$20
    RTS
.hang:
    BRA .hang

; $C2:4125 — C2Scene_MemberFirstLeg (19 bytes, $4125–$4137)
; Sets the velocity of the route's first leg: C2Scene_MemberYLeg for a
; C2Scene_RouteYFirst route, else C2Scene_MemberXLeg.
; Callers (2 JSR sites): C2Scene_MemberFollow ($C2:3C62) and C2Scene_MemberBoardStart ($C2:3DF2).
; Entry: M any (SEP #$20 here), X=0, X = the task, DP any, DB=$00 (low
;        WRAM absolute)
; Exit:  M=0, X=0; as C2Scene_MemberXLeg / C2Scene_MemberYLeg
; Calls: C2Scene_MemberXLeg or C2Scene_MemberYLeg.
C2Scene_MemberFirstLeg:
    SEP #$20
    LDA.w C2Scene_FollowTask.Route,X
    BIT.b #!C2Scene_RouteYFirst
    REP #$20
    BNE .y_leg
    JSR C2Scene_MemberXLeg
    RTS
.y_leg:
    JSR C2Scene_MemberYLeg
    RTS

; $C2:4138 — C2Scene_MemberXLeg (26 bytes, $4138–$4151)
; A leg in X: .XVel = -1 for a negative .DeltaX, else +1; .XVelFrac,
; .YVel and .YVelFrac 0.
; Callers (3 JSR sites): C2Scene_MemberMoveY ($C2:3D80), C2Scene_MemberBoardY ($C2:3EA5) and
;   C2Scene_MemberFirstLeg ($C2:4130).
; Entry: M=0, X=0, X = the task, DP any, DB=$00 (low WRAM absolute)
; Exit:  M=0, X=0; A = the new .XVel; X, Y unchanged
; No calls.
C2Scene_MemberXLeg:
    LDA.w C2Scene_FollowTask.DeltaX,X
    BPL .plus
    LDA.w #!C2Scene_WholeMinus1
    BRA .set
.plus:
    LDA.w #1
.set:
    STA.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    RTS

; $C2:4152 — C2Scene_MemberYLeg (26 bytes, $4152–$416B)
; C2Scene_MemberXLeg for Y: .YVel = -1 / +1 by .DeltaY, the other three
; velocity words 0.
; Callers (3 JSR sites): C2Scene_MemberMoveX ($C2:3D1F), C2Scene_MemberBoardX ($C2:3E41) and
;   C2Scene_MemberFirstLeg ($C2:4134).
; Entry: M=0, X=0, X = the task, DP any, DB=$00 (low WRAM absolute)
; Exit:  M=0, X=0; A = the new .YVel; X, Y unchanged
; No calls.
C2Scene_MemberYLeg:
    LDA.w C2Scene_FollowTask.DeltaY,X
    BPL .plus
    LDA.w #!C2Scene_WholeMinus1
    BRA .set
.plus:
    LDA.w #1
.set:
    STA.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.XVelFrac,X
    RTS

; $C2:416C — C2Scene_MemberStand (24 bytes, $416C–$4183)
; Not moving (.Facing loses C2Scene_WalkMoving) and the stand animation
; of the member's character (the Party_Members byte of .Slot;
; C2Scene_SetStandAnim, tail call).
; Callers (7 JSR sites): C2Scene_MemberInit ($C2:3C36), C2Scene_MemberFollow ($C2:3CB2, $C2:3CD2),
;   C2Scene_MemberMoveX ($C2:3D31), C2Scene_MemberMoveY ($C2:3D92), C2Scene_MemberBoardX ($C2:3E71)
;   and C2Scene_MemberBoardY ($C2:3ED5).
; Entry: M any (SEP #$20 here), X=0, X = the task, DP=$0000 (TDC for 0;
;        C2Scene_AnimChar), DB=$00 (low WRAM absolute)
; Exit:  as C2Scene_SetStandAnim: M=1, X=0; X = the task
; Calls: C2Scene_SetStandAnim (JMP).
C2Scene_MemberStand:
    SEP #$20
    LDA.w C2Scene_FollowTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    STA.w C2Scene_FollowTask.Facing,X
    TDC                         ; B = 0 for the TAX
    LDA.w C2Scene_FollowTask.Slot,X
    TAX
    LDA.l !Party_Members,X
    STA.b !C2Scene_AnimChar
    JMP C2Scene_SetStandAnim

; $C2:4184 — C2Scene_MemberWalkAnim (49 bytes, $4184–$41B4)
; Zeroes the member's idle count (C2Scene_IdleFrames + .Slot) and starts
; the walk animation (C2Scene_SetWalkAnim) unless it already runs for an
; unchanged direction (.Facing = .PrevFacing with C2Scene_WalkMoving
; set); .Facing gets C2Scene_WalkMoving.
; Callers (6 JSR sites): C2Scene_MemberFollow ($C2:3C68), C2Scene_MemberMoveX ($C2:3D25),
;   C2Scene_MemberMoveY ($C2:3D86), C2Scene_MemberBoardStart ($C2:3DF8), C2Scene_MemberBoardX
;   ($C2:3E47) and C2Scene_MemberBoardY ($C2:3EAB).
; Entry: M any (SEP #$20 here), X=0, X = the task, B=0 (the TAX of .Slot;
;        C2Scene_FaceVelocity leaves it so), DP=$0000 (TDC for 0),
;        DB=$00 (low WRAM absolute)
; Exit:  M=1, X=0; X = the task; Y = the task (no new animation) or as
;        C2Scene_SetWalkAnim leaves it
; Calls: C2Scene_SetWalkAnim.
C2Scene_MemberWalkAnim:
    SEP #$20
    TXY
    LDA.w C2Scene_FollowTask.Slot,Y
    TAX
    STZ.w !C2Scene_IdleFrames,X
    TYX
    LDA.w C2Scene_FollowTask.Facing,X
    AND.b #!C2Scene_WalkMoving^$FF
    CMP.w C2Scene_FollowTask.PrevFacing,X
    BNE .start
    LDA.w C2Scene_FollowTask.Facing,X
    BMI .done                   ; already walking that way
.start:
    LDA.w C2Scene_FollowTask.Facing,X
    ORA.b #!C2Scene_WalkMoving
    STA.w C2Scene_FollowTask.Facing,X
    TDC                         ; B = 0 for the TAX
    LDA.w C2Scene_FollowTask.Slot,X
    TAX
    LDA.l !Party_Members,X
    STA.b !C2Scene_AnimChar
    JSR C2Scene_SetWalkAnim
.done:
    RTS

; $C2:41B5 — C2Scene_PathBlocked (80 bytes, $41B5–$4204)
; Tests the two one-turn paths between 8x8 tiles (C2Scene_RouteFromX,
; C2Scene_RouteFromY) and (C2Scene_RouteToX, C2Scene_RouteToY) for wall
; tiles: C2Scene_PathXYBlocked when the path along the row to the target
; column (C2Scene_ScanRow) and then down that column (C2Scene_ScanCol)
; has one, C2Scene_PathYXBlocked when the path along the column and then
; the target row has one.
; Callers (2 JSR sites): C2Scene_MemberRoute ($C2:3FE0) and C2Scene_MemberRouteTrail ($C2:4097).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Tmp_00-$15), DB=$00
;        (WRMPYA/B and RDMPYL absolute); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; A = C2Scene_PathResult (0-3, B = 0); X as the last
;        scan leaves it (the task or $7000), Y clobbered; C2Tmp_00-$07,
;        $0E and $10-$15 changed
; Calls: C2Scene_ScanRow, C2Scene_ScanCol.
C2Scene_PathBlocked:
    SEP #$20
    STZ.b !C2Scene_PathResult
    LDA.b !C2Scene_RouteFromX
    STA.b !C2Scene_ScanX
    LDA.b !C2Scene_RouteFromY
    STA.b !C2Scene_ScanY
    LDA.b !C2Scene_RouteToX
    STA.b !C2Scene_ScanEnd
    JSR C2Scene_ScanRow
    BCC .xy_col
    LDA.b #!C2Scene_PathXYBlocked
    TSB.b !C2Scene_PathResult
    BRA .yx
.xy_col:
    LDA.b !C2Scene_RouteToY
    STA.b !C2Scene_ScanEnd
    JSR C2Scene_ScanCol
    BCC .yx
    LDA.b #!C2Scene_PathXYBlocked
    TSB.b !C2Scene_PathResult
.yx:
    LDA.b !C2Scene_RouteFromX
    STA.b !C2Scene_ScanX
    LDA.b !C2Scene_RouteFromY
    STA.b !C2Scene_ScanY
    LDA.b !C2Scene_RouteToY
    STA.b !C2Scene_ScanEnd
    JSR C2Scene_ScanCol
    BCC .yx_row
    LDA.b #!C2Scene_PathYXBlocked
    TSB.b !C2Scene_PathResult
    BRA .done
.yx_row:
    LDA.b !C2Scene_RouteToX
    STA.b !C2Scene_ScanEnd
    JSR C2Scene_ScanRow
    BCC .done
    LDA.b #!C2Scene_PathYXBlocked
    TSB.b !C2Scene_PathResult
.done:
    TDC                         ; B = 0
    LDA.b !C2Scene_PathResult
    RTS

; $C2:4205 — C2Scene_ScanRow (85 bytes, $4205–$4259)
; Walks C2Scene_ScanX one column at a time to C2Scene_ScanEnd along tile
; row C2Scene_ScanY - 1 (the row above the point, as the leader's
; .PropUL/UR), testing each new column's property nibble
; (C2Scene_GetTileProp, BG2's map and C2Scene_Unk7000) for
; C2Scene_TilePropWallBits. C=1 at the first wall (C2Scene_ScanX is left
; on it), C=0 when C2Scene_ScanEnd is reached (or was the start).
; Callers (2 JSR sites): C2Scene_PathBlocked ($C2:41C5, $C2:41F8).
; Entry: M=1, X=0, DP=$0000 (C2Tmp_00-$07, $10-$15), DB=$00 (WRMPYA/B
;        and RDMPYL absolute)
; Exit:  M=1, X=0; C as above; C2Scene_ScanY unchanged, C2Scene_ScanX at
;        the stop; X = $7000 (C2Scene_Unk7000's address), A, Y
;        clobbered; C2Scene_PropMap
;        and C2Scene_PropTable set
; Calls: C2Scene_GetTileProp.
C2Scene_ScanRow:
    LDX.w #(!C2Scene_BgMaps+!C2Scene_MapBytes)&$FFFF ; layer 2's map
    STX.b !C2Scene_PropMap
    LDA.b #bank(!C2Scene_BgMaps)
    STA.b !C2Scene_PropMap+2
    LDX.w #!C2Scene_Unk7000&$FFFF
    STX.b !C2Scene_PropTable
    LDA.b #bank(!C2Scene_Unk7000)
    STA.b !C2Scene_PropTable+2
    DEC.b !C2Scene_ScanY
    SEC
    LDA.b !C2Scene_ScanEnd
    SBC.b !C2Scene_ScanX
    BEQ .open
    BMI .left
.right:
    INC.b !C2Scene_ScanX
    LDA.b !C2Scene_ScanX
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_ScanY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    AND.b #!C2Scene_TilePropWallBits
    BNE .wall
    LDA.b !C2Scene_ScanX
    CMP.b !C2Scene_ScanEnd
    BNE .right
    BRA .open
.left:
    DEC.b !C2Scene_ScanX
    LDA.b !C2Scene_ScanX
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_ScanY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    AND.b #!C2Scene_TilePropWallBits
    BNE .wall
    LDA.b !C2Scene_ScanX
    CMP.b !C2Scene_ScanEnd
    BNE .left
.open:
    INC.b !C2Scene_ScanY
    CLC
    RTS
.wall:
    INC.b !C2Scene_ScanY
    SEC
    RTS

; $C2:425A — C2Scene_ScanCol (131 bytes, $425A–$42DC)
; C2Scene_ScanRow down or up a column: C2Scene_ScanY (and C2Scene_ScanEnd)
; are taken one row up, then C2Scene_ScanY walks to C2Scene_ScanEnd
; testing the two tiles of each new row at columns C2Scene_ScanX - 1 and
; C2Scene_ScanX (the first kept in the task's .ScanProp) for
; C2Scene_TilePropWallBits. C=1 at the first wall.
; Quirk, kept: C2Scene_ScanY is put back afterwards but C2Scene_ScanEnd
; is left one less (both callers set it again before using it).
; Callers (2 JSR sites): C2Scene_PathBlocked ($C2:41D4, $C2:41E9).
; Entry: M=1, X=0, DP=$0000 (C2Tmp_00-$07, $10-$15), DB=$00 (WRMPYA/B
;        and RDMPYL absolute); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C as above; X = the task (after a test) or $7000
;        (C2Scene_Unk7000's address); A, Y clobbered;
;        C2Scene_PropMap/PropTable set
; Calls: C2Scene_GetTileProp.
C2Scene_ScanCol:
    LDX.w #(!C2Scene_BgMaps+!C2Scene_MapBytes)&$FFFF ; layer 2's map
    STX.b !C2Scene_PropMap
    LDA.b #bank(!C2Scene_BgMaps)
    STA.b !C2Scene_PropMap+2
    LDX.w #!C2Scene_Unk7000&$FFFF
    STX.b !C2Scene_PropTable
    LDA.b #bank(!C2Scene_Unk7000)
    STA.b !C2Scene_PropTable+2
    DEC.b !C2Scene_ScanY
    DEC.b !C2Scene_ScanEnd
    SEC
    LDA.b !C2Scene_ScanEnd
    SBC.b !C2Scene_ScanY
    BEQ .open
    BMI .up
.down:
    INC.b !C2Scene_ScanY
    LDA.b !C2Scene_ScanX
    DEC A
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_ScanY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_FollowTask.ScanProp,X
    LDA.b !C2Scene_ScanX
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_ScanY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    ORA.w C2Scene_FollowTask.ScanProp,X
    AND.b #!C2Scene_TilePropWallBits
    BNE .wall
    LDA.b !C2Scene_ScanY
    CMP.b !C2Scene_ScanEnd
    BNE .down
    BRA .open
.up:
    DEC.b !C2Scene_ScanY
    LDA.b !C2Scene_ScanX
    DEC A
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_ScanY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_FollowTask.ScanProp,X
    LDA.b !C2Scene_ScanX
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_ScanY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    ORA.w C2Scene_FollowTask.ScanProp,X
    AND.b #!C2Scene_TilePropWallBits
    BNE .wall
    LDA.b !C2Scene_ScanY
    CMP.b !C2Scene_ScanEnd
    BNE .up
.open:
    INC.b !C2Scene_ScanY
    CLC
    RTS
.wall:
    INC.b !C2Scene_ScanY
    SEC
    RTS

; ============================================================
; Object A's tasks and scripts ($C2:42DD–$C2:4CC4)
; ============================================================
; C2Scene_ObjATask runs the sprite of object A (C2Scene_ObjAX/Y,
; C2Scene_Unk0294, C2Scene_ObjALoc), the thing C2Scene_ObjWatch lets the
; party get into. Like the party tasks it has no reference in the bank's
; code (probably started from scene data). It keeps C2Scene_ObjAX/Y on
; its own position, and while the party is in it (C2Scene_ObjWatch state
; C2Scene_ObjWatchStBusyA) it takes the controls the leader's task
; otherwise takes: with C2Scene_ObjAFlag5 it moves 24 pixels up
; (C2Scene_ObjARise), is steered by the D-pad 8 pixels at a time while
; scrolling BG layers 1 and 2 (C2Scene_ObjAFly, C2Scene_ObjAMove), and
; can come down again where the six property nibbles under it are clear
; (C2Scene_ObjALand); without it, getting in starts scene mode
; C2Scene_ModeUnk8 at once. Mode 8 (C2Scene_Unk6A34, not matched)
; probably leaves a location number in C2Scene_ObjANextLoc; then the task
; runs one of its own scripts (C2Scene_ObjAScrLeave) that ends in
; C2Script_GoToLocation-like copies to Loc_Id. Everything about what
; object A is comes from this behaviour only (a vehicle, probably).
;
; Direct page work bytes (C2Scene_BoxesOverlap's and C2Scene_GetTileProps'
; inputs are named at those routines).

; $C2:42DD — C2Scene_ObjATask (9 bytes, $42DD–$42E5)
; Task handler: runs the C2Scene_ObjAStates handler of .State.
; Callers note: none found (see the banner).
; Entry: M=1, X=0, X = C2Scene_TaskCur = the task (C2Scene_TaskRunAll),
;        DP=$0000 (TDC for 0: B = 0 for the TAX), DB=$00 (low WRAM)
; Exit:  as the state's handler
; Calls: a C2Scene_ObjAStates handler (JMP (abs,X)).
C2Scene_ObjATask:
    TDC
    LDA.w C2Scene_ObjTask.State,X
    ASL A
    TAX
    JMP (C2Scene_ObjAStates,X)

; $C2:42E6 — C2Scene_ObjAStates (9 words, $42E6–$42F7)
; C2Scene_ObjATask's handler for each .State 0-8.
C2Scene_ObjAStates:
    dw C2Scene_ObjAInit         ; 0
    dw C2Scene_ObjAWait         ; 1 (C2Scene_ObjAStWait)
    dw C2Scene_ObjARise         ; 2
    dw C2Scene_ObjAFly          ; 3 (C2Scene_ObjAStFly)
    dw C2Scene_ObjAMove         ; 4
    dw C2Scene_ObjALand         ; 5 (C2Scene_ObjAStLand)
    dw C2Scene_ObjAAfterMode8   ; 6 (C2Scene_ObjAStMode8)
    dw C2Scene_ObjAScript       ; 7 (C2Scene_ObjAStScript)
    dw C2Scene_ObjAWaitEmpty    ; 8 (C2Scene_ObjAStWaitEmpty)

; $C2:42F8 — C2Scene_ObjAInit (211 bytes, $42F8–$43CA)
; State 0: puts the sprite at C2Scene_ObjAX/Y (fractions and .SprTile
; 0), then by C2Scene_Unk0294:
; - C2Scene_ObjBusy clear: .State C2Scene_ObjAStWait, .SprAttr
;   C2Scene_ObjAttrPrio2, facing down (.Facing and .PrevFacing),
;   C2Scene_ObjAAloft = 0, the rest animation (C2Scene_AnimObjARest, or
;   C2Scene_AnimObjARest5 with C2Scene_ObjAFlag5) and C2Anim_Run;
; - busy, C2Scene_ObjAInMode8 clear (the scene was loaded with the party
;   in the object): .State C2Scene_ObjAStFly, .SprAttr
;   C2Scene_ObjAttrPrio3, the facing from Loc_EntryFacing,
;   C2Scene_ObjAAloft = 1, C2Scene_ObjASpotBits cleared, the facing's
;   animation (C2Scene_ObjAFaceAnim), the property nibbles at the
;   position (C2Scene_GetTileProps, C2Scene_ObjAGetProps), C2Anim_Run;
; - busy and C2Scene_ObjAInMode8 (back from mode 8): queues sound
;   command C2Scene_SoundCmd86 (arguments 0, 0; the third left as it
;   was), .State C2Scene_ObjAStScript on the script C2Scene_ObjAScrArrive,
;   .SprAttr C2Scene_ObjAttrPrio3, the facing from Loc_EntryFacing,
;   C2Scene_ObjASpotBits cleared, C2Scene_ObjAAloft = 1; no C2Anim_Run.
; Callers note: none direct (C2Scene_ObjAStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (DP_Field and low
;        WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered; C2Tmp_00-$15 as
;        the callees leave them on the second path
; Calls: C2Scene_SetAnim, C2Anim_Run, C2Scene_ObjAFaceAnim,
;   C2Scene_GetTileProps, C2Scene_ObjAGetProps, C2Scene_QueueSoundCmd.
C2Scene_ObjAInit:
    LDX.b !C2Scene_TaskCur
    REP #$20
    LDA.w !C2Scene_ObjAX
    STA.w C2Scene_Task.SprX,X
    LDA.w !C2Scene_ObjAY
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.XFrac,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.SprTile,X
    SEP #$20
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjBusy
    BNE .busy
    INC.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_ObjAttrPrio2
    STA.w C2Scene_Task.SprAttr,X
    LDA.b #!C2Scene_FacingDown
    STA.w C2Scene_ObjTask.Facing,X
    STA.w C2Scene_ObjTask.PrevFacing,X
    STZ.w !C2Scene_ObjAAloft
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BNE .rest5
    LDA.b #!C2Scene_AnimObjARest
    JSR C2Scene_SetAnim
    BRA .run
.rest5:
    LDA.b #!C2Scene_AnimObjARest5
    JSR C2Scene_SetAnim
.run:
    JSR C2Anim_Run
    CLC
    RTS
.busy:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BNE .from_mode8
    LDA.b #!C2Scene_ObjAStFly
    STA.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_ObjAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask
    STA.w C2Scene_ObjTask.Facing,X
    STA.w C2Scene_ObjTask.PrevFacing,X
    LDA.b #1
    STA.w !C2Scene_ObjAAloft
    LDA.b #!C2Scene_ObjASpotBits
    TRB.w !C2Scene_Unk0294
    JSR C2Scene_ObjAFaceAnim
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    JSR C2Scene_ObjAGetProps
    JSR C2Anim_Run
    CLC
    RTS
.from_mode8:
    LDA.b #!C2Scene_SoundCmd86
    STA.w !C2Scene_SoundCmdBuf
    STZ.w !C2Scene_SoundCmdBuf+1
    STZ.w !C2Scene_SoundCmdBuf+2
    STZ.w !C2Scene_SoundCmdPrio
    JSR C2Scene_QueueSoundCmd
    LDA.b #!C2Scene_ObjAStScript
    STA.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_ObjAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask
    STA.w C2Scene_ObjTask.Facing,X
    STA.w C2Scene_ObjTask.PrevFacing,X
    LDA.b #!C2Scene_ObjASpotBits
    TRB.w !C2Scene_Unk0294
    LDA.b #1
    STA.w !C2Scene_ObjAAloft
    REP #$20
    LDA.w #C2Scene_ObjAScrArrive
    STA.w C2Scene_Task.ScriptPtr,X
    SEP #$20
    LDA.b #bank(C2Scene_ObjAScrArrive)
    STA.w C2Scene_Task.ScriptBank,X
    STZ.w C2Scene_Task.ScriptWait,X
    CLC
    RTS

; $C2:43CB — C2Scene_ObjAWait (113 bytes, $43CB–$443B)
; State 1: runs the animation until C2Scene_ObjWatch reaches state
; C2Scene_ObjWatchStBusyA (the whole party is in), then sets
; C2Scene_ObjBusy and:
; - without C2Scene_ObjAFlag5: sets C2Scene_ObjAInMode8, scene mode
;   C2Scene_ModeUnk8, .State C2Scene_ObjAStMode8, C2Scene_ObjANextLoc = 0,
;   and ends at C2Scene_ObjAFly's .done (C2Anim_Run);
; - with it: .State 2 (C2Scene_ObjARise), the zone song argument
;   C2Scene_ObjASongArg (C2Scene_ObjASound), the property nibbles at the
;   position, velocity 0 across and C2Scene_HalfPixel up (-0.5 pixel a
;   frame), .Frames = 0, .Duration = C2Scene_RiseFrames, animation
;   C2Scene_AnimObjARise, and falls into C2Scene_ObjARise.
; Callers note: none direct (C2Scene_ObjAStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0 (waiting, or through C2Scene_ObjAFly's .done);
;        else as
;        C2Scene_ObjARise
; Calls: C2Anim_Run, C2Scene_ObjASound, C2Scene_GetTileProps,
;   C2Scene_ObjAGetProps, C2Scene_SetAnim; jumps to C2Scene_ObjAFly's
;   .done.
C2Scene_ObjAWait:
    LDA.w !C2Scene_Unk027E
    CMP.b #!C2Scene_ObjWatchStBusyA
    BEQ .aboard
    JSR C2Anim_Run
    CLC
    RTS
.aboard:
    LDA.b #!C2Scene_ObjBusy
    TSB.w !C2Scene_Unk0294
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BNE .rise
    LDA.b #!C2Scene_ObjAInMode8
    TSB.w !C2Scene_Unk0294
    LDA.b #!C2Scene_ModeUnk8
    STA.w !C2Scene_Mode
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_ObjAStMode8
    STA.w C2Scene_ObjTask.State,X
    LDY.w #0
    STY.w !C2Scene_ObjANextLoc
    JMP C2Scene_ObjAFly_done
.rise:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_ObjTask.State,X
    JSR C2Scene_ObjASound
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    JSR C2Scene_ObjAGetProps
    REP #$20
    LDA.w #!C2Scene_HalfPixel
    STA.w C2Scene_Task.YVelFrac,X
    LDA.w #!C2Scene_WholeMinus1
    STA.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.Frames,X
    SEP #$20
    LDA.b #!C2Scene_RiseFrames
    STA.w C2Scene_ObjTask.Duration,X
    LDA.b #!C2Scene_AnimObjARise
    JSR C2Scene_SetAnim

; $C2:443C — C2Scene_ObjARise (123 bytes, $443C–$44B6)
; State 2: moves by the velocity (C2Scene_TaskMove, C2Scene_WrapTaskPos)
; until .Frames reaches .Duration; on frame C2Scene_RiseAttrAt the
; sprite gets .SprAttr C2Scene_ObjAttrPrio3. Then:
; - with C2Scene_Flag0Copy = C2Scene_Flag0ObjAGo1DD: in mode
;   C2Scene_ModeIdle1 only, scene mode C2Scene_ModeIdle7, the script
;   C2Scene_ObjAScrGo1DD (another task; it leaves for location $1DD)
;   and C2Anim_Run; it stays in this state;
; - else .State C2Scene_ObjAStFly, the facing's animation, the zone song
;   argument again (C2Scene_ObjASound), C2Scene_ObjAAloft = 1, .SprY +
;   C2Scene_Lift (the position goes back down the 24 pixels it rose;
;   why is not traced), velocity and .Frames 0,
;   Loc_EntryFacing bits 0-1 = .Facing, and falls into
;   C2Scene_ObjAFly.
; .Frames is a word; only its low byte is compared.
; Callers note: none direct (C2Scene_ObjAStates); C2Scene_ObjAWait falls
;   in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (DP_Field and low
;        WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task (C2Anim_Run reloads it after the
;        script starts); A, Y clobbered; C2Tmp_01, $08 and $0A changed
;        by C2Scene_TaskSpawnScript when it starts one; else as
;        C2Scene_ObjAFly
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Anim_Run,
;   C2Scene_TaskSpawnScript, C2Scene_ObjAFaceAnim, C2Scene_ObjASound.
C2Scene_ObjARise:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_RiseAttrAt
    BNE .attr_done
    LDA.b #!C2Scene_ObjAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
.attr_done:
    LDA.w C2Scene_Task.Frames,X
    CMP.w C2Scene_ObjTask.Duration,X
    BCS .risen
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    SEP #$20
    JSR C2Anim_Run
    CLC
    RTS
.risen:
    LDA.w !C2Scene_Flag0Copy
    CMP.b #!C2Scene_Flag0ObjAGo1DD
    BNE .fly
    LDA.w !C2Scene_Mode
    CMP.b #!C2Scene_ModeIdle1
    BNE .wait
    LDA.b #!C2Scene_ModeIdle7
    STA.w !C2Scene_Mode
    LDA.b #bank(C2Scene_ObjAScrGo1DD)
    LDX.w #C2Scene_ObjAScrGo1DD
    JSR C2Scene_TaskSpawnScript
    JSR C2Anim_Run
.wait:
    CLC
    RTS
.fly:
    INC.w C2Scene_ObjTask.State,X
    JSR C2Scene_ObjAFaceAnim
    JSR C2Scene_ObjASound
    LDA.b #1
    STA.w !C2Scene_ObjAAloft
    REP #$20
    CLC
    LDA.w #!C2Scene_Lift
    ADC.w C2Scene_Task.SprY,X
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    SEP #$20
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask^$FF
    ORA.w C2Scene_ObjTask.Facing,X
    STA.w !DP_Field+!Loc_EntryFacing

; $C2:44B7 — C2Scene_ObjAFly (446 bytes, $44B7–$4674)
; State 3 (C2Scene_ObjAStFly): in scene mode C2Scene_ModeIdle1, with
; any bit of Pad_Unk00F8 (read as a word) set, the first that applies:
; - Pad_Unk00F8Bit7 with C2Scene_ObjAOnSpot: unless
;   C2Scene_Unk0294Bit2 is already set, scene mode C2Scene_ModeIdle7,
;   C2Scene_Unk0294Bit2 set and the script C2Scene_ObjAScrSpot (another
;   task; it leaves for location $1C1);
; - Pad_Unk00F8Bit7 when none of the six property nibbles .PropUL-DR,
;   .PropBL/B has a bit of C2Scene_ObjALandMask, object B's box does not
;   overlap object A's (C2Scene_ObjBOverlap) and BankC6_UnkE797 returns
;   C=0: comes down: velocity C2Scene_HalfPixel down (+0.5 a frame),
;   .SprY - C2Scene_Lift, .Frames 0, .Duration
;   C2Scene_LandFrames, facing down (also into Loc_EntryFacing),
;   animation C2Scene_AnimObjALand, C2Scene_ObjAAloft = 0, the zone's
;   song (C2Scene_ZoneSoundAtView), .State C2Scene_ObjAStLand;
; - otherwise (also bit 7 where it cannot come down) the other
;   buttons: Pad_Unk00F8Bit0 sets C2Scene_ObjAInMode8, mode
;   C2Scene_ModeUnk8, .State C2Scene_ObjAStMode8 and
;   C2Scene_ObjANextLoc = 0; Pad_Unk00F8Bit6 mode C2Scene_ModeMenu;
;   Pad_Unk00F8Bit2 mode C2Scene_ModeMode7; then Up, Down, Left, Right
;   (C2Scene_PadUp...) start a step that way (.step): .PrevFacing =
;   .Facing, .Facing = the direction, the velocity from
;   C2Scene_ObjAStepVel (2 pixels a frame, fractions 0); on a new facing
;   its bits go into Loc_EntryFacing and the facing's animation starts
;   (C2Scene_ObjAFaceAnim); .TargetX/Y 8 pixels ahead
;   (C2Scene_SetStepTarget, C2Scene_WrapStepTarget) and the property
;   nibbles there; C2Scene_Unk1BF7 = 0; .State + 1, and it falls into
;   C2Scene_ObjAMove.
; .done ($C2:4509, the end of every path above that does not fall
; through, and of C2Scene_ObjAWait's mode-8 path, which JMPs to it):
; C2Anim_Run, C=0.
; Quirk, kept: C2Scene_ObjBOverlap returns C=1 only with M=0 (its
; overlap path), so its JMP to .buttons reaches that 16-bit code in the
; right width; its C=0 returns can be M=1 or M=0, which the JSL's
; REP #$20 after them makes no matter.
; Callers note: none direct (C2Scene_ObjAStates); C2Scene_ObjARise falls
;   in. Its .done is also the target of a JMP in C2Scene_ObjAWait.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur, the box and property
;        temporaries), DB=$00 (Pad_Unk00F8, DP_Field and low WRAM
;        absolute); C2Scene_TaskCur = the task. At .done: M any (SEP
;        here), X=0, the same DP and DB
; Exit:  C=0; M=1, X=0; X = the task (.done's C2Anim_Run reloads it
;        after the script starts; C2Scene_TaskSpawnScript changes C2Tmp_01,
;        $08 and $0A); A, Y clobbered; C2Tmp_00-$15 changed by the
;        callees on the box and step paths; or as C2Scene_ObjAMove
; Calls: C2Scene_TaskSpawnScript, C2Scene_ObjBOverlap, BankC6_UnkE797
;   (JSL), C2Scene_SetAnim, C2Scene_ZoneSoundAtView, C2Scene_ObjAFaceAnim,
;   C2Scene_SetStepTarget, C2Scene_WrapStepTarget, C2Scene_GetTileProps,
;   C2Scene_ObjAGetProps, C2Anim_Run.
C2Scene_ObjAFly:
    LDA.w !C2Scene_Mode
    CMP.b #!C2Scene_ModeIdle1
    BNE .done
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !Pad_Unk00F8
    BEQ .done
    BIT.w #!Pad_Unk00F8Bit7
    BNE .button7
.buttons:
    LDX.b !C2Scene_TaskCur
    LDA.w !Pad_Unk00F8
    BIT.w #!Pad_Unk00F8Bit0
    BEQ .not0
    JMP .mode8
.not0:
    BIT.w #!Pad_Unk00F8Bit6
    BEQ .not6
    JMP .menu
.not6:
    BIT.w #!Pad_Unk00F8Bit2
    BEQ .not2
    JMP .mode7
.not2:
    BIT.w #!C2Scene_PadUp
    BEQ .not_up
    JMP .up
.not_up:
    BIT.w #!C2Scene_PadDown
    BEQ .not_down
    JMP .down
.not_down:
    BIT.w #!C2Scene_PadLeft
    BEQ .not_left
    JMP .left
.not_left:
    BIT.w #!C2Scene_PadRight
    BEQ .done
    JMP .right
.done:
    SEP #$20
    JSR C2Anim_Run
    CLC
    RTS
.button7:
    SEP #$20
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAOnSpot
    BEQ .try_land
    BIT.b #!C2Scene_Unk0294Bit2
    BNE .done
    LDA.b #!C2Scene_ModeIdle7
    STA.w !C2Scene_Mode
    LDA.b #!C2Scene_Unk0294Bit2
    TSB.w !C2Scene_Unk0294
    LDA.b #bank(C2Scene_ObjAScrSpot)
    LDX.w #C2Scene_ObjAScrSpot
    JSR C2Scene_TaskSpawnScript
    BRA .done
.try_land:
    REP #$20
    LDA.w C2Scene_ObjTask.PropUL,X
    ORA.w C2Scene_ObjTask.PropDL,X
    ORA.w C2Scene_ObjTask.PropBL,X
    AND.w #!C2Scene_ObjALandMask
    BNE .buttons
    SEP #$20
    LDX.w !C2Scene_ObjAX
    STX.b !C2Scene_BoxAX
    LDX.w !C2Scene_ObjAY
    STX.b !C2Scene_BoxAY
    LDX.w #C2Scene_ObjAFlyBox
    STX.b !C2Scene_BoxAPtr
    LDA.b #bank(C2Scene_ObjAFlyBox)
    STA.b !C2Scene_BoxAPtr+2
    JSR C2Scene_ObjBOverlap
    BCC .not_b
    JMP .buttons                ; C=1 comes back only with M=0 (see the header)
.not_b:
    JSL BankC6_UnkE797
    REP #$20
    BCC .land
    JMP .buttons
.land:
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    LDA.w #!C2Scene_HalfPixel
    STA.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    CLC
    LDA.w #!C2Scene_LiftUp
    ADC.w C2Scene_Task.SprY,X
    STA.w C2Scene_Task.SprY,X
    SEP #$20
    LDA.b #!C2Scene_FacingDown
    STA.w C2Scene_ObjTask.Facing,X
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask^$FF
    ORA.w C2Scene_ObjTask.Facing,X
    STA.w !DP_Field+!Loc_EntryFacing
    LDA.b #!C2Scene_LandFrames
    STA.w C2Scene_ObjTask.Duration,X
    LDA.b #!C2Scene_AnimObjALand
    JSR C2Scene_SetAnim
    STZ.w !C2Scene_ObjAAloft
    JSR C2Scene_ZoneSoundAtView
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_ObjAStLand
    STA.w C2Scene_ObjTask.State,X
    JMP .done
.mode7:
    SEP #$20
    LDA.b #!C2Scene_ModeMode7
    STA.w !C2Scene_Mode
    JMP .done
.menu:
    SEP #$20
    LDA.b #!C2Scene_ModeMenu
    STA.w !C2Scene_Mode
    JMP .done
.mode8:
    SEP #$20
    LDA.b #!C2Scene_ObjAInMode8
    TSB.w !C2Scene_Unk0294
    LDA.b #!C2Scene_ModeUnk8
    STA.w !C2Scene_Mode
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_ObjAStMode8
    STA.w C2Scene_ObjTask.State,X
    LDY.w #0
    STY.w !C2Scene_ObjANextLoc
    JMP .done
.up:
    SEP #$20
    LDA.w C2Scene_ObjTask.Facing,X
    STA.w C2Scene_ObjTask.PrevFacing,X
    LDA.b #!C2Scene_FacingUp
    STA.w C2Scene_ObjTask.Facing,X
    BRA .step
.down:
    SEP #$20
    LDA.w C2Scene_ObjTask.Facing,X
    STA.w C2Scene_ObjTask.PrevFacing,X
    LDA.b #!C2Scene_FacingDown
    STA.w C2Scene_ObjTask.Facing,X
    BRA .step
.left:
    SEP #$20
    LDA.w C2Scene_ObjTask.Facing,X
    STA.w C2Scene_ObjTask.PrevFacing,X
    LDA.b #!C2Scene_FacingLeft
    STA.w C2Scene_ObjTask.Facing,X
    BRA .step
.right:
    SEP #$20
    LDA.w C2Scene_ObjTask.Facing,X
    STA.w C2Scene_ObjTask.PrevFacing,X
    LDA.b #!C2Scene_FacingRight
    STA.w C2Scene_ObjTask.Facing,X
.step:
    LDY.b !C2Scene_TaskCur
    TDC                         ; A = DP = 0: clears the high byte
    LDA.w C2Scene_ObjTask.Facing,Y
    ASL A                       ; * 4: one C2Scene_ObjAStepVel entry
    ASL A
    TAX
    REP #$20
    LDA.l C2Scene_ObjAStepVel,X
    STA.w C2Scene_Task.XVel,Y
    LDA.l C2Scene_ObjAStepVel+2,X
    STA.w C2Scene_Task.YVel,Y
    TDC
    STA.w C2Scene_Task.XVelFrac,Y
    STA.w C2Scene_Task.YVelFrac,Y
    SEP #$20
    LDA.w C2Scene_ObjTask.Facing,Y
    CMP.w C2Scene_ObjTask.PrevFacing,Y
    BEQ .same_facing
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask^$FF
    ORA.w C2Scene_ObjTask.Facing,Y
    STA.w !DP_Field+!Loc_EntryFacing
    JSR C2Scene_ObjAFaceAnim
.same_facing:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_SetStepTarget
    JSR C2Scene_WrapStepTarget
    LDA.w C2Scene_ObjTask.TargetX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_ObjTask.TargetY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    JSR C2Scene_ObjAGetProps    ; returns M=1
    STZ.w !C2Scene_Unk1BF7
    INC.w C2Scene_ObjTask.State,X

; $C2:4675 — C2Scene_ObjAMove (109 bytes, $4675–$46E1)
; State 4: moves by the velocity (C2Scene_TaskMove, C2Scene_WrapTaskPos)
; and scrolls BG layers 1 and 2 with it (C2Scene_Unk0568 by .XVel,
; C2Scene_Unk066C by .YVel, the low bytes), as the leader's step does;
; C2Scene_Unk1BF1/1BF3 = .XVel/.YVel; C2Anim_Run; C2Scene_ObjAX/Y = the
; position. At .TargetX/Y, .State = C2Scene_ObjAStFly (a 16-bit store,
; so .Frames' low byte becomes 0 too).
; Callers note: none direct (C2Scene_ObjAStates); C2Scene_ObjAFly falls
;   in.
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur and the
;        scroll temporaries), DB=$00 (low WRAM absolute); C2Scene_TaskCur
;        = the task
; Exit:  C=0; M=0, X=0; X = the task; A clobbered (the last compare);
;        Y and C2Tmp_00-$1A as C2Anim_Run and the scrolls leave them
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_Unk0568,
;   C2Scene_Unk066C, C2Anim_Run.
C2Scene_ObjAMove:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    SEP #$20
    LDA.w C2Scene_Task.XVel,X
    STA.b !C2Scene_ScrollPx
    LDA.b #1
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk0568
    LDA.b #2
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk0568
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.YVel,X
    STA.b !C2Scene_ScrollPx
    LDA.b #1
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk066C
    LDA.b #2
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk066C
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.XVel,X
    STA.w !C2Scene_Unk1BF1
    LDA.w C2Scene_Task.YVel,X
    STA.w !C2Scene_Unk1BF3
    JSR C2Anim_Run
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_ObjAX
    LDA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_ObjAY
    LDA.w C2Scene_Task.SprX,X
    CMP.w C2Scene_ObjTask.TargetX,X
    BNE .moving
    LDA.w C2Scene_Task.SprY,X
    CMP.w C2Scene_ObjTask.TargetY,X
    BNE .moving
    LDA.w #!C2Scene_ObjAStFly
    STA.w C2Scene_ObjTask.State,X
.moving:
    CLC
    RTS

; $C2:46E2 — C2Scene_ObjALand (70 bytes, $46E2–$4727)
; State 5 (C2Scene_ObjAStLand): moves by the velocity until .Frames
; reaches .Duration (low byte), with .SprAttr C2Scene_ObjAttrPrio2 from
; frame C2Scene_LandAttrAt; C2Anim_Run. Then C2Scene_ObjBusy is
; cleared (C2Scene_ObjWatch moves on to C2Scene_ObjWatchStEmpty and the
; party gets out), .State 0, animation C2Scene_AnimObjARest5, velocity
; and .Frames 0.
; Callers note: none direct (C2Scene_ObjAStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0 (C2Anim_Run's); X = the task; A, Y clobbered
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_SetAnim,
;   C2Anim_Run.
C2Scene_ObjALand:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_LandAttrAt
    BNE .attr_done
    LDA.b #!C2Scene_ObjAttrPrio2
    STA.w C2Scene_Task.SprAttr,X
.attr_done:
    LDA.w C2Scene_Task.Frames,X
    CMP.w C2Scene_ObjTask.Duration,X
    BCS .landed
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    CLC
    RTS
.landed:
    LDA.b #!C2Scene_ObjBusy
    TRB.w !C2Scene_Unk0294
    STZ.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_AnimObjARest5
    JSR C2Scene_SetAnim
    REP #$20
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    JSR C2Anim_Run
    CLC
    RTS

; $C2:4728 — C2Scene_ObjAAfterMode8 (251 bytes, $4728–$4822)
; State 6 (C2Scene_ObjAStMode8): waits for C2Scene_ObjANextLoc, which
; C2Scene_ObjAWait and C2Scene_ObjAFly zero before scene mode
; C2Scene_ModeUnk8 (so probably mode 8's sub-program C2Scene_Unk6A34
; sets it; not traced). Every frame C2Scene_ObjAX/Y = the position,
; C2Scene_Unk1BF7 = 0 and C2Anim_Run. Then:
; - negative: C2Scene_ObjAInMode8 cleared; without C2Scene_ObjAFlag5
;   also C2Scene_ObjBusy, animation C2Scene_AnimObjARest, .State
;   C2Scene_ObjAStWaitEmpty, velocity and .Frames 0; with it .State
;   C2Scene_ObjAStFly (back to flying);
; - positive: .State C2Scene_ObjAStScript on the script
;   C2Scene_ObjAScrLeave (which takes the party to location
;   C2Scene_ObjANextLoc and puts the object there), and the entry
;   position for it: C2Scene_ObjALoc1D9: tile (7, 8) facing down;
;   C2Scene_ObjALoc1F7: the location becomes C2Scene_ObjALoc1D8 at (7,
;   8), or C2Scene_ObjALoc1B0 at (7, 24) with C2Scene_ObjAFlag5, facing
;   down; C2Scene_ObjALoc1F2 without C2Scene_ObjAFlag5: location
;   C2Scene_ObjALoc0F3 at (8, 12) facing down, and bit 0 of
;   C2Scene_Unk7F00CC set; any other (also $1F2 with the flag): the
;   object's own tile (position / 8) and .Facing. The three named ones
;   also zero C2Scene_Unk7F00CD.
; Quirks, kept: the last case stores the tile X and Y as words, so
; Loc_EntryY is first written with the high byte of X / 8 and
; Loc_EntryFacing with that of Y / 8 before both are overwritten. The
; C2Scene_ObjALoc1F2 case leaves X = C2Scene_Tile8x12 ($0C08), so .done
; copies the words at $0C1C and $0C20 (inside the task records) into
; C2Scene_ObjAX/Y instead of the task's position (the script then leaves
; the scene). The negative case without C2Scene_ObjAFlag5 reaches .done
; with M=0, so its STZ also zeroes the byte after C2Scene_Unk1BF7.
; Callers note: none direct (C2Scene_ObjAStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (DP_Field and low
;        WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0 (C2Anim_Run's); X = the task; A, Y clobbered
; Calls: C2Scene_SetAnim, C2Anim_Run.
C2Scene_ObjAAfterMode8:
    LDX.b !C2Scene_TaskCur
    LDY.w !C2Scene_ObjANextLoc
    BNE .chosen
    JMP .done
.chosen:
    BPL .leave
    LDA.b #!C2Scene_ObjAInMode8
    TRB.w !C2Scene_Unk0294
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BNE .fly
    LDA.b #!C2Scene_ObjBusy
    TRB.w !C2Scene_Unk0294
    LDA.b #!C2Scene_AnimObjARest
    JSR C2Scene_SetAnim
    LDA.b #!C2Scene_ObjAStWaitEmpty
    STA.w C2Scene_ObjTask.State,X
    REP #$20
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    JMP .done
.fly:
    LDA.b #!C2Scene_ObjAStFly
    STA.w C2Scene_ObjTask.State,X
    JMP .done
.leave:
    LDA.b #!C2Scene_ObjAStScript
    STA.w C2Scene_ObjTask.State,X
    STZ.w C2Scene_Task.ScriptWait,X
    LDA.b #bank(C2Scene_ObjAScrLeave)
    STA.w C2Scene_Task.ScriptBank,X
    REP #$20
    LDA.w #C2Scene_ObjAScrLeave
    STA.w C2Scene_Task.ScriptPtr,X
    SEP #$20
    CPY.w #!C2Scene_ObjALoc1D9
    BNE .not_1d9
    LDY.w #!C2Scene_Tile7x8
    STY.w !DP_Field+!Loc_EntryX
    LDA.b #!C2Scene_FacingDown
    STA.w !DP_Field+!Loc_EntryFacing
    TDC
    STA.l !C2Scene_Unk7F00CD
    BRA .done
.not_1d9:
    CPY.w #!C2Scene_ObjALoc1F7
    BNE .not_1f7
    LDX.w #!C2Scene_ObjALoc1D8
    LDY.w #!C2Scene_Tile7x8
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BEQ .set_1f7
    LDX.w #!C2Scene_ObjALoc1B0
    LDY.w #!C2Scene_Tile7x24
.set_1f7:
    STX.w !C2Scene_ObjANextLoc
    STY.w !DP_Field+!Loc_EntryX
    LDA.b #!C2Scene_FacingDown
    STA.w !DP_Field+!Loc_EntryFacing
    TDC
    STA.l !C2Scene_Unk7F00CD
    LDX.b !C2Scene_TaskCur
    BRA .done
.not_1f7:
    CPY.w #!C2Scene_ObjALoc1F2
    BNE .own_tile
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BNE .own_tile
    LDX.w #!C2Scene_ObjALoc0F3
    STX.w !C2Scene_ObjANextLoc
    LDX.w #!C2Scene_Tile8x12
    STX.w !DP_Field+!Loc_EntryX
    LDA.b #!C2Scene_FacingDown
    STA.w !DP_Field+!Loc_EntryFacing
    TDC
    STA.l !C2Scene_Unk7F00CD
    LDA.l !C2Scene_Unk7F00CC
    ORA.b #!C2Scene_Unk7F00CCBit0
    STA.l !C2Scene_Unk7F00CC
    BRA .done
.own_tile:
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    LSR A                       ; / C2Scene_TilePx
    LSR A
    LSR A
    STA.w !DP_Field+!Loc_EntryX ; quirk: a word (see the header)
    LDA.w C2Scene_Task.SprY,X
    LSR A
    LSR A
    LSR A
    STA.w !DP_Field+!Loc_EntryY
    SEP #$20
    LDA.w C2Scene_ObjTask.Facing,X
    STA.w !DP_Field+!Loc_EntryFacing
.done:
    LDY.w C2Scene_Task.SprX,X
    STY.w !C2Scene_ObjAX
    LDY.w C2Scene_Task.SprY,X
    STY.w !C2Scene_ObjAY
    STZ.w !C2Scene_Unk1BF7
    JSR C2Anim_Run
    CLC
    RTS

; $C2:4823 — C2Scene_ObjAScript (101 bytes, $4823–$4887)
; State 7 (C2Scene_ObjAStScript): runs the task's own script
; (C2Scene_TaskRunScript on .ScriptPtr: C2Scene_ObjAScrArrive or
; C2Scene_ObjAScrLeave). When it ends (C=1): C2Scene_ObjAInMode8
; cleared; without C2Scene_ObjAFlag5 also C2Scene_ObjBusy, animation
; C2Scene_AnimObjARest, .State 0, velocity and .Frames 0, C2Anim_Run;
; with it .State C2Scene_ObjAStFly, the property nibbles at the position
; and C2Anim_Run. Every frame C2Scene_ObjAX/Y = the position and
; C2Scene_Unk1BF7 = 0.
; Callers note: none direct (C2Scene_ObjAStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM: the
;        script's RAM ops and the task records); C2Scene_TaskCur = the
;        task
; Exit:  C=0; M=1, X=0; X = the task (not reloaded after a waiting
;        script: the ops its scripts stop on, C2Script_WaitAnimating,
;        C2Script_MoveFrames and C2Script_Wait (C2Scene_ObjAScrLeave's
;        flag-5 path), leave it in X; at the end C2Scene_SetAnim
;        or an LDX reloads it); A, Y clobbered
; Calls: C2Scene_TaskRunScript, C2Scene_SetAnim, C2Scene_GetTileProps,
;   C2Scene_ObjAGetProps, C2Anim_Run.
C2Scene_ObjAScript:
    JSR C2Scene_TaskRunScript
    BCC .copy_pos
    LDA.b #!C2Scene_ObjAInMode8
    TRB.w !C2Scene_Unk0294
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BNE .fly
    LDA.b #!C2Scene_ObjBusy
    TRB.w !C2Scene_Unk0294
    LDA.b #!C2Scene_AnimObjARest
    JSR C2Scene_SetAnim
    STZ.w C2Scene_ObjTask.State,X
    REP #$20
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    JSR C2Anim_Run
    BRA .copy_pos
.fly:
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_ObjAStFly
    STA.w C2Scene_ObjTask.State,X
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    JSR C2Scene_ObjAGetProps
    JSR C2Anim_Run
.copy_pos:
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_ObjAX
    LDA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_ObjAY
    SEP #$20
    STZ.w !C2Scene_Unk1BF7
    CLC
    RTS

; $C2:4888 — C2Scene_ObjAWaitEmpty (17 bytes, $4888–$4898)
; State 8 (C2Scene_ObjAStWaitEmpty): when C2Scene_ObjWatch reaches
; C2Scene_ObjWatchStEmpty (the party is getting out), .State 0;
; C2Anim_Run every frame.
; Callers note: none direct (C2Scene_ObjAStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Anim_Run.
C2Scene_ObjAWaitEmpty:
    LDA.w !C2Scene_Unk027E
    CMP.b #!C2Scene_ObjWatchStEmpty
    BNE .run
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_ObjTask.State,X
.run:
    JSR C2Anim_Run
    CLC
    RTS

; $C2:4899 — C2Scene_ObjAStepVel (8 words, $4899–$48A8)
; C2Scene_ObjAFly's step velocity per facing: .XVel then .YVel (whole
; pixels a frame, signed).
C2Scene_ObjAStepVel:
    dw 0,-2&$FFFF               ; up
    dw 0,2                      ; down
    dw -2&$FFFF,0               ; left
    dw 2,0                      ; right

; $C2:48A9 — C2Scene_ObjAFaceAnim (28 bytes, $48A9–$48C4)
; Starts the animation of the task's .Facing: entry .Facing of
; C2Scene_ObjAFaceAnims, or of C2Scene_ObjAFaceAnims5 with
; C2Scene_ObjAFlag5 (C2Scene_SetAnim, by JMP).
; Callers (3 JSR sites): C2Scene_ObjAInit ($C2:436B), C2Scene_ObjARise ($C2:4484) and
;   C2Scene_ObjAFly ($C2:4652).
; Callers note: also script op $34 (C2Script_CallNear) in
;   C2Scene_ObjAScrArrive.
; Entry: M=1, X=0, DP=$0000 (TDC for 0, C2Scene_TaskCur), DB=$00 (low
;        WRAM absolute); C2Scene_TaskCur = the task
; Exit:  as C2Scene_SetAnim: M=1, X=0; X = the task; A =
;        C2SceneRom_AnimBank; Y unchanged
; Calls: C2Scene_SetAnim (JMP).
C2Scene_ObjAFaceAnim:
    LDX.b !C2Scene_TaskCur
    TDC                         ; A = DP = 0: clears the high byte
    LDA.w C2Scene_ObjTask.Facing,X
    TAX
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BNE .flag5
    LDA.l C2Scene_ObjAFaceAnims,X
    JMP C2Scene_SetAnim
.flag5:
    LDA.l C2Scene_ObjAFaceAnims5,X
    JMP C2Scene_SetAnim

; $C2:48C5 — C2Scene_ObjAFaceAnims (4 bytes, $48C5–$48C8)
; Animation numbers per facing (up, down, left, right) of
; C2Scene_ObjAFaceAnim.
C2Scene_ObjAFaceAnims:
    db $2F,$2E,$30,$31

; $C2:48C9 — C2Scene_ObjAFaceAnims5 (4 bytes, $48C9–$48CC)
; The same with C2Scene_ObjAFlag5.
C2Scene_ObjAFaceAnims5:
    db $1C,$1B,$1D,$1E

; $C2:48CD — C2Scene_ObjAJump (27 bytes, $48CD–$48E7)
; Moves the task C2Scene_ObjAJumpPx (512) pixels in X the way .XVel
; points (back when it is negative) and wraps the position
; (C2Scene_WrapTaskPos, by JMP). Called by script op $34 in the
; sideways dashes of C2Scene_ObjAScrLeave and C2Scene_ObjAScrArrive,
; between their two halves.
; Callers note: none direct (script op $34, C2Script_CallNear).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur), DB=$00
;        (low WRAM absolute); C2Scene_TaskCur = the task
; Exit:  as C2Scene_WrapTaskPos: M=0, X=0; X = the task; A = the new
;        .SprY; Y unchanged
; Calls: C2Scene_WrapTaskPos (JMP).
C2Scene_ObjAJump:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.XVel,X
    BMI .back
    LDA.w #!C2Scene_ObjAJumpPx
    BRA .add
.back:
    LDA.w #-!C2Scene_ObjAJumpPx&$FFFF
.add:
    CLC
    ADC.w C2Scene_Task.SprX,X
    STA.w C2Scene_Task.SprX,X
    JMP C2Scene_WrapTaskPos

; $C2:48E8 — C2Scene_ObjAOverlap (47 bytes, $48E8–$4916)
; C=1 when object A is active (C2Scene_ObjActive in C2Scene_Unk0294),
; at the current location (Loc_Id equal to C2Scene_ObjALoc, unmasked)
; and its box (C2Scene_ObjAFlyBox at C2Scene_ObjAX/Y) overlaps box A,
; which the caller sets (C2Scene_BoxAX/AY/APtr). C2Scene_ObjBFly uses it
; so object B does not come down on A; C2Scene_ObjBOverlap is its
; object-B twin.
; Quirk, kept: the AND #$FF before the CPX does nothing, as in
; C2Scene_ObjWatchIdle.
; Callers (1 JSR site): C2Scene_ObjBFly ($C2:4E46).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (the box temporaries),
;        DB=$00 (DP_Field and low WRAM absolute); box A set
; Exit:  X=0; C=1 (M=0) on an overlap; C=0 with M=1 (inactive or
;        elsewhere) or M=0 (no overlap); A, X, Y clobbered;
;        C2Scene_BoxBX/BY/BPtr set when the boxes are tested
; Calls: C2Scene_BoxesOverlap.
C2Scene_ObjAOverlap:
    SEP #$20
    LDA.w !C2Scene_Unk0294
    BPL .no                     ; not C2Scene_ObjActive
    LDX.w !DP_Field+!Loc_Id
    AND.b #!Eng_LowByteMask     ; quirk: no effect (see the header)
    CPX.w !C2Scene_ObjALoc
    BNE .no
    LDX.w !C2Scene_ObjAX
    STX.b !C2Scene_BoxBX
    LDX.w !C2Scene_ObjAY
    STX.b !C2Scene_BoxBY
    LDX.w #C2Scene_ObjAFlyBox
    STX.b !C2Scene_BoxBPtr
    LDA.b #bank(C2Scene_ObjAFlyBox)
    STA.b !C2Scene_BoxBPtr+2
    REP #$20
    JSR C2Scene_BoxesOverlap
    BCC .no
    SEC
    RTS
.no:
    CLC
    RTS

; $C2:4917 — C2Scene_ObjBOverlap (47 bytes, $4917–$4945)
; C2Scene_ObjAOverlap for object B: active (C2Scene_ObjBFlags), Loc_Id
; C2Scene_ObjBLocId (unmasked) and C2Scene_ObjBLandBox at
; C2Scene_ObjBX/Y against box A. C2Scene_ObjAFly uses it so object A does
; not come down on object B.
; Quirk, kept: the same AND #$FF with no effect.
; Callers (1 JSR site): C2Scene_ObjAFly ($C2:4556).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (the box temporaries),
;        DB=$00 (DP_Field and low WRAM absolute); box A set
; Exit:  as C2Scene_ObjAOverlap: C=1 only with M=0
; Calls: C2Scene_BoxesOverlap.
C2Scene_ObjBOverlap:
    SEP #$20
    LDA.w !C2Scene_ObjBFlags
    BPL .no                     ; not C2Scene_ObjActive
    LDX.w !DP_Field+!Loc_Id
    AND.b #!Eng_LowByteMask     ; quirk: no effect (see the header)
    CPX.w #!C2Scene_ObjBLocId
    BNE .no
    LDX.w !C2Scene_ObjBX
    STX.b !C2Scene_BoxBX
    LDX.w !C2Scene_ObjBY
    STX.b !C2Scene_BoxBY
    LDX.w #C2Scene_ObjBLandBox
    STX.b !C2Scene_BoxBPtr
    LDA.b #bank(C2Scene_ObjBLandBox)
    STA.b !C2Scene_BoxBPtr+2
    REP #$20
    JSR C2Scene_BoxesOverlap
    BCC .no
    SEC
    RTS
.no:
    CLC
    RTS

; $C2:4946 — C2Scene_ObjAFlyBox (4 words, $4946–$494D)
; C2Scene_BoxesOverlap extents (left, right, up, down) of object A in
; C2Scene_ObjAFly and C2Scene_ObjASpotWatch: 8 each way.
C2Scene_ObjAFlyBox:
    dw 8,8,8,8

; $C2:494E — C2Scene_ObjBLandBox (4 words, $494E–$4955)
; Object B's extents for C2Scene_ObjBOverlap: 8 each way.
C2Scene_ObjBLandBox:
    dw 8,8,8,8

; $C2:4956 — C2Scene_SpotBox (4 words, $4956–$495D)
; The extents of the spot at C2Scene_SpotX/Y (C2Scene_ObjASpotWatch): 8
; each way.
C2Scene_SpotBox:
    dw 8,8,8,8

; $C2:495E — C2Scene_ObjAMarkTask (9 bytes, $495E–$4966)
; Task handler of a second sprite that goes with object A (no reference
; in the bank's code, as C2Scene_ObjATask): runs the
; C2Scene_ObjAMarkStates handler of .State.
; Callers note: none found.
; Entry: M=1, X=0, X = C2Scene_TaskCur = the task, DP=$0000 (TDC for 0:
;        B = 0 for the TAX), DB=$00 (low WRAM)
; Exit:  as the state's handler
; Calls: a C2Scene_ObjAMarkStates handler (JMP (abs,X)).
C2Scene_ObjAMarkTask:
    TDC
    LDA.w C2Scene_ObjTask.State,X
    ASL A
    TAX
    JMP (C2Scene_ObjAMarkStates,X)

; $C2:4967 — C2Scene_ObjAMarkStates (2 words, $4967–$496A)
; C2Scene_ObjAMarkTask's handler for .State 0 and 1.
C2Scene_ObjAMarkStates:
    dw C2Scene_ObjAMarkInit     ; 0
    dw C2Scene_ObjAMarkShow     ; 1

; $C2:496B — C2Scene_ObjAMarkInit (33 bytes, $496B–$498B)
; State 0: ends the task (C=1) unless object A is at this location
; (Loc_Id AND C2Scene_LocIdMask equal to C2Scene_ObjALoc). Otherwise
; .State 1, .SprAttr C2Scene_ObjAttrPrio3, .SprTile 0, and falls into
; C2Scene_ObjAMarkShow.
; Callers note: none direct (C2Scene_ObjAMarkStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (DP_Field and low
;        WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=1 (the task ends), M=1, A = the low byte of the compare; or as
;        C2Scene_ObjAMarkShow
; Calls: falls into C2Scene_ObjAMarkShow.
C2Scene_ObjAMarkInit:
    REP #$20
    LDA.w !DP_Field+!Loc_Id
    AND.w #!C2Scene_LocIdMask
    CMP.w !C2Scene_ObjALoc
    SEP #$20
    BEQ .here
    SEC
    RTS
.here:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_ObjAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
    STZ.w C2Scene_Task.SprTile,X
    STZ.w C2Scene_Task.SprTile+1,X

; $C2:498C — C2Scene_ObjAMarkShow (67 bytes, $498C–$49CE)
; State 1, every frame: with C2Scene_ObjAFlag5 and C2Scene_ObjAAloft
; set, animation C2Scene_AnimMarkBelow at C2Scene_ObjAX, C2Scene_ObjAY +
; C2Scene_Lift (24 pixels below object A: probably its shadow while
; it is up); otherwise C2Scene_AnimMarkAbove at C2Scene_ObjAX,
; C2Scene_ObjAY - C2Scene_Lift. Then C2Anim_Run. The animation is
; started again (C2Scene_SetAnim) on every frame, so it never gets past
; its first step.
; Callers note: none direct (C2Scene_ObjAMarkStates); C2Scene_ObjAMarkInit
;   falls in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_SetAnim, C2Anim_Run.
C2Scene_ObjAMarkShow:
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BEQ .above
    LDA.w !C2Scene_ObjAAloft
    BNE .below
.above:
    LDA.b #!C2Scene_AnimMarkAbove
    JSR C2Scene_SetAnim
    REP #$20
    LDA.w !C2Scene_ObjAX
    STA.w C2Scene_Task.SprX,X
    CLC
    LDA.w !C2Scene_ObjAY
    ADC.w #!C2Scene_LiftUp
    STA.w C2Scene_Task.SprY,X
    BRA .run
.below:
    LDA.b #!C2Scene_AnimMarkBelow
    JSR C2Scene_SetAnim
    REP #$20
    LDA.w !C2Scene_ObjAX
    STA.w C2Scene_Task.SprX,X
    CLC
    LDA.w !C2Scene_ObjAY
    ADC.w #!C2Scene_Lift
    STA.w C2Scene_Task.SprY,X
.run:
    JSR C2Anim_Run
    CLC
    RTS

; $C2:49CF — C2Scene_ObjASpotWatch (91 bytes, $49CF–$4A29)
; Task handler (no reference in the bank's code): while C2Scene_ObjWatch
; is in C2Scene_ObjWatchStBusyA (the party in object A) and
; C2Scene_ObjAInMode8 is clear, tests object A's box
; (C2Scene_ObjAFlyBox at C2Scene_ObjAX/Y) against C2Scene_SpotBox at
; C2Scene_SpotX/Y. On an overlap it sets C2Scene_ObjAOnSpot, puts
; C2Scene_Unk1B58Spot in C2Scene_Unk1B58 and sets C2Scene_TrigKeep in
; C2Scene_TrigFlags; otherwise it clears all three. C=0 (never ends).
; Callers note: none found.
; Entry: M=1, X=0, DP=$0000 (the box temporaries), DB=$00 (low WRAM
;        absolute)
; Exit:  C=0; M=1, X=0; A clobbered; when the test runs, X =
;        C2Scene_SpotBox, Y as C2Scene_BoxesOverlap leaves it and
;        C2Tmp_08-$15 set
; Calls: C2Scene_BoxesOverlap.
C2Scene_ObjASpotWatch:
    LDA.w !C2Scene_Unk027E
    CMP.b #!C2Scene_ObjWatchStBusyA
    BNE .done
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BNE .done
    LDX.w !C2Scene_ObjAX
    STX.b !C2Scene_BoxAX
    LDX.w !C2Scene_ObjAY
    STX.b !C2Scene_BoxAY
    LDX.w #C2Scene_ObjAFlyBox
    STX.b !C2Scene_BoxAPtr
    LDA.b #bank(C2Scene_ObjAFlyBox)
    STA.b !C2Scene_BoxAPtr+2
    LDX.w !C2Scene_SpotX
    STX.b !C2Scene_BoxBX
    LDX.w !C2Scene_SpotY
    STX.b !C2Scene_BoxBY
    LDX.w #C2Scene_SpotBox
    STX.b !C2Scene_BoxBPtr
    LDA.b #bank(C2Scene_SpotBox)
    STA.b !C2Scene_BoxBPtr+2
    JSR C2Scene_BoxesOverlap
    SEP #$20
    BCC .off
    LDA.b #!C2Scene_ObjAOnSpot
    TSB.w !C2Scene_Unk0294
    LDA.b #!C2Scene_Unk1B58Spot
    STA.w !C2Scene_Unk1B58
    LDA.b #!C2Scene_TrigKeep
    TSB.w !C2Scene_TrigFlags
    CLC
    RTS
.off:
    LDA.b #!C2Scene_ObjAOnSpot
    TRB.w !C2Scene_Unk0294
    STZ.w !C2Scene_Unk1B58
    LDA.b #!C2Scene_TrigKeep
    TRB.w !C2Scene_TrigFlags
.done:
    CLC
    RTS

; $C2:4A2A — C2Scene_ObjASound (46 bytes, $4A2A–$4A57)
; Queues C2Scene_SoundCmd10 with C2Scene_ObjASongArg (arguments
; C2Scene_SoundArgUnused, C2Scene_SoundArg80, rank 0), as
; C2Scene_ZoneSoundQueue does with a zone's sound; when it is queued
; (C=0) the argument goes to C2Scene_Unk02AE. Probably object A's music.
; Quirk, kept: both values of C2Scene_ObjAFlag5 load the same argument.
; Callers (2 JSR sites): C2Scene_ObjAWait ($C2:4404) and C2Scene_ObjARise ($C2:4487).
; Entry: M=1, X any (not used), DP any, DB=$00 (low WRAM absolute)
; Exit:  M=1; C as C2Scene_QueueSoundCmd leaves it; A clobbered; X, Y
;        unchanged
; Calls: C2Scene_QueueSoundCmd.
C2Scene_ObjASound:
    LDA.b #!C2Scene_SoundCmd10
    STA.w !C2Scene_SoundCmdBuf
    LDA.b #!C2Scene_SoundArgUnused
    STA.w !C2Scene_SoundCmdBuf+2
    LDA.b #!C2Scene_SoundArg80
    STA.w !C2Scene_SoundCmdBuf+3
    STZ.w !C2Scene_SoundCmdPrio
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAFlag5
    BNE .flag5
    LDA.b #!C2Scene_ObjASongArg
    BRA .set
.flag5:
    LDA.b #!C2Scene_ObjASongArg ; quirk: the same (see the header)
.set:
    STA.w !C2Scene_SoundCmdBuf+1
    JSR C2Scene_QueueSoundCmd
    BCS .done
    LDA.w !C2Scene_SoundCmdBuf+1
    STA.w !C2Scene_Unk02AE
.done:
    RTS

; $C2:4A58 — C2Scene_ObjAGetProps (67 bytes, $4A58–$4A9A)
; After C2Scene_GetTileProps (C2Scene_PropX/Y = the point's 8x8 column
; and row): .PropBL = the property nibble of the tile below-left (column
; - 1, wrapping to C2Scene_MapTilesX - 1, row + 1 AND 127) and .PropB
; that of the tile below (column, row + 1), through C2Scene_GetTileProp
; on BG2's map and C2Scene_Unk7000. With .PropUL-DR that makes the six
; nibbles C2Scene_ObjAFly checks before coming down.
; Callers (4 JSR sites): C2Scene_ObjAInit ($C2:437F), C2Scene_ObjAWait ($C2:4416), C2Scene_ObjAFly
;   ($C2:466C) and C2Scene_ObjAScript ($C2:486D).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Tmp_00-$04, $08-$15),
;        DB=$00 (WRMPYA/B and RDMPYL absolute); C2Scene_PropX/Y from
;        C2Scene_GetTileProps; C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; A = .PropB; Y as C2Scene_GetTileProp
;        leaves it; C2Scene_PropY = row + 1; C2Scene_PropMap/PropTable
;        set; C2Tmp_00-$04 changed
; Calls: C2Scene_GetTileProp.
C2Scene_ObjAGetProps:
    SEP #$20
    LDY.w #(!C2Scene_BgMaps+!C2Scene_MapBytes)&$FFFF ; layer 2's map
    STY.b !C2Scene_PropMap
    LDA.b #bank(!C2Scene_BgMaps)
    STA.b !C2Scene_PropMap+2
    LDY.w #!C2Scene_Unk7000&$FFFF
    STY.b !C2Scene_PropTable
    LDA.b #bank(!C2Scene_Unk7000)
    STA.b !C2Scene_PropTable+2
    REP #$20
    LDA.b !C2Scene_PropX
    DEC A
    BPL .col_ok
    LDA.w #!C2Scene_MapTilesX-1
.col_ok:
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_PropY
    INC A
    AND.w #!C2Scene_MapTilesY-1
    STA.b !C2Scene_PropY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_ObjTask.PropBL,X
    LDA.b !C2Scene_PropX
    STA.b !C2Scene_PropCol
    LDA.b !C2Scene_PropY
    STA.b !C2Scene_PropRow
    JSR C2Scene_GetTileProp
    LDX.b !C2Scene_TaskCur
    STA.w C2Scene_ObjTask.PropB,X
    RTS

; Object A's scene scripts (C2Scene_TaskRunScript). Task byte operands
; are offsets into the running task's record: .Facing (+$28) is object
; A's facing, and +$22 (.PropUL) serves as a loop count. Branch offsets
; count from the opcode; a C2Script_Jump target is written one less.

; $C2:4A9B — C2Scene_ObjAScrGo1DD (18 bytes, $4A9B–$4AAC)
; Script of a task C2Scene_ObjARise starts with C2Scene_Flag0ObjAGo1DD:
; the new task (a copy of object A's record) puts its sprite at .SprY
; $198 with animation $1B, fades out and leaves for location $1DD at tile
; (7, 25) facing down.
C2Scene_ObjAScrGo1DD:
    db $0D,C2Scene_Task.SprY,$98 ; C2Script_SetTaskByte
    db $0D,C2Scene_Task.SprY+1,$01 ; C2Script_SetTaskByte: .SprY = $198
    db $30,$1B                  ; C2Script_SetAnim
    db $28,$01                  ; C2Script_SpawnUnk20A2 (fade out), 1 frame per step
    db $39,$12                  ; C2Script_WaitAnimating, 18 frames
    db $05,$DD,$03,$07,$19      ; C2Script_GoToLocation: $03DD (Loc_Id $1DD, facing 1), X 7, Y 25
    db $52                      ; C2Script_End

; $C2:4AAD — C2Scene_ObjAScrLeave (223 bytes, $4AAD–$4B8B)
; Object A's own script for state C2Scene_ObjAStScript after mode 8 chose
; a location (C2Scene_ObjAAfterMode8). Without C2Scene_ObjAFlag5: sound
; command C2Scene_SoundCmd18 ($C8, $80), sprite palette 0 (palette 8)
; faded to C2SceneRom_ObjAPalA's colors and then to
; C2SceneRom_LastPalRow's, and a fade out. With it: sound $AC, $80, half
; a pixel a frame ahead for 64 frames (C2Scene_ObjAScrSlowVel), then a
; dash at 8 pixels a frame (C2Scene_ObjAScrDash, 50 rounds of 2 frames;
; sideways it is split in 14 and 36 with a C2Scene_ObjAJump between),
; palette 8 faded to C2SceneRom_ObjAPalA, 12 more rounds, sound $AD,
; $80, palettes 0-7 and 9-15 set at once (0 from C2SceneRom_ObjAPalB,
; the others from C2SceneRom_ObjAPalA; palette 8 is still in its 32-step
; fade, 24 frames along) and a fade out. Both end at .go:
; Loc_ReturnId = Loc_Id, C2Scene_ObjALoc = C2Scene_ObjANextLoc,
; scene mode C2Scene_ModeUnk2 (C2Scene_Mode2 leaves the scene), Loc_Id =
; C2Scene_ObjANextLoc, and an 8-frame wait.
C2Scene_ObjAScrLeave:
    db $26                      ; C2Script_IfRamBitsSet: C2Scene_ObjAFlag5 in C2Scene_Unk0294
    dw !C2Scene_Unk0294
    db !C2Scene_ObjAFlag5,.flag5-C2Scene_ObjAScrLeave
    db $3B,$C8,$80              ; C2Script_SoundCmd18
    db $04                      ; C2Script_SpawnUnk1DD4: palette 8 from
    dl !C2SceneRom_ObjAPalA     ; C2SceneRom_ObjAPalA,
    db $08,$02                  ; a step every 2 frames
    db $39,$40                  ; C2Script_WaitAnimating, 64 frames
    db $04                      ; C2Script_SpawnUnk1DD4: palette 8 from
    dl !C2SceneRom_LastPalRow
    db $08,$02
    db $39,$14                  ; C2Script_WaitAnimating, 20 frames
    db $28,$02                  ; C2Script_SpawnUnk20A2 (fade out), 2 frames per step
    db $39,$22                  ; C2Script_WaitAnimating, 34 frames
    db $1A                      ; C2Script_Jump to .go
    dw .go-1
.flag5:
    db $3B,$AC,$80              ; C2Script_SoundCmd18
    db $2E                      ; C2Script_SetXVelocity: 0
    dw 0,0
    db $2F                      ; C2Script_SetYVelocity: 0
    dw 0,0
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrSlowVel
    db $31,$40                  ; C2Script_MoveFrames, 64 frames
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrFastVel
    db $0D,C2Scene_ObjTask.PropUL,50 ; C2Script_SetTaskByte: the dash's rounds
.test_up:
    db $1C,C2Scene_ObjTask.Facing,.dash-.test_up ; C2Script_IfTaskByteZero: up
.test_down:
    db $1F,C2Scene_ObjTask.Facing,!C2Scene_FacingDown,.dash-.test_down ; C2Script_IfTaskByteEq: down
    db $0D,C2Scene_ObjTask.PropUL,14 ; C2Script_SetTaskByte: sideways, 14 rounds,
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrDash
    db $34                      ; C2Script_CallNear
    dw C2Scene_ObjAJump
    db $0D,C2Scene_ObjTask.PropUL,36 ; C2Script_SetTaskByte: then 36
.dash:
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrDash
    db $04                      ; C2Script_SpawnUnk1DD4: palette 8 from
    dl !C2SceneRom_ObjAPalA
    db $08,$01                  ; a step every frame
    db $0D,C2Scene_ObjTask.PropUL,12 ; C2Script_SetTaskByte
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrDash
    db $3B,$AD,$80              ; C2Script_SoundCmd18
    db $04                      ; C2Script_SpawnUnk1DD4: palette 0 at once
    dl !C2SceneRom_ObjAPalB
    db $00,$00
    db $04                      ; C2Script_SpawnUnk1DD4: palettes 1-7 and 9-15 at once
    dl !C2SceneRom_ObjAPalA
    db $01,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $02,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $03,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $04,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $05,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $06,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $07,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $09,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $0A,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $0B,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $0C,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $0D,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $0E,$00
    db $04
    dl !C2SceneRom_ObjAPalA
    db $0F,$00
    db $28,$02                  ; C2Script_SpawnUnk20A2 (fade out), 2 frames per step
    db $38,$22                  ; C2Script_Wait, 34 frames
.go:
    db $19                      ; C2Script_CopyRamByte
    dw !DP_Field+!Loc_ReturnId,!DP_Field+!Loc_Id
    db $19
    dw !DP_Field+!Loc_ReturnId+1,!DP_Field+!Loc_Id+1
    db $19
    dw !C2Scene_ObjALoc,!C2Scene_ObjANextLoc
    db $19
    dw !C2Scene_ObjALoc+1,!C2Scene_ObjANextLoc+1
    db $13                      ; C2Script_SetRamByte
    dw !C2Scene_Mode
    db !C2Scene_ModeUnk2
    db $19                      ; C2Script_CopyRamByte
    dw !DP_Field+!Loc_Id,!C2Scene_ObjANextLoc
    db $19
    dw !DP_Field+!Loc_Id+1,!C2Scene_ObjANextLoc+1
    db $39,$08                  ; C2Script_WaitAnimating, 8 frames
    db $52                      ; C2Script_End

; $C2:4B8C — C2Scene_ObjAScrArrive (108 bytes, $4B8C–$4BF7)
; Object A's own script when the scene loads with the party in it after
; mode 8 (C2Scene_ObjAInit). Without C2Scene_ObjAFlag5: sprite priority
; bits $20 and C2Scene_SprAttrScroll, the rest animation, palette 8 set
; to C2SceneRom_LastPalRow's colors, sound $AE, $80, then faded to
; C2SceneRom_ObjAPalA's and back to the scene's own (C2Scene_ObjPal0,
; the palette the scene loaded into C2Scene_PaletteStage). With it:
; C2Script_SoundCmd10IfClear with $13 (C2Scene_ObjASongArg), the
; facing's animation (C2Scene_ObjAFaceAnim), palette 8 set to
; C2SceneRom_ObjAPalA, a dash in at 8 pixels a frame (62 rounds; 16 and
; 46 sideways, C2Scene_ObjAJump between) with palette 8 faded back to
; the scene's own, and 64 frames at half a pixel a frame.
C2Scene_ObjAScrArrive:
    db $26                      ; C2Script_IfRamBitsSet: C2Scene_ObjAFlag5 in C2Scene_Unk0294
    dw !C2Scene_Unk0294
    db !C2Scene_ObjAFlag5,.flag5-C2Scene_ObjAScrArrive
    db $02,$20                  ; C2Script_SetSprPriority
    db $0E,C2Scene_Task.SprAttr,!C2Scene_SprAttrScroll ; C2Script_OrTaskByte
    db $30,!C2Scene_AnimObjARest ; C2Script_SetAnim
    db $04                      ; C2Script_SpawnUnk1DD4: palette 8 at once from
    dl !C2SceneRom_LastPalRow
    db $08,$00
    db $39,$01                  ; C2Script_WaitAnimating, 1 frame
    db $3B,$AE,$80              ; C2Script_SoundCmd18
    db $39,$0F                  ; C2Script_WaitAnimating, 15 frames
    db $04                      ; C2Script_SpawnUnk1DD4: palette 8 from
    dl !C2SceneRom_ObjAPalA
    db $08,$02                  ; a step every 2 frames
    db $39,$40                  ; C2Script_WaitAnimating, 64 frames
    db $04                      ; C2Script_SpawnUnk1DD4: palette 8 from
    dl !C2Scene_ObjPal0
    db $08,$02
    db $39,$40                  ; C2Script_WaitAnimating, 64 frames
    db $52                      ; C2Script_End
.flag5:
    db $3D,!C2Scene_ObjASongArg ; C2Script_SoundCmd10IfClear
    db $34                      ; C2Script_CallNear
    dw C2Scene_ObjAFaceAnim
    db $04                      ; C2Script_SpawnUnk1DD4: palette 8 at once from
    dl !C2SceneRom_ObjAPalA
    db $08,$00
    db $2E                      ; C2Script_SetXVelocity: 0
    dw 0,0
    db $2F                      ; C2Script_SetYVelocity: 0
    dw 0,0
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrFastVel
    db $39,$04                  ; C2Script_WaitAnimating, 4 frames
    db $04                      ; C2Script_SpawnUnk1DD4: palette 8 from
    dl !C2Scene_ObjPal0
    db $08,$01                  ; a step every frame
    db $3B,$AE,$80              ; C2Script_SoundCmd18
    db $0D,C2Scene_ObjTask.PropUL,62 ; C2Script_SetTaskByte: the dash's rounds
.test_up:
    db $1C,C2Scene_ObjTask.Facing,.dash-.test_up ; C2Script_IfTaskByteZero: up
.test_down:
    db $1F,C2Scene_ObjTask.Facing,!C2Scene_FacingDown,.dash-.test_down ; C2Script_IfTaskByteEq: down
    db $0D,C2Scene_ObjTask.PropUL,16 ; C2Script_SetTaskByte: sideways, 16 rounds,
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrDash
    db $34                      ; C2Script_CallNear
    dw C2Scene_ObjAJump
    db $0D,C2Scene_ObjTask.PropUL,46 ; C2Script_SetTaskByte: then 46
.dash:
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrDash
    db $36                      ; C2Script_Call
    dw C2Scene_ObjAScrSlowVel
    db $31,$40                  ; C2Script_MoveFrames, 64 frames
    db $52                      ; C2Script_End

; $C2:4BF8 — C2Scene_ObjAScrSlowVel (35 bytes, $4BF8–$4C1A)
; Script subroutine (C2Script_Call): the velocity half a pixel a frame
; in the .Facing direction (the other axis left as it is).
C2Scene_ObjAScrSlowVel:
    db $1D,C2Scene_ObjTask.Facing,.not_up-C2Scene_ObjAScrSlowVel ; C2Script_IfTaskByteNonZero
    db $2F                      ; C2Script_SetYVelocity: -0.5
    dw !C2Scene_HalfPixel,!C2Scene_WholeMinus1
    db $37                      ; C2Script_Return
.not_up:
    db $1E,C2Scene_ObjTask.Facing,!C2Scene_FacingDown,.not_down-.not_up ; C2Script_IfTaskByteNe
    db $2F                      ; C2Script_SetYVelocity: +0.5
    dw !C2Scene_HalfPixel,0
    db $37                      ; C2Script_Return
.not_down:
    db $1E,C2Scene_ObjTask.Facing,!C2Scene_FacingLeft,.right-.not_down ; C2Script_IfTaskByteNe
    db $2E                      ; C2Script_SetXVelocity: -0.5
    dw !C2Scene_HalfPixel,!C2Scene_WholeMinus1
    db $37                      ; C2Script_Return
.right:
    db $2E                      ; C2Script_SetXVelocity: +0.5
    dw !C2Scene_HalfPixel,0
    db $37                      ; C2Script_Return

; $C2:4C1B — C2Scene_ObjAScrFastVel (35 bytes, $4C1B–$4C3D)
; C2Scene_ObjAScrSlowVel at 8 pixels a frame.
C2Scene_ObjAScrFastVel:
    db $1D,C2Scene_ObjTask.Facing,.not_up-C2Scene_ObjAScrFastVel ; C2Script_IfTaskByteNonZero
    db $2F                      ; C2Script_SetYVelocity: -8
    dw 0,-8&$FFFF
    db $37                      ; C2Script_Return
.not_up:
    db $1E,C2Scene_ObjTask.Facing,!C2Scene_FacingDown,.not_down-.not_up ; C2Script_IfTaskByteNe
    db $2F                      ; C2Script_SetYVelocity: +8
    dw 0,8
    db $37                      ; C2Script_Return
.not_down:
    db $1E,C2Scene_ObjTask.Facing,!C2Scene_FacingLeft,.right-.not_down ; C2Script_IfTaskByteNe
    db $2E                      ; C2Script_SetXVelocity: -8
    dw 0,-8&$FFFF
    db $37                      ; C2Script_Return
.right:
    db $2E                      ; C2Script_SetXVelocity: +8
    dw 0,8
    db $37                      ; C2Script_Return

; $C2:4C3E — C2Scene_ObjAScrDash (10 bytes, $4C3E–$4C47)
; Script subroutine: task byte +$22 rounds of 2 frames' movement
; (C2Script_MoveFrames), each starting a C2Scene_ObjAScrTrail task.
C2Scene_ObjAScrDash:
    db $31,$02                  ; C2Script_MoveFrames, 2 frames
    db $09                      ; C2Script_SpawnScript
    dl C2Scene_ObjAScrTrail
.loop_op:
    db $1B,C2Scene_ObjTask.PropUL,(C2Scene_ObjAScrDash-.loop_op)&$FF ; C2Script_LoopTaskByte
    db $37                      ; C2Script_Return

; $C2:4C48 — C2Scene_ObjAScrTrail (39 bytes, $4C48–$4C6E)
; Script of the tasks C2Scene_ObjAScrDash starts (each a copy of object
; A's record, so at its position): the animation for the copied .Facing
; ($33 up, $32 down, $34 left, $35 right), shown for 8 rounds of a frame
; of animation and a frame of wait, then the task ends. Probably the
; dash's after-images.
C2Scene_ObjAScrTrail:
    db $1D,C2Scene_ObjTask.Facing,.not_up-C2Scene_ObjAScrTrail ; C2Script_IfTaskByteNonZero
    db $30,$33                  ; C2Script_SetAnim
    db $1A                      ; C2Script_Jump to .show
    dw .show-1
.not_up:
    db $1E,C2Scene_ObjTask.Facing,!C2Scene_FacingDown,.not_down-.not_up ; C2Script_IfTaskByteNe
    db $30,$32                  ; C2Script_SetAnim
    db $1A                      ; C2Script_Jump to .show
    dw .show-1
.not_down:
    db $1E,C2Scene_ObjTask.Facing,!C2Scene_FacingLeft,.right-.not_down ; C2Script_IfTaskByteNe
    db $30,$34                  ; C2Script_SetAnim
    db $1A                      ; C2Script_Jump to .show
    dw .show-1
.right:
    db $30,$35                  ; C2Script_SetAnim
.show:
    db $0D,C2Scene_ObjTask.PropUL,8 ; C2Script_SetTaskByte
.loop:
    db $39,$01                  ; C2Script_WaitAnimating, 1 frame
    db $38,$01                  ; C2Script_Wait, 1 frame
.loop_op:
    db $1B,C2Scene_ObjTask.PropUL,(.loop-.loop_op)&$FF ; C2Script_LoopTaskByte
    db $52                      ; C2Script_End

; $C2:4C6F — C2Scene_ObjAScrUnk4C6F (32 bytes, $4C6F–$4C8E)
; A script with no reference found (no pointer to it in the bank): fade
; out, swap the low bytes of Loc_Id and Loc_ReturnId (through task byte
; +$22), C2Scene_ObjALoc = Loc_Id, scene mode C2Scene_ModeUnk2. Probably
; a way back to the return location with object A; use not traced.
C2Scene_ObjAScrUnk4C6F:
    db $28,$02                  ; C2Script_SpawnUnk20A2 (fade out), 2 frames per step
    db $38,$21                  ; C2Script_Wait, 33 frames
    db $17,C2Scene_ObjTask.PropUL ; C2Script_RamByteToTask
    dw !DP_Field+!Loc_Id
    db $19                      ; C2Script_CopyRamByte
    dw !DP_Field+!Loc_Id,!DP_Field+!Loc_ReturnId
    db $16,C2Scene_ObjTask.PropUL ; C2Script_TaskByteToRam
    dw !DP_Field+!Loc_ReturnId
    db $19                      ; C2Script_CopyRamByte
    dw !C2Scene_ObjALoc,!DP_Field+!Loc_Id
    db $19
    dw !C2Scene_ObjALoc+1,!DP_Field+!Loc_Id+1
    db $13                      ; C2Script_SetRamByte
    dw !C2Scene_Mode
    db !C2Scene_ModeUnk2
    db $52                      ; C2Script_End

; $C2:4C8F — C2Scene_ObjAScrSpot (54 bytes, $4C8F–$4CC4)
; Script of the task C2Scene_ObjAFly starts on the spot
; (C2Scene_ObjAOnSpot): fade out, Loc_Id, Loc_EntryX/Y and
; Loc_EntryFacing copied to Loc_ReturnId-Loc_ReturnFacing, then location
; $1C1 at tile (7, 21) facing down and scene mode C2Scene_ModeUnk2.
C2Scene_ObjAScrSpot:
    db $28,$02                  ; C2Script_SpawnUnk20A2 (fade out), 2 frames per step
    db $38,$21                  ; C2Script_Wait, 33 frames
    db $19                      ; C2Script_CopyRamByte
    dw !DP_Field+!Loc_ReturnId,!DP_Field+!Loc_Id
    db $19
    dw !DP_Field+!Loc_ReturnId+1,!DP_Field+!Loc_Id+1
    db $19
    dw !DP_Field+!Loc_ReturnX,!DP_Field+!Loc_EntryX
    db $19
    dw !DP_Field+!Loc_ReturnY,!DP_Field+!Loc_EntryY
    db $19
    dw !DP_Field+!Loc_ReturnFacing,!DP_Field+!Loc_EntryFacing
    db $13                      ; C2Script_SetRamByte: Loc_Id = $01C1
    dw !DP_Field+!Loc_Id
    db $C1
    db $13
    dw !DP_Field+!Loc_Id+1
    db $01
    db $13                      ; C2Script_SetRamByte: Loc_EntryX = 7
    dw !DP_Field+!Loc_EntryX
    db $07
    db $13                      ; C2Script_SetRamByte: Loc_EntryY = 21
    dw !DP_Field+!Loc_EntryY
    db $15
    db $13                      ; C2Script_SetRamByte: Loc_EntryFacing = down
    dw !DP_Field+!Loc_EntryFacing
    db !C2Scene_FacingDown
    db $13                      ; C2Script_SetRamByte
    dw !C2Scene_Mode
    db !C2Scene_ModeUnk2
    db $52                      ; C2Script_End

; ============================================================
; Object B's tasks and its two mates ($C2:4CC5–$C2:5627)
; ============================================================
; C2Scene_ObjBTask is object B's own sprite (C2Scene_ObjBX/Y,
; C2Scene_ObjBFlags), with C2Scene_ObjAFly's controls but its own
; checks before it comes down and no mode 8. C2Scene_ObjBMarkTask draws a
; second sprite with it, as C2Scene_ObjAMarkTask does for A. The two
; mate tasks run for party slots 1 and 2 (.Slot, +$24, as
; C2Scene_FollowTask, set by whoever starts them; not traced): each shows
; object B's rest animation in that member's palette
; (C2Scene_Member1Pal / Member2Pal) and, once the party is in, goes up
; with B and keeps to a spot beside it (C2Scene_ObjBMateSpot), then comes
; back to B's position when B lands. Their positions are kept in
; C2Scene_ObjBMate1X/Y and C2Scene_ObjBMate2X/Y (C2Scene_ObjBMateSavePos),
; where their mark tasks (C2Scene_ObjBMateMarkTask) follow them. None of
; the five task handlers has a reference in the bank's code (probably
; started from scene data, as the others). What object B is, is not
; traced (location C2Scene_ObjBLocId; something three can ride,
; probably).

; $C2:4CC5 — C2Scene_ObjBTask (9 bytes, $4CC5–$4CCD)
; Task handler: runs the C2Scene_ObjBStates handler of .State.
; Callers note: none found (see the banner).
; Entry: M=1, X=0, X = C2Scene_TaskCur = the task, DP=$0000 (TDC for 0:
;        B = 0 for the TAX), DB=$00 (low WRAM)
; Exit:  as the state's handler
; Calls: a C2Scene_ObjBStates handler (JMP (abs,X)).
C2Scene_ObjBTask:
    TDC
    LDA.w C2Scene_ObjTask.State,X
    ASL A
    TAX
    JMP (C2Scene_ObjBStates,X)

; $C2:4CCE — C2Scene_ObjBStates (6 words, $4CCE–$4CD9)
; C2Scene_ObjBTask's handler for each .State 0-5.
C2Scene_ObjBStates:
    dw C2Scene_ObjBInit         ; 0
    dw C2Scene_ObjBWait         ; 1 (C2Scene_ObjBStWait)
    dw C2Scene_ObjBRise         ; 2
    dw C2Scene_ObjBFly          ; 3 (C2Scene_ObjBStFly)
    dw C2Scene_ObjBMove         ; 4
    dw C2Scene_ObjBLand         ; 5 (C2Scene_ObjBStLand)

; $C2:4CDA — C2Scene_ObjBInit (93 bytes, $4CDA–$4D36)
; State 0: the sprite at C2Scene_ObjBX/Y (fractions and .SprTile 0),
; facing down (.Facing, .PrevFacing). Without C2Scene_ObjBusy in
; C2Scene_ObjBFlags: .State C2Scene_ObjBStWait, .SprAttr
; C2Scene_ObjBAttrPrio2, C2Scene_ObjBAloft = 0, animation
; C2Scene_AnimObjBRest. With it (the scene loaded with the party in B):
; .State C2Scene_ObjBStFly, .SprAttr C2Scene_ObjBAttrPrio3,
; C2Scene_ObjBAloft = 1, the facing-down animation of
; C2Scene_ObjBFaceAnims. C2Anim_Run either way.
; Callers note: none direct (C2Scene_ObjBStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_SetAnim, C2Anim_Run.
C2Scene_ObjBInit:
    LDX.b !C2Scene_TaskCur
    REP #$20
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_Task.SprX,X
    LDA.w !C2Scene_ObjBY
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.XFrac,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.SprTile,X
    SEP #$20
    LDA.b #!C2Scene_FacingDown
    STA.w C2Scene_ObjTask.Facing,X
    STA.w C2Scene_ObjTask.PrevFacing,X
    LDA.w !C2Scene_ObjBFlags
    BIT.b #!C2Scene_ObjBusy
    BNE .busy
    INC.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_ObjBAttrPrio2
    STA.w C2Scene_Task.SprAttr,X
    STZ.w !C2Scene_ObjBAloft
    LDA.b #!C2Scene_AnimObjBRest
    JSR C2Scene_SetAnim
    JSR C2Anim_Run
    CLC
    RTS
.busy:
    LDA.b #!C2Scene_ObjBStFly
    STA.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_ObjBAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
    LDA.b #1
    STA.w !C2Scene_ObjBAloft
    LDX.w #!C2Scene_FacingDown
    LDA.l C2Scene_ObjBFaceAnims,X
    JSR C2Scene_SetAnim
    JSR C2Anim_Run
    CLC
    RTS

; $C2:4D37 — C2Scene_ObjBWait (66 bytes, $4D37–$4D78)
; State 1: runs the animation until C2Scene_ObjWatch reaches
; C2Scene_ObjWatchStBusyB (the party is in B); then sets C2Scene_ObjBusy
; in C2Scene_ObjBFlags, .State 2, the property nibbles at the position
; (C2Scene_GetTileProps; .PropBL/B are never set by these tasks),
; velocity C2Scene_HalfPixel up, .Frames 0, animation
; C2Scene_AnimObjBRise, and falls into C2Scene_ObjBRise.
; Callers note: none direct (C2Scene_ObjBStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur, C2Tmp_00-$15), DB=$00
;        (low WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered (waiting); else as
;        C2Scene_ObjBRise
; Calls: C2Anim_Run, C2Scene_GetTileProps, C2Scene_SetAnim.
C2Scene_ObjBWait:
    LDA.w !C2Scene_Unk027E
    CMP.b #!C2Scene_ObjWatchStBusyB
    BEQ .aboard
    JSR C2Anim_Run
    CLC
    RTS
.aboard:
    LDA.b #!C2Scene_ObjBusy
    TSB.w !C2Scene_ObjBFlags
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_ObjTask.State,X
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    REP #$20
    LDA.w #!C2Scene_HalfPixel
    STA.w C2Scene_Task.YVelFrac,X
    LDA.w #!C2Scene_WholeMinus1
    STA.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.Frames,X
    LDA.w #!C2Scene_AnimObjBRise
    JSR C2Scene_SetAnim

; $C2:4D79 — C2Scene_ObjBRise (86 bytes, $4D79–$4DCE)
; State 2: as C2Scene_ObjARise with fixed counts: moves for
; C2Scene_RiseFrames frames (.SprAttr C2Scene_ObjBAttrPrio3 from frame
; C2Scene_RiseAttrAt); then .State C2Scene_ObjBStFly,
; C2Scene_ObjBAloft = 1, .SprY + C2Scene_Lift, velocity and .Frames 0,
; the facing-down animation (C2Scene_ObjBFaceAnims entry 1, loaded as a
; constant), Loc_EntryFacing bits 0-1 = .Facing, and falls into
; C2Scene_ObjBFly.
; Callers note: none direct (C2Scene_ObjBStates); C2Scene_ObjBWait falls
;   in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (DP_Field and low
;        WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered (moving); else as
;        C2Scene_ObjBFly
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Anim_Run,
;   C2Scene_SetAnim.
C2Scene_ObjBRise:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_RiseAttrAt
    BNE .attr_done
    LDA.b #!C2Scene_ObjBAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
.attr_done:
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_RiseFrames
    BCS .risen
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    CLC
    RTS
.risen:
    INC.w C2Scene_ObjTask.State,X
    LDA.b #1
    STA.w !C2Scene_ObjBAloft
    REP #$20
    CLC
    LDA.w C2Scene_Task.SprY,X
    ADC.w #!C2Scene_Lift
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    LDA.w #!C2Scene_AnimObjBDown
    JSR C2Scene_SetAnim
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask^$FF
    ORA.w C2Scene_ObjTask.Facing,X
    STA.w !DP_Field+!Loc_EntryFacing

; $C2:4DCF — C2Scene_ObjBFly (431 bytes, $4DCF–$4F7D)
; State 3 (C2Scene_ObjBStFly): in scene mode C2Scene_ModeIdle1, with
; any bit of Pad_Unk00F8 (a word) set:
; - Pad_Unk00F8Bit7 comes down when none of .PropUL-DR and .PropBL/B
;   has a bit of C2Scene_ObjALandMask, .PropUL/UR are not both trigger
;   tiles (C2Scene_OnTrigTiles), object A's box does not overlap B's
;   (C2Scene_ObjAOverlap with C2Scene_ObjBLandBox at C2Scene_ObjBX/Y) and
;   B's 8x8 tile is not inside the rectangle of columns 0 to
;   C2Scene_ObjBNoLandCols - 1 and rows 0 to C2Scene_ObjBNoLandRows - 1
;   (BankC6_UnkE74E): velocity
;   C2Scene_HalfPixel down, .Frames 0, .SprY - C2Scene_Lift, animation
;   C2Scene_AnimObjBRise, facing down (also into Loc_EntryFacing),
;   C2Scene_ObjBAloft = 0, C2Scene_ObjBLanding set (the mates come
;   back), .State C2Scene_ObjBStLand;
; - otherwise (also bit 7 where it cannot come down) Pad_Unk00F8Bit6
;   selects mode C2Scene_ModeMenu, Pad_Unk00F8Bit2 C2Scene_ModeMode7, and
;   Up, Down, Left, Right start a step (.step): the velocity from
;   C2Scene_ObjBStepVel; on a new facing .Facing, its bits in
;   Loc_EntryFacing and its C2Scene_ObjBFaceAnims animation; .TargetX/Y 8
;   pixels ahead (C2Scene_SetStepTarget, C2Scene_WrapStepTarget) and the
;   four nibbles there (C2Scene_GetTileProps). If any of them has both
;   wall bits (C2Scene_TilePropWallBits) the step is dropped: velocity 0
;   and the nibbles read again at the position. Else C2Scene_Unk1BF7 =
;   0, .State + 1 and it falls into C2Scene_ObjBMove.
; .done: C2Anim_Run, C=0. Unlike object A there is no mode-8 button and
; .PrevFacing is not set here.
; Callers note: none direct (C2Scene_ObjBStates); C2Scene_ObjBRise falls
;   in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur and the box, property and
;        rectangle temporaries), DB=$00 (Pad_Unk00F8, DP_Field and low
;        WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered; C2Tmp_00-$15 changed
;        on the landing and step paths; or as C2Scene_ObjBMove
; Calls: C2Scene_OnTrigTiles, C2Scene_ObjAOverlap, BankC6_UnkE74E (JSL),
;   C2Scene_SetAnim, C2Scene_SetStepTarget, C2Scene_WrapStepTarget,
;   C2Scene_GetTileProps, C2Anim_Run.
!C2Scene_RectTileX = !C2Tmp_00          ; BankC6_UnkE74E's input: the 8x8 tile tested
!C2Scene_RectTileY = !C2Tmp_01
!C2Scene_RectTop = !C2Tmp_02            ; the rectangle: rows top to bottom - 1
!C2Scene_RectBottom = !C2Tmp_03
!C2Scene_RectLeft = !C2Tmp_04           ; columns left to right - 1
!C2Scene_RectRight = !C2Tmp_05
!C2Scene_RectOut = !C2Tmp_06            ; out: non-zero when the tile is outside
!C2Scene_StepFacing = !C2Tmp_08         ; 16-bit: the facing of the step being started
C2Scene_ObjBFly:
    LDA.w !C2Scene_Mode
    CMP.b #!C2Scene_ModeIdle1
    BNE .done
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !Pad_Unk00F8
    BEQ .done
    BIT.w #!Pad_Unk00F8Bit7
    BNE .button7
.buttons:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !Pad_Unk00F8
    BIT.w #!Pad_Unk00F8Bit6
    BEQ .not6
    JMP .menu
.not6:
    BIT.w #!Pad_Unk00F8Bit2
    BEQ .not2
    JMP .mode7
.not2:
    BIT.w #!C2Scene_PadUp
    BEQ .not_up
    JMP .up
.not_up:
    BIT.w #!C2Scene_PadDown
    BEQ .not_down
    JMP .down
.not_down:
    BIT.w #!C2Scene_PadLeft
    BEQ .not_left
    JMP .left
.not_left:
    BIT.w #!C2Scene_PadRight
    BEQ .done
    JMP .right
.done:
    JSR C2Anim_Run
    CLC
    RTS
.button7:
    LDA.w C2Scene_ObjTask.PropUL,X
    ORA.w C2Scene_ObjTask.PropDL,X
    ORA.w C2Scene_ObjTask.PropBL,X
    AND.w #!C2Scene_ObjALandMask
    BNE .buttons
    JSR C2Scene_OnTrigTiles
    BCS .buttons
    LDX.w !C2Scene_ObjBX
    STX.b !C2Scene_BoxAX
    LDX.w !C2Scene_ObjBY
    STX.b !C2Scene_BoxAY
    LDX.w #C2Scene_ObjBLandBox
    STX.b !C2Scene_BoxAPtr
    LDA.b #bank(C2Scene_ObjBLandBox)
    STA.b !C2Scene_BoxAPtr+2
    JSR C2Scene_ObjAOverlap
    BCS .buttons
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,X
    LSR A                       ; / C2Scene_TilePx
    LSR A
    LSR A
    STA.b !C2Scene_RectTileX
    LDA.w C2Scene_Task.SprY,X
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RectTileY
    SEP #$20
    STZ.b !C2Scene_RectTop
    LDA.b #!C2Scene_ObjBNoLandRows
    STA.b !C2Scene_RectBottom
    STZ.b !C2Scene_RectLeft
    LDA.b #!C2Scene_ObjBNoLandCols
    STA.b !C2Scene_RectRight
    JSL BankC6_UnkE74E
    LDA.b !C2Scene_RectOut
    BNE .land
    JMP .buttons
.land:
    REP #$20
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    LDA.w #!C2Scene_HalfPixel
    STA.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    CLC
    LDA.w C2Scene_Task.SprY,X
    ADC.w #!C2Scene_LiftUp
    STA.w C2Scene_Task.SprY,X
    LDA.w #!C2Scene_AnimObjBRise
    JSR C2Scene_SetAnim
    LDA.b #!C2Scene_FacingDown
    STA.w C2Scene_ObjTask.Facing,X
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask^$FF
    ORA.w C2Scene_ObjTask.Facing,X
    STA.w !DP_Field+!Loc_EntryFacing
    STZ.w !C2Scene_ObjBAloft
    LDA.b #!C2Scene_ObjBLanding
    TSB.w !C2Scene_ObjBFlags
    LDA.b #!C2Scene_ObjBStLand
    STA.w C2Scene_ObjTask.State,X
    JMP .done
.menu:
    SEP #$20
    LDA.b #!C2Scene_ModeMenu
    STA.w !C2Scene_Mode
    JMP .done
.mode7:
    SEP #$20
    LDA.b #!C2Scene_ModeMode7
    STA.w !C2Scene_Mode
    JMP .done
.up:
    TDC                         ; C2Scene_FacingUp
    BRA .step
.down:
    LDA.w #!C2Scene_FacingDown
    BRA .step
.left:
    LDA.w #!C2Scene_FacingLeft
    BRA .step
.right:
    LDA.w #!C2Scene_FacingRight
.step:
    STA.b !C2Scene_StepFacing
    LDY.b !C2Scene_TaskCur
    ASL A                       ; * 4: one C2Scene_ObjBStepVel entry
    ASL A
    TAX
    LDA.l C2Scene_ObjBStepVel,X
    STA.w C2Scene_Task.XVel,Y
    LDA.l C2Scene_ObjBStepVel+2,X
    STA.w C2Scene_Task.YVel,Y
    TYX
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.YVelFrac,X
    LDA.b !C2Scene_StepFacing
    SEP #$20
    CMP.w C2Scene_ObjTask.Facing,Y
    BEQ .same_facing
    STA.w C2Scene_ObjTask.Facing,Y
    TAX
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask^$FF
    ORA.w C2Scene_ObjTask.Facing,Y
    STA.w !DP_Field+!Loc_EntryFacing
    LDA.l C2Scene_ObjBFaceAnims,X
    JSR C2Scene_SetAnim
.same_facing:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_SetStepTarget
    JSR C2Scene_WrapStepTarget
    LDA.w C2Scene_ObjTask.TargetX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_ObjTask.TargetY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    LDA.w C2Scene_ObjTask.PropUL,X
    AND.b #!C2Scene_TilePropWallBits
    CMP.b #!C2Scene_TilePropWallBits
    BCS .blocked
    LDA.w C2Scene_ObjTask.PropUR,X
    AND.b #!C2Scene_TilePropWallBits
    CMP.b #!C2Scene_TilePropWallBits
    BCS .blocked
    LDA.w C2Scene_ObjTask.PropDL,X
    AND.b #!C2Scene_TilePropWallBits
    CMP.b #!C2Scene_TilePropWallBits
    BCS .blocked
    LDA.w C2Scene_ObjTask.PropDR,X
    AND.b #!C2Scene_TilePropWallBits
    CMP.b #!C2Scene_TilePropWallBits
    BCC .open
.blocked:
    REP #$20
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_PropX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_PropY
    JSR C2Scene_GetTileProps
    JSR C2Anim_Run
    CLC
    RTS
.open:
    STZ.w !C2Scene_Unk1BF7
    INC.w C2Scene_ObjTask.State,X

; $C2:4F7E — C2Scene_ObjBMove (109 bytes, $4F7E–$4FEA)
; State 4: C2Scene_ObjAMove for object B: moves, scrolls BG layers 1 and
; 2, C2Scene_Unk1BF1/1BF3 = the velocity, C2Anim_Run, C2Scene_ObjBX/Y =
; the position, and at the target .State = C2Scene_ObjBStFly (a word:
; .Frames' low byte too).
; Callers note: none direct (C2Scene_ObjBStates); C2Scene_ObjBFly falls
;   in.
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur and the
;        scroll temporaries), DB=$00 (low WRAM absolute); C2Scene_TaskCur
;        = the task
; Exit:  C=0; M=0, X=0; X = the task; A clobbered; Y and C2Tmp_00-$1A as
;        C2Anim_Run and the scrolls leave them
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_Unk0568,
;   C2Scene_Unk066C, C2Anim_Run.
C2Scene_ObjBMove:
    REP #$20
    LDX.b !C2Scene_TaskCur
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    SEP #$20
    LDA.w C2Scene_Task.XVel,X
    STA.b !C2Scene_ScrollPx
    LDA.b #1
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk0568
    LDA.b #2
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk0568
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.YVel,X
    STA.b !C2Scene_ScrollPx
    LDA.b #1
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk066C
    LDA.b #2
    STA.b !C2Scene_ScrollLayer
    JSR C2Scene_Unk066C
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.XVel,X
    STA.w !C2Scene_Unk1BF1
    LDA.w C2Scene_Task.YVel,X
    STA.w !C2Scene_Unk1BF3
    JSR C2Anim_Run
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_ObjBX
    LDA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_ObjBY
    LDA.w C2Scene_Task.SprX,X
    CMP.w C2Scene_ObjTask.TargetX,X
    BNE .moving
    LDA.w C2Scene_Task.SprY,X
    CMP.w C2Scene_ObjTask.TargetY,X
    BNE .moving
    LDA.w #!C2Scene_ObjBStFly
    STA.w C2Scene_ObjTask.State,X
.moving:
    CLC
    RTS

; $C2:4FEB — C2Scene_ObjBLand (76 bytes, $4FEB–$5036)
; State 5 (C2Scene_ObjBStLand): moves for C2Scene_LandFrames frames
; (.SprAttr C2Scene_ObjBAttrPrio2 from frame C2Scene_LandAttrAt); then
; C2Scene_ObjBusy and C2Scene_ObjBLanding cleared, .State
; C2Scene_ObjBStWait (not 0, unlike object A), animation
; C2Scene_AnimObjBRest, velocity and .Frames 0. C2Anim_Run either way.
; Callers note: none direct (C2Scene_ObjBStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_SetAnim,
;   C2Anim_Run.
C2Scene_ObjBLand:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_LandAttrAt
    BNE .attr_done
    LDA.b #!C2Scene_ObjBAttrPrio2
    STA.w C2Scene_Task.SprAttr,X
.attr_done:
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_LandFrames
    BCS .landed
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    CLC
    RTS
.landed:
    LDA.b #!C2Scene_ObjBusy
    TRB.w !C2Scene_ObjBFlags
    LDA.b #!C2Scene_ObjBLanding
    TRB.w !C2Scene_ObjBFlags
    LDA.b #!C2Scene_ObjBStWait
    STA.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_AnimObjBRest
    JSR C2Scene_SetAnim
    REP #$20
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    JSR C2Anim_Run
    CLC
    RTS

; $C2:5037 — C2Scene_ObjBStepVel (8 words, $5037–$5046)
; C2Scene_ObjBFly's step velocity per facing (.XVel, .YVel), as
; C2Scene_ObjAStepVel.
C2Scene_ObjBStepVel:
    dw 0,-2&$FFFF               ; up
    dw 0,2                      ; down
    dw -2&$FFFF,0               ; left
    dw 2,0                      ; right

; $C2:5047 — C2Scene_ObjBFaceAnims (4 bytes, $5047–$504A)
; Object B's animation per facing (up, down, left, right).
C2Scene_ObjBFaceAnims:
    db $26,$25,$27,$28

; $C2:504B — C2Scene_ObjBMarkTask (9 bytes, $504B–$5053)
; Task handler of object B's second sprite (no reference in the bank's
; code): runs the C2Scene_ObjBMarkStates handler of .State.
; Callers note: none found.
; Entry: M=1, X=0, X = C2Scene_TaskCur = the task, DP=$0000 (TDC for 0:
;        B = 0 for the TAX), DB=$00 (low WRAM)
; Exit:  as the state's handler
; Calls: a C2Scene_ObjBMarkStates handler (JMP (abs,X)).
C2Scene_ObjBMarkTask:
    TDC
    LDA.w C2Scene_ObjTask.State,X
    ASL A
    TAX
    JMP (C2Scene_ObjBMarkStates,X)

; $C2:5054 — C2Scene_ObjBMarkStates (2 words, $5054–$5057)
; C2Scene_ObjBMarkTask's handler for .State 0 and 1.
C2Scene_ObjBMarkStates:
    dw C2Scene_ObjBMarkInit     ; 0
    dw C2Scene_ObjBMarkShow     ; 1

; $C2:5058 — C2Scene_ObjBMarkInit (16 bytes, $5058–$5067)
; State 0: .State 1, .SprAttr C2Scene_ObjAttrPrio3, .SprTile 0; falls
; into C2Scene_ObjBMarkShow. (Unlike C2Scene_ObjAMarkInit it does not
; check the location.)
; Callers note: none direct (C2Scene_ObjBMarkStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  as C2Scene_ObjBMarkShow
; Calls: falls into C2Scene_ObjBMarkShow.
C2Scene_ObjBMarkInit:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_ObjAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
    STZ.w C2Scene_Task.SprTile,X
    STZ.w C2Scene_Task.SprTile+1,X

; $C2:5068 — C2Scene_ObjBMarkShow (39 bytes, $5068–$508E)
; State 1, every frame: the C2Scene_ObjBMarkOfs entry of
; C2Scene_ObjBAloft (0: above B, C2Scene_AnimMarkAbove; 1: below,
; C2Scene_AnimMarkBelow): the sprite at C2Scene_ObjBX, C2Scene_ObjBY +
; the entry's offset, its animation started again (so it stays on its
; first step), C2Anim_Run.
; Callers note: none direct (C2Scene_ObjBMarkStates); C2Scene_ObjBMarkInit
;   falls in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), B=0 (the 16-bit TAX; not
;        set here: from C2Scene_ObjBMarkTask's TDC),
;        DB=$00 (low WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_SetAnim, C2Anim_Run.
C2Scene_ObjBMarkShow:
    LDY.b !C2Scene_TaskCur
    LDA.w !C2Scene_ObjBAloft
    ASL A                       ; * 4: one C2Scene_ObjBMarkOfs entry
    ASL A
    TAX
    REP #$20
    CLC
    LDA.l C2Scene_ObjBMarkOfs,X
    ADC.w !C2Scene_ObjBY
    STA.w C2Scene_Task.SprY,Y
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_Task.SprX,Y
    LDA.l C2Scene_ObjBMarkOfs+2,X
    JSR C2Scene_SetAnim
    JSR C2Anim_Run
    CLC
    RTS

; $C2:508F — C2Scene_ObjBMarkOfs (4 words, $508F–$5096)
; Per C2Scene_ObjBAloft: the Y offset from object B and the animation.
C2Scene_ObjBMarkOfs:
    dw !C2Scene_LiftUp,!C2Scene_AnimMarkAbove ; 0: on the ground
    dw !C2Scene_Lift,!C2Scene_AnimMarkBelow   ; 1: up

; $C2:5097 — C2Scene_ObjBMateTask (9 bytes, $5097–$509F)
; Task handler of one of object B's mates (see the banner): runs the
; C2Scene_ObjBMateStates handler of .State.
; Callers note: none found.
; Entry: M=1, X=0, X = C2Scene_TaskCur = the task, DP=$0000 (TDC for 0:
;        B = 0 for the TAX), DB=$00 (low WRAM)
; Exit:  as the state's handler
; Calls: a C2Scene_ObjBMateStates handler (JMP (abs,X)).
C2Scene_ObjBMateTask:
    TDC
    LDA.w C2Scene_FollowTask.State,X
    ASL A
    TAX
    JMP (C2Scene_ObjBMateStates,X)

; $C2:50A0 — C2Scene_ObjBMateStates (6 words, $50A0–$50AB)
; C2Scene_ObjBMateTask's handler for each .State 0-5.
C2Scene_ObjBMateStates:
    dw C2Scene_ObjBMateInit     ; 0
    dw C2Scene_ObjBMateWait     ; 1 (C2Scene_MateStWait)
    dw C2Scene_ObjBMateRise     ; 2
    dw C2Scene_ObjBMateFollow   ; 3 (C2Scene_MateStFollow)
    dw C2Scene_ObjBMateMove     ; 4
    dw C2Scene_ObjBMateLand     ; 5 (C2Scene_MateStLand)

; $C2:50AC — C2Scene_ObjBMateInit (100 bytes, $50AC–$510F)
; State 0: the sprite at C2Scene_ObjBX/Y (fractions and .SprTile 0),
; facing down, .SprAttr C2Scene_MemberAttr with the slot's palette
; (C2Scene_Member1Pal for .Slot C2Scene_Slot1, else C2Scene_Member2Pal).
; Without C2Scene_ObjBusy in C2Scene_ObjBFlags: .State
; C2Scene_MateStWait and animation C2Scene_AnimObjBRest (no C2Anim_Run
; this frame). With it: .State C2Scene_MateStFollow, OAM priority 3
; (C2Scene_SprAttrPrioMask), .PrevFacing C2Scene_NoFacing so that
; C2Scene_ObjBMateFaceAnim starts the facing's animation, the position
; saved (C2Scene_ObjBMateSavePos), C2Anim_Run.
; Callers note: none direct (C2Scene_ObjBMateStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_SetAnim, C2Scene_ObjBMateFaceAnim,
;   C2Scene_ObjBMateSavePos, C2Anim_Run.
C2Scene_ObjBMateInit:
    LDX.b !C2Scene_TaskCur
    REP #$20
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_Task.SprX,X
    LDA.w !C2Scene_ObjBY
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.XFrac,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.SprTile,X
    SEP #$20
    LDA.b #!C2Scene_FacingDown
    STA.w C2Scene_FollowTask.Facing,X
    STA.w C2Scene_FollowTask.PrevFacing,X
    LDA.w C2Scene_FollowTask.Slot,X
    CMP.b #!C2Scene_Slot1
    BNE .slot2
    LDA.b #!C2Scene_MemberAttr|!C2Scene_Member1Pal
    BRA .attr
.slot2:
    LDA.b #!C2Scene_MemberAttr|!C2Scene_Member2Pal
.attr:
    STA.w C2Scene_Task.SprAttr,X
    LDA.w !C2Scene_ObjBFlags
    BIT.b #!C2Scene_ObjBusy
    BNE .busy
    INC.w C2Scene_FollowTask.State,X
    LDA.b #!C2Scene_AnimObjBRest
    JSR C2Scene_SetAnim
    CLC
    RTS
.busy:
    LDA.b #!C2Scene_MateStFollow
    STA.w C2Scene_FollowTask.State,X
    LDA.w C2Scene_Task.SprAttr,X
    ORA.b #!C2Scene_SprAttrPrioMask
    STA.w C2Scene_Task.SprAttr,X
    LDA.b #!C2Scene_NoFacing
    STA.w C2Scene_FollowTask.PrevFacing,X
    TDC                         ; B = 0 for C2Scene_ObjBMateFaceAnim's TAX
    JSR C2Scene_ObjBMateFaceAnim
    REP #$20
    JSR C2Scene_ObjBMateSavePos
    JSR C2Anim_Run
    CLC
    RTS

; $C2:5110 — C2Scene_ObjBMateWait (60 bytes, $5110–$514B)
; State 1: nothing (C=0) until C2Scene_ObjWatch reaches
; C2Scene_ObjWatchStBusyB. Then .State 2, .Frames 0, velocity up 1 and
; half a pixel sideways (right for slot 1 with animation
; C2Scene_AnimMate1Glide, left for slot 2 with C2Scene_AnimMate2Glide),
; and falls into C2Scene_ObjBMateRise.
; Callers note: none direct (C2Scene_ObjBMateStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0, M=1, A = C2Scene_Unk027E (waiting); else as
;        C2Scene_ObjBMateRise
; Calls: C2Scene_SetAnim.
C2Scene_ObjBMateWait:
    LDA.w !C2Scene_Unk027E
    CMP.b #!C2Scene_ObjWatchStBusyB
    BEQ .aboard
    CLC
    RTS
.aboard:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_FollowTask.State,X
    STZ.w C2Scene_Task.Frames,X
    LDA.w C2Scene_FollowTask.Slot,X
    CMP.b #!C2Scene_Slot1
    REP #$20
    BNE .slot2
    TDC                         ; right: whole 0 (+ the half below)
    LDY.w #!C2Scene_AnimMate1Glide
    BRA .set
.slot2:
    LDA.w #!C2Scene_WholeMinus1 ; left: whole -1 (+ the half)
    LDY.w #!C2Scene_AnimMate2Glide
.set:
    STA.w C2Scene_Task.XVel,X
    LDA.w #!C2Scene_HalfPixel
    STA.w C2Scene_Task.XVelFrac,X
    LDA.w #!C2Scene_WholeMinus1
    STA.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    TYA
    JSR C2Scene_SetAnim

; $C2:514C — C2Scene_ObjBMateRise (89 bytes, $514C–$51A4)
; State 2: moves for C2Scene_RiseFrames frames (OAM priority 3 from frame
; C2Scene_RiseAttrAt), saving the position (C2Scene_ObjBMateSavePos)
; and running the animation each frame. Then .State C2Scene_MateStFollow,
; priority 3, .SprY + C2Scene_Lift, velocity and .Frames 0, the facing's
; animation (.PrevFacing C2Scene_NoFacing), and falls into
; C2Scene_ObjBMateFollow.
; Callers note: none direct (C2Scene_ObjBMateStates); C2Scene_ObjBMateWait
;   falls in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered (moving); else as
;        C2Scene_ObjBMateFollow
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_ObjBMateSavePos,
;   C2Anim_Run, C2Scene_ObjBMateFaceAnim.
C2Scene_ObjBMateRise:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_RiseAttrAt
    BNE .attr_done
    LDA.w C2Scene_Task.SprAttr,X
    ORA.b #!C2Scene_SprAttrPrioMask
    STA.w C2Scene_Task.SprAttr,X
.attr_done:
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_RiseFrames
    BCS .risen
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Scene_ObjBMateSavePos
    JSR C2Anim_Run
    CLC
    RTS
.risen:
    INC.w C2Scene_FollowTask.State,X
    LDA.w C2Scene_Task.SprAttr,X
    ORA.b #!C2Scene_SprAttrPrioMask
    STA.w C2Scene_Task.SprAttr,X
    REP #$20
    CLC
    LDA.w C2Scene_Task.SprY,X
    ADC.w #!C2Scene_Lift
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.Frames,X
    SEP #$20
    TDC                         ; B = 0 for C2Scene_ObjBMateFaceAnim's TAX
    LDA.b #!C2Scene_NoFacing
    STA.w C2Scene_FollowTask.PrevFacing,X
    JSR C2Scene_ObjBMateFaceAnim

; $C2:51A5 — C2Scene_ObjBMateFollow (130 bytes, $51A5–$5226)
; State 3, also re-entered from C2Scene_ObjBMateMove every
; C2Scene_MateAimFrames frames:
; - with C2Scene_ObjBLanding (object B is coming down): .State
;   C2Scene_MateStLand, .Frames 0, +$22 = 0, .SprY - C2Scene_Lift, the
;   target C2Scene_ObjBX/Y (C2Scene_ObjBMateToObjB) reached in
;   C2Scene_MateGlideFrames frames (C2Scene_ObjBMateGlideVel), facing
;   down and the slot's glide animation, C2Anim_Run;
; - else the target is the mate's spot beside B (C2Scene_ObjBMateSpot);
;   if it is not reached (C2Scene_ObjBMateAim: velocity 2 pixels a frame
;   towards it) the facing follows the direction
;   (C2Scene_ObjBMateFaceDir); if it is, velocity 0 and .Facing =
;   Loc_EntryFacing's (the party's). Then the facing's animation if it
;   changed, .State 4, .Frames 0, and it falls into
;   C2Scene_ObjBMateMove.
; Quirk, kept: on the landing path .PrevFacing is loaded from absolute
; $0028 (the low byte of C2Scene_Bg2VScroll), not from the task's
; .Facing; nothing reads it before the next facing change sets it again.
; Callers note: also C2Scene_ObjBMateStates entry 3; C2Scene_ObjBMateRise
;   falls in.
; Callers (1 JMP site): C2Scene_ObjBMateMove ($C2:5246).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur, C2Tmp_00-$0E), DB=$00 (low WRAM
;        absolute and the division registers); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered (landing); else as
;        C2Scene_ObjBMateMove
; Calls: C2Scene_ObjBMateToObjB, C2Scene_ObjBMateGlideVel,
;   C2Scene_SetAnim, C2Anim_Run, C2Scene_ObjBMateSpot,
;   C2Scene_ObjBMateAim, C2Scene_ObjBMateFaceDir,
;   C2Scene_ObjBMateFaceAnim.
C2Scene_ObjBMateFollow:
    LDA.w !C2Scene_ObjBFlags
    BIT.b #!C2Scene_ObjBLanding
    BEQ .follow
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_MateStLand
    STA.w C2Scene_FollowTask.State,X
    STZ.w C2Scene_Task.Frames,X
    STZ.w C2Scene_FollowTask.ScanProp,X
    REP #$20
    CLC
    LDA.w C2Scene_Task.SprY,X
    ADC.w #!C2Scene_LiftUp
    STA.w C2Scene_Task.SprY,X
    JSR C2Scene_ObjBMateToObjB
    JSR C2Scene_ObjBMateGlideVel
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_Bg2VScroll   ; quirk: absolute, not the task's .Facing (see the header)
    STA.w C2Scene_FollowTask.PrevFacing,X
    LDA.b #!C2Scene_FacingDown
    STA.w C2Scene_FollowTask.Facing,X
    LDA.w C2Scene_FollowTask.Slot,X
    CMP.b #!C2Scene_Slot1
    BNE .slot2
    LDA.b #!C2Scene_AnimMate1Glide
    BRA .anim
.slot2:
    LDA.b #!C2Scene_AnimMate2Glide
.anim:
    JSR C2Scene_SetAnim
    JSR C2Anim_Run
    CLC
    RTS
.follow:
    TDC                         ; B = 0 for C2Scene_ObjBMateSpot's TAX
    JSR C2Scene_ObjBMateSpot
    JSR C2Scene_ObjBMateAim
    BCC .there
    JSR C2Scene_ObjBMateFaceDir
    BRA .face
.there:
    REP #$20
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    SEP #$20
    TDC
    LDA.w C2Scene_FollowTask.Facing,X
    STA.w C2Scene_FollowTask.PrevFacing,X
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask
    STA.w C2Scene_FollowTask.Facing,X
.face:
    JSR C2Scene_ObjBMateFaceAnim
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_FollowTask.State,X
    STZ.w C2Scene_Task.Frames,X

; $C2:5227 — C2Scene_ObjBMateMove (34 bytes, $5227–$5248)
; State 4: for C2Scene_MateAimFrames frames moves without overshooting
; the target (C2Scene_ObjBMateClampVel, C2Scene_TaskMove,
; C2Scene_WrapTaskPos), saves the position and runs the animation; then
; .State back to C2Scene_MateStFollow and on into C2Scene_ObjBMateFollow
; (JMP) to aim again.
; Callers note: none direct (C2Scene_ObjBMateStates);
;   C2Scene_ObjBMateFollow falls in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur, C2Tmp_08/$0A), DB=$00
;        (low WRAM absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered (moving); else as
;        C2Scene_ObjBMateFollow
; Calls: C2Scene_ObjBMateClampVel, C2Scene_TaskMove, C2Scene_WrapTaskPos,
;   C2Scene_ObjBMateSavePos, C2Anim_Run; jumps to C2Scene_ObjBMateFollow.
C2Scene_ObjBMateMove:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_MateAimFrames
    BCS .aim
    REP #$20
    JSR C2Scene_ObjBMateClampVel
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Scene_ObjBMateSavePos
    JSR C2Anim_Run
    CLC
    RTS
.aim:
    DEC.w C2Scene_FollowTask.State,X
    JMP C2Scene_ObjBMateFollow

; $C2:5249 — C2Scene_ObjBMateLand (65 bytes, $5249–$5289)
; State 5 (C2Scene_MateStLand): moves until .Frames passes
; C2Scene_LandFrames, which is $30 frames (C2Scene_TaskRunAll has
; already counted .Frames to 1 on the frame Follow ended), saving the
; position; then .State C2Scene_MateStWait, OAM priority 2
; (C2Scene_SprAttrPrio2), fractions and velocity 0. C2Anim_Run either
; way. (The glide velocity C2Scene_ObjBMateFollow set reaches object
; B's position after C2Scene_MateGlideFrames frames, the same $30
; frames this state moves.)
; Callers note: none direct (C2Scene_ObjBMateStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Scene_ObjBMateSavePos,
;   C2Anim_Run.
C2Scene_ObjBMateLand:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_LandFrames
    BCS .landed
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Scene_ObjBMateSavePos
    JSR C2Anim_Run
    CLC
    RTS
.landed:
    LDA.b #!C2Scene_MateStWait
    STA.w C2Scene_FollowTask.State,X
    LDA.w C2Scene_Task.SprAttr,X
    AND.b #!C2Scene_SprAttrPrioMask^$FF
    ORA.b #!C2Scene_SprAttrPrio2
    STA.w C2Scene_Task.SprAttr,X
    REP #$20
    STZ.w C2Scene_Task.XFrac,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    JSR C2Anim_Run
    CLC
    RTS

; $C2:528A — C2Scene_ObjBMateClampVel (147 bytes, $528A–$531C)
; Keeps a step from going past the target: per axis, when the distance
; to .TargetX (.TargetY) is less than the whole pixels of the speed
; (|.XVel| with the fraction's borrow), the velocity becomes that
; distance, fraction 0, negated again if it was negative
; (C2Scene_NegateXVel / NegateYVel). Distances of half the map or more
; are taken the other way round the map.
; Quirk, kept: the X wrap subtracts C2Scene_MapHeightPx (1024, the Y
; wrap) instead of C2Scene_MapWidthPx (1536), so a distance over half
; the width comes out 512 too short.
; Callers (1 JSR site): C2Scene_ObjBMateMove ($C2:5232).
; Entry: M=0, X=0, X = the task, DP=$0000 (C2Tmp_08, $0A), DB=$00 (low
;        WRAM absolute)
; Exit:  M=0, X=0; X unchanged; A, C2Tmp_08 and C2Tmp_0A clobbered; Y
;        unchanged
; Calls: C2Scene_NegateXVel, C2Scene_NegateYVel.
!C2Scene_ClampSpeed = !C2Tmp_08         ; 16-bit whole pixels of the speed on the axis
!C2Scene_ClampNeg = !C2Tmp_0A           ; non-zero: the velocity was negative
C2Scene_ObjBMateClampVel:
    STZ.b !C2Scene_ClampNeg
    LDA.w C2Scene_Task.XVel,X
    BPL .x_speed
    INC.b !C2Scene_ClampNeg
    CLC
    LDA.w C2Scene_Task.XVelFrac,X
    EOR.w #!Eng_Invert16
    ADC.w #1
    LDA.w C2Scene_Task.XVel,X
    EOR.w #!Eng_Invert16
    ADC.w #0
.x_speed:
    STA.b !C2Scene_ClampSpeed
    SEC
    LDA.w C2Scene_FollowTask.TargetX,X
    SBC.w C2Scene_Task.SprX,X
    BPL .x_dist
    EOR.w #!Eng_Invert16
    INC A
.x_dist:
    CMP.w #!C2Scene_MapWidthPx/2
    BCC .x_near
    SEC
    SBC.w #!C2Scene_MapHeightPx ; quirk: the Y wrap (see the header)
    EOR.w #!Eng_Invert16
    INC A
.x_near:
    CMP.b !C2Scene_ClampSpeed
    BCS .y
    STA.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.XVelFrac,X
    LDA.b !C2Scene_ClampNeg
    BEQ .y
    JSR C2Scene_NegateXVel
.y:
    STZ.b !C2Scene_ClampNeg
    LDA.w C2Scene_Task.YVel,X
    BPL .y_speed
    INC.b !C2Scene_ClampNeg
    CLC
    LDA.w C2Scene_Task.YVelFrac,X
    EOR.w #!Eng_Invert16
    ADC.w #1
    LDA.w C2Scene_Task.YVel,X
    EOR.w #!Eng_Invert16
    ADC.w #0
.y_speed:
    STA.b !C2Scene_ClampSpeed
    SEC
    LDA.w C2Scene_FollowTask.TargetY,X
    SBC.w C2Scene_Task.SprY,X
    BPL .y_dist
    EOR.w #!Eng_Invert16
    INC A
.y_dist:
    CMP.w #!C2Scene_MapHeightPx/2
    BCC .y_near
    SEC
    SBC.w #!C2Scene_MapHeightPx
    EOR.w #!Eng_Invert16
    INC A
.y_near:
    CMP.b !C2Scene_ClampSpeed
    BCS .done
    STA.w C2Scene_Task.YVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    LDA.b !C2Scene_ClampNeg
    BEQ .done
    JSR C2Scene_NegateYVel
.done:
    RTS

; $C2:531D — C2Scene_ObjBMateSpot (68 bytes, $531D–$5360)
; .TargetX/Y = the mate's spot beside object B: C2Scene_ObjBX/Y plus the
; C2Scene_ObjBMateSpots entry of (Loc_EntryFacing's facing * 2 + .Slot
; - 1), snapped to the 8x8 tile (C2Scene_TileSnapMask) and wrapped into
; the map (X once by C2Scene_MapWidthPx, Y AND C2Scene_MapHeightMask).
; Callers (1 JSR site): C2Scene_ObjBMateFollow ($C2:51EE).
; Entry: M=1, X=0, B=0 (the 16-bit TAX), DP=$0000 (C2Scene_TaskCur,
;        C2Tmp_00), DB=$00 (DP_Field and low WRAM absolute);
;        C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the entry offset, Y = the task; A = .TargetY's
;        low byte (B = its high byte); C2Tmp_00 = facing * 2
; No calls.
!C2Scene_SpotFacing2 = !C2Tmp_00        ; the party's facing * 2
C2Scene_ObjBMateSpot:
    LDY.b !C2Scene_TaskCur
    LDA.w !DP_Field+!Loc_EntryFacing
    AND.b #!C2Scene_FacingMask
    ASL A
    STA.b !C2Scene_SpotFacing2
    LDA.w C2Scene_FollowTask.Slot,Y
    DEC A
    ORA.b !C2Scene_SpotFacing2
    ASL A                       ; * 4: one C2Scene_ObjBMateSpots entry
    ASL A
    TAX
    REP #$20
    LDA.l C2Scene_ObjBMateSpots,X
    CLC
    ADC.w !C2Scene_ObjBX
    AND.w #!C2Scene_TileSnapMask
    BPL .x_pos
    CLC
    ADC.w #!C2Scene_MapWidthPx
    BRA .x_ok
.x_pos:
    CMP.w #!C2Scene_MapWidthPx
    BCC .x_ok
    SBC.w #!C2Scene_MapWidthPx
.x_ok:
    STA.w C2Scene_FollowTask.TargetX,Y
    LDA.l C2Scene_ObjBMateSpots+2,X
    CLC
    ADC.w !C2Scene_ObjBY
    AND.w #!C2Scene_MapHeightMask&!C2Scene_TileSnapMask
    STA.w C2Scene_FollowTask.TargetY,Y
    SEP #$20
    RTS

; $C2:5361 — C2Scene_ObjBMateToObjB (19 bytes, $5361–$5373)
; .TargetX/Y = C2Scene_ObjBX/Y.
; Callers (1 JSR site): C2Scene_ObjBMateFollow ($C2:51C5).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur), DB=$00
;        (low WRAM absolute); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; A = C2Scene_ObjBY; Y unchanged
; No calls.
C2Scene_ObjBMateToObjB:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_FollowTask.TargetX,X
    LDA.w !C2Scene_ObjBY
    STA.w C2Scene_FollowTask.TargetY,X
    SEP #$20
    RTS

; $C2:5374 — C2Scene_ObjBMateAim (95 bytes, $5374–$53D2)
; Velocity 0, then the direction from the position to .TargetX/Y
; (C2Scene_Unk229D). C=0 when C2Scene_Unk229D gives X = 0 (probably
; within 4 pixels on both axes: there). Else C=1 with the velocity 4 x
; the cosine and sine of the direction (C2Scene_Unk2273 / Unk2277) in
; 1/256 pixels (2 pixels a frame at most), written into the middle bytes
; of .XVelFrac/.XVel and .YVelFrac/.YVel with the high bytes
; sign-extended.
; Callers (1 JSR site): C2Scene_ObjBMateFollow ($C2:51F1).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur,
;        C2Tmp_00-$0E), DB=$00 (low WRAM absolute and C2Scene_Unk229D's
;        table); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; C as above; C2Tmp_08 = the direction (0-255; a word);
;        C2Tmp_0A-$0E the points; Y = the task (C=1) or 0 (C=0); A, X
;        clobbered
; Calls: C2Scene_Unk229D, C2Scene_Unk2273 (JSL), C2Scene_Unk2277 (JSL).
!C2Scene_AimFromX = !C2Tmp_08           ; C2Scene_Unk229D's input: the task's position
!C2Scene_AimFromY = !C2Tmp_0A
!C2Scene_AimToX = !C2Tmp_0C             ; and the target
!C2Scene_AimToY = !C2Tmp_0E
!C2Scene_AimDir = !C2Tmp_08             ; out: the direction
C2Scene_ObjBMateAim:
    REP #$20
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_AimFromX
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_AimFromY
    LDA.w C2Scene_FollowTask.TargetX,X
    STA.b !C2Scene_AimToX
    LDA.w C2Scene_FollowTask.TargetY,X
    STA.b !C2Scene_AimToY
    JSR C2Scene_Unk229D
    STA.b !C2Scene_AimDir
    TXY
    BNE .move
    SEP #$20
    CLC
    RTS
.move:
    LDY.b !C2Scene_TaskCur
    JSL C2Scene_Unk2273
    ASL A                       ; * 4
    ASL A
    STA.w C2Scene_Task.XVelFrac+1,Y
    LDA.b !C2Scene_AimDir
    JSL C2Scene_Unk2277
    ASL A
    ASL A
    STA.w C2Scene_Task.YVelFrac+1,Y
    TDC
    SEP #$20
    LDA.w C2Scene_Task.XVel,Y
    BPL .x_pos
    LDA.b #!C2Scene_SignByte
    STA.w C2Scene_Task.XVel+1,Y
.x_pos:
    LDA.w C2Scene_Task.YVel,Y
    BPL .y_pos
    LDA.b #!C2Scene_SignByte
    STA.w C2Scene_Task.YVel+1,Y
.y_pos:
    SEC
    RTS

; $C2:53D3 — C2Scene_ObjBMateGlideVel (105 bytes, $53D3–$543B)
; The velocity that reaches .TargetX/Y in C2Scene_MateGlideFrames
; frames: per axis the distance with its bytes swapped (XBA) divided by
; C2Scene_MateGlideFrames with the hardware divider, the quotient stored
; in the middle bytes (.XVelFrac+1, .XVel), negated for a negative
; distance. Exact for distances below 256 pixels (the high byte goes into
; the low byte of the dividend).
; Quirk, kept: the positive X case waits two NOPs (and a BRA) where the
; negative one calls C2Scene_NegateXVel, which gives the divider its time
; either way.
; Callers (2 JSR sites): C2Scene_ObjBMateFollow ($C2:51C8) and C2Scene_ObjBMateMarkFollow
;   ($C2:559A).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur,
;        C2Tmp_08/$0A), DB=$00 (WRDIVL/B, RDDIVL and low WRAM absolute);
;        C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; A clobbered; Y unchanged; C2Tmp_08/$0A =
;        the X and Y distances
; Calls: C2Scene_NegateXVel, C2Scene_NegateYVel.
!C2Scene_GlideDX = !C2Tmp_08            ; 16-bit .TargetX - .SprX
!C2Scene_GlideDY = !C2Tmp_0A            ; 16-bit .TargetY - .SprY
C2Scene_ObjBMateGlideVel:
    REP #$20
    LDX.b !C2Scene_TaskCur
    SEC
    LDA.w C2Scene_FollowTask.TargetX,X
    SBC.w C2Scene_Task.SprX,X
    STA.b !C2Scene_GlideDX
    BPL .x_abs
    EOR.w #!Eng_Invert16
    INC A
.x_abs:
    XBA
    STA.w WRDIVL
    SEP #$20
    LDA.b #!C2Scene_MateGlideFrames
    STA.w WRDIVB
    REP #$20
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    LDA.w RDDIVL
    STA.w C2Scene_Task.XVelFrac+1,X
    SEC
    LDA.w C2Scene_FollowTask.TargetY,X
    SBC.w C2Scene_Task.SprY,X
    STA.b !C2Scene_GlideDY
    BPL .y_abs
    EOR.w #!Eng_Invert16
    INC A
.y_abs:
    XBA
    STA.w WRDIVL
    SEP #$20
    LDA.b #!C2Scene_MateGlideFrames
    STA.w WRDIVB
    REP #$20
    LDA.b !C2Scene_GlideDX
    BMI .x_neg
    NOP                         ; quirk: the divider's wait (see the header)
    NOP
    BRA .y_quot
.x_neg:
    JSR C2Scene_NegateXVel
.y_quot:
    LDA.w RDDIVL
    STA.w C2Scene_Task.YVelFrac+1,X
    LDA.b !C2Scene_GlideDY
    BPL .done
    JSR C2Scene_NegateYVel
.done:
    SEP #$20
    RTS

; $C2:543C — C2Scene_ObjBMateSpots (16 words, $543C–$545B)
; C2Scene_ObjBMateSpot's X and Y offsets from object B per party facing
; (up, down, left, right) and slot (1, 2): 24 pixels across and 24 along.
C2Scene_ObjBMateSpots:
    dw !C2Scene_LiftUp,!C2Scene_Lift ; up, slot 1: left, behind
    dw !C2Scene_Lift,!C2Scene_Lift   ; up, slot 2: right, behind
    dw !C2Scene_Lift,!C2Scene_LiftUp ; down, slot 1
    dw !C2Scene_LiftUp,!C2Scene_LiftUp ; down, slot 2
    dw !C2Scene_Lift,!C2Scene_Lift   ; left, slot 1
    dw !C2Scene_Lift,!C2Scene_LiftUp ; left, slot 2
    dw !C2Scene_LiftUp,!C2Scene_LiftUp ; right, slot 1
    dw !C2Scene_LiftUp,!C2Scene_Lift ; right, slot 2

; $C2:545C — C2Scene_ObjBMateFaceDir (20 bytes, $545C–$546F)
; .PrevFacing = .Facing; .Facing = Rom_DirToFacing's entry for the
; direction in C2Scene_AimDir (C2Scene_ObjBMateAim's).
; Callers (1 JSR site): C2Scene_ObjBMateFollow ($C2:51F6).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur, C2Scene_AimDir), DB=$00
;        (low WRAM absolute); C2Scene_AimDir = the direction (its high byte
;        is zeroed here)
; Exit:  M=1, X=0; X = the direction, Y = the task; A = the new .Facing
; No calls.
C2Scene_ObjBMateFaceDir:
    STZ.b !C2Scene_AimDir+1
    LDY.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.Facing,Y
    STA.w C2Scene_FollowTask.PrevFacing,Y
    LDX.b !C2Scene_AimDir
    LDA.l !Rom_DirToFacing,X
    STA.w C2Scene_FollowTask.Facing,Y
    RTS

; $C2:5470 — C2Scene_ObjBMateFaceAnim (28 bytes, $5470–$548B)
; When .Facing differs from .PrevFacing: starts entry (.Slot - 1) * 4 +
; .Facing of C2Scene_ObjBMateFaceAnims (C2Scene_SetAnim, by JMP).
; Callers (3 JSR sites): C2Scene_ObjBMateInit ($C2:5103), C2Scene_ObjBMateRise ($C2:51A2) and
;   C2Scene_ObjBMateFollow ($C2:521C).
; Entry: M=1, X=0, B=0 (the 16-bit TAX; its callers' TDC), DP=$0000
;        (C2Scene_TaskCur), DB=$00 (low WRAM absolute); C2Scene_TaskCur =
;        the task
; Exit:  M=1, X=0; Y = the task; unchanged facing: A = .Facing, X
;        unchanged; else as C2Scene_SetAnim (X = the task)
; Calls: C2Scene_SetAnim (JMP).
C2Scene_ObjBMateFaceAnim:
    LDY.b !C2Scene_TaskCur
    LDA.w C2Scene_FollowTask.Facing,Y
    CMP.w C2Scene_FollowTask.PrevFacing,Y
    BEQ .same
    LDA.w C2Scene_FollowTask.Slot,Y
    DEC A
    ASL A                       ; * 4 (C=0 after it: the slot is 1 or 2)
    ASL A
    ADC.w C2Scene_FollowTask.Facing,Y
    TAX
    LDA.l C2Scene_ObjBMateFaceAnims,X
    JMP C2Scene_SetAnim
.same:
    RTS

; $C2:548C — C2Scene_ObjBMateFaceAnims (8 bytes, $548C–$5493)
; The mates' animation per slot (1, then 2) and facing (up, down, left,
; right).
C2Scene_ObjBMateFaceAnims:
    db $2B,$2A,$2C,$6E          ; slot 1
    db $71,$70,$72,$73          ; slot 2

; $C2:5494 — C2Scene_ObjBMateMarkTask (9 bytes, $5494–$549C)
; Task handler of a mate's second sprite (.Slot as the mate's; no
; reference in the bank's code): runs the C2Scene_ObjBMateMarkStates
; handler of .State.
; Callers note: none found.
; Entry: M=1, X=0, X = C2Scene_TaskCur = the task, DP=$0000 (TDC for 0:
;        B = 0 for the TAX), DB=$00 (low WRAM)
; Exit:  as the state's handler
; Calls: a C2Scene_ObjBMateMarkStates handler (JMP (abs,X)).
C2Scene_ObjBMateMarkTask:
    TDC
    LDA.w C2Scene_FollowTask.State,X
    ASL A
    TAX
    JMP (C2Scene_ObjBMateMarkStates,X)

; $C2:549D — C2Scene_ObjBMateMarkStates (5 words, $549D–$54A6)
; C2Scene_ObjBMateMarkTask's handler for each .State 0-4.
C2Scene_ObjBMateMarkStates:
    dw C2Scene_ObjBMateMarkInit ; 0
    dw C2Scene_ObjBMateMarkWait ; 1 (C2Scene_MateStWait)
    dw C2Scene_ObjBMateMarkRise ; 2
    dw C2Scene_ObjBMateMarkFollow ; 3 (C2Scene_MateStFollow)
    dw C2Scene_ObjBMateMarkLand ; 4 (C2Scene_MateMarkStLand)

; $C2:54A7 — C2Scene_ObjBMateMarkInit (103 bytes, $54A7–$550D)
; State 0: .SprAttr C2Scene_ObjAttrPrio3. With C2Scene_ObjBusy in
; C2Scene_ObjBFlags: .State C2Scene_MateStFollow, animation
; C2Scene_AnimMarkBelow, the sprite C2Scene_MateMarkDrop (48) pixels
; below the slot's saved mate position (C2Scene_ObjBMate1X/Y or
; 2X/Y), .SprTile 0, C=0 (no C2Anim_Run). Without it: .State
; C2Scene_MateStWait, the sprite at C2Scene_ObjBX, C2Scene_ObjBY -
; C2Scene_Lift, .SprTile 0, animation C2Scene_AnimMarkAbove, and falls
; into C2Scene_ObjBMateMarkWait.
; Callers note: none direct (C2Scene_ObjBMateMarkStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=0, X=0; X = the task; A clobbered (busy path); else as
;        C2Scene_ObjBMateMarkWait
; Calls: C2Scene_SetAnim.
C2Scene_ObjBMateMarkInit:
    LDX.b !C2Scene_TaskCur
    LDA.b #!C2Scene_ObjAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
    LDA.w !C2Scene_ObjBFlags
    BIT.b #!C2Scene_ObjBusy
    BEQ .idle
    LDA.b #!C2Scene_MateStFollow
    STA.w C2Scene_FollowTask.State,X
    LDA.b #!C2Scene_AnimMarkBelow
    JSR C2Scene_SetAnim
    REP #$20
    LDA.w C2Scene_FollowTask.Slot,X
    CMP.w #!C2Scene_Slot1
    BNE .slot2
    LDA.w !C2Scene_ObjBMate1X
    STA.w C2Scene_Task.SprX,X
    CLC
    LDA.w !C2Scene_ObjBMate1Y
    ADC.w #!C2Scene_MateMarkDrop
    STA.w C2Scene_Task.SprY,X
    BRA .tile
.slot2:
    LDA.w !C2Scene_ObjBMate2X
    STA.w C2Scene_Task.SprX,X
    CLC
    LDA.w !C2Scene_ObjBMate2Y
    ADC.w #!C2Scene_MateMarkDrop
    STA.w C2Scene_Task.SprY,X
.tile:
    STZ.w C2Scene_Task.SprTile,X
    CLC
    RTS
.idle:
    INC.w C2Scene_FollowTask.State,X
    REP #$20
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_Task.SprX,X
    CLC
    LDA.w !C2Scene_ObjBY
    ADC.w #!C2Scene_LiftUp
    STA.w C2Scene_Task.SprY,X
    STZ.w C2Scene_Task.SprTile,X
    LDA.w #!C2Scene_AnimMarkAbove
    JSR C2Scene_SetAnim

; $C2:550E — C2Scene_ObjBMateMarkWait (52 bytes, $550E–$5541)
; State 1: nothing (C=0) until C2Scene_ObjWatch reaches
; C2Scene_ObjWatchStBusyB; then .State 2, .Frames 0, velocity half a
; pixel up and half a pixel sideways (right for slot 1, left for slot
; 2), and falls into C2Scene_ObjBMateMarkRise.
; Callers note: none direct (C2Scene_ObjBMateMarkStates);
;   C2Scene_ObjBMateMarkInit falls in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0, M=1, A = C2Scene_Unk027E (waiting); else as
;        C2Scene_ObjBMateMarkRise
; No calls.
C2Scene_ObjBMateMarkWait:
    LDA.w !C2Scene_Unk027E
    CMP.b #!C2Scene_ObjWatchStBusyB
    BEQ .aboard
    CLC
    RTS
.aboard:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_FollowTask.State,X
    STZ.w C2Scene_Task.Frames,X
    LDA.w C2Scene_FollowTask.Slot,X
    CMP.b #!C2Scene_Slot1
    REP #$20
    BNE .slot2
    TDC                         ; right: whole 0 (+ the half below)
    BRA .set
.slot2:
    LDA.w #!C2Scene_WholeMinus1 ; left: whole -1 (+ the half)
.set:
    STA.w C2Scene_Task.XVel,X
    LDA.w #!C2Scene_HalfPixel
    STA.w C2Scene_Task.XVelFrac,X
    STA.w C2Scene_Task.YVelFrac,X
    LDA.w #!C2Scene_WholeMinus1
    STA.w C2Scene_Task.YVel,X
    SEP #$20

; $C2:5542 — C2Scene_ObjBMateMarkRise (43 bytes, $5542–$556C)
; State 2: moves for C2Scene_RiseFrames frames with C2Anim_Run; then
; .State C2Scene_MateStFollow, .SprY + C2Scene_MateMarkDrop, animation
; C2Scene_AnimMarkBelow, and falls into C2Scene_ObjBMateMarkFollow.
; Callers note: none direct (C2Scene_ObjBMateMarkStates);
;   C2Scene_ObjBMateMarkWait falls in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered (moving); else as
;        C2Scene_ObjBMateMarkFollow
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Anim_Run,
;   C2Scene_SetAnim.
C2Scene_ObjBMateMarkRise:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_RiseFrames
    BCS .risen
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    CLC
    RTS
.risen:
    INC.w C2Scene_FollowTask.State,X
    REP #$20
    CLC
    LDA.w C2Scene_Task.SprY,X
    ADC.w #!C2Scene_MateMarkDrop
    STA.w C2Scene_Task.SprY,X
    LDA.w #!C2Scene_AnimMarkBelow
    JSR C2Scene_SetAnim

; $C2:556D — C2Scene_ObjBMateMarkFollow (100 bytes, $556D–$55D0)
; State 3: with C2Scene_ObjBLanding: .State C2Scene_MateMarkStLand,
; .Frames 0, the target C2Scene_ObjBX, C2Scene_ObjBY - C2Scene_Lift,
; .SprY - C2Scene_MateMarkDrop, the glide velocity to the target
; (C2Scene_ObjBMateGlideVel), animation C2Scene_AnimMarkAbove,
; C2Anim_Run. Otherwise the sprite at the slot's saved mate position
; (C2Scene_ObjBMate1X/Y or 2X/Y) plus C2Scene_Lift in Y, wrapped
; (C2Scene_WrapTaskPos), and C2Anim_Run.
; Callers note: none direct (C2Scene_ObjBMateMarkStates);
;   C2Scene_ObjBMateMarkRise falls in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute and the division registers); C2Scene_TaskCur = the
;        task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered; C2Tmp_08/$0A
;        changed on the landing path
; Calls: C2Scene_ObjBMateGlideVel, C2Scene_SetAnim, C2Scene_WrapTaskPos,
;   C2Anim_Run.
C2Scene_ObjBMateMarkFollow:
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_ObjBFlags
    BIT.b #!C2Scene_ObjBLanding
    BEQ .follow
    LDA.b #!C2Scene_MateMarkStLand
    STA.w C2Scene_FollowTask.State,X
    STZ.w C2Scene_Task.Frames,X
    REP #$20
    LDA.w !C2Scene_ObjBX
    STA.w C2Scene_FollowTask.TargetX,X
    CLC
    LDA.w !C2Scene_ObjBY
    ADC.w #!C2Scene_LiftUp
    STA.w C2Scene_FollowTask.TargetY,X
    CLC
    LDA.w C2Scene_Task.SprY,X
    ADC.w #!C2Scene_MateMarkDropUp
    STA.w C2Scene_Task.SprY,X
    JSR C2Scene_ObjBMateGlideVel
    LDA.b #!C2Scene_AnimMarkAbove
    JSR C2Scene_SetAnim
    JSR C2Anim_Run
    CLC
    RTS
.follow:
    LDA.w C2Scene_FollowTask.Slot,X
    CMP.b #!C2Scene_Slot1
    REP #$20
    BNE .slot2
    LDA.w !C2Scene_ObjBMate1X
    LDY.w !C2Scene_ObjBMate1Y
    BRA .set
.slot2:
    LDA.w !C2Scene_ObjBMate2X
    LDY.w !C2Scene_ObjBMate2Y
.set:
    STA.w C2Scene_Task.SprX,X
    TYA
    CLC
    ADC.w #!C2Scene_Lift
    STA.w C2Scene_Task.SprY,X
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    CLC
    RTS

; $C2:55D1 — C2Scene_ObjBMateMarkLand (52 bytes, $55D1–$5604)
; State 4 (C2Scene_MateMarkStLand): moves until .Frames passes
; C2Scene_LandFrames, $30 frames (.Frames is already 1 when it starts);
; then .State C2Scene_MateStWait, fractions and velocity 0. C2Anim_Run
; either way.
; Callers note: none direct (C2Scene_ObjBMateMarkStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task; A, Y clobbered
; Calls: C2Scene_TaskMove, C2Scene_WrapTaskPos, C2Anim_Run.
C2Scene_ObjBMateMarkLand:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.Frames,X
    CMP.b #!C2Scene_LandFrames
    BCS .landed
    REP #$20
    JSR C2Scene_TaskMove
    JSR C2Scene_WrapTaskPos
    JSR C2Anim_Run
    CLC
    RTS
.landed:
    LDA.b #!C2Scene_MateStWait
    STA.w C2Scene_FollowTask.State,X
    REP #$20
    STZ.w C2Scene_Task.XFrac,X
    STZ.w C2Scene_Task.YFrac,X
    STZ.w C2Scene_Task.XVelFrac,X
    STZ.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    STZ.w C2Scene_Task.YVel,X
    JSR C2Anim_Run
    CLC
    RTS

; $C2:5605 — C2Scene_ObjBMateSavePos (35 bytes, $5605–$5627)
; Copies the task's position to C2Scene_ObjBMate1X/Y (.Slot bit 0 set:
; slot 1) or C2Scene_ObjBMate2X/Y, where the mark tasks read it.
; Callers (4 JSR sites): C2Scene_ObjBMateInit ($C2:5108), C2Scene_ObjBMateRise ($C2:516C),
;   C2Scene_ObjBMateMove ($C2:523B) and C2Scene_ObjBMateLand ($C2:525A).
; Entry: M=0, X=0, X = the task, DP any, DB=$00 (low WRAM absolute);
;        .Slot's high byte (+$25) 0 or not, only bit 0 is tested
; Exit:  M=0, X=0; A = .SprY; X, Y unchanged
; No calls.
C2Scene_ObjBMateSavePos:
    LDA.w C2Scene_FollowTask.Slot,X
    BIT.w #!C2Scene_Slot1
    BEQ .slot2
    LDA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_ObjBMate1X
    LDA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_ObjBMate1Y
    BRA .done
.slot2:
    LDA.w C2Scene_Task.SprX,X
    STA.w !C2Scene_ObjBMate2X
    LDA.w C2Scene_Task.SprY,X
    STA.w !C2Scene_ObjBMate2Y
.done:
    RTS


; ============================================================
; The label task ($C2:5628–$C2:5774)
; ============================================================

; $C2:5628 — C2Scene_LabelTask (15 bytes, $5628–$5636)
; Task handler (no reference in the bank's code, as the object tasks):
; draws string C2Scene_Unk1B58 of C2SceneRom_LabelStrings with the text
; window code into a buffer, uploads it to VRAM and shows it as a sprite
; 48 px above the party's position (every piece of its frame at Y
; offset $D0); while the party is in object A it is placed at
; C2Scene_ObjAY + C2Scene_LabelBelowObjA ($40) instead, so 16 px below
; object A's position, just under its sprite.
; C2Scene_Unk1B58 is a ListA entry's byte 2 (C2Scene_GetListAUnk02) or
; C2Scene_Unk1B58Spot (C2Scene_ObjASpotWatch), so probably the name of
; the place the party is on; not traced further. Runs the
; C2Scene_LabelStates handler of .State.
; Callers note: none found.
; Entry: M any (REP #$20 / SEP #$20 here), X=0, X = C2Scene_TaskCur = the
;        task, DP any, DB=$00 (the task record, absolute)
; Exit:  as the state's handler
; Calls: a C2Scene_LabelStates handler (JMP (abs,X)).
C2Scene_LabelTask:
    REP #$20
    LDA.w C2Scene_ObjTask.State,X
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    SEP #$20
    JMP (C2Scene_LabelStates,X)

; $C2:5637 — C2Scene_LabelStates (4 words, $5637–$563E)
; C2Scene_LabelTask's handler for each .State 0-3.
C2Scene_LabelStates:
    dw C2Scene_LabelInit        ; 0
    dw C2Scene_LabelWait        ; 1 (C2Scene_LabelStWait)
    dw C2Scene_LabelDraw        ; 2
    dw C2Scene_LabelShow        ; 3

; $C2:563F — C2Scene_LabelInit (36 bytes, $563F–$5662)
; State 0: .State 1, .SprAttr C2Scene_ObjAttrPrio3, .SprTile 0, the
; animation and frame templates copied to C2Scene_Unk8600/8604
; (C2Scene_Unk5775), and the animation pointer on C2Scene_Unk8600 (its
; first op shows the frame at C2Scene_Unk8604: C2Anim_OpShowFrame);
; falls into C2Scene_LabelWait.
; Callers note: none direct (C2Scene_LabelStates).
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (low WRAM
;        absolute); C2Scene_TaskCur = the task
; Exit:  as C2Scene_LabelWait
; Calls: C2Scene_Unk5775.
C2Scene_LabelInit:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_ObjTask.State,X
    LDA.b #!C2Scene_ObjAttrPrio3
    STA.w C2Scene_Task.SprAttr,X
    STZ.w C2Scene_Task.SprTile,X
    STZ.w C2Scene_Task.SprTile+1,X
    JSR C2Scene_Unk5775
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w #!C2Scene_Unk8600&$FFFF
    STA.w C2Scene_Task.AnimPtr,X
    SEP #$20
    LDA.b #bank(!C2Scene_Unk8600)
    STA.w C2Scene_Task.AnimBank,X

; $C2:5663 — C2Scene_LabelWait (54 bytes, $5663–$5698)
; State 1: nothing (C=0) while C2Scene_Unk1B58 is 0. Then .State 2,
; .AnimTimer 0, and the text window started (TextWin_Init) on string
; C2Scene_Unk1B58 of C2SceneRom_LabelStrings, mode TextWin_ModeUnk2,
; drawing into C2Scene_HdmaArea (the buffer C2Scene_ClearUnk8621
; clears); falls into C2Scene_LabelDraw.
; Callers note: none direct (C2Scene_LabelStates); C2Scene_LabelInit falls
;   in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (the text window
;        block at TextWin_Dp, absolute); C2Scene_TaskCur = the task
; Exit:  C=0, M=1, A = 0 (waiting); else as C2Scene_LabelDraw
; Calls: TextWin_Init (JSL).
C2Scene_LabelWait:
    LDA.w !C2Scene_Unk1B58
    BNE .start
    CLC
    RTS
.start:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_ObjTask.State,X
    STZ.w C2Scene_Task.AnimTimer,X
    LDA.w !C2Scene_Unk1B58
    STA.w !TextWin_Dp+!TextWin_StrIndex
    REP #$10
    LDX.w #!C2SceneRom_LabelStrings&$FFFF
    STX.w !TextWin_Dp+!TextWin_StrTable
    LDA.b #bank(!C2SceneRom_LabelStrings)
    STA.w !TextWin_Dp+!TextWin_StrTable+2
    LDA.b #!TextWin_ModeUnk2
    STA.w !TextWin_Dp+!TextWin_Mode
    LDX.w #!C2Scene_HdmaArea&$FFFF
    STX.w !TextWin_Dp+!TextWin_GfxBuf
    LDA.b #bank(!C2Scene_HdmaArea)
    STA.w !TextWin_Dp+!TextWin_GfxBuf+2
    JSL TextWin_Init

; $C2:5699 — C2Scene_LabelDraw (96 bytes, $5699–$56F8)
; State 2: one TextWin_Step of one character (TextWin_StepCount 1) per
; frame while TextWin_Status comes back TextWin_StatusStepDone (C=0).
; When the string is done: .State 3 and two VRAM uploads queued
; (C2Scene_VramQ, locked while written): C2Scene_LabelDmaBytes from the
; buffer to VRAM C2Scene_LabelVramTop and as many from
; C2Scene_LabelHalfOfs further on to C2Scene_LabelVramBottom, bank $7E,
; VMAIN VMAIN_IncAfterHigh; then it falls into C2Scene_LabelShow. There
; is no check that the queue has room.
; Callers note: none direct (C2Scene_LabelStates); C2Scene_LabelWait falls
;   in.
; Entry: M=1, X=0, DP=$0000 (C2Scene_TaskCur), DB=$00 (the text window
;        block and the queue, absolute); C2Scene_TaskCur = the task
; Exit:  C=0, M=1, X=0 (drawing: TextWin_Step restores P); A, X, Y
;        clobbered; else as C2Scene_LabelShow
; Calls: TextWin_Step (JSL).
C2Scene_LabelDraw:
    LDA.b #1
    STA.w !TextWin_Dp+!TextWin_StepCount
    JSL TextWin_Step
    LDA.w !TextWin_Dp+!TextWin_Status
    CMP.b #!TextWin_StatusStepDone
    BNE .drawn
    CLC
    RTS
.drawn:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_ObjTask.State,X
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
    LDA.w #!C2Scene_HdmaArea&$FFFF
    STA.w C2Scene_VramQ.Src,X
    LDA.w #(!C2Scene_HdmaArea+!C2Scene_LabelHalfOfs)&$FFFF
    STA.w C2Scene_VramQ[1].Src,X
    LDA.w #!C2Scene_LabelVramTop
    STA.w C2Scene_VramQ.Dest,X
    LDA.w #!C2Scene_LabelVramBottom
    STA.w C2Scene_VramQ[1].Dest,X
    LDA.w #!C2Scene_LabelDmaBytes
    STA.w C2Scene_VramQ.Size,X
    STA.w C2Scene_VramQ[1].Size,X
    SEP #$20
    TXA
    CLC
    ADC.b #2*!C2Scene_VramQEntrySize
    STA.w !C2Scene_VramQEnd
    STZ.w !C2Scene_VramQLock
    REP #$10

; $C2:56F9 — C2Scene_LabelShow (124 bytes, $56F9–$5774)
; State 3: with C2Scene_Unk1B58 0, .State C2Scene_LabelStWait and the
; buffer cleared (C2Scene_ClearUnk8621), and the sprite still drawn this
; frame; with C2Scene_Unk1B59 set (probably "the label changed"),
; .State C2Scene_LabelStWait, C2Scene_Unk1B59 = 0, the buffer cleared,
; C=0 at once. Otherwise, unless C2Scene_ObjAInMode8 is set (then
; nothing): the sprite at C2Scene_StartX/Y (the party), or C2Scene_ObjAX,
; C2Scene_ObjAY + C2Scene_LabelBelowObjA while C2Scene_ObjWatch is in
; C2Scene_ObjWatchStBusyA; the frame's first byte (C2Scene_Unk8604) =
; C2Scene_LabelPieces; .SprX - TextWin_PenX / 2 (the drawn width's half:
; centred); C2Anim_Run. C=0.
; Callers note: none direct (C2Scene_LabelStates); C2Scene_LabelDraw falls
;   in.
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur), DB=$00
;        (low WRAM and the text window block, absolute); C2Scene_TaskCur =
;        the task
; Exit:  C=0; M=1, X=0; A, X, Y clobbered
; Calls: C2Scene_ClearUnk8621, C2Anim_Run.
C2Scene_LabelShow:
    SEP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_Unk1B58
    BNE .label
    LDA.b #!C2Scene_LabelStWait
    STA.w C2Scene_ObjTask.State,X
    JSR C2Scene_ClearUnk8621
    BRA .show
.label:
    LDA.w !C2Scene_Unk1B59
    BEQ .show
    LDA.b #!C2Scene_LabelStWait
    STA.w C2Scene_ObjTask.State,X
    STZ.w !C2Scene_Unk1B59
    JSR C2Scene_ClearUnk8621
    CLC
    RTS
.show:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BNE .done
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !C2Scene_Unk027E
    AND.w #!Eng_LowByteMask
    CMP.w #!C2Scene_ObjWatchStBusyA
    BEQ .in_obj_a
    LDA.w !C2Scene_StartX
    STA.w C2Scene_Task.SprX,X
    LDA.w !C2Scene_StartY
    STA.w C2Scene_Task.SprY,X
    BRA .place
.in_obj_a:
    LDA.w !C2Scene_ObjAX
    STA.w C2Scene_Task.SprX,X
    LDA.w !C2Scene_ObjAY
    CLC
    ADC.w #!C2Scene_LabelBelowObjA
    STA.w C2Scene_Task.SprY,X
.place:
    SEP #$30
    LDA.b #!C2Scene_LabelPieces
    STA.l !C2Scene_Unk8604
    REP #$30
    LDA.w !TextWin_Dp+!TextWin_PenX
    AND.w #!Eng_LowByteMask
    LSR A
    EOR.w #!Eng_Invert16
    INC A
    LDX.b !C2Scene_TaskCur
    CLC
    ADC.w C2Scene_Task.SprX,X
    STA.w C2Scene_Task.SprX,X
    JSR C2Anim_Run
.done:
    CLC
    RTS

; ============================================================
; Scene WRAM table setup ($C2:5775–$C2:57DE)
; ============================================================

org $C25775
; $C2:5775 — C2Scene_Unk5775 (35 bytes, $5775–$5797)
; Copies C2Scene_Unk8600Init (4 bytes) to C2Scene_Unk8600 and
; C2Scene_Unk8604Init (C2Scene_Unk8604Size bytes, MVN) to
; C2Scene_Unk8604: an animation script for C2Scene_LabelTask's sprite
; (C2Anim_OpShowFrame on the frame at C2Scene_Unk8604) and that frame.
; Callers (2 JSR sites): C2Scene_ReloadScene ($C2:2C93) and C2Scene_LabelInit ($C2:564F).
; Entry: M any (REP #$20 here), X=0 (16-bit MVN counts), DP any, DB any
;        (saved around the MVN, which leaves it at $7E)
; Exit:  M=1, X=0; DB unchanged; A = $FFFF; X = the end of the source,
;        Y = the end of the copy
; No calls.
C2Scene_Unk5775:
    REP #$20
    LDA.l C2Scene_Unk8600Init
    STA.l !C2Scene_Unk8600
    LDA.l C2Scene_Unk8600Init+2
    STA.l !C2Scene_Unk8600+2
    PHB
    LDX.w #C2Scene_Unk8604Init
    LDY.w #!C2Scene_Unk8604&$FFFF
    LDA.w #!C2Scene_Unk8604Size-1
    MVN bank(!C2Scene_Unk8604),bank(C2Scene_Unk8604Init) ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    RTS

; $C2:5798 — C2Scene_ClearUnk8621 (24 bytes, $5798–$57AF)
; Zeroes the first C2Scene_Unk8621Bytes bytes of C2Scene_HdmaArea
; ($7E:8621-$8A20, up to C2Scene_HdmaValues): a zero word at the start,
; then an overlapping MVN.
; Callers (3 JSR sites): C2Scene_LabelShow ($C2:5707, $C2:5719) and unmatched ($C2:6965).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (TDC for 0), DB any
;        (saved around the MVN)
; Exit:  M=1, X=0; DB unchanged; A = $FFFF; X = $8A20, Y = $8A21
; No calls.
C2Scene_ClearUnk8621:
    REP #$20
    PHB
    TDC
    STA.l !C2Scene_HdmaArea
    LDX.w #!C2Scene_HdmaArea&$FFFF
    LDY.w #(!C2Scene_HdmaArea+1)&$FFFF
    LDA.w #!C2Scene_Unk8621Bytes-2
    MVN !Bank7E,!Bank7E         ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    RTS

; $C2:57B0 — C2Scene_Unk57B0 (18 bytes, $57B0–$57C1)
; Data with no reference found in the bank (no pointer to any of its
; bytes): 0, 1, 2, 3, 3, 4, 5, 6, 6, two zeros, then $F4 down to $D0 in
; steps of 6. Use unknown.
C2Scene_Unk57B0:
    db $00,$01,$02,$03,$03,$04,$05,$06,$06,$00
    db $00,$F4,$EE,$E8,$E2,$DC,$D6,$D0

; $C2:57C2 — C2Scene_Unk8600Init (4 bytes, $57C2–$57C5)
; C2Scene_Unk5775's source for C2Scene_Unk8600.
C2Scene_Unk8600Init:
    db $04,$04,$86,$00

; $C2:57C6 — C2Scene_Unk8604Init (25 bytes, $57C6–$57DE)
; C2Scene_Unk5775's source for C2Scene_Unk8604: a 0 word, $D0, then
; five groups $E0+2n,$01,$10+16n,$D0 (n = 0-4), and $EA,$01.
C2Scene_Unk8604Init:
    db $00,$00,$D0
    db $E0,$01,$10,$D0
    db $E2,$01,$20,$D0
    db $E4,$01,$30,$D0
    db $E6,$01,$40,$D0
    db $E8,$01,$50,$D0
    db $EA,$01

; ============================================================
; Text window entries ($C2:57DF–$C2:58B1)
; ============================================================
; A text box drawn into a buffer one step at a time, called from other
; banks through BankC2_Entry0003 (TextWin_Init) and BankC2_Entry0009
; (TextWin_Step). Both work on the block at $0200 (DP=$0200), which the
; caller fills first: the field ($C0:20F4-$C0:2121) sets the string
; number, the string table, the output buffer ($7E:F000) and the mode,
; and before each step the character count. The text decoder itself
; is TextWin_StateTable's handlers, TextWin_State0-3 (below).

org $C257DF
; $C2:57DF — TextWin_Init (68 bytes, $57DF–$5822)
; Starts string TextWin_StrIndex: TextWin_TextPtr = the 16-bit entry
; TextWin_StrIndex of the table at TextWin_StrTable, in the table's bank;
; state 0 (TextWin_State), status TextWin_StatusStart, TextWin_Unk17 = 0,
; TextWin_Unk3D = $00:0200 (use not traced), and the pen X
; (TextWin_PenX) at TextWin_PenXLeft, or 0 when TextWin_Mode is
; TextWin_ModeUnk2 or has bit 7 set.
; Callers (4 sites: 2 JSL, 2 JMP): BankC2_Entry0003 (JMP $C2:0003), BankC2_Entry0006 (JMP $C2:0006),
;   C2Scene_LabelWait (JSL $C2:5695) and unmatched (JSL $C2:69BB).
; Callers note: JMP from BankC2_Entry0003 ($C2:0003) and BankC2_Entry0006
;   ($C2:0006), the cross-bank JSL vectors; JSL from C2Scene_LabelWait
;   ($C2:5695) and unmatched code at $C2:69BB.
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
; Callers (4 sites: 2 JSL, 2 JMP): BankC2_Entry0009 (JMP $C2:0009), BankC2_Entry000C (JMP $C2:000C),
;   C2Scene_LabelDraw (JSL $C2:569E) and unmatched (JSL $C2:69C4).
; Callers note: JMP from BankC2_Entry0009 ($C2:0009) and BankC2_Entry000C
;   ($C2:000C), the cross-bank JSL vectors; JSL from C2Scene_LabelDraw
;   ($C2:569E) and unmatched code at $C2:69C4.
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
; - $A0-$FF: a glyph, drawn by TextWin_DrawGlyph. The
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
; Callers note: also TextWin_StateTable entry 0, through TextWin_Step.
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
; Text window glyph drawing and decimal digits ($C2:5DC4–$C2:6262)
; ============================================================
; The text decoder's back end: TextWin_DrawGlyph puts one glyph into the
; output buffer and moves the pen; TextWin_Dec8/16/24 turn the number
; codes' values into decimal digits. Data: the character name pointers,
; the buffer tile offsets, the glyph widths and the "Nadia" string.

; $C2:5DC4 — TextWin_DrawGlyph (114 bytes, $5DC4–$5E35)
; Draws glyph TextWin_Glyph at TextWin_PenX into TextWin_GfxBuf and
; moves the pen on by the glyph's width:
; - TextWin_FontPtr = TextWinRom_Font + glyph * 24, TextWin_FontNibPtr =
;   TextWinRom_FontRight + glyph / 2 * 24 (16-bit glyph, bank $FF);
;   TextWin_OutPtr = TextWin_GfxBuf + TextWin_GlyphTopSkip;
;   TextWin_PenShift = pen AND 7, TextWin_PenTile2 = the pen's tile * 2;
;   TextWin_GlyphLow = the glyph's low byte;
; - TextWin_Blit2bpp when TextWin_Mode AND TextWin_ModeBlitMask is 0,
;   else TextWin_Blit4bpp;
; - TextWin_PenX + entry (glyph low byte - TextWin_FirstGlyph) of
;   TextWin_GlyphWidths; TextWin_Unk17 + 1.
; Quirk, kept: the width index is the low byte only, so a glyph $01xx or
; $02xx (TextWin_Wide1/2) with a low byte under $A0 reads past the
; 96-byte table (into TextWin_StrNadia and the code after it).
; Callers (4 JSR sites): TextWin_State0_Draw ($C2:58C4), TextWin_State1 ($C2:5C12), TextWin_State2
;   ($C2:5C4B) and TextWin_State3 ($C2:5C94).
; Entry: M any (REP #$20 here), X=0, DP=$0200 (TextWin_Dp), DB any (the
;        blitters set their own)
; Exit:  M=1, X=0; A = $0000 (B = 0); X = the width index; Y as the
;        blitter leaves it; TextWin_PenX and TextWin_Unk17 moved on;
;        dp $60-$64, $68, $6A-$6F and $73-$7B (the work bytes) changed
; Calls: TextWin_Blit2bpp or TextWin_Blit4bpp.
TextWin_DrawGlyph:
    REP #$20
    LDA.b !TextWin_Glyph
    ASL A
    ASL A
    ASL A
    STA.b !TextWin_GlyphX8
    ASL A
    ADC.b !TextWin_GlyphX8      ; glyph * 24 (C = 0 from the ASL of a small code)
    CLC
    ADC.w #!TextWinRom_Font&$FFFF
    STA.b !TextWin_FontPtr
    LDA.b !TextWin_Glyph
    LSR A
    ASL A
    ASL A
    ASL A
    STA.b !TextWin_GlyphX8
    ASL A
    ADC.b !TextWin_GlyphX8
    CLC
    ADC.w #!TextWinRom_FontRight&$FFFF
    STA.b !TextWin_FontNibPtr
    LDA.b !TextWin_PenX
    AND.w #!TextWin_PenShiftMask
    STA.b !TextWin_PenShift
    LDA.b !TextWin_GfxBuf
    CLC
    ADC.w #!TextWin_GlyphTopSkip
    STA.b !TextWin_OutPtr
    SEP #$20
    LDA.b !TextWin_GfxBuf+2
    STA.b !TextWin_OutPtr+2
    LDA.b #bank(!TextWinRom_Font)
    STA.b !TextWin_FontPtr+2
    STA.b !TextWin_FontNibPtr+2
    LDA.b !TextWin_PenX
    AND.b #!TextWin_PenTileMask
    LSR A
    LSR A
    STA.b !TextWin_PenTile2
    STZ.b !TextWin_PenTile2+1
    LDA.b !TextWin_Glyph
    STA.b !TextWin_GlyphLow
    LDA.b !TextWin_Mode
    AND.b #!TextWin_ModeBlitMask
    BNE .blit4bpp
    JSR TextWin_Blit2bpp
    BRA .advance
.blit4bpp:
    JSR TextWin_Blit4bpp
.advance:
    LDA.b #0
    XBA                         ; B = 0 for the TAX
    SEC
    LDA.b !TextWin_Glyph
    SBC.b #!TextWin_FirstGlyph
    TAX
    CLC
    LDA.l TextWin_GlyphWidths,X
    ADC.b !TextWin_PenX
    STA.b !TextWin_PenX
    INC.b !TextWin_Unk17
    LDA.b #0
    XBA
    RTS

; $C2:5E36 — TextWin_Blit2bpp (83 bytes, $5E36–$5E88)
; Draws the glyph's 24 bytes with TextWin_Blit2bppRow, one per
; TextWin_GlyphRow: the first 8 (TextWin_GlyphTopPairs pairs) at
; TextWin_OutPtr on, then TextWin_OutPtr + TextWin_NextRow2bpp and the
; other 16, TextWin_OutPtr + 1 after each byte. So the glyph starts 8
; bytes into its tile row and goes on $100 bytes further: the buffer is
; probably 2bpp tiles, rows of 16 tiles $100 bytes apart (see
; TextWin_TileOfs2bpp).
; Callers (1 JSR site): TextWin_DrawGlyph ($C2:5E16).
; Entry: M=1, X=0, DP=$0200, DB any (set to $C2 for the offset table and
;        restored); TextWin_DrawGlyph's work bytes set
; Exit:  M=1, X=0; DB unchanged; A, X, Y clobbered; TextWin_RowCount 0,
;        TextWin_GlyphRow 24, TextWin_OutPtr moved on
; Calls: TextWin_Blit2bppRow.
TextWin_Blit2bpp:
    PHB
    LDA.b #bank(TextWin_TileOfs2bpp)
    PHA
    PLB
    LDA.b #!TextWin_GlyphTopPairs
    STA.b !TextWin_RowCount
    STZ.b !TextWin_GlyphRow
    STZ.b !TextWin_GlyphRow+1
.top:
    JSR TextWin_Blit2bppRow
    REP #$20
    INC.b !TextWin_GlyphRow
    INC.b !TextWin_OutPtr
    SEP #$20
    JSR TextWin_Blit2bppRow
    REP #$20
    INC.b !TextWin_GlyphRow
    INC.b !TextWin_OutPtr
    SEP #$20
    DEC.b !TextWin_RowCount
    BNE .top
    REP #$20
    LDA.b !TextWin_OutPtr
    CLC
    ADC.w #!TextWin_NextRow2bpp
    STA.b !TextWin_OutPtr
    SEP #$20
    LDA.b #!TextWin_GlyphLowPairs
    STA.b !TextWin_RowCount
.low:
    JSR TextWin_Blit2bppRow
    REP #$20
    INC.b !TextWin_GlyphRow
    INC.b !TextWin_OutPtr
    SEP #$20
    JSR TextWin_Blit2bppRow
    REP #$20
    INC.b !TextWin_GlyphRow
    INC.b !TextWin_OutPtr
    SEP #$20
    DEC.b !TextWin_RowCount
    BNE .low
    PLB
    RTS

; $C2:5E89 — TextWin_Blit2bppRow (38 bytes, $5E89–$5EAE, with the table
; TextWin_Blit2bppShifts and the shift entries TextWin_Blit2bppShr0
; $C2:5EBF, TextWin_Blit2bppShr4, TextWin_Blit2bppShr3,
; TextWin_Blit2bppShr2, TextWin_Blit2bppShr1 $C2:5ECF-$5ED2,
; TextWin_Blit2bppShl3, TextWin_Blit2bppShl2 and TextWin_Blit2bppShl1
; $C2:5EE5/$5EE8/$5EEB, to $5F06)
; One glyph byte: A = byte TextWin_GlyphRow of TextWin_FontPtr in the
; high byte and of TextWin_FontNibPtr in the low (its high nibble for an
; even TextWin_GlyphLow, its low nibble moved up for an odd one): 12
; pixels in bits 15-4. Then, by TextWin_PenShift through
; TextWin_Blit2bppShifts:
; - 0: high byte stored in the pen's tile, low byte in the next;
; - 1-4: shifted right that many times; the high byte ORed into the
;   pen's tile, the low stored in the next;
; - 5-7: shifted left 3/2/1 times into TextWin_GlyphSpill (a right shift
;   by 5-7 across three tiles): the spill ORed into the pen's tile, the
;   high byte stored in the next, the low byte in the one after.
; Each tile's byte is at TextWin_OutPtr + its TextWin_TileOfs2bpp word
; (entry TextWin_PenTile2 / 2, + 1, + 2).
; Callers (4 JSR sites): TextWin_Blit2bpp ($C2:5E43, $C2:5E4E, $C2:5E6D, $C2:5E78).
; Entry: M=1, X=0, DP=$0200, DB=$C2 (the offset table; TextWin_Blit2bpp
;        sets it)
; Exit:  M=1, X=0; X = TextWin_PenTile2; Y = the last offset; A = the
;        last byte stored; TextWin_GlyphSpill set
; No calls.
TextWin_Blit2bppRow:
    LDY.b !TextWin_GlyphRow
    LDA.b [!TextWin_FontPtr],Y
    XBA
    LDA.b !TextWin_GlyphLow
    LSR A
    BCC .even
    LDA.b [!TextWin_FontNibPtr],Y
    ASL A
    ASL A
    ASL A
    ASL A
    BRA .row
.even:
    LDA.b [!TextWin_FontNibPtr],Y
    AND.b #!TextWin_RightNibble
.row:
    REP #$20
    TAY
    STZ.b !TextWin_GlyphSpill
    LDA.b !TextWin_PenShift
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    TYA
    JMP (TextWin_Blit2bppShifts,X)

; $C2:5EAF — TextWin_Blit2bppShifts (8 words, $5EAF–$5EBE)
; TextWin_Blit2bppRow's entry for each pen shift 0-7.
TextWin_Blit2bppShifts:
    dw TextWin_Blit2bppShr0     ; 0
    dw TextWin_Blit2bppShr1     ; 1
    dw TextWin_Blit2bppShr2     ; 2
    dw TextWin_Blit2bppShr3     ; 3
    dw TextWin_Blit2bppShr4     ; 4
    dw TextWin_Blit2bppShl3     ; 5
    dw TextWin_Blit2bppShl2     ; 6
    dw TextWin_Blit2bppShl1     ; 7

TextWin_Blit2bppShr0:           ; header: see TextWin_Blit2bppRow
    SEP #$20
    LDX.b !TextWin_PenTile2
    LDY.w TextWin_TileOfs2bpp+2,X
    STA.b [!TextWin_OutPtr],Y
    LDY.w TextWin_TileOfs2bpp,X
    XBA
    STA.b [!TextWin_OutPtr],Y
    RTS

TextWin_Blit2bppShr4:           ; header: see TextWin_Blit2bppRow
    LSR A
TextWin_Blit2bppShr3:           ; header: see TextWin_Blit2bppRow
    LSR A
TextWin_Blit2bppShr2:           ; header: see TextWin_Blit2bppRow
    LSR A
TextWin_Blit2bppShr1:           ; header: see TextWin_Blit2bppRow
    LSR A
    SEP #$20
    LDX.b !TextWin_PenTile2
    LDY.w TextWin_TileOfs2bpp+2,X
    STA.b [!TextWin_OutPtr],Y
    LDY.w TextWin_TileOfs2bpp,X
    XBA
    ORA.b [!TextWin_OutPtr],Y
    STA.b [!TextWin_OutPtr],Y
    RTS

TextWin_Blit2bppShl3:           ; header: see TextWin_Blit2bppRow
    ASL A
    ROL.b !TextWin_GlyphSpill
TextWin_Blit2bppShl2:           ; header: see TextWin_Blit2bppRow
    ASL A
    ROL.b !TextWin_GlyphSpill
TextWin_Blit2bppShl1:           ; header: see TextWin_Blit2bppRow
    ASL A
    ROL.b !TextWin_GlyphSpill
    SEP #$20
    LDX.b !TextWin_PenTile2
    LDY.w TextWin_TileOfs2bpp+4,X
    STA.b [!TextWin_OutPtr],Y
    LDY.w TextWin_TileOfs2bpp+2,X
    XBA
    STA.b [!TextWin_OutPtr],Y
    LDY.w TextWin_TileOfs2bpp,X
    LDA.b !TextWin_GlyphSpill
    ORA.b [!TextWin_OutPtr],Y
    STA.b [!TextWin_OutPtr],Y
    RTS

; $C2:5F07 — TextWin_Blit4bpp (83 bytes, $5F07–$5F59)
; As TextWin_Blit2bpp with TextWin_Blit4bppRow and
; TextWin_NextRow4bpp: the second part goes $200 bytes on, and the tiles
; are TextWin_TileOfs4bpp's, $20 bytes apart (probably 4bpp tiles, the
; glyph in their first two planes).
; Callers (1 JSR site): TextWin_DrawGlyph ($C2:5E1B).
; Entry: M=1, X=0, DP=$0200, DB any (set to $C2 for the offset table and
;        restored); TextWin_DrawGlyph's work bytes set
; Exit:  M=1, X=0; DB unchanged; A, X, Y clobbered; TextWin_RowCount 0,
;        TextWin_GlyphRow 24, TextWin_OutPtr moved on
; Calls: TextWin_Blit4bppRow.
TextWin_Blit4bpp:
    PHB
    LDA.b #bank(TextWin_TileOfs4bpp)
    PHA
    PLB
    LDA.b #!TextWin_GlyphTopPairs
    STA.b !TextWin_RowCount
    STZ.b !TextWin_GlyphRow
    STZ.b !TextWin_GlyphRow+1
.top:
    JSR TextWin_Blit4bppRow
    REP #$20
    INC.b !TextWin_GlyphRow
    INC.b !TextWin_OutPtr
    SEP #$20
    JSR TextWin_Blit4bppRow
    REP #$20
    INC.b !TextWin_GlyphRow
    INC.b !TextWin_OutPtr
    SEP #$20
    DEC.b !TextWin_RowCount
    BNE .top
    REP #$20
    CLC
    LDA.b !TextWin_OutPtr
    ADC.w #!TextWin_NextRow4bpp
    STA.b !TextWin_OutPtr
    SEP #$20
    LDA.b #!TextWin_GlyphLowPairs
    STA.b !TextWin_RowCount
.low:
    JSR TextWin_Blit4bppRow
    REP #$20
    INC.b !TextWin_GlyphRow
    INC.b !TextWin_OutPtr
    SEP #$20
    JSR TextWin_Blit4bppRow
    REP #$20
    INC.b !TextWin_GlyphRow
    INC.b !TextWin_OutPtr
    SEP #$20
    DEC.b !TextWin_RowCount
    BNE .low
    PLB
    RTS

; $C2:5F5A — TextWin_Blit4bppRow (38 bytes, $5F5A–$5F7F, with the table
; TextWin_Blit4bppShifts and the shift entries TextWin_Blit4bppShr0
; $C2:5F90, TextWin_Blit4bppShr4, TextWin_Blit4bppShr3,
; TextWin_Blit4bppShr2, TextWin_Blit4bppShr1 $C2:5FA0-$5FA3,
; TextWin_Blit4bppShl3, TextWin_Blit4bppShl2 and TextWin_Blit4bppShl1
; $C2:5FB6/$5FB9/$5FBC, to $5FD7)
; TextWin_Blit2bppRow with the tile offsets of TextWin_TileOfs4bpp.
; Callers (4 JSR sites): TextWin_Blit4bpp ($C2:5F14, $C2:5F1F, $C2:5F3E, $C2:5F49).
; Entry: M=1, X=0, DP=$0200, DB=$C2 (the offset table; TextWin_Blit4bpp
;        sets it)
; Exit:  M=1, X=0; X = TextWin_PenTile2; Y = the last offset; A = the
;        last byte stored; TextWin_GlyphSpill set
; No calls.
TextWin_Blit4bppRow:
    LDY.b !TextWin_GlyphRow
    LDA.b [!TextWin_FontPtr],Y
    XBA
    LDA.b !TextWin_GlyphLow
    LSR A
    BCC .even
    LDA.b [!TextWin_FontNibPtr],Y
    ASL A
    ASL A
    ASL A
    ASL A
    BRA .row
.even:
    LDA.b [!TextWin_FontNibPtr],Y
    AND.b #!TextWin_RightNibble
.row:
    REP #$20
    TAY
    STZ.b !TextWin_GlyphSpill
    LDA.b !TextWin_PenShift
    AND.w #!Eng_LowByteMask
    ASL A
    TAX
    TYA
    JMP (TextWin_Blit4bppShifts,X)

; $C2:5F80 — TextWin_Blit4bppShifts (8 words, $5F80–$5F8F)
; TextWin_Blit4bppRow's entry for each pen shift 0-7.
TextWin_Blit4bppShifts:
    dw TextWin_Blit4bppShr0     ; 0
    dw TextWin_Blit4bppShr1     ; 1
    dw TextWin_Blit4bppShr2     ; 2
    dw TextWin_Blit4bppShr3     ; 3
    dw TextWin_Blit4bppShr4     ; 4
    dw TextWin_Blit4bppShl3     ; 5
    dw TextWin_Blit4bppShl2     ; 6
    dw TextWin_Blit4bppShl1     ; 7

TextWin_Blit4bppShr0:           ; header: see TextWin_Blit4bppRow
    SEP #$20
    LDX.b !TextWin_PenTile2
    LDY.w TextWin_TileOfs4bpp+2,X
    STA.b [!TextWin_OutPtr],Y
    LDY.w TextWin_TileOfs4bpp,X
    XBA
    STA.b [!TextWin_OutPtr],Y
    RTS

TextWin_Blit4bppShr4:           ; header: see TextWin_Blit4bppRow
    LSR A
TextWin_Blit4bppShr3:           ; header: see TextWin_Blit4bppRow
    LSR A
TextWin_Blit4bppShr2:           ; header: see TextWin_Blit4bppRow
    LSR A
TextWin_Blit4bppShr1:           ; header: see TextWin_Blit4bppRow
    LSR A
    SEP #$20
    LDX.b !TextWin_PenTile2
    LDY.w TextWin_TileOfs4bpp+2,X
    STA.b [!TextWin_OutPtr],Y
    LDY.w TextWin_TileOfs4bpp,X
    XBA
    ORA.b [!TextWin_OutPtr],Y
    STA.b [!TextWin_OutPtr],Y
    RTS

TextWin_Blit4bppShl3:           ; header: see TextWin_Blit4bppRow
    ASL A
    ROL.b !TextWin_GlyphSpill
TextWin_Blit4bppShl2:           ; header: see TextWin_Blit4bppRow
    ASL A
    ROL.b !TextWin_GlyphSpill
TextWin_Blit4bppShl1:           ; header: see TextWin_Blit4bppRow
    ASL A
    ROL.b !TextWin_GlyphSpill
    SEP #$20
    LDX.b !TextWin_PenTile2
    LDY.w TextWin_TileOfs4bpp+4,X
    STA.b [!TextWin_OutPtr],Y
    LDY.w TextWin_TileOfs4bpp+2,X
    XBA
    STA.b [!TextWin_OutPtr],Y
    LDY.w TextWin_TileOfs4bpp,X
    LDA.b !TextWin_GlyphSpill
    ORA.b [!TextWin_OutPtr],Y
    STA.b [!TextWin_OutPtr],Y
    RTS

; $C2:5FD8 — TextWin_CharNamePtrs (7 words, $5FD8–$5FE5)
; The 16-bit addresses (bank $7E) of the first 7 names at
; TextWin_CharNames, TextWin_CharNameSize bytes apart (codes $11 and
; $13-$19).
TextWin_CharNamePtrs:
    dw (!TextWin_CharNames+(0*!TextWin_CharNameSize))&$FFFF
    dw (!TextWin_CharNames+(1*!TextWin_CharNameSize))&$FFFF
    dw (!TextWin_CharNames+(2*!TextWin_CharNameSize))&$FFFF
    dw (!TextWin_CharNames+(3*!TextWin_CharNameSize))&$FFFF
    dw (!TextWin_CharNames+(4*!TextWin_CharNameSize))&$FFFF
    dw (!TextWin_CharNames+(5*!TextWin_CharNameSize))&$FFFF
    dw (!TextWin_CharNames+(6*!TextWin_CharNameSize))&$FFFF

; $C2:5FE6 — TextWin_TileOfs2bpp (64 words, $5FE6–$6065)
; TextWin_Blit2bppRow: the TextWin_GfxBuf offset of each 8-pixel tile
; column of the pen (index pen / 8; the glyph spans up to three, + 1 and
; + 2). Columns 0-15 are $10 bytes apart from $000, 16-31 from $200; 32-47
; ($100 on) and 48-63 ($300 on) are only reached past column 31 (the
; tile row below the first two blocks).
TextWin_TileOfs2bpp:
    dw $0000,$0010,$0020,$0030,$0040,$0050,$0060,$0070
    dw $0080,$0090,$00A0,$00B0,$00C0,$00D0,$00E0,$00F0
    dw $0200,$0210,$0220,$0230,$0240,$0250,$0260,$0270
    dw $0280,$0290,$02A0,$02B0,$02C0,$02D0,$02E0,$02F0
    dw $0100,$0110,$0120,$0130,$0140,$0150,$0160,$0170
    dw $0180,$0190,$01A0,$01B0,$01C0,$01D0,$01E0,$01F0
    dw $0300,$0310,$0320,$0330,$0340,$0350,$0360,$0370
    dw $0380,$0390,$03A0,$03B0,$03C0,$03D0,$03E0,$03F0

; $C2:6066 — TextWin_TileOfs4bpp (64 words, $6066–$60E5)
; As TextWin_TileOfs2bpp for TextWin_Blit4bppRow, $20 bytes per tile:
; columns 0-15 from $000, 16-31 from $400, then $200 and $600.
TextWin_TileOfs4bpp:
    dw $0000,$0020,$0040,$0060,$0080,$00A0,$00C0,$00E0
    dw $0100,$0120,$0140,$0160,$0180,$01A0,$01C0,$01E0
    dw $0400,$0420,$0440,$0460,$0480,$04A0,$04C0,$04E0
    dw $0500,$0520,$0540,$0560,$0580,$05A0,$05C0,$05E0
    dw $0200,$0220,$0240,$0260,$0280,$02A0,$02C0,$02E0
    dw $0300,$0320,$0340,$0360,$0380,$03A0,$03C0,$03E0
    dw $0600,$0620,$0640,$0660,$0680,$06A0,$06C0,$06E0
    dw $0700,$0720,$0740,$0760,$0780,$07A0,$07C0,$07E0

; $C2:60E6 — TextWin_GlyphWidths (96 bytes, $60E6–$6145)
; The pen advance in pixels of each glyph $A0-$FF (TextWin_DrawGlyph;
; index glyph - TextWin_FirstGlyph). $A0-$B9 are the capitals and
; $BA-$D3 the small letters ("A" $A0, "a" $BA; TextWin_HexGlyphs,
; TextWin_StrNadia; probably), $D4-$DD the digits; glyphs $F2 and
; $F4-$FE have width 0.
TextWin_GlyphWidths:
    db $07,$07,$07,$07,$06,$06,$07,$07,$05,$07,$08,$06,$09,$08,$07,$07 ; $A0
    db $07,$07,$06,$07,$07,$07,$0B,$07,$07,$07,$07,$07,$06,$07,$07,$06 ; $B0
    db $07,$07,$03,$06,$07,$03,$0B,$07,$07,$07,$07,$06,$06,$05,$07,$07 ; $C0
    db $0B,$07,$07,$07,$07,$04,$07,$07,$08,$07,$07,$07,$07,$07,$03,$07 ; $D0
    db $05,$08,$06,$03,$09,$04,$04,$03,$03,$03,$08,$08,$08,$09,$0B,$04 ; $E0
    db $0B,$09,$00,$09,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04 ; $F0

; $C2:6146 — TextWin_StrNadia (5 bytes, $6146–$614A)
; Glyphs "Nadia" (TextWin_CodeNadia, code $1E).
TextWin_StrNadia:
    db $AD,$BA,$BD,$C2,$BA

; $C2:614B — TextWin_DivBits (19 bytes, $614B–$615D)
; One decimal digit by shift and subtract: TextWin_DivQuot = A /
; divisor, A = the remainder, for a divisor that the caller put in
; TextWin_DivSub shifted left by Y - 1 (Y = the quotient bits). Each
; pass: if A >= TextWin_DivSub, A - TextWin_DivSub and a 1 bit, else a
; 0, into TextWin_DivQuot; TextWin_DivSub / 2. Works in the caller's
; width: 8-bit for TextWin_Dec8, 16-bit for TextWin_Dec16 (then
; TextWin_DivQuot's second byte is zeroed too).
; Callers (6 JSR sites): TextWin_Dec8 ($C2:616A, $C2:6176) and TextWin_Dec16 ($C2:618C, $C2:6198,
;   $C2:61A4, $C2:61B0).
; Entry: M=1 or 0 (the operand width), X=0, DP=$0200, DB any; A = the
;        value; TextWin_DivSub = the shifted divisor; Y = the bit count
; Exit:  M, X unchanged; A = the remainder; TextWin_DivQuot = the digit;
;        TextWin_DivSub shifted right Y times; Y = 4 (the next digit's
;        bit count for the callers); X unchanged
; No calls.
TextWin_DivBits:
    STZ.b !TextWin_DivQuot
.next:
    CMP.b !TextWin_DivSub
    BCC .bit
    SBC.b !TextWin_DivSub
.bit:
    ROL.b !TextWin_DivQuot
    LSR.b !TextWin_DivSub
    DEY
    BNE .next
    LDY.w #4
    RTS

; $C2:615E — TextWin_Dec8 (34 bytes, $615E–$617F)
; TextWin_NumValue's first byte as 3 decimal digits (0-9 each) at
; TextWin_DecDigits, most significant first (TextWin_DivBits by 100 and
; 10; the remainder is the last digit). Each digit is stored as a word,
; the next store replacing its second byte.
; Callers (1 JSR site): TextWin_CodeNum8 ($C2:5961).
; Entry: M any (SEP #$20 here), X=0, DP=$0200, DB any
; Exit:  M=1, X=0; A = the last digit; X = the word at TextWin_DivQuot
;        (the tens digit, high byte not cleared); Y = 4; TextWin_DivSub
;        changed
; Calls: TextWin_DivBits.
TextWin_Dec8:
    SEP #$20
    LDA.b !TextWin_NumValue
    LDY.w #2
    LDX.w #!TextWin_Dec8First
    STX.b !TextWin_DivSub
    JSR TextWin_DivBits
    LDX.b !TextWin_DivQuot
    STX.b !TextWin_DecDigits
    LDX.w #!TextWin_DecTens
    STX.b !TextWin_DivSub
    JSR TextWin_DivBits
    LDX.b !TextWin_DivQuot
    STX.b !TextWin_DecDigits+1
    STA.b !TextWin_DecDigits+2
    RTS

; $C2:6180 — TextWin_Dec16 (61 bytes, $6180–$61BC)
; TextWin_NumValue's first word as 5 decimal digits at TextWin_DecDigits
; (TextWin_DivBits in 16 bits by 10000, 1000, 100 and 10; the remainder
; is the last digit, stored as a word: TextWin_DecDigits+5 = 0).
; Callers (1 JSR site): TextWin_CodeNum16 ($C2:5998).
; Entry: M any (REP #$20 here), X=0, DP=$0200 (TDC at the end), DB any
; Exit:  M=1, X=0; A = $0200 (TDC: A = $00, B = $02); X = the tens digit;
;        Y = 4; TextWin_DivSub, TextWin_DivQuot changed
; Calls: TextWin_DivBits.
TextWin_Dec16:
    REP #$20
    LDA.b !TextWin_NumValue
    LDY.w #3
    LDX.w #!TextWin_Dec16First
    STX.b !TextWin_DivSub
    JSR TextWin_DivBits
    LDX.b !TextWin_DivQuot
    STX.b !TextWin_DecDigits
    LDX.w #!TextWin_DecThousands
    STX.b !TextWin_DivSub
    JSR TextWin_DivBits
    LDX.b !TextWin_DivQuot
    STX.b !TextWin_DecDigits+1
    LDX.w #!TextWin_DecHundreds
    STX.b !TextWin_DivSub
    JSR TextWin_DivBits
    LDX.b !TextWin_DivQuot
    STX.b !TextWin_DecDigits+2
    LDX.w #!TextWin_DecTens
    STX.b !TextWin_DivSub
    JSR TextWin_DivBits
    LDX.b !TextWin_DivQuot
    STX.b !TextWin_DecDigits+3
    STA.b !TextWin_DecDigits+4
    TDC
    SEP #$20
    RTS

; $C2:61BD — TextWin_Dec24 (116 bytes, $61BD–$6230)
; TextWin_NumValue's 24 bits as 8 decimal digits at TextWin_DecDigits
; (TextWin_Div24Bits by 10000000 ... 10; the last digit is what is left
; of TextWin_NumValue's first byte). TextWin_NumValue is used up (left as
; the last digit).
; Callers (1 JSR site): TextWin_CodeNum24 ($C2:59E6).
; Entry: M any (SEP #$20 here), X=0, DP=$0200, DB any
; Exit:  M=1, X=0; A = the last digit; X = the tens digit and the
;        divisor's next byte; Y = 4; TextWin_NumValue,
;        TextWin_Div24Quot/Sub changed
; Calls: TextWin_Div24Bits.
TextWin_Dec24:
    SEP #$20
    LDY.w #1
    LDX.w #!TextWin_Dec24First&$FFFF
    STX.b !TextWin_Div24Sub
    LDA.b #!TextWin_Dec24First>>16
    STA.b !TextWin_Div24Sub+2
    JSR TextWin_Div24Bits
    LDX.b !TextWin_Div24Quot
    STX.b !TextWin_DecDigits
    LDX.w #!TextWin_DecMillions&$FFFF
    STX.b !TextWin_Div24Sub
    LDA.b #!TextWin_DecMillions>>16
    STA.b !TextWin_Div24Sub+2
    JSR TextWin_Div24Bits
    LDX.b !TextWin_Div24Quot
    STX.b !TextWin_DecDigits+1
    LDX.w #!TextWin_DecHundredK&$FFFF
    STX.b !TextWin_Div24Sub
    LDA.b #!TextWin_DecHundredK>>16
    STA.b !TextWin_Div24Sub+2
    JSR TextWin_Div24Bits
    LDX.b !TextWin_Div24Quot
    STX.b !TextWin_DecDigits+2
    LDX.w #!TextWin_DecTenK&$FFFF
    STX.b !TextWin_Div24Sub
    LDA.b #!TextWin_DecTenK>>16
    STA.b !TextWin_Div24Sub+2
    JSR TextWin_Div24Bits
    LDX.b !TextWin_Div24Quot
    STX.b !TextWin_DecDigits+3
    LDX.w #!TextWin_DecThousands
    STX.b !TextWin_Div24Sub
    STZ.b !TextWin_Div24Sub+2
    JSR TextWin_Div24Bits
    LDX.b !TextWin_Div24Quot
    STX.b !TextWin_DecDigits+4
    LDX.w #!TextWin_DecHundreds
    STX.b !TextWin_Div24Sub
    STZ.b !TextWin_Div24Sub+2
    JSR TextWin_Div24Bits
    LDX.b !TextWin_Div24Quot
    STX.b !TextWin_DecDigits+5
    LDX.w #!TextWin_DecTens
    STX.b !TextWin_Div24Sub
    STZ.b !TextWin_Div24Sub+2
    JSR TextWin_Div24Bits
    LDX.b !TextWin_Div24Quot
    STX.b !TextWin_DecDigits+6
    LDA.b !TextWin_NumValue
    STA.b !TextWin_DecDigits+7
    RTS

; $C2:6231 — TextWin_Div24Bits (50 bytes, $6231–$6262)
; TextWin_DivBits for 24 bits, in place: TextWin_NumValue (3 bytes) is
; the value and becomes the remainder; TextWin_Div24Sub (3 bytes, shifted
; left by Y - 1) the divisor; TextWin_Div24Quot gets Y quotient bits.
; Each pass subtracts only when the trial subtraction does not borrow.
; Callers (7 JSR sites): TextWin_Dec24 ($C2:61CB, $C2:61DB, $C2:61EB, $C2:61FB, $C2:6209, $C2:6217,
;   $C2:6225).
; Entry: M=1, X=0, DP=$0200, DB any; Y = the bit count
; Exit:  M=1, X=0; Y = 4; A clobbered; TextWin_NumValue, TextWin_Div24Quot and
;        TextWin_Div24Sub changed; X unchanged
; No calls.
TextWin_Div24Bits:
    STZ.b !TextWin_Div24Quot
.next:
    SEC
    LDA.b !TextWin_NumValue
    SBC.b !TextWin_Div24Sub
    LDA.b !TextWin_NumValue+1
    SBC.b !TextWin_Div24Sub+1
    LDA.b !TextWin_NumValue+2
    SBC.b !TextWin_Div24Sub+2
    BCC .bit
    LDA.b !TextWin_NumValue
    SBC.b !TextWin_Div24Sub
    STA.b !TextWin_NumValue
    LDA.b !TextWin_NumValue+1
    SBC.b !TextWin_Div24Sub+1
    STA.b !TextWin_NumValue+1
    LDA.b !TextWin_NumValue+2
    SBC.b !TextWin_Div24Sub+2
    STA.b !TextWin_NumValue+2
.bit:
    ROL.b !TextWin_Div24Quot
    LSR.b !TextWin_Div24Sub+2
    ROR.b !TextWin_Div24Sub+1
    ROR.b !TextWin_Div24Sub
    DEY
    BNE .next
    LDY.w #4
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
; Metatile map and tile property lookups ($C2:6291–$C2:62EC)
; ============================================================
; Both index a 96-column metatile map (C2Scene_MapCols, through the
; hardware multiplier) at C2Scene_PropMap; C2Scene_GetTileProp then
; reads C2Scene_PropTable, two bytes per metatile number (top and
; bottom row of 8x8 tiles), a nibble per 8x8 tile (high: left).

; $C2:6291 — C2Scene_GetMapCell (29 bytes, $6291–$62AD)
; A = the metatile number at column C2Scene_PropCol (0-95), row
; C2Scene_PropRow of the map at C2Scene_PropMap (byte row * 96 +
; column).
; Callers note: none found (no reference in the bank, and no byte pattern).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Tmp_00/$01, $10-$12),
;        DB=$00 (WRMPYA/B and RDMPYL absolute); C2Scene_PropMap set
; Exit:  M=1, X=0; A = the metatile (B = the next map byte); Y = the
;        offset; X unchanged
; No calls.
C2Scene_GetMapCell:
    SEP #$20
    LDA.b !C2Scene_PropRow
    STA.w WRMPYA
    LDA.b #!C2Scene_MapCols
    STA.w WRMPYB
    REP #$20
    CLC
    LDA.b !C2Scene_PropCol
    AND.w #!Eng_LowByteMask
    ADC.w RDMPYL
    TAY
    LDA.b [!C2Scene_PropMap],Y
    SEP #$20
    RTS

; $C2:62AE — C2Scene_GetTileProp (63 bytes, $62AE–$62EC)
; A = the property nibble of 8x8 tile C2Scene_PropCol (0-191),
; C2Scene_PropRow (0-127): the metatile at column / 2, row / 2 of the
; map at C2Scene_PropMap; its byte row bit 0 (byte metatile * 2 + row
; bit 0) of C2Scene_PropTable; the high nibble for an even column, the
; low one for an odd column. C2Scene_PropCol/Row are halved in place.
; Callers (12 JSR sites): C2Scene_GetTileProps ($C2:3A0F, $C2:3A25, $C2:3A3D, $C2:3A4D),
;   C2Scene_ScanRow ($C2:422C, $C2:4245), C2Scene_ScanCol ($C2:4284, $C2:4294, $C2:42B3, $C2:42C3)
;   and C2Scene_ObjAGetProps ($C2:4A82, $C2:4A92).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Tmp_00-$04, $10-$15),
;        DB=$00 (WRMPYA/B and RDMPYL absolute); C2Scene_PropMap and
;        C2Scene_PropTable set
; Exit:  M=1, X=0; A = the nibble (0-15; B = the high byte of the
;        table offset); Y = the table offset; X unchanged;
;        C2Scene_PropCol/Row halved, C2Scene_PropColBit 0,
;        C2Scene_PropRowBit = row bit 0
; No calls.
C2Scene_GetTileProp:
    SEP #$20
    STZ.b !C2Scene_PropColBit
    STZ.b !C2Scene_PropRowBit
    STZ.b !C2Scene_PropRowBit+1 ; the high byte of the 16-bit add below
    LSR.b !C2Scene_PropCol
    ROL.b !C2Scene_PropColBit
    LSR.b !C2Scene_PropRow
    ROL.b !C2Scene_PropRowBit
    LDA.b !C2Scene_PropRow
    STA.w WRMPYA
    LDA.b #!C2Scene_MapCols
    STA.w WRMPYB
    REP #$20
    CLC
    LDA.b !C2Scene_PropCol
    AND.w #!Eng_LowByteMask
    ADC.w RDMPYL
    TAY
    LDA.b [!C2Scene_PropMap],Y
    AND.w #!Eng_LowByteMask
    ASL A                       ; 2 bytes per metatile; C = 0 for the ADC
    ADC.b !C2Scene_PropRowBit
    TAY
    SEP #$20
    LDA.b [!C2Scene_PropTable],Y
    LSR.b !C2Scene_PropColBit
    BCS .odd
    LSR A
    LSR A
    LSR A
    LSR A
    RTS
.odd:
    AND.b #!C2Scene_TilePropLowNibble
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
; Screen effects and script routines ($C2:754D–$C2:7B59)
; ============================================================
; Small routines for the scene scripts and the tasks they start, none
; referenced from bank $C2 code. The routines ending in RTS without a
; task's C=0/C=1 meaning are called by script op $34 (C2Script_CallNear,
; M=1 and X=0; found as "$34 lo hi" in the bank $C3 scene scripts, e.g.
; $C3:8E67 calls C2Scene_PlaceBelowViewAt178); the task handlers are
; started by op $35 (C2Script_SpawnTask, "$35 lo hi" at $C3:8BBD and on).
; All run inside C2Scene_TaskRunAll (from the scene NMI), with DP=$0000
; and DB=$00, C2Scene_TaskCur = the running task. The BG3 tasks wait while
; object A is in scene mode 8 (C2Scene_ObjAInMode8) and also scroll BG3
; by the leader's last move (C2Scene_Unk1BF1/1BF3), which they then zero.
; The HDMA effects use C2Scene_HdmaTable records 0/1 (two runs of 112
; lines, whose addresses the NMI copies from C2Scene_HdmaValues) in
; indirect mode, pointing into the C2Scene_LineBuf* buffers.

org $C2754D
; $C2:754D — C2Scene_PlaceBelowView (40 bytes, $754D–$7574)
; Script routine: puts the task at a random X 64-191 pixels into BG2's
; view (C2Scene_BgTileX+2 x 8 + a random 0-127 + 64) and 256 pixels below
; the view's top (C2Scene_BgTileY+2 + 32 tile rows, x 8): just under the
; screen.
; Quirk, kept: the first ADC has no CLC; the carry is bit 13 of the tile
; X shifted out by the third ASL, 0 for any tile X (0-191).
; Entry: M=1 (the 8-bit AND/STZ; C2Scene_Random sets M=1 again), X=0,
;        DP=$0000 (C2Tmp_08, the tile words), DB=$00 (the task record
;        and C2Scene_Random's index); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .SprY; Y unchanged;
;        C2Tmp_08 = the random part (a word); C2Scene_Unk1B30 + 1
; Calls: C2Scene_Random.
C2Scene_PlaceBelowView:
    JSR C2Scene_Random
    AND.b #!C2Scene_PlaceRandMask
    STA.b !C2Tmp_08
    STZ.b !C2Tmp_09
    LDX.b !C2Scene_TaskCur
    REP #$20
    LDA.b !C2Scene_BgTileX+2            ; BG2's tile X, x 8
    ASL A
    ASL A
    ASL A
    ADC.b !C2Tmp_08                     ; no CLC (see the header)
    CLC
    ADC.w #!C2Scene_PlaceMarginX
    STA.w C2Scene_Task.SprX,X
    LDA.b !C2Scene_BgTileY+2
    CLC
    ADC.w #!C2Scene_PlaceRowsDown
    ASL A
    ASL A
    ASL A
    STA.w C2Scene_Task.SprY,X
    RTS

; $C2:7575 — C2Scene_PlaceBelowViewAt178 (35 bytes, $7575–$7597)
; Script routine: as C2Scene_PlaceBelowView, but X is pixel $178 (tile
; column C2Scene_PlaceFixedCol) + a random 0-255, not relative to the
; view; Y is again 256 pixels below the top of BG2's view.
; Entry: M=1 (C2Scene_Random leaves M=1), X=0, DP=$0000, DB=$00;
;        C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .SprY; Y unchanged;
;        C2Tmp_08 = the random byte (a word); C2Scene_Unk1B30 + 1
; Calls: C2Scene_Random.
C2Scene_PlaceBelowViewAt178:
    JSR C2Scene_Random
    STA.b !C2Tmp_08
    STZ.b !C2Tmp_09
    LDX.b !C2Scene_TaskCur
    REP #$20
    LDA.w #!C2Scene_PlaceFixedCol
    ASL A
    ASL A
    ASL A
    ADC.b !C2Tmp_08                     ; the carry is 0 here ($2F x 8 does not overflow)
    STA.w C2Scene_Task.SprX,X
    LDA.b !C2Scene_BgTileY+2
    CLC
    ADC.w #!C2Scene_PlaceRowsDown
    ASL A
    ASL A
    ASL A
    STA.w C2Scene_Task.SprY,X
    RTS

; $C2:7598 — C2Scene_RandomVelocity (43 bytes, $7598–$75C2)
; Script routine: gives the task one of 16 velocities at random: the
; four words of entry (random AND 15) of C2SceneRom_RandVelocities go to
; .XVelFrac, .XVel, .YVelFrac and .YVel.
; Entry: M=1 (C2Scene_Random leaves M=1), X=0, DP=$0000 (C2Scene_TaskCur),
;        DB=$00 (the task record); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the entry x 8; Y = the task; A = the new .YVel;
;        C2Scene_Unk1B30 + 1
; Calls: C2Scene_Random.
C2Scene_RandomVelocity:
    JSR C2Scene_Random
    LDY.b !C2Scene_TaskCur
    REP #$20
    AND.w #!C2Scene_RandVelMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !C2SceneRom_RandVelocities,X
    STA.w C2Scene_Task.XVelFrac,Y
    LDA.l !C2SceneRom_RandVelocities+2,X
    STA.w C2Scene_Task.XVel,Y
    LDA.l !C2SceneRom_RandVelocities+4,X
    STA.w C2Scene_Task.YVelFrac,Y
    LDA.l !C2SceneRom_RandVelocities+6,X
    STA.w C2Scene_Task.YVel,Y
    RTS

; $C2:75C3 — C2Scene_TaskBg3Drift (58 bytes, $75C3–$75FC)
; Task handler (started by op $35 at $C3:8BBD): while object A is not
; in mode 8, counts frames in .Var22 and moves BG3 one pixel left every
; 4th frame and one pixel down every 8th; then adds the leader's last
; move (C2Scene_Unk1BF1/1BF3) to BG3's scroll and zeroes it. Never ends.
; Entry: M=1 (8-bit flag test), X=0, DP=$0000 (the scroll shadows),
;        DB=$00 (C2Scene_Unk0294, the record, C2Scene_Unk1BF1/1BF3);
;        C2Scene_TaskCur = the task
; Exit:  C=0 (the task goes on); M=1 when object A is in mode 8 (nothing
;        done), else M=0 with X = the task and A = C2Scene_Bg3VScroll;
;        C2Scene_Bg3HScroll/VScroll, .Var22 and C2Scene_Unk1BF1/1BF3
;        changed
; No calls.
C2Scene_TaskBg3Drift:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BNE .done
    REP #$20
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_EffectTask.Var22,X
    LDA.w C2Scene_EffectTask.Var22,X
    AND.w #!C2Scene_DriftHMask
    BNE .no_left
    DEC.b !C2Scene_Bg3HScroll
.no_left:
    LDA.w C2Scene_EffectTask.Var22,X
    AND.w #!C2Scene_DriftVMask
    BNE .no_down
    INC.b !C2Scene_Bg3VScroll
.no_down:
    LDA.b !C2Scene_Bg3HScroll
    CLC
    ADC.w !C2Scene_Unk1BF1
    STA.b !C2Scene_Bg3HScroll
    LDA.b !C2Scene_Bg3VScroll
    CLC
    ADC.w !C2Scene_Unk1BF3
    STA.b !C2Scene_Bg3VScroll
    STZ.w !C2Scene_Unk1BF1
    STZ.w !C2Scene_Unk1BF3
.done:
    CLC
    RTS

; $C2:75FD — C2Scene_TaskBg3DriftWave (85 bytes, $75FD–$7651)
; Task handler (op $35 at $C3:980D, next to C2Scene_TaskBg3Wave's at
; $C3:9811): as C2Scene_TaskBg3Drift, but BG3 moves one pixel left and
; one down together every 4th frame, and the leader's Y move also slides
; the wave's start (C2Scene_HdmaValueA916) by that many lines (2 bytes
; each), kept inside the first copy of the 64-line wave
; (C2Scene_WaveBuf - C2Scene_WaveBufCopy - 1) by adding or subtracting
; its 128 bytes. The ASL doubles C2Scene_Unk1BF3 in place before it is
; zeroed. Never ends.
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_TaskCur = the task
; Exit:  C=0; M=1 when object A is in mode 8 (nothing done), else M=0
;        with X = the task and A = the new C2Scene_HdmaValueA916;
;        C2Scene_Bg3HScroll/VScroll, .Var22, C2Scene_HdmaValueA916 and
;        C2Scene_Unk1BF1/1BF3 changed
; No calls.
C2Scene_TaskBg3DriftWave:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BNE .done
    REP #$20
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_EffectTask.Var22,X
    LDA.w C2Scene_EffectTask.Var22,X
    AND.w #!C2Scene_DriftHMask
    BNE .no_step
    DEC.b !C2Scene_Bg3HScroll
    INC.b !C2Scene_Bg3VScroll
.no_step:
    LDA.b !C2Scene_Bg3HScroll
    CLC
    ADC.w !C2Scene_Unk1BF1
    STA.b !C2Scene_Bg3HScroll
    LDA.b !C2Scene_Bg3VScroll
    CLC
    ADC.w !C2Scene_Unk1BF3
    STA.b !C2Scene_Bg3VScroll
    ASL.w !C2Scene_Unk1BF3              ; lines to bytes
    LDA.l !C2Scene_HdmaValueA916
    CLC
    ADC.w !C2Scene_Unk1BF3
    CMP.w #!C2Scene_WaveBuf&$FFFF
    BCS .not_below
    CLC
    ADC.w #!C2Scene_WaveBufCopy-!C2Scene_WaveBuf
    BRA .store
.not_below:
    CMP.w #!C2Scene_WaveBufCopy&$FFFF
    BCC .store
    SEC
    SBC.w #!C2Scene_WaveBufCopy-!C2Scene_WaveBuf
.store:
    STA.l !C2Scene_HdmaValueA916
    STZ.w !C2Scene_Unk1BF1
    STZ.w !C2Scene_Unk1BF3
.done:
    CLC
    RTS

; $C2:7652 — C2Scene_TaskBg3Wave (176 bytes, $7652–$7701)
; Task handler (op $35 at $C3:9811): a horizontal wave on BG3. In forced
; blank (C2Scene_InidispShadow bit 7) it only turns HDMA channel 1 off;
; while object A is in mode 8 it waits. Else, on its first frame
; (.State 0 -> 1) it zeroes the phase .Var22 and starts the wave at
; C2Scene_WaveBuf (C2Scene_HdmaValueA916). Each frame it sets up
; C2Scene_HdmaTableA918 (three runs of 64 lines and one of 32, whose
; addresses the NMI fills from C2Scene_HdmaValueA916, so every 64-line
; band shows the same 64 words) as HDMA channel 1 to BG3HOFS (indirect,
; one register written twice), turns the channel on, writes the 64
; words of C2Scene_WaveBuf, C2Scene_Bg3HScroll + sin(phase + 16 x line)
; / 4 (Trig_Sin1024: one period over the 64 lines, -63..+63 pixels),
; with the phase taken before .Var22 goes up by one, and copies them to
; C2Scene_WaveBufCopy. Never ends.
; Entry: M=1, X=0 with X = the task (as C2Scene_TaskRunAll calls it; not
;        reloaded), DP=$0000 (C2Tmp_08-$12, the shadows), DB=$00 (the
;        record, the DMA registers)
; Exit:  C=0; M=1 (forced blank or mode 8: nothing else done) or M=0
;        with A = $FFFF, X = $A9A5, Y = $AA25 (the MVN's ends) and DB
;        unchanged (saved around the MVN); C2Tmp_08,
;        $0A and $10-$12 changed
; Calls: Trig_Sin1024 (JSL).
C2Scene_TaskBg3Wave:
    LDA.b !C2Scene_InidispShadow
    BPL .shown
    LDA.b #DMA_CH1
    TRB.b !C2Scene_HdmaenShadow
    CLC
    RTS
.shown:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BEQ .run
    CLC
    RTS
.run:
    LDA.w C2Scene_EffectTask.State,X
    BNE .started
    INC.w C2Scene_EffectTask.State,X
    STZ.w C2Scene_EffectTask.Var22,X
    STZ.w C2Scene_EffectTask.Var22+1,X
    REP #$20
    LDA.w #!C2Scene_WaveBuf&$FFFF
    STA.l !C2Scene_HdmaValueA916
    SEP #$20
.started:
    LDA.b #!C2Scene_HdmaRun64
    STA.l !C2Scene_HdmaTableA918
    STA.l !C2Scene_HdmaTableA918+3
    STA.l !C2Scene_HdmaTableA918+6
    LDA.b #!C2Scene_HdmaRun32
    STA.l !C2Scene_HdmaTableA918+9
    TDC
    STA.l !C2Scene_HdmaTableA918+12     ; end of the table
    LDY.w #(!BBAD_BG3HOFS<<8)|!DMAP_HdmaIndirect|DMA_MODE_1BYTE_X2
    STY.w DMAP1
    LDY.w #!C2Scene_HdmaTableA918&$FFFF
    STY.w A1T1L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B                         ; bank of the indirect addresses
    LDA.b #DMA_CH1
    TSB.b !C2Scene_HdmaenShadow
    LDY.w #!C2Scene_WaveBuf&$FFFF
    STY.b !C2Tmp_10
    LDA.b #bank(!C2Scene_WaveBuf)
    STA.b !C2Tmp_12
    REP #$20
    LDA.w C2Scene_EffectTask.Var22,X
    STA.b !C2Tmp_0A
    CLC
    ADC.w #1
    STA.w C2Scene_EffectTask.Var22,X
    LDY.w #0
.line:
    LDA.b !C2Tmp_0A
    JSL Trig_Sin1024
    STA.b !C2Tmp_08
    LDA.b !C2Tmp_0A
    CLC
    ADC.w #!C2Scene_WaveLineStep
    STA.b !C2Tmp_0A
    LDA.b !C2Tmp_08
    BPL .positive
    LSR A                               ; / 4, keeping the sign
    LSR A
    ORA.w #!C2Scene_WaveSignBits
    BRA .add
.positive:
    LSR A
    LSR A
.add:
    CLC
    ADC.b !C2Scene_Bg3HScroll
    STA.b [!C2Tmp_10],Y
    INY
    INY
    CPY.w #!C2Scene_WaveBufCopy-!C2Scene_WaveBuf
    BNE .line
    PHB
    LDX.w #!C2Scene_WaveBuf&$FFFF
    LDY.w #!C2Scene_WaveBufCopy&$FFFF
    LDA.w #!C2Scene_WaveBufCopy-!C2Scene_WaveBuf-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    CLC
    RTS

; $C2:7702 — C2Scene_TaskBg3Slide (87 bytes, $7702–$7758)
; Task handler (op $35 at $C3:9F92): while object A is not in mode 8,
; moves BG3 by a fixed velocity, X about -3.46 and Y +2 pixels a frame
; (set into .XVelFrac-.YVel on the first frame, .State 0 -> 1), through
; the task's own position (.SprX/.SprY = the BG3 scroll, C2Scene_TaskMove,
; back into the scroll, keeping the fractions in .XFrac/.YFrac); then
; adds the leader's last move as C2Scene_TaskBg3Drift. Never ends.
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_TaskCur = the task
; Exit:  C=0; M=1 when object A is in mode 8 (nothing done), else M=0
;        with X = the task and A = C2Scene_Bg3VScroll; the scroll, the
;        task's position and C2Scene_Unk1BF1/1BF3 changed
; Calls: C2Scene_TaskMove.
C2Scene_TaskBg3Slide:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BNE .done
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.State,X
    REP #$20                            ; (the flags are still the 8-bit load's)
    BNE .started
    INC.w C2Scene_EffectTask.State,X
    LDA.w #!C2Scene_SlideXVelFrac
    STA.w C2Scene_Task.XVelFrac,X
    LDA.w #!C2Scene_SlideXVel
    STA.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    LDA.w #!C2Scene_SlideYVel
    STA.w C2Scene_Task.YVel,X
.started:
    LDA.b !C2Scene_Bg3HScroll
    STA.w C2Scene_Task.SprX,X
    LDA.b !C2Scene_Bg3VScroll
    STA.w C2Scene_Task.SprY,X
    JSR C2Scene_TaskMove
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_Bg3HScroll
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_Bg3VScroll
    LDA.b !C2Scene_Bg3HScroll
    CLC
    ADC.w !C2Scene_Unk1BF1
    STA.b !C2Scene_Bg3HScroll
    LDA.b !C2Scene_Bg3VScroll
    CLC
    ADC.w !C2Scene_Unk1BF3
    STA.b !C2Scene_Bg3VScroll
    STZ.w !C2Scene_Unk1BF1
    STZ.w !C2Scene_Unk1BF3
.done:
    CLC
    RTS

; $C2:7759 — C2Scene_TaskBg3LineWave (153 bytes, $7759–$77F1)
; Task handler (no reference found; laid out as C2Scene_TaskBg3Wave):
; in forced blank only turns HDMA channel 1 off; waits while object A is
; in mode 8. Else (on the first frame .State 0 -> 1 and .Var22 = 0) sets
; up C2Scene_HdmaTable[0] as two runs of 112 lines on HDMA channel 1 to
; BG3HOFS (indirect, one register twice) from C2Scene_LineBufA and its
; second half, turns the channel on, and fills C2Scene_LineBufA: every
; even line C2Scene_Bg3HScroll, every odd line C2Scene_Bg3HScroll +
; sin(phase + n) (Trig_Sin1024, -255..+255 pixels; n = 0, 1, ... down
; the odd lines), the phase going up by 4 each frame. Never ends.
; Quirk, kept: after the even-line loop X is $1C0, not the task, so the
; phase is read from and written to $0022 + $1C0 = C2Scene_Unk01E2 in
; low WRAM; the .Var22 the first frame zeroes is never used.
; Entry: M=1, X=0 with X = the task (as C2Scene_TaskRunAll calls it),
;        DP=$0000, DB=$00 (the record, C2Scene_Unk01E2, the DMA
;        registers)
; Exit:  C=0; M=1 (forced blank or mode 8: nothing else done) or M=0
;        with X = $01C2, Y = $01BE; C2Tmp_0A = the phase + 112;
;        C2Scene_Unk01E2 + 4
; Calls: Trig_Sin1024 (JSL).
C2Scene_TaskBg3LineWave:
    LDA.b !C2Scene_InidispShadow
    BPL .shown
    LDA.b #DMA_CH1
    TRB.b !C2Scene_HdmaenShadow
    CLC
    RTS
.shown:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BEQ .run
    CLC
    RTS
.run:
    LDA.w C2Scene_EffectTask.State,X
    BNE .started
    INC.w C2Scene_EffectTask.State,X
    STZ.w C2Scene_EffectTask.Var22,X
    STZ.w C2Scene_EffectTask.Var22+1,X
.started:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[0].Count0
    STA.l C2Scene_HdmaTable[0].Count1
    TDC
    STA.l C2Scene_HdmaTable[0].End
    REP #$20
    LDA.w #!C2Scene_LineBufA&$FFFF
    STA.l !C2Scene_HdmaValues
    LDA.w #(!C2Scene_LineBufA+!C2Scene_LineBufHalf)&$FFFF
    STA.l !C2Scene_HdmaValues+2
    SEP #$20
    LDY.w #(!BBAD_BG3HOFS<<8)|!DMAP_HdmaIndirect|DMA_MODE_1BYTE_X2
    STY.w DMAP1
    LDY.w #C2Scene_HdmaTable[0].Count0&$FFFF
    STY.w A1T1L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B
    LDA.b #DMA_CH1
    TSB.b !C2Scene_HdmaenShadow
    REP #$20
    LDX.w #0
.even:
    LDA.b !C2Scene_Bg3HScroll
    STA.l !C2Scene_LineBufA,X
    INX
    INX
    INX
    INX
    CPX.w #!C2Scene_LineBufBytes
    BNE .even
    LDA.w C2Scene_EffectTask.Var22,X    ; X = $1C0 here: C2Scene_Unk01E2 (see the header)
    STA.b !C2Tmp_0A
    CLC
    ADC.w #!C2Scene_LineWaveStep
    STA.w C2Scene_EffectTask.Var22,X
    LDX.w #2
.odd:
    TXY
    LDA.b !C2Tmp_0A
    JSL Trig_Sin1024
    INC.b !C2Tmp_0A
    TYX
    CLC
    ADC.b !C2Scene_Bg3HScroll
    STA.l !C2Scene_LineBufA,X
    INX
    INX
    INX
    INX
    CPX.w #!C2Scene_LineBufBytes+2
    BNE .odd
    CLC
    RTS

; $C2:77F2 — C2Scene_TaskBg3SlideFast (87 bytes, $77F2–$7848)
; Task handler (op $35 at $C3:AC92): C2Scene_TaskBg3Slide with the
; velocity X about -17.32 and Y -10 pixels a frame. Never ends.
; Entry: M=1, X=0, DP=$0000, DB=$00; C2Scene_TaskCur = the task
; Exit:  C=0; M=1 when object A is in mode 8 (nothing done), else M=0
;        with X = the task and A = C2Scene_Bg3VScroll; the scroll, the
;        task's position and C2Scene_Unk1BF1/1BF3 changed
; Calls: C2Scene_TaskMove.
C2Scene_TaskBg3SlideFast:
    LDA.w !C2Scene_Unk0294
    BIT.b #!C2Scene_ObjAInMode8
    BNE .done
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.State,X
    REP #$20                            ; (the flags are still the 8-bit load's)
    BNE .started
    INC.w C2Scene_EffectTask.State,X
    LDA.w #!C2Scene_SlideFastXVelFrac
    STA.w C2Scene_Task.XVelFrac,X
    LDA.w #!C2Scene_SlideFastXVel
    STA.w C2Scene_Task.XVel,X
    STZ.w C2Scene_Task.YVelFrac,X
    LDA.w #!C2Scene_SlideFastYVel
    STA.w C2Scene_Task.YVel,X
.started:
    LDA.b !C2Scene_Bg3HScroll
    STA.w C2Scene_Task.SprX,X
    LDA.b !C2Scene_Bg3VScroll
    STA.w C2Scene_Task.SprY,X
    JSR C2Scene_TaskMove
    LDA.w C2Scene_Task.SprX,X
    STA.b !C2Scene_Bg3HScroll
    LDA.w C2Scene_Task.SprY,X
    STA.b !C2Scene_Bg3VScroll
    LDA.b !C2Scene_Bg3HScroll
    CLC
    ADC.w !C2Scene_Unk1BF1
    STA.b !C2Scene_Bg3HScroll
    LDA.b !C2Scene_Bg3VScroll
    CLC
    ADC.w !C2Scene_Unk1BF3
    STA.b !C2Scene_Bg3VScroll
    STZ.w !C2Scene_Unk1BF1
    STZ.w !C2Scene_Unk1BF3
.done:
    CLC
    RTS

; $C2:7849 — C2Scene_TaskBg1Pan (23 bytes, $7849–$785F)
; Task handler (no op $35 reference found): counts frames in .Var22
; (8-bit) and every 4th frame scrolls layer 1 one pixel
; (C2Scene_Unk0568 with C2Scene_ScrollLayer = C2Scene_ScrollPx = 1),
; which also builds the tile column that comes into view. Never ends.
; Entry: M=1 (8-bit counter), X=0, DP=$0000, DB=$00 (the record and
;        C2Scene_Unk0568's state); C2Scene_TaskCur = the task
; Exit:  C=0; M=1, X=0; X = the task (no scroll) or as C2Scene_Unk0568
;        leaves it; A, Y and C2Tmp_00-$1A as C2Scene_Unk0568 leaves them
; Calls: C2Scene_Unk0568.
C2Scene_TaskBg1Pan:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_EffectTask.Var22,X
    LDA.w C2Scene_EffectTask.Var22,X
    AND.b #!C2Scene_PanMask
    BNE .done
    LDA.b #1
    STA.b !C2Scene_ScrollPx
    STA.b !C2Scene_ScrollLayer          ; layer 1
    JSR C2Scene_Unk0568
.done:
    CLC
    RTS

; $C2:7860 — C2Scene_ClearParty (15 bytes, $7860–$786E)
; Script routine: marks all three Party_Members slots empty
; (C2Scene_PartySlotEmpty).
; Entry: M=1 (8-bit stores), X any, DP any, DB any (long stores)
; Exit:  M=1; A = C2Scene_PartySlotEmpty; X, Y unchanged
; No calls.
C2Scene_ClearParty:
    LDA.b #!C2Scene_PartySlotEmpty
    STA.l !Party_Members
    STA.l !Party_Members+1
    STA.l !Party_Members+2
    RTS

; $C2:786F — C2Scene_SaveParty (25 bytes, $786F–$7887)
; Script routine: copies the three Party_Members bytes to
; C2Scene_PartySave (C2Scene_RestoreParty puts them back).
; Entry: M=1, X any, DP any, DB any (long addressing throughout)
; Exit:  M=1; A = the third member byte; X, Y unchanged
; No calls.
C2Scene_SaveParty:
    LDA.l !Party_Members
    STA.l !C2Scene_PartySave
    LDA.l !Party_Members+1
    STA.l !C2Scene_PartySave+1
    LDA.l !Party_Members+2
    STA.l !C2Scene_PartySave+2
    RTS

; $C2:7888 — C2Scene_RestoreParty (25 bytes, $7888–$78A0)
; Script routine: copies C2Scene_PartySave back to Party_Members.
; Entry: M=1, X any, DP any, DB any (long addressing throughout)
; Exit:  M=1; A = the third member byte; X, Y unchanged
; No calls.
C2Scene_RestoreParty:
    LDA.l !C2Scene_PartySave
    STA.l !Party_Members
    LDA.l !C2Scene_PartySave+1
    STA.l !Party_Members+1
    LDA.l !C2Scene_PartySave+2
    STA.l !Party_Members+2
    RTS

; $C2:78A1 — C2Scene_TaskInView (66 bytes, $78A1–$78E2)
; Script routine (op $34 at $C3:8E82, followed by an op $23 test of
; $0000): C2Tmp_00 = 1 when the task is in BG2's view with a margin,
; else 0. The position relative to the view plus 16 (.SprX -
; C2Scene_Bg2HScroll + 16, wrapped by the map width when negative; Y the
; same with the map height) must be below 288 (X) and 272 (Y): from 16
; pixels left of / above the screen to 16 right of it and 32 below.
; Entry: M=1 (REP #$20 here), X=0, DP=$0000 (the scroll shadows and
;        C2Tmp), DB=$00 (the record); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; A = C2Tmp_00 = 1 or 0 (8-bit; C2Tmp_01
;        unchanged); C2Tmp_08/0A = the relative X/Y; Y unchanged
; No calls.
C2Scene_TaskInView:
    LDX.b !C2Scene_TaskCur
    REP #$20
    LDA.w C2Scene_Task.SprX,X
    SEC
    SBC.b !C2Scene_Bg2HScroll
    CLC
    ADC.w #!C2Scene_ViewMargin
    BPL .x_done
    CLC
    ADC.w #!C2Scene_MapWidthPx
.x_done:
    STA.b !C2Tmp_08
    LDA.w C2Scene_Task.SprY,X
    SEC
    SBC.b !C2Scene_Bg2VScroll
    CLC
    ADC.w #!C2Scene_ViewMargin
    BPL .y_done
    CLC
    ADC.w #!C2Scene_MapHeightPx
.y_done:
    STA.b !C2Tmp_0A
    LDA.b !C2Tmp_08
    CMP.w #!C2Scene_ViewTestW
    BCS .out
    LDA.b !C2Tmp_0A
    CMP.w #!C2Scene_ViewTestH
    BCS .out
    SEP #$20
    LDA.b #1
    STA.b !C2Tmp_00
    RTS
.out:
    SEP #$20
    STZ.b !C2Tmp_00
    RTS

; $C2:78E3 — C2Scene_Win1Init (116 bytes with C2Scene_Win1Step, $78E3–$7956)
; Script routine: sets up C2Scene_HdmaTable[0] (two runs of 112 lines)
; as HDMA channel 1 to WH0/WH1 (indirect, two registers), turns the
; channel on, zeroes the buffer toggle .Var24 and falls into the
; sub-entry C2Scene_Win1Step ($C2:7911; op $34 at $C3:9C06 calls it on
; its own, probably once a frame): picks C2Scene_LineBufA (.Var24 even)
; or C2Scene_LineBufB (odd), points both C2Scene_HdmaValues words and
; WinFx_TablePtr (bank $7E) at it, adds one to .Var24, and has
; BankC3_Entry0008 (A = WinFx_Mode0) build the window table there from
; the task's .SprX, .SprY and .Var22 (low bytes, as WinFx_ArgX, ArgY and
; ArgSize; the shape is not traced). The table written is the one the
; next NMI shows, while the other stays on screen.
; Entry (both): M any at C2Scene_Win1Init (SEP #$20 there), M=1 at
;        C2Scene_Win1Step (the 8-bit toggle; op $34 calls it with M=1),
;        X=0, DP=$0000 (the shadows and
;        C2Scene_TaskCur), DB=$00 (the record, the DMA registers and
;        WinFx_*); C2Scene_TaskCur = the task
; Exit (both):  M=1, X=0 (as BankC3_Entry0008 returns, saving P); X, Y
;        and A as BankC3_Entry0008 leaves them (not traced); .Var24 + 1;
;        WinFx_* and C2Scene_HdmaValues words 0-1 changed
; Calls: BankC3_Entry0008 (JSL).
C2Scene_Win1Init:
    SEP #$20
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[0].Count0
    STA.l C2Scene_HdmaTable[0].Count1
    TDC
    STA.l C2Scene_HdmaTable[0].End
    LDY.w #(!BBAD_WH0<<8)|!DMAP_HdmaIndirect|DMA_MODE_2BYTE
    STY.w DMAP1
    LDY.w #C2Scene_HdmaTable[0].Count0&$FFFF
    STY.w A1T1L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B
    LDA.b #DMA_CH1
    TSB.b !C2Scene_HdmaenShadow
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_EffectTask.Var24,X
C2Scene_Win1Step:                       ; header: see C2Scene_Win1Init
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var24,X
    LSR A
    REP #$20
    BCC .buf_a
    LDA.w #!C2Scene_LineBufB&$FFFF
    LDY.w #(!C2Scene_LineBufB+!C2Scene_LineBufHalf)&$FFFF
    BRA .set
.buf_a:
    LDA.w #!C2Scene_LineBufA&$FFFF
    LDY.w #(!C2Scene_LineBufA+!C2Scene_LineBufHalf)&$FFFF
.set:
    STA.l !C2Scene_HdmaValues
    STA.w !WinFx_TablePtr
    TYA
    STA.l !C2Scene_HdmaValues+2
    SEP #$20
    INC.w C2Scene_EffectTask.Var24,X
    LDA.w C2Scene_Task.SprX,X
    STA.w !WinFx_ArgX
    LDA.w C2Scene_Task.SprY,X
    STA.w !WinFx_ArgY
    LDA.w C2Scene_EffectTask.Var22,X
    STA.w !WinFx_ArgSize
    LDA.b #bank(!C2Scene_LineBufA)
    STA.w !WinFx_TableBank
    TDC                                 ; A = WinFx_Mode0
    JSL BankC3_Entry0008
    RTS

; $C2:7957 — C2Scene_Win2Init (42 bytes, $7957–$7980)
; Script routine (op $34 at $C3:A937): sets up C2Scene_HdmaTable[1] (two
; runs of 112 lines) as HDMA channel 2 to WH2/WH3 (indirect, two
; registers) and turns the channel on. Unlike C2Scene_Win1Init it leaves
; .Var24 alone and does not build a table (C2Scene_Win2Step does).
; Entry: M any (SEP #$20 here), X=0 (16-bit STY), DP=$0000
;        (C2Scene_HdmaenShadow), DB=$00 (the DMA registers)
; Exit:  M=1, X=0; A = DMA_CH2; Y = C2Scene_HdmaTable[1]'s address; X
;        unchanged
; No calls.
C2Scene_Win2Init:
    SEP #$20
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[1].Count0
    STA.l C2Scene_HdmaTable[1].Count1
    TDC
    STA.l C2Scene_HdmaTable[1].End
    LDY.w #(!BBAD_WH2<<8)|!DMAP_HdmaIndirect|DMA_MODE_2BYTE
    STY.w DMAP2
    LDY.w #C2Scene_HdmaTable[1].Count0&$FFFF
    STY.w A1T2L
    LDA.b #!Bank7E
    STA.w A1B2
    STA.w DAS2B
    LDA.b #DMA_CH2
    TSB.b !C2Scene_HdmaenShadow
    RTS

; $C2:7981 — C2Scene_Win2Step (71 bytes, $7981–$79C7)
; Script routine (op $34 at $C3:A93E, right after C2Scene_Win2Init's):
; adds one to .Var24 and picks C2Scene_LineBufD (now odd) or
; C2Scene_LineBufC (even) as WinFx_TablePtr (bank $7E), has
; BankC3_Entry0008 (A = WinFx_Mode1) build the window table there from
; .SprX, .SprY and .Var22 as C2Scene_Win1Step does, then points
; C2Scene_HdmaValues words 2-3 (C2Scene_HdmaTable[1]) at the buffer and
; its second half.
; Entry: M=1 (8-bit loads; op $34 calls it with M=1), X=0, DP=$0000,
;        DB=$00; C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the buffer + C2Scene_LineBufHalf; Y
;        as BankC3_Entry0008 leaves it; .Var24 + 1; WinFx_* and
;        C2Scene_HdmaValues words 2-3 changed
; Calls: BankC3_Entry0008 (JSL).
C2Scene_Win2Step:
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_EffectTask.Var24,X
    LDA.w C2Scene_EffectTask.Var24,X
    LSR A
    BCS .buf_d
    LDY.w #!C2Scene_LineBufC&$FFFF
    BRA .set
.buf_d:
    LDY.w #!C2Scene_LineBufD&$FFFF
.set:
    STY.w !WinFx_TablePtr
    LDA.b #bank(!C2Scene_LineBufC)
    STA.w !WinFx_TableBank
    LDA.w C2Scene_Task.SprX,X
    STA.w !WinFx_ArgX
    LDA.w C2Scene_Task.SprY,X
    STA.w !WinFx_ArgY
    LDA.w C2Scene_EffectTask.Var22,X
    STA.w !WinFx_ArgSize
    LDA.b #!WinFx_Mode1
    JSL BankC3_Entry0008
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w !WinFx_TablePtr
    STA.l !C2Scene_HdmaValues+4
    CLC
    ADC.w #!C2Scene_LineBufHalf
    STA.l !C2Scene_HdmaValues+6
    RTS

; $C2:79C8 — C2Scene_AddGravity (24 bytes, $79C8–$79DF)
; Script routine: adds 1/8 pixel a frame (C2Scene_GravityFrac) to the
; task's Y velocity (.YVelFrac, carrying into .YVel).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur), DB=$00
;        (the record); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .YVel; Y unchanged
; No calls.
C2Scene_AddGravity:
    REP #$20
    LDX.b !C2Scene_TaskCur
    CLC
    LDA.w C2Scene_Task.YVelFrac,X
    ADC.w #!C2Scene_GravityFrac
    STA.w C2Scene_Task.YVelFrac,X
    LDA.w C2Scene_Task.YVel,X
    ADC.w #0
    STA.w C2Scene_Task.YVel,X
    RTS

; $C2:79E0 — C2Scene_NudgeXRandom (44 bytes, $79E0–$7A0B)
; Script routine (op $34 at $C3:B792 and $C3:CB7E): moves the task right
; by a random 0-48 pixels: a random byte x C2Scene_NudgeRange / 256
; (WRMPYA/B), rounded up when the low byte of the product has bit 7 set.
; Entry: M=1 (8-bit multiply; C2Scene_Random leaves M=1), X=0,
;        DP=$0000, DB=$00 (the multiplier registers and the record);
;        C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .SprX; Y unchanged;
;        C2Scene_Unk1B30 + 1
; Calls: C2Scene_Random.
C2Scene_NudgeXRandom:
    JSR C2Scene_Random
    STA.w WRMPYA
    LDA.b #!C2Scene_NudgeRange
    STA.w WRMPYB
    NOP                                 ; the multiplier's 8 cycles
    NOP
    NOP
    NOP
    LDA.w RDMPYL
    BMI .round_up
    LDA.w RDMPYH
    BRA .add
.round_up:
    LDA.w RDMPYH
    INC A
.add:
    REP #$20
    LDX.b !C2Scene_TaskCur
    AND.w #!Eng_LowByteMask
    CLC
    ADC.w C2Scene_Task.SprX,X
    STA.w C2Scene_Task.SprX,X
    RTS

; $C2:7A0C — C2Scene_RandPosA (37 bytes with C2Scene_RandYA, $7A0C–$7A30)
; Script routine: .SprX = $220 + a random 0-255, then falls into the
; sub-entry C2Scene_RandYA ($C2:7A1F): .SprY = $38 + a random 0-255.
; Entry (both): M=1 (C2Scene_Random leaves M=1; SEP #$20 before the
;        sub-entry), X=0, DP=$0000, DB=$00 (the record and the random
;        index); C2Scene_TaskCur = the task
; Exit (both):  M=0, X=0; X = the task; A = the new .SprY; Y unchanged;
;        C2Scene_Unk1B30 + 2 (+1 through C2Scene_RandYA)
; Calls: C2Scene_Random.
C2Scene_RandPosA:
    JSR C2Scene_Random
    REP #$20
    LDX.b !C2Scene_TaskCur
    AND.w #!Eng_LowByteMask
    CLC
    ADC.w #!C2Scene_RandPosAX
    STA.w C2Scene_Task.SprX,X
    SEP #$20
C2Scene_RandYA:                         ; header: see C2Scene_RandPosA
    JSR C2Scene_Random
    REP #$20
    LDX.b !C2Scene_TaskCur
    AND.w #!Eng_LowByteMask
    CLC
    ADC.w #!C2Scene_RandPosAY
    STA.w C2Scene_Task.SprY,X
    RTS

; $C2:7A31 — C2Scene_RandPosB (37 bytes with C2Scene_RandYB, $7A31–$7A55)
; Script routine: as C2Scene_RandPosA with .SprX = $E0 + a random 0-255,
; falling into the sub-entry C2Scene_RandYB ($C2:7A44): .SprY = -$48 + a
; random 0-255.
; Entry (both): M=1, X=0, DP=$0000, DB=$00; C2Scene_TaskCur = the task
; Exit (both):  M=0, X=0; X = the task; A = the new .SprY; Y unchanged;
;        C2Scene_Unk1B30 + 2 (+1 through C2Scene_RandYB)
; Calls: C2Scene_Random.
C2Scene_RandPosB:
    JSR C2Scene_Random
    REP #$20
    LDX.b !C2Scene_TaskCur
    AND.w #!Eng_LowByteMask
    CLC
    ADC.w #!C2Scene_RandPosBX
    STA.w C2Scene_Task.SprX,X
    SEP #$20
C2Scene_RandYB:                         ; header: see C2Scene_RandPosB
    JSR C2Scene_Random
    REP #$20
    LDX.b !C2Scene_TaskCur
    AND.w #!Eng_LowByteMask
    CLC
    ADC.w #!C2Scene_RandPosBY
    STA.w C2Scene_Task.SprY,X
    RTS

; $C2:7A56 — C2Scene_NoiseInit (89 bytes, $7A56–$7AAE)
; Script routine (op $34 at $C3:C953): sets up C2Scene_HdmaTable[0]
; (two runs of 112 lines) as both HDMA channel 1 to BG1HOFS and channel
; 2 to BG2HOFS (indirect, one register twice: both layers get the same
; values) and turns them on. Fills C2Scene_LineBufA with the first $1C0
; bytes of ROM bank $C0 (code, used as noise) and C2Scene_LineBufB with
; C2Scene_Bg1HScroll on every line (one word stored, then copied up by
; an overlapping MVN).
; Quirk, kept: that MVN moves $1BF bytes, one more than the buffer's
; rest, so the low byte of the scroll also lands at $7E:8FB6, the byte
; after C2Scene_LineBufB. The table is pointed at a buffer by
; C2Scene_NoiseShow / NoiseHide / NoiseStep.
; Entry: M=1 (8-bit stores), X=0, DP=$0000 (C2Scene_Bg1HScroll,
;        C2Scene_HdmaenShadow), DB=$00 (the DMA registers; saved around
;        the MVNs)
; Exit:  M=0, X=0; A = $FFFF, X = $8FB5, Y = $8FB7 (the last MVN's
;        ends); DB unchanged
; No calls.
C2Scene_NoiseInit:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[0].Count0
    STA.l C2Scene_HdmaTable[0].Count1
    TDC
    STA.l C2Scene_HdmaTable[0].End
    LDY.w #(!BBAD_BG1HOFS<<8)|!DMAP_HdmaIndirect|DMA_MODE_1BYTE_X2
    STY.w DMAP1
    LDY.w #(!BBAD_BG2HOFS<<8)|!DMAP_HdmaIndirect|DMA_MODE_1BYTE_X2
    STY.w DMAP2
    LDY.w #C2Scene_HdmaTable[0].Count0&$FFFF
    STY.w A1T1L
    STY.w A1T2L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B
    STA.w A1B2
    STA.w DAS2B
    LDA.b #DMA_CH1|DMA_CH2
    TSB.b !C2Scene_HdmaenShadow
    REP #$20
    PHB
    LDX.w #0                            ; from $C0:0000
    LDY.w #!C2Scene_LineBufA&$FFFF
    LDA.w #!C2Scene_LineBufBytes-1
    MVN !Bank7E,!BankC0                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDA.b !C2Scene_Bg1HScroll
    STA.l !C2Scene_LineBufB
    LDX.w #!C2Scene_LineBufB&$FFFF
    LDY.w #(!C2Scene_LineBufB+2)&$FFFF
    LDA.w #!C2Scene_LineBufBytes-2      ; one byte too many (see the header)
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTS

; $C2:7AAF — C2Scene_NoiseStep (43 bytes, $7AAF–$7AD9)
; Script routine: moves both C2Scene_HdmaValues words 0-1 on by 32
; lines (C2Scene_NoiseStep bytes), back to C2Scene_LineBufA when they
; reach its end ($8D16), so the screen shows the next part of the noise
; (the second word can end up before the first; each wraps on its own).
; Entry: M any (REP #$20 here), X any, DP any, DB any (long addressing)
; Exit:  M=0; A = the new word 1; X, Y unchanged
; No calls.
C2Scene_NoiseStep:
    REP #$20
    LDA.l !C2Scene_HdmaValues
    CLC
    ADC.w #!C2Scene_NoiseStep
    CMP.w #(!C2Scene_LineBufA+!C2Scene_LineBufBytes)&$FFFF
    BCC .store0
    LDA.w #!C2Scene_LineBufA&$FFFF
.store0:
    STA.l !C2Scene_HdmaValues
    LDA.l !C2Scene_HdmaValues+2
    CLC
    ADC.w #!C2Scene_NoiseStep
    CMP.w #(!C2Scene_LineBufA+!C2Scene_LineBufBytes)&$FFFF
    BCC .store1
    LDA.w #!C2Scene_LineBufA&$FFFF
.store1:
    STA.l !C2Scene_HdmaValues+2
    RTS

; $C2:7ADA — C2Scene_NoiseShow (17 bytes, $7ADA–$7AEA)
; Script routine (op $34 at $C3:CA30): points C2Scene_HdmaValues words
; 0-1 at C2Scene_LineBufA and its second half (the noise).
; Entry: M any (REP #$20 here), X any, DP any, DB any (long stores)
; Exit:  M=0; A = the second address; X, Y unchanged
; No calls.
C2Scene_NoiseShow:
    REP #$20
    LDA.w #!C2Scene_LineBufA&$FFFF
    STA.l !C2Scene_HdmaValues
    LDA.w #(!C2Scene_LineBufA+!C2Scene_LineBufHalf)&$FFFF
    STA.l !C2Scene_HdmaValues+2
    RTS

; $C2:7AEB — C2Scene_NoiseHide (17 bytes, $7AEB–$7AFB)
; Script routine (no reference found): points C2Scene_HdmaValues words
; 0-1 at C2Scene_LineBufB and its second half (every line the plain
; C2Scene_Bg1HScroll that C2Scene_NoiseInit stored).
; Entry: M any (REP #$20 here), X any, DP any, DB any (long stores)
; Exit:  M=0; A = the second address; X, Y unchanged
; No calls.
C2Scene_NoiseHide:
    REP #$20
    LDA.w #!C2Scene_LineBufB&$FFFF
    STA.l !C2Scene_HdmaValues
    LDA.w #(!C2Scene_LineBufB+!C2Scene_LineBufHalf)&$FFFF
    STA.l !C2Scene_HdmaValues+2
    RTS

; $C2:7AFC — C2Scene_UnpackBgPack (36 bytes, $7AFC–$7B1F)
; Script routine (op $34 at $C3:A130 and $C3:C16E): unpacks the
; C2SceneRom_BgPacks entry at byte offset C2Tmp_08 (entry x 3, a word set
; by the script) into C2Scene_DecompBuf.
; Entry: M=1, X=0 (the 16-bit offset), DP=$0000 (C2Tmp_08), DB=$00
;        (Menu_Decomp*)
; Exit:  M=1, X=0; A, X, Y as Decomp_ToWramVec leaves them (not traced);
;        Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_UnpackBgPack:
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    LDX.b !C2Tmp_08
    REP #$20
    LDA.l !C2SceneRom_BgPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_BgPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTS

; $C2:7B20 — C2Scene_UnpackBg3MapPack (36 bytes, $7B20–$7B43)
; Script routine (no op $34 reference found): as C2Scene_UnpackBgPack
; from C2SceneRom_Bg3MapPacks.
; Entry: M=1, X=0, DP=$0000 (C2Tmp_08), DB=$00 (Menu_Decomp*)
; Exit:  M=1, X=0; A, X, Y as Decomp_ToWramVec leaves them (not traced);
;        Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C2Scene_UnpackBg3MapPack:
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDX.b !C2Tmp_08
    REP #$20
    LDA.l !C2SceneRom_Bg3MapPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_Bg3MapPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTS

; $C2:7B44 — C2Scene_SetUnk7F00AABit0 (11 bytes, $7B44–$7B4E)
; Script routine (op $34 at $C3:CCA3): sets bit 0 of C2Scene_Unk7F00AA
; (a byte of Menu_FlagBlock7F; what it means is not traced).
; Entry: M=1, X any, DP any, DB any (long addressing)
; Exit:  M=1; A = the new byte; X, Y unchanged
; No calls.
C2Scene_SetUnk7F00AABit0:
    LDA.l !C2Scene_Unk7F00AA
    ORA.b #!C2Scene_Unk7F00AABit0
    STA.l !C2Scene_Unk7F00AA
    RTS

; $C2:7B4F — C2Scene_SetUnk7F019ABit3 (11 bytes, $7B4F–$7B59)
; Script routine (op $34 at $C3:9238): sets bit 3 of C2Scene_Unk7F019A
; (Menu_FlagBlock7F; meaning not traced).
; Entry: M=1, X any, DP any, DB any (long addressing)
; Exit:  M=1; A = the new byte; X, Y unchanged
; No calls.
C2Scene_SetUnk7F019ABit3:
    LDA.l !C2Scene_Unk7F019A
    ORA.b #!C2Scene_Unk7F019ABit3
    STA.l !C2Scene_Unk7F019A
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
; More script routines and the BG2 line waves ($C2:7BC4–$C2:7DE3)
; ============================================================
; As the routines at $C2:754D-$C2:7B59: called by script op $34 from the
; bank $C3 scene scripts (M=1, X=0, DP=$0000, DB=$00, C2Scene_TaskCur =
; the task), the result, where there is one, in C2Tmp_00 for the
; script's next test.

; $C2:7BC4 — C2Scene_TestUnk7F00F7Bit1 (13 bytes, $7BC4–$7BD0)
; Script routine (op $34 at $C3:98F4): C2Tmp_00 = 1 when bit 1 of
; C2Scene_Unk7F00F7 is set, else 0.
; Entry: M=1 (8-bit), X any, DP=$0000 (C2Tmp_00), DB any (long read)
; Exit:  M=1; A = C2Scene_Unk7F00F7; C2Tmp_00 = 0 or 1; X, Y unchanged
; No calls.
C2Scene_TestUnk7F00F7Bit1:
    STZ.b !C2Tmp_00
    LDA.l !C2Scene_Unk7F00F7
    BIT.b #!C2Scene_Unk7F00F7Bit1
    BEQ .done
    INC.b !C2Tmp_00
.done:
    RTS

; $C2:7BD1 — C2Scene_SetConfig1E (7 bytes, $7BD1–$7BD7)
; Script routine (op $34 at $C3:B665 and $C3:C669): Menu_Config1E (the
; byte LocLoad_AudioSetup keeps the music track in) = C2Tmp_00.
; Entry: M=1, X any, DP=$0000 (C2Tmp_00), DB any (long store)
; Exit:  M=1; A = C2Tmp_00; X, Y unchanged
; No calls.
C2Scene_SetConfig1E:
    LDA.b !C2Tmp_00
    STA.l !Menu_Config1E
    RTS

; $C2:7BD8 — C2Scene_BuildPatternTiles (80 bytes, $7BD8–$7C27)
; Script routine (no op $34 reference found): builds ten 4bpp tiles at
; C2Scene_PatternTiles ($7F:9000, the unpack buffer): zeroes the first
; eight ($100 bytes) and sets the two after them (C2Scene_PatternSolid,
; $40 bytes) to $FF (colour 15), each by storing one byte and copying it
; up with an overlapping MVN; then writes the 32 bytes of
; C2Scene_PatternRows as bit plane 0 of the eight tiles, 8 rows per
; pair of tiles, both tiles of a pair alike. The patterns get denser
; from pair to pair (probably the steps of a dissolve; who uploads the
; tiles is not traced).
; The MVNs set DB to $7F, so the plane stores are absolute in bank $7F;
; DB is saved and restored around them.
; Entry: M=1 (8-bit stores), X=0 (16-bit addresses), DP=$0000 (TDC for
;        0), DB any (saved)
; Exit:  M=1, X=0; X = $20, Y = $9100 (the last tile pair's end + $30);
;        A = the last pattern byte; DB unchanged
; No calls.
C2Scene_BuildPatternTiles:
    TDC
    STA.l !C2Scene_PatternTiles
    LDA.b #!C2Scene_PatternAllSet
    STA.l !C2Scene_PatternSolid
    PHB
    REP #$20
    LDX.w #!C2Scene_PatternTiles&$FFFF
    TXY
    INY
    LDA.w #!C2Scene_PatternTileBytes-2
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!C2Scene_PatternSolid&$FFFF
    TXY
    INY
    LDA.w #!C2Scene_PatternSolidBytes-2
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    SEP #$20                            ; DB = $7F from here
    LDY.w #!C2Scene_PatternTiles&$FFFF
    LDX.w #0
.row:
    LDA.l C2Scene_PatternRows,X
    STA.w !Eng_PtrBase,Y                ; plane 0 of this row ...
    STA.w !Eng_PtrBase+!C2Scene_Tile4bppBytes,Y ; ... and of the same row of the next tile
    INX
    INY
    INY
    REP #$20
    TYA
    AND.w #!C2Scene_TilePlanes01Mask
    BNE .same_pair
    CLC                                 ; 8 rows done: on to the next pair
    TYA
    ADC.w #!C2Scene_PatternNextPair
    TAY
.same_pair:
    SEP #$20
    CPX.w #!C2Scene_PatternRowCount
    BCC .row
    PLB
    RTS

; $C2:7C28 — C2Scene_PatternRows (32 bytes, $7C28–$7C47)
; Bit plane 0 rows of the four tile pairs C2Scene_BuildPatternTiles
; builds, 8 rows per pair, sparse to full.
C2Scene_PatternRows:
    db $00,$00,$00,$00,$88,$00,$22,$00
    db $88,$22,$88,$22,$CC,$33,$CC,$33
    db $EE,$BB,$EE,$BB,$EE,$FF,$FB,$BF
    db $FF,$FF,$EF,$FF,$FF,$FF,$FF,$FF

; $C2:7C48 — C2Scene_SetUnk7F00CE (7 bytes, $7C48–$7C4E)
; Script routine (no op $34 reference found): C2Scene_Unk7F00CE =
; C2Tmp_00.
; Entry: M=1, X any, DP=$0000 (C2Tmp_00), DB any (long store)
; Exit:  M=1; A = C2Tmp_00; X, Y unchanged
; No calls.
C2Scene_SetUnk7F00CE:
    LDA.b !C2Tmp_00
    STA.l !C2Scene_Unk7F00CE
    RTS

; $C2:7C4F — C2Scene_SetUnk7F00DA (7 bytes, $7C4F–$7C55)
; Script routine (op $34 at $C3:C448): C2Scene_Unk7F00DA = C2Tmp_00.
; Entry: M=1, X any, DP=$0000 (C2Tmp_00), DB any (long store)
; Exit:  M=1; A = C2Tmp_00; X, Y unchanged
; No calls.
C2Scene_SetUnk7F00DA:
    LDA.b !C2Tmp_00
    STA.l !C2Scene_Unk7F00DA
    RTS

; $C2:7C56 — C2Scene_Bg2HWaveInit (65 bytes, $7C56–$7C96)
; Script routine (op $34 at $C3:C18F): sets up C2Scene_HdmaTable[0] (two
; runs of 112 lines) as HDMA channel 1 to BG2HOFS (indirect, one register
; twice) and turns it on, zeroes the buffer toggle .Var26 and zeroes
; $7E:8B56-$7E:8FB5 (C2Scene_LineBufA to the end of C2Scene_LineBufB,
; with the $E0 bytes between them) for C2Scene_Bg2HWaveStep.
; Entry: M=1 (8-bit stores), X=0, DP=$0000 (TDC for 0, the shadows),
;        DB=$00 (the DMA registers and the record; saved around the MVN)
; Exit:  M=0, X=0; A = $FFFF, X = $8FB5, Y = $8FB6 (the MVN's ends); DB
;        unchanged
; No calls.
C2Scene_Bg2HWaveInit:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[0].Count0
    STA.l C2Scene_HdmaTable[0].Count1
    TDC
    STA.l C2Scene_HdmaTable[0].End
    LDY.w #(!BBAD_BG2HOFS<<8)|!DMAP_HdmaIndirect|DMA_MODE_1BYTE_X2
    STY.w DMAP1
    LDY.w #C2Scene_HdmaTable[0].Count0&$FFFF
    STY.w A1T1L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B
    LDA.b #DMA_CH1
    TSB.b !C2Scene_HdmaenShadow
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_EffectTask.Var26,X
    REP #$20
    PHB
    TDC
    STA.l !C2Scene_LineBufA
    LDX.w #!C2Scene_LineBufA&$FFFF
    TXY
    INY
    LDA.w #(!C2Scene_LineBufB+!C2Scene_LineBufBytes-!C2Scene_LineBufA)-2
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTS

; $C2:7C97 — C2Scene_Bg2VWaveInit (65 bytes, $7C97–$7CD7)
; Script routine (no op $34 reference found): as C2Scene_Bg2HWaveInit
; for BG2VOFS: C2Scene_HdmaTable[1] as HDMA channel 2, zeroes .Var26 and
; $7E:9176-$7E:95D5 (C2Scene_LineBufC to the end of C2Scene_LineBufD)
; for C2Scene_Bg2VWaveStep.
; Entry: M=1, X=0, DP=$0000, DB=$00 (saved around the MVN)
; Exit:  M=0, X=0; A = $FFFF, X = $95D5, Y = $95D6; DB unchanged
; No calls.
C2Scene_Bg2VWaveInit:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[1].Count0
    STA.l C2Scene_HdmaTable[1].Count1
    TDC
    STA.l C2Scene_HdmaTable[1].End
    LDY.w #(!BBAD_BG2VOFS<<8)|!DMAP_HdmaIndirect|DMA_MODE_1BYTE_X2
    STY.w DMAP2
    LDY.w #C2Scene_HdmaTable[1].Count0&$FFFF
    STY.w A1T2L
    LDA.b #!Bank7E
    STA.w A1B2
    STA.w DAS2B
    LDA.b #DMA_CH2
    TSB.b !C2Scene_HdmaenShadow
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_EffectTask.Var26,X
    REP #$20
    PHB
    TDC
    STA.l !C2Scene_LineBufC
    LDX.w #!C2Scene_LineBufC&$FFFF
    TXY
    INY
    LDA.w #(!C2Scene_LineBufD+!C2Scene_LineBufBytes-!C2Scene_LineBufC)-2
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTS

; $C2:7CD8 — C2Scene_Bg2HWaveStep (134 bytes, $7CD8–$7D5D)
; Script routine (op $34 at $C3:C1A1, probably once a frame): one step of
; a wave that runs up BG2: adds one to .Var26 and, by its parity, shows
; C2Scene_LineBufA (now even) or C2Scene_LineBufB (odd) through
; C2Scene_HdmaValues words 0-1 and fills that buffer with the other one
; moved up a line (lines 0-222 from 1-223, by MVN); the new line 223 is
; sin(.Var24 + 16) x the amplitude .Var22 / 256 (Trig_Sin1024's
; magnitude times .Var22 with WRMPYA/B, the sign put back), and .Var24
; keeps the new phase. The value is the whole BG2HOFS (C2Scene_Bg2HScroll
; is not added).
; Entry: M any (SEP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur,
;        C2Tmp_10-$12), DB=$00 (the record and the multiplier; saved
;        around the MVN, which sets $7E); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; A = the new line's value; X = the sine; Y = the task;
;        C2Tmp_10-$12 = the new line's address; C as Trig_Sin1024 left
;        it (1 for the second half turn); DB unchanged
; Calls: Trig_Sin1024 (JSL).
C2Scene_Bg2HWaveStep:
    SEP #$20
    PHB
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_EffectTask.Var26,X
    LDA.w C2Scene_EffectTask.Var26,X
    LSR A
    REP #$20
    BCS .buf_b
    LDA.w #!C2Scene_LineBufA&$FFFF
    STA.l !C2Scene_HdmaValues
    LDA.w #(!C2Scene_LineBufA+!C2Scene_LineBufHalf)&$FFFF
    STA.l !C2Scene_HdmaValues+2
    LDX.w #(!C2Scene_LineBufB+2)&$FFFF
    LDY.w #!C2Scene_LineBufA&$FFFF
    LDA.w #!C2Scene_LineBufBytes-2-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #(!C2Scene_LineBufA+!C2Scene_LineBufBytes-2)&$FFFF
    BRA .new_line
.buf_b:
    LDA.w #!C2Scene_LineBufB&$FFFF
    STA.l !C2Scene_HdmaValues
    LDA.w #(!C2Scene_LineBufB+!C2Scene_LineBufHalf)&$FFFF
    STA.l !C2Scene_HdmaValues+2
    LDX.w #(!C2Scene_LineBufA+2)&$FFFF
    LDY.w #!C2Scene_LineBufB&$FFFF
    LDA.w #!C2Scene_LineBufBytes-2-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #(!C2Scene_LineBufB+!C2Scene_LineBufBytes-2)&$FFFF
.new_line:
    STY.b !C2Tmp_10
    PLB
    LDY.b !C2Scene_TaskCur
    CLC
    LDA.w C2Scene_EffectTask.Var24,Y
    ADC.w #!C2Scene_WaveLineStep
    STA.w C2Scene_EffectTask.Var24,Y
    JSL Trig_Sin1024
    TAX
    PHP                                 ; keep the sign
    BPL .magnitude
    EOR.w #!Eng_Invert16
    INC A
.magnitude:
    SEP #$20
    STA.w WRMPYA
    LDA.w C2Scene_EffectTask.Var22,Y
    STA.w WRMPYB
    LDA.b #bank(!C2Scene_LineBufA)
    STA.b !C2Tmp_12
    TDC                                 ; B = 0: the 8-bit load below gives a word
    LDA.w RDMPYH
    REP #$20
    PLP
    BPL .store
    EOR.w #!Eng_Invert16
    INC A
.store:
    STA.b [!C2Tmp_10]
    RTS

; $C2:7D5E — C2Scene_Bg2VWaveStep (134 bytes, $7D5E–$7DE3)
; Script routine (no op $34 reference found): C2Scene_Bg2HWaveStep for
; BG2VOFS: C2Scene_LineBufC (even) or C2Scene_LineBufD (odd) through
; C2Scene_HdmaValues words 2-3 (C2Scene_HdmaTable[1]).
; Entry: M any (SEP #$20 here), X=0, DP=$0000, DB=$00 (saved around the
;        MVN); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; A = the new line's value; X = the sine; Y = the task;
;        C2Tmp_10-$12 = the new line's address; C as Trig_Sin1024 left
;        it; DB unchanged
; Calls: Trig_Sin1024 (JSL).
C2Scene_Bg2VWaveStep:
    SEP #$20
    PHB
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_EffectTask.Var26,X
    LDA.w C2Scene_EffectTask.Var26,X
    LSR A
    REP #$20
    BCS .buf_d
    LDA.w #!C2Scene_LineBufC&$FFFF
    STA.l !C2Scene_HdmaValues+4
    LDA.w #(!C2Scene_LineBufC+!C2Scene_LineBufHalf)&$FFFF
    STA.l !C2Scene_HdmaValues+6
    LDX.w #(!C2Scene_LineBufD+2)&$FFFF
    LDY.w #!C2Scene_LineBufC&$FFFF
    LDA.w #!C2Scene_LineBufBytes-2-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #(!C2Scene_LineBufC+!C2Scene_LineBufBytes-2)&$FFFF
    BRA .new_line
.buf_d:
    LDA.w #!C2Scene_LineBufD&$FFFF
    STA.l !C2Scene_HdmaValues+4
    LDA.w #(!C2Scene_LineBufD+!C2Scene_LineBufHalf)&$FFFF
    STA.l !C2Scene_HdmaValues+6
    LDX.w #(!C2Scene_LineBufC+2)&$FFFF
    LDY.w #!C2Scene_LineBufD&$FFFF
    LDA.w #!C2Scene_LineBufBytes-2-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #(!C2Scene_LineBufD+!C2Scene_LineBufBytes-2)&$FFFF
.new_line:
    STY.b !C2Tmp_10
    PLB
    LDY.b !C2Scene_TaskCur
    CLC
    LDA.w C2Scene_EffectTask.Var24,Y
    ADC.w #!C2Scene_WaveLineStep
    STA.w C2Scene_EffectTask.Var24,Y
    JSL Trig_Sin1024
    TAX
    PHP
    BPL .magnitude
    EOR.w #!Eng_Invert16
    INC A
.magnitude:
    SEP #$20
    STA.w WRMPYA
    LDA.w C2Scene_EffectTask.Var22,Y
    STA.w WRMPYB
    LDA.b #bank(!C2Scene_LineBufC)
    STA.b !C2Tmp_12
    TDC
    LDA.w RDMPYH
    REP #$20
    PLP
    BPL .store
    EOR.w #!Eng_Invert16
    INC A
.store:
    STA.b [!C2Tmp_10]
    RTS

; $C2:7DE4 — BankC2_FreeSpace7DE4 (540 bytes, $7DE4–$7FFF)
; $FF fill up to $C2:8000, where the menu part of the bank starts
; (BankC2_Entry8000). Not code; nothing reads it.
BankC2_FreeSpace7DE4:
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF


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
; Callers of BankC2_Entry8004 (15 JSL sites): GameLoop ($C0:0059), Evt_OpD7_GetItemCount ($C0:3807),
;   Evt_OpCF_IfCharListed ($C0:389B), Evt_OpD0_AddCharToReserve ($C0:38CC), Evt_OpD1_UnlistChar
;   ($C0:38E1), Evt_OpD2_IfCharInParty ($C0:38F6), Evt_OpD3_AddCharToParty ($C0:392B),
;   Evt_OpD4_MoveCharToReserve ($C0:39DA), Evt_OpD5_BankC2Cmd0A ($C0:3A7C),
;   Evt_OpF8_BankC2Cmd06And07 ($C0:3E61), Evt_BankC2CmdTail ($C0:3E67), Scene_PostLoadInit
;   ($C0:56CF) and unmatched ($FF:FB84, $FF:FB92, $FF:FB98).
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
