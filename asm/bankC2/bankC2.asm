; ============================================================
; Bank $C2 — (mostly unmatched)
; File offset 0x020000 (bank $C2 = ROM offset $20000)
;
; Bank $C0 enters this bank through BankC2_Entry0000/8000/8004
; (label-only stubs in include/unmatched.asm). Only the register setup
; and the sine helper below are matched so far; they use the engine
; names.
; ============================================================

arch snes.cpu
hirom

incsrc "../hardware.inc"

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
; on are the same bytes as MainInit's. INIDISP is not written (the bank's entry code at
; $C2:000F has already set forced blank).
; Callers (2 JSR sites, unmatched): $C2:0031 in the bank's entry code
;   (BankC2_Entry0000 jumps to $C2:000F, which runs SEI, NMI/DMA off,
;   forced blank, DB=$00 and DP=$0000 first) and $C2:2557.
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
