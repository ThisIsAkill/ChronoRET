; ============================================================
; ram_battle.inc — Named WRAM / direct-page locations used by the
; battle engine (bank $C1). Same conventions as ram_engine.inc.
;
; Battler slots: 0-2 = party (PCs), 3-10 = enemies. Arrays indexed by
; battler slot are named !Battler_<Field>; arrays indexed by PC slot
; only are named !Pc_<Field>.
; ============================================================
!ram_battle_inc ?= 0
if !ram_battle_inc == 0
!ram_battle_inc = 1

endif
