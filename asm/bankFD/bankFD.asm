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
;
; Also matched: RandomTableFD ($FD:BA61), a copy of bank $C0's
; RandomTable read by the battle engine, and Ppu_SetBgLayout right after
; MainInit ($FD:C0D7).
; ============================================================

arch snes.cpu
hirom

incsrc "../hardware.inc"

; ============================================================
; $FD:BA61 — RandomTableFD (256 bytes, $FD:BA61–$BB60)
; A byte-identical copy of RandomTable ($C0:FE00): the same shuffle of
; 0-255. Read with LDA.l $FDBA61,X by battle code in bank $C1: at
; $C1:AF56/AF60 and $C1:AFAE/AFB8 (unmatched), two copies of a roll that
; take X from a counter (dp $26 in the first, $B3E6 in the second). When
; the range is $FF they use the entry as is (the reads at $AF56/$AFAE) and
; leave the counter alone; otherwise they step the counter and reduce the
; entry with the shift-and-subtract divide at $C1:C92A, using the
; remainder plus dp $25 (entry mod range, plus a base). What the rolls
; are for is not traced. The 6 bytes after the table
; ($FD:BB61–$BB66) repeat its last 6 entries; nothing reads them that
; xref finds, and they are left unmatched.
; ============================================================
org $FDBA61

RandomTableFD:
    db $B1,$CA,$EE,$6C,$5A,$71,$2E,$55,$D6,$00,$CC,$99,$90,$6B,$7D,$EB ; $00
    db $4F,$A0,$07,$AC,$DF,$8A,$56,$9E,$F1,$9A,$63,$75,$11,$91,$A3,$B8 ; $10
    db $94,$73,$F7,$54,$D9,$6E,$72,$C0,$F4,$80,$DE,$B9,$BB,$8D,$66,$26 ; $20
    db $D0,$36,$E1,$E9,$70,$DC,$CD,$2F,$4A,$67,$5D,$D2,$60,$B5,$9D,$7F ; $30
    db $45,$37,$50,$44,$78,$04,$19,$2C,$EF,$FD,$64,$81,$03,$DA,$95,$4C ; $40
    db $7A,$0B,$AD,$1F,$BA,$DD,$3E,$F9,$D7,$1A,$29,$F8,$18,$B3,$20,$F6 ; $50
    db $D1,$5E,$34,$92,$7B,$24,$43,$88,$97,$D4,$0F,$35,$AA,$83,$68,$27 ; $60
    db $A8,$D5,$BE,$FA,$14,$31,$AF,$10,$0D,$D8,$6A,$CE,$23,$61,$F3,$3D ; $70
    db $A4,$08,$33,$E3,$A9,$38,$E6,$93,$1D,$1C,$F0,$0E,$87,$59,$65,$82 ; $80
    db $BC,$FF,$FE,$7E,$8F,$C1,$1E,$F5,$CB,$49,$02,$32,$09,$C4,$8E,$C6 ; $90
    db $2B,$40,$A7,$17,$76,$3B,$16,$2A,$C8,$FB,$B2,$58,$A5,$15,$AE,$25 ; $A0
    db $CF,$46,$C7,$48,$B4,$0A,$3F,$C9,$06,$85,$51,$89,$62,$4D,$12,$8C ; $B0
    db $EA,$A2,$98,$4B,$79,$6F,$5C,$47,$30,$1B,$E7,$C5,$22,$9C,$E8,$96 ; $C0
    db $3A,$E4,$7C,$E0,$69,$A1,$B7,$05,$39,$74,$01,$9F,$BD,$C3,$84,$FC ; $D0
    db $77,$86,$13,$4E,$BF,$F2,$53,$5B,$ED,$21,$8B,$6D,$C2,$41,$B6,$DB ; $E0
    db $3C,$D3,$28,$EC,$2D,$E2,$9B,$A6,$42,$52,$57,$5F,$E5,$AB,$B0,$0C ; $F0

; ============================================================
; MainInit ($FD:C000)
; Called via: JML from Reset ($00:FF03), which also carries the soft
; resets, and JML $FDC000 at $C0:418D (unmatched; after JSR InitHW and
; S=$06FF). The bytes at $FD:851D read as JSR $C000 but sit in a block of
; packed data ($FD:8480 onwards does not decode as code), not a caller.
; Entry: native mode; from a hardware reset M=1 X=1, D=$0000, DB=$00;
;        from $C0:418D M=1, X=0, DB=$00. Steps 1-3 set M, X, S, DB and DP,
;        so nothing else about the entry state matters
; Exit:  (jumps, never returns) M=1 X=0, D=$2100, DB=$00, S=$06FF,
;        screen in forced blank, NMI/IRQ/DMA/HDMA off
;
; Every register write goes through a relocated direct page so each
; store is two bytes: first DP=$4200 for the CPU I/O block, then
; DP=$2100 for the PPU. Most registers are simply zeroed; the non-zero
; register values are named in hardware.inc (the Mode 7 1.0 is a literal).
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

    ; Step 4 — PPU. Non-zero writes: sprite size/base (OBSEL), BG mode,
    ; the Mode 7 identity matrix (#$01 = 1.0 in the high bytes of A and D),
    ; W34SEL, the layer enables (TM/TS), and COLDATA (written $C0, which
    ; sets green and blue to 0). Everything else (tilemap and character
    ; bases, scroll, VRAM address, color math) starts at 0, presumably to
    ; be set by each scene later.
    LDA.b #!OBSEL_Size16And32_Base6000
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

; ============================================================
; $FD:C0D7 — Ppu_SetBgLayout (77 bytes, $FD:C0D7–$C123)
; Sets a fixed background layout through DP=$2100, the way MainInit
; writes the PPU: mode 1 with BG3 on top, BG1/BG2 tiles at VRAM word
; $1000 and BG3 tiles at $5000, 64x32 maps at $6800 (BG1), $7000 (BG2)
; and $7800 (BG3), OBSEL and SETINI 0, the BG1-BG3 scroll registers 0
; (24 bytes the same as MainInit's scroll clears), BG1, BG2 and OBJ on
; the main screen, color math adding the sub screen, and the fixed color
; black. What the layout is used for is not traced.
; Callers: JSL from $C0:0A5D (unmatched; in a routine at $C0:0A50,
;   called by JSR from $C0:286F, that
;   runs a DP=$1D00 step first and more setup after).
; Entry: M=1 (8-bit A; the immediates are 8-bit), X either width, DP any
;        (saved and restored), DB any (all stores are direct page)
; Exit:  M=1, DP restored, DB unchanged; A = COLDATA_AllZero ($E0); X, Y
;        unchanged
; No calls.
org $FDC0D7
Ppu_SetBgLayout:
    PHD
    REP #$20                ; A → 16-bit
    LDA.w #!DP_PPU
    TCD                     ; DP = $2100: two-byte register stores
    SEP #$20                ; A → 8-bit
    LDA.b #BG_MODE_1|BG3_HIGH_PRIO
    STA.b BGMODE-!DP_PPU
    LDA.b #!BG12NBA_Both1000
    STA.b BG12NBA-!DP_PPU
    LDA.b #!BG34NBA_Bg3At5000
    STA.b BG34NBA-!DP_PPU
    LDA.b #!BG1SC_6800_64x32
    STA.b BG1SC-!DP_PPU
    LDA.b #!BG2SC_7000_64x32
    STA.b BG2SC-!DP_PPU
    LDA.b #!BG3SC_7800_64x32
    STA.b BG3SC-!DP_PPU
    LDA.b #$00
    STA.b OBSEL-!DP_PPU
    STA.b SETINI-!DP_PPU
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
    LDA.b #!TM_Bg1Bg2Obj
    STA.b TM-!DP_PPU
    LDA.b #!CGWSEL_AddSubscreen
    STA.b CGWSEL-!DP_PPU
    LDA.b #!COLDATA_AllZero
    STA.b COLDATA-!DP_PPU
    PLD
    RTL
