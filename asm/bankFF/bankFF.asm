; ============================================================
; Bank $FF — (mostly unmatched)
; File offset 0x3F0000 (bank $FF = ROM offset $3F0000)
;
; Only the wave table below is matched so far.
; ============================================================

arch snes.cpu
hirom

; ============================================================
; Wave tables ($FF:F759–$FF:F7D8)
; A byte-identical copy of ScrollWaveA/ScrollWaveB in bank $00
; ($C0:FF30–$C0:FFAF): one period of a sine-like wave between -6 and +6
; (32 signed 16-bit entries), stored twice.
;
; Read by the routine just before it ($FF:F716–$FF:F758, reached by JSL
; from $C2:CECE; searched: the only long reference to $FFF759). It masks
; a phase with AND #$3E, then reads LDA.l $FFF759,X with X stepping by 4
; and Y from the word at DP $51 up to $20 in steps of 2, adds the word at
; DP $00 (copied from $0D0C) with ADC and stores to $9240,Y. As in bank
; $00, the reads run past A into B, so B is A's second period and lets
; the loop read ahead without masking each index. There is no CLC in the
; loop; reproduced as found, effect not traced. What the outputs drive is
; not traced; "Scroll" follows the bank $00 copy's (guessed) name.
; ============================================================
org $FFF759

ScrollWaveFF_A:         ; $FF:F759 (32 × sint16)
    dw  $0000,$0001,$0002,$0003,$0004,$0005,$0005,$0006
    dw  $0006,$0006,$0005,$0005,$0004,$0003,$0002,$0001
    dw  $0000,$FFFF,$FFFE,$FFFD,$FFFC,$FFFB,$FFFB,$FFFA
    dw  $FFFA,$FFFA,$FFFB,$FFFB,$FFFC,$FFFD,$FFFE,$FFFF

ScrollWaveFF_B:         ; $FF:F799 (32 × sint16: A's second period)
    dw  $0000,$0001,$0002,$0003,$0004,$0005,$0005,$0006
    dw  $0006,$0006,$0005,$0005,$0004,$0003,$0002,$0001
    dw  $0000,$FFFF,$FFFE,$FFFD,$FFFC,$FFFB,$FFFB,$FFFA
    dw  $FFFA,$FFFA,$FFFB,$FFFB,$FFFC,$FFFD,$FFFE,$FFFF
