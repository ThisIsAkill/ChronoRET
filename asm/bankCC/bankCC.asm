; ============================================================
; Bank $CC — battle helpers (mostly unmatched)
; File offset 0x0C0000 (bank $CC = ROM offset $C0000)
;
; Bank $C1 reaches code here by JSL ($C1:405B, $C1:409C, $C1:40A9,
; $C1:40B9, ... call into $CC:F06B–$CC:F278), so this part of the bank
; belongs to the battle engine and uses the same direct-page scratch.
; Only the multiply helper below is matched so far.
; ============================================================

arch snes.cpu
hirom

; ============================================================
; Battle Math ($CC:F365–$CC:F382)
; ============================================================

; $CC:F365 — Battle_Mul8CC (30 bytes, $F365–$F382)
; A byte-identical copy of Battle_Mul8 ($C1:0089): 8×8→16 hardware
; multiply through WRMPYA/WRMPYB/RDMPYL. It ends in RTS, so each bank
; that needs it keeps its own copy (a JSR cannot leave the bank).
; In:  !Battle_Mul8A = multiplicand, !Battle_Mul8B = multiplier
; Out: !Battle_Mul8Product = 16-bit product; operands mirrored to
;      !Battle_MulMirrorA/B
; The two NOPs after REP are multiply latency: the 8x8 product is only
; valid in RDMPYL 8 cycles after the WRMPYB write.
; Entry: M=1, X either width, DP=0 (assumed, as for Battle_Mul8: the
;        operands are the battle direct-page bytes; the callers' DP is not
;        traced), DB any (the HW registers are reached with STA.l/LDA.l)
; Exit:  M=1; A=0 (TDC with DP=0); X/Y and DB unchanged; DP $77/$78 and
;        $AF/$B0 written
; Callers (3 JSR sites): unmatched ($CC:F23E, $CC:F25A, $CC:F2C4).
; Callers note: JSR from $CC:F23E, $CC:F25A and $CC:F2C4 (searched: no other
;          JSR/JMP/JSL reaches $F365). No calls.
org $CCF365
Battle_Mul8CC:
    LDA.b !Battle_Mul8A
    STA.b !Battle_MulMirrorA
    STA.l WRMPYA            ; $004202 — load multiplicand (long: DB may be any)
    LDA.b !Battle_Mul8B
    STA.b !Battle_MulMirrorB
    STA.l WRMPYB            ; $004203 — load multiplier (triggers multiply)
    REP #$20                ; A → 16-bit
    NOP
    NOP
    LDA.l RDMPYL            ; $004216 — read 16-bit product
    STA.b !Battle_Mul8Product
    TDC
    SEP #$20                ; A → 8-bit
    RTS
