; ============================================================
; ram_engine.inc — Named WRAM / direct-page locations used by the
; engine core (banks $00, $C0, $FD).
;
; Conventions:
;   !Name = $addr            single variable or per-index array
;   struct Name $addr ...    multi-field records (asar struct; index
;                            with Name[i].Field when the record repeats)
; Every name carries a short comment: width, meaning, and how it was
; inferred (which routine reads/writes it).
;
; Direct page: bank $C0 code often runs with DP=$2100 (hardware
; registers). A dp operand there is a PPU register, not WRAM, so those
; use hardware.inc names via the !DP_ prefix defined below, never a
; WRAM name.
; ============================================================
!ram_engine_inc ?= 0
if !ram_engine_inc == 0
!ram_engine_inc = 1

endif
