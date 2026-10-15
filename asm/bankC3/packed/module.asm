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
; calls as an idle step and the script at $9450 adds as an NMI task
; (an empty one) and removes again.
; Callers note: C3Mod_Start ($3000). C3Mod_Return: C3Mod_Start
;   ($3023); the NMI task added by script opcode $F8 at $9453 and
;   removed by $F7 at $94C6 (script $9450, page $0A).
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
;        and pulled as words), DP = the page of C3Math_A.. (the
;        script's page at C3Mod_BuildM7Tables' calls $3591-$35E8, the
;        caller's own at C3Mod_MulSigned16's; the others' not traced),
;        DB any (saved); C3Math_A, C3Math_B = the operands.
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
;        left by 8, with the entry carry in bit 7 (the first ROL takes
;        it in, the next seven take in zeros); C3Math_Q = the divisor -
;        1; X, Y unchanged.
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
; Callers note: C3Mod_ViewOffsetTask ($4458, $446B) and $4E61, $4ECB,
;   $9939, $9953, $9B0A and $9B1D (code not matched yet).
; Entry: M=0, X=0 (C3Mod_Mul16's), DP = the page of C3Math_A.. ($0A00 at
;        C3Mod_ViewOffsetTask's calls; the others' not traced); DB any;
;        C3Math_A, C3Math_B = the signed operands.
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
; Entry: M, X, DP and DB as C3_RandomByte needs; X=0 at the calls, M=1
;        at $577A, $5780, $5786, $57B3, $57B9, $7397 and $80A6, M=0 at
;        $7F85, $7FA0, $80D3, $98E3 and $98EE (there C3_RandomByte's adds
;        are 16-bit, it stores a word to C3_RandSeed, and the callers
;        mask the result with an AND).
; Exit:  as C3_RandomByte leaves them (A = the new C3_RandSeed, a byte
;        or a word by M).
; Calls: C3_RandomByte (JSL).
C3Mod_KernelRandom:
    JSL !C3_RandomByte
    RTS

; $7E:3448 — C3Mod_TableRandom (25 bytes, $3448–$3460)
; The next byte of RandomTable: C3_RandIndex goes up by one (wrapping at
; 256; the AND #$FF after the INC changes nothing) and indexes the
; table. B is set to DP's low byte first (TDC / XBA), so that the TAX
; makes a 16-bit index of the byte: right only with DP on a page
; boundary ($0A00 at C3Mod_PickRun's call, the script's page; the
; others' not traced).
; Callers note: C3Mod_PickRun ($3F59, a script routine) and $65AE,
;   $65BF, $65C9, $728E and $9BE1 (code not matched yet).
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
; Callers note: C3Mod_BuildM7Tables ($357F), C3Mod_ViewOffsetTask
;   ($444F) and $4D19, $56B6, $5867, $5BD7, $5BFB, $5CBC, $73C9, $76DB,
;   $994A, $9990, $99DB and $9B01 (code not matched yet). C3Mod_Sine:
;   C3Mod_BuildM7Tables ($35B7), C3Mod_ViewOffsetTask ($4462) and
;   $4D26, $56C2, $585B, $5C11, $5CE0, $6014, $73BD, $73FD, $76FE,
;   $9930, $9983, $99BB and $9B14 (code not matched yet).
; Entry: M=0, X=0 (16-bit index), DP any, DB any (the read is long); A
;        = the angle (only bits 0-9 count).
; Exit:  A = the signed value; X = the angle AND C3_AngleMask entered
;        at C3Mod_Sine, (the angle + C3_QuarterTurn) AND C3_AngleMask
;        entered at C3Mod_Cosine; Y unchanged.
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
; Callers note: a task: LDX #C3Mod_FadeInTask / JSR $395E at $6BD8;
;   added by script opcode $FA at $3F29 (C3Mod_Prog0ScriptA), $554C,
;   $6399, $6905, $7C93, $918E, $933D, $9403, $9528 and $966B, removed
;   by $F9 at $92C1 and $961F (the others: code and scripts not
;   matched yet).
; Entry: a task (C3Mod_RunTasks): M=0 (8-bit set here), X=0, DP any, DB
;        = $00 (the variables are absolute).
; Exit:  RTS with M=1; A = C3_Brightness after a step, else as on entry
;        (the DEC of C3_FadeTimer loads nothing); at the end JMP
;        C3Mod_TaskEnd.
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
; Callers note: a task added by script opcode $FA at $41F6
;   (C3Mod_Prog0Finish), $423F (C3Mod_Prog0Quit), $9149, $91A0, $91F5,
;   $9280, $94E6 and $96CB, and by LDX #C3Mod_FadeOutTask / JSR $395E at
;   $63E8 (the others: code and scripts not matched yet).
; Entry: a task: M=0 (8-bit set here), X=0, DP any, DB = $00.
; Exit:  RTS with M=1; A = C3_FadeStep after a step, else as on entry;
;        at the end JMP C3Mod_TaskEnd.
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
; Callers note: a task added by script opcode $FA at $5B92 and by LDX
;   #C3Mod_MusicFadeTask / JSR $395E at $5BA9 (M=1; code and script not
;   matched yet).
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
; Callers note: a task added by script opcode $FA at $562F, $6978,
;   $727F, $7EC1, $931F and $95FE, by LDX #C3Mod_FadeOutExitTask / JSR
;   $395E at $4684 (C3Mod_RaceTask), and by LDX #C3Mod_FadeOutExitTask
;   / JMP C3Mod_TaskReplace at $6BF3 (the others: code and scripts not
;   matched yet).
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
; Exit:  C3_SqrtRoot = the root; A = A minus the sum taken, including
;        the failed last subtraction, so it has wrapped below 0
;        (16-bit); C clear; X, Y unchanged.
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
; VRAM fills at $3D9D (DMAP $09 to VMDATAL: fixed address, two
; registers, so whole words cleared), $5AEE (DMAP $08 to VMDATAL: one
; register, only the low bytes cleared) and $90B0 (DMAP/BBAD from Y:
; $1808 when entered at $90A7, $1809 from the callers of $90AA, at
; $8A50, $8A69 and $9F81); the $FF bytes around it have no reader found
; (probably fill bytes too).
C3Mod_FillBytes:
    db $FF, $00, $00, $FF

; $7E:350E — C3Mod_UnpackNibbles (46 bytes, $350E–$353B)
; Unpacks Y bytes of 4-bit pixels from $0C00 up into one byte per pixel
; at $7F:0200 (C3_BitmapSrc, through WMDATA): the low nibble first, then
; the high. It reads the bytes with PLA, the stack pointed at
; C3_NibbleStack ($0BFF) and saved in C3_StackSave meanwhile. An
; interrupt then pushes onto the bytes already read (and, near the
; start, into page $0B below $0C00, the second script page), which does
; little harm unless its handler's stack reaches further (the module
; calls it with the screen off, probably).
; Callers note: $53E1 (code not matched yet).
; Entry: M=1 (set here), X=0, DP any (saved; DP_PPU inside), DB = $00
;        (C3_StackSave is absolute); Y = the byte count (not 0).
; Exit:  M=1, X=0, DP restored, S restored; A = the last high nibble, X
;        = S as saved after the PHD (the entry S - 2), Y = 0; WMADD past
;        the pixels.
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
;        byte with B (A's high byte, as on entry) above it (TAX is
;        16-bit), Y = 0; WMADD past the bytes.
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

; ============================================================
; The mode-7 plane, packs, HDMA, script tasks ($355F–$3779)
; ============================================================

; $7E:355F — C3Mod_M7HdmaAB (7 bytes, $355F–$3565)
; Indirect HDMA tables (DMAP $43: M7A/M7B written twice each) for the
; mode-7 matrix that C3Mod_BuildM7Tables computes: 112 lines from
; C3_M7ABLines ($7E:F100), 112 from its second half, then the end.
; C3Mod_M7HdmaABNext ($3566) is the same one line later (+4 bytes). The
; HDMA records at $3D4A, $7B9C, $7BBB and $8FEA (in C3Mod_SetupHdma's
; lists) name $355F; no reader of $3566 was found.
C3Mod_M7HdmaAB:
    db !C3_HdmaRepeat112 : dw !C3_M7ABLines
    db !C3_HdmaRepeat112 : dw !C3_M7ABLines+!C3_M7HalfBytes
    db 0

; $7E:3566 — C3Mod_M7HdmaABNext (7 bytes, $3566–$356C)
; See C3Mod_M7HdmaAB.
C3Mod_M7HdmaABNext:
    db !C3_HdmaRepeat112 : dw !C3_M7ABLines+4
    db !C3_HdmaRepeat112 : dw !C3_M7ABLines+!C3_M7HalfBytes+4
    db 0

; $7E:356D — C3Mod_M7HdmaCD (7 bytes, $356D–$3573)
; As C3Mod_M7HdmaAB for M7C/M7D, from C3_M7CDLines ($7E:F488); named by
; the HDMA records at $3D4F, $7BA1, $7BC0 and $8FEF. C3Mod_M7HdmaCDNext
; ($3574) is one line later (no reader found).
C3Mod_M7HdmaCD:
    db !C3_HdmaRepeat112 : dw !C3_M7CDLines
    db !C3_HdmaRepeat112 : dw !C3_M7CDLines+!C3_M7HalfBytes
    db 0

; $7E:3574 — C3Mod_M7HdmaCDNext (7 bytes, $3574–$357A)
; See C3Mod_M7HdmaCD.
C3Mod_M7HdmaCDNext:
    db !C3_HdmaRepeat112 : dw !C3_M7CDLines+4
    db !C3_HdmaRepeat112 : dw !C3_M7CDLines+!C3_M7HalfBytes+4
    db 0

; $7E:357B — C3Mod_BuildM7Tables (270 bytes with its variants, $357B–$3688)
; Fills C3_M7ABLines / C3_M7CDLines with a mode-7 matrix per line for a
; plane turned by C3_M7Angle and seen in perspective: for each line,
; with a divisor X that steps from line to line (up, by default), M7A =
; M7D = the scaled cosine / X and M7B = -M7C = the scaled sine / X (the
; signs as the angle gives them): a ground plane in perspective,
; probably (the race track). The hardware
; divider does the divisions (DP = DP_CPU inside): each line starts the
; next division while it stores the last quotient.
; It is self-modifying, set up before the loop:
;   - the two dividends, C3_M7Scale's low byte x |cos| and x |sin|
;     (C3Mod_Mul16's low word), go into the LDA immediates .cos_dividend
;     and .sin_dividend;
;   - the BRA at .cos_sign gets offset 0 (the quotient is negated) or 4
;     (it is not), by the cosine's sign;
;   - the two STA operands .store_b / .store_c get M7B's and M7C's
;     columns in the order that puts the negated sine in M7C, by the
;     sine's sign;
;   - then the JSR at .setup calls the routine whose address the caller
;     wrote over its operand ($35FD; the assembled $0000 is
;     never called): C3Mod_Prog0Setup ($45B0), $801F, $8042 or $9B46
;     (not matched yet)
;     set the first divisor X and the first line's offset Y for their
;     view; $801F and $8042 also write the end offset over .end's CPY
;     operand ($3637).
; The loop's step is self-modifying too: the INX / NOP at .step can be
; INX / INX or DEX / DEX ($8066, $8051), NOP / INX ($45D1), or a BRA to
; one of the variants after the loop (a word of C3Mod_M7StepBranches):
;   - .blank_line: the next line all zeros (a blank line between each
;     two), X + 1;
;   - .double_d: this line's M7D doubled, X + 1;
;   - .stream_x: X = the next byte of a WRAM stream (WMDATA, set up by
;     $801F at $7E:E260): the distances come from a table;
;   - .copy_line: the next line a copy of this one, X + 2 (half the
;     vertical resolution).
; Quirk: the STX to WRDIVB writes 16 bits, so HTIMEL ($4207) gets X's
; high byte (0) each time.
; Callers note: JMP (a tail call) from $4306, $82F2 and $9AF0 (code not
;   matched yet; script routines, with their page as DP).
; Entry: M=0, X=0 (16-bit X and Y), DP = the script's page
;        (C3_M7Angle, C3_M7Scale; C3Math_A.. at $F0 of it), DB any
;        (set to $7E: PHK / PLB).
; Exit:  M=0, X=0, DP = DP_CPU (not restored), DB = $7E; Y = the end
;        offset; A = what the last line left: the negated quotient
;        stored by .store_c, or, after a variant at .step, 0
;        (.blank_line), the doubled M7D word (.double_d), the WMDATA
;        byte (.stream_x) or the copied M7C word (.copy_line); X = the
;        divisor the next line would take (stepped after the last
;        line, or the WMDATA byte with .stream_x); C3Math_A.. as
;        C3Mod_Mul16 leaves them.
; Calls: C3Mod_Cosine, C3Mod_Sine, C3Mod_Mul16, the setup routine (JSR
;   over a written operand).
C3Mod_BuildM7Tables:
    PHK
    PLB
    LDA.b !C3_M7Angle
    JSR C3Mod_Cosine
    BPL .cos_positive
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3Math_A
    LDA.b !C3_M7Scale
    AND.w #!Eng_LowByteMask
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo
    STA.w .cos_dividend+1
    LDA.w #!Op_BRA                      ; BRA +0: the negation runs
    BRA .set_cos_sign
.cos_positive:
    STA.b !C3Math_A
    LDA.b !C3_M7Scale
    AND.w #!Eng_LowByteMask
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo
    STA.w .cos_dividend+1
    LDA.w #!Op_BRA|((.store_a-.cos_negate)<<8)  ; BRA +4, over the negation
.set_cos_sign:
    STA.w .cos_sign
    LDA.b !C3_M7Angle
    JSR C3Mod_Sine
    BPL .sin_positive
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3Math_A
    LDA.b !C3_M7Scale
    AND.w #!Eng_LowByteMask
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo
    STA.w .sin_dividend+1
    LDA.w #!C3_M7CDLines-4
    STA.w .store_b+1                    ; the quotient to M7C
    LDA.w #!C3_M7ABLines-2
    STA.w .store_c+1                    ; its negation to M7B
    BRA .setup
.sin_positive:
    STA.b !C3Math_A
    LDA.b !C3_M7Scale
    AND.w #!Eng_LowByteMask
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo
    STA.w .sin_dividend+1
    LDA.w #!C3_M7ABLines-2
    STA.w .store_b+1                    ; the quotient to M7B
    LDA.w #!C3_M7CDLines-4
    STA.w .store_c+1                    ; its negation to M7C
.setup:
    JSR !C3_NoCall                      ; the caller's setup routine (operand written at run time)
    LDA.w #!DP_CPU
    TCD
    LDA.w .cos_dividend+1
    STA.b WRDIVL-!DP_CPU                ; and WRDIVH
.line:
    STX.b WRDIVB-!DP_CPU                ; cosine / X (and HTIMEL = 0: see above)
.sin_dividend:
    LDA.w #0                            ; written above
    STA.b WRDIVL-!DP_CPU
    INY
    INY
    INY
    LDA.b RDDIVL-!DP_CPU
    STX.b WRDIVB-!DP_CPU                ; sine / X
.cos_sign:
    BRA .cos_negate                     ; written above: +0 or +4
.cos_negate:
    EOR.w #!Eng_Invert16
    INC A
.store_a:
    STA.w !C3_M7ABLines-3,Y             ; M7A
    STA.w !C3_M7CDLines+2-3,Y           ; M7D
.cos_dividend:
    LDA.w #0                            ; written above
    STA.b WRDIVL-!DP_CPU
    INY
    LDA.b RDDIVL-!DP_CPU
.store_b:
    STA.w !Eng_PtrBase,Y                ; operand written above (M7B or M7C)
    EOR.w #!Eng_Invert16
    INC A
.store_c:
    STA.w !Eng_PtrBase,Y                ; operand written above (the other)
.step:
    INX                                 ; or another step (see above)
    NOP
.end:
    CPY.w #!C3_M7EndDefault             ; operand written by the setup routine
    BNE .line
    RTS
.blank_line:
    LDA.w #0
    STA.w !C3_M7ABLines,Y
    STA.w !C3_M7CDLines+2,Y
    LDA.w #0
    STA.w !C3_M7ABLines+2,Y
    LDA.w #0
    STA.w !C3_M7CDLines,Y
    INY
    INY
    INY
    INY
    INX
    BRA .end
.double_d:
    LDA.w !C3_M7CDLines+2-4,Y
    ASL A
    STA.w !C3_M7CDLines+2-4,Y
    INX
    BRA .end
.stream_x:
    LDA.l WMDATA
    AND.w #!Eng_LowByteMask
    TAX
    BRA .end
.copy_line:
    LDA.w !C3_M7ABLines-4,Y
    STA.w !C3_M7ABLines,Y
    STA.w !C3_M7CDLines+2,Y
    LDA.w !C3_M7ABLines+2-4,Y
    STA.w !C3_M7ABLines+2,Y
    LDA.w !C3_M7CDLines-4,Y
    STA.w !C3_M7CDLines,Y
    INX
    INX
    INY
    INY
    INY
    INY
    BRA .end

; $7E:3689 — C3Mod_M7StepBranches (8 bytes, $3689–$3690)
; The BRA instructions written over C3Mod_BuildM7Tables' .step (at
; $3634) to pick a variant: .blank_line, .double_d, .stream_x,
; .copy_line. $368D is copied there at $7A0C, $368F at $45C5; no
; reader of the first two was found.
C3Mod_M7StepBranches:
    dw !Op_BRA|((C3Mod_BuildM7Tables_blank_line-C3Mod_BuildM7Tables_end)<<8)
    dw !Op_BRA|((C3Mod_BuildM7Tables_double_d-C3Mod_BuildM7Tables_end)<<8)
    dw !Op_BRA|((C3Mod_BuildM7Tables_stream_x-C3Mod_BuildM7Tables_end)<<8)
    dw !Op_BRA|((C3Mod_BuildM7Tables_copy_line-C3Mod_BuildM7Tables_end)<<8)

; $7E:3691 — C3Mod_UnpackPack (25 bytes, $3691–$36A9)
; Unpacks a pack of C3Rom_PackPtrs (bank $FE) with Decomp_ToWram: X is
; the entry's offset (3 x its number); its long pointer goes to
; Decomp_Src / Decomp_SrcBank (two overlapping word copies). Where it
; goes, Decomp_Dest / Decomp_DestBank, is the caller's.
; Callers note: C3Mod_Prog0 ($3B69, $3B75, $3BEF), C3Mod_Prog0LoadGfx
;   ($3DBF, $3DD1, $3DEA, $3DF7, $3E19, $3E29, $3E39, $3E7D, $3E93,
;   $3EA9) and $53D2, $541B, $543A, $544A,
;   $5989, $599D, $59B9, $59C9, $59FA, $6259, $626B, $627F, $6295,
;   $62AA, $62B6, $62C2, $62D1, $6C3F, $78F2, $7905, $7945, $7987,
;   $7ADE, $7AFD, $7B0D, $8549, $857B, $8598, $85A5, $85C3, $85E4,
;   $85F0, $869B, $87B0, $87E9, $8A2C, $8A46, $8A5F, $8A78, $8A8A,
;   $8BE4, $8C48, $8C76, $8C8E, $8CF8, $8D04, $8D10, $8EF4, $8F04,
;   $8F14 and $8F2A (code not matched yet).
; Entry: M any (saved; M=1 at the calls), X=0 (16-bit offset), DP any,
;        DB any (Decomp_ToWram saves them; the stores are long); X = the
;        entry's offset; Decomp_Dest/DestBank set.
; Exit:  P restored; A, X, Y as Decomp_ToWram leaves them (restored);
;        Decomp_OutLen = the bytes written.
; Calls: Decomp_ToWram (JSL).
C3Mod_UnpackPack:
    PHP
    REP #$20
    LDA.l !C3Rom_PackPtrs,X
    STA.l !Decomp_Src
    LDA.l !C3Rom_PackPtrs+1,X
    STA.l !Decomp_Src+1                 ; and Decomp_SrcBank
    JSL !Decomp_ToWram
    PLP
    RTS

; $7E:36AA — C3Mod_CopyRawPack (34 bytes, $36AA–$36CB)
; Copies a block of bank $FE that C3Rom_PackPtrs points to, as it is
; (one of the raw entries): C3_CopyFEto7F when Decomp_DestBank bit 0 is
; set, else C3_CopyFEto7E, C3_RowCount bytes ($F0 of the caller's
; page) from the entry's address to Y. Only the pointer's low word is
; read: the bank is $FE.
; Callers note: $540A, $5488, $5493, $7963, $8663, $866C, $8675, $867E,
;   $868C, $8841, $884A, $8AC1, $8BFC, $8E0B, $8E14, $8ED6 and $8F42
;   (code not matched yet).
; Entry: M any (saved; M=1 at the calls but $7963's, M=0), X=0 (16-bit
;        X and Y), DP = the page of the count, DB = $00 or $7E (a bank
;        that maps low WRAM: LDA.w Decomp_DestBank is absolute; saved,
;        and the table read is long); X =
;        the entry's offset (3 x its number), Y = the destination,
;        C3_RowCount = the byte count (not 0), Decomp_DestBank bit 0 =
;        the WRAM bank.
; Exit:  P and DB restored; A = $FFFF; X, Y past the copied bytes.
; Calls: C3_CopyFEto7E or C3_CopyFEto7F (JSL).
C3Mod_CopyRawPack:
    PHP
    PHB
    REP #$20
    LDA.l !C3Rom_PackPtrs,X
    TAX
    LDA.w !Decomp_DestBank
    LSR A
    BCC .to_7e
    LDA.b !C3_RowCount
    DEC A
    JSL !C3_CopyFEto7F
    BRA .done
.to_7e:
    LDA.b !C3_RowCount
    DEC A
    JSL !C3_CopyFEto7E
.done:
    PLB
    PLP
    RTS

; $7E:36CC — C3Mod_SetupHdma (61 bytes, $36CC–$3708)
; Sets up HDMA channels from a list of 5-byte records at Y (in bank $7E),
; channel 0 first: DMAPn and BBADn, the table's address (A1TnL/H) and
; bank (A1Bn, and DASBn, the indirect bank), until a record whose first
; byte is $FF. The 16-bit stores also write DASnL with the next record's
; first byte and A2AnL with the byte after the bank, which HDMA sets
; itself. The bank is set with PEA $007E / PLB, which leaves a $00 on the
; stack that the final PLB takes back: DB is $00 at the exit, whatever
; it was.
; Callers note: C3Mod_Prog0 ($3C49) and $67AD, $70E0, $7A2A, $7A5D,
;   $8714, $8ACD, $8B12, $8DAF, $8E7D and $8F7D (code not matched yet).
; Entry: M=1 (M=0 set here), X=0, DP any (saved), DB any; Y = the list.
; Exit:  M=1, X=0, DP restored, DB = $00; A = $00FF (the end record's
;        first byte, ANDed with $FF before the CMP); X = 16 x the
;        channels set, Y = the end record.
C3Mod_SetupHdma:
    PHD
    PEA.w !DP_DMA
    PLD
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays (see above)
    PLB
    REP #$20
    LDX.w #0
.record:
    LDA.w !Eng_PtrBase,Y
    AND.w #!Eng_LowByteMask
    CMP.w #!C3_HdmaListEnd
    BEQ .done
    LDA.w !Eng_PtrBase,Y
    STA.b DMAP0-!DP_DMA,X               ; and BBADn
    LDA.w !Eng_PtrBase+2,Y
    STA.b A1T0L-!DP_DMA,X               ; and A1TnH
    LDA.w !Eng_PtrBase+4,Y
    STA.b A1B0-!DP_DMA,X                ; and DASnL (the next record's first byte)
    STA.b DAS0B-!DP_DMA,X               ; and A2AnL
    TXA
    CLC
    ADC.w #!C3_DmaChannelBytes
    TAX
    TYA
    CLC
    ADC.w #!C3_HdmaRecordBytes
    TAY
    BRA .record
.done:
    SEP #$20
    PLB                                 ; the $00 from the PEA
    PLD
    RTS

; $7E:3709 — C3Mod_HdmaAlternate (64 bytes, $3709–$3748)
; Writes an HDMA table through WMDATA (DP = DP_PPU: WMDATA as $80): 112
; pairs of one-line entries, the first with the bytes at C3_ScratchF0
; and $00F1, the second with $00F2 and $00F3 (two values on alternate
; lines), then the end byte. The four bytes are copied into the LDA
; immediates of its loop first (long stores into its own code). No
; caller was found (no call, stored address or table entry).
; Entry: M=1, X=0 (the 16-bit count load), DP = DP_PPU, DB = $00 or $7E
;        (the $00F0 reads are absolute); WMADD = where the table goes.
; Exit:  P restored (X high byte cleared by the SEP #$30: X = 0 after
;        the loop anyway); A = the byte copied from $00F3 (the last
;        LDA immediate; STZ writes the end), X = 0, Y = 1; WMADD past
;        the table.
C3Mod_HdmaAlternate:
    LDA.w !C3_ScratchF0
    STA.l .first_a+1
    LDA.w !C3_ScratchF0+1
    STA.l .first_b+1
    LDA.w !C3_ScratchF2
    STA.l .second_a+1
    LDA.w !C3_ScratchF2+1
    STA.l .second_b+1
    LDX.w #!C3_HdmaPairs
    LDY.w #!C3_HdmaOneLine
    PHP
    SEP #$30
.pair:
    STY.b WMDATA-!DP_PPU                ; one line
.first_a:
    LDA.b #0                            ; written above
    STA.b WMDATA-!DP_PPU
.first_b:
    LDA.b #0
    STA.b WMDATA-!DP_PPU
    STY.b WMDATA-!DP_PPU
.second_a:
    LDA.b #0
    STA.b WMDATA-!DP_PPU
.second_b:
    LDA.b #0
    STA.b WMDATA-!DP_PPU
    DEX
    BNE .pair
    STZ.b WMDATA-!DP_PPU                ; the end
    PLP
    RTS

; $7E:3749 — C3Mod_ScriptTaskA (11 bytes, $3749–$3753)
; A task, and a subroutine: runs the script of page $0A00 (DP = $0A00,
; DB = $7E, C3_RunScript) until it yields.
; Callers note: JSR from C3Mod_Prog0 ($3CD8) and $54B4, $5A0A, $62F0,
;   $6792, $70CE, $79AA, $86E6 and $8F94 (code not matched yet); a task:
;   the tables at $7EC7 and $7EDC (C3_TaskList), and the scripts'
;   opcode $FA at $3F1A (C3Mod_Prog0ScriptA), $4130 (C3Mod_Prog0Start),
;   $5540, $5B05, $6393, $6984, $7157, $931C, $932E and $93E3.
; Entry: M=0, X=0 (C3_RunScript's), DP any, DB any (both set here and
;        not restored: a task's are restored by C3Mod_RunTasks).
; Exit:  M=0, X=0, DP = $0A00, DB = $7E; A, X, Y as C3_RunScript leaves
;        them.
; Calls: C3_RunScript (JSL).
C3Mod_ScriptTaskA:
    LDA.w #!C3_ScriptPageA
    TCD
    PHK
    PLB
    JSL !C3_RunScript
    RTS

; $7E:3754 — C3Mod_ScriptTaskB (11 bytes, $3754–$375E)
; As C3Mod_ScriptTaskA, for the script of page $0B00.
; Callers note: JSR from $70D1 (code not matched yet); a task: the
;   tables at $7EC7 and $7EDC, and the scripts' opcode $FA at $3F1D
;   (C3Mod_Prog0ScriptA), $4133 (C3Mod_Prog0Start), $5543, $6987,
;   $715A and $9331.
; Entry: M=0, X=0, DP any, DB any (set here, not restored).
; Exit:  M=0, X=0, DP = $0B00, DB = $7E; A, X, Y as C3_RunScript leaves
;        them.
; Calls: C3_RunScript (JSL).
C3Mod_ScriptTaskB:
    LDA.w #!C3_ScriptPageB
    TCD
    PHK
    PLB
    JSL !C3_RunScript
    RTS

; $7E:375F — C3Mod_PlaySong (27 bytes, $375F–$3779)
; Plays the song in A: C3_SongReq and C3_SongCur = A (so C3_SongCheck
; sends nothing more), and Audio_CmdPlayMusic with it and arguments
; C3_SongArgs through Audio_DriverCommand.
; Callers note: C3Mod_Prog0 ($3B5A) and $5AA7 and $8FE6 (code not
;   matched yet).
; Entry: M any (8-bit set here), X=0 (the 16-bit argument store), DP
;        any, DB = $00 (the variables and the Audio_Cmd* block are
;        absolute); A = the song.
; Exit:  M=1, X=0; A, X as Audio_DriverCommand leaves them (X =
;        C3_SongArgs).
; Calls: Audio_DriverCommand (JSL).
C3Mod_PlaySong:
    SEP #$20
    STA.w !C3_SongReq
    STA.w !C3_SongCur
    STA.w !Audio_CmdArg0
    LDA.b #!Audio_CmdPlayMusic
    STA.w !Audio_CmdId
    LDX.w #!C3_SongArgs
    STX.w !Audio_CmdArg1                ; and Arg2
    JSL !Audio_DriverCommand
    RTS


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
;   $318F, $3197, $319F, $31AD JMP), C3Mod_ExitTask ($426D) and $4BC8,
;   $63E5 and $8EB2 (code not matched yet).
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
;   Its JSL callers each call C3Mod_UnpackPack ($3691) first (code not
; matched yet), which probably puts the picture at $7F:0200.
; Callers note: JSL from C3Mod_Prog0LoadGfx ($3DED, $3DFA) and $7908
;   and $87B3 (code not matched yet).
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

; $7E:37FA — C3Mod_PalAnimTask (17 bytes, $37FA–$380A)
; A task: runs the field's palette animations once a frame
; (FdVec_FFF7: PalAnim_TickAll), keeping the multiplier operands around
; the call: WRMPYA/WRMPYB are read into C3_ScratchF0 and written back
; after. Quirk: those registers are write-only, so the read gives open
; bus and the "restore" writes whatever it read (harmless unless a
; product was pending, probably).
; Callers note: JSR from $8319 and $8355 (code not matched yet); a task
;   added by the scripts' opcode $FA at $5B0B, $6396, $6993, $7D04,
;   $7EB3, $9334 and $93E9 (removed again by $F9 at $7D0C).
; Entry: a task: M=0 (8-bit set here), X=0, DP=0 (C3_ScratchF0 is
;        direct page), DB = $00 (the registers are absolute).
; Exit:  M=1, X=0; A, Y as PalAnim_TickAll leaves them; X =
;        C3_ScratchF0.
; Calls: FdVec_FFF7 (JSL).
C3Mod_PalAnimTask:
    SEP #$20
    LDX.w WRMPYA                        ; and WRMPYB (write-only: open bus)
    STX.b !C3_ScratchF0
    JSL !FdVec_FFF7
    LDX.b !C3_ScratchF0
    STX.w WRMPYA                        ; and WRMPYB
    RTS

; $7E:380B — C3Mod_OamUploadTask (56 bytes, $380B–$3842)
; An NMI task: closes the OAM high-table byte being filled
; (C3Mod_FinishOamHigh), sends all of OAM (Oam_LowTable and
; Oam_HighTable, C3_OamBytes) by DMA channel 7 from OAM address 0, then
; sets OAMADDH's priority-rotation bit with OAMADDL = C3_OamRotate (the
; sprite given the first priority, probably), and starts the next
; frame's sprites over: C3_OamPos = 0, C3_OamHiPtr = Oam_HighTable.
; Callers note: an NMI task added by the scripts' opcode $F8 at $3F2F,
;   $4145, $554F, $5B20, $639C, $699C, $7181, $7C73, $9325 and $93EC.
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0, DP=0 (C3_OamPos..
;        are direct page), DB = $00.
; Exit:  M=1, X=0; A = C3_OamRotate, X = Oam_HighTable.
; Calls: C3Mod_FinishOamHigh.
C3Mod_OamUploadTask:
    JSR C3Mod_FinishOamHigh
    LDX.w #0
    STX.w OAMADDL                       ; and OAMADDH
    STZ.w A1B7
    LDX.w #!BBAD_OAMDATA<<8             ; DMAP7 = 0 (one register), BBAD7 = OAMDATA
    STX.w DMAP7
    LDX.w #!Oam_LowTable
    STX.w A1T7L
    LDX.w #!C3_OamBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDA.b #!C3_OamPriorityRotate
    STA.w OAMADDH
    LDA.b !C3_OamRotate
    STA.w OAMADDL
    LDX.w #0
    STX.b !C3_OamPos
    LDX.w #!Oam_HighTable
    STX.b !C3_OamHiPtr
    RTS

; ============================================================
; Sprites hidden, the palette sent ($3843–$38AE)
; ============================================================

; $7E:3843 — C3Mod_HideSprites (45 bytes, $3843–$386F)
; Fills Oam_LowTable ($0700-$08FF) with C3_OamHideY by DMA channel 7
; from MPYL (M7A = 1, M7B = C3_OamHideY, so the product's low byte is
; C3_OamHideY): every byte $E0, so every sprite at X = Y = $E0, below
; the screen (the tile and attribute bytes $E0 too; the high table is
; not touched). M7B is set back to 0 after.
; Callers note: C3Mod_Init ($30F6); an NMI task (C3Mod_RunNmiTasks,
;   once a frame in vblank) added by script opcode $F8 at $3F32
;   (C3Mod_Prog0ScriptA), $4148 (C3Mod_Prog0Start), $5B23, $639F,
;   $7184, $7C76, $9328 and $93EF (the others: scripts not matched
;   yet).
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

; $7E:3870 — C3Mod_FinishOamHigh (27 bytes, $3870–$388A)
; Closes the Oam_HighTable byte at C3_OamHiPtr when fewer than 4
; sprites have been put in it: (C3_OamPos / 4) AND 3 sprites are in, and
; for each slot left it shifts in a %01 pair from the top (SEC / ROR /
; LSR: X bit 8 set, small size), so the unused sprites of the byte sit
; off screen. B is cleared first (TDC / XBA, with DP = 0) for the 16-bit
; TAX.
; Callers note: C3Mod_OamUploadTask ($380B) and $99A3 (code not matched
;   yet).
; Entry: M any (8-bit set here, not restored), X=0 (16-bit compare), DP=0
;        (C3_OamPos, C3_OamHiPtr), DB any (the pointer is direct-page
;        indirect, bank DB: $00 at the calls).
; Exit:  M=1, X=0; A = the byte; X = 4; Y unchanged.
C3Mod_FinishOamHigh:
    TDC
    XBA
    SEP #$20
    LDA.b !C3_OamPos
    LSR A
    LSR A
    AND.b #!C3_OamSlotMask
    TAX
    LDA.b (!C3_OamHiPtr)
.fill:
    CPX.w #!C3_OamSlotsPerByte
    BEQ .done
    INX
    SEC
    ROR A
    LSR A                               ; a %01 pair in at the top
    BRA .fill
.done:
    STA.b (!C3_OamHiPtr)
    RTS

; $7E:388B — C3Mod_UploadPalette (36 bytes, $388B–$38AE)
; Sends the 256 colours of C3_PaletteBuf ($7E:2200) to CGRAM from
; colour 0, by DMA channel 7 (one register, CGDATA).
; Callers note: C3Mod_Start ($300D) and $8AC7, $8C97 (code not matched
;   yet); an NMI task (C3Mod_RunNmiTasks, once a frame in vblank) added
;   by script opcode $F8 at $5B1D, $63A2, $6999, $717E, $7CF9, $7EB6,
;   $932B and $93F5, and removed by $F7 at $7D0F (scripts not matched
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

; $7E:38AF — C3Mod_CommitPalette (20 bytes, $38AF–$38C2)
; Copies the 512-byte palette at $7E:2000 (C3_PaletteWork) over
; C3_PaletteBuf ($7E:2200), the copy C3Mod_UploadPalette sends.
; Callers note: C3Mod_Prog0LoadGfx ($3DC2) and $59FD, $62EB, $796F,
;   $869E, $87A1, $8AC4, $8BFF, $8C94, $8E17 and $8F48 (code not
;   matched yet).
; Entry: M any (16-bit set here), X=0 (MVN's X and Y), DP any, DB any
;        (saved).
; Exit:  M=1, X=0, DB restored; A = 0 (the MVN's $FFFF + 1); X =
;        $2200, Y = $2400.
C3Mod_CommitPalette:
    REP #$20
    PHB
    LDX.w #!C3_PaletteWork&$FFFF
    LDY.w #!C3_PaletteBuf&$FFFF
    LDA.w #!C3_PaletteBytes-1
    MVN $7E,$7E                         ; lint-ok: MVN operands are bank bytes (WRAM bank $7E)
    INC A
    PLB
    SEP #$20
    RTS

; $7E:38C3 — C3Mod_DmaFromArgs (36 bytes, $38C3–$38E6)
; Runs a DMA on channel 7 described by C3_DmaMode.. at $00F0-$00F9:
; DMAP7 and BBAD7 from the bytes at $00F0 and $00F2, the A-bus address
; and bank from $00F4 / $00F6, the count from $00F8. RTL: called with
; JSL from the module.
; Callers note: JSL from $792F and $7933 (code not matched yet).
; Entry: M=1, X=0 (16-bit address and count), DP any, DB = $00 (the
;        arguments are read absolute, the registers written absolute).
; Exit:  M=1, X=0; A = MDMAEN_Ch7, X = the count; Y unchanged.
C3Mod_DmaFromArgs:
    LDA.w !C3_DmaMode
    STA.w DMAP7
    LDA.w !C3_DmaBbad
    STA.w BBAD7
    LDX.w !C3_DmaAddr
    STX.w A1T7L
    LDA.w !C3_DmaBank
    STA.w A1B7
    LDX.w !C3_DmaCount
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTL

; $7E:38E7 — C3Mod_DmaUnpacked (36 bytes, $38E7–$390A)
; As C3Mod_DmaFromArgs, but the A-bus side is what Decomp_ToWram just
; wrote: Decomp_Dest / Decomp_DestBank, Decomp_OutLen bytes (the mode
; and B-bus register from $00F0 / $00F2).
; Callers note: JSL from C3Mod_Prog0LoadGfx ($3DDD, $3E1C, $3E2C,
;   $3E3C, $3E86, $3E9C, $3EB2) and $53F7, $543D, $5996, $59A6, $59C2, $5AB2, $6278, $6288,
;   $6298, $6C48, $78FE, $7AF6, $7B06, $8586, $85D0, $8A39, $8A49,
;   $8A62, $8BE7, $8C51, $8EF7, $8F07, $8F1D and $8F2D (code not
;   matched yet; most right after C3Mod_UnpackPack).
; Entry: M=1, X=0, DP any, DB = $00.
; Exit:  M=1, X=0; A = MDMAEN_Ch7, X = Decomp_OutLen; Y unchanged.
C3Mod_DmaUnpacked:
    LDA.w !C3_DmaMode
    STA.w DMAP7
    LDA.w !C3_DmaBbad
    STA.w BBAD7
    LDX.w !Decomp_Dest
    STX.w A1T7L
    LDA.w !Decomp_DestBank
    STA.w A1B7
    LDX.w !Decomp_OutLen
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTL

; $7E:390B — C3Mod_SetM7Scroll (41 bytes, $390B–$3933)
; Writes BG1HOFS / BG1VOFS (the mode-7 scroll) and M7X / M7Y (the
; centre) from the direct page's bytes $02-$09 (script variables 1-4,
; C3Script_Vars + 2.. + 9, if DP is a script page, as the names
; assume), each register twice (low, then high byte). No caller was
; found (no call, stored address or script call), so the DP is an
; inference.
; Entry: M=1, X any, DP = the page of the values (a script page,
;        probably), DB = $00 (absolute register stores).
; Exit:  M=1; A = variable 4's high byte; X, Y unchanged.
C3Mod_SetM7Scroll:
    LDA.b !C3Script_Vars+2
    STA.w BG1HOFS
    LDA.b !C3Script_Vars+3
    STA.w BG1HOFS
    LDA.b !C3Script_Vars+4
    STA.w BG1VOFS
    LDA.b !C3Script_Vars+5
    STA.w BG1VOFS
    LDA.b !C3Script_Vars+6
    STA.w M7X
    LDA.b !C3Script_Vars+7
    STA.w M7X
    LDA.b !C3Script_Vars+8
    STA.w M7Y
    LDA.b !C3Script_Vars+9
    STA.w M7Y
    RTS

; $7E:3934 — C3Mod_TaskRemove (21 bytes, $3934–$3948)
; The module's copy of C3_TaskListRemove: clears the first word of
; C3_TaskList equal to X, searching without a bound (a value not in the
; list is searched for past its end).
; Callers note: $482E and $4879 (code not matched yet).
; Entry: M any (P saved; 16-bit set here), X=0, DP any, DB = $00 or $7E
;        (the list is absolute); X = the task's address.
; Exit:  P restored; A = the address, X = its offset in the list; Y
;        unchanged.
C3Mod_TaskRemove:
    PHP
    REP #$20
    TXA
    LDX.w #0
.find:
    CMP.w !C3_TaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    STZ.w !C3_TaskList,X
    PLP
    RTS

; $7E:3949 — C3Mod_NmiTaskRemove (21 bytes, $3949–$395D)
; As C3Mod_TaskRemove, for C3_NmiTaskList.
; Callers note: $9EF6 (code not matched yet).
; Entry: M any (P saved), X=0, DP any, DB = $00 or $7E; X = the task's
;        address.
; Exit:  P restored; A = the address, X = its offset; Y unchanged.
C3Mod_NmiTaskRemove:
    PHP
    REP #$20
    TXA
    LDX.w #0
.find:
    CMP.w !C3_NmiTaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    STZ.w !C3_NmiTaskList,X
    PLP
    RTS

; $7E:395E — C3Mod_TaskAdd (22 bytes, $395E–$3973)
; The module's copy of C3_TaskListAdd: X into the first free (zero)
; word of C3_TaskList, searched without a bound.
; Callers note: C3Mod_RaceTask ($4687) and $4834, $489D, $5BAC, $5D54,
;   $63EB, $6BDB and $6BE1 (code not matched yet).
; Entry: M any (P saved; 16-bit set here), X=0 (pushed and pulled as a
;        word), DP any, DB = $00 or $7E; X = the task's address.
; Exit:  P restored; A = the address, X = its offset; Y unchanged.
C3Mod_TaskAdd:
    PHP
    PHX
    LDX.w #0
    REP #$20
.find:
    LDA.w !C3_TaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    PLA
    STA.w !C3_TaskList,X
    PLP
    RTS

; $7E:3974 — C3Mod_NmiTaskAdd (22 bytes, $3974–$3989)
; As C3Mod_TaskAdd, for C3_NmiTaskList.
; Callers note: C3Mod_RaceTask ($46A1) and $4897, $48BD, $48D7, $8652
;   and $9C69 (code not matched yet).
; Entry: M any (P saved), X=0, DP any, DB = $00 or $7E; X = the task's
;        address.
; Exit:  P restored; A = the address, X = its offset; Y unchanged.
C3Mod_NmiTaskAdd:
    PHP
    PHX
    LDX.w #0
    REP #$20
.find:
    LDA.w !C3_NmiTaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    PLA
    STA.w !C3_NmiTaskList,X
    PLP
    RTS

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
; Callers note: JMP from tasks (reached through C3_TaskList; the trace
;   follows them): C3Mod_FadeInTask ($3492), C3Mod_FadeOutTask ($34A8),
;   C3Mod_FadeOutStopTask ($34E0), C3Mod_FadeOutExitTask ($34F8),
;   C3Mod_CountDownTask ($44F8), and $48A6, $5BBB, $5BCB, $5CB7,
;   $5D47, $6ACA, $9A9F, $9B7B and $9EF9 (code not matched yet).
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
; Callers note: JMP from tasks (the trace follows them):
;   C3Mod_MusicFadeTask ($34BF, after LDX #C3Mod_FadeOutStopTask),
;   C3Mod_ExitTask ($427F), C3Mod_WaitSongEndTask ($476E), and $485A,
;   $63F1, $6A71, $6A94, $6BF6 and $98A9 (code not matched yet).
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
; Callers note: JMP from NMI tasks (the trace follows them):
;   C3Mod_ClearColumnTask ($4674), and $7A32, $7A65, $8DF0, $8E85,
;   $9D22, $9F56 and $9F87 (code not matched yet); also a JMP byte
;   pattern at $78A8, right after the RTS at $78A7, which no trace
;   reaches (probably dead).
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

; ============================================================
; Sprites: a number, a list with mixed sizes ($39F5–$3B47)
; ============================================================

; $7E:39F5 — C3Mod_DrawNumber (136 bytes, $39F5–$3A7C)
; Draws C3_ScratchF0 as up to 5 decimal digits with C3_SprListSmall:
; the digits go into the tile bytes of C3Mod_NumberSprites (tile
; C3_DigitTile0 + the digit; its records place them right to left, 7
; pixels apart from C3_SprBaseX / C3_SprBaseY); the leading zeros are
; left out by the list's count (the ones digit always shows). The
; ten-thousands, thousands and hundreds come from subtraction loops, the
; tens and ones from the hardware divider (16-bit stores: WRDIVB's also
; writes HTIMEL with 0). DB is set to $7E for the list with PEA $007E /
; PLB, and to $00 for the sprite builder by the second PLB (the PEA's
; other byte).
; Callers note: $5187 and $51AE (code not matched yet).
; Entry: M=0, X any (8-bit set here), DP=0 (C3_ScratchF0, and
;        C3_SprListSmall's C3_OamPos..), DB any (left $00); C3_ScratchF0
;        = the number; C3_SprBaseX/Y = where its left end goes.
; Exit:  M=0, X=0, DB = $00; A, X, Y as C3_SprListSmall leaves them;
;        C3Mod_NumberSprites rewritten.
; Calls: C3_SprListSmall (JSL).
C3Mod_DrawNumber:
    LDA.b !C3_ScratchF0
    SEP #$10
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays for the second PLB
    PLB
    LDY.b #!C3_DigitTile0-1
.ten_thousands:
    SEC
    SBC.w #!C3_Dec10000
    INY
    BCS .ten_thousands
    ADC.w #!C3_Dec10000
    STY.w C3Mod_NumberSprites_ten_thousands
    LDY.b #!C3_DigitTile0-1
.thousands:
    SEC
    SBC.w #!C3_Dec1000
    INY
    BCS .thousands
    ADC.w #!C3_Dec1000
    STY.w C3Mod_NumberSprites_thousands
    LDY.b #!C3_DigitTile0-1
.hundreds:
    SEC
    SBC.w #!C3_Dec100
    INY
    BCS .hundreds
    ADC.w #!C3_Dec100
    STY.w C3Mod_NumberSprites_hundreds
    STA.l WRDIVL                        ; and WRDIVH
    LDA.w #!C3_Dec10
    STA.l WRDIVB                        ; and HTIMEL (0)
    SEP #$20
    LDY.w C3Mod_NumberSprites_ten_thousands
    LDX.b #!C3_NumberRecords+1
    NOP                                 ; (the divider's time)
    LDA.b #!C3_DigitTile0
    CLC
    ADC.l RDDIVL
    STA.w C3Mod_NumberSprites_tens
    LDA.l RDMPYL                        ; the remainder
    CLC
    ADC.b #!C3_DigitTile0
    STA.w C3Mod_NumberSprites_ones
    TYA
    CMP.b #!C3_DigitTile0
    BNE .count
    DEX                                 ; a leading zero: one record less
    LDA.w C3Mod_NumberSprites_thousands
    CMP.b #!C3_DigitTile0
    BNE .count
    DEX
    LDA.w C3Mod_NumberSprites_hundreds
    CMP.b #!C3_DigitTile0
    BNE .count
    DEX
    LDA.w C3Mod_NumberSprites_tens
    CMP.b #!C3_DigitTile0
    BNE .count
    DEX
.count:
    STX.w C3Mod_NumberSprites
    PLB                                 ; DB = $00
    REP #$30
    LDA.w #C3Mod_NumberSprites
    JSL !C3_SprListSmall
    RTS

; $7E:3A7D — C3Mod_NumberSprites (21 bytes, $3A7D–$3A91)
; C3Mod_DrawNumber's sprite list for C3_SprListSmall: the count (records
; + 1, written) and 5 records of tile (written), attribute, X, Y: the
; ones, tens, hundreds, thousands and ten-thousands, X = $1C down to 0.
C3Mod_NumberSprites:
    db 0
.ones:
    db 0, !C3_DigitAttr, $1C, 0
.tens:
    db 0, !C3_DigitAttr, $15, 0
.hundreds:
    db 0, !C3_DigitAttr, $0E, 0
.thousands:
    db 0, !C3_DigitAttr, $07, 0
.ten_thousands:
    db 0, !C3_DigitAttr, $00, 0

; $7E:3A92 — C3Mod_SprListMixedEnd (5 bytes, $3A92–$3A96)
; C3Mod_SprListMixed's exit, placed before its entry.
C3Mod_SprListMixedEnd:                  ; header: see C3Mod_SprListMixed
    REP #$20
    STY.b !C3_OamPos
    RTL

; $7E:3A97 — C3Mod_SprListMixed (177 bytes, $3A97–$3B47)
; Adds a list of sprites to the OAM shadow, like the kernel's
; C3_SprListSmall / C3_SprListLarge but with both sizes and signed
; offsets: the list (in bank $7E at A, read through WMDATA) is a byte n +
; 1, then n records of tile, attribute, X, Y. The attribute's bit 4
; (C3_SprLargeBit) picks the large size and is cleared in OAM (so the
; sprites have priority 0 or 2 only). X and Y are signed bytes added to
; C3_SprBaseX / C3_SprBaseY: an X below 0 gets X bit 8 set, an X from
; $100 up hides the sprite (Y = $E0; its X byte is not written, and its
; high-table bits are small, X bit 8 clear); a Y below 0 or from $E0 up
; becomes $E0 (below the screen). Each sprite's two high-table bits are
; shifted in at the top of the byte at C3_OamHiPtr, which moves on after
; every 4 sprites; C3_OamPos is stored back at the end, through
; C3Mod_SprListMixedEnd ($3A92), placed before the entry. The Y byte
; is read with a 16-bit LDA (WMDATA and the write-only WMADDL: open bus
; in the high byte, which the sign extension drops).
; Sub-entry: C3Mod_SprListMixedEnd, the exit (RTL).
; Callers note: JSL from $7F9C, $7FB0, $7FBF, $8386 and $9A6A (code not
;   matched yet).
; Entry: M=0 (A stored to WMADDL/M as a word), X=0 (16-bit Y), DP=0
;        (C3_OamPos.., C3_SprAttr), DB = $00-$3F (the ports and the
;        OAM shadow are absolute); A = the list's address.
; Exit:  RTL with M=0, X=0; Y = C3_OamPos (advanced); C3_OamHiPtr
;        advanced; C3_SprLeft = 0; C3_SprAttr = the last record's
;        attribute (unchanged for an empty list); A changed; WMADD after
;        the list.
C3Mod_SprListMixed:
    STA.w WMADDL                        ; and WMADDM
    LDY.b !C3_OamPos
    LDA.w #!Bank7E
    SEP #$20
    STA.w WMADDH
    LDA.w WMDATA
    STA.b !C3_SprLeft
.next:
    DEC.b !C3_SprLeft
    BEQ C3Mod_SprListMixedEnd
    LDA.w WMDATA
    STA.w !Oam_LowTable+2,Y             ; the tile
    LDA.w WMDATA
    STA.b !C3_SprAttr
    AND.b #!C3_SprLargeBit^$FF
    STA.w !Oam_LowTable+3,Y             ; the attribute
    LDA.w WMDATA                        ; X
    REP #$20
    ORA.w #!C3_SignExtend
    BIT.w #!C3_SignBit8
    BNE .x_signed
    AND.w #!Eng_LowByteMask
.x_signed:
    CLC
    ADC.b !C3_SprBaseX
    BMI .left
    CMP.w #!C3_ScreenRight
    BPL .off_right
    SEP #$20
    STA.w !Oam_LowTable,Y
    LDA.b !C3_SprAttr
    BIT.b #!C3_SprLargeBit
    BEQ .small
    LDA.b (!C3_OamHiPtr)
    LSR A
    SEC
    ROR A                               ; %10: large, X bit 8 clear
    BRA .high_bits
.small:
    LDA.b (!C3_OamHiPtr)
    LSR A
    LSR A                               ; %00
    BRA .high_bits
.left:
    SEP #$20
    STA.w !Oam_LowTable,Y
    LDA.b !C3_SprAttr
    BIT.b #!C3_SprLargeBit
    BEQ .left_small
    LDA.b (!C3_OamHiPtr)
    SEC
    ROR A
    SEC
    ROR A                               ; %11: large, X bit 8
    BRA .high_bits
.left_small:
    LDA.b (!C3_OamHiPtr)
    SEC
    ROR A
    LSR A                               ; %01: small, X bit 8
.high_bits:
    STA.b (!C3_OamHiPtr)
    REP #$20
    LDA.w WMDATA                        ; Y (the high byte: see above)
    ORA.w #!C3_SignExtend
    BIT.w #!C3_SignBit8
    BNE .y_signed
    AND.w #!Eng_LowByteMask
.y_signed:
    CLC
    ADC.b !C3_SprBaseY
    BMI .y_off
    CMP.w #!C3_SprHideY
    BMI .y_ok
.y_off:
    LDA.w #!C3_SprHideY
.y_ok:
    SEP #$20
.store_y:
    STA.w !Oam_LowTable+1,Y
    INY
    INY
    INY
    INY
    TYA
    AND.b #!C3_OamGroupMask
    BNE .same_byte
    INC.b !C3_OamHiPtr                  ; the next high-table byte after 4 sprites
.same_byte:
    JMP .next
.off_right:
    SEP #$20
    LDA.b (!C3_OamHiPtr)
    LSR A
    LSR A
    STA.b (!C3_OamHiPtr)
    LDA.w WMDATA                        ; the Y byte, unused
    LDA.b #!C3_SprHideY
    BRA .store_y

%C3ModOrg($7E3B48)
; ============================================================
; Program 0 (and 9): the set-up ($3B48–$3F13)
; ============================================================

; $7E:3B48 — C3Mod_Prog0 (509 bytes, $3B48–$3D44)
; The program of C3Mod_ProgramTable entries 0 and 9: sets up the race
; course scene and starts its scripts, then returns to C3Mod_Start.
;   - C3_Prog9 = 1 when C3_EntryArg bits 0-3 are not 0 (program 9);
;     unless C3_EntryNoSong, song C3_SongCourse (C3Mod_PlaySong);
;   - the graphics (C3Mod_Prog0LoadGfx, which also leaves
;     Decomp_DestBank = $7F); packs 2 and 3 unpacked to $7F:0A00 and
;     $7F:8A00; then, with DB = $7F (the MVN's): $7F:0A00-$37FF moved
;     to $3800 up (MVN), pack 3's four 8x8 blocks put into the 64-byte
;     rows from $3808 (the second one twice: C3Mod_CopyTileBlock), and
;     mirrored rows written through WMDATA (DP = DP_PPU; the row end in
;     C3_MirrorEnd, $7F:0200): 120 rows from $0A00 and $2C00 to
;     $7F:5A00, 72 from $3800 to $7800, then pack 4 (unpacked over pack
;     3 at $7F:8A00) as 96 rows to $AE00 (C3_MirrorLeft, $7F:0202,
;     counts the 12 calls);
;   - $7E:F000-$FFFF and $7E:0C00-$1DFF filled from MPYL by DMA (B to
;     A), so zeroed if M7A x M7B is 0 (C3Mod_Init's C3Mod_HideSprites
;     leaves M7A = 1, M7B = 0; not on the C3_BootIrqOn path, which
;     skips it); C3Scale_PrevEnd = $0A00; the HDMA channels of
;     C3Mod_Prog0Hdma (C3Mod_SetupHdma) and C3_HdmaEnable = channels
;     0-5; C3Mod_Prog0Vars;
;   - C3_EntryArg bit 6 clear: page $0A00 runs C3Mod_Prog0ScriptA and
;     $0B00 C3Mod_Prog0ScriptB, C3_HdmaEnable without channel 0 and
;     C3_StaffTextPtr = 0; set: the kernel's wipe set up (WinFx_C3E*:
;     table at $7E:E000, frame 0), wipe mode 2 written over
;     C3Mod_ExitTask's operand, the PPU windows (window 1 on BG1-BG4,
;     the sprites and the colour window, WH0 = 0, WH1 = $FF, WH2 = 0,
;     TMW = BG1-BG3 and OBJ, TSW = BG3), and page
;     $0A00 runs C3Mod_Prog0WipeA or C3Mod_Prog0WipeB in turn
;     (C3_StartCount bit 0) with $0B00 on C3Mod_Prog0WipeScriptB;
;     both: C3_FadeStep = C3_FadeTimer = 8;
;   - runs page $0A00's script once (C3Mod_ScriptTaskA: DP = $0A00,
;     DB = $7E until the PLB), writes C3Mod_Prog0Setup over
;     C3Mod_BuildM7Tables' setup call ($35FD) and C3Mod_Unk51D1 over
;     C3Mod_Start's idle call ($3024);
;   - builds the copy code at $7E:B574 (C3_BuildCopyCode, X = $0C00,
;     Y = $0200), sets the BG maps and tiles (BG1SC = $60, BG2SC =
;     $64, BG3SC = $68, BG12NBA = BG34NBA = $77), CGWSEL = add the sub
;     screen, TM = BG1-BG3 and OBJ, TS = BG3, and saves the low bytes
;     of 20 VRAM words from $0B00, 128 words apart (VMAIN = +128 after
;     the low byte), to C3_MapColumnSave by DMA (B to A, RDVRAML): a
;     column of the mode-7 map, which C3Mod_ClearColumnTask and
;     C3Mod_RestoreColumnTask rewrite.
; Callers note: C3Mod_ProgramTable entries 0 and 9 (C3Mod_Start's JSR
;   (table,X) at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs);
;        C3_EntryArg as the module was entered with.
; Exit:  M=1, X=0, DP=0, DB=$00 (C3_BuildCopyCode's); A = MDMAEN_Ch7,
;        X = C3_MapColumnBytes, Y = $0010 (C3_BuildCopyCode's).
; Calls: C3Mod_PlaySong, C3Mod_Prog0LoadGfx, C3Mod_UnpackPack,
;   C3Mod_CopyTileBlock, C3Mod_MirrorRows3, C3Mod_MirrorRows,
;   C3Mod_SetupHdma, C3Mod_Prog0Vars, C3Mod_ScriptTaskA,
;   C3_BuildCopyCode (JSL).
C3Mod_Prog0:
    LDA.w !C3_EntryArg
    AND.b #!C3_EntryLowNibble
    BEQ .prog0
    INC.b !C3_Prog9
.prog0:
    LDA.w !C3_EntryArg
    BIT.b #!C3_EntryNoSong
    BNE .no_song
    LDA.b #!C3_SongCourse
    JSR C3Mod_PlaySong
.no_song:
    JSR C3Mod_Prog0LoadGfx
    LDX.w #!C3_Prog0PicsA
    STX.w !Decomp_Dest
    LDX.w #2*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0PicsB
    STX.w !Decomp_Dest
    LDX.w #3*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    REP #$20
    LDX.w #!C3_Prog0PicsA
    LDY.w #!C3_Prog0PicsMoved
    LDA.w #!C3_Prog0PicsBytes-1
    PHB
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    LDX.w #!C3_Prog0PicsB
    LDY.w #!C3_Prog0PicsMoved+8
    JSR C3Mod_CopyTileBlock
    PHX
    LDY.w #!C3_Prog0PicsMoved+$608
    JSR C3Mod_CopyTileBlock
    PLX                                 ; the same block again
    LDY.w #!C3_Prog0PicsMoved+$C08
    JSR C3Mod_CopyTileBlock
    LDY.w #!C3_Prog0PicsMoved+$140C
    JSR C3Mod_CopyTileBlock
    LDY.w #!C3_Prog0PicsMoved+$1A0C
    JSR C3Mod_CopyTileBlock
    SEP #$20
    PHD
    PEA.w !DP_PPU
    PLD
    LDA.b #!WMADDH_Bank7F
    STA.b WMADDH-!DP_PPU
    LDX.w #!C3_MirrorEnd32
    STX.w !C3_MirrorEnd                 ; $7F:0200 (DB = $7F)
    LDX.w #!C3_Prog0MirrorA
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDY.w #!C3_Prog0PicsA
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    LDY.w #!C3_Prog0PicsA+$2200
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    LDX.w #!C3_Prog0MirrorB
    STX.b WMADDL-!DP_PPU
    LDY.w #!C3_Prog0PicsMoved
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    LDX.w #!C3_MirrorEnd24
    STX.w !C3_MirrorEnd
    LDX.w #4*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0MirrorC
    STX.b WMADDL-!DP_PPU
    LDY.w #!C3_Prog0PicsB
    LDA.b #!C3_Prog0MirrorCalls
    STA.w !C3_MirrorLeft                ; $7F:0202
.mirror:
    JSR C3Mod_MirrorRows
    DEC.w !C3_MirrorLeft
    BNE .mirror
    PLD
    PLB
    LDX.w #!BBAD_MPYL<<8|!DMAP_BtoA
    STX.w DMAP7                         ; and BBAD7
    LDX.w #!C3_M7Tables&$FFFF
    STX.w A1T7L
    LDA.b #bank(!C3_M7Tables)
    STA.w A1B7
    LDX.w #!C3_M7TablesBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!BBAD_MPYL<<8|!DMAP_BtoA
    STX.w DMAP7
    LDX.w #!C3_Prog0Clear
    STX.w A1T7L
    LDA.b #!Bank7E
    STA.w A1B7
    LDX.w #!C3_Prog0ClearBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_Prog0PicsA
    STX.b !C3Scale_PrevEnd
    LDY.w #C3Mod_Prog0Hdma
    JSR C3Mod_SetupHdma
    LDA.b #!C3_Prog0HdmaOn
    STA.w !C3_HdmaEnable
    JSR C3Mod_Prog0Vars                 ; returns with M=0
    LDA.w !C3_EntryArg
    BIT.w #!C3_EntryWipeStart
    BNE .wipe_start
    LDA.w #C3Mod_Prog0ScriptA
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    LDA.w #C3Mod_Prog0ScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
    LDA.w #!C3_Prog0Fade
    STA.w !C3_FadeStep                  ; and C3_FadeTimer
    SEP #$20
    LDA.b #!C3_Prog0HdmaNoWipe
    STA.w !C3_HdmaEnable
    REP #$20
    STZ.w !C3_StaffTextPtr
    BRA .run_script
.wipe_start:
    LDA.w #!C3_Prog0Fade
    STA.w !C3_FadeStep
    LDA.w #!Bank7E
    STA.w !WinFx_C3ETableBank           ; and its high byte
    LDX.w #!C3_WipeTable&$FFFF
    STX.w !WinFx_C3ETablePtr
    STZ.w !WinFx_WipeFrame              ; and WinFx_C3ETablePtr's low byte (0 already)
    SEP #$20
    LDA.b #!WinFx_C3EMode2
    STA.l C3Mod_ExitTask_wipe_mode+1
    REP #$20
    LDA.w #!W12SEL_Bg12Win1             ; each store also zeroes the next register,
    STA.w W12SEL                        ; which the next store rewrites:
    STA.w W34SEL                        ; window 1 on BG1-BG4,
    STA.w WOBJSEL                       ; the sprites and the colour window; WH0 = 0
    LDA.w #!WH_RightEdge
    STA.w WH1                           ; and WH2 = 0
    LDX.w #!Layer_Bg123Obj|(!Layer_Bg3<<8)
    STX.w TMW                           ; and TSW
    LDA.w !C3_StartCount
    INC A
    STA.w !C3_StartCount
    LSR A
    BCS .wipe_b
    LDA.w #C3Mod_Prog0WipeA
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    LDA.w #C3Mod_Prog0WipeScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
    BRA .run_script
.wipe_b:
    LDA.w #C3Mod_Prog0WipeB
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    LDA.w #C3Mod_Prog0WipeScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
.run_script:
    PHB
    JSR C3Mod_ScriptTaskA
    LDA.w #C3Mod_Prog0Setup
    STA.w C3Mod_BuildM7Tables_setup+1   ; DB = $7E here
    LDA.w #C3Mod_Unk51D1
    STA.w C3Mod_Start_wait_exit+1
    PLB
    SEP #$20
    LDA.b #!Bank7E
    STA.w WMADDH
    LDX.w #!C3_CopyCode&$FFFF
    STX.w WMADDL                        ; and WMADDM
    LDX.w #!C3_CopyCodeDest
    LDY.w #!C3_CopyCodeSrc
    JSL !C3_BuildCopyCode
    LDX.w #!C3_Prog0Bg1Sc|(!C3_Prog0Bg2Sc<<8)
    STX.w BG1SC                         ; and BG2SC
    LDA.b #!C3_Prog0Bg3Sc
    STA.w BG3SC
    LDA.b #!C3_Prog0Tiles
    STA.w BG12NBA
    STA.w BG34NBA
    LDA.b #!CGWSEL_AddSubscreen
    STA.w CGWSEL
    LDX.w #!Layer_Bg123Obj|(!Layer_Bg3<<8)
    STX.w TM                            ; and TS
    LDA.b #!VMAIN_Inc128
    STA.w VMAIN
    LDX.w #!C3_MapColumn
    STX.w VMADDL
    LDX.w #!BBAD_RDVRAML<<8|!DMAP_BtoA
    STX.w DMAP7
    LDX.w #!C3_MapColumnSave&$FFFF
    STX.w A1T7L
    LDA.b #bank(!C3_MapColumnSave)
    STA.w A1B7
    LDX.w #!C3_MapColumnBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

; $7E:3D45 — C3Mod_Prog0Hdma (31 bytes, $3D45–$3D63)
; Program 0's HDMA channels, records for C3Mod_SetupHdma (DMAP, BBAD,
; table, bank), channel 0 first:
;   0: indirect, WH0: C3Mod_WipeHdmaA (C3Mod_WipeTask switches it);
;   1: indirect, M7A/M7B: C3Mod_M7HdmaAB;
;   2: indirect, M7C/M7D: C3Mod_M7HdmaCD;
;   3: indirect, two registers twice (BG1HOFS/BG1VOFS):
;      C3Mod_ScrollHdma;
;   4: indirect, two registers (CGADSUB/COLDATA): C3Mod_MathHdma;
;   5: indirect, BGMODE: C3Mod_ModeHdma;
; then the end byte.
C3Mod_Prog0Hdma:
    db !DMAP_HdmaIndirect, !BBAD_WH0 : dw C3Mod_WipeHdmaA : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7A : dw C3Mod_M7HdmaAB : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7C : dw C3Mod_M7HdmaCD : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_BG1HOFS : dw C3Mod_ScrollHdma : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegs, !BBAD_CGADSUB : dw C3Mod_MathHdma : db !Bank7E
    db !DMAP_HdmaIndirect, !BBAD_BGMODE : dw C3Mod_ModeHdma : db !Bank7E
    db !C3_HdmaListEnd

; $7E:3D64 — C3Mod_WipeHdmaA (7 bytes, $3D64–$3D6A)
; Indirect HDMA table for WH0 (window 1's left edge): 112 lines from
; $7E:E000 and 112 from $E070, one byte a line (the table the kernel's
; wipe, WinFx_StepWipe, writes on odd frames), then the end.
C3Mod_WipeHdmaA:
    db !C3_HdmaRepeat112 : dw !C3_WipeTable&$FFFF
    db !C3_HdmaRepeat112 : dw (!C3_WipeTable&$FFFF)+(!C3_WipeHalf)
    db 0

; $7E:3D6B — C3Mod_WipeHdmaB (7 bytes, $3D6B–$3D71)
; The same for the second buffer, $7E:E0E0 (WinFx_Lines on: even
; frames).
C3Mod_WipeHdmaB:
    db !C3_HdmaRepeat112 : dw (!C3_WipeTable&$FFFF)+(2*!C3_WipeHalf)
    db !C3_HdmaRepeat112 : dw (!C3_WipeTable&$FFFF)+(3*!C3_WipeHalf)
    db 0

; $7E:3D72 — C3Mod_WipeTask (26 bytes, $3D72–$3D8B)
; A task: one frame of the kernel's wipe (BankC3_Entry000E, i.e.
; WinFx_StepWipe, with the WinFx_C3E* arguments C3Mod_Prog0 set), then
; points HDMA channel 0's table (A1T0L) by WinFx_WipeFrame's parity:
; C3Mod_WipeHdmaA when it is odd, else C3Mod_WipeHdmaB.
; Callers note: a task added by script opcode $FA at $413F
;   (C3Mod_Prog0Start).
; Entry: a task (C3Mod_RunTasks): M=0, X=0, DP=0, DB=$00 (WinFx_StepWipe
;        restores what it saves; the stores are absolute).
; Exit:  RTS with M=1, X=0; A = WinFx_WipeFrame / 2, X = the table's
;        address; Y as WinFx_StepWipe leaves it (restored).
; Calls: BankC3_Entry000E (JSL).
C3Mod_WipeTask:
    JSL !BankC3_Entry000E
    SEP #$20
    LDA.w !WinFx_WipeFrame
    LSR A
    BCC .even
    LDX.w #C3Mod_WipeHdmaA
    STX.w A1T0L
    RTS
.even:
    LDX.w #C3Mod_WipeHdmaB
    STX.w A1T0L
    RTS

; $7E:3D8C — C3Mod_Prog0LoadGfx (299 bytes, $3D8C–$3EB6)
; Program 0's graphics, all with the screen off (the NMI is not on
; yet):
;   - VRAM words $4000-$47FF cleared (DMA of a fixed zero word,
;     C3Mod_FillBytes + 1, to VMDATAL/H; the sprite tiles, OBSEL
;     C3_Obsel);
;   - pack 5 to C3_PaletteWork ($00:2000, Decomp_DestBank = 0) and
;     C3Mod_CommitPalette;
;   - C3Mod_Unk89ED: Decomp_Dest = $7F:0200 (C3_BitmapSrc) for the
;     rest; pack 7 to VRAM's high bytes from word 0 (VMAIN = $80 as
;     left by the clear: C3_DmaMode 0, C3_DmaBbad VMDATAH: the mode-7
;     tiles), packs 8 and 9 each doubled in height (C3Mod_DoubleRows)
;     and sent by C3Mod_Unk8752 (from VMADD 0 on; probably the mode-7
;     map in the low bytes, not traced);
;   - VMAIN = $80, two registers (VMDATAL/H): packs 13 and 14 to words
;     $7000 and $7100 (the BG tiles, BG12NBA = BG34NBA = $77), pack 6
;     to $5000 (the sprites' second tile page);
;   - $7E:E100-$E13F zeroed (a word stored, then an overlapping MVN),
;     $7F:0300-$09FF filled from MPYL by DMA (B to A; 0 if M7A x M7B
;     is, as C3Mod_Prog0's fills);
;   - the first $800 bytes (Decomp_OutLen set) of pack 10 to word
;     $6000, of pack 12 to $6800 and of pack 11 to $6400 (the maps of
;     BG1, BG3 and BG2: BG1SC $60, BG3SC $68, BG2SC $64).
; Callers note: C3Mod_Prog0 ($3B5D).
; Entry: M=1, X=0, DP with a low byte of 0 (the TDC that makes
;        C3_DmaMode 0; DP=0 at the call; the DMA arguments are
;        absolute), DB=$00 (absolute register and RAM stores).
; Exit:  M=1, X=0, DP and DB unchanged (the MVN's DB restored);
;        Decomp_DestBank = $7F, Decomp_Dest = C3_BitmapSrc;
;        C3_DmaMode = DMAP_TwoRegs, C3_DmaBbad = VMDATAL; A =
;        MDMAEN_Ch7, X = Decomp_OutLen ($0800), Y = $E140 (past the
;        MVN; Decomp_ToWram restores it).
; Calls: C3Mod_UnpackPack, C3Mod_CommitPalette, C3Mod_Unk89ED,
;   C3Mod_DmaUnpacked (JSL), C3Mod_DoubleRows (JSL), C3Mod_Unk8752.
C3Mod_Prog0LoadGfx:
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    LDX.w #!BBAD_VMDATAL<<8|!DMAP_FixedSource|!DMAP_TwoRegs
    STX.w DMAP7                         ; and BBAD7
    LDX.w #C3Mod_FillBytes+1            ; the zero word
    STX.w A1T7L
    LDA.b #!Bank7E
    STA.w A1B7
    LDX.w #!C3_SprTilesBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    STZ.w !Decomp_DestBank
    LDX.w #!C3_PaletteWork&$FFFF
    STX.w !Decomp_Dest
    LDX.w #5*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSR C3Mod_CommitPalette
    JSR C3Mod_Unk89ED
    LDX.w #0
    STX.w VMADDL
    LDX.w #7*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    TDC                                 ; A = 0 (DP = 0 at the call)
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAH
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDX.w #0
    STX.w VMADDL
    LDX.w #8*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DoubleRows
    JSR C3Mod_Unk8752
    LDX.w #9*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DoubleRows
    JSR C3Mod_Unk8752
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    LDX.w #!C3_Prog0BgTiles
    STX.w VMADDL
    LDX.w #13*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog0BgTiles+$100
    STX.w VMADDL
    LDX.w #14*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_SprTilesHigh
    STX.w VMADDL
    LDX.w #6*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    REP #$20
    LDX.w #!C3_WipeTable+$100&$FFFF
    TXY
    INY
    LDA.w #0
    STA.l !Eng_PtrBase|(!Bank7E<<16),X
    LDA.w #!C3_WipeClearBytes-2
    PHB
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes
    PLB
    SEP #$20
    LDX.w #!BBAD_MPYL<<8|!DMAP_BtoA
    STX.w DMAP7
    LDX.w #!C3_Prog0Clear7F&$FFFF
    STX.w A1T7L
    LDA.b #!Bank7F
    STA.w A1B7
    LDX.w #!C3_Prog0Clear7FBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_Prog0Bg1Map
    STX.w VMADDL
    LDX.w #10*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0MapBytes
    STX.w !Decomp_OutLen
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog0Bg3Map
    STX.w VMADDL
    LDX.w #12*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0MapBytes
    STX.w !Decomp_OutLen
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog0Bg2Map
    STX.w VMADDL
    LDX.w #11*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0MapBytes
    STX.w !Decomp_OutLen
    JSL C3Mod_DmaUnpacked
    RTS

; $7E:3EB7 — C3Mod_CopyTileBlock (22 bytes, $3EB7–$3ECC)
; Copies a block of 8 rows of 8 bytes, stored one after the other at X,
; into a bitmap of 64-byte rows at Y (MVN in bank $7F, Y moved on by
; $38 after each row's 8).
; Callers note: C3Mod_Prog0 ($3B8D, $3B94, $3B9B, $3BA1, $3BA7).
; Entry: M=0, X=0 (MVN's 16-bit X and Y), DP = the page of C3_RowsLeft
;        (0 at the calls), DB any; X = the block, Y = where its first
;        row goes.
; Exit:  M=0, X=0, DB = $7F (the MVN's, not restored); A = Y = Y + 8 x
;        $40, X = X + 64; C3_RowsLeft = 0.
C3Mod_CopyTileBlock:
    LDA.w #!C3_TileRows
    STA.b !C3_RowsLeft
.row:
    LDA.w #!C3_TileRowBytes-1
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    TYA
    CLC
    ADC.w #!C3_RowBytes-!C3_TileRowBytes
    TAY
    DEC.b !C3_RowsLeft
    BNE .row
    RTS

; $7E:3ECD — C3Mod_MirrorRows3 (6 bytes with C3Mod_MirrorRows, $3ECD–$3F13)
; C3Mod_MirrorRows three times (JSR, JSR, and falling in): 24 rows.
; C3Mod_MirrorRows ($3ED3) writes 8 rows of 64 bytes through WMDATA,
; each the 32 bytes at Y + C3_MirrorEnd down to Y + C3_MirrorEnd - 31
; (read right to left: a 32-pixel row mirrored, if the bytes are
; pixels) and then 32 zero bytes; Y moves on by 64 (C3_RowBytes) per
; row. C3_MirrorEnd ($0200 of the source bank) is $20 or $18 at
; C3Mod_Prog0's calls.
; Callers note: C3Mod_Prog0 ($3BC3, $3BC6, $3BC9, $3BCF, $3BD2, $3BDD,
;   $3BE0, $3BE3). C3Mod_MirrorRows: C3Mod_Prog0 ($3BFF),
;   C3Mod_MirrorRows3 ($3ECD, $3ED0) and $8813, $8816 (code not matched
;   yet).
; Entry: M=1, X=0 (16-bit X and Y), DP = DP_PPU (WMDATA as $80), DB =
;        the source's bank ($7F at C3Mod_Prog0's calls: C3_MirrorEnd
;        and the rows are absolute); Y = the first source row; WMADD
;        = where the rows go.
; Exit:  M=1, X=0, DP and DB unchanged; A = Y (the last row's TYA /
;        ADC, 16-bit), X = 0, Y = Y + 8 x 64 per call (24 x 64 for
;        C3Mod_MirrorRows3); WMADD past the rows.
C3Mod_MirrorRows3:
    JSR C3Mod_MirrorRows
    JSR C3Mod_MirrorRows
C3Mod_MirrorRows:                       ; header: see C3Mod_MirrorRows3
    LDX.w #!C3_TileRows
.row:
    PHX
    REP #$20
    TYA
    CLC
    ADC.w !C3_MirrorEnd
    TAX
    SEP #$20
    PHY
    LDY.w #!C3_MirrorBytes
.byte:
    LDA.w !Eng_PtrBase,X
    STA.b WMDATA-!DP_PPU
    DEX
    DEY
    BNE .byte
    PLY
    LDX.w #!C3_MirrorBytes/8
    TDC                                 ; A = 0 (DP_PPU's low byte)
.zeros:
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    DEX
    BNE .zeros
    REP #$21                            ; and C = 0
    TYA
    ADC.w #!C3_RowBytes
    TAY
    SEP #$20
    PLX
    DEX
    BNE .row
    RTS

; ============================================================
; Program 0's scripts and tasks ($3F14–$4318)
; ============================================================
; The scripts are C3_RunScript's (opcodes !C3Op_*, module.inc). Page
; $0A00's variables steer the mode-7 view (C3_View*: 0 the scale, 1 the
; X position, 2 the distance, 5 the angle, 6 the horizon line, 8 the
; first divisor, 9 the X speed, 11 the step mode, as the tasks below
; read them); page $0B00's variable 2 is the view's Y (C3_ViewY). A
; loop opcode runs its body limit + 1 times (counter 0 first).

; $7E:3F14 — C3Mod_Prog0ScriptA (69 bytes, $3F14–$3F58)
; Page $0A00's first script (C3_EntryArg bit 6 clear): adds the frame
; tasks (C3Mod_ViewTask, C3Mod_PadDelayTask, both scripts' tasks,
; C3Mod_TurnTask, C3Mod_Unk4F54, C3Mod_Unk4D0D, C3Mod_FadeInTask,
; C3Mod_ViewOffsetTask) and the NMI tasks (C3Mod_OamUploadTask,
; C3Mod_HideSprites, C3Mod_Unk5221, C3Mod_ScrollNmiTask,
; C3Mod_HorizonNmiTask, C3Mod_ClearColumnTask), sets the view (speed 0,
; distance $4C, scale $50, first divisor $28, X -$8C, angle 0, horizon
; $38) and goes on in C3Mod_Prog0RunA or C3Mod_Prog0RunB, picked at
; random by C3Mod_PickRun.
C3Mod_Prog0ScriptA:
    db !C3Op_TaskAdd : dw C3Mod_ViewTask
    db !C3Op_TaskAdd : dw C3Mod_PadDelayTask
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskB
    db !C3Op_TaskAdd : dw C3Mod_TurnTask
    db !C3Op_TaskAdd : dw C3Mod_Unk4F54
    db !C3Op_TaskAdd : dw C3Mod_Unk4D0D
    db !C3Op_TaskAdd : dw C3Mod_FadeInTask
    db !C3Op_TaskAdd : dw C3Mod_ViewOffsetTask
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_HideSprites
    db !C3Op_NmiAdd : dw C3Mod_Unk5221
    db !C3Op_NmiAdd : dw C3Mod_ScrollNmiTask
    db !C3Op_NmiAdd : dw C3Mod_HorizonNmiTask
    db !C3Op_NmiAdd : dw C3Mod_ClearColumnTask
    db !C3Op_Set|9 : dw $0000
    db !C3Op_Set|2 : dw $004C
    db !C3Op_Set|0 : dw $0050
    db !C3Op_Set|8 : dw $0028
    db !C3Op_Set|1 : dw -$8C
    db !C3Op_Set|5 : dw $0000
    db !C3Op_Set|6 : dw $0038
    db !C3Op_CallW : dw C3Mod_PickRun

; $7E:3F59 — C3Mod_PickRun (13 bytes, $3F59–$3F65)
; A script routine (opcode $x0, C3Mod_CallW): page $0A00's script goes
; on in C3Mod_Prog0RunA or C3Mod_Prog0RunB, by bit 1 of a random byte
; (C3Mod_TableRandom): C3Script_Ptr = the C3Mod_Prog0Runs entry, which
; is 2 bytes before the script (C3_RunScript adds 2 after the call).
; Callers note: script opcode $F0 at $3F56 (C3Mod_Prog0ScriptA).
; Entry: M=0, X=0 (the 16-bit table index), DP = the script's page
;        (C3Script_Ptr is direct page; $0A00 here), DB = $7E (the table
;        read is absolute; C3_RunScript runs with the module's bank).
; Exit:  M=0, X=0; A = C3Script_Ptr = the entry, X = 0 or 2; Y
;        unchanged.
; Calls: C3Mod_TableRandom.
C3Mod_PickRun:
    JSR C3Mod_TableRandom
    AND.w #!C3_PickRunBit
    TAX
    LDA.w C3Mod_Prog0Runs,X
    STA.b !C3Script_Ptr
    RTS

; $7E:3F66 — C3Mod_Prog0Runs (4 bytes, $3F66–$3F69)
; C3Mod_PickRun's two script entries, each 2 bytes before the script.
C3Mod_Prog0Runs:
    dw C3Mod_Prog0RunA-2, C3Mod_Prog0RunB-2

; $7E:3F6A — C3Mod_Prog0RunA (66 bytes, $3F6A–$3FAB)
; One of the two opening views (page $0A00): distance $D0, scale $50,
; first divisor 8, step mode 1 (C3Mod_Prog0Setup: every other line
; copied), var 12 = 1; 15 times eight frames of a turn (angle + $10)
; with the distance - 1, then divisor + 1 and scale + 1; var 12 = 0,
; eight more frames of it, divisor and scale + 1, step mode 0; then
; adds C3Mod_SteerTask and waits for good (a jump to itself).
C3Mod_Prog0RunA:
    db !C3Op_Set|2 : dw $00D0
    db !C3Op_Set|0 : dw $0050
    db !C3Op_Set|8 : dw $0008
    db !C3Op_Set|11 : dw $0001
    db !C3Op_Set|12 : dw $0001
.l3F79:
    db !C3Op_Add|5 : dw $0010
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|1 : dw $0007, .l3F79             ; 8 passes
    db !C3Op_Add|8 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Loop|0 : dw $000E, .l3F79                  ; 15 passes
    db !C3Op_Set|12 : dw $0000
.l3F92:
    db !C3Op_Add|5 : dw $0010
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $0007, .l3F92             ; 8 passes
    db !C3Op_Add|8 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Set|11 : dw $0000
    db !C3Op_TaskAdd : dw C3Mod_SteerTask
.l3FA9:
    db !C3Op_JumpYield : dw .l3FA9

; $7E:3FAC — C3Mod_Prog0RunB (94 bytes, $3FAC–$4009)
; The other opening view (page $0A00): angle $300, distance $10,
; divisor $18, scale $60; 64 frames of the distance + 2; step mode 1,
; var 12 = -1; four 16-frame turns (scale + 2, + 1, - 1, - 2; angle -
; $14, - $C, - $A, - 6; distance - 1 each frame), with var 12 = 0
; after the first; step mode 0, C3Mod_SteerTask added, then waits for
; good.
C3Mod_Prog0RunB:
    db !C3Op_Set|5 : dw $0300
    db !C3Op_Set|2 : dw $0010
    db !C3Op_Set|8 : dw $0018
    db !C3Op_Set|0 : dw $0060
.l3FB8:
    db !C3Op_Add|2 : dw $0002
    db !C3Op_LoopYield|0 : dw $003F, .l3FB8             ; 64 passes
    db !C3Op_Set|11 : dw $0001
    db !C3Op_Set|12 : dw -$1
.l3FC6:
    db !C3Op_Add|0 : dw $0002
    db !C3Op_Add|5 : dw -$14
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l3FC6             ; 16 passes
    db !C3Op_Set|12 : dw $0000
.l3FD7:
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Add|5 : dw -$C
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l3FD7             ; 16 passes
.l3FE5:
    db !C3Op_Add|0 : dw -$1
    db !C3Op_Add|5 : dw -$A
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l3FE5             ; 16 passes
.l3FF3:
    db !C3Op_Add|0 : dw -$2
    db !C3Op_Add|5 : dw -$6
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l3FF3             ; 16 passes
    db !C3Op_Set|11 : dw $0000
    db !C3Op_TaskAdd : dw C3Mod_SteerTask
.l4007:
    db !C3Op_JumpYield : dw .l4007

; $7E:400A — C3Mod_Prog0ScriptB (67 bytes, $400A–$404C)
; Page $0B00's first script: C3_ViewY = $18, vars 0 and 6 = $FF; the
; count-down: sound effect $96 (C3_SndSfxA) three times 60 frames
; apart, then effect $97 (Audio_CmdPlaySfx); 20 frames later
; C3_PauseAllowed = 1 (poke), var 13 = 1, sound effect $44, the task
; C3Mod_Unk485D added; then waits for good.
C3Mod_Prog0ScriptB:
    db !C3Op_Set|2 : dw $0018
    db !C3Op_Set|0 : dw $00FF
    db !C3Op_Set|6 : dw $00FF
    db !C3Op_Driver : dw !C3_SndSfxA|($96<<8), $0080
.l4018:
    db !C3Op_LoopYield|1 : dw $003B, .l4018             ; 60 passes
    db !C3Op_Driver : dw !C3_SndSfxA|($96<<8), $0080
.l4022:
    db !C3Op_LoopYield|1 : dw $003B, .l4022             ; 60 passes
    db !C3Op_Driver : dw !C3_SndSfxA|($96<<8), $0080
.l402C:
    db !C3Op_LoopYield|1 : dw $003B, .l402C             ; 60 passes
    db !C3Op_Driver : dw !Audio_CmdPlaySfx|($97<<8), $0080
.l4036:
    db !C3Op_LoopYield|1 : dw $0013, .l4036             ; 20 passes
    db !C3Op_Poke8 : dw !C3_PauseAllowed : db 1
    db !C3Op_Set|13 : dw $0001
    db !C3Op_Driver : dw !C3_SndSfxA|($44<<8), $0080
    db !C3Op_TaskAdd : dw C3Mod_Unk485D
.l404A:
    db !C3Op_JumpYield : dw .l404A

; $7E:404D — C3Mod_Prog0WipeA (118 bytes, $404D–$40C2)
; Page $0A00's first script with C3_EntryArg bit 6 (a run that ends by
; itself): the tasks (C3Mod_Prog0Start); distance $DE, scale $40,
; divisor $F; starts the kernel's wipe (WinFx_C3EMode = 1 by poke) and
; a frame later adds C3Mod_ExitTask, sets C3_Brightness = 15 and plays
; effect $BA; then the view moves (112 frames of distance - 1, turns of
; angle - 4 a frame, ...) and the wipe goes the other way
; (WinFx_C3EMode = 2, effect $BA again); after 8 more frames of moves
; and a 24-frame wait it ends (opcode $xF: C3_ExitFlag, the module
; leaves).
C3Mod_Prog0WipeA:
    db !C3Op_Call : dw C3Mod_Prog0Start
    db !C3Op_Set|2 : dw $00DE
    db !C3Op_Set|0 : dw $0040
    db !C3Op_Set|8 : dw $000F
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db 1
    db !C3Op_Yield
    db !C3Op_TaskAdd : dw C3Mod_ExitTask
    db !C3Op_Poke8 : dw !C3_Brightness : db 15
    db !C3Op_Driver : dw !C3_SndSfxA|($BA<<8), $0080
.l406A:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $006F, .l406A             ; 112 passes
.l4072:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|5 : dw -$4
    db !C3Op_LoopYield|0 : dw $002F, .l4072             ; 48 passes
.l407D:
    db !C3Op_Add|5 : dw -$4
    db !C3Op_LoopYield|0 : dw $002F, .l407D             ; 48 passes
.l4085:
    db !C3Op_Add|5 : dw -$4
    db !C3Op_Add|2 : dw $0001
    db !C3Op_LoopYield|0 : dw $001F, .l4085             ; 32 passes
    db !C3Op_Add|8 : dw $0001
.l4093:
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Yield
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_LoopYield|0 : dw $0033, .l4093             ; 52 passes
    db !C3Op_Add|8 : dw $0001
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db 2
    db !C3Op_Driver : dw !C3_SndSfxA|($BA<<8), $0080
.l40AE:
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Yield
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_LoopYield|0 : dw $0003, .l40AE             ; 4 passes
.l40BD:
    db !C3Op_LoopYield|1 : dw $0017, .l40BD             ; 24 passes
    db !C3Op_End

; $7E:40C3 — C3Mod_Prog0WipeB (106 bytes, $40C3–$412C)
; As C3Mod_Prog0WipeA, with another flight (distance $40, scale $FF,
; divisor $30; turns of angle + 4 a frame, the scale and the divisor
; going down), the alternate run (C3_StartCount bit 0).
C3Mod_Prog0WipeB:
    db !C3Op_Call : dw C3Mod_Prog0Start
    db !C3Op_Set|2 : dw $0040
    db !C3Op_Set|0 : dw $00FF
    db !C3Op_Set|8 : dw $0030
.l40CF:
    db !C3Op_LoopYield|1 : dw $0007, .l40CF             ; 8 passes
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db 1
    db !C3Op_Yield
    db !C3Op_TaskAdd : dw C3Mod_ExitTask
    db !C3Op_Poke8 : dw !C3_Brightness : db 15
    db !C3Op_Driver : dw !C3_SndSfxA|($BA<<8), $0080
.l40E5:
    db !C3Op_LoopYield|1 : dw $0007, .l40E5             ; 8 passes
.l40EA:
    db !C3Op_Add|0 : dw -$1
    db !C3Op_Add|5 : dw $0004
    db !C3Op_Add|2 : dw $0001
    db !C3Op_LoopYield|1 : dw $0003, .l40EA             ; 4 passes
    db !C3Op_Add|8 : dw -$1
    db !C3Op_Loop|0 : dw $001F, .l40EA                  ; 32 passes
.l4100:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|5 : dw $0004
    db !C3Op_Add|0 : dw -$1
    db !C3Op_LoopYield|0 : dw $003F, .l4100             ; 64 passes
.l410E:
    db !C3Op_LoopYield|1 : dw $0027, .l410E             ; 40 passes
.l4113:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $005F, .l4113             ; 96 passes
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db 2
    db !C3Op_Driver : dw !C3_SndSfxA|($BA<<8), $0080
.l4124:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $001F, .l4124             ; 32 passes
    db !C3Op_End

; $7E:412D — C3Mod_Prog0Start (49 bytes, $412D–$415D)
; Called by script opcode $F3 (from C3Mod_Prog0WipeA and
; C3Mod_Prog0WipeB): adds the tasks of C3Mod_Prog0ScriptA, with
; C3Mod_WipeTask in place of C3Mod_FadeInTask and without
; C3Mod_PadDelayTask, and its NMI tasks but C3Mod_ClearColumnTask;
; X speed $11, angle 0, horizon $38; returns (opcode $F4).
C3Mod_Prog0Start:
    db !C3Op_TaskAdd : dw C3Mod_ViewTask
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskB
    db !C3Op_TaskAdd : dw C3Mod_TurnTask
    db !C3Op_TaskAdd : dw C3Mod_Unk4F54
    db !C3Op_TaskAdd : dw C3Mod_Unk4D0D
    db !C3Op_TaskAdd : dw C3Mod_WipeTask
    db !C3Op_TaskAdd : dw C3Mod_ViewOffsetTask
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_HideSprites
    db !C3Op_NmiAdd : dw C3Mod_Unk5221
    db !C3Op_NmiAdd : dw C3Mod_ScrollNmiTask
    db !C3Op_NmiAdd : dw C3Mod_HorizonNmiTask
    db !C3Op_Set|9 : dw $0011
    db !C3Op_Set|5 : dw $0000
    db !C3Op_Set|6 : dw $0038
    db !C3Op_Return

; $7E:415E — C3Mod_Prog0WipeScriptB (15 bytes, $415E–$416C)
; Page $0B00's script for the C3_EntryArg bit 6 run: C3_ViewY = $18,
; vars 0 and 6 = $FF, var 13 = 1, then waits for good.
C3Mod_Prog0WipeScriptB:
    db !C3Op_Set|2 : dw $0018
    db !C3Op_Set|0 : dw $00FF
    db !C3Op_Set|6 : dw $00FF
    db !C3Op_Set|13 : dw $0001
.l416A:
    db !C3Op_JumpYield : dw .l416A

; $7E:416D — C3Mod_DriftTask (57 bytes, $416D–$41A5)
; A task: on the two frames in four that have C3_FrameCount bit 1
; clear, moves the view one step towards its rest: the scale (page
; $0A00's var 0) to $A0, the horizon (var 6) to $38, the distance (var
; 2) to $90 (each + 1 or - 1 by the sign of the difference, BMI: right
; while it is below $8000).
; Callers note: a task by replacement: LDX #C3Mod_DriftTask / JMP
;   C3Mod_TaskReplace at $476B (C3Mod_WaitSongEndTask); removed by
;   script opcode $F9 at $41AB (C3Mod_Prog0Finish).
; Entry: a task (C3Mod_RunTasks): M=0, X=0, DP=0 (C3_FrameCount; set to
;        $0A00 here, restored by C3Mod_RunTasks), DB any.
; Exit:  M=0, X=0, DP = $0A00 after a step (else 0); A = the distance
;        (or C3_FrameCount / 4 on the frames it waits); X, Y unchanged.
C3Mod_DriftTask:
    LDA.b !C3_FrameCount
    LSR A
    LSR A
    BCC .step
    RTS
.step:
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.b !C3_ViewScale
    CMP.w #!C3_DriftScale
    BEQ .horizon
    BMI .scale_up
    DEC.b !C3_ViewScale
    BRA .horizon
.scale_up:
    INC.b !C3_ViewScale
.horizon:
    LDA.b !C3_ViewHorizon
    CMP.w #!C3_DriftHorizon
    BEQ .distance
    BMI .horizon_down
    DEC.b !C3_ViewHorizon
    BRA .distance
.horizon_down:
    INC.b !C3_ViewHorizon
.distance:
    LDA.b !C3_ViewDist
    CMP.w #!C3_DriftDist
    BEQ .done
    BMI .closer
    DEC.b !C3_ViewDist
    BRA .done
.closer:
    INC.b !C3_ViewDist
.done:
    RTS

; $7E:41A6 — C3Mod_Prog0Finish (107 bytes, $41A6–$4210)
; Page $0A00's last script, started by C3Mod_WaitSongEndTask: waits 320
; frames, removes C3Mod_DriftTask (opcode $F9), turns (angle + 2 a
; frame) while the distance and the scale go down, waits 112 frames,
; then moves the horizon down and raises the distance and the scale,
; adding C3Mod_FadeOutTask halfway, and ends (opcode $xF: the module
; leaves).
C3Mod_Prog0Finish:
    db !C3Op_LoopYield|1 : dw $013F, C3Mod_Prog0Finish  ; 320 passes
    db !C3Op_TaskRemove : dw C3Mod_DriftTask
.l41AE:
    db !C3Op_Add|5 : dw $0002
    db !C3Op_LoopYield|1 : dw $0006, .l41AE             ; 7 passes
    db !C3Op_Add|5 : dw $0002
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|0 : dw -$1
    db !C3Op_LoopYield|0 : dw $001F, .l41AE             ; 32 passes
.l41C4:
    db !C3Op_Add|5 : dw $0002
    db !C3Op_LoopYield|1 : dw $0006, .l41C4             ; 7 passes
    db !C3Op_Add|5 : dw $0002
    db !C3Op_Add|2 : dw -$2
    db !C3Op_Add|0 : dw -$2
    db !C3Op_LoopYield|0 : dw $001F, .l41C4             ; 32 passes
.l41DA:
    db !C3Op_LoopYield|1 : dw $006F, .l41DA             ; 112 passes
.l41DF:
    db !C3Op_Add|6 : dw $0001
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Yield
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $0017, .l41DF             ; 24 passes
    db !C3Op_TaskAdd : dw C3Mod_FadeOutTask
.l41F9:
    db !C3Op_Add|6 : dw $0001
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Yield
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $0017, .l41F9             ; 24 passes
    db !C3Op_End

; $7E:4211 — C3Mod_Prog0Quit (60 bytes, $4211–$424C)
; Page $0A00's script when the race is left (stored by code at $48A3):
; stops sound effect groups 0 and 1 (C3_SndStopSfx), sets the tempo
; adjustment ($40, $80), waits 32 frames, adds C3Mod_RestoreColumnTask
; (an NMI task) and jumps to .fade: C3Mod_FadeOutTask, 128 frames,
; C3_SndStopAll and the end (opcode $xF). The copy at .copy (the same
; three commands and wait, then .fade) is reached by nothing found.
C3Mod_Prog0Quit:
    db !C3Op_Driver : dw !C3_SndStopSfx|($00<<8), $0000
    db !C3Op_Driver : dw !C3_SndStopSfx|($01<<8), $0000
    db !C3Op_Driver : dw !C3_SndTempoPitch|($40<<8), $0080
.l4220:
    db !C3Op_LoopYield|1 : dw $001F, .l4220             ; 32 passes
    db !C3Op_NmiAdd : dw C3Mod_RestoreColumnTask
    db !C3Op_Jump : dw .fade
.copy:
    db !C3Op_Driver : dw !C3_SndStopSfx|($00<<8), $0000
    db !C3Op_Driver : dw !C3_SndStopSfx|($01<<8), $0000
    db !C3Op_Driver : dw !C3_SndTempoPitch|($40<<8), $0080
.l423A:
    db !C3Op_LoopYield|1 : dw $001F, .l423A             ; 32 passes
.fade:
    db !C3Op_TaskAdd : dw C3Mod_FadeOutTask
.l4242:
    db !C3Op_LoopYield|1 : dw $007F, .l4242             ; 128 passes
    db !C3Op_Driver : dw !C3_SndStopAll|($00<<8), $0000
    db !C3Op_End

; $7E:424D — C3Mod_ExitTask (54 bytes, $424D–$4282)
; A task of the C3_EntryArg bit 6 run: once any button is down (C3_Pad)
; while no wipe runs (WinFx_C3EMode 0), starts the wipe with mode
; .wipe_mode's operand (C3Mod_Prog0 writes 2 there, $683F writes 1),
; plays effect $BA (C3_SndSfxA) by C3Mod_AudioSend unless C3_SongBusy,
; sets C3_ExitTimer = 32 and C3_Unk7F0062 = 0 and hands over to
; C3Mod_ExitCountTask.
; Callers note: a task added by script opcode $FA at $405E
;   (C3Mod_Prog0WipeA), $40D9 (C3Mod_Prog0WipeB) and $68BD (code not
;   matched yet).
; Entry: a task: M=0 (8-bit set here), X=0 (the 16-bit pad and timer
;        loads), DP=0 (C3_Pad), DB=$00 (absolute RAM and Audio_Cmd*).
; Exit:  RTS with M=1, X = C3_Pad, A as on entry (no button) or
;        WinFx_C3EMode (a wipe runs); else JMP C3Mod_TaskReplace with X
;        = C3Mod_ExitCountTask.
; Calls: C3Mod_AudioSend.
C3Mod_ExitTask:
    SEP #$20
    LDX.b !C3_Pad
    BEQ .wait
    LDA.w !WinFx_C3EMode
    BNE .wait
.wipe_mode:
    LDA.b #!WinFx_C3EMode2              ; written by C3Mod_Prog0 and $683F
    STA.w !WinFx_C3EMode
    LDA.w !C3_SongBusy
    BNE .no_sound
    LDX.w #!C3_SfxWipe|(!C3_SfxArg1<<8)
    STX.w !Audio_CmdArg0                ; and Audio_CmdArg1
    LDA.b #!C3_SndSfxA
    STA.w !Audio_CmdId
    JSR C3Mod_AudioSend
.no_sound:
    LDX.w #!C3_ExitFrames
    STX.w !C3_ExitTimer
    LDA.b #0
    STA.l !C3_Unk7F0062
    LDX.w #C3Mod_ExitCountTask
    JMP C3Mod_TaskReplace
.wait:
    RTS

; $7E:4283 — C3Mod_ExitCountTask (8 bytes, $4283–$428A)
; A task: counts C3_ExitTimer down and, when it reaches 0, adds 1 to
; C3_ExitFlag (the module leaves). It is not ended: past 0 the timer
; would wrap, but the module has left by then.
; Callers note: a task by replacement: LDX #C3Mod_ExitCountTask / JMP
;   C3Mod_TaskReplace at $427C (C3Mod_ExitTask).
; Entry: a task: M=0, X=0, DP=0 (C3_ExitFlag), DB=$00.
; Exit:  M=0; A, X, Y unchanged.
C3Mod_ExitCountTask:
    DEC.w !C3_ExitTimer
    BNE .wait
    INC.b !C3_ExitFlag
.wait:
    RTS

; $7E:428B — C3Mod_TurnTask (50 bytes, $428B–$42BC)
; A task: moves the view: C3_ViewX += C3_ViewSpeedX (page $0A00, kept
; to $000-$3FF), then the mode-7 plane's scroll and centre: X =
; C3_ViewX + C3_ViewOffsetX (centre + $7F), Y = C3_ViewY (page $0B00)
; + C3_ViewOffsetY (centre + $E0), for C3Mod_ScrollNmiTask.
; Callers note: a task added by script opcode $FA at $3F20
;   (C3Mod_Prog0ScriptA) and $4136 (C3Mod_Prog0Start).
; Entry: a task: M any (REP #$20 here), X any, DP any (set to $0A00
;        here, restored by C3Mod_RunTasks), DB=$00 (absolute RAM).
; Exit:  M=0, DP = $0A00; A = C3_PlaneCentreY; X, Y unchanged.
C3Mod_TurnTask:
    REP #$20
    PEA.w !C3_ScriptPageA
    PLD
    LDA.b !C3_ViewX
    CLC
    ADC.b !C3_ViewSpeedX
    AND.w #!C3_PlaneMask
    STA.b !C3_ViewX
    LDA.b !C3_ViewX
    CLC
    ADC.w !C3_ViewOffsetX
    STA.w !C3_PlaneScrollX
    CLC
    ADC.w #!C3_PlaneCentreDX
    STA.w !C3_PlaneCentreX
    LDA.w !C3_ScriptPageB+!C3_ViewY
    CLC
    ADC.w !C3_ViewOffsetY
    STA.w !C3_PlaneScrollY
    CLC
    ADC.w #!C3_PlaneCentreDY
    STA.w !C3_PlaneCentreY
    RTS

; $7E:42BD — C3Mod_PadDelayTask (17 bytes, $42BD–$42CD)
; A task: rotates the words C3_Pad, C3_PadPrev and C3_PadHeld (C3_Pad
; gets C3_PadPrev, C3_PadPrev gets C3_PadHeld, C3_PadHeld gets C3_Pad,
; through C3_TmpF0): as C3_ReadPad rewrites C3_Pad each frame before
; the tasks run, C3_PadHeld is this frame's pad and C3_PadPrev the
; last frame's.
; Callers note: a task added by script opcode $FA at $3F17
;   (C3Mod_Prog0ScriptA).
; Entry: a task: M=0, X any, DP=0 (the pad words), DB any.
; Exit:  M=0; A = C3_PadHeld (the pad); X, Y unchanged.
C3Mod_PadDelayTask:
    LDA.b !C3_Pad
    STA.b !C3_TmpF0
    LDA.b !C3_PadPrev
    STA.b !C3_Pad
    LDA.b !C3_PadHeld
    STA.b !C3_PadPrev
    LDA.b !C3_TmpF0
    STA.b !C3_PadHeld
    RTS

; $7E:42CE — C3Mod_ViewTask (59 bytes, $42CE–$4308)
; A task: rebuilds the mode-7 tables (JMP C3Mod_BuildM7Tables, with
; C3Mod_Prog0Setup written over its setup call) when the view changed:
; page $0A00's scale, angle, horizon, first divisor or step mode
; differs from its copy in C3_ViewCache (5 words). The copies from the
; first that differs on are updated (they enter at that one's store);
; a new scale also clears C3_Unk1446 (C3Mod_ClearUnk1446).
; Callers note: a task added by script opcode $FA at $3F14
;   (C3Mod_Prog0ScriptA) and $412D (C3Mod_Prog0Start).
; Entry: a task: M=0, X=0 (C3Mod_BuildM7Tables'), DP any (set to $0A00
;        here, restored by C3Mod_RunTasks), DB any (absolute only in
;        C3Mod_ClearUnk1446's MVN and C3Mod_BuildM7Tables, which set
;        it).
; Exit:  unchanged: RTS with A = the step mode; else as
;        C3Mod_BuildM7Tables leaves them (M=0, X=0, DP = DP_CPU, DB =
;        $7E).
; Calls: C3Mod_ClearUnk1446, C3Mod_BuildM7Tables (JMP).
C3Mod_ViewTask:
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.b !C3_ViewScale
    CMP.b !C3_ViewCache
    BNE .scale
    LDA.b !C3_ViewAngle
    CMP.b !C3_ViewCache+2
    BNE .angle
    LDA.b !C3_ViewHorizon
    CMP.b !C3_ViewCache+4
    BNE .horizon
    LDA.b !C3_ViewFirstDiv
    CMP.b !C3_ViewCache+6
    BNE .first_div
    LDA.b !C3_ViewStepMode
    CMP.b !C3_ViewCache+8
    BNE .step_mode
    RTS
.scale:
    STA.b !C3_ViewCache
    JSR C3Mod_ClearUnk1446
    LDA.b !C3_ViewAngle
.angle:
    STA.b !C3_ViewCache+2
    LDA.b !C3_ViewHorizon
.horizon:
    STA.b !C3_ViewCache+4
    LDA.b !C3_ViewFirstDiv
.first_div:
    STA.b !C3_ViewCache+6
    LDA.b !C3_ViewStepMode
.step_mode:
    STA.b !C3_ViewCache+8
    JMP C3Mod_BuildM7Tables

; $7E:4309 — C3Mod_ClearUnk1446 (16 bytes, $4309–$4318)
; Zeroes the 256 bytes of C3_Unk1446 ($1446-$1545: a word stored, then
; an overlapping MVN in bank $00).
; Callers note: C3Mod_ViewTask ($42F3) and C3Mod_Prog0Vars ($4640,
;   JMP).
; Entry: M=0, X=0 (MVN's 16-bit X and Y), DP any, DB any (set to $00
;        by the MVN; the STZ before it is absolute, so DB must be $00
;        or $7E, or another bank that maps low WRAM: $00 at both
;        calls).
; Exit:  M=0, X=0, DB = $00; A = $FFFF; X = $1545, Y = $1546.
C3Mod_ClearUnk1446:
    STZ.w !C3_Unk1446
    LDX.w #!C3_Unk1446
    LDY.w #!C3_Unk1446+1
    LDA.w #!C3_Unk1446Bytes-2
    MVN $00,$00                         ; lint-ok: MVN operands are bank bytes (bank $00)
    RTS

; $7E:4319 — C3Mod_ForwardPads (16 bytes, $4319–$4328)
; The D-pad buttons (JOY1's high byte as a word) that point along the
; view, by eighth of a turn of the angle (C3Mod_SteerTask's index:
; (angle + $40) / 64, even): Up, Up+Right, Right, Down+Right, Down,
; Down+Left, Left, Up+Left; C3Mod_SteerTask and C3Mod_Prog0Vars copy
; the entry to C3_PadForward (probably the button that drives
; forward; its reader is not matched yet).
C3Mod_ForwardPads:
    dw !C3_PadUp, !C3_PadUp|!C3_PadRight, !C3_PadRight, !C3_PadDown|!C3_PadRight
    dw !C3_PadDown, !C3_PadDown|!C3_PadLeft, !C3_PadLeft, !C3_PadUp|!C3_PadLeft

; $7E:4329 — C3Mod_BackPads (16 bytes, $4329–$4338)
; The opposite directions, for C3_PadBack.
C3Mod_BackPads:
    dw !C3_PadDown, !C3_PadDown|!C3_PadLeft, !C3_PadLeft, !C3_PadUp|!C3_PadLeft
    dw !C3_PadUp, !C3_PadUp|!C3_PadRight, !C3_PadRight, !C3_PadDown|!C3_PadRight

; $7E:4339 — C3Mod_SteerTask (127 bytes, $4339–$43B7)
; A task (and a subroutine) of the view, on page $0A00:
;   - program 9 only (C3_Prog9): the L and R buttons (C3_PadHeld) turn
;     the view: C3_ViewLeanR / C3_ViewLeanL count up while R / L is
;     held (to 12) and down otherwise (C3Mod_LeanR, C3Mod_LeanL), and
;     the angle moves by C3_ViewLeanR / 4 - C3_ViewLeanL / 4 a frame;
;   - C3_PadForward / C3_PadBack = the C3Mod_ForwardPads /
;     C3Mod_BackPads entry for the angle's eighth of a turn;
;   - on odd frames (C3_FrameCount bit 0), X held brings the view up
;     (distance, scale and horizon + 1, while the scale is below $7F),
;     else A held takes it down (- 1 each, while the scale is $60 or
;     more).
; Callers note: a task added by script opcode $FA at $3FA6
;   (C3Mod_Prog0RunA) and $4004 (C3Mod_Prog0RunB); removed by LDX
;   #C3Mod_SteerTask / JSR C3Mod_TaskRemove at $482B and $4876 (code not
;   matched yet).
; Entry: a task (C3Mod_RunTasks): M=0, X=0 (16-bit counters), DP any
;        (set to $0A00 here, restored by C3Mod_RunTasks), DB=$00
;        (C3_Prog9, C3_PadHeld and C3_FrameCount are read absolute).
; Exit:  M=0, X=0, DP = $0A00; A, X changed (X = the pad table index);
;        Y unchanged; C3_TmpF0/F2 of page $0A00 changed in program 9.
; Calls: C3Mod_LeanR, C3Mod_LeanL.
C3Mod_SteerTask:
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.w !C3_Prog9
    BEQ .pads
    LDA.w !C3_PadHeld
    JSR C3Mod_LeanR
    JSR C3Mod_LeanL
    LDA.b !C3_ViewLeanR
    LSR A
    LSR A
    STA.b !C3_TmpF0
    LDA.b !C3_ViewLeanL
    LSR A
    LSR A
    STA.b !C3_TmpF2
    LDA.b !C3_ViewAngle
    CLC
    ADC.b !C3_TmpF0
    SEC
    SBC.b !C3_TmpF2
    STA.b !C3_ViewAngle
.pads:
    LDA.w !C3_ScriptPageA+!C3_ViewAngle
    CLC
    ADC.w #!C3_EighthTurn/2
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    AND.w #!C3_PadTableMask
    TAX
    LDA.l C3Mod_ForwardPads,X
    STA.w !C3_PadForward
    LDA.l C3Mod_BackPads,X
    STA.w !C3_PadBack
    LDA.w !C3_PadHeld
    BIT.w #!C3_PadX
    BEQ .not_up
    LDA.w !C3_FrameCount
    LSR A
    BCC .not_up
    LDA.b !C3_ViewScale
    CMP.w #!C3_ViewScaleMax
    BPL .done
    INC.b !C3_ViewDist
    INC.b !C3_ViewScale
    INC.b !C3_ViewHorizon
    RTS
.not_up:
    LDA.w !C3_PadHeld
    BIT.w #!C3_PadA
    BEQ .done
    LDA.w !C3_FrameCount
    LSR A
    BCC .done
    LDA.b !C3_ViewScale
    CMP.w #!C3_ViewScaleMin
    BMI .done
    DEC.b !C3_ViewDist
    DEC.b !C3_ViewScale
    DEC.b !C3_ViewHorizon
.done:
    RTS

; $7E:43B8 — C3Mod_LeanR (29 bytes, $43B8–$43D4)
; C3_ViewLeanR + 1 (up to C3_LeanMax) while the R button is in A, else
; - 1 (down to 0).
; Callers note: C3Mod_SteerTask ($4345).
; Entry: M=0, X=0 (the 16-bit count), DP = page $0A00 (C3_ViewLeanR),
;        DB any; A = the pad.
; Exit:  M=0, X=0; A unchanged (saved), X = C3_ViewLeanR; Y unchanged.
C3Mod_LeanR:
    PHA
    LDX.b !C3_ViewLeanR
    BIT.w #!C3_PadR
    BEQ .release
    INX
    CPX.w #!C3_LeanMax
    BMI .store
    LDX.w #!C3_LeanMax
    BRA .store
.release:
    CPX.w #0
    BEQ .store
    DEX
.store:
    STX.b !C3_ViewLeanR
    PLA
    RTS

; $7E:43D5 — C3Mod_LeanL (29 bytes, $43D5–$43F1)
; The same for C3_ViewLeanL and the L button.
; Callers note: C3Mod_SteerTask ($4348).
; Entry: M=0, X=0, DP = page $0A00 (C3_ViewLeanL), DB any; A = the pad.
; Exit:  M=0, X=0; A unchanged (saved), X = C3_ViewLeanL; Y unchanged.
C3Mod_LeanL:
    PHA
    LDX.b !C3_ViewLeanL
    BIT.w #!C3_PadL
    BEQ .release
    INX
    CPX.w #!C3_LeanMax
    BMI .store
    LDX.w #!C3_LeanMax
    BRA .store
.release:
    CPX.w #0
    BEQ .store
    DEX
.store:
    STX.b !C3_ViewLeanL
    PLA
    RTS

; $7E:43F2 — C3Mod_ScrollNmiTask (85 bytes, $43F2–$4446)
; An NMI task: writes the mode-7 centre (M7X = C3_PlaneCentreX, M7Y =
; C3_PlaneCentreY), BG2HOFS = C3_Bg2ScrollX, BG3HOFS / BG3VOFS =
; C3_Bg3ScrollX / Y (each register low byte, then high byte), and
; copies the sky's and the plane's scroll (C3_SkyScrollX/Y,
; C3_PlaneScrollX/Y) to C3_SkyScrollHdma / C3_PlaneScrollHdma, which
; C3Mod_ScrollHdma's lines send to BG1HOFS/BG1VOFS this frame.
; Callers note: an NMI task added by script opcode $F8 at $3F38
;   (C3Mod_Prog0ScriptA) and $414E (C3Mod_Prog0Start).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0 (the word copies),
;        DP any, DB=$00 (absolute registers and RAM).
; Exit:  M=1, X=0; A = C3_Bg3ScrollY's high byte, X = C3_PlaneScrollY;
;        Y unchanged.
C3Mod_ScrollNmiTask:
    LDA.w !C3_PlaneCentreX
    STA.w M7X
    LDA.w !C3_PlaneCentreX+1
    STA.w M7X
    LDA.w !C3_PlaneCentreY
    STA.w M7Y
    LDA.w !C3_PlaneCentreY+1
    STA.w M7Y
    LDA.w !C3_Bg2ScrollX
    STA.w BG2HOFS
    LDA.w !C3_Bg2ScrollX+1
    STA.w BG2HOFS
    LDA.w !C3_Bg3ScrollX
    STA.w BG3HOFS
    LDA.w !C3_Bg3ScrollX+1
    STA.w BG3HOFS
    LDA.w !C3_Bg3ScrollY
    STA.w BG3VOFS
    LDA.w !C3_Bg3ScrollY+1
    STA.w BG3VOFS
    LDX.w !C3_SkyScrollX
    STX.w !C3_SkyScrollHdma
    LDX.w !C3_PlaneScrollX
    STX.w !C3_PlaneScrollHdma
    LDX.w !C3_SkyScrollY
    STX.w !C3_SkyScrollHdma+2
    LDX.w !C3_PlaneScrollY
    STX.w !C3_PlaneScrollHdma+2
    RTS

; $7E:4447 — C3Mod_ViewOffsetTask (85 bytes, $4447–$449B)
; A task: from page $0A00's view, C3_ViewOffsetY = cos(angle) x
; distance / 256 and C3_ViewOffsetX = the same with C3Mod_Sine
; (C3Mod_MulSigned16's product bits 8-23, in page $0A00's C3Math_*),
; which C3Mod_TurnTask adds to the plane's position; the sky's vertical
; scroll C3_SkyScrollY = $17 - the horizon and C3_Bg3ScrollY = $15 -
; it; the sky's horizontal scroll C3_SkyScrollX = - the angle, with
; C3_Bg3ScrollX = it / 2 and C3_Bg2ScrollX = it / 4 (LSR of the
; negated word: right modulo the BG's 1,024 pixels).
; Callers note: a task added by script opcode $FA at $3F2C
;   (C3Mod_Prog0ScriptA) and $4142 (C3Mod_Prog0Start).
; Entry: a task: M any (REP #$20 here), X=0 (C3Mod_MulSigned16's), DP
;        any (set to $0A00 here), DB=$00 (absolute RAM).
; Exit:  M=0, X=0, DP = $0A00; A = C3_Bg2ScrollX; X = the angle AND
;        C3_AngleMask (C3Mod_Sine's; C3Mod_MulSigned16 keeps X); Y
;        unchanged; page $0A00's C3Math_* changed.
; Calls: C3Mod_Cosine, C3Mod_Sine, C3Mod_MulSigned16.
C3Mod_ViewOffsetTask:
    REP #$20
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.b !C3_ViewAngle
    JSR C3Mod_Cosine
    STA.b !C3Math_A
    LDA.b !C3_ViewDist
    STA.b !C3Math_B
    JSR C3Mod_MulSigned16
    LDA.b !C3Math_Lo+1                  ; product / 256
    STA.w !C3_ViewOffsetY
    LDA.b !C3_ViewAngle
    JSR C3Mod_Sine
    STA.b !C3Math_A
    LDA.b !C3_ViewDist
    STA.b !C3Math_B
    JSR C3Mod_MulSigned16
    LDA.b !C3Math_Lo+1
    STA.w !C3_ViewOffsetX
    LDA.b !C3_ViewHorizon
    EOR.w #!Eng_Invert16
    INC A
    CLC
    ADC.w #!C3_SkyTopY
    STA.w !C3_SkyScrollY
    DEC A
    DEC A
    STA.w !C3_Bg3ScrollY
    LDA.w #0
    CLC
    ADC.w !C3_ScriptPageA+!C3_ViewAngle
    EOR.w #!Eng_Invert16
    INC A
    STA.w !C3_SkyScrollX
    LSR A
    STA.w !C3_Bg3ScrollX
    LSR A
    STA.w !C3_Bg2ScrollX
    RTS

; $7E:449C — C3Mod_SkyNmiTask (50 bytes, $449C–$44CD)
; An NMI task: the sky's horizontal scroll from C3_Unk009D / 4 and
; C3_ViewX / 2: C3_TmpF0 = -(C3_ViewX / 2 + C3_Unk009D / 4 + $88 + the
; carries of the shifts), C3_SkyScrollX = it + C3_Unk143E,
; C3_Bg2ScrollX = C3_SkyScrollX / 4 and C3_Bg3ScrollX = C3_SkyScrollX
; x 3/8 (/ 4 + / 8, plus the carry of the shift). Quirk: no CLC before
; the ADCs, so the bits the LSRs shift out are added in.
; Callers note: an NMI task added by LDX #C3Mod_SkyNmiTask / JSR
;   C3Mod_NmiTaskAdd at $4894 (code not matched yet).
; Entry: an NMI task: M any (REP #$20 here), X any, DP=0 (C3_TmpF0),
;        DB=$00 (absolute RAM).
; Exit:  M=0; A = C3_Bg3ScrollX; X, Y unchanged; C3_TmpF0 changed.
C3Mod_SkyNmiTask:
    REP #$20
    LDA.w !C3_Unk009D
    LSR A
    LSR A
    STA.b !C3_TmpF0
    LDA.w !C3_ScriptPageA+!C3_ViewX
    LSR A
    ADC.b !C3_TmpF0
    ADC.w #!C3_SkyBaseX
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_TmpF0
    CLC
    ADC.w !C3_Unk143E
    STA.w !C3_SkyScrollX
    LSR A
    LSR A
    STA.w !C3_Bg2ScrollX
    LDA.w !C3_SkyScrollX
    LSR A
    LSR A
    STA.b !C3_TmpF0
    LSR A
    ADC.b !C3_TmpF0
    STA.w !C3_Bg3ScrollX
    RTS

; $7E:44CE — C3Mod_CountDownTask (48 bytes, $44CE–$44FD)
; A task: every fourth frame (C3_FrameCount bits 0-1 clear), takes
; 2000, 200, 20 or 2 off C3_Unk0069 (the first that fits, tried from
; the largest); when none fits (below 2) it ends itself
; (C3Mod_TaskEnd), C3_Unk0069 left as it is.
; Callers note: a task added by LDX #C3Mod_CountDownTask / JSR
;   C3Mod_TaskAdd at $489A (code not matched yet).
; Entry: a task: M=0, X=0 (C3Mod_TaskEnd's), DP=0 (C3_FrameCount and
;        C3_Unk0069 are direct page), DB any.
; Exit:  RTS with A = C3_Unk0069 (after a step) or C3_FrameCount AND 3;
;        at the end JMP C3Mod_TaskEnd with A = C3_Unk0069 - 2 (wrapped
;        below 0).
C3Mod_CountDownTask:
    LDA.b !C3_FrameCount
    AND.w #!C3_CountDownEvery-1
    BNE .wait
    LDA.b !C3_Unk0069
    SEC
    SBC.w #!C3_Dec1000*2
    BCS .store
    ADC.w #!C3_Dec1000*2
    SEC
    SBC.w #!C3_Dec100*2
    BCS .store
    ADC.w #!C3_Dec100*2
    SEC
    SBC.w #!C3_Dec10*2
    BCS .store
    ADC.w #!C3_Dec10*2
    SEC
    SBC.w #2
    BCS .store
    JMP C3Mod_TaskEnd
.store:
    STA.b !C3_Unk0069
.wait:
    RTS

; $7E:44FE — C3Mod_HorizonNmiTask (33 bytes, $44FE–$451E)
; An NMI task: splits the horizon (page $0A00's C3_ViewHorizon, its low
; byte) into the line counts of the first two entries of
; C3Mod_ModeHdma, C3Mod_MathHdma and C3Mod_ScrollHdma: half of it, and
; half plus the bit shifted out (so the two add up to the horizon: the
; sky's lines in BG mode 1, the plane below in mode 7), then goes on
; at C3Mod_Unk5261. Quirk: a horizon of 0 or 1 gives a first count of
; 0, which ends the tables there.
; Callers note: an NMI task added by script opcode $F8 at $3F3B
;   (C3Mod_Prog0ScriptA) and $4151 (C3Mod_Prog0Start).
; Entry: an NMI task: M=1, X any, DP any, DB=$00 (C3_ViewHorizon is
;        read absolute; the stores are long).
; Exit:  as C3Mod_Unk5261 leaves them (JMP).
C3Mod_HorizonNmiTask:
    LDA.w !C3_ScriptPageA+!C3_ViewHorizon
    LSR A
    STA.l C3Mod_ModeHdma
    STA.l C3Mod_MathHdma
    STA.l C3Mod_ScrollHdma
    ADC.b #0
    STA.l C3Mod_ModeHdma+3
    STA.l C3Mod_MathHdma+3
    STA.l C3Mod_ScrollHdma+3
    JMP C3Mod_Unk5261

; $7E:451F — C3Mod_ModeHdma (12 bytes, $451F–$452A)
; Indirect HDMA table for BGMODE (C3Mod_Prog0Hdma channel 5): the
; horizon's lines (two entries, counts written by
; C3Mod_HorizonNmiTask) from .mode1, then one line from .mode7 (held
; to the bottom), then the end; .mode1 / .mode7 are the values, BG
; mode 1 and 7.
C3Mod_ModeHdma:
    db 0 : dw .mode1
    db 0 : dw .mode1
    db 1 : dw .mode7
    db 0
.mode1:
    db !C3_BgMode1
.mode7:
    db !BGMODE_Mode7

; $7E:452B — C3Mod_MathHdma (55 bytes, $452B–$4561)
; Indirect HDMA table for CGADSUB / COLDATA (channel 4, two registers):
; the horizon's lines from C3Mod_MathValues (.sky), then 15 entries of
; two lines from .fade + 34 on (one pair each, 30 lines), then one line
; from C3Mod_MathValues' first pair (held to the bottom), then the end.
C3Mod_MathHdma:
    db 0 : dw C3Mod_MathValues_sky
    db 0 : dw C3Mod_MathValues_sky
    db 2 : dw C3Mod_MathValues_fade+34
    db 2 : dw C3Mod_MathValues_fade+36
    db 2 : dw C3Mod_MathValues_fade+38
    db 2 : dw C3Mod_MathValues_fade+40
    db 2 : dw C3Mod_MathValues_fade+42
    db 2 : dw C3Mod_MathValues_fade+44
    db 2 : dw C3Mod_MathValues_fade+46
    db 2 : dw C3Mod_MathValues_fade+48
    db 2 : dw C3Mod_MathValues_fade+50
    db 2 : dw C3Mod_MathValues_fade+52
    db 2 : dw C3Mod_MathValues_fade+54
    db 2 : dw C3Mod_MathValues_fade+56
    db 2 : dw C3Mod_MathValues_fade+58
    db 2 : dw C3Mod_MathValues_fade+60
    db 2 : dw C3Mod_MathValues_fade+62
    db 1 : dw C3Mod_MathValues
    db 0

; $7E:4562 — C3Mod_MathValues (68 bytes, $4562–$45A5)
; CGADSUB / COLDATA pairs for C3Mod_MathHdma: $50 / black at the start
; (half colour math on the sprites: the bottom of the screen; $87A6
; writes $05 over that CGADSUB byte), .sky: $42 / black (half on BG2),
; .fade: 32 pairs of $91
; (subtract, on BG1 and the sprites) with all three colours at 31 down
; to 0; C3Mod_MathHdma uses the last 15 (14 down to 0) under the
; horizon.
C3Mod_MathValues:
    db !C3_MathTop, !COLDATA_AllZero
.sky:
    db !C3_MathSky, !COLDATA_AllZero
.fade:
    db !C3_MathFade, !COLDATA_AllZero|31, !C3_MathFade, !COLDATA_AllZero|30
    db !C3_MathFade, !COLDATA_AllZero|29, !C3_MathFade, !COLDATA_AllZero|28
    db !C3_MathFade, !COLDATA_AllZero|27, !C3_MathFade, !COLDATA_AllZero|26
    db !C3_MathFade, !COLDATA_AllZero|25, !C3_MathFade, !COLDATA_AllZero|24
    db !C3_MathFade, !COLDATA_AllZero|23, !C3_MathFade, !COLDATA_AllZero|22
    db !C3_MathFade, !COLDATA_AllZero|21, !C3_MathFade, !COLDATA_AllZero|20
    db !C3_MathFade, !COLDATA_AllZero|19, !C3_MathFade, !COLDATA_AllZero|18
    db !C3_MathFade, !COLDATA_AllZero|17, !C3_MathFade, !COLDATA_AllZero|16
    db !C3_MathFade, !COLDATA_AllZero|15, !C3_MathFade, !COLDATA_AllZero|14
    db !C3_MathFade, !COLDATA_AllZero|13, !C3_MathFade, !COLDATA_AllZero|12
    db !C3_MathFade, !COLDATA_AllZero|11, !C3_MathFade, !COLDATA_AllZero|10
    db !C3_MathFade, !COLDATA_AllZero|9, !C3_MathFade, !COLDATA_AllZero|8
    db !C3_MathFade, !COLDATA_AllZero|7, !C3_MathFade, !COLDATA_AllZero|6
    db !C3_MathFade, !COLDATA_AllZero|5, !C3_MathFade, !COLDATA_AllZero|4
    db !C3_MathFade, !COLDATA_AllZero|3, !C3_MathFade, !COLDATA_AllZero|2
    db !C3_MathFade, !COLDATA_AllZero|1, !C3_MathFade, !COLDATA_AllZero

; $7E:45A6 — C3Mod_ScrollHdma (10 bytes, $45A6–$45AF)
; Indirect HDMA table for BG1HOFS / BG1VOFS (channel 3, two registers
; twice): the horizon's lines from C3_SkyScrollHdma (the sky), then one
; line from C3_PlaneScrollHdma (the plane, held), then the end.
C3Mod_ScrollHdma:
    db 0 : dw !C3_SkyScrollHdma
    db 0 : dw !C3_SkyScrollHdma
    db 1 : dw !C3_PlaneScrollHdma
    db 0

; $7E:45B0 — C3Mod_Prog0Setup (38 bytes, $45B0–$45D5)
; C3Mod_BuildM7Tables' setup routine for program 0 (C3Mod_Prog0 writes
; it over the JSR operand at $35FD): the horizon (page $0A00's
; C3_ViewHorizon, made at least 1 and stored back) x 4 as the first
; line's offset Y, C3_ViewFirstDiv as the first divisor X; the step at
; $3634: C3Mod_M7StepBranches' .copy_line BRA when C3_ViewStepMode is
; set (each line after the first copies the one before: half the
; vertical detail), else NOP / INX.
; Callers note: the JSR at $35FC (C3Mod_BuildM7Tables' .setup, its
;   operand written at $3CDE by C3Mod_Prog0).
; Entry: M=0, X=0, DP = page $0A00 (C3Mod_BuildM7Tables' DP), DB any
;        (the code stores are long).
; Exit:  M=0, X=0; Y = the horizon x 4, X = C3_ViewFirstDiv; A = the
;        step written.
C3Mod_Prog0Setup:
    LDA.b !C3_ViewHorizon
    CMP.w #1
    BCS .horizon_ok
    LDA.w #1
    STA.b !C3_ViewHorizon
.horizon_ok:
    ASL A
    ASL A
    TAY
    LDX.b !C3_ViewFirstDiv
    LDA.b !C3_ViewStepMode
    BEQ .every_line
    LDA.l C3Mod_M7StepBranches+6        ; BRA .copy_line
    STA.l C3Mod_BuildM7Tables_step
    RTS
.every_line:
    LDA.w #!Op_NOP|(!Op_INX<<8)
    STA.l C3Mod_BuildM7Tables_step
    RTS

; $7E:45D6 — C3Mod_Prog0Vars (109 bytes, $45D6–$4642)
; Program 0's race variables (called by C3Mod_Prog0): program 9
; (C3_Prog9) writes $D8 over the operands at $53A0, $4F74 and $50DA,
; $E8 over $53A4, 6 over $5395 and 1 over $53AE (code not matched
; yet); program 0 sets C3_Unk00BA = $80 and C3_Unk009A = 3. Then: the
; words C3_Unk0055 = C3_Unk0059 = $4000, C3_Unk007A = $3000,
; C3_Unk007E = $5000, C3_Unk00AE = 0, C3_Unk004E = $6000, C3_Unk0073 =
; $2000, C3_Unk00A8 = $20, C3_Unk00A2 = C3_Unk00A0 = 1, C3_Unk1444 =
; 0, C3_PadForward / C3_PadBack = the angle-0 entries (Up / Down), and
; C3_Unk1446 cleared (JMP C3Mod_ClearUnk1446).
; Callers note: C3Mod_Prog0 ($3C51).
; Entry: M=1, X=0, DP=0, DB=$00 (absolute RAM; the code stores are
;        long).
; Exit:  M=0 (REP #$20: CALL_EXITS in tools/c3module.py), X=0, DB =
;        $00; as C3Mod_ClearUnk1446 leaves them (A = $FFFF, X = $1545,
;        Y = $1546).
; Calls: C3Mod_ClearUnk1446 (JMP).
C3Mod_Prog0Vars:
    LDA.b !C3_Prog9
    BEQ .prog0
    LDA.b #!C3_Prog9Unk53A0
    STA.l C3Mod_Unk53A0
    STA.l C3Mod_Unk4F74
    STA.l C3Mod_Unk50DA
    LDA.b #!C3_Prog9Unk53A4
    STA.l C3Mod_Unk53A4
    LDA.b #!C3_Prog9Unk5395
    STA.l C3Mod_Unk5395
    LDA.b #!C3_Prog9Unk53AE
    STA.l C3Mod_Unk53AE
    BRA .both
.prog0:
    LDA.b #!C3_Prog0Unk00BA
    STA.b !C3_Unk00BA
    LDA.b #!C3_Prog0Unk009A
    STA.b !C3_Unk009A
.both:
    REP #$20
    LDA.w #!C3_Init0055
    STA.b !C3_Unk0055
    STA.b !C3_Unk0059
    LDA.w #!C3_Init007A
    STA.b !C3_Unk007A
    LDA.w #!C3_Init007E
    STA.b !C3_Unk007E
    STZ.b !C3_Unk00AE
    LDA.w #!C3_Init004E
    STA.b !C3_Unk004E
    LDA.w #!C3_Init0073
    STA.b !C3_Unk0073
    LDA.w #!C3_Init00A8
    STA.b !C3_Unk00A8
    LDA.w #1
    STA.b !C3_Unk00A2
    STA.b !C3_Unk00A0
    STZ.w !C3_Unk1444
    LDA.l C3Mod_ForwardPads
    STA.w !C3_PadForward
    LDA.l C3Mod_BackPads
    STA.w !C3_PadBack
    JMP C3Mod_ClearUnk1446

; $7E:4643 — C3Mod_ClearColumnTask (52 bytes with C3Mod_RestoreColumnTask, $4643–$4676)
; NMI tasks that run once: DMA channel 7 writes 19 bytes to VRAM's low
; bytes from word $0B00 on, 128 words apart (VMAIN = +128 after the
; low byte): the column of the mode-7 map C3Mod_Prog0 saved, from
; GfxRom_D2's first bytes (zeros: the cells cleared) or, at
; C3Mod_RestoreColumnTask ($464D), from C3_MapColumnSave (put back);
; then C3Mod_NmiTaskEnd. Quirk: C3Mod_Prog0 saved 20 bytes, 19 are
; written back.
; Callers note: an NMI task added by script opcode $F8 at $3F3E
;   (C3Mod_Prog0ScriptA) and by LDX #C3Mod_ClearColumnTask / JSR
;   C3Mod_NmiTaskAdd at $48D4 (code not matched yet).
;   C3Mod_RestoreColumnTask: added by script opcode $F8 at $4225
;   (C3Mod_Prog0Quit) and by LDX #C3Mod_RestoreColumnTask / JSR
;   C3Mod_NmiTaskAdd at $469E (C3Mod_RaceTask) and $48BA (code not
;   matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0 (the 16-bit register
;        pairs; C3Mod_NmiTaskEnd's PLX), DP and DB as it ran them (DB =
;        $00: absolute registers).
; Exit:  JMP C3Mod_NmiTaskEnd with A = MDMAEN_Ch7, X =
;        C3_MapColumnBytes - 1; VMADD past the column.
C3Mod_ClearColumnTask:
    LDX.w #!GfxRom_D2&$FFFF
    STX.w A1T7L
    LDA.b #bank(!GfxRom_D2)
    BRA C3Mod_RestoreColumnTask_bank
C3Mod_RestoreColumnTask:                ; header: see C3Mod_ClearColumnTask
    LDX.w #!C3_MapColumnSave&$FFFF
    STX.w A1T7L
    LDA.b #bank(!C3_MapColumnSave)
.bank:
    STA.w A1B7
    LDX.w #!BBAD_VMDATAL<<8
    STX.w DMAP7                         ; DMAP7 = 0 (one register), BBAD7 = VMDATAL
    LDA.b #!VMAIN_Inc128
    STA.w VMAIN
    LDX.w #!C3_MapColumn
    STX.w VMADDL
    LDX.w #!C3_MapColumnBytes-1
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    JMP C3Mod_NmiTaskEnd

; $7E:4677 — C3Mod_RaceTask (222 bytes, $4677–$4754)
; A task (the first part of one; it goes on at C3Mod_Unk48FD):
;   - the A button (C3_PadHeld bit 7) once (C3_Unk00BE set): adds
;     C3Mod_FadeOutExitTask (the module leaves after the fade);
;   - while C3_Unk00A2 is set: when C3_Unk009E is 8 and C3_Unk009C is
;     $400 or more, clears it and adds C3Mod_RestoreColumnTask (an NMI
;     task: the map column put back);
;   - C3_PadHeld = 0;
;   - unless C3_Unk00B0 is 1, nothing more here. With it: C3_Unk0098 =
;     $8000 in program 9, else 0; program 9 (C3_EntryArg bits 0-3)
;     moves C3_Unk004E to $2000 and C3_Unk0073 to $6000 by $80 a frame
;     (rounded down to $80), not while C3_SongBusy (then straight to
;     C3Mod_Unk48FD); program 0 clears C3_Unk0063, sets C3_Unk0088 = 1
;     once C3_Unk0051 - C3_Unk0076 is $1000 or more (BMI) and, unless
;     C3_SongBusy, moves C3_Unk004E to $4000 the same way;
;   - C3_Unk00B2 (a byte) one step towards 0; once the word
;     C3_Unk00B2 is 0, C3_Unk0088 is set and C3_Unk004E (bit 0 aside)
;     is $4000: C3_Unk0065 = C3_Unk0067 = 0 and C3_Unk00B0 and
;     C3_Unk1444 + 1.
; The SBC and ADC of the moves have no SEC / CLC: the CMP before each
; leaves the carry right (set when above, clear when below).
; Callers note: a task by replacement: LDX #C3Mod_RaceTask / JMP
;   C3Mod_TaskReplace at $4857 (code not matched yet).
; Entry: a task: M=0, X=0, DP=0 (the C3_Unk00xx words), DB=$00
;        (C3_EntryArg, C3_SongBusy and C3_Unk1444 are absolute).
; Exit:  JMP C3Mod_Unk48FD with M=0, X=0.
; Calls: C3Mod_TaskAdd, C3Mod_NmiTaskAdd, C3Mod_Unk48FD (JMP).
C3Mod_RaceTask:
    LDA.b !C3_Unk00BE
    BNE .no_quit
    LDA.b !C3_PadHeld
    BIT.w #!C3_PadA
    BEQ .no_quit
    INC.b !C3_Unk00BE
    LDX.w #C3Mod_FadeOutExitTask
    JSR C3Mod_TaskAdd
.no_quit:
    LDA.b !C3_Unk00A2
    BEQ .pad_used
    LDA.b !C3_Unk009E
    CMP.w #!C3_Race009E
    BNE .pad_used
    LDA.b !C3_Unk009C                   ; C = 1 from the CMP
    SBC.w #!C3_Race009C
    BCC .pad_used
    STZ.b !C3_Unk00A2
    LDX.w #C3Mod_RestoreColumnTask
    JSR C3Mod_NmiTaskAdd
.pad_used:
    STZ.b !C3_PadHeld
    LDA.b !C3_Unk00B0
    CMP.w #1
    BEQ .phase1
.to_next:
    JMP C3Mod_Unk48FD
.phase1:
    STZ.b !C3_Unk0098
    LDA.b !C3_Prog9
    BEQ .prog
    LDA.w #!C3_Race0098
    STA.b !C3_Unk0098
.prog:
    LDA.w !C3_EntryArg
    AND.w #!C3_EntryLowNibble
    BEQ .prog0
    LDA.w !C3_SongBusy
    AND.w #!Eng_LowByteMask
    BNE .to_next
    LDA.b !C3_Unk004E
    CMP.w #!C3_Race004EProg9
    BEQ .move_0073
    BMI .up_004E
    SBC.w #!C3_RaceMoveStep
    BRA .round_004E
.up_004E:
    ADC.w #!C3_RaceMoveStep
.round_004E:
    AND.w #!C3_RaceMoveMask
    STA.b !C3_Unk004E
.move_0073:
    LDA.b !C3_Unk0073
    CMP.w #!C3_Race0073Prog9
    BEQ .moved
    BMI .up_0073
    SBC.w #!C3_RaceMoveStep
    BRA .round_0073
.up_0073:
    ADC.w #!C3_RaceMoveStep
.round_0073:
    AND.w #!C3_RaceMoveMask
    STA.b !C3_Unk0073
.moved:
    BRA .count_00B2
.prog0:
    STZ.b !C3_Unk0063
    LDA.b !C3_Unk0051                   ; C = 1 from the CMP #1
    SBC.b !C3_Unk0076
    CMP.w #!C3_Race0088Gap
    BMI .song
    LDA.w #1
    STA.b !C3_Unk0088
.song:
    LDA.w !C3_SongBusy
    AND.w #!Eng_LowByteMask
    BNE .done
    LDA.b !C3_Unk004E
    CMP.w #!C3_Race004EProg0
    BEQ .count_00B2
    BMI .up_004E_prog0
    SBC.w #!C3_RaceMoveStep
    BRA .round_004E_prog0
.up_004E_prog0:
    ADC.w #!C3_RaceMoveStep
.round_004E_prog0:
    AND.w #!C3_RaceMoveMask
    STA.b !C3_Unk004E
.count_00B2:
    SEP #$20
    LDA.b !C3_Unk00B2
    BEQ .test_end
    BPL .down_00B2
    INC A
    BRA .store_00B2
.down_00B2:
    DEC A
.store_00B2:
    STA.b !C3_Unk00B2
.test_end:
    REP #$20
    LDA.b !C3_Unk00B2
    BNE .done
    LDA.b !C3_Unk0088
    BEQ .done
    LDA.b !C3_Unk004E
    AND.w #!C3_Race004EMask
    CMP.w #!C3_Race004EProg0
    BNE .done
    STZ.b !C3_Unk0065
    STZ.b !C3_Unk0067
    INC.b !C3_Unk00B0
    INC.w !C3_Unk1444
.done:
    JMP C3Mod_Unk48FD

; $7E:4755 — C3Mod_WaitSongEndTask (29 bytes, $4755–$4771)
; A task: unless C3_SongBusy, once APUIO3's low nibble is not 0 (the
; sound driver's report on port 3; probably the song's end, not
; traced): C3_FrameCount's low byte = 0, page $0A00 runs
; C3Mod_Prog0Finish and this task hands over to C3Mod_DriftTask.
; Callers note: a task added by LDX #C3Mod_WaitSongEndTask / JSR
;   C3Mod_TaskAdd at $4831 (code not matched yet).
; Entry: a task: M any (8-bit set here), X=0 (the 16-bit pointer
;        store), DP=0 (C3_FrameCount), DB=$00 (absolute).
; Exit:  RTS with M=1, A = C3_SongBusy or the nibble (0); else JMP
;        C3Mod_TaskReplace with X = C3Mod_DriftTask.
C3Mod_WaitSongEndTask:
    SEP #$20
    LDA.w !C3_SongBusy
    BNE .wait
    LDA.w APUIO3
    AND.b #!C3_NibbleMask
    BEQ .wait
    STZ.b !C3_FrameCount
    LDX.w #C3Mod_Prog0Finish
    STX.w !C3_ScriptPageA+!C3Script_Ptr
    LDX.w #C3Mod_DriftTask
    JMP C3Mod_TaskReplace
.wait:
    RTS

; $7E:4772 — C3Mod_Unk4772 (22 bytes, $4772–$4787)
; Eleven words, the numbers with repeated digits 111-666, 888, 999,
; 1111, 2222 and 3333 (no 777); read by
; the CMP $4770,X loop at $47F2 (X = $16 down to 2; code not matched
; yet).
C3Mod_Unk4772:
    dw 111, 222, 333, 444, 555, 666, 888, 999, 1111, 2222, 3333

%C3ModOrg($7E4788)
C3Mod_Rest4788:
    %C3ModRomBytes($7E4788, $7EA651)

; $7E:A651 — C3Mod_StaffTexts (3,886 bytes, $A651–$B57E)
; The staff credits the module shows, in two texts to the module's end:
;   - $A651-$AADA: "PRODUCER/KAZU`KO AOKI@DIRECTOR/..." up to "...KANAME
;     TANAKA@" and a $00: names after their job, "/" between names, "@"
;     between jobs, "`" standing for HI (and "[", "]", "^", "_" for
;     other pairs of letters, probably); $86BF and $86D1 load $A651
;     as a text pointer (into $0382) when C3_EntryArg bits 0-3 are $A
;     ($86BF) or $B ($86D1);
;   - $AADB on: a $1C, then "XEXECUTIVE PRODUCER/..." to the end, the
;     same list with "/" between names, then "CHRONO TRIGGER", the
;     translators, test players and special thanks; no reader of it was
;     found ("X" and the $1C are probably control bytes);
;   - it ends with the module's end marker "\CODE END 7E" (as the kernel
;     ends with "CODE END C3").
; The copy code C3_BuildCopyCode writes at run time ($B574) overwrites
; the last bytes (GENERATED in tools/c3module.py).
%C3ModOrg($7EA651)
C3Mod_StaffTexts:
    db "PRODUCER/KAZU`KO AOKI@DIRECTOR/TAKAS` TOKITA/YOS`NORI KI"
    db "TASE/AKI`KO MATSUI@CHARACTER DESIGN/AKIRA TORIYAMA@SUPER"
    db "VISOR/YUJI HORII/`RONOBU SAKAGUC`@MUSIC/YASUNORI MITSUDA"
    db "/NOBUO UEMATSU@MAIN PROGRAM/KEIZO KOKUBO/KATSU`SA `GUC`@"
    db "SOUND PROGRAM/MINORU AKAO@SOUND ENGINEER/EIJI NAKAMURA@G"
    db "RAP`C DIRECTOR/YASU`KO KAMATA/MASANORI HOS`NO/TETSUYA TA"
    db "K]^_`@STORY PLAN/MASATO KATO@EVENT PLAN/`ROYUKI ITOU/KEI"
    db "SUKE MATSUHARA/`ROKI C`BA@FIELD PLAN/KEITA ETO/KENIC` NI"
    db "S`@BATTLE PLAN/MAKOTO S`MAMOTO/HARUYUKI NIS`DA/TOS`AKI S"
    db "UZUKI@BATTLE PROGRAM/TOS`O ENDO/KIYOS` YOS`I@WORLDMAP PR"
    db "OGRAM/KAZUMI KOBAYAS`@MENU PROGRAM/AKI`RO S`MIZU@VISUAL "
    db "PROGRAM/KOJI SUGIMOTO/KEN NARITA@EFFECT GRAP`C/`ROKATSU "
    db "SASAKI/YUKIO NAKATANI@FIELD GRAP`C/S`NIC`RO OKANIWA/MANA"
    db "BU DAIS`MA/TOS`YA HASUI/MATSUZO ITAKURA@FIELD GRAP`C/TET"
    db "SUYA NOMURA/KAZU`RO OKAWA/YOS`NORI OGURA@FIELD GRAP`C/YU"
    db "SUKE NAORA/TAKAMIC` S`BUYA/S`NIC`RO HAMASAKA/AKIYOS` MAS"
    db "UDA@FIELD GRAP`C/MASAAKI HAYAS`/TAKAYUKI ODAC`/YASUYUKI "
    db "HONNE@CHARACTER GRAP`C/`ROS` UC`YAMA/TAIZO INUKAI/FUMI N"
    db "AKAS`MA@MONSTER GRAP`C/KOUIC` EBE/TSUTOMU TERADA/TADA`RO"
    db " USUDA@MAP DESIGN/MAMI KAWAI/AKANE HARUKI/`ROTO YAMAMOTO"
    db "@MAP DESIGN/`DETOS` KEZUKA/KANAME TANAKA@"
    db $00
    db $1C
    db "XEXECUTIVE PRODUCER/TETSUO MIZUNO/`TOS` TAKEMURA/`SAS` S"
    db "UZUKI@PRODUCER//KAZUHIKO AOKI/////DIRECTOR//TAKASHI TOKI"
    db "TA/YOSHINORI KITASE/AKIHIKO MATSUI/////CHARACTER DESIGN/"
    db "/AKIRA TORIYAMA/////SUPERVISOR//YUJI HORII/HIRONOBU SAKA"
    db "GUCHI/////MUSIC//YASUNORI MITSUDA/NOBUO UEMATSU/////MAIN"
    db " PROGRAM//KEIZO KOKUBO/KATSUHISA HIGUCHI/////SOUND PROGR"
    db "AM//MINORU AKAO/////SOUND ENGINEER//EIJI NAKAMURA/////GR"
    db "APHIC DIRECTOR//YASUHIKO KAMATA/MASANORI HOSHINO/TETSUYA"
    db " TAKAHASHI/////STORY PLAN//MASATO KATO/////EVENT PLAN//H"
    db "IROYUKI ITOU/KEISUKE MATSUHARA/HIROKI CHIBA/////FIELD PL"
    db "AN//KEITA ETO/KENICHI NISHI/////BATTLE PLAN//MAKOTO SHIM"
    db "AMOTO/HARUYUKI NISHIDA/TOSHIAKI SUZUKI/////BATTLE PROGRA"
    db "M//TOSHIO ENDO/KIYOSHI YOSHII/////WORLDMAP PROGRAM//KAZU"
    db "MI KOBAYASHI/////MENU PROGRAM//AKIHIRO SHIMIZU/////VISUA"
    db "L PROGRAM//KOJI SUGIMOTO/KEN NARITA/////EFFECT GRAPHIC//"
    db "HIROKATSU SASAKI/YUKIO NAKATANI/////FIELD GRAPHIC//SHINI"
    db "CHIRO OKANIWA/MANABU DAISHIMA/TOSHIYA HASUI/MATSUZO ITAK"
    db "URA//TETSUYA NOMURA/KAZUHIRO OKAWA/YOSHINORI OGURA/YUSUK"
    db "E NAORA/TAKAMICHI SHIBUYA/SHINICHIRO HAMASAKA/AKIYOSHI M"
    db "ASUDA/MASAAKI HAYASHI/TAKAYUKI ODACHI/YASUYUKI HONNE////"
    db "/CHARACTER GRAPHIC//HIROSHI UCHIYAMA/TAIZO INUKAI/FUMI N"
    db "AKASHIMA/////MONSTER GRAPHIC//KOUICHI EBE/TSUTOMU TERADA"
    db "/TADAHIRO USUDA/////MAP DESIGN//MAMI KAWAI/AKANE HARUKI/"
    db "HIROTO YAMAMOTO/HIDETOSHI KEZUKA/KANAME TANAKA/////EXECU"
    db "TIVE PRODUCER//TETSUO MIZUNO/HITOSHI TAKEMURA/HISASHI SU"
    db "ZUKI//////////////////////////////////      CHRONO TRIGG"
    db "ER//////////\\//////TRANSLATOR//TED WOOLSEY//WEIMIN LI/"
    db "AIKO ITO/RIKA MARUYA/NORIKO WADA/////SOUND EFFECT//YOSHITA"
    db "KA HIROTA/CHIHARU MINEKAWA/TADAKAZU OKANO/YASUAKI YABUTA"
    db "/////TEST PLAYER//KENICHI SHINODA/KEN SAKUYAMA/TOMOKO MO"
    db "RIYASU/HARUO OGURA/HIROTSUGU YAMAMOTO/REO NOMOTO/AKIHIRO"
    db " ICHIKAWA/AKITOSHI TAKAHASHI/////////ADVERTISEMENT//K[YA"
    db "MASHITA/Y[HIRATA/T[NOMURA/K[SOUSUI/T[TSURUZONO/M[OKAMIYA"
    db "/N[WATANABE/K[MAEDA/M[MIZUSHIMA/////SYSTEM ADMINISTER//M"
    db "[NAKAJIMA/M[OGURA/Y[ORIKASA/Y[OHDAIRA/////TEST COORDINAT"
    db "OR//S[KAJITANI/R[KODA/K[INAGI/N[HANADA/H[MASUDA/N[KANAI/"
    db "H[SAKURAI/////SPECIAL THANKS//K[TORISHIMA///N[HORIE/F[TA"
    db "KEDA/T[TAKAHASHI/T[KONDOH//S[HASHIMOTO////K[ADACHI/Y[KUW"
    db "AHARA/H[OKAWA/Y[UENISHI///N[MATSUEDA/I[DOBASHI/M[SAITO/H"
    db "[KAWAI///S[MORIYA/K[SUZUKI/T[KONDO/S[TANAKA////K[TANIKAW"
    db "A/J[SAITO/S[HIDAKI/K[OOGO/H[SUZUKI/M[ITOH/R[MIYAMOTO///H"
    db "[YOKOTA/M[YUMOTO/N[ISHIKAWA/H[KIZUKA/S[ARAI/K[MATSUMOTO/"
    db "K[HIRATA/M[KOUNO/R[TSUKAKOSHI/K[KANEKO/H[SHIMODAIRA/M[NO"
    db "UMURA/A[HINO/H[HAMADA///T[OHNO/H[NOGUCHI/M[HORIE/M[MORI/"
    db "M[KOBAYASHI///M[KANESHIGE/M[SOMENO/Y[TANAKA/R[TAKEDA///T"
    db "[MORITA/Y[SUEMITSU/W[SATO/H[NAKAMURA/S[AOYAMA/H[NAGAHARA"
    db "/H[SHINGU///R[SILVEIRA/J[YANAGIHARA/T[HORII/D[SMITH/C[CH"
    db "AMBERLAIN/E[GREGORY/D[ABRAHAM/C[BUDD/M[FREGUIA//////////"
    db "///////////////////////\\CODE END 7E"

incsrc "unmatched.asm"
