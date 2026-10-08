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

; --- Stack / fixed RAM ---
!StackTop        = $06FF     ; initial S (MainInit); stack grows down from $06FF
!NmiTrampoline   = $000500   ; 4 B: JML target of the native NMI stub ($00:FF10). Installed by
                             ; InstallNMI ($C0:0B64, from the GameLoop init path) as JML $C0:EA63;
                             ; set to RTI ($40) by $C0:2E4B and repointed into bank $FD by
                             ; $FD:EAF4 (JML $FD:DE15; called from $FD:DBB8). Not touched by MainInit.
!IrqTrampoline   = $000504   ; 4 B: JML target of the native IRQ stub ($00:FF14). Installed by
                             ; InstallIRQ ($C0:0B75) as JML $C0:ECCC; set to RTI by $C0:2E4B and
                             ; repointed by $FD:EAF4 (JML $FD:DE87), the routine that also
                             ; repoints the NMI trampoline.

endif
