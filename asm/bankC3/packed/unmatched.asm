; ============================================================
; Names for module code not matched yet (label-only, no bytes)
; Included at the end of module.asm. Each stub puts a label at a
; module address inside the ROM's bytes (%C3ModRomBytes); it moves to
; module.asm as a routine once matched.
; ============================================================

; The programs of C3Mod_ProgramTable, by entry number (what each one is
; has not been traced).
%C3ModOrg($7E6B04)
C3Mod_Prog1:
%C3ModOrg($7E671F)
C3Mod_Prog3:
%C3ModOrg($7E7092)
C3Mod_Prog5:
%C3ModOrg($7E78DD)
C3Mod_Prog6:
%C3ModOrg($7E6248)
C3Mod_Prog7:
%C3ModOrg($7E8538)
C3Mod_Prog10:
%C3ModOrg($7E8E95)
C3Mod_Prog12:
%C3ModOrg($7E8EA8)
C3Mod_Prog13:

; Module code (and operands written at run time) that matched code
; names, by address (what they are has not been traced).
%C3ModOrg($7E89ED)
C3Mod_Unk89ED:
%C3ModOrg($7E8752)
C3Mod_Unk8752:
%C3ModOrg($7E90A7)
C3Mod_Unk90A7:
