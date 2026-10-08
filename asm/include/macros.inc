; ============================================================
; macros.inc — Named encodings for instructions asar cannot express
; the way the original ROM encodes them (see the wiki's asar Quirks
; page). Game code calls these instead of hand-writing opcode bytes,
; so every such spot reads as the instruction it is.
; ============================================================
!macros_inc ?= 0
if !macros_inc == 0
!macros_inc = 1

endif
