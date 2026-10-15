; ============================================================
; SPC700 sound driver (bank $C7 boot block 0)
; ROM $C7:24C3: a length word ($1BEF), then the program, $C7:24C5-$40B3,
; which Audio_Boot sends through the IPL ROM to ARAM $0200-$1DEE and
; starts at $0200 (Audio_BootBlockPtrs / Audio_BootBlockAram).
;
; Assembled in asar's spc700 mode: %SpcOrg(aram) puts the bytes at the
; ROM address of an ARAM address (ROM = $C7:24C5 + aram - $0200) while
; labels take the ARAM address (asar's `base`). Every direct-page and
; absolute operand has an explicit .b / .w width.
;
; Layout of the block (tools/spc700.py traces it from $0200 and the
; dispatch tables; NEXT.md, the SPC700 item, has the evidence):
;   $0200-$1543  code
;   $1544-$1721  tables: transfer modes, sequence commands $C4-$FF (handlers,
;                operand counts, second handlers), CPU commands
;                (Spc_CmdTable10, Spc_CmdFirstTable10, Spc_CmdTable80), the
;                DSP shadow lists (Spc_ShadowRegs / Spc_ShadowSources)
;   $1722-$1D6C  code (sequence command handlers and helpers)
;   $1D6D-$1DEE  tables (pitch, FIR sets, ...) and Spc_BuiltinSample
; Only part of the block is matched (symbols/spc700_functions.csv, from
; tools/progress.py, lists it); the rest, and the length word, is still
; original bytes, and the names this code uses there are label-only in
; asm/spc700/unmatched.asm.
;
; Header convention (STYLE.md's, with the SPC700's state):
;   Entry/Exit: P (the direct-page flag: P=0 puts the direct page at
;   $0000, P=1 at $0100), A, X, Y (YA for word results), SP when moved,
;   and the PSW flags callers branch on; the DSP registers written
;   ("DSP:") and the port protocol with the 65816 side ("Ports:") where
;   a routine reads or writes CPUIO0-3. The driver runs with I=0
;   (interrupts are never used: DI at the start) and P=0 except where a
;   header says otherwise.
; Callers are hand-written (`; Callers note:`): tools/callers.py and
; tools/xref.py read 65816 code only.
; ============================================================

macro SpcOrg(aram)
    base off
    org !AudioRom_SpcDriver+2+<aram>-!AudioAram_Driver
    base <aram>
endmacro

arch spc700

; ============================================================
; Start and main loop ($0200-$0376)
; ============================================================

; $0200 — Spc_Start (153 bytes, $0200–$0298; ROM $C7:24C5–$255D)
; The driver's entry point: the IPL ROM jumps here when Audio_Boot's
; last step names $0200. It sets the stack, clears the direct page
; $00-$EF and sets up:
;   - !Spc_CurSong, !Spc_SavedSong and !Spc_NewSong = $FF (none);
;   - echo volume 0 (EVOLL/EVOLR), the !Spc_CmdQueue entries free;
;   - DIR = the page of !AudioAram_Dir, every voice's GAIN =
;     !DSP_GAIN_Start;
;   - the port latches cleared, timer 0 every 5.25 ms (one main-loop
;     pass), timer 1 every 16 ms, both on;
;   - the echo delay !Spc_StartEchoDelay through command $FC's handler
;     (Spc_CmdSetEchoDelay with !Spc_CmdArg0 = 5);
;   - !Spc_KofShadow = $FF (every voice keyed off on the first pass),
;     !Spc_FadeTimer = 7, the three !Spc_GroupVol volumes $FF with no
;     fade running;
;   - directory entry !Spc_BuiltinDirEntry ($1E40) = Spc_BuiltinSample /
;     Spc_BuiltinSampleLoop, its ParamB word $FF $E0 ($1FA0) and its
;     ParamA word $E1 $00 ($1F20) (boot block 3 holds entries 0-8, a
;     song load writes entries $20-$2F);
;   - main volume !DSP_MVOL_Start on both sides, !Spc_UnkD8 = 2;
; then falls into Spc_MainLoop.
; Callers note: no CALL or JMP; reached from the IPL ROM (Audio_Boot).
; Entry: SP, P, A, X, Y any (all set here); ARAM as the boot blocks left
;        it
; Exit:  falls into Spc_MainLoop with P=0, I=0, SP=$FF, X=0, A =
;        !DSP_MVOL_Start, Y = !DSP_MVOLR
; DSP:   EVOLL, EVOLR, DIR, GAIN of voices 0-7, MVOLL, MVOLR (and what
;        Spc_CmdSetEchoDelay writes)
; Callees: Spc_WriteDsp, Spc_CmdSetEchoDelay
%SpcOrg($0200)
Spc_Start:
    clrp
    di
    mov x,#!Spc_StackTop
    mov sp,x
    mov a,#$00
    mov x,a
.clear:
    mov (x+),a
    cmp x,#!Spc_ClearEnd
    bne .clear
    dec.b !Spc_CurSong                  ; $FF: none
    decw.b !Spc_SavedSong               ; and !Spc_NewSong: $FF
    mov y,#!DSP_EVOLL
    call Spc_WriteDsp
    mov y,#!DSP_EVOLR
    call Spc_WriteDsp
    mov x,#!Spc_QueueBytes
.free_queue:
    mov.w !Spc_CmdQueue-!Spc_QueueEntry+x,a ; the entry's id byte
    dec x
    dec x
    dec x
    dec x
    bne .free_queue
    mov a,#!AudioAram_Dir>>8
    mov y,#!DSP_DIR
    call Spc_WriteDsp
    mov y,#!DSP_GAIN
    mov x,#!DSP_GAIN_Start
.gain:
    mov.b !SPC_DSPADDR,y
    mov.b !SPC_DSPDATA,x
    mov a,y
    clrc
    adc a,#!DSP_VoiceStride
    mov y,a
    bpl .gain                           ; voices 0-7 ($07-$77)
    mov.b !SPC_CONTROL,#!SPC_CONTROL_ClearPorts
    mov.b !SPC_T0TARGET,#!SPC_Timer0Divider
    mov.b !SPC_T1TARGET,#!SPC_Timer1Divider
    mov.b !SPC_CONTROL,#!SPC_CONTROL_Timers01
    mov.b !Spc_CmdArg0,#!Spc_StartEchoDelay
    call Spc_CmdSetEchoDelay
    dec.b !Spc_KofShadow                ; $FF: key off every voice on the first pass
    mov.b !Spc_FadeTimer,#!Spc_FadeTicks
    mov x,#6                            ; groups 2, 1, 0 (X = 2 x (group + 1))
.groups:
    mov a,#!Spc_GroupVolStart
    mov.w !Spc_GroupVol+1-2+x,a         ; the volume (high byte)
    inc a
    mov.w !Spc_GroupFadeSteps-2+x,a     ; no fade running
    dec x
    dec x
    bne .groups
    mov a,#Spc_BuiltinSample&$FF
    mov.w !Spc_BuiltinDir,a
    mov a,#Spc_BuiltinSample>>8
    mov.w !Spc_BuiltinDir+1,a
    mov a,#Spc_BuiltinSampleLoop&$FF
    mov.w !Spc_BuiltinDir+2,a
    mov a,#Spc_BuiltinSampleLoop>>8
    mov.w !Spc_BuiltinDir+3,a
    mov a,#!Spc_BuiltinParamB0
    mov.w !Spc_BuiltinParamB,a
    mov a,#!Spc_BuiltinParamB1
    mov.w !Spc_BuiltinParamB+1,a
    mov a,#!Spc_BuiltinParamA0
    mov.w !Spc_BuiltinParamA,a
    mov a,#!Spc_BuiltinParamA1
    mov.w !Spc_BuiltinParamA+1,a
    mov a,#!DSP_MVOL_Start
    mov y,#!DSP_MVOLL
    call Spc_WriteDsp
    mov y,#!DSP_MVOLR
    call Spc_WriteDsp
    mov.b !Spc_UnkD8,#!Spc_UnkD8Start

; $0299 — Spc_MainLoop (222 bytes, $0299–$0376; ROM $C7:255E–$263B)
; The driver's loop: one pass per tick of timer 0 (5.25 ms).
;   1. Spc_PollCommand until timer 0 has ticked (a command that came in
;      runs at once). Reading T0OUT clears its count, so ticks beyond the
;      first are dropped: a late pass is not made up.
;   2. Writes the 17 DSP registers of Spc_ShadowRegs from their shadows
;      (Spc_ShadowSources: FIR7 ... FIR0 from !Spc_FirShadow, EFB, EVOLR
;      and EVOLL from !Spc_EvolShadow, EON, KOF, FLG, NON, PMON, KON last),
;      then clears !Spc_KonShadow and !Spc_KofShadow. !Spc_EvolShadow is
;      !Spc_EchoVolume, doubled when !Spc_Flags87 bit 3 is set (to $7F
;      only when the shift carries out: a volume of $40-$7F doubles to
;      $80-$FE). Quirk: the BRA after `mov a,#!Spc_EvolMax` branches to
;      the next instruction.
;   3. Unless !Spc_Flags88 bit 7 is set (then Spc_Unk1438 instead), the
;      ports the 65816 reads: CPUIO0 = 0, CPUIO1 = the song's fade steps
;      left (!Spc_GroupFadeSteps), CPUIO2 = !Spc_UnkD3 (nibbles swapped)
;      OR !Spc_Unk7B, CPUIO3 = the voices in use: (!Spc_SongTracks' two
;      nibbles ORed, low nibble) OR !Spc_SfxVoices.
;   4. With !Spc_Flags87 bit 4 set, back to 1. Every 7th pass
;      (!Spc_FadeTimer) the fades (Spc_Unk1492); then the tempo step
;      (Spc_StepTracks) and the queued commands (Spc_RunQueue); bit 4 again.
;   5. The song's tracks (voice bits !Spc_SongTracks AND !Spc_Unk24,
;      less !Spc_SfxVoices), X = 0, 2, ...: Spc_TrackEffects, or Spc_WriteVoice
;      while any effect plays, with !Spc_GroupVolume = the song's volume;
;      Spc_QueueCommand after each.
;   6. The effect tracks (!Spc_SfxVoices AND !Spc_Unk25), X = $1E down:
;      tracks 15-14 with the second volume, 13-8 with the third,
;      Spc_TrackEffects and Spc_QueueCommand for each.
;   7. Clears !Spc_UnkD0/!Spc_UnkD1, runs the queue again (Spc_RunQueue)
;      and Spc_AnimateBuiltin, and goes back to 1.
; Callers note: Spc_Start falls in; JMP from Spc_StartSong ($0CF3, with
;   SP reset); the pass loops back here (JMP $0374, BEQ/BBS inside).
; Entry: P=0; SP as Spc_Start or Spc_StartSong leaves it
; Exit:  does not return
; Ports: CPUIO0-3 as in 3; commands through Spc_PollCommand
; DSP:   the 17 shadowed registers each pass
; Callees: Spc_PollCommand, Spc_Unk1438, Spc_Unk1492, Spc_StepTracks,
;   Spc_RunQueue, Spc_TrackEffects, Spc_WriteVoice, Spc_QueueCommand, Spc_AnimateBuiltin
Spc_MainLoop:
    call Spc_PollCommand
    mov.b y,!SPC_T0OUT
    beq Spc_MainLoop
    mov y,#!Spc_NumShadowRegs
    mov.b a,!Spc_EchoVolume
    bbc.b !Spc_Flags87.3,.set_evol
    asl a
    bcc .set_evol
    mov a,#!Spc_EvolMax
    bra .set_evol                       ; to the next instruction
.set_evol:
    mov.b !Spc_EvolShadow,a
.write_dsp:
    mov.w a,Spc_ShadowRegs-1+y
    mov.b !SPC_DSPADDR,a
    mov.w a,Spc_ShadowSources-1+y
    mov x,a
    mov a,(x)
    mov.b !SPC_DSPDATA,a
    dbnz y,.write_dsp
    mov.b !Spc_KofShadow,y
    mov.b !Spc_KonShadow,y
    bbs.b !Spc_Flags88.7,.report
    mov.b a,!Spc_SongTracks
    xcn a
    or.b a,!Spc_SongTracks
    and a,#!Spc_LowNibble               ; voice n or n+4
    or.b a,!Spc_SfxVoices
    mov y,a
    mov.b a,!Spc_UnkD3
    xcn a
    or.b a,!Spc_Unk7B
    movw.b !SPC_CPUIO2,ya
    mov.w y,!Spc_GroupFadeSteps
    mov a,#$00
    movw.b !SPC_CPUIO0,ya
    bra .ports_done
.report:
    call Spc_Unk1438
.ports_done:
    bbs.b !Spc_Flags87.4,Spc_MainLoop
    dec.b !Spc_FadeTimer
    bne .no_fade
    mov.b !Spc_FadeTimer,#!Spc_FadeTicks
    call Spc_Unk1492
.no_fade:
    call Spc_StepTracks
    call Spc_RunQueue
    bbs.b !Spc_Flags87.4,Spc_MainLoop
    mov x,#$00
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit0
    mov.b a,!Spc_SfxVoices
    eor a,#!Spc_InvertBits
    and.b a,!Spc_SongTracks
    and.b a,!Spc_Unk24
    mov.b !Spc_TrackBits,a
    mov.w a,!Spc_GroupVol+1             ; group 0: the song
    mov.b !Spc_GroupVolume,a
    bra .song_next
.song_track:
    mov.b !Spc_CurTrack,x
    mov.b a,!Spc_SfxVoices
    bne .with_sfx
    call Spc_TrackEffects
    bra .song_stepped
.with_sfx:
    call Spc_WriteVoice
.song_stepped:
    call Spc_QueueCommand
.song_skip:
    inc x
    inc x
    asl.b !Spc_VoiceBit
.song_next:
    lsr.b !Spc_TrackBits
    bcs .song_track
    bne .song_skip
    mov x,#!Spc_TrackSfxLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
    mov.b a,!Spc_SfxVoices
    and.b a,!Spc_Unk25
    mov.b !Spc_TrackBits,a
    mov.w a,!Spc_GroupVol+3             ; group 1: tracks 15-14
    mov.b !Spc_GroupVolume,a
    bra .sfx_a_next
.sfx_a_track:
    mov.b !Spc_CurTrack,x
    call Spc_TrackEffects
    call Spc_QueueCommand
.sfx_a_skip:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
    bbs.b !Spc_VoiceBit.5,.sfx_b        ; voices 7-6 done
.sfx_a_next:
    asl.b !Spc_TrackBits
    bcs .sfx_a_track
    bra .sfx_a_skip
.sfx_b:
    mov.w a,!Spc_GroupVol+5             ; group 2: tracks 13-8
    mov.b !Spc_GroupVolume,a
    bra .sfx_b_next
.sfx_b_track:
    mov.b !Spc_CurTrack,x
    call Spc_TrackEffects
    call Spc_QueueCommand
.sfx_b_skip:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
.sfx_b_next:
    asl.b !Spc_TrackBits
    bcs .sfx_b_track
    bne .sfx_b_skip
    mov a,#$00
    mov y,a
    movw.b !Spc_UnkD0,ya                ; and !Spc_UnkD1
    call Spc_RunQueue
    call Spc_AnimateBuiltin
    jmp Spc_MainLoop


; ============================================================
; Track stepping ($0377-$07A2)
; ============================================================

; $0377 — Spc_StepTracks (158 bytes, $0377–$0414; ROM $C7:263C–$26D9)
; Steps the song's tracks and the effect tracks for one pass:
;   1. Unless !Spc_Flags88 bit 5 is set (command $F6: every pass steps),
;      the song's tempo: !Spc_Tempo, raised with !Spc_TempoAdjHi below $80
;      (+ 2 x tempo x adj / 256, capped at $FF) or lowered with it from
;      $80 up (tempo x adj / 256, at least 1), is added to
;      !Spc_TempoAccum; without a carry the song does not step.
;   2. Each track of !Spc_SongTracks (X = 0, 2, ...; !Spc_CurTrack): its
;      wait counts down; at 0 Spc_TrackStep takes its next note (a track
;      that ends there, !Spc_Flags88 bit 3, is not updated further). With
;      the wait at 2, unless the voice is in !Spc_Unk5A (the next note
;      follows on: a tie, or !Spc_Unk5C/60), the voice is cleared from
;      !Spc_Unk24 and keyed off (!Spc_KofShadow), unless an effect holds
;      it. Then Spc_TrackSlides and Spc_QueueCommand.
;   3. After the song's tracks: Spc_StepSongFades, and the effect voices
;      are cleared from !Spc_UnkD0 and !Spc_UnkD1.
;   4. The effects' tempo: !Spc_SfxTempo ($81) added to
;      !Spc_SfxTempoAccum (skipped, and the effects step, with bit 5 set);
;      on the carry effect tracks 12-15 (X = $18 up, the voices of the high
;      nibble of !Spc_SfxVoices) step as in 2, with !Spc_Unk5B and
;      !Spc_Unk25 for !Spc_Unk5A and !Spc_Unk24. Effect tracks 8-11 are
;      never stepped (effects only use voices 4-7).
; Quirk (a byte shared by two instructions): for an effect track the BCS
; lands on the operand byte of `mov a,#$FC`, which is `inc y`, so Y = 1
; picks the effect bytes ($5B, $25) and Y = 0 the song's.
; Callers note: CALL from Spc_MainLoop ($02EF).
; Entry: P=0
; Exit:  A, X, Y clobbered
; Callees: Spc_TrackStep, Spc_TrackSlides, Spc_QueueCommand,
;   Spc_StepSongFades
Spc_StepTracks:
    bbs.b !Spc_Flags88.5,.song
    mov.b a,!Spc_Tempo
    mov.b y,!Spc_TempoAdjHi
    beq .add
    mul ya
    mov a,y
    bbs.b !Spc_TempoAdjHi.7,.slower
    asl a
    clrc
    adc.b a,!Spc_Tempo
    bcc .add
    mov a,#!Spc_TempoMax
    bra .add
.slower:
    bne .add
    inc a
.add:
    clrc
    adc.b a,!Spc_TempoAccum
    mov.b !Spc_TempoAccum,a
    bcc .sfx_tempo
.song:
    mov x,#$00
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit0
    mov.b !Spc_TrackBits,!Spc_SongTracks
    bra .loop
.track:
    mov.b !Spc_CurTrack,x
    dec.b !Spc_TrackWait+x
    bne .waiting
    clr1.b !Spc_Flags88.3
    call Spc_TrackStep
    bbc.b !Spc_Flags88.3,.update
    bra .next
.waiting:
    mov y,#$00
    cmp x,#!Spc_TrackFirstSfx
    bcs .sfx_y+1                        ; effect track: on the `inc y` inside .sfx_y
.sfx_y:
    mov a,#$FC                          ; lint-ok: $FC is the `inc y` the BCS above lands on
    mov a,#$02
    cbne.b !Spc_TrackWait+x,.update
    mov.w a,!Spc_Unk5A+y
    and.b a,!Spc_VoiceBit
    bne .update
    mov.b a,!Spc_VoiceBit
    eor a,#!Spc_InvertBits
    and.w a,!Spc_Unk24+y
    mov.w !Spc_Unk24+y,a
    mov a,y
    bne .key_off
    mov.b a,!Spc_SfxVoices
    and.b a,!Spc_VoiceBit
    bne .update
.key_off:
    or.b !Spc_KofShadow,!Spc_VoiceBit
.update:
    call Spc_TrackSlides
    call Spc_QueueCommand
.next:
    inc x
    inc x
    asl.b !Spc_VoiceBit
.loop:
    lsr.b !Spc_TrackBits
    bcs .track
    bne .next
    cmp x,#!Spc_TrackSfxStep
    bcs .done
    call Spc_StepSongFades
    mov.b a,!Spc_SfxVoices
    tclr.w !Spc_UnkD0,a
    tclr.w !Spc_UnkD1,a
.sfx_tempo:
    bbs.b !Spc_Flags88.5,.sfx
    mov a,#!Spc_SfxTempo
    clrc
    adc.b a,!Spc_SfxTempoAccum
    mov.b !Spc_SfxTempoAccum,a
    bcc .done
.sfx:
    mov x,#!Spc_TrackSfxStep
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit4
    mov.b a,!Spc_SfxVoices
    xcn a
    mov.b !Spc_TrackBits,a
    bra .loop
.done:
    ret

; $0415 — Spc_LivePass (79 bytes, $0415–$0463; ROM $C7:26DA–$2728)
; One pass of the song alone, for Spc_XferLive (mode 5) to run while it
; waits for a step: unless paused (!Spc_Flags87 bit 4), writes the DSP
; shadows (Spc_ShadowRegs, as Spc_MainLoop does) and clears the KON / KOF
; shadows, counts !Spc_FadeTimer (Spc_Unk1492 every 7th pass), steps the
; song (Spc_StepSongOnly), runs Spc_TrackEffects for the song's tracks
; (!Spc_SongTracks and !Spc_Unk24, less !Spc_SfxVoices) with the song's
; volume, and clears !Spc_UnkD0 / !Spc_UnkD1. No effect tracks, no
; command queue, no port report.
; Callers note: CALL from Spc_XferLive ($1124).
; Entry: P=0
; Exit:  A, X, Y clobbered (A = Y = 0 unless paused)
; DSP:   the 17 shadowed registers
; Callees: Spc_Unk1492, Spc_StepSongOnly, Spc_TrackEffects
Spc_LivePass:
    bbs.b !Spc_Flags87.4,.done
    mov y,#!Spc_NumShadowRegs
.write_dsp:
    mov.w a,Spc_ShadowRegs-1+y
    mov.b !SPC_DSPADDR,a
    mov.w a,Spc_ShadowSources-1+y
    mov x,a
    mov a,(x)
    mov.b !SPC_DSPDATA,a
    dbnz y,.write_dsp
    mov.b !Spc_KofShadow,y
    mov.b !Spc_KonShadow,y
    dec.b !Spc_FadeTimer
    bne .no_fade
    mov.b !Spc_FadeTimer,#!Spc_FadeTicks
    call Spc_Unk1492
.no_fade:
    call Spc_StepSongOnly
    mov x,#$00
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit0
    mov.b a,!Spc_SfxVoices
    eor a,#!Spc_InvertBits
    and.b a,!Spc_SongTracks
    and.b a,!Spc_Unk24
    mov.b !Spc_TrackBits,a
    mov.w a,!Spc_GroupVol+1
    mov.b !Spc_GroupVolume,a
    bra .loop
.track:
    mov.b !Spc_CurTrack,x
    call Spc_TrackEffects
.next:
    inc x
    inc x
    asl.b !Spc_VoiceBit
.loop:
    lsr.b !Spc_TrackBits
    bcs .track
    bne .next
    mov a,#$00
    mov y,a
    movw.b !Spc_UnkD0,ya
.done:
    ret

; $0464 — Spc_StepSongOnly (99 bytes, $0464–$04C6; ROM $C7:2729–$278B)
; Spc_StepTracks for the song alone (Spc_LivePass): the tempo step
; (without the !Spc_Flags88 bit 5 bypass), the song's tracks with the
; key-off two passes before a note's end (!Spc_Unk5A, !Spc_Unk24; no
; Y-indexed form) and Spc_TrackSlides, then Spc_StepSongFades; no
; Spc_QueueCommand.
; Callers note: CALL from Spc_LivePass ($0436).
; Entry: P=0
; Exit:  A, X, Y clobbered
; Callees: Spc_TrackStep, Spc_TrackSlides, Spc_StepSongFades
Spc_StepSongOnly:
    mov.b a,!Spc_Tempo
    mov.b y,!Spc_TempoAdjHi
    beq .add
    mul ya
    mov a,y
    bbs.b !Spc_TempoAdjHi.7,.slower
    asl a
    clrc
    adc.b a,!Spc_Tempo
    bcc .add
    mov a,#!Spc_TempoMax
    bra .add
.slower:
    bne .add
    inc a
.add:
    clrc
    adc.b a,!Spc_TempoAccum
    mov.b !Spc_TempoAccum,a
    bcc .done
    mov x,#$00
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit0
    mov.b !Spc_TrackBits,!Spc_SongTracks
    bra .loop
.track:
    mov.b !Spc_CurTrack,x
    dec.b !Spc_TrackWait+x
    bne .waiting
    clr1.b !Spc_Flags88.3
    call Spc_TrackStep
    bbc.b !Spc_Flags88.3,.update
    bra .next
.waiting:
    mov a,#$02
    cbne.b !Spc_TrackWait+x,.update
    mov.b a,!Spc_Unk5A
    and.b a,!Spc_VoiceBit
    bne .update
    mov.b a,!Spc_VoiceBit
    tclr.w !Spc_Unk24,a
    mov.b a,!Spc_SfxVoices
    and.b a,!Spc_VoiceBit
    bne .update
    or.b !Spc_KofShadow,!Spc_VoiceBit
.update:
    call Spc_TrackSlides
.next:
    inc x
    inc x
    asl.b !Spc_VoiceBit
.loop:
    lsr.b !Spc_TrackBits
    bcs .track
    bne .next
    call Spc_StepSongFades
.done:
    ret

; $04C7 — Spc_StepSongFades (64 bytes, $04C7–$0506; ROM $C7:278C–$27CB)
; One step of each of the song's own fades that is running: the tempo
; (!Spc_TempoWord += !Spc_TempoFadeDelta, !Spc_TempoFadeSteps), the echo
; volume (!Spc_EchoVolWord, !Spc_EchoVolDelta, !Spc_EchoVolSteps), EFB
; (!Spc_EfbWord, !Spc_EfbDelta, !Spc_EfbSteps) and the eight FIR
; coefficients (!Spc_FirWord += !Spc_FirDelta, !Spc_FirSteps). The fades
; are set by sequence commands (not matched; probably).
; Callers note: CALL from Spc_StepTracks ($03F1) and Spc_StepSongOnly
;   ($04C3).
; Entry: P=0
; Exit:  A, Y clobbered; X = 0 after a FIR step, else unchanged
Spc_StepSongFades:
    mov.b a,!Spc_TempoFadeSteps
    beq .echo
    dec.b !Spc_TempoFadeSteps
    movw.b ya,!Spc_TempoFadeDelta
    addw.b ya,!Spc_TempoWord
    movw.b !Spc_TempoWord,ya
.echo:
    mov.b a,!Spc_EchoVolSteps
    beq .efb
    dec.b !Spc_EchoVolSteps
    movw.b ya,!Spc_EchoVolDelta
    addw.b ya,!Spc_EchoVolWord
    movw.b !Spc_EchoVolWord,ya
.efb:
    mov.b a,!Spc_EfbSteps
    beq .fir
    dec.b !Spc_EfbSteps
    movw.b ya,!Spc_EfbDelta
    addw.b ya,!Spc_EfbWord
    movw.b !Spc_EfbWord,ya
.fir:
    mov.b a,!Spc_FirSteps
    beq .done
    dec.b !Spc_FirSteps
    mov x,#!Spc_FirBytes
.fir_loop:
    mov.b a,!Spc_FirWord-2+x
    clrc
    adc.w a,!Spc_FirDelta-2+x
    mov.b !Spc_FirWord-2+x,a
    mov.b a,!Spc_FirWord-2+1+x
    adc.w a,!Spc_FirDelta-2+1+x
    mov.b !Spc_FirWord-2+1+x,a
    dec x
    dec x
    bne .fir_loop
.done:
    ret

; $0507 — Spc_TrackStep (438 bytes, $0507–$06BC; ROM $C7:27CC–$2981)
; (with its sub-entry Spc_TrackLookAhead)
; Takes the next note of track X (!Spc_CurTrack = X, !Spc_VoiceBit its
; voice). Sequence bytes $C4-$FF are commands (Spc_RunSeqCommand), run
; until a byte below $C4 comes:
;   - its length: when no command has set !Spc_TrackWait,
;     Spc_DurationTable[byte % 14];
;   - $B6-$C3: a rest: nothing more;
;   - $A8-$B5: a tie: only Spc_TrackLookAhead;
;   - $00-$A7: a note, index byte / 14 (0-11). Its note number: for a
;     song track in drum mode (!Spc_Unk7C) Spc_DrumNote's, else the low
;     byte of !Spc_TrackF200 + the index; + the transpose (!Spc_TrackF360
;     high byte) - 10, kept in !Spc_TrackF3A0's high byte. Its pitch
;     (Spc_NotePitch) goes to !Spc_TrackPitch. With a vibrato depth byte
;     (!Spc_Track150 high byte): Spc_Unk18A2, and the depth in pitch units
;     (!Spc_TrackF300) = pitch x Spc_VibDepthTable[0, or !Spc_TrackUnk110
;     for an effect track] / 256 (the pitch itself when that byte is 0).
;     With a tremolo byte (!Spc_Track170): Spc_Unk1960. Clears the vibrato
;     offset, the tremolo phase and the pitch slide. A song track adds its
;     voice to !Spc_Unk24 (an effect track to !Spc_Unk25); a song track
;     whose voice an effect holds goes on to Spc_TrackLookAhead without a
;     key-on. Key-on (!Spc_KonShadow) unless the voice is in !Spc_Unk5C
;     (!Spc_Unk5D) and not !Spc_Unk60 (!Spc_Unk61) and was keyed on before
;     (!Spc_Unk5E / 5F, set at the first): legato, probably. Then the voice
;     is marked in !Spc_UnkD0 / !Spc_UnkD1 (volume and pitch rewritten) and
;     Spc_Unk1AED writes its sample (and ADSR).
; Spc_TrackLookAhead (188 bytes, $0601–$06BC) then finds the next note
; (Spc_PeekNote): a tie sets the voice in !Spc_Unk5A (!Spc_Unk5B for
; effects: no key-off before it); a rest clears it from !Spc_Unk5C/60
; (5D/61); for a note or rest the !Spc_Unk5A bit is set from
; !Spc_Unk5C | !Spc_Unk60. A pitch slide asked for (!Spc_Track150 low
; byte, semitones) moves the note ahead by that much and sets the step
; (!Spc_TrackF3C0 / !Spc_TrackF4E0, 24 bits) to (target - pitch) x 256 /
; the slide's steps (!Spc_TrackF360 low byte; 0: the whole difference),
; signed, then clears the request and the pitch fraction.
; Callers note: CALL from Spc_StepTracks ($03AB) and Spc_StepSongOnly
;   ($0495). Spc_TrackLookAhead: JMP from $052C (a tie, inside).
; Entry: P=0; X = the track, !Spc_CurTrack = X, !Spc_VoiceBit its bit,
;        !Spc_TrackWait+X = 0
; Exit:  X = the track; A, Y clobbered
; DSP:   SRCN, ADSR1/ADSR2 (Spc_Unk1AED)
; Callees: Spc_ReadSeqByte, Spc_RunSeqCommand, Spc_DrumNote,
;   Spc_NotePitch, Spc_Unk18A2, Spc_Unk1960, Spc_Unk1AED, Spc_PeekNote
; Sub-entries: Spc_TrackLookAhead.
Spc_TrackStep:
    call Spc_ReadSeqByte
    cmp a,#!Spc_SeqFirstCmd
    bcc .byte
    call Spc_RunSeqCommand
    bra Spc_TrackStep
.byte:
    mov.b y,!Spc_TrackWait+x
    bne .kind
    mov x,#!Spc_NumDurations
    div ya,x
    mov.b x,!Spc_CurTrack
    mov.w a,Spc_DurationTable+y
    mov.b !Spc_TrackWait+x,a
.kind:
    mov.b a,!Spc_TempA5
    cmp a,#!Spc_SeqFirstTie
    bcc .note
    cmp a,#!Spc_SeqFirstRest
    bcc .tie
    ret
.tie:
    jmp Spc_TrackLookAhead
.note:
    mov y,#$00
    mov x,#!Spc_NumDurations
    div ya,x
    mov.b !Spc_TempA5,a
    mov.b x,!Spc_CurTrack
    cmp x,#!Spc_TrackFirstSfx
    bcs .tone
    mov.b a,!Spc_VoiceBit
    and.b a,!Spc_Unk7C
    beq .tone
    call Spc_DrumNote
    bra .transpose
.tone:
    mov.w a,!Spc_TrackF200+x
    clrc
    adc.b a,!Spc_TempA5
.transpose:
    clrc
    adc.w a,!Spc_TrackF360+1+x
    setc
    sbc a,#!Spc_NoteBase
    mov.w !Spc_TrackF3A0+1+x,a
    call Spc_NotePitch
    mov.b a,!Spc_Quotient
    mov.w !Spc_TrackPitch+x,a
    mov.b a,!Spc_Quotient+1
    mov.w !Spc_TrackPitch+1+x,a
    mov.w a,!Spc_Track150+1+x
    beq .tremolo
    mov.b !Spc_TempA5,a
    call Spc_Unk18A2
    cmp x,#!Spc_TrackFirstSfx
    bcs .sfx_vib
    mov y,#$00
    bra .vib
.sfx_vib:
    mov.w a,!Spc_TrackUnk110+x
    mov y,a
.vib:
    mov.w a,Spc_VibDepthTable+y
    mov y,a
    bne .vib_scale
    movw.b ya,!Spc_Quotient
    bra .vib_set
.vib_scale:
    mov.b !Spc_Temp9D,y
    mov.b a,!Spc_Quotient+1
    mul ya
    movw.b !Spc_Temp9B,ya
    mov.b a,!Spc_Quotient
    mov.b y,!Spc_Temp9D
    mul ya
    mov a,y
    mov y,#$00
    addw.b ya,!Spc_Temp9B
.vib_set:
    mov.w !Spc_TrackF300+x,a
    mov a,y
    mov.w !Spc_TrackF300+1+x,a
.tremolo:
    mov.w a,!Spc_Track170+x
    beq .trem_set
    mov.b !Spc_TempA5,a
    call Spc_Unk1960
    mov a,#$00
.trem_set:
    mov.w !Spc_TrackVibOffset+x,a
    mov.w !Spc_TrackVibOffset+1+x,a
    mov.w !Spc_TrackTremPhase+x,a
    mov.w !Spc_TrackTremPhase+1+x,a
    mov.w !Spc_TrackF3C0+x,a
    mov.w !Spc_TrackF3C0+1+x,a
    mov.w !Spc_TrackF4E0+x,a
    cmp x,#!Spc_TrackFirstSfx
    bcs .sfx_key
    or.b !Spc_Unk24,!Spc_VoiceBit
    mov.b a,!Spc_SfxVoices
    and.b a,!Spc_VoiceBit
    bne Spc_TrackLookAhead
    mov.b a,!Spc_VoiceBit
    and.b a,!Spc_Unk60
    bne .key_on
    mov.b a,!Spc_VoiceBit
    and.b a,!Spc_Unk5C
    beq .key_on
    and.b a,!Spc_Unk5E
    bne .mark
    or.b !Spc_Unk5E,!Spc_VoiceBit
    bra .key_on
.sfx_key:
    or.b !Spc_Unk25,!Spc_VoiceBit
    mov.b a,!Spc_VoiceBit
    and.b a,!Spc_Unk61
    bne .key_on
    mov.b a,!Spc_VoiceBit
    and.b a,!Spc_Unk5D
    beq .key_on
    and.b a,!Spc_Unk5F
    bne .mark
    or.b !Spc_Unk5F,!Spc_VoiceBit
.key_on:
    or.b !Spc_KonShadow,!Spc_VoiceBit
.mark:
    or.b !Spc_UnkD0,!Spc_VoiceBit
    or.b !Spc_UnkD1,!Spc_VoiceBit
    call Spc_Unk1AED
Spc_TrackLookAhead:                     ; header: see Spc_TrackStep
    call Spc_PeekNote
    mov y,a
    mov.b a,!Spc_VoiceBit
    cmp x,#!Spc_TrackFirstSfx
    bcs .sfx_next
    cmp y,#!Spc_SeqFirstRest
    bcs .song_rest
    cmp y,#!Spc_SeqFirstTie
    bcc .song_note
    tset.w !Spc_Unk5A,a
    bra .slide
.song_rest:
    tclr.w !Spc_Unk5C,a
    tclr.w !Spc_Unk60,a
.song_note:
    tclr.w !Spc_Unk5A,a
    mov.b a,!Spc_Unk5C
    or.b a,!Spc_Unk60
    and.b a,!Spc_VoiceBit
    tset.w !Spc_Unk5A,a
    bra .slide
.sfx_next:
    cmp y,#!Spc_SeqFirstRest
    bcs .sfx_rest
    cmp y,#!Spc_SeqFirstTie
    bcc .sfx_note
    tset.w !Spc_Unk5B,a
    bra .slide
.sfx_rest:
    tclr.w !Spc_Unk5D,a
    tclr.w !Spc_Unk61,a
.sfx_note:
    tclr.w !Spc_Unk5B,a
    mov.b a,!Spc_Unk5D
    or.b a,!Spc_Unk61
    and.b a,!Spc_VoiceBit
    tset.w !Spc_Unk5B,a
.slide:
    mov.w a,!Spc_Track150+x
    beq .done
    clrc
    adc.w a,!Spc_TrackF3A0+1+x
    mov.w !Spc_TrackF3A0+1+x,a
    call Spc_NotePitch
    mov.w a,!Spc_TrackPitch+1+x
    mov y,a
    mov.w a,!Spc_TrackPitch+x
    movw.b !Spc_Temp9B,ya
    movw.b ya,!Spc_Quotient
    setc
    subw.b ya,!Spc_Temp9B
    movw.b !Spc_Temp9B,ya
    push p
    bcs .slide_steps
    eor.b !Spc_Temp9B,#!Spc_InvertBits
    eor.b !Spc_Temp9C,#!Spc_InvertBits
    incw.b !Spc_Temp9B
.slide_steps:
    mov.w a,!Spc_TrackF360+x
    bne .slide_div
    mov.b !Spc_Temp9D,#$00
    bra .slide_sign
.slide_div:
    mov x,a
    mov.b a,!Spc_Temp9C
    mov y,#$00
    div ya,x
    mov.b !Spc_Temp9D,a
    mov.b a,!Spc_Temp9B
    div ya,x
    mov.b !Spc_Temp9C,a
    mov a,#$00
    div ya,x
    mov.b !Spc_Temp9B,a
.slide_sign:
    pop p
    bcs .slide_set
    eor.b !Spc_Temp9B,#!Spc_InvertBits
    eor.b !Spc_Temp9C,#!Spc_InvertBits
    eor.b !Spc_Temp9D,#!Spc_InvertBits
    incw.b !Spc_Temp9B
    bne .slide_set
    inc.b !Spc_Temp9D
.slide_set:
    mov.b x,!Spc_CurTrack
    mov.b a,!Spc_Temp9B
    mov.w !Spc_TrackF4E0+x,a
    mov.b a,!Spc_Temp9C
    mov.w !Spc_TrackF3C0+x,a
    mov.b a,!Spc_Temp9D
    mov.w !Spc_TrackF3C0+1+x,a
    mov a,#$00
    mov.w !Spc_Track150+x,a
    mov.w !Spc_TrackF4E0+1+x,a
.done:
    ret

; $06BD — Spc_NotePitch (99 bytes, $06BD–$071F; ROM $C7:2982–$29E4)
; The pitch of note A for track X: octave = A / 12, P = the semitone's
; word from Spc_PitchTable. With t = (!Spc_TrackTuning's low byte + the
; fine tune, !Spc_TrackF3A0's low byte) & $FF, Q = P x t / 256; when the
; tuning's high byte h is nonzero, (Q's high byte x h) / 256 is added to
; Q (under 0.4%). The result is P + Q = P x (256 + t) / 256 for t below
; $80, Q alone = P x t / 256 from $80 up (BBS on t's bit 7). Then it is
; shifted left or right by the octave's distance from 4.
; Callers note: CALL from Spc_TrackStep ($0557) and Spc_TrackLookAhead
;   ($0657).
; Entry: P=0; A = the note; !Spc_CurTrack = X = the track
; Exit:  !Spc_Quotient = the pitch; X = the track; A, Y clobbered
Spc_NotePitch:
    mov x,#!Spc_NotesPerOctave
    mov y,#$00
    div ya,x
    mov.b x,!Spc_CurTrack
    mov.b !Spc_TempA4,a
    mov a,y
    asl a
    mov y,a
    mov.w a,Spc_PitchTable+y
    mov.b !Spc_TempB7,a
    mov.w a,Spc_PitchTable+1+y
    mov.b !Spc_TempB7+1,a
    mov y,a
    mov.w a,!Spc_TrackTuning+x
    clrc
    adc.w a,!Spc_TrackF3A0+x
    mov.b !Spc_Temp9B,a
    mul ya
    movw.b !Spc_Quotient,ya
    mov.b y,!Spc_TempB7
    mov.b a,!Spc_Temp9B
    mul ya
    mov a,y
    mov y,#$00
    addw.b ya,!Spc_Quotient
    movw.b !Spc_Quotient,ya
    mov.w a,!Spc_TrackTuning+1+x
    beq .no_tuning_hi
    mul ya
    mov a,y
    mov y,#$00
    addw.b ya,!Spc_Quotient
    bra .tuned
.no_tuning_hi:
    mov.b a,!Spc_Quotient
.tuned:
    bbs.b !Spc_Temp9B.7,.octave
    addw.b ya,!Spc_TempB7
.octave:
    movw.b !Spc_Quotient,ya
    mov a,#$04
    mov.b y,!Spc_TempA4
    bmi .down
    beq .down
    cmp.b a,!Spc_TempA4
    bcs .down_test
.up:
    asl.b !Spc_Quotient
    rol.b !Spc_Quotient+1
    inc a
    cbne.b !Spc_TempA4,.up
    ret
.down:
    lsr.b !Spc_Quotient+1
    ror.b !Spc_Quotient
    dec a
.down_test:
    cbne.b !Spc_TempA4,.down
    ret

; $0720 — Spc_DrumNote (29 bytes, $0720–$073C; ROM $C7:29E5–$2A01)
; A song track in drum mode: the note's index (!Spc_TempA5, 0-11) picks
; a three-byte entry of the song's drum kit at !AudioAram_SongExtra
; (the 36 bytes a song load sends there): byte 0 the sample
; (Spc_SetTrackSample), byte 1 the note returned, byte 2 below $80: the
; pan (x 2, into !Spc_TrackF280's high byte).
; Callers note: CALL from Spc_TrackStep ($0542).
; Entry: P=0; X = the track; !Spc_TempA5 = the index
; Exit:  A = !Spc_TempA5 = the note; X kept; Y clobbered
; Callees: Spc_SetTrackSample
Spc_DrumNote:
    mov.b a,!Spc_TempA5
    mov y,#$03
    mul ya
    mov y,a
    mov.w a,!AudioAram_SongExtra+2+y
    bmi .no_pan
    asl a
    mov.w !Spc_TrackF280+1+x,a
.no_pan:
    mov.w a,!AudioAram_SongExtra+1+y
    mov.b !Spc_TempA5,a
    mov.w a,!AudioAram_SongExtra+y
    call Spc_SetTrackSample
    mov.b a,!Spc_TempA5
    ret

; $073D — Spc_RunSeqCommand (33 bytes, $073D–$075D; ROM $C7:2A02–$2A22)
; (with its sub-entry Spc_ReadSeqByte)
; Runs sequence command A ($C4-$FF) of track X: pushes its handler
; (Spc_SeqCmdTable[A - $C4]); when it has operands
; (Spc_SeqOperandCounts) reads the first into A (Spc_ReadSeqByte); RETs
; into the handler. The SBC relies on C=1 from the caller's CMP.
; Spc_ReadSeqByte (11 bytes, $0753–$075D): A = !Spc_TempA5 = the byte at
; track X's !Spc_TrackPtr, which moves on by one.
; Callers note: CALL from Spc_TrackStep ($050E). Spc_ReadSeqByte: CALL
;   from Spc_TrackStep ($0507) and unmatched code, the sequence command
;   handlers ($1736, $1775, $179E, $17D3, $17F6, $1809, $182A, $187D,
;   $1885, $193B, $1943, $19AD, $1BEF, $1C0B, $1C10, $1D19, $1D1D).
; Entry: P=0; X = the track; A = the command, C=1
; Exit:  through the handler (RET); Spc_ReadSeqByte: A = the byte, Y
;        unchanged, X unchanged
; Callees: the handlers of Spc_SeqCmdTable (RET)
; Sub-entries: Spc_ReadSeqByte.
Spc_RunSeqCommand:
    sbc a,#!Spc_SeqFirstCmd
    mov.b !Spc_TempA5,a
    asl a
    mov y,a
    mov.w a,Spc_SeqCmdTable+1+y
    push a
    mov.w a,Spc_SeqCmdTable+y
    push a
    mov.b y,!Spc_TempA5
    mov.w a,Spc_SeqOperandCounts+y
    bne Spc_ReadSeqByte
    ret
Spc_ReadSeqByte:                        ; header: see Spc_RunSeqCommand
    mov.b a,(!Spc_TrackPtr+x)
    mov.b !Spc_TempA5,a
    inc.b !Spc_TrackPtr+x
    bne .done
    inc.b !Spc_TrackPtr+1+x
.done:
    ret

; $075E — Spc_PeekNote (69 bytes, $075E–$07A2; ROM $C7:2A23–$2A67)
; (with its sub-entry Spc_PeekNoteFrom)
; Finds track X's next note byte without moving its pointer: from
; !Spc_TrackPtr (copied to !Spc_Ptr93, with !Spc_TempBA = the track's
; !Spc_TrackUnk27), skips commands: one with a second handler
; (Spc_SeqCmdTable2) runs it and comes back to Spc_PeekNoteFrom (its
; address is pushed first); where a second handler reads operands it
; steps !Spc_Ptr93 past them itself. The others are skipped with their
; operands (Spc_SeqOperandCounts). Returns the first byte below $C4, or
; $EB (!Spc_SeqEndTrack: the end, which counts as a rest).
; Quirk of the original: $1B86, the second handler of $DC and $E4-$E7,
; only clears the voice from !Spc_Unk5C/60 (5D/61) and does not step
; !Spc_Ptr93; $DC has one operand, so that operand is read as the next
; byte (DC 21 1C gives $21).
; Callers note: CALL from Spc_TrackLookAhead ($0601). Spc_PeekNoteFrom:
;   the return address pushed at $0786/$0789.
; Entry: P=0; X = the track
; Exit:  A = the byte; Y = 0; X kept (as the second handlers leave it)
; Callees: the handlers of Spc_SeqCmdTable2 (RET)
; Sub-entries: Spc_PeekNoteFrom.
Spc_PeekNote:
    mov.b a,!Spc_TrackPtr+x
    mov.b y,!Spc_TrackPtr+1+x
    movw.b !Spc_Ptr93,ya
    mov.b a,!Spc_TrackUnk27+x
    mov.b !Spc_TempBA,a
Spc_PeekNoteFrom:                       ; header: see Spc_PeekNote
    mov y,#$00
.byte:
    mov.b a,(!Spc_Ptr93)+y
    cmp a,#!Spc_SeqFirstCmd
    bcc .done
    incw.b !Spc_Ptr93
    cmp a,#!Spc_SeqEndTrack
    beq .done
    setc
    sbc a,#!Spc_SeqFirstCmd
    mov.b !Spc_Temp92,a
    asl a
    mov y,a
    mov.w a,Spc_SeqCmdTable2+1+y
    beq .skip
    mov.b !Spc_Temp9B,a
    mov a,#Spc_PeekNoteFrom>>8
    push a
    mov a,#Spc_PeekNoteFrom&$FF
    push a
    mov.b a,!Spc_Temp9B
    push a
    mov.w a,Spc_SeqCmdTable2+y
    push a
    mov y,#$00
    ret
.skip:
    mov.b y,!Spc_Temp92
    mov.w a,Spc_SeqOperandCounts+y
    beq Spc_PeekNoteFrom
    mov y,a
.operands:
    incw.b !Spc_Ptr93
    dbnz y,.operands
    bra .byte
.done:
    ret

; ============================================================
; DSP and port helpers ($07A3-$07AE)
; ============================================================

; $07A3 — Spc_WriteDsp (5 bytes, $07A3–$07A7; ROM $C7:2A68–$2A6C)
; Writes A to the DSP register Y.
; Callers note: CALL from Spc_Start ($0213, $0218, $022A, $028E, $0293),
;   Spc_StartSong ($0BEA, $0C37, $0C3B), Spc_CmdVolumeBoost ($0EF8),
;   Spc_CmdControl ($12D4) and unmatched code ($135F, $1364, $1369,
;   $136E, $137D, $138B, $1B20); JMP from Spc_CmdVolumeBoost ($0EFD) and
;   unmatched code ($1B27, and $12F6: command $FD, DSP register
;   !Spc_CmdArg0 = !Spc_CmdArg1).
; Entry: P=0; A = the value, Y = the register
; Exit:  A, X, Y unchanged; PSW unchanged
; DSP:   register Y
%SpcOrg($07A3)
Spc_WriteDsp:
    mov.b !SPC_DSPADDR,y
    mov.b !SPC_DSPDATA,a
    ret

; $07A8 — Spc_ClearPorts01 (7 bytes, $07A8–$07AE; ROM $C7:2A6D–$2A73)
; Clears the latches of ports 0 and 1, so CPUIO0/1 read 0 until the
; 65816 writes APUIO0/1 again, keeping timers 0 and 1 running (CONTROL
; = !SPC_CONTROL_ClearPorts01, then !SPC_CONTROL_Timers01).
; Callers note: CALL from Spc_PollCommand ($0BA9) and Spc_QueueCommand
;   ($08C7); JMP from Spc_CmdSongCheck ($0D42) and Spc_XferReceive ($1079,
;   the end of a load).
; Entry: P=0
; Exit:  A, X, Y unchanged; PSW unchanged
; Ports: CPUIO0/1 read 0 afterwards
Spc_ClearPorts01:
    mov.b !SPC_CONTROL,#!SPC_CONTROL_ClearPorts01
    mov.b !SPC_CONTROL,#!SPC_CONTROL_Timers01
    ret


; ============================================================
; Track slides ($07AF-$0891)
; ============================================================

; $07AF — Spc_TrackSlides (227 bytes, $07AF–$0891; ROM $C7:2A74–$2B56)
; The per-pass slides of track X:
;   - with P=1, counts down the vibrato and tremolo delays
;     (!Spc_TrackVibDelay, !Spc_TrackTremDelay) when nonzero;
;   - the volume slide: while !Spc_TrackF2C0's low byte counts down,
;     !Spc_TrackF240 += !Spc_TrackVolDelta;
;   - the pan slide: while its high byte counts down, !Spc_TrackF280 +=
;     !Spc_TrackPanDelta;
;   - the pitch slide: while the step (!Spc_TrackF3C0, !Spc_TrackF4E0's low
;     byte) is nonzero, it is added to the pitch (!Spc_TrackPitch with the
;     fraction in !Spc_TrackF4E0's high byte), counting !Spc_TrackF360's
;     low byte down; at the last step the step is cleared;
;   - the pan LFO (!Spc_Track170 high byte nonzero): !Spc_TrackF4C0 +=
;     !Spc_TrackPanLfoDelta; when !Spc_TrackPanLfoTimer's counter runs out
;     the step's sign flips and the counter reloads (a triangle).
; A changed volume or pan (high byte) marks the voice in !Spc_UnkD0, a
; pitch step in !Spc_UnkD1.
; Callers note: CALL from Spc_StepTracks ($03DD) and Spc_StepSongOnly
;   ($04B6).
; Entry: P=0; X = the track, !Spc_VoiceBit its voice
; Exit:  P=0; X kept; A, Y clobbered
Spc_TrackSlides:
    setp
    mov.b a,!Spc_TrackVibDelay-!Spc_Page1+x
    beq .trem_delay
    dec.b !Spc_TrackVibDelay-!Spc_Page1+x
.trem_delay:
    mov.b a,!Spc_TrackTremDelay-!Spc_Page1+x
    beq .p0
    dec.b !Spc_TrackTremDelay-!Spc_Page1+x
.p0:
    clrp
    mov.w a,!Spc_TrackF2C0+x
    beq .pan
    dec a
    mov.w !Spc_TrackF2C0+x,a
    mov.w a,!Spc_TrackF240+x
    clrc
    adc.w a,!Spc_TrackVolDelta+x
    mov.w !Spc_TrackF240+x,a
    mov.w a,!Spc_TrackF240+1+x
    adc.w a,!Spc_TrackVolDelta+1+x
    cmp.w a,!Spc_TrackF240+1+x
    mov.w !Spc_TrackF240+1+x,a
    beq .pan
    or.b !Spc_UnkD0,!Spc_VoiceBit
.pan:
    mov.w a,!Spc_TrackF2C0+1+x
    beq .pitch
    dec a
    mov.w !Spc_TrackF2C0+1+x,a
    mov.w a,!Spc_TrackF280+x
    clrc
    adc.w a,!Spc_TrackPanDelta+x
    mov.w !Spc_TrackF280+x,a
    mov.w a,!Spc_TrackF280+1+x
    adc.w a,!Spc_TrackPanDelta+1+x
    cmp.w a,!Spc_TrackF280+1+x
    mov.w !Spc_TrackF280+1+x,a
    beq .pitch
    or.b !Spc_UnkD0,!Spc_VoiceBit
.pitch:
    mov.w a,!Spc_TrackF4E0+x
    mov.b !Spc_Temp9B,a
    mov.w a,!Spc_TrackF3C0+x
    mov.b !Spc_Temp9C,a
    mov.w a,!Spc_TrackF3C0+1+x
    mov.b !Spc_Temp9D,a
    movw.b ya,!Spc_Temp9B
    bne .pitch_step
    mov.b a,!Spc_Temp9D
    beq .pan_lfo
.pitch_step:
    mov.w a,!Spc_TrackF360+x
    dec a
    bne .pitch_add
    mov.w !Spc_TrackF3C0+x,a
    mov.w !Spc_TrackF3C0+1+x,a
    mov.w !Spc_TrackF4E0+x,a
.pitch_add:
    mov.w !Spc_TrackF360+x,a
    clrc
    mov.w a,!Spc_TrackPitch+x
    mov y,a
    mov.w a,!Spc_TrackF4E0+1+x
    addw.b ya,!Spc_Temp9B
    mov.w !Spc_TrackF4E0+1+x,a
    mov a,y
    mov.w !Spc_TrackPitch+x,a
    mov.b a,!Spc_Temp9D
    adc.w a,!Spc_TrackPitch+1+x
    mov.w !Spc_TrackPitch+1+x,a
    or.b !Spc_UnkD1,!Spc_VoiceBit
.pan_lfo:
    mov.w a,!Spc_Track170+1+x
    beq .done
    mov.w a,!Spc_TrackPanLfoDelta+x
    mov.b !Spc_Temp9B,a
    mov.w a,!Spc_TrackPanLfoDelta+1+x
    mov.b !Spc_Temp9C,a
    mov.w a,!Spc_TrackF4C0+1+x
    mov y,a
    mov.b !Spc_Temp9D,a
    mov.w a,!Spc_TrackF4C0+x
    addw.b ya,!Spc_Temp9B
    mov.w !Spc_TrackF4C0+x,a
    mov a,y
    cmp.w a,!Spc_TrackF4C0+1+x
    mov.w !Spc_TrackF4C0+1+x,a
    beq .pan_lfo_count
    or.b !Spc_UnkD0,!Spc_VoiceBit
.pan_lfo_count:
    mov.w a,!Spc_TrackPanLfoTimer+1+x
    dec a
    bne .pan_lfo_set
    eor.b !Spc_Temp9B,#!Spc_InvertBits
    eor.b !Spc_Temp9C,#!Spc_InvertBits
    incw.b !Spc_Temp9B
    mov.b a,!Spc_Temp9B
    mov.w !Spc_TrackPanLfoDelta+x,a
    mov.b a,!Spc_Temp9C
    mov.w !Spc_TrackPanLfoDelta+1+x,a
    mov.w a,!Spc_TrackPanLfoTimer+x
.pan_lfo_set:
    mov.w !Spc_TrackPanLfoTimer+1+x,a
.done:
    ret

; ============================================================
; Command queue ($0892-$0902)
; ============================================================

; $0892 — Spc_QueueCommand (59 bytes, $0892–$08CC; ROM $C7:2B57–$2B91)
; Takes a command that arrives while the tracks are stepped, so the
; 65816 does not wait for the end of the pass: when CPUIO0 is nonzero
; (read until two reads agree) and is not $FE (transfers) or $10-$17
; (song loads; these stay in the port for Spc_PollCommand's next poll),
; copies CPUIO0-3 into the next free !Spc_CmdQueue entry, moves
; !Spc_QueueEnd on by 4 (not past the last entry: once the queue is full
; the last entry is overwritten), clears the port 0/1 latches and echoes
; the id. Spc_RunQueue runs the entries.
; Callers note: CALL from Spc_MainLoop ($031C, $0340, $035C) and
;   Spc_StepTracks ($03E0) and unmatched code ($1308, in Spc_Unk12F9's
;   wait).
; Entry: P=0; X any (kept): the track being stepped, except at the
;        $1308 call, where it holds the address of the count Spc_Unk12F9
;        waits on
; Exit:  A, Y clobbered (Y = the id when one was queued); X unchanged
; Ports: CPUIO0-3 read; CPUIO0 = the id (echo) when queued
; Callees: Spc_ClearPorts01
%SpcOrg($0892)
Spc_QueueCommand:
    mov.b a,!SPC_CPUIO0
    beq .done
    cmp.b a,!SPC_CPUIO0
    bne Spc_QueueCommand
    cmp a,#!SpcCmd_Xfer
    beq .done
    cmp a,#!SpcCmd_FirstSong
    bcc .queue
    cmp a,#!SpcCmd_FirstNotQueued
    bcc .done
.queue:
    push x
    mov.b x,!Spc_QueueEnd
    mov.w !Spc_CmdQueue+x,a
    mov y,a
    mov.b a,!SPC_CPUIO1
    mov.w !Spc_CmdQueue+1+x,a
    mov.b a,!SPC_CPUIO2
    mov.w !Spc_CmdQueue+2+x,a
    mov.b a,!SPC_CPUIO3
    mov.w !Spc_CmdQueue+3+x,a
    mov a,x
    clrc
    adc a,#!Spc_QueueEntry
    cmp a,#!Spc_QueueBytes
    bcs .full                           ; the last entry stays the next one
    mov.b !Spc_QueueEnd,a
.full:
    pop x
    call Spc_ClearPorts01
    mov.b !SPC_CPUIO0,y
.done:
    ret

; $08CD — Spc_RunQueue (54 bytes, $08CD–$0902; ROM $C7:2B92–$2BC7)
; Runs the queued commands in order: for each !Spc_CmdQueue entry with a
; nonzero id, copies it to !Spc_CmdId-!Spc_CmdArg2 and runs it through
; Spc_RunCommand (which writes the echo to CPUIO0 a second time for
; $00-$0F and $20-$FF; the 65816 had its echo from Spc_QueueCommand).
; Then frees the entries it ran (their id bytes = 0) and !Spc_QueueEnd = 0.
; Callers note: CALL from Spc_MainLoop ($02F2, $036E) and unmatched code
;   ($1312).
; Entry: P=0
; Exit:  A = 0, X = 0; Y as the last command left it; !Spc_QueueEnd = 0
; Callees: Spc_RunCommand
Spc_RunQueue:
    mov x,#$00
.entry:
    mov.w a,!Spc_CmdQueue+x
    beq .ran
    mov.b !Spc_CmdId,a
    mov.w a,!Spc_CmdQueue+1+x
    mov.b !Spc_CmdArg0,a
    mov.w a,!Spc_CmdQueue+2+x
    mov.b !Spc_CmdArg1,a
    mov.w a,!Spc_CmdQueue+3+x
    mov.b !Spc_CmdArg2,a
    push x
    call Spc_RunCommand
    pop a
    clrc
    adc a,#!Spc_QueueEntry
    mov x,a
    cmp x,#!Spc_QueueBytes
    bne .entry
.ran:
    mov a,x
    beq .empty
    mov a,#$00
.free:
    mov.w !Spc_CmdQueue-!Spc_QueueEntry+x,a ; the entry's id byte
    dec x
    dec x
    dec x
    dec x
    bne .free
.empty:
    mov.b !Spc_QueueEnd,a
    ret


; ============================================================
; Track LFOs and voice writes ($0903-$0B95)
; ============================================================

; $0903 — Spc_TrackEffects (243 bytes, $0903–$09F5; ROM $C7:2BC8–$2CBA)
; (with its sub-entry Spc_TrackTremolo); then falls into Spc_WriteVoice.
; The LFOs of track X for one pass:
;   - vibrato, with a depth byte (!Spc_Track150 high byte) and, for a
;     song track, its delay run out: !Spc_TrackVibPhase +=
;     !Spc_TrackVibStep; when the phase's high byte changes, the offset
;     !Spc_TrackVibOffset = the depth (!Spc_TrackF300) x the phase's high
;     byte x 2 / 256, signed, and the pitch is marked (!Spc_UnkD1). When
;     !Spc_TrackVibTimer's counter runs out, Spc_LfoRate gives the next
;     step from !Spc_TrackVibRate and the vibrato's stage (!Spc_TrackF220
;     high byte, bits 0-2), and the counter reloads;
;   - Spc_TrackTremolo (97 bytes, $0995–$09F5): with a tremolo byte
;     (!Spc_Track170) and its delay run out, the same with
;     !Spc_TrackTremPhase / !Spc_TrackTremStep / !Spc_TrackTremTimer /
;     !Spc_TrackTremRate (stage in bits 4-6); a change of the phase's high
;     byte marks the volume (!Spc_UnkD0).
; Callers note: CALL from Spc_MainLoop ($0314, $033D, $0359) and
;   Spc_LivePass ($0451). Spc_TrackTremolo: JMP from $0913 (inside).
; Entry: P=0; X = the track, !Spc_VoiceBit its voice, !Spc_GroupVolume
;        its group's volume
; Exit:  as Spc_WriteVoice
; Callees: Spc_LfoRate; Spc_WriteVoice (fall-through)
; Sub-entries: Spc_TrackTremolo.
Spc_TrackEffects:
    mov.w a,!Spc_Track150+1+x
    beq .no_vibrato
    mov.b !Spc_TempA5,a
    cmp x,#!Spc_TrackFirstSfx
    bcs .vibrato
    mov.w a,!Spc_TrackVibDelay+x
    beq .vibrato
.no_vibrato:
    jmp Spc_TrackTremolo
.vibrato:
    mov.w a,!Spc_TrackVibStep+1+x
    mov y,a
    mov.w a,!Spc_TrackVibStep+x
    movw.b !Spc_Quotient,ya
    mov.w a,!Spc_TrackVibPhase+1+x
    mov y,a
    mov.w a,!Spc_TrackVibPhase+x
    addw.b ya,!Spc_Quotient
    movw.b !Spc_TempB7,ya
    mov.w !Spc_TrackVibPhase+x,a
    mov a,y
    cmp.w a,!Spc_TrackVibPhase+1+x
    beq .vib_count
    mov.w !Spc_TrackVibPhase+1+x,a
    asl.b !Spc_TempB7
    rol.b !Spc_TempB7+1
    mov.w a,!Spc_TrackF300+1+x
    mov y,a
    mov.w a,!Spc_TrackF300+x
    movw.b !Spc_Temp9B,ya
    mov.b a,!Spc_TempB7+1
    mul ya
    movw.b !Spc_Temp9D,ya
    mov.b y,!Spc_Temp9B
    mov.b a,!Spc_TempB7+1
    mul ya
    mov a,y
    mov y,#$00
    addw.b ya,!Spc_Temp9D
    bbc.b !Spc_TempB7+1.7,.vib_set
    subw.b ya,!Spc_Temp9B
.vib_set:
    mov.w !Spc_TrackVibOffset+x,a
    mov a,y
    mov.w !Spc_TrackVibOffset+1+x,a
    or.b !Spc_UnkD1,!Spc_VoiceBit
.vib_count:
    mov.w a,!Spc_TrackVibTimer+1+x
    dec a
    bne .vib_count_set
    mov.w a,!Spc_TrackVibRate+1+x
    mov y,a
    mov.w a,!Spc_TrackVibRate+x
    movw.b !Spc_Temp9B,ya
    mov.b a,!Spc_Quotient+1
    mov.b !Spc_TempB7,a
    mov.w a,!Spc_TrackF220+1+x
    mov.b !Spc_Temp9E,a
    and.b !Spc_Temp9E,#!Spc_TremStageMask
    and a,#$07
    call Spc_LfoRate
    mov.w !Spc_TrackVibStep+x,a
    mov a,y
    mov.w !Spc_TrackVibStep+1+x,a
    mov.b a,!Spc_Temp9D
    or.b a,!Spc_Temp9E
    mov.w !Spc_TrackF220+1+x,a
    mov.w a,!Spc_TrackVibTimer+x
.vib_count_set:
    mov.w !Spc_TrackVibTimer+1+x,a
Spc_TrackTremolo:                       ; header: see Spc_TrackEffects
    mov.w a,!Spc_Track170+x
    beq Spc_WriteVoice
    mov.b !Spc_TempA5,a
    mov.w a,!Spc_TrackTremDelay+x
    bne Spc_WriteVoice
    mov.w a,!Spc_TrackTremStep+1+x
    mov y,a
    mov.w a,!Spc_TrackTremStep+x
    movw.b !Spc_Quotient,ya
    mov.b !Spc_TempB7,y
    mov.w a,!Spc_TrackTremPhase+1+x
    mov y,a
    mov.w a,!Spc_TrackTremPhase+x
    addw.b ya,!Spc_Quotient
    mov.w !Spc_TrackTremPhase+x,a
    mov a,y
    cmp.w a,!Spc_TrackTremPhase+1+x
    beq .trem_count
    mov.w !Spc_TrackTremPhase+1+x,a
    or.b !Spc_UnkD0,!Spc_VoiceBit
.trem_count:
    mov.w a,!Spc_TrackTremTimer+1+x
    dec a
    bne .trem_count_set
    mov.w a,!Spc_TrackTremRate+1+x
    mov y,a
    mov.w a,!Spc_TrackTremRate+x
    movw.b !Spc_Temp9B,ya
    mov.w a,!Spc_TrackF220+1+x
    mov.b !Spc_Temp9E,a
    and.b !Spc_Temp9E,#!Spc_VibStageMask
    xcn a
    and a,#$07
    call Spc_LfoRate
    mov.w !Spc_TrackTremStep+x,a
    mov a,y
    mov.w !Spc_TrackTremStep+1+x,a
    mov.b a,!Spc_Temp9D
    xcn a
    or.b a,!Spc_Temp9E
    mov.w !Spc_TrackF220+1+x,a
    mov.w a,!Spc_TrackTremTimer+x
.trem_count_set:
    mov.w !Spc_TrackTremTimer+1+x,a

; $09F6 — Spc_WriteVoice (232 bytes, $09F6–$0ADD; ROM $C7:2CBB–$2DA2)
; (with its sub-entry Spc_WritePitch)
; Writes track X's voice to the DSP when it is marked (nothing when
; !Spc_UnkD0 and !Spc_UnkD1 are both 0):
;   - volume (in !Spc_UnkD0): the pan byte is !Spc_PanCentre with
;     !Spc_Flags87 bit 0 (mono), else the inverse of pan + pan LFO
;     (!Spc_TrackF280, !Spc_TrackF4C0 high bytes, through Spc_Unk12DE);
;     the volume is !Spc_TrackF240's high byte, moved by a nonzero tremolo
;     phase p (!Spc_TrackTremPhase high byte): below $80 it becomes
;     volume + volume x 2p / 256; from $80 up volume x (2p - 256) / 256
;     (the BCS after the MUL still sees the ASL's carry): volume x (1 +
;     signed p / 128) in all. Quirk of the original: the sum is capped at
;     $7F only when the add carries with bit 7 set (sum >= $180); sums of
;     $80-$FF and $100-$17F keep their low byte. Then x !Spc_GroupVolume
;     / 256, and for a song track 0 when
;     muted (!Spc_Mute), else x !Spc_TrackF220 x !Spc_Unk4D / 65536
;     (!Spc_Unk4D: the song command's Arg1, a song volume probably). Left
;     = volume x pan / 256, right = volume x (pan ^ $FF) / 256 (with mono:
;     $80 and $7F), written to VOLL / VOLR and kept in !Spc_VoiceVol.
;   - Spc_WritePitch (102 bytes, $0A78–$0ADD), pitch (in !Spc_UnkD1): the
;     pitch plus the vibrato offset; a song track's is scaled by
;     !Spc_PitchAdjHi (below $80: + pitch x adj x 2 / 256; from $80:
;     pitch x adj / 256), tracks 14-15 by !Spc_SfxPitchAdj (+ pitch x adj
;     x 2 / 256), tracks 8-13 not at all; written to PL / PH (the register
;     in !Spc_Temp9C, which Spc_StartSong sets before it calls
;     Spc_WritePitch).
; Callers note: CALL from Spc_MainLoop ($0319). Spc_WritePitch: CALL
;   from Spc_StartSong ($0C41).
; Entry: P=0; X = the track, !Spc_VoiceBit its voice, !Spc_GroupVolume
;        its group's volume (Spc_WritePitch: !Spc_Temp9C = the voice's PL
;        register)
; Exit:  X kept; A, Y clobbered
; DSP:   VOLL, VOLR, PL, PH of the voice
; Callees: Spc_Unk12DE
; Sub-entries: Spc_WritePitch.
Spc_WriteVoice:
    movw.b ya,!Spc_UnkD0
    bne .voice
    ret
.voice:
    mov a,x
    and a,#!Spc_LowNibble
    mov.b !Spc_Temp9B,a
    xcn a
    lsr a
    mov.b !Spc_Temp9C,a
    mov.b a,!Spc_VoiceBit
    and.b a,!Spc_UnkD0
    beq .pitch
    mov.b !Spc_Temp9D,#!Spc_PanCentre
    bbs.b !Spc_Flags87.0,.volume
    mov.w a,!Spc_TrackF280+1+x
    mov y,a
    mov.w a,!Spc_TrackF4C0+1+x
    call Spc_Unk12DE
    eor a,#!Spc_InvertBits
    mov.b !Spc_Temp9D,a
.volume:
    mov.w a,!Spc_TrackF240+1+x
    mov y,a
    mov.b !Spc_Temp9E,a
    mov.w a,!Spc_TrackTremPhase+1+x
    beq .group
    asl a
    mul ya
    bcs .group
    mov a,y
    adc.b a,!Spc_Temp9E
    bpl .vol_capped
    bcc .vol_capped
    mov a,#!Spc_VolMax
.vol_capped:
    mov y,a
.group:
    mov.b a,!Spc_GroupVolume
    mul ya
    cmp x,#!Spc_TrackFirstSfx
    bcs .sides
    mov.b a,!Spc_VoiceBit
    and.b a,!Spc_Mute
    beq .song_vol
    mov y,#$00
    bra .sides
.song_vol:
    mov.w a,!Spc_TrackF220+x
    mul ya
    mov.b a,!Spc_Unk4D
    mul ya
.sides:
    mov.b !Spc_Temp9E,y
    mov.b a,!Spc_Temp9D
.side:
    mul ya
    mov a,y
    mov.b y,!Spc_Temp9B
    mov.w !Spc_VoiceVol+y,a
    mov.b y,!Spc_Temp9C
    mov.b !SPC_DSPADDR,y
    mov.b !SPC_DSPDATA,a
    not1 !Spc_Temp9B.0
    inc.b !Spc_Temp9C
    bbs.b !Spc_Temp9C.1,.pitch
    mov.b a,!Spc_Temp9D
    eor a,#!Spc_InvertBits
    mov.b y,!Spc_Temp9E
    bra .side
.pitch:
    mov.b a,!Spc_VoiceBit
    and.b a,!Spc_UnkD1
    beq Spc_WritePitch_done
    set1.b !Spc_Temp9C.1
Spc_WritePitch:                         ; header: see Spc_WriteVoice
    mov.w a,!Spc_TrackPitch+x
    clrc
    adc.w a,!Spc_TrackVibOffset+x
    mov.b !Spc_Temp9D,a
    mov.w a,!Spc_TrackPitch+1+x
    adc.w a,!Spc_TrackVibOffset+1+x
    mov.b !Spc_Temp9E,a
    cmp x,#!Spc_TrackFirstSfx
    bcc .song_pitch
    cmp x,#!Spc_TrackSfxA
    bcs .sfx_pitch
.unscaled:
    movw.b ya,!Spc_Temp9D
    bra .write
.sfx_pitch:
    mov.b y,!Spc_SfxPitchAdj
    beq .unscaled
    mul ya
    movw.b !Spc_Temp9F,ya
    mov.b y,!Spc_SfxPitchAdj
    mov.b a,!Spc_Temp9D
    mul ya
    mov a,y
    mov y,#$00
    addw.b ya,!Spc_Temp9F
    asl a
    mov.b !Spc_TempA1,a
    mov a,y
    rol a
    mov y,a
    mov.b a,!Spc_TempA1
    addw.b ya,!Spc_Temp9D
    bra .write
.song_pitch:
    mov.b y,!Spc_PitchAdjHi
    mul ya
    movw.b !Spc_Temp9F,ya
    mov.b y,!Spc_PitchAdjHi
    mov.b a,!Spc_Temp9D
    mul ya
    mov a,y
    mov y,#$00
    addw.b ya,!Spc_Temp9F
    bbs.b !Spc_PitchAdjHi.7,.write
    asl a
    mov.b !Spc_TempA1,a
    mov a,y
    rol a
    mov y,a
    mov.b a,!Spc_TempA1
    addw.b ya,!Spc_Temp9D
.write:
    mov.b !Spc_Temp9B,x
    mov.b x,!Spc_Temp9C
    mov.b !SPC_DSPADDR,x
    mov.b !SPC_DSPDATA,a
    inc x
    mov.b !SPC_DSPADDR,x
    mov.b !SPC_DSPDATA,y
    mov.b x,!Spc_Temp9B
.done:
    ret

; $0ADE — Spc_LfoRate (126 bytes, $0ADE–$0B5B; ROM $C7:2DA3–$2E20)
; The next step of a vibrato or tremolo at a turn of its counter. Every
; call negates the step (!Spc_Quotient): the LFO turns. While the stage
; (A) is nonzero it counts down (the new stage in !Spc_Temp9D) and the
; step's size grows by a quarter of the base rate (!Spc_Temp9B/9C), on
; the turns that make the step positive for a depth byte (!Spc_TempA5)
; below $80, on those that make it negative for $80-$BF, and on every
; turn from $C0 up (keeping the turn's sign: the old step's sign in
; !Spc_TempB7 bit 7 picks it). Stage 0: only the negation, no more growth.
; Callers note: CALL from Spc_TrackEffects ($097E, $09DE).
; Entry: P=0; A = the stage (0-7); !Spc_TempA5 = the depth byte;
;        !Spc_Quotient = the step; !Spc_Temp9B/9C = the base rate;
;        !Spc_TempB7 = the old step's high byte (read for $C0 up)
; Exit:  YA = the step; !Spc_Temp9D = the stage; X unchanged
Spc_LfoRate:
    mov.b !Spc_Temp9D,#$00
    cmp.b !Spc_TempA5,#!Spc_LfoShapeC0
    bcs .shape_c0
    cmp.b !Spc_TempA5,#!Spc_LfoShape80
    bcs .shape_80
    eor.b !Spc_Quotient,#!Spc_InvertBits
    eor.b !Spc_Quotient+1,#!Spc_InvertBits
    incw.b !Spc_Quotient
    mov y,a
    beq .done
    dec a
    mov.b !Spc_Temp9D,a
    bbs.b !Spc_Quotient+1.7,.done
    lsr.b !Spc_Temp9C
    ror.b !Spc_Temp9B
    lsr.b !Spc_Temp9C
    ror.b !Spc_Temp9B
    movw.b ya,!Spc_Temp9B
    addw.b ya,!Spc_Quotient
    ret
.shape_80:
    eor.b !Spc_Quotient,#!Spc_InvertBits
    eor.b !Spc_Quotient+1,#!Spc_InvertBits
    incw.b !Spc_Quotient
    mov y,a
    beq .done
    dec a
    mov.b !Spc_Temp9D,a
    bbc.b !Spc_Quotient+1.7,.done
    lsr.b !Spc_Temp9C
    ror.b !Spc_Temp9B
    lsr.b !Spc_Temp9C
    ror.b !Spc_Temp9B
    eor.b !Spc_Temp9B,#!Spc_InvertBits
    eor.b !Spc_Temp9C,#!Spc_InvertBits
    incw.b !Spc_Temp9B
    movw.b ya,!Spc_Temp9B
    addw.b ya,!Spc_Quotient
    ret
.shape_c0:
    mov y,a
    beq .negate
    dec a
    mov.b !Spc_Temp9D,a
    bbc.b !Spc_Quotient+1.7,.shape_c0_add
    eor.b !Spc_Quotient,#!Spc_InvertBits
    eor.b !Spc_Quotient+1,#!Spc_InvertBits
    incw.b !Spc_Quotient
.shape_c0_add:
    lsr.b !Spc_Temp9C
    ror.b !Spc_Temp9B
    lsr.b !Spc_Temp9C
    ror.b !Spc_Temp9B
    movw.b ya,!Spc_Temp9B
    addw.b ya,!Spc_Quotient
    movw.b !Spc_Quotient,ya
    bbs.b !Spc_TempB7.7,.done
.negate:
    eor.b !Spc_Quotient,#!Spc_InvertBits
    eor.b !Spc_Quotient+1,#!Spc_InvertBits
    incw.b !Spc_Quotient
.done:
    movw.b ya,!Spc_Quotient
    ret

; $0B5C — Spc_AnimateBuiltin (58 bytes, $0B5C–$0B95; ROM $C7:2E21–$2E5A)
; Changes one nibble of Spc_BuiltinSampleLoop each pass: !Spc_UnkD8
; counts from !Spc_BuiltinFirst to !Spc_BuiltinLast (2 x the byte, bit 0
; the nibble; BRR header bytes skipped), and the byte at !Spc_UnkD8 / 2
; is XORed with $70 or $07. At the last step byte 1 of the loop is
; flipped as well. The built-in sample (directory entry $10) so plays a
; changing waveform, probably.
; Callers note: CALL from Spc_MainLoop ($0371).
; Entry: P=0
; Exit:  A = the new !Spc_UnkD8; X = 9 or kept (kept when the count
;        wraps); Y clobbered
Spc_AnimateBuiltin:
    mov.b a,!Spc_UnkD8
    cmp a,#!Spc_BuiltinLast
    beq .first
.flip:
    lsr a
    mov y,a
    mov a,#!Spc_BuiltinFlip
    bcc .apply
    xcn a
.apply:
    eor.w a,Spc_BuiltinSampleLoop+y
    mov.w Spc_BuiltinSampleLoop+y,a
    mov.b a,!Spc_UnkD8
    inc a
    cmp a,#!Spc_BuiltinLast+1
    beq .wrap
    push a
    lsr a
    mov y,#$00
    mov x,#!Spc_BrrBlock
    div ya,x
    mov a,y
    pop a
    bne .set
    inc a
    inc a
    bra .set
.wrap:
    mov a,#!Spc_BuiltinFirst
.set:
    mov.b !Spc_UnkD8,a
    ret
.first:
    mov a,#!Spc_BuiltinFlip
    eor.w a,Spc_BuiltinSampleLoop+1
    mov.w Spc_BuiltinSampleLoop+1,a
    mov.b a,!Spc_UnkD8
    bra .flip

; ============================================================
; CPU commands ($0B96-$0E10)
; ============================================================
; The 65816 writes a command's arguments to APUIO1-3 and its id to APUIO0
; (Audio_RunCommand / Audio_CmdSend / Audio_StartSong), then waits for
; APUIO0 to read the id back. Ids $80-$FF and $00-$0F / $20-$7F are
; echoed here at once; $10, $11, $14, $15, $18 and $19 by their handlers;
; the rest of $10-$1F run Spc_NullCommand and are never echoed.

; $0B96 — Spc_PollCommand (22 bytes, $0B96–$0BAB; ROM $C7:2E5B–$2E70)
; Takes a command if one is waiting: when CPUIO0 is nonzero, reads it
; until two reads agree, copies CPUIO0-3 to !Spc_CmdId-!Spc_CmdArg2,
; clears the port 0/1 latches (Spc_ClearPorts01) and runs it: falls into
; Spc_RunCommand.
; Spc_RunCommand (44 bytes, $0BAC–$0BD7) runs the command in !Spc_CmdId:
;   - $80-$FF: echoed (CPUIO0 = the id), then Spc_RunHighCommand;
;   - $10-$1F: Spc_CmdTable10's handler, with Spc_CmdFirstTable10's
;     (when its high byte is nonzero: only that byte is tested) run first:
;     both are pushed and the RET runs the second, which returns into the
;     first. Not echoed here;
;   - $00-$0F, $20-$7F: echoed only.
; Callers note: CALL from Spc_MainLoop ($0299); Spc_RunCommand is also
;   called by Spc_RunQueue ($08E6) for the queued commands.
; Entry: P=0 (Spc_RunCommand: !Spc_CmdId-!Spc_CmdArg2 set)
; Exit:  no command: X = 0, Z=1; $00-$0F / $20-$7F: A = X = the id;
;        else as the handler leaves it (a song handler does not return:
;        Spc_StartSong)
; Ports: CPUIO0-3 read; CPUIO0 = the id (echo) as above
; Callees: Spc_ClearPorts01, Spc_RunHighCommand (JMP), the table's
;   handlers (RET)
; Sub-entries: Spc_RunCommand.
%SpcOrg($0B96)
Spc_PollCommand:
    mov.b x,!SPC_CPUIO0
    bne .read
    ret
.again:
    mov.b x,!SPC_CPUIO0
.read:
    cmp.b x,!SPC_CPUIO0
    bne .again
    movw.b ya,!SPC_CPUIO2
    movw.b !Spc_CmdArg1,ya              ; and !Spc_CmdArg2
    movw.b ya,!SPC_CPUIO0
    movw.b !Spc_CmdId,ya                ; and !Spc_CmdArg0
    call Spc_ClearPorts01
Spc_RunCommand:                         ; header: see Spc_PollCommand
    mov.b x,!Spc_CmdId
    mov a,x
    bpl .low
    mov.b !SPC_CPUIO0,x
    jmp Spc_RunHighCommand
.low:
    cmp x,#!SpcCmd_FirstSong
    bcc .echo
    cmp x,#!SpcCmd_AfterSong
    bcs .echo
    and a,#!SpcCmd_SongIndexMask
    asl a
    mov y,a
    mov.w a,Spc_CmdTable10+1+y
    push a
    mov.w a,Spc_CmdTable10+y
    push a
    mov.w a,Spc_CmdFirstTable10+1+y
    beq .run
    push a
    mov.w a,Spc_CmdFirstTable10+y
    push a
.run:
    ret
.echo:
    mov.b !SPC_CPUIO0,x
    ret

; $0BD8 — Spc_CmdSong14 (3 bytes, $0BD8–$0BDA; ROM $C7:2E9D–$2E9F)
; Commands $10, $11, $14 and $15 (Spc_CmdTable10), after
; Spc_CmdSongCheck has let them through:
;   - Spc_CmdSong14 ($14): Spc_SaveSong, then as $10;
;   - Spc_CmdSong10 ($10): !Spc_SongHeaderSet = !Spc_SongSetA, then
;     Spc_StartSong;
;   - Spc_CmdSong15 ($15): Spc_SaveSong, then as $11;
;   - Spc_CmdSong11 ($11): !Spc_SongHeaderSet = !Spc_SongSetB, falls into
;     Spc_StartSong.
; ($14 is what the battle music cue sends, !Audio_Cmd14: the song that
; was playing is kept aside, and Spc_StartSong resumes it when it is
; asked for again.)
; Callers note: reached only through Spc_CmdTable10 (pushed by
;   Spc_RunCommand, entered by RET).
; Entry: P=0; !Spc_CmdArg0-2 as Spc_StartSong wants them
; Exit:  through Spc_StartSong (does not return)
; Callees: Spc_SaveSong, Spc_StartSong (BRA / fall-through)
; Sub-entries: Spc_CmdSong10, Spc_CmdSong15, Spc_CmdSong11.
Spc_CmdSong14:
    call Spc_SaveSong
Spc_CmdSong10:                          ; header: see Spc_CmdSong14
    mov.b !Spc_SongHeaderSet,#!Spc_SongSetA
    bra Spc_StartSong
Spc_CmdSong15:                          ; header: see Spc_CmdSong14
    call Spc_SaveSong
Spc_CmdSong11:                          ; header: see Spc_CmdSong14
    mov.b !Spc_SongHeaderSet,#!Spc_SongSetB

; $0BE6 — Spc_StartSong (272 bytes, $0BE6–$0CF5; ROM $C7:2EAB–$2FBA)
; Starts the song the 65816 has just loaded (or the one saved aside):
;   1. Keys off every voice (KOF = $FF), !Spc_NewSong = !Spc_CmdArg0,
;      !Spc_Unk4D = !Spc_CmdArg1; when !Spc_CmdArg2's low nibble (the
;      song's echo delay) differs from !Spc_EchoDelay, takes it and
;      starts the echo change (!Spc_Flags88 bits 0 and 1, Spc_Unk1316).
;   2. Spc_XferReceive: takes the transfers that follow (the samples'
;      directory, the song data; Audio_LoadNewSamples ... on the 65816
;      side).
;   3. Clears !Spc_SfxVoices, !Spc_Flags88 bit 5, !Spc_UnkD1,
;      !Spc_SongCond and !Spc_UnkD3.
;   4. When !Spc_SavedSong = !Spc_NewSong (the song asked for is the
;      one Spc_SaveSong kept): Spc_RestoreSong, and when the song has
;      tracks (a restored song with none goes on as a new start, below),
;      puts the noise clock back in FLG and, for each track 0-7,
;      adds 1 to its wait, writes its sample (Spc_Unk1AED), writes 0 to
;      its voice's VOLL and VOLR and runs Spc_WritePitch with !Spc_Temp9C =
;      the voice's next register number (PL); then clears $55/$57/$59,
;      keys on !Spc_Unk24 (!Spc_KonShadow), sets !Spc_KofShadow and
;      !Spc_Unk25 to 0 and marks the song's tracks in !Spc_UnkD0.
;      Else a new start: clears !Spc_SongTracks, the EON/NON/PMON words,
;      the KON/KOF shadows, !Spc_Unk24/25, !Spc_Unk5A, 5C, 60, 7C and 7B,
;      sets tempo 1 with the accumulator at $FF, copies the chosen set of 8 track pointers of
;      the header at !AudioAram_Song (!Spc_SongHeaderSet) and moves each
;      by (!AudioAram_Song + !SpcSong_Data) - the header's
;      !SpcSong_Origin; a track whose pointer equals !SpcSong_NoTrack is
;      left out, the others go into !Spc_SongTracks, Spc_InitTrack and
;      !Spc_TrackF220 = $FF; then !Spc_UnkD0 = 0.
;   5. With !Spc_Flags88 bit 0 set, finishes the echo change: with bit 1
;      set, Spc_Unk12F9 on !Spc_Unk82, !Spc_Unk83 = 0 and echo writes on
;      (Spc_Unk1397); then Spc_Unk12F9 on !Spc_EchoDelay, and clears bit
;      0 (bit 1 is left as it is).
;   6. Copies !Spc_SongEon/Non/Pmon to their shadows, resets SP and jumps
;      to Spc_MainLoop (with A = timer 0's count, discarding it).
; Callers note: Spc_CmdSong11 falls in; BRA from Spc_CmdSong10 ($0BDE).
; Entry: P=0; !Spc_CmdArg0 = the song, !Spc_CmdArg1 = byte 1 of its
;        AudioRom_SongEcho word, !Spc_CmdArg2 = the echo delay (low
;        nibble); !Spc_SongHeaderSet set
; Exit:  does not return: SP = $FF, JMP Spc_MainLoop
; DSP:   KOF. On a resume, for voices 0-7: VOLL/VOLR, SRCN and ADSR1/ADSR2
;        (Spc_Unk1AED: with !Spc_SfxVoices just cleared it runs on into the
;        ADSR writes at $1B0C) and PL/PH (Spc_WritePitch). On an echo change
;        (Spc_Unk1316, through $1352): FLG (echo writes off), EON, EFB,
;        EVOLL and EVOLR = 0, EDL = !Spc_EchoDelay, ESA; FLG again in
;        Spc_Unk1397. Spc_Unk12F9 may also run queued commands, with their
;        own writes
; Ports: through Spc_XferReceive and Spc_Unk12F9
; Callees: Spc_WriteDsp, Spc_Unk1316, Spc_XferReceive, Spc_RestoreSong,
;   Spc_Unk1AED, Spc_WritePitch, Spc_InitTrack, Spc_Unk12F9, Spc_Unk1397,
;   Spc_MainLoop (JMP)
Spc_StartSong:
    mov a,#!DSP_KOF_All
    mov y,#!DSP_KOF
    call Spc_WriteDsp
    mov.b !Spc_NewSong,!Spc_CmdArg0
    mov.b a,!Spc_CmdArg1
    mov.b !Spc_Unk4D,a
    mov.b a,!Spc_CmdArg2
    and a,#!SpcCmd_EchoDelayMask
    cmp.b a,!Spc_EchoDelay
    beq .echo_same
    mov.b !Spc_EchoDelay,a
    set1.b !Spc_Flags88.0
    set1.b !Spc_Flags88.1
    call Spc_Unk1316
.echo_same:
    call Spc_XferReceive
    mov a,#$00
    mov y,a
    mov.b !Spc_SfxVoices,a
    clr1.b !Spc_Flags88.5
    movw.b !Spc_SongCond,ya
    mov.b !Spc_UnkD1,a
    cmp.b !Spc_SavedSong,!Spc_NewSong
    bne .new_song
    call Spc_RestoreSong
    mov.b a,!Spc_SongTracks
    beq .new_song
    and.b !Spc_FlgShadow,#!Spc_FlgKeep
    or.b !Spc_FlgShadow,!Spc_NoiseClock
    mov x,#$00
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit0
.resume_track:
    inc.b !Spc_TrackWait+x
    mov.b !Spc_CurTrack,x
    call Spc_Unk1AED
    mov a,x
    xcn a
    lsr a                               ; voice x $10: its VOLL
    mov y,a
    mov a,#$00
    call Spc_WriteDsp
    inc y                               ; VOLR
    call Spc_WriteDsp
    inc y
    mov.b !Spc_Temp9C,y
    call Spc_WritePitch
    inc x
    inc x
    asl.b !Spc_VoiceBit
    bne .resume_track
    mov a,#$00
    mov.b !Spc_SongEon+1,a
    mov.b !Spc_SongNon+1,a
    mov.b !Spc_SongPmon+1,a
    mov.b !Spc_KonShadow,!Spc_Unk24
    mov.b !Spc_KofShadow,a
    mov.b !Spc_Unk25,a
    mov.b !Spc_UnkD0,!Spc_SongTracks
    bra .echo_change
.new_song:
    mov a,#$00
    mov y,a
    mov.b !Spc_SongTracks,a
    movw.b !Spc_SongEon,ya
    movw.b !Spc_SongNon,ya
    movw.b !Spc_SongPmon,ya
    mov.b !Spc_KonShadow,a
    mov.b !Spc_KofShadow,a
    movw.b !Spc_Unk24,ya                ; and !Spc_Unk25
    mov.b !Spc_Unk5A,a
    mov.b !Spc_Unk5C,a
    mov.b !Spc_Unk60,a
    mov.b !Spc_Unk7C,a
    mov.b !Spc_Unk7B,a
    mov.b !Spc_Tempo,#!Spc_StartTempo
    mov.b !Spc_TempoAccum,#!Spc_TempoAccumStart
    mov.b y,!Spc_SongHeaderSet
    mov x,#!Spc_NumSongTracks
.copy_set:
    mov.w a,!AudioAram_Song+!SpcSong_Tracks-1+y
    mov.b !Spc_TrackPtr-1+x,a
    dec y
    dec x
    bne .copy_set
    mov.w a,!AudioAram_Song+!SpcSong_Origin
    mov.b !Spc_Scratch00,a
    mov.w a,!AudioAram_Song+!SpcSong_Origin+1
    mov.b !Spc_Scratch00+1,a
    mov a,#(!AudioAram_Song+!SpcSong_Data)&$FF
    mov y,#(!AudioAram_Song+!SpcSong_Data)>>8
    subw.b ya,!Spc_Scratch00
    movw.b !Spc_Scratch00,ya            ; the move
    mov x,#!Spc_TrackLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
    mov.w a,!AudioAram_Song+!SpcSong_NoTrack
    mov.w y,!AudioAram_Song+!SpcSong_NoTrack+1
    movw.b !Spc_Temp9B,ya
.move_track:
    mov.b a,!Spc_TrackPtr+x
    mov.b y,!Spc_TrackPtr+1+x
    cmpw.b ya,!Spc_Temp9B
    beq .no_track
    or.b !Spc_SongTracks,!Spc_VoiceBit
    addw.b ya,!Spc_Scratch00
    mov.b !Spc_TrackPtr+x,a
    mov.b !Spc_TrackPtr+1+x,y
    call Spc_InitTrack
    mov a,#!Spc_TrackF220Start
    mov.w !Spc_TrackF220+x,a
.no_track:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
    bne .move_track
    mov.b !Spc_UnkD0,#$00
.echo_change:
    bbc.b !Spc_Flags88.0,.echo_done
    bbc.b !Spc_Flags88.1,.echo_wait
    mov x,#!Spc_Unk82
    call Spc_Unk12F9
    mov.b !Spc_Unk83,#$00
    call Spc_Unk1397
.echo_wait:
    mov x,#!Spc_EchoDelay
    call Spc_Unk12F9
    clr1.b !Spc_Flags88.0
.echo_done:
    mov.b !Spc_EonShadow,!Spc_SongEon
    mov.b !Spc_NonShadow,!Spc_SongNon
    mov.b !Spc_PmonShadow,!Spc_SongPmon
    mov x,#!Spc_StackTop
    mov sp,x
    mov.b a,!SPC_T0OUT
    jmp Spc_MainLoop

; $0CF6 — Spc_InitTrack (51 bytes, $0CF6–$0D28; ROM $C7:2FBB–$2FED)
; Resets track X's state before it starts: !Spc_TrackUnk27 = X x 2;
; clears its words in !Spc_Track150 / !Spc_Track170 and the work area
; (!Spc_TrackF3C0, !Spc_TrackF4C0, the bytes !Spc_TrackF4E0,
; !Spc_TrackF3A0, !Spc_TrackF360's high byte); !Spc_TrackF300 = $1000;
; !Spc_TrackWait = 1 (it steps on the next pass).
; Callers note: CALL from Spc_StartSong ($0CBC) and Spc_StartSfx ($0D88).
; Entry: P=0; X = the track (0-$1E, even)
; Exit:  A = !Spc_TrackF300Start; X, Y unchanged
Spc_InitTrack:
    mov a,x
    asl a
    mov.b !Spc_TrackUnk27+x,a
    mov a,#$00
    mov.w !Spc_Track150+x,a
    mov.w !Spc_TrackF3C0+x,a
    mov.w !Spc_TrackF3C0+1+x,a
    mov.w !Spc_TrackF4E0+x,a
    mov.w !Spc_Track150+1+x,a
    mov.w !Spc_Track170+x,a
    mov.w !Spc_Track170+1+x,a
    mov.w !Spc_TrackF4C0+x,a
    mov.w !Spc_TrackF4C0+1+x,a
    mov.w !Spc_TrackF3A0+x,a
    mov.w !Spc_TrackF360+1+x,a
    mov.w !Spc_TrackF300+x,a
    inc a
    mov.b !Spc_TrackWait+x,a
    mov a,#!Spc_TrackF300Start
    mov.w !Spc_TrackF300+1+x,a
    ret

; $0D29 — Spc_CmdSongCheck (28 bytes, $0D29–$0D44; ROM $C7:2FEE–$3009)
; Run first for commands $10, $11, $14 and $15 (Spc_CmdFirstTable10):
; compares the song asked for (!Spc_CmdArg0) with !Spc_CurSong and
; makes it the current song.
;   - A different song: CPUIO1 = the song (bit 7 clear for songs below
;     $80), CPUIO0 = the id (echo), and returns into the command's
;     handler (Spc_CmdSong10 ...), which takes the load.
;   - The same song: drops the handler's address from the stack, CPUIO1
;     = !SpcCmd_SameSong, CPUIO0 = the id, waits until CPUIO0 is nonzero
;     (the 65816's next step: Audio_StartSong sends Audio_Seq), and
;     leaves through Spc_ClearPorts01, returning to Spc_PollCommand's
;     caller. On the 65816 side Audio_StartSong sees APUIO1 bit 7 and
;     ends the load there.
; Callers note: reached only through Spc_CmdFirstTable10 (pushed by
;   Spc_RunCommand, entered by RET); it returns into the handler pushed
;   under it.
; Entry: P=0; X = the id (Spc_RunCommand), !Spc_CmdArg0 = the song
; Exit:  !Spc_CurSong = the song; A = the song (or !SpcCmd_SameSong /
;        CPUIO0's value), X unchanged
; Ports: CPUIO0 (echo), CPUIO1 (the answer); CPUIO0 read
; Callees: Spc_ClearPorts01 (JMP)
Spc_CmdSongCheck:
    mov.b a,!Spc_CmdArg0
    cmp.b a,!Spc_CurSong
    mov.b !Spc_CurSong,a
    beq .same
    mov.b !SPC_CPUIO1,a
    mov.b !SPC_CPUIO0,x
    ret
.same:
    pop a                               ; the handler's address
    pop a
    mov a,#!SpcCmd_SameSong
    mov.b !SPC_CPUIO1,a
    mov.b !SPC_CPUIO0,x
.wait:
    mov.b a,!SPC_CPUIO0
    beq .wait
    jmp Spc_ClearPorts01

; $0D45 — Spc_CmdSfx18 (12 bytes, $0D45–$0D50; ROM $C7:300A–$3015)
; Commands $18 and $19 (Spc_CmdTable10): echo the id, then start the
; sound effect !Spc_CmdArg0 in Spc_StartSfx on a group of tracks:
;   - Spc_CmdSfx18 ($18): tracks 15 and 14 (voices 7 and 6: X = $1E,
;     bits $C0);
;   - Spc_CmdSfx19 ($19, Audio_CmdPlaySfx): tracks 13 and 12 (voices 5
;     and 4: X = $1A, bits $30).
; Callers note: reached only through Spc_CmdTable10.
; Entry: P=0; X = the id; !Spc_CmdArg0 = the effect, !Spc_CmdArg1 = the
;        high byte for the tracks' !Spc_TrackF280
; Exit:  through Spc_StartSfx
; Ports: CPUIO0 = the id (echo)
; Callees: Spc_StartSfx (BRA / fall-through)
; Sub-entries: Spc_CmdSfx19.
Spc_CmdSfx18:
    mov.b !SPC_CPUIO0,x
    mov x,#!Spc_TrackSfxLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
    mov.b !Spc_CmdArg2,#!Spc_SfxGroupA
    bra Spc_StartSfx
Spc_CmdSfx19:                           ; header: see Spc_CmdSfx18
    mov.b !SPC_CPUIO0,x
    mov x,#!Spc_TrackSfxB
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit5
    mov.b !Spc_CmdArg2,#!Spc_SfxGroupB

; $0D5B — Spc_StartSfx (160 bytes, $0D5B–$0DFA; ROM $C7:3020–$30BF)
; Starts sound effect !Spc_CmdArg0 on the two tracks from X down (voice
; bit !Spc_VoiceBit); nothing while !Spc_Flags87 bit 4 is set.
;   1. The effect's entry in the table at !AudioAram_Block2F00: two
;      track pointers (4 bytes per effect), taken from the second down.
;      A pointer whose high byte is 0 is skipped and does not use up a
;      track (so a lone pointer lands on the upper track); each other one
;      goes to the track's !Spc_TrackPtr, adds its voice bit to
;      !Spc_TempA4, and the track starts: Spc_InitTrack, wait 2,
;      !Spc_TrackF240 high byte $46, !Spc_TrackF280 high byte =
;      !Spc_CmdArg1, !Spc_TrackF200 = $48, !Spc_TrackF2C0 = 0, sample 2
;      (Spc_SetTrackSample).
;      Quirk (a byte shared by two instructions): the skip branch lands
;      on the operand byte of `mov a,#$DC`, which is `dec y`, so both
;      paths step Y by 2 while only the taken one steps X.
;   2. The voices of the group already held by an effect, plus the new
;      ones: cleared from !Spc_KonShadow, !Spc_Unk5B, !Spc_Unk5D,
;      !Spc_Unk61, !Spc_UnkD0, !Spc_UnkD1 and !Spc_Unk25, set in
;      !Spc_KofShadow; Spc_EndTrack for each of them that is a voice 7-4
;      (tracks 15-12, the loop's reach: both groups' voices).
;   3. The new voices: set in !Spc_SfxVoices, cleared from the EON, PMON
;      and NON shadows and from !Spc_Unk24.
; Callers note: Spc_CmdSfx19 falls in; BRA from Spc_CmdSfx18 ($0D4F).
; Entry: P=0; X = the first track, !Spc_VoiceBit its voice bit,
;        !Spc_CmdArg2 = the group's voice bits, !Spc_CmdArg0/1 as in
;        Spc_CmdSfx18
; Exit:  A = the new voice bits; X = $16; Y = $FF when no voice was ended,
;        else the value of $57 (!Spc_SongNon+1) after the last Spc_EndTrack
;        (it reaches `mov y,$57` at $1A51 through $1A68 and $1A48); with
;        !Spc_Flags87 bit 4 set: A, X, Y as on entry
; Callees: Spc_InitTrack, Spc_SetTrackSample, Spc_EndTrack
Spc_StartSfx:
    bbc.b !Spc_Flags87.4,.start
    ret
.start:
    mov.b !Spc_Ptr93,!Spc_CmdArg0
    mov.b !Spc_Ptr93+1,#$00
    asl.b !Spc_Ptr93                    ; x 4 (!Spc_SfxEntry)
    rol.b !Spc_Ptr93+1
    asl.b !Spc_Ptr93
    rol.b !Spc_Ptr93+1
    mov a,#!AudioAram_Block2F00&$FF
    mov y,#!AudioAram_Block2F00>>8
    addw.b ya,!Spc_Ptr93
    movw.b !Spc_Ptr93,ya
    mov y,#!Spc_SfxEntry-1
    mov.b !Spc_TempA4,#$00
.pointer:
    mov.b a,(!Spc_Ptr93)+y
    beq .skip+1                         ; on the `dec y` inside .skip
    mov.b !Spc_TrackPtr+1+x,a
    dec y
    mov.b a,(!Spc_Ptr93)+y
    mov.b !Spc_TrackPtr+x,a
    or.b !Spc_TempA4,!Spc_VoiceBit
    call Spc_InitTrack
    inc.b !Spc_TrackWait+x
    mov a,#!Spc_TrackF240Sfx
    mov.w !Spc_TrackF240+1+x,a
    mov.b a,!Spc_CmdArg1
    mov.w !Spc_TrackF280+1+x,a
    mov a,#!Spc_TrackF200Sfx
    mov.w !Spc_TrackF200+x,a
    mov a,#$00
    mov.w !Spc_TrackF2C0+x,a
    mov.w !Spc_TrackF2C0+1+x,a
    mov.b !Spc_Temp9B,y
    mov a,#!Spc_SfxStartSample
    call Spc_SetTrackSample
    mov.b y,!Spc_Temp9B
    dec x
    dec x
    lsr.b !Spc_VoiceBit
.skip:
    mov a,#$DC                          ; lint-ok: $DC is the `dec y` opcode the BEQ above lands on
    dec y
    bpl .pointer
    mov.b a,!Spc_SfxVoices
    and.b a,!Spc_CmdArg2
    or.b a,!Spc_TempA4
    tclr.w !Spc_KonShadow,a
    tclr.w !Spc_Unk5B,a
    tclr.w !Spc_Unk5D,a
    tclr.w !Spc_Unk61,a
    tclr.w !Spc_UnkD0,a
    tclr.w !Spc_UnkD1,a
    tset.w !Spc_KofShadow,a
    tclr.w !Spc_Unk25,a
    mov.b !Spc_TempA5,a
    mov x,#!Spc_TrackSfxLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
.end_old:
    asl.b !Spc_TempA5
    bcc .end_next
    call Spc_EndTrack
.end_next:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
    bbc.b !Spc_VoiceBit.3,.end_old      ; voices 7-4 (tracks 15-12)
    mov.b a,!Spc_TempA4
    tset.w !Spc_SfxVoices,a
    tclr.w !Spc_EonShadow,a
    tclr.w !Spc_PmonShadow,a
    tclr.w !Spc_NonShadow,a
    tclr.w !Spc_Unk24,a
    ret

; $0DFB — Spc_RunHighCommand (22 bytes, $0DFB–$0E10; ROM $C7:30C0–$30D5)
; Commands $80-$8F and $F0-$FF (already echoed by Spc_RunCommand): RET
; into Spc_CmdTable80's entry (id & $1F); $90-$EF do nothing.
; Callers note: JMP from Spc_RunCommand ($0BB3).
; Entry: P=0; X = the id ($80-$FF)
; Exit:  through the handler (RET into it); $90-$EF: returns with A, X,
;        Y unchanged, C=1
; Callees: the handlers of Spc_CmdTable80 (RET)
Spc_RunHighCommand:
    cmp x,#!SpcCmd_FirstTop
    bcs .dispatch
    cmp x,#!SpcCmd_FirstHigh
    bcs .done
.dispatch:
    mov a,x
    and a,#!SpcCmd_HighIndexMask
    asl a
    mov y,a
    mov.w a,Spc_CmdTable80+1+y
    push a
    mov.w a,Spc_CmdTable80+y
    push a
.done:
    ret

; ============================================================
; Commands $80-$8F and $F0-$FF ($0E11-$12DD)
; ============================================================
; Reached through Spc_CmdTable80 (Spc_RunHighCommand), already echoed;
; the arguments are in !Spc_CmdArg0-!Spc_CmdArg2. Entries that do
; nothing go to Spc_NullCommand: $84, $8A-$8D, $8F, $F7, $FA, $FB.

; $0E11 — Spc_CmdFadeAll (9 bytes, $0E11–$0E19; ROM $C7:30D6–$30DE)
; Command $80: the fade of commands $81, $82 and $83 on all three
; !Spc_GroupVol groups (the song, effect tracks 14-15, 8-13).
; Callers note: reached only through Spc_CmdTable80 entry 0.
; Entry: P=0; !Spc_CmdArg0 = the steps, !Spc_CmdArg1 = the volume
; Exit:  as Spc_CmdFadeSfxB
; Callees: Spc_CmdFadeSong, Spc_CmdFadeSfxA, Spc_CmdFadeSfxB (JMP)
Spc_CmdFadeAll:
    call Spc_CmdFadeSong
    call Spc_CmdFadeSfxA
    jmp Spc_CmdFadeSfxB

; $0E1A — Spc_CmdFadeSong (69 bytes, $0E1A–$0E5E; ROM $C7:30DF–$3123)
; (with its sub-entries Spc_CmdFadeSfxA, Spc_CmdFadeSfxB, Spc_StartFade)
; Commands $81, $82 and $83: fade one !Spc_GroupVol volume to
; !Spc_CmdArg1 over !Spc_CmdArg0 steps (Spc_Unk1492 makes a step every
; 7 passes). Each marks its group's voices in !Spc_UnkD0 first
; (Spc_CmdFadeSong $81: the song, X = 0, bits !Spc_SongVolMarks = voices
; 0-6, voice 7 left out; Spc_CmdFadeSfxA $82: X = 2, $C0;
; Spc_CmdFadeSfxB $83: X = 4, $30), then Spc_StartFade:
;   - steps 0, or a target equal to the volume: the volume is set at
;     once (fraction 0, delta 0, steps 0);
;   - else the steps are stored and the delta per step is (target -
;     volume) x 256 / steps, signed (Spc_FadeDelta), with the fraction
;     cleared.
; (LocLoad_AudioSetup's $81 with Arg0 0, Arg1 $FF sets the song's volume
; to $FF at once; the battle cues fade it over $40 / $80 steps.)
; Callers note: Spc_CmdFadeAll ($0E11 CALL, $0E14 CALL, $0E17 JMP) and
;   Spc_CmdTable80 entries 1-3.
; Entry: P=0; !Spc_CmdArg0 = the steps, !Spc_CmdArg1 = the volume
; Exit:  A, X, Y clobbered
; Callees: Spc_FadeDelta
; Sub-entries: Spc_CmdFadeSfxA, Spc_CmdFadeSfxB, Spc_StartFade.
Spc_CmdFadeSong:
    or.b !Spc_UnkD0,#!Spc_SongVolMarks
    mov x,#!Spc_GroupSong
    jmp Spc_StartFade
Spc_CmdFadeSfxA:                        ; header: see Spc_CmdFadeSong
    or.b !Spc_UnkD0,#!Spc_SfxGroupA
    mov x,#!Spc_GroupSfxA
    jmp Spc_StartFade
Spc_CmdFadeSfxB:                        ; header: see Spc_CmdFadeSong
    or.b !Spc_UnkD0,#!Spc_SfxGroupB
    mov x,#!Spc_GroupSfxB
Spc_StartFade:                          ; header: see Spc_CmdFadeSong
    mov.b y,!Spc_CmdArg1
    mov.b a,!Spc_CmdArg0
.set_steps:
    mov.w !Spc_GroupFadeSteps+x,a
    bne .fade
    mov.w !Spc_GroupVol+x,a
    mov.w !Spc_GroupFadeDelta+x,a
    mov.w !Spc_GroupFadeDelta+1+x,a
    mov a,y
    mov.w !Spc_GroupVol+1+x,a
    ret
.fade:
    mov a,y
    setc
    sbc.w a,!Spc_GroupVol+1+x
    beq .set_steps                      ; A = 0: set at once
    push x
    call Spc_FadeDelta
    pop x
    mov.w !Spc_GroupFadeDelta+x,a
    mov a,y
    mov.w !Spc_GroupFadeDelta+1+x,a
    mov a,#$00
    mov.w !Spc_GroupVol+x,a
    ret

; $0E5F — Spc_FadeDelta (32 bytes, $0E5F–$0E7E; ROM $C7:3124–$3143)
; The signed step of a fade: |A| x 256 / !Spc_CmdArg0 as a 16-bit value
; (quotient in Y, the remainder's fraction in A), negated when C=0.
; Callers note: CALL from Spc_StartFade ($0E4E), Spc_CmdTempo ($0EA1),
;   Spc_CmdSongPitch ($0ECA) and unmatched code, sequence commands that
;   start fades of their own with the steps in !Spc_CmdArg0 ($1749,
;   $1784, $17B2, $17E5, $181B, $184E).
; Entry: P=0; A = the difference (as a SBC left it), C = 1 for
;        difference >= 0, 0 for < 0; !Spc_CmdArg0 = the steps (nonzero)
; Exit:  YA = the step (also in !Spc_Quotient); X = !Spc_CmdArg0; PSW as
;        on entry apart from N and Z (POP P), C as on entry
Spc_FadeDelta:
    push p
    bcs .positive
    eor a,#!Spc_InvertBits
    inc a
.positive:
    mov.b x,!Spc_CmdArg0
    mov y,#$00
    div ya,x
    mov.b !Spc_Quotient+1,a
    mov a,#$00
    div ya,x
    mov.b !Spc_Quotient,a
    pop p
    bcs .done
    eor.b !Spc_Quotient,#!Spc_InvertBits
    eor.b !Spc_Quotient+1,#!Spc_InvertBits
    incw.b !Spc_Quotient
.done:
    movw.b ya,!Spc_Quotient
    ret

; $0E7F — Spc_CmdTempoPitch (3 bytes, $0E7F–$0E81; ROM $C7:3144–$3146)
; Command $85: Spc_CmdSongPitch, then falls into Spc_CmdTempo ($86).
; Spc_CmdTempo (40 bytes, $0E82–$0EA9): fades !Spc_TempoAdj ($AA) to
; !Spc_CmdArg1 over !Spc_CmdArg0 steps, compared as signed values: steps
; 0 or no difference sets it at once (fraction, delta and steps 0); else
; !Spc_TempoAdjSteps = steps, !Spc_TempoAdjDelta = Spc_FadeDelta, the
; fraction 0. Spc_StepTracks raises the tempo with it below $80 and
; lowers it from $80 up. (C2Scene_ObjAInit sends $86 with 0, 0: no
; adjustment.)
; Callers note: reached only through Spc_CmdTable80 entries 5 and 6.
; Entry: P=0; !Spc_CmdArg0 = the steps, !Spc_CmdArg1 = the value
; Exit:  A, X, Y clobbered
; Callees: Spc_CmdSongPitch, Spc_FadeDelta
; Sub-entries: Spc_CmdTempo.
Spc_CmdTempoPitch:
    call Spc_CmdSongPitch
Spc_CmdTempo:                           ; header: see Spc_CmdTempoPitch
    mov.b y,!Spc_CmdArg1
    mov.b a,!Spc_CmdArg0
.set_steps:
    mov.b !Spc_TempoAdjSteps,a
    bne .fade
    mov.b !Spc_TempoAdj+1,y
    mov.b !Spc_TempoAdj,a
    mov.b !Spc_TempoAdjDelta+1,a
    mov.b !Spc_TempoAdjDelta,a
    ret
.fade:
    mov.b !Spc_TempA5,!Spc_TempoAdj+1
    eor.b !Spc_TempA5,#!Spc_SignBias
    mov a,y
    eor a,#!Spc_SignBias
    setc
    sbc.b a,!Spc_TempA5
    beq .set_steps                      ; A = 0: set at once
    call Spc_FadeDelta
    movw.b !Spc_TempoAdjDelta,ya
    mov.b !Spc_TempoAdj,#$00
    ret

; $0EAA — Spc_CmdSongPitch (44 bytes, $0EAA–$0ED5; ROM $C7:316F–$319A)
; Command $87 (and the first half of $85): fades !Spc_PitchAdj ($AF) as
; Spc_CmdTempo fades !Spc_TempoAdj (!Spc_PitchAdjSteps,
; !Spc_PitchAdjDelta), then !Spc_UnkD1 = $FF (every voice's pitch to be
; rewritten, inferred). Spc_WritePitch scales a song track's pitch by $AF:
; a pitch shift (up below $80, down from $80).
; Callers note: CALL from Spc_CmdTempoPitch ($0E7F); Spc_CmdTable80
;   entry 7.
; Entry: P=0; !Spc_CmdArg0 = the steps, !Spc_CmdArg1 = the value
; Exit:  A, X, Y clobbered
; Callees: Spc_FadeDelta
Spc_CmdSongPitch:
    mov.b y,!Spc_CmdArg1
    mov.b a,!Spc_CmdArg0
.set_steps:
    mov.b !Spc_PitchAdjSteps,a
    bne .fade
    mov.b !Spc_PitchAdj+1,y
    mov.b !Spc_PitchAdj,a
    mov.b !Spc_PitchAdjDelta+1,a
    mov.b !Spc_PitchAdjDelta,a
    bra .mark
.fade:
    mov.b !Spc_TempA5,!Spc_PitchAdj+1
    eor.b !Spc_TempA5,#!Spc_SignBias
    mov a,y
    eor a,#!Spc_SignBias
    setc
    sbc.b a,!Spc_TempA5
    beq .set_steps                      ; A = 0: set at once
    call Spc_FadeDelta
    movw.b !Spc_PitchAdjDelta,ya
    mov.b !Spc_PitchAdj,#$00
.mark:
    mov.b !Spc_UnkD1,#!Spc_AllBits
    ret

; $0ED6 — Spc_CmdSfxPitch (16 bytes, $0ED6–$0EE5; ROM $C7:319B–$31AA)
; Command $89: !Spc_SfxPitchAdj = !Spc_CmdArg0 (the pitch adjustment of
; effect tracks 14-15, Spc_WritePitch); when it changed, the voices of
; group $C0 held by effects are marked in !Spc_UnkD1.
; Callers note: reached only through Spc_CmdTable80 entry 9.
; Entry: P=0; !Spc_CmdArg0 = the value
; Exit:  A = Arg0, or the marked bits; X, Y unchanged
Spc_CmdSfxPitch:
    mov.b a,!Spc_CmdArg0
    cmp.b a,!Spc_SfxPitchAdj
    mov.b !Spc_SfxPitchAdj,a
    beq .done
    mov a,#!Spc_SfxGroupA
    and.b a,!Spc_SfxVoices
    tset.w !Spc_UnkD1,a
.done:
    ret

; $0EE6 — Spc_CmdVolumeBoost (26 bytes, $0EE6–$0EFF; ROM $C7:31AB–$31C4)
; Command $8E: !Spc_Flags87 bit 3 = (!Spc_CmdArg0 != 0), which doubles
; the echo volume (Spc_MainLoop), and MVOLL/MVOLR = !DSP_MVOL_Boost when
; set, !DSP_MVOL_Start when clear.
; Callers note: reached only through Spc_CmdTable80 entry 14.
; Entry: P=0; !Spc_CmdArg0 = on (nonzero) or off
; Exit:  A = the main volume; Y = !DSP_MVOLR; X unchanged
; DSP:   MVOLL, MVOLR
; Callees: Spc_WriteDsp (CALL, JMP)
Spc_CmdVolumeBoost:
    mov a,#!Spc_TestCarry
    clrc
    adc.b a,!Spc_CmdArg0
    mov1 !Spc_Flags87.3,c
    bcs .boost
    mov a,#!DSP_MVOL_Start
    bra .write
.boost:
    mov a,#!DSP_MVOL_Boost
.write:
    mov y,#!DSP_MVOLL
    call Spc_WriteDsp
    mov y,#!DSP_MVOLR
    jmp Spc_WriteDsp

; $0F00 — Spc_CmdMono (14 bytes, $0F00–$0F0D; ROM $C7:31C5–$31D2)
; Command $F3: !Spc_Flags87 bit 0 = (!Spc_CmdArg0 != 0), then every
; voice's volume to be rewritten (!Spc_UnkD0 = $FF). With bit 0 set
; Spc_WriteVoice skips the pan and uses $80 ($0A0D): left = volume x $80,
; right = volume x $7F, nearly the same: mono (the menu sends it with its stereo / mono setting, Menu_CfgA3).
; Callers note: reached only through Spc_CmdTable80 entry 19.
; Entry: P=0; !Spc_CmdArg0 = mono (nonzero) or stereo
; Exit:  A = Arg0; X, Y unchanged
Spc_CmdMono:
    mov.b a,!Spc_CmdArg0
    bne .mono
    clr1.b !Spc_Flags87.0
    bra .mark
.mono:
    set1.b !Spc_Flags87.0
.mark:
    mov.b !Spc_UnkD0,#!Spc_AllBits
    ret

; $0F0E — Spc_CmdStopAll (9 bytes, $0F0E–$0F16; ROM $C7:31D3–$31DB)
; Command $F0: Spc_CmdStopSong, Spc_StopSfxA and Spc_StopSfxB.
; Callers note: reached only through Spc_CmdTable80 entry 16.
; Entry: P=0
; Exit:  as Spc_StopSfxB
; Callees: Spc_CmdStopSong, Spc_StopSfxA, Spc_StopSfxB (JMP)
Spc_CmdStopAll:
    call Spc_CmdStopSong
    call Spc_StopSfxA
    jmp Spc_StopSfxB

; $0F17 — Spc_CmdStopSong (37 bytes, $0F17–$0F3B; ROM $C7:31DC–$3200)
; Command $F1: stops the song. The voices not held by effects are keyed
; off (!Spc_KofShadow) and cleared from !Spc_KonShadow and the EON, PMON
; and NON shadows; !Spc_SongTracks and the song's EON/PMON/NON bytes
; ($54, $58, $56) are cleared, and !Spc_CurSong, !Spc_SavedSong and
; !Spc_NewSong = $FF (no song, none kept aside).
; Callers note: CALL from Spc_CmdStopAll ($0F0E) and unmatched code
;   ($14C1, the end of a fade-out in Spc_Unk1492); Spc_CmdTable80 entry
;   17.
; Entry: P=0
; Exit:  A = $FF; X, Y unchanged
Spc_CmdStopSong:
    mov.b a,!Spc_SfxVoices
    eor a,#!Spc_InvertBits
    tset.w !Spc_KofShadow,a
    tclr.w !Spc_KonShadow,a
    tclr.w !Spc_EonShadow,a
    tclr.w !Spc_PmonShadow,a
    tclr.w !Spc_NonShadow,a
    mov a,#$00
    mov.b !Spc_SongTracks,a
    mov.b !Spc_SongEon,a
    mov.b !Spc_SongPmon,a
    mov.b !Spc_SongNon,a
    dec a
    mov.b !Spc_CurSong,a                ; $FF: none
    mov.b !Spc_SavedSong,a
    mov.b !Spc_NewSong,a
    ret

; $0F3C — Spc_CmdStopSfx (3 bytes, $0F3C–$0F3E; ROM $C7:3201–$3203)
; Command $F2: stops the effects of one group: Spc_StopSfxB when
; !Spc_CmdArg0 bit 0 is set, else falls into Spc_StopSfxA.
; Spc_StopSfxA (50 bytes, $0F3F–$0F70) stops the effects on voices 7-6
; (group $C0 of !Spc_SfxVoices): keys them off and clears them from
; !Spc_KonShadow, !Spc_Unk25, !Spc_UnkD0 and !Spc_UnkD1; each of their
; tracks (15, 14) is pointed at Spc_TrackEndCmd with wait 2, so it ends
; on its next step (the byte there is sequence command $EB, which ends a
; track, probably: its handler $1D4A runs into Spc_EndTrack).
; Callers note: Spc_StopSfxA: CALL from Spc_CmdStopAll ($0F11),
;   Spc_XferHeader ($104A) and unmatched code ($14F3, when the group's
;   fade-out in Spc_Unk1492 reaches 0). Both: Spc_CmdTable80 entry 18. C3_ReadPad
;   sends $F2 with Arg0 0 on pausing (!C3_SndPause).
; Entry: P=0 (Spc_CmdStopSfx: !Spc_CmdArg0 bit 0 picks the group)
; Exit:  A clobbered; X = $1A (group A), or $16 when Arg0 bit 0 is set
;        (through Spc_StopSfxB); Y unchanged
; Sub-entries: Spc_StopSfxA.
Spc_CmdStopSfx:
    bbs.b !Spc_CmdArg0.0,Spc_StopSfxB
Spc_StopSfxA:                           ; header: see Spc_CmdStopSfx
    mov.b a,!Spc_SfxVoices
    and a,#!Spc_SfxGroupA
    tset.w !Spc_KofShadow,a
    tclr.w !Spc_KonShadow,a
    tclr.w !Spc_Unk25,a
    tclr.w !Spc_UnkD0,a
    tclr.w !Spc_UnkD1,a
    mov.b !Spc_TempA4,a
    mov x,#!Spc_TrackSfxLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
.track:
    asl.b !Spc_TempA4
    bcc .next
    mov a,#Spc_TrackEndCmd&$FF
    mov.b !Spc_TrackPtr+x,a
    mov a,#Spc_TrackEndCmd>>8
    mov.b !Spc_TrackPtr+1+x,a
    mov a,#!Spc_StopWait
    mov.b !Spc_TrackWait+x,a
.next:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
    bbc.b !Spc_VoiceBit.5,.track        ; voices 7-6
    ret

; $0F71 — Spc_StopSfxB (52 bytes, $0F71–$0FA4; ROM $C7:3236–$3269)
; As Spc_StopSfxA for voices 5-4 (group $30, tracks 13-12): keyed off,
; cleared from the same bits, their tracks pointed at Spc_TrackEndCmd
; with wait 2.
; Callers note: CALL from Spc_XferHeader ($104D) and unmatched code
;   ($1521, when the group's fade-out in Spc_Unk1492 reaches 0); JMP from
;   Spc_CmdStopAll ($0F14); BBS from Spc_CmdStopSfx ($0F3C).
; Entry: P=0
; Exit:  A clobbered; X = $16; Y unchanged
Spc_StopSfxB:
    mov.b a,!Spc_SfxVoices
    and a,#!Spc_SfxGroupB
    tset.w !Spc_KofShadow,a
    tclr.w !Spc_KonShadow,a
    tclr.w !Spc_Unk25,a
    tclr.w !Spc_UnkD0,a
    tclr.w !Spc_UnkD1,a
    asl a                               ; voices 5-4 to bits 7-6
    asl a
    mov.b !Spc_TempA4,a
    mov x,#!Spc_TrackSfxB
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit5
.track:
    asl.b !Spc_TempA4
    bcc .next
    mov a,#Spc_TrackEndCmd&$FF
    mov.b !Spc_TrackPtr+x,a
    mov a,#Spc_TrackEndCmd>>8
    mov.b !Spc_TrackPtr+1+x,a
    mov a,#!Spc_StopWait
    mov.b !Spc_TrackWait+x,a
.next:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
    bbc.b !Spc_VoiceBit.3,.track        ; voices 5-4
    ret

; $0FA5 — Spc_CmdMuteSet (7 bytes, $0FA5–$0FAB; ROM $C7:326A–$3270)
; Commands $F4, $F8 and $F9 change !Spc_Mute (the voices whose song
; tracks are silenced) and mark the voices' volumes to be rewritten:
;   - Spc_CmdMuteSet ($F4): !Spc_Mute = !Spc_CmdArg0, all voices marked;
;   - Spc_CmdMuteClear ($F8, 9 bytes, $0FAC–$0FB4): clears Arg0's bits;
;   - Spc_CmdMuteAdd ($F9, 9 bytes, $0FB5–$0FBD): sets Arg0's bits;
;     those two mark Arg0's voices.
; Callers note: reached only through Spc_CmdTable80 entries 20, 24, 25.
; Entry: P=0; !Spc_CmdArg0 = voice bits
; Exit:  A = Arg0 ($F8/$F9); X, Y unchanged
; Sub-entries: Spc_CmdMuteClear, Spc_CmdMuteAdd.
Spc_CmdMuteSet:
    mov.b !Spc_Mute,!Spc_CmdArg0
    mov.b !Spc_UnkD0,#!Spc_AllBits
    ret
Spc_CmdMuteClear:                       ; header: see Spc_CmdMuteSet
    mov.b a,!Spc_CmdArg0
    tclr.w !Spc_Mute,a
    tset.w !Spc_UnkD0,a
    ret
Spc_CmdMuteAdd:                         ; header: see Spc_CmdMuteSet
    mov.b a,!Spc_CmdArg0
    tset.w !Spc_Mute,a
    tset.w !Spc_UnkD0,a
    ret

; $0FBE — Spc_CmdPause (80 bytes, $0FBE–$100D; ROM $C7:3283–$32D2)
; Command $F5 (BattleCD_PauseWait: Arg0 $F5 to pause, 0 to go on).
;   - Arg0 nonzero: clears ADSR1 bit 7 of every voice (the envelope
;     then follows GAIN, which Spc_Start set to a mode that does not
;     move: frozen, probably), writes 0 to every VOLL/VOLR, sets
;     !Spc_Flags87 bit 4 (Spc_MainLoop then steps nothing and
;     Spc_StartSfx starts nothing), and clears !Spc_UnkD0,
;     !Spc_KonShadow and !Spc_VoiceVol (16 bytes).
;   - Arg0 0: sets ADSR1 bit 7 again, clears bit 4, !Spc_UnkD0 = $FF
;     (every volume rewritten on the next pass).
; Callers note: reached only through Spc_CmdTable80 entry 21.
; Entry: P=0; !Spc_CmdArg0 = pause (nonzero) or go on (0)
; Exit:  pausing: A, X, Y = 0; going on: A = Y = $85 (the loop's end), X
;        unchanged
; DSP:   ADSR1 of voices 0-7; pausing also VOLL/VOLR of voices 0-7
Spc_CmdPause:
    mov.b a,!Spc_CmdArg0
    beq .go_on
    mov y,#!DSP_ADSR1
.adsr_off:
    mov.b !SPC_DSPADDR,y
    mov.b a,!SPC_DSPDATA
    and a,#!DSP_ADSR_OffMask
    mov.b !SPC_DSPDATA,a
    mov a,y
    clrc
    adc a,#!DSP_VoiceStride
    mov y,a
    bpl .adsr_off
    mov x,#$00
    mov y,#!DSP_VOLL
.silence:
    mov.b !SPC_DSPADDR,y
    mov.b !SPC_DSPDATA,x
    inc y                               ; VOLR
    mov.b !SPC_DSPADDR,y
    mov.b !SPC_DSPDATA,x
    mov a,y
    clrc
    adc a,#!DSP_VoiceStride-1
    mov y,a
    bpl .silence
    set1.b !Spc_Flags87.4
    mov a,#$00
    mov.b !Spc_UnkD0,a
    mov.b !Spc_KonShadow,a
    mov y,#!Spc_NumVoiceVol
.clear_vol:
    mov.w !Spc_VoiceVol-1+y,a
    dbnz y,.clear_vol
    ret
.go_on:
    mov y,#!DSP_ADSR1
.adsr_on:
    mov.b !SPC_DSPADDR,y
    mov.b a,!SPC_DSPDATA
    or a,#!DSP_ADSR_OnBit
    mov.b !SPC_DSPDATA,a
    mov a,y
    clrc
    adc a,#!DSP_VoiceStride
    mov y,a
    bpl .adsr_on
    clr1.b !Spc_Flags87.4
    mov.b !Spc_UnkD0,#!Spc_AllBits
    ret

; $100E — Spc_XferReceive (110 bytes, $100E–$107B; ROM $C7:32D3–$3340)
; Command $FE, and the song commands' load (Spc_StartSong): takes the
; 65816's transfers (Audio_CmdLoadSong, Audio_SendSampleDir,
; Audio_SendSongData, Audio_UploadSample, Audio_CmdSwapSample,
; Audio_UploadBlock2F00).
;   1. Waits for CPUIO0 = (the command's id + 1) & $7F, the 65816's next
;      sequence value, read until two reads agree; while it still reads
;      the id, echoes the id again.
;   2. Spc_XferHeader (also the return address every mode handler goes
;      back to): with an echo change running (!Spc_Flags88 bit 0),
;      Spc_Unk1326 counts timer 1. Takes a header: !Spc_XferAddr =
;      CPUIO2/3, the mode = CPUIO1.
;      - Mode !SpcCmd_XferEnd ($E0): CPUIO1 = 0, CPUIO0 = the step's
;        value (echo), and leaves through Spc_ClearPorts01: the load is
;        over.
;      - Else: CPUIO1 = the mode asked for, CPUIO0 = the value (echo).
;        An address below $1E00 (the driver) takes mode 0 all the same
;        (CPUIO1 still shows the mode asked for); an address in $2Fxx (the effects block) first stops both
;        effect groups. Pushes Spc_XferHeader and the mode's handler
;        (Spc_XferModeTable, mode & 7), waits for CPUIO0 to change and
;        settle (the first data step), sets CPUIO1 = !SpcCmd_XferBusy and
;        RETs into the handler, which returns to Spc_XferHeader for the
;        next header.
; Each step thereafter: data in CPUIO1-3, a new value in CPUIO0; the
; handler echoes it. A step value with bit 7 set ends the block ($E0) or,
; for $FF with CPUIO1 $F0 (Audio_Boot's reset kick), runs command $FF
; (Spc_CmdControl: back to the IPL ROM); other such values are waited out.
; Modes (Spc_XferModeTable): 0, 4, 6 Spc_XferSkip; 1 Spc_XferBytes;
; 2 Spc_XferWords (!Audio_XferWords); 3 Spc_XferTriples
; (!Audio_XferTriples); 5 Spc_XferLive (!Audio_XferLive); 7
; Spc_XferMove (!Audio_XferMove).
; Callers note: CALL from Spc_StartSong ($0C05); Spc_CmdTable80 entry 30.
;   Spc_XferHeader: the return address pushed at $1059/$105C.
; Entry: P=0; X = the command's id
; Exit:  through Spc_ClearPorts01: A = $E0, X = the last step's value,
;        Y = the last header's CPUIO3
; Ports: CPUIO0-3 read; CPUIO0 (echoes) and CPUIO1 (the mode, $EE, 0)
;        written
; Callees: Spc_Unk1326, Spc_StopSfxA, Spc_StopSfxB, the mode handlers
;   (RET), Spc_ClearPorts01 (JMP)
; Sub-entries: Spc_XferHeader.
Spc_XferReceive:
    mov a,x
    inc a
    and a,#!SpcCmd_SeqMask
    mov.b !Spc_Temp9B,a
.wait_seq:
    mov.b a,!SPC_CPUIO0
    beq .wait_seq
    cmp.b a,!SPC_CPUIO0
    bne .wait_seq
    cmp.b x,!SPC_CPUIO0
    bne .changed
    mov.b !SPC_CPUIO0,x
    bra .wait_seq
.changed:
    cmp.b a,!Spc_Temp9B
    bne .wait_seq
    mov x,a
Spc_XferHeader:                         ; header: see Spc_XferReceive
    bbc.b !Spc_Flags88.0,.header
    call Spc_Unk1326
.header:
    movw.b ya,!SPC_CPUIO2
    movw.b !Spc_XferAddr,ya
    mov.b a,!SPC_CPUIO1
    cmp a,#!SpcCmd_XferEnd
    beq .end
    mov.b !SPC_CPUIO1,a
    mov.b !SPC_CPUIO0,x
    and a,#!Spc_XferModeMask
    asl a
    cmp y,#!Spc_XferLowPage
    bcc .refuse
    cmp y,#!Spc_XferSfxPage
    bne .dispatch
    push x
    push a
    call Spc_StopSfxA
    call Spc_StopSfxB
    pop a
    pop x
    bra .dispatch
.refuse:
    mov a,#$00                          ; mode 0
.dispatch:
    mov y,a
    mov a,#Spc_XferHeader>>8
    push a
    mov a,#Spc_XferHeader&$FF
    push a
    mov.w a,Spc_XferModeTable+1+y
    push a
    mov.w a,Spc_XferModeTable+y
    push a
.wait_step:
    cmp.b x,!SPC_CPUIO0
    beq .wait_step
.settle:
    mov.b x,!SPC_CPUIO0
    cmp.b x,!SPC_CPUIO0
    bne .settle
    mov a,#!SpcCmd_XferBusy
    mov.b !SPC_CPUIO1,a
    ret
.end:
    mov.b !SPC_CPUIO1,#$00
    mov.b !SPC_CPUIO0,x
    jmp Spc_ClearPorts01

; $107C — Spc_XferTriples (112 bytes, $107C–$10EB; ROM $C7:3341–$33B0)
; Mode 3 (!Audio_XferTriples): three bytes per step, CPUIO1-3, stored
; at !Spc_XferAddr on. The store addresses are written into the three
; store instructions (.store1-3, self-modifying), indexed by Y; when Y
; passes $7F (it is then $80, $81 or $82) the bases move on by $80 and
; Y drops by $80. The echo is
; written after CPUIO1 is read and before CPUIO2/3 are, so those two are
; read while the 65816 may already be on its next step (a timing
; assumption, as the code reads; not traced on the 65816 side).
; Then the step values as in Spc_XferReceive: bit 7 set ends ($E0), or
; command $FF / $F0 resets.
; Callers note: reached only through Spc_XferModeTable entry 3 (RET from
;   Spc_XferHeader).
; Entry: P=0; X = the step's value (settled), !Spc_XferAddr set
; Exit:  to Spc_XferHeader (RET); X = $E0; A, Y clobbered
; Ports: CPUIO1-3 read; CPUIO0 = each step's value (echo)
; Callees: Spc_CmdControl (JMP)
Spc_XferTriples:
    movw.b ya,!Spc_XferAddr
    mov.w .store1+1,a
    mov.w .store1+2,y
    mov.w .store2+1,a
    mov.w .store2+2,y
    mov.w .store3+1,a
    mov.w .store3+2,y
    mov y,#$00
    bra .data
.settled:
    cmp.b x,!SPC_CPUIO0
    bne .read
.data:
    mov.b a,!SPC_CPUIO1
.store1:
    mov.w !Spc_XferAddr+y,a             ; the operand is rewritten above
    inc y
    mov.b !SPC_CPUIO0,x
    mov.b a,!SPC_CPUIO2
.store2:
    mov.w !Spc_XferAddr+y,a
    inc y
    mov.b a,!SPC_CPUIO3
.store3:
    mov.w !Spc_XferAddr+y,a
    inc y
    bmi .advance
.wait:
    cmp.b x,!SPC_CPUIO0
    beq .wait
.read:
    mov.b x,!SPC_CPUIO0
    bpl .settled
    cmp.b x,!SPC_CPUIO0
    bne .read
    cmp x,#!SpcCmd_XferEnd
    beq .done
    cmp x,#!SpcCmd_Control
    bne .wait
    mov a,#!SpcCmd_ControlReset
    cbne.b !SPC_CPUIO1,.wait
    mov.b !Spc_CmdArg0,a
    jmp Spc_CmdControl
.advance:
    mov a,y
    and a,#!SpcCmd_SeqMask              ; Y - $80
    mov y,a
    mov.w a,.store1+1
    eor a,#!Spc_SignBias                ; + $80 to the bases
    bmi .same_page
    inc.w .store1+2
    inc.w .store2+2
    inc.w .store3+2
.same_page:
    mov.w .store1+1,a
    mov.w .store2+1,a
    mov.w .store3+1,a
    bra .wait
.done:
    ret

; $10EC — Spc_XferLive (123 bytes, $10EC–$1166; ROM $C7:33B1–$342B)
; Mode 5 (!Audio_XferLive): as Spc_XferTriples, but while it waits for a
; step it keeps the music going: when timer 0 has ticked, a pass of
; Spc_LivePass (the song alone, without effects or commands). Commands
; $70/$71 (Audio_CmdBlockVariant, Audio_CmdSwapSample) use this mode
; (!Audio_XferLive), so the song goes on while their data comes in.
; Callers note: reached only through Spc_XferModeTable entry 5.
; Entry: P=0; X = the step's value (settled), !Spc_XferAddr set
; Exit:  to Spc_XferHeader (RET); X = $E0; A, Y clobbered
; Ports: as Spc_XferTriples
; Callees: Spc_LivePass, Spc_CmdControl (JMP)
Spc_XferLive:
    movw.b ya,!Spc_XferAddr
    mov.w .store1+1,a
    mov.w .store1+2,y
    mov.w .store2+1,a
    mov.w .store2+2,y
    mov.w .store3+1,a
    mov.w .store3+2,y
    mov y,#$00
    bra .data
.settled:
    cmp.b x,!SPC_CPUIO0
    bne .read
.data:
    mov.b a,!SPC_CPUIO1
.store1:
    mov.w !Spc_XferAddr+y,a             ; the operand is rewritten above
    inc y
    mov.b !SPC_CPUIO0,x
    mov.b a,!SPC_CPUIO2
.store2:
    mov.w !Spc_XferAddr+y,a
    inc y
    mov.b a,!SPC_CPUIO3
.store3:
    mov.w !Spc_XferAddr+y,a
    inc y
    bmi .advance
.wait:
    mov.b a,!SPC_T0OUT
    beq .no_tick
    push x
    push y
    call Spc_LivePass
    pop y
    pop x
.no_tick:
    cmp.b x,!SPC_CPUIO0
    beq .wait
.read:
    mov.b x,!SPC_CPUIO0
    bpl .settled
    cmp.b x,!SPC_CPUIO0
    bne .read
    cmp x,#!SpcCmd_XferEnd
    beq .done
    cmp x,#!SpcCmd_Control
    bne .wait
    mov a,#!SpcCmd_ControlReset
    cbne.b !SPC_CPUIO1,.wait
    mov.b !Spc_CmdArg0,a
    jmp Spc_CmdControl
.advance:
    mov a,y
    and a,#!SpcCmd_SeqMask              ; Y - $80
    mov y,a
    mov.w a,.store1+1
    eor a,#!Spc_SignBias                ; + $80 to the bases
    bmi .same_page
    inc.w .store1+2
    inc.w .store2+2
    inc.w .store3+2
.same_page:
    mov.w .store1+1,a
    mov.w .store2+1,a
    mov.w .store3+1,a
    bra .wait
.done:
    ret

; $1167 — Spc_XferWords (75 bytes, $1167–$11B1; ROM $C7:342C–$3476)
; Mode 2 (!Audio_XferWords): two bytes per step, CPUIO1/2, stored at
; !Spc_XferAddr on (two self-modified stores, Y counting through a page,
; then the bases' high bytes go up); the echo comes after both are read.
; Step values as in Spc_XferTriples.
; Callers note: reached only through Spc_XferModeTable entry 2.
; Entry: P=0; X = the step's value (settled), !Spc_XferAddr set
; Exit:  to Spc_XferHeader (RET); X = $E0; A, Y clobbered
; Ports: CPUIO1/2 read; CPUIO0 = each step's value (echo)
; Callees: Spc_CmdControl (JMP)
Spc_XferWords:
    movw.b ya,!Spc_XferAddr
    mov.w .store1+1,a
    mov.w .store1+2,y
    mov.w .store2+1,a
    mov.w .store2+2,y
    mov y,#$00
    bra .data
.settled:
    cmp.b x,!SPC_CPUIO0
    bne .read
.data:
    mov.b a,!SPC_CPUIO1
.store1:
    mov.w !Spc_XferAddr+y,a             ; the operand is rewritten above
    inc y
    mov.b a,!SPC_CPUIO2
    mov.b !SPC_CPUIO0,x
.store2:
    mov.w !Spc_XferAddr+y,a
    inc y
    bne .wait
    inc.w .store1+2
    inc.w .store2+2
.wait:
    cmp.b x,!SPC_CPUIO0
    beq .wait
.read:
    mov.b x,!SPC_CPUIO0
    bpl .settled
    cmp.b x,!SPC_CPUIO0
    bne .read
    cmp x,#!SpcCmd_XferEnd
    beq .done
    cmp x,#!SpcCmd_Control
    bne .wait
    mov a,#!SpcCmd_ControlReset
    cbne.b !SPC_CPUIO1,.wait
    mov.b !Spc_CmdArg0,a
    jmp Spc_CmdControl
.done:
    ret

; $11B2 — Spc_XferBytes (50 bytes, $11B2–$11E3; ROM $C7:3477–$34A8)
; Mode 1: one byte per step, CPUIO1, stored through (!Spc_XferAddr)+Y.
; It echoes the step's value before it reads CPUIO1. No 65816 caller
; uses mode 1 (its
; transfer modes are 2, 3, 5 and 7: !Audio_Xfer*).
; Callers note: reached only through Spc_XferModeTable entry 1.
; Entry: P=0; X = the step's value (settled), !Spc_XferAddr set
; Exit:  to Spc_XferHeader (RET); X = $E0; A, Y clobbered;
;        !Spc_XferAddr+1 moved on by the pages written
; Ports: CPUIO1 read; CPUIO0 = each step's value (echo)
; Callees: Spc_CmdControl (JMP)
Spc_XferBytes:
    mov y,#$00
    bra .data
.settled:
    cmp.b x,!SPC_CPUIO0
    bne .read
.data:
    mov.b !SPC_CPUIO0,x
    mov.b a,!SPC_CPUIO1
    mov.b (!Spc_XferAddr)+y,a
    inc y
    bne .wait
    inc.b !Spc_XferAddr+1
.wait:
    cmp.b x,!SPC_CPUIO0
    beq .wait
.read:
    mov.b x,!SPC_CPUIO0
    bpl .settled
    cmp.b x,!SPC_CPUIO0
    bne .read
    cmp x,#!SpcCmd_XferEnd
    beq .done
    cmp x,#!SpcCmd_Control
    bne .wait
    mov a,#!SpcCmd_ControlReset
    cbne.b !SPC_CPUIO1,.wait
    mov.b !Spc_CmdArg0,a
    jmp Spc_CmdControl
.done:
    ret

; $11E4 — Spc_XferSkip (34 bytes, $11E4–$1205; ROM $C7:34A9–$34CA)
; Modes 0, 4 and 6, and every transfer to an address below $1E00: echoes
; each step and stores nothing, until a step value with bit 7 set ends
; it ($E0) or resets (command $FF / $F0). This keeps the driver's own
; code from being overwritten.
; Callers note: reached only through Spc_XferModeTable entries 0, 4, 6.
; Entry: P=0; X = the step's value (settled)
; Exit:  to Spc_XferHeader (RET); A = X = $E0; Y unchanged
; Ports: CPUIO0 = each step's value (echo)
; Callees: Spc_CmdControl (JMP)
Spc_XferSkip:
    mov.b !SPC_CPUIO0,x
.wait:
    cmp.b x,!SPC_CPUIO0
    beq .wait
.read:
    mov.b x,!SPC_CPUIO0
    cmp.b x,!SPC_CPUIO0
    bne .read
    mov a,x
    bpl Spc_XferSkip
    cmp x,#!SpcCmd_XferEnd
    beq .done
    cmp x,#!SpcCmd_Control
    bne Spc_XferSkip
    mov a,#!SpcCmd_ControlReset
    cbne.b !SPC_CPUIO1,Spc_XferSkip
    mov.b !Spc_CmdArg0,a
    jmp Spc_CmdControl
.done:
    ret

; $1206 — Spc_XferMove (111 bytes, $1206–$1274; ROM $C7:34CB–$3539)
; Mode 7 (!Audio_XferMove): moves blocks inside ARAM (Audio_CmdLoadSong's
; compaction of the sample slots, when a song's sample set changes). The
; header's address
; is the first block's source; then, each a step with a word in
; CPUIO2/3: the destination (!Spc_XferDest), the length (!Spc_Temp9B
; low, !Spc_Temp9C pages), and the next block's source, until a step
; ends the transfer (Spc_XferNextStep, C=1). The length's whole pages
; are copied first, upwards (a self-modified load and store, Y through
; each page); then the rest, !Spc_Temp9B bytes, downwards from the end
; (pointers - 1, Y from the count down to 1, again self-modified).
; Callers note: reached only through Spc_XferModeTable entry 7; it loops
;   back to its start (BRA $1272).
; Entry: P=0; X = the step's value (settled), !Spc_XferAddr = the source
; Exit:  to Spc_XferHeader (RET) with C=1; X = $E0, Y = $60
; Ports: CPUIO2/3 read; CPUIO0 = each step's value (echo)
; Callees: Spc_XferNextStep
Spc_XferMove:
    movw.b ya,!SPC_CPUIO2
    movw.b !Spc_XferDest,ya
    mov.b !SPC_CPUIO0,x
    call Spc_XferNextStep
    bcs .done
    movw.b ya,!SPC_CPUIO2
    movw.b !Spc_Temp9B,ya               ; the length
    mov.b !SPC_CPUIO0,x
    mov a,y
    beq .rest
    movw.b ya,!Spc_XferAddr
    mov.w .page_load+1,a
    mov.w .page_load+2,y
    movw.b ya,!Spc_XferDest
    mov.w .page_store+1,a
    mov.w .page_store+2,y
    mov y,#$00
.page_load:
    mov.w a,!Spc_XferAddr+y             ; the operands are rewritten above
.page_store:
    mov.w !Spc_XferAddr+y,a
    inc y
    bne .page_load
    inc.b !Spc_XferAddr+1
    inc.b !Spc_XferDest+1
    inc.w .page_load+2
    inc.w .page_store+2
    dbnz.b !Spc_Temp9C,.page_load
.rest:
    decw.b !Spc_XferAddr
    decw.b !Spc_XferDest
    movw.b ya,!Spc_XferAddr
    mov.w .rest_load+1,a
    mov.w .rest_load+2,y
    movw.b ya,!Spc_XferDest
    mov.w .rest_store+1,a
    mov.w .rest_store+2,y
    mov.b y,!Spc_Temp9B
    beq .next
.rest_load:
    mov.w a,!Spc_XferAddr+y             ; the operands are rewritten above
.rest_store:
    mov.w !Spc_XferAddr+y,a
    dbnz y,.rest_load
.next:
    call Spc_XferNextStep
    bcs .done
    movw.b ya,!SPC_CPUIO2
    movw.b !Spc_XferAddr,ya             ; the next source
    mov.b !SPC_CPUIO0,x
    call Spc_XferNextStep
    bcs .done
    bra Spc_XferMove
.done:
    ret

; $1275 — Spc_XferNextStep (40 bytes, $1275–$129C; ROM $C7:353A–$3561)
; Waits for Spc_XferMove's next step: for CPUIO0 to change, then to
; settle. A value with bit 7 clear: returns C=0. $E0: returns C=1 (the
; end). $FF with CPUIO1 $F0: command $FF (Spc_CmdControl, the reset);
; other values with bit 7 set are waited out.
; Quirk (a byte shared by two instructions): the C=0 return branches to
; the operand of `mov y,#$60`, which is `clrc`, so the C=1 path loads Y
; with $60 and the C=0 path keeps Y.
; Callers note: CALL from Spc_XferMove ($120C, $1262, $126D).
; Entry: P=0; X = the last step's value
; Exit:  C=0: X = the new value (not echoed), Y unchanged; C=1: X = $E0,
;        Y = $60; A unchanged, or $F0 after a $FF step that was no reset
; Ports: CPUIO0 read (CPUIO1 for the reset)
; Callees: Spc_CmdControl (JMP)
Spc_XferNextStep:
    cmp.b x,!SPC_CPUIO0
    beq Spc_XferNextStep
.read:
    mov.b x,!SPC_CPUIO0
    bpl .data
    cmp.b x,!SPC_CPUIO0
    bne .read
    cmp x,#!SpcCmd_XferEnd
    beq .end
    cmp x,#!SpcCmd_Control
    bne Spc_XferNextStep
    mov a,#!SpcCmd_ControlReset
    cbne.b !SPC_CPUIO1,Spc_XferNextStep
    mov.b !Spc_CmdArg0,a
    jmp Spc_CmdControl
.data:
    cmp.b x,!SPC_CPUIO0
    beq .clrc+1                         ; on the `clrc` inside .clrc
    bra Spc_XferNextStep
.end:
    setc
.clrc:
    mov y,#$60                          ; lint-ok: $60 is the `clrc` opcode the BEQ above lands on
    ret

; $129D — Spc_CmdTimer (25 bytes, $129D–$12B5; ROM $C7:3562–$357A)
; Command $F6: !Spc_Flags88 bit 5 = (!Spc_CmdArg0 != 0); timer 0's
; divider = !SPC_Timer0Fast (a main-loop pass every 125 us) when set,
; !SPC_Timer0Divider (5.25 ms) when clear, with timer 0 stopped and
; started again around the write. With bit 5 set Spc_StepTracks also steps
; the song every pass, without the tempo: a fast-forward, probably.
; Callers note: reached only through Spc_CmdTable80 entry 22.
; Entry: P=0; !Spc_CmdArg0 = on (nonzero) or off
; Exit:  A = the divider; X, Y unchanged
Spc_CmdTimer:
    mov.b a,!Spc_CmdArg0
    clrc
    adc a,#!Spc_TestCarry
    mov1 !Spc_Flags88.5,c
    bcs .fast
    mov a,#!SPC_Timer0Divider
    bra .set
.fast:
    mov a,#!SPC_Timer0Fast
.set:
    mov.b !SPC_CONTROL,#!SPC_CONTROL_Timer1
    mov.b !SPC_T0TARGET,a
    mov.b !SPC_CONTROL,#!SPC_CONTROL_Timers01
    ret

; $12B6 — Spc_CmdSongCond (7 bytes, $12B6–$12BC; ROM $C7:357B–$3581)
; Command $88: !Spc_SongCond = !Spc_CmdArg0 & $0F, the value some
; sequence commands compare to choose a branch of the song ($1D05,
; $1D2E).
; Callers note: reached only through Spc_CmdTable80 entry 8.
; Entry: P=0; !Spc_CmdArg0 = the value (low nibble)
; Exit:  A = the value; X, Y unchanged
Spc_CmdSongCond:
    mov.b a,!Spc_CmdArg0
    and a,#!Spc_LowNibble
    mov.b !Spc_SongCond,a
    ret

; $12BD — Spc_CmdControl (32 bytes, $12BD–$12DC; ROM $C7:3582–$35A1)
; Command $FF, also taken in the middle of a transfer:
;   - Arg0 !SpcCmd_ControlReport (1): !Spc_Flags88 bit 7 = (Arg1 != 0)
;     (Spc_MainLoop then leaves CPUIO0-3 to Spc_Unk1438);
;   - Arg0 !SpcCmd_ControlReset ($F0): FLG = !DSP_FLG_ResetMute, the IPL
;     ROM mapped in (CONTROL = !SPC_CONTROL_IplRom) and JMP !SPC_IplRom:
;     the driver stops and the IPL ROM waits for a new upload. This is
;     what Audio_Boot's !Audio_ResetKick0/1 ($FF in APUIO0, $F0 in
;     APUIO1) does to a running driver;
;   - other values: nothing.
; Callers note: JMP from Spc_XferTriples ($10C9), Spc_XferLive ($1144),
;   Spc_XferWords ($11AE), Spc_XferBytes ($11E0), Spc_XferSkip ($1202)
;   and Spc_XferNextStep ($1290); Spc_CmdTable80 entry 31.
; Entry: P=0; !Spc_CmdArg0, !Spc_CmdArg1 as above
; Exit:  reset: does not return; else A = Arg0 (or Arg1 + $FF), X, Y
;        unchanged
; DSP:   FLG (reset)
; Callees: Spc_WriteDsp
Spc_CmdControl:
    mov.b a,!Spc_CmdArg0
    cmp a,#!SpcCmd_ControlReport
    bne .reset
    mov.b a,!Spc_CmdArg1
    clrc
    adc a,#!Spc_TestCarry
    mov1 !Spc_Flags88.7,c
.done:
    ret
.reset:
    cmp a,#!SpcCmd_ControlReset
    bne .done
    mov a,#!DSP_FLG_ResetMute
    mov y,#!DSP_FLG
    call Spc_WriteDsp
    mov.b !SPC_CONTROL,#!SPC_CONTROL_IplRom
    jmp !SPC_IplRom

; $12DD — Spc_NullCommand (1 byte, $12DD–$12DD; ROM $C7:35A2–$35A2)
; A lone RET: the handler of the commands that do nothing ($12, $13,
; $16, $17, $1A-$1F in Spc_CmdTable10; $84, $8A-$8D, $8F, $F7, $FA, $FB
; in Spc_CmdTable80; and sequence commands $E5 and $E7, through the
; words at $1596 and $159A of the sequence-command handler table at
; $1554, indexed by command - $C4 from $073D).
; Callers note: reached only through those table entries.
; Entry: P=0
; Exit:  A, X, Y and PSW unchanged
Spc_NullCommand:
    ret

base off
arch 65816
