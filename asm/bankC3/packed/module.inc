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
!Audio_DriverCommand = $C70004           ; bankC7.asm: sends the Audio_Cmd* block (JSL)
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
