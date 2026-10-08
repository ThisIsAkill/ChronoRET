; ============================================================
; Bank $FD — Main hardware initialization + engine jump
;
; The entry point of this bank is MainInit ($FD:C000), jumped to
; from the reset routine in bank $00 (JML $FDC000 at $00:FF03).
;
; MainInit performs a complete hardware register init in four phases:
;   1.  CPU mode setup  ($FD:C000–$C011)
;   2.  CPU register init with DP=$4200 ($FD:C012–$C035)
;   3.  DP switch to $2100 + INIDISP forced blank ($FD:C036–$C041)
;   4.  PPU register init ($FD:C042–$C0D2)
;   5.  Long jump to main engine loop at $C0:000E ($FD:C0D3)
;
; Total: 215 bytes ($FD:C000–$C0D6 inclusive).
; ============================================================

arch snes.cpu
hirom

incsrc "../hardware.inc"

; ============================================================
; MainInit — hardware initialization
; File offset: $3DC000 | SNES $FD:C000
; Called via: JML from Reset ($00:FF03)
; On entry: native 65816 mode, M=1, X=1, E=0
; ============================================================
org $FDC000

MainInit:

; ----------------------------------------------------------
; Phase 1: CPU mode and register setup
; Set 16-bit index, 8-bit accumulator, establish stack
; pointer, data bank, and direct page.
; ----------------------------------------------------------
    REP #$10            ; X/Y → 16-bit (clear X flag)
    SEP #$20            ; A   →  8-bit (set M flag)

    LDX.w #!StackTop    ; stack base: $0700 page (16-bit X)
    TXS                 ; S = $06FF

    LDA #$00
    PHA
    PLB                 ; data bank register B = $00

    REP #$20            ; A → 16-bit
    LDA.w #!DP_CPU      ; DP → CPU register area ($4200–$420F)
    TCD
    SEP #$20            ; A → 8-bit

; ----------------------------------------------------------
; Phase 2: CPU register init  (DP = $4200)
; Disable IRQ/NMI, DMA/HDMA; select FastROM; zero math regs.
; All writes are 8-bit via DP-relative addressing.
; ----------------------------------------------------------
    LDA.b #!MEMSEL_FastRom
    STA.b MEMSEL-!DP_CPU ; MEMSEL  = $01 → FastROM (3.58 MHz ROM access)

    LDA #$00
    STA.b NMITIMEN-!DP_CPU ; NMITIMEN = $00 → disable NMI, IRQ, auto-joypad
    STA.b MDMAEN-!DP_CPU ; MDMAEN  = $00 → disable all DMA channels
    STA.b HDMAEN-!DP_CPU ; HDMAEN  = $00 → disable all HDMA channels
    STA.b WRMPYA-!DP_CPU ; WRMPYA  = $00 (multiply operand A)
    STA.b WRMPYB-!DP_CPU ; WRMPYB  = $00 (multiply operand B)
    STA.b WRDIVL-!DP_CPU ; WRDIVL  = $00 (dividend low)
    STA.b WRDIVH-!DP_CPU ; WRDIVH  = $00 (dividend high)
    STA.b WRDIVB-!DP_CPU ; WRDIVB  = $00 (divisor)
    STA.b HTIMEL-!DP_CPU ; HTIMEL  = $00 (H-count timer low)
    STA.b HTIMEH-!DP_CPU ; HTIMEH  = $00 (H-count timer high)
    STA.b VTIMEL-!DP_CPU ; VTIMEL  = $00 (V-count timer low)
    STA.b VTIMEH-!DP_CPU ; VTIMEH  = $00 (V-count timer high)

    LDA.b #!WRIO_AllHigh
    STA.b WRIO-!DP_CPU  ; WRIO    = $FF → all programmable I/O pins high

; ----------------------------------------------------------
; Phase 3: Switch DP to PPU register area; force blank
; ----------------------------------------------------------
    REP #$20            ; A → 16-bit
    LDA.w #!DP_PPU      ; DP → PPU register area ($2100–$2133)
    TCD
    SEP #$20            ; A → 8-bit

    LDA.b #!INIDISP_ForcedBlank
    STA.b INIDISP-!DP_PPU ; INIDISP = $80 → forced blank (screen disabled)

; ----------------------------------------------------------
; Phase 4: PPU register init  (DP = $2100)
; Initialize all relevant PPU registers to known state.
; ----------------------------------------------------------

    ; OAM
    LDA.b #!OBSEL_Init
    STA.b OBSEL-!DP_PPU ; OBSEL   = 16x16/32x32 sprites, tiles at VRAM $6000
    LDA #$00
    STA.b OAMADDL-!DP_PPU ; OAMADDL = $00 (OAM address low)
    STA.b OAMADDH-!DP_PPU ; OAMADDH = $00 (OAM address high, priority=0)

    ; BG mode
    LDA.b #!BGMODE_Mode1Bg3Prio
    STA.b BGMODE-!DP_PPU ; BGMODE  = $09 → Mode 1 (001), BG3 high priority (bit3)

    ; BG tilemap/character addresses — zeroed (set at runtime)
    LDA #$00
    STA.b MOSAIC-!DP_PPU ; MOSAIC  = $00 (mosaic off)
    STA.b BG1SC-!DP_PPU ; BG1SC   = $00 (tilemap base addr + size)
    STA.b BG2SC-!DP_PPU ; BG2SC   = $00
    STA.b BG3SC-!DP_PPU ; BG3SC   = $00
    STA.b BG4SC-!DP_PPU ; BG4SC   = $00
    STA.b BG12NBA-!DP_PPU ; BG12NBA = $00 (BG1/2 chr base)
    STA.b BG34NBA-!DP_PPU ; BG34NBA = $00 (BG3/4 chr base)

    ; BG scroll registers — double-write each (lo then hi byte)
    STA.b BG1HOFS-!DP_PPU ; BG1HOFS write 1 = $00
    STA.b BG1HOFS-!DP_PPU ; BG1HOFS write 2 = $00  → BG1 H-scroll = 0
    STA.b BG1VOFS-!DP_PPU ; BG1VOFS write 1 = $00
    STA.b BG1VOFS-!DP_PPU ; BG1VOFS write 2 = $00  → BG1 V-scroll = 0
    STA.b BG2HOFS-!DP_PPU ; BG2HOFS write 1 = $00
    STA.b BG2HOFS-!DP_PPU ; BG2HOFS write 2 = $00
    STA.b BG2VOFS-!DP_PPU ; BG2VOFS write 1 = $00
    STA.b BG2VOFS-!DP_PPU ; BG2VOFS write 2 = $00
    STA.b BG3HOFS-!DP_PPU ; BG3HOFS write 1 = $00
    STA.b BG3HOFS-!DP_PPU ; BG3HOFS write 2 = $00
    STA.b BG3VOFS-!DP_PPU ; BG3VOFS write 1 = $00
    STA.b BG3VOFS-!DP_PPU ; BG3VOFS write 2 = $00
    STA.b BG4HOFS-!DP_PPU ; BG4HOFS write 1 = $00
    STA.b BG4HOFS-!DP_PPU ; BG4HOFS write 2 = $00
    STA.b BG4VOFS-!DP_PPU ; BG4VOFS write 1 = $00
    STA.b BG4VOFS-!DP_PPU ; BG4VOFS write 2 = $00

    ; VRAM address and increment
    STA.b VMAIN-!DP_PPU ; VMAIN  = $00 → inc by 1 word after low-byte access
    STA.b VMADDL-!DP_PPU ; VMADDL = $00 (VRAM address low)
    STA.b VMADDH-!DP_PPU ; VMADDH = $00 (VRAM address high) → addr = $0000

    ; Mode 7 matrix — initialize to identity (M7A=M7D=$0100, M7B=M7C=$0000)
    ; Double-write each 16-bit element: first write = lo, second = hi.
    STA.b M7SEL-!DP_PPU ; M7SEL  = $00 (no flip, no fill with tile 0)
    STA.b M7A-!DP_PPU   ; M7A lo = $00  (first write — will be overwritten)
    LDA #$01
    STA.b M7A-!DP_PPU   ; M7A hi = $01  → M7A = $0100 = 1.0
    DEC                 ; A = $00
    STA.b M7B-!DP_PPU   ; M7B lo = $00
    STA.b M7B-!DP_PPU   ; M7B hi = $00  → M7B = $0000
    STA.b M7C-!DP_PPU   ; M7C lo = $00
    STA.b M7C-!DP_PPU   ; M7C hi = $00  → M7C = $0000
    STA.b M7D-!DP_PPU   ; M7D lo = $00
    INC                 ; A = $01
    STA.b M7D-!DP_PPU   ; M7D hi = $01  → M7D = $0100 = 1.0
    DEC                 ; A = $00
    STA.b M7X-!DP_PPU   ; M7X lo = $00
    STA.b M7X-!DP_PPU   ; M7X hi = $00  → center X = 0
    STA.b M7Y-!DP_PPU   ; M7Y lo = $00
    STA.b M7Y-!DP_PPU   ; M7Y hi = $00  → center Y = 0

    ; CGRAM (palette) address reset
    STA.b CGADD-!DP_PPU ; CGADD  = $00 (palette write pointer = entry 0)

    ; Window registers — all disabled/zeroed
    STA.b W12SEL-!DP_PPU ; W12SEL = $00 (no window mask for BG1/BG2)
    LDA.b #!W34SEL_Bg3Win1Inv
    STA.b W34SEL-!DP_PPU ; W34SEL = $03 (BG3 window 1 enable+invert; see BANK_MAP)
    LDA #$00
    STA.b WOBJSEL-!DP_PPU ; WOBJSEL = $00 (no window mask for OBJ/color)
    STA.b WH0-!DP_PPU   ; WH0    = $00 (window 1 left position)
    STA.b WH1-!DP_PPU   ; WH1    = $00 (window 1 right position)
    STA.b WH2-!DP_PPU   ; WH2    = $00 (window 2 left position)
    STA.b WH3-!DP_PPU   ; WH3    = $00 (window 2 right position)
    STA.b WBGLOG-!DP_PPU ; WBGLOG = $00 (window combine logic = OR for all BGs)
    STA.b WOBJLOG-!DP_PPU ; WOBJLOG = $00 (window combine logic = OR for OBJ/color)

    ; Layer enables — all layers on both screens (overridden later per-scene)
    STA.b TMW-!DP_PPU   ; TMW    = $00 (window mask off for main screen layers)
    STA.b TSW-!DP_PPU   ; TSW    = $00 (window mask off for subscreen layers)

    ; Color math — disabled
    STA.b CGWSEL-!DP_PPU ; CGWSEL = $00 (color math on all pixels, no sub screen)
    STA.b CGADSUB-!DP_PPU ; CGADSUB = $00 (no color math on any layer)

    LDA.b #!TM_AllLayers
    STA.b TM-!DP_PPU    ; TM = $1F → main screen: BG1+BG2+BG3+BG4+OBJ all on
    STA.b TS-!DP_PPU    ; TS = $1F → sub screen: same

    ; Fixed color for color math = black
    LDA.b #!COLDATA_GreenBlueZero
    STA.b COLDATA-!DP_PPU ; COLDATA = $C0 → write B+G channels, value = 0

    ; Screen mode init
    LDA #$00
    STA.b SETINI-!DP_PPU ; SETINI = $00 → no interlace, no overscan, no ext sync

; ----------------------------------------------------------
; Jump to main engine
; ----------------------------------------------------------
    JML GameLoop        ; → $C0:000E (main game engine entry)
