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

; --- Bank includes ---
; As banks get mapped and functions get matched, include their
; .asm files here. Until a bank has ANY matched content, leave
; it commented out — asar will just use the original ROM bytes
; for anything not explicitly included.

incsrc "bank00/bank00.asm"
incsrc "bankC0/bankC0.asm"
; incsrc "bank01/bank01.asm"
; incsrc "bank02/bank02.asm"
incsrc "bankFD/bankFD.asm"

; --- Status ---
; No banks included yet. This file currently produces a
; byte-identical copy of the base ROM when built, which is the
; correct starting state (verify with `make diff`).
