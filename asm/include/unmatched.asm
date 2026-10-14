; ============================================================
; unmatched.asm — Names for routines that matched code calls but that
; are not matched yet.
;
; Each entry is a label-only `org` stub: it emits no bytes, it only gives
; the call site a name instead of an address. When a routine gets
; matched, delete its stub here; the real label in the bank file takes
; over and every call site keeps working unchanged.
;
; Keeping these out of the bank files is deliberate: game code holds
; only game code (see tools/lint_readability.py, rule PLUMB).
; ============================================================

; --- Bank $C0 ---






; --- Bank $C0 field/scene callees (names from observed behavior; Unk
; --- where the body has not been read closely enough to say more) ---


; --- Other banks, called from bank $C0 ---

org $FFD024
MenuRom_SlotLocBounds: ; 26 rising bytes from 0 read by Menu_SlotLocName: the string of a save's
                    ; SRAM +$0603 byte is the last entry not above it
org $C6E74E
BankC6_UnkE74E:     ; JSL from C2Scene_ObjBFly: C2Tmp_06 = 0 when the tile (C2Tmp_00, $01) is inside
                    ; columns C2Tmp_04 to $05 - 1 and rows C2Tmp_02 to $03 - 1, else bits 0-3 for
                    ; left / right / above / below (not matched)
org $C6E797
BankC6_UnkE797:     ; JSL from C2Scene_ObjAFly before object A comes down: takes the task's 8x8 tile
                    ; and dispatches on Loc_Id - $1F0 through a table at $C6:E7BA; C=1 keeps it up
org $C31313
BankC3_PackedModule: ; packed data (Decomp_ToWram's format, 12-bit mode), $C3:1313-$C3:7A2B
                    ; (26,393 bytes): the bank $C3 module, 65816 code and its data, which
                    ; C3_BootModule unpacks to C3Mod_Code ($7E:3000-$7E:B57E, $857F bytes) and
                    ; jumps to. Pointed to by C3Rom_PackPtrs entry 1 ($FE:0003). Kept as ROM
                    ; bytes: matching its code needs it unpacked (and a packer that rebuilds
                    ; these exact bytes). $C3:1200-$C3:1312 before it is another pack
                    ; (C3Rom_PackPtrs entry 0; $400 bytes unpacked; user not traced).
