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
; (C2Scene_ClearDp), the NMI/IRQ trampolines (C2Scene_InstallInterrupts),
; an empty VRAM queue (C2Scene_VramQInit) and a black palette
; (C2Scene_ClearPalette), and jumps into C2Scene_Main, which does not
; come back here.
; Callers: JMP from BankC2_Entry0000 ($C2:0000).
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
; its shadow and brightness and HDMAEN from its shadow; then rebuild the
; sprites: empty the sprite list (C2Scene_SprResetLists), zero
; C2Scene_OamNext, hide every sprite (C2Scene_HideAllSprites), run the
; tasks (C2Scene_TaskRunAll, which add sprite nodes) and draw the list
; into the OAM shadow (C2Scene_SprDrawList), for the next NMI's DMA; and
; set bit 0 again. C2Scene_SprResetLists returns with M=0, so the STZ of
; C2Scene_OamNext is a 16-bit store that zeroes $4E (C2Scene_TaskCur)
; as well.
; Callers: none (an interrupt handler, entered through the trampoline).
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
; Callers (6 JSR sites): BankC2_SceneBoot ($C2:003A); unmatched: $C2:2560,
;   $C2:25F0, $C2:265B, $C2:6331 and $C2:6A37.
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
; Callers (6 JSR sites, unmatched): $C2:2582, $C2:2612, $C2:269D,
;   $C2:63C7, $C2:6A99 and $C2:6AB1.
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
; Callers (3 JSR sites): C2Scene_Main ($C2:23CF, in C2Scene_MainLoop);
;   unmatched: $C2:63BA and $C2:6A9C.
; Entry/Exit: those of C2Scene_WaitFrame.
C2Scene_WaitOneFrame:
    JMP C2Scene_WaitFrame

; $C2:0471 — C2Scene_TaskClearAll (25 bytes, $0471–$0489)
; Frees all 64 task records (zeroes each .Handler) and points
; C2Scene_TaskCur at the first record, so that tasks spawned before any
; task runs copy their parameters from record 0.
; Callers (3 JSR sites): C2Scene_Main ($C2:23B1); unmatched: $C2:6334 and
;   $C2:6A3A.
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
; Callers (13 JSR sites): C2Scene_TaskSpawnScript ($C2:04E0); unmatched:
;   $C2:10C4, $C2:10F7, $C2:1590, $C2:159E, $C2:15AC, $C2:15BA, $C2:183F,
;   $C2:1DE2, $C2:63A6, $C2:7417, $C2:742D and $C2:7441.
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
; Callers (2 JSR sites): C2Scene_TaskSpawnScriptLow ($C2:0502); unmatched:
;   $C2:1A49.
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
; Callers (21 JSR/JMP sites): C2Scene_LoadScene (JMP at $C2:2C90);
;   unmatched: $C2:1203, $C2:242E, $C2:2459, $C2:2527, $C2:256B, $C2:2596,
;   $C2:25FB, $C2:2626, $C2:2676, $C2:3154, $C2:33B2, $C2:33DF, $C2:4479, $C2:452C,
;   $C2:63AE, $C2:66DF, $C2:66FF, $C2:6AAB, $C2:741F and $C2:7427.
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
; Callers (1 JSR site, unmatched): $C2:1A3A.
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
; definitions are in bank $7E. Read by C2Scene_DrawBgLayer and by
; unmatched code at $C2:0576 and $C2:067A. Layer 1's set is the one
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
; 2's follows it at +$1800. Read by C2Scene_DrawBgLayer and unmatched code
; at $C2:057C, $C2:0680 and $C2:1176.
C2Scene_LayerMaps:
    dw $4000                    ; 1: C2Scene_BgMaps
    dw $5800                    ; 2
    dw $7000                    ; 3

; $C2:0562 — C2Scene_LayerVramMaps (3 words, $0562–$0567)
; Per layer: the VRAM word address of its tilemap. 1 and 2 are the BG1SC
; and BG2SC bases BankC2_InitHwRegs sets ($6000, $6800); 3's $7000 is
; where the BG3 tiles go, not the BG3 map ($7800), so layer 3 is probably
; not drawn this way. Read by C2Scene_DrawBgLayer and unmatched code at
; $C2:0582 and $C2:0686.
C2Scene_LayerVramMaps:
    dw $6000                    ; 1: BG1 map
    dw $6800                    ; 2: BG2 map
    dw $7000                    ; 3

; ============================================================
; Scene BG layer redraw ($C2:09C5–$C2:0B52)
; ============================================================
; A BG layer's tilemap is built from 16x16 metatiles: the layer's map
; (C2Scene_LayerMaps) holds a metatile number per cell, and each
; metatile (C2Scene_LayerMetatiles) is four tile words. A redraw builds
; the tilemap column by column in the buffer at C2Scene_VramQBufPtr and
; DMAs each column to VRAM straight away, so it needs forced blank or
; vblank (its callers are the scene setup, under forced blank, and the
; unmatched script code at $C2:1950).

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
; passes 3 (C2Scene_LoadScene and C2Scene_ReloadScene pass 1 and 2; the
; unmatched caller passes a script byte).
; Callers (5 sites): C2Scene_LoadScene ($C2:2C81, $C2:2C88),
;   C2Scene_ReloadScene ($C2:2CB7, JMP at $C2:2CBE); unmatched: $C2:1950.
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
; Callers (1 JSR site, unmatched): $C2:0ED6.
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
; Callers: JMP from BankC2_SceneBoot ($C2:0040). C2Scene_MainLoop: from
;   C2Scene_ModeIdle and the unmatched mode handlers (JMP at $C2:244F,
;   $C2:258A, $C2:261A and $C2:26A5).
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
; are unmatched; what they show is not traced (4, for one, turns the NMI
; off and loops on C2Scene_RestoreFlagTail for good).
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
; Callers: none direct (C2Scene_ModeTable).
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

org $C226A8
; $C2:26A8 — C2Scene_ClearVram (44 bytes, $26A8–$26D3)
; Zeroes all of VRAM with one DMA on channel 7: word writes to
; VMDATAL/H from the fixed source C2Scene_ZeroWord, VRAM address 0, a
; byte count of 0 (= 65536 bytes). Needs forced blank, which the boot has
; set.
; Callers (3 JSR sites): C2Scene_Main ($C2:23A8); unmatched: $C2:632E and
;   $C2:6A34.
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
; Callers (2 JSR sites, unmatched): $C2:24E0 (C2Scene_Mode2) and $C2:2518
;   (C2Scene_Mode4).
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
; Callers: JMP from C2Scene_LoadVram ($C2:2D6D).
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
; Callers (2 JSR sites): C2Scene_LoadVram ($C2:2CDF); unmatched: $C2:63DF.
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
; Callers (2 JSR sites): C2Scene_LoadPalettes ($C2:28D9, $C2:28E3; it
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
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C74), C2Scene_ReloadScene
;   ($C2:2CAD).
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
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C77), C2Scene_ReloadScene
;   ($C2:2CB0).
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
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C62), C2Scene_ReloadScene
;   ($C2:2CA7).
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
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C68), C2Scene_ReloadScene
;   ($C2:2CAA).
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
; Callers (3 JSR sites): C2Scene_LoadPartyGfx ($C2:2B87, $C2:2B9B,
;   $C2:2BAF).
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
; Callers (3 sites): C2Scene_LoadPartyGfx ($C2:2B91, $C2:2BA5; JMP at
;   $C2:2BB9).
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
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C7A), C2Scene_ReloadScene
;   ($C2:2C96).
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
; calls it too, from the unmatched
; callers' addresses): C2Scene_Unk5775, the HDMA area cleared and
; C2Scene_HdmaValueA916 = C2Scene_HdmaValueA916Init, then the VRAM and
; palette loads (C2Scene_LoadVram), the metatiles, the Unk7000, UnkB800
; and UnkC000 packs, and BG layers 1 and 2 redrawn. The maps and lists
; are not reloaded: C2Scene_SaveState keeps them, and the header pointer
; with the direct page.
; Callers (3 JSR sites, unmatched): $C2:2563, $C2:25F3 and $C2:266E.
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
; Callers (2 JSR sites): C2Scene_LoadScene ($C2:2C5F), C2Scene_ReloadScene
;   ($C2:2CA4).
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
; Callers (9 JSR sites): C2Scene_LoadVram ($C2:2CCD, $C2:2CDC, $C2:2CEB,
;   $C2:2CFC, $C2:2D0D), C2Scene_LoadLocExtraGfx ($C2:2DBF, $C2:2DDB,
;   $C2:2E01, $C2:2E1D).
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
; from the unmatched callers: scene modes 5 and 8 save, do something
; else and restore; mode 5 then reloads, mode 8 only when the flag test
; at $C2:265E passes.
; Callers (2 JSR sites, unmatched): $C2:2542 (C2Scene_Mode5) and $C2:2652
;   (C2Scene_Mode8).
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
; Callers (2 JSR sites, unmatched): $C2:255D (C2Scene_Mode5) and $C2:2658
;   (C2Scene_Mode8).
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
; Callers: JMP from BankC2_Entry0003 ($C2:0003) and BankC2_Entry0006
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
; Callers: JMP from BankC2_Entry0009 ($C2:0009) and BankC2_Entry000C
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
; Callers: none direct (TextWin_StatusTable).
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
; Callers: none direct (TextWin_StatusTable).
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
; Scene extra-graphics loaders ($C2:7B5A–$C2:7BC3)
; ============================================================
; Three fixed-entry pack loaders used only by C2Scene_LoadLocExtraGfx.

org $C27B5A
; $C2:7B5A — C2Scene_LoadExtraObjPack (37 bytes, $7B5A–$7B7E)
; Unpacks entry C2Scene_ExtraObjPack of C2SceneRom_ObjPacks into
; C2Scene_DecompBuf.
; Callers (4 JSR sites): C2Scene_LoadLocExtraGfx ($C2:2DB1, $C2:2DCD,
;   $C2:2DF3, $C2:2E0F).
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
; Callers (3 JSR sites):
;   C2Scene_LoadLocExtraGfx ($C2:2DC7, $C2:2DED, $C2:2E09).
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
; Callers (JMP, 4 sites): C2Scene_LoadLocExtraGfx ($C2:2DCA, $C2:2DF0,
;   $C2:2E0C, $C2:2E20).
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
; Callers: BankC2_Entry8000 (JSL): Field_SceneChangeTick ($C0:0D18),
;   Field_PauseAndMenuInput ($C0:1960), Field_RunBankC2Mode5 ($C0:19CE)
;   and $C2:2552 (unmatched). BankC2_Entry8002 (JSL): C2Scene_NmiHandler
;   ($C2:031B); unmatched: $C0:EC15, $C1:EE27, $CD:091A and $CD:09C6.
;   BankC2_Entry8004 (15 JSL sites): GameLoop ($C0:0059); unmatched:
;   $C0:3807, $C0:389B, $C0:38CC, $C0:38E1, $C0:38F6, $C0:392B, $C0:39DA,
;   $C0:3A7C, $C0:3E61, $C0:3E67, $C0:56CF, $FF:FB84, $FF:FB92 and
;   $FF:FB98.
; Entry/Exit: those of the routine each vector reaches.
BankC2_Entry8000:
    BRA BankC2_MenuEntry
BankC2_Entry8002:               ; header: see BankC2_Entry8000
    BRA BankC2_ReadPadLong
BankC2_Entry8004:               ; header: see BankC2_Entry8000
    BRA BankC2_CommandLong

; $C2:8006 — BankC2_ReadPadLong (4 bytes, $8006–$8009)
; Menu_ReadPad as a long call (the BankC2_Entry8002 vector).
; Callers: none direct (BRA from BankC2_Entry8002).
; Entry/Exit: as Menu_ReadPad (everything preserved), returning with RTL
; Calls: Menu_ReadPad.
BankC2_ReadPadLong:
    JSR Menu_ReadPad
    RTL

; $C2:800A — BankC2_CommandLong (4 bytes, $800A–$800D)
; Menu_Unk8C36 as a long call (the BankC2_Entry8004 vector).
; Callers: none direct (BRA from BankC2_Entry8004).
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
; Callers (2 JSR sites): Menu_ReadPad ($C2:84DB); unmatched: $C2:8487
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
; Callers (1 JSR site): Menu_ReadPad ($C2:84DE). Menu_MapButtonsOne: JSR
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
; Callers (2 JSR sites): Menu_ReadPad ($C2:84E1); unmatched: $C2:8490
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
