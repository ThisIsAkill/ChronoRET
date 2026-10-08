; ============================================================
; constants_engine.inc — Named constants for the engine core (banks $00, $C0, $FD).
; Same conventions as constants.inc: !Subsystem_Thing, grouped, each
; with a one-line note on what it means and how that was inferred.
; ============================================================
!constants_engine_inc ?= 0
if !constants_engine_inc == 0
!constants_engine_inc = 1

; --- Crash trap ---
!CrashMarkerRead = $ABCDEF   ; read forever by BRK_Handler; a ROM address (HiROM mirror of
                             ; file offset $2BCDEF), value discarded. Inferred: chosen to be
                             ; recognizable on a bus trace, not to fetch data.

endif
