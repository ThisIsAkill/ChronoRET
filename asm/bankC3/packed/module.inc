; ============================================================
; Assembly setup and names for the unpacked bank $C3 module
; (asm/bankC3/packed/module.asm, assembled on its own by
; tools/c3pack.py onto a $857F-byte image of $7E:3000-$7E:B57E)
; ============================================================

arch 65816
norom

; The shared names (no bytes emitted), as asm/main.asm includes them.
incsrc "../../include/constants.inc"
incsrc "../../include/constants_engine.inc"
incsrc "../../include/ram_engine.inc"
incsrc "../../include/macros.inc"
incsrc "../../hardware.inc"

; Put the following bytes at a module address: the image's offset is
; the address - C3Mod_Code ($7E:3000), and labels take the address.
macro C3ModOrg(addr)
    base off
    org <addr>-!C3Mod_Code
    base <addr>
endmacro

; The ROM's module, unpacked by tools/c3pack.py: the bytes the source
; does not cover yet come from it. To find which bytes the source writes
; itself, the tool assembles a copy of asm/ in which this file is made of
; a fill byte (c3pack.source_bytes, tools/isolated.py). This and the
; incbin below are the only file reads the lint allows in the module.
!C3Mod_RomImage = "../../../build/c3pack/rom_module.bin"

; The ROM's bytes for module addresses start to end-1, at the current
; position.
macro C3ModRomBytes(start, end)
    incbin "!C3Mod_RomImage":<start>-!C3Mod_Code..<end>-!C3Mod_Code
endmacro

; ------------------------------------------------------------
; Kernel and engine entry points the module calls. The module is
; assembled apart from asm/main.asm, so their labels are not visible
; here: each is a define with the label's name, and
; tools/lint_c3module.py checks that it holds the label's address
; (rule KERNEL).
; ------------------------------------------------------------
!C3_ModuleFrame = $C308D0                ; bankC3.asm: one frame of the module (JSL)
!ReentryVectors = $C00000                ; bankC0.asm: entry [0], the warm restart into GameLoop_Main
!C3_RandomByte = $C302DD                 ; bankC3.asm: the kernel's random byte (JSL)
!Decomp_ToWram = $C30557                 ; bankC3.asm: the unpacker (JSL)
!C3_CopyFEto7E = $C3099C                 ; bankC3.asm: MVN from bank $FE to $7E (JSL)
!C3_CopyFEto7F = $C309A0                 ; bankC3.asm: the same to $7F (JSL)
!C3_RunScript = $C30AFF                  ; bankC3.asm: the script interpreter (JSL)
!Audio_DriverCommand = $C70004           ; bankC7.asm: sends the Audio_Cmd* block (JSL)
!C3_SprListSmall = $C30D0E              ; bankC3.asm: a list of small sprites (JSL)
!FdVec_FFF7 = $FDFFF7                    ; bankFD.asm: JMP PalAnim_TickAll (JSL)
!RandomTable = $C0FE00                   ; bankC0.asm: 256 random bytes
!BankC3_Entry000E = $C3000E              ; bankC3.asm: BRA/JMP to the wipe, WinFx_StepWipe (JSL)
!C3_BuildCopyCode = $C309E9              ; bankC3.asm: writes the bitmap-to-tiles copy code (JSL)

; ------------------------------------------------------------
; RAM the module uses (DB = $00 and DP = 0 unless a header says
; otherwise; the kernel's names, C3_*, are in ram_engine.inc)
; ------------------------------------------------------------
!C3_FadeStep = $038E                     ; 8-bit: frames per brightness step of the fade tasks
                                         ; (C3Mod_FadeInTask..); C3Mod_Init sets C3_FadeStepInit
!C3_FadeTimer = $038F                    ; 8-bit: frames left to the next step (reloaded from
                                         ; C3_FadeStep)
!C3_RandIndex = $039B                    ; 8-bit: C3Mod_TableRandom's index into RandomTable
!C3_OamRotate = $10                      ; 8-bit, dp: OAMADDL with priority rotation (the sprite
                                         ; given the first priority, probably); C3Mod_OamUploadTask
!C3_PaletteWork = $7E2000                ; 512 bytes: the palette the module builds, copied to
                                         ; C3_PaletteBuf by C3Mod_CommitPalette
!C3_DmaMode = $00F0                      ; C3Mod_DmaFromArgs / DmaUnpacked: DMAP7 (absolute)
!C3_DmaBbad = $00F2                      ; ... BBAD7
!C3_DmaAddr = $00F4                      ; ... 16-bit A-bus address (DmaFromArgs)
!C3_DmaBank = $00F6                      ; ... A-bus bank
!C3_DmaCount = $00F8                     ; ... 16-bit byte count
!C3_SprAttr = $0A                        ; 8-bit, dp: C3Mod_SprListMixed's attribute byte
!C3_StackSave = $00FE                    ; 16-bit: S while C3Mod_UnpackNibbles reads with PLA
!C3_Unk0366 = $0366                      ; 8-bit: C3Mod_Init clears it (use not traced)
!C3_PaletteBuf = $7E2200                 ; 512 bytes: the 256 CGRAM colours C3Mod_UploadPalette sends
!C3_RowCount = $F0                       ; dp offset (the caller's DP): C3Mod_DoubleRows /
                                         ; C3Mod_SpaceRows count their 64 source rows here
; The math routines' operands and results, dp offsets in the caller's
; direct page (0, $00F0-$00FF, or a script page: $0A00 at
; C3Mod_ViewOffsetTask's calls, the script's at C3Mod_BuildM7Tables'):
!C3Math_A = $F0                          ; 16-bit: multiplicand / dividend (Div32: low word)
!C3Math_B = $F2                          ; 16-bit: multiplier / divisor (Div32: dividend high word)
!C3Math_Lo = $F4                         ; 16-bit: product low word / quotient (Div32: divisor low)
!C3Math_Hi = $F6                         ; 16-bit: product high word (Div32: divisor high)
!C3Math_Q = $F8                          ; 32-bit: C3Mod_Div32's quotient ($F8-$FB);
                                         ; C3Mod_DivHighByte: the divisor - 1
!C3Math_R = $FC                          ; 32-bit: C3Mod_Div32's remainder ($FC-$FF)
!C3_SqrtRoot = $F0                       ; 16-bit: C3Mod_SquareRoot's result
!C3_TmpF0 = $F0                          ; 16-bit dp scratch of the caller's page (C3Mod_PadDelayTask,
                                         ; C3Mod_SteerTask, C3Mod_SkyNmiTask)
!C3_TmpF2 = $F2                          ; ... a second word (C3Mod_SteerTask)
!C3_RowsLeft = $F0                       ; dp (DP=0 at the calls): C3Mod_CopyTileBlock's row count
!C3_PadPrev = $04                        ; 16-bit, dp (DP=0): last frame's pad (C3Mod_PadDelayTask)
!C3_PadHeld = $06                        ; 16-bit, dp (DP=0): this frame's pad, C3_Pad as
                                         ; C3Mod_PadDelayTask copies it (C3Mod_RaceTask zeroes it)
!C3_RaceResult = $0380                   ; 8-bit: the race's result for the game: 1 won, 2 lost
                                         ; (C3Mod_Init clears it; written as a word with C3_RacePrize)
!C3_RacePrize = $0381                    ; 8-bit: the finish's score prizes (C3Mod_RaceFinish):
                                         ; bits 0-2 a special number (1-4), bits 5-7 1300/1500/2000
!C3_ResultWord = $0382                   ; 16-bit: C3Mod_Prog0 clears it; the score at the finish
                                         ; (C3Mod_RaceFinish); the staff programs put the staff
                                         ; text's address there ($86C2, $86D4)
; The race (program 0), dp words with DP=0: the player's bike and the
; rival. Distances are 32-bit (the high word counts laps: 8 ends the
; race), the side is the position across the track (0-$7000, shown
; up and down: the D-pad steers it), speeds are 8.8 (distance / 64 a
; frame).
!C3_BikeSpeed = $4A                      ; 16-bit: the bike's speed
!C3_BikeAccel = $4C                      ; 16-bit: added to it each frame ($100, 0 at the cap)
!C3_BikeSide = $4E                       ; 16-bit: the bike's side position
!C3_BikeDist = $51                       ; 32-bit ($51-$54): the bike's distance
!C3_BikeTopSpeed = $55                   ; 16-bit: its speed cap ...
!C3_BikeSpeedCap = $57                   ; 16-bit: ... the cap this frame
!C3_BikeTopBehind = $59                  ; 16-bit: ... the cap while it is behind the rival
!C3_BikeHidden = $63                     ; 16-bit: set when the bike leads by $1000 or more
                                         ; (C3Mod_RaceStepTask; tested at $5033)
!C3_BikeSideUp = $65                     ; 16-bit: the bike's side speed up (C3_PadSidePlus)
!C3_BikeSideDown = $67                   ; 16-bit: ... and down (C3_PadSideMinus)
!C3_Score = $69                          ; 16-bit: the score x 2 (+2 a frame in the lead, -1 behind,
                                         ; +20 / -10 by the bumps; shown / 2)
!C3_RivalSpeed = $6F                     ; 16-bit: the rival's speed
!C3_RivalAccel = $71                     ; 16-bit: its acceleration ($F8, 0 at the cap)
!C3_RivalSide = $73                      ; 16-bit: its side position
!C3_RivalDist = $76                      ; 32-bit ($76-$79): its distance
!C3_RivalTopSpeed = $7A                  ; 16-bit: its speed cap ...
!C3_RivalSpeedCap = $7C                  ; 16-bit: ... this frame
!C3_RivalTopAhead = $7E                  ; 16-bit: ... while the bike is ahead
!C3_RivalHidden = $88                    ; 16-bit: as C3_BikeHidden (tested at $50BF)
!C3_RivalSideUp = $8A                    ; 16-bit: the rival's side speed up
!C3_RivalSideDown = $8C                  ; 16-bit: ... and down
!C3_RaceGap = $8E                        ; 16-bit, signed: (the bike's distance - the rival's) / 32
!C3_RivalControl = $98                   ; 16-bit: bit 15 accelerate, bit 9 steer up, bit 8 down
!C3_BoostsLeft = $9A                     ; 16-bit: boosts left (B button), 3 at the start
!C3_PackDist = $9C                       ; 32-bit ($9C-$9F): the mean of the two distances
!C3_BoostHeld = $A0                      ; 16-bit: B held (a boost wants a new press)
!C3_ColumnCleared = $A2                  ; 16-bit: the mode-7 map column is cleared
!C3_BumpNow = $A4                        ; 16-bit: the bikes' relation this frame (see
                                         ; C3Mod_RaceStepTask)
!C3_BumpSide = $A6                       ; 16-bit: its across part (scratch)
!C3_BumpLast = $A8                       ; 16-bit: the last relation while apart
!C3_BikeSteer = $AE                      ; 16-bit: 1 or 2 while the bike steers (0 not)
!C3_RacePhase = $B0                      ; 16-bit: 0 racing, 1 finished (slowing down), 2 after
!C3_FinishGap = $B2                      ; 8-bit: C3_RaceGap's low byte at the finish, counted to 0
                                         ; by C3Mod_RaceTask (read as a word too)
!C3_BoostTimer = $BA                     ; 16-bit: frames of the boost lamp left
!C3_RaceFrames = $BC                     ; 16-bit: + 1 each frame of C3Mod_RaceStepTask
!C3_QuitSeen = $BE                       ; 16-bit: set once C3Mod_RaceTask has seen the A button
!C3_PadSideMinus = $00B6                 ; 16-bit: the D-pad button that steers the bike's side
                                         ; down (C3Mod_SideMinusPads' entry for the view's angle)
!C3_PadSidePlus = $00B8                  ; 16-bit: the one that steers it up (C3Mod_SidePlusPads)
!C3_Prog9 = $44                          ; 8-bit, dp (DP=0): 1 when C3Mod_Prog0 runs as program 9
                                         ; (C3_EntryArg bits 0-3 not 0), else 0 (Init's clear)
!C3_StartCount = $0397                   ; 16-bit: C3Mod_Prog0's C3_EntryArg bit 6 runs, counted
                                         ; (bit 0 picks C3Mod_Prog0WipeA or B)
!C3_ExitTimer = $0399                    ; 16-bit: frames C3Mod_ExitCountTask waits
!C3_SkyScrollX = $141C                   ; 16-bit: BG1's horizontal scroll above the horizon (sky)
!C3_SkyScrollY = $141E                   ; 16-bit: its vertical scroll
!C3_PlaneScrollX = $1420                 ; 16-bit: BG1's scroll below the horizon (the mode-7 plane)
!C3_PlaneScrollY = $1422
!C3_SkyScrollHdma = $1424                ; 4 bytes: C3_SkyScrollX/Y as C3Mod_ScrollHdma sends them
!C3_PlaneScrollHdma = $1428              ; 4 bytes: C3_PlaneScrollX/Y, likewise
!C3_PlaneCentreX = $142C                 ; 16-bit: M7X (C3Mod_ScrollNmiTask)
!C3_PlaneCentreY = $142E                 ; 16-bit: M7Y
!C3_Bg2ScrollX = $1430                   ; 16-bit: BG2HOFS
!C3_Bg3ScrollX = $1434                   ; 16-bit: BG3HOFS
!C3_Bg3ScrollY = $1436                   ; 16-bit: BG3VOFS
!C3_Unk143E = $143E                      ; 16-bit: added to the sky's scroll by C3Mod_SkyNmiTask
!C3_ViewOffsetX = $1440                  ; 16-bit: -sin(angle) x distance / 256 (C3Mod_ViewOffsetTask)
!C3_ViewOffsetY = $1442                  ; 16-bit: -cos(angle) x distance / 256
!C3_Unk1444 = $1444                      ; 16-bit: C3Mod_Prog0Vars clears it, C3Mod_RaceTask steps it
!C3_Unk1446 = $1446                      ; 256 bytes ($1446-$1545): cleared by C3Mod_ClearUnk1446
!C3_Unk1446Bytes = $0100                 ; its size
!C3_MirrorEnd = $0200                    ; 16-bit, in the source's bank ($7F:0200 at C3Mod_Prog0):
                                         ; C3Mod_MirrorRows' first byte, from Y
!C3_MirrorLeft = $0202                   ; 8-bit, $7F:0202: C3Mod_Prog0's C3Mod_MirrorRows calls left
!C3_M7Tables = $7EF000                   ; $7E:F000-$FFFF: the mode-7 line tables (C3_M7ABLines..)
!C3_WipeTable = $7EE000                  ; the kernel wipe's line table and its two buffers
                                         ; (WinFx_C3ETablePtr: $E000 and $E0E0)
!C3_CopyCode = $7EB574                   ; where C3_BuildCopyCode's routine goes (GENERATED)
!C3_MapColumnSave = $7EC995              ; 20 bytes: the mode-7 map column C3Mod_Prog0 saves
!C3_Unk7F0062 = $7F0062                  ; 8-bit: C3Mod_ExitTask zeroes it (use not traced)
; Page $0A00's script variables as the view tasks read them (dp offsets
; in the page; C3Script_Vars + 2n is variable n):
!C3_ViewScale = $00                      ; var 0: C3Mod_BuildM7Tables' scale (C3_M7Scale)
!C3_ViewX = $02                          ; var 1: the plane's X ($000-$3FF)
!C3_ViewDist = $04                       ; var 2: the distance (C3Mod_ViewOffsetTask)
!C3_ViewAngle = $0A                      ; var 5: the angle (C3_M7Angle)
!C3_ViewHorizon = $0C                    ; var 6: the horizon line
!C3_ViewFirstDiv = $10                   ; var 8: C3Mod_BuildM7Tables' first divisor
!C3_ViewSpeedX = $12                     ; var 9: added to C3_ViewX each frame
!C3_ViewStepMode = $16                   ; var 11: nonzero: every other line copied (C3Mod_Prog0Setup)
!C3_ViewCache = $30                      ; 5 words (loop counters 7-11): C3Mod_ViewTask's copies
!C3_ViewLeanR = $3A                      ; 16-bit (loop counter 12): R held, 0-12 (C3Mod_LeanR)
!C3_ViewLeanL = $3C                      ; 16-bit (loop counter 13): L held, 0-12
!C3_ViewY = $04                          ; page $0B00's var 2: the plane's Y (C3Mod_TurnTask)

; ------------------------------------------------------------
; Constants
; ------------------------------------------------------------
!C3_ProgramMask = $1F                    ; C3_EntryArg bits 0-4: the program (C3Mod_ProgramTable;
                                         ; it has 16 entries, so values $10-$1F would read code)
!C3_FadeStepInit = $04                   ; what C3Mod_Init stores in C3_FadeStep/FadeTimer (also
                                         ; the M7A value of its DMA fill, any value but 0 would do)
!C3_ClearFromTasks = $14E0               ; bytes C3Mod_Init clears from C3_TaskList ($0920-$1DFF)
!C3_ClearFromOamHigh = $1500             ; bytes it clears from Oam_HighTable ($0900-$1DFF)
!C3_DirectPageBytes = $0100              ; the direct page $0000-$00FF, cleared first
!C3_Obsel = $02                          ; OBSEL: 8x8 and 16x16 sprites, tiles at VRAM word $4000
!C3_ColdataBlack = $E0                   ; COLDATA: red, green and blue intensity 0
!C3_OamHideY = $E0                       ; the byte C3Mod_HideSprites fills Oam_LowTable with
                                         ; (X = Y = $E0: below the 224 visible lines)
!C3_OamLowBytes = $0200                  ; Oam_LowTable size (128 sprites x 4)
!C3_PaletteBytes = $0200                 ; CGRAM size (256 colours x 2)
!C3_ApuTries = $0400                     ; C3Mod_AudioSend: echo polls before it sends again
!C3_RowBytes = $40                       ; C3Mod_DoubleRows / SpaceRows: bytes per bitmap row
!C3_BitmapRows = $40                     ; ... source rows (64)
!C3_BitmapSrc = $0200                    ; ... the source bitmap, $7F:0200-$11FF
!C3_BitmapDest = $2200                   ; ... the 128 output rows, $7F:2200-$41FF
!C3_NmiTaskListBytes = $10               ; C3_NmiTaskList size (8 words)
!HVBJOY_VBlank = $80                     ; HVBJOY bit 7: in V-blank
; Sound commands of C3Mod_SoundReset (Audio_CmdId, sent as they are to the
; SPC700 driver; its Spc_CmdTable80 names the handlers)
!C3_SndTempoPitch = $85                  ; Spc_CmdTempoPitch: song pitch and tempo adjustment
!C3_SndSfxPitch = $89                    ; Spc_CmdSfxPitch: the effects' pitch adjustment
!C3_SndStopSfx = $F2                     ; Spc_CmdStopSfx: stop one effect group (Arg0 bit 0)
!C3_SndFadeSong = $81                    ; Spc_CmdFadeSong: the song's volume to Arg1 over Arg0 steps
!C3_SndFullVolume = $FF00                ; Audio_CmdArg0/Arg1 as a word: 0 steps, volume $FF
!C3_SndFadeOut = $0040                   ; Audio_CmdArg0/Arg1 as a word: $40 steps to volume 0
!C3_SndStopAll = $F0                     ; Spc_CmdStopAll: stop the song and the effects
!C3_BrightnessFull = $0F                 ; C3_Brightness at the end of a fade in
!C3_AngleMask = $03FF                    ; C3Mod_Sine: 1024 steps per turn
!C3_QuarterTurn = $0100                  ; ... a quarter turn (C3Mod_Cosine adds it)
!C3_HalfTurn = $0200                     ; ... half a turn
!Op_BRA = $80                            ; 65816 opcode BRA (C3Mod_BuildM7Tables writes BRAs into itself)
!C3_NoCall = $0000                       ; a JSR operand written at run time (the assembled $0000 is
                                         ; never called)
!C3_M7ABLines = $F100                    ; $7E:F100: per line, M7A and M7B (4 bytes), 224 lines; the
                                         ; indirect HDMA tables C3Mod_M7HdmaAB.. point into it
!C3_M7CDLines = $F488                    ; $7E:F488: per line, M7C and M7D (4 bytes)
!C3_M7HalfBytes = $01C0                  ; 112 lines x 4 bytes: the second half of a table
!C3_HdmaRepeat112 = $F0                  ; HDMA line count: repeat ($80) for 112 lines
!C3_M7EndDefault = $0380                 ; C3Mod_BuildM7Tables' end offset as assembled (224 x 4);
                                         ; the setup routines write theirs over it
!C3_M7Angle = $0A                        ; dp (the script's page: variable 5): the plane's angle,
                                         ; 1,024 steps per turn
!C3_M7Scale = $00                        ; dp (variable 0): the scale (its low byte)
!C3_DmaChannelBytes = $10                ; one DMA channel's registers ($43n0-$43nF)
!C3_HdmaRecordBytes = 5                  ; C3Mod_SetupHdma: DMAP, BBAD, address, bank
!C3_HdmaListEnd = $00FF                  ; ... a record starting with $FF ends the list
!C3_ScriptPageA = $0A00                  ; the direct page of the first script (C3Script_*)
!C3_ScriptPageB = $0B00                  ; ... and of the second
!C3_HdmaPairs = $70                      ; C3Mod_HdmaAlternate: 112 pairs of lines
!C3_HdmaOneLine = $01                    ; ... each entry one line
!C3_OamBytes = $0220                     ; all of OAM: Oam_LowTable and Oam_HighTable
!C3_OamPriorityRotate = $80              ; OAMADDH bit 7: priority rotation
!C3_OamSlotMask = $03                    ; sprites in a high-table byte so far (offset / 4, mod 4)
!C3_OamSlotsPerByte = 4                  ; sprites per Oam_HighTable byte
!C3_DigitTile0 = $20                     ; C3Mod_DrawNumber: the tile of digit 0 (1-9 follow)
!C3_DigitAttr = $3F                      ; ... its attribute: priority 3, palette 7, tile bit 8
!C3_NumberRecords = 5
!C3_Dec10000 = 10000                     ; ... the decimal places
!C3_Dec1000 = 1000
!C3_Dec100 = 100
!C3_Dec10 = 10                    ; ... digits
!C3_SprLargeBit = $10                    ; C3Mod_SprListMixed: attribute bit 4, the large size
!C3_SignExtend = $FF00                   ; ORA: a negative byte as a 16-bit value
!C3_SignBit8 = $0080                     ; ... the byte's sign bit
!C3_SprHideY = $00E0                     ; Y of a hidden sprite (below the 224 lines)
!C3_NibbleMask = $0F                     ; a byte's low nibble (one 4-bit pixel)
!C3_Div32Steps = 32                      ; C3Mod_Div32: one step per dividend bit
!C3_NibbleStack = $0BFF                  ; C3Mod_UnpackNibbles: S before its first PLA (reads
                                         ; from $0C00 up)
!C3_EntryLowNibble = $0F                 ; C3_EntryArg bits 0-3 (nonzero: program 9, for C3Mod_Prog0)
!C3_EntryWipeStart = $40                 ; C3_EntryArg bit 6: C3Mod_Prog0 starts the wipe run
                                         ; (C3Mod_Prog0WipeA/B, it ends by itself)
!C3_SongCourse = $2C                     ; C3Mod_Prog0's song (C3Mod_PlaySong)
!C3_PackPtrBytes = 3                     ; bytes per C3Rom_PackPtrs entry (X = 3 x the pack)
!C3_Prog0PicsA = $0A00                   ; $7F:0A00: where C3Mod_Prog0 unpacks pack 2 (and
                                         ; C3Scale_PrevEnd's start)
!C3_Prog0PicsB = $8A00                   ; $7F:8A00: packs 3 and 4
!C3_Prog0PicsMoved = $3800               ; $7F:3800: the MVN's destination
!C3_Prog0PicsBytes = $2E00               ; ... its length
!C3_TileRows = 8                         ; rows of an 8x8 block (C3Mod_CopyTileBlock, MirrorRows)
!C3_TileRowBytes = 8                     ; bytes of a block's row
!C3_MirrorBytes = 32                     ; bytes C3Mod_MirrorRows reverses per row (and zeros after)
!C3_MirrorEnd32 = $0020                  ; C3_MirrorEnd values of C3Mod_Prog0
!C3_MirrorEnd24 = $0018
!C3_Prog0MirrorA = $5A00                 ; $7F: where C3Mod_Prog0's mirrored rows go
!C3_Prog0MirrorB = $7800
!C3_Prog0MirrorC = $AE00
!C3_Prog0MirrorCalls = 12                ; C3Mod_MirrorRows calls for pack 4 (96 rows)
!C3_M7TablesBytes = $1000                ; C3_M7Tables' size
!C3_Prog0Clear = $0C00                   ; $7E:0C00-$1DFF, filled from MPYL by C3Mod_Prog0
!C3_Prog0ClearBytes = $1200
!C3_Prog0HdmaOn = $3F                    ; HDMA channels 0-5 (C3Mod_Prog0Hdma)
!C3_Prog0HdmaNoWipe = $3E                ; ... without channel 0 (the wipe's WH0)
!C3_Prog0Fade = $0808                    ; C3_FadeStep and C3_FadeTimer = 8 (one word)
!C3_CopyCodeDest = $0C00                 ; C3_BuildCopyCode's X (stores from $0C00 up)
!C3_CopyCodeSrc = $0200                  ; ... its Y (source base)
!C3_Prog0Bg1Sc = $60                     ; BG1SC: map at VRAM word $6000, 32x32
!C3_Prog0Bg2Sc = $64                     ; BG2SC: map at $6400
!C3_Prog0Bg3Sc = $68                     ; BG3SC: map at $6800
!C3_Prog0Tiles = $77                     ; BG12NBA / BG34NBA: tiles at VRAM word $7000
!VMAIN_Inc128 = $02                      ; VMAIN: + 128 words after the low byte (a mode-7 map column)
!BBAD_RDVRAML = $39                      ; B-bus address of RDVRAML ($2139)
!C3_MapColumn = $0B00                    ; VRAM word: the top of the saved map column (row 22, x 0)
!C3_MapColumnBytes = $0014               ; 20 bytes saved (19 written back)
!C3_WipeHalf = $70                       ; 112 lines: half a wipe buffer
!C3_SprTilesVram = $4000                 ; VRAM word of the sprite tiles (OBSEL C3_Obsel)
!C3_SprTilesBytes = $1000                ; bytes C3Mod_Prog0LoadGfx clears there
!C3_SprTilesHigh = $5000                 ; the sprites' second tile page
!C3_Prog0BgTiles = $7000                 ; VRAM word: BG1-BG3 tiles (C3_Prog0Tiles)
!C3_Prog0Bg1Map = $6000                  ; VRAM words of the three maps
!C3_Prog0Bg2Map = $6400
!C3_Prog0Bg3Map = $6800
!C3_Prog0MapBytes = $0800                ; bytes sent of each map's pack
!C3_Prog0Clear7F = $7F0300               ; $7F:0300-$09FF, filled from MPYL by C3Mod_Prog0LoadGfx
!C3_Prog0Clear7FBytes = $0700
!C3_WipeClearBytes = $40                 ; $7E:E100-$E13F zeroed by C3Mod_Prog0LoadGfx
!C3_PickRunBit = $0002                   ; C3Mod_PickRun: a random byte's bit 1 (x 2 = the index)
!C3_PlaneMask = $03FF                    ; C3_ViewX's range (the mode-7 plane's 1,024 pixels)
!C3_PlaneCentreDX = $007F                ; M7X = the scroll + this (C3Mod_TurnTask)
!C3_PlaneCentreDY = $00E0                ; M7Y = the scroll + this
!C3_ExitFrames = $0020                   ; C3Mod_ExitTask: frames before the module leaves
!C3_SfxWipe = $BA                        ; sound effect of the wipe (C3Mod_ExitTask, the scripts)
!C3_SndSfxA = $18                        ; Spc_CmdSfx18: a sound effect on voices 7 and 6
!C3_SfxArg1 = $80                        ; its Audio_CmdArg1 in the module
!C3_DriftScale = $00A0                   ; C3Mod_DriftTask's rest: the scale,
!C3_DriftHorizon = $0038                 ; the horizon
!C3_DriftDist = $0090                    ; and the distance
!C3_EighthTurn = $80                     ; an eighth of a turn (1,024 steps)
!C3_PadTableMask = $000E                 ; the angle / 64 as an even index (8 entries)
!C3_ViewScaleMax = $007F                 ; C3Mod_SteerTask: X raises the scale while below this
!C3_ViewScaleMin = $0060                 ; ... A lowers it while it is at least this
!C3_LeanMax = $000C                      ; C3Mod_LeanR / LeanL: the count's top
!C3_SkyTopY = $0017                      ; C3_SkyScrollY = this - the horizon
!C3_SkyBaseX = $0088                     ; C3Mod_SkyNmiTask's constant
!C3_CountDownEvery = 4                   ; C3Mod_CountDownTask: one step every 4 frames
!C3_BgMode1 = $01                        ; BGMODE: mode 1 (the sky)
!C3_MathTop = $50                        ; CGADSUB: half colour math on the sprites (the bottom)
!C3_MathSky = $42                        ; CGADSUB: half colour math on BG2 (the sky)
!C3_MathFade = $91                       ; CGADSUB: subtract, on BG1 and the sprites (the fade)
!C3_Prog9Unk53A0 = $D8                   ; what C3Mod_Prog0Vars writes in program 9: over the
                                         ; operands at $4F74/$50DA and into the sprite-list data
                                         ; at $53A0 (the others: sprite-list data only)
!C3_Prog9Unk53A4 = $E8
!C3_Prog9Unk5395 = $06
!C3_Prog9Unk53AE = $01
!C3_BoostTimerStart = $80                ; C3_BoostTimer at the start (program 0)
!C3_BoostsStart = 3                      ; C3_BoostsLeft at the start (program 0)
!C3_BikeTopStart = $4000                 ; C3Mod_Prog0Vars' start values
!C3_RivalTopStart = $3000
!C3_RivalAheadStart = $5000
!C3_BikeSideStart = $6000
!C3_RivalSideStart = $2000
!C3_BumpLastStart = $0020
!C3_RaceLaps = $0008                     ; laps (the distances' high word) of a race
!C3_ColumnBackFinish = $0400             ; C3Mod_RaceTask: the column is put back from lap 8 + this
!C3_RivalGo = $8000                      ; C3_RivalControl: accelerate
!C3_RivalSteerUp = $0200                 ; ... steer up (C3_RivalSideUp)
!C3_RivalSteerDown = $0100               ; ... steer down
!C3_FinishSideLow = $2000                ; C3Mod_RaceTask (program 9): where the sides go
!C3_FinishSideHigh = $6000
!C3_SideCentre = $4000                   ; the middle of the track (program 0's finish)
!C3_SideEvenMask = $FFFE
!C3_SideMoveStep = $0080                 ; the finish moves: $80 a frame
!C3_SideMoveMask = $FF80
!C3_HideLead = $1000                     ; the lead that sets C3_BikeHidden / C3_RivalHidden
!C3_RaceWon = $0001                      ; C3_RaceResult (a word: C3_RacePrize = 0)
!C3_RaceLost = $0002
!C3_TopSpeedFinish = $7000               ; C3Mod_RaceFinish: the bike's caps (program 0)
!C3_RivalTopFinish9 = $4000              ; ... the rival's (program 9)
!C3_FinishVarB6 = $0FFF                  ; ... page $0B00's var 6
!C3_FinishFade = $0505                   ; ... C3_FadeStep and C3_FadeTimer = 5
!C3_ScriptVar6 = $0C                     ; a script page's var 6 (C3Script_Vars + 12)
!C3_Score777 = 777                       ; C3Mod_RaceFinish: special scores (the score shown) ...
!C3_Score123 = 123
!C3_Score1234 = 1234
!C3_Score1000 = 1000                     ; (and 2000, 3000)
!C3_Score1300 = 1300                     ; ... and thresholds
!C3_Score1500 = 1500
!C3_RepDigitCount = 11                   ; C3Mod_RepDigits' entries
!C3_PrizeRepDigits = $01                 ; C3_RacePrize values ...
!C3_Prize777 = $02
!C3_PrizeRun = $03
!C3_PrizeThousands = $04
!C3_Prize1300 = $20                      ; ... and bits
!C3_Prize1500 = $40
!C3_Prize2000 = $80
!C3_SongWon = $1B                        ; C3_SongReq at the finish (the win song, probably)
!C3_ColumnBackDist = $1000               ; C3Mod_RaceStepTask: lap 0 from here: the column back
!C3_ColumnClearDist = $F200              ; ... lap 7 from here: the column cleared
!C3_SpeedDrag = $0080                    ; taken off both speeds each frame
!C3_BikeAccelOn = $0100                  ; C3_BikeAccel below the cap
!C3_RivalAccelOn = $00F8                 ; C3_RivalAccel below the cap
!C3_LampEvery = 8                        ; the boost lamp rotates every 8th frame
!C3_BoostTiles = $7EE100                 ; 64 bytes: two sprite tiles, the boost lamp (sent to VRAM
                                         ; word $5180 by C3Mod_LampUpload)
!C3_BoostTilesBytes = $0040               ; its size
!C3_LampLeftRows = $E111                 ; bank $7E (DB = $7E): the lamp's first tile, row 0's bit
                                         ; plane 3 (+2: row 1's), rotated by C3Mod_RaceStepTask
!C3_LampRightRows = $E131                ; ... the second tile's
!C3_LampVram = $5180                     ; VRAM word C3Mod_LampUpload sends it to
!C3_BoostFrames = $0080                  ; C3_BoostTimer for a boost
!C3_BoostSpeed = $1700                   ; added to C3_BikeSpeed by a boost
!C3_SpeedMax = $7FFF                     ; the most a boost gives
!C3_ViewXBase = $0374                    ; C3_ViewX = C3_PackDist / 16 + this + 1
!C3_SideNear = $0020                     ; the sides' high bytes within this: the rival steers away
!C3_SideMiddle = $0040                   ; the middle of the sides' high bytes
!C3_BikeSteerPlus = 1                    ; C3_BikeSteer values
!C3_BikeSteerMinus = 2
!C3_SidePush = $0028                     ; the bike's side speed + this while steering
!C3_RivalSidePush = $0018                ; the rival's
!C3_SideSpeedMax = $0210                 ; side speeds' top
!C3_SideDecay = $0010                    ; taken off the side speeds each frame
!C3_SideMax = $7000                      ; the side positions' top
!C3_BikeLength = $0100                   ; the bump test's lengths (distance units)
!C3_RivalLength = $00C0
!C3_BumpAhead = $0200                    ; ... and margins
!C3_BumpBehind = $0180
!C3_BumpWidth = $1000                    ; ... the bikes' width (side units)
!C3_BumpAheadOnly = $01                  ; C3_BumpNow / C3_BumpLast: the bike ahead
!C3_BumpBehindOnly = $02                 ; ... behind
!C3_BumpBelowOnly = $10                  ; ... below (side)
!C3_BumpAboveOnly = $20                  ; ... above
!C3_BumpScoreUp = 20                     ; C3_Score + this for a bump from behind
!C3_BumpScoreDown = 10                   ; - this for a bump into the rival
!C3_SfxBump = $98                        ; the bump's sound effect (Audio_CmdPlaySfx)
!C3_StepMask = $01FF                     ; a speed / 64 as a distance step
!C3_TmpF6 = $F6                          ; 32-bit (C3_TmpF6/F8) dp scratch of the bump routines
!C3_TmpF8 = $F8
!C3_PadB = $8000                         ; JOY1 as a word: B
!Op_RTS = $60                            ; 65816 opcode RTS
!C3_PadR = $0010                         ; JOY1 as a word (C3_Pad..): R
!C3_PadL = $0020                         ; L
!C3_PadX = $0040                         ; X
!C3_PadA = $0080                         ; A
!C3_PadRight = $0100                     ; Right
!C3_PadLeft = $0200                      ; Left
!C3_PadDown = $0400                      ; Down
!C3_PadUp = $0800                        ; Up
!Op_NOP = $EA                            ; 65816 opcodes written into code
!Op_INX = $E8
; C3_RunScript's opcodes (bankC3.asm's header has the operands): the
; variable ones take the variable n in bits 0-3, the loops the counter.
!C3Op_Set = $00                          ; var n = word
!C3Op_Add = $10                          ; var n += word
!C3Op_CopyVar = $20                      ; var n = var (byte: 2 x m)
!C3Op_AddVar = $30                       ; var n += var (byte: 2 x m)
!C3Op_Loop = $80                         ; counter n, word limit, word target
!C3Op_LoopYield = $90                    ; the same, then yield
!C3Op_CallW = $F0                        ; word: module routine (C3Mod_CallW)
!C3Op_Poke8 = $F1                        ; word address, byte
!C3Op_Poke16 = $F2                       ; word address, word
!C3Op_Call = $F3                         ; word: a script subroutine
!C3Op_Return = $F4
!C3Op_WaitApu = $F5                      ; byte: wait for APUIO2's low nibble
!C3Op_Driver = $F6                       ; words: Audio_CmdId/Arg0, Arg1/Arg2
!C3Op_NmiRemove = $F7                    ; word: C3_NmiTaskList
!C3Op_NmiAdd = $F8
!C3Op_TaskRemove = $F9                   ; word: C3_TaskList
!C3Op_TaskAdd = $FA
!C3Op_Ppu = $FB                          ; byte value, byte register - $2100
!C3Op_Yield = $FC
!C3Op_JumpYield = $FD                    ; word
!C3Op_Jump = $FE                         ; word
!C3Op_End = $FF                          ; sets C3_ExitFlag

; ------------------------------------------------------------
; The steps of the unrolled dividers (C3Mod_Div16, C3Mod_DivHighByte):
; each shifts the next dividend bit into the remainder in A, takes the
; divisor off when it fits (the carry is the quotient bit) and shifts
; that bit into C3Math_Lo.
; ------------------------------------------------------------
macro C3ModDivStep()                    ; C3Mod_Div16: SEC, then the divisor
    ROL.b !C3Math_A
    ROL A
    SEC
    SBC.b !C3Math_B
    BCS ?fits
    ADC.b !C3Math_B
    CLC
?fits:
    ROL.b !C3Math_Lo
endmacro

macro C3ModDivHighStep()                ; C3Mod_DivHighByte's first 8: no SEC, divisor - 1
    ROL.b !C3Math_A
    ROL A
    SBC.b !C3Math_Q
    BCS ?fits
    ADC.b !C3Math_B
    CLC
?fits:
    ROL.b !C3Math_Lo
endmacro

macro C3ModDivZeroStep()                ; its last 8: a zero bit (ASL) in place of the dividend's
    ASL A
    SBC.b !C3Math_Q
    BCS ?fits
    ADC.b !C3Math_B
    CLC
?fits:
    ROL.b !C3Math_Lo
endmacro
