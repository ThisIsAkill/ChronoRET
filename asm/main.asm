; ============================================================
; Chrono Trigger (SNES) — Decompilation entry point
;
; This file is fed to `asar` along with the original ROM as a
; base. Anything NOT overridden here is left untouched (asar's
; "patch over base ROM" mode), which is what lets us match the
; project incrementally: unmatched regions of the ROM stay as
; original bytes, matched regions get replaced by our labeled,
; reassembled source below.
; ============================================================

; --- Shared names (no bytes emitted) ---
; Defines must be visible before any bank uses them.

incsrc "include/constants.inc"
incsrc "include/constants_engine.inc"
incsrc "include/constants_battle.inc"
incsrc "include/ram_engine.inc"
incsrc "include/ram_battle.inc"
incsrc "include/macros.inc"

; --- Bank includes ---
; As banks get mapped and functions get matched, include their
; .asm files here. Until a bank has ANY matched content, leave
; it commented out — asar will just use the original ROM bytes
; for anything not explicitly included.

incsrc "bank00/bank00.asm"
incsrc "bankC0/bankC0.asm"
incsrc "bankC1/bankC1.asm"
incsrc "bankCC/bankCC.asm"

incsrc "bankC2/bankC2.asm"
incsrc "bankCF/bankCF.asm"
; incsrc "bank01/bank01.asm"
; incsrc "bank02/bank02.asm"
incsrc "bankFD/bankFD.asm"
incsrc "bankFF/bankFF.asm"

; --- Names for not-yet-matched routines (label-only, no bytes) ---
incsrc "include/unmatched.asm"
incsrc "include/unmatched_battle.asm"
