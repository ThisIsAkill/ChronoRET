; ============================================================
; Bank $00 — Boot/vector page ($FF00–$FFFF)
;
; The entire last 256 bytes of bank $00 (file offset $00FF00–$00FFFF).
; Contains: reset entry, native-mode interrupt stubs, BRK crash handler,
; bitmask LUTs, scroll-wave tables, SNES internal ROM header, and the
; native/emulation interrupt vector table.
; ============================================================

arch snes.cpu
hirom

; ============================================================
; Reset entry point — $00:FF00 (file 0x00FF00)
; SNES emulation-mode RESET vector ($FFFC/$FFFD) = $FF00.
; CPU starts in emulation (6502-compat) mode; first three instructions
; switch it to native 65816 mode, then long-jump to the real init.
; ============================================================
org $C0FF00

Reset:
    SEI                 ; disable IRQs while changing CPU mode
    CLC                 ; carry=0 → XCE switches to native mode
    XCE                 ; exchange carry ↔ emulation bit
    JML MainInit        ; long jump to hardware init ($FD:C000)

    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; padding $FF07–$FF0F

; ============================================================
; Native-mode interrupt stubs ($FF10–$FF1F)
; RAM handlers are installed during MainInit; these stubs dispatch there.
; ============================================================
NMI_Stub:               ; native NMI vector target (see $FFEA)
    JML $000500         ; → RAM-resident NMI handler

IRQ_Stub:               ; native IRQ vector target (see $FFEE)
    JML $000504         ; → RAM-resident IRQ handler

; Both native BRK and emulation-mode COP point here (see $FFE6, $FFF4).
; Reads a magic SRAM cookie then loops forever — crash trap.
BRK_Handler:
    LDA.l $ABCDEF       ; read SRAM sanity cookie
    BRA BRK_Handler     ; infinite loop — no recovery

    db $FF,$FF          ; padding $FF1E–$FF1F

; ============================================================
; Bitmask lookup tables ($FF20–$FF2F)
; BitSet[N] = (1 << N), BitClear[N] = ~(1 << N).
; Used for testing/setting/clearing single bits in flag bytes.
; ============================================================
BitSet:                 ; $FF20 — bit N set, others clear
    db $01,$02,$04,$08,$10,$20,$40,$80

BitClear:               ; $FF28 — bit N clear, others set
    db $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F

; ============================================================
; Scroll wave tables ($FF30–$FFAF)
; Two identical 32-entry signed 16-bit tables (64 bytes each).
; Values oscillate 0→+6→0→-6, used for wave-scroll / shake effects.
; Table A and B are separate so two effects can have independent phases.
; ============================================================
ScrollWaveA:            ; $FF30 (32 × sint16)
    dw  $0000,$0001,$0002,$0003,$0004,$0005,$0005,$0006
    dw  $0006,$0006,$0005,$0005,$0004,$0003,$0002,$0001
    dw  $0000,$FFFF,$FFFE,$FFFD,$FFFC,$FFFB,$FFFB,$FFFA
    dw  $FFFA,$FFFA,$FFFB,$FFFB,$FFFC,$FFFD,$FFFE,$FFFF

ScrollWaveB:            ; $FF70 (32 × sint16, same values as A)
    dw  $0000,$0001,$0002,$0003,$0004,$0005,$0005,$0006
    dw  $0006,$0006,$0005,$0005,$0004,$0003,$0002,$0001
    dw  $0000,$FFFF,$FFFE,$FFFD,$FFFC,$FFFB,$FFFB,$FFFA
    dw  $FFFA,$FFFA,$FFFB,$FFFB,$FFFC,$FFFD,$FFFE,$FFFF

; ============================================================
; SNES internal ROM header ($FFB0–$FFDF)
; Standard SFC/SNES format.  $FFB0–$FFBF is the extended header area;
; the official header begins at $FFC0.
; ============================================================
                        ; $FFB0 — extended header: maker+game code
    db "C3"             ; maker code (Square)
    db "ACTE"           ; game code (Chrono Trigger)
    db $00,$00,$00,$00,$00,$00,$00,$00,$00,$00  ; reserved

ROMTitle:               ; $FFC0 — ROM title (21 bytes, space-padded)
    db "CHRONO TRIGGER       "

    db $31              ; $FFD5 — map mode: HiROM ($21) + FastROM ($10)
    db $02              ; $FFD6 — ROM type: ROM + SRAM
    db $0C              ; $FFD7 — ROM size: 2^12 KiB = 4 MiB
    db $03              ; $FFD8 — SRAM size: 2^3 KiB = 8 KiB
    db $01              ; $FFD9 — country: USA
    db $33              ; $FFDA — developer ID ($33 = extended header present)
    db $00              ; $FFDB — ROM version: 1.0
    dw $8773            ; $FFDC–$FFDD — checksum complement
    dw $788C            ; $FFDE–$FFDF — checksum ($8773+$788C=$FFFF ✓)

; ============================================================
; Interrupt vector table ($FFE0–$FFFF)
; Native-mode vectors: $FFE4–$FFEF
; Emulation-mode vectors: $FFF4–$FFFF
; ============================================================
    db $FF,$FF,$FF,$FF  ; $FFE0–$FFE3 — pre-vector padding (unused)

    ; Native mode vectors
    dw $FFFF            ; $FFE4 — native COP     (unused — $FF fill)
    dw BRK_Handler      ; $FFE6 — native BRK     → crash handler
    dw $FFFF            ; $FFE8 — native ABORT    (unused)
    dw NMI_Stub         ; $FFEA — native NMI      → $FF10
    dw $FFFF            ; $FFEC — native RESET     (unused; emulation RESET is used)
    dw IRQ_Stub         ; $FFEE — native IRQ      → $FF14

    db $FF,$FF,$FF,$FF  ; $FFF0–$FFF3 — pre-emulation padding

    ; Emulation mode vectors
    dw BRK_Handler      ; $FFF4 — emulation COP  → crash handler (same as BRK)
    dw $FFFF            ; $FFF6 — (unused)
    dw $FFFF            ; $FFF8 — emulation ABORT (unused)
    dw $FFFF            ; $FFFA — emulation NMI   (unused in emulation mode)
    dw Reset            ; $FFFC — emulation RESET → $FF00 ← boot vector
    dw $FFFF            ; $FFFE — emulation IRQBRK (unused)
