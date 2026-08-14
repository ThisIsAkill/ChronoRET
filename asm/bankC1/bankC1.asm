arch snes.cpu
hirom
incsrc "../hardware.inc"

; ============================================================
; Bank $C1 — Battle Engine
; File offset 0x010000 (bank $C1 = ROM offset $10000)
;
; CPU state on entry from field via JSL $C10000 (Battle_Main):
;   native mode, M=1 (A 8-bit), X=0 (X/Y 16-bit)
;   DP=0, DB=caller's bank
; ============================================================

; ============================================================
; Math Utility Cluster ($C1:0089–$C1:011E)
; ============================================================

; $C1:0089 — Battle_Mul8 (30 bytes, $0089–$00A6)
; 8×8→16 HW multiply via $4202/$4203/$4216.
; In:  $AD = multiplicand, $AE = multiplier
; Out: $AF = 16-bit product; mirrors operands to $77/$78
; M=1 on entry; uses STA.l for HW regs (DB unknown, must be fully qualified)
org $C10089
Battle_Mul8:
    LDA $AD
    STA $77
    STA.l WRMPYA            ; $004202 — load multiplicand (long: DB may be any)
    LDA $AE
    STA $78
    STA.l WRMPYB            ; $004203 — load multiplier (triggers multiply)
    REP #$20                ; A → 16-bit
    NOP
    NOP
    LDA.l RDMPYL            ; $004216 — read 16-bit product
    STA $AF
    TDC
    SEP #$20                ; A → 8-bit
    RTS

; $C1:00A7 — Battle_MulAccum (48 bytes, $00A7–$00D6)
; Multiply-accumulate: $A5 × $A7 via HW mult, 32-bit accumulate into $A9/$AA.
; Also multiplies $A8 × $A7 and accumulates into $AA (upper 16 bits).
; In:  $A5 = multiplicand, $A7 = multiplier, $A8 = accumulator byte, $AA = upper word
; Out: $A9/$AA = updated 32-bit accumulator
; Sets DB=0 itself (PHB/TDC/PHA/PLB) to safely use STA.w for HW regs.
org $C100A7
Battle_MulAccum:
    PHB
    TDC
    PHA
    PLB                     ; DB = 0 (hardware regs accessible via absolute)
    LDA $A5
    STA $77
    STA.w WRMPYA            ; $4202 — first operand (DB=0 → $004202)
    LDA $A7
    STA $78
    STA.w WRMPYB            ; $4203 — triggers first multiply ($A5 × $A7)
    PHP
    LDA $A8
    STZ $AB
    LDX.w RDMPYL            ; $4216 — read 16-bit product of $A5 × $A7
    STA $78
    STA.w WRMPYB            ; $4203 — triggers second multiply ($A8 × $A7)
    STX $A9                 ; save first product low word
    REP #$21                ; A → 16-bit, C=0 (clear carry for ADC)
    LDA $AA
    ADC.w RDMPYL            ; $4216 — add second product to running accumulator
    STA $AA
    TDC
    PLP
    SEP #$20                ; A → 8-bit
    PLB
    RTS

; $C1:00D7 — Battle_Divide (54 bytes, $00D7–$010C)
; 16÷8 HW divide via $4204/$4205/$4206/$4214.
; In:  $B1/$B2 = 16-bit dividend (lo/hi), $B3 = 8-bit divisor
; Out: $B5 = 16-bit quotient, $B7 = 16-bit remainder; mirrors to $79/$7A/$7B
; Guards with INC/STZ $A029 (re-entrancy flag in WRAM).
org $C100D7
Battle_Divide:
    INC.w $A029             ; increment re-entrancy guard
    LDA $B1
    STA $79
    STA.l WRDIVL            ; $004204 — dividend low byte
    LDA $B2
    STA $7A
    STA.l WRDIVH            ; $004205 — dividend high byte
    LDA $B3
    STA $7B
    STA.l WRDIVB            ; $004206 — divisor (triggers divide)
    REP #$20                ; A → 16-bit
    NOP                     ; 6 NOPs: hardware latency for divide result
    NOP
    NOP
    NOP
    NOP
    NOP
    LDA.l RDDIVL            ; $004214 — read 16-bit quotient
    STA $B5
    LDA.l RDMPYL            ; $004216 — read 16-bit remainder
    STA $B7
    TDC
    SEP #$20                ; A → 8-bit
    STZ.w $A029             ; clear re-entrancy guard
    RTS

; $C1:010D–$C1:011E — Shift helpers (18 bytes, $010D–$011E)
; Overlapping fall-through stubs for power-of-2 left/right shifts on A.
; All routines operate on M=1 (8-bit A); ASL A / LSR A = 1 byte each.
;
; Left-shift chain: ShiftLeft7 (8 ASL → *256) → ShiftLeft4 (4 ASL → *16)
;   → ShiftLeft3 (3 ASL → *8, RTS)
; Right-shift chain: Loc_C10116 (8 LSR → >>8) → ShiftRight6 (>>6)
;   → ShiftRight5 (>>5) → ShiftRight4 (>>4) → ShiftRight3 (>>3, RTS)
org $C1010D
Battle_ShiftLeft7:          ; A <<= 7 (falls through ShiftLeft4 + ShiftLeft3 chain)
    ASL A
    ASL A
    ASL A
    ASL A
Battle_ShiftLeft4:          ; A <<= 4 (falls through ShiftLeft3 chain)
    ASL A
Battle_ShiftLeft3:          ; A <<= 3
    ASL A
    ASL A
    ASL A
    RTS
Loc_C10116:                 ; A >>= 8 (2 extra LSR before ShiftRight6 chain)
    LSR A
    LSR A
Battle_ShiftRight6:         ; A >>= 6
    LSR A
Battle_ShiftRight5:         ; A >>= 5
    LSR A
Battle_ShiftRight4:         ; A >>= 4
    LSR A
Battle_ShiftRight3:         ; A >>= 3
    LSR A
    LSR A
    LSR A
    RTS
