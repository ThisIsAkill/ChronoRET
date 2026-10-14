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
org $C2C9E5
Menu_UnkC9E5:       ; Menu_MainPreviewTable entry 4 (not analysed)
org $C2D065
Menu_UnkD065:       ; Menu_MainPreviewTable entry 5 (not analysed)
org $C2CAE6
Menu_UnkCAE6:       ; Menu_MainRedrawTable entry 4 (not analysed)
org $C2D0DB
Menu_UnkD0DB:       ; Menu_MainRedrawTable entry 5 (not analysed)
org $C2C54F
Menu_UnkC54F:       ; JSR from mode 4: Menu_ButtonMap = MenuRom_DefaultButtonMap, or Menu_CfgButtonMap with
                    ; Menu_CfgA4 set, then the map drawn (Menu_UnkC57A); its first byte is Menu_WindowVramRec's
                    ; last (not matched)
org $C2C57A
Menu_UnkC57A:       ; JSR from Menu_Icon3Preview: the six button map rows' button tiles (not matched)
org $C2C5C7
Menu_UnkC5C7:       ; JMP from Menu_CfgMapAssign (not matched)
org $C2C627
Menu_Mode05H0:      ; Menu_Mode05List entry 0 (not analysed)
org $C2C65D
Menu_Mode05H1:      ; Menu_Mode05List entry 1 (not analysed)
org $C2C6B9
Menu_Mode05H2:      ; Menu_Mode05List entry 2 (not analysed)
org $C2C7AC
Menu_Mode07H0:      ; Menu_Mode07List entry 0 (not analysed)
org $C2C7E0
Menu_Mode07H1:      ; Menu_Mode07List entry 1 (not analysed)
org $C2CEDC
Menu_Mode06H0:      ; Menu_Mode06List entry 0 (not analysed)
org $C2CEFD
Menu_Mode06H1:      ; Menu_Mode06List entry 1 (not analysed)
org $C2CF61
Menu_Mode06H2:      ; Menu_Mode06List entry 2 (not analysed)
org $C2CF92
Menu_Mode06H3:      ; Menu_Mode06List entry 3 (not analysed)
org $C2D4F8
Menu_Mode0BH0:      ; Menu_Mode0BList entry 0 (not analysed)
org $C2D506
Menu_Mode0BH1:      ; Menu_Mode0BList entry 1 (not analysed)
org $C2D52B
Menu_Mode0CH0:      ; Menu_Mode0CList entry 0 (not analysed)
org $C2D546
Menu_Mode0CH1:      ; Menu_Mode0CList entry 1 (not analysed)
org $C2D58B
Menu_Mode0CH2:      ; Menu_Mode0CList entry 2 (not analysed)
org $C2D645
Menu_Mode0CH3:      ; Menu_Mode0CList entry 3 (not analysed)
org $C2D690
Menu_Mode0CH4:      ; Menu_Mode0CList entry 4 (not analysed)
org $C2D618
Menu_Mode0CH5:      ; Menu_Mode0CList entry 5 (not analysed)
org $C2D6C3
Menu_Mode0CH6:      ; Menu_Mode0CList entry 6 (not analysed)
org $C2D715
Menu_Mode0CH7:      ; Menu_Mode0CList entry 7 (not analysed)
org $C2D778
Menu_Mode0CH8:      ; Menu_Mode0CList entry 8 (not analysed)
org $C2E1ED
Menu_Mode0DH0:      ; Menu_Mode0DList entry 0 (not analysed)
org $C2E21E
Menu_Mode0DH1:      ; Menu_Mode0DList entry 1 (not analysed)
org $C2E236
Menu_Mode0DH2:      ; Menu_Mode0DList entry 2 (not analysed)
org $C2E201
Menu_Mode0DH3:      ; Menu_Mode0DList entry 3 (not analysed)
org $C2E209
Menu_Mode0DH4:      ; Menu_Mode0DList entry 4 (not analysed)
org $C2E613
Menu_Mode0EH0:      ; Menu_Mode0EList entry 0 (not analysed)
org $C2E61B
Menu_Mode0EH1:      ; Menu_Mode0EList entry 1 (not analysed)
org $C2E6AE
Menu_Mode0EH2:      ; Menu_Mode0EList entry 2 (not analysed)
org $C2E705
Menu_Mode0EH3:      ; Menu_Mode0EList entry 3 (not analysed)
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
