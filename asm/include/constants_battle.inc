; ============================================================
; constants_battle.inc — Named constants for the battle engine (bank $C1).
; Same conventions as constants.inc: !Subsystem_Thing, grouped, each
; with a one-line note on what it means and how that was inferred.
;
; Widths: these are plain numbers; every use states .b/.w, so the
; digit count written here never decides an encoding.
; ============================================================
!constants_battle_inc ?= 0
if !constants_battle_inc == 0
!constants_battle_inc = 1

; --- Battler slots ---
!Battle_NumSlots         = $0B   ; 11 battler slots: 0-2 PCs, 3-10 enemies (scan bounds everywhere)
!Battle_LastSlot         = $0A   ; highest battler slot
!Battle_NumPcSlots       = 3     ; PC slots 0-2 (also "all three PCs" when compared with a PC count)
!Battle_LastPcSlot       = 2     ; highest PC slot
!Battle_FirstEnemySlot   = 3     ; enemies start at slot 3

; --- Character ids (!Pc_CharId); CT's standard 0-6 order, inferred ---
!Pc_CharRobo             = 3     ; searched by BattleTgt_EnemyLineFromChar3 / Char3Radius
!Pc_CharFrog             = 4     ; BattleTgt_PcByCharId4
!Pc_CharAyla             = 5     ; BattleTgt_PcByCharId5
!Pc_CharMagus            = 6     ; BattleTgt_Char6Radius

; --- Pad bits (!Battle_PadEdgeButtons / !Battle_PadEdgeDpad) ---
!Battle_PadConfirm       = $80   ; confirm button (every menu)
!Battle_PadAltConfirm    = $40   ; second confirm button: main menu, with CfgCursorMemory, confirms row 0
!Battle_PadConfirmAny    = $C0   ; either confirm button (target select)
!Battle_PadPageDown      = $20   ; item list: page down
!Battle_PadPageUp        = $10   ; item list: page up
!Battle_PadCancel        = $08   ; cancel button
!Battle_DpadUp           = $08   ; D-pad up
!Battle_DpadDown         = $04   ; D-pad down
!Battle_DpadLeft         = $02   ; D-pad left
!Battle_DpadRight        = $01   ; D-pad right
!Battle_DpadUpRight      = $09   ; up or right (area-target aim: next enemy)
!Battle_DpadDownLeft     = $06   ; down or left (area-target aim: other direction)
!Battle_DpadRightDown    = $05   ; right or down (target cursor: next)
!Battle_DpadLeftUp       = $0A   ; left or up (target cursor: previous)

; --- Math and geometry ---
!Battle_LowByteMask      = $00FF ; keep the low byte of a 16-bit A
!Battle_Invert16         = $FFFF ; EOR mask; with INC A negates a 16-bit value
!Battle_SineIndexMask    = $03FF ; angle * 4 wrapped to the 1024-entry (1 B each) sine table
!Battle_SineHalfTable    = $0200 ; table offset of angle $80: from here the sine is negative
!Battle_GeoRowMask       = $FFF8 ; |dy| rounded down to a multiple of 8 (angle table row)
!Battle_AngleQuarter     = $40   ; 90 degrees (256 angle units per turn)
!Battle_AngleHalfTurn    = $80   ; 180 degrees
!Battle_AngleThreeQuarter = $C0  ; 270 degrees

; --- Text and number formatting ---
!BattleMsg_Hundred       = 100   ; place value subtracted by FormatNumberDigits
!BattleMsg_Ten           = 10    ; place value subtracted by FormatNumberDigits / FormatTwoDigits
!BattleMsg_GlyphZero     = $73   ; tile of digit 0 (BattleRom_DigitTiles[0]); leading ones get blanked
!BattleMsg_TextLen       = 16    ; characters per re-encoded text buffer
!BattleMsg_TextBufBytes  = 32    ; both 16-byte tile rows ($94A0-$94BF) cleared together
!BattleMsg_CharTileMin   = $73   ; text bytes from here up are already tiles (digits, symbols)
!BattleMsg_CharSet2Min   = $69   ; text bytes $69-$72: code set 2 (inferred: kana with a handakuten)
!BattleMsg_CharSet1Min   = $40   ; text bytes $40-$68: code set 1 (inferred: kana with a dakuten); below = tiles
!BattleMsg_CharSet1TileAdd = $40 ; lower-row tile = text byte + $40 for set 1
!BattleMsg_CharSet1Top   = $71   ; upper-row tile above a set-1 character (inferred: the dakuten mark)
!BattleMsg_CharSet2TileAdd = $17 ; lower-row tile = text byte + $17 for set 2
!BattleMsg_CharSet2Top   = $72   ; upper-row tile above a set-2 character (inferred: the handakuten mark)
!BattleMsg_ArgNone       = $FF   ; "no battler" argument to the info-panel message calls
!BattleMsg_Glyph_I       = $A8   ; font: 'I' (A-Z start at $A0, a-z at $BA; checked against the name tables)
!BattleMsg_Glyph_t       = $CD   ; font: 't'
!BattleMsg_Glyph_e       = $BE   ; font: 'e'
!BattleMsg_Glyph_m       = $C6   ; font: 'm'

; --- Tilemap tiles and attributes (status bar and menu windows) ---
!BattleUI_MapRowBytes    = $40   ; one tilemap row: 32 entries x 2 bytes
!BattleUI_AttrPal2       = $29   ; attribute: priority, palette 2, tile-number bit 8 set (normal text and frames)
!BattleUI_AttrPal3       = $2D   ; attribute: priority, palette 3, tile-number bit 8 set (greyed menu lines, low-HP digits,
                                 ; PC names, a non-empty ATB gauge)
!BattleUI_AttrPal2VFlip  = $A9   ; palette 2 + vertical flip: the up-arrow tile drawn as a down arrow
!BattleUI_TileBlank      = $FF   ; empty tile
!BattleUI_TileBlankPair  = $FFFF ; two empty tiles (16-bit fill)
!BattleUI_TileSpacer     = $5F   ; tile after the HP digits (layouts 1/2) and after an item name
!BattleUI_TileHpSlash    = $E0   ; tile between HP and MaxHP in layout 0 (inferred: '/')
!BattleUI_TileH          = $64   ; header glyph 'H' (inferred: pairs with $66 as "HP")
!BattleUI_TileM          = $65   ; header glyph 'M' (BattleRom_TechBorder spells "MP" with $65 $66)
!BattleUI_TileP          = $66   ; header glyph 'P'
!BattleUI_TileGaugeCapL  = $5D   ; tile left of the ATB gauge (col 25; inferred: its left end cap)
!BattleUI_TileGaugeCapR  = $5E   ; tile right of the ATB gauge (col 30; inferred: its right end cap)
!BattleUI_TileGauge0     = $67   ; ATB gauge tile for 0 units still to fill; $67+n for n (graphics not checked)
!BattleUI_TileGauge8     = $6F   ; ATB gauge tile for 8 units still to fill (graphics not checked)
!BattleUI_GaugeUnits     = 32    ; ATB gauge length in units (4 tiles x 8)
!BattleMenu_TileCursorTL = $60   ; 2x2 row cursor, top-left tile
!BattleMenu_TileCursorTR = $61   ; top-right
!BattleMenu_TileCursorBL = $62   ; bottom-left
!BattleMenu_TileCursorBR = $63   ; bottom-right
!BattleMenu_TileArrow    = $7F   ; item-list scroll arrow (points up; flipped for down)

; --- Status-bar layout (byte offsets into the $0CC0 map) ---
!BattleUI_StatusEntries  = $00C0 ; 192 entries cleared by BuildStatusBarFrame (6 rows x 32)
!BattleUI_CmdWindowRows  = 6     ; rows in a PC's command window (frame and command list)
!BattleUI_CmdWindowCols  = 7     ; columns in a PC's command list
!BattleUI_PanelStride    = $80   ; two tilemap rows: next PC or enemy-name line
!BattleUI_PanelDestL1    = $0068 ; first PC line's name cell, layout 1
!BattleUI_PanelDestL02   = $005A ; first PC line's name cell, layouts 0 and 2
!BattleUI_EnemyPanelDest = $0042 ; first enemy-name line
!BattleUI_HpOffsetL0     = $0E   ; HP digits after the name cell, layout 0
!BattleUI_HpBackL1       = $0E   ; HP digits before the name cell, layout 1 (subtracted)
!BattleUI_HpOffsetL2     = $0C   ; HP digits after the name cell, layout 2
!BattleUI_MaxHpOffsetL0  = $16   ; MaxHP digits after the name cell, layout 0
!BattleUI_MpOffsetL0     = $1E   ; MP digits after the name cell, layout 0
!BattleUI_MpBackL1       = 6     ; MP digits before the name cell, layout 1 (subtracted)
!BattleUI_MpOffsetL2     = $14   ; MP digits after the name cell, layout 2
!BattleUI_GaugeCapOffsetL1 = $0A ; ATB gauge's left cap after the name cell, layout 1
!BattleUI_GaugeCapOffsetL2 = $18 ; ATB gauge's left cap after the name cell, layout 2
!BattleUI_MpCellL0       = $10   ; MP digits after the HP cell (UpdateNextPcPanel), layout 0
!BattleUI_MpCellL12      = 8     ; same, layouts 1 and 2
!BattleUI_GaugeCellOffset = $1A  ; ATB gauge after BattleRom_HpCellL1's cell
!BattleUI_FrameCol1Joined = $0E  ; slot-1 window frame without its left border (slot 0's window is shown)
!BattleUI_FrameCol1Full  = $0C   ; slot-1 window frame with its left border (slot 0's is not shown)
!BattleUI_FrameCol2Joined = $1A  ; slot-2 window frame without its left border (slot 1's window is shown)
!BattleUI_FrameCol2Full  = $18   ; slot-2 window frame with its left border (slot 1's is not shown)
!BattleUI_FrameRowBytesFull = $0E ; bytes per frame row with the left border (7 cells)
!BattleUI_FrameRowBytesJoined = $0C ; bytes per frame row without the left border (6 cells)
!Pc_NameRowLen           = 5     ; name tiles per row
!Enemy_NameLen           = 11    ; tiles per enemy-name row
!Enemy_NameLines         = 3     ; enemy-name lines in the status bar

; --- Menus and lists ---
!BattleMenu_SubmenuTech  = 1     ; !BattleMenu_Submenu / !BattleMenu_CmdMenu: tech
!BattleMenu_SubmenuItem  = 2     ; ... item
!BattleMenu_LockTech     = $01   ; !BattleMenu_Lock bit that also blocks the tech list
!BattleMenu_ListRows     = 3     ; visible rows of a command/tech/item list
!BattleMenu_LastRow      = 2     ; last visible row
!BattleMenu_WindowRows   = 6     ; rows of the tech window frame
!BattleMenu_WindowBytes  = $0180 ; one window map: 6 rows x $40
!BattleMenu_ListRowStride = $80  ; one list line = two tilemap rows
!BattleMenu_TechRowPairs = 2     ; RenderTechListRows draws 2 x 2 lines
!BattleMenu_TechBorderCols = 9   ; columns copied from BattleRom_TechBorder per row
!BattleMenu_TechBorderSkip = $2E ; rest of a row after those 9 entries ($40 - 9*2)
!BattleMenu_TechRowCells = 18    ; entries recoloured per tech line by UpdateTechMpAvail
!BattleMenu_NameLeadCells = 3    ; tech-list cells blanked left of a name (BattleMenu_BlankNameLeadCells)
!BattleMenu_NameTailCells = 4    ; tech-list cells blanked right of a name (BattleMenu_BlankNameTailCells)
!BattleMenu_DoubleTechPcs = 2    ; ready PCs a double tech needs
!BattleMenu_TripleTechPcs = 3    ; ready PCs a triple tech needs
!BattleMenu_ReadyQueueSize = 3   ; entries scanned in !BattleMenu_ReadyQueue
!BattleMenu_NoSlot       = $FF   ; roster / active-PC value: none
!BattleMenu_RosterRedraw = $FE   ; !BattleMenu_RosterIdxDrawn value forcing a window rebuild
!BattleMenu_CacheInvalid = $FF   ; "never drawn" value for change-tracking caches (forces a redraw)
!BattleMenu_CursorTopY   = $2D   ; target cursor y below which !Battle_UnkEC is set
!BattleMenu_CursorBottomY = $9C  ; target cursor y from which !Battle_UnkEC is cleared
!Item_RecordSize         = 5     ; bytes per Item_BattleList record
!Item_NameLen            = 11    ; bytes per item name
!Item_NameTable          = $0B5E ; item names in bank $CC: 11 B per item id, an icon byte then the text
!Item_MaxScroll          = $FA   ; last item-list scroll position

; --- Tech list ---
!Tech_ListLen            = 20    ; lines per PC tech list
!Tech_NameLen            = 11    ; bytes per tech name
!Tech_NameTable          = $15C4 ; tech names in bank $CC (11 B each, by tech id)
!Tech_CodeBlank          = $FF   ; !Tech_ListCode: empty line
!Tech_CodeBlank2         = $FE   ; !Tech_ListCode: empty line (second kind)
!Tech_CodeTripleHeader   = $FD   ; !Tech_ListCode: "Triple Technique" header (ROM text $CC:FB5D) (needs 3 ready PCs)
!Tech_CodeDoubleHeader   = $FC   ; !Tech_ListCode: "Double Technique" header (ROM text $CC:FB4B) (needs 2 ready PCs)
!Tech_CodeSkip           = $FB   ; !Tech_ListCode: unselectable line with no text drawn
!Tech_CodeSpecialMask    = $F0   ; codes $F0-$FF are special lines
!Tech_DoubleHeaderText   = $0000 ; offset of the "Double Technique" line in BattleRom_TechFixedText
!Tech_TripleHeaderText   = $0012 ; offset of the "Triple Technique" line
!Tech_HeaderTextLen      = 18    ; bytes per header line
!Tech_NoEntry            = $FF   ; !Tech_ListEntry value: no entry on this line
!Tech_NoPartners         = $FF   ; Partners value: single tech / no tech data
!Tech_PartnerLoMask      = $0F   ; first partner slot
!Tech_PartnerHiMask      = $F0   ; second partner slot; $F0 after masking = none
!Tech_FlagUnusable       = $80   ; Tech_MenuEntry.Flags bit: unusable now
!Tech_FlagUsableMask     = $7F   ; clears it
!Tech_FirstComboId       = $39   ; tech ids from here up are double/triple techs
!Tech_IdUnk74            = $74   ; tech id that also needs !Battle_Unk1C48 == $42; which tech is unknown
!Battle_Unk1C48Wanted    = $42   ; the value that check wants

; --- Command records (BattleCmd) ---
!BattleCmd_StateWaiting  = $80   ; .State: waiting for a command
!BattleCmd_ClearWaiting  = $7F   ; mask clearing it
!BattleCmd_StateQueued   = $40   ; .State: command committed
!BattleCmd_KindAttack    = $80   ; .Kind: attack
!BattleCmd_KindItem      = $40   ; .Kind: item
!BattleCmd_KindTech      = $20   ; .Kind: tech

; --- Target selection ---
!BattleTgt_ModeMask      = $7F   ; !BattleTgt_Mode bits that select the handler
!BattleTgt_NumModes      = $21   ; handlers in BattleTgt_ModeTable
!BattleTgt_LastMode      = $20   ; out-of-range modes are clamped to this one
!BattleTgt_ModeAllAlliesKo = 4   ; the only mode that may list !Battler_KoFlag battlers
!BattleTgt_ModeAttack    = 7     ; mode used by Attack (single enemy)
!BattleTgt_ModeRoboRadiusBig = $14 ; mode $14: Char3Radius with the large radius
!BattleTgt_ModeEnemyRadiusBig = $1A ; mode $1A: EnemyRadius with the large radius
!BattleTgt_NumAreaTypes  = 7     ; entries in BattleTgt_AreaTable
!BattleTgt_AllFlag       = $80   ; !BattleTgt_TargetAll: select every candidate
!BattleTgt_ResultNone    = $80   ; !BattleTgt_Result: no valid target
!BattleTgt_Empty         = $FF   ; empty candidate / selection entry
!BattleTgt_LineWidth     = 2     ; line areas: half-width / 8 used by every caller
!BattleTgt_LineVariantAim = 1    ; !BattleTgt_AreaVariant: box ending at the aimed-at battler
!BattleTgt_RadiusSq3     = 9     ; circle radius 3 cells, squared
!BattleTgt_RadiusSq4     = $10   ; radius 4 cells, squared
!BattleTgt_RadiusSq5     = $19   ; radius 5 cells, squared
!BattleTgt_RowHalfHeight = $20   ; row area: +/- this many pixels around the centre's y
!BattleTgt_ScreenMax     = $FF   ; clamp for the row area's lower edge
!BattleTgt_SweepBatch    = 3     ; multi-target cursor: selection entries drawn per frame
!BattleTgt_SweepWrap     = 6     ; ... the sweep restarts after this index

; --- OAM (cursor sprites) ---
!BattleOam_CursorSprites = 4     ; cursor sprites 0-3
!BattleOam_CursorBytes   = $0010 ; their low-table bytes (4 x 4)
!BattleOam_CursorSizeBits = $AA  ; high table: large size, x bit 8 clear, for all four
!BattleOam_HideCursorBits = $55  ; high table: x bit 8 set for all four (moves them off screen)
!BattleOam_ShowSprite0   = $FE   ; high-table mask clearing sprite 0's x bit 8
!BattleOam_ShowSprite1   = $FB   ; ... sprite 1
!BattleOam_ShowSprite2   = $EF   ; ... sprite 2
!BattleOam_OffscreenY    = $F0   ; y that parks a sprite below the screen
!BattleOam_CursorAttr    = $32   ; attribute of target cursors: priority 3, palette 1
!BattleOam_AttrKeepMask  = $F1   ; keeps flip/priority/name bit, clears the palette
!BattleOam_CursorCentreX = $10   ; cursor x = battler x - this

; --- Sound (APU command block !Sfx_Command) ---
!Sfx_CmdPlay             = $19   ; APU command used for every menu sound in this bank (inferred: play SFX)
!Sfx_Param2Default       = $80   ; !Sfx_Param2 value sent with it (meaning not established)
!Sfx_TurnReady           = $42   ; sound id played when a PC's turn comes up (inferred)

endif
