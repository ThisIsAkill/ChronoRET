; ============================================================
; constants.inc — Named constants shared across banks.
;
; Naming: !UpperCamel_Thing for values, grouped by subsystem with a
; one-line comment saying how the value was inferred. Bit flags are
; named for what the set bit means (e.g. !TargetMode_AllFlag = $80).
; ============================================================
!constants_inc ?= 0
if !constants_inc == 0
!constants_inc = 1

endif
