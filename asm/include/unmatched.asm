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
org $C2FCB2
Menu_ShopBuyQtyInit: ; JSR from Menu_Mode0CH2: Menu_ItemCount = 1, Menu_ShopPriceHi = 0, Menu_ShopPrice
                    ; and Menu_ShopUnitPrice = Menu_ShopBuyPrices[Menu_ItemId], then the gold divided by
                    ; it into Menu_ShopQuot (24 by 16 bits, by $C2:FD1D) (not matched)
org $C2FCE1
Menu_ShopSellQtyInit: ; JSR from Menu_Mode0CH3: the same with the sell price (Menu_ItemInfo1 / 2, rounded
                    ; up) and 9,999,999 - the gold as the dividend; no division (Menu_ShopQuot not
                    ; written) when the gold is above it (not matched)
org $C2FD58
Menu_UnkFD58:       ; JSR from Menu_ShopCalcPrices: probably Menu_ShopProduct = the Menu_Tmp00 word x
                    ; the Menu_ShopMulArg word, by Menu_UnkFD68 and a second pass (not matched)
org $C2FD68
Menu_UnkFD68:       ; JSR from Menu_ShopQtyRight: Menu_ShopProduct = 0, then for each of the
                    ; Menu_ShopMulLen bytes of Menu_ShopMulArg its product with Menu_Tmp00 added at
                    ; the byte's place (16-bit adds) (not matched)
org $C2FD97
Menu_ShopGainGold:  ; JSR from Menu_Mode0CH4: the gold (Menu_Unk2C53, 3 bytes) + Menu_ShopPrice, capped
                    ; at 9,999,999 ($C2:FDDF) (not matched)
org $C2FDBB
Menu_ShopPayGold:   ; JSR from Menu_Mode0CH5: the gold - Menu_ShopPrice, then the same cap (not matched)
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
