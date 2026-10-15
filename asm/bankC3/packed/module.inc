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

; ------------------------------------------------------------
; RAM the module uses (DB = $00 and DP = 0 unless a header says
; otherwise; the kernel's names, C3_*, are in ram_engine.inc)
; ------------------------------------------------------------
!C3_Unk0380 = $0380                      ; 8-bit: C3Mod_Init clears it (use not traced)
!C3_Unk0381 = $0381                      ; 8-bit: C3Mod_Init clears it (use not traced)
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
; direct page (0 at every call traced: $00F0-$00FF):
!C3Math_A = $F0                          ; 16-bit: multiplicand / dividend (Div32: low word)
!C3Math_B = $F2                          ; 16-bit: multiplier / divisor (Div32: dividend high word)
!C3Math_Lo = $F4                         ; 16-bit: product low word / quotient (Div32: divisor low)
!C3Math_Hi = $F6                         ; 16-bit: product high word (Div32: divisor high)
!C3Math_Q = $F8                          ; 32-bit: C3Mod_Div32's quotient ($F8-$FB);
                                         ; C3Mod_DivHighByte: the divisor - 1
!C3Math_R = $FC                          ; 32-bit: C3Mod_Div32's remainder ($FC-$FF)
!C3_SqrtRoot = $F0                       ; 16-bit: C3Mod_SquareRoot's result

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
