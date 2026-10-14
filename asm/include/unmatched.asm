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
org $C2B8DA
Menu_UnkB8DA:       ; Menu_MainPreviewTable entry 2 (not analysed)
org $C2C2FF
Menu_UnkC2FF:       ; Menu_MainPreviewTable entry 3 (not analysed)
org $C2C9E5
Menu_UnkC9E5:       ; Menu_MainPreviewTable entry 4 (not analysed)
org $C2D065
Menu_UnkD065:       ; Menu_MainPreviewTable entry 5 (not analysed)
org $C2B960
Menu_UnkB960:       ; Menu_MainRedrawTable entry 2 (not analysed)
org $C2C397
Menu_UnkC397:       ; Menu_MainRedrawTable entry 3 (not analysed)
org $C2CAE6
Menu_UnkCAE6:       ; Menu_MainRedrawTable entry 4 (not analysed)
org $C2D0DB
Menu_UnkD0DB:       ; Menu_MainRedrawTable entry 5 (not analysed)
org $C2FA49
Menu_UnkFA49:       ; JSR from Menu_DrawDescText: clears a buffer row at Menu_TextDest, sets TextWin_*
                    ; and Menu_Unk0DC7-0DD7, then TextWin_Init (JSL BankC2_Entry0003) (not matched)
org $C2FC3E
Menu_VramRecBg3Rows60: ; Menu_VramRec in unmatched data: VRAM $6F80 (BG3 map row 60) = $7E:5D00, $100 bytes
org $C2FBEA
Menu_VramRecBg1Low: ; Menu_VramRec in unmatched data: VRAM $5C00 (BG1 map, lower half) = $7E:3600, $800 bytes
org $C2FC06
Menu_VramRecBg2Low: ; Menu_VramRec in unmatched data: VRAM $6400 (BG2 map, lower half) = $7E:4600, $800 bytes
org $C2FC1B
Menu_VramRecBg3:    ; Menu_VramRec in unmatched data: VRAM $6800 (BG3 map) = $7E:4E00, $680 bytes
org $C2FC45
Menu_VramRecBg3Rows58: ; Menu_VramRec in unmatched data: VRAM $6F40 (BG3 map row 58) = $7E:5C80, $100 bytes
org $C2FC37
Menu_VramRecBg3Rows0: ; Menu_VramRec in unmatched data: VRAM $6FC0 (BG3 map row 62) = $7E:4E00 (rows 0-1), $80 bytes
org $C2FC5A
Menu_VramRecDigits: ; Menu_VramRec in unmatched data: VRAM $5740 = $7E:8E80 (Menu_ShadowTiles), $140 bytes
org $C2B83E
Menu_UnkB83E:       ; JSR from Menu_UseHealItem (and $C2:B826): the HP / MP item's member cursor (with
                    ; Menu_UseKind bit 3 all members), sets Menu_UseTarget and Menu_Unk0DBC (not matched)
org $C2FBE3
Menu_VramRecClock:  ; Menu_VramRec in unmatched data: VRAM $5840 = $7E:2E80, $640 bytes (queued by
                    ; Menu_MainMenuLoop after the clock is drawn)
org $C2FBF8
Menu_VramRecBg2:    ; Menu_VramRec in unmatched data: VRAM $6000 = $7E:3E00 (Menu_Bg2Map), $1000 bytes
org $C2FBFF
Menu_VramRecBg2B:   ; Menu_VramRec in unmatched data: VRAM $6040 = $7E:3E80, $680 bytes (its first byte
                    ; is the last of Menu_VramRecBg2)
org $C2B35D
Menu_Mode03H0:      ; Menu_Mode03List entry 0 (not analysed)
org $C2B365
Menu_Mode03H1:      ; Menu_Mode03List entry 1 (not analysed)
org $C2B36D
Menu_Mode03H2:      ; Menu_Mode03List entry 2 (not analysed)
org $C2B3AE
Menu_Mode03H3:      ; Menu_Mode03List entry 3 (not analysed)
org $C2B48E
Menu_Mode03H4:      ; Menu_Mode03List entry 4 (not analysed)
org $C2BF3D
Menu_Mode04H0:      ; Menu_Mode04List entry 0 (not analysed)
org $C2BF45
Menu_Mode04H1:      ; Menu_Mode04List entry 1 (not analysed)
org $C2BF6D
Menu_Mode04H2:      ; Menu_Mode04List entry 2 (not analysed)
org $C2BF9F
Menu_Mode04H3:      ; Menu_Mode04List entry 3 (not analysed)
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
