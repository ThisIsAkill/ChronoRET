; ============================================================
; constants_menu.inc — Named constants for bank $C2 (the menu/scene
; bank). Same conventions as constants_engine.inc; names start with
; `Menu` (see ram_menu.inc for why bank $C2 has its own files).
; ============================================================
!constants_menu_inc ?= 0
if !constants_menu_inc == 0
!constants_menu_inc = 1

; --- ROM data read by matched bank-$C2 code (not matched itself yet) ---
!MenuRom_DefaultConfig = $C2FCA6         ; 12 B copied to Menu_Config for a new game
!MenuRom_DefaultButtonMap = $C2FCA9      ; = MenuRom_DefaultConfig+3: the 9 B from the button map on,
                                         ; copied to Menu_Unk0408
!MenuRom_CharRecordInit = $CC0000        ; $280 B copied to Menu_CharRecords for a new game

; --- DMA ---
!MenuRom_DmaCopyBank = $FF              ; source bank of Menu_DmaCopyFFToWram

; --- WRAM / VRAM clears (Menu_InitPpuAndRam, Menu_InitNewGameData) ---
!Menu_VramClearBytes = $FFFF             ; DMA count of the VRAM clear: one byte short of 64 KiB, so
                                         ; the high byte of word $7FFF is not written
!Menu_ClearMidStart = $0C00              ; first WRAM block zeroed: $7E:0C00-$1DFF
!Menu_ClearMidSize = $1200
!Menu_ClearHighStart = $2E00             ; second: $7E:2E00-$FFFF
!Menu_ClearHighSize = $D200
!Menu_ClearDpSize = $0100                ; third: $7E:0000-$00FF (the direct page)
!Menu_Unk2400Size = $0200                ; bytes in Menu_Unk2400
!Menu_CharRecordInitSize = $0280         ; bytes copied from MenuRom_CharRecordInit
!Menu_PartyOrderSize = 9                 ; entries in Menu_PartyOrder
!Menu_PartyEmpty = $80                   ; Menu_PartyOrder entry: no character (bit 7 set)
!Menu_Unk2C7CSize = 30                   ; bytes in Menu_Unk2C7C
!Menu_FlagBlock7FSize = $0200            ; bytes in Menu_FlagBlock7F
!Menu_Page04Size = $0100                 ; bytes zeroed from Menu_PlayTime: the whole page $0400-$04FF
!Menu_ConfigSize = 32                    ; bytes zeroed from Menu_Config
!Menu_DefaultConfigSize = 12             ; bytes copied from MenuRom_DefaultConfig
!Menu_Unk0408Size = 9                    ; bytes copied to Menu_Unk0408

; --- Scene mode (BankC2_Entry0000) ---
!C2Scene_DpClearCount = $00EE            ; C2Scene_ClearDp MVN count - 1: $EF bytes from $01 (with the
                                         ; STZ of $00 that is dp $00-$EF)
!C2Scene_InitBgMode = $09                ; C2Scene_BgModeShadow at boot: mode 1, BG3 on top
!C2Scene_OamBytes = $0220                ; bytes DMAed to OAM each NMI: the 512 B low table and 32 B
                                         ; high table
!C2Scene_PaletteBytes = $0200            ; bytes DMAed to CGRAM: all 256 colors
!C2Scene_NmiUpdate = $01                 ; C2Scene_NmiFlags bit 0
!C2Scene_NmiPalette = $02                ; C2Scene_NmiFlags bit 1
!C2Scene_Unk0B20Size = $0010            ; bytes in C2Scene_Unk0B20
!C2Scene_FlagTailSize = $10             ; bytes in C2Scene_FlagTailCopy
!C2Scene_HalfScreenTilesX = $10          ; 16 tiles: half the 256-pixel screen width
!C2Scene_HalfScreenTilesY = $0E          ; 14 tiles: half the 224-pixel screen height
!C2Scene_MapTilesX = $C0                 ; C2Scene_SetStartScroll wraps X into 0-191 (probably the map
                                         ; width in tiles)
!C2Scene_MapTilesY = $80                 ; and Y into 0-127
!C2Scene_VramQEntrySize = 8              ; bytes per C2Scene_VramQ entry

; --- Scene tasks and sprite list ---
!C2Scene_TaskSize = $40                  ; bytes per C2Scene_Task record
!C2Scene_TaskCount = 64                  ; records in C2Scene_TaskRecords
!C2Scene_TaskLowSlots = 4                ; records 0-3: only C2Scene_TaskSpawnLow uses them
!C2Scene_TaskCopyStart = 5               ; C2Scene_TaskSpawn copies record bytes from here on
!C2Scene_TaskCopyCount = $003A           ; MVN count - 1: the $3B bytes +$05-$3F
!C2Scene_SprNodeSize = $10               ; bytes per C2Scene_SprNode
!C2Scene_SprNodeCount = 64               ; nodes in C2Scene_SprNodes
!C2Scene_SprLinkSize = 4                 ; bytes per C2Scene_SprLinkInit entry
!C2Scene_SprResetGroup = 8               ; nodes per pass of C2Scene_SprResetLists' copy loop
!C2Scene_SprAttrFront = $01              ; C2Scene_SprNode.Attr bit 0: kept at the front of the
                                         ; active list (drawn first, so on top), in the order added
!C2Scene_SprAttrScroll = $80             ; .Attr bit 7: .X/.Y are BG2 coordinates (C2Scene_SprDrawNode
                                         ; subtracts the BG2 scroll)
!C2Scene_SprAttrOamMask = $3E00          ; .Attr bits 1-5 moved to the high byte: the OAM
                                         ; palette and priority bits
!C2Scene_SprTileMask = $3FFF             ; .Tile bits added to each piece's tile word
!C2Scene_SprTileLarge = $40              ; .Tile high byte bit 6: large sprites (OAM size bit)
!C2Scene_SprWrapW = $0600                ; BG2-relative X is wrapped into -$300..$2FF
!C2Scene_SprWrapH = $0400                ; BG2-relative Y is wrapped into -$200..$1FF
!C2Scene_SprClipMargin = 15              ; a piece is drawn only if X is in -15..255 and Y in -15..223
!C2Scene_SprClipW = (256+!C2Scene_SprClipMargin)
!C2Scene_SprClipH = (224+!C2Scene_SprClipMargin)
!C2Scene_ByteSignBit = $0080            ; bit 7 of a byte read with 16-bit A: the sign of a frame's
                                         ; X/Y offset (C2Scene_SprDrawNode sign-extends it)
!C2Scene_OamSlotMask = $7F               ; low-table slot = C2Scene_OamNext AND this (128 sprites)
!C2Scene_OamEntrySize = 4                ; bytes per sprite in the OAM low table
!C2Scene_HidePassBytes = (8*4)           ; C2Scene_HideAllSprites: 8 sprites per pass, in each quarter
!C2Scene_SoundCmdSending = $FF           ; C2Scene_SoundCmdState while the command is being sent

; --- Joypad and play time ---
!Menu_Dp = $0000                         ; direct page of the pad reader (and of the menu and scene code)
!Menu_PadAutoReadBusy = $01              ; HVBJOY bit 0: the auto-joypad read is still running
!Menu_PadJoy1LMask = $F0                 ; JOY1L bits kept: A X L R
!Menu_PadSoftReset = $3030               ; JOY1 with exactly L, R, Select and Start held: soft reset
!Menu_PlayTimeDp = $0400                 ; direct page Menu_TickPlayTime points at (Menu_PlayTime)
!Menu_PlayTimeSize = 6                   ; bytes in Menu_PlayTime and Menu_PlayTimeLimits

; --- Text window ---
!TextWin_StatusStart = 4                 ; TextWin_Status after TextWin_Init
!TextWin_ModeUnk2 = 2                    ; TextWin_Mode value that starts lines 8 pixels further left
!TextWin_ModeMask = $0F                  ; TextWin_Mode bits compared with TextWin_ModeUnk2 on a pen reset
!TextWin_PenXLeft = 8                    ; pen X at the start of a string and for statuses 5, 7, 9, 11
!TextWin_PenXIndent = $14                ; pen X for statuses 6, 8, 10, 12 (probably an indented line;
                                         ; inferred only from the larger X)

endif
