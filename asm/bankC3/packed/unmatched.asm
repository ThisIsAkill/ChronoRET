; ============================================================
; Names for module code not matched yet (label-only, no bytes)
; Included at the end of module.asm. Each stub puts a label at a
; module address inside the ROM's bytes (%C3ModRomBytes); it moves to
; module.asm as a routine once matched.
; ============================================================

; The programs of C3Mod_ProgramTable, by entry number (what each one is
; has not been traced).
%C3ModOrg($7E7092)
C3Mod_Prog5:
%C3ModOrg($7E78DD)
C3Mod_Prog6:
%C3ModOrg($7E8538)
C3Mod_Prog10:
%C3ModOrg($7E8E95)
C3Mod_Prog12:
%C3ModOrg($7E8EA8)
C3Mod_Prog13:

; Module code (and operands written at run time) that matched code
; names, by address (what they are has not been traced).
%C3ModOrg($7E73C6)
C3Mod_Unk73C6:
%C3ModOrg($7E7441)
C3Mod_Unk7441:
%C3ModOrg($7E783C)
C3Mod_Unk783C:
%C3ModOrg($7E7841)
C3Mod_Unk7841:
