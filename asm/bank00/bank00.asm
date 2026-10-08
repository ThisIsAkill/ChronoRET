; ============================================================
; Bank $00 — Boot/vector page ($FF00–$FFFF)
;
; The entire last 256 bytes of bank $00 (file offset $00FF00–$00FFFF).
; Contains: reset entry, native-mode interrupt stubs, BRK crash handler,
; bitmask LUTs, wave tables, SNES internal ROM header, and the
; native/emulation interrupt vector table.
; ============================================================

arch snes.cpu
hirom

; ============================================================
; Reset ($00:FF00) — target of the emulation-mode RESET vector ($FFFC)
;
; The CPU comes out of reset in emulation mode with I already set. Only
; CLC+XCE are needed to enter native mode; the SEI first is defensive
; (redundant after a hardware reset, but harmless if this is ever jumped to).
; Entry: emulation mode, I=1 (hardware reset state)
; Exit:  native mode, M=1 X=1, D=$0000, DB=$00 — continues in MainInit
; ============================================================
org $C0FF00

Reset:
    SEI                 ; defensive: reset already set I
    CLC
    XCE                 ; carry 0 → leave emulation mode
    JML MainInit        ; bank $FD hardware init

    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; unused fill $FF07–$FF0F

; ============================================================
; Native-mode interrupt stubs ($FF10–$FF17)
;
; The native NMI and IRQ vectors can only point into bank $00, so they
; land here and jump on through 4-byte trampolines in WRAM ($0500, $0504)
; that the game rewrites as it changes mode. The trampolines are not set
; by MainInit; see !NmiTrampoline / !IrqTrampoline in ram_engine.inc for
; who installs and repoints them.
; Entry: native mode, interrupt taken (M, X, D, DB as the interrupted code
;        left them; the CPU has pushed PB, PC and P)
; Exit:  nothing changed; control continues at the trampoline, whose
;        handler ends in RTI
; ============================================================
NMI_Stub:               ; native NMI vector target (see $FFEA)
    JML !NmiTrampoline

IRQ_Stub:               ; native IRQ vector target (see $FFEE)
    JML !IrqTrampoline

; ============================================================
; BRK_Handler ($FF18) — native BRK and emulation-mode COP both land here
;
; A crash trap: it reads a fixed, recognizable address forever and never
; returns. The value read is discarded; the read itself is what an
; external bus trace or debugger can see (inferred, see
; !CrashMarkerRead).
; Entry: any (an unexpected BRK/COP)
; Exit:  never returns
; ============================================================
BRK_Handler:
    LDA.l !CrashMarkerRead
    BRA BRK_Handler

    db $FF,$FF          ; unused fill $FF1E–$FF1F

; ============================================================
; Bitmask lookup tables ($FF20–$FF2F)
; BitSet[N] = (1 << N), BitClear[N] = ~(1 << N), for N = 0..7.
; Used for testing/setting/clearing single bits in flag bytes.
; ============================================================
BitSet:                 ; $FF20 — bit N set, others clear
    db $01,$02,$04,$08,$10,$20,$40,$80

BitClear:               ; $FF28 — bit N clear, others set
    db $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F

; ============================================================
; Wave tables ($FF30–$FFAF)
; One period of a sine-like wave between -6 and +6 (32 signed 16-bit
; entries), stored twice. Two routines read it, at $FD:C5A7 and $FD:C6F7
; (the table reads start at $FD:C5F3 / $FD:C743). Each masks a phase with
; AND #$3E, then makes 16 reads, $C0FF30,X, $C0FF34,X, ... $C0FF6C,X (a
; step of 4 per output), adds the word at $1D8F with ADC.l $001D8F and
; stores to $1D27, $1D2B, ... (first routine) or $1DA7 ... $1DE3 (second).
; There is no CLC between outputs, so a carry from one sum passes into the
; next; reproduced as found, effect not traced.
; The reads run past A into B (up to $FFAB), so B is A's second period:
; it lets them read ahead without masking each index.
; What the outputs drive is not traced yet; "Scroll" in the names is a
; guess.
; ============================================================
ScrollWaveA:            ; $FF30 (32 × sint16)
    dw  $0000,$0001,$0002,$0003,$0004,$0005,$0005,$0006
    dw  $0006,$0006,$0005,$0005,$0004,$0003,$0002,$0001
    dw  $0000,$FFFF,$FFFE,$FFFD,$FFFC,$FFFB,$FFFB,$FFFA
    dw  $FFFA,$FFFA,$FFFB,$FFFB,$FFFC,$FFFD,$FFFE,$FFFF

ScrollWaveB:            ; $FF70 (32 × sint16: A's second period)
    dw  $0000,$0001,$0002,$0003,$0004,$0005,$0005,$0006
    dw  $0006,$0006,$0005,$0005,$0004,$0003,$0002,$0001
    dw  $0000,$FFFF,$FFFE,$FFFD,$FFFC,$FFFB,$FFFB,$FFFA
    dw  $FFFA,$FFFA,$FFFB,$FFFB,$FFFC,$FFFD,$FFFE,$FFFF

; ============================================================
; SNES cartridge header ($FFB0–$FFDF), standard layout
; ============================================================
RomExtHeader:           ; $FFB0 — extended header (present: $FFDA = $33)
    db "C3"             ; maker code
    db "ACTE"           ; game code
    db $00,$00,$00,$00,$00,$00,$00  ; $FFB6–$FFBC reserved
RomExpansionRam:        ; $FFBD — no expansion RAM
    db $00
RomSpecialVersion:      ; $FFBE — normal release
    db $00
RomCartridgeSubtype:    ; $FFBF — none
    db $00

ROMTitle:               ; $FFC0 — 21 bytes, space-padded
    db "CHRONO TRIGGER       "
RomMapMode:             ; $FFD5 — HiROM ($21) + FastROM ($10)
    db $31
RomType:                ; $FFD6 — ROM + RAM + battery (the save SRAM)
    db $02
RomSize:                ; $FFD7 — 2^12 KiB = 4 MiB
    db $0C
RomSramSize:            ; $FFD8 — 2^3 KiB = 8 KiB
    db $03
RomRegion:              ; $FFD9 — North America
    db $01
RomDeveloperId:         ; $FFDA — $33: the extended header at $FFB0 is valid
    db $33
RomVersion:             ; $FFDB — 1.0
    db $00
RomChecksumComplement:  ; $FFDC
    dw $8773
RomChecksum:            ; $FFDE — sum of all ROM bytes; complement + checksum = $FFFF
    dw $788C

; ============================================================
; Interrupt vector table ($FFE0–$FFFF)
; Native mode: $FFE4–$FFEF. Emulation mode: $FFF4–$FFFF. $FFFF entries
; are slots the game never uses; $FFEC and $FFF6 are reserved by the CPU
; (there is no native RESET vector: reset always starts in emulation mode).
; ============================================================
RomVectors:
    db $FF,$FF,$FF,$FF  ; $FFE0–$FFE3 unused

    ; Native mode
    dw $FFFF            ; $FFE4 COP    (unused)
    dw BRK_Handler      ; $FFE6 BRK
    dw $FFFF            ; $FFE8 ABORT  (unused)
    dw NMI_Stub         ; $FFEA NMI
    dw $FFFF            ; $FFEC reserved
    dw IRQ_Stub         ; $FFEE IRQ

    db $FF,$FF,$FF,$FF  ; $FFF0–$FFF3 unused

    ; Emulation mode
    dw BRK_Handler      ; $FFF4 COP    (same crash trap as BRK)
    dw $FFFF            ; $FFF6 reserved
    dw $FFFF            ; $FFF8 ABORT  (unused)
    dw $FFFF            ; $FFFA NMI    (unused: NMI is off after reset, NMITIMEN=0, during
                        ;               the three instructions Reset runs in emulation mode)
    dw Reset            ; $FFFC RESET  → boot
    dw $FFFF            ; $FFFE IRQ/BRK (unused)
