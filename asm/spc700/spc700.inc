; ============================================================
; spc700.inc — names for the SPC700 sound driver (asm/spc700/driver.asm)
;
; Everything here is an ARAM address or a value, as the SPC700 sees it;
; nothing is a SNES bus address. Prefixes keep these apart from the 65816
; names (asar lets a later define replace an earlier one silently):
;   !SPC_*    the SPC700's I/O registers ($F0-$FF) and their values
;   !DSP_*    S-DSP register numbers (written to !SPC_DSPADDR)
;   !Spc_*    the driver's RAM: direct page ($0000-$00EF, P=0), page 1
;             and the work area from $F100
;   !SpcCmd_* command ids as the driver sees them in !Spc_CmdId
;   !SpcSong_* offsets in the song header at !AudioAram_Song
; The ARAM layout shared with the 65816 side (!AudioAram_*) is in
; constants_engine.inc.
;
; A name or meaning marked "inferred" rests on the code cited; "Unk"
; names say what has been observed so far.
; ============================================================

; --- SPC700 I/O registers (direct page, P=0) ---
!SPC_CONTROL = $F1                       ; write: timer enables (bits 0-2), port latch clears
                                         ; (bit 4: ports 0/1, bit 5: ports 2/3), IPL ROM (bit 7)
!SPC_DSPADDR = $F2                       ; S-DSP register number for !SPC_DSPDATA
!SPC_DSPDATA = $F3                       ; S-DSP register data
!SPC_CPUIO0 = $F4                        ; port 0: read = what the 65816 wrote to APUIO0, write = what
                                         ; it reads there
!SPC_CPUIO1 = $F5                        ; port 1 (APUIO1)
!SPC_CPUIO2 = $F6                        ; port 2 (APUIO2)
!SPC_CPUIO3 = $F7                        ; port 3 (APUIO3)
!SPC_T0TARGET = $FA                      ; timer 0 divider (8 kHz ticks)
!SPC_T1TARGET = $FB                      ; timer 1 divider (8 kHz ticks)
!SPC_T0OUT = $FD                         ; timer 0 count (4 bits), cleared by the read
!SPC_T1OUT = $FE                         ; timer 1 count (4 bits), cleared by the read

!SPC_CONTROL_ClearPorts = $30            ; clear all four port latches, timers off, IPL ROM off
!SPC_CONTROL_Timers01 = $03              ; timers 0 and 1 on, IPL ROM off
!SPC_CONTROL_ClearPorts01 = $13          ; the same plus clear the port 0/1 latches
!SPC_CONTROL_Timer1 = $02                ; timer 1 on, timer 0 off (stopped to take a new divider)
!SPC_CONTROL_Timer0 = $01                ; timer 0 on, timer 1 off (stopped, so it restarts at 0)
!SPC_CONTROL_IplRom = $80                ; the IPL ROM mapped at $FFC0, timers off
!SPC_IplRom = $FFC0                      ; the IPL ROM's entry
!SPC_Timer0Divider = $2A                 ; 42 x 125 us = 5.25 ms: one pass of the main loop
!SPC_Timer1Divider = $80                 ; 128 x 125 us = 16 ms
!SPC_Timer0Fast = $01                    ; timer 0 divider under command $F6: a pass every 125 us

; --- S-DSP registers (per voice: + $10 x voice) ---
!DSP_GAIN = $07                          ; voice 0's GAIN
!DSP_VoiceStride = $10                   ; voice n's registers are at n x $10
!DSP_MVOLL = $0C                         ; main volume left
!DSP_MVOLR = $1C                         ; main volume right
!DSP_EVOLL = $2C                         ; echo volume left
!DSP_EVOLR = $3C                         ; echo volume right
!DSP_KOF = $5C                           ; key off (a bit per voice)
!DSP_DIR = $5D                           ; sample directory page
!DSP_SRCN = $04                          ; voice 0's sample number
!DSP_OUTX = $09                          ; voice 0's current output sample (read)
!DSP_EON = $4D                           ; echo on (a bit per voice)
!DSP_EFB = $0D                           ; echo feedback
!DSP_EDL = $7D                           ; echo delay (low nibble: 16 ms steps)
!DSP_ESA = $6D                           ; echo buffer page
!DSP_KON = $4C                           ; key on
!DSP_PMON = $2D                          ; pitch modulation on
!DSP_NON = $3D                           ; noise on
!DSP_FIR0 = $0F                          ; FIR coefficient 0 (coefficient n: + n x $10)
!DSP_FLG_EchoOff = $20                   ; FLG bit 5: echo writes off
!DSP_FLG_EchoOnMask = $DF                ; FLG without bit 5
!DSP_ADSR1_AttackMask = $0F              ; ADSR1 bits 0-3: attack rate
!DSP_ADSR1_DecayMask = $70               ; ADSR1 bits 4-6: decay rate
!DSP_ADSR2_RateMask = $1F                ; ADSR2 bits 0-4: sustain rate
!DSP_ADSR2_LevelMask = $E0               ; ADSR2 bits 5-7: sustain level
!DSP_VOLL = $00                          ; voice 0's volume left (VOLR is the next register)
!DSP_ADSR1 = $05                         ; voice 0's ADSR1 (bit 7: ADSR on, else GAIN)
!DSP_FLG = $6C                           ; reset, mute, echo-write disable, noise clock
!DSP_ADSR_OnBit = $80                    ; ADSR1 bit 7
!DSP_ADSR_OffMask = $7F                  ; ADSR1 without bit 7
!DSP_FLG_ResetMute = $E0                 ; FLG: soft reset, mute, echo writes off
!DSP_MVOL_Boost = $7F                    ; main volume command $8E sets (Spc_CmdVolumeBoost)

!DSP_GAIN_Start = $A0                    ; GAIN Spc_Start gives every voice (bits 7-5 = %101:
                                         ; exponential decrease; rate 0: the envelope does not move)
!DSP_MVOL_Start = $40                    ; main volume Spc_Start sets (both sides)
!DSP_KOF_All = $FF                       ; key off all eight voices

; --- Driver RAM: direct page ---
; Tracks: 16 tracks, X = track x 2. Tracks 0-7 ($00-$0E) are the song's, one
; per voice; tracks 8-15 ($10-$1E) play sound effects on voices 0-7 (the
; voice of track t is t & 7). A track's voice bit is 1 << voice.
!Spc_Scratch00 = $00                     ; word: the offset that moves the song's addresses to where it
                                         ; was loaded (Spc_StartSong); the jump commands add it
!Spc_TrackPtr = $02                      ; word per track ($02-$21): the track's read pointer in ARAM
!Spc_KonShadow = $22                     ; KON for the next pass (written by Spc_MainLoop, then 0)
!Spc_KofShadow = $23                     ; KOF for the next pass (written by Spc_MainLoop, then 0)
!Spc_Unk24 = $24                         ; voice bits; Spc_MainLoop runs the song's tracks only for
                                         ; these; a resumed song keys them on again (Spc_StartSong)
!Spc_Unk25 = $25                         ; voice bits; Spc_MainLoop runs the effect tracks only for
                                         ; these; Spc_StartSfx clears the new effect's
!Spc_TrackWait = $26                     ; byte per track (+X): passes until the track's next step
                                         ; (Spc_InitTrack sets 1, decremented by $03A5)
!Spc_TrackUnk27 = $27                    ; byte per track (+X): the loop stack's slot (4 per track, from
                                         ; X x 2; Spc_SeqLoopStart / Spc_SeqLoopEnd)
!Spc_TempoWord = $46                     ; word: !Spc_Tempo ($47) with its fraction ($46), for its fade
!Spc_Tempo = $47                         ; added to !Spc_TempoAccum each pass ($0377); a song step
                                         ; runs on the carry (inferred: tempo); 1 at a song's start
!Spc_TempoAccum = $48                    ; the accumulator; $FF at a song's start (first pass steps)
!Spc_SfxTempoAccum = $49                 ; the effects' accumulator: + !Spc_SfxTempo each pass, the effect
                                         ; tracks step on the carry (Spc_StepTracks)
!Spc_TempoFadeSteps = $4A                ; steps left of the tempo's fade (Spc_StepSongFades)
!Spc_TempoFadeDelta = $4B                ; word: added to !Spc_TempoWord each step
!Spc_Unk4D = $4D                         ; the song's volume: !Spc_CmdArg1 of the song command (byte 1 of
                                         ; AudioRom_SongEcho), or sequence command $F4 (Spc_WriteVoice)
!Spc_EchoVolWord = $4E                   ; word: !Spc_EchoVolume ($4F) with its fraction, for its fade
!Spc_EchoVolDelta = $50                  ; word: its step
!Spc_EchoVolSteps = $52                  ; steps left
!Spc_EchoVolume = $4F                    ; source of both EVOL shadows (!Spc_EvolShadow)
!Spc_SongTracks = $53                    ; voice bits of the tracks the song uses (set by
                                         ; Spc_StartSong from the header's pointers)
!Spc_SongEon = $54                       ; copied to !Spc_EonShadow at a song's start (byte; $55 is
                                         ; cleared with it)
!Spc_SongNon = $56                       ; copied to !Spc_NonShadow at a song's start
!Spc_SongPmon = $58                      ; copied to !Spc_PmonShadow at a song's start
!Spc_Unk5A = $5A                         ; cleared at a song's start
!Spc_Unk5B = $5B                         ; voice bits; Spc_StartSfx clears the new effect's
!Spc_Unk5C = $5C                         ; cleared at a song's start
!Spc_Unk5D = $5D                         ; voice bits; Spc_StartSfx clears the new effect's
!Spc_Unk5E = $5E                         ; song voices keyed on once while in !Spc_Unk5C (Spc_TrackStep)
!Spc_Unk5F = $5F                         ; the same for effect voices (!Spc_Unk5D)
!Spc_Unk60 = $60                         ; cleared at a song's start
!Spc_Unk61 = $61                         ; voice bits; Spc_StartSfx clears the new effect's
!Spc_NoiseClock = $62                    ; ORed into !Spc_FlgShadow's low 5 bits (the FLG noise
                                         ; clock) when a song is resumed
!Spc_SfxNoiseClock = $63                 ; the effects' noise clock (used while any effect voice has noise)
!Spc_FirWord = $65                       ; 8 words ($65-$74): FIR0-7 with fractions (the high bytes are
                                         ; !Spc_FirShadow), faded by Spc_StepSongFades
!Spc_FirShadow = $66                     ; 8 words ($66-$75): FIR0-7 take the low bytes ($66, $68, ...)
!Spc_EfbShadow = $76                     ; EFB
!Spc_EfbWord = $75                       ; word: EFB ($76, !Spc_EfbShadow) with its fraction
!Spc_FirSteps = $77                      ; steps left of the FIR fade
!Spc_EfbSteps = $78                      ; steps left of the EFB fade
!Spc_EfbDelta = $79                      ; word: the EFB step
!Spc_Unk7B = $7B                         ; low nibble of what Spc_MainLoop writes to CPUIO2
!Spc_Unk7C = $7C                         ; cleared at a song's start
!Spc_CurSong = $80                       ; the song playing ($FF: none); inferred: Spc_CmdSongCheck
                                         ; compares the requested song with it
!Spc_EchoDelay = $81                     ; the echo delay in effect (EDL), compared with each song
                                         ; command's !Spc_CmdArg2
!Spc_Unk82 = $82                         ; the echo delay before a change (Spc_SetEchoDelay reads EDL);
                                         ; Spc_WaitTimer1 waits on it
!Spc_Unk83 = $83                         ; timer 1 counts since an echo change (Spc_CountTimer1 during
                                         ; transfers; Spc_WaitTimer1 starts from it)
!Spc_SfxVoices = $86                     ; voice bits taken by sound effects (set by Spc_StartSfx)
!Spc_Flags87 = $87                       ; bit 3: echo volume doubled; bit 4: no song step or new
                                         ; effect (Spc_MainLoop, Spc_StartSfx); other bits not traced
!Spc_Flags88 = $88                       ; bits 0/1: echo change to finish (Spc_StartSong; Spc_StartEchoChange
                                         ; clears bit 1 when the old EDL was 0); bit 5:
                                         ; $0377 steps the song every pass, without the tempo; bit 7:
                                         ; Spc_MainLoop leaves CPUIO0-3 to $1438 (not traced)
!Spc_EonShadow = $89                     ; EON for the next pass
!Spc_NonShadow = $8A                     ; NON
!Spc_PmonShadow = $8B                    ; PMON
!Spc_FlgShadow = $8C                     ; FLG
!Spc_CmdId = $8D                         ; the command being run: what the 65816 wrote to APUIO0
                                         ; (Audio_CmdId)
!Spc_CmdArg0 = $8E                       ; APUIO1 (Audio_CmdArg0)
!Spc_CmdArg1 = $8F                       ; APUIO2 (Audio_CmdArg1)
!Spc_CmdArg2 = $90                       ; APUIO3 (Audio_CmdArg2)
!Spc_VoiceBit = $91                      ; the voice bit of the track in hand (X)
!Spc_XferAddr = $97                      ; word: a transfer's ARAM address (its header's APUIO2/3);
                                         ; also the placeholder operand of the stores
                                         ; Spc_XferTriples / Live / Words rewrite
!Spc_XferDest = $99                      ; word: Spc_XferMove's destination
!Spc_Ptr93 = $93                         ; word: a pointer (Spc_StartSfx: the effect's entry in the
                                         ; table at !AudioAram_Block2F00)
!Spc_Ptr95 = $95                         ; word: a second pointer (save/restore, effect track lookup)
!Spc_Temp92 = $92                        ; scratch byte
!Spc_Temp9B = $9B                        ; scratch byte
!Spc_Temp9C = $9C                        ; scratch byte
!Spc_Temp9D = $9D                        ; scratch byte
!Spc_Temp9E = $9E                        ; scratch byte
!Spc_Temp9F = $9F                        ; scratch word ($9F-$A0)
!Spc_TempA0 = $A0                        ; scratch byte
!Spc_TempA1 = $A1                        ; scratch byte
!Spc_TempA2 = $A2                        ; scratch byte
!Spc_Mute = $A7                          ; voice bits: song tracks on these voices get volume 0
                                         ; (Spc_Unk09F6 at $0A40); commands $F4, $F8, $F9
!Spc_TempoAdj = $A9                      ; word: $AA = a tempo adjustment (signed; Spc_Unk0377 scales
                                         ; !Spc_Tempo by it, probably), $A9 its fraction
!Spc_TempoAdjHi = $AA                    ; !Spc_TempoAdj's value byte (bit 7: slower)
!Spc_TempoAdjDelta = $AB                 ; word: added to !Spc_TempoAdj each fade step
!Spc_TempoAdjSteps = $AD                 ; fade steps left
!Spc_PitchAdj = $AE                      ; word: $AF = the song tracks' pitch adjustment (signed;
                                         ; Spc_Unk0A78 scales the pitch by it), $AE its fraction
!Spc_PitchAdjHi = $AF                    ; !Spc_PitchAdj's value byte (bit 7: lower)
!Spc_SfxPitchAdj = $B1                   ; the same for effect tracks 14-15 (Spc_Unk0A78, X >= $1C)
!Spc_PitchAdjDelta = $B2                 ; word: added to !Spc_PitchAdj each fade step
!Spc_PitchAdjSteps = $B4                 ; fade steps left
!Spc_Quotient = $B5                      ; scratch word: Spc_FadeDelta's result, Spc_NotePitch's pitch,
                                         ; the LFO step in Spc_LfoRate
!Spc_TempB7 = $B7                        ; scratch word ($B7-$B8)
!Spc_TempBA = $BA                        ; scratch byte (Spc_PeekNote: the track's !Spc_TrackUnk27)
!Spc_TrackBits = $A3                     ; the voice bits a loop over tracks has still to visit
!Spc_TempA4 = $A4                        ; scratch byte
!Spc_TempA5 = $A5                        ; scratch byte
!Spc_CurTrack = $A6                      ; X of the track being stepped
!Spc_GroupVolume = $A8                   ; the volume of the track group being stepped (from
                                         ; !Spc_GroupVol)
!Spc_SongHeaderSet = $B9                 ; which track pointer set of the song header to start:
                                         ; !Spc_SongSetA or !Spc_SongSetB (the set's end offset)
!Spc_SavedSong = $BB                     ; the song saved by $13A9 ($FF: none)
!Spc_NewSong = $BC                       ; the song a song command asks for (!Spc_CmdArg0)
!Spc_FadeTimer = $BD                     ; counts passes down from 7; at 0, $1492 (the volume fades)
!Spc_UnkD0 = $D0                         ; voice bits; set to the song's tracks on a resume, cleared
                                         ; on a new start and each pass; $1492 ORs in the tracks whose
                                         ; group volume changed (inferred: volumes to rewrite)
!Spc_UnkD1 = $D1                         ; voice bits; cleared with !Spc_UnkD0; Spc_Unk09F6 rewrites the
                                         ; pitch of these voices ($0A72; inferred: pitches to rewrite)
!Spc_SongCond = $D2                      ; compared with sequence command operands to choose a branch
                                         ; ($1D05, $1D2E); command $88 sets it; 0 at a song's start
!Spc_VoiceVol = $BE                      ; 16 bytes: each voice's last VOLL/VOLR (Spc_Unk09F6, $0A57)
!Spc_UnkD3 = $D3                         ; high nibble of what Spc_MainLoop writes to CPUIO2
!Spc_QueueEnd = $D7                      ; offset of the first free !Spc_CmdQueue entry
!Spc_UnkD8 = $D8                         ; Spc_AnimateBuiltin's position in Spc_BuiltinSampleLoop (2 after
                                         ; Spc_Start, then 3-$23)
!Spc_EvolShadow = $D9                    ; EVOL (left and right both)

; --- Driver RAM: page 1 (per track, +X) ---
!Spc_Track150 = $0150                    ; word per track: low byte a pitch slide asked for (semitones,
                                         ; taken by the next note's Spc_TrackLookAhead), high byte the
                                         ; vibrato's depth byte (0: off)
!Spc_Track170 = $0170                    ; word per track: low byte the tremolo's depth byte (0: off),
                                         ; high byte nonzero: the pan LFO on
!Spc_Page1 = $0100                       ; page 1: what P=1 direct-page operands are relative to
!Spc_FirDelta = $0100                    ; 8 words: the FIR coefficients' steps (Spc_StepSongFades)
!Spc_TrackUnk110 = $0110                 ; byte per track (+X): a song track's vibrato delay (reloaded at
                                         ; each note), an effect track's index into Spc_VibDepthTable
                                         ; (song tracks use index 0) (Spc_SeqVibrato)
!Spc_TrackVibDelay = $0111               ; byte per track (+X): passes before the vibrato starts (counted
                                         ; down by Spc_TrackSlides with P=1; song tracks only wait)
!Spc_TrackTremDelay = $0131              ; the same for the tremolo (all tracks)
!Spc_TrackTremDelayReload = $0130        ; byte per track (+X): the tremolo's delay, reloaded at each note

; --- Driver RAM: work area ---
!Spc_GroupVol = $F160                    ; 3 words: a volume for the song's tracks, for effect tracks
                                         ; 14-15 and for 8-13, in the high bytes (low byte: fraction);
                                         ; $FF after Spc_Start. Inferred: $1492 fades them and marks
                                         ; the group's tracks in !Spc_UnkD0
!Spc_GroupFadeSteps = $F166              ; 3 words: steps of each group's fade still to run (low byte)
!Spc_GroupFadeDelta = $F16C              ; 3 words: each group's volume step (signed, x 256)
!Spc_CmdQueue = $F172                    ; 16 x 4 bytes: commands received while the tracks are
                                         ; stepped ($0892), run later by $08CD; id 0 = free
!Spc_TrackF200 = $F200                   ; word per track: low byte = the note a note byte's index is
                                         ; added to (Spc_TrackStep; $48 at an effect's start), high
                                         ; byte the track's sample (Spc_SetTrackSample)
!Spc_TrackF220 = $F220                   ; word per track: low byte a song track's volume scale
                                         ; (Spc_WriteVoice; $FF at a song's start), high byte the LFO
                                         ; stages (bits 0-2 vibrato, 4-6 tremolo; Spc_TrackEffects)
!Spc_TrackF240 = $F240                   ; word per track: the track's volume in the high byte, a
                                         ; fraction in the low (Spc_WriteVoice, Spc_TrackSlides); $46 at
                                         ; an effect's start
!Spc_TrackVolDelta = $F260              ; word per track: the volume slide's step (Spc_TrackSlides)
!Spc_TrackF280 = $F280                   ; word per track: the pan in the high byte ($80: centre;
                                         ; Spc_WriteVoice), a fraction in the low; an effect starts
                                         ; with !Spc_CmdArg1
!Spc_TrackPanDelta = $F2A0              ; word per track: the pan slide's step
!Spc_TrackF2C0 = $F2C0                   ; word per track: steps left of the volume slide (low) and of
                                         ; the pan slide (high) (Spc_TrackSlides)
!Spc_TrackVibTimer = $F2E0              ; word per track: the vibrato rate's reload (low) and counter
                                         ; (high) (Spc_TrackEffects)
!Spc_TrackF300 = $F300                   ; word per track: the vibrato's depth in pitch units, set at
                                         ; each note (Spc_TrackStep); Spc_InitTrack sets $1000
!Spc_TrackTremTimer = $F320             ; word per track: the tremolo rate's reload and counter
!Spc_TrackPanLfoTimer = $F340           ; word per track: the pan LFO's reload and counter
!Spc_TrackF360 = $F360                   ; word per track: low byte the pitch slide's steps, high byte
                                         ; a transpose in semitones (Spc_TrackStep); Spc_InitTrack
                                         ; clears the transpose
!Spc_TrackTuning = $F380                ; word per track: the sample's ParamA word (Spc_SetTrackSample),
                                         ; its tuning in Spc_NotePitch
!Spc_TrackF3A0 = $F3A0                   ; word per track: low byte a fine tune added to the tuning
                                         ; (Spc_NotePitch), high byte the note playing
!Spc_TrackF3C0 = $F3C0                   ; word per track: the pitch slide's step, bits 8-23 (bits 0-7
                                         ; in !Spc_TrackF4E0's low byte)
!Spc_TrackPanLfoDelta = $F3E0           ; word per track: the pan LFO's step (its sign flips at each turn)
!Spc_TrackVibRate = $F400               ; word per track: the vibrato's base rate (Spc_LfoRate)
!Spc_TrackVibStep = $F420               ; word per track: the vibrato's step now
!Spc_TrackTremRate = $F440              ; word per track: the tremolo's base rate
!Spc_TrackTremStep = $F460              ; word per track: the tremolo's step now
!Spc_TrackVibPhase = $F480              ; word per track: the vibrato's phase
!Spc_TrackTremPhase = $F4A0             ; word per track: the tremolo's phase
!Spc_TrackF4C0 = $F4C0                   ; word per track: the pan LFO's value (high byte added to the pan
                                         ; in Spc_WriteVoice)
!Spc_TrackF4E0 = $F4E0                   ; word per track: low byte the pitch slide step's bits 0-7,
                                         ; high byte the pitch's fraction
!Spc_TrackVibOffset = $F500             ; word per track: the vibrato's pitch offset now
!Spc_TrackPitch = $F520                 ; word per track: the note's pitch (DSP pitch units), slides
                                         ; included
!Spc_TrackAdsr = $F540                  ; word per track: the sample's ParamB word (ADSR1/ADSR2)
!Spc_LoopIter = $F560                    ; byte per loop slot: the pass through a song track's loop (1, 2,
                                         ; ...; Spc_SeqLoopJump compares it)
!Spc_LoopCount = $F580                   ; byte per loop slot: passes left + 1 (0: endless)
!Spc_LoopReturn = $F5C0                  ; word per loop slot: where the loop starts

; --- Values ---
!Spc_StackTop = $FF                      ; SP at Spc_Start and at each song start (stack $01FF down)
!Spc_ClearEnd = $F0                      ; Spc_Start clears the direct page up to here
!Spc_None = $FF                          ; "no song" in !Spc_CurSong / !Spc_SavedSong
!Spc_QueueBytes = $40                    ; !Spc_CmdQueue: 16 entries x 4 bytes
!Spc_QueueEntry = 4                      ; bytes per !Spc_CmdQueue entry
!Spc_StartEchoDelay = $05                ; the echo delay Spc_Start sets (as Audio_Boot's
                                         ; !Audio_DefaultEchoDelay on the 65816 side)
!Spc_GroupVolStart = $FF                 ; each !Spc_GroupVol volume after Spc_Start (full)
!Spc_TempoAccumStart = $FF               ; !Spc_TempoAccum at a song's start: the first pass steps
!Spc_TrackF220Start = $FF                ; !Spc_TrackF220 at a song track's start
!Spc_LowNibble = $0F                     ; the low nibble
!Spc_InvertBits = $FF                    ; EOR mask: all eight bits inverted
!Spc_StartTempo = $01                    ; !Spc_Tempo at a song's start (a step every 256 passes until
                                         ; the song sets its own, probably)
!Spc_AddMax = $FF                        ; Spc_AddSigned's ceiling
!Spc_DpSave = $0000                      ; the direct page bytes Spc_SaveSong keeps ($00-$7F)
!Spc_SaveFirstPage = $F2                 ; Spc_SaveSong keeps $F200-$F7FF ...
!Spc_SavePage = $F8                      ; ... at $F800-$FDFF, the direct page at $FE00 and page 1 at $FF00
!Spc_SaveDpBytes = $80                   ; direct page bytes kept
!Spc_SavePage1Bytes = $90                ; page 1 bytes kept ($0100-$018F: the FIR steps and per-track
                                         ; bytes)
!Spc_ResumeFadeSteps = $10               ; Spc_RestoreSong fades the song in over 16 steps,
!Spc_ResumeVolume = $10                  ; from volume $10,
!Spc_ResumeFadeDelta = $0EF0             ; by $0E.F0 a step (to $FF)
!Spc_LevelMask = $70                     ; Spc_ReportLevels: a level's 3 bits
!Spc_TempoScale = $14                    ; a tempo byte t gives !Spc_Tempo = t + t x 20 / 256
!Spc_NumVibDepths = $0C                  ; effect tracks: Spc_VibDepthTable entries
!Spc_LfoDepthMask = $3F                  ; an LFO depth byte's size bits
!Spc_LfoMagnitudeMask = $7F              ; the pan LFO's depth without its sign
!Spc_EvenMask = $FE                      ; clears bit 0
!Spc_NoiseClockMask = $1F                ; FLG's noise clock bits
!Spc_PmonNever = $50                     ; effect voices 6 and 4 never get pitch modulation
!Spc_FadeTicks = 7                       ; passes per !Spc_FadeTimer round
!Spc_UnkD8Start = $02                    ; !Spc_UnkD8 after Spc_Start
!Spc_NumShadowRegs = $11                 ; DSP registers Spc_MainLoop writes each pass
!Spc_EvolMax = $7F                       ; a doubled echo volume is capped here
!Spc_FlgKeep = $E0                       ; FLG bits kept when !Spc_NoiseClock is ORed in
!Spc_SongSetA = $10                      ; !Spc_SongHeaderSet for commands $10/$14: the first set
!Spc_SongSetB = $20                      ; ... and for $11/$15: the second
!Spc_NumSongTracks = $10                 ; bytes of track pointers per set (8 words)
!Spc_TrackLast = $0E                     ; X of the song's last track
!Spc_TrackSfxLast = $1E                  ; X of the last effect track
!Spc_VoiceBit7 = $80                     ; voice 7's bit
!Spc_VoiceBit0 = $01                     ; voice 0's bit
!Spc_TrackF240Sfx = $46                  ; !Spc_TrackF240 high byte at an effect's start
!Spc_TrackF200Sfx = $48                  ; !Spc_TrackF200 at an effect's start
!Spc_TrackF300Start = $10                ; !Spc_TrackF300 high byte at a track's start
!Spc_SfxStartSample = $02               ; the sample an effect track starts with (Spc_StartSfx)
!Spc_TrackSfxB = $1A                     ; X of command $19's first track (track 13)
!Spc_VoiceBit5 = $20                     ; voice 5's bit
!Spc_SfxGroupA = $C0                     ; command $18's voices (7, 6)
!Spc_SfxGroupB = $30                     ; command $19's voices (5, 4)
!Spc_SongVolMarks = $7F                  ; the bits command $81 sets in !Spc_UnkD0 (voices 0-6: voice 7
                                         ; is left out)
!Spc_GroupSong = 0                       ; X of a !Spc_GroupVol group: the song
!Spc_GroupSfxA = 2                       ; effect tracks 14-15
!Spc_GroupSfxB = 4                       ; effect tracks 8-13
!Spc_SignBias = $80                      ; EOR that turns a signed byte into an ordered unsigned one
!Spc_NumVoiceVol = $10                   ; bytes of !Spc_VoiceVol
!Spc_StopWait = $02                      ; !Spc_TrackWait of a track pointed at Spc_TrackEndCmd
!Spc_AllBits = $FF                       ; every voice bit
!Spc_XferLowPage = $1E                   ; a transfer to an address below $1E00 (the driver) is
                                         ; refused: its data is taken and dropped (Spc_XferSkip)
!Spc_XferSfxPage = $2F                   ; a transfer to $2Fxx (the effects block) stops effects first
!Spc_XferModeMask = $07                  ; APUIO1's mode bits (Spc_XferModeTable)
!Spc_TestCarry = $FF                     ; CLC / ADC of this: C = 1 iff the byte is nonzero
!Spc_BuiltinDirEntry = $10               ; the directory entry Spc_Start fills itself
; its directory entry ($1E40), ParamA word ($1F20) and ParamB word ($1FA0)
!Spc_BuiltinDir = !AudioAram_Dir+(4*!Spc_BuiltinDirEntry)
!Spc_BuiltinParamA = !AudioAram_ParamA+(2*!Spc_BuiltinDirEntry)
!Spc_BuiltinParamB = !AudioAram_ParamB+(2*!Spc_BuiltinDirEntry)
!Spc_BuiltinParamA0 = $E1                ; the ParamA word's bytes (meaning not traced)
!Spc_BuiltinParamA1 = $00
!Spc_BuiltinParamB0 = $FF                ; the ParamB word's bytes (ADSR1/ADSR2, probably:
!Spc_BuiltinParamB1 = $E0                ; envelope on, fastest attack and decay)
!Spc_SfxEntry = 4                        ; bytes per entry of the effect table at $2F00: two track
                                         ; pointers
!Spc_TempoMax = $FF                      ; a raised tempo is capped here
!Spc_SfxTempo = $81                      ; added to !Spc_SfxTempoAccum each pass: effects step on about
                                         ; half the passes
!Spc_TrackFirstSfx = $10                 ; X of the first effect track (8)
!Spc_TrackSfxStep = $18                  ; X of the first effect track Spc_StepTracks steps (12: voices
                                         ; 4-7 are the only ones effects use)
!Spc_TrackSfxA = $1C                     ; X of track 14, the first of !Spc_SfxPitchAdj's tracks
!Spc_VoiceBit4 = $10                     ; voice 4's bit
!Spc_SeqFirstTie = $A8                   ; sequence bytes: $00-$A7 notes, $A8-$B5 ties, $B6-$C3 rests,
!Spc_SeqFirstRest = $B6                  ; $C4-$FF commands (each with its length: byte % 14)
!Spc_SeqFirstCmd = $C4
!Spc_SeqEndTrack = $EB                   ; the command that ends a track (Spc_PeekNote stops on it)
!Spc_NumDurations = $0E                  ; lengths per note value (Spc_DurationTable)
!Spc_NotesPerOctave = $0C
!Spc_NoteBase = $0A                      ; subtracted from base + index + transpose
!Spc_FirBytes = $10                      ; 8 FIR words
!Spc_VibStageMask = $07                  ; !Spc_TrackF220 high byte: the vibrato's stage
!Spc_TremStageMask = $70                 ; ... and the tremolo's
!Spc_LfoShape80 = $80                    ; depth bytes from here use Spc_LfoRate's second shape
!Spc_LfoShapeC0 = $C0                    ; ... and from here the third
!Spc_PanCentre = $80                     ; the pan with !Spc_Flags87 bit 0 (mono)
!Spc_VolMax = $7F                        ; a tremolo-raised volume that overflows is capped here
!Spc_BuiltinFirst = $03                  ; !Spc_UnkD8 runs from here (2 x the byte index in
!Spc_BuiltinLast = $23                   ; Spc_BuiltinSampleLoop, nibble in bit 0) up to here
!Spc_BuiltinFlip = $70                   ; XORed into the byte (swapped for the low nibble)
!Spc_BrrBlock = $09                      ; bytes per BRR block (its header byte is skipped)

; Commands (!Spc_CmdId; the 65816 side's numbering, Audio_RunCommand)
!SpcCmd_FirstSong = $10                  ; $10-$1F: Spc_CmdTable10 (and Spc_CmdFirstTable10)
!SpcCmd_AfterSong = $20                  ; $20-$7F: nothing (echoed)
!SpcCmd_FirstHigh = $90                  ; $90-$EF: nothing (echoed); $80-$8F, $F0-$FF: Spc_CmdTable80
!SpcCmd_FirstTop = $F0                   ; first of the $F0-$FF range
!SpcCmd_HighIndexMask = $1F              ; $80-$8F -> 0-15, $F0-$FF -> 16-31
!SpcCmd_SongIndexMask = $0F              ; $10-$1F -> 0-15
!SpcCmd_EchoDelayMask = $0F              ; the delay in !Spc_CmdArg2 / !Spc_CmdArg0 (EDL: 0-15)
!SpcCmd_FirstNotQueued = $18            ; $10-$17 are not queued while tracks are stepped
!SpcCmd_Xfer = $FE                       ; take transfers (Spc_XferReceive); not queued either
!SpcCmd_SeqMask = $7F                    ; sequence values count modulo $80 (as !Audio_SeqMask)
!SpcCmd_XferEnd = $E0                    ; APUIO1 of a header, or APUIO0 of a step, that ends a
                                         ; transfer (the 65816's !Audio_SeqHeader)
!SpcCmd_XferBusy = $EE                   ; CPUIO1 while a transfer is taken
!SpcCmd_Control = $FF                    ; command $FF (Spc_CmdControl), also honoured mid-transfer
!SpcCmd_ControlReset = $F0               ; its Arg0 for: back to the IPL ROM (!Audio_ResetKick1)
!SpcCmd_ControlReport = $01              ; its Arg0 for: !Spc_Flags88 bit 7 = Arg1 != 0
!SpcCmd_SameSong = $FF                   ; CPUIO1 after a song command asking for the song already
                                         ; playing (the 65816 then skips the load: Audio_StartSong)

; The song header at !AudioAram_Song (written by the 65816: Audio_SendSongData)
!SpcSong_Origin = 0                      ; word: the ARAM address the track pointers assume
!SpcSong_NoTrack = 2                     ; word: a track pointer equal to this is "no track"
!SpcSong_Tracks = 4                      ; two sets of 8 track pointers ($04-$13, $14-$23)
!SpcSong_Data = $24                      ; the song's data: where !SpcSong_Origin is moved to
