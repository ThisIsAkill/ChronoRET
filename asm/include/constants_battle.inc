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

; --- Battler boxes (Battle_CalcBattlerBox and the box tests) ---
!Battle_BoxBottomPad     = 8     ; pixels a box reaches below the probe y, unless !Battle_Unk2989NoBoxPad
!Battle_Unk2989NoBoxPad  = $04   ; !Battle_Unk2989 bit: set = boxes end at the probe y; meaning unknown
!Battle_BoxEdgeMax       = $FF   ; right-edge clamp (rightmost pixel)
!Battle_CellBlocked      = $40   ; !Battle_CellMap bit: always blocks a box
!Battle_OverlapPc        = $80   ; Battle_BoxOverlapsOthers result: touches a PC's box ($81 = an enemy's)

; --- Position queries (BattlePos_Query) ---
!BattlePos_Fail          = $FF   ; !BattlePos_Result: the condition does not hold
!BattlePos_NoBest        = $FFFF ; nearest-battler scans: starting best distance (anything is nearer)
!BattlePos_DistSq4       = $0010 ; squared distance limits: 4 pixels ...
!BattlePos_DistSq16      = $0100 ; ... 16 pixels
!BattlePos_DistSq32      = $0400 ; ... 32 pixels
!BattlePos_DistSq40      = $0640 ; ... 40 pixels
!BattlePos_DistSq48      = $0900 ; ... 48 pixels
!BattlePos_DistSq64      = $1000 ; ... 64 pixels
!BattlePos_RowBand       = $20   ; query 5: largest |dy| that still counts as the same row
!BattlePos_MidRow        = 8     ; queries 9/10: cell row (y / 16) where the lower half of the screen starts
!BattlePos_RightCol      = $0B   ; query 11: cell column (x / 16) where the right part starts
!BattlePos_LeftColEnd    = 5     ; query 12: cell column where the left part ends (exclusive)
!Battle_Invert8          = $FF   ; EOR mask; with INC A negates an 8-bit value

; --- PC animation (Battle_TickPcSlots) ---
!Battle_AnimDefault      = 3     ; !Battle_AnimId when no status picks another (inferred: standing)
!Battle_AnimUnk2B        = $2B   ; replaces animation 3 while !Battle_Unk99CF/99D0 is set; which animation is unknown
!Battle_AnimRestart      = $FF   ; !Battler_AnimFrame value: the next step starts the list again
!Battle_AnimTicksDivisor = 5     ; a list's duration byte / this = frames until the next step
!Battle_FacingSlotMask   = $7F   ; !Battle_FacingTurn: the PC slot
!Battle_FacingHandedOn   = $80   ; !Battle_FacingTurn: handed on, not taken yet
!Battle_StatusUnk4BNoTurn = $02  ; BattlerStats.Status2 bit that stops the facing update; meaning unknown
!BattlePos_QueryNearestEnemy = 2 ; !BattlePos_Mode of BattlePos_NearestEnemy
!BattleSys_ServicePosQuery = 5   ; $C10045 service number of BattlePos_Query

; --- Status animations and effects (Battle_PickStatusAnim, Battle_FxHandlerTable) ---
!Battle_AnimUntargetable = 0     ; !Battle_AnimId default for an !Battler_Untargetable battler; what animation 0 shows is unknown
!Battle_AnimUnk12        = $12   ; animation for BattlerStats.Unk2F bit 0 when no status record matches; unknown
!Battle_StatusAnimNone   = $FF   ; BattleRom_StatusAnim.Anim: no animation of its own
!Battle_StatsUnk2FBit    = $01   ; BattlerStats.Unk2F bit tested by Battle_PickStatusAnim; meaning unknown
!Battle_FxNone           = $FF   ; !Battler_FxWanted: no effect (runs Battle_FxReset)
!Battle_FxUnk2F          = $80   ; !Battler_FxWanted from the Unk2F path (also runs Battle_FxReset)
!Battle_PaletteCopyLen   = $1A   ; bytes Battle_FxReset copies from !Battle_PaletteSaved
!Battle_PaletteTintCopyLen = $18 ; bytes Battle_FxOverlay2Tint copies, from byte 2 on
!Battle_FxOverlayStride  = $10   ; !Battler_FxOverlayBase per overlay block (4 frames x 4 B at $CC:F6D4)
!Battle_FxOverlayFrameStart = $FF ; !Battler_FxOverlayFrame before the first frame (the first tick makes it 0)

; --- Enemy animation (Battle_TickEnemyGroup) ---
!Battle_TickOrderNone    = $FF   ; !Battle_TickOrder entry: nobody (third entry of enemy group 3)
!Battle_EnemyListKind1   = 1     ; list block loaded for !BattleRom_EnemyAnimKind 1 (kind 0 loads list 3); meaning unknown
!Battle_EnemyListOther   = 6     ; list block loaded for every other kind; meaning unknown
!Battle_EnemyAnimListLen = 8     ; entries copied per list into !Enemy_AnimTicks/Frames
!Battle_EnemyAnimFrames  = 4     ; !Enemy_AnimFrame wraps here (entries 4-7 are never shown)
!Battle_EnemyGroupSize   = 3     ; !Battle_TickOrder entries visited per group
!Battle_EnemyGroupLast   = 3     ; highest !Battle_UnkA4 group

; --- Enemy movers (Battle_TickEnemyMovers, Battle_EnemyMoverTable) ---
; Move ids are !Enemy_Anim values; the names say what the mover does with
; them, read from the handlers (what the enemies look like doing it is not
; checked).
!Enemy_MoveNear32        = $01   ; Battle_MoverApproach: stop within 32 pixels of the target
!Enemy_MoveNear64        = $02   ; Battle_MoverApproach: stop within 64 pixels
!Enemy_MoveNear4         = $03   ; Battle_MoverApproach: stop within 4 pixels; passes cell bit 7 and other battlers
!Enemy_MoveAxisY         = $08   ; Battle_MoverAxis: line up with the target's row (move $09: its column)
!Enemy_MoveLoopSmall     = $0A   ; Battle_MoverLoop: half-height loop, shorter turn-back when blocked
!Enemy_MoveLoopPass      = $0C   ; Battle_MoverLoop: passes cell bit 7 and other battlers
!Enemy_MoveOrbitHold     = $0D   ; Battle_MoverOrbit: does not approach the ring, only circles when already on it
!Enemy_MoveOrbitWide     = $0E   ; Battle_MoverOrbit: ring radius $40 instead of $20
!Enemy_MoveOrbitPass     = $0F   ; Battle_MoverOrbit: passes cell bit 7 and other battlers
!Enemy_MoveRingFar       = $10   ; Battle_MoverKeepRange: ring radius $80 and no arrival
!Enemy_MoveUp            = $11   ; Battle_MoverFixedDir: straight up
!Enemy_MoveDown          = $12   ; straight down
!Enemy_MoveRight         = $13   ; right
!Enemy_MoveLeft          = $14   ; left
!Enemy_MoveDownRight     = $15   ; down-right (any other id that reaches this mover: up-right)
!Enemy_MoveDownLeft      = $16   ; down-left
!Enemy_MoveUpLeft        = $17   ; up-left
!Battle_MoveStepLen      = 8     ; pixels per step: the sine scale of every probe; the stepper at $CF:F978 ends at 8
!Battle_GoalSlot         = !Battle_NumSlots ; probe entry 11, just past the battlers: the ring goal point
!Battle_AngleEighth      = $20   ; 45 degrees
!Battle_AngleAxisShift   = 6     ; LSR/ASL count that rounds an angle down to a quarter turn
!Battle_RingRadius       = $40   ; Battle_MoverKeepRange's ring radius (!Enemy_MoveRingFar: $80)
!Battle_RingRadiusFar    = $80
!Battle_OrbitRadiusSmall = $20   ; Battle_MoverOrbit's ring radius (!Enemy_MoveOrbitWide: doubled)
!Battle_OrbitTurn        = $10   ; angle the orbit point moves on per step
!Battle_OrbitTurnBack    = $F0   ; the same, backwards (-$10)
!Battle_LoopDropY        = $10   ; the loop centre lies this far below the enemy's start
!Battle_LoopRadiusBig    = $20   ; Battle_MoverLoop's vertical radius (!Enemy_MoveLoopSmall: halved); also the
                                 ; extra horizontal radius
!Battle_LoopTurn         = $10   ; phase step per loop step
!Battle_LoopTurnBack     = $F0   ; the same, backwards (-$10)
!Battle_LoopBounce       = $58   ; phase jump back when a loop step is blocked
!Battle_LoopBounceSmall  = $30   ; the same for !Enemy_MoveLoopSmall
!Battle_ScreenCentreX    = $80   ; Battle_MoverToCentre's goal: the middle of the 256x224 screen
!Battle_ScreenCentreY    = $70
!Battle_FacingUp         = 0     ; !Battler_Facing values, from !BattleRom_FacingByAngle (0 for angles $A0-$DF,
!Battle_FacingDown       = 1     ; 1 for $20-$5F, 2 for $60-$9F, 3 for $E0-$1F) with y growing downwards; the
!Battle_FacingLeft       = 2     ; directions are inferred from that, not from the graphics
!Battle_FacingRight      = 3
!Battle_FacingFromAngle  = $FF   ; Battle_MoverFixedDir: keep the facing the table gave

; --- PC poses (Battle_RunPcPose and the services that start it) ---
!Battle_AnimDown         = 8     ; BattleRom_StatusAnim's animation for KO (Status bit 7); service 9's pose
!Battle_AnimUnk0A        = $0A   ; service 8's pose (inferred: victory); not looked at
!Battle_AnimUnk0C        = $0C   ; the battle-start pose (Battle_StartPose); not looked at
!Battle_Unk2989NoEndPose = $01   ; !Battle_Unk2989 bit: set = service 8 returns before its pose; meaning unknown
!Battle_PoseTicksLast    = $17   ; last byte of !Pc_PoseTicks cleared by Battle_RunPcPose (3 x 8 B)
!Battle_PoseListLen      = 8     ; entries per PC pose list
!Battle_PoseEntryStart   = $FF   ; !Pc_PoseEntry before the first step
!Battle_PoseFrames       = $40   ; frames a pose runs (Battle_RunPcPose)

; --- Text and number formatting ---
!BattleMsg_Thousand      = 1000  ; place value subtracted by FormatNumber4Digits
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

; --- Battler frame decoder (Battle_DrawBattlerFrame) ---
!Battle_FrameLayoutTall  = 2     ; !Battler_FrameLayout: 8 x 6 tiles
!Battle_FrameLayoutStrip = 3     ; 96 x 1 tiles; the checked entry point never decodes it
!Battle_FrameLayoutTallAlt = 5   ; row order used instead of layout 2 for every slot but 3 (BattleRom_FrameLayout)
!Battle_FrameLayoutBytes = 14    ; size of one BattleRom_FrameLayout record
!Battle_FrameTileMask    = $07FF ; frame tilemap entry: tile number (0 = blank cell, written as zeros)
!Battle_FrameHFlip       = $4000 ; frame tilemap entry: mirror the tile horizontally (bit 15 is not tested)
!Battle_TileBytes        = $0020 ; one 8x8 4bpp tile (inferred from the 32-byte cell copy)
!Battle_SignExtendNeg    = $FF   ; high byte of a sign-extended negative byte

; --- Info messages (BattleMsg_ShowFromTableCC3A09Vec, A = id) ---
!BattleMsg_InfoNone      = $FF   ; sent before message $75 (inferred: clear the panel, as $FF means none for $CD002D)
!BattleMsg_Info75        = $75   ; shown once by BattleSys_UpkeepTwoFrames; text not traced

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

; --- Actions (BattleSys_RunAction, service 4) ---
!Battle_ActFlagSecond    = $40   ; !Battle_ActFlags bit 6: start the second thread group
!Battle_ActAltFlag       = $80   ; !Battle_ActUnkAE9B bit 7: PC attacks use the "Alt" record set
!Battle_ActNumKinds      = 4     ; entries of BattleAct_LoaderTable
!Battle_ActParamsLen     = $10   ; bytes of the parameter block from !Battle_ActScriptId
!Battle_ActArgNone       = $FF   ; !Battle_ActUnkArg987C: no BattleAnim_UnkVecCD0018 call
!Battle_ActUnkA1A8Cleared = $28  ; bytes of !Battle_ActUnkA1A8 service 4 clears (5 lists of 8)
!Battle_ActHitKind3      = 3     ; the only !Battle_ActPcHitKind BattleAct_FlagLethalPcHits checks
!Battle_ActAnimLoop      = 2     ; !Battler_ActAnimMode: start the list again at its end
!Battle_ActCalcEntries   = 6     ; entries of !Battle_ActCalcSel

!Battle_ActKind3FirstId  = $BC   ; BattleAct_LoadKind3: record = !Battle_ActId - this
!Battle_ActIdUnk37       = $37   ; the id that calls BattleAnim_UnkVecCD0018 even with !Battle_ActFlags set; unknown
!Battle_ActThreads       = $10   ; script threads 0-15
!Battle_ActObjects       = $10   ; action objects (BattleActObj, object lists)
!Battle_ActObjRecTypeMask = $E0  ; top three bits of an object record's first byte
!Battle_ActObjRecMark    = $40   ; type 010: a mark (BattleAct_IndexObjLists)
!Battle_ActFrameRowsMask = $0F   ; frame header: row count
!Battle_ActFrameCols     = 8     ; columns per row (one mask bit each)
!Battle_ActFramesPerCall = 4     ; frames BattleAct_UnpackFrames builds per call
!Battle_ActAnimOnce      = 1     ; !Battler_ActAnimMode: play the list once (the "play" opcodes)
!Battle_ActTargetSetThread = 4   ; thread that acts for every slot of !Battle_ActTargetSet
!Battle_ActFirstObjThread = 8    ; threads 8-15 are object threads 0-7
!Battle_ActNumOpcodes    = $DB   ; opcodes $00-$DA have a handler in BattleAct_OpcodeTable
!Battle_ActOpSetSpeed    = $08   ; first of the opcodes $08-$0F (BattleAct_OpSetSpeed)
!Battle_ActOpCalcToResult = $3D  ; opcodes $3D-$40: results entry 0-3 (BattleAct_OpCalcToResult)
!Battle_ActOpCalcToResult4 = $45 ; opcodes $45-$46: results entry 4-5
!Battle_MoveUnitStep     = $0100 ; 1.0 in 8.8: the major axis' step (BattleAct_CalcMoveStep)

; --- Path search (BattleAct_FindPath, on !Battle_PathMap) ---
!Battle_PathRowMask      = $F0   ; y & this = 16 * cell row (the cell is row * 16 + x / 16)
!Battle_PathUp           = $F0   ; cell index step to the neighbour above (-16, 8-bit)
!Battle_PathDown         = $10   ; ... below (+16)
!Battle_PathLeft         = $FF   ; ... to the left (-1, 8-bit)
!Battle_PathRight        = $01   ; ... to the right
!Battle_PathCellStart    = $20   ; start cell while searching (blocks like any non-zero value)
!Battle_PathCellGoal     = $FF   ; goal cell
!Battle_PathMark         = $E0   ; ORed into each cell of the found path
!Battle_PathMaxWave      = $1F   ; waves run 1-30; the search fails when the count reaches this
!Battle_PathNotFound     = $80   ; result: no path (bit 7); 1-4 = found
!Battle_ActVarMax        = $FF   ; top of a script variable (opcode $49 clamps to 0-this)
!Battle_ActFollowFirstObj = 9    ; opcode $1C operand: 0-8 = entry of !Battle_ActBattlers, 9 on = object thread n - 9
!Battle_ActFollowObj     = $40   ; !Battle_ActObjFollow: bit 6 set = an object thread (bits 0-2) rather than a slot
!Battle_ActFollowNone    = $FF   ; !Battle_ActObjFollow: follows nothing
!Battle_ActKeepBit7      = $80   ; opcodes $27-$2A keep bit 7 of !Battler_UnkA5CD / !Battler_Unk9FF7 (the scans' skip bit)
!Battle_PathDirUp        = 0     ; path walk directions (!Battler_PathFromDir; * 8 = step kind base)
!Battle_PathDirDown      = 1
!Battle_PathDirLeft      = 2
!Battle_PathDirRight     = 3
!Battle_PathDirNone      = $FF   ; !Battler_PathFromDir at the start: no direction left out
!Battle_PathStepFrames   = 7     ; !Battler_PathStepFrame of a new step: 8 frames per cell
!Battle_PathMapBytes     = $100  ; bytes of a path map (16 x 16 cells)
!Battle_CurveKeepHeading = $FF   ; curving move operand: start from !Battle_ActorUnkA5AA
!Battle_MoveKindCurve    = 7     ; !Battle_ActorMoveKind of a curving move ($CF:F405)
!Battle_ActClearBit7     = $7F   ; opcodes $5D/$5E: keep bits 0-6 of !Battler_Unk9FF7
!Battle_Unk9FF7Skip      = $80   ; !Battler_Unk9FF7 bit 7: skipped by the target scans (set by opcode $5E)
!Battle_ActNumObjThreads = 8     ; object threads 0-7
!Battle_PalSeqStepStart  = $FF   ; !Battle_ActPalSeqStep on start: the first step makes it 0
; Hit numbers (BattleAct_OpShowHitNumbers):
!Battle_HitNumSpriteBytes = $B0  ; bytes of Battle_HitNumSprite (11 slots x 4 sprites x 4 B)
!Battle_HitNumSlotBytes  = $10   ; bytes per battler slot (4 sprites)
!Battle_HitNumColourBytes = 8    ; bytes of !Battle_HitNumColoursA/B copied
!Battle_HitNumSetMask    = 7     ; opcode & this = record set (0-5 for $50-$55)
!Battle_HitNumAttr       = $31   ; attribute: priority 3, palette 0, name-table bit set
!Battle_HitNumAttrAlt    = $39   ; the same with palette 4: hit kinds 1 and 2
!Battle_ActHitKind1      = 1     ; hit kinds (!Battle_ActPcHitKind) opcodes $50-$55 tell apart; 0 = none
!Battle_ActHitKind2      = 2
!Battle_ActHitKind5      = 5     ; drawn as tiles !Battle_HitNumTileK5A/B instead of a number
!Battle_HitNumTileZero   = $90   ; digit tile 0 (!BattleRom_DigitTilesB): a leading one is not drawn
!Battle_HitNumTileK5A    = $9A   ; the two tiles drawn for hit kind 5 (probably a word such as "miss"; not checked)
!Battle_HitNumTileK5B    = $9B
!Battle_HitNumHighHidden = $55   ; high-table byte: x bit 8 set for all four sprites (off screen)
!Battle_HitNumShow0      = $FC   ; masks that clear the x bit 8 of sprite 0, 1, 2 or 3 in the high-table byte
!Battle_HitNumShow1      = $F3
!Battle_HitNumShow2      = $CF
!Battle_HitNumShow3      = $3F
; Palettes:
!Battle_ActOpLoadPal     = $60   ; opcode $60 (BattleAct_OpLoadPalEntry)
!Battle_ActOpStartPalSeq = $61   ; opcodes $61-$64: start palette sequence 0-3
!Battle_ActOpStopPalSeq  = $65   ; opcodes $65-$68: stop sequence 0-3
!Battle_PalListPosMask   = 7     ; !BattleRom_PalListFlags bits that place the colours
!Battle_PalSet6Len       = 6     ; bytes of a !BattleRom_PalSets6 set
!Battle_PalSet14Len      = $0E   ; bytes of a !BattleRom_PalSets14 set
!Battle_SpecialPalette   = 8     ; !Battler_Palette: the unit at !Battle_PaletteLive+$80 that opcode $69 fills
!Battle_SpecialPalLen    = $18   ; bytes opcode $69 copies from !BattleRom_SpecialPals (then 6 bytes of $FF)
!Battle_SpecialPalFill   = $FF   ; byte for the last six colour bytes of that palette
!Battle_PaletteLoBytes   = $100  ; bytes of !Battle_PaletteLiveLo (end of the copies into it)
; Links, headings, sound, calls:
!Battle_ActObjLinkBit7   = $80   ; opcode $73's flag in !Battle_ActObjLinks
!Battle_ActObjLinkBit6   = $40   ; opcode $74's flag
!Battle_ActObjLinkThreadMask = $3F ; bits of the object thread kept below the flag
!Battle_ActRefFirstObj   = $0A   ; opcode $75 operand: 0-9 = entry of !Battle_ActBattlers, 10 on = object thread n - 10
!Battle_ActOpSound       = $78   ; opcodes $78/$79: APU command !Sfx_CmdUnk18 + (opcode - this)
!Battle_ActOpSoundCalc   = $7A   ; opcodes $7A/$7B: the same with a calculated !Sfx_Param2
!Battle_ActOp80LenMask   = $0F   ; opcode $80: low bits of the length byte = bytes copied, the length byte included
!Battle_ActOpSetCalcSel  = $81   ; opcodes $81-$84: !Battle_ActCalcSel entry 0-3
!Battle_ActOpSetCalcSel4 = $47   ; opcodes $47/$48: entries 4 and 5
; Arc and heading moves (opcodes $98-$A9):
!Battle_MoveKindArc      = 1     ; !Battle_ActorMoveKind of an arc move ($CF:F087)
!Battle_MoveKindHeading  = 2     ; ... of a heading move ($CF:F194)
!Battle_ActOpArcQuarter  = $9C   ; opcodes $9C/$9D: the arc opcodes' quarter form (BattleAct_ArcQuarterPoint)
!Battle_ActOpArcQuarterUnkPoint = $9D
!Battle_ArcModeHalf      = 2     ; !Battle_ActorArcMode: start speed !Battle_ArcSpeedHalf instead of !Battle_ArcSpeedFull
!Battle_ArcSpeedFull     = $FFFF ; arc start speeds
!Battle_ArcSpeedHalf     = $7FFF
!Battle_HeadProbeDist    = $10   ; heading moves: distance ahead of the actor whose cell is tested
!Battle_CellBlocksAny    = $C0   ; !Battle_CellMap bits 6-7: either kind of blocking cell
!Battle_ActMidRise       = $40   ; BattleAct_CalcMidpointSteps: !Battle_ActUnkMidY is this far above the midpoint
!Battle_ActUnkAAFCStart  = $24   ; BattleAct_CalcMidpointSteps: start value of !Battle_ActUnkAAFC
; Circle, kind-4, shake moves (opcodes $C0-$C3, $D2-$D8):
!Battle_MoveKindCircle   = 3     ; !Battle_ActorMoveKind: circle around a centre ($CF:F1F8)
!Battle_MoveKindUnk4     = 4     ; ... opcode $D2's arc-like move ($CF:F23D; see BattleAct_OpMoveKind4ToCalc)
!Battle_MoveKindEllipse  = 5     ; ... the circle with half the radius in y ($CF:F354)
!Battle_MoveKindShake    = 6     ; ... the offset toggled on and off along a heading ($CF:F39F)
!Battle_CircleRadiusMask = $7F   ; circle opcodes: low 7 bits of the first operand = radius (bit 7 = direction)
!Battle_Kind4AccelDiv    = $80   ; opcode $D2: !Battle_ArcSpeedHalf / this = the accel ($FF)

; Facing modes (BattleAct_CalcFacing, opcode $72) and calc handlers (BattleAct_RunCalc):
!BattleAct_FaceModeToward = $0A  ; modes $0A-$13: face entry (mode - this) of !Battle_ActBattlers (0-9 copy its facing)
!BattleAct_FaceModeFixed = $14   ; modes $14-$17: facing = mode - this (!Battle_FacingUp..Right); $18 = face the centre
!BattleAct_CalcOffsetPos = $09   ; handlers $09-$11: entry (n - this) of !Battle_ActBattlers, with its screen offsets
!BattleAct_CalcYMax      = $FF   ; those handlers clamp y + offset to 0..this
!BattleAct_CalcAheadDist = $18   ; handler $17: pixels ahead of the actor along its move angle (Battle_SinLookup scale)
!BattleAct_CalcFixedXY   = $80   ; handler $18: the point it gives, in both x and y (meaning unknown)
!BattleAct_CalcSavedPos  = $19   ; handlers $19-$1B: !Battle_ActSavedX/Y entry (n - this)
!BattleAct_CalcObjOffset = $1C   ; handlers $1C-$23: object (n - this) position plus !Battle_ActObjOfsX/Y
!BattleAct_CalcLerpCaster = $24  ; handlers $24-$29: point between entry 0 and the main target, weight pair n - this
!BattleAct_CalcVarPair   = $2A   ; handlers $2A-$31: !Battle_ActVars pair (n - this)
!BattleAct_CalcLerpEntry1 = $32  ; handlers $32-$38: the same from entry 1
!BattleAct_CalcLerpOffset = $39  ; handlers $39-$3F: the same from entry 0, both points with their screen offsets
!BattleAct_CalcLerpObj0  = $41   ; handlers $41-$47: point between entry 0 and object 0, weight pair n - this

; --- Sound (APU command block !Sfx_Command) ---
!Sfx_CmdPlay             = $19   ; APU command used for every menu sound in this bank (inferred: play SFX)
!Sfx_Param2Default       = $80   ; !Sfx_Param2 value sent with it (meaning not established)
!Sfx_TurnReady           = $42   ; sound id played when a PC's turn comes up (inferred)
!Sfx_CmdUnk18            = $18   ; APU command service 4 sends when an action's script has ended; meaning unknown
!Sfx_Unk18Arg            = $FF   ; !Sfx_Param1 sent with it

; --- Battle main routine (BattleSys_Main) ---
!BattleSys_ServiceUnk0    = 0     ; $C10045 service run first by BattleSys_Main (BattleSys_SceneSetup)
!BattleSys_ServiceUpkeep  = 3     ; ... BattleSys_UpkeepTwoFrames
!BattleSys_ServiceUnk6    = 6     ; ... BattleSys_Service6 (BattleCF_RemoveMarkedEnemies), run by the debug win
!BattleSys_ServiceVictory = 8     ; ... BattleSys_VictoryPose
!BattleSys_ServiceDefeat  = 9     ; ... BattleSys_DefeatPose
!Battle_EntryNone         = $FF   ; list / slot entry: empty (the BattleSys_Main lists, !Battler_UnkAEFF)
!Battle_2989Bit5          = $20   ; !Battle_Unk2989 bit 5: Battle_RandRange returns its low bound; BattleSys_Main
                                  ; skips the turn lists and ends after one pass (meaning unknown)
!Battle_NumEnemies        = 8     ; enemy entries (slots 3-10)
!Battle_NumLists          = 13    ; turn lists in !Battle_ListFlags / !Battle_ListTimers
!Battle_ListEntries       = !Battle_NumLists*!Battle_NumSlots ; bytes in each of those two arrays ($8F)
!Battle_ListBit0          = $1000 ; !Battle_ListDue bit of list 0 (list n: this >> n)
!Battle_ListDueBit        = $80   ; !Battle_ListFlags bit: the slot is due
!Battle_StatsStride       = $80   ; bytes per BattlerStats record
!Battle_StatusKo          = $80   ; BattlerStats.Status bit 7: KO'd
!Battle_UnkB0B6Slots      = 10    ; BattleSys_Main runs $C1:B0B6 for Y = 0 to this (11 calls: Y is tested after the call)
!Battle_EndUnk895BArg     = $79   ; A passed to $C1:895B on the !Battle_Unk99CD end (meaning unknown)
!Battle_EndUnkCD0021Arg   = 8     ; A passed to $CD:0021 on that end (meaning unknown)
!Battle_RewardBitGold     = $40   ; !Battle_UnkB2AF bit set once the gold is paid
!Battle_RewardBitItem     = $20   ; !Battle_UnkB2AF bit set once an item is given
!Battle_NumRewardItems    = 6     ; entries in !Battle_RewardItems
!Battle_JoySelectHi       = $20   ; JOY2H bit 5: Select
!Battle_AF15NotCounted    = $40   ; !Battle_UnkAF15 bit 6: the enemy does not count for the victory test
!Battle_RandFullRange     = $FF   ; Battle_RandRange: high - low of this returns the raw random byte
!Battle_Mul16Steps        = 16    ; Battle_Mul16: one step per multiplier bit
!Battle_Div32Steps        = 32    ; Battle_Div32: one step per dividend bit

; --- Turn lists (BattleSys_ListHandler*, BattleSys_Unk8461) ---
!Battle_ListDueAll        = $1FFF ; !Battle_ListDue: the bits of lists 0-12
!Battle_ListIndex9        = 9     ; turn list 9
!Battle_ListIndex10       = 10    ; turn list 10
!Battle_TurnList          = 12    ; turn list 12, the battlers' turns (BattleSys_Unk8461)
!Battle_ListRunsReset     = 10    ; !Battle_ListRuns value set back after the last run
!Battle_List0StatusBit    = $80   ; BattlerStats.Status2 bit list 0 clears at its end
!Battle_List1StatusBit    = $40   ; BattlerStats.Status2 bit that makes list 1 hit
!Battle_List3StatusBit    = $80   ; BattlerStats.Unk4C+1 bit list 3 clears at its end
!Battle_List4StatusBit    = $40   ; BattlerStats.Unk4C+1 bit list 4 clears at its end
!Battle_List5StatusBit    = $40   ; BattlerStats.Unk4C+2 bit list 5 clears at its end
!Battle_List8StatusBit    = $10   ; BattlerStats.Status2 bit that makes list 8 call Battle_RecordHit / Battle_ApplyHits
!Battle_List9StatusBit    = $20   ; BattlerStats.Unk4C+2 / Unk4C+7 bit that makes list 9 hit
!Battle_List10StatusBit   = $04   ; BattlerStats.Unk4C+2 bit list 10 clears at its end
!Battle_ListHalveBit      = $80   ; BattlerStats.Unk4C+1 / Unk4C+6 bit: lists 8 and 9 halve their timer
!Battle_ListDoubleBit     = $20   ; BattlerStats.Status2 bit: lists 8 and 9 double their timer
!Battle_List1DivBase      = 8     ; list 1's divisor: BattlerStats.Unk64 / 2 + this
!Battle_List1HitKind      = 3     ; !Battle_ActPcHitKind of list 1's hit
!Battle_List8Amount       = 1     ; !Battle_UnkAD89 of list 8's call
!Battle_List9Amount       = 5     ; !Battle_UnkAD89 of list 9's hit
!Battle_List9HitKind      = 2     ; !Battle_ActPcHitKind of list 9's hit
!Battle_List9UnkB202      = $C0   ; !Battle_UnkB202 of list 9's hit (meaning unknown)
!Battle_ListHitActId      = $7F   ; A for BattleSys_Unk895B after the hits of lists 1 and 9 (action record)
!Battle_ActMainMaskSlot0Hi = $80  ; high byte of !Battle_ActMainMask with only slot 0 (bit 15)
!BattleSys_ServiceEnqueue = 1     ; $C10045 service BattleMenu_EnqueueReadyBattler
!Battle_TurnAnimLo        = $0A   ; BattleSys_Unk8461: an enemy whose !Enemy_AnimWanted is in
!Battle_TurnAnimEnd       = $11   ; [this low, this end) (or 0, 4, 6) takes its turn; meaning unknown
!Battle_TurnNoReactBit    = $04   ; BattlerStats.Status2 bit: no reaction scripts after this enemy's turn
!Battle_NoReactMask       = $8F   ; BattlerStats.Status2 bits: any set = the enemy's reaction script is skipped
!Battle_UnkAEB2Bytes      = 9     ; bytes BattleSys_Unk8461 zeroes from !Battle_UnkAEB2
!Battle_UnkB192Size       = 4     ; bytes per !Battle_UnkB192 record
!Battle_AF15Bit7          = $80   ; !Battle_UnkAF15 bit 7: BattleSys_Unk8C09 runs the enemy even with no id
!BattleAi_BlockEnd        = $FE   ; script byte that ends a block's test part and its action part
!BattleAi_ScriptEnd       = $FF   ; script byte that ends a script part
!BattleAi_CodeUnk20       = $20   ; first code of a reaction part that lets an empty enemy entry run it (and puts
                                  ; its id back); meaning unknown
!BattleAi_RecordSize      = 4     ; bytes per test record in a script block
!BattleAi_SecondTest      = $01   ; !Battle_UnkB1CF: the block has a second test (set before the first runs)
!BattleAi_FirstPassed     = $80   ; !Battle_UnkB1CF: the first of two tests passed (BattleAi_NoteFirstTest)
!BattleAi_TestFailed      = 1     ; !Battle_UnkAF24 left by a test that fails (it counts up)
!BattleAi_NoTarget        = 2     ; !Battle_UnkAF24 left by a choose handler that found no target (BattleAi_RunMainPart
                                  ; then zeroes !Battle_UnkB2B6 and skips only the action part)
!BattleAi_ActRestart      = $04   ; action code: a chosen block whose action part starts with it is begun from its
                                  ; first action again (BattleAi_TestPassed); meaning of the action not traced
!BattleAi_ActCode1        = 1     ; action code 1: BattleAi_SetCmdBits adds $80 and !Battle_UnkAEEB = 4
!BattleAi_ActCode2        = 2     ; action code 2: BattleAi_EnemyTurn goes to $C1:D7C4 (others: $C1:D8D1);
                                  ; BattleAi_SetCmdBits adds $40
!BattleAi_CmdBitCode1     = $80   ; !Battle_UnkB18E bit for action code 1
!BattleAi_CmdBitCode2     = $40   ; !Battle_UnkB18E bit for action code 2
!BattleAi_UnkAEEBCode1    = 4     ; !Battle_UnkAEEB for action code 1
!BattleAi_RunBuild        = 0     ; !BattleAi_RunMode: build the action block, then play
!BattleAi_RunPlay         = 1     ; !BattleAi_RunMode: play the block as it is
!BattleAi_RunNone         = 2     ; !BattleAi_RunMode: neither; BattleAi_EnemyTurn only steps on to the next action
!BattleAi_ActCodeSwapped  = 5     ; !BattleAi_ActCode left by run handler $07 (read later: not traced)
!BattleAi_ActCodeGone     = 7     ; !BattleAi_ActCode left by run handler $09 (read later: not traced)
!BattleAi_StatDeltaSub    = $80   ; run handler $0C: delta bit 7 set = subtract the rest
!BattleAi_StatByteMax     = $FF   ; run handler $0C: the sum is capped here
!BattleAi_FlagsNop7       = $80   ; run handler $0D's flag bits, highest first: $80 nothing ...
!BattleAi_FlagsClearB320  = $40   ; ... zero the enemy's !Battle_UnkB320 ...
!BattleAi_FlagsClearSt1   = $20   ; ... clear BattlerStats.Status bit 1 ...
!BattleAi_FlagsNop4       = $10   ; ... nothing ...
!BattleAi_FlagsClearClock = $08   ; ... zero !Battle_FrameCounter's low 3 bytes ...
!BattleAi_FlagsIncB320    = $04   ; ... count !Battle_UnkB320 up ...
!BattleAi_FlagsSetSt1     = $02   ; ... set BattlerStats.Status bit 1 ...
!BattleAi_FlagsNop0       = $01   ; ... nothing
!BattleAi_StatusBit1      = $02   ; the BattlerStats.Status bit run handler $0D sets / clears (meaning unknown)
!BattleAi_AnimNoTarget    = 4     ; !Enemy_AnimWanted set when the chosen target is an enemy that is gone (one of the
                                  ; values that let BattleSys_Unk8461 run the enemy's turn)
!BattleAi_RandPcBound     = $30   ; Battle_RandRange high bound for a random PC: the result / 16 is 0-2
!BattleAi_NoPlayMask      = $82   ; acting battler's BattlerStats.Status2 bits that stop the play (meaning unknown)
!BattleAi_AE55Bit3        = $08   ; !Battle_UnkAE55 bit that stops BattleAi_EnemyTurn's reaction flag
!BattleAi_MaskSlot0       = $8000 ; !Battle_ActMainMask bit of slot 0 (slot n: this >> n)
!BattleAi_ArgUnk1         = 1     ; BattleAi_ArgToDp0E: !BattleAi_ActArg 1 and 2 give 4,
!BattleAi_ArgUnk2         = 2
!BattleAi_ArgUnk3         = 3     ; ... 3 and 4 give $0D (meaning unknown)
!BattleAi_ArgUnk4         = 4
!BattleAi_ArgOut12        = 4
!BattleAi_ArgOut34        = $0D
!Battle_HitEntrySize      = 4     ; bytes per battler slot in a !Battle_HitAmount / !Battle_ActPcHitAmount set
!Battle_HitSetSize        = (!Battle_NumSlots*!Battle_HitEntrySize) ; bytes per set ($2C)
!Battle_HitNegate         = $80   ; !Battle_UnkB202 bit: Battle_RecordHit negates !Battle_UnkAD89 first
!Battle_HitMpBit          = $4000 ; !Battle_HitFlags bit: the amount is taken off MP, not HP
!Battle_HitMpBitHi        = $40   ; the same bit in !Battle_HitFlagsHi
!Battle_HitCancelBitHi    = $20   ; !Battle_HitFlagsHi bit: Battle_ClearCancelledHits zeroes the slot's amounts
!Battle_StatsEnd          = (!Battle_NumSlots*!Battle_StatsStride) ; offset past the last BattlerStats record ($580)
!BattleAi_TargetMarked40  = $40   ; !BattleAi_Targets bit set by BattleAi_AddPcByByte (PcStatBlk.Unk20 bit 5)
!BattleAi_PcUnk20Bit5     = $20   ; PcStatBlk.Unk20 bits BattleAi_AddPcByByte copies into the entry's marks
!BattleAi_PcUnk20Bit4     = $10
!BattleAi_PcMaskAny       = $FF   ; !BattleAi_PcByteMask: any bit (BattleAi_TargetsByPcByte)
!BattleAi_TargetMarked    = $80   ; !BattleAi_Targets bit: a test accepted the entry
!BattleAi_TargetSlotMask  = $0F   ; !BattleAi_Targets bits that hold the slot
!BattleAi_TargetUseFirst  = $80   ; target code bit: use !BattleAi_FirstTarget instead of a target handler
!BattleAi_ScriptUnk8D08   = $8D08 ; bank-$CC script BattleAi_PickScript uses instead of the enemy's own when
                                  ; BattlerStats.Unk4C+2 or +7 has bit 7 (one test-0 block, action 1; meaning unknown)
!BattleAi_ScriptUnk8D1E   = $8D1E ; ... and when BattlerStats.Status2 has bit 2 that .Unk4C+4 lacks (action 4 list)
!BattleAi_Unk4CBit7       = $80   ; the BattlerStats.Unk4C+2 / +7 bit for !BattleAi_ScriptUnk8D08
!BattleAi_Status2Bit2     = $04   ; the BattlerStats.Status2 bit for !BattleAi_ScriptUnk8D1E (the same bit as
                                  ; !Battle_TurnNoReactBit)
!BattleAi_TgtCodePcs      = $01   ; target code 1: the present PCs (BattleAi_TargetTable entry 1); test $02's choice
!BattleAi_TgtCodeUnk16    = $16   ; target code $16: the present enemies (BattleAi_TargetEnemies); test $02's other choice
!BattlePos_QueryWithin32  = 4     ; !BattlePos_Mode: subject within 32 pixels of other (test $0C)
!BattlePos_QuerySameRow   = 5     ; !BattlePos_Mode: |dy| within !BattlePos_RowBand (test $0D)
!BattlePos_QueryAbove     = 6     ; !BattlePos_Mode: subject above other; + 1 = left of other (test $0E)
!BattlePos_QueryPathClear = 8     ; !BattlePos_Mode: path to the other is clear (test $0F)
!BattlePos_QueryLowerHalf = 9     ; !BattlePos_Mode: subject in the lower half (test $10) ...
!BattlePos_QueryUpperHalf = $0A   ; ... upper half
!BattlePos_QueryRightPart = $0B   ; ... right part
!BattlePos_QueryLeftPart  = $0C   ; ... left part
!BattlePos_QueryWithin48  = $0E   ; !BattlePos_Mode: subject within 48 pixels of other (test $1F)
!BattlePos_QueryNearestPc = 0     ; !BattlePos_Mode: nearest PC (target handler $06)
!BattlePos_QueryFarthestPc = 1    ; !BattlePos_Mode: farthest PC (target handler $07)
!BattlePos_QueryFarthestEnemy = 3 ; !BattlePos_Mode: farthest enemy (target handler $18)
!BattleAi_RandPcHigh      = $63   ; target handler $05: Battle_RandRange high bound (rolls 0-98) ...
!BattleAi_RandPc1From     = $21   ; ... rolls from here pick PC 1 (below: PC 0) ...
!BattleAi_RandPc2From     = $42   ; ... from here PC 2
!BattleAi_HpStartMin      = $7FFF ; target handler $08: start of its lowest-HP search
!BattleAi_HpStartMinAll   = $FFFF ; target handlers $19 / $26: start of their lowest-HP search
!BattleAi_TgtBit0         = $01   ; !BattleAi_PcByteMask bits the target handlers $0E-$14, $20-$25
!BattleAi_TgtBit1         = $02   ;   ask for in a stat-block byte (meanings unknown; see each
!BattleAi_TgtBit2         = $04   ;   handler for the byte)
!BattleAi_TgtBit3         = $08
!BattleAi_TgtBit4         = $10
!BattleAi_TgtBit6         = $40
!BattleAi_TgtBit7         = $80
!BattleAi_PathArgBit0     = $01   ; test $0F: !BattlePos_Arg = record byte 2 * 4 + this
!BattleAi_PercentBound    = 100   ; Battle_RandRange high bound for a 0-99 roll (test $17, choose $04)
!BattleAi_B19EKindMask    = $F0   ; !Battle_UnkB19E byte 0 bits tests $11/$12 compare
!BattleAi_B19EKind0       = $40   ; ... with this when the record's selector is 0
!BattleAi_B19EKind1       = $50   ; ... with this when it is 1
!BattleAi_B19EBit4        = $10   ; !Battle_UnkB19E byte 0 bit tests $13/$14 look at
!BattleAi_B19ELowMask     = $0F   ; !Battle_UnkB19E byte 0 low nibble (test $14: a battler slot, probably)
!BattleAi_ChanceStep1     = 25    ; choose $04: rolls 0-99 below this take the next action ...
!BattleAi_ChanceStep2     = 50    ; ... below this the one after it ...
!BattleAi_ChanceStep3     = 75    ; ... below this the third; the rest the fourth
!BattleAi_EffByte2Keep    = $F0   ; choose $04 keeps these bits of !Battle_UnkAEE6+2 and ORs DP $0E into the rest

; --- Battle setup (Battle_SetupBattle) ---
!Battle_StatsUnk2DCalc56  = 5     ; BattlerStats.Unk2D value that makes Battle_SetupBattle derive .Unk56
!Battle_Unk56Divisor      = 24    ; Battle_CalcUnk56: .Unk3F / this ...
!Battle_Unk56Base         = $44   ; ... + this
!Battle_CmdBytesCleared   = 18    ; BattleCmd bytes Battle_SetupBattle zeroes (3 records are 21 bytes)
!Battle_UnkAD8EBytes      = 12    ; bytes of !Battle_UnkAD8E set to $FF
!Battle_StatByteMax       = $00FF ; clamp of the 8-bit stat sums (16-bit compare)
!Battle_PcStatUnk4CBit6   = $40   ; PcStatBlk.Unk4C bit tested before $FD:B14D
!Battle_UnkCC0262Ofs      = $0262 ; added to .Unk29 * 6 for an X that is then overwritten (quirk)
!Battle_EnemyRecUnk5E04Size = 7   ; bytes per record at !BattleRom_EnemyUnk5E04
!Battle_AE5DBit7          = $80   ; !Battle_UnkAE5D: the enemy record's byte 1 is non-zero
!Battle_AE5DBit6          = $40   ; !Battle_UnkAE5D: its byte 0 is non-zero
!Battle_CF15Call1A        = $29   ; arguments ($06, $08) of Battle_SetupBattle's four $C1:CF15 calls
!Battle_CF15Call1B        = $43   ; (third argument 6, 3, 3, 4); meaning unknown
!Battle_CF15Call2A        = $27
!Battle_CF15Call2B        = $70
!Battle_CF15Call3A        = $28
!Battle_CF15Call3B        = $48
!Battle_CF15Call4A        = $2A
!Battle_CF15Call4B        = $4B

; --- Bank $FD battle helpers (BattleFD_*) ---
!Battle_RestoreHpHalf     = 1     ; BattleFD_RestoreEnemies HP mode (script byte +9): half the max HP
!Battle_RestoreHpQuarter  = 2     ; ... a quarter of it
!Battle_RestoreHpOne      = 3     ; ... 1 HP (other values: the full HP BattleFD_UnkB438 set)
!Battle_RestoreActKind    = 2     ; !Battle_ActKind BattleFD_RestoreEnemies sets
!BattleRom_UnkB18ERecSize = 11    ; bytes per record of !BattleRom_UnkCC6FCB / UnkCC88CB
!Battle_AutoEnemyBit      = $80   ; BattlerStats.Unk4C+2 / Unk4C+7 bit: BattleFD_UnkAB30 makes the PC attack a random enemy
!Battle_AutoAnyBit        = $04   ; BattlerStats.Status2 bit: BattleFD_UnkAB30 makes the PC attack a random other battler
!Battle_UnkB3C9Auto       = $80   ; !Battle_UnkB3C9 value BattleFD_UnkAB30 sets
!Battle_PercentRange      = 100   ; Battle_RandRange high bound for a 0-99 roll
!Battle_ItemDrawBelow     = 90    ; BattleFD_AddEnemyRewards: a roll below this gives .ItemA (90%)
!Battle_RewardListLen     = 3     ; items in each half of !Battle_RewardItems
!Battle_Unk78CounterBit   = $40   ; BattlerStats.Unk78 bit: the slot may act in BattleFD_UnkAC6E
!Battle_Unk7AActNowBit    = $80   ; BattlerStats.Unk7A bit: BattleFD_UnkAC6E makes the slot act at once
!Battle_HitRecClearBytes  = $B0   ; bytes BattleFD_UnkACEE zeroes from !Battle_ActPcHitAmount
!Battle_HitSetsBytes      = $84   ; bytes of the three !Battle_HitAmount sets (3 x !Battle_HitSetSize); BattleFD_UnkACFD zeroes them
!Battle_TechEntryEmpty    = $FF   ; fill of the Tech_MenuEntry blocks (BattleFD_UnkAD09)
!Battle_TechEntryBlocksBytes = $1A4 ; 3 PCs x $8C B of Tech_MenuEntry records
!Battle_RewardBitUnk0     = $80   ; !Battle_UnkB2AF bit: BattleFD_UnkAD17 shows message 0 (!Battle_UnkB28C)
!Battle_RewardBitUnk6     = $10   ; !Battle_UnkB2AF bit: BattleFD_UnkAD17 shows message 1 (!Battle_UnkB2DB)
!Battle_EndMsgUnk0        = 0     ; BattleSys_UnkVecCD0021 messages of BattleFD_UnkAD17: !Battle_UnkB28C
!Battle_EndMsgUnk1        = 1     ; ... !Battle_UnkB2DB/B2DD
!Battle_EndMsgGold        = 2     ; ... !Battle_RewardGold
!Battle_EndMsgItem        = 3     ; ... one reward item
!Battle_EndMsgUnk4        = 4     ; ... a PC's !Battle_UnkB2B0 bit 7
!Battle_EndMsgUnk5        = 5     ; ... an entry of the PC's !Battle_UnkB3CE list
!Battle_EndMsgUnk6        = 6     ; ... an entry of !Battle_UnkB305
!Battle_EndMsgUnk7        = 7     ; ... !Battle_UnkB310
!Battle_B2B0Msg4Bit       = $80   ; !Battle_UnkB2B0 bit: message 4
!Battle_B2B3Msg5Bit       = $08   ; !Battle_UnkB2B3 bits: messages 5, 6, 7
!Battle_B2B3Msg6Bit       = $04
!Battle_B2B3Msg7Bit       = $02
!Battle_UnkB3CEListMask   = 7     ; entries per PC list of !Battle_UnkB3CE - 1 (8 entries)
!Battle_Unk57CountId      = $A9   ; BattlerStats.Unk57 value BattleFD_UnkAE99 counts
!Battle_Unk57FlagId       = $AB   ; BattlerStats.Unk57 value BattleFD_UnkAEC4 flags
!Battle_Unk50Bit2         = $04   ; BattlerStats.Unk4C+4 (+$50) bit BattleFD_UnkAEC4 sets
!Battle_Unk1C48Bytes      = 15    ; bytes of !Battle_Unk1C48 BattleFD_UnkAEF2 fills (3 records)
!Battle_Unk1C4AInit       = $80   ; value BattleFD_UnkAEF2 puts in record byte 2
!BattleRom_UnkCC06A7Size  = 6     ; bytes per record of !BattleRom_UnkCC06A7
!Battle_HighBit           = $80   ; bit 7: the top of a bit scan or shift

!Battle_ItemClass1First   = $5A   ; first item id of the second range BattleFD_ItemRecOffset knows (ids below: the first)
!Battle_ItemClass2First   = $7B   ; ... of the third range
!Battle_ItemClass3First   = $94   ; ... of the fourth range
!Battle_ItemClass4First   = $BC   ; ... of the fifth range: the ids the battle item list can take
!Battle_ItemIdEnd         = $F2   ; BattleFD_ItemRecOffset: ids from this on get no offset
!Battle_ItemRec0Size      = 5     ; bytes per record of the first range ...
!Battle_ItemRec1Size      = 3     ; ... of the second and third
!Battle_ItemRec3Size      = 4     ; ... of the fourth and fifth
!Battle_ItemRec0Ofs       = $0262 ; offset in bank $CC of the first range's records
!Battle_ItemRec1Ofs       = $047E ; ... the second's
!Battle_ItemRec2Ofs       = $04E1 ; ... the third's
!Battle_ItemRec3Ofs       = $052C ; ... the fourth's
!Battle_ItemRec4Ofs       = $05CC ; ... the fifth's
!Battle_ItemListBit       = $80   ; !BattleRom_ItemUseFlags byte 0 bit: the battle item list takes the item
!Battle_ItemFlagUnusable  = $80   ; Item_BattleList.Flags bit 7 (the dead code of BattleFD_AddItemEntry sets it)
!Battle_ItemEntrySize     = 5     ; bytes per Item_BattleList record
!Battle_PcItemSize        = 8     ; bytes per Battle_PcItem record
!Battle_B3BFPcItemBit     = $02   ; !Battle_UnkB3BF bit BattleFD_UnkB655 sets
!Battle_Unk47Bit1         = $02   ; BattlerStats.Unk47 bit BattleFD_UnkB0D5 copies (inverted) to !Battler_Unk9F29
!Battle_Unk47Bits01       = $03   ; BattlerStats.Unk47 bits BattleFD_UnkB121 copies to !Battle_UnkA020
!Battle_StatCap99         = 99    ; BattleFD_UnkB14D: cap of five of the seven boosted stats
!Battle_StatCap16         = 16    ; cap of PcStatBlk.Unk38 (BattleFD_UnkB14D, BattleFD_UnkB7EB)
!Battle_StatCapFF         = $FF   ; cap of PcStatBlk.Unk3B (BattleFD_UnkB14D)
!Battle_AtbEmpty          = $FF   ; !Pc_AtbCur / !Pc_AtbMax before BattleFD_UnkB7EB sets them
!Battle_NumCharIds        = 7     ; entries of !Battle_UnkB1BE (character ids 0-6)
!Battle_EnemyInitSize     = 12    ; bytes per BattleEnemyInit record
!Battle_DemoRecUnk0B      = $23   ; character record bytes +11 and +14 BattleFD_UnkB2DE sets
!Battle_DemoRecUnk0C      = $80   ; character record byte +12 BattleFD_UnkB2DE sets
!Battle_DemoRecordBytes   = $0230 ; bytes BattleFD_UnkB33F copies from !MenuRom_CharRecordInit
!Battle_Unk79StatusBit    = $80   ; BattlerStats.Unk79 bit: BattleFD_UnkB363 sets status bits
!Battle_Unk79Bit6         = $40   ; BattlerStats.Unk79 bit BattleFD_UnkB363 tests to no effect
!Battle_Unk57HpQuarter    = $A0   ; BattlerStats.Unk57: BattleFD_UnkB363 adds a quarter to the max HP
!Battle_Unk57HpHalf       = $A1   ; BattlerStats.Unk57: ... adds half
!Battle_MaxHpCap          = 999   ; BattleFD_UnkB363's max HP cap
!Battle_Unk56SetA         = $3D   ; BattlerStats.Unk56 values that make BattleFD_UnkB3EB set .Unk72
!Battle_Unk56SetB         = $42
!Battle_Unk72Value        = $32   ; the value it sets
!Battle_Unk57B3EB         = $B3   ; BattlerStats.Unk57 that makes BattleFD_UnkB555 run BattleFD_UnkB3EB
!Battle_Unk6CBase         = 4     ; BattlerStats.Unk6C bytes as BattleFD_UnkB3FE sets them
!Battle_Unk6CRaised       = 5     ; the one picked by .Unk2E
!Battle_Unk2EBit7         = $80   ; BattlerStats.Unk2E bits: .Unk6C+0 ... +3
!Battle_Unk2EBit6         = $40
!Battle_Unk2EBit5         = $20
!Battle_Unk2EBit4         = $10
!Battle_EnemyRec4FBytes   = 5     ; BattleRom_EnemyStats bytes copied to .Unk4C+3 on
!Battle_EnemyRec64Bytes   = 12    ; ... to .Unk64 on
!Battle_EnemyRec46Bytes   = 3     ; ... to .Unk46 on
!Battle_AtbBase           = 105   ; list 12's reload value (BattleFD_UnkB4E7), the base of the first !Battler_UnkAFAB
!Battle_AtbStepPerUnk38   = 6     ; ... less this per point of .Unk38 (BattleFD_UnkB7EB)
!Battle_AtbTableRow       = 16    ; bytes per row of !BattleRom_UnkCC2E31
!Battle_ConfigSpeedMask   = $07   ; !Menu_Config bits that pick the row (probably the battle speed setting)
!Battle_Unk0ANotCountedBit = $01  ; PcStatBlk.Unk0A bit: the enemy gets !Battle_AF15NotCounted (BattleFD_UnkB7EB)
!Battle_List0Time         = 60    ; first timer and reload of the turn lists (BattleFD_UnkB4E7)
!Battle_List1Time         = 150
!Battle_List2Time         = 90
!Battle_List3Time         = 110
!Battle_List4Time         = 90
!Battle_List5Time         = 60
!Battle_List6Time         = 60
!Battle_List7Time         = 60
!Battle_List8Time         = 30
!Battle_List9Time         = 25
!Battle_List10Time        = 60
!Battle_List11Time        = 120
!Battle_UnkB19EBytes      = 32    ; ... from !Battle_UnkB19E and from !Enemy_AnimWanted
!Battle_UnkB18EBytes      = $30   ; bytes BattleFD_UnkB732 zeroes from !Battle_UnkB18E
!Battle_UnkB3BEInit       = 3     ; !Battle_UnkB3BE as BattleFD_UnkB732 sets it
; --- PC command runner (BattleSys_UnkB967) ---
!BattleCmd_ClearQueued    = $FF^!BattleCmd_StateQueued ; mask clearing .State bit 6
!BattleCmd_KindUnk10      = $10   ; .Kind bit 4 (from !Battle_Unk9F38, probably): calls BattleSys_UnkBC60
!BattleCmd_MenuTech       = 1     ; .Menu: the tech menu (BattleSys_UnkB967 runs a tech only from menu 1 or 3)
!BattleCmd_MenuUnk3       = 3     ; .Menu value 3, also accepted for a tech; what sets it is not traced
!BattleCmd_RecSize        = 7     ; bytes per BattleCmd record
!Tech_PartnerNone         = $0F   ; a Partners nibble: no partner
!Battle_ActKindAttack     = 1     ; !Battle_ActKind: BattleAct_LoadAttack
!Battle_ActKindTech       = 2     ; !Battle_ActKind: BattleAct_LoadTech
!Battle_ActKindItem       = 3     ; !Battle_ActKind: BattleAct_LoadKind3, which BattleSys_UnkB967's item path uses
                                  ; (id = item id, record = id - !Battle_ActKind3FirstId)
!Battle_B1FCAttackBit     = $02   ; !Battle_UnkB1FC bit 1: set over BattleSys_RunPcAttack
!Battle_GaugeCap          = $FF   ; !Battler_UnkAFAB: the largest value (doubling and the tech wait saturate here)
!Battle_GaugeTenths       = 10    ; BattleSys_ResetTechUsers: the tech wait is in tenths of the reload value
!BattleSys_ServiceRemoveReady = 2 ; $C10045 service BattleMenu_RemoveBattlerFromReady
!BattleSys_ServiceRunAction = 4   ; $C10045 service BattleSys_RunAction
!Battle_CD0021Unk3        = 3     ; A for $CD:0021 after a tech with !Battle_UnkB3BF positive; meaning unknown
!Battle_CD0021Unk0D       = $0D   ; A for it with !Battle_UnkB3BF = $FF
!Battle_UnkB3BFUnkFF      = $FF   ; the negative !Battle_UnkB3BF value that is acted on
!Battle_UnkAEE6Bytes      = 17    ; bytes of !Battle_UnkAEE6: BattleSys_UnkBF81 copies them, BattleFD_UnkB555 zeroes them
!Battle_Rec05CCBit7       = $80   ; !BattleRom_UnkCC05CC byte 0: BattleSys_Effect29
!Battle_Rec05CCBit2       = $04   ; ... BattleSys_Effect2A
!Battle_Rec05CCBit6       = $40   ; ... BattleSys_Effect2B
!Battle_Unk1C48Stride     = 5     ; bytes per PC in !Battle_Unk1C48 (entries 0, 5, 10; BattleFD_UnkAEF2 fills 3)
!Battle_InvSlots          = $0100 ; entries in !Battle_InvIds
!Battle_InvKeepCount      = 2     ; BattleSys_UnkBC60: an inventory entry with this many or more is left alone
!Battle_BC60CF15Arg3      = 5     ; third and fourth arguments of BattleSys_UnkBC60's $C1:CF15 call
!Battle_BC60CF15Arg4      = 4     ; (its first two are !Battle_CF15Call1A/B)

; --- Tech MP costs ---
!Battle_TechRecSize       = 11    ; bytes per BattleRom_TechRec record
!Battle_TechRecNumMask    = $7F   ; the bits of a BattleRom_TechRec byte used as an index (bit 7 masked off)
!Battle_MpCostHalfId      = $A2   ; !Pc_UnkB3BA value: the cost is halved (rounded up)
!Battle_MpCostQuarterId   = $A3   ; !Pc_UnkB3BA value: the cost is quartered (rounded up twice)

; --- Turn helpers ($C1:B4E9-$C1:B80C) ---
!BattleCmd_StateArmed     = 1     ; .State 1: set by BattleSys_Unk8461 before service 1 adds bit 7
!Battle_CmdGroupBytes     = 9     ; bytes of !Battle_CmdGroups
!Battle_ItemListBytes     = !Item_RecordSize*$100 ; the 256 Item_BattleList records ($500 bytes)
!Battle_ItemListEntries   = $0100 ; records in Item_BattleList (BattleSys_RefundItem's scan)
!Battle_FixedAtbMax       = $30   ; !Pc_AtbMax of each PC in the !Battle_Unk2989 bit-5 battle (BattleSys_UnkB725)
!BattleCmd_AllBytes       = 3*!BattleCmd_RecSize ; the three BattleCmd records (21 bytes)

; --- Battler checks ($C1:B093-$C1:B487) ---
!Battle_LowHpShift        = 3     ; BattleSys_UnkB093: HP at most MaxHp >> this sets BattlerStats.Unk2F bit 0
!Battle_ListPartBit       = $01   ; !Battle_ListFlags bit 0: the slot takes part in the list (BattleSys_UnkB0B6)
!Battle_List2StatusBit    = $20   ; BattlerStats.Status2 bit for list 2 (the same bit as !Battle_ListDoubleBit)
!Battle_List11StatusBit   = $02   ; BattlerStats.Unk4C+1 / Unk4C+6 bit for list 11
!Battle_Status2LockBit    = $08   ; BattlerStats.Status2 bit 3: sets the PC's !Pc_LockStatus (BattleSys_UnkB0B6)
!Battle_EnemyAnimStatus7  = 4     ; !Enemy_AnimWanted BattleSys_UnkB0B6 sets while Status2 bit 7 is on
!Battle_NoActMask2        = $86   ; BattlerStats.Status2 bits 7, 2, 1: BattleSys_UnkB3F9 drops the PC's command
!Battle_Unk4C3ReviveBit   = $80   ; BattlerStats.Unk4C+3 bit 7: BattleSys_UpdateKo revives the KO'd PC once
!Battle_ReviveHpMul       = 5     ; BattlerStats.Unk66 times this = the revive's HP amount
!Battle_ActIdRevive       = $7A   ; !Battle_ActId (kind 2) of the revive's action (by context)
!Battle_CD0021Unk09       = 9     ; A for $CD:0021 after the revive (BattleMsg_InfoArgs.Id = the character)
!Battle_CharRecordSize    = $50   ; bytes per !Menu_CharRecords record (BattleFD_UnkAE52 copies a PC's record in,
                                  ; BattleSys_UnkB442 copies a PC's block back)

; --- Tech menu builders ---
!Tech_FirstTripleId       = $66   ; tech ids from here up are triple techs (the doubles end here)
!Tech_TripleEnd           = $75   ; one past the last triple tech
!Battle_TechInfoFlagsMask = $3F   ; the bits of !BattleRom_TechInfo byte 1 copied to TechMenuRec.Flags
!Battle_TechBitFirst      = $80   ; the !Battle_TechBits* bit of the tech being looked at (shifted in from bit 0 up)
!Battle_DoubleBitsPerByte = 3     ; double techs per !Battle_TechBits2 byte
!Battle_TripleBitsPerByte = 1     ; triple techs per !Battle_TechBits3 byte
!Battle_MaxDoubleEntries  = 6     ; BattleSys_UnkCA1A stops after this many double-tech entries
!Battle_CA1AUnk0AStep     = 12    ; BattleSys_UnkCA1A adds this to DP $0A per tech (never read there)
!Tech_EntrySize           = 7     ; bytes per Tech_MenuEntry record
!Tech_MpCostNone          = $FF   ; a Tech_MenuEntry .MpCost value: that slot does not take part

; --- Setup: item list and the PCs' records ---
!Battle_EquipRecSize      = 6     ; bytes per !BattleRom_EquipRec* record
!Battle_EquipBase2        = $5A   ; first .Unk28 id (subtracted before indexing !BattleRom_EquipRec2)
!Battle_EquipBase3        = $7B   ; first .Unk27 id (subtracted before indexing !BattleRom_EquipRec3)
!Battle_EquipBonusMask    = $0F   ; !BattleRom_EquipBonus bits 3-0: the amount added


; --- Action target resolution (BattleSys_UnkC1DD) ---
; Target modes as BattleSys_UnkC1DD tests them; the names follow the
; BattleTgt_ModeTable handler of the same number (the menu's meaning).
!BattleTgt_ModeSingleAlly = 0     ; mode 0: one target
!BattleTgt_ModeAllAllies = 1      ; mode 1: the caster's side
!BattleTgt_ModeSingleKoAlly = 3   ; mode 3: one KO'd target
!BattleTgt_ModePcByCharId5 = 5    ; mode 5: one target
!BattleTgt_ModePcByCharId4 = 6    ; mode 6: one target
!BattleTgt_ModeAllEnemies = 8     ; mode 8: the other side
!BattleTgt_ModeEveryone  = 9      ; mode 9: BattleSys_UnkC1DD picks one of four ways (see there)
!BattleTgt_ModeAllEnemies2 = $0A  ; mode $0A: AllEnemies in the menu; BattleSys_UnkC1DD fills no list for it
!BattleTgt_ModeEnemyLineFromCaster = $0B ; mode $0B
!BattleTgt_ModeEnemyLineFromCaster2 = $0C ; mode $0C
!BattleTgt_ModeEnemyLineFromChar3 = $0D ; mode $0D
!BattleTgt_ModeUnk0E     = $0E    ; mode $0E: SingleAlly in the menu; BattleSys_UnkC1DD picks an enemy target
!BattleTgt_ModeEnemyRow  = $0F    ; mode $0F
!BattleTgt_ModeUnk10     = $10    ; mode $10: SingleAlly in the menu; an area mode for BattleSys_UnkC1DD
!BattleTgt_ModeCasterRadius = $11 ; mode $11
!BattleTgt_ModeEnemyRadius = $12  ; mode $12
!BattleTgt_ModeChar3Radius = $13  ; mode $13
!BattleTgt_ModeUnk15     = $15    ; mode $15: SingleAlly in the menu; an area mode for BattleSys_UnkC1DD
!BattleTgt_ModeChar6Radius = $1B  ; mode $1B
!BattleTgt_ModeUnk32     = $32    ; mode $32: past BattleTgt_ModeTable; BattleSys_UnkC1DD adds the chosen target to the area's list
!BattleSys_ServiceAreaQuery = 7   ; $C10045 service number of BattleTgt_RunAreaQuery
!Battle_Unk4CNoActMask   = $18    ; BattlerStats.Unk4C bits 4-3: either set = BattleSys_UnkC1DD drops the action
!Battle_RandWayPick1     = 8      ; mode 9: under this (of 100) = pick an enemy target
!Battle_RandWayOwnSide1  = 12     ; ... under this = the caster's side
!Battle_RandWayPick2     = 18     ; ... under this = pick an enemy target
!Battle_RandWayOtherSide = 20     ; ... under this = the other side; else the action is dropped
!Battle_AreaEntryBytes   = 3      ; bytes per area record entry (!BattleRom_AreaRecPtr)
!Battle_AreaQueryBit     = $80    ; entry byte 1 bit 7: a position query (service 5), not an area
!Battle_AreaParamMask    = $7F    ; entry byte 1 bits 6-0: BattleSys_AreaParamTable index
!Battle_AreaSizeMask     = $7F    ; entry byte 2 bits 6-0: !BattleTgt_AreaSize
!Battle_AreaVariantBit   = $80    ; entry byte 2 bit 7: !BattleTgt_AreaVariant = 1
!Battle_TwoEmptyEntries  = $FFFF  ; two $FF list entries read as one word
!Battle_AD8EShiftEnd     = 10     ; BattleSys_UnkC1DD shifts !Battle_UnkAD8E entries 0-9 down (entry 10 stays)
!Battle_NoTargetMaskHi   = $10    ; !Battle_ActMainMask high byte of the no-target action (bit 12; meaning unknown)
!Battle_NoTargetTech1    = $7B    ; !Battle_ActId of the action a PC's area tech plays when the area finds no one:
!Battle_NoTargetTech2    = $7C    ;   one user, two users, three users (probably a "nothing happens" display; not
!Battle_NoTargetTech3    = $7D    ;   traced)


; --- Action effects (BattleSys_RunTechParts, BattleSys_Effect*) ---
!Battle_EffArg3Mask      = $3F    ; !BattleRom_UnkCC05CC byte 3 bits 5-0: DP $16 of BattleSys_LoadEffectArgs
!Battle_EffArg2Mask      = $0F    ; byte 2 bits 3-0: its DP $18
!Battle_EffArg3Bit6      = $40    ; byte 3 bit 6: BattleSys_Effect2A also runs BattleSys_LoadEffectArgs and BattleSys_RestoreHpMp
!Battle_StatusBit6       = $40    ; BattlerStats.Status bit 6: cleared by BattleSys_Effect2C; meaning unknown
!Battle_TechParts        = 3      ; parts (users) of a tech: BattleRom_TechRec.Part1-3
!Battle_TechPartNone     = $80    ; a .Part byte with bit 7: BattleSys_RunTechParts skips the part
!Battle_TechFlagsBit6    = $40    ; BattleRom_TechRec.Flags bit 6: !Battle_UnkB2CA gets !Battle_B2CABit5
!Battle_TechFlagsBit5    = $20    ; .Flags bit 5: !Battle_UnkB2CA gets !Battle_B2CABit4
!Battle_TechFlagsMergeMask = $07  ; .Flags bits 2-0: the last !Battle_ActPcHitAmount set Battle_SumHitSets folds
!Battle_B2CABit5         = $20    ; !Battle_UnkB2CA bits, ORed into !Battle_UnkAE4D for each part; meaning unknown
!Battle_B2CABit4         = $10
!Battle_EffectRecSize    = 12     ; bytes per effect record (!BattleRom_UnkCC213F, by part number)
!Battle_B1F5StopBit      = $80    ; bit 7 of the byte BattleSys_RunTechParts reads at $7E:B1F5 + the tech offset
!Battle_B200StopBit      = $80    ; !Battle_UnkB200 bit 7: with the bit above, the tech's remaining parts are skipped
!Battle_TechMpFail       = $FF    ; !Battle_UnkB3C8 from BattleSys_CheckTechMp: a user cannot take part
!Battle_EnemyTechFlagsBit6 = $40 ; enemy record flags bit 6: BattleSys_UnkD7C4/D8D1 set !Battle_UnkB2CA to !Battle_B2CABit6
!Battle_B2CABit6         = $40    ; !Battle_UnkB2CA value of the enemy runners: !Battle_UnkAE4D gets !Battle_AE4DBit5
!Battle_B2CABit7         = $80    ; !Battle_UnkB2CA bit 7: cleared by the enemy runners (never set there)
!Battle_B2CABits76       = $C0    ; either bit: the enemy runners OR !Battle_AE4DBit5 into !Battle_UnkAE4D
!Battle_AE4DBit5         = $20    ; !Battle_UnkAE4D bit 5; meaning unknown
!Battle_EnemyPartNone    = $FF    ; an enemy record's part number: no effect
!Battle_TechFlagsStopBit = $80    ; enemy record flags bit 7: with !Battle_UnkB200 bit 7, no hit set merge
!Battle_EffByte1Mask     = $1F    ; effect byte 1 bits 4-0: DP $18 of BattleSys_EffRecArgsUnk66
!Battle_EffResultMiss    = $80    ; DP $16 after BattleSys_SetStatus in BattleSys_Effect02: a miss (never produced)
!Battle_EffResultMissFE  = $FE    ; DP $16 after BattleSys_StealItem in BattleSys_Effect06: a miss
!Battle_EffResultNoneFF  = $FF    ; ... $FF: !Battle_UnkB200 bit 7 (a dead store there)
!Battle_AE4DBit4         = $10    ; !Battle_UnkAE4D bit 4: BattleSys_Effect03 skips its first test
!Battle_AE4DBit2         = $04    ; bit 2: BattleSys_Effect03 also runs BattleSys_UnkE976
!Battle_AE4DBit1         = $02    ; bit 1: BattleSys_Effect03 also runs BattleSys_StealItem
!Battle_Eff01Bit6        = $40    ; BattleSys_Effect01: effect byte 1 bit 6: also run BattleSys_EffRecArgsUnk66 and BattleSys_RestoreHpMp
!Battle_Eff05Bit7        = $80    ; BattleSys_Effect05: effect byte 1 bits that each run BattleSys_DrainHpMp
!Battle_Eff05Bit6        = $40
!Battle_Eff05Bit7Arg     = 3      ; DP $1A for the bit-7 run
!Battle_Eff05Bit6Arg     = 7      ; DP $1A for the bit-6 run
!Battle_Eff05Bit6Arg16   = 20     ; DP $16 for the bit-6 run
!Battle_MissSecondBit7   = $80    ; effect byte 11 bits: BattleSys_RecordMiss also sets !Battle_ActFlagSecond (bit 7
!Battle_MissSecondBit6   = $40    ;   with DP $1C = 0, bit 6 with DP $1C = 1)
!Battle_HighByteMask     = $FF00  ; the high byte of a 16-bit value (the Battle_Scale* Byte forms keep it)
!Battle_HitAmountMax     = 9999   ; cap of the enemy amounts Battle_SumHitSets leaves in set 0

; --- Effect arithmetic ($C1:DA37-$C1:EB48) ---
!Battle_RestoreHpBit     = $80    ; BattleSys_RestoreHpMp: DP $1A bit 7: restore HP
!Battle_RestoreMpBit     = $40    ; ... bit 6: restore MP
!Battle_RestoreFull      = $0F    ; ... DP $18 value: restore to .MaxHp / .MaxMp
!Battle_RestoreHpStep    = 50     ; ... an HP amount not a multiple of this gets a random part
!Battle_RestoreMpStep    = 10     ; ... MP: the amount is DP $18 times this (and the same test)
!Battle_CureKoBit        = $80    ; BattleSys_CureStatus: DP $16 bit 7: also clear the KO bit
!Battle_CureKeepStatus   = $C0    ; ... the .Status bits it keeps
!Battle_CureKeepUnk4C    = $C2    ; ... the .Unk4C bits it keeps
!Battle_StatusIdxNone    = $FF    ; BattleSys_SetStatus: DP $16 value: set nothing
!Battle_SetStatusRefused = $80    ; ... DP $40 value when status byte 1 is refused
!Battle_SureHitChance    = 99     ; BattleSys_RollHit: the chance when the hit value is not below the evade
!Battle_Status2Bits12    = $06    ; BattlerStats.Status2 bits 1-2: cleared by damage (BattleSys_ApplyDamage,
                                  ; BattleSys_WakeTarget)
!Battle_Status2Bits02    = $05    ; .Status2 bits 0 and 2: BattleSys_AdjustHit / AdjustEvade cut the value
!Battle_Status2Bits71    = $82    ; .Status2 bits 7 and 1: BattleSys_AdjustEvade x 4 / 20
!Battle_Unk4DBit0        = $01    ; .Unk4C+1 / .Unk4C+6 bit 0: BattleSys_AdjustEvade doubles the value
!Battle_Twentieths       = 20     ; the divisor of the x n / 20 cuts of AdjustHit, AdjustEvade, AdjustDefence
!Battle_Twentieths10     = 10     ; x 10 / 20
!Battle_Twentieths15     = 15     ; x 15 / 20
!Battle_Twentieths16     = 16     ; x 16 / 20
!Battle_Twentieths18     = 18     ; x 18 / 20
!Battle_DefenceRange     = $0100  ; BattleSys_ApplyDamage: damage x (this - defence) / this
!Battle_B1FCBit0         = $01    ; !Battle_UnkB1FC bit 0: BattleSys_ApplyDamage skips the x 7 / 10 cuts
!Battle_B1FCHealBit      = $40    ; !Battle_UnkB1FC bit 6: BattleSys_ApplyDamage gives the amount back (and clears it)
!Battle_AE4DBit6         = $40    ; !Battle_UnkAE4D bit 6: no x 7 / 10 for !Battle_List10StatusBit
!Battle_AE4DBit7         = $80    ; !Battle_UnkAE4D bit 7: no x 7 / 10 for !Battle_List5StatusBit
!Battle_BarrierDiv       = 10     ; BattleSys_ApplyDamage: the cut is / this, then x !Battle_BarrierMul
!Battle_BarrierMul       = 7
!Battle_ArmStatus2Bits   = $F0    ; BattleSys_ArmStatusList: the .Status2 bits that have a list
!Battle_ArmUnk4CBits     = $C0    ; ... the .Unk4C / .Unk4C+1 bits that have one
!Battle_ArmUnk4C2Bits    = $60    ; ... the .Unk4C+2 bits that have one
!Battle_List6StatusBit   = $80    ; .Unk4C bit list 6 would start (dead code in BattleSys_ArmStatusList)
!Battle_List7StatusBit   = $40    ; .Unk4C bit list 7 would start (the same)
!Battle_StatMax          = $FF    ; the cap of a byte value: BattleSys_AdjustEvade, AdjustDefence

!Battle_DmgKind9         = 9      ; BattleSys_CalcDamage: formula kinds 9 and 10 (effect byte 5; their code is dead)
!Battle_DmgKind10        = 10
!Battle_DmgMul12         = 12     ; ... the factors and divisors of its formulas
!Battle_DmgMul16         = 16
!Battle_DmgDiv15         = 15
!Battle_DmgDiv18         = 18
!Battle_DmgDiv20         = 20
!Battle_DmgDiv140        = 140
!Battle_DmgCutDiv        = 10     ; ... the caster's .Status2 cuts: x 8 / this
!Battle_DmgBoostBit7     = $80    ; the caster's .Unk4C+2 | .Unk4C+7 bits: x 3 / 2 (16-bit, no truncation)
!Battle_DmgBoostBit3     = $08    ; ... / 2 x 3
!Battle_DmgBoostBit1     = $02    ; ... / 4 x 5
!Battle_Status2Bit2      = $04    ; .Status2 bit 2: BattleSys_CalcDamage divides by 4
!Battle_DefUnk6B         = $3E    ; BattleSys_AdjustDefence: effect byte 6 value: the target's .Unk6B
!Battle_DefUnk69         = $3C    ; ... value: the target's .Unk69 x 5 / 2
!Battle_AE4EScaleMask    = $03    ; !Battle_UnkAE4E bits 1-0: n, the defence x n / 4 when not 0
!Battle_ActHitKind4      = 4      ; !Battle_ActPcHitKind of an MP drain's target (BattleSys_DrainHpMp)
!Battle_DrainRandDiv     = 10     ; BattleSys_DrainHpMp: the random part is below amount / this + 3
!Battle_StealTripleUnk57 = $A5    ; BattleSys_StealItem: the caster's .Unk57 value that triples the chance
!Battle_AE4EBit7         = $80    ; !Battle_UnkAE4E bit 7: BattleSys_RunUnkB2CCHandlers also tries the caster's .Unk73
!Battle_Unk74RunBit      = $01    ; BattlerStats.Unk74 bit 0: ... and runs it
!Battle_ItemCountMax     = 99     ; BankC1_AddItem: the most of one item
!Battle_GoldCapHi        = $98    ; BankC1_AddGold: the gold cap 9,999,999 = $98967F, high byte
!Battle_GoldCapLo        = $967F  ; ... its low word


; --- Hit modifiers ($C1:ED89-$C1:F204, BattleSys_HitModTable) ---
!Battle_PlayTimeDiv      = 10     ; BattleSys_HitModPlayTime: Menu_PlayTime+1 mod this picks the factor
!Battle_PlayTimeKeepFrom = 3      ; ... remainders 1-2 halve the amount, from this on it is kept
!Battle_PlayTimeAddFrom  = 5      ; ... from this on half of DP $00 is added (a quirk)
!Battle_PlayTimeDoubleFrom = 7    ; ... from this on doubled
!Battle_PlayTimeTripleFrom = 9    ; ... from this on tripled
!Battle_StatusRollTop    = 100    ; BattleSys_HitModRandomStatus: the roll is 0 to this (BattleSys_RollUpTo1A)
!Battle_StatusByte2      = 1      ; BattleSys_SetStatus's DP $16 for status byte 1 (.Status2)
!Battle_StatusRoll1Below = 40     ; BattleSys_HitModRandomStatus: a roll below this sets .Status2 bit 2
!Battle_StatusRoll1Bits  = $04
!Battle_StatusRoll2Below = 65     ; ... below this, bit 7
!Battle_StatusRoll2Bits  = $80
!Battle_StatusRoll3Below = 90     ; ... below this, bit 1
!Battle_StatusRoll3Bits  = $02
!Battle_StatusRoll4Below = 100    ; ... below this, bit 6 (100 itself keeps A = $64: the quirk)
!Battle_StatusRoll4Bits  = $40
!Battle_Unk47StatusChance = 80    ; BattleSys_HitModUnk47Status: the roll must be at most this
!Battle_B190Bit7         = $80    ; !Battle_UnkB190 bits BattleSys_HitModUnk6CScale tests in this order:
!Battle_B190Bit6         = $40    ;   the first one set picks .Unk6C+0, +1, +2, +3
!Battle_B190Bit5         = $20
!Battle_B190Bit4         = $10
!Battle_Unk6CFactorValue = 4      ; BattleSys_HitModUnk6CScale: the amount x this / the .Unk6C value
!Battle_Unk6CHealBit     = $80    ; BattlerStats.Unk6C+n bit 7: the amount is given back (!Battle_B1FCHealBit)
!Battle_Unk6CBit6        = $40    ; ... bit 6: the divisor is 2 less
!Battle_Unk6CValueMask   = $3F    ; ... bits 5-0: the divisor
!Battle_Unk6CBit6Cut     = 2      ; ... what bit 6 takes off it
!Battle_HitModRestoreHpBit = $80  ; BattleSys_HitModRestore: DP $1C bit 7: restore the target's HP to .MaxHp
!Battle_HitModCureBit    = $40    ; ... bit 6: clear its statuses
!Battle_Unk46Bit7        = $80    ; BattlerStats.Unk46 bit 7: BattleSys_HitModHalveHp / KoOrDrop do not act on it
!Battle_HpDigitDiv       = 10     ; BattleSys_HitModHpDigit: the caster's HP mod this
!Battle_AltBoostMaxArg   = 1      ; BattleSys_HitModAltBoost: DP $1E value that makes the amount 9999
!Battle_AltBoostMul      = 2      ; ... else the amount x this


; --- Experience and tech points ($C1:F205-$C1:FA60) ---
!Battle_TotalCapHi       = $98    ; the 24-bit experience / tech point totals: cap 9,999,999 = $98967F, high byte
!Battle_TotalCapLo       = $967F  ; ... its low word
!Battle_TotalCapLoOver   = $9680  ; ... BattleSys_AddExp: a low word from this up becomes !Battle_TotalCapLo
!Battle_LevelMax         = 99     ; the highest level
!Battle_GrowStatMax      = 99     ; BattleSys_LevelUpStep: the cap of .Unk0B-.Unk11
!Battle_GrowStat0DMax    = 50     ; ... and of .Unk0D
!Battle_GrowDiv          = 100    ; ... the growth is the record byte x (level - 1) / this
!Battle_StatGrowthSize   = 7      ; bytes per !BattleRom_StatGrowth record
!Battle_MaxMpCap         = 99     ; BattleSys_GrowHpMp: the max MP cap
!Battle_ReserveExpMul    = 15     ; BattleSys_AwardReserveExp: a character not in the battle gets x 15 / 20
!Battle_ReserveExpDiv    = 20
!Battle_ComboMsgListLen  = 10     ; bytes of !Battle_UnkB305 BattleSys_AwardTechPoints sets to $FF
!Battle_ComboKinds       = 4      ; !Battle_ComboMasks entries (three pairs, one trio)
!Battle_ComboRecSize     = 5      ; bytes per !BattleRom_ComboTechs record
!Battle_ComboReqSize     = 3      ; bytes per tech in a record's requirement list (one per member)
!Battle_ComboDouble      = 2      ; members of a double tech (message 6)
!Battle_ComboTriple      = 3      ; members of a triple tech (message 7)
!Battle_ComboNone        = $FF    ; a !BattleRom_ComboTechs record's first tech id: no techs
!Battle_TechBit0         = $80    ; the first tech's bit in a !Battle_TechBits1/2/3 byte (the next ones follow down)
!Battle_TechNeedsUnlock  = $80    ; BattleRom_TechRec.UserSet bit 7: the tech needs the character's !Battle_Unk7F01E0 bit
!Battle_Unk2FAllTechs    = $10    ; BattlerStats.Unk2F bit 4: all the PC's single techs are learned

; --- Battle set-up in bank $CC ($CC:E000-$CC:F364) ---
!Battle_InitUploadDone    = 4     ; !Battle_InitUploadStage once the three stages have run
!Battle_InitPieceBytes    = $0040 ; bytes of each small upload (two 4bpp tiles)
!Battle_InitGfxABytes     = $1000 ; stage 1: !BattleRom_InitGfxA
!Battle_InitGfxAVram      = $5800 ; VRAM word address it goes to
!Battle_InitTilesBVram    = $0060 ; stage 1: !BattleRom_InitTilesB
!Battle_InitTilesCVram    = $0020 ; stage 1: !BattleRom_InitTilesC
!Battle_InitStatusMapBytes = $0780 ; stage 2: from the status-bar map buffer (BattleUI_StatusTile(0,0), read through
                                  ; bank $00)
!Battle_InitStatusMapVram = $7820
!Battle_InitTilesDVram    = $0160 ; stage 2: !BattleRom_InitTilesD, first copy
!Battle_InitTilesEVram    = $0120 ; stage 2: the same bytes again
!Battle_InitMapBufHead    = $01C0 ; stage 2: the first 7 rows of !Battle_InitMapBuf ...
!Battle_InitMapBufVram    = $7B00 ; ... to here
!Battle_InitMapTailVram   = $7800 ; stage 2: the eighth row (!Battle_InitMapBufTail)
!Battle_InitFrameBufBytes = $0C00 ; stage 3: !Battle_ActFrameBuf ($2D00-$38FF, with !Battle_InitTileBuf)
!Battle_InitFrameBufVram  = $1800
!Battle_ObjPiece2Vram     = $0060 ; Battle_InitUploadObjTilesDead: the third piece (never reached)
!Battle_ObjPiece3Vram     = $0160 ; ... and the fourth
!Battle_UnkE4Init         = $40   ; !Battle_UnkE4 at set-up
!Battle_Block1D00Bytes    = $0100 ; bytes of !Battle_Block1D00
!Battle_TechListsBytes    = $0102 ; bytes set to $FF from !Tech_ListCode ($94D0-$95D1: both tech-list arrays and
                                  ; the bytes after them)
!Battle_Cfg0ModeBit       = $40   ; !Battle_Config0 bit 6: !Battle_CfgBattleMode is this bit inverted
!Battle_Cfg0InfoBit       = $80   ; !Battle_Config0 bit 7: !BattleMenu_CfgInfoPanel
!Battle_Cfg1CursorBit     = $40   ; !Battle_Config1 bit 6: !BattleMenu_CfgCursorMemory
!Battle_Cfg1ListBit       = $80   ; !Battle_Config1 bit 7: !BattleMenu_CfgListMemory
!Battle_Unk9842Bytes      = $0F   ; bytes of !Battle_Unk9842
!Battle_Unk9842Empty      = $FF   ; their value at set-up
!Battle_PcOffsetYInit     = $F0   ; !Battler_ScreenOffsetY of the PCs at set-up (-16)
!Enemy_MoveBytes          = $10   ; !Enemy_MoveTimer and !Enemy_MoveInterval, 8 B each
!Enemy_MoveTimerInit      = $20   ; their value at set-up (overwritten for each enemy present)
!Battle_OamTableBytes     = $0200 ; entries of !Battle_OamHighXBit / !Battle_OamHighXClear / !Battle_OamHighIdx
!Battler_UnkA5C2Init      = $C0   ; !Battler_UnkA5C2 at set-up
!Battle_CellRowBytes      = $10   ; cells per !Battle_CellMap row
!Battle_CellMapBytes      = $0100 ; bytes of !Battle_CellMap (16 rows)
!Battle_CellMapMidRows    = 11    ; rows 2-12, copied from !BattleRom_CellMapRow
!Battle_FieldAttrABit7    = $80   ; !Battle_FieldAttrA bit kept as the cell's bit 7
!Battle_FieldAttrBBit7    = $80   ; !Battle_FieldAttrB bit that becomes the cell's bit 6 (shifted right once)
!BattleMenu_TechTextBytes = $0500 ; bytes of the tech-list text buffer cleared at set-up (20 map rows)
!BattleUI_StatusMapBytes  = $04C0 ; bytes of the status-bar map buffer cleared at set-up (19 map rows)
!Battle_InitMapTiles1B    = $30   ; first tile of map row 1, columns 16-31, in !Battle_InitMapBuf (columns 0-15: $00)
!Battle_InitMapTiles2A    = $10   ; first tile of row 2, columns 0-15
!Battle_InitMapTiles2B    = $40   ; first tile of row 2, columns 16-31
!Battle_InitMapRomBytes   = $C0   ; bytes from !BattleRom_InitMapRows
!Pc_NumChars              = 7     ; character ids 0-6
!Battle_PaletteCopyBytes  = $0200 ; bytes copied from !Battle_PaletteSavedLo to !Battle_PaletteLiveLo at set-up
!Battle_PcPalette0        = $0A   ; !Battler_BasePalette / !Battler_Palette of PC 0; PCs 1 and 2 get $0C and $0E
!Tech_EntryNone           = $FF   ; Tech_MenuEntry.TechId: no tech in this entry
!Tech_SingleEntries       = 8     ; Tech_MenuEntry 0-7: the single techs
!Tech_FirstDoubleEntry    = $0A   ; Tech_MenuEntry 10-15: the double techs
!Tech_DoubleEntries       = 6
!Tech_FirstTripleEntry    = $12   ; Tech_MenuEntry 18: the triple tech
!Battler_StartRecBytes    = 5     ; bytes of a Battler_StartRec
!Battler_SprBytesPc       = $0F   ; !Battler_SprBytes of a PC
!Enemy_SprFlag80          = $80   ; !Enemy_SprFlags bit 7: copied to !Battler_UnkA5C2 / !Battler_UnkA5CD
!Enemy_SprFlag08          = $08   ; bit 3: counted in !Battle_EnemyPartsOn, enemy noted in !Battle_PartsAnchor
!Enemy_SprFlag20          = $20   ; bit 5: counts !Enemy_UnkA006 up
!Enemy_SprFlag04          = $04   ; bit 2: copied to !Battler_UnkA08C
!Enemy_IdLowerA           = $D8   ; enemy ids (high byte 0) whose !Battler_ScreenY is set one pixel lower at set-up
!Enemy_IdLowerB           = $94
!Enemy_IdLowerC           = $AD
!Enemy_KindLockMenus      = 3     ; !BattleRom_EnemyKindList kind: sets !BattleMenu_Lock bit 0 (no tech or item list)
!Enemy_KindUnkA113        = 4     ; kind: !Battle_UnkA113 = 4
!Enemy_NameBytes          = $0C   ; bytes of one re-encoded enemy name row (11 letters and the end)
!Battle_SprRecCount       = $2C   ; Battle_SprRec records
!Battle_HiTableLarge4     = $AA   ; a high-table byte with the large size for all four sprites, x bit 8 clear
!Battle_SprAttrPriority2  = $20   ; attribute bits added to !Enemy_Unk988B (priority bit 5)
!Battle_SprRecRowBytes    = $10   ; four Battle_SprRec records
!Battle_InitTiles2bppCount = $10  ; tiles in !BattleRom_InitTiles2bpp
!Battle_Tile2bppBytes     = $10   ; bytes of a 2bpp tile (also the zero planes added to widen it)
!Battle_InitTiles4bppCount = $40  ; tiles in !BattleRom_InitTiles4bpp
!Battle_Tile4bppBytes     = $20   ; bytes of a 4bpp tile
!Battler_FrameDmaVramASlot3 = $0400 ; the six words Battle_InitSceneGfx gives slot 3 when its frame layout is 2 ...
!Battler_FrameDmaVramBSlot3 = $0700
!Battler_FrameDmaSizeASlot3 = $0500
!Battler_FrameDmaSizeBSlot3 = $0100
!Battler_FrameDmaSrcASlot3 = $6BAD
!Battler_FrameDmaSrcBSlot3 = $71AD
!Battler_FrameDmaVramAOther = $0680 ; ... and any other slot with frame layout 2
!Battler_FrameDmaVramBOther = $0780
!Battler_FrameDmaSizeAOther = $0100
!Battler_FrameDmaSizeBOther = $0500
!Battler_FrameDmaSrcAOther = $70AD
!Battler_FrameDmaSrcBOther = $72AD
!Battle_Unk57ValueA       = $A4   ; BattlerStats.Unk57 values of a PC that make Battle_InitSceneGfx set !Battle_Unk9F34
!Battle_Unk57ValueB       = $B8   ; (probably an accessory's id; not traced)
!Battle_ActVarsBytes      = $8D   ; bytes BattleAct_ResetState zeroes from !Battle_ActVars ($5D80-$5E0C)
!Battle_ActObjPosBytes    = $40   ; ... from !Battle_ActObjX ($A240-$A27F, up to !Battle_ActObjOfsY's end)
!Battle_ActAnimBytes      = $84   ; ... from !Battler_ActAnimMode ($A124-$A1A7)
!Battle_ActListEnd        = $FF   ; end of the !Battle_ActBattlers / !Battle_ActTargets lists
!Battle_ActObjAnimBytes   = $40   ; ... from !Battle_ActUnkA1A8 ($A1A8-$A1E7)
!Battle_ActorMoveBytes    = $72   ; ... from !Battle_ActorMoving ($A337-$A3A8)
!Battle_PosHistBytes      = $58   ; bytes of the position history from !Battler_PosHistX (4 records x 22)
!Battle_PosHistInit       = $F0   ; value it is filled with
!Battle_FxAppliedStale    = $55   ; !Battler_FxApplied value no effect has (BattleAct_ResetFxApplied)
!BattleRom_PalSets6Bytes  = 6     ; bytes of a !BattleRom_PalSets6 colour set
!BattleRom_PalSets14Bytes = $0E   ; bytes of a !BattleRom_PalSets14 colour set
!Battle_NumPalSeqs        = 4     ; palette sequences BattleAct_StepPalettes steps
!Battle_ActObjThreads     = 8     ; object threads 0-7
!Battle_ActObjTimeMask    = $7F   ; BattleRom_ActObjRec.Time: the frame count
!Battle_ActObjFrameStop   = $80   ; !Battle_ActObjFrame bit 7: the list ended at this record
!Battle_ActObjEntryRestart = $FF  ; !Battle_ActObjAnimEntry: the next step starts the list again
!Battle_ActObjRecLowMask  = $1F   ; BattleRom_ActObjRec.Flags bits 0-4
!Battle_ActObjFrameBit5   = $20   ; !Battle_ActObjFrame bit 5: the record's .Time had bit 7

; --- Bank $CF: vblank uploads and the per-frame update ---
!Battle_OamBytes          = $0220 ; bytes of OAM (low and high table) BattleCF_VblankUploads sends
!Battle_CgramBytes        = $0200 ; bytes of CGRAM (all 256 colours)
!Battle_WindowMapVram     = $7A00 ; VRAM word address !BattleMenu_WindowMap goes to (also stage 3 of
                                  ; Battle_InitUploadStep, through bank $00)
!Battle_GfxSteps          = 4     ; graphics steps of !BattleRom_GfxStepSrcA..; !Battle_UnkA4 wraps at this
!Battle_BlinkFrames       = $0C   ; frames between toggles of !BattleUI_UnkA110
!Battle_PartMainSlot      = 3     ; battler slot copied under !Battle_UnkA113 ...
!Battle_PartMirrorSlot    = 9     ; ... and the slot it is copied to
!Battle_CursorGlowSteps   = $3E   ; entries of !BattleRom_CursorGlow
!Battle_CursorPalBit      = $08   ; !BattleMenu_CursorPalette bit that picks OBJ palette 5 for the glow
!Battle_RotObjLastOfs     = $16   ; byte offset of colour 11 from colour 0: the last colour the rotation moves up
!Battle_ColourInRow       = $0F   ; colour number within a 16-colour row (mask), also the row's last colour
!Battle_ColoursPerRow     = $10   ; colours per palette row
!Battle_RowBytes          = $20   ; bytes per palette row
!Battle_DemoQuitFlag      = $80   ; value stored to !Battle_UnkBB80 before the demo battle restarts the game
!Battle_PadLR             = $30   ; JOY1L bits 5 and 4: the R and L buttons
!Battle_LrHoldFrames      = $78   ; frames L and R must be held before !Battle_Unk99CD is bumped (120)
!Battle_2989Bit7          = $80   ; !Battle_Unk2989 bit 7: holding L and R does not bump !Battle_Unk99CD
!Battle_HitNumBounceEnd   = $80   ; !BattleRom_HitNumBounce entry that ends the bounce
!Battle_HitNumSprites     = 4     ; hit-number sprites per battler slot (Battle_HitNumSprite records)
!Battle_FxCycleSecondOfs  = $18   ; second copy of the cycled colour: byte $18 of the palette unit
!Battle_FxCycleBytes      = $7C   ; length of an effect's colour list (62 colours); the step wraps here

; --- Bank $CF: the sprite builder ---
!Battle_SprIdxBias        = $0C   ; sprite index of battler slot 0 (index = slot + 12)
!Battle_SprIdxEnd         = $17   ; sprite index after the last battler (slot 10 + 12 + 1)
!Battle_SprListBattler    = $40   ; !BattleSpr_List bit: the battler's own entry (it gets the position history)
!Battle_SprListIdxMask    = $1F   ; !BattleSpr_List bits holding the sprite index
!Battle_SprListEnd        = $FF   ; !BattleSpr_List value after the last entry
!Battle_SprKeyTop         = $FE   ; sort key of the extra entry of a !Battler_UnkA5CD battler (sorts first)
!Battle_SprFirstOamOfs    = $10   ; first OAM byte offset the builder uses (sprite 4; 0-3 are the cursors)
!Battle_SprDrawn          = $80   ; !Battler_SprDrawState once the battler is drawn
!Battle_PosHistRecBytes   = 22    ; bytes from one position-history record to the next (11 x, then 11 y)
!Battle_SignFill          = $FF   ; high byte of a sign-extended negative byte
!Battle_OamKeepTileFlip   = $C1FF ; OAM tile/attribute word bits kept: flips, name bit and tile (palette and priority
                                  ; are replaced)
!Battle_SprHideY          = $F0   ; y low byte from which a sprite with y off the 0-255 range is left showing
!Battle_UnkA5D8DX         = 8     ; x left of the battler's screen x of the !Battler_UnkA5D8 sprite
!Battle_UnkA5D8DY         = 4     ; y above its screen y
!Battle_UnkA5D8Tile       = 2     ; tile of that sprite
!Battle_SprGroupBytes     = $10   ; OAM bytes of four sprites
!Battle_LastObjThread     = 7     ; object threads 0-7
!Battle_ObjThreadMask     = $07   ; bits naming an object thread
!Battle_ActLinkThreadMask7F = $7F ; clears the in-front bit (7) of a !Battle_ActObjLinks entry
!Battle_ActLinkThreadMaskBF = $BF ; clears the behind bit (6)
!Battle_ActLinkBytes      = $58   ; bytes of !Battle_ActObjLinks (8 threads x 11 slots; BattleAct_ResetState sets them)
!Battle_FxOverlayFrames   = 4     ; status-overlay frames (0-3)
!Battle_ActFrameMask      = $3F   ; !Battle_ActObjFrame bits holding the frame
!Battle_OamAttrNoPriority = $CF   ; attribute bits kept when an object's priority bits are put in

; --- Bank $CF: movers, entry and exit ---
!Battle_CellRowBottom     = $0E   ; cell row the heading movers stop at (the bottom edge row, probably)
!Battle_CellColRight      = $0F   ; cell column they stop at (the right edge column, probably)
!Battle_NearMargin        = $10   ; BattleCF_PointsNear margin of the curving and kind-4 movers (16 pixels)
!Battle_ObjNearMargin     = $18   ; the objects' kind-4 mover's first margin (24 pixels)
!Battle_Kind4LandHeight   = $E8   ; !Battler_UnkA4AF from which the kind-4 mover lands (-24..-1)
!Battle_Kind4ArcSteps     = 4     ; arc steps per move step of the kind-4 movers
!Battle_ActLinkFront      = $80   ; !Battle_ActObjLinks bit 7: the object is drawn in front of the battler
!Battle_ActLinkBehind     = $40   ; bit 6: drawn behind it
!Battle_ItemListBytes     = $0500 ; bytes of Item_BattleList (256 records of 5)
!Battle_ItemRecBytes      = 5     ; bytes per Item_BattleList record
!Battle_ItemQtyLimit      = $64   ; 100: a merged quantity that would reach this is not stored
!Battle_2989Bit1          = $02   ; !Battle_Unk2989 bit 1: copied to !Battle_UnkEC at the battle's start
!Battle_2989Bit4          = $10   ; !Battle_Unk2989 bit 4: ORed into !Battle_ActAttrBits at the start
!Battle_ActAttrInit       = $20   ; !Battle_ActAttrBits at the start (OAM priority 2), with that bit
!Battle_ClearRamLast      = $7FEB ; last word offset of the battle RAM clear from !Battle_ActFrameBuf ($7E:2D01-$ACEC)
!Battle_ClearDpLast       = $006A ; last word offset of the DP clear from $80 ($80-$EB)
!Battle_UnkB9Init         = $0F   ; !Battle_UnkB9 at the start
!Battle_Flag7F00BABit0    = $01   ; !Battle_Flag7F00BA bit 0
!Battle_Flag7F00BABit1    = $02   ; !Battle_Flag7F00BA bit 1
!Battle_CharIdMask        = $07   ; !Pc_CharId bits used as the character id
!Battle_TilePixelMask     = $0F   ; pixel within a 16-pixel tile
!Battle_FieldPcBytes      = 5     ; bytes per Battle_FieldPc record
!Battle_FieldObjBytes     = $0C   ; bytes per Battle_FieldObj record
!Battle_OamHighAllSet     = $FF   ; OAM high-table byte with x bit 8 and the size bit set for four sprites
!Battle_LastCharRecOfs    = $0C   ; offset of the last !BattleRom_CharRecOffset entry (character id 6)
!Battle_PanelMapVram      = $7820 ; VRAM word address the three queued window maps go to
!Battle_VramQRun          = $80   ; !Battle_VramQPending value set by the queue routines
!Battle_FieldObjKind6Flag = $40   ; Battle_FieldObj.Flags bit 6 (the field's FieldBtl_ObjKind6Flag): the enemy stays
                                  ; present when service 6 removes it

; --- Bank $D1's battle-effect code (BattleFx_*) ---
!Battle_JoyStartHi        = $10   ; JOY1H bit 4: Start
!Battle_JoyRLo            = $10   ; JOY1L bit 4: R
!Battle_JoyLLo            = $20   ; JOY1L bit 5: L
!Battle_2989NoPause       = $20   ; !Battle_Unk2989 bit 5 (via !BattleFx_Unk2989Copy): Start does not pause, and
                                  ; BattleCD_NmiMain's toggle button is off
!BattleFx_NmiDpSaveLen    = $2A   ; MVN count - 1: DP $00-$2A (43 bytes)
!BattleFx_UnkCE17Set      = $FF   ; !Battle_LastScriptMsg when the timer ends with !Battle_ScriptMsgUp set
!BattleFx_White           = $7FFF ; colour: white
!BattleFx_Anim7ColourBit  = $40   ; FieldAnimB[7].Unk1 bit flipped by BattleFx_SwapObjPalettes (64 colours)
!BattleFx_MapRowBytes     = $20   ; bytes per row of BattleFx_UploadMapBlock (16 map words)
!BattleFx_MapRows         = 16    ; rows it sends
!BattleFx_MapRowWords     = $20   ; VRAM words from one row to the next (a 32-word-wide map)
!BattleFx_AnimKind3       = $30   ; FieldAnimB .Unk0 value the palette moves give: kind 3, no skip
!BattleFx_AnimUnk4Init    = $0100 ; FieldAnimB .Unk4/.Unk5 (word) set by BattleFx_LoadBgRows2To4: 0 and 1
!BattleFx_GradCount       = 14    ; colours in the HP gradient
!BattleFx_GradBytes       = 28    ; bytes of them
!BattleFx_GradFadeSteps   = $20   ; steps of a gradient fade
!BattleFx_GradForceLevel  = $7F   ; !BattleFx_GradForce bits 0-6: the forced level
!BattleFx_RedMask         = $1F   ; colour bits 0-4: red
!BattleFx_GreenMask       = $03E0 ; colour bits 5-9: green
!BattleFx_GreenStep       = $20   ; one unit of green
!BattleFx_BlueMaskHi      = $7C   ; colour bits 10-14 in the high byte: blue (one unit = 4)
!BattleFx_SwayAmp         = 40    ; BattleFx_SwayQuad's sway: 40 x the sine / 256
!BattleFx_SwayLeft        = $B0   ; its top edge's left x before the sway
!BattleFx_SwaySize        = $20   ; its top and bottom edges' width
!BattleFx_SwayHalf        = $10   ; half of that, left of the point
!BattleFx_BgTilesVram     = $2000 ; VRAM word address of a background set's first pack
!BattleFx_BgPackWords     = $0800 ; VRAM words from one pack to the next
!BattleFx_BgPackBytes     = $1000 ; bytes uploaded per pack
!BattleFx_BgPackNone      = $FF   ; BattleFx_BgSetPacks entry: no pack in this slot
!BattleFx_DecompBuf       = $D000 ; $7E:D000: where BattleFx_LoadBgSet unpacks before the upload
!BattleFx_BgMapBytes      = $0800 ; bytes of a set's map uploaded
!BattleFx_BgMapVram       = $6800 ; VRAM word address of the map
!BattleFx_WinLines        = 212   ; lines BattleFx_GrowBand's row band is held to
!BattleFx_WinQuarterBytes = $D4   ; bytes of 53 lines (212 / 4 lines x 4 B): BattleFx_GrowBand's four blocks
!BattleFx_BandRowsMax     = 9     ; !BattleFx_CountB stops counting at this in BattleFx_GrowBand
!BattleFx_WinFull         = $FF00 ; a window pair word: left 0, right 255 (the whole line)
!BattleFx_WinEmpty        = $00FF ; a window pair word: left 255, right 0 (nothing)
!BattleFx_RampBottom      = $C0   ; BattleFx_RampWin2's start: $C0 - !BattleFx_CountA
!BattleFx_WaveRadius      = $60   ; the wave windows' radius before !BattleFx_CountA is taken off
!BattleFx_WinUsedBytes    = $0350 ; bytes of the wave windows' 212 lines (4 B each)
!BattleFx_SignExtend      = $FF00 ; ORA that sign-extends a negative 8-bit offset
!BattleFx_WaveBPhase      = $A8   ; added to !BattleFx_CountB for BattleFx_WaveWindowB's angles
!BattleFx_LineAddDp       = $0A00 ; D for BattleFx_AddLineOffsets: its per-line bytes at $7E:0A00
!BattleFx_InitFF          = $FF   ; value BattleFx_Init stores to several bytes (meaning not traced)
!BattleFx_IrqLine         = $D3   ; VTIMEL: the battle IRQ at line 211
!BattleFx_UnkBE9BInit     = $7878 ; !BattleFx_UnkBE9B+0/+2 at set-up
!BattleFx_UnkBEA1Init     = $0077 ; !BattleFx_UnkBE9B+6/+$E at set-up
!BattleFx_UnkBEA5Init     = $FFDF ; !BattleFx_UnkBE9B+$A at set-up
!BattleFx_UnkCA04Init     = $FF27 ; !BattleFx_UnkCA02+2 at set-up
!BattleFx_UnkCA08Init     = $00D7 ; !BattleFx_UnkCA02+6/+$A at set-up
!BattleFx_UnkCA10Init     = $000D ; !BattleFx_UnkCA02+$E at set-up
!BattleFx_UnkCA14Init     = $00BD ; !BattleFx_UnkCA02+$12 at set-up
!BattleFx_UnkC02BInit     = $0505 ; the two words of !BattleFx_UnkC02B at set-up
!BattleFx_UnkC14FInit     = 9     ; the byte at !BattleFx_WinTable0-$12 at set-up
!BattleFx_UnkCD46Alt      = $FD   ; !BattleFx_UnkCD46 when !Battle_Unk2A21 bit 0 is set
!BattleFx_UnkBEABRun1     = 19    ; !BattleFx_UnkBEAB entries with the first value
!BattleFx_UnkBEABRun      = 12    ; entries per later value
!BattleFx_UnkBEABStart    = $FFFC ; the first value (-4); each run adds 4
!BattleFx_UnkBF6BOfs      = $0098 ; !BattleFx_UnkBF6B's values are !BattleFx_UnkBEAB's less this
!BattleFx_UnkBEABBytes    = $C0   ; bytes of the 48 entries
!BattleFx_WinTableBytes   = $0380 ; bytes of a window table (224 lines x 4)
!BattleFx_UnkBB05Bytes    = $0180 ; bytes of !BattleFx_UnkBB05
!BattleFx_UnkCCEEBytes    = $10   ; bytes of !Battle_PalRowSave (8 colours)
!BattleFx_HighNibble      = $F0   ; mask: a byte's high nibble
!BattleFx_LowNibble       = $0F   ; mask: a byte's low nibble
!BattleFx_BounceMirrorOfs = $10   ; !BattleFx_RecOfs whose output is base - position
!BattleFx_WinBlockBytes   = $70   ; bytes of 28 window table lines (a table is eight such blocks)
!BattleFx_Op80Bits8Mask   = $1C   ; opcode $80 argument bits 2-4 (BattleFx_Op80Bits8)
!BattleFx_Op80BitsHiMask  = $E0   ; bits 5-7 (BattleFx_Op80BitsHi)
!BattleFx_Op80SwapBit     = $40   ; argument byte 1 bit 6 (BattleFx_Op80Kind0)
!BattleFx_Op80PairMask    = $38   ; argument byte 1 bits 3-5 (BattleFx_Op80Kind0)
!BattleFx_UnkCCC1Base     = $40   ; byte 0 of both !Battle_PalAnimRecs89 records: its base value
!BattleFx_UnkCCC1Swap     = $10   ; or'd into it with bit 6 of the argument
!BattleFx_UnkCCC8Bit7     = $80   ; the value BattleFx_Op80Kind0 gives !Battle_PalAnimRecs89+7/+8/+$13/+$14
!BattleFx_GradStartA      = $E8   ; BattleFx_BuildGradHdma: the falling lists' first value
!BattleFx_GradStartB      = $E0   ; the rising lists' first value (and the end entries' value)
!BattleFx_GradFracA1      = $AB   ; fraction byte of the first falling value
!BattleFx_GradFracB1      = $55   ; ... of the first rising value
!BattleFx_GradFracA2      = $56   ; ... of the second falling value
!BattleFx_GradFracB2      = $AA   ; ... of the second rising value
!BattleFx_GradStep1       = $0055 ; step per entry of lists A and B
!BattleFx_GradStep2       = $00AA ; step per entry of lists C and D
!BattleFx_GradRepeat1     = $81   ; first byte of the B and D entries
!BattleFx_GradHdmaBytes   = $0120 ; bytes BattleFx_BuildGradHdma zeroes
!BattleFx_GradPart1Bytes  = $60   ; bytes of 24 entries
!BattleFx_GradPart2Bytes  = $30   ; bytes of 12 entries
!BattleFx_BoxCentre       = $6A   ; BattleFx_GrowBox's centre line (106)

; ------------------------------------------------------------
; Bank $CD: constants ($CD:0000-$CD:16B4)
; ------------------------------------------------------------
!Battle_2A21Bit0          = $01   ; !Battle_Unk2A21 bit 0 (see there)
!Battle_2A21Bit4          = $10   ; !Battle_Unk2A21 bit 4: the enemy exit goes straight to the dissolve
!Battle_A01DBit0          = $01   ; !Battler_UnkA01D bit 0: the enemy exit runs !BattleCD_FxExit38
!Battle_PalAnimCopy10     = $80   ; !Battle_PalAnimCopy bit 7: copy !Battle_PalAnimRec10
!BattleCD_PalAnimClearB      = $7F   ; clears !Battle_PalAnimCopy10
!BattleCD_PalAnimClearA      = $FE   ; clears bit 0 after the !Battle_PalAnimRecs89 copy
!BattleCD_FxExit40        = $40   ; layer effect after an enemy's dissolve (the first exit path); meaning unknown
!BattleCD_FxExit38        = $38   ; layer effect of the second exit path; meaning unknown
!BattleCD_MainNoBg1       = $FE   ; !Battle_HdmaScreens AND mask: BG1 off the main screen
!BattleCD_MainNoBg2       = $FD   ; ... BG2 off the main screen
!BattleCD_ScreenBg3       = $04   ; TM/TS bit 2: BG3
!BattleCD_FxMainScreen    = $13   ; TM while a layer effect runs: BG1, BG2 and OBJ
!BattleCD_FxWinScreens    = $1717 ; TMW/TSW while it runs: BG1-3 and OBJ in both
!BattleCD_FxBg3Sc         = $7C   ; BG3SC while it runs: map at VRAM $7C00, 32x32
!BattleCD_FxBgMode        = $49   ; BGMODE line data while it runs (mode 1, BG3 on top, 16x16 BG1 tiles; from the value)
!BattleCD_SfxDissolve     = $95   ; BattleCD_ApuCmd18 sound of the dissolve
!BattleCD_SfxWipe         = $08   ; ... of the opening wipe
!BattleCD_SfxArgCentre    = $0080 ; X (the APU's second argument) for sounds not tied to a battler: the middle, probably
!BattleCD_DissolvePattern = 7     ; !Battle_DissolvePattern of every dissolve
!BattleCD_DissolveRecBytes = $0009 ; bytes of !BattleRom_DissolveRec copied (1-9)
!BattleCD_DissolveDelay   = 10    ; frames before the dissolve starts
!BattleCD_DissolveSteps   = 32    ; dissolve steps (two phases each)
!BattleCD_DissolveSlot6   = $0006 ; the slot whose layout 2 is treated as layout 5
!BattleCD_DissolveRowBits = $0038 ; !Battle_DissolvePhase bits 3-5: the pixel row
!BattleCD_TilePlanes23    = $0010 ; offset of bit planes 2-3 in a 4bpp tile
!BattleCD_MsgNoSfx        = $FF   ; BattleFx_MsgSfx: no sound
!BattleCD_MsgFixedWait    = 60    ; frames message !Battle_EndUnkCD0021Arg stays up
!BattleCD_MsgShownOn      = $10   ; !Battle_MsgShown while a message is up
!BattleCD_TextStepCount   = $40   ; TextWin_StepCount of the first step: the whole string, probably
!BattleCD_InfoEnemy       = $0C   ; !BattleRom_MsgStrings string of BattleCD_ShowEnemyInfo
!BattleCD_InfoTarget      = $0B   ; ... of BattleCD_ShowTargetInfo
!BattleCD_TextGfxPart     = $0080 ; an eighth of !Battle_TextGfxBuf (one store a pass in BattleCD_ClearTextGfx)
!BattleCD_TextHalfBytes   = $0200 ; half of !Battle_TextGfxBuf (one frame's upload)
!BattleCD_TextVramA       = $5800 ; VRAM word address of the text's first half
!BattleCD_TextVramB       = $5980 ; ... of its second half
!BattleCD_PadDelayFirst   = $000F ; !Battle_PadDelay after nothing was held
!BattleCD_PadDelayRepeat  = $18   ; !Battle_PadDelay after a press of the button in bit 7
!BattleCD_PadToggleBit    = $01   ; !Battle_PadHeld bit the NMI toggles !BattleFx_CeSetWant with
!BattleCD_Cmd81Arg1       = $10   ; first argument of BattleCD_ApuCmd81's !Audio_CmdUnk81
!BattleCD_ApuCmd80        = $80   ; APU command of BattleCD_RunEndFx (sent as it is); meaning unknown
!BattleCD_Cmd80Arg2       = $FF   ; its second argument
!BattleCD_EndSong         = $3A   ; song BattleCD_RunEndFx plays (!Audio_CmdPlayMusic)
!BattleCD_ExitFadeFrames  = 15    ; frames waited after several screen changes
!BattleCD_FxPalDelayLong  = 31    ; frames waited after BattleCD_LoadFxPalB with !Battle_Unk2A21 bit 0
!BattleCD_EvtBit6         = $40   ; FieldBtl_EvtFlags bit 6 (MusicCueDispatch reads it): keeps the music, probably
!BattleCD_EvtNoBit6       = $BF   ; clears it
!BattleCD_CA25Unk02       = 2     ; !BattleFx_CeSetBase at the end of the opening wipe
!BattleCD_CA25Unk08       = 8     ; ... at the last battle-end step
!BattleCD_CA25Unk0C       = $0C   ; ... at the start of the closing wipe
!BattleCD_CA25Unk0E       = $0E   ; ... after the closing wipe
!BattleCD_ReentryScrollStep = 2   ; ReentryVectors offset of vector [1] (ScrollStepAccum)
!BattleCD_ReentryAudioFade = $0B  ; ReentryVectors offset of vector [4] (AudioFadeDispatch)
!BattleCD_BgSaveBytes     = $0F80 ; bytes of !Battle_BgTileSave
!BattleCD_BgTileVram      = $5000 ; VRAM word address they go back to
!BattleCD_WipeSteps       = 23    ; steps of a wipe
!BattleCD_WipeOpen        = $FF   ; !Battle_WipeMode: opening, first step
!BattleCD_WipeClose       = $80   ; !Battle_WipeMode: closing
!BattleCD_HdmaTableBytes  = $002D ; bytes per table of !Battle_HdmaTables
!BattleCD_HdmaTablesEnd   = $0195 ; nine of them
!BattleCD_ScrollPassBytes = $0010 ; four scroll entries (one pass of BattleCD_ScrollFill)
!BattleCD_ScrollFillEnd   = $80   ; 32 entries of 4 bytes
!BattleCD_AllHdma         = $FF   ; HDMAEN: all eight channels
!BattleCD_NmiWaitLine     = $40   ; the scanline BattleCD_NmiMain waits for (BattleCD_WaitScanline); why is not traced
!BattleCD_CDC9Period      = $0D   ; !BattleFx_GradStart's reload
!BattleCD_PalAnimBytes    = $0C   ; bytes per FieldAnimB record
!BattleCD_PalAnims8To11   = $0030 ; four FieldAnimB records (8-11)
!BattleCD_ShakeYRandSeed  = $40   ; A the y shake passes to BattleCD_RandByte
!BattleCD_ClearBit0       = $FE   ; AND mask clearing bit 0
!BattleCD_ColDataBlack    = $E0   ; COLDATA: all three channels, intensity 0
!BattleCD_FullBright      = $0F   ; INIDISP: full brightness, no forced blank
!BattleCD_ChannelBytes    = $10   ; bytes per script channel
!BattleCD_ChannelBlockBytes = $0020 ; bytes per block of !Battle_FxChannels (two channels)
!BattleCD_NoScript        = $FF   ; !Battle_FxScriptIds entry: none
!BattleCD_FxEnd87         = $0087 ; battle-end layer effect of BattleCD_LayerFx87
!BattleCD_FxEnd84         = $0084 ; battle-end layer effect of BattleCD_LayerFx84
!BattleCD_CE0EInit        = $80   ; !BattleFx_GradForce set by BattleCD_LayerFx84
!BattleCD_EndFxDelay      = $80   ; frames BattleCD_LayerFx84 waits before its effect
!BattleCD_PalRowOfs       = $30   ; byte offset of colour 24 in a palette buffer
!BattleCD_PalRowBytes     = $0010 ; colours 24-31
!BattleCD_CgadsubHalf     = $40   ; CGADSUB bit 6: half colour math
!BattleCD_FxRec2A21Ofs    = $20   ; record offset added with !Battle_Unk2A21 bit 0
!BattleCD_FxPlain86       = $86   ; layer effects that do not set the screen (BattleCD_LayerFxSetsScreen) ...
!BattleCD_FxPlainFirst    = $7B   ; ... and $7B-$7F
!BattleCD_FxPlainLast     = $7F
!BattleCD_FxByBattle      = $0088 ; layer effect replaced by $88-$8A by !Battle_UnkA017/A018
!BattleCD_NoPage          = $FFFF ; !Battle_LastPageSlot/Src after a load: matches no page
!BattleCD_CD04Init        = $1F   ; !Battle_UnkCD04 after a load
!BattleCD_FxLastSetOfs    = $0006 ; BattleCD_LoadLayerFx's fourth tile set (* 2)
!BattleCD_FxBlankOfsA     = $02E0 ; offset of the set's tiles $2E-$2F in !Battle_ActFrameBuf
!BattleCD_FxBlankOfsB     = $03E0 ; ... of tiles $3E-$3F
!BattleCD_FxBlankBytes    = $0020 ; two 2bpp tiles
!BattleCD_FxSetBytes      = $0400 ; bytes of a tile set / graphics part
!BattleCD_FxTilemapBytes  = $0800 ; bytes of the first tilemap upload
!BattleCD_FxTilemapVram   = $7C00 ; its VRAM word address (BG3's map)
!BattleCD_FxColoursA      = $32   ; byte offset of colour 25 (first colour set)
!BattleCD_FxColoursB      = $3A   ; byte offset of colour 29 (second colour set)
!BattleCD_FxFillStep      = $1000 ; BattleCD_FillFxTilemaps: distance between its three passes
!BattleCD_FxFillHalf      = $0800 ; bytes per half of a pass
!BattleCD_FxBlankEntry    = $00EE ; tilemap entry: tile $EE, attribute 0
!BattleCD_FxAttr          = $38   ; BattleCD_BuildFxTilemap's attribute: priority, palette 6
!BattleCD_FxAttrPal       = $04   ; the attribute's palette bit 0 (palette 7)
!BattleCD_FxBlockMask     = $3F   ; !Battle_FxRecord bits 0-5: the block count
!BattleCD_FxMapBitsEnd    = $0021 ; Y after the 32 bitmap bytes
!BattleCD_FxRingMask      = $001F ; !Battle_FxMapCount bits that wrap the cell pointer
!BattleCD_FxRingBytes     = $0020 ; bytes it moves back
!BattleCD_FxCellRowBits   = $38   ; cell bits 3-5: the tile row (* 32 tiles)
!BattleCD_FxCellFlips     = $C0   ; cell bits 6-7: the flips (as attribute bits 6-7)
!BattleCD_FxColumns       = $10   ; cells per row
!BattleCD_FxPageBytes     = $0200 ; bytes per tilemap page
!BattleCD_FxIdMask        = $7FFF ; BattleCD_LoadFxRecord's mask of X
!BattleCD_FxSetTiles      = $0040 ; tiles per layer-3 tile set
!BattleCD_FlipBits        = $0006 ; entry bits 14-15 (after >> 13): the flips * 2
!BattleCD_Tile2Bytes      = $0010 ; bytes of a 2bpp tile
!BattleCD_Tile4Bytes      = $0020 ; bytes of a 4bpp tile
!BattleCD_TileNumMask     = $1FFF ; entry bits 0-12: the tile
!BattleCD_Tile2bppFlag    = $2000 ; entry bit 13: a plain 2bpp source (else a third plane follows)
!BattleCD_GfxPartTiles    = $0020 ; tiles per graphics part
!BattleCD_ColourByteBits  = $18   ; tile number bits 3-4: the byte of !Battle_FxColourBits
!BattleCD_FxPeriodMask    = $0F   ; a script's first byte: the period
!BattleCD_FxNoPage        = $7F   ; script byte: a step with no page
!BattleCD_FxEnd           = $FF   ; script byte: the end
!BattleCD_WaitShort       = 16    ; frames of BattleCD_Wait16Frames

; ------------------------------------------------------------
; Bank $CD: the helpers $CD:3B5F-$CD:3FFF and the script opcodes ($CD:16B5 on)
; ------------------------------------------------------------
!BattleCD_Div16Bits       = $0010 ; quotient bits of BattleCD_Div16 (one pass each)
!BattleCD_ApuCmdPause     = $F5   ; APU command of BattleCD_PauseWait (sent as it is; argument $F5 on pausing, 0 on
                                  ; resuming: the music's pause, probably)
!BattleCD_DmaPieceLarge   = $1000 ; BattleCD_QueueVramDma's piece while !Battle_CgramPending is set
!BattleCD_DmaPieceSmall   = $0400 ; ... and otherwise
!BattleCD_ScrollWavesBg3Mode = 3   ; !Battle_LayerFxMode of layer 3's wave scroll (BattleCD_ScrollModeTable entry 3)
!BattleCD_FxWaveKeep      = $FF   ; script opcode $E7's operand that keeps !Battle_FxWaveOfs
!BattleCD_FxVarMask       = $7F   ; script opcode $D8's variable number (bit 7 = clear it)
!BattleCD_FxDriftPick     = $0B   ; script opcode $D7: operand bits that pick the work bytes
!BattleCD_FxDriftAdd      = $40   ; ... operand bit 6: add (else subtract)
!BattleCD_FxDriftMask     = $1F   ; ... the random steps' range (0-31)
!BattleCD_FxDivMax        = $FF   ; both bytes of the dividend $FFFF (script opcode $CD)
!BattleCD_ScreenXMin      = 8     ; BattleCD_ClampX's range
!BattleCD_ScreenXMax      = $F8
!BattleCD_ScreenYMin      = 8     ; BattleCD_ClampY's range
!BattleCD_ScreenYMax      = $D4
!BattleCD_99D2Mask        = $7F   ; !Battle_Unk99D2 without bit 7 (script opcode $CB)
!BattleCD_PaletteFlip     = $08   ; !Battler_Palette bit 3 (script opcode $C9 flips it)
!BattleCD_FxEnemyLine     = $6F   ; the line script opcodes $C7/$C8 measure the first enemy's y from
!BattleCD_FxWobbleAmpXY   = $20   ; script opcode $C6's swing of the x and y angles
!BattleCD_FxWobbleAmpZ    = $24   ; ... of the z angle
!BattleCD_FxCircleX       = $80   ; the centre of script opcode $C4's circles
!BattleCD_FxCircleY       = $87
!BattleCD_FxModel2        = $20   ; !BattleCD_FxModelOfs of model 2 (script opcode $BE)
!BattleCD_FxEdgeMax       = $FF   ; the band's right edge at most (script opcodes $B5/$B6)
!BattleCD_FxWinLastWord   = $00FE ; offset of !Battle_FxWinLines' last word before the middle
!BattleCD_FxWaveAmpX      = $32   ; script opcode $B3: the x swing
!BattleCD_FxWaveAmpY      = $0F   ; ... the y swing
!BattleCD_FxWaveBaseY     = $20   ; ... added to the y
!BattleCD_FxWaveTableEnd  = $0350 ; 106 entries of 8 bytes
!BattleCD_HighByteMask    = $FF00 ; keeps a 16-bit A's high byte
!BattleCD_FxScaleWhole    = $FF   ; !Battle_FxObjScale: (nearly) unscaled
!BattleCD_FxNear          = 4     ; BattleCD_FxOpTriCentre: midpoints closer than this are moved apart by it
!BattleCD_FxNearNeg       = $FC   ; ... -4 as a byte
!BattleCD_FxWaveFrameMask = $1F   ; script opcode $8F's first operand: the frame mask of the phase step
!BattleCD_FxWaveSpeedMask = $7F   ; ... its third operand without bit 7 (64 entries)
!BattleCD_FxSignByte      = $FF   ; the high byte of a negative byte widened to a word
!BattleCD_ScrollWavesMode = 2     ; !Battle_LayerFxMode of the wave scroll (BattleCD_ScrollModeTable entry 2)
!BattleCD_FxObjBytes      = $002A ; bytes of the two objects' fields (!Battle_FxObjCentreX on)
!BattleCD_FxPhaseA        = $C0   ; the flat ring's starting phases (script opcode $A2): a third of a turn apart
!BattleCD_FxPhaseB        = $15
!BattleCD_FxPhaseC        = $6A
!BattleCD_FxPalAnimPick   = $07   ; script opcode $8E: the record bits of its sixth byte
!BattleCD_FxPalAnimStep   = $F8   ; ... the bits that go to .Unk3

endif
