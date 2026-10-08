; ============================================================
; Bank $FD — Main hardware initialization + engine jump
;
; The entry point of this bank is MainInit ($FD:C000), jumped to
; from the reset routine in bank $00 (JML $FDC000 at $00:FF03).
;
; MainInit puts the CPU and PPU into a known state in five steps:
;   1.  CPU mode, stack, data bank, DP=$4200   ($FD:C000–$C013)
;   2.  CPU I/O registers through DP=$4200     ($FD:C014–$C035)
;   3.  DP=$2100, screen into forced blank     ($FD:C036–$C041)
;   4.  PPU registers through DP=$2100         ($FD:C042–$C0D2)
;   5.  Long jump into the engine at $C0:000E  ($FD:C0D3–$C0D6)
;
; Total: 215 bytes ($FD:C000–$C0D6 inclusive).
; ============================================================

arch snes.cpu
hirom

incsrc "../hardware.inc"

; ============================================================
; MainInit ($FD:C000)
; Called via: JML from Reset ($00:FF03)
; Entry: native mode, M=1 X=1, D=$0000, DB=$00
; Exit:  (jumps, never returns) M=1 X=0, D=$2100, DB=$00, S=$06FF,
;        screen in forced blank, NMI/IRQ/DMA/HDMA off
;
; Every register write goes through a relocated direct page so each
; store is two bytes: first DP=$4200 for the CPU I/O block, then
; DP=$2100 for the PPU. Most registers are simply zeroed; the few
; non-zero values are named in hardware.inc.
; ============================================================
org $FDC000

MainInit:

    ; Step 1 — 16-bit index, 8-bit A; S=$06FF (the top of page $06,
    ; growing down); data bank 0; DP onto the CPU I/O registers.
    REP #$10
    SEP #$20
    LDX.w #!StackTop
    TXS
    LDA #$00
    PHA
    PLB
    REP #$20
    LDA.w #!DP_CPU
    TCD
    SEP #$20

    ; Step 2 — FastROM on; NMI, IRQ, auto-joypad, DMA and HDMA off;
    ; multiplier, divider and H/V timers zeroed; I/O port pins high.
    LDA.b #!MEMSEL_FastRom
    STA.b MEMSEL-!DP_CPU
    LDA #$00
    STA.b NMITIMEN-!DP_CPU
    STA.b MDMAEN-!DP_CPU
    STA.b HDMAEN-!DP_CPU
    STA.b WRMPYA-!DP_CPU
    STA.b WRMPYB-!DP_CPU
    STA.b WRDIVL-!DP_CPU
    STA.b WRDIVH-!DP_CPU
    STA.b WRDIVB-!DP_CPU
    STA.b HTIMEL-!DP_CPU
    STA.b HTIMEH-!DP_CPU
    STA.b VTIMEL-!DP_CPU
    STA.b VTIMEH-!DP_CPU
    LDA.b #!WRIO_AllHigh
    STA.b WRIO-!DP_CPU

    ; Step 3 — DP onto the PPU registers; screen off so VRAM, CGRAM and
    ; OAM can be written freely.
    REP #$20
    LDA.w #!DP_PPU
    TCD
    SEP #$20
    LDA.b #FORCED_BLANK
    STA.b INIDISP-!DP_PPU

    ; Step 4 — PPU. Sprite size/base and BG mode get real values; tilemap
    ; and character bases, scroll, VRAM address and color math start at 0
    ; and are set per scene later.
    LDA.b #!OBSEL_Size16x32_Base6000
    STA.b OBSEL-!DP_PPU
    LDA #$00
    STA.b OAMADDL-!DP_PPU
    STA.b OAMADDH-!DP_PPU
    LDA.b #BG_MODE_1|BG3_HIGH_PRIO
    STA.b BGMODE-!DP_PPU
    LDA #$00
    STA.b MOSAIC-!DP_PPU
    STA.b BG1SC-!DP_PPU
    STA.b BG2SC-!DP_PPU
    STA.b BG3SC-!DP_PPU
    STA.b BG4SC-!DP_PPU
    STA.b BG12NBA-!DP_PPU
    STA.b BG34NBA-!DP_PPU

    ; Scroll registers are write-twice (low byte, then high byte), hence
    ; each pair of stores.
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

    ; VMAIN = 0 is VRAM_INC_1 (step one word after the low byte); VRAM
    ; address $0000.
    STA.b VMAIN-!DP_PPU
    STA.b VMADDL-!DP_PPU
    STA.b VMADDH-!DP_PPU

    ; Mode 7 matrix to identity. Each element is write-twice: the first
    ; store is the low byte, the second the high byte, so A=$0100 (1.0)
    ; and D=$0100, B=C=0, centre (0,0). A is stepped with INC/DEC between
    ; the 0 and 1 high bytes instead of reloading.
    STA.b M7SEL-!DP_PPU
    STA.b M7A-!DP_PPU
    LDA #$01
    STA.b M7A-!DP_PPU
    DEC
    STA.b M7B-!DP_PPU
    STA.b M7B-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7D-!DP_PPU
    INC
    STA.b M7D-!DP_PPU
    DEC
    STA.b M7X-!DP_PPU
    STA.b M7X-!DP_PPU
    STA.b M7Y-!DP_PPU
    STA.b M7Y-!DP_PPU

    STA.b CGADD-!DP_PPU

    ; Windows. W34SEL gets BG3 window 1 enable+invert, but no layer has
    ; windowing turned on (TMW = TSW = 0 below), so the setting has no
    ; visible effect yet. Why it is set here is unknown; presumably a
    ; later scene enables BG3 masking and relies on it.
    STA.b W12SEL-!DP_PPU
    LDA.b #!W34SEL_Bg3Win1Inv
    STA.b W34SEL-!DP_PPU
    LDA #$00
    STA.b WOBJSEL-!DP_PPU
    STA.b WH0-!DP_PPU
    STA.b WH1-!DP_PPU
    STA.b WH2-!DP_PPU
    STA.b WH3-!DP_PPU
    STA.b WBGLOG-!DP_PPU
    STA.b WOBJLOG-!DP_PPU
    STA.b TMW-!DP_PPU
    STA.b TSW-!DP_PPU

    ; Color math off.
    STA.b CGWSEL-!DP_PPU
    STA.b CGADSUB-!DP_PPU

    ; Layer enables: all BGs and sprites on, main and sub screen
    ; (overridden per scene).
    LDA.b #!TM_AllLayers
    STA.b TM-!DP_PPU
    STA.b TS-!DP_PPU

    ; Fixed color: green and blue set to 0. Red is not written here and
    ; keeps whatever value it had.
    LDA.b #!COLDATA_GreenBlueZero
    STA.b COLDATA-!DP_PPU

    ; No interlace, overscan or external sync.
    LDA #$00
    STA.b SETINI-!DP_PPU

    ; Step 5 — into the engine.
    JML GameLoop        ; $C0:000E (see the open question on this label in STATUS.md)
