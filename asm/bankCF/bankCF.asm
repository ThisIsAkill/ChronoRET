; ============================================================
; Bank $CF — battle support (mostly unmatched)
; File offset 0x0F0000 (bank $CF = ROM offset $F0000)
;
; Bank $C1 reaches code at the end of this bank by JSL (the per-frame
; merge at $CF:FAE2, the VRAM upload queue helpers at $CF:FD02–$CF:FD9D,
; the per-slot pointer load at $CF:FD9E; label-only stubs in
; include/unmatched_battle.asm), so this part of the bank belongs to the
; battle engine and uses its RAM names. Only the two helpers below are
; matched so far.
; ============================================================

arch snes.cpu
hirom

; ============================================================
; Battle Math ($CF:F9FB–$CF:FA42)
; ============================================================

; $CF:F9FB — Battle_SinLookupCF (72 bytes, $F9FB–$FA42)
; Bank $CF's own scaled sine: returns (sin(A) × !BattleCF_SinScale) >> 8
; in A. It is Battle_SinLookup ($C1:01F9) with Battle_Mul8x16 ($C1:00A7)
; written inline after it (a JSR cannot leave the bank), and with its
; own direct-page slots: the scale at $00 instead of $AE, the factor and
; product at $02-$06 instead of $A5-$AB, and no MulMirror copies. The
; first 24 bytes (through the negate) are byte-identical to
; Battle_SinLookup's. !BattleRom_SineTable holds |sin|
; for 1024 steps per turn; angle × 4 picks every fourth entry, negated for
; the second half turn.
; Callers (20 JSR sites): unmatched ($CF:F1CA, $CF:F1D7, $CF:F20E, $CF:F21A, $CF:F36B, $CF:F37C,
;   $CF:F3F2, $CF:F3FE, $CF:F48B, $CF:F498, $CF:F657, $CF:F664, $CF:F6A3, $CF:F6AE, $CF:F840,
;   $CF:F850, $CF:F920, $CF:F933, $CF:F9A8, $CF:F9B5).
; Callers note (20 JSR sites, all in unmatched bank $CF code, in pairs: e.g.
;   $CF:F1CA/F1D7, $CF:F20E/F21A, $CF:F36B/F37C, $CF:F3F2/F3FE). In the
;   pair at $CF:F1CA the caller stores a per-battler byte to $00, calls
;   with an angle and again with angle + $40 (the cosine), and adds the
;   two results to Battler_ScreenY and Battler_ScreenX: a point on a
;   circle of that radius (seen at that site only).
; Entry: M=1 (8-bit A), X=0 (16-bit; LDX.w RDMPYL / STX.b move the
;        16-bit first product), DP=0 (assumed, as for the bank $C1 battle
;        code; PHB / TDC / PHA / PLB sets DB to D's low byte, which must be
;        0 for STA.w to reach the multiply registers), DB any (restored);
;        angle in A, scale in !BattleCF_SinScale
; Exit:  M=1, X=0 (P restored by PLP; the SEP #$20 after it is
;        redundant, as in Battle_Mul8x16); A = !BattleCF_SinProduct+1
;        (product >> 8); X = the first partial product; Y and DB
;        unchanged; DP $02-$06 written
; No calls.
org $CFF9FB
Battle_SinLookupCF:
    REP #$20                    ; A → 16-bit
    ASL A
    ASL A
    AND.w #!Battle_SineIndexMask ; angle × 4, wrapped to the 1024-entry table
    TAX                         ; X = table byte index
    LDA.l !BattleRom_SineTable,X
    AND.w #!Battle_LowByteMask  ; keep this entry (the 16-bit read also took the next)
    CPX.w #!Battle_SineHalfTable ; second half turn → negative
    BCC .first_half
    EOR.w #!Battle_Invert16
    INC A                       ; two's complement negate (EOR + INC)
.first_half:
    STA.b !BattleCF_SinFactor16 ; signed sine (16-bit store)
    SEP #$20                    ; A → 8-bit
    ; inline Battle_Mul8x16: SinScale × SinFactor16 → 24-bit SinProduct
    PHB
    TDC
    PHA
    PLB                         ; DB = 0 (hardware regs reachable with .w)
    LDA.b !BattleCF_SinScale
    STA.w WRMPYA
    LDA.b !BattleCF_SinFactor16
    STA.w WRMPYB                ; first multiply: scale × sine low byte
    PHP
    LDA.b !BattleCF_SinFactor16+1
    STZ.b !BattleCF_SinProduct+2
    LDX.w RDMPYL                ; first 16-bit partial product
    STA.w WRMPYB                ; second multiply: scale × sine high byte
    STX.b !BattleCF_SinProduct
    REP #$21                    ; A → 16-bit, C=0 for the ADC
    LDA.b !BattleCF_SinProduct+1
    ADC.w RDMPYL                ; add the second partial product, shifted up 8 bits
    STA.b !BattleCF_SinProduct+1
    TDC
    PLP
    SEP #$20                    ; A → 8-bit
    PLB
    LDA.b !BattleCF_SinProduct+1 ; return product >> 8
    RTS

; ============================================================
; Battle Number Formatting ($CF:FDAD–$CF:FE1F)
; ============================================================

; $CF:FDAD — BattleMsg_FormatNumber4Digits (115 bytes, $FDAD–$FE1F)
; A four-digit, long-call version of BattleMsg_FormatNumberDigits
; ($C1:011F): the same subtract-and-count loops with one more for the
; thousands, and the digits looked up in !BattleRom_DigitTilesB (tiles
; $90-$99) instead of !BattleRom_DigitTiles. Formats the 16-bit value in
; !BattleMsg_NumValue (0-9999; a larger value indexes past the table)
; into Digit1000 / Digit100 / Digit10 / Digit1, all four as digit tiles:
; nothing is blanked here (the caller counts the leading $90 tiles
; itself). NumValue is consumed. Ends in RTL, so bank $C1 can reach it.
; Callers (1 JSL site): BattleAct_OpShowHitNumbers ($C1:5BB9).
; Callers note: JSL from $C1:5BB9 (unmatched; it stores a word from
;   $AD9C,X to NumValue first, then counts the leading $90 tiles in
;   Digit1000, Digit100, Digit10 (stopping at the first other tile) and
;   indexes a 4-byte table at $CC:F5C4 with that count, which looks like
;   the placement of a number drawn with these tiles; not traced).
; Entry: M=0 (16-bit A; set by the caller, so the SBC/ADC immediates
;        carry an explicit .w), X=0 (16-bit), DP=0 (TDC / TAX zeroes the
;        digit counters only because D=0), DB=$7E (NumValue and the digit
;        bytes are absolute WRAM)
; Exit:  M=1 (8-bit A), X=0; X and Y unchanged (PHX/PLX); A = the
;        thousands tile; !BattleMsg_NumValue consumed
; No JSR/JSL calls.
org $CFFDAD
BattleMsg_FormatNumber4Digits:
    PHX
    TDC
    TAX
.thousands_loop:
    SEC
    LDA.w !BattleMsg_NumValue
    SBC.w #!BattleMsg_Thousand  ; subtract 1000
    STA.w !BattleMsg_NumValue
    INX
    BCS .thousands_loop
    CLC
    LDA.w !BattleMsg_NumValue
    ADC.w #!BattleMsg_Thousand  ; restore overshoot
    STA.w !BattleMsg_NumValue
    DEX
    PHX                         ; push thousands digit count
    TDC
    TAX
.hundreds_loop:
    SEC
    LDA.w !BattleMsg_NumValue
    SBC.w #!BattleMsg_Hundred   ; subtract 100
    STA.w !BattleMsg_NumValue
    INX
    BCS .hundreds_loop
    CLC
    LDA.w !BattleMsg_NumValue
    ADC.w #!BattleMsg_Hundred   ; restore overshoot
    STA.w !BattleMsg_NumValue
    DEX
    PHX                         ; push hundreds digit count
    TDC
    TAX
.tens_loop:
    SEC
    LDA.w !BattleMsg_NumValue
    SBC.w #!BattleMsg_Ten       ; subtract 10
    STA.w !BattleMsg_NumValue
    INX
    BCS .tens_loop
    CLC
    LDA.w !BattleMsg_NumValue
    ADC.w #!BattleMsg_Ten       ; restore overshoot; A = ones digit (not stored back)
    DEX
    PHX                         ; push tens digit count
    SEP #$20                    ; A → 8-bit
    TAX                         ; X = ones digit
    LDA.l !BattleRom_DigitTilesB,X
    STA.w !BattleMsg_Digit1
    PLX                         ; X = tens count
    LDA.l !BattleRom_DigitTilesB,X
    STA.w !BattleMsg_Digit10
    PLX                         ; X = hundreds count
    LDA.l !BattleRom_DigitTilesB,X
    STA.w !BattleMsg_Digit100
    PLX                         ; X = thousands count
    LDA.l !BattleRom_DigitTilesB,X
    STA.w !BattleMsg_Digit1000
    PLX
    RTL
