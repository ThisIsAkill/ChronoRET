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

endif
