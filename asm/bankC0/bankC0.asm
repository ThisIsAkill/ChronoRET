arch snes.cpu
hirom
incsrc "../hardware.inc"

; ============================================================
; Bank $C0 — Engine Core / Main Game Loop
; File offset 0x000000 (bank $C0 maps directly to ROM start)
;
; CPU state on entry from MainInit ($FD:C000):
;   native mode, M=1 (A 8-bit), X=0 (X/Y 16-bit)
;   DP=$2100, DB=$00, S=$06FF
; ============================================================

; ============================================================
; Label stubs — no bytes emitted; used for JSR/JSL/BRL targets
; ============================================================

; BRL targets (raw hex won't compute relative — must use labels)
org $C00AFF
AltEntry2:      ; alternate cold-start entry 2

org $C01BAB
AltEntry3:      ; alternate cold-start entry 3

org $C01BE6
AltEntry4:      ; alternate cold-start entry 4

org $C02C41
AltEntry1:      ; alternate cold-start entry 1

org $C02E1E
LoadSavePath:   ; entry for mode >= $01FF (load/save/transition)

org $C0EC60
Sub_EC60:       ; called from main frame loop after VBlankHandler

; Unmatched routines called from matched code
org $C00B86
FrameStateInit: ; save/reset per-frame state variables

org $C0B309
Sub_B309:       ; called from PostVBlank inner loop (sprite -> OAM buffer)

; ============================================================
; $C0:0000 — Entry jump table (5 entries, BRA/BRL)
; Entry 0 is warm restart (skip one-time init, enter frame loop).
; Entries 1-4 are alternate cold-start targets.
; ============================================================
org $C00000

EntryTable:
    BRA GameLoop_Main       ; [0] warm restart — skip init, enter frame loop
    BRL $2C3C               ; [1] → AltEntry1  ($2C41)
    BRL $0AF7               ; [2] → AltEntry2  ($0AFF)
    BRL $1BA0               ; [3] → AltEntry3  ($1BAB)
    BRL $1BD8               ; [4] → AltEntry4  ($1BE6)

; ============================================================
; $C0:000E — GameLoop: one-time startup init (from MainInit)
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$2100, DB=$00
; ============================================================
GameLoop:
    SEP #$20                ; M=1: A → 8-bit (safety)
    REP #$10                ; X=0: X/Y → 16-bit

    ; Install RAM-resident interrupt handlers first — they live at
    ; $7E:0500/$7E:0504, which are deliberately NOT cleared below.
    JSR InstallNMI          ; NMI handler: JML $C0:EA63 at $7E:0500
    JSR InstallIRQ          ; IRQ handler: JML $C0:ECCC at $7E:0504

    REP #$20                ; A → 16-bit for TCD
    LDA #$0100
    TCD                     ; DP = $0100 (WRAM variable page)
    SEP #$20                ; A → 8-bit

    JSR InitHW              ; disable hardware (SEI, forced blank, no NMI/DMA)

    ; Clear WRAM block 1: $7E:0000-04FF (1280 bytes, stops before handlers)
    LDX #$0500
    STX $4E                 ; ($014E-$014F) = byte count
    LDX #$0000
    STX $4B                 ; ($014B-$014C) = dest addr
    LDA #$7E
    STA $4D                 ; ($014D) = dest bank
    JSR ClearRAMDMA         ; DMA fill with 0

    ; Clear WRAM block 2: $7E:0700-FFFF (59648 bytes)
    LDX #$E900
    STX $4E
    LDX #$0700
    STX $4B
    LDA #$7E
    STA $4D
    JSR ClearRAMDMA

    ; Clear WRAM block 3: $7F:5080-A0FF (20608 bytes)
    LDX #$5080
    STX $4E
    STX $4B                 ; count == dest addr (both $5080)
    LDA #$7F
    STA $4D
    JSR ClearRAMDMA

    JSL $C70000             ; engine subsystem init
    LDA #$09
    JSL $C28004

GameLoop_Main:
    JSR InitHW              ; forced blank, disable NMI/DMA
    JSR InstallNMI          ; reinstall NMI handler
    JSR InstallIRQ          ; reinstall IRQ handler

    ; Dispatch on game mode index at WRAM $0100 (16-bit)
    LDX $0100
    CPX #$01F0
    BMI GL_ModeOk1
    JML $C20000             ; mode >= $01F0 → alternate handler in bank $C2

GL_ModeOk1:
    CPX #$01FF
    BMI GL_ModeOk2
    LDX #$7C00
    BRL $2DA1               ; → LoadSavePath ($2E1E)

GL_ModeOk2:
    REP #$20
    LDA #$0100
    TCD                     ; DP = $0100
    SEP #$20

    JSR FrameStateInit      ; save/reset per-frame state variables
    JSR FrameUpdate         ; per-frame logic dispatch
    JSR $B192
    JSR $56A6
    JSR $28AA
    JSR $2848               ; input polling

GameLoop_FrameBody:
    LDA.w $00F0
    TSB $51                 ; ($0151) |= [$00F0]
    LDA.w $00F6
    TSB $50                 ; ($0150) |= [$00F6]
    JSR $18D9
    JSR $0C76
    JSR $881E
    JSR $1AAC
    JSL $C01F87
    JSR $21E1
    JSR $274D
    JSR VBlankHandler       ; sync to VBlank (tail-jumps via BRL to PostVBlank)
    JSR $EC60
    BRA GameLoop_FrameBody

; ============================================================
; $C0:00BF — VBlankHandler
; Performs per-VBlank audio + DMA tasks; tail-jumps to PostVBlank.
; Caller's return addr stays on stack so PostVBlank's RTS resumes there.
; ============================================================
VBlankHandler:
    SEP #$10                ; X/Y → 8-bit
    JSR $59D9
    JSR $5A46
    JSL $FDC2C1
    REP #$10                ; X/Y → 16-bit
    JSL $FDFFF7
    SEP #$10
    JSR $A810
    JSR $CA76
    REP #$10
    BRL $B193               ; → PostVBlank ($B271), RTS returns to caller

VBlankHandlerShort:
    SEP #$10
    JSL $FDC2C1
    REP #$10
    JSL $FDFFF7
    RTS

Sub_00EB:
    JSR $881E
    JSR VBlankHandlerShort
    BRL $EB6C               ; → Sub_EC60 ($EC60)

FrameUpdate:
    JSR $092B
    JSR $1B53
    JSR $0960
    JSR $6DCF
    JSR $7084
    JSR $7F7E
    JSR $A33B
    JSR $09DD
    JSR $0A14
    JSR $56D4
    JSL $FDFFFA
    JSL $FDFFF4
    RTS

; ============================================================
; $C0:0B4E — InitHW (22 bytes)
; Disables interrupts, enables forced blank, clears NMI/DMA/HDMA.
; Called with M=1, X=0.
; ============================================================
org $C00B4E
InitHW:
    SEI
    LDA #$00
    PHA
    PLB                     ; DB = $00
    LDA #$80
    STA.w INIDISP             ; $2100: forced blank on, brightness 0
    LDA #$00
    STA.w NMITIMEN            ; $4200: disable NMI, IRQ, joypad auto-read
    STA.w MDMAEN              ; $420B: disable all DMA channels
    STA.w HDMAEN              ; $420C: disable all HDMA channels
    RTS

; ============================================================
; $C0:0B64 — InstallNMI (17 bytes)
; Writes JML $C0:EA63 (5C 63 EA C0) to WRAM $7E:0500.
; Called with M=1 (8-bit A), X=0 (16-bit X).
; ============================================================
InstallNMI:
    LDA #$5C                ; JML opcode
    STA $0500
    LDX #$EA63              ; low 16-bit of $C0:EA63 (little-endian)
    STX $0501
    LDA #$C0                ; bank byte
    STA $0503
    RTS

; ============================================================
; $C0:0B75 — InstallIRQ (17 bytes)
; Writes JML $C0:ECCC (5C CC EC C0) to WRAM $7E:0504.
; ============================================================
InstallIRQ:
    LDA #$5C
    STA $0504
    LDX #$ECCC
    STX $0505
    LDA #$C0
    STA $0507
    RTS

; ============================================================
; $C0:2DF1 — ClearRAMDMA (45 bytes)
; Zeros a WRAM region via DMA channel 7, sourcing from MPYL (always 0
; since M7A=M7B=0). Caller loads $4B/$4C=dest addr, $4D=dest bank,
; $4E/$4F=byte count before calling.
; ============================================================
org $C02DF1
ClearRAMDMA:
    LDA #$00
    STA.w M7A                 ; $211B: clear Mode-7 operand A (write twice per spec)
    STA.w M7A
    STA.w M7B                 ; $211C: clear Mode-7 operand B (write twice)
    STA.w M7B                 ; -> MPYL ($2134) = 0*0 = 0 (DMA source byte)
    LDA #$80
    STA.w DMAP7               ; $4370: B->A direction, byte unit, increment A-bus
    LDA #$34                ; $2100 + $34 = $2134 = MPYL
    STA.w BBAD7               ; $4371: B-bus source = MPYL
    LDX $4B
    STX $4372               ; $4372: A-bus (WRAM) destination address
    LDA $4D
    STA.w A1B7                ; $4374: A-bus destination bank
    LDX $4E
    STX $4375               ; $4375: byte count
    LDA #$80
    STA.w MDMAEN              ; $420B: enable DMA channel 7 (auto-clears when done)
    RTS

; ============================================================
; $C0:B271 — PostVBlank (152 bytes)
; OAM buffer culling routine. Processes sprite descriptors from the frame-
; built table at $7E:0E00, calls Sub_B309 to push each sprite into the OAM
; buffer, then pads any unused slots with $E0 (Y=$E0 places sprites below
; the visible area). Updates write-head pointers in DP so the next frame
; knows where to start writing.
;
; Entered via BRL tail-call from VBlankHandler ($C0:00BF).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y).
; RTS returns to VBlankHandler's caller ($C0:00BA = JSR $EC60).
; ============================================================
org $C0B271
PostVBlank:
    LDX #$0901
    STX $89                 ; ($0189): range-A write head
    LDX #$0000
    STX $8B                 ; ($018B): range-A end (empty)
    LDX #$0907
    STX $81                 ; ($0181): range-B write head
    LDX #$0000
    STX $83                 ; ($0183): range-B end
    LDX #$091A
    STX $85                 ; ($0185): range-C write head
    LDX #$0000
    STX $87                 ; ($0187): range-C end
    LDX #$0710
    STX $DF                 ; ($01DF): OAM lo-buf start, range 3
    LDX #$0770
    STX $DB                 ; ($01DB): OAM lo-buf start, range 1
    LDA #$00
    STA.w WMADDH              ; $2183 = $00: WRAM bank 0
    STA $6E                 ; ($016E) = 0
    LDX #$08A0
    STX $DD                 ; ($01DD): OAM lo-buf start, range 2
    LDY #$007E              ; iterate sprite descriptor table (63 slots * 2)
PV_SpriteLoop:
    LDA $0E00,Y
    BMI PV_NextSprite       ; bit 7: no sprite
    STA $6D                 ; ($016D): descriptor index
    JSR Sub_B309
PV_CheckChain:
    LDX $6D
    LDA $0E81,X             ; chained sprite-B descriptor
    BMI PV_NextSprite
    STA $6D
    JSR Sub_B309
    BRA PV_CheckChain
PV_NextSprite:
    DEY
    DEY
    BPL PV_SpriteLoop
    LDX $DB
    LDA #$E0                ; Y=$E0 hides sprite below NTSC scanlines
PV_FillRange1:
    CPX $7B
    BCS PV_EndRange1
    STA.w $0001,X             ; Y byte of 4-byte OAM entry
    INX
    INX
    INX
    INX
    CPX #$08A0
    BCC PV_FillRange1
PV_EndRange1:
    LDX $DB
    STX $7B                 ; ($017B): range-1 write pointer
    LDX $DD
PV_FillRange2:
    CPX $7D
    BCS PV_EndRange2
    STA.w $0001,X
    INX
    INX
    INX
    INX
    CPX #$0900
    BCC PV_FillRange2
PV_EndRange2:
    LDX $DD
    STX $7D                 ; ($017D): range-2 write pointer
    LDX $DF
PV_FillRange3:
    CPX $7F
    BCS PV_EndRange3
    STA.w $0001,X
    INX
    INX
    INX
    INX
    CPX #$0770
    BCC PV_FillRange3
PV_EndRange3:
    LDX $DF
    STX $7F                 ; ($017F): range-3 write pointer
    RTS
