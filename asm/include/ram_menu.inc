; ============================================================
; ram_menu.inc — Named WRAM / direct-page locations used by bank $C2
; (the menu/scene bank entered through BankC2_Entry0000/8000/8004).
;
; Why a file of its own: bank $C2 runs with its own direct page
; (DP=$0000, set by its entry code) and DB=$7E, and gives low WRAM a
; layout of its own: $0A00, $0D00 and the direct page mean other things
; here than in the field engine (ram_engine.inc: Obj_ScreenX at $0A00,
; Obj_VramTile at $0D00, the field direct page at $0100). Where both
; banks really share a location (the party list at $2980, the play-time
; bytes at $0400), the name here says so.
;
; Names start with `Menu` so they never collide with the engine and
; battle sets (asar lets a later define silently replace an earlier
; one). Conventions as ram_engine.inc: `!Name = $addr`, one comment per
; name with width, meaning and how it was inferred. Direct-page names
; are full addresses (DP=$0000 makes them the same); absolute ones are
; the bank-$7E offset, read with DB=$7E.
; ============================================================
!ram_menu_inc ?= 0
if !ram_menu_inc == 0
!ram_menu_inc = 1

; --- New-game data (Menu_InitNewGameData / Menu_ClearConfigAndFlags) ---
!Menu_FlagBlock7F = $7F0000              ; 512 B at $7F:0000-$01FF, zeroed for a new game. Its first byte
                                         ; is Eng_Unk7F0000 (gates Field_FadeToBankC2Mode5); probably the
                                         ; story/event flags (unverified)
!Menu_DataInitDone = $7F0061             ; 8-bit; the call at $C2:8048 runs Menu_InitNewGameData only while it
                                         ; is 0 (and the mode is 0), then sets it to 1; $C2:8D7E clears it
                                         ; and $C2:E65D sets it to 1 after their own unguarded calls;
                                         ; $C2:8D85 sets it to 2 when a slot check returns 0 (after JSR $C2:95BB)
!Menu_PlayTime = $0400                   ; 6 B: play-time counter, one byte per digit group, lowest first
                                         ; (Menu_TickPlayTime: frames, then up to the limits in
                                         ; Menu_PlayTimeLimits); the field engine calls the first byte
                                         ; Eng_Unk0400
!Menu_PlayTimeMaxed = $0406              ; 8-bit; set to 1 by Menu_TickPlayTime when the top group wraps
!Menu_PlayTimePaused = $0407             ; 8-bit; non-zero stops Menu_TickPlayTime (the field engine's
                                         ; Field_FadeBusy, $FF while it pauses); BankC2_MenuEntry clears it
!Menu_Unk0408 = $0408                    ; 9 B; a second copy of the default button map (and the byte
                                         ; after it), Menu_ClearConfigAndFlags; not read in matched code
!Menu_Unk2400 = $2400                    ; 512 B $2400-$25FF zeroed by Menu_InitNewGameData; use unknown
!Menu_CharRecords = $2600                ; character records, $50 B each (stride of the loops at $C2:8142
                                         ; and $C2:82F6); Menu_InitNewGameData fills $2600-$287F from
                                         ; MenuRom_CharRecordInit
!Menu_PartyOrder = $2980                 ; 9 B: character id per party position, $80 = empty; the first 3
                                         ; are the active party (the field's Party_Members), inferred
                                         ; from Menu_BuildPartyLists
!Menu_Config = $2990                     ; 32 B $2990-$29AF zeroed by Menu_ClearConfigAndFlags; the first
                                         ; 12 get MenuRom_DefaultConfig
!Menu_ButtonMap = $2993                  ; 8 B: the JOY1 mask behind each mapped button bit (Menu_MapButtons)
!Menu_Config01 = $7E2991                 ; 8-bit; Menu_Config+1 as a long address; bits 0-2 pick the
                                         ; colour set Pal_LoadUnkRow0 loads and Field_UploadUnk1F00's graphics set
!Menu_Config1E = $7E29AE                 ; 8-bit; Menu_Config+$1E as a long address; C2Scene_LoadScene copies it
                                         ; to C2Scene_Unk02AE; use unknown
!Menu_Unk29AF = $29AF                    ; 16-bit; set to $0080 by Menu_InitNewGameData; use unknown
!Menu_Unk2C53 = $2C53                    ; 3 B $2C53-$2C55 zeroed by Menu_InitNewGameData (two 16-bit STZs)
!Menu_Unk2C7C = $2C7C                    ; 30 B $2C7C-$2C99 zeroed by Menu_InitNewGameData

; --- Joypad (Menu_PollPad / Menu_MapButtons), dp $F0-$FF with DP=$0000 ---
; Pad_Pressed ($00F0) and Pad_Unk00F6-$00F9 are named in ram_engine.inc,
; where the field reads them.
!Menu_PadHeld = $00F2                    ; 16-bit buttons held now (layout as Pad_Pressed)
!Menu_PadRepeat = $00F4                  ; 16-bit; newly pressed, plus the held buttons each time
                                         ; Menu_PadRepeatTimer runs out (auto-repeat)
!Menu_PadRepeatMapped = $00FA            ; 8-bit Menu_PadRepeat through the button map (Menu_MapButtons)
!Menu_PadRepeatDpad = $00FB              ; 8-bit copy of Menu_PadRepeat's high byte (the D-pad)
!Menu_PadRepeatDelay = $00FC             ; 8-bit; frames before (and between) auto-repeats: what
                                         ; Menu_PadRepeatTimer reloads from (Menu_NmiPad sets it from
                                         ; Menu_RepeatDelays)
!Menu_PadRepeatTimer = $00FD             ; 8-bit auto-repeat countdown
!Menu_PadPrevHeld = $00FE                ; 16-bit Menu_PadHeld of the frame before

; ==== Scene mode (BankC2_Entry0000) direct page ====
; BankC2_SceneBoot sets DP=$0000; C2Scene_ClearDp zeroes $00-$EF and
; C2Scene_NmiHandler copies the shadows below to the PPU every frame (that
; copy is how each one was identified). Names are dp offsets.
!C2Scene_DpClearStart = $00              ; first byte C2Scene_ClearDp zeroes ($00-$EF)
!C2Scene_InidispShadow = $1C             ; 8-bit; ORed with C2Scene_Brightness into INIDISP each NMI
                                         ; (C2Scene_ClearDp sets FORCED_BLANK)
!C2Scene_Brightness = $1D                ; 8-bit; see C2Scene_InidispShadow
!C2Scene_BgModeShadow = $1E              ; 8-bit BGMODE
!C2Scene_MosaicShadow = $1F              ; 8-bit MOSAIC
!C2Scene_Bg1HScroll = $20                ; 16-bit BG1HOFS
!C2Scene_Bg2HScroll = $22                ; 16-bit BG2HOFS
!C2Scene_Bg3HScroll = $24                ; 16-bit BG3HOFS
!C2Scene_Bg1VScroll = $26                ; 16-bit BG1VOFS
!C2Scene_Bg2VScroll = $28                ; 16-bit BG2VOFS
!C2Scene_Bg3VScroll = $2A                ; 16-bit BG3VOFS
!C2Scene_M7A = $2C                       ; 16-bit M7A (C2Scene_ClearDp: $0100 = 1.0)
!C2Scene_M7B = $2E                       ; 16-bit M7B
!C2Scene_M7C = $30                       ; 16-bit M7C
!C2Scene_M7D = $32                       ; 16-bit M7D (C2Scene_ClearDp: $0100 = 1.0)
!C2Scene_M7X = $34                       ; 16-bit M7X
!C2Scene_M7Y = $36                       ; 16-bit M7Y
!C2Scene_W12SelShadow = $38              ; 8-bit W12SEL
!C2Scene_W34SelShadow = $39              ; 8-bit W34SEL
!C2Scene_WObjSelShadow = $3A             ; 8-bit WOBJSEL
!C2Scene_WH0Shadow = $3B                 ; 8-bit WH0 (C2Scene_ClearDp: 1)
!C2Scene_WH1Shadow = $3C                 ; 8-bit WH1
!C2Scene_WH2Shadow = $3D                 ; 8-bit WH2 (C2Scene_ClearDp: 1)
!C2Scene_WH3Shadow = $3E                 ; 8-bit WH3
!C2Scene_WBgLogShadow = $3F              ; 8-bit WBGLOG
!C2Scene_WObjLogShadow = $40             ; 8-bit WOBJLOG
!C2Scene_TmShadow = $41                  ; 8-bit TM
!C2Scene_TsShadow = $42                  ; 8-bit TS
!C2Scene_TmwShadow = $43                 ; 8-bit TMW
!C2Scene_TswShadow = $44                 ; 8-bit TSW
!C2Scene_CgwselShadow = $45              ; 8-bit CGWSEL
!C2Scene_CgadsubShadow = $46             ; 8-bit CGADSUB
!C2Scene_FixedBlue = $47                 ; 8-bit fixed-color blue intensity (COLDATA with the blue bit)
!C2Scene_FixedRed = $48                  ; 8-bit fixed-color red intensity
!C2Scene_FixedGreen = $49                ; 8-bit fixed-color green intensity
!C2Scene_HdmaenShadow = $4A              ; 8-bit HDMAEN, written at the end of the NMI register copy
!C2Scene_FrameCounter = $4B              ; 8-bit; +1 every NMI, even when the update is skipped
                                         ; (C2Scene_WaitFrame waits for it to change)
!C2Scene_NmiFlags = $4C                  ; 8-bit; bit 0: run the NMI update (set again at its end),
                                         ; bit 1: upload C2Scene_PaletteBuf (one-shot); C2Scene_Main sets
                                         ; both ($C2:23C6)
!C2Scene_OamNext = $4D                   ; 8-bit; next OAM slot C2Scene_SprDrawNode fills (it uses the
                                         ; low 7 bits for the low table); the NMI zeroes it after
                                         ; C2Scene_SprResetLists with a 16-bit STZ (M=0 there), which
                                         ; zeroes C2Scene_TaskCur's low byte too
!C2Scene_TaskCur = $4E                   ; 16-bit address of the C2Scene_Task record being run
                                         ; (C2Scene_TaskRunAll); C2Scene_TaskSpawn copies a new task's
                                         ; parameters from it
!C2Scene_TaskHandler = $50               ; 16-bit; the running task's .Handler, the target of
                                         ; C2Scene_TaskCallHandler's JMP (abs)
!C2Scene_SprFramePtr = $55               ; 24-bit pointer to a sprite frame (a count byte, then 4-byte
                                         ; pieces): input of C2Scene_SprAdd, and the walk pointer of
                                         ; C2Scene_SprDrawNode
!C2Anim_Ptr = $52                        ; 24-bit pointer to the current op of the running task's animation
                                         ; script (C2Anim_Run; copied from and back to .AnimPtr/.AnimBank)
!C2Script_Ptr = $58                      ; 24-bit pointer to the current op of the running task's script
                                         ; (C2Scene_TaskRunScript; .ScriptPtr/.ScriptBank)
!C2Script_CallVec = $5B                  ; 24-bit target of script ops $34 (C2Script_CallNear: JMP (abs),
                                         ; bank $C2) and $4E (C2Script_CallLong: JML [abs])
!C2Scene_VramQLock = $5E                 ; 8-bit; non-zero: C2Scene_VramQFlush does nothing
!C2Scene_VramQEnd = $5F                  ; 8-bit byte offset past the last C2Scene_VramQ entry (0 = empty)
!C2Scene_BgTileX = $E3                   ; 2 words, X in tiles (C2Scene_SetStartScroll sets both alike);
                                         ; word 0 for BG1, word 1 for BG2: C2Scene_DrawBgLayer stores 8x
                                         ; them into the scroll shadows and draws the map from them
!C2Scene_BgTileY = $E7                   ; 2 words, Y in tiles (as C2Scene_BgTileX)
!C2Scene_VramQBufPtr = $E0               ; 24-bit; reset to C2Scene_VramQBuf after each flush (probably
                                         ; where the next queued data is written; unverified)
                                         ; C2Scene_DrawBgLayer builds each tilemap column at this address
                                         ; (DB=$7E) and DMAs it from there to VRAM
!C2Scene_HeaderPtr = $ED                 ; 24-bit pointer to this scene's header in bank $C6 (set by
                                         ; C2Scene_GetHeaderPtr from C2SceneRom_HeaderTable); each header
                                         ; byte picks a pack for one C2Scene_Load* routine
                                         ; (C2Scene_Hdr* offsets in constants_menu.inc)

; One VRAM DMA request, 8 B, at dp $60 + 8 * n (C2Scene_VramQFlush).
struct C2Scene_VramQ $0060
.Src:   skip 2          ; A-bus source address
.Bank:  skip 1          ; A-bus source bank
.Dest:  skip 2          ; VRAM word address
.Size:  skip 2          ; byte count
.Vmain: skip 1          ; VMAIN value for the transfer
endstruct align 8

; Scratch: the scene code uses dp $00-$1B as temporaries (the PPU shadows
; start at $1C). Each routine gives the slots it uses an alias next to its
; header.
!C2Tmp_00 = $00                          ; 1-2 B scratch
!C2Tmp_01 = $01                          ; 1 B scratch
!C2Tmp_02 = $02                          ; 1-2 B scratch
!C2Tmp_03 = $03                          ; 1-2 B scratch
!C2Tmp_04 = $04                          ; 1-2 B scratch
!C2Tmp_05 = $05                          ; 1 B scratch
!C2Tmp_06 = $06                          ; 1-2 B scratch
!C2Tmp_07 = $07                          ; 1 B scratch
!C2Tmp_08 = $08                          ; 1-2 B scratch
!C2Tmp_09 = $09                          ; 1-2 B scratch
!C2Tmp_0A = $0A                          ; 1-2 B scratch
!C2Tmp_0B = $0B                          ; 1 B scratch
!C2Tmp_0C = $0C                          ; 1-2 B scratch
!C2Tmp_0E = $0E                          ; 1-2 B scratch
!C2Tmp_10 = $10                          ; 1-2 B scratch
!C2Tmp_13 = $13                          ; 1-2 B scratch
!C2Tmp_12 = $12                          ; 1-2 B scratch
!C2Tmp_14 = $14                          ; 1-2 B scratch
!C2Tmp_16 = $16                          ; 1 B scratch
!C2Tmp_18 = $18                          ; 1-2 B scratch
!C2Tmp_19 = $19                          ; 1-3 B scratch
!C2Tmp_1A = $1A                          ; 1-2 B scratch
!C2Tmp_1B = $1B                          ; 1 B scratch

; ==== Text window (TextWin_Init / TextWin_Step) ====
; A block at $0200 that both run on as their direct page; names are dp
; offsets (DP=!TextWin_Dp). The callers fill the first part (the field at
; $C0:20F4-$C0:2121, absolute $020C-$0214).
!TextWin_Dp = $0200                      ; the block's address, loaded into D
!TextWin_StrIndex = $0C                  ; 8-bit string number: index into TextWin_StrTable
!TextWin_StrTable = $0D                  ; 24-bit pointer to a table of 16-bit string addresses (in the
                                         ; table's bank)
!TextWin_GfxBuf = $10                    ; 24-bit output buffer (the field passes $7E:F000): the glyph
                                         ; pixels TextWin_DrawGlyph ORs in (TextWin_TileOfs2bpp/4bpp layout)
!TextWin_StepCount = $13                 ; 8-bit; the field sets 1 before each TextWin_Step; state 0
                                         ; decrements it per glyph and sets status $10 at 0 (probably
                                         ; characters per step)
!TextWin_Mode = $14                      ; 8-bit; the field passes 0. Bit 7 or the value TextWin_ModeUnk2:
                                         ; pen X starts at 0; low nibble 0 or not picks TextWin_Blit2bpp
                                         ; or TextWin_Blit4bpp (TextWin_DrawGlyph)
!TextWin_Status = $15                    ; 8-bit; TextWin_CheckStatus dispatches on it ($00-$20): 0
                                         ; = idle; TextWin_Init sets TextWin_StatusStart; the field
                                         ; reads it after each step
!TextWin_Unk17 = $17                     ; 8-bit; zeroed with each pen reset; +1 per glyph (TextWin_DrawGlyph)
!TextWin_State = $30                     ; 8-bit index into TextWin_StateTable
!TextWin_TextPtr = $31                   ; 24-bit pointer to the next byte of the string
!TextWin_PenX = $34                      ; 8-bit pen X in pixels (TextWin_DrawGlyph uses bits 0-2 as the
                                         ; shift within a tile and bits 3-7 as the tile, and adds the width)
!TextWin_Unk3D = $3D                     ; 24-bit; TextWin_Init sets it to $00:0200 (= TextWin_Dp). Control
                                         ; codes $0D-$0F and $11-$12 read their value from here and step it
                                         ; on (the argument pointer)
!TextWin_Code3Arg = $16                  ; 8-bit; the byte after control code $03 (TextWin_CodeStatusArg);
                                         ; use not traced
!TextWin_Glyph = $35                     ; 16-bit glyph code for TextWin_DrawGlyph ($00A0-$00FF, or $01xx/$02xx
                                         ; after the prefix codes $01/$02)
!TextWin_SubPtr = $37                    ; 24-bit pointer into the sub-string states 1-3 read
!TextWin_SubLeft = $3A                   ; 8-bit bytes (glyphs) of the sub-string still to draw
!TextWin_DictCode = $3B                  ; 8-bit the last dictionary code (TextWin_State0, code $12); not read
                                         ; in the decoder
!TextWin_Digits = $40                    ; 8 B the digits of a number for states 2 (0-9) and 3 (glyphs),
                                         ; read through TextWin_SubPtr = $00:0240
!TextWin_DecDigits = $60                 ; 8 B decimal digits from TextWin_Dec8/16/24 (most significant first)
!TextWin_HexIn = $60                     ; 8-bit the byte TextWin_HexByte prints (written as a word)
!TextWin_NumValue = $68                  ; 24-bit the value codes $0D-$0F read (1, 2 or 3 bytes)
!TextWin_HexPos = $6A                    ; 16-bit TextWin_HexByte's write offset into TextWin_Digits
; TextWin_DrawGlyph's work bytes (they overlap the number buffers above,
; which no glyph draw needs at the same time):
!TextWin_GlyphRow = $60                  ; 16-bit glyph byte 0-23 being drawn (index into both font tables)
!TextWin_GlyphLow = $62                  ; 8-bit copy of TextWin_Glyph's low byte: bit 0 picks the nibble
!TextWin_GlyphSpill = $63                ; 8-bit (written as a word): the bits shifted out on the left at
                                         ; pen shifts 5-7
!TextWin_RowCount = $68                  ; 8-bit byte pairs still to draw in the current part
!TextWin_PenShift = $6A                  ; 8-bit (written as a word) TextWin_PenX AND 7: pixels into the tile
!TextWin_GlyphX8 = $6C                   ; 16-bit glyph * 8 (on the way to * 24)
!TextWin_PenTile2 = $6E                  ; 16-bit (TextWin_PenX AND $F8) / 4: the tile * 2, index into the
                                         ; tile offset tables
!TextWin_OutPtr = $73                    ; 24-bit: TextWin_GfxBuf + 8, then + 1 per glyph byte
!TextWin_FontPtr = $76                   ; 24-bit: the glyph's 24 bytes in TextWinRom_Font
!TextWin_FontNibPtr = $79                ; 24-bit: its pair's 24 bytes in TextWinRom_FontRight
; The decimal converters' work bytes:
!TextWin_DivQuot = $65                   ; TextWin_DivBits: the quotient digit (8- or 16-bit)
!TextWin_DivSub = $6A                    ; TextWin_DivBits: the shifted divisor (8- or 16-bit)
!TextWin_Div24Quot = $6B                 ; 8-bit TextWin_Div24Bits quotient digit
!TextWin_Div24Sub = $6C                  ; 24-bit TextWin_Div24Bits shifted divisor
!TextWin_NumHex = $A1                    ; 8-bit; non-zero: codes $0D/$0E print in hexadecimal (2 or 4
                                         ; digits); who sets it is not traced
!TextWin_CharNames = $7E2C23             ; 6-byte character names (TextWin_CharNamePtrs points at the first 7;
                                         ; code $20 prints the 8th, at $7E:2C4D); read up to 5 bytes or a 0

; --- Scene mode absolute RAM ---
!C2Scene_Unk0B20 = $0B20                 ; 16 B $0B20-$0B2F zeroed by C2Scene_ClearPalette (right after
                                         ; C2Scene_PaletteBuf): one byte per 16-color palette, the
                                         ; number of palette tasks working on it (C2Scene_TaskUnk1DD4
                                         ; and C2Scene_TaskPalFade +1 at the start, -1 at the end; a
                                         ; fade stops when it is not 1)
!C2Scene_TaskRecords = $0B30             ; 64 C2Scene_Task records, $0B30-$1B2F (C2Scene_TaskRunAll walks
                                         ; them all; C2Scene_TaskClearAll frees them all)
!C2Scene_TaskRecordsEnd = $1B30          ; first address past the records
!C2Scene_Unk1B30 = $1B30                 ; 8-bit; zeroed by C2Scene_ClearUnk1B30; C2Scene_Random's index
                                         ; into RandomTable (one up per call)
!C2Scene_Unk1B31 = $1B31                 ; 8-bit; zeroed by C2Scene_ClearUnk1B30; use unknown
!C2Scene_Flag0Copy = $1BA6               ; 8-bit copy of Eng_Unk7F0000 (C2Scene_SaveFlagTail)
!C2Scene_FlagTailCopy = $1BA7            ; 16 B copy of $7F:01F0-$01FF, the end of Menu_FlagBlock7F
                                         ; (C2Scene_SaveFlagTail; C2Scene_RestoreFlagTail writes it back)
!C2Scene_StartX = $0283                  ; 16-bit; Loc_EntryX * 8 (C2Scene_SetStartPos): probably pixels
!C2Scene_StartY = $0285                  ; 16-bit; Loc_EntryY * 8
!C2Scene_SoundCmdState = $1BEC           ; 8-bit: 0 = nothing to send; 1 = a command waits in the
                                         ; driver block $1E00-$1E03 (set by C2Scene_QueueSoundCmd,
                                         ; which copies it from C2Scene_SoundCmdBuf);
                                         ; C2Scene_SoundCmdSending while Audio_DriverCommand runs.
                                         ; C2Scene_WaitFrames and C2Scene_MainLoop send it, once per frame
!C2Scene_SoundCmdBuf = $1BE8            ; 4 B: the next sound command and its 3 argument bytes, copied to
                                         ; Audio_CmdId-Audio_CmdArg2 by C2Scene_QueueSoundCmd
!C2Scene_SoundCmdPrio = $1BED            ; 8-bit; the caller's rank for C2Scene_SoundCmdBuf (every matched
                                         ; caller passes 0); a command is queued only when this is <=
                                         ; C2Scene_SoundCmdPendPrio (probably lower = more important)
!C2Scene_SoundCmdPendPrio = $1BEE        ; 8-bit C2Scene_SoundCmdPrio of the command that is queued
!C2Scene_Unk1BF6 = $1BF6                 ; 8-bit; zeroed by C2Scene_Main. Bit 0 (C2Scene_FadeInBusy): a
                                         ; fade-in task runs (C2Scene_TaskUnk2105); bit 1
                                         ; (C2Scene_FadeOutBusy): a fade-out task runs
                                         ; (C2Scene_TaskUnk20A2)
!C2Scene_Mode = $027C                    ; 8-bit; selects C2Scene_MainLoop's handler (index into
                                         ; C2Scene_ModeTable); who sets it is not traced
!C2Scene_Unk027D = $027D                 ; 8-bit; zeroed by C2Scene_LoadScene (next to C2Scene_Mode); use unknown
!C2Scene_Unk0280 = $0280                 ; 3 B $0280-$0282 zeroed by C2Scene_LoadScene; use unknown
!C2Scene_Unk0294 = $0294                 ; 8-bit; C2Scene_LoadScene clears bit 2 (C2Scene_Unk0294Bit2).
                                         ; Object A's flags (C2Scene_ObjWatch): C2Scene_ObjActive,
                                         ; C2Scene_ObjBusy and the count C2Scene_ObjCountMask
!C2Scene_Unk02AE = $02AE                 ; 8-bit; C2Scene_LoadScene copies the byte at Menu_Config+$1E into it;
                                         ; use unknown
!C2Scene_Unk02B1 = $02B1                 ; 3 B $02B1-$02B3 zeroed by C2Scene_LoadScene; use unknown
!C2Scene_Unk1B32 = $1B32                 ; 3 words $1B32-$1B37 set to $FFFF by C2Scene_LoadScene; the first
                                         ; is the byte offset of the C2Scene_ListA entry C2Scene_Mode3
                                         ; acts on (who sets it is not matched)
!C2Scene_Unk1B43 = $1B43                 ; 8-bit; zeroed by C2Scene_Mode3 and C2Scene_TrigListAB before a
                                         ; ListD script; C2Scene_TrigWatchWait waits for it to be non-zero
                                         ; (probably set by the script when it ends; not traced)
!C2Scene_Unk1B45 = $1B45                 ; 16-bit; the address of the ListD script C2Scene_Mode3 started
                                         ; (also read by unmatched code); use unknown
!C2Scene_Unk027E = $027E                 ; 8-bit; non-zero keeps the zone task from changing the song
                                         ; (C2Scene_ZoneSoundWatch); use unknown
!C2Scene_Unk027F = $027F                 ; 8-bit; C2Scene_ObjWatch copies C2Scene_Unk027E here before each
                                         ; step (the state it last ran)
!C2Scene_Unk0281 = $0281                 ; 8-bit; C2Scene_TrigWatch copies its state C2Scene_Unk0280 here
                                         ; before each step
!C2Scene_TrigFlags = $0282               ; 8-bit (byte 3 of C2Scene_Unk0280): bit 0
                                         ; (C2Scene_TrigRecheck) makes C2Scene_TrigWatchCheck look the
                                         ; party's tile up in the lists; bit 1 (C2Scene_TrigKeep) keeps
                                         ; what it found. Who sets them is not traced
!C2Scene_ObjSel = $028F                  ; 8-bit; which object C2Scene_ObjWatch follows:
                                         ; C2Scene_ObjSelA, C2Scene_ObjSelB, or 0 (none)
!C2Scene_ObjAX = $0290                   ; 16-bit X of object A (the C2Scene_ObjABox test); same units
                                         ; as C2Scene_StartX (probably pixels)
!C2Scene_ObjAY = $0292                   ; 16-bit Y of object A
                                         ; (object A's flags are C2Scene_Unk0294)
!C2Scene_ObjBX = $029A                   ; 16-bit X of object B (the C2Scene_ObjBBox test)
!C2Scene_ObjBY = $029C                   ; 16-bit Y of object B
!C2Scene_ObjBFlags = $029E               ; 8-bit flags of object B, as C2Scene_Unk0294's for A
                                         ; (C2Scene_ObjActive, C2Scene_ObjBusy, C2Scene_ObjCountMask)
!C2Scene_ObjALoc = $029F                 ; 16-bit Loc_Id (bits 0-8) object A is at: C2Scene_ObjWatchIdle
                                         ; tests it only when this equals the current one
!C2Scene_TrigFound = $1B44               ; 8-bit C2Scene_TrigDispatch's mask of the lists with an entry at
                                         ; the party's tile: bit 0 ListA, bit 1 ListC, bit 2 ListB
!C2Scene_Unk1B47 = $1B47                 ; 8-bit; C2Scene_GetListCUnk03 copies a ListC byte here; use not
                                         ; traced
!C2Scene_ZoneSounds = $1B9B              ; bytes indexed by a sound zone (0-15): the argument sent with
                                         ; C2Scene_SoundCmd10 for it (probably a song). Who fills it is not found
!C2Scene_SoundZone = $EB                 ; 8-bit dp: the sound zone C2Scene_ZoneSoundWatch last looked up
                                         ; (C2Scene_ZoneNone: none)
!C2Scene_ListACount = $1B38              ; 8-bit entry count of C2Scene_ListA (C2Scene_LoadLists)
!C2Scene_ListBCount = $1B39              ; 8-bit entry count of C2Scene_ListB
!C2Scene_ListCCount = $1B3A              ; 8-bit entry count of C2Scene_ListC (ListD's count is not kept)
!C2Scene_Unk1B58 = $1B58                 ; 8-bit; zeroed by C2Scene_LoadScene; C2Scene_GetListAUnk02 copies
                                         ; byte 2 of a ListA entry here; use unknown
!C2Scene_Unk1B59 = $1B59                 ; 8-bit; zeroed by C2Scene_LoadScene; use unknown
!C2Scene_Unk1BF7 = $1BF7                 ; 8-bit; zeroed by C2Scene_LoadScene and by C2Scene_LeaderInput
                                         ; when a step starts; use unknown
!C2Scene_ObjANextLoc = $02AF            ; 16-bit; zeroed by object A before scene mode C2Scene_ModeUnk8;
                                         ; the dial (C2Scene_Dial, mode 8) writes the Loc_Id it picked, or
                                         ; C2Scene_DialNoDest on a cancel; C2Scene_ObjAAfterMode8 waits for
                                         ; it: negative = none, else a Loc_Id the party leaves for
!C2Scene_ObjAAloft = $1BEF               ; 8-bit; 1 while object A is up (C2Scene_ObjARise to
                                         ; C2Scene_ObjAFly's landing), 0 otherwise (C2Scene_ObjAMarkShow)
!C2Scene_SpotX = $02A2                   ; 16-bit centre X of the spot C2Scene_ObjASpotWatch tests
                                         ; (who sets it is not traced)
!C2Scene_SpotY = $02A4                   ; 16-bit centre Y
!C2Scene_Unk7F00CC = $7F00CC             ; 8-bit in Menu_FlagBlock7F; bit 0 set by C2Scene_ObjAAfterMode8
                                         ; (C2Scene_ObjALoc1F2); meaning not traced
!C2Scene_Unk7F00CD = $7F00CD             ; 8-bit; zeroed by C2Scene_ObjAAfterMode8; meaning not traced
!C2Scene_ObjBAloft = $1BF0               ; 8-bit; 1 while object B is up (C2Scene_ObjBRise to its landing),
                                         ; 0 otherwise (C2Scene_ObjBMarkShow)
!C2Scene_ObjBMate1X = $02A6              ; 16-bit position of slot 1's mate of object B
!C2Scene_ObjBMate1Y = $02A8              ; (C2Scene_ObjBMateSavePos; its mark task follows it)
!C2Scene_ObjBMate2X = $02AA              ; and of slot 2's
!C2Scene_ObjBMate2Y = $02AC
!C2Scene_Unk1BF1 = $1BF1                 ; 16-bit; the leader's .XVel after each frame of a step or a
                                         ; C2Scene_LeaderBoard move (read by unmatched code)
!C2Scene_Unk1BF3 = $1BF3                 ; 16-bit; and its .YVel
!C2Scene_IdleFrames = $02B1              ; 3 B, C2Scene_Unk02B1, one per party slot: frames the leader
                                         ; (C2Scene_LeaderInput) or member (C2Scene_MemberFollow) has
                                         ; stood still (see C2Scene_IdleAnimAt)
!C2Scene_TrailPos = $1B5A                ; 8-bit byte offset of the next word of C2Scene_TrailX/Y
                                         ; (C2Scene_TrailPush; 0-$1E)
!C2Scene_TrailX = $1B5B                  ; 16 words: the leader's pixel X at the end of each of its
                                         ; last 16 steps (C2Scene_TrailFill, C2Scene_TrailPush); the other
                                         ; members walk to them (C2Scene_MemberTrailTarget,
                                         ; C2Scene_MemberRouteTrail)
!C2Scene_TrailY = $1B7B                  ; 16 words: the matching pixel Y
!C2Scene_SavedReturnId = $04FC          ; 16-bit; C2Script_GoToLocation copies Loc_ReturnId here; use not
                                         ; traced
!C2Scene_SavedReturnX = $04FE           ; 8-bit; its copy of Loc_ReturnX (written as a word, then
                                         ; C2Scene_SavedReturnY over the high byte)
!C2Scene_SavedReturnY = $04FF           ; 8-bit; its copy of Loc_ReturnY
!C2Scene_MemberWords = $1B3B             ; 3 words $1B3B-$1B40, one per party position
                                         ; (C2Script_SetMemberWord): non-zero, the address (bank $7F) of a
                                         ; script that position's task runs while C2Scene_TrigWatch waits
                                         ; (C2Scene_LeaderScriptStart, C2Scene_MemberScriptStart)
!C2Scene_Unk1B41 = $1B41                 ; 16-bit, right after them; C2Script_SetMemberWord's word for
                                         ; character 7; use not traced
!C2Scene_FlagTailByte1 = $1BA8           ; = C2Scene_FlagTailCopy+1, the copy of $7F:01F1; bit 7 picks the
                                         ; palette C2Scene_LoadLocExtraGfx loads for Loc_Id $01F1

; Parameter block of Decomp_ToWramVec (the same bytes as Battle_DecompSrc..
; in ram_battle.inc; the scene loaders fill it with DB=$00).
!Menu_DecompSrc = $0300                  ; 16-bit address of the packed data
!Menu_DecompSrcBank = $0302              ; 8-bit its bank
!Menu_DecompDest = $0303                 ; 16-bit WRAM destination address
!Menu_DecompDestBank = $0305             ; 8-bit its bank ($7E or $7F; $00 for low WRAM)

; Scene data unpacked into WRAM by the C2Scene_Load* routines (each name
; says what is inferred; "Unk" ones are only known by where they go).
!C2Scene_Metatiles = $7E3000             ; 8 B per 16x16 metatile: tile words top-left, top-right,
                                         ; bottom-left, bottom-right (C2Scene_DrawMetatile); BG1's set
                                         ; here, BG2's at $7E:3800 (C2Scene_LayerMetatiles)
!C2Scene_BgMaps = $7E4000                ; one byte (metatile number) per 16x16 cell, 96 x 64 cells per
                                         ; layer ($1800 B); BG1's map here, BG2's at $7E:5800
                                         ; (C2Scene_LayerMaps)
!C2Scene_Unk7000 = $7E7000               ; C2Scene_LoadUnk7000's pack; use unknown
!C2Scene_Unk7200 = $7E7200               ; C2Scene_LoadUnk7200's pack; use unknown
!C2Scene_Unk7F01ED = $7F01ED            ; 8-bit in Menu_FlagBlock7F; non-zero makes script op $3D
                                         ; (C2Script_SoundCmd10IfClear) skip its sound command; meaning not traced
!C2Scene_Unk7F01F4 = $7F01F4            ; 8-bit in Menu_FlagBlock7F; bits 1/3 (or bit 1 of the next byte) make
                                         ; C2Scene_Mode8 skip its reload and fade-in; meaning not traced
!C2Scene_Unk7F01F5 = $7F01F5            ; 8-bit, the next byte (see C2Scene_Unk7F01F4)
!C2Scene_ListA = $7E7E00                 ; 7-byte entries (C2Scene_LoadLists; C2Scene_ListAEntry); probably
                                         ; the scene's exits: C2Scene_Mode3 leaves for the location of
                                         ; entry C2Scene_Unk1B32 (byte offset)
!C2Scene_ListC = $7E8180                 ; 3-byte entries; use unknown
!C2Scene_ListB = $7E8300                 ; 3-byte entries; use unknown
!C2Scene_ListD = $7E8480                 ; 2-byte entries: addresses of scripts in bank $7F (the scene
                                         ; script's, C2Scene_ScriptBuf), started by C2Scene_Mode3
!C2Scene_Unk8600 = $7E8600               ; 4 B C2Scene_Unk5775 copies from C2Scene_Unk8600Init: C2Scene_LabelTask's
                                         ; animation script (shows the frame at C2Scene_Unk8604)
!C2Scene_Unk8604 = $7E8604               ; 25 B C2Scene_Unk5775 copies from C2Scene_Unk8604Init: the sprite
                                         ; frame of C2Scene_LabelTask (its first byte set to C2Scene_LabelPieces)
!C2Scene_HdmaArea = $7E8621              ; $800 B $7E:8621-$8E20 zeroed by C2Scene_ClearHdmaArea (holds
                                         ; C2Scene_HdmaValues and C2Scene_HdmaTable); C2Scene_LabelTask
                                         ; draws its text into the start of it
!C2Scene_UnkB800 = $7EB800               ; C2Scene_LoadUnkB800's pack; use unknown
!C2Scene_UnkC000 = $7EC000               ; C2Scene_LoadUnkC000's pack; use unknown
!C2Scene_UnkC600 = $7EC600               ; C2Scene_LoadUnkC600's pack; use unknown
!C2Scene_UnkC800 = $7EC800               ; C2Scene_LoadUnkC800's pack; use unknown
!C2Scene_ListPack = $7F0400              ; C2Scene_LoadLists unpacks the four lists' source here
!C2Scene_ScriptBuf = $7F0400             ; then C2Scene_LoadScript unpacks the scene's script over it;
                                         ; C2Scene_LoadScene starts a C2Scene_TaskRunScript task on it
!C2Scene_SaveDp = $7F3F00                ; C2Scene_SaveState's copy of dp $00-$EF
!C2Scene_SaveLowRam = $7F2800            ; its copy of $0700-$1DFF
!C2Scene_SaveSprNodes = $7F4000          ; its copy of $7E:B000-$B507 (C2Scene_SprNodes to the list heads)
!C2Scene_SaveBgMaps = $7F4600            ; its copy of $7E:4000-$6FFF (C2Scene_BgMaps and after)
!C2Scene_SaveUnk7200 = $7F7600           ; its copy of $7E:7200-$7DFF
!C2Scene_SaveLists = $7F8200             ; its copy of $7E:7E00-$85FF (C2Scene_ListA to ListD)
!C2Scene_PaletteStage = $7F8C00          ; 512 B: the scene's palettes are built here, DMAed to CGRAM and
                                         ; copied to C2Scene_PaletteBuf (C2Scene_LoadVram)
!C2Scene_ObjPal0 = $7F8D00               ; colors $80-$83 of C2Scene_PaletteStage (sprite palette 0, colors
                                         ; 0-3): C2Scene_LoadVram sets black and three grays
!C2Scene_PartyPalDest = $7F8D80          ; colors $C0, $D0, $E0 (sprite palettes 4-6, 32 B apart): the
                                         ; party members' palettes (C2Scene_LoadPalettes)
!C2Scene_PartyPalSrc = $7F8E00           ; the party palettes pack, 32 B per character
                                         ; (C2Scene_LoadPalettes)
!C2Scene_DecompBuf = $7F9000             ; staging buffer for graphics packs before their VRAM DMA
!C2Scene_PartyGfxSrcB = $7FAC00          ; inside the unpacked party graphics pack: $40 B per character
                                         ; here and at +$200 (C2Scene_CopyPartyGfxB)
!C2Scene_PartyGfx = $7FB000              ; $1000 B: the party's graphics, built by C2Scene_LoadPartyGfx
!C2Scene_PartyGfxB = $7FBC00             ; inside it: the second part of each member's graphics, $40 B per
                                         ; member here and at +$200 (C2Scene_CopyPartyGfxB)

; One 16x16 metatile (C2Scene_DrawMetatile), 8 B, at the layer's
; C2Scene_LayerMetatiles base + 8 * the map byte; each field a BG tilemap
; word.
struct C2Scene_Metatile $0000
.TopLeft:     skip 2
.TopRight:    skip 2
.BottomLeft:  skip 2
.BottomRight: skip 2
endstruct

!C2Scene_PaletteBuf = $0920              ; 512 B CGRAM shadow, uploaded by the NMI when C2Scene_NmiFlags
                                         ; bit 1 is set
!C2Scene_VramQBuf = $7EF000              ; see C2Scene_VramQBufPtr
!C2Scene_HdmaValues = $7E8A21            ; 10 words copied by every NMI update into C2Scene_HdmaTable
!C2Scene_HdmaValueA916 = $7EA916         ; word copied by every NMI update into C2Scene_HdmaTableA918

; Five 13-byte records at $7E:8A35; the NMI writes the word after the
; first and the fourth byte of each from C2Scene_HdmaValues. Probably HDMA
; tables (a line count, then a value), inferred only from that layout.
struct C2Scene_HdmaTable $7E8A35
.Count0: skip 1
.Value0: skip 2
.Count1: skip 1
.Value1: skip 2
         skip 7
endstruct align 13
!C2Scene_HdmaTableA918 = $7EA918         ; probably an HDMA table of 3-byte entries (count, word):
                                         ; the NMI writes the word of entries 0-3

;
; A scene task: one 64-byte record of C2Scene_TaskRecords, run once per
; frame by C2Scene_TaskRunAll (from the NMI) while .Handler is non-zero.
; Fields from .Params on are copied from the spawning task by
; C2Scene_TaskSpawn; what most of them hold depends on the handler.
struct C2Scene_Task $0000
.Handler:    skip 2     ; +$00 handler address in bank $C2 (0 = free slot)
.Unk02:      skip 1     ; +$02 zeroed by C2Scene_TaskSpawn
.Frames:     skip 2     ; +$03 +1 after each frame the handler returns C=0
.ScriptReturn:          ; +$05 = .Params: C2Script_Call keeps the return address here
.Params:     skip 2     ; +$05 first byte copied from the spawner
.ScriptPtr:  skip 2     ; +$07 C2Scene_TaskSpawnScript: 16-bit address of the script
.ScriptBank: skip 1     ; +$09 C2Scene_TaskSpawnScript: its bank
.ScriptWait:            ; +$0A = .Unk0A: frame countdown of the script's timed ops
.Unk0A:      skip 1     ; +$0A zeroed by C2Scene_TaskSpawnScript
.AnimPtr:    skip 2     ; +$0B 16-bit address of the C2Anim_Run script (C2Scene_SetAnim)
.AnimBank:   skip 1     ; +$0D its bank (C2Scene_SetAnim: C2SceneRom_AnimBank)
.AnimTimer:  skip 1     ; +$0E frame countdown of C2Anim_OpShowFrame / C2Anim_OpWait
.SprAttr:    skip 1     ; +$0F C2Scene_SprAdd: the new node's .Attr
.SprTile:    skip 2     ; +$10 C2Scene_SprAdd: the new node's .Tile
.XFrac:      skip 2     ; +$12 fraction of .SprX (16.16 fixed point, C2Scene_TaskMove)
.SprX:       skip 2     ; +$14 C2Scene_SprAdd: the new node's .X
.YFrac:      skip 2     ; +$16 fraction of .SprY
.SprY:       skip 2     ; +$18 C2Scene_SprAdd: the new node's .Y
.XVelFrac:   skip 2     ; +$1A X velocity per frame, fraction (C2Scene_TaskMove)
.XVel:       skip 2     ; +$1C X velocity, whole pixels (signed)
.YVelFrac:   skip 2     ; +$1E Y velocity, fraction
.YVel:       skip 2     ; +$20 Y velocity, whole pixels (signed)
             skip $10
.OpState:    skip 2     ; +$32 zeroed by C2Scene_TaskRunScript before each new op;
                        ; C2Script_MoveToX/Y set it on their first frame
.OpTarget:   skip 1     ; +$34 16-bit target of C2Script_MoveToX/Y (overlaps .Unk35);
                        ; C2Script_SpawnUnk1DD4 passes a byte here
.Unk35:      skip 2     ; +$35 C2Script_SpawnUnk1DD4 passes a word here
.Unk37:      skip 1     ; +$37 C2Script_SpawnUnk1DD4 passes a byte here
             skip 8
endstruct

; Other views of a C2Scene_Task record, for task handlers that use the
; record their own way (the fields after .Handler and .Unk02 differ).
; C2Scene_TaskUnk1CF5 (tile upload, started by script op $03): its state
; and what it reads from the spawning op.
struct C2Scene_UploadTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 (C2Scene_Task.Unk02, zeroed by C2Scene_TaskSpawn): 0 = start, 1 = upload
            skip 4
.OpPtr:     skip 3     ; +$07 = .ScriptPtr/.ScriptBank copied from the spawner: its op $03
            skip 1
.Src:       skip 2     ; +$0B source address of the next part
.SrcBank:   skip 1     ; +$0D its bank
.Dest:      skip 2     ; +$0E VRAM word address of the next part
            skip 2
.PerFrame:  skip 2     ; +$12 32-byte units uploaded per frame (0 in the op: all at once)
.Left:      skip 2     ; +$14 32-byte units still to upload
endstruct

; C2Scene_TaskUnk1DD4 (palette load, started by script op $04) and the
; palette fade task it starts: the op's arguments (left in the spawner's
; record, copied by C2Scene_TaskSpawn) and the fade's own fields. The
; fade's step arrays .RedStep-.BlueStep (+$10-$3F) overwrite the arguments at
; +$32-$37, so it copies them to +$07-$0D first.
struct C2Scene_PalTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 (C2Scene_Task.Unk02): the fade's state, 0-2
.Timer:     skip 2     ; +$03 = C2Scene_Task.Frames: frames since the last step (C2Scene_TaskRunAll counts)
.Steps:     skip 2     ; +$05 fade steps done (C2Scene_PalFadeSteps in all)
.Palette:   skip 2     ; +$07 the fade's copy of .ArgPalette
.Rate:      skip 1     ; +$09 the fade's copy of .ArgRate: frames per step
            skip 1
.Src:       skip 2     ; +$0B the fade's copy of .ArgSrc
.SrcBank:   skip 1     ; +$0D the fade's copy of .ArgBank
.Colors:    skip 2     ; +$0E address of the palette's 16 colors in C2Scene_PaletteBuf
.RedStep:   skip 16    ; +$10 per color: the red steps still to take (C2Scene_PalFadePlan)
.GreenStep: skip 16    ; +$20 the same for green
.BlueStep:  skip 2     ; +$30 the same for blue, 16 B (+$30-$3F, over the arguments below)
.ArgPalette: skip 2    ; +$32 palette number 0-15 (op $04 arg 4; high byte 0) = C2Scene_Task.OpState
.ArgRate:   skip 1     ; +$34 0: copy at once; else fade, one step per this many frames (arg 5)
.ArgSrc:    skip 2     ; +$35 address of the 16 new colors (args 1-2)
.ArgBank:   skip 1     ; +$37 their bank (arg 3)
            skip 8
endstruct

; C2Scene_TaskUnk20A2/2105/2194/21F8 (screen fades and mosaic, started by
; script ops $28-$2B): the state and what they read from the spawning op.
; One C2Scene_ListA entry (7 B). Only the fields C2Scene_Mode3 reads are named.
struct C2Scene_ListAEntry $7E7E00
.Flags:     skip 1     ; bit 7: C2Scene_ListEntryBit7 (script ops $44/$45); bits 0-6: tile X
                       ; (C2Scene_FindTrigEntries matches the word at +0 AND C2Scene_ListTileMask)
.TileY:     skip 1     ; bits 0-5: tile Y
.Unk02:     skip 1     ; C2Scene_GetListAUnk02 copies it to C2Scene_Unk1B58
.Loc:       skip 2     ; bits 0-8: a Loc_Id (C2Scene_ListANoLoc: none); the high byte / 2 is the entry
                       ; facing (as script op $05's argument)
.EntryX:    skip 1     ; Loc_EntryX; with no location, the C2Scene_ListD index
.EntryY:    skip 1     ; Loc_EntryY
endstruct

; One C2Scene_ListB entry (3 B): a tile trigger that starts a ListD script
; (C2Scene_TrigListB, C2Scene_GetListBScript).
struct C2Scene_ListBEntry $7E8300
.Flags:     skip 1     ; bit 7: C2Scene_ListEntryBit7 (the trigger is live); bits 0-6: tile X
.TileY:     skip 1     ; bits 0-5: tile Y
.Script:    skip 1     ; index of the C2Scene_ListD script it starts
endstruct

struct C2Scene_FxTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 (C2Scene_Task.Unk02, 0 from C2Scene_TaskSpawn)
.Timer:     skip 2     ; +$03 = C2Scene_Task.Frames: frames since the last step (only the
                       ; low byte is reset)
            skip 2
.OpPtr:     skip 3     ; +$07 = .ScriptPtr/.ScriptBank copied from the spawner: its op
.Rate:      skip 1     ; +$0A frames per step (op arg 1, or arg 2 for the mosaic)
            skip $35
endstruct

; The other party members' task (C2Scene_MemberTask; this view is
; C2Scene_FollowTask): +$22 and the fields
; from +$24 on differ from C2Scene_WalkTask's.
struct C2Scene_FollowTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 = C2Scene_Task.Unk02: the step within the current state
            skip $1F   ; +$03-$21: as C2Scene_Task
.ScanProp:  skip 1     ; +$22 C2Scene_ScanCol: the left tile's property nibble (scratch)
            skip 1
.Slot:      skip 1     ; +$24 the party position (C2Scene_Slot1/2) whose member this is, set by
                       ; whoever starts the task (not traced); read as a word in two places
            skip 1
.Unk26:     skip 1     ; +$26 as C2Scene_WalkTask.Unk26 (zeroed by C2Scene_MemberInit)
.PrevFacing: skip 1    ; +$27 .Facing (bits 0-1) before C2Scene_FaceVelocity's last change
.Facing:    skip 1     ; +$28 as C2Scene_WalkTask.Facing
.Route:     skip 1     ; +$29 C2Scene_RouteXFirst / C2Scene_RouteYFirst and the legs left
.TargetX:   skip 2     ; +$2A pixel X the member walks to
.TargetY:   skip 2     ; +$2C pixel Y
.DeltaX:    skip 2     ; +$2E .TargetX - .SprX (C2Scene_MemberDelta)
.DeltaY:    skip 2     ; +$30 .TargetY - .SprY
            skip $0E
endstruct

; The party leader's task (C2Scene_LeaderTask) and the walk helpers it
; calls: the fields after C2Scene_Task's motion words. The position
; (.SprX/.SprY) and velocity words are C2Scene_Task's own.
struct C2Scene_WalkTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 = C2Scene_Task.Unk02: the step within the current state; zeroed
                       ; by C2Scene_LeaderTask when either watcher's state has changed
            skip $1F   ; +$03-$21: as C2Scene_Task
.PropUL:    skip 1     ; +$22 C2Scene_GetTileProps: the property nibble of the 8x8 tile up
                       ; and left of the point (column - 1, row - 1)
.PropUR:    skip 1     ; +$23 up and right (column, row - 1)
.PropDL:    skip 1     ; +$24 down and left (column - 1, row)
.PropDR:    skip 1     ; +$25 down and right (column, row)
.Unk26:     skip 1     ; +$26 bit 0 picks the second walk animation of a facing
                       ; (C2Scene_SetWalkAnim); the leader's code only zeroes it
            skip 1
.Facing:    skip 1     ; +$28 bits 0-1: C2Scene_FacingUp/Down/Left/Right; bit 7:
                       ; C2Scene_WalkMoving
            skip 1
.TargetX:   skip 2     ; +$2A pixel X where the current step or move ends
.TargetY:   skip 2     ; +$2C pixel Y
            skip $12
endstruct

; Object A's task (C2Scene_ObjATask) and its mark task: the fields after
; C2Scene_Task's motion words (+$22-$25 and the targets as C2Scene_WalkTask).
struct C2Scene_ObjTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 = C2Scene_Task.Unk02: the state (C2Scene_ObjAStates)
            skip $1F   ; +$03-$21: as C2Scene_Task (.Frames counts a timed move)
.PropUL:    skip 1     ; +$22 C2Scene_GetTileProps' nibbles, as C2Scene_WalkTask; the scripts
.PropUR:    skip 1     ; also use +$22 as a loop count
.PropDL:    skip 1
.PropDR:    skip 1
.Duration:  skip 1     ; +$26 frames C2Scene_ObjARise / C2Scene_ObjALand move
.PrevFacing: skip 1    ; +$27 .Facing before the last change
.Facing:    skip 1     ; +$28 0-3 (C2Scene_FacingUp...)
            skip 1
.TargetX:   skip 2     ; +$2A where the current step ends (C2Scene_SetStepTarget)
.TargetY:   skip 2     ; +$2C
.PropBL:    skip 1     ; +$2E the nibble of the tile below .PropDL (C2Scene_ObjAGetProps)
.PropB:     skip 1     ; +$2F and of the tile below .PropDR
            skip $10
endstruct

; One node of the scene's sprite list (C2Scene_SprAdd, C2Scene_SprDrawNode),
; 16 B, at C2Scene_SprNodes + $10 * n. The list heads C2Scene_SprActiveHead
; and C2Scene_SprFreeHead are only .Prev and .Next.
struct C2Scene_SprNode $0000
.Prev:  skip 2          ; address of the previous node (or of the head)
.Next:  skip 2          ; address of the next node (or of the head)
.X:     skip 2          ; 16-bit screen (or, with C2Scene_SprAttrScroll, BG2) X
.Y:     skip 2          ; 16-bit Y; the active list is kept in falling .Y order
.Attr:  skip 1          ; C2Scene_SprAttr* flags; bits 1-5 become OAM attribute bits 1-5
                        ; (palette and priority)
.Tile:  skip 2          ; bits 0-13 added to each piece's tile word; bit 14
                        ; (C2Scene_SprTileLarge in the high byte) large sprites; bit 15
                        ; (C2Scene_SprTileBehind) appended at the end of the list
.Frame: skip 3          ; 24-bit pointer to the frame (see C2Scene_SprFramePtr)
        skip 2
endstruct

!C2Scene_SprNodes = $7EB000              ; 64 C2Scene_SprNode records, $7E:B000-$B3FF
!C2Scene_SprLinkInit = $7EB400           ; 64 x 4 B: each node's .Prev and .Next on a free list
                                         ; (built by C2Scene_SprInitLinks, copied into the nodes every
                                         ; frame by C2Scene_SprResetLists)
!C2Scene_SprActiveHead = $7EB500         ; 4 B .Prev/.Next: head of the list C2Scene_SprDrawList draws
!C2Scene_SprFreeHead = $7EB504           ; 4 B .Prev/.Next: head of the free nodes

; --- The map view (C2Scene_MapView, scene mode 6) ---
!C2Scene_TileColors = $7EAB25            ; $380 B: one colour (0-15) per BG tile, built by
                                         ; C2Scene_MapTileColors for the mode-7 picture
!C2Scene_MapMarkersOff = $1B48           ; 8-bit; zeroed by C2Scene_ScrMapViewMarkers, raised by
                                         ; C2Scene_ScrMapViewExit; non-zero ends the marker tasks
!C2Scene_MapGradTop = $7E8B56            ; 112 B: COLDATA values of the gradient's top half
                                         ; (C2Scene_MapViewGradient; inside C2Scene_HdmaArea)
!C2Scene_MapGradBottom = $7E8BC6         ; and of its bottom half (the first 112 of 1792 written)

struct C2Scene_ZoomTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 = C2Scene_Task.Unk02: C2Scene_MapZoomStates index
            skip $1F   ; +$03-$21: as C2Scene_Task
.Angle:     skip 2     ; +$22 rotation (Trig_Sin1024 units); zeroed and never changed here
.DivA:      skip 2     ; +$24 C2SceneRom_ZoomDivA entry: divisor of M7A/M7B (low byte used)
.DivB:      skip 2     ; +$26 C2SceneRom_ZoomDivB entry: divisor of M7C/M7D
.Step:      skip 2     ; +$28 byte offset into both tables (0-$3E)
            skip $16
endstruct

; --- The dial (C2Scene_Dial, scene mode 8) ---
!C2Scene_DialSel = $1BB7                 ; 8-bit; the marker the hand rests on (C2Scene_DialInit/Turn);
                                         ; the marker tasks show the one it names
!C2Scene_DialVerts = $1BB8               ; 6 B: the hand's three points, X then Y (C2Scene_DialDrawHand)
!C2Scene_DialEdgeActive = $1BC4          ; 3 words each, one per edge of the hand: non-zero while drawn
!C2Scene_DialEdgeSlope = $1BCA           ; signed X step per line, 8.8
!C2Scene_DialEdgeTop = $1BD0             ; top line in the high byte
!C2Scene_DialEdgeBottom = $1BD6          ; last line in the high byte
!C2Scene_DialEdgeX = $1BDC               ; X, 8.8
!C2Scene_DialEdgeLines = $1BE2           ; lines left - 1 (the low byte counts)
!C2Scene_DialFlags = $1BF5               ; 8-bit; buffer flags C2Scene_DialHandBuf/SwirlBuf/FlagBit2
!C2Scene_HandBufA = $7E8B56              ; the two hand buffers: WH0/WH1 per line (C2Scene_HdmaBufBytes)
!C2Scene_HandBufB = $7E8DF6
!C2Scene_SwirlCosA = $7E9176             ; the swirl's M7A/M7D values per line, buffer A
!C2Scene_SwirlCosB = $7E9416             ; and buffer B
!C2Scene_SwirlSinA = $7E9796             ; its M7B/M7C values, buffer A
!C2Scene_SwirlSinB = $7E9A36             ; and B

struct C2Scene_DialTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 = C2Scene_Task.Unk02: the state
            skip $11   ; +$03-$13
.Target:    skip 2     ; +$14 (= .SprX) the hand angle being turned to
            skip 2
.Pos:       skip 2     ; +$18 (= .SprY) the hand's angle now
            skip 6
.Vel:       skip 2     ; +$20 (= .YVel) hand angle step per frame (+/- C2Scene_DialTurnStep)
.Sel:       skip 1     ; +$22 marker 0-6 (also the marker tasks' own number)
            skip $1D
endstruct

struct C2Scene_SwirlTask $0000
            skip 2     ; +$00 .Handler
.State:     skip 1     ; +$02 = C2Scene_Task.Unk02
            skip $15
.Angle:     skip 2     ; +$18 angle of the next new line
            skip $26
endstruct

; --- The menu's NMI (Menu_Nmi): dp offsets from Menu_NmiDp ($0D00) ---
!Menu_NmiFrames = $00                    ; 8-bit; +1 every menu NMI
!Menu_FrameReady = $01                   ; 8-bit; bit 7 clear: the NMI runs the upload (Menu_Unk85D6) and
                                         ; sets it to Menu_FrameDone; the menu loop waits for non-zero
                                         ; ($C2:81CA)
!Menu_InidispShadow = $10                ; 8-bit; INIDISP after the NMI (0: forced blank)
!Menu_HdmaenShadow = $13                 ; 8-bit; HDMAEN after the upload (bit 7 masked off)
!Menu_RepeatFast = $18                   ; 8-bit; non-zero: Menu_NmiPad sets the repeat delay and timer
                                         ; to 1 once, then clears it
!Menu_RepeatStage = $19                  ; 8-bit index into Menu_RepeatDelays (1 after a release, 0
                                         ; after the first repeat); handled as a word by Menu_NmiPad
!Menu_NmiTimer = $76                     ; 8-bit; -1 per menu NMI down to 0 (who sets it not traced)
!Menu_Unk83 = $83                        ; 8-bit; Menu_NmiPad stores a held button mask here (use not
                                         ; traced)
!Menu_NmiSavedSp = $1DFE                 ; 16-bit S at the menu NMI's entry
!Menu_NmiStackTop = $1DFD                ; the menu NMI's own stack
!Menu_ButtonMap1Long = $7E2994          ; Menu_ButtonMap+1 as a long address (Menu_NmiPad)
!Menu_Joy2Copy = $041F                   ; 16-bit JOY2L/H copied by Menu_NmiPad each menu NMI

endif
