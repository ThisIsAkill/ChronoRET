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

; --- Scene loading (C2Scene_LoadScene and the C2Scene_Load* routines) ---
; ROM tables in bank $C6. Each pack table holds 3-byte long pointers to
; packed data that Decomp_ToWramVec unpacks; a header byte (below) is
; the entry number, and a byte with bit 7 set loads nothing.
!C2SceneRom_HeaderTable = $C6FD00        ; 16-bit address (bank $C6) of each scene's header, indexed by
                                         ; (Loc_Id AND C2Scene_LocIdMask) - Loc_FirstBankC2
!C2SceneRom_HeaderBank = $C6             ; bank of the headers (C2Scene_GetHeaderPtr)
!C2SceneRom_ObjPacks = $C6FDF0           ; sprite graphics packs (C2Scene_LoadObjGfx; entry 0 is the
                                         ; party's, C2Scene_LoadPartyGfx)
!C2SceneRom_BgPacks = $C6FE20            ; BG graphics packs (C2Scene_LoadBgGfx, C2Scene_LoadBg3Gfx,
                                         ; C2Scene_LoadUnkB800)
!C2SceneRom_PalettePacks = $C6FEA0       ; palette packs (C2Scene_LoadPalettes; entry 0 is the party's;
                                         ; also C2Scene_LoadUnkC000)
!C2SceneRom_MetatilePacks = $C6FF00      ; C2Scene_LoadMetatiles
!C2SceneRom_MapPacks = $C6FF20           ; C2Scene_LoadBgMaps
!C2SceneRom_Bg3MapPacks = $C6FF40        ; C2Scene_LoadBg3Map
!C2SceneRom_Unk7000Packs = $C6FF80       ; C2Scene_LoadUnk7000
!C2SceneRom_Unk7200Packs = $C6FFA0       ; C2Scene_LoadUnk7200
!C2SceneRom_ListPacks = $C6FFC0          ; C2Scene_LoadLists
!C2SceneRom_ScriptPacks = $C6FFE0        ; C2Scene_LoadScript
!C2SceneRom_LastPalRow = $C6F620         ; 32 B (33 copied) for colors $F0-$FF of C2Scene_PaletteBuf
                                         ; (C2Scene_LoadVram)
!C2Scene_PackEntrySize = 3               ; bytes per pack-table entry (a long pointer)
!C2Scene_LocIdMask = $01FF               ; Loc_Id bits that give the location number
; Scene header: byte offsets (each byte a pack number, bit 7 = none).
!C2Scene_HdrBgGfx = $00                  ; 7 bytes: BG graphics packs (C2Scene_LoadBgGfx)
!C2Scene_HdrUnkB800 = $07                ; C2Scene_LoadUnkB800
!C2Scene_HdrBg3Gfx = $08                 ; C2Scene_LoadBg3Gfx
!C2Scene_HdrPalettes = $0A               ; C2Scene_LoadPalettes
!C2Scene_HdrUnkC000 = $0B                ; C2Scene_LoadUnkC000
!C2Scene_HdrObjGfx = $0C                 ; 4 bytes: sprite graphics packs (C2Scene_LoadObjGfx)
!C2Scene_HdrMetatiles = $10              ; C2Scene_LoadMetatiles
!C2Scene_HdrMaps = $11                   ; C2Scene_LoadBgMaps
!C2Scene_HdrUnk7000 = $12                ; C2Scene_LoadUnk7000
!C2Scene_HdrUnk7200 = $13                ; C2Scene_LoadUnk7200
!C2Scene_HdrBg3Map = $14                 ; C2Scene_LoadBg3Map
!C2Scene_HdrLists = $15                  ; C2Scene_LoadLists
!C2Scene_HdrScript = $16                 ; C2Scene_LoadScript
!C2Scene_ObjPackCount = 4                ; sprite graphics packs per scene
!C2Scene_BgPackCount = 7                 ; BG graphics packs per scene
!C2Scene_PackSlotSize = $1000            ; C2Scene_DecompBuf bytes per graphics pack
!C2Scene_PartyObjPack = 0                ; C2SceneRom_ObjPacks entry: the party's sprite graphics
!C2Scene_UnkC800Pack = 1                 ; C2SceneRom_ObjPacks entry C2Scene_LoadUnkC800 unpacks
!C2Scene_PartyPalPack = 0                ; C2SceneRom_PalettePacks entry: the party's palettes
!C2Scene_ExtraObjPack = 3                ; C2SceneRom_ObjPacks entry of C2Scene_LoadExtraObjPack
!C2Scene_ExtraPalPack = 3                ; C2SceneRom_PalettePacks entry of C2Scene_LoadExtraPalette
!C2Scene_UnkC600Pack = $12               ; C2SceneRom_PalettePacks entry of C2Scene_LoadUnkC600
!C2Scene_PartyGfxSize = $0400            ; party graphics bytes per character (C2Scene_CopyPartyGfx)
!C2Scene_PartyGfxBSize = $40             ; and in each of the two extra blocks (C2Scene_CopyPartyGfxB)
!C2Scene_PartyGfxBGap = $0200            ; distance between those two blocks (source and destination)
!C2Scene_PartyPalSize = $10              ; party palette bytes copied per character (8 colors)
!C2Scene_PartyPalStride = 32             ; bytes per character in C2Scene_PartyPalSrc (as a shift: 5)
!C2Scene_PalRowBytes = $0020             ; bytes in one 16-color palette row (C2SceneRom_LastPalRow)
!C2Scene_LastPalRowDest = $0B00          ; = C2Scene_PaletteBuf + $1E0: colors $F0-$FF
!C2Scene_Gray1 = $14A5                   ; BGR555 (5,5,5): the colors C2Scene_LoadVram puts at
!C2Scene_Gray2 = $294A                   ; (10,10,10)      $7F:8D02-$8D07 (sprite palette 0, colors 1-3)
!C2Scene_Gray3 = $6B5A                   ; (26,26,26)
!C2Scene_HdmaAreaPasses = $0200          ; C2Scene_ClearHdmaArea passes, 4 bytes each
!C2Scene_HdmaValueA916Init = $A925       ; C2Scene_ReloadScene's value for C2Scene_HdmaValueA916 (use not
                                         ; traced)
!C2Scene_ExtraGfxFlagMin = $D4           ; C2Scene_LoadLocExtraGfx does nothing while Eng_Unk7F0000 is
                                         ; below this
!C2Scene_Unk0294Bit2 = $04               ; the C2Scene_Unk0294 bit C2Scene_LoadScene clears
!C2Scene_Unk1B32Init = $FFFF             ; C2Scene_LoadScene's value for the three C2Scene_Unk1B32 words
; VRAM word addresses and DMA byte counts (BankC2_InitHwRegs: sprite
; tiles at $0000, BG1/BG2 tiles at $2000, BG3 tiles at $7000, BG3 map at
; $7800).
!C2Scene_VramObj = $0000
!C2Scene_ObjGfxBytes = $4000             ; the four sprite packs
!C2Scene_VramPartyGfx = $1000            ; where C2Scene_PartyGfx goes
!C2Scene_PartyGfxBytes = $1000
!C2Scene_VramBgGfx = $2000
!C2Scene_BgGfxBytes = $7000              ; the seven BG packs
!C2Scene_VramBg3Gfx = $7000
!C2Scene_VramBg3Map = $7800
!C2Scene_PackBytes = $1000               ; one pack (C2Scene_LoadBg3Gfx, C2Scene_LoadBg3Map)
!C2Scene_VramExtraObj = $0C00            ; C2Scene_LoadLocExtraGfx's sprite tiles (Loc_Id $01F0-$01F2)
!C2Scene_ExtraObjBytes = $0800
!C2Scene_ExtraPalA = $0A40               ; C2Scene_PaletteBuf + $120: colors $90-$9F (Loc_Id $01F0, $01F2)
!C2Scene_ExtraPalB = $0A80               ; colors $B0-$BF (Loc_Id $01F1, bit 7 of C2Scene_FlagTailByte1
!C2Scene_ExtraPalC = $0A60               ; clear) or colors $A0-$AF (set)
!C2Scene_FlagTailBit7 = $80
; C2Scene_SaveState / C2Scene_RestoreState block sizes
!C2Scene_SaveDpBytes = $00F0             ; dp $00-$EF
!C2Scene_SaveLowStart = $0700            ; low WRAM block: $0700-$1DFF
!C2Scene_SaveLowBytes = $1700
!C2Scene_SaveSprBytes = $0508            ; C2Scene_SprNodes ($400), C2Scene_SprLinkInit ($100), the heads (8)
!C2Scene_SaveMapBytes = $3000            ; two C2Scene_MapBytes maps
!C2Scene_SaveUnk7200Bytes = $0C00        ; $7E:7200-$7DFF
!C2Scene_SaveListBytes = $0800           ; $7E:7E00-$85FF
; BG layer redraw (C2Scene_DrawBgLayer)
!C2Scene_LayerMask = 3                   ; C2Scene_DrawLayer is taken AND this (0 hangs)
!C2Scene_PxMetaRowMask = $00F0           ; pixel Y bits giving the metatile row within 256 pixels
!C2Scene_MapCols = $60                   ; 96 metatile columns per layer map (16 px each: 1536 px)
!C2Scene_MapRows = $40                   ; 64 rows
!C2Scene_MapBytes = (!C2Scene_MapCols*!C2Scene_MapRows) ; $1800
!C2Scene_MapWidthPx = (!C2Scene_MapCols*!C2Scene_MetatilePx) ; 1536: C2Scene_WrapTaskPos wraps X here
!C2Scene_MapHeightMask = ((!C2Scene_MapRows*!C2Scene_MetatilePx)-1) ; $3FF: and Y with this (1024 px)
!C2Scene_DrawCols = 18                   ; columns drawn per redraw (288 px: the screen and a margin)
!C2Scene_DrawRows = 16                   ; metatiles per column (256 px of the 32-tile map height)
!C2Scene_MetatilePx = $10                ; 16 pixels per metatile
!C2Scene_TilePx = 8                      ; 8 pixels per tile
!C2Scene_BgXMask = $01FF                 ; BG pixel X wraps at 512 (64-tile map)
!C2Scene_BgYMask = $00FF                 ; BG pixel Y wraps at 256 (32-tile map)
!C2Scene_ColBufHalf = $40                ; bytes per tile column in the column buffer (32 words)
!C2Scene_ColBufMask = $3F                ; byte offset wraps within one tile column
!C2Scene_ColRowStep = 4                  ; buffer bytes per metatile row (two tile words)
!C2Scene_MapScreenCols = $20             ; tile columns in the left 32x32 screen of a 64x32 map
!C2Scene_MapScreen2Skip = $03E0          ; added to reach the right screen: $400 words - 32
; BG layer scroll (C2Scene_Unk0568 / C2Scene_Unk066C and their edge builders)
!C2Scene_PxInTileMask = $0007            ; pixel bits within one tile
!C2Scene_MapHeightPx = (!C2Scene_MapHeightMask+1) ; 1024: BG pixel Y of a layer wraps here
!C2Scene_EdgeAheadCols = $20             ; the column built on a scroll right: 32 tiles right of the edge
!C2Scene_EdgeAheadRows = $1C             ; the row built on a scroll down: 28 tiles (224 px) below it
!C2Scene_EdgeRightPx = $0100             ; its pixel X: 256 px right of the scroll
!C2Scene_EdgeBottomPx = $00E0            ; its pixel Y: 224 px below the scroll
!C2Scene_EdgeColTiles = $1E              ; tiles built per column (30: 240 px)
!C2Scene_EdgeRowTiles = $22              ; tiles built per row (34: 272 px)
!C2Scene_PxTileRowMask = $00F8           ; pixel Y bits giving the tile row within 256 px
!C2Scene_PxTileColMask = $01F8           ; pixel X bits giving the tile column within 512 px
!C2Scene_RowBufMask = $7F                ; byte offset wraps within one 64-tile row
!C2Scene_RowBufHalf = $40                ; bytes of one 32x32 screen's part of a row (32 words)

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
!C2Scene_SprAttrHold = $40               ; C2Scene_Task.SprAttr bit 6: C2Anim_OpShowFrame holds the frame
                                         ; (neither loads nor counts .AnimTimer)
!C2Scene_SprAttrKeepPal = $F1            ; .SprAttr bits kept by C2Script_SetSprPalette (it replaces 1-3)
!C2Scene_SprAttrKeepPrio = $4F           ; .SprAttr bits kept by C2Script_SetSprPriority (it replaces 4,
                                         ; 5 and 7)
!C2SceneRom_AnimTable = $C3E000          ; 16-bit addresses of the animation scripts (C2Scene_SetAnim)
!C2SceneRom_AnimBank = $C3               ; their bank: the table's own
; --- Scene scripts (C2Scene_TaskRunScript and the C2Script_* ops) ---
!C2Script_SpawnUnk1CF5Len = 10           ; bytes C2Script_SpawnUnk1CF5 advances (the opcode and 9 bytes it
                                         ; does not read itself)
!C2Script_CopyMapBlockLen = 9           ; bytes C2Script_CopyMapBlock advances (the opcode and 8 arguments)
!C2Scene_ReturnTileOfs = $10             ; tiles C2Script_GoToLocation adds to BG2's tile X and Y for the
                                         ; return position
!C2Scene_ModeUnk2 = 2                    ; C2Scene_Mode set by C2Script_GoToLocation (C2Scene_Mode2:
                                         ; restores the flag tail and turns the NMI off; probably leaves
                                         ; the scene)
!C2SceneRom_TurnAround = C2Scene_TurnAround ; 4 B at $C2:2509: facing 0-3 -> 1, 0, 3, 2 (the facing EOR 1, as the field's
                                         ; Loc_ReturnFacing; read by C2Script_GoToLocation)
!C2Scene_NoBg3PanBit0 = $10              ; C2Scene_FlagTailCopy byte 0 bit 4: C2Script_ScrollFrames leaves
                                         ; BG3 alone (as do the two below; meaning not traced)
!C2Scene_NoBg3PanBit3 = $20              ; byte 3 bit 5
!C2Scene_NoBg3PanBit8 = $02              ; byte 8 bit 1
!C2Scene_WholeMinus1 = $FFFF             ; -1 as the whole-pixel word (C2Script_PanKeepFraction)
!C2Scene_ListEntryBit7 = $80             ; bit 7 of the first byte of a C2Scene_ListA/B/C entry (set and
                                         ; cleared by script ops $44/$45; meaning not traced)
!C2Scene_ListTileMask = $3F7F            ; the first word of a ListA/B/C entry AND this: tile X (bits 0-6)
                                         ; and tile Y (bits 8-13), compared with the party's 16-pixel tile
                                         ; (C2Scene_FindTrigEntries)
!C2Scene_NoEntry = $FFFF                 ; C2Scene_FindTrigEntries' offset when a list has no entry at the
                                         ; tile (the same value as C2Scene_Unk1B32Init)
!C2Scene_ListAEntrySize = 7              ; bytes per C2Scene_ListA entry (C2Scene_LoadLists)
!C2Scene_ListBCEntrySize = 3             ; bytes per C2Scene_ListB / ListC entry
!C2Scene_SoundCmd10 = $10                ; sound command sent by script ops $3D/$4A with one argument
                                         ; (meaning not traced; the argument also goes to C2Scene_Unk02AE)
!C2Scene_SoundCmd18 = $18                ; sound command sent by script op $3B (as Audio_CmdPlaySfx's
                                         ; two arguments; meaning not traced)
!C2Scene_SoundArgUnused = $FF            ; argument bytes 2 and 3 of C2Scene_SoundCmd10
!C2Scene_MetatileSetBytes = $0800        ; layer 2's metatiles follow layer 1's (C2Scene_LayerMetatiles)
!C2Scene_MetatileRowBytes = 4            ; bytes of one row of a metatile: two tile words
!C2Scene_Bg1MapVram = $6000              ; VRAM word address of the BG1 tilemap (C2Scene_LayerVramMaps)
!C2Scene_Bg2MapVram = $6800              ; and of the BG2 tilemap
!C2Scene_TileColMask = $3F               ; tile column within the 64-column tilemap
!C2Scene_ScreenTileMask = $1F            ; tile column or row within one 32x32 screen
!C2Scene_TileRowWords = $20              ; VRAM words per tilemap row of one screen
!C2Scene_PalColors = $10                 ; colors per palette (16; 32 bytes of C2Scene_PaletteBuf)
!C2Scene_PalFadeSteps = $20              ; steps of a palette fade (C2Scene_TaskPalFade)
!C2Scene_ColorRedMask = $1F              ; BGR555 color: red, bits 0-4
!C2Scene_ColorGreenMask = $03E0          ; green, bits 5-9
!C2Scene_ColorGreenUnit = $0020          ; one step of green
!C2Scene_ColorBlueHiMask = $7C           ; blue, bits 10-14, as bits 2-6 of the high byte
!C2Scene_ColorBlueHiUnit = 4             ; one step of blue in the high byte
!C2Scene_FadeDownFlag = $80              ; fade step byte: counting down (the channel falls)
!C2Scene_FadeDownBias = $1F              ; a falling channel's count starts at its drop + this
!C2Scene_FadeCountMask = $3F             ; the count in a step byte (index into C2Scene_PalFadeStepTable)
!C2Scene_FadeInBusy = $01                ; C2Scene_Unk1BF6 bit 0: a fade-in runs
!C2Scene_FadeOutBusy = $02               ; C2Scene_Unk1BF6 bit 1: a fade-out runs
!C2Scene_FadeInStart = 1                 ; C2Scene_TaskUnk2105 .State: first step from forced blank
!C2Scene_FadeInDone = 3                  ; its .State that ends it (C2Scene_FadeInEnd)
!C2Scene_MosaicBgMask = $0F              ; MOSAIC bits 0-3: the BGs it applies to
!C2Scene_MosaicSizeMask = $F0            ; MOSAIC bits 4-7: the block size - 1
!C2Scene_MosaicSizeStep = $10            ; one step of the size
!C2Scene_SoundCmdQueued = 1             ; C2Scene_SoundCmdState: a command waits in the driver block
!C2Scene_SoundCmdSending = $FF           ; C2Scene_SoundCmdState while the command is being sent
; --- Scene modes (C2Scene_ModeTable's handlers) ---
!C2Scene_ModeIdle1 = 1                   ; C2Scene_Mode the handlers of modes 3, 5, 6, 8 and 9 set when done
                                         ; (an idle mode: C2Scene_ModeIdle)
!C2Scene_ModeMenu = 5                    ; the mode that calls BankC2_Entry8000 with C2Scene_MenuArgMenu (9
                                         ; passes ExitMenu_Mode5)
!C2Scene_ModeHalt = 4                    ; C2Scene_Mode4, which never leaves (set by C2Scene_TrigListC)
!C2Scene_ModeIdle7 = 7                   ; the third idle mode (C2Scene_ModeIdle)
!C2Scene_MenuArgMenu = 1                 ; BankC2_Entry8000 argument of mode 5, the value the field passes on
                                         ; a menu request ($C0:1960); probably the main menu
!C2Scene_ListANoLoc = $01FF              ; C2Scene_ListAEntry.Loc AND C2Scene_LocIdMask = this: no location;
                                         ; .EntryX then picks a C2Scene_ListD script (C2Scene_Mode3)
!C2Scene_FadeOutWaitFrames = $12         ; frames C2Scene_Mode3 and C2Scene_Mode8 wait for C2Scene_ScrFadeOut
!C2Scene_FadeWaitFrames = $11            ; frames modes 5 and 9 wait for each fade script, mode 8 after its
                                         ; fade-in
!C2Scene_Unk7F01F4Bits = $0A             ; C2Scene_Unk7F01F4 bits 1 and 3: C2Scene_Mode8 skips its reload
!C2Scene_Unk7F01F5Bit1 = $02             ; C2Scene_Unk7F01F5 bit 1: likewise
!C2Scene_Mode6OutFrames = $22            ; frames C2Scene_Mode6 waits for C2Scene_ScrMosaicFadeOut
!C2Scene_Mode6InFrames = $29             ; and for C2Scene_ScrMosaicFadeIn
!C2Scene_SoundCmd81 = $81                ; sound commands sent here; meanings not traced ($81 with arguments
!C2Scene_SoundCmd82 = $82                ; $0C,$00 and later $00,$FF looks like a volume fade out and back)
!C2Scene_SoundCmd83 = $83
!C2Scene_SoundArg80 = $80                ; third argument byte of the zone songs' C2Scene_SoundCmd10 (meaning
                                         ; not traced; script ops $3D/$4A pass $FF there)
!C2Scene_SoundFadeArg = $0C              ; first argument of the zone task's first C2Scene_SoundCmd81
!C2Scene_ZoneNone = $FF                  ; C2Scene_SoundZone: no zone looked up
!C2Scene_ZoneFadeFrames = $3C            ; frames the zone task waits between the two commands (60)
!C2Scene_ZoneRowBytes = $30              ; bytes per row of the zone map (96 metatiles, 4 bits each)
!C2Scene_ZoneMask = $0F                  ; a zone number (one nibble)
!C2Scene_ViewMidCol = 8                  ; metatiles from BG1's left edge to the middle of the view (128 px)
!C2Scene_ViewMidRow = 7                  ; and from its top (112 px)

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

!TextWin_DictPtrs = $DEFA00              ; 16-bit pointers (in bank $DE) to the dictionary sub-strings: a
                                         ; length byte, then that many glyph bytes (TextWin_State0)
!TextWinRom_TechNames = $CC15C4          ; 11-byte names (code $12 $00); entry 1 spells "Cyclone" with $A0 =
                                         ; "A" (TextWin_HexGlyphs) and $BA = "a": probably the techs
!TextWinRom_EnemyNames = $CC6500         ; 11-byte names (code $12 $01); entry 1 spells "Reptite": probably
                                         ; the enemies
!TextWinRom_ItemNames = $CC0B5E          ; 11-byte names, an icon byte first (code $1F, of
                                         ; Treasure_ItemId); entry 1 spells "Wood" $FF "Sword"
!TextWin_FirstGlyph = $A0                ; string bytes from here up are glyphs (TextWin_State0)
!TextWin_FirstDict = $21                 ; bytes $21-$9F are dictionary entries 0-$7E (TextWin_DictPtrs)
!TextWin_Code12Dict = 8                  ; after code $12, bytes from 8 up are dictionary entries $1F on
!TextWin_Code12DictBase = $1F
!TextWin_StatusStepDone = $10            ; TextWin_Status when TextWin_StepCount runs out
!TextWin_StateDict = 1                   ; TextWin_State values: 1 = a sub-string of glyphs (State1)
!TextWin_StateDec = 2                    ; 2 = decimal digits 0-9 (State2)
!TextWin_StateHex = 3                    ; 3 = glyph codes from TextWin_Digits (State3)
!TextWin_Wide1 = 1                       ; glyph prefixes: the next byte is the low byte of glyph $01xx
!TextWin_Wide2 = 2                       ; ... or $02xx
!TextWin_DigitGlyph0 = $D4               ; glyph of the digit 0 (TextWin_HexGlyphs; 1-9 follow)
!TextWin_RomNameSize = 11                ; bytes per name in TextWinRom_TechNames / EnemyNames / ItemNames
!TextWin_NamePad = $EF                   ; the byte that pads the ROM names (TextWin_NameLen10/11 stop at it)
!TextWin_TechIconByte = $2F              ; a tech name starting with this byte has it skipped (an icon?)
!TextWin_CharNameMax = 5                 ; TextWin_CharNameLen counts up to this many bytes or a 0
!TextWin_CharNameSize = 6                ; bytes per name at TextWin_CharNames
!TextWin_FirstCharName = $13             ; codes $13-$19: TextWin_CharNamePtrs entry (code - $13)
!TextWin_FirstMemberName = $1B           ; codes $1B-$1D: party position (code - $1B)
!TextWin_NibbleHi = $00F0                ; TextWin_HexByte: the high digit's bits (then / 16 * 2)
!TextWin_NibbleLo = $000F                ; the low digit's bits
!TextWin_WideGlyphMin = $0100            ; a TextWin_HexGlyphs entry this high or more is stored as two bytes
                                         ; (prefix first); none is
!TextWin_HexDigitCount8 = 2              ; TextWin_SubLeft for code $0D in hexadecimal
!TextWin_HexDigitCount16 = 4             ; and for code $0E
!TextWin_StrNadiaLen = 5                 ; bytes TextWin_CodeNadia draws from TextWin_StrNadia
; --- Glyph drawing (TextWin_DrawGlyph) ---
!TextWinRom_Font = $FF2060               ; 24 bytes per glyph code (code * 24): the left 8 pixels of each of
                                         ; 24 rows (probably 12 lines of two 2bpp planes, as they are stored)
!TextWinRom_FontRight = $FF3860          ; 24 bytes per two glyph codes (code / 2 * 24): the right 4 pixels
                                         ; of each row, high nibble for an even code, low for an odd one
!TextWin_GlyphTopSkip = 8                ; TextWin_GfxBuf bytes skipped before the first glyph byte (the
                                         ; top 4 lines of the tile row, 2 bytes each)
!TextWin_GlyphTopPairs = 4               ; glyph byte pairs drawn into the first tile row
!TextWin_GlyphLowPairs = 8               ; and into the next (24 bytes in all)
!TextWin_NextRow2bpp = $00F0             ; TextWin_OutPtr step to the next tile row ($100 bytes on from the
                                         ; first byte drawn) in TextWin_Blit2bpp's layout
!TextWin_NextRow4bpp = $01F0             ; and $200 bytes on in TextWin_Blit4bpp's
!TextWin_ModeBlitMask = $0F              ; TextWin_Mode bits: 0 = TextWin_Blit2bpp, else TextWin_Blit4bpp
!TextWin_PenShiftMask = $0007            ; TextWin_PenX bits: pixels into the tile
!TextWin_PenTileMask = $F8               ; TextWin_PenX bits: the tile (* 8)
!TextWin_RightNibble = $F0               ; TextWinRom_FontRight bits of an even glyph code
; --- Decimal digits (TextWin_Dec8/16/24): each divisor is shifted left by
; (quotient bits - 1) for the shift-and-subtract loop ---
!TextWin_Dec8First = 100<<1              ; hundreds of a byte: 2 bits (0-2)
!TextWin_DecTens = 10<<3                 ; tens: 4 bits (every converter)
!TextWin_Dec16First = 10000<<2           ; ten thousands of a word: 3 bits (0-6)
!TextWin_DecThousands = 1000<<3          ; 4 bits
!TextWin_DecHundreds = 100<<3            ; 4 bits
!TextWin_Dec24First = 10000000           ; ten millions of 24 bits: 1 bit (0-1)
!TextWin_DecMillions = 1000000<<3
!TextWin_DecHundredK = 100000<<3
!TextWin_DecTenK = 10000<<3

; --- Scene objects and tile triggers (C2Scene_ObjWatch, C2Scene_TrigWatch) ---
!C2Scene_ObjActive = $80                 ; C2Scene_Unk0294 / C2Scene_ObjBFlags bit 7: the object is tested
!C2Scene_ObjBusy = $40                   ; bit 6: C2Scene_ObjWatchBusyA/B wait while it is set
!C2Scene_ObjCountMask = $03              ; bits 0-1: compared with the number of party members
                                         ; (C2Scene_ObjWatchFull) and with 0 (C2Scene_ObjWatchEmpty)
!C2Scene_ObjSelA = 2                     ; C2Scene_ObjSel: object A ($0290-$0294)
!C2Scene_ObjSelB = 3                     ; C2Scene_ObjSel: object B ($029A-$029E)
!C2Scene_ObjBLocId = $01F3               ; the Loc_Id word object B is tested at (compared unmasked)
!C2Scene_Flag0ObjAScript = $D2           ; C2Scene_Flag0Copy value with which object A starts
                                         ; C2Scene_ScrGoToLoc1D8 instead (meaning not traced)
!C2Scene_ObjWatchStIdle = 0              ; C2Scene_Unk027E states (C2Scene_ObjWatchStates)
!C2Scene_ObjWatchStBusyA = 2
!C2Scene_ObjWatchStBusyB = 3
!C2Scene_ObjWatchStFull = 4
!C2Scene_ObjWatchStEmpty = 5
!C2Scene_TrigStWait = 1                  ; C2Scene_Unk0280 state C2Scene_TrigWatchWait (0: check)
!C2Scene_TrigRecheck = $01               ; C2Scene_TrigFlags bit 0
!C2Scene_TrigKeep = $02                  ; C2Scene_TrigFlags bit 1
!C2Scene_TrigTaskState1 = 1              ; the value C2Scene_TrigListA/C put in the current task's .Unk02
!C2Scene_TrigFoundA = $01                ; C2Scene_TrigFound bits: a ListA entry at the tile
!C2Scene_TrigFoundC = $02                ; a ListC entry
!C2Scene_TrigFoundB = $04                ; a ListB entry

; --- C2Scene_Unk5775 and C2Scene_ClearUnk8621 ---
!C2Scene_Unk8604Size = 25                ; bytes of C2Scene_Unk8604Init
!C2Scene_Unk8621Bytes = $0400            ; bytes C2Scene_ClearUnk8621 zeroes from C2Scene_HdmaArea on

; --- The party leader's task (C2Scene_LeaderTask) and its walk helpers ---
!C2Scene_PartySlotEmpty = $80            ; Party_Members byte bit 7: no member in the slot (as
                                         ; C2Scene_ObjWatchFull counts them)
!C2Scene_StepInput = 1                   ; C2Scene_WalkTask.State: C2Scene_LeaderInput (state 0 of
                                         ; C2Scene_Unk0280); C2Scene_LeaderStep goes back to it
!C2Scene_StepsPerTrigState = 8           ; bytes of C2Scene_LeaderWalkSteps per C2Scene_Unk0280 state
                                         ; (4 words; as a shift: 3)
!C2Scene_FacingUp = 0                    ; C2Scene_WalkTask.Facing bits 0-1, as the D-pad sets them:
!C2Scene_FacingDown = 1                  ; Up gives .YVel -1, Down +1, Left .XVel -1, Right +1
!C2Scene_FacingLeft = 2
!C2Scene_FacingRight = 3
!C2Scene_FacingMask = $03
!C2Scene_WalkMoving = $80                ; .Facing bit 7: the walk animation is running
!C2Scene_PadUp = $0800                   ; Pad_Unk00F8 read as a word: Pad_Unk00F9 bit 3 (Up in the
!C2Scene_PadDown = $0400                 ; Pad_Pressed high-byte layout), bit 2 (Down), bit 1 (Left)
!C2Scene_PadLeft = $0200                 ; and bit 0 (Right)
!C2Scene_PadRight = $0100
!Pad_Unk00F8Bit6 = $40                   ; Pad_Unk00F8 bit 6 (X with the default button map): scene
                                         ; mode C2Scene_ModeMenu in C2Scene_LeaderInput
!Pad_Unk00F8Bit2 = $04                   ; bit 2 (Select with the default map): mode C2Scene_ModeMode7
!Pad_Unk00F8Bit0 = $01                   ; bit 0 (Y with the default map): mode C2Scene_ModeMenu9
!C2Scene_ModeListA = 3                   ; C2Scene_Mode3: act on the ListA entry at C2Scene_Unk1B32
!C2Scene_ModeMode7 = 6                   ; C2Scene_Mode6: C2Scene_MapView (BG mode 7) between mosaics
!C2Scene_ModeMenu9 = 9                   ; C2Scene_Mode5 with ExitMenu_Mode5
!C2Scene_Loc1F5 = $01F5                  ; the Loc_Id where the leader gets C2Scene_LeaderAttr1F5
!C2Scene_LeaderAttr = $A8                ; C2Scene_Task.SprAttr of the leader's sprite (C2Scene_SprAttr*
!C2Scene_LeaderAttr1F5 = $B8             ; flags; meaning of the bit 4 difference not traced)
!C2Scene_IdleAnimAt = $F0                ; C2Scene_IdleFrames value at which the idle animation starts
!C2Scene_IdleHold = $FE                  ; then the count is kept at $FE/$FF (C2Scene_IdleSet: $FF, so
!C2Scene_IdleSet = $FF                   ; the animation is started only once)
!C2Scene_AnimIdle = $A2                  ; animation C2Scene_LeaderInput starts after C2Scene_IdleAnimAt
                                         ; frames without input (not adjusted for C2Scene_AltAnimChar)
!C2Scene_AltAnimChar = 6                 ; Party_Members character whose walk and stand animations are
!C2Scene_AltAnimOfs = $0C                ; this many entries further on (C2Scene_SetWalkAnim/SetStandAnim)
!C2Scene_TrailLen = 16                   ; positions in C2Scene_TrailX/Y
!C2Scene_TrailMask = $1F                 ; C2Scene_TrailPos wraps within the 16 words
!C2Scene_TilePropWall = $0303            ; C2Scene_WalkTask.PropUL/UR as a word: bits 0-1 of either
                                         ; stop a step there (C2Scene_TileBlocked)
!C2Scene_TilePropTrig = $0404            ; and bit 2 of both: C2Scene_OnTrigTiles (C2Scene_TrigFlags)
!C2Scene_TilePropLowNibble = $0F         ; a property nibble (C2Scene_GetTileProp, odd column)
; --- The other party members' task (C2Scene_MemberTask) ---
!C2Scene_MemberAttr = $A0                ; C2Scene_Task.SprAttr of a member's sprite (C2Scene_LeaderAttr
!C2Scene_MemberAttr1F5 = $B0             ; - 8), and at Loc_Id C2Scene_Loc1F5
!C2Scene_Member1Pal = $0A                ; ORed into it for party slot 1 (attribute bits 1-3: palette 5)
!C2Scene_Member2Pal = $0C                ; and for slot 2 (palette 6)
!C2Scene_Member1Tile = $0020             ; C2Scene_Task.SprTile of slot 1 (the second $400 bytes of
!C2Scene_Member2Tile = $0040             ; C2Scene_PartyGfx: 32 tiles on) and of slot 2
!C2Scene_Slot1 = 1                       ; C2Scene_FollowTask.Slot values: party positions 1 and 2
!C2Scene_Slot2 = 2
!C2Scene_FollowWait = 8                  ; C2Scene_Task.Frames a member waits after starting a move or
                                         ; standing still before it looks at the leader again
!C2Scene_NearLo16 = $0010                ; C2Scene_LeaderNear16: the leader is near when within -16..+16
!C2Scene_NearHi16 = $0011                ; pixels of the member on both axes
!C2Scene_NearLo32 = $0020                ; C2Scene_LeaderNear32: -32..+32
!C2Scene_NearHi32 = $0021
!C2Scene_RouteXFirst = $10               ; C2Scene_FollowTask.Route bit 4: the first leg is in X
!C2Scene_RouteYFirst = $20               ; bit 5: the first leg is in Y
!C2Scene_RouteLegs = $0F                 ; bits 0-3: the legs (1 or 2) still to go
!C2Scene_PathXYBlocked = $01             ; C2Scene_PathBlocked bit 0: the X-then-Y path has a wall
!C2Scene_PathYXBlocked = $02             ; bit 1: the Y-then-X path has one
!C2Scene_PathBothBlocked = $03
!C2Scene_TileSnapMask = $FFF8            ; a pixel position AND this: the start of its 8x8 tile
!C2Scene_TilePropWallBits = $03          ; C2Scene_TilePropWall's bits in one property nibble
!C2Scene_AnimIdle1 = $A3                 ; idle animations of the slot 1 and 2 members (as
!C2Scene_AnimIdle2 = $A4                 ; C2Scene_AnimIdle for the leader)

; --- The map view (C2Scene_MapView, scene mode 6) ---
!C2Scene_BgMode7 = $07                   ; C2Scene_BgModeShadow: BG mode 7
!C2Scene_MapObjVram = $6000              ; VRAM word address of the sprite tiles in the map view (OBSEL
                                         ; OBSEL_Size16And32_Base6000)
!C2Scene_TileBytes = $0020               ; bytes in one 8x8 4bpp tile
!C2Scene_TileWords = 16                  ; VRAM words in one 8x8 4bpp tile
!C2SceneRom_MapMarkerTiles = $C6F500     ; two 4bpp tiles: sprite tiles 0 and 2 of the map view
!C2SceneRom_MapViewObjPal = $C6F540      ; 16 colours: sprite palette 0 of the map view (33 B copied)
!C2Scene_ObjPal0Dest = $0A20             ; = C2Scene_PaletteBuf + $100: colour $80 (sprite palette 0)
!C2Scene_MapViewEndFrames = $11          ; frames C2Scene_MapView waits after the zoom-in ends
!C2Scene_MapTileCount = $0380            ; tiles in the seven BG packs ($7000 bytes / 32)
!C2Scene_TileRow2Plane0 = $04            ; byte offsets in a 4bpp tile of row 2's bit planes 0-3
!C2Scene_TileRow2Plane1 = $05            ; (C2Scene_MapTileColors takes bit 4 of each: column 3)
!C2Scene_TileRow2Plane2 = $14
!C2Scene_TileRow2Plane3 = $15
!C2Scene_TilePalBits = $1C               ; tile word high byte bits 2-4: the palette (* 4)
!C2Scene_TileNumMask = $03FF             ; tile word bits 0-9: the tile number
!C2Scene_Mode7RowBytes = 8               ; bytes per pixel row of a mode-7 tile (one per pixel)
!C2Scene_MapBandBytes = $0300            ; one band of the picture: 12 mode-7 tiles of 64 bytes
!C2Scene_MapBandWords = $0300            ; the same in VRAM words (the DMA writes VMDATAH only)
!C2Scene_MapBandRowMask = $0003          ; metatile rows per band - 1 (two pixel rows each)
!C2Scene_MapTilePxMask = $0007           ; metatile columns per mode-7 tile - 1 (one pixel each)
!C2Scene_MapNextTile = (64-7)            ; from a tile's 8th pixel to the next tile's first: + 57
!C2Scene_MapBackToRow = ($300-$10)       ; from past the band's row end back to its first tile,
                                         ; two pixel rows further down
!C2Scene_MapFirstTileVram = $0040        ; VRAM word of mode-7 tile 1 (64 words per tile)
!C2Scene_MapHideColA = $0F               ; C2Scene_MapFilterColor: colours shown as 0 (palette * 16 +
!C2Scene_MapHideColB = $2F               ; colour): $0F, $2F and $24-$2B; at Loc_Id
!C2Scene_MapHideFrom = $24               ; C2Scene_MapLoc1F3 $40-$4E instead
!C2Scene_MapHideTo = $2C
!C2Scene_MapLoc1F3 = $01F3               ; the Loc_Id with its own hidden colours
!C2Scene_MapHide1F3From = $40
!C2Scene_MapHide1F3To = $4F
!C2Scene_TmBytes = $0400                 ; the 32 x 32 tile block C2Scene_MapBuildTilemap builds
!C2Scene_TmRowBytes = $20                ; bytes (tiles) per row of it
!C2Scene_TmRows = $20                    ; its rows
!C2Scene_Mode7MapWidth = $0080           ; VRAM words per row of the 128 x 128 mode-7 tilemap
!C2Scene_MapTileCol0 = 2                 ; the picture's first tile column in the mode-7 map
!C2Scene_MapTileRow0 = 6                 ; and its first tile row
!C2Scene_MapFirstTile = 1                ; the picture's first mode-7 tile (tile 0 stays blank)
!C2Scene_MapTilesWide = 12               ; the picture in tiles: 96 metatiles at 8 per tile
!C2Scene_MapTilesHigh = 16               ; 64 metatile rows at 4 per tile
!C2Scene_ZoomSteps = 32                  ; entries of C2SceneRom_ZoomDivA/B (word offsets 0-$3E)
!C2SceneRom_ZoomDivA = $C6F560           ; 32 words $FF, $F0, ... $10: the zoom's M7A/M7B divisors
!C2SceneRom_ZoomDivB = $C6F5A0           ; 32 words $7F, $78, ... $08: its M7C/M7D divisors
!C2Scene_MapViewExitBtn = $0008          ; Pad_Unk00F6 bit 3 (read as a word): ends the map view
!C2Scene_MapMarkerAttr = $30             ; C2Scene_Task.SprAttr of the map markers: OAM attribute bits
                                         ; 4-5 (priority 3), palette 0
!C2Scene_LocMarkerY = $00C0              ; C2Scene_TaskLocMarker's screen Y
!C2Scene_AnimLocLabel = $0047            ; its C2SceneRom_AnimTable entry
!C2Scene_MapGradLines = $0007            ; lines per step of the map view's gradient
!C2Scene_MapGradLevels = $10             ; steps per half (blue 0-15, then 16-31)
!C2Scene_MapGradRun = $F0                ; HDMA line-count byte: repeat (bit 7), 112 lines
!C2Scene_MapLabelVram = $6200            ; VRAM word of sprite tile $20: where the label goes
!C2Scene_MapLabelA = $6C                 ; label string replaced by C2Scene_MapLabelEarly while
!C2Scene_MapLabelAFlag = $36             ; C2Scene_Flag0Copy is below this
!C2Scene_MapLabelB = $6B                 ; label string replaced by it while C2Scene_FlagTailCopy+6
!C2Scene_MapLabelBBit = $01              ; has this bit clear
!C2Scene_MapLabelEarly = $6F             ; the replacement string
!C2Scene_MapLabelGlyphs = $0C            ; TextWin_StepCount for the label's one TextWin_Step

; --- The dial (C2Scene_Dial, scene mode 8) ---
!C2Scene_DialBg1X = $FF80                ; C2Scene_Bg1HScroll in the dial (-128)
!C2Scene_DialBg1Y = $FF90                ; C2Scene_Bg1VScroll (-112)
!C2Scene_M7OneHigh = $01                 ; high byte of 1.0 in a mode-7 matrix value
!C2Scene_DialWobjsel = $20               ; WOBJSEL: window 1 makes the colour window
!C2Scene_DialWinLayers = $11             ; TMW/TSW: BG1 and OBJ
!C2Scene_DialGrey = $0F                  ; the fixed colour's red, green and blue intensity
!C2Scene_DialFadeFrames = $12            ; frames C2Scene_Dial waits after the start and after its fade out
!C2Scene_DialCentreX = $84               ; screen point the hand turns about
!C2Scene_DialCentreY = $70
!C2Scene_WinEmpty = $0001                ; WH0 = 1, WH1 = 0 as a word: left past right, an empty window
!C2Scene_HdmaBufBytes = $01C0            ; 224 lines of one word (the hand and swirl buffers)
!C2Scene_HdmaHalfBytes = $00E0           ; the 112 lines of one HDMA run
!C2Scene_HdmaLastLine = $01BE            ; byte offset of line 223's word
!C2Scene_ScreenLines = $00E0             ; 224 visible lines
!C2Scene_DialBtnBack = $0010             ; Pad_Unk00F8 bits (as a word) the dial reads: bit 4 turns
!C2Scene_DialBtnFwd = $0020              ; back, bit 5 forward (as Right/Up and Left/Down),
!C2Scene_DialBtnOk = $0080               ; bit 7 confirms, bit 3 cancels
!C2Scene_DialBtnCancel = $0008
!C2Scene_DialTurnStep = 4                ; hand angle units per frame
!C2Scene_DialMarks = 7                   ; markers (and C2Scene_DialLocs entries)
!C2Scene_DialLastSel = 6
!C2Scene_DialNoDest = $FFFF              ; C2Scene_ObjANextLoc after a cancel
!C2Scene_DialSfxSame = $01               ; C2Scene_SoundCmd18 argument when the current location is picked
!C2Scene_DialLateFlag = $CC              ; C2Scene_Flag0Copy from which C2Scene_DialLocsLate is used
!C2Scene_DialHandBuf = $01               ; C2Scene_DialFlags bit 0: C2Scene_HandBufB is on screen
!C2Scene_DialSwirlBuf = $02              ; bit 1: the swirl's B buffers are on screen
!C2Scene_DialFlagBit2 = $04              ; bit 2: cleared by C2Scene_SwirlInit, not otherwise used here
!C2Scene_HandClearFrom = $0090           ; C2Scene_DialDrawHand's clear: from line 72's word
!C2Scene_HandClearCount = $009D          ; MVN count - 1: lines 73-151
!C2Scene_HandPointCount = 3              ; points (and edges) of the hand
!C2Scene_SwirlPhase = $0080              ; added to the angle for the M7B/M7C sine (1/8 turn)
!C2Scene_SwirlLineStep = 4               ; angle units per line (and per frame)
!C2Scene_DialPack0Bank = $C3             ; source bank of C2Scene_DialPacks entry 0
!C2Scene_DialPack12Bank = $C6            ; and of entries 1 and 2
!C2Scene_DialObjVramB = $6400            ; sprite tile $40
!C2Scene_DialObjSrcB = $7F9800           ; pack 0 from $800 on: sprite tiles $40-$7F
!C2Scene_DialObjBytesB = $0800
!C2Scene_DialObjTiles = $0040            ; entries of C2Scene_DialObjTileList
!C2Scene_DialWhite = $FFFF               ; the colour C2Scene_DialLoad stores
!C2Scene_DialWhiteColor = $D1            ; at this colour of C2Scene_PaletteStage
!C2Scene_DialPixelBytes = $0800          ; mode-7 tiles 0-31, 64 pixels each
!C2Scene_DialMapRows = $20               ; rows of one 32 x 32 block
!C2Scene_DialMapRowBytes = $0040         ; bytes (words) of one row
!C2Scene_DialMapBlockCount = 16
!C2SceneRom_DialNibbles = $C6F700        ; $400 B: two 4-bit pixels per byte, high first
!C2Scene_DialNibbleBytes = $0400
!C2Scene_DialNibbleMask = $0F

; --- The menu's NMI (Menu_Nmi) ---
!Menu_NmiDp = $0D00                      ; direct page of Menu_Nmi (the menu's frame state)
!Menu_HdmaenMask = $7F                   ; Menu_HdmaenShadow bits written to HDMAEN (channel 7 kept off)
!Menu_FrameDone = $FF                    ; Menu_FrameReady after the NMI's upload
!Menu_StackTopByte = $01                 ; stack-relative offset of the byte pushed last
!Menu_PadHeldNoBit0 = $FFFE              ; Menu_PadHeld bits that count as held for the repeat stage
; --- Object A's tasks (C2Scene_ObjATask, C2Scene_ObjAMarkTask, C2Scene_ObjASpotWatch) ---
!C2Scene_ObjAFlag5 = $20                 ; C2Scene_Unk0294 bit 5: object A goes up and is steered when the
                                         ; party is in (else it starts mode 8 at once) and uses the other
                                         ; animations; who sets it is not traced
!C2Scene_ObjAInMode8 = $10               ; bit 4: set when object A starts scene mode C2Scene_ModeUnk8,
                                         ; cleared when it goes on afterwards
!C2Scene_ObjAOnSpot = $08                ; bit 3: object A overlaps the spot at C2Scene_SpotX/Y
                                         ; (C2Scene_ObjASpotWatch)
!C2Scene_ObjASpotBits = $0C              ; bits 2-3 (C2Scene_Unk0294Bit2 and C2Scene_ObjAOnSpot)
!C2Scene_ModeUnk8 = 8                    ; C2Scene_Mode8: C2Scene_Dial runs while the mode stays this; set
                                         ; by object A
!C2Scene_ObjAStWait = 1                  ; C2Scene_ObjTask.State values of C2Scene_ObjATask
!C2Scene_ObjAStFly = 3                   ; (C2Scene_ObjAStates)
!C2Scene_ObjAStLand = 5
!C2Scene_ObjAStMode8 = 6
!C2Scene_ObjAStScript = 7
!C2Scene_ObjAStWaitEmpty = 8
!C2Scene_ObjAttrPrio2 = $A0              ; C2Scene_Task.SprAttr: C2Scene_SprAttrScroll and OAM priority 2
!C2Scene_ObjAttrPrio3 = $B0              ; the same with priority 3 (attribute bits 4-5); also the dial's
                                         ; markers (C2Scene_DialMarkInit)
!C2Scene_AnimObjARest = $2D              ; object A's animation at rest
!C2Scene_AnimObjARest5 = $18             ; and with C2Scene_ObjAFlag5
!C2Scene_AnimObjARise = $19              ; while it goes up (C2Scene_ObjAWait)
!C2Scene_AnimObjALand = $1A              ; while it comes down (C2Scene_ObjAFly)
!C2Scene_AnimMarkAbove = $4E              ; the mark tasks' sprite above object A or B (or a mate)
!C2Scene_AnimMarkBelow = $1F              ; and below it while it is up
!C2Scene_SoundCmd86 = $86                ; sound command C2Scene_ObjAInit sends (arguments 0, 0); meaning not
                                         ; traced
!C2Scene_ObjASongArg = $13               ; C2Scene_SoundCmd10 argument of C2Scene_ObjASound (probably a song)
!C2Scene_Flag0ObjAGo1DD = $D3            ; C2Scene_Flag0Copy value with which object A, once up, starts
                                         ; C2Scene_ObjAScrGo1DD (meaning not traced)
!C2Scene_RiseFrames = $30                ; frames the objects (and mates) move up at -0.5: 24 pixels
!C2Scene_LandFrames = $31                ; frames they move down when landing
!C2Scene_RiseAttrAt = 8                  ; .Frames at which a rising sprite gets OAM priority 3
!C2Scene_LandAttrAt = $20                ; and a landing one priority 2 again
!C2Scene_Lift = $0018                    ; 24 pixels: how far the objects' sprites go up
!C2Scene_LiftUp = $FFE8                  ; -24
!C2Scene_HalfPixel = $8000               ; a velocity fraction word: half a pixel a frame
!C2Scene_ObjALandMask = $0707            ; property nibble bits 0-2 (two nibbles a word) that keep object A
                                         ; from coming down
!C2Scene_ObjAJumpPx = $0200              ; pixels C2Scene_ObjAJump moves the task in X
!C2Scene_ObjALoc1D9 = $01D9              ; C2Scene_ObjANextLoc values C2Scene_ObjAAfterMode8 treats apart
!C2Scene_ObjALoc1F7 = $01F7
!C2Scene_ObjALoc1F2 = $01F2
!C2Scene_ObjALoc1D8 = $01D8              ; and the ones it puts there instead
!C2Scene_ObjALoc1B0 = $01B0
!C2Scene_ObjALoc0F3 = $00F3
!C2Scene_Tile7x8 = $0807                 ; Loc_EntryX/Y as a word: tile X 7, Y 8
!C2Scene_Tile7x24 = $1807                ; X 7, Y 24
!C2Scene_Tile8x12 = $0C08                ; X 8, Y 12
!C2Scene_Unk7F00CCBit0 = $01             ; the C2Scene_Unk7F00CC bit set for C2Scene_ObjALoc1F2
!C2Scene_Unk1B58Spot = $4C               ; C2Scene_Unk1B58 while object A is on the spot
!C2SceneRom_ObjAPalA = $C6F5E0           ; 16 colors object A's scripts fade palettes to (bank $C6)
!C2SceneRom_ObjAPalB = $C6F600           ; 16 colors C2Scene_ObjAScrLeave sets palette 0 to

; --- Object B's tasks and its mates (C2Scene_ObjBTask, C2Scene_ObjBMateTask and their mark tasks) ---
!C2Scene_ObjBLanding = $20               ; C2Scene_ObjBFlags bit 5: object B is coming down (set by
                                         ; C2Scene_ObjBFly, cleared by C2Scene_ObjBLand); the mates go back
!C2Scene_ObjBStWait = 1                  ; C2Scene_ObjTask.State values of C2Scene_ObjBTask
!C2Scene_ObjBStFly = 3
!C2Scene_ObjBStLand = 5
!C2Scene_ObjBAttrPrio2 = $A8             ; object B's .SprAttr: palette 4 (bits 1-3), C2Scene_SprAttrScroll,
!C2Scene_ObjBAttrPrio3 = $B8             ; OAM priority 2 or 3
!C2Scene_AnimObjBRest = $24              ; object B's (and its mates') animation at rest
!C2Scene_AnimObjBRise = $29              ; object B's while it goes up or down
!C2Scene_AnimObjBDown = $25              ; C2Scene_ObjBFaceAnims' facing-down entry, loaded as a constant
!C2Scene_ObjBNoLandCols = $0E            ; BankC6_UnkE74E's rectangle where object B does not come down:
!C2Scene_ObjBNoLandRows = $34            ; 8x8 columns 0-13, rows 0-51
!C2Scene_MateStWait = 1                  ; C2Scene_FollowTask.State values of the mate tasks
!C2Scene_MateStFollow = 3
!C2Scene_MateStLand = 5                  ; (C2Scene_ObjBMateTask)
!C2Scene_MateMarkStLand = 4              ; (C2Scene_ObjBMateMarkTask)
!C2Scene_NoFacing = $FF                  ; .PrevFacing that matches no facing (forces the animation)
!C2Scene_SprAttrPrioMask = $30           ; C2Scene_Task.SprAttr bits 4-5: the OAM priority (3 when all set)
!C2Scene_SprAttrPrio2 = $20              ; priority 2
!C2Scene_AnimMate1Glide = $6F            ; slot 1's mate going up or back to object B
!C2Scene_AnimMate2Glide = $74            ; slot 2's
!C2Scene_MateAimFrames = 4               ; frames a mate moves before it aims again
!C2Scene_MateGlideFrames = $30           ; frames C2Scene_ObjBMateGlideVel's velocity takes to the target
!C2Scene_SignByte = $FF                  ; the high byte that sign-extends a negative byte
!C2Scene_MateMarkDrop = $0030            ; 48 pixels: a mate's mark below the mate while up
!C2Scene_MateMarkDropUp = $FFD0          ; -48

; --- The label task (C2Scene_LabelTask) ---
!C2Scene_LabelStWait = 1                 ; C2Scene_ObjTask.State of C2Scene_LabelWait
!C2SceneRom_LabelStrings = $C6F400       ; the string table C2Scene_LabelTask draws from (bank $C6): 16-bit
                                         ; string addresses; also C2Scene_MapViewLabel's TextWin_StrTable
!C2Scene_LabelHalfOfs = $0200            ; buffer offset of the text's second half (the lower 8 rows)
!C2Scene_LabelVramTop = $1E00            ; VRAM word addresses of the two halves
!C2Scene_LabelVramBottom = $1F00
!C2Scene_LabelDmaBytes = $0180           ; bytes uploaded per half (12 tiles of 32 bytes)
!C2Scene_LabelBelowObjA = $0040          ; pixels below object A the label goes while the party is in it
!C2Scene_LabelPieces = 6                 ; the first byte of the frame at C2Scene_Unk8604 (probably its piece
                                         ; count)

; --- Direction helpers (C2Scene_Unk2273 / Unk2277 / Unk229D) ---
!C2Scene_SinMax = $0080                  ; C2Scene_Unk2277 at direction $40: +128 (the table holds 127)
!C2Scene_SinMin = $FF80                  ; and at direction $C0: -128 (the table holds -127)
!C2Scene_AimRiseMask = $FFFC             ; |dy| bits kept for the angle row (|dy| / 4 * 32 = this * 8)
!C2Scene_FullTurn = $0100                ; a whole turn in direction units (256): C2Scene_Unk229D's
                                         ; result for the up-right quarter is this - the angle

; --- Screen effects and script routines ($C2:754D-$C2:7DE3) ---
!C2Scene_PlaceRandMask = $7F             ; C2Scene_PlaceBelowView: random X spread 0-127 ...
!C2Scene_PlaceMarginX = $0040            ; ... from 64 pixels into BG2's view
!C2Scene_PlaceRowsDown = $0020           ; 32 tile rows (256 pixels) below the top of BG2's view
!C2Scene_PlaceFixedCol = $002F           ; C2Scene_PlaceBelowViewAt178: tile column 47 (pixel $178)
!C2Scene_RandVelMask = $000F             ; C2Scene_RandomVelocity: 16 entries ...
!C2SceneRom_RandVelocities = $C6F640     ; ... of 8 bytes: .XVelFrac, .XVel, .YVelFrac, .YVel words
!C2Scene_DriftHMask = $0003              ; C2Scene_TaskBg3Drift: BG3 one pixel left every 4 frames ...
!C2Scene_DriftVMask = $0007              ; ... and one down every 8
!C2Scene_HdmaRun112 = $F0                ; HDMA line count byte: repeat mode, 112 lines
!C2Scene_HdmaRun64 = $C0                 ; repeat mode, 64 lines
!C2Scene_HdmaRun32 = $A0                 ; repeat mode, 32 lines
!C2Scene_WaveLineStep = $0010            ; sine steps (of 1024 a turn) from one line to the next: 64 lines
                                         ; make one period
!C2Scene_WaveSignBits = $C000            ; the sign bits a shift right by 2 clears (the wave is sin / 4)
!C2Scene_LineWaveStep = $0004            ; C2Scene_TaskBg3LineWave: phase steps per frame
!C2Scene_SlideXVelFrac = $8931           ; C2Scene_TaskBg3Slide's BG3 velocity: X -4 + $8931/65536
!C2Scene_SlideXVel = $FFFC               ; (about -3.46 pixels a frame) ...
!C2Scene_SlideYVel = $0002               ; ... and Y +2
!C2Scene_SlideFastXVelFrac = $ADF4       ; C2Scene_TaskBg3SlideFast's: X -18 + $ADF4/65536
!C2Scene_SlideFastXVel = $FFEE           ; (about -17.32) ...
!C2Scene_SlideFastYVel = $FFF6           ; ... and Y -10
!C2Scene_PanMask = $03                   ; C2Scene_TaskBg1Pan: one pixel every 4 frames
!C2Scene_ViewMargin = $0010              ; C2Scene_TaskInView: the view test reaches 16 pixels past the
!C2Scene_ViewTestW = $0120               ; left and top edges and spans 288 x 272 pixels
!C2Scene_ViewTestH = $0110
!C2Scene_GravityFrac = $2000             ; C2Scene_AddGravity: +1/8 pixel a frame to .YVel each call
!C2Scene_NudgeRange = $30                ; C2Scene_NudgeXRandom: a random byte * this / 256 (0-48 rounded)
!C2Scene_RandPosAX = $0220               ; C2Scene_RandPosA: X $220-$31F ...
!C2Scene_RandPosAY = $0038               ; ... and Y $38-$137
!C2Scene_RandPosBX = $00E0               ; C2Scene_RandPosB: X $E0-$1DF ...
!C2Scene_RandPosBY = $FFB8               ; ... and Y -$48 to $B7
!C2Scene_NoiseStep = $0040               ; C2Scene_NoiseStep: 32 lines further into the noise each call
!C2Scene_Unk7F00F7Bit1 = $02
!C2Scene_PatternTileBytes = $0100        ; C2Scene_BuildPatternTiles: 8 tiles of 32 bytes zeroed ...
!C2Scene_PatternSolidBytes = $0040       ; ... then 2 tiles set to $FF
!C2Scene_PatternAllSet = $FF             ; every pixel colour 15
!C2Scene_PatternRowCount = $20           ; bytes of C2Scene_PatternRows
!C2Scene_Tile4bppBytes = $0020           ; bytes in one 8x8 4bpp tile
!C2Scene_TilePlanes01Mask = $000F        ; offset within a tile's 16 bytes of bit planes 0-1
!C2Scene_PatternNextPair = $0030         ; from past one tile's planes 0-1 to the next tile pair
!C2Scene_Unk7F00AABit0 = $01
!C2Scene_Unk7F019ABit3 = $08

; --- The menu kernel (BankC2_MenuEntry, Menu_RunThreads) ---
!Menu_StackTop = $09FF                   ; S of the menu's top level (BankC2_MenuEntry, Menu_RunThreads)
!Menu_ResetStack = $06FF                 ; S Menu_ExitToGame leaves for GameLoop_Main (as StackTop)
!Menu_NmiAndJoypad = $81                 ; NMITIMEN: NMI and auto-joypad read
!Menu_JoypadOnly = $01                   ; NMITIMEN: auto-joypad read only
!Menu_AudioCmd70 = $70                   ; sound-driver command Menu_Setup sends first (meaning not traced)
!Menu_AudioArgFF = $FF                   ; the $FF argument of its $18, $19 and $82 commands
!Menu_AudioCmd82Arg0 = $01               ; Audio_CmdArg0 of its $82 command
!Menu_FillFF = $FFFF                     ; Menu_Setup's fill value
!Menu_Unk9B76Bytes = $20                 ; bytes of Menu_Unk9B76
!Menu_PartyListBytes = 9                 ; bytes of Menu_PartyList
!Menu_Unk0D38Count = $0E                 ; Menu_Setup's loop end: Y = 2, 4, ... $0E (7 words)
!Menu_Unk3FDivisor = 10
!Menu_ActiveSlots = 3                    ; Menu_PartyOrder positions of the active party
!Menu_ThreadSlots = $40                  ; 8 slots of 8 bytes
!Menu_ThreadSlotBytes = 8
!Menu_ThreadStackBase = $0A3F            ; S of slot 0 when it starts; slot n's is $40 x n higher
!Menu_ThStFree = 0                       ; Menu_Thread.State values
!Menu_ThStNew = 1
!Menu_ThStWaiting = 2
!Menu_ThStRunning = 3
!Menu_ThNewWait1 = $0101                 ; .State = Menu_ThStNew with .Wait = 1, as one word
!Menu_ThWait1 = $0102                    ; .State = Menu_ThStWaiting with .Wait = 1
!Menu_MainThreadSlot = $0008             ; slot 1 (byte offset): Menu_MainThread
!Menu_Thread3Slot = $0018                ; slot 3: Menu_UnkE91B
!Menu_Unk58Init = $3020                  ; Menu_Unk58's value before thread 3 starts
!Menu_FadeInSlot = $0000                 ; slot 0: Menu_FadeInThread
!Menu_AllThreads = $FF                   ; Menu_KillThreads mask: every slot
!Menu_VramRecBytes = 8                       ; bytes in one Menu_VramQueue record
!Menu_FadeInStep = $02                   ; Menu_FadeInThread's brightness step
!Menu_FadeOutStep = $FE                  ; Menu_FadeOut's (-2)
!Menu_BrightnessMask = $0F               ; INIDISP bits 0-3: the brightness
!Menu_Unk82E1First = $AE                 ; the range of Menu_CharRec.Unk2A values Menu_Unk82E1 marks
!Menu_Unk82E1End = $B3
!Menu_Unk2857Mark = $80
!Menu_Unk2857Bytes = 5
!Menu_CharRecBytes = $50                 ; bytes in one Menu_CharRecords record (Menu_CharRec)
!Menu_CharRecCount = 7                   ; records Menu_InitSystems and Menu_Unk82E1 walk
!Menu_Unk21BAGap = $001A                 ; bytes Menu_Unk834D skips after each member's 6 in Menu_Unk21BA
!Menu_Unk21BASrcBank = $D1               ; source bank of its MVN
!Menu_VectorBytes = 8                    ; bytes of Menu_InterruptVectors (two JMLs)

; --- Menu uploads, inventory and character helpers ($C2:8663-$C2:89E3) ---
!Menu_PalBytes = $0200                   ; bytes of Menu_PalBuf (256 colours)
!Menu_PalDirtyAll = $FF                  ; Menu_UploadPalette clears every bit of Menu_PalDirty (TRB)
!Menu_GradTableBytes = $20               ; bytes of Menu_GradientSteps / Menu_GradTable
!Menu_ItemCat1First = $5A                ; first ids of item categories 1-3 (Menu_ItemCategoryBounds);
!Menu_ItemCat2First = $7B                ; Menu_AddItem does not add these ids
!Menu_ItemCat3First = $94
!Menu_ItemLastCategory = 4
!Menu_ItemIdEnd = $F2                    ; one past the last item id / inventory slot scanned
!Menu_ItemMaxCount = 99                  ; most of one item in a slot
!Menu_InvFull = $FF                      ; Menu_AddItem: no free slot; Menu_RemoveItem: not found
!Menu_ItemShort = $FE                    ; Menu_RemoveItem: fewer than asked
!Menu_Unk2C23Mask = $07
!Menu_Unk2C23Bytes = 6
!Menu_EquipChecks = 7                    ; entries of Menu_EquipChars
!MenuRom_ItemTablesA = $FFCF0E           ; 5 words: per item category, the address (bank $CC) of a table
!MenuRom_ItemRecSizesA = $FFCF18         ; 5 bytes: its record size (Menu_ItemDataPtrA)
!MenuRom_ItemTablesB = $FFCF1D           ; the same for a second set of tables (Menu_ItemDataPtrB)
!MenuRom_ItemRecSizesB = $FFCF27

; --- Menu cursors and list arrows ($C2:89E4-$C2:8C35) ---
!Menu_CursorSlot = $0030                 ; thread slot 6 (byte offset): the cursor threads
!Menu_ArrowsSlot = $0020                 ; slot 4: Menu_ListArrowsThread
!Menu_CursorRowsA = $0A                  ; Menu_CursorStepA draws rows 0-9 only
!Menu_CursorTileAttrA = $2020            ; tile $20, attributes $20
!Menu_CursorTileAttrD = $3020            ; tile $20, attributes $30
!Menu_CursorFixedRows = 3                ; Menu_CursorThreadB: indexes from 3 on are scrolled
!Menu_CursorRowStep = $30                ; 48 pixels per scroll step
!Menu_CursorWrapMin = $F0                ; Y below this after wrapping upward: not drawn
!Menu_BlinkMaskDefault = $FC             ; TRB mask leaving a 2-bit countdown (4 frames per phase)
!Menu_BlinkTimersInit = $0103            ; Menu_StartCursorD: timers 0 and 1 = 3 and 1 ...
!Menu_BlinkTimer2Init = $02              ; ... timer 2 = 2
!Menu_CursorBlinkDInit = $02             ; and Menu_CursorBlink = 2
!Menu_Blink0 = $01                       ; Menu_CursorBlink bits of sprites 0, 1, 2
!Menu_Blink1 = $02
!Menu_Blink2 = $04
!Menu_ArrowHidden = $E000                ; X 0, Y $E0 (never stored, see Menu_ListArrowsThread)
!Menu_ArrowTimerMask = $F8               ; a 3-bit countdown (8 frames per phase)
!Menu_ArrowGap = $08                     ; the down arrow's Y below the up arrow's
!Menu_ArrowUpTile = $3022                ; tile $22, attributes $30
!Menu_ArrowDownTile = $B022              ; tile $22, attributes $B0 (vertical flip)

; --- Menu NMI upload and commands ($C2:85D6-$C2:8662, $C2:8C36-$C2:8E2C) ---
!Menu_NmiMoveReq = $80                   ; Menu_HdmaenShadow bit 7: Menu_NmiUpload runs the queued move
!Menu_WinRegBytes = $10                  ; bytes of Menu_WinRegShadow
!Menu_MoveCodeMvn = $7E54                ; MVN opcode $54, destination bank $7E
!Menu_MoveCodeRtl = $6B7E                ; source bank $7E, RTL ($6B)
!Menu_PartyOrderBytes = 9                ; positions in Menu_PartyOrder
!Menu_BonusHalfId = $A1                  ; Menu_CharRec.Unk2A values: Menu_RecRefillWord3 adds half ...
!Menu_BonusQuarterId = $A0               ; ... or a quarter of .Word5
!Menu_StatMax = 999                      ; cap of Menu_RecRefillWord3
!Menu_SramUnk7FE2Set = $FF               ; Menu_CmdSetSram7FE2's value
!Menu_SaveSlots = 3                      ; slots Menu_CmdBootCheckSaves tries
!Menu_DataNew = 0                        ; Menu_DataInitDone after Menu_CmdBootCheckSaves: no slot passed
!Menu_DataFromSave = 2                   ; ... one passed
!Menu_EquipKeepChar = 5                  ; record whose category-0 byte Menu_CmdEquip's id-0 path keeps
!Menu_EquipSlots = 4                     ; equipment bytes per record (categories 0-3)

; --- Menu setup: tiles, graphics, OAM, item tables ($C2:960B-$C2:99C9, $C2:C511, $C2:ED08) ---
!MenuRom_BankFF = $FF0000                ; bank $FF base for LDA.l this,X with X a bank-$FF address
!Menu_Tile2bppBytes = $0010              ; bytes in one 2bpp 8x8 tile (= planes 0-1 of a 4bpp tile)
!Menu_TileRows = 8                       ; rows of an 8x8 tile
!Menu_TilePlane0 = $0000                 ; offsets in a 4bpp tile of row 0's plane 0, 1, 2 and 3 bytes
!Menu_TilePlane1 = $0001
!Menu_TilePlane2 = $0010
!Menu_TilePlane3 = $0011
!Menu_ColorBytes = 2                     ; bytes per CGRAM colour
!MenuRom_Font2bpp = $FF8E60              ; $E00 B of 2bpp tiles (Menu_LoadGraphics step 1)
!Menu_Font2bppBytes = $0E00
!MenuRom_Font2bppB = $FFC9FC             ; $100 B (16 tiles) laid over its tiles $10-$1F
!Menu_Font2bppBBytes = $0100
!Menu_Font2bppBTile = $10
!Menu_FontFirstTile = $10                ; first tile the 2bpp-to-4bpp loop copies (2bpp tile $10 of
                                         ; Menu_Bg3TileBuf to 4bpp tile $10 of Menu_TileBuf)
!Menu_FontTiles = $00F0                  ; tiles it copies
!Menu_FontTile2F = $2F                   ; Menu_TileBuf tiles given plane 2 = 0 OR 1: $2F and $D4-$DD
!Menu_FontTileD4 = $D4
!Menu_FontTileDE = $DE
!MenuRom_Tiles4bpp = $FFD5E4             ; $600 B of 4bpp tiles (step 2)
!Menu_Tiles4bppBytes = $0600
!MenuRom_Tiles3bpp = $FFDBE4             ; $95 3bpp tiles expanded after them
!Menu_Tiles3bppCount = $0095
!Menu_Tiles3bppOr3 = $0008               ; of those, the first 8 get plane 3 = OR
!Menu_TilesBBytes = $12A0                ; bytes moved to Menu_TileBuf ($30 + $95 tiles)
!MenuRom_WindowGfx = $FF9E10             ; 8 window styles of $280 B (20 4bpp tiles each)
!Menu_WindowGfxBytes = $1400
!Menu_WinStyleBytes = $0280
!Menu_WinExtraTile = $88                 ; Menu_Bg3TileBuf tile copied after the window styles ...
!Menu_WinExtraTiles = 13                 ; ... and how many
!Menu_WinTilesOr3 = $00A4                ; tiles given plane 3 = OR in step 3
!MenuRom_PalA = $FF9C68                  ; 4 colours, loaded to colours 0-3 and 4-7
!MenuRom_PalB = $FF9C78                  ; 4 colours -> 16-19
!MenuRom_PalC = $FFCBBC                  ; 4 colours -> 20-23
!MenuRom_PalD = $FFCBC4                  ; 16 colours -> $70-$7F
!MenuRom_ObjPal = $FF9DF0                ; 16 colours -> $80-$8F (the first sprite palette)
!MenuRom_ObjTiles = $FF9CF0              ; 4 pieces of 64 B laid over sprite tiles $20, $30, $22, $32
!Menu_ObjPieceBytes = $0040
!Menu_ObjClearBytes = $1000              ; Menu_TileBuf bytes cleared before the sprite tiles
!Menu_ObjExtraTile = $70                 ; Menu_Bg3TileBuf tile copied (twice 12 tiles) to tiles 4, $14
!Menu_ObjExtraTiles = 12
!Menu_ObjCopyBytes = $0400               ; Menu_TileBuf tiles 0-$1F copied to tile $20
!Menu_TileBufBytes = $4000               ; Menu_TileBuf bytes cleared at the end
!Menu_Unk0D47Init = $0010
!Menu_WinStyleMask = $07                 ; Menu_Config01 bits 0-2: the window style
!Menu_WinVramDest = $3DC0                ; VRAM word address of the window-style tiles
!MenuRom_WindowPals = $FFB210            ; 16 B (8 colours) per window style
!Menu_WinPalRowMask = $001C              ; Menu_Unk0D47 high-byte bits picking the palette row
!Menu_OamHidden = $E000                  ; OAM entry X 0, Y $E0: off the screen
!Menu_OamHighInit = $AAAA                ; OAM high-table bytes: every sprite large, X bit 8 clear
!Oam_LowTableBytes = $0200               ; bytes of Oam_LowTable
!Oam_HighTableBytes = $0020              ; bytes of Oam_HighTable
!MenuRom_ItemRec0 = $CC0000              ; bytes 0-4 of an item record (X = Menu_ItemDataPtr or
!MenuRom_ItemRec1 = $CC0001              ; Menu_ItemDataPtrB, an address in bank $CC)
!MenuRom_ItemRec2 = $CC0002
!MenuRom_ItemRec3 = $CC0003
!MenuRom_ItemRec4 = $CC0004
!Menu_ItemInfo0Mask = $1E                ; record A byte 0 bits kept in Menu_ItemInfo0
!Menu_ItemInfo0Bit1 = $02                ; the Menu_ItemInfo0 bit cleared for item Menu_ItemIdC8
!Menu_ItemIdC8 = $C8
!Menu_ItemRecB1Bit6 = $40                ; record B byte 1 bit 6: byte 2 goes to Menu_ItemInfo4 (category 3)
!Menu_ItemCat4First = $BC                ; first id of item category 4 (Menu_ItemCategoryBounds)
!Menu_ItemNameFirst = $0B5E              ; first word of Menu_ItemNamePtrs ...
!Menu_ItemNameBytes = $000B              ; ... and the step
!Menu_Flag7F00BABit0 = $0001             ; Menu_Flag7F00BA bits Menu_BuildItemTables tests
!Menu_Flag7F00BABit1 = $0002

endif
