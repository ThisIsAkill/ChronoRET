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

; ============================================================
; Battle Message / Number Display Cluster ($C1:011F–$C1:01F8)
; ============================================================

; $C1:011F — BattleMsg_FormatNumberDigits (85 bytes, $011F–$0173)
; Format the 16-bit value at $9499 into four font digit tiles:
;   $949C = $FF (blank, thousands), $949D = hundreds,
;   $949E = tens, $949F = ones.
;   Digit tile glyphs looked up via table at $CCF903.
; Entry: M=0 (16-bit A), X=0 (16-bit), DB=$7E (WRAM accessible)
; Exit:  M=1 (8-bit A), X=0 (16-bit)
; Note: M=0 is established by the caller; no REP #$20 emitted here.
;   SBC/ADC with 16-bit immediates forced via db to get 3-byte encoding.
; No JSR/JSL calls.
org $C1011F
BattleMsg_FormatNumberDigits:
    PHX
    TDC
    TAX
.hundreds_loop:
    SEC
    LDA.w $9499
    db $E9,$64,$00              ; SBC #$0064 — subtract 100 (3-byte M=0 form)
    STA.w $9499
    INX
    BCS .hundreds_loop
    CLC
    LDA.w $9499
    db $69,$64,$00              ; ADC #$0064 — restore overshoot
    STA.w $9499
    DEX
    PHX                         ; push hundreds digit count
    TDC
    TAX
.tens_loop:
    SEC
    LDA.w $9499
    db $E9,$0A,$00              ; SBC #$000A — subtract 10
    STA.w $9499
    INX
    BCS .tens_loop
    CLC
    LDA.w $9499
    db $69,$0A,$00              ; ADC #$000A — restore overshoot; A = ones digit (not stored back)
    DEX
    PHX                         ; push tens digit count
    SEP #$20                    ; A → 8-bit
    TAX                         ; X = ones digit
    LDA.l $CCF903,X             ; ones → digit tile glyph
    STA.w $949F
    PLX                         ; X = tens count
    LDA.l $CCF903,X
    STA.w $949E
    PLX                         ; X = hundreds count
    LDA.l $CCF903,X
    STA.w $949D
    LDA #$FF                    ; thousands digit = blank ($FF)
    STA.w $949C
    PLX
    RTS

; $C1:0174 — Battle_DivTen9499 (53 bytes, $0174–$01A8)
; Two-digit variant of BattleMsg_FormatNumberDigits: formats $9499
; as tens+ones only. $949C/$949D = $FF (blank); $949E = tens, $949F = ones.
; Used for two-digit battle values (0–99).
; Entry: M=0 (16-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1 (8-bit A), X=0 (16-bit)
; Note: same SBC/ADC db trick as BattleMsg_FormatNumberDigits.
; No JSR/JSL calls.
org $C10174
Battle_DivTen9499:
    PHX
    TDC
    TAX
.tens_loop:
    SEC
    LDA.w $9499
    db $E9,$0A,$00              ; SBC #$000A — subtract 10
    STA.w $9499
    INX
    BCS .tens_loop
    CLC
    LDA.w $9499
    db $69,$0A,$00              ; ADC #$000A — restore overshoot; A = ones digit
    DEX
    PHX                         ; push tens digit count
    SEP #$20                    ; A → 8-bit
    TAX                         ; X = ones digit
    LDA.l $CCF903,X             ; ones → digit tile glyph
    STA.w $949F
    PLX                         ; X = tens count
    LDA.l $CCF903,X
    STA.w $949E
    LDA #$FF                    ; hundreds = blank
    STA.w $949D
    STA.w $949C                 ; thousands = blank
    PLX
    RTS

; $C1:01A9 — BattleMsg_ReencodeTextBuffer (80 bytes, $01A9–$01F8)
; Copy 16-char source buf $94C0–$94CF (backup), blank $94A0/$94B0,
; then re-encode each char byte into tile ($94A0,X) + plane marker ($94B0,X):
;   $40–$68 → tile += $40, plane = $71
;   $69–$72 → tile += $17, plane = $72
;   $73+    → tile = char unchanged, plane = $FF (passthrough)
;   $00     → stop early (blank fill already done by MVN)
; Entry: M=1 (8-bit A), X=0 (16-bit); entry state from caller
; Exit:  M=1 (8-bit A)
; No JSR/JSL calls.
org $C101A9
BattleMsg_ReencodeTextBuffer:
    REP #$20                    ; A → 16-bit
    LDX.w #$94A0                ; src index for MVN
    LDY.w #$94C0                ; dst index for MVN
    LDA.w #$000F                ; count − 1 = 15 (copy 16 bytes)
    MVN $7E,$7E                 ; copy $7E:$94A0..$94AF → $7E:$94C0..$94CF (backup)
    LDX.w #$001E                ; loop index = 30 (step −2, 16 word-slots)
.blank_loop:
    STA.w $94A0,X               ; write $FFFF (MVN leaves A=$FFFF) to blank each word slot
    DEX
    DEX
    BPL .blank_loop
    TDC                         ; A = 0
    TAX                         ; X = 0
    SEP #$20                    ; A → 8-bit
.char_loop:
    LDA.w $94C0,X               ; read source char from backup
    BEQ .done                   ; $00 = end of string
    CMP #$73
    BCS .passthrough            ; $73+ → passthrough (tile unchanged, plane = $FF)
    CMP #$69
    BCS .range69                ; $69–$72 → add $17, plane = $72
    CMP #$40
    BCC .passthrough            ; < $40 → passthrough
    ; $40–$68: add $40 to get tile index, plane = $71
    CLC
    ADC #$40
    STA.w $94A0,X
    LDA #$71
    BRA .store_plane
.range69:
    ; $69–$72: add $17 to get tile index, plane = $72
    CLC
    ADC #$17
    STA.w $94A0,X
    LDA #$72
    BRA .store_plane
.passthrough:
    STA.w $94A0,X               ; store tile unchanged
    LDA #$FF                    ; plane = $FF (passthrough marker)
.store_plane:
    STA.w $94B0,X               ; write plane marker
    INX
    CPX.w #$0010                ; processed all 16 chars?
    BNE .char_loop
.done:
    RTS

; ============================================================
; Trig / Geometry Cluster ($C1:01F9–$C1:0298)
; ============================================================

; $C1:01F9 — Battle_SinLookup (41 bytes, $01F9–$0221)
; Sine lookup: computes sin(A) × $AE and stores result in $AA.
; A (8-bit on entry) is a phase angle; table at $C0F900 gives signed
; sine values. Multiplied by $AE via Battle_MulAccum ($A5 = sin, $A7 = $AE).
; Entry: M=1 (8-bit A), X=0 (16-bit); angle in A
; Exit:  M=1 (8-bit A); result byte in $AA (high byte of MulAccum product)
; Calls: Battle_MulAccum ($C1:00A7, matched)
org $C101F9
Battle_SinLookup:
    REP #$20                    ; A → 16-bit
    ASL A
    ASL A
    AND.w #$03FF                ; wrap angle to [0, 1023] (512-entry sin table, × 2 = 1024 indices)
    TAX                         ; X = table byte index
    LDA.l $C0F900,X             ; read 16-bit entry from sine table (signed, little-endian)
    AND.w #$00FF                ; keep low byte (magnitude)
    CPX.w #$0200                ; X >= $0200 → second half of sine (negative quadrants)
    BCC .first_quadrant
    EOR.w #$FFFF                ; invert for negative quadrant
    INC A                       ; two's complement negate (EOR + INC)
.first_quadrant:
    STA $A7                     ; $A7 (M=0: also clears $A8) = signed sin value
    LDA $AE                     ; read multiplier (M=0: also reads $AF)
    AND.w #$00FF                ; keep low byte only ($AE value, zero-extend)
    STA $A5                     ; $A5 (M=0: also clears $A6) = multiplier byte
    SEP #$20                    ; A → 8-bit
    JSR Battle_MulAccum         ; $A5 × $A7 → 32-bit accumulate into $A9/$AA
    LDA $AA                     ; return high byte of product
    RTS

; $C1:0222 — Calc_Delta16 (119 bytes, $0222–$0298)
; 16-bit signed vector delta and direction-angle computation.
; Computes (D3–D5) and (D4–D6) as 16-bit signed differences (→ $D7/$D8, $D9/$DA),
; derives absolute deltas ($DE/$DF, $E0/$E1), computes a blended "magnitude" index
; in $E2, looks up a base direction angle from $C0F300, then adjusts the sign
; of the angle based on the quadrant determined by $D8 and $DA sign bits.
; Entry: M=1 (8-bit A), X=0 (16-bit)
; Exit:  M=1 (8-bit A); direction angle in $DB
; No JSR/JSL calls.
org $C10222
Calc_Delta16:
    ; --- Phase 1: compute (D3 − D5) → $D7/$D8, (D4 − D6) → $D9/$DA ---
    SEC
    LDA $D3
    SBC $D5
    STA $D7
    LDA #$00
    SBC #$00                    ; propagate borrow → $D8 = high byte (0 or $FF)
    STA $D8
    SEC
    LDA $D4
    SBC $D6
    STA $D9
    LDA #$00
    SBC #$00                    ; propagate borrow → $DA
    STA $DA
    ; --- Phase 2: absolute values → $DE/$DF, $E0/$E1 ---
    LDA $D7
    EOR $D8                     ; XOR sign byte: if negative, flips bits
    SEC
    SBC $D8                     ; subtract sign byte: two's complement abs
    STA $DE
    STZ $DF
    LDA $D9
    EOR $DA
    SEC
    SBC $DA
    STA $E0
    STZ $E1
    ; --- Phase 3: blended magnitude index in $E2 ---
    REP #$20                    ; A → 16-bit
    LDA $DE                     ; 16-bit |ΔX| ($DE/$DF)
    LSR A
    LSR A
    LSR A                       ; |ΔX| >> 3
    STA $DC
    LDA $E0                     ; 16-bit |ΔY| ($E0/$E1)
    AND.w #$FFF8                ; mask lower 3 bits (align to 8)
    ASL A
    ASL A                       ; |ΔY| & $FFF8, × 4
    CLC
    ADC $DC                     ; + (|ΔX| >> 3)
    STA $E2                     ; blended index
    ASL A                       ; × 2 (dead code: X overridden by LDX $E2 below)
    TAX
    TDC                         ; A = 0
    SEP #$20                    ; A → 8-bit
    LDX $E2                     ; X = table index (overrides dead TAX above)
    LDA.l $C0F300,X             ; look up base direction angle from $C0F300
    STA $DB
    ; --- Phase 4: quadrant adjustment of angle ---
    LDA $D8                     ; check sign of ΔX (high byte)
    BMI .d8_negative            ; ΔX < 0
    LDA $DA                     ; check sign of ΔY (high byte)
    BMI .da_negative_q1         ; ΔX ≥ 0, ΔY < 0 → Q4
    ; Q1: ΔX ≥ 0, ΔY ≥ 0 → angle = $80 + base
    CLC
    LDA #$80
    ADC $DB
    STA $DB
    RTS
.da_negative_q1:                ; Q4: ΔX ≥ 0, ΔY < 0 → angle = $80 − base
    SEC
    LDA #$80
    SBC $DB
    STA $DB
    RTS
.d8_negative:
    LDA $DA                     ; check sign of ΔY
    BMI .da_negative_q3         ; ΔX < 0, ΔY < 0 → Q3
    ; Q2: ΔX < 0, ΔY ≥ 0 → angle = 0 − base (negate)
    TDC                         ; A = 0
    SEC
    SBC $DB
    STA $DB
.da_negative_q3:                ; Q3: ΔX < 0, ΔY < 0 → angle unchanged ($DB as is)
    LDA $DB
    RTS
