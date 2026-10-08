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
!BattleSys_ServiceUnk0    = 0     ; $C10045 service run first by BattleSys_Main ($C1:0023; not analysed)
!BattleSys_ServiceUpkeep  = 3     ; ... BattleSys_UpkeepTwoFrames
!BattleSys_ServiceUnk6    = 6     ; ... $C1:006D, run by the debug win; not analysed
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

endif
