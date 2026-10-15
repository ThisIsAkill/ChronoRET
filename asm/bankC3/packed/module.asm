; ============================================================
; The bank $C3 module (BankC3_PackedModule), unpacked
; WRAM $7E:3000-$7E:B57E ($857F bytes), stored packed at $C3:1313-$7A2B
;
; C3_BootModule unpacks the module with Decomp_ToWram to $7E:3000
; (C3Mod_Code) and jumps there; it is the jet-bike race program, about
; half code. Its source is matched here in unpacked form: this file is
; assembled on its own (asar, base $7E:3000) by tools/c3pack.py, which
; packs the result with the original packer's rules back to the 26,393
; bytes in ROM (build/c3pack/module.lz, incbin'd by bankC3.asm). The
; source must write every byte; what is not matched yet is incbin'd
; from the ROM's module, unpacked by the same tool to
; build/c3pack/rom_module.bin (%C3ModRomBytes), as unmatched bytes are
; left as ROM bytes elsewhere, under a label `C3Mod_Rest<addr>` that
; only marks where the block starts.
;
; Labels take the WRAM address ($7E:xxxx); %C3ModOrg(addr) starts a
; block at one. Headers give module addresses ($XXXX is $7E:XXXX).
; The module runs with DB = $00 (C3_BootModule keeps the field's) and,
; after C3Mod_Init, DP = 0 unless a header says otherwise. Callers are
; hand-written (`; Callers note:`): tools/c3module.py traces the module
; and tools/lint_c3module.py checks that every JSR, JSL, JMP, JML and
; BRL site the trace finds is named by its address.
; ============================================================

incsrc "module.inc"

; ============================================================
; Start, setup and leaving ($3000–$31BE)
; ============================================================

; $7E:3000 — C3Mod_Start (67 bytes, $3000–$3042)
; The module's entry point: C3_BootModule unpacks the module and jumps
; here. Sets everything up (C3Mod_Init), runs the program that
; C3_EntryArg bits 0-4 pick from C3Mod_ProgramTable (it returns once
; the program has set up its tasks, probably), uploads the palette
; (C3Mod_UploadPalette), waits for a vertical blank, runs one module
; frame by hand and turns on the NMI, the V-count IRQ and the
; auto-joypad read (Nmi_Nmitimen). From then on the module runs from
; its NMI (C3_ModuleNmi): this loop only waits for C3_ExitFlag. Then
; it turns the NMI, the IRQ and HDMA off and forces a blank, resets the
; sound (C3Mod_SoundReset), sets the stack back to StackTop and leaves
; through ReentryVectors entry [0], the warm restart into
; GameLoop_Main.
; The idle call at $3023 is self-modifying: programs write another
; routine's address over its operand ($3024: $51D1 at $3CE4, $7441 at
; $70D7, $8278 at $79B7, $8930 at $8794 and $87D0, and back to
; C3Mod_Return at $96FE), so the loop runs that routine once per pass
; between frames; C3Mod_Return, the default, does nothing (an RTS).
; Callers note: reached only by C3_BootModule's JML !C3Mod_Code
;   ($C3:0073).
; Entry: M=1, X=0, DP any (C3Mod_Init sets DP = 0), DB=$00 (absolute
;        register and RAM stores); C3_EntryArg = the argument
;        C3_BootModule kept.
; Exit:  never returns: JML ReentryVectors with S = StackTop, M=1,
;        X=0, DP=0, DB=$00 (C3_ModuleFrame set it), A as
;        C3Mod_SoundReset leaves it, X = StackTop.
; Calls: C3Mod_Init, the program (JSR through C3Mod_ProgramTable),
;   C3Mod_UploadPalette, C3Mod_WaitVblank, C3_ModuleFrame (JSL),
;   C3Mod_Return, C3Mod_SoundReset.
%C3ModOrg($7E3000)
C3Mod_Start:
    JSR C3Mod_Init
    LDA.w !C3_EntryArg
    AND.b #!C3_ProgramMask
    ASL A
    TAX                                 ; B = 0 (C3Mod_Init leaves A = 0)
    JSR (C3Mod_ProgramTable,X)
    JSR C3Mod_UploadPalette
    JSR C3Mod_WaitVblank
    JSL !C3_ModuleFrame
    LDA.b #!Nmi_Nmitimen
    STA.w NMITIMEN
    REP #$20
    STZ.b !C3_ExitFlag
    STZ.w !C3_Paused
.wait_exit:
    JSR C3Mod_Return
    LDA.b !C3_ExitFlag
    BEQ .wait_exit
    LDA.w #FORCED_BLANK
    SEP #$20
    STZ.w NMITIMEN
    STZ.w HDMAEN
    STA.w INIDISP
    JSR C3Mod_SoundReset
    LDX.w #!StackTop
    TXS
    JML !ReentryVectors

; $7E:3043 — C3Mod_ProgramTable (32 bytes, $3043–$3062)
; The programs, by C3_EntryArg bits 0-4 (C3Mod_Start's JSR (table,X)
; at $300A). Only 16 entries: an argument of $10-$1F would read the
; code after the table. Several programs share an entry: 0 and 9; 7
; and 8; 10, 11, 14 and 15. What each program is has not been traced
; (the names are the entry numbers).
C3Mod_ProgramTable:
    dw C3Mod_Prog0, C3Mod_Prog1, C3Mod_Prog2, C3Mod_Prog3
    dw C3Mod_Prog4, C3Mod_Prog5, C3Mod_Prog6, C3Mod_Prog7
    dw C3Mod_Prog7, C3Mod_Prog0, C3Mod_Prog10, C3Mod_Prog10
    dw C3Mod_Prog12, C3Mod_Prog13, C3Mod_Prog10, C3Mod_Prog10

; $7E:3063 — C3Mod_Init (276 bytes, $3063–$3176)
; Sets the module up from whatever the field left:
;   - sets its variables: C3_FadeStep and C3_FadeTimer =
;     C3_FadeStepInit; the pause words, C3_NoSoftReset, C3_SongBusy,
;     C3_Brightness, C3_HdmaEnable, C3_Unk0380/0381/0366 = 0;
;   - clears the direct page $0000-$00FF with DMA channel 7, reading
;     MPYL (M7A x M7B = $0404 x 0 = 0) the way ClearRAMDMA does;
;   - with C3_BootIrqOn in C3_EntryArg (entered from the field hook,
;     the display still on): clears $0920-$1DFF (from C3_TaskList,
;     the channel's other registers kept from the first fill) and
;     returns, with the PPU, the sound and the sprites as they were
;     and C3_OamHiPtr 0 (cleared with the direct page);
;   - else clears $0900-$1DFF (from Oam_HighTable); unless
;     C3_EntryNoSong is set, C3_SongReq = 0 and the sound is reset
;     (C3Mod_SoundReset); hides every sprite (C3Mod_HideSprites);
;     C3_OamHiPtr = Oam_HighTable; then sets the PPU registers
;     $2100-$2133 to a blank state: forced blank, OBSEL = C3_Obsel,
;     the others written 0 (mode 0, scrolls, mode-7 matrix, windows,
;     layers and colour math off; COLDATA first gets C3_ColdataBlack,
;     then 0, which selects no colour and so changes nothing). Left
;     untouched, never written: OAMDATA ($2104), VMADDL/H and
;     VMDATAL/H ($2116-$2119) and CGDATA ($2122).
; The 8-bit stores of the 16-bit pause words clear their high bytes
; one by one. The SEP #$20 / REP #$10 before the PPU part change
; nothing (M=1 and X=0 already). The scroll and mode-7 registers are
; written twice each (low, then high byte), M7Y once and then with
; STX, which also writes CGADD.
; Sub-entry: C3Mod_Return ($3176), its final RTS, which C3Mod_Start
; calls as an idle step.
; Callers note: C3Mod_Start ($3000). C3Mod_Return: C3Mod_Start
;   ($3023).
; Entry: M=1, X=0, DP any (set here: DP_DMA, DP_PPU, then 0), DB=$00
;        (absolute register and RAM stores).
; Exit:  M=1, X=0, DP=0, DB=$00; A = 0 (16-bit); X =
;        C3_ClearFromTasks on the C3_BootIrqOn path, else 0; Y
;        unchanged. C3Mod_Return: nothing changed.
; Calls: C3Mod_SoundReset, C3Mod_HideSprites.
C3Mod_Init:
    LDA.b #!C3_FadeStepInit
    STA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    STZ.w !C3_Unk0380
    STZ.w !C3_Unk0381
    STZ.w !C3_PauseAllowed
    STZ.w !C3_Paused
    STZ.w !C3_PauseHeld
    STZ.w !C3_PauseAllowed+1
    STZ.w !C3_Paused+1
    STZ.w !C3_PauseHeld+1
    STZ.w !C3_NoSoftReset
    STZ.w !C3_SongBusy
    STZ.w !C3_Brightness
    STZ.w !C3_HdmaEnable
    STZ.w !C3_Unk0366
    PEA.w !DP_DMA
    PLD
    STA.w M7A
    STA.w M7A
    TDC                                 ; A = $00, the low byte of DP_DMA
    STA.w M7B
    STA.w M7B                           ; MPYL = 0 now
    LDX.w #!BBAD_MPYL<<8|!DMAP_BtoA
    STX.b DMAP7-!DP_DMA                 ; DMAP7 and BBAD7
    LDX.w #!DP_C3Zero                   ; destination $00:0000, the direct page
    STX.b A1T7L-!DP_DMA
    STZ.b A1B7-!DP_DMA
    LDX.w #!C3_DirectPageBytes
    STX.b DAS7L-!DP_DMA
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    PEA.w !DP_C3Zero
    PLD
    LDA.w !C3_EntryArg
    BIT.b #!C3_BootIrqOn
    BEQ .from_event
    LDX.w #!C3_TaskList
    STX.w A1T7L
    LDX.w #!C3_ClearFromTasks
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    TDC
    XBA
    RTS
.from_event:
    LDX.w #!Oam_HighTable
    STX.w A1T7L
    LDX.w #!C3_ClearFromOamHigh
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDA.w !C3_EntryArg
    BIT.b #!C3_EntryNoSong
    BNE .sound_done
    STZ.w !C3_SongReq
    JSR C3Mod_SoundReset
.sound_done:
    JSR C3Mod_HideSprites
    LDX.w #!Oam_HighTable
    STX.b !C3_OamHiPtr
    SEP #$20
    REP #$10
    PEA.w !DP_PPU
    PLD
    LDA.b #FORCED_BLANK
    STA.b INIDISP-!DP_PPU
    LDA.b #!C3_Obsel
    STA.b OBSEL-!DP_PPU
    LDA.b #!C3_ColdataBlack
    STA.b COLDATA-!DP_PPU
    LDX.w #0
    TDC
    XBA
    TXA                                 ; A = 0 (16-bit)
    STX.b OAMADDL-!DP_PPU
    STA.b BGMODE-!DP_PPU
    STA.b MOSAIC-!DP_PPU
    STX.b BG1SC-!DP_PPU                 ; and BG2SC
    STX.b BG3SC-!DP_PPU                 ; and BG4SC
    STX.b BG12NBA-!DP_PPU               ; and BG34NBA
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG3HOFS-!DP_PPU
    STA.b BG3HOFS-!DP_PPU
    STA.b BG3VOFS-!DP_PPU
    STA.b BG3VOFS-!DP_PPU
    STA.b BG4HOFS-!DP_PPU
    STA.b BG4HOFS-!DP_PPU
    STA.b BG4VOFS-!DP_PPU
    STA.b BG4VOFS-!DP_PPU
    STA.b VMAIN-!DP_PPU
    STA.b M7SEL-!DP_PPU
    STA.b M7A-!DP_PPU
    STA.b M7A-!DP_PPU
    STA.b M7B-!DP_PPU
    STA.b M7B-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7D-!DP_PPU
    STA.b M7D-!DP_PPU
    STA.b M7X-!DP_PPU
    STA.b M7X-!DP_PPU
    STA.b M7Y-!DP_PPU
    STX.b M7Y-!DP_PPU                   ; and CGADD
    STX.b W12SEL-!DP_PPU                ; and W34SEL
    STA.b WOBJSEL-!DP_PPU
    STX.b WH0-!DP_PPU                   ; and WH1
    STX.b WH2-!DP_PPU                   ; and WH3
    STX.b WBGLOG-!DP_PPU                ; and WOBJLOG
    STX.b TM-!DP_PPU                    ; and TS
    STX.b TMW-!DP_PPU                   ; and TSW
    STX.b CGWSEL-!DP_PPU                ; and CGADSUB
    STX.b COLDATA-!DP_PPU               ; and SETINI
    PEA.w !DP_C3Zero
    PLD
C3Mod_Return:                           ; header: see C3Mod_Init
    RTS

; $7E:3177 — C3Mod_SoundReset (57 bytes, $3177–$31AF)
; Unless C3_EntryNoSong is set in C3_EntryArg (then it returns at
; once, through C3Mod_Return), sends the sound driver five commands
; (C3Mod_AudioSend each): C3_SndTempoPitch and C3_SndSfxPitch with
; arguments 0, 0 (no pitch or tempo adjustment, probably), then
; C3_SndStopSfx with Arg0 0 and with Arg0 1 (both effect groups
; stopped), and last C3_SndFadeSong with Arg0 0 and Arg1 $FF (the
; song's volume to $FF at once, as LocLoad_AudioSetup sends it).
; Audio_CmdArg2 is never written here.
; Callers note: C3Mod_Start ($3038) and C3Mod_Init ($30F3).
; Entry: M=1, X=0, DP any, DB=$00 (the Audio_Cmd* block is absolute).
; Exit:  M=1, X=0, DP and DB unchanged; A = C3_SndFadeSong (or
;        C3_EntryArg on the early return); X = the polls C3Mod_AudioSend
;        left (unchanged on the early return); Y unchanged;
;        Audio_CmdId.. Arg1 = the last command.
; Calls: C3Mod_AudioSend (JMP for the last one).
C3Mod_SoundReset:
    LDA.w !C3_EntryArg
    BIT.b #!C3_EntryNoSong
    BNE C3Mod_Return
    STZ.w !Audio_CmdArg1
    LDX.w #!C3_SndTempoPitch
    STX.w !Audio_CmdId                  ; and Arg0 = 0
    JSR C3Mod_AudioSend
    LDA.b #!C3_SndSfxPitch
    STA.w !Audio_CmdId
    JSR C3Mod_AudioSend
    LDA.b #!C3_SndStopSfx
    STA.w !Audio_CmdId
    JSR C3Mod_AudioSend
    LDA.b #1
    STA.w !Audio_CmdArg0
    JSR C3Mod_AudioSend
    LDX.w #!C3_SndFullVolume
    STX.w !Audio_CmdArg0                ; and Arg1
    LDA.b #!C3_SndFadeSong
    STA.w !Audio_CmdId
    JMP C3Mod_AudioSend

; $7E:31B0 — C3Mod_WaitVblank (15 bytes, $31B0–$31BE)
; Waits for the start of a vertical blank: first for HVBJOY bit 7 to
; clear (out of any blank already under way), then for it to set.
; Callers note: C3Mod_Start ($3010) and $710F (code not matched yet).
; Entry: M=1, X any, DP any, DB=$00 (HVBJOY is absolute).
; Exit:  M=1; A = HVBJOY; X, Y, DP and DB unchanged.
C3Mod_WaitVblank:
    LDA.w HVBJOY
    BIT.b #!HVBJOY_VBlank
    BNE C3Mod_WaitVblank
.wait_start:
    LDA.w HVBJOY
    BIT.b #!HVBJOY_VBlank
    BEQ .wait_start
    RTS

; ============================================================
; Math, random numbers, sine ($31BF–$347A)
; ============================================================

; $7E:31BF — C3Mod_Mul16 (74 bytes, $31BF–$3208)
; Unsigned 16 x 16-bit multiply with the CPU's 8 x 8 multiplier:
; C3Math_Lo/Hi ($F4-$F7) = C3Math_A x C3Math_B, from the four byte
; products (low x low, the two cross products added together, high x
; high). DB is set to 0 for the multiplier registers (and restored).
; Quirk: the carry of the cross-product sum is kept with a 16-bit ROL of
; $F7 (where the high word's high byte will be), which also shifts the
; byte after it, $F8, left by one, and brings its bit 7 in as the carry
; of the next add: the product is one too big in its bits 8-23 when
; $F8 bit 7 is set (the callers leave $F8 as it is).
; Callers note: C3Mod_MulSigned16 ($33F0) and $3591, $35A7, $35C9,
;   $35E8, $4F4A, $56DE, $5BE7, $5C05, $5C22, $5CCD, $5CF0, $6025, $99CB
;   and $99EB (code not matched yet).
; Entry: M=0 (16-bit A for the product reads), X=0 (X and Y are pushed
;        and pulled as words), DP = the page of C3Math_A.. (0 at every
;        call), DB any (saved); C3Math_A, C3Math_B = the operands.
; Exit:  P, X, Y, DB restored; A = the product's high word; C3Math_Lo
;        and C3Math_Hi = the product; $F8 shifted left (see above).
%C3ModOrg($7E31BF)
C3Mod_Mul16:
    PHP
    PHB
    PHX
    PHY
    SEP #$10
    LDY.b #0
    PHY
    PLB                                 ; DB = $00
    LDX.b !C3Math_B
    LDY.b !C3Math_A
    STX.w WRMPYA
    STY.w WRMPYB                        ; A low x B low
    LDY.b !C3Math_A+1
    STZ.b !C3Math_Hi
    LDA.w RDMPYL
    STY.w WRMPYB                        ; A high x B low
    STA.b !C3Math_Lo
    LDX.b !C3Math_B+1
    LDY.b !C3Math_A
    LDA.w RDMPYL
    STX.w WRMPYA
    STY.w WRMPYB                        ; A low x B high
    LDY.b !C3Math_A+1
    CLC
    ADC.w RDMPYL                        ; the cross products
    ROL.b !C3Math_Hi+1                  ; their carry to $F7 (and $F8 shifted: see above)
    STY.w WRMPYB                        ; A high x B high
    ADC.b !C3Math_Lo+1
    STA.b !C3Math_Lo+1
    LDA.w RDMPYL
    ADC.b !C3Math_Hi
    STA.b !C3Math_Hi
    REP #$10
    PLY
    PLX
    PLB
    PLP
    RTS

; $7E:3209 — C3Mod_Div16 (217 bytes, $3209–$32E1)
; Unsigned 16-bit divide, unrolled: C3Math_Lo = A / C3Math_B, A = the
; remainder; C3Math_A (the dividend, stored from A) is shifted out to
; 0. Quirk: a remainder from $8000 up loses its top bit in the ROL A,
; so the result is right only for divisors up to $8000.
; Callers note: only C3Mod_DivSigned16 ($3425), which nothing calls.
; Entry: M=0, X any, DP = the page of C3Math_A.. ; DB any; A = the
;        dividend, C3Math_B = the divisor (not 0).
; Exit:  A = the remainder, C3Math_Lo = the quotient, C3Math_A = 0;
;        C3Math_B, X, Y, P's M and X unchanged.
C3Mod_Div16:
    STA.b !C3Math_A
    LDA.w #0
    STA.b !C3Math_Lo
    CLC
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    RTS

; $7E:32E2 — C3Mod_DivHighByte (189 bytes, $32E2–$339E)
; Divides the dividend's high byte x 256 by C3Math_B, unrolled:
; C3Math_Lo = (A AND $FF00) / C3Math_B, A = the remainder. The first 8
; steps shift in the dividend's bits 15-8; the last 8 shift in zeros
; (ASL) where C3Mod_Div16 would take bits 7-0 (so the low byte is
; ignored: probably on purpose, a fraction of 256ths). It subtracts
; C3Math_B - 1 (in C3Math_Q) with the carry clear from the shift, one
; instruction less than SEC / SBC. Quirk: as for C3Mod_Div16, a remainder
; from $8000 up (a divisor above $8000) gives a wrong step.
; Callers note: $4E30, $4E43, $4E55, $4EAB, $4EBF, $8210 and $896E (code
;   not matched yet).
; Entry: M=0, X any, DP = the page of C3Math_A.. (0 at the calls); DB
;        any; A = the dividend, C3Math_B = the divisor (not 0).
; Exit:  A = the remainder, C3Math_Lo = the quotient; C3Math_A shifted
;        left by 8; C3Math_Q = the divisor - 1; X, Y unchanged.
C3Mod_DivHighByte:
    STA.b !C3Math_A
    LDA.b !C3Math_B
    DEC A
    STA.b !C3Math_Q
    LDA.w #0
    STA.b !C3Math_Lo
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    RTS

; $7E:339F — C3Mod_Div32 (55 bytes, $339F–$33D5)
; Unsigned 32-bit divide, 32 steps: C3Math_Q ($F8-$FB) = the dividend
; ($F0-$F3: C3Math_A low word, C3Math_B high word) / the divisor ($F4-$F7:
; C3Math_Lo, C3Math_Hi), C3Math_R ($FC-$FF) = the remainder. The
; dividend words are shifted left 32 times on the way (what comes in
; at their bottom is not used).
; Callers note: $5C44 (code not matched yet).
; Entry: M=0, X=0 (the 16-bit step count), DP = the page of C3Math_A..
;        (0 at the call); DB any; the dividend and the divisor (not 0) as
;        above.
; Exit:  C3Math_Q = the quotient, C3Math_R = the remainder; A = the
;        remainder's high word; X = 0; Y unchanged; C3Math_A/B shifted.
C3Mod_Div32:
    STZ.b !C3Math_Q+2
    STZ.b !C3Math_Q
    STZ.b !C3Math_R+2
    STZ.b !C3Math_R
    LDX.w #!C3_Div32Steps
.step:
    ROL.b !C3Math_A
    ROL.b !C3Math_B
    ROL.b !C3Math_R
    ROL.b !C3Math_R+2
    SEC
    LDA.b !C3Math_R
    SBC.b !C3Math_Lo
    STA.b !C3Math_R
    LDA.b !C3Math_R+2
    SBC.b !C3Math_Hi
    STA.b !C3Math_R+2
    BCS .fits
    LDA.b !C3Math_R
    ADC.b !C3Math_Lo
    STA.b !C3Math_R
    LDA.b !C3Math_R+2
    ADC.b !C3Math_Hi
    STA.b !C3Math_R+2
    CLC
.fits:
    ROL.b !C3Math_Q
    ROL.b !C3Math_Q+2
    DEX
    BNE .step
    RTS

; $7E:33D6 — C3Mod_MulSigned16 (55 bytes, $33D6–$340C)
; Signed 16 x 16-bit multiply: the operands are made positive in place,
; multiplied (C3Mod_Mul16) and the 32-bit product negated when their
; signs differed.
; Callers note: $4458, $446B, $4E61, $4ECB, $9B0A and $9B1D (code not
;   matched yet).
; Entry: M=0, X=0 (C3Mod_Mul16's), DP = the page of C3Math_A.. (0 at the
;        calls); DB any; C3Math_A, C3Math_B = the signed operands.
; Exit:  P restored; C3Math_Lo/Hi = the signed product; C3Math_A and
;        C3Math_B = the operands' magnitudes; A = the product's high
;        word; X, Y unchanged; $F8 as C3Mod_Mul16 leaves it.
; Calls: C3Mod_Mul16.
C3Mod_MulSigned16:
    PHP
    LDA.b !C3Math_A
    EOR.b !C3Math_B
    PHP                                 ; N: the signs differ
    LDA.b !C3Math_A
    BPL .a_positive
    EOR.w #!Eng_Invert16
    INC A
.a_positive:
    STA.b !C3Math_A
    LDA.b !C3Math_B
    BPL .b_positive
    EOR.w #!Eng_Invert16
    INC A
.b_positive:
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    PLP
    BPL .done
    CLC
    LDA.b !C3Math_Lo
    EOR.w #!Eng_Invert16
    ADC.w #1
    STA.b !C3Math_Lo
    LDA.b !C3Math_Hi
    EOR.w #!Eng_Invert16
    ADC.w #0
    STA.b !C3Math_Hi
.done:
    PLP
    RTS

; $7E:340D — C3Mod_DivSigned16 (54 bytes, $340D–$3442)
; A signed counterpart of C3Mod_Div16 that nothing calls (no call site,
; no table or stored address found): it takes the magnitudes of
; C3Math_B and C3Math_A, divides (C3Mod_Div16) and, when the signs
; differed, takes the magnitudes of C3Math_Lo and C3Math_Hi again
; instead of negating the quotient, so the sign is never applied. It
; also loads C3Math_Hi, which C3Mod_Div16 does not write, in place of
; the remainder. Kept as it is (dead code, probably unfinished).
; Entry: M=0, X any, DP = the page of C3Math_A..; DB any; C3Math_A,
;        C3Math_B = the signed dividend and divisor.
; Exit:  P restored; C3Math_Lo = |the quotient|; A = C3Math_Hi (or its
;        magnitude); C3Math_A = 0; C3Math_B = |the divisor|.
; Calls: C3Mod_Div16.
C3Mod_DivSigned16:
    PHP
    LDA.b !C3Math_A
    EOR.b !C3Math_B
    PHP                                 ; N: the signs differ
    LDA.b !C3Math_B
    BPL .b_positive
    EOR.w #!Eng_Invert16
    INC A
.b_positive:
    STA.b !C3Math_B
    LDA.b !C3Math_A
    BPL .a_positive
    EOR.w #!Eng_Invert16
    INC A
.a_positive:
    JSR C3Mod_Div16
    LDA.b !C3Math_Hi                    ; not the remainder (see above)
    PLP
    BPL .done
    LDA.b !C3Math_Lo
    BPL .lo_positive
    EOR.w #!Eng_Invert16
    INC A
.lo_positive:
    STA.b !C3Math_Lo
    LDA.b !C3Math_Hi
    BPL .hi_positive
    EOR.w #!Eng_Invert16
    INC A
.hi_positive:
    STA.b !C3Math_Hi
.done:
    PLP
    RTS

; $7E:3443 — C3Mod_KernelRandom (5 bytes, $3443–$3447)
; The kernel's random byte (C3_RandomByte) for code in the module (a JSR
; target for the JSL).
; Callers note: $577A, $5780, $5786, $57B3, $57B9, $7397, $7F85, $7FA0,
;   $80A6, $80D3, $98E3 and $98EE (code not matched yet).
; Entry: M, X, DP and DB as C3_RandomByte needs (M=1, X=0 at the
;        calls).
; Exit:  as C3_RandomByte leaves them (A = the byte).
; Calls: C3_RandomByte (JSL).
C3Mod_KernelRandom:
    JSL !C3_RandomByte
    RTS

; $7E:3448 — C3Mod_TableRandom (25 bytes, $3448–$3460)
; The next byte of RandomTable: C3_RandIndex goes up by one (wrapping at
; 256; the AND #$FF after the INC changes nothing) and indexes the
; table. B is set to DP's low byte first (TDC / XBA), so that the TAX
; makes a 16-bit index of the byte: right only with DP on a page
; boundary (0 at the calls).
; Callers note: $3F59 (a script routine), $65AE, $65BF, $65C9, $728E
;   and $9BE1 (code not matched yet).
; Entry: M any (saved; 8-bit here), X any (saved; with X=1 the TAX
;        takes the byte alone), DP = a page boundary, DB any (the reads
;        and the store are long).
; Exit:  P and X restored; A = the random byte, B = DP's low byte (so A
;        as a word is the byte when M=0 at the call).
C3Mod_TableRandom:
    PHP
    PHX
    SEP #$20
    TDC
    XBA                                 ; B = DP's low byte (0)
    LDA.l !C3_RandIndex
    INC A
    AND.b #!Eng_LowByteMask             ; changes nothing (the INC wraps at 256 already)
    STA.l !C3_RandIndex
    TAX
    LDA.l !RandomTable,X
    PLX
    PLP
    RTS

; $7E:3461 — C3Mod_Cosine (25 bytes with C3Mod_Sine, $3461–$3479)
; The sine of the angle in A (1,024 steps per turn) as a signed 16-bit
; value of magnitude 0-$FF from Rom_SineTable's |sin| bytes, negative
; for angles $000-$1FF and positive for $200-$3FF (so -sin, probably
; for the screen's downward y). C3Mod_Cosine adds a quarter turn and
; falls into C3Mod_Sine ($3465).
; Callers note: $357F, $444F, $4D19, $56B6, $5867, $5BD7, $5BFB, $5CBC,
;   $73C9, $76DB, $99DB and $9B01 (code not matched yet). C3Mod_Sine:
;   $35B7, $4462, $4D26, $56C2, $585B, $5C11, $5CE0, $6014, $73BD,
;   $73FD, $76FE, $99BB and $9B14 (code not matched yet).
; Entry: M=0, X=0 (16-bit index), DP any, DB any (the read is long); A
;        = the angle (only bits 0-9 count).
; Exit:  A = the signed value; X = the angle AND C3_AngleMask; Y
;        unchanged.
C3Mod_Cosine:
    CLC
    ADC.w #!C3_QuarterTurn
C3Mod_Sine:                             ; header: see C3Mod_Cosine
    AND.w #!C3_AngleMask
    TAX
    LDA.l !Rom_SineTable,X
    AND.w #!Eng_LowByteMask
    CPX.w #!C3_HalfTurn
    BCS .done
    EOR.w #!Eng_Invert16
    INC A
.done:
    RTS

; ============================================================
; Fade tasks ($347A–$34FA)
; ============================================================

; $7E:347A — C3Mod_FadeInTask (27 bytes, $347A–$3494)
; A task: every C3_FadeStep frames (C3_FadeTimer counts them down), one
; step brighter (C3_Brightness + 1); at full brightness it ends itself
; (C3Mod_TaskEnd).
; Callers note: a task: LDX #C3Mod_FadeInTask / JSR $395E at $6BD8
;   (code not matched yet).
; Entry: a task (C3Mod_RunTasks): M=0 (8-bit set here), X=0, DP any, DB
;        = $00 (the variables are absolute).
; Exit:  RTS with M=1, A = C3_Brightness (or C3_FadeTimer); at the end
;        JMP C3Mod_TaskEnd.
C3Mod_FadeInTask:
    SEP #$20
    DEC.w !C3_FadeTimer
    BNE .wait
    LDA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    INC.w !C3_Brightness
    LDA.w !C3_Brightness
    CMP.b #!C3_BrightnessFull
    BEQ .end
.wait:
    RTS
.end:
    JMP C3Mod_TaskEnd

; $7E:3495 — C3Mod_FadeOutTask (22 bytes, $3495–$34AA)
; A task: every C3_FadeStep frames one step darker (C3_Brightness - 1);
; at 0 (C3_ModuleFrame then shows forced blank) it ends itself.
; Callers note: a task added by the script at $94E6 (opcode $xA).
; Entry: a task: M=0 (8-bit set here), X=0, DP any, DB = $00.
; Exit:  RTS with M=1; at the end JMP C3Mod_TaskEnd.
C3Mod_FadeOutTask:
    SEP #$20
    DEC.w !C3_FadeTimer
    BNE .wait
    LDA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    DEC.w !C3_Brightness
    BEQ .end
.wait:
    RTS
.end:
    JMP C3Mod_TaskEnd

; $7E:34AB — C3Mod_MusicFadeTask (23 bytes, $34AB–$34C1)
; A task that runs once: it has the sound driver fade the song out
; (C3_SndFadeSong, $40 steps to volume 0, by Audio_DriverCommand) and
; hands its entry over to C3Mod_FadeOutStopTask (C3Mod_TaskReplace).
; Callers note: a task added by the script at $5B92 (opcode $xA).
; Entry: a task: M=0 (8-bit set here), X=0, DP any, DB = $00 (the
;        Audio_Cmd* block is absolute).
; Exit:  JMP C3Mod_TaskReplace with X = C3Mod_FadeOutStopTask.
; Calls: Audio_DriverCommand (JSL).
C3Mod_MusicFadeTask:
    SEP #$20
    LDX.w #!C3_SndFadeOut
    STX.w !Audio_CmdArg0                ; and Arg1 = 0
    LDA.b #!C3_SndFadeSong
    STA.w !Audio_CmdId
    JSL !Audio_DriverCommand
    LDX.w #C3Mod_FadeOutStopTask
    JMP C3Mod_TaskReplace

; $7E:34C2 — C3Mod_FadeOutStopTask (33 bytes, $34C2–$34E2)
; A task: fades out as C3Mod_FadeOutTask; at 0 it stops all sound
; (C3_SndStopAll) and sets C3_ExitFlag (INC of its low byte), so the
; module leaves (C3Mod_Start), and ends itself.
; Callers note: a task by replacement: LDX #C3Mod_FadeOutStopTask /
;   JMP C3Mod_TaskReplace in C3Mod_MusicFadeTask ($34BC).
; Entry: a task: M=0 (8-bit set here), X=0, DP=0 (C3_ExitFlag is
;        direct page), DB = $00.
; Exit:  RTS with M=1; at the end JMP C3Mod_TaskEnd.
; Calls: Audio_DriverCommand (JSL).
C3Mod_FadeOutStopTask:
    SEP #$20
    DEC.w !C3_FadeTimer
    BNE .wait
    LDA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    DEC.w !C3_Brightness
    BEQ .end
.wait:
    RTS
.end:
    LDA.b #!C3_SndStopAll
    STA.w !Audio_CmdId
    JSL !Audio_DriverCommand
    INC.b !C3_ExitFlag
    JMP C3Mod_TaskEnd

; $7E:34E3 — C3Mod_FadeOutExitTask (24 bytes, $34E3–$34FA)
; A task: fades out as C3Mod_FadeOutTask; at 0 it sets C3_ExitFlag (the
; module leaves) and ends itself.
; Callers note: a task added by the script at $95FE (opcode $xA).
; Entry: a task: M=0 (8-bit set here), X=0, DP=0, DB = $00.
; Exit:  RTS with M=1; at the end JMP C3Mod_TaskEnd.
C3Mod_FadeOutExitTask:
    SEP #$20
    DEC.w !C3_FadeTimer
    BNE .wait
    LDA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    DEC.w !C3_Brightness
    BEQ .end
.wait:
    RTS
.end:
    INC.b !C3_ExitFlag
    JMP C3Mod_TaskEnd

; ============================================================
; Square root, fill bytes, nibble unpackers ($34FB–$355E)
; ============================================================

; $7E:34FB — C3Mod_SquareRoot (15 bytes, $34FB–$3509)
; The square root of A, rounded to the nearest: C3_SqrtRoot = k after
; subtracting 0, 0, 1, 1, 2, 2, ... (each k twice) until A would go
; below 0. With the carry clear on entry the first subtraction takes 1
; more, and the result is round(sqrt(A)) (checked for every 16-bit A);
; with it set, round(sqrt(A + 1)). Its caller enters with the carry of
; an ADC (clear unless the sum overflowed).
; Callers note: $7699 (code not matched yet).
; Entry: M=0, X any, DP = the page of C3_SqrtRoot (0 at the call); DB
;        any; A = the value; C as above.
; Exit:  C3_SqrtRoot = the root; A = what is left (A minus the sum
;        taken); C clear; X, Y unchanged.
C3Mod_SquareRoot:
    STZ.b !C3_SqrtRoot
.take:
    SBC.b !C3_SqrtRoot
    BCC .done
    SBC.b !C3_SqrtRoot
    BCC .done
    INC.b !C3_SqrtRoot
    BRA .take
.done:
    RTS

; $7E:350A — C3Mod_FillBytes (4 bytes, $350A–$350D)
; DMA fill sources: the zero word at $350B is the fixed source of the
; VRAM clears at $3D9D, $5AEE and $90B0 (DMAP $09: fixed address, two
; registers); the $FF bytes around it have no reader found (probably
; fill bytes too).
C3Mod_FillBytes:
    db $FF, $00, $00, $FF

; $7E:350E — C3Mod_UnpackNibbles (46 bytes, $350E–$353B)
; Unpacks Y bytes of 4-bit pixels from $0C00 up into one byte per pixel
; at $7F:0200 (C3_BitmapSrc, through WMDATA): the low nibble first, then
; the high. It reads the bytes with PLA, the stack pointed at
; C3_NibbleStack ($0BFF) and saved in C3_StackSave meanwhile, so no
; interrupt must come (the module calls it with the screen off,
; probably).
; Callers note: $53E1 (code not matched yet).
; Entry: M=1 (set here), X=0, DP any (saved; DP_PPU inside), DB = $00
;        (C3_StackSave is absolute); Y = the byte count (not 0).
; Exit:  M=1, X=0, DP restored, S restored; A = the last high nibble, X
;        = S, Y = 0; WMADD past the pixels.
C3Mod_UnpackNibbles:
    SEP #$20
    PHD
    PEA.w !DP_PPU
    PLD
    TSX
    STX.w !C3_StackSave
    LDX.w #!C3_NibbleStack
    TXS
    LDX.w #!C3_BitmapSrc
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDA.b #!Bank7F
    STA.b WMADDH-!DP_PPU
.byte:
    PLA
    TAX
    AND.b #!C3_NibbleMask
    STA.b WMDATA-!DP_PPU
    TXA
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b WMDATA-!DP_PPU
    DEY
    BNE .byte
    LDX.w !C3_StackSave
    TXS
    PLD
    RTS

; $7E:353C — C3Mod_NibblesToVram (35 bytes, $353C–$355E)
; Sends Y bytes of 4-bit pixels from $7F:0200 (C3_BitmapSrc, read
; through WMDATA) to VRAM's high bytes (VMDATAH: mode-7 characters, one
; pixel per word), the low nibble first, then the high: two words per
; byte from the current VRAM address (set by the caller; VMAIN must
; step after the high byte).
; Callers note: $8A7E (code not matched yet).
; Entry: M=1 (set here), X=0, DP any (saved; DP_PPU inside), DB any; Y
;        = the byte count (not 0).
; Exit:  M=1, X=0, DP restored; A = the last high nibble, X = the last
;        byte, Y = 0; WMADD past the bytes.
C3Mod_NibblesToVram:
    SEP #$20
    PHD
    PEA.w !DP_PPU
    PLD
    LDX.w #!C3_BitmapSrc
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDA.b #!Bank7F
    STA.b WMADDH-!DP_PPU
.byte:
    LDA.b WMDATA-!DP_PPU
    TAX
    AND.b #!C3_NibbleMask
    STA.b VMDATAH-!DP_PPU
    TXA
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b VMDATAH-!DP_PPU
    DEY
    BNE .byte
    PLD
    RTS

%C3ModOrg($7E355F)
C3Mod_Rest355F:
    %C3ModRomBytes($7E355F, $7E377A)

; ============================================================
; The sound port, bitmap row copies, the script's call ($377A–$37F9)
; ============================================================

; $7E:377A — C3Mod_AudioCommand (4 bytes, $377A–$377D)
; C3Mod_AudioSend for callers in other banks (JSL, RTL).
; Callers note: the kernel's C3_ReadPad (JSL !C3Mod_AudioCommand,
;   $C3:0AE1 and $C3:0AF3), sending the pause and resume sounds.
; Entry: as C3Mod_AudioSend: M any, X=0, DP any, DB=$00.
; Exit:  as C3Mod_AudioSend.
; Calls: C3Mod_AudioSend.
%C3ModOrg($7E377A)
C3Mod_AudioCommand:
    JSR C3Mod_AudioSend
    RTL

; $7E:377E — C3Mod_AudioSend (40 bytes, $377E–$37A5)
; Sends the command block Audio_CmdId, Arg0, Arg1, Arg2 to the sound
; driver: Arg2..Arg0 to APUIO3..APUIO1, then the command to APUIO0
; last, and waits for the driver to echo the command in APUIO0. After
; C3_ApuTries polls without the echo it writes the four ports again,
; for ever: there is no give-up. The block is not cleared afterwards
; (C3Mod_SoundReset relies on that, sending runs of commands that
; change one byte each).
; Callers note: C3Mod_AudioCommand ($377A), C3Mod_SoundReset ($3187,
;   $318F, $3197, $319F, $31AD JMP) and $426D, $4BC8, $63E5 and $8EB2
;   (code not matched yet).
; Entry: M any (SEP #$20 here), X=0 (the 16-bit poll count), DP any,
;        DB=$00 (the ports and the block are absolute).
; Exit:  M=1, X=0; A = Audio_CmdId; X = polls left (nonzero), Y, DP
;        and DB unchanged.
C3Mod_AudioSend:
    SEP #$20
.send:
    LDX.w #!C3_ApuTries
    LDA.w !Audio_CmdArg2
    STA.w APUIO3
    LDA.w !Audio_CmdArg1
    STA.w APUIO2
    LDA.w !Audio_CmdArg0
    STA.w APUIO1
    LDA.w !Audio_CmdId
    STA.w APUIO0
.poll:
    CMP.w APUIO0
    BEQ .done
    DEX
    BNE .poll
    BRA .send
.done:
    RTS

; $7E:37A6 — C3Mod_DoubleRows (36 bytes, $37A6–$37C9)
; Stretches a 64 x 64-byte bitmap in bank $7F to twice its height: each
; 64-byte row of $7F:0200-$11FF (C3_BitmapSrc) is copied twice in a row
; to $7F:2200-$41FF (C3_BitmapDest), 128 rows (two MVNs per row, the
; source pointer saved for the second). The row count lives in the
; caller's direct page (C3_RowCount). What the bitmap is (probably a
; picture for C3_ScaleBitmap, which reads 64-byte rows) is not traced.
;   Its JSL callers each call $3691 first (code not matched yet), which
; probably puts the picture at $7F:0200.
; Callers note: JSL from $3DED, $3DFA, $7908 and $87B3 (code not
;   matched yet).
; Entry: M any (REP #$20 here), X=0 (MVN's 16-bit X and Y), DP any
;        (its C3_RowCount word is used), DB any (saved).
; Exit:  M=1, X=0, DP and DB as on entry; A = $FFFF; X = $1200, Y =
;        $4200 (past the copies); C3_RowCount = 0.
C3Mod_DoubleRows:
    PHB
    REP #$20
    LDA.w #!C3_BitmapRows
    STA.b !C3_RowCount
    LDY.w #!C3_BitmapDest
    LDX.w #!C3_BitmapSrc
.row:
    PHX
    LDA.w #!C3_RowBytes-1
    MVN $7F,$7F                         ; lint-ok: MVN operands are bank bytes (WRAM bank $7F)
    PLX
    LDA.w #!C3_RowBytes-1
    MVN $7F,$7F                         ; lint-ok: MVN operands are bank bytes
    DEC.b !C3_RowCount
    BNE .row
    SEP #$20
    PLB
    RTL

; $7E:37CA — C3Mod_SpaceRows (41 bytes, $37CA–$37F2)
; Like C3Mod_DoubleRows, but each copied row is followed by a row of
; zeros: after the copy it stores a zero word at the next output row
; (STZ with DB = $7F from the MVN) and spreads it with an overlapping
; 63-byte MVN (each byte copied onto the next), so the 128 output rows
; at $7F:2200-$41FF alternate picture and blank.
; Callers note: JSL from $544D, $859B, $85A8 and $8A8D (code not
;   matched yet).
; Entry: M any (REP #$20 here), X=0, DP any (its C3_RowCount word is
;        used), DB any (saved).
; Exit:  M=1, X=0, DP and DB as on entry; A = $FFFF; X = $1200, Y =
;        $4200; C3_RowCount = 0.
C3Mod_SpaceRows:
    PHB
    REP #$20
    LDA.w #!C3_BitmapRows
    STA.b !C3_RowCount
    LDY.w #!C3_BitmapDest
    LDX.w #!C3_BitmapSrc
.row:
    LDA.w #!C3_RowBytes-1
    MVN $7F,$7F                         ; lint-ok: MVN operands are bank bytes (WRAM bank $7F)
    PHX
    TYX
    INY
    STZ.w !Eng_PtrBase,X                ; the row X points at (DB = $7F after the MVN)
    LDA.w #!C3_RowBytes-2
    MVN $7F,$7F                         ; lint-ok: MVN operands are bank bytes
    PLX
    DEC.b !C3_RowCount
    BNE .row
    SEP #$20
    PLB
    RTL

; $7E:37F3 — C3Mod_CallW (7 bytes, $37F3–$37F9)
; Calls the module code at the address in C3_ScratchF0 and returns
; with RTL: the kernel's way into module code. JSR (abs,X) with X = 0
; reads the pointer in the program bank, at $7E:00F0, which is the same
; WRAM as $00:00F0.
; Callers note: the kernel's C3_RunScript (JSL !C3Mod_CallW at
;   $C3:0C58, script opcode 0, which puts its operand in C3_ScratchF0).
; Entry: X=0 (LDX.w #0 is three bytes, A2 00 00: with X=1 the last
;        $00 would run as BRK), M as the called code wants, DP any, DB
;        any (C3_RunScript calls it with M=0, X=0, DB=$7E); the address
;        in C3_ScratchF0.
; Exit:  what the called code leaves, X included.
C3Mod_CallW:
    LDX.w #0
    JSR (!C3_ScratchF0,X)
    RTL

%C3ModOrg($7E37FA)
C3Mod_Rest37FA:
    %C3ModRomBytes($7E37FA, $7E3843)

; ============================================================
; Sprites hidden, the palette sent ($3843–$38AE)
; ============================================================

; $7E:3843 — C3Mod_HideSprites (45 bytes, $3843–$386F)
; Fills Oam_LowTable ($0700-$08FF) with C3_OamHideY by DMA channel 7
; from MPYL (M7A = 1, M7B = C3_OamHideY, so the product's low byte is
; C3_OamHideY): every byte $E0, so every sprite at X = Y = $E0, below
; the screen (the tile and attribute bytes $E0 too; the high table is
; not touched). M7B is set back to 0 after.
; Callers note: C3Mod_Init ($30F6).
; Entry: M=1, X=0, DP any, DB=$00 (absolute register stores).
; Exit:  M=1, X=0, DP and DB unchanged; A = MDMAEN_Ch7, X =
;        C3_OamLowBytes; Y unchanged; DMA channel 7's registers set.
%C3ModOrg($7E3843)
C3Mod_HideSprites:
    LDA.b #1
    STA.w M7A
    STZ.w M7A                           ; M7A = $0001
    LDA.b #!C3_OamHideY
    STA.w M7B
    STZ.w A1B7
    LDA.b #!BBAD_MPYL
    STA.w BBAD7
    LDX.w #!Oam_LowTable
    STX.w A1T7L
    LDX.w #!C3_OamLowBytes
    STX.w DAS7L
    LDA.b #!DMAP_BtoA
    STA.w DMAP7
    STA.w MDMAEN                        ; DMAP_BtoA = MDMAEN_Ch7, the same bit 7
    STZ.w M7B
    RTS

%C3ModOrg($7E3870)
C3Mod_Rest3870:
    %C3ModRomBytes($7E3870, $7E388B)

; $7E:388B — C3Mod_UploadPalette (36 bytes, $388B–$38AE)
; Sends the 256 colours of C3_PaletteBuf ($7E:2200) to CGRAM from
; colour 0, by DMA channel 7 (one register, CGDATA).
; Callers note: C3Mod_Start ($300D) and $8AC7, $8C97 (code not matched
;   yet).
; Entry: M=1, X=0, DP any, DB=$00 (absolute register stores).
; Exit:  M=1, X=0, DP and DB unchanged; A = MDMAEN_Ch7, X =
;        C3_PaletteBytes; Y unchanged; DMA channel 7's registers set.
%C3ModOrg($7E388B)
C3Mod_UploadPalette:
    LDA.b #0
    STA.w DMAP7
    STA.w CGADD
    LDA.b #bank(!C3_PaletteBuf)
    STA.w A1B7
    LDA.b #!BBAD_CGDATA
    STA.w BBAD7
    LDX.w #!C3_PaletteBuf&$FFFF
    STX.w A1T7L
    LDX.w #!C3_PaletteBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

%C3ModOrg($7E38AF)
C3Mod_Rest38AF:
    %C3ModRomBytes($7E38AF, $7E398A)

; ============================================================
; The task lists ($398A–$39F5)
; ============================================================

; $7E:398A — C3Mod_RunTasks (29 bytes, $398A–$39A6)
; Runs the frame's tasks: JSRs each nonzero word of C3_TaskRun (the
; copy C3_ModuleFrame makes of C3_TaskList) in turn, saving DB, X, P
; and DP around each, with M=0 and DP and DB as the frame left them.
; A task can leave by JMP to C3Mod_TaskEnd (it frees its own entry of
; C3_TaskList) or to C3Mod_TaskReplace (it puts the address in X
; there) instead of returning; both come back into this loop at
; C3Mod_TaskNext. A task
; that changes C3_TaskList changes what runs next frame, not this
; one (C3_TaskRun is the copy).
; Sub-entry: C3Mod_TaskNext ($399F), the next entry.
; Callers note: the kernel's C3_ModuleFrame (JSL !C3Mod_RunTasks,
;   $C3:0938). C3Mod_TaskNext: C3Mod_TaskEnd, C3Mod_TaskReplace and,
;   by a slip, C3Mod_NmiTaskReplace (BRA).
; Entry: M any (REP #$20 here), X=0 (16-bit index), DP and DB as the
;        tasks expect (C3_ModuleFrame: DP=0, DB=$00).
; Exit:  M=0, X=0; A = 0 (the last entry was free) or what the last
;        task left; X = C3_TaskListBytes; Y as the tasks leave it; DP
;        and DB as on entry (restored after each task).
C3Mod_RunTasks:
    REP #$20
    LDX.w #0
.task:
    LDA.w !C3_TaskRun,X
    BEQ C3Mod_TaskNext
    PHB
    PHX
    PHP
    PHD
    JSR (!C3_TaskRun,X)
    PLD
    PLP
    PLX
    PLB
C3Mod_TaskNext:                         ; header: see C3Mod_RunTasks
    INX
    INX
    CPX.w #!C3_TaskListBytes
    BNE C3Mod_RunTasks_task             ; C3Mod_RunTasks' .task
    RTL

; $7E:39A7 — C3Mod_TaskEnd (10 bytes, $39A7–$39B0)
; A task's way out, reached by JMP from the task's own level (with
; nothing of the task's left on the stack): drops the task's return
; address (C3Mod_RunTasks' JSR), pulls what C3Mod_RunTasks saved (DP,
; P, X, DB),
; clears the task's entry of C3_TaskList and goes on with the next
; task (C3Mod_TaskNext).
; Callers note: JMP from tasks, in code neither matched nor traced yet
;   (the tasks are reached through C3_TaskList): JMP byte patterns at
;   $3492, $34A8, $34E0, $34F8, $44F8, $48A6, $5BBB, $5BCB, $5CB7,
;   $5D47, $6ACA, $9A9F, $9B7B and $9EF9.
; Entry: JMP from a task run by C3Mod_RunTasks, with the stack as the
;        task found it (C3Mod_RunTasks' JSR return address on top: a JSR
;        here would push a second one and misalign the pulls); X=0
;        (the first PLX must pull that 2-byte address), M any; DP, DB
;        any (restored).
; Exit:  into C3Mod_TaskNext with P, X, DP and DB as C3Mod_RunTasks
;        saved them (M=0, X=0); A unchanged.
C3Mod_TaskEnd:
    PLX                                 ; drop the return address
    PLD
    PLP
    PLX
    PLB
    STZ.w !C3_TaskList,X
    BRA C3Mod_TaskNext

; $7E:39B1 — C3Mod_TaskReplace (13 bytes, $39B1–$39BD)
; As C3Mod_TaskEnd, but the task's entry of C3_TaskList gets the
; address in X instead (the task hands itself over to another, from
; next frame).
; Callers note: JMP from tasks, in code neither matched nor traced yet:
;   JMP byte patterns at $34BF (after LDX #$34C2), $427F, $476E, $485A,
;   $63F1, $6A71, $6A94, $6BF6 and $98A9.
; Entry: JMP from a task run by C3Mod_RunTasks, with the stack as the
;        task found it (C3Mod_RunTasks' JSR return address on top, as
;        for C3Mod_TaskEnd); X=0 (16-bit index: the address and the PLX
;        of the return address) with the new task's address in the X
;        register; M any; DP, DB any (restored).
; Exit:  into C3Mod_TaskNext with P, X, DP and DB as C3Mod_RunTasks
;        saved them (M=0, X=0); A = the new address.
C3Mod_TaskReplace:
    REP #$20
    TXA
    PLX                                 ; drop the return address
    PLD
    PLP
    PLX
    PLB
    STA.w !C3_TaskList,X
    BRA C3Mod_TaskNext

; $7E:39BE — C3Mod_RunNmiTasks (32 bytes, $39BE–$39DD)
; The NMI tasks: JSRs each nonzero word of C3_NmiTaskList (8 words,
; the list itself, not a copy) in turn, saving DB, X, P and DP around
; each, with M=1 and A = DP (TDC; C3_ModuleFrame's DP is 0). Ending
; or replacing an NMI task goes through C3Mod_NmiTaskEnd /
; C3Mod_NmiTaskReplace, which come back at C3Mod_NmiTaskNext.
; Sub-entry: C3Mod_NmiTaskNext ($39D6).
; Callers note: the kernel's C3_ModuleFrame (JSL !C3Mod_RunNmiTasks,
;   $C3:08F7), in the forced blank at the start of each frame.
;   C3Mod_NmiTaskNext: C3Mod_NmiTaskEnd (BRA).
; Entry: M any (REP #$20 here), X=0 (16-bit index), DP and DB as the
;        tasks expect (C3_ModuleFrame: DP=0, DB=$00).
; Exit:  M=0, X=0; A = 0 (the last entry was free) or what the last
;        task left; X = C3_NmiTaskListBytes; Y as the tasks leave it; DP
;        and DB as on entry (restored after each task).
C3Mod_RunNmiTasks:
    REP #$20
    LDX.w #0
.task:
    LDA.w !C3_NmiTaskList,X
    BEQ C3Mod_NmiTaskNext
    PHB
    PHX
    PHP
    PHD
    TDC
    SEP #$20
    JSR (!C3_NmiTaskList,X)
    PLD
    PLP
    PLX
    PLB
C3Mod_NmiTaskNext:                      ; header: see C3Mod_RunNmiTasks
    INX
    INX
    CPX.w #!C3_NmiTaskListBytes
    BNE C3Mod_RunNmiTasks_task          ; C3Mod_RunNmiTasks' .task
    RTL

; $7E:39DE — C3Mod_NmiTaskEnd (10 bytes, $39DE–$39E7)
; C3Mod_TaskEnd for an NMI task (reached by JMP the same way): clears
; its entry of C3_NmiTaskList and goes on with the next NMI task
; (C3Mod_NmiTaskNext).
; Callers note: JMP from NMI tasks, in code neither matched nor traced
;   yet: JMP byte patterns at $4674, $78A8, $7A32, $7A65, $8DF0, $8E85,
;   $9D22, $9F56 and $9F87.
; Entry: JMP from a task run by C3Mod_RunNmiTasks, with the stack as
;        the task found it (C3Mod_RunNmiTasks' JSR return address on
;        top: a JSR here would misalign the pulls); X=0 (the first PLX
;        must pull that 2-byte address), M any; DP, DB any (restored).
; Exit:  into C3Mod_NmiTaskNext with P, X, DP and DB as
;        C3Mod_RunNmiTasks saved them (M=0, X=0); A unchanged.
C3Mod_NmiTaskEnd:
    PLX                                 ; drop the return address
    PLD
    PLP
    PLX
    PLB
    STZ.w !C3_NmiTaskList,X
    BRA C3Mod_NmiTaskNext

; $7E:39E8 — C3Mod_NmiTaskReplace (13 bytes, $39E8–$39F4)
; C3Mod_TaskReplace for an NMI task (reached by JMP the same way): its
; entry of C3_NmiTaskList gets the address in X. Quirk: it then branches to C3Mod_TaskNext, the
; frame task loop, not to C3Mod_NmiTaskNext: the NMI tasks after it
; are skipped for this frame, and the C3_TaskRun entries after the
; replaced entry's index run instead, in the forced blank (C3_TaskRun
; still holds the previous frame's copy then: C3_ModuleFrame copies
; C3_TaskList after the NMI tasks), before the RTL; they run again
; later in the frame from C3Mod_RunTasks. Kept as it is (the bytes of
; the BRA say so: $80 $AA, to $399F).
; Callers note: none found: no JMP $39E8 byte pattern in the module.
;   It would be reached by JMP, as C3Mod_TaskReplace is.
; Entry: JMP from a task run by C3Mod_RunNmiTasks, with the stack as
;        the task found it (C3Mod_RunNmiTasks' JSR return address on
;        top); X=0 (16-bit index: the address and the PLX of the return
;        address) with the new task's address in the X register; M any;
;        DP, DB any (restored).
; Exit:  into C3Mod_TaskNext (see above) with P, X, DP and DB as
;        C3Mod_RunNmiTasks saved them (M=0, X=0); A = the new address.
C3Mod_NmiTaskReplace:
    REP #$20
    TXA
    PLX                                 ; drop the return address
    PLD
    PLP
    PLX
    PLB
    STA.w !C3_NmiTaskList,X
    BRA C3Mod_TaskNext

%C3ModOrg($7E39F5)
C3Mod_Rest39F5:
    %C3ModRomBytes($7E39F5, $7EB57F)

incsrc "unmatched.asm"
