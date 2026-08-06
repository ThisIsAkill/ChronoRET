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

    LDX #$06FF          ; stack base: $0700 page (16-bit X)
    TXS                 ; S = $06FF

    LDA #$00
    PHA
    PLB                 ; data bank register B = $00

    REP #$20            ; A → 16-bit
    LDA #$4200          ; DP → CPU register area ($4200–$420F)
    TCD
    SEP #$20            ; A → 8-bit

; ----------------------------------------------------------
; Phase 2: CPU register init  (DP = $4200)
; Disable IRQ/NMI, DMA/HDMA; select FastROM; zero math regs.
; All writes are 8-bit via DP-relative addressing.
; ----------------------------------------------------------
    LDA #$01
    STA $0D             ; MEMSEL  = $01 → FastROM (3.58 MHz ROM access)

    LDA #$00
    STA $00             ; NMITIMEN = $00 → disable NMI, IRQ, auto-joypad
    STA $0B             ; MDMAEN  = $00 → disable all DMA channels
    STA $0C             ; HDMAEN  = $00 → disable all HDMA channels
    STA $02             ; WRMPYA  = $00 (multiply operand A)
    STA $03             ; WRMPYB  = $00 (multiply operand B)
    STA $04             ; WRDIVL  = $00 (dividend low)
    STA $05             ; WRDIVH  = $00 (dividend high)
    STA $06             ; WRDIVB  = $00 (divisor)
    STA $07             ; HTIMEL  = $00 (H-count timer low)
    STA $08             ; HTIMEH  = $00 (H-count timer high)
    STA $09             ; VTIMEL  = $00 (V-count timer low)
    STA $0A             ; VTIMEH  = $00 (V-count timer high)

    LDA #$FF
    STA $01             ; WRIO    = $FF → all programmable I/O pins high

; ----------------------------------------------------------
; Phase 3: Switch DP to PPU register area; force blank
; ----------------------------------------------------------
    REP #$20            ; A → 16-bit
    LDA #$2100          ; DP → PPU register area ($2100–$2133)
    TCD
    SEP #$20            ; A → 8-bit

    LDA #$80
    STA $00             ; INIDISP = $80 → forced blank (screen disabled)

; ----------------------------------------------------------
; Phase 4: PPU register init  (DP = $2100)
; Initialize all relevant PPU registers to known state.
; ----------------------------------------------------------

    ; OAM
    LDA #$63
    STA $01             ; OBSEL   = $63 → sprites: 8×8/16×16, base=0, gap=3
    LDA #$00
    STA $02             ; OAMADDL = $00 (OAM address low)
    STA $03             ; OAMADDH = $00 (OAM address high, priority=0)

    ; BG mode
    LDA #$09
    STA $05             ; BGMODE  = $09 → Mode 1 (001), BG3 high priority (bit3)

    ; BG tilemap/character addresses — zeroed (set at runtime)
    LDA #$00
    STA $06             ; MOSAIC  = $00 (mosaic off)
    STA $07             ; BG1SC   = $00 (tilemap base addr + size)
    STA $08             ; BG2SC   = $00
    STA $09             ; BG3SC   = $00
    STA $0A             ; BG4SC   = $00
    STA $0B             ; BG12NBA = $00 (BG1/2 chr base)
    STA $0C             ; BG34NBA = $00 (BG3/4 chr base)

    ; BG scroll registers — double-write each (lo then hi byte)
    STA $0D             ; BG1HOFS write 1 = $00
    STA $0D             ; BG1HOFS write 2 = $00  → BG1 H-scroll = 0
    STA $0E             ; BG1VOFS write 1 = $00
    STA $0E             ; BG1VOFS write 2 = $00  → BG1 V-scroll = 0
    STA $0F             ; BG2HOFS write 1 = $00
    STA $0F             ; BG2HOFS write 2 = $00
    STA $10             ; BG2VOFS write 1 = $00
    STA $10             ; BG2VOFS write 2 = $00
    STA $11             ; BG3HOFS write 1 = $00
    STA $11             ; BG3HOFS write 2 = $00
    STA $12             ; BG3VOFS write 1 = $00
    STA $12             ; BG3VOFS write 2 = $00
    STA $13             ; BG4HOFS write 1 = $00
    STA $13             ; BG4HOFS write 2 = $00
    STA $14             ; BG4VOFS write 1 = $00
    STA $14             ; BG4VOFS write 2 = $00

    ; VRAM address and increment
    STA $15             ; VMAIN  = $00 → inc by 1 word after low-byte access
    STA $16             ; VMADDL = $00 (VRAM address low)
    STA $17             ; VMADDH = $00 (VRAM address high) → addr = $0000

    ; Mode 7 matrix — initialize to identity (M7A=M7D=$0100, M7B=M7C=$0000)
    ; Double-write each 16-bit element: first write = lo, second = hi.
    STA $1A             ; M7SEL  = $00 (no flip, no fill with tile 0)
    STA $1B             ; M7A lo = $00  (first write — will be overwritten)
    LDA #$01
    STA $1B             ; M7A hi = $01  → M7A = $0100 = 1.0
    DEC                 ; A = $00
    STA $1C             ; M7B lo = $00
    STA $1C             ; M7B hi = $00  → M7B = $0000
    STA $1D             ; M7C lo = $00
    STA $1D             ; M7C hi = $00  → M7C = $0000
    STA $1E             ; M7D lo = $00
    INC                 ; A = $01
    STA $1E             ; M7D hi = $01  → M7D = $0100 = 1.0
    DEC                 ; A = $00
    STA $1F             ; M7X lo = $00
    STA $1F             ; M7X hi = $00  → center X = 0
    STA $20             ; M7Y lo = $00
    STA $20             ; M7Y hi = $00  → center Y = 0

    ; CGRAM (palette) address reset
    STA $21             ; CGADD  = $00 (palette write pointer = entry 0)

    ; Window registers — all disabled/zeroed
    STA $23             ; W12SEL = $00 (no window mask for BG1/BG2)
    LDA #$03
    STA $24             ; W34SEL = $03 (BG3 window 1 enable+invert; see BANK_MAP)
    LDA #$00
    STA $25             ; WOBJSEL = $00 (no window mask for OBJ/color)
    STA $26             ; WH0    = $00 (window 1 left position)
    STA $27             ; WH1    = $00 (window 1 right position)
    STA $28             ; WH2    = $00 (window 2 left position)
    STA $29             ; WH3    = $00 (window 2 right position)
    STA $2A             ; WBGLOG = $00 (window combine logic = OR for all BGs)
    STA $2B             ; WOBJLOG = $00 (window combine logic = OR for OBJ/color)

    ; Layer enables — all layers on both screens (overridden later per-scene)
    STA $2E             ; TMW    = $00 (window mask off for main screen layers)
    STA $2F             ; TSW    = $00 (window mask off for subscreen layers)

    ; Color math — disabled
    STA $30             ; CGWSEL = $00 (color math on all pixels, no sub screen)
    STA $31             ; CGADSUB = $00 (no color math on any layer)

    LDA #$1F
    STA $2C             ; TM = $1F → main screen: BG1+BG2+BG3+BG4+OBJ all on
    STA $2D             ; TS = $1F → sub screen: same

    ; Fixed color for color math = black
    LDA #$C0
    STA $32             ; COLDATA = $C0 → write B+G channels, value = 0

    ; Screen mode init
    LDA #$00
    STA $33             ; SETINI = $00 → no interlace, no overscan, no ext sync

; ----------------------------------------------------------
; Jump to main engine
; ----------------------------------------------------------
    JML GameLoop        ; → $C0:000E (main game engine entry)
