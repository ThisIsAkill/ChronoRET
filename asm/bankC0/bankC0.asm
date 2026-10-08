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
; $C0:B309 — Spr_AppendToOam (1016 bytes, $B309–$B700)
; (was Sub_B309.) Appends object Obj_Cur's sprite to the OAM shadow.
; Called from Oam_BuildShadow for every object in the draw buckets.
; First Spr_PrepareTiles brings the object's SprTile records up to
; date (C=1: nothing to draw; for size 3 this includes Spr_Place24's
; carry quirk, which can skip a 24-tile object for the frame). Then, by size class (Obj_SprSize bits
; 0-1: 4/8/12/24 tiles = 1/2/3/6 high-table bytes) and by the OAM
; range in Obj_OamFlags bits 2-3:
;   - the object's packed high-table bytes (Obj_OamHiA/B/C) go to
;     the range's high-table pointer (Oam_RangeNHiPtr);
;   - WMADD is aimed at the range's low-table pointer
;     (Oam_RangeNLoPtr), which then advances 4 bytes per tile;
;   - X, Y, Tile, Attr of each SprTile record are written through
;     WMDATA. (Earlier notes called these 4-byte copies a palette
;     copy; they are OAM low-table entries.)
; With DP pointed at $2100, WMADDL/WMDATA are dp operands; the field
; variables are reached with absolute !DP_Field+ addresses.
; On entry: M=1, X=0 (16-bit), DP=$0100, DB=$00 (the high-table
; stores through Eng_PtrBase are bank $00), Obj_Cur = object.
; Exit: M=1, X=0, DP=$0100 (PLD), DB=$00; A, X and Y clobbered.
; ============================================================
org $C0B309
Spr_AppendToOam:
    JSR Spr_PrepareTiles            ; C=1: nothing to draw
    BCC .proceed
    RTS
.proceed:
    LDX.b !Obj_Cur          ; object slot
    LDA.w !Obj_SprSize,X    ; size class in bits 0-1
    AND.b #!ObjSpr_SizeMask
    BEQ .type0
    CMP #$01
    BNE .chk_t2
    BRL .type1
.chk_t2:
    CMP #$02
    BNE .type3_far
    BRL .type2
.type3_far:
    BRL .type3

; ============================================================
; Size 0: 4 tiles, 1 high-table byte, 4 low-table entries
; ============================================================
.type0:
    LDX.b !Obj_Cur
    PHD
    REP #$20                ; A → 16-bit
    LDA.w #!DP_PPU
    TCD                     ; DP = $2100: WMADDL/WMDATA as dp operands
    SEP #$20                ; A → 8-bit
    LDA.w !Obj_OamFlags,X   ; OAM range bits
    AND.b #!ObjOam_RangeMask
    BEQ .t0r1               ; no bits → range 1
    BIT.b #!ObjOam_Range2   ; test bit 2
    BNE .t0r2               ; bit 2 → range 2
    BRA .t0r3               ; bit 3 only → range 3

.t0r1:                      ; range 1 (Oam_Range1HiPtr / Oam_Range1LoPtr)
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range1HiPtr
    STA.w !Eng_PtrBase,X    ; high-table byte → *Oam_Range1HiPtr
    INX
    STX.w !DP_Field+!Oam_Range1HiPtr
    LDX.w !DP_Field+!Oam_Range1LoPtr
    STX.b WMADDL-!DP_PPU    ; WMADDL/WMADDM = low-table pointer
    LDX.w !DP_Field+!Obj_Cur ; object slot (absolute: DP is $2100 here)
    REP #$20
    LDA.w !DP_Field+!Oam_Range1LoPtr
    CLC
    ADC.w #!Spr_Size0Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range1LoPtr
.t0_gfx:                    ; shared low-table copy (size 0)
    LDA.w !Obj_TileRecOfs,X ; object's first SprTile record
    TAX
    SEP #$20
    LDA.b #!Spr_Size0Tiles
    STA.w !DP_Field+!Spr_TileCount ; tiles left to copy
.t0_copy:
    LDA.l SprTile.X,X
    STA.b WMDATA-!DP_PPU    ; X, Y, tile, attr → OAM shadow
    LDA.l SprTile.Y,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Tile,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Attr,X
    STA.b WMDATA-!DP_PPU
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride
    TAX
    SEP #$20
    DEC.w !DP_Field+!Spr_TileCount
    BNE .t0_copy
    PLD
    RTS

.t0r2:                      ; range 2 (Oam_Range2HiPtr / Oam_Range2LoPtr)
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range2HiPtr
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range2HiPtr
    LDX.w !DP_Field+!Oam_Range2LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range2LoPtr
    CLC
    ADC.w #!Spr_Size0Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range2LoPtr
    BRA .t0_gfx

.t0r3:                      ; range 3 (Oam_Range3HiPtr / Oam_Range3LoPtr)
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range3HiPtr
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range3HiPtr
    LDX.w !DP_Field+!Oam_Range3LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range3LoPtr
    CLC
    ADC.w #!Spr_Size0Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range3LoPtr
    BRA .t0_gfx

; ============================================================
; Size 1: 8 tiles, 2 high-table bytes (via PHA/PLA), 8 entries
; ============================================================
.type1:
    LDX.b !Obj_Cur
    PHD
    REP #$20
    LDA.w #!DP_PPU
    TCD
    SEP #$20
    LDA.w !Obj_OamFlags,X
    AND.b #!ObjOam_RangeMask
    BEQ .t1r1
    BIT.b #!ObjOam_Range2
    BNE .t1r2_tramp         ; bit 2 → range 2 (too far for BNE)
    BRL .t1r3               ; bit 3 only → range 3
.t1r2_tramp:
    BRL .t1r2

.t1r1:                      ; range 1 (Oam_Range1HiPtr / Oam_Range1LoPtr)
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range1HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range1HiPtr
    LDX.w !DP_Field+!Oam_Range1LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range1LoPtr
    CLC
    ADC.w #!Spr_Size1Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range1LoPtr
.t1_gfx:                    ; shared gfx+OAM entry copy loop (type 1)
    LDA.w !Obj_TileRecOfs,X
    TAX
    SEP #$20
    LDA.b #!Spr_Size1Tiles
    STA.w !DP_Field+!Spr_TileCount
.t1_copy:
    LDA.l SprTile.X,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Y,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Tile,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Attr,X
    STA.b WMDATA-!DP_PPU
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride
    TAX
    SEP #$20
    DEC.w !DP_Field+!Spr_TileCount
    BNE .t1_copy
    PLD
    RTS

.t1r3:                      ; range 3 (Oam_Range3HiPtr / Oam_Range3LoPtr)
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range3HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range3HiPtr
    LDX.w !DP_Field+!Oam_Range3LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range3LoPtr
    CLC
    ADC.w #!Spr_Size1Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range3LoPtr
    BRA .t1_gfx

.t1r2:                      ; range 2 (Oam_Range2HiPtr / Oam_Range2LoPtr)
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range2HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range2HiPtr
    LDX.w !DP_Field+!Oam_Range2LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range2LoPtr
    CLC
    ADC.w #!Spr_Size1Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range2LoPtr
    BRL .t1_gfx

; ============================================================
; Size 2: 12 tiles, 3 high-table bytes (via PHA/PLA), 12 entries
; ============================================================
.type2:
    LDX.b !Obj_Cur
    PHD
    REP #$20
    LDA.w #!DP_PPU
    TCD
    SEP #$20
    LDA.w !Obj_OamFlags,X
    AND.b #!ObjOam_RangeMask
    BEQ .t2r1
    BIT.b #!ObjOam_Range2
    BNE .t2r2_tramp
    BRL .t2r3
.t2r2_tramp:
    BRL .t2r2

.t2r1:                      ; range 1 (Oam_Range1HiPtr / Oam_Range1LoPtr)
    LDA.l !Obj_OamHiB,X
    PHA
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range1HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range1HiPtr
    LDX.w !DP_Field+!Oam_Range1LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range1LoPtr
    CLC
    ADC.w #!Spr_Size2Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range1LoPtr
.t2_gfx:                    ; shared gfx+OAM entry copy loop (type 2)
    LDA.w !Obj_TileRecOfs,X
    TAX
    SEP #$20
    LDA.b #!Spr_Size2Tiles
    STA.w !DP_Field+!Spr_TileCount
.t2_copy:
    LDA.l SprTile.X,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Y,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Tile,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Attr,X
    STA.b WMDATA-!DP_PPU
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride
    TAX
    SEP #$20
    DEC.w !DP_Field+!Spr_TileCount
    BNE .t2_copy
    PLD
    RTS

.t2r3:                      ; range 3 (Oam_Range3HiPtr / Oam_Range3LoPtr)
    LDA.l !Obj_OamHiB,X
    PHA
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range3HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range3HiPtr
    LDX.w !DP_Field+!Oam_Range3LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range3LoPtr
    CLC
    ADC.w #!Spr_Size2Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range3LoPtr
    BRA .t2_gfx

.t2r2:                      ; range 2 (Oam_Range2HiPtr / Oam_Range2LoPtr)
    LDA.l !Obj_OamHiB,X
    PHA
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range2HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range2HiPtr
    LDX.w !DP_Field+!Oam_Range2LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range2LoPtr
    CLC
    ADC.w #!Spr_Size2Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range2LoPtr
    BRL .t2_gfx

; ============================================================
; Size 3: 24 tiles, 6 high-table bytes (Obj_OamHiA/B/C via PHA/PLA), 24 entries
; ============================================================
.type3:
    LDX.b !Obj_Cur
    PHD
    REP #$20
    LDA.w #!DP_PPU
    TCD
    SEP #$20
    LDA.w !Obj_OamFlags,X
    AND.b #!ObjOam_RangeMask
    BEQ .t3r1
    BIT.b #!ObjOam_Range2
    BNE .t3r2_tramp
    BRL .t3r3
.t3r2_tramp:
    BRL .t3r2

.t3r1:                      ; range 1 (Oam_Range1HiPtr / Oam_Range1LoPtr)
    LDA.l !Obj_OamHiC+1,X
    PHA
    LDA.l !Obj_OamHiC,X
    PHA
    LDA.l !Obj_OamHiB+1,X
    PHA
    LDA.l !Obj_OamHiB,X
    PHA
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range1HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range1HiPtr
    LDX.w !DP_Field+!Oam_Range1LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range1LoPtr
    CLC
    ADC.w #!Spr_Size3Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range1LoPtr
.t3_gfx:                    ; shared low-table copy (size 3)
    LDA.w !Obj_TileRecOfs,X
    TAX
    SEP #$20
    LDA.b #!Spr_Size3Tiles
    STA.w !DP_Field+!Spr_TileCount
.t3_copy:
    LDA.l SprTile.X,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Y,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Tile,X
    STA.b WMDATA-!DP_PPU
    LDA.l SprTile.Attr,X
    STA.b WMDATA-!DP_PPU
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride
    TAX
    SEP #$20
    DEC.w !DP_Field+!Spr_TileCount
    BNE .t3_copy
    PLD
    RTS

.t3r3:                      ; range 3 (Oam_Range3HiPtr / Oam_Range3LoPtr)
    LDA.l !Obj_OamHiC+1,X
    PHA
    LDA.l !Obj_OamHiC,X
    PHA
    LDA.l !Obj_OamHiB+1,X
    PHA
    LDA.l !Obj_OamHiB,X
    PHA
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range3HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range3HiPtr
    LDX.w !DP_Field+!Oam_Range3LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range3LoPtr
    CLC
    ADC.w #!Spr_Size3Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range3LoPtr
    BRL .t3_gfx

.t3r2:                      ; range 2 (Oam_Range2HiPtr / Oam_Range2LoPtr)
    LDA.l !Obj_OamHiC+1,X
    PHA
    LDA.l !Obj_OamHiC,X
    PHA
    LDA.l !Obj_OamHiB+1,X
    PHA
    LDA.l !Obj_OamHiB,X
    PHA
    LDA.l !Obj_OamHiA+1,X
    PHA
    LDA.l !Obj_OamHiA,X
    LDX.w !DP_Field+!Oam_Range2HiPtr
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    PLA
    STA.w !Eng_PtrBase,X
    INX
    STX.w !DP_Field+!Oam_Range2HiPtr
    LDX.w !DP_Field+!Oam_Range2LoPtr
    STX.b WMADDL-!DP_PPU
    LDX.w !DP_Field+!Obj_Cur
    REP #$20
    LDA.w !DP_Field+!Oam_Range2LoPtr
    CLC
    ADC.w #!Spr_Size3Tiles*!Oam_EntrySize
    STA.w !DP_Field+!Oam_Range2LoPtr
    BRL .t3_gfx

; ============================================================
; $C0:B701 — Spr_PrepareTiles (135 bytes, $B701–$B787)
; (was Sub_B701.) Brings object Obj_Cur's SprTile records up to date
; before Spr_AppendToOam copies them. Returns C=1 when there is
; nothing to draw. By size class (Obj_SprSize) and Obj_State:
;   0                        → C=1.
;   1..$7F, below threshold  → C=1 (threshold: 2 for size 1, 3 for
;                              size 2, none for size 0).
;   1..$7F at/above it, or
;   $81..$FF at/above it     → Spr_LoadN (copy from SprTileSrc and
;                              place), run the matching SprBuf_Free1/2/3,
;                              set Obj_State = $80, C=0.
;   $80, or $81.. below it   → Spr_PlaceN (re-place the existing
;                              records at the object's position), C=0.
; Size 3 always goes to Spr_Place24 (BRL), whose carry is returned: on
; its Spr_BaseYHi != 0 path that is the carry of the last tile's Y add,
; so C=1 there makes Spr_AppendToOam skip the whole 24-tile object for
; the frame (kept as in the original).
; On entry: M=1, X/Y 16-bit, DP=$0100, DB=$00, Obj_Cur = object.
; Exit: M=1, X/Y 16-bit, DB unchanged; C as above.
; ============================================================
org $C0B701
Spr_PrepareTiles:
    LDX.b !Obj_Cur
    LDA.w !Obj_SprSize,X
    AND.b #!ObjSpr_SizeMask
    BEQ .t0
    CMP #$01
    BNE .chk2
    BRA .t1
.chk2:
    CMP #$02
    BNE .t3plus
    BRA .t2

.t0:
    LDA.w !Obj_State,X
    BNE .t0_nz
    SEC
    RTS
.t0_nz:
    BMI .t0_neg
.t0_init:
    JSR Spr_Load4
    JSR SprBuf_Free1
    LDX.b !Obj_Cur
    LDA.b #!ObjState_Ready
    STA.w !Obj_State,X
    CLC
    RTS
.t0_neg:
    AND.b #!ObjState_CountMask
    BNE .t0_init
    JSR Spr_Place4
    CLC
    RTS

.t1:
    LDA.w !Obj_State,X
    BNE .t1_nz
.t1_abort:
    SEC
    RTS
.t1_nz:
    BMI .t1_neg
    CMP #$02
    BCC .t1_abort
.t1_init:
    JSR Spr_Load8
    JSR SprBuf_Free2
    LDX.b !Obj_Cur
    LDA.b #!ObjState_Ready
    STA.w !Obj_State,X
    CLC
    RTS
.t1_neg:
    AND.b #!ObjState_CountMask
    CMP #$02
    BCS .t1_init
    JSR Spr_Place8
    CLC
    RTS

.t2:
    LDA.w !Obj_State,X
    BNE .t2_nz
.t2_abort:
    SEC
    RTS
.t2_nz:
    BMI .t2_neg
    CMP #$03
    BCC .t2_abort
.t2_init:
    JSR Spr_Load12
    JSR SprBuf_Free3
    LDX.b !Obj_Cur
    LDA.b #!ObjState_Ready
    STA.w !Obj_State,X
    CLC
    RTS
.t2_neg:
    AND.b #!ObjState_CountMask
    CMP #$03
    BCS .t2_init
    JSR Spr_Place12
    CLC
    RTS

.t3plus:
    BRL Spr_Place24         ; size 3: always re-placed

; ============================================================
; $C0:B788 — Spr_Place4 (322 bytes, $B788–$B8C9)
; (was Sub_B788.) Re-places a 4-tile (size 0) object: with DB=$7F,
; each SprTile record's X = Spr_BaseX + OfsX (bit 8 packed into
; Obj_OamHiA with the large-size bits) and Y = Spr_BaseY + OfsY,
; clamped to Oam_HiddenY according to the sign of the base and the
; offset (three clamp variants on Spr_BaseYHi / Spr_BaseY bit 7).
; Quirk: the Spr_BaseYHi != 0 variant also clamps SprTile[4], the
; record after this 4-tile object's last one, from that record's own
; OfsY. Kept as in the original; it looks harmless, since each object's
; records are placed again before Spr_AppendToOam copies them (inferred).
; Called from Spr_PrepareTiles.
; On entry: M=1, X/Y 16-bit, X = Obj_Cur, DP=$0100 (Spr_* scratch).
; Exit: M=1, X/Y 16-bit, DB restored (PLB).
; ============================================================
org $C0B788
Spr_Place4:
    PHB
    LDA.b #!Bank7F
    PHA
    PLB                     ; DB = $7F: SprTile records by abs,X
    REP #$20                ; M→0 (16-bit A)
    LDA.l !Obj_ScreenY,X    ; long: DB=$7F does not reach bank $00
    AND.w #!Spr_YMask9
    STA.b !Spr_BaseY        ; 16-bit: Y bits 0-7 and bit 8
    LDA.l !Obj_ScreenX,X    ; base X coordinate
    STA.b !Spr_BaseX        ; 16-bit
    STZ.b !Spr_HiBits
    LDA.l !Obj_TileRecOfs,X ; sprite first tile record (16-bit)
    STA.b !Spr_FirstRec     ; 16-bit
    CLC
    ADC.w #!SprTile_Stride*3 ; last of the 4 records first
.x_loop:
    TAX
    LDA.w SprTile.OfsX,X    ; this record's X offset
    CLC
    ADC.b !Spr_BaseX
    SEP #$20                ; M→1 (8-bit A)
    STA.w SprTile.X,X       ; write X position low byte
    XBA                     ; get high byte (bit 8 of sum = X overflow bit)
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp     ; pack X bit 8 of this tile
    CPX.b !Spr_FirstRec     ; reached base first tile record?
    BEQ .x_done
    STA.b !Spr_HiBits
    REP #$20                ; M→0
    TXA
    SEC
    SBC.w #!SprTile_Stride  ; step back one tile
    BRA .x_loop
.x_done:
    ORA.b #!Oam_HiLarge4    ; set high attribute bits
    LDX.b !Obj_Cur          ; object slot
    STA.w !Obj_OamHiA,X     ; packed high-table byte
    LDX.b !Spr_FirstRec     ; back to the first record
    LDA.b !Spr_BaseYHi      ; check bit 8 of position
    BEQ .y_hi_clear         ; = 0: dispatch on Spr_BaseY bit 7
    ; Spr_BaseYHi != 0: keep a Y only if the add carries and lands on
    ; $E0-$FF, else Oam_HiddenY. Five records: see the quirk above.
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp1
    CMP.b #!Oam_HiddenY
    BCS .hi_store1
.hi_clamp1:
    LDA.b #!Oam_HiddenY
.hi_store1:
    STA.w SprTile.Y,X
    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp2
    CMP.b #!Oam_HiddenY
    BCS .hi_store2
.hi_clamp2:
    LDA.b #!Oam_HiddenY
.hi_store2:
    STA.w SprTile[1].Y,X
    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp3
    CMP.b #!Oam_HiddenY
    BCS .hi_store3
.hi_clamp3:
    LDA.b #!Oam_HiddenY
.hi_store3:
    STA.w SprTile[2].Y,X
    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp4
    CMP.b #!Oam_HiddenY
    BCS .hi_store4
.hi_clamp4:
    LDA.b #!Oam_HiddenY
.hi_store4:
    STA.w SprTile[3].Y,X
    LDA.w SprTile[4].OfsY,X ; 5th record (quirk)
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp5
    CMP.b #!Oam_HiddenY
    BCS .hi_store5
.hi_clamp5:
    LDA.b #!Oam_HiddenY
.hi_store5:
    STA.w SprTile[4].Y,X
    SEP #$20
    PLB
    RTS
.y_hi_clear:
    LDA.b !Spr_BaseY
    BPL .y_pos              ; Spr_BaseY bit 7 clear
    ; Spr_BaseY bit 7 set: keep a Y unless the add carries and lands on
    ; $E0-$FF, which becomes Oam_HiddenY
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .neg_store1
    CMP.b #!Oam_HiddenY
    BCC .neg_store1
    LDA.b #!Oam_HiddenY
.neg_store1:
    STA.w SprTile.Y,X
    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .neg_store2
    CMP.b #!Oam_HiddenY
    BCC .neg_store2
    LDA.b #!Oam_HiddenY
.neg_store2:
    STA.w SprTile[1].Y,X
    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .neg_store3
    CMP.b #!Oam_HiddenY
    BCC .neg_store3
    LDA.b #!Oam_HiddenY
.neg_store3:
    STA.w SprTile[2].Y,X
    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .neg_store4
    CMP.b #!Oam_HiddenY
    BCC .neg_store4
    LDA.b #!Oam_HiddenY
.neg_store4:
    STA.w SprTile[3].Y,X
    SEP #$20
    PLB
    RTS
.y_pos:
    ; Spr_BaseY bit 7 clear: keep a Y of $00-$7F or $E0-$FF; $80-$DF
    ; becomes Oam_HiddenY
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store1
    CMP.b #!Oam_HiddenY
    BCS .pos_store1
    LDA.b #!Oam_HiddenY
.pos_store1:
    STA.w SprTile.Y,X
    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store2
    CMP.b #!Oam_HiddenY
    BCS .pos_store2
    LDA.b #!Oam_HiddenY
.pos_store2:
    STA.w SprTile[1].Y,X
    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store3
    CMP.b #!Oam_HiddenY
    BCS .pos_store3
    LDA.b #!Oam_HiddenY
.pos_store3:
    STA.w SprTile[2].Y,X
    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store4
    CMP.b #!Oam_HiddenY
    BCS .pos_store4
    LDA.b #!Oam_HiddenY
.pos_store4:
    STA.w SprTile[3].Y,X
    SEP #$20
    PLB
    RTS

; ============================================================
; $C0:C6E7 — Spr_PackHiBits4 (83 bytes, $C6E7–$C739)
; (was Sub_C6E7.) For the 4 SprTile records starting at X: X =
; Spr_BaseX + OfsX, and returns in A the OAM high-table byte for
; them (X bit 8 of each, large-size bits set). Called 6 times by
; Spr_Place24, once per group of 4 records.
; On entry: M=0, X/Y 16-bit, X = the group's first SprTile record,
; DP=$0100 (Spr_* scratch), DB=$7F.
; Exit: M=1, X unchanged, A = the packed high-table byte.
; ============================================================
org $C0C6E7
Spr_PackHiBits4:
    LDA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX        ; add base X (16-bit)
    SEP #$20                ; M→1
    STA.w SprTile.X,X       ; store tile 0 X low byte
    XBA
    AND #$01
    STA.b !Spr_HiBits       ; tile 0 X overflow bit

    REP #$20                ; M→0
    LDA.w SprTile[1].OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile[1].X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp     ; tile 1 X overflow bit

    REP #$20
    LDA.w SprTile[2].OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile[2].X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp2    ; tile 2 X overflow bit

    REP #$20
    LDA.w SprTile[3].OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile[3].X,X
    XBA
    AND #$01                ; tile 3 X overflow bit in A[0]
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp2    ; pack: (bit3<<2) | bit2
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp     ; pack: (bit3<<4) | (bit2<<2) | bit1
    ASL A
    ASL A
    ORA.b !Spr_HiBits       ; pack: (bit3<<6) | (bit2<<4) | (bit1<<2) | bit0
    ORA.b #!Oam_HiLarge4    ; set size bits (SNES OAM: bit pairs = [xhi, size])
    RTS

; ============================================================
; $C0:C73A — Spr_Place24 (592 bytes, $C73A–$C989)
; (was Sub_C73A.) Re-places a 24-tile (size 3) object: six
; Spr_PackHiBits4 groups fill Obj_OamHiA/B/C, then all 24 Y
; positions are rebuilt from Spr_BaseY + OfsY with the clamp variant
; chosen by Spr_BaseYHi / Spr_BaseY bit 7. Reached by BRL from
; Spr_PrepareTiles for size 3, so its carry is Spr_PrepareTiles' result.
; On entry: M=1, X/Y 16-bit, DP=$0100 (Spr_* scratch), DB=$00.
; Exit: M=1, X/Y 16-bit, DB restored (PLB). Carry: C=0 from the two
; Spr_BaseYHi = 0 loops (their last ADC is the record step), but on the
; Spr_BaseYHi != 0 path the carry of the last tile's Y add is left in
; C. C=1 there makes Spr_AppendToOam skip the object for the frame.
; Kept as in the original.
; ============================================================
org $C0C73A
Spr_Place24:
    PHB
    LDA.b #!Bank7F
    PHA
    PLB                         ; DB=$7F

    REP #$20                    ; M→0
    LDX.b !Obj_Cur              ; object slot (16-bit X)
    LDA.l !Obj_ScreenY,X        ; 9-bit Y position value
    AND.w #!Spr_YMask9
    STA.b !Spr_BaseY            ; Spr_BaseY=lo byte, Spr_BaseYHi=hi bit (bit 8)
    LDA.l !Obj_ScreenX,X
    STA.b !Spr_BaseX
    LDA.l !Obj_TileRecOfs,X     ; first tile record
    TAX

    ; X positions and high-table bytes, 4 records per Spr_PackHiBits4
    ; call; X steps 4 records after each one
    JSR Spr_PackHiBits4                ; records 0-3
    STX.b !Spr_FirstRec
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA,X
    LDX.b !Spr_FirstRec
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride*4
    TAX
    JSR Spr_PackHiBits4                ; records 4-7
    STX.b !Spr_FirstRec
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA+1,X
    LDX.b !Spr_FirstRec
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride*4
    TAX
    JSR Spr_PackHiBits4                ; records 8-11
    STX.b !Spr_FirstRec
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiB,X
    LDX.b !Spr_FirstRec
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride*4
    TAX
    JSR Spr_PackHiBits4                ; records 12-15
    STX.b !Spr_FirstRec
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiB+1,X
    LDX.b !Spr_FirstRec
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride*4
    TAX
    JSR Spr_PackHiBits4                ; records 16-19
    STX.b !Spr_FirstRec
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiC,X
    LDX.b !Spr_FirstRec
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride*4
    TAX
    JSR Spr_PackHiBits4                ; records 20-23
    STX.b !Spr_FirstRec
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiC+1,X
    LDX.b !Obj_Cur              ; reload the object slot
    REP #$20
    LDA.l !Obj_TileRecOfs,X     ; first tile record again for the Y pass
    TAX
    SEP #$20                    ; M→1

    ; Y positions: three variants on Spr_BaseYHi / Spr_BaseY bit 7
    LDA.b !Spr_BaseYHi
    BEQ .y_hi_clear
    BRL .y_hi_set
.y_hi_clear:
    LDA.b !Spr_BaseY
    BMI .y_neg                  ; bit 7 set: no clamp
    BRL .y_pos                  ; bit 7 clear: clamp $80-$DF

    ; Spr_BaseYHi = 0, Spr_BaseY bit 7 set: plain add, no clamp
.y_neg:
    LDA.b #!Spr_Size3Tiles
    STA.b !Spr_TileCount        ; counter = 24
.neg_loop:
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile.Y,X           ; store Y (no clamp; overflow wraps)
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride
    TAX
    SEP #$20
    DEC.b !Spr_TileCount
    BNE .neg_loop
    PLB
    RTS

    ; Spr_BaseYHi = 0, Spr_BaseY bit 7 clear: $80-$DF → Oam_HiddenY
.y_pos:
    LDA.b #!Spr_Size3Tiles
    STA.b !Spr_TileCount
.pos_loop:
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store       ; 0–$7F: store as-is
    CMP.b #!Oam_HiddenY
    BCS .pos_store       ; $E0–$FF: already off-screen, store as-is
    LDA.b #!Oam_HiddenY         ; $80–$DF: clamp to $E0
.pos_store:
    STA.w SprTile.Y,X
    REP #$20
    TXA
    CLC
    ADC.w #!SprTile_Stride
    TAX
    SEP #$20
    DEC.b !Spr_TileCount
    BNE .pos_loop
    PLB
    RTS

    ; Spr_BaseYHi != 0, unrolled: only a result of $00-$7F without a
    ; carry is kept, anything else → Oam_HiddenY. The last ADC's carry
    ; survives to the RTS (see the header).
.y_hi_set:
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp00
    BPL .hi_store00
.hi_clamp00: LDA.b #!Oam_HiddenY
.hi_store00: STA.w SprTile.Y,X
    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp01
    BPL .hi_store01
.hi_clamp01: LDA.b #!Oam_HiddenY
.hi_store01: STA.w SprTile[1].Y,X
    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp02
    BPL .hi_store02
.hi_clamp02: LDA.b #!Oam_HiddenY
.hi_store02: STA.w SprTile[2].Y,X
    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp03
    BPL .hi_store03
.hi_clamp03: LDA.b #!Oam_HiddenY
.hi_store03: STA.w SprTile[3].Y,X
    LDA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp04
    BPL .hi_store04
.hi_clamp04: LDA.b #!Oam_HiddenY
.hi_store04: STA.w SprTile[4].Y,X
    LDA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp05
    BPL .hi_store05
.hi_clamp05: LDA.b #!Oam_HiddenY
.hi_store05: STA.w SprTile[5].Y,X
    LDA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp06
    BPL .hi_store06
.hi_clamp06: LDA.b #!Oam_HiddenY
.hi_store06: STA.w SprTile[6].Y,X
    LDA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp07
    BPL .hi_store07
.hi_clamp07: LDA.b #!Oam_HiddenY
.hi_store07: STA.w SprTile[7].Y,X
    LDA.w SprTile[8].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp08
    BPL .hi_store08
.hi_clamp08: LDA.b #!Oam_HiddenY
.hi_store08: STA.w SprTile[8].Y,X
    LDA.w SprTile[9].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp09
    BPL .hi_store09
.hi_clamp09: LDA.b #!Oam_HiddenY
.hi_store09: STA.w SprTile[9].Y,X
    LDA.w SprTile[10].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp10
    BPL .hi_store10
.hi_clamp10: LDA.b #!Oam_HiddenY
.hi_store10: STA.w SprTile[10].Y,X
    LDA.w SprTile[11].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp11
    BPL .hi_store11
.hi_clamp11: LDA.b #!Oam_HiddenY
.hi_store11: STA.w SprTile[11].Y,X
    LDA.w SprTile[12].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp12
    BPL .hi_store12
.hi_clamp12: LDA.b #!Oam_HiddenY
.hi_store12: STA.w SprTile[12].Y,X
    LDA.w SprTile[13].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp13
    BPL .hi_store13
.hi_clamp13: LDA.b #!Oam_HiddenY
.hi_store13: STA.w SprTile[13].Y,X
    LDA.w SprTile[14].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp14
    BPL .hi_store14
.hi_clamp14: LDA.b #!Oam_HiddenY
.hi_store14: STA.w SprTile[14].Y,X
    LDA.w SprTile[15].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp15
    BPL .hi_store15
.hi_clamp15: LDA.b #!Oam_HiddenY
.hi_store15: STA.w SprTile[15].Y,X
    LDA.w SprTile[16].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp16
    BPL .hi_store16
.hi_clamp16: LDA.b #!Oam_HiddenY
.hi_store16: STA.w SprTile[16].Y,X
    LDA.w SprTile[17].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp17
    BPL .hi_store17
.hi_clamp17: LDA.b #!Oam_HiddenY
.hi_store17: STA.w SprTile[17].Y,X
    LDA.w SprTile[18].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp18
    BPL .hi_store18
.hi_clamp18: LDA.b #!Oam_HiddenY
.hi_store18: STA.w SprTile[18].Y,X
    LDA.w SprTile[19].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp19
    BPL .hi_store19
.hi_clamp19: LDA.b #!Oam_HiddenY
.hi_store19: STA.w SprTile[19].Y,X
    LDA.w SprTile[20].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp20
    BPL .hi_store20
.hi_clamp20: LDA.b #!Oam_HiddenY
.hi_store20: STA.w SprTile[20].Y,X
    LDA.w SprTile[21].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp21
    BPL .hi_store21
.hi_clamp21: LDA.b #!Oam_HiddenY
.hi_store21: STA.w SprTile[21].Y,X
    LDA.w SprTile[22].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp22
    BPL .hi_store22
.hi_clamp22: LDA.b #!Oam_HiddenY
.hi_store22: STA.w SprTile[22].Y,X
    LDA.w SprTile[23].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp23
    BPL .hi_store23
.hi_clamp23: LDA.b #!Oam_HiddenY
.hi_store23: STA.w SprTile[23].Y,X
    PLB
    RTS

; ============================================================
; $C0:C98A — Obj_AnimTickAndQueue (236 bytes, $C98A–$CA75)
; Per-object animation tick, called for object Obj_Cur from the
; object loop ($C0:A832, $C0:A878). Counts Obj_AnimTimer down; when it
; runs out the object moves to its next frame:
;   - it is put in the frame-build queue (ObjQ_Head / ObjQ_Tail, linked
;     through Obj_QueueNext) unless already there: at the head when
;     Obj_Unk1100 is 0 (or 1/2 with ObjQ_Unk78 = 2), else at the tail;
;   - Obj_AnimColumn advances, and the new frame's duration is read
;     from bank $E4 at Obj_AnimTimeTbl + row*4 + column. A zero
;     duration ends the row: the row's first entry becomes the timer
;     and the column restarts (mode 2 counts ObjX_AnimLoops first).
; Earlier notes described the queue as primary/secondary "focus" slots.
; Entry: M=1, X/Y 8-bit, Obj_Cur = object.
; ============================================================
org $C0C98A
Obj_AnimTickAndQueue:
    LDX.b !Obj_Cur        ; current entity slot index
    LDA.w !Obj_AnimTimer,X ; per-slot animation timer
    BEQ .tick_done        ; already zero → execute now
    DEC.w !Obj_AnimTimer,X ; count down
    BEQ .tick_done        ; just expired → execute
.rts:
    RTS                   ; $C996 — timer still running, early exit
.tick_done:               ; $C997
    LDA.w !Obj_Unk1100,X  ; sprite state flags
    BEQ .no_type          ; 0 → slot has no type/owner
    BMI .rts              ; bit7 set → inactive slot, return
    CMP #$01
    BEQ .type_1_or_2      ; type 1
    CMP #$02
    BEQ .type_1_or_2      ; type 2
    CPX.b !ObjQ_Tail      ; is this slot already the queue tail?
    BEQ .rts              ; yes → no change needed
    LDA.b !ObjQ_Tail      ; load queue tail slot index
    BMI .promote_sec      ; negative ($80) = no secondary → promote
    LDA.w !Obj_QueueNext,X ; Obj_QueueNext of current slot
    BPL .rts              ; non-negative → slot occupied, skip
.promote_sec:             ; $C9B3
    TXA                   ; A = current slot index
    LDX.b !ObjQ_Tail      ; X = current queue tail slot
    CPX.b #!ObjQ_Empty    ; secondary empty ($80)?
    BPL .set_both2        ; yes → A already holds current slot, set both
    STA.w !Obj_QueueNext,X ; link old secondary's shadow → current slot
    STA.b !ObjQ_Tail      ; queue tail = current slot (A)
    TAX                   ; X = current slot
    INC.w !Obj_AnimColumn,X ; advance animation column counter
    BRA .do_anim
.set_both1:               ; $C9C5 — from .no_type when primary is negative
    TXA                   ; A = current slot (X = current, A was primary)
.set_both2:               ; $C9C6 — from .promote_sec / .promote_sec2 when slot empty
    STA.b !ObjQ_Tail      ; queue tail = current slot
    STA.b !ObjQ_Head      ; queue head = current slot
    TAX                   ; X = current slot
    INC.w !Obj_AnimColumn,X
    BRA .do_anim
.no_type:                 ; $C9D0
    CPX.b !ObjQ_Head      ; is this slot already the queue head?
    BEQ .rts              ; yes → no change
    LDA.b !ObjQ_Head      ; load queue head slot index
    BMI .set_both1        ; negative → no primary, set this as both
    STA.w !Obj_QueueNext,X ; link primary into current's shadow
    STX.b !ObjQ_Head      ; queue head = current slot
    INC.w !Obj_AnimColumn,X
    BRA .do_anim
.type_1_or_2:             ; $C9E2
    LDA.b !ObjQ_Unk78     ; tertiary mode flag
    CMP #$02
    BNE .type_sec         ; not 2 → check secondary
    STZ.b !ObjQ_Unk78     ; reset tertiary mode
    BRA .no_type          ; re-run as type-0 path
.type_sec:                ; $C9EC
    CPX.b !ObjQ_Tail      ; is this slot already the queue tail?
    BEQ .rts              ; yes → no change
    LDA.b !ObjQ_Tail
    BMI .promote_sec2     ; negative → no secondary, promote
    LDA.w !Obj_QueueNext,X ; Obj_QueueNext
    BPL .rts              ; occupied → skip
.promote_sec2:            ; $C9F9
    TXA
    LDX.b !ObjQ_Tail
    CPX.b #!ObjQ_Empty
    BPL .set_both2        ; empty secondary → set both (skip TXA)
    STA.w !Obj_QueueNext,X
    STA.b !ObjQ_Tail
    TAX
    INC.w !Obj_AnimColumn,X
.do_anim:                 ; $CA09 — fall-through from .promote_sec2 and BRAs above
    LDX.b !Obj_Cur        ; reload entity slot
    LDA.w !Obj_AnimMode,X ; animation mode byte
    BEQ .use_primary_row  ; mode 0 → use primary row
    DEC                   ; mode - 1
    BEQ .use_primary_row  ; mode 1 → use primary row
    LDA.w !Obj_AnimRowAlt,X ; mode >= 2 → use secondary row byte
    BRA .got_row
.use_primary_row:         ; $CA18
    LDA.w !Obj_AnimRow,X  ; primary animation row byte
.got_row:                 ; $CA1B
    REP #$20              ; A=16-bit
    AND.w #!Eng_LowByteMask ; zero high byte
    ASL                   ; row × 2
    ASL                   ; row × 4 (frame row offset)
    CLC
    ADC.w !Obj_AnimTimeTbl,X ; + slot base pointer → frame row address
    STA.b !Anim_RowAddr   ; save frame row address (16-bit)
    LDA.w !Obj_AnimColumn,X ; animation column counter (16-bit)
    AND.w #!Eng_LowByteMask ; zero high byte
    ADC.b !Anim_RowAddr   ; + frame row = frame-entry address (carry from ADC above)
    REP #$10              ; X=16-bit
    TAX                   ; X = 16-bit frame-entry address
    SEP #$20              ; A=8-bit
    LDA.l !AnimRom,X      ; read frame-step byte from bank $E4 sprite table
    BNE .got_frame        ; nonzero → use as timer
    LDX.b !Anim_RowAddr   ; X = frame row base address (16-bit)
    LDA.l !AnimRom,X      ; read row-base frame value from bank $E4
    SEP #$10              ; X=8-bit
    LDX.b !Obj_Cur        ; reload entity slot
    STA.w !Obj_AnimTimer,X ; store row-base byte as new timer
    LDA.w !Obj_AnimMode,X ; check animation mode
    CMP #$02
    BNE .mode_simple      ; mode != 2 → simple clear and return
    LDA.l !ObjX_AnimLoops,X ; long: loop-count byte for this slot (ObjX_AnimLoops)
    DEC
    BEQ .loop_end         ; hit 0 → decrement column counter
    DEC
    BEQ .loop_one         ; hit 0 (was 2) → bump counter then decrement column
    STA.l !ObjX_AnimLoops,X ; store updated loop count
    STZ.w !Obj_AnimColumn,X ; reset animation column counter
    RTS
.loop_one:                ; $CA61
    INC
    STA.l !ObjX_AnimLoops,X
.loop_end:                ; $CA66
    DEC.w !Obj_AnimColumn,X ; decrement animation column counter
    RTS
.mode_simple:             ; $CA6A
    STZ.w !Obj_AnimColumn,X ; clear animation column counter
    RTS
.got_frame:               ; $CA6E — A = nonzero frame-step byte, X still 16-bit
    SEP #$10              ; X=8-bit
    LDX.b !Obj_Cur        ; reload entity slot
    STA.w !Obj_AnimTimer,X ; store frame-step byte as new animation timer
    RTS

; ============================================================
; $C0:CA76 — Field_ProcessAnimQueue (99 bytes, $CA76–$CAD8)
; Builds queued object frames while there is time left in the frame,
; called from Field_EndOfFrame. Skips the frame if the previous VRAM
; upload queue (VramQ_Valid) is still pending. Otherwise, while the
; V counter is past line 240 or below ObjQ_ScanlineLimit, it takes the
; queue head into Obj_Cur and runs Obj_BuildSpriteFrameStep; when that
; returns C=0 (step finished) the head is unlinked (Obj_QueueNext =
; $80) and the queue advances; C=1 retries the same object.
; Entry: M=1, X/Y 8-bit.
; ============================================================
org $C0CA76
Field_ProcessAnimQueue:
    LDA.w !VramQ_Valid    ; animation-queue busy / processed flag
    BEQ .proceed          ; zero → proceed
    RTS                   ; nonzero → already done this frame, exit
.proceed:                 ; $CA7C
    REP #$10              ; X=16-bit (NOP: immediately reset below)
    SEP #$10              ; X=8-bit
    STZ.b !VramQ_Pos      ; clear scratch byte
    LDA.w STAT78          ; STAT78: read PPU status (arms latch)
.latch:                   ; $CA85 — loop re-entry point for each slot step
    LDA.w SLHV            ; SLHV:  software-latch H/V counters
    LDA.w OPVCT           ; OPVCT: read vertical counter (low byte)
    XBA                   ; save low byte in B
    LDA.w OPVCT           ; OPVCT: read vertical counter (high bit)
    AND #$01              ; keep only bit 0 (9th bit of V)
    XBA                   ; restore low byte (B = high bit)
    REP #$20              ; A=16-bit: A[7:0]=V_low, A[15:8]=V_high_bit
    CMP.w #!Ppu_FirstHiddenLine ; compare with scanline 240 (vblank)
    BPL .in_window        ; V >= 240 → safe window, proceed
    CMP.b !ObjQ_ScanlineLimit ; compare with threshold
    BCS .exit_sep         ; V >= $6B → too close to display, exit
.in_window:               ; $CA9D
    LDA #$0000            ; clear A (16-bit zero)
    SEP #$20              ; A=8-bit
    LDA.b !ObjQ_Head      ; queue head slot index
    BMI .exit_rts         ; negative ($80) = no valid slot, exit
    STA.b !Obj_Cur        ; current slot = queue head
    LDA.b !ObjQ_Head
    CMP.b !ObjQ_Tail      ; primary == secondary?
    BEQ .same_slot        ; yes → single-slot path
    JSR Obj_BuildSpriteFrameStep  ; process primary slot step
    BCS .latch            ; carry set → step not complete, re-latch
    LDA.b !ObjQ_Head      ; update queue head via queue links
    TAX
    LDA.w !Obj_QueueNext,X ; next slot in queue links
    STA.b !ObjQ_Head      ; advance queue head
    LDA.b #!ObjQ_Empty
    STA.w !Obj_QueueNext,X ; mark old primary as invalid ($80)
    BRA .latch            ; re-latch and continue
.same_slot:               ; $CAC2 — $76 == $77
    JSR Obj_BuildSpriteFrameStep
    BCS .latch            ; not complete, retry
    LDA.b !ObjQ_Head
    TAX
    LDA.b #!ObjQ_Empty
    STA.w !Obj_QueueNext,X ; mark slot invalid
    STA.b !ObjQ_Head      ; queue head = invalid ($80)
    STA.b !ObjQ_Tail      ; queue tail = invalid ($80)
    BRA .latch            ; re-latch
.exit_rts:                ; $CAD5
    RTS
.exit_sep:                ; $CAD6
    SEP #$20              ; A=8-bit
    RTS

; ============================================================
; $C0:CAD9 — Obj_BuildSpriteFrameStep (49 bytes, $CAD9–$CB09)
; One step of building object Obj_Cur's current frame, graphics
; included: skips (C=0) unless Obj_Unk1100 bit 7 is clear,
; Obj_Unk1A81 is 1..$7F and Obj_Unk0F00 is nonzero; then by size class
; tail-calls Obj_BuildFrame4 / 8 / 12 (size 3: C=0, nothing).
; C=1 from a builder means "call again" (a multi-pass build).
; Called by Field_ProcessAnimQueue and the map-load pass ($C0:B109).
; Entry: M=1, X/Y 8-bit.
; ============================================================
org $C0CAD9
Obj_BuildSpriteFrameStep:
    LDX.b !Obj_Cur        ; entity slot index
    LDA.w !Obj_Unk1100,X  ; sprite state flags
    BPL .active           ; bit7 clear → slot active
.no_carry_rts:            ; $CAE0 — shared CLC+RTS exit
    CLC
    RTS
.active:                  ; $CAE2
    LDA.w !Obj_Unk1A81,X  ; timer/state byte
    BEQ .no_carry_rts     ; zero → not ready
    BMI .no_carry_rts     ; negative → not ready
    LDA.w !Obj_Unk0F00,X  ; animation type byte
    BEQ .no_carry_rts     ; zero → no animation
    LDA.w !Obj_SprSize,X  ; sprite pass/type flags
    AND.b #!ObjSpr_SizeMask ; isolate bits 0-1
    BEQ .type0            ; 0 → single-slot builder
    CMP #$01
    BNE .check2
    BRA .type1            ; 1 → 8-slot builder
.check2:
    CMP #$02
    BEQ .type2            ; 2 → 12-slot builder
    CLC
    RTS                   ; 3 → unhandled, no-op
.type0:
    BRL Obj_BuildFrame4             ; tail-call Obj_BuildFrame4 ($CB04 + $00D8 = $CBDC)
.type1:
    BRL Obj_BuildFrame8             ; tail-call Obj_BuildFrame8 ($CB07 + $03EE = $CEF5)
.type2:
    BRL Obj_BuildFrame12             ; tail-call Obj_BuildFrame12 ($CB0A + $09ED = $D4F7)

; ============================================================
; $C0:B8CA — Spr_Load4 (411 bytes, $B8CA–$BA64)
; (was Sub_B8CA.) Builds a 4-tile (size 0) object's SprTile records
; from SprTileSrc (OfsX, OfsY, Tile/Attr), placing them at the
; object's position as Spr_Place4 does (same three Y clamps).
; Quirk, as in Spr_Place4: the Spr_BaseYHi != 0 variant also clamps
; SprTile[4], one record past the object, from that record's own OfsY
; (it copies no OfsY into it first). Kept as in the original.
; Called from Spr_PrepareTiles.
; On entry: M=1, X/Y 16-bit, X = Obj_Cur, DP=$0100 (Spr_* scratch).
; Exit: M=1, X/Y 16-bit, DB restored (PLB).
; ============================================================
org $C0B8CA
Spr_Load4:
    PHB
    LDA.b #!Bank7F
    PHA
    PLB
    REP #$20
    LDA.l !Obj_ScreenY,X
    AND.w #!Spr_YMask9
    STA.b !Spr_BaseY
    LDA.l !Obj_ScreenX,X
    STA.b !Spr_BaseX
    STZ.b !Spr_HiBits
    LDA.l !Obj_TileRecOfs,X
    STA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*3 ; last of the 4 records first

    ; X: copy each OfsX from SprTileSrc, add Spr_BaseX, pack bit 8
.x_loop:
    TAX
    LDA.w SprTileSrc.OfsX,X ; 16-bit
    STA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20                ; M=1
    STA.w SprTile.X,X       ; X low byte
    XBA
    AND #$01                ; extract X bit 8 (overflow)
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_FirstRec
    BEQ .x_done             ; first record done
    STA.b !Spr_HiBits
    REP #$20                ; M=0
    TXA
    SEC
    SBC.w #!SprTile_Stride  ; previous record
    BRA .x_loop

.x_done:
    ORA.b #!Oam_HiLarge4    ; large-size bits
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA,X     ; the object's high-table byte
    LDX.b !Spr_FirstRec     ; back to the first record
    LDA.b !Spr_BaseYHi
    BEQ .y_hi_clear

    ; Spr_BaseYHi != 0: copy OfsY; keep a Y only if the add carries and
    ; lands on $E0-$FF, else Oam_HiddenY
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp0
    CMP.b #!Oam_HiddenY
    BCS .hi_store0
.hi_clamp0:
    LDA.b #!Oam_HiddenY
.hi_store0:
    STA.w SprTile.Y,X

    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp1
    CMP.b #!Oam_HiddenY
    BCS .hi_store1
.hi_clamp1:
    LDA.b #!Oam_HiddenY
.hi_store1:
    STA.w SprTile[1].Y,X

    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp2
    CMP.b #!Oam_HiddenY
    BCS .hi_store2
.hi_clamp2:
    LDA.b #!Oam_HiddenY
.hi_store2:
    STA.w SprTile[2].Y,X

    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp3
    CMP.b #!Oam_HiddenY
    BCS .hi_store3
.hi_clamp3:
    LDA.b #!Oam_HiddenY
.hi_store3:
    STA.w SprTile[3].Y,X

    LDA.w SprTile[4].OfsY,X ; 5th record, not copied (quirk)
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp4
    CMP.b #!Oam_HiddenY
    BCS .hi_store4
.hi_clamp4:
    LDA.b #!Oam_HiddenY
.hi_store4:
    STA.w SprTile[4].Y,X

    REP #$20                ; Tile and Attr together, 16-bit
    LDA.w SprTileSrc.Tile,X
    STA.w SprTile.Tile,X
    LDA.w SprTileSrc[1].Tile,X
    STA.w SprTile[1].Tile,X
    LDA.w SprTileSrc[2].Tile,X
    STA.w SprTile[2].Tile,X
    LDA.w SprTileSrc[3].Tile,X
    STA.w SprTile[3].Tile,X
    SEP #$20
    PLB
    RTS

.y_hi_clear:
    LDA.b !Spr_BaseY
    BPL .y_pos              ; Spr_BaseY bit 7 clear

    ; Spr_BaseY bit 7 set: keep a Y unless the add carries and lands on
    ; $E0-$FF, which becomes Oam_HiddenY
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .neg_store0
    CMP.b #!Oam_HiddenY
    BCC .neg_store0
    LDA.b #!Oam_HiddenY
.neg_store0:
    STA.w SprTile.Y,X

    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .neg_store1
    CMP.b #!Oam_HiddenY
    BCC .neg_store1
    LDA.b #!Oam_HiddenY
.neg_store1:
    STA.w SprTile[1].Y,X

    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .neg_store2
    CMP.b #!Oam_HiddenY
    BCC .neg_store2
    LDA.b #!Oam_HiddenY
.neg_store2:
    STA.w SprTile[2].Y,X

    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .neg_store3
    CMP.b #!Oam_HiddenY
    BCC .neg_store3
    LDA.b #!Oam_HiddenY
.neg_store3:
    STA.w SprTile[3].Y,X
    BRA .epilogue

    ; Spr_BaseY bit 7 clear: keep $00-$7F or $E0-$FF; $80-$DF becomes
    ; Oam_HiddenY
.y_pos:
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store0
    CMP.b #!Oam_HiddenY
    BCS .pos_store0
    LDA.b #!Oam_HiddenY
.pos_store0:
    STA.w SprTile.Y,X

    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store1
    CMP.b #!Oam_HiddenY
    BCS .pos_store1
    LDA.b #!Oam_HiddenY
.pos_store1:
    STA.w SprTile[1].Y,X

    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store2
    CMP.b #!Oam_HiddenY
    BCS .pos_store2
    LDA.b #!Oam_HiddenY
.pos_store2:
    STA.w SprTile[2].Y,X

    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store3
    CMP.b #!Oam_HiddenY
    BCS .pos_store3
    LDA.b #!Oam_HiddenY
.pos_store3:
    STA.w SprTile[3].Y,X

.epilogue:
    REP #$20                ; Tile and Attr together, 16-bit
    LDA.w SprTileSrc.Tile,X
    STA.w SprTile.Tile,X
    LDA.w SprTileSrc[1].Tile,X
    STA.w SprTile[1].Tile,X
    LDA.w SprTileSrc[2].Tile,X
    STA.w SprTile[2].Tile,X
    LDA.w SprTileSrc[3].Tile,X
    STA.w SprTile[3].Tile,X
    SEP #$20
    PLB
    RTS

; ============================================================
; $C0:BA65 — Spr_Place8 (631 bytes, $BA65–$BCDB)
; (was Sub_BA65.) Re-places an 8-tile (size 1) object from its
; existing SprTile records: two groups of 4 records give X and the two
; high-table bytes (Obj_OamHiA, Obj_OamHiA+1), then all 8 Y positions
; with the clamp variant chosen by Spr_BaseYHi / Spr_BaseY bit 7.
; Called from Spr_PrepareTiles.
; On entry: M=1, X/Y 16-bit, DP=$0100 (Spr_* scratch); loads X =
; Obj_Cur itself.
; Exit: M=1, X/Y 16-bit, DB restored (PLB).
; ============================================================
org $C0BA65
Spr_Place8:
    PHB
    LDA.b #!Bank7F
    PHA
    PLB
    REP #$20
    LDX.b !Obj_Cur
    LDA.l !Obj_ScreenY,X
    AND.w #!Spr_YMask9
    STA.b !Spr_BaseY
    LDA.l !Obj_ScreenX,X
    STA.b !Spr_BaseX
    STZ.b !Spr_HiBits
    LDA.l !Obj_TileRecOfs,X
    STA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; X of records 3..0, high-table bits → Obj_OamHiA
.x1_loop:
    TAX
    LDA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_FirstRec
    BEQ .x1_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x1_loop
.x1_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA,X
    STZ.b !Spr_HiBits
    REP #$20
    LDA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*4
    STA.b !Spr_GroupRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; X of records 7..4, high-table bits → Obj_OamHiA+1
.x2_loop:
    TAX
    LDA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_GroupRec
    BEQ .x2_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x2_loop
.x2_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA+1,X
    LDX.b !Spr_FirstRec
    LDA.b !Spr_BaseYHi
    BEQ .y_hi_clear
    BRL .y_hi_set

.y_hi_clear:
    LDA.b !Spr_BaseY
    BPL .y_pos

    ; Spr_BaseY bit 7 set: a Y of $E0-$FF becomes Oam_HiddenY
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store0
    LDA.b #!Oam_HiddenY
.neg_store0:
    STA.w SprTile.Y,X

    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store1
    LDA.b #!Oam_HiddenY
.neg_store1:
    STA.w SprTile[1].Y,X

    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store2
    LDA.b #!Oam_HiddenY
.neg_store2:
    STA.w SprTile[2].Y,X

    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store3
    LDA.b #!Oam_HiddenY
.neg_store3:
    STA.w SprTile[3].Y,X

    LDA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store4
    LDA.b #!Oam_HiddenY
.neg_store4:
    STA.w SprTile[4].Y,X

    LDA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store5
    LDA.b #!Oam_HiddenY
.neg_store5:
    STA.w SprTile[5].Y,X

    LDA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store6
    LDA.b #!Oam_HiddenY
.neg_store6:
    STA.w SprTile[6].Y,X

    LDA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store7
    LDA.b #!Oam_HiddenY
.neg_store7:
    STA.w SprTile[7].Y,X
    SEP #$20
    PLB
    RTS

    ; Spr_BaseY bit 7 clear: a Y of $80-$DF becomes Oam_HiddenY, except
    ; that an OfsY of $00-$7F whose add does not carry is always kept
.y_pos:
    LDA.w SprTile.OfsY,X
    BMI .pos_ofs_neg0
    CLC
    ADC.b !Spr_BaseY
    BCC .pos_store0
    BRA .pos_chk0
.pos_ofs_neg0:
    CLC
    ADC.b !Spr_BaseY
.pos_chk0:
    BPL .pos_store0
    CMP.b #!Oam_HiddenY
    BCS .pos_store0
    LDA.b #!Oam_HiddenY
.pos_store0:
    STA.w SprTile.Y,X

    LDA.w SprTile[1].OfsY,X
    BMI .pos_ofs_neg1
    CLC
    ADC.b !Spr_BaseY
    BCC .pos_store1
    BRA .pos_chk1
.pos_ofs_neg1:
    CLC
    ADC.b !Spr_BaseY
.pos_chk1:
    BPL .pos_store1
    CMP.b #!Oam_HiddenY
    BCS .pos_store1
    LDA.b #!Oam_HiddenY
.pos_store1:
    STA.w SprTile[1].Y,X

    LDA.w SprTile[2].OfsY,X
    BMI .pos_ofs_neg2
    CLC
    ADC.b !Spr_BaseY
    BCC .pos_store2
    BRA .pos_chk2
.pos_ofs_neg2:
    CLC
    ADC.b !Spr_BaseY
.pos_chk2:
    BPL .pos_store2
    CMP.b #!Oam_HiddenY
    BCS .pos_store2
    LDA.b #!Oam_HiddenY
.pos_store2:
    STA.w SprTile[2].Y,X

    LDA.w SprTile[3].OfsY,X
    BMI .pos_ofs_neg3
    CLC
    ADC.b !Spr_BaseY
    BCC .pos_store3
    BRA .pos_chk3
.pos_ofs_neg3:
    CLC
    ADC.b !Spr_BaseY
.pos_chk3:
    BPL .pos_store3
    CMP.b #!Oam_HiddenY
    BCS .pos_store3
    LDA.b #!Oam_HiddenY
.pos_store3:
    STA.w SprTile[3].Y,X

    LDA.w SprTile[4].OfsY,X
    BMI .pos_ofs_neg4
    CLC
    ADC.b !Spr_BaseY
    BCC .pos_store4
    BRA .pos_chk4
.pos_ofs_neg4:
    CLC
    ADC.b !Spr_BaseY
.pos_chk4:
    BPL .pos_store4
    CMP.b #!Oam_HiddenY
    BCS .pos_store4
    LDA.b #!Oam_HiddenY
.pos_store4:
    STA.w SprTile[4].Y,X

    LDA.w SprTile[5].OfsY,X
    BMI .pos_ofs_neg5
    CLC
    ADC.b !Spr_BaseY
    BCC .pos_store5
    BRA .pos_chk5
.pos_ofs_neg5:
    CLC
    ADC.b !Spr_BaseY
.pos_chk5:
    BPL .pos_store5
    CMP.b #!Oam_HiddenY
    BCS .pos_store5
    LDA.b #!Oam_HiddenY
.pos_store5:
    STA.w SprTile[5].Y,X

    LDA.w SprTile[6].OfsY,X
    BMI .pos_ofs_neg6
    CLC
    ADC.b !Spr_BaseY
    BCC .pos_store6
    BRA .pos_chk6
.pos_ofs_neg6:
    CLC
    ADC.b !Spr_BaseY
.pos_chk6:
    BPL .pos_store6
    CMP.b #!Oam_HiddenY
    BCS .pos_store6
    LDA.b #!Oam_HiddenY
.pos_store6:
    STA.w SprTile[6].Y,X

    LDA.w SprTile[7].OfsY,X
    BMI .pos_ofs_neg7
    CLC
    ADC.b !Spr_BaseY
    BCC .pos_store7
    BRA .pos_chk7
.pos_ofs_neg7:
    CLC
    ADC.b !Spr_BaseY
.pos_chk7:
    BPL .pos_store7
    CMP.b #!Oam_HiddenY
    BCS .pos_store7
    LDA.b #!Oam_HiddenY
.pos_store7:
    STA.w SprTile[7].Y,X
    SEP #$20
    PLB
    RTS

    ; Spr_BaseYHi != 0: keep a Y only if the add carries and lands on
    ; $E0-$FF, else Oam_HiddenY
.y_hi_set:
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp0
    CMP.b #!Oam_HiddenY
    BCS .hi_store0
.hi_clamp0:
    LDA.b #!Oam_HiddenY
.hi_store0:
    STA.w SprTile.Y,X

    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp1
    CMP.b #!Oam_HiddenY
    BCS .hi_store1
.hi_clamp1:
    LDA.b #!Oam_HiddenY
.hi_store1:
    STA.w SprTile[1].Y,X

    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp2
    CMP.b #!Oam_HiddenY
    BCS .hi_store2
.hi_clamp2:
    LDA.b #!Oam_HiddenY
.hi_store2:
    STA.w SprTile[2].Y,X

    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp3
    CMP.b #!Oam_HiddenY
    BCS .hi_store3
.hi_clamp3:
    LDA.b #!Oam_HiddenY
.hi_store3:
    STA.w SprTile[3].Y,X

    LDA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp4
    CMP.b #!Oam_HiddenY
    BCS .hi_store4
.hi_clamp4:
    LDA.b #!Oam_HiddenY
.hi_store4:
    STA.w SprTile[4].Y,X

    LDA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp5
    CMP.b #!Oam_HiddenY
    BCS .hi_store5
.hi_clamp5:
    LDA.b #!Oam_HiddenY
.hi_store5:
    STA.w SprTile[5].Y,X

    LDA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp6
    CMP.b #!Oam_HiddenY
    BCS .hi_store6
.hi_clamp6:
    LDA.b #!Oam_HiddenY
.hi_store6:
    STA.w SprTile[6].Y,X

    LDA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp7
    CMP.b #!Oam_HiddenY
    BCS .hi_store7
.hi_clamp7:
    LDA.b #!Oam_HiddenY
.hi_store7:
    STA.w SprTile[7].Y,X
    SEP #$20
    PLB
    RTS

; ============================================================
; $C0:BCDC — Spr_Load8 (790 bytes, $BCDC–$BFF1)
; (was Sub_BCDC.) Builds an 8-tile (size 1) object's SprTile records
; from SprTileSrc and places them: OfsX, OfsY and Tile/Attr are copied
; from SprTileSrc, then X, the two high-table bytes and Y are set as in
; Spr_Place8. The Spr_BaseY bit 7 clear clamp is the plain one ($80-$DF
; → Oam_HiddenY for every record), without Spr_Place8's exception.
; Called from Spr_PrepareTiles.
; On entry: M=1, X/Y 16-bit, DP=$0100 (Spr_* scratch); loads X =
; Obj_Cur itself.
; Exit: M=1, X/Y 16-bit, DB restored (PLB).
; ============================================================
org $C0BCDC
Spr_Load8:
    PHB
    LDA.b #!Bank7F
    PHA
    PLB
    REP #$20
    LDX.b !Obj_Cur
    LDA.l !Obj_ScreenY,X
    AND.w #!Spr_YMask9
    STA.b !Spr_BaseY
    LDA.l !Obj_ScreenX,X
    STA.b !Spr_BaseX
    STZ.b !Spr_HiBits
    LDA.l !Obj_TileRecOfs,X
    STA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; Records 3..0: copy OfsX, set X, high-table bits → Obj_OamHiA
.x1_loop:
    TAX
    LDA.w SprTileSrc.OfsX,X
    STA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_FirstRec
    BEQ .x1_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x1_loop
.x1_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA,X
    STZ.b !Spr_HiBits
    REP #$20
    LDA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*4
    STA.b !Spr_GroupRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; Records 7..4, high-table bits → Obj_OamHiA+1
.x2_loop:
    TAX
    LDA.w SprTileSrc.OfsX,X
    STA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_GroupRec
    BEQ .x2_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x2_loop
.x2_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA+1,X
    LDX.b !Spr_FirstRec
    LDA.b !Spr_BaseYHi
    BEQ .y_hi_clear
    BRL .y_hi_set

.y_hi_clear:
    LDA.b !Spr_BaseY
    BMI .y_neg
    BRL .y_pos              ; Spr_BaseY bit 7 clear

    ; Spr_BaseY bit 7 set: copy OfsY; a Y of $E0-$FF becomes Oam_HiddenY
.y_neg:
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store0
    LDA.b #!Oam_HiddenY
.neg_store0:
    STA.w SprTile.Y,X
    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store1
    LDA.b #!Oam_HiddenY
.neg_store1:
    STA.w SprTile[1].Y,X
    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store2
    LDA.b #!Oam_HiddenY
.neg_store2:
    STA.w SprTile[2].Y,X
    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store3
    LDA.b #!Oam_HiddenY
.neg_store3:
    STA.w SprTile[3].Y,X
    LDA.w SprTileSrc[4].OfsY,X
    STA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store4
    LDA.b #!Oam_HiddenY
.neg_store4:
    STA.w SprTile[4].Y,X
    LDA.w SprTileSrc[5].OfsY,X
    STA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store5
    LDA.b #!Oam_HiddenY
.neg_store5:
    STA.w SprTile[5].Y,X
    LDA.w SprTileSrc[6].OfsY,X
    STA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store6
    LDA.b #!Oam_HiddenY
.neg_store6:
    STA.w SprTile[6].Y,X
    LDA.w SprTileSrc[7].OfsY,X
    STA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    CMP.b #!Oam_HiddenY
    BCC .neg_store7
    LDA.b #!Oam_HiddenY
.neg_store7:
    STA.w SprTile[7].Y,X
    REP #$20
    LDA.w SprTileSrc.Tile,X
    STA.w SprTile.Tile,X
    LDA.w SprTileSrc[1].Tile,X
    STA.w SprTile[1].Tile,X
    LDA.w SprTileSrc[2].Tile,X
    STA.w SprTile[2].Tile,X
    LDA.w SprTileSrc[3].Tile,X
    STA.w SprTile[3].Tile,X
    LDA.w SprTileSrc[4].Tile,X
    STA.w SprTile[4].Tile,X
    LDA.w SprTileSrc[5].Tile,X
    STA.w SprTile[5].Tile,X
    LDA.w SprTileSrc[6].Tile,X
    STA.w SprTile[6].Tile,X
    LDA.w SprTileSrc[7].Tile,X
    STA.w SprTile[7].Tile,X
    SEP #$20
    PLB
    RTS

    ; Spr_BaseY bit 7 clear: copy OfsY; $80-$DF becomes Oam_HiddenY
.y_pos:
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store0
    CMP.b #!Oam_HiddenY
    BCS .pos_store0
    LDA.b #!Oam_HiddenY
.pos_store0:
    STA.w SprTile.Y,X
    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store1
    CMP.b #!Oam_HiddenY
    BCS .pos_store1
    LDA.b #!Oam_HiddenY
.pos_store1:
    STA.w SprTile[1].Y,X
    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store2
    CMP.b #!Oam_HiddenY
    BCS .pos_store2
    LDA.b #!Oam_HiddenY
.pos_store2:
    STA.w SprTile[2].Y,X
    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store3
    CMP.b #!Oam_HiddenY
    BCS .pos_store3
    LDA.b #!Oam_HiddenY
.pos_store3:
    STA.w SprTile[3].Y,X
    LDA.w SprTileSrc[4].OfsY,X
    STA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store4
    CMP.b #!Oam_HiddenY
    BCS .pos_store4
    LDA.b #!Oam_HiddenY
.pos_store4:
    STA.w SprTile[4].Y,X
    LDA.w SprTileSrc[5].OfsY,X
    STA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store5
    CMP.b #!Oam_HiddenY
    BCS .pos_store5
    LDA.b #!Oam_HiddenY
.pos_store5:
    STA.w SprTile[5].Y,X
    LDA.w SprTileSrc[6].OfsY,X
    STA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store6
    CMP.b #!Oam_HiddenY
    BCS .pos_store6
    LDA.b #!Oam_HiddenY
.pos_store6:
    STA.w SprTile[6].Y,X
    LDA.w SprTileSrc[7].OfsY,X
    STA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store7
    CMP.b #!Oam_HiddenY
    BCS .pos_store7
    LDA.b #!Oam_HiddenY
.pos_store7:
    STA.w SprTile[7].Y,X
    REP #$20
    LDA.w SprTileSrc.Tile,X
    STA.w SprTile.Tile,X
    LDA.w SprTileSrc[1].Tile,X
    STA.w SprTile[1].Tile,X
    LDA.w SprTileSrc[2].Tile,X
    STA.w SprTile[2].Tile,X
    LDA.w SprTileSrc[3].Tile,X
    STA.w SprTile[3].Tile,X
    LDA.w SprTileSrc[4].Tile,X
    STA.w SprTile[4].Tile,X
    LDA.w SprTileSrc[5].Tile,X
    STA.w SprTile[5].Tile,X
    LDA.w SprTileSrc[6].Tile,X
    STA.w SprTile[6].Tile,X
    LDA.w SprTileSrc[7].Tile,X
    STA.w SprTile[7].Tile,X
    SEP #$20
    PLB
    RTS

    ; Spr_BaseYHi != 0: copy OfsY; keep a Y only if the add carries and
    ; lands on $E0-$FF, else Oam_HiddenY
.y_hi_set:
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp0
    CMP.b #!Oam_HiddenY
    BCS .hi_store0
.hi_clamp0:
    LDA.b #!Oam_HiddenY
.hi_store0:
    STA.w SprTile.Y,X
    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp1
    CMP.b #!Oam_HiddenY
    BCS .hi_store1
.hi_clamp1:
    LDA.b #!Oam_HiddenY
.hi_store1:
    STA.w SprTile[1].Y,X
    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp2
    CMP.b #!Oam_HiddenY
    BCS .hi_store2
.hi_clamp2:
    LDA.b #!Oam_HiddenY
.hi_store2:
    STA.w SprTile[2].Y,X
    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp3
    CMP.b #!Oam_HiddenY
    BCS .hi_store3
.hi_clamp3:
    LDA.b #!Oam_HiddenY
.hi_store3:
    STA.w SprTile[3].Y,X
    LDA.w SprTileSrc[4].OfsY,X
    STA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp4
    CMP.b #!Oam_HiddenY
    BCS .hi_store4
.hi_clamp4:
    LDA.b #!Oam_HiddenY
.hi_store4:
    STA.w SprTile[4].Y,X
    LDA.w SprTileSrc[5].OfsY,X
    STA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp5
    CMP.b #!Oam_HiddenY
    BCS .hi_store5
.hi_clamp5:
    LDA.b #!Oam_HiddenY
.hi_store5:
    STA.w SprTile[5].Y,X
    LDA.w SprTileSrc[6].OfsY,X
    STA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp6
    CMP.b #!Oam_HiddenY
    BCS .hi_store6
.hi_clamp6:
    LDA.b #!Oam_HiddenY
.hi_store6:
    STA.w SprTile[6].Y,X
    LDA.w SprTileSrc[7].OfsY,X
    STA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCC .hi_clamp7
    CMP.b #!Oam_HiddenY
    BCS .hi_store7
.hi_clamp7:
    LDA.b #!Oam_HiddenY
.hi_store7:
    STA.w SprTile[7].Y,X
    REP #$20
    LDA.w SprTileSrc.Tile,X
    STA.w SprTile.Tile,X
    LDA.w SprTileSrc[1].Tile,X
    STA.w SprTile[1].Tile,X
    LDA.w SprTileSrc[2].Tile,X
    STA.w SprTile[2].Tile,X
    LDA.w SprTileSrc[3].Tile,X
    STA.w SprTile[3].Tile,X
    LDA.w SprTileSrc[4].Tile,X
    STA.w SprTile[4].Tile,X
    LDA.w SprTileSrc[5].Tile,X
    STA.w SprTile[5].Tile,X
    LDA.w SprTileSrc[6].Tile,X
    STA.w SprTile[6].Tile,X
    LDA.w SprTileSrc[7].Tile,X
    STA.w SprTile[7].Tile,X
    SEP #$20
    PLB
    RTS

; ============================================================
; $C0:BFF2 — Spr_Place12 (717 bytes, $BFF2–$C2BE)
; (was Sub_BFF2.) Re-places a 12-tile (size 2) object from its
; existing SprTile records: three groups of 4 records give X and the
; high-table bytes (Obj_OamHiA, Obj_OamHiA+1, Obj_OamHiB), then the 12
; Y positions by Spr_BaseYHi / Spr_BaseY bit 7:
;   Spr_BaseYHi != 0      keep only $00-$7F without a carry, else
;                         Oam_HiddenY;
;   bit 7 set ("negative") plain add, no clamp;
;   bit 7 clear           $80-$DF → Oam_HiddenY (the plain clamp:
;                         unlike Spr_Place8, no OfsY sign test).
; Called from Spr_PrepareTiles.
; On entry: M=1, X/Y 16-bit, DP=$0100 (Spr_* scratch); loads X =
; Obj_Cur itself.
; Exit: M=1, X/Y 16-bit, DB restored (PLB).
; ============================================================
org $C0BFF2
Spr_Place12:
    PHB
    LDA.b #!Bank7F
    PHA
    PLB
    REP #$20
    LDX.b !Obj_Cur
    LDA.l !Obj_ScreenY,X
    AND.w #!Spr_YMask9
    STA.b !Spr_BaseY
    LDA.l !Obj_ScreenX,X
    STA.b !Spr_BaseX
    STZ.b !Spr_HiBits
    LDA.l !Obj_TileRecOfs,X
    STA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; X of records 3..0, high-table bits → Obj_OamHiA
.x1_loop:
    TAX
    LDA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_FirstRec
    BEQ .x1_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x1_loop
.x1_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA,X
    STZ.b !Spr_HiBits
    REP #$20
    LDA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*4
    STA.b !Spr_GroupRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; X of records 7..4, high-table bits → Obj_OamHiA+1
.x2_loop:
    TAX
    LDA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_GroupRec
    BEQ .x2_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x2_loop
.x2_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA+1,X
    STZ.b !Spr_HiBits
    REP #$20
    LDA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*8
    STA.b !Spr_GroupRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; X of records 11..8, high-table bits → Obj_OamHiB
.x3_loop:
    TAX
    LDA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_GroupRec
    BEQ .x3_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x3_loop
.x3_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiB,X

    ; Y positions
    LDX.b !Spr_FirstRec
    LDA.b !Spr_BaseYHi
    BEQ .y_hi_clear
    BRL .y_hi_set               ; Spr_BaseYHi != 0

.y_hi_clear:
    LDA.b !Spr_BaseY
    BMI .y_neg
    BRL .y_pos                  ; Spr_BaseY bit 7 clear

    ; Spr_BaseY bit 7 set: plain add, no clamp
.y_neg:
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile.Y,X
    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[1].Y,X
    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[2].Y,X
    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[3].Y,X
    LDA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[4].Y,X
    LDA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[5].Y,X
    LDA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[6].Y,X
    LDA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[7].Y,X
    LDA.w SprTile[8].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[8].Y,X
    LDA.w SprTile[9].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[9].Y,X
    LDA.w SprTile[10].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[10].Y,X
    LDA.w SprTile[11].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[11].Y,X
    PLB
    RTS

    ; Spr_BaseY bit 7 clear: $80-$DF → Oam_HiddenY
.y_pos:
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store0
    CMP.b #!Oam_HiddenY
    BCS .pos_store0
    LDA.b #!Oam_HiddenY
.pos_store0:
    STA.w SprTile.Y,X
    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store1
    CMP.b #!Oam_HiddenY
    BCS .pos_store1
    LDA.b #!Oam_HiddenY
.pos_store1:
    STA.w SprTile[1].Y,X
    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store2
    CMP.b #!Oam_HiddenY
    BCS .pos_store2
    LDA.b #!Oam_HiddenY
.pos_store2:
    STA.w SprTile[2].Y,X
    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store3
    CMP.b #!Oam_HiddenY
    BCS .pos_store3
    LDA.b #!Oam_HiddenY
.pos_store3:
    STA.w SprTile[3].Y,X
    LDA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store4
    CMP.b #!Oam_HiddenY
    BCS .pos_store4
    LDA.b #!Oam_HiddenY
.pos_store4:
    STA.w SprTile[4].Y,X
    LDA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store5
    CMP.b #!Oam_HiddenY
    BCS .pos_store5
    LDA.b #!Oam_HiddenY
.pos_store5:
    STA.w SprTile[5].Y,X
    LDA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store6
    CMP.b #!Oam_HiddenY
    BCS .pos_store6
    LDA.b #!Oam_HiddenY
.pos_store6:
    STA.w SprTile[6].Y,X
    LDA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store7
    CMP.b #!Oam_HiddenY
    BCS .pos_store7
    LDA.b #!Oam_HiddenY
.pos_store7:
    STA.w SprTile[7].Y,X
    LDA.w SprTile[8].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store8
    CMP.b #!Oam_HiddenY
    BCS .pos_store8
    LDA.b #!Oam_HiddenY
.pos_store8:
    STA.w SprTile[8].Y,X
    LDA.w SprTile[9].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store9
    CMP.b #!Oam_HiddenY
    BCS .pos_store9
    LDA.b #!Oam_HiddenY
.pos_store9:
    STA.w SprTile[9].Y,X
    LDA.w SprTile[10].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store10
    CMP.b #!Oam_HiddenY
    BCS .pos_store10
    LDA.b #!Oam_HiddenY
.pos_store10:
    STA.w SprTile[10].Y,X
    LDA.w SprTile[11].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store11
    CMP.b #!Oam_HiddenY
    BCS .pos_store11
    LDA.b #!Oam_HiddenY
.pos_store11:
    STA.w SprTile[11].Y,X
    PLB
    RTS

    ; Spr_BaseYHi != 0: keep only $00-$7F without a carry
.y_hi_set:
    LDA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp0
    BPL .hi_store0
.hi_clamp0:
    LDA.b #!Oam_HiddenY
.hi_store0:
    STA.w SprTile.Y,X
    LDA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp1
    BPL .hi_store1
.hi_clamp1:
    LDA.b #!Oam_HiddenY
.hi_store1:
    STA.w SprTile[1].Y,X
    LDA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp2
    BPL .hi_store2
.hi_clamp2:
    LDA.b #!Oam_HiddenY
.hi_store2:
    STA.w SprTile[2].Y,X
    LDA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp3
    BPL .hi_store3
.hi_clamp3:
    LDA.b #!Oam_HiddenY
.hi_store3:
    STA.w SprTile[3].Y,X
    LDA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp4
    BPL .hi_store4
.hi_clamp4:
    LDA.b #!Oam_HiddenY
.hi_store4:
    STA.w SprTile[4].Y,X
    LDA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp5
    BPL .hi_store5
.hi_clamp5:
    LDA.b #!Oam_HiddenY
.hi_store5:
    STA.w SprTile[5].Y,X
    LDA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp6
    BPL .hi_store6
.hi_clamp6:
    LDA.b #!Oam_HiddenY
.hi_store6:
    STA.w SprTile[6].Y,X
    LDA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp7
    BPL .hi_store7
.hi_clamp7:
    LDA.b #!Oam_HiddenY
.hi_store7:
    STA.w SprTile[7].Y,X
    LDA.w SprTile[8].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp8
    BPL .hi_store8
.hi_clamp8:
    LDA.b #!Oam_HiddenY
.hi_store8:
    STA.w SprTile[8].Y,X
    LDA.w SprTile[9].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp9
    BPL .hi_store9
.hi_clamp9:
    LDA.b #!Oam_HiddenY
.hi_store9:
    STA.w SprTile[9].Y,X
    LDA.w SprTile[10].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp10
    BPL .hi_store10
.hi_clamp10:
    LDA.b #!Oam_HiddenY
.hi_store10:
    STA.w SprTile[10].Y,X
    LDA.w SprTile[11].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp11
    BPL .hi_store11
.hi_clamp11:
    LDA.b #!Oam_HiddenY
.hi_store11:
    STA.w SprTile[11].Y,X
    PLB
    RTS

; ============================================================
; $C0:C2BF — Spr_Load12 (1064 bytes, $C2BF–$C6E6)
; (was Sub_C2BF.) Builds a 12-tile (size 2) object's SprTile records
; from SprTileSrc and places them: OfsX, OfsY and Tile/Attr are copied
; from SprTileSrc, then X, the three high-table bytes and Y are set as
; in Spr_Place12, with the same three clamps.
; Called from Spr_PrepareTiles.
; On entry: M=1, X/Y 16-bit, DP=$0100 (Spr_* scratch); loads X =
; Obj_Cur itself.
; Exit: M=1, X/Y 16-bit, DB restored (PLB).
; ============================================================
org $C0C2BF
Spr_Load12:
    PHB
    LDA.b #!Bank7F
    PHA
    PLB
    REP #$20
    LDX.b !Obj_Cur
    LDA.l !Obj_ScreenY,X
    AND.w #!Spr_YMask9
    STA.b !Spr_BaseY
    LDA.l !Obj_ScreenX,X
    STA.b !Spr_BaseX
    STZ.b !Spr_HiBits
    LDA.l !Obj_TileRecOfs,X
    STA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; Records 3..0: copy OfsX, set X, high-table bits → Obj_OamHiA
.x1_loop:
    TAX
    LDA.w SprTileSrc.OfsX,X
    STA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_FirstRec
    BEQ .x1_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x1_loop
.x1_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA,X
    STZ.b !Spr_HiBits
    REP #$20
    LDA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*4
    STA.b !Spr_GroupRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; Records 7..4 → Obj_OamHiA+1
.x2_loop:
    TAX
    LDA.w SprTileSrc.OfsX,X
    STA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_GroupRec
    BEQ .x2_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x2_loop
.x2_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiA+1,X
    LDX.b !Spr_FirstRec         ; dead: the TAX in .x3_loop reloads X
    STZ.b !Spr_HiBits
    REP #$20
    LDA.b !Spr_FirstRec
    CLC
    ADC.w #!SprTile_Stride*8
    STA.b !Spr_GroupRec
    CLC
    ADC.w #!SprTile_Stride*3

    ; Records 11..8 → Obj_OamHiB
.x3_loop:
    TAX
    LDA.w SprTileSrc.OfsX,X
    STA.w SprTile.OfsX,X
    CLC
    ADC.b !Spr_BaseX
    SEP #$20
    STA.w SprTile.X,X
    XBA
    AND #$01
    STA.b !Spr_HiBitTmp
    LDA.b !Spr_HiBits
    ASL A
    ASL A
    ORA.b !Spr_HiBitTmp
    CPX.b !Spr_GroupRec
    BEQ .x3_done
    STA.b !Spr_HiBits
    REP #$20
    TXA
    SEC
    SBC.w #!SprTile_Stride
    BRA .x3_loop
.x3_done:
    ORA.b #!Oam_HiLarge4
    LDX.b !Obj_Cur
    STA.w !Obj_OamHiB,X
    LDX.b !Spr_FirstRec
    LDA.b !Spr_BaseYHi
    BEQ .y_hi_clear
    BRL .y_hi_set               ; Spr_BaseYHi != 0

.y_hi_clear:
    LDA.b !Spr_BaseY
    BMI .y_neg
    BRL .y_pos                  ; Spr_BaseY bit 7 clear

    ; Spr_BaseY bit 7 set: copy OfsY, plain add, no clamp
.y_neg:
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile.Y,X
    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[1].Y,X
    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[2].Y,X
    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[3].Y,X
    LDA.w SprTileSrc[4].OfsY,X
    STA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[4].Y,X
    LDA.w SprTileSrc[5].OfsY,X
    STA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[5].Y,X
    LDA.w SprTileSrc[6].OfsY,X
    STA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[6].Y,X
    LDA.w SprTileSrc[7].OfsY,X
    STA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[7].Y,X
    LDA.w SprTileSrc[8].OfsY,X
    STA.w SprTile[8].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[8].Y,X
    LDA.w SprTileSrc[9].OfsY,X
    STA.w SprTile[9].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[9].Y,X
    LDA.w SprTileSrc[10].OfsY,X
    STA.w SprTile[10].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[10].Y,X
    LDA.w SprTileSrc[11].OfsY,X
    STA.w SprTile[11].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    STA.w SprTile[11].Y,X
    REP #$20
    LDA.w SprTileSrc.Tile,X
    STA.w SprTile.Tile,X
    LDA.w SprTileSrc[1].Tile,X
    STA.w SprTile[1].Tile,X
    LDA.w SprTileSrc[2].Tile,X
    STA.w SprTile[2].Tile,X
    LDA.w SprTileSrc[3].Tile,X
    STA.w SprTile[3].Tile,X
    LDA.w SprTileSrc[4].Tile,X
    STA.w SprTile[4].Tile,X
    LDA.w SprTileSrc[5].Tile,X
    STA.w SprTile[5].Tile,X
    LDA.w SprTileSrc[6].Tile,X
    STA.w SprTile[6].Tile,X
    LDA.w SprTileSrc[7].Tile,X
    STA.w SprTile[7].Tile,X
    LDA.w SprTileSrc[8].Tile,X
    STA.w SprTile[8].Tile,X
    LDA.w SprTileSrc[9].Tile,X
    STA.w SprTile[9].Tile,X
    LDA.w SprTileSrc[10].Tile,X
    STA.w SprTile[10].Tile,X
    LDA.w SprTileSrc[11].Tile,X
    STA.w SprTile[11].Tile,X
    SEP #$20
    PLB
    RTS

    ; Spr_BaseY bit 7 clear: copy OfsY; $80-$DF → Oam_HiddenY
.y_pos:
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store0
    CMP.b #!Oam_HiddenY
    BCS .pos_store0
    LDA.b #!Oam_HiddenY
.pos_store0:
    STA.w SprTile.Y,X
    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store1
    CMP.b #!Oam_HiddenY
    BCS .pos_store1
    LDA.b #!Oam_HiddenY
.pos_store1:
    STA.w SprTile[1].Y,X
    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store2
    CMP.b #!Oam_HiddenY
    BCS .pos_store2
    LDA.b #!Oam_HiddenY
.pos_store2:
    STA.w SprTile[2].Y,X
    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store3
    CMP.b #!Oam_HiddenY
    BCS .pos_store3
    LDA.b #!Oam_HiddenY
.pos_store3:
    STA.w SprTile[3].Y,X
    LDA.w SprTileSrc[4].OfsY,X
    STA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store4
    CMP.b #!Oam_HiddenY
    BCS .pos_store4
    LDA.b #!Oam_HiddenY
.pos_store4:
    STA.w SprTile[4].Y,X
    LDA.w SprTileSrc[5].OfsY,X
    STA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store5
    CMP.b #!Oam_HiddenY
    BCS .pos_store5
    LDA.b #!Oam_HiddenY
.pos_store5:
    STA.w SprTile[5].Y,X
    LDA.w SprTileSrc[6].OfsY,X
    STA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store6
    CMP.b #!Oam_HiddenY
    BCS .pos_store6
    LDA.b #!Oam_HiddenY
.pos_store6:
    STA.w SprTile[6].Y,X
    LDA.w SprTileSrc[7].OfsY,X
    STA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store7
    CMP.b #!Oam_HiddenY
    BCS .pos_store7
    LDA.b #!Oam_HiddenY
.pos_store7:
    STA.w SprTile[7].Y,X
    LDA.w SprTileSrc[8].OfsY,X
    STA.w SprTile[8].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store8
    CMP.b #!Oam_HiddenY
    BCS .pos_store8
    LDA.b #!Oam_HiddenY
.pos_store8:
    STA.w SprTile[8].Y,X
    LDA.w SprTileSrc[9].OfsY,X
    STA.w SprTile[9].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store9
    CMP.b #!Oam_HiddenY
    BCS .pos_store9
    LDA.b #!Oam_HiddenY
.pos_store9:
    STA.w SprTile[9].Y,X
    LDA.w SprTileSrc[10].OfsY,X
    STA.w SprTile[10].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store10
    CMP.b #!Oam_HiddenY
    BCS .pos_store10
    LDA.b #!Oam_HiddenY
.pos_store10:
    STA.w SprTile[10].Y,X
    LDA.w SprTileSrc[11].OfsY,X
    STA.w SprTile[11].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BPL .pos_store11
    CMP.b #!Oam_HiddenY
    BCS .pos_store11
    LDA.b #!Oam_HiddenY
.pos_store11:
    STA.w SprTile[11].Y,X
    REP #$20
    LDA.w SprTileSrc.Tile,X
    STA.w SprTile.Tile,X
    LDA.w SprTileSrc[1].Tile,X
    STA.w SprTile[1].Tile,X
    LDA.w SprTileSrc[2].Tile,X
    STA.w SprTile[2].Tile,X
    LDA.w SprTileSrc[3].Tile,X
    STA.w SprTile[3].Tile,X
    LDA.w SprTileSrc[4].Tile,X
    STA.w SprTile[4].Tile,X
    LDA.w SprTileSrc[5].Tile,X
    STA.w SprTile[5].Tile,X
    LDA.w SprTileSrc[6].Tile,X
    STA.w SprTile[6].Tile,X
    LDA.w SprTileSrc[7].Tile,X
    STA.w SprTile[7].Tile,X
    LDA.w SprTileSrc[8].Tile,X
    STA.w SprTile[8].Tile,X
    LDA.w SprTileSrc[9].Tile,X
    STA.w SprTile[9].Tile,X
    LDA.w SprTileSrc[10].Tile,X
    STA.w SprTile[10].Tile,X
    LDA.w SprTileSrc[11].Tile,X
    STA.w SprTile[11].Tile,X
    SEP #$20
    PLB
    RTS

    ; Spr_BaseYHi != 0: copy OfsY; keep only $00-$7F without a carry
.y_hi_set:
    LDA.w SprTileSrc.OfsY,X
    STA.w SprTile.OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp0
    BPL .hi_store0
.hi_clamp0:
    LDA.b #!Oam_HiddenY
.hi_store0:
    STA.w SprTile.Y,X
    LDA.w SprTileSrc[1].OfsY,X
    STA.w SprTile[1].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp1
    BPL .hi_store1
.hi_clamp1:
    LDA.b #!Oam_HiddenY
.hi_store1:
    STA.w SprTile[1].Y,X
    LDA.w SprTileSrc[2].OfsY,X
    STA.w SprTile[2].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp2
    BPL .hi_store2
.hi_clamp2:
    LDA.b #!Oam_HiddenY
.hi_store2:
    STA.w SprTile[2].Y,X
    LDA.w SprTileSrc[3].OfsY,X
    STA.w SprTile[3].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp3
    BPL .hi_store3
.hi_clamp3:
    LDA.b #!Oam_HiddenY
.hi_store3:
    STA.w SprTile[3].Y,X
    LDA.w SprTileSrc[4].OfsY,X
    STA.w SprTile[4].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp4
    BPL .hi_store4
.hi_clamp4:
    LDA.b #!Oam_HiddenY
.hi_store4:
    STA.w SprTile[4].Y,X
    LDA.w SprTileSrc[5].OfsY,X
    STA.w SprTile[5].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp5
    BPL .hi_store5
.hi_clamp5:
    LDA.b #!Oam_HiddenY
.hi_store5:
    STA.w SprTile[5].Y,X
    LDA.w SprTileSrc[6].OfsY,X
    STA.w SprTile[6].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp6
    BPL .hi_store6
.hi_clamp6:
    LDA.b #!Oam_HiddenY
.hi_store6:
    STA.w SprTile[6].Y,X
    LDA.w SprTileSrc[7].OfsY,X
    STA.w SprTile[7].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp7
    BPL .hi_store7
.hi_clamp7:
    LDA.b #!Oam_HiddenY
.hi_store7:
    STA.w SprTile[7].Y,X
    LDA.w SprTileSrc[8].OfsY,X
    STA.w SprTile[8].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp8
    BPL .hi_store8
.hi_clamp8:
    LDA.b #!Oam_HiddenY
.hi_store8:
    STA.w SprTile[8].Y,X
    LDA.w SprTileSrc[9].OfsY,X
    STA.w SprTile[9].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp9
    BPL .hi_store9
.hi_clamp9:
    LDA.b #!Oam_HiddenY
.hi_store9:
    STA.w SprTile[9].Y,X
    LDA.w SprTileSrc[10].OfsY,X
    STA.w SprTile[10].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp10
    BPL .hi_store10
.hi_clamp10:
    LDA.b #!Oam_HiddenY
.hi_store10:
    STA.w SprTile[10].Y,X
    LDA.w SprTileSrc[11].OfsY,X
    STA.w SprTile[11].OfsY,X
    CLC
    ADC.b !Spr_BaseY
    BCS .hi_clamp11
    BPL .hi_store11
.hi_clamp11:
    LDA.b #!Oam_HiddenY
.hi_store11:
    STA.w SprTile[11].Y,X
    REP #$20
    LDA.w SprTileSrc.Tile,X
    STA.w SprTile.Tile,X
    LDA.w SprTileSrc[1].Tile,X
    STA.w SprTile[1].Tile,X
    LDA.w SprTileSrc[2].Tile,X
    STA.w SprTile[2].Tile,X
    LDA.w SprTileSrc[3].Tile,X
    STA.w SprTile[3].Tile,X
    LDA.w SprTileSrc[4].Tile,X
    STA.w SprTile[4].Tile,X
    LDA.w SprTileSrc[5].Tile,X
    STA.w SprTile[5].Tile,X
    LDA.w SprTileSrc[6].Tile,X
    STA.w SprTile[6].Tile,X
    LDA.w SprTileSrc[7].Tile,X
    STA.w SprTile[7].Tile,X
    LDA.w SprTileSrc[8].Tile,X
    STA.w SprTile[8].Tile,X
    LDA.w SprTileSrc[9].Tile,X
    STA.w SprTile[9].Tile,X
    LDA.w SprTileSrc[10].Tile,X
    STA.w SprTile[10].Tile,X
    LDA.w SprTileSrc[11].Tile,X
    STA.w SprTile[11].Tile,X
    SEP #$20
    PLB
    RTS

; ============================================================
; $C0:E12A — Spr_LoadLargeObj (1034 bytes, $E12A–$E533)
; (was Sub_E12A.) Loads a 24-tile ("large") object in one go. It never
; reads Obj_SprSize; "size 3" is inferred from the 24 records it fills,
; which only Spr_Place24 (size 3) re-places.
; 1. Pointers: Spr_GfxPtr = Obj_GfxBank:Obj_GfxOfs, Spr_FramePtr =
;    Obj_FrameBank:Obj_FrameOfs, Spr_WramPtr = $7F:SprBuf_Base (the
;    object uses the whole tile buffer: Obj_TileBuf = SprBuf_Base). It
;    does not mark any SprBuf_Owner entry, although it overwrites every
;    chunk.
; 2. For each of the 96 tile words at the start of the frame data,
;    copy that 32-byte 4bpp tile into the buffer: Spr_CopyTileFlipped
;    when bit 14 (SprFrame_HFlip) is set, else Spr_CopyTile.
; 3. DMA the $0C00-byte buffer to VRAM word $0400 (channel 7).
; 4. Fill the object's 24 SprTile records: OfsX = sign-extended byte,
;    OfsY = byte, from the position pairs after the tile words; Tile =
;    16x16 tile numbers $40-$4E / $60-$6E / $80-$8E; Attr = $22.
; Earlier notes read the frame data as "scene data" and the position
; bytes as palette groups.
; On entry: X = Obj_Cur (16-bit), M=1, DP=$0100, DB=$00 (absolute
; object-table loads and DMA register stores). Called from
; Field_RestoreState for Field_UnkAEObj.
; Exit: M=1, X/Y 16-bit, DP and DB unchanged.
; ============================================================
org $C0E12A
Spr_LoadLargeObj:
    LDA.w !Obj_GfxBank,X
    STA.b !Spr_GfxPtr+2
    LDA.b #!Bank7F
    STA.b !Spr_WramPtr+2
    REP #$20                ; A → 16-bit
    LDA.w !Obj_GfxOfs,X
    STA.b !Spr_GfxPtr
    SEP #$20                ; A → 8-bit (undone at once: a redundant
    REP #$20                ; pair, kept as in the original)
    LDX.b !Obj_Cur
    LDA.w #!SprBuf_Base
    STA.w !Obj_TileBuf,X
    STA.b !Spr_WramPtr      ; next tile goes here
    SEP #$20                ; A → 8-bit
    LDA #$00
    STA.w !Obj_LastFrame,X
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20                ; A → 16-bit
    LDA.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    ; --- Copy the 96 tiles into the WRAM buffer ---
    SEP #$30                ; A,X,Y → 8-bit (for the 1-byte WMADDH write)
    LDA.b #!WMADDH_Bank7F
    STA.w WMADDH
    REP #$30                ; A,X,Y → 16-bit
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMDATA writes go to $7F:3800
    LDA.w #!SprBuf_Tiles    ; 96 tile words
    STA.b !Spr_TileCount
    LDY #$0000              ; frame-data index
    BRA .first_iter
.next_iter:
    LDA.b !Spr_WramPtr      ; next 32-byte tile
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.first_iter:
    LDA.b [!Spr_FramePtr],Y ; tile word
    BIT.w #!SprFrame_HFlip
    BNE .big_fill
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next_iter
    BRA .dma
.big_fill:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next_iter
    ; --- DMA the buffer to VRAM ---
.dma:
    SEP #$20                ; A → 8-bit
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!Bank7F
    STA.w A1B7
    LDY.w #!SprBuf_VramWord
    STY.w VMADDL
    LDY.w #!SprBuf_Base
    STY.w A1T7L
    LDY.w #!SprBuf_Bytes
    STY.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    ; --- 24 SprTile records: position offsets ---
    REP #$20                ; A → 16-bit
    LDX.b !Obj_Cur
    LDA.w !Obj_TileRecOfs,X
    REP #$10                ; X → 16-bit
    TAX                     ; X = object's first record
    SEP #$20                ; A → 8-bit
    LDY.w #!LargeObj_LayoutOfs ; position bytes follow the tile words
    ; per record: X offset byte (sign-extended to 16 bits), Y offset byte
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .sp01
    LDA.b #!Eng_SignExtNeg
    BRA .se01
.sp01:
    LDA #$00
.se01:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .sp02
    LDA.b #!Eng_SignExtNeg
    BRA .se02
.sp02:
    LDA #$00
.se02:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .sp03
    LDA.b #!Eng_SignExtNeg
    BRA .se03
.sp03:
    LDA #$00
.se03:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .sp04
    LDA.b #!Eng_SignExtNeg
    BRA .se04
.sp04:
    LDA #$00
.se04:
    STA.l SprTile[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsX,X
    BPL .sp05
    LDA.b #!Eng_SignExtNeg
    BRA .se05
.sp05:
    LDA #$00
.se05:
    STA.l SprTile[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsX,X
    BPL .sp06
    LDA.b #!Eng_SignExtNeg
    BRA .se06
.sp06:
    LDA #$00
.se06:
    STA.l SprTile[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsX,X
    BPL .sp07
    LDA.b #!Eng_SignExtNeg
    BRA .se07
.sp07:
    LDA #$00
.se07:
    STA.l SprTile[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsX,X
    BPL .sp08
    LDA.b #!Eng_SignExtNeg
    BRA .se08
.sp08:
    LDA #$00
.se08:
    STA.l SprTile[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsX,X
    BPL .sp09
    LDA.b #!Eng_SignExtNeg
    BRA .se09
.sp09:
    LDA #$00
.se09:
    STA.l SprTile[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsX,X
    BPL .sp10
    LDA.b #!Eng_SignExtNeg
    BRA .se10
.sp10:
    LDA #$00
.se10:
    STA.l SprTile[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsX,X
    BPL .sp11
    LDA.b #!Eng_SignExtNeg
    BRA .se11
.sp11:
    LDA #$00
.se11:
    STA.l SprTile[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsX,X
    BPL .sp12
    LDA.b #!Eng_SignExtNeg
    BRA .se12
.sp12:
    LDA #$00
.se12:
    STA.l SprTile[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[12].OfsX,X
    BPL .sp13
    LDA.b #!Eng_SignExtNeg
    BRA .se13
.sp13:
    LDA #$00
.se13:
    STA.l SprTile[12].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[12].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[13].OfsX,X
    BPL .sp14
    LDA.b #!Eng_SignExtNeg
    BRA .se14
.sp14:
    LDA #$00
.se14:
    STA.l SprTile[13].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[13].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[14].OfsX,X
    BPL .sp15
    LDA.b #!Eng_SignExtNeg
    BRA .se15
.sp15:
    LDA #$00
.se15:
    STA.l SprTile[14].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[14].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[15].OfsX,X
    BPL .sp16
    LDA.b #!Eng_SignExtNeg
    BRA .se16
.sp16:
    LDA #$00
.se16:
    STA.l SprTile[15].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[15].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[16].OfsX,X
    BPL .sp17
    LDA.b #!Eng_SignExtNeg
    BRA .se17
.sp17:
    LDA #$00
.se17:
    STA.l SprTile[16].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[16].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[17].OfsX,X
    BPL .sp18
    LDA.b #!Eng_SignExtNeg
    BRA .se18
.sp18:
    LDA #$00
.se18:
    STA.l SprTile[17].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[17].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[18].OfsX,X
    BPL .sp19
    LDA.b #!Eng_SignExtNeg
    BRA .se19
.sp19:
    LDA #$00
.se19:
    STA.l SprTile[18].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[18].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[19].OfsX,X
    BPL .sp20
    LDA.b #!Eng_SignExtNeg
    BRA .se20
.sp20:
    LDA #$00
.se20:
    STA.l SprTile[19].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[19].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[20].OfsX,X
    BPL .sp21
    LDA.b #!Eng_SignExtNeg
    BRA .se21
.sp21:
    LDA #$00
.se21:
    STA.l SprTile[20].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[20].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[21].OfsX,X
    BPL .sp22
    LDA.b #!Eng_SignExtNeg
    BRA .se22
.sp22:
    LDA #$00
.se22:
    STA.l SprTile[21].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[21].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[22].OfsX,X
    BPL .sp23
    LDA.b #!Eng_SignExtNeg
    BRA .se23
.sp23:
    LDA #$00
.se23:
    STA.l SprTile[22].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[22].OfsY,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[23].OfsX,X
    BPL .sp24
    LDA.b #!Eng_SignExtNeg
    BRA .se24
.sp24:
    LDA #$00
.se24:
    STA.l SprTile[23].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[23].OfsY,X
    ; --- Tile numbers: three rows of eight 16x16 tiles ---
    LDA.b #!LargeObj_TileRow0
    STA.l SprTile.Tile,X
    LDA.b #!LargeObj_TileRow0+2
    STA.l SprTile[1].Tile,X
    LDA.b #!LargeObj_TileRow0+4
    STA.l SprTile[2].Tile,X
    LDA.b #!LargeObj_TileRow0+6
    STA.l SprTile[3].Tile,X
    LDA.b #!LargeObj_TileRow0+8
    STA.l SprTile[4].Tile,X
    LDA.b #!LargeObj_TileRow0+10
    STA.l SprTile[5].Tile,X
    LDA.b #!LargeObj_TileRow0+12
    STA.l SprTile[6].Tile,X
    LDA.b #!LargeObj_TileRow0+14
    STA.l SprTile[7].Tile,X
    LDA.b #!LargeObj_TileRow1
    STA.l SprTile[8].Tile,X
    LDA.b #!LargeObj_TileRow1+2
    STA.l SprTile[9].Tile,X
    LDA.b #!LargeObj_TileRow1+4
    STA.l SprTile[10].Tile,X
    LDA.b #!LargeObj_TileRow1+6
    STA.l SprTile[11].Tile,X
    LDA.b #!LargeObj_TileRow1+8
    STA.l SprTile[12].Tile,X
    LDA.b #!LargeObj_TileRow1+10
    STA.l SprTile[13].Tile,X
    LDA.b #!LargeObj_TileRow1+12
    STA.l SprTile[14].Tile,X
    LDA.b #!LargeObj_TileRow1+14
    STA.l SprTile[15].Tile,X
    LDA.b #!LargeObj_TileRow2
    STA.l SprTile[16].Tile,X
    LDA.b #!LargeObj_TileRow2+2
    STA.l SprTile[17].Tile,X
    LDA.b #!LargeObj_TileRow2+4
    STA.l SprTile[18].Tile,X
    LDA.b #!LargeObj_TileRow2+6
    STA.l SprTile[19].Tile,X
    LDA.b #!LargeObj_TileRow2+8
    STA.l SprTile[20].Tile,X
    LDA.b #!LargeObj_TileRow2+10
    STA.l SprTile[21].Tile,X
    LDA.b #!LargeObj_TileRow2+12
    STA.l SprTile[22].Tile,X
    LDA.b #!LargeObj_TileRow2+14
    STA.l SprTile[23].Tile,X
    ; --- Attributes ---
    LDA.b #!LargeObj_Attr
    STA.l SprTile.Attr,X
    STA.l SprTile[1].Attr,X
    STA.l SprTile[2].Attr,X
    STA.l SprTile[3].Attr,X
    STA.l SprTile[4].Attr,X
    STA.l SprTile[5].Attr,X
    STA.l SprTile[6].Attr,X
    STA.l SprTile[7].Attr,X
    STA.l SprTile[8].Attr,X
    STA.l SprTile[9].Attr,X
    STA.l SprTile[10].Attr,X
    STA.l SprTile[11].Attr,X
    STA.l SprTile[12].Attr,X
    STA.l SprTile[13].Attr,X
    STA.l SprTile[14].Attr,X
    STA.l SprTile[15].Attr,X
    STA.l SprTile[16].Attr,X
    STA.l SprTile[17].Attr,X
    STA.l SprTile[18].Attr,X
    STA.l SprTile[19].Attr,X
    STA.l SprTile[20].Attr,X
    STA.l SprTile[21].Attr,X
    STA.l SprTile[22].Attr,X
    STA.l SprTile[23].Attr,X
    RTS

; ============================================================
; $C0:E534 — Spr_CopyTileFlipped (339 bytes, $C0:E534–$E686)
; (was Sub_E534.) Copies one 32-byte 4bpp tile, mirrored left-right,
; from Spr_GfxPtr + (tile number × 32) to the WRAM tile buffer through
; WMDATA: each byte goes through BitReverseTable ($C0:FD00), which
; mirrors a tile row. (Earlier notes called it a "palette-like lookup
; at bank $FD" and decoded the entry with M=1 as AND #$FF / ORA [$0A];
; the callers run it with M=0, giving AND #$07FF and five ASLs.)
; On entry: M=0, X/Y 16-bit (TAY of tile*32), A = frame-data tile word
; (bit 14 set), Y = frame-data index, WMADD already at the destination,
; DP=$0100 (Spr_GfxPtr, Spr_SavedY are dp), DB=$00.
; Returns with M=0 and Y restored from Spr_SavedY; X clobbered.
; ============================================================
org $C0E534
Spr_CopyTileFlipped:
    AND.w #!SprFrame_TileMask ; tile number
    ASL
    ASL
    ASL
    ASL
    ASL                     ; × 32: byte offset of the 4bpp tile
    STY.b !Spr_SavedY
    TAY                     ; Y = tile's byte offset
    SEP #$20                ; A → 8-bit
    TDC                     ; C = D = $0100
    XBA                     ; B = 0 for the TAX below
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA
    INY
    LDA.b [!Spr_GfxPtr],Y
    TAX
    LDA.w BitReverseTable,X
    STA.w WMDATA            ; last byte: no INY
    REP #$20                ; A → 16-bit
    LDY.b !Spr_SavedY
    RTS

; ============================================================
; $C0:E687 — Spr_CopyTile (178 bytes, $C0:E687–$E738)
; (was Sub_E687.) Copies one 32-byte 4bpp tile from Spr_GfxPtr +
; (tile number × 32) to Spr_WramPtr in bank $7F, then moves WMADD
; past it so a following Spr_CopyTileFlipped writes the next tile.
; The source bank (Spr_GfxPtr+2) picks the copier: $7F → Spr_CopyTile7F,
; $D2/$D3/$D4 → Spr_CopyTileD2/D3/D4, anything else → bank $D5 below.
; Each copier is an unrolled 16-word move with DB = $7F, X = source
; offset and Y = destination address.
; On entry: M=0, X/Y 16-bit (TAX of the source offset, LDY of the
; destination), A = frame-data tile word (bit 14 clear), Y = frame-data
; index, DP=$0100 (Spr_GfxPtr, Spr_WramPtr, Spr_SavedY are dp), DB=$00
; (the WMADDL store after the PLB).
; Returns with M=0, Y restored from Spr_SavedY, X clobbered, WMADD just
; past the copied tile; the four bank copiers below end the same way.
; ============================================================
org $C0E687
Spr_CopyTile:
    AND.w #!SprFrame_TileMask
    ASL
    ASL
    ASL
    ASL
    ASL                     ; × 32: byte offset of the tile
    STY.b !Spr_SavedY
    CLC
    ADC.b !Spr_GfxPtr       ; X = source offset in its bank
    TAX
    LDY.b !Spr_WramPtr      ; Y = destination in bank $7F
    SEP #$20                ; A → 8-bit
    LDA.b !Spr_GfxPtr+2     ; source bank
    CMP.b #!Bank7F
    BNE .not7f
    BRL Spr_CopyTile7F
.not7f:
    SEC
    SBC.b #!BankD2
    BNE .notd2
    BRL Spr_CopyTileD2
.notd2:
    DEC
    BNE .notd3
    BRL Spr_CopyTileD3
.notd3:
    DEC
    BNE .d5copy
    BRL Spr_CopyTileD4
.d5copy:                    ; $D5 (or any other bank): read bank $D5
    PHB
    LDA.b #!Bank7F          ; (M=1 after SEP above)
    PHA
    PLB                     ; DB = $7F
    REP #$20                ; A → 16-bit
    LDA.l !GfxRom_D5,X
    STA.w !Wram7F_PtrBase,Y
    LDA.l !GfxRom_D5+2,X
    STA.w !Wram7F_PtrBase+2,Y
    LDA.l !GfxRom_D5+4,X
    STA.w !Wram7F_PtrBase+4,Y
    LDA.l !GfxRom_D5+6,X
    STA.w !Wram7F_PtrBase+6,Y
    LDA.l !GfxRom_D5+8,X
    STA.w !Wram7F_PtrBase+8,Y
    LDA.l !GfxRom_D5+10,X
    STA.w !Wram7F_PtrBase+10,Y
    LDA.l !GfxRom_D5+12,X
    STA.w !Wram7F_PtrBase+12,Y
    LDA.l !GfxRom_D5+14,X
    STA.w !Wram7F_PtrBase+14,Y
    LDA.l !GfxRom_D5+16,X
    STA.w !Wram7F_PtrBase+16,Y
    LDA.l !GfxRom_D5+18,X
    STA.w !Wram7F_PtrBase+18,Y
    LDA.l !GfxRom_D5+20,X
    STA.w !Wram7F_PtrBase+20,Y
    LDA.l !GfxRom_D5+22,X
    STA.w !Wram7F_PtrBase+22,Y
    LDA.l !GfxRom_D5+24,X
    STA.w !Wram7F_PtrBase+24,Y
    LDA.l !GfxRom_D5+26,X
    STA.w !Wram7F_PtrBase+26,Y
    LDA.l !GfxRom_D5+28,X
    STA.w !Wram7F_PtrBase+28,Y
    LDA.l !GfxRom_D5+30,X
    STA.w !Wram7F_PtrBase+30,Y
    PLB
    TYA
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.w WMADDL            ; WMADD = just past the copied tile
    LDY.b !Spr_SavedY
    RTS

; ============================================================
; $C0:E739 — Spr_CopyTileD4 (131 bytes, $C0:E739–$E7BB)
; Copies a 32-byte tile from GfxRom_D4+X to $7F:Y (BRL from
; Spr_CopyTile when the graphics are in bank $D4).
; Entry and exit state as Spr_CopyTile (exit: M=0, Y = Spr_SavedY,
; WMADD past the tile).
; ============================================================
org $C0E739
Spr_CopyTileD4:
    PHB
    LDA.b #!Bank7F          ; M=1 here (set before the BRL in Spr_CopyTile)
    PHA
    PLB                     ; DB = $7F
    REP #$20                ; A → 16-bit
    LDA.l !GfxRom_D4,X
    STA.w !Wram7F_PtrBase,Y
    LDA.l !GfxRom_D4+2,X
    STA.w !Wram7F_PtrBase+2,Y
    LDA.l !GfxRom_D4+4,X
    STA.w !Wram7F_PtrBase+4,Y
    LDA.l !GfxRom_D4+6,X
    STA.w !Wram7F_PtrBase+6,Y
    LDA.l !GfxRom_D4+8,X
    STA.w !Wram7F_PtrBase+8,Y
    LDA.l !GfxRom_D4+10,X
    STA.w !Wram7F_PtrBase+10,Y
    LDA.l !GfxRom_D4+12,X
    STA.w !Wram7F_PtrBase+12,Y
    LDA.l !GfxRom_D4+14,X
    STA.w !Wram7F_PtrBase+14,Y
    LDA.l !GfxRom_D4+16,X
    STA.w !Wram7F_PtrBase+16,Y
    LDA.l !GfxRom_D4+18,X
    STA.w !Wram7F_PtrBase+18,Y
    LDA.l !GfxRom_D4+20,X
    STA.w !Wram7F_PtrBase+20,Y
    LDA.l !GfxRom_D4+22,X
    STA.w !Wram7F_PtrBase+22,Y
    LDA.l !GfxRom_D4+24,X
    STA.w !Wram7F_PtrBase+24,Y
    LDA.l !GfxRom_D4+26,X
    STA.w !Wram7F_PtrBase+26,Y
    LDA.l !GfxRom_D4+28,X
    STA.w !Wram7F_PtrBase+28,Y
    LDA.l !GfxRom_D4+30,X
    STA.w !Wram7F_PtrBase+30,Y
    PLB
    TYA
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.w WMADDL            ; WMADD = just past the copied tile
    LDY.b !Spr_SavedY
    RTS

; ============================================================
; $C0:E7BC — Spr_CopyTileD2 (131 bytes, $C0:E7BC–$E83E)
; Copies a 32-byte tile from GfxRom_D2+X to $7F:Y (BRL from
; Spr_CopyTile when the graphics are in bank $D2).
; Entry and exit state as Spr_CopyTile (exit: M=0, Y = Spr_SavedY,
; WMADD past the tile).
; ============================================================
org $C0E7BC
Spr_CopyTileD2:
    PHB
    LDA.b #!Bank7F          ; M=1 here (set before the BRL in Spr_CopyTile)
    PHA
    PLB                     ; DB = $7F
    REP #$20
    LDA.l !GfxRom_D2,X
    STA.w !Wram7F_PtrBase,Y
    LDA.l !GfxRom_D2+2,X
    STA.w !Wram7F_PtrBase+2,Y
    LDA.l !GfxRom_D2+4,X
    STA.w !Wram7F_PtrBase+4,Y
    LDA.l !GfxRom_D2+6,X
    STA.w !Wram7F_PtrBase+6,Y
    LDA.l !GfxRom_D2+8,X
    STA.w !Wram7F_PtrBase+8,Y
    LDA.l !GfxRom_D2+10,X
    STA.w !Wram7F_PtrBase+10,Y
    LDA.l !GfxRom_D2+12,X
    STA.w !Wram7F_PtrBase+12,Y
    LDA.l !GfxRom_D2+14,X
    STA.w !Wram7F_PtrBase+14,Y
    LDA.l !GfxRom_D2+16,X
    STA.w !Wram7F_PtrBase+16,Y
    LDA.l !GfxRom_D2+18,X
    STA.w !Wram7F_PtrBase+18,Y
    LDA.l !GfxRom_D2+20,X
    STA.w !Wram7F_PtrBase+20,Y
    LDA.l !GfxRom_D2+22,X
    STA.w !Wram7F_PtrBase+22,Y
    LDA.l !GfxRom_D2+24,X
    STA.w !Wram7F_PtrBase+24,Y
    LDA.l !GfxRom_D2+26,X
    STA.w !Wram7F_PtrBase+26,Y
    LDA.l !GfxRom_D2+28,X
    STA.w !Wram7F_PtrBase+28,Y
    LDA.l !GfxRom_D2+30,X
    STA.w !Wram7F_PtrBase+30,Y
    PLB
    TYA
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.w WMADDL
    LDY.b !Spr_SavedY
    RTS

; ============================================================
; $C0:E83F — Spr_CopyTileD3 (131 bytes, $C0:E83F–$E8C1)
; Copies a 32-byte tile from GfxRom_D3+X to $7F:Y (BRL from
; Spr_CopyTile when the graphics are in bank $D3).
; Entry and exit state as Spr_CopyTile (exit: M=0, Y = Spr_SavedY,
; WMADD past the tile).
; ============================================================
org $C0E83F
Spr_CopyTileD3:
    PHB
    LDA.b #!Bank7F          ; M=1 here (set before the BRL in Spr_CopyTile)
    PHA
    PLB                     ; DB = $7F
    REP #$20
    LDA.l !GfxRom_D3,X
    STA.w !Wram7F_PtrBase,Y
    LDA.l !GfxRom_D3+2,X
    STA.w !Wram7F_PtrBase+2,Y
    LDA.l !GfxRom_D3+4,X
    STA.w !Wram7F_PtrBase+4,Y
    LDA.l !GfxRom_D3+6,X
    STA.w !Wram7F_PtrBase+6,Y
    LDA.l !GfxRom_D3+8,X
    STA.w !Wram7F_PtrBase+8,Y
    LDA.l !GfxRom_D3+10,X
    STA.w !Wram7F_PtrBase+10,Y
    LDA.l !GfxRom_D3+12,X
    STA.w !Wram7F_PtrBase+12,Y
    LDA.l !GfxRom_D3+14,X
    STA.w !Wram7F_PtrBase+14,Y
    LDA.l !GfxRom_D3+16,X
    STA.w !Wram7F_PtrBase+16,Y
    LDA.l !GfxRom_D3+18,X
    STA.w !Wram7F_PtrBase+18,Y
    LDA.l !GfxRom_D3+20,X
    STA.w !Wram7F_PtrBase+20,Y
    LDA.l !GfxRom_D3+22,X
    STA.w !Wram7F_PtrBase+22,Y
    LDA.l !GfxRom_D3+24,X
    STA.w !Wram7F_PtrBase+24,Y
    LDA.l !GfxRom_D3+26,X
    STA.w !Wram7F_PtrBase+26,Y
    LDA.l !GfxRom_D3+28,X
    STA.w !Wram7F_PtrBase+28,Y
    LDA.l !GfxRom_D3+30,X
    STA.w !Wram7F_PtrBase+30,Y
    PLB
    TYA
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.w WMADDL
    LDY.b !Spr_SavedY
    RTS

; ============================================================
; $C0:E8C2 — Spr_CopyTile7F (115 bytes, $C0:E8C2–$E934)
; Copies a 32-byte tile from $7F:X to $7F:Y (BRL from Spr_CopyTile when
; the graphics are already in WRAM); abs,X reads since DB = $7F.
; Entry and exit state as Spr_CopyTile (exit: M=0, Y = Spr_SavedY,
; WMADD past the tile).
; ============================================================
org $C0E8C2
Spr_CopyTile7F:
    PHB
    LDA.b #!Bank7F          ; M=1 here (set before the BRL in Spr_CopyTile)
    PHA
    PLB                     ; DB = $7F
    REP #$20
    LDA.w !Wram7F_PtrBase,X ; DB = $7F
    STA.w !Wram7F_PtrBase,Y
    LDA.w !Wram7F_PtrBase+2,X
    STA.w !Wram7F_PtrBase+2,Y
    LDA.w !Wram7F_PtrBase+4,X
    STA.w !Wram7F_PtrBase+4,Y
    LDA.w !Wram7F_PtrBase+6,X
    STA.w !Wram7F_PtrBase+6,Y
    LDA.w !Wram7F_PtrBase+8,X
    STA.w !Wram7F_PtrBase+8,Y
    LDA.w !Wram7F_PtrBase+10,X
    STA.w !Wram7F_PtrBase+10,Y
    LDA.w !Wram7F_PtrBase+12,X
    STA.w !Wram7F_PtrBase+12,Y
    LDA.w !Wram7F_PtrBase+14,X
    STA.w !Wram7F_PtrBase+14,Y
    LDA.w !Wram7F_PtrBase+16,X
    STA.w !Wram7F_PtrBase+16,Y
    LDA.w !Wram7F_PtrBase+18,X
    STA.w !Wram7F_PtrBase+18,Y
    LDA.w !Wram7F_PtrBase+20,X
    STA.w !Wram7F_PtrBase+20,Y
    LDA.w !Wram7F_PtrBase+22,X
    STA.w !Wram7F_PtrBase+22,Y
    LDA.w !Wram7F_PtrBase+24,X
    STA.w !Wram7F_PtrBase+24,Y
    LDA.w !Wram7F_PtrBase+26,X
    STA.w !Wram7F_PtrBase+26,Y
    LDA.w !Wram7F_PtrBase+28,X
    STA.w !Wram7F_PtrBase+28,Y
    LDA.w !Wram7F_PtrBase+30,X
    STA.w !Wram7F_PtrBase+30,Y
    PLB
    TYA
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.w WMADDL
    LDY.b !Spr_SavedY
    RTS

; ============================================================
; $C0:E935 — SprBuf_FreeAll (29 bytes, $E935–$E951)
; (was Sub_E935.) Marks all eight SprBuf_Owner entries free ($80),
; with DP pointed at $0B00 so each store is a 2-byte dp store.
; Reached by BRL from Obj_ResetStates and called after a battle by
; DefaultHandler; those are its only direct callers.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DB=$00. DP is saved and
; restored. Exit: same.
; ============================================================
org $C0E935
SprBuf_FreeAll:
    PHD
    REP #$20                ; A → 16-bit
    LDA.w #!DP_SprBufPage
    TCD                     ; DP = $0B00
    SEP #$20                ; A → 8-bit
    LDA.b #!Obj_None        ; free
    STA.b !SprBuf_Owner-!DP_SprBufPage
    STA.b !SprBuf_Owner+1-!DP_SprBufPage
    STA.b !SprBuf_Owner+2-!DP_SprBufPage
    STA.b !SprBuf_Owner+3-!DP_SprBufPage
    STA.b !SprBuf_Owner+4-!DP_SprBufPage
    STA.b !SprBuf_Owner+5-!DP_SprBufPage
    STA.b !SprBuf_Owner+6-!DP_SprBufPage
    STA.b !SprBuf_Owner+7-!DP_SprBufPage
    PLD
    RTS

; ============================================================
; $C0:E952 — SprBuf_Alloc1 (40 bytes, $E952–$E979)
; (was Sub_E952.) Gives object Obj_Cur one $200-byte chunk of the
; WRAM tile buffer: the first free entry n (0-3) of SprBuf_Owner gets
; Obj_Cur, and Obj_TileBuf = SprBuf_Base + n*$200.
; Returns C=1 on success, with X = Obj_Cur (Obj_BuildFrame4 relies on
; it), C=0 when all four are taken.
; On entry: M=1 (8-bit A), X/Y 8-bit, DP=$0100. Called from Obj_BuildFrame4.
; ============================================================
org $C0E952
SprBuf_Alloc1:
    LDX #$00
.e952_loop:
    LDA.w !SprBuf_Owner,X
    BPL .e952_next
    LDA.b !Obj_Cur
    STA.w !SprBuf_Owner,X
    TXA
    XBA
    REP #$20             ; A → 16-bit
    AND.w #!Eng_HighByteMask
    ASL                  ; entry × $200
    CLC
    ADC.w #!SprBuf_Base  ; chunk address
    LDX.b !Obj_Cur
    STA.w !Obj_TileBuf,X
    SEP #$20             ; A → 8-bit
    SEC                  ; success
    RTS
.e952_next:
    INX
    CPX #$04
    BMI .e952_loop       ; loop for entries 0–3
    CLC                  ; all taken
    RTS

; ============================================================
; $C0:E97A — SprBuf_Alloc2 (48 bytes, $E97A–$E9A9)
; (was Sub_E97A.) As SprBuf_Alloc1 for two adjacent free chunks
; (start entries 0-2). Called from Obj_BuildFrame8 and Obj_BuildFrame8Pass0.
; ============================================================
org $C0E97A
SprBuf_Alloc2:
    LDX #$00
.e97a_loop:
    LDA.w !SprBuf_Owner,X
    BPL .e97a_next
    LDA.w !SprBuf_Owner+1,X
    BPL .e97a_next
    LDA.b !Obj_Cur
    STA.w !SprBuf_Owner,X
    STA.w !SprBuf_Owner+1,X
    TXA
    XBA
    REP #$20
    AND.w #!Eng_HighByteMask
    ASL
    CLC
    ADC.w #!SprBuf_Base
    LDX.b !Obj_Cur
    STA.w !Obj_TileBuf,X
    SEP #$20
    SEC
    RTS
.e97a_next:
    INX
    CPX #$03             ; search entries 0–2 (3 positions)
    BMI .e97a_loop
    CLC
    RTS

; ============================================================
; $C0:E9AA — SprBuf_Alloc3 (56 bytes, $E9AA–$E9E1)
; (was Sub_E9AA.) As SprBuf_Alloc1 for three adjacent free chunks
; (start entries 0-1). Called from Obj_BuildFrame12Pass0 and Obj_BuildFrame12Pass0Alt.
; ============================================================
org $C0E9AA
SprBuf_Alloc3:
    LDX #$00
.e9aa_loop:
    LDA.w !SprBuf_Owner,X
    BPL .e9aa_next
    LDA.w !SprBuf_Owner+1,X
    BPL .e9aa_next
    LDA.w !SprBuf_Owner+2,X
    BPL .e9aa_next
    LDA.b !Obj_Cur
    STA.w !SprBuf_Owner,X
    STA.w !SprBuf_Owner+1,X
    STA.w !SprBuf_Owner+2,X
    TXA
    XBA
    REP #$20
    AND.w #!Eng_HighByteMask
    ASL
    CLC
    ADC.w #!SprBuf_Base
    LDX.b !Obj_Cur
    STA.w !Obj_TileBuf,X
    SEP #$20
    SEC
    RTS
.e9aa_next:
    INX
    CPX #$02             ; only entries 0–1 for triple allocation
    BMI .e9aa_loop
    CLC
    RTS

; ============================================================
; $C0:E9E2 — SprBuf_Free1 (29 bytes, $E9E2–$E9FE)
; (was Sub_E9E2.) Releases the SprBuf chunk owned by Obj_Cur: finds it
; among the first 4 SprBuf_Owner entries and marks it free. Run by
; Spr_PrepareTiles after Spr_Load4, once the object's tiles are in VRAM.
; On entry: M=1, X/Y 16-bit, DP=$0100 (Obj_Cur is dp), DB=$00.
; Exit: M=1, X/Y 16-bit (set again on both paths).
; Quirk: the LDX.b !Obj_Cur is dead, overwritten by LDX #$00 at once
; (kept as in the original; SprBuf_Free2/3 have it too).
; ============================================================
org $C0E9E2
SprBuf_Free1:
    SEP #$10                ; X → 8-bit
    LDX.b !Obj_Cur          ; dead: overwritten by the next load
    LDX #$00
.loop:
    LDA.w !SprBuf_Owner,X
    CMP.b !Obj_Cur
    BEQ .found
    INX
    CPX #$04                ; entries 0-3
    BNE .loop
    REP #$10
    RTS
.found:
    LDA.b #!Obj_None
    STA.w !SprBuf_Owner,X
    REP #$10
    RTS

; ============================================================
; $C0:E9FF — SprBuf_Free2 (32 bytes, $E9FF–$EA1E)
; (was Sub_E9FF.) As SprBuf_Free1 for a 2-chunk object: the first of
; the 3 possible start entries owned by Obj_Cur and the one after it
; are freed. Run by Spr_PrepareTiles after Spr_Load8.
; On entry: M=1, X/Y 16-bit, DP=$0100 (Obj_Cur is dp), DB=$00.
; Exit: M=1, X/Y 16-bit. Same dead LDX.b !Obj_Cur as SprBuf_Free1.
; ============================================================
org $C0E9FF
SprBuf_Free2:
    SEP #$10                ; X → 8-bit
    LDX.b !Obj_Cur          ; dead: overwritten by the next load
    LDX #$00
.loop:
    LDA.w !SprBuf_Owner,X
    CMP.b !Obj_Cur
    BEQ .found
    INX
    CPX #$03                ; start entries 0-2
    BNE .loop
    REP #$10
    RTS
.found:
    LDA.b #!Obj_None
    STA.w !SprBuf_Owner,X
    STA.w !SprBuf_Owner+1,X
    REP #$10
    RTS

org $C0EA1F
SprBuf_Free3:
    ; (was Sub_EA1F.) 35 bytes ($EA1F–$EA41). As SprBuf_Free1 for a
    ; 3-chunk object (2 possible start entries). Run after Spr_Load12.
    SEP #$10                ; X → 8-bit
    LDX.b !Obj_Cur          ; (discarded; immediately overwritten)
    LDX #$00
.ea1f_loop:
    LDA.w !SprBuf_Owner,X
    CMP.b !Obj_Cur
    BEQ .ea1f_found
    INX
    CPX #$02                ; start entries 0-1
    BNE .ea1f_loop
    REP #$10                ; X → 16-bit (no match)
    RTS
.ea1f_found:
    LDA.b #!Obj_None
    STA.w !SprBuf_Owner,X   ; free all three chunks
    STA.w !SprBuf_Owner+1,X
    STA.w !SprBuf_Owner+2,X
    REP #$10                ; X → 16-bit
    RTS

; ============================================================
; $C0:0000 — ReentryVectors (14 bytes)
; Mid-game JSL re-entry vector table.  Other banks JSL into one of
; these entries; the BRA/BRL tail-dispatches to the target routine,
; and its RTL returns directly to the JSL caller.
;   [0] $0000  BRA → GameLoop_Main  (warm restart; no RTL return)
;   [1] $0002  JSL → ScrollStepAccum  ($C0:2C41)
;   [2] $0005  JSL → AudioDrvSync     ($C0:0AFF)
;   [3] $0008  JSL → MusicCueDispatch ($C0:1BAB)
;   [4] $000B  JSL → AudioFadeDispatch($C0:1BE6)
; ============================================================
org $C00000

ReentryVectors:
    BRA GameLoop_Main       ; [0] warm restart — skip init, enter frame loop
    BRL ScrollStepAccum     ; [1] $C0:2C41
    BRL AudioDrvSync        ; [2] $C0:0AFF
    BRL MusicCueDispatch    ; [3] $C0:1BAB
    BRL AudioFadeDispatch   ; [4] $C0:1BE6

; ============================================================
; $C0:000E — GameLoop: one-time startup init (from MainInit)
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$2100, DB=$00
; ============================================================
GameLoop:
    SEP #$20                ; M=1: A → 8-bit (safety)
    REP #$10                ; X=0: X/Y → 16-bit

    ; Install RAM-resident interrupt handlers first — they live at
    ; $7E:0500/$7E:0504, which are deliberately NOT cleared below.
    JSR InstallNMI          ; JML NmiHandler at $7E:0500
    JSR InstallIRQ          ; JML IrqHandler at $7E:0504

    REP #$20                ; A → 16-bit for TCD
    LDA.w #!DP_Field
    TCD                     ; DP = $0100 (WRAM variable page)
    SEP #$20                ; A → 8-bit

    JSR InitHW              ; disable hardware (SEI, forced blank, no NMI/DMA)

    ; Clear WRAM block 1: $7E:0000-04FF (1280 bytes, stops before handlers)
    LDX.w #!Boot_ClearLowSize
    STX.b !DmaFill_Size
    LDX #$0000
    STX.b !DmaFill_Dest
    LDA.b #!Bank7E
    STA.b !DmaFill_Bank
    JSR ClearRAMDMA         ; DMA fill with 0

    ; Clear WRAM block 2: $7E:0700-FFFF (59648 bytes)
    LDX.w #!Boot_ClearMainSize
    STX.b !DmaFill_Size
    LDX.w #!Boot_ClearMainStart
    STX.b !DmaFill_Dest
    LDA.b #!Bank7E
    STA.b !DmaFill_Bank
    JSR ClearRAMDMA

    ; Clear WRAM block 3: $7F:5080-A0FF (20608 bytes)
    LDX.w #!Boot_Clear7FStart
    STX.b !DmaFill_Size
    STX.b !DmaFill_Dest     ; count == dest addr (both $5080)
    LDA.b #!Bank7F
    STA.b !DmaFill_Bank
    JSR ClearRAMDMA

    JSL Audio_DriverInit    ; sound driver init (bank $C7)
    LDA.b #!BankC2_BootArg
    JSL BankC2_Entry8004

; GameLoop_Main ($C0:005D): warm-restart entry. Reached by falling out
; of GameLoop, by ReentryVectors[0] (JSL $C0:0000 from other banks) and
; by Field_SceneChangeTick's warp (BRL ReentryVectors after resetting the
; stack). Reinstalls the interrupt trampolines and dispatches on Loc_Id.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y). DB is set to $00 by
; InitHW. DP is not known here (DP=$0100 when falling out of GameLoop,
; anything on a JSL from another bank), so Loc_Id is read as the
; absolute address !DP_Field+!Loc_Id; GameLoop_LoadField sets DP=$0100.
GameLoop_Main:
    JSR InitHW              ; forced blank, disable NMI/DMA
    JSR InstallNMI          ; reinstall NMI handler
    JSR InstallIRQ          ; reinstall IRQ handler

    ; Dispatch on the location index (Loc_Id, WRAM $0100, 16-bit)
    LDX.w !DP_Field+!Loc_Id
    CPX.w #!Loc_FirstBankC2
    BMI GameLoop_NotBankC2
    JML BankC2_Entry0000    ; Loc_Id >= $01F0 → handled in bank $C2

; GameLoop_NotBankC2 (was GL_ModeOk1): the path for Loc_Id below
; Loc_FirstBankC2. Both tests here and above are BMI on X minus the
; limit, i.e. signed compares; Loc_Id >= Loc_LoadSave goes to
; LoadSavePath with X = LoadSave_EntryX.
GameLoop_NotBankC2:
    CPX.w #!Loc_LoadSave
    BMI GameLoop_LoadField
    LDX.w #!LoadSave_EntryX
    BRL LoadSavePath

; GameLoop_LoadField (was GL_ModeOk2): loads the field location Loc_Id
; and falls into the per-frame loop.
GameLoop_LoadField:
    REP #$20
    LDA.w #!DP_Field
    TCD                     ; DP = $0100
    SEP #$20

    JSR Field_InitLoadState ; reset the field page for this location
    JSR LoadLocation        ; location-load steps (10 JSR + 2 JSL)
    JSR Obj_ResetStates     ; clear Obj_State, then SprBuf_FreeAll
    JSR Scene_PostLoadInit
    JSR TileAnimList_Clear
    JSR Scene_SettleFrames  ; run frames until the new scene reports ready

GameLoop_FrameBody:
    LDA.w !Pad_Pressed
    TSB.b !Pad_PressedLatch ; accumulate newly pressed buttons
    LDA.w !Pad_Unk00F6
    TSB.b !Pad_Unk00F6Latch ; accumulate Pad_Unk00F6
    JSR Field_PauseAndMenuInput
    JSR Field_SceneChangeTick
    JSR Field_FrameUpdate
    JSR Field_Unk1AAC
    JSL Field_Unk1F87
    JSR Field_EventHookDispatch
    JSR Field_Unk274D
    JSR Field_EndOfFrame    ; end-of-frame work and OAM shadow build
    JSR Sub_EC60            ; wait for the NMI (the frame wait)
    BRA GameLoop_FrameBody

; ============================================================
; $C0:00BF — Field_EndOfFrame (was VBlankHandler)
; End-of-frame work, called once per frame from GameLoop_FrameBody just
; before Sub_EC60 waits for the NMI; it is not an interrupt handler
; and waits for nothing itself. Runs the Vblank_* helpers,
; EngFD_UnkC2C1, FdVec_FFF7 (ticks the counter table at $0520),
; Field_ProcessAnimQueue, then tail-jumps to Oam_BuildShadow, whose RTS
; returns to this routine's caller.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit (from Oam_BuildShadow): M=1, X=0, DP and DB unchanged.
; ============================================================
Field_EndOfFrame:
    SEP #$10                ; X/Y → 8-bit
    JSR Vblank_Unk59D9
    JSR Vblank_ReadScanlineCounters
    JSL EngFD_UnkC2C1
    REP #$10                ; X/Y → 16-bit
    JSL FdVec_FFF7
    SEP #$10
    JSR Vblank_UnkA810
    JSR Field_ProcessAnimQueue
    REP #$10
    BRL Oam_BuildShadow-!BankWrap ; offset wraps around the bank to $B271

; Field_EndOfFrameShort (was VBlankHandlerShort): the EngFD_UnkC2C1 +
; FdVec_FFF7 part of Field_EndOfFrame only, for the fade and idle loops
; (Field_IdleFrame, Field_FadeInAfterReload, DefaultHandler).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100. Sets 8-bit X/Y
; around EngFD_UnkC2C1, which needs it; exit M=1, X=0.
Field_EndOfFrameShort:
    SEP #$10
    JSL EngFD_UnkC2C1
    REP #$10
    JSL FdVec_FFF7
    RTS

; Field_IdleFrame (was Sub_00EB): one frame of field upkeep without
; game logic: Field_FrameUpdate, Field_EndOfFrameShort, Sub_EC60.
Field_IdleFrame:
    JSR Field_FrameUpdate
    JSR Field_EndOfFrameShort
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

; ============================================================
; $C0:00F4 — LoadLocation (39 bytes, $00F4–$011A)
; One-time location-load called once per scene entry from GameLoop_Main.
; Calls 10 location-load steps (JSR) and two bank-$FD service vectors.
; NOT called per frame — only when entering a new location/map.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
LoadLocation:
    JSR LocLoad_Unk092B
    JSR LocLoad_AudioSetup
    JSR LocLoad_Unk0960
    JSR LocLoad_Unk6DCF
    JSR LocLoad_Unk7084
    JSR LocLoad_ClearPage1D00
    JSR LocLoad_UnkA33B
    JSR LocLoad_Unk09DD
    JSR LocLoad_Unk0A14
    JSR LocLoad_Unk56D4
    JSL FdVec_FFFA
    JSL FdVec_FFF4
    RTS

; ============================================================
; $C0:011B — Field_SaveState (138 bytes, $011B–$01A4)
; (was Sub_011B.) Saves the field before handing control to bank $C2
; (BankC2_Entry8000), so Field_RestoreState can rebuild it after:
;   - if Field_Unk29 is set, force it to 1 and clear Field_Unk26/27;
;   - copy Field_SaveBlock to SceneSave_Buffer (Field_StashSaveBlock);
;   - the leader's tile X/Y and facing become the entry point
;     (Loc_EntryX/Y/Facing);
;   - each party member's Obj_PosX, Obj_PosY and Obj_PrioLow word
;     (16-bit, so Obj_PrioHigh too) → SceneSave_Party*;
;   - Field_UnkAB-AD → SceneSave_UnkAB, the four words Map_Unk7F3728,
;     Map_Unk7F3748, Map_Unk7F3768, Map_Unk7F3781 → SceneSave_MapWords,
;     Field_Unk1DF9 → SceneSave_Unk1DF9.
; Called from Field_SceneChangeTick, Field_PauseAndMenuInput and
; Field_FadeToBankC2Mode5.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C0011B
Field_SaveState:
    LDA.b !Field_Unk29
    BEQ .call_mvn
    LDA #$01
    STA.b !Field_Unk29
    LDA #$00
    STA.b !Field_Unk26
    STZ.b !Field_Unk27
.call_mvn:
    JSR Field_StashSaveBlock ; Field_SaveBlock → SceneSave_Buffer
    LDY.b !Party_ObjSlot    ; leader's object (16-bit)
    LDA.w !Obj_TileX,Y
    STA.b !Loc_EntryX
    LDA.w !Obj_TileY,Y
    STA.b !Loc_EntryY
    LDA.w !Obj_Facing,Y
    STA.b !Loc_EntryFacing
    LDX #$0000              ; party member x 2
.slot_loop:
    TDC                     ; C = D = $0100
    XBA                     ; B = 0 for the TAY below
    LDA.b !Party_ObjSlot,X
    BMI .next_slot          ; Obj_None
    TAY                     ; Y = member's object
    REP #$20                ; A → 16-bit
    LDA.w !Obj_PosX,Y
    STA.l !SceneSave_PartyPosX,X
    LDA.w !Obj_PosY,Y
    STA.l !SceneSave_PartyPosY,X
    LDA.w !Obj_PrioLow,Y
    STA.l !SceneSave_PartyPrio,X
    SEP #$20                ; A → 8-bit
.next_slot:
    INX
    INX                     ; next member
    CPX #$0006              ; 3 members
    BNE .slot_loop
    LDA.b !Field_UnkAB
    STA.l !SceneSave_UnkAB
    LDA.b !Field_UnkAC
    STA.l !SceneSave_UnkAB+1
    LDA.b !Field_UnkAD
    STA.l !SceneSave_UnkAB+2
    REP #$20                ; A → 16-bit
    LDA.l !Map_Unk7F3728
    STA.l !SceneSave_MapWords
    LDA.l !Map_Unk7F3748
    STA.l !SceneSave_MapWords+2
    LDA.l !Map_Unk7F3768
    STA.l !SceneSave_MapWords+4
    LDA.l !Map_Unk7F3781
    STA.l !SceneSave_MapWords+6
    SEP #$20                ; A → 8-bit
    LDA.w !Field_Unk1DF9
    STA.l !SceneSave_Unk1DF9
    RTS

; ============================================================
; $C0:01A5 — Field_RestoreState (167 bytes, $01A5–$024B)
; (was Sub_01A5.) Rebuilds the field after a bank-$C2 round trip:
; 1. Field_RestoreSaveBlock (SceneSave_Buffer → Field_SaveBlock).
; 2. EngFD_UnkC2C1 (8-bit X), Hdma_InitChannelsFD.
; 3. Previous-frame OAM range ends = full limits.
; 4. Re-run eight location-load steps (LoadLocation's list without
;    LocLoad_Unk092B / LocLoad_AudioSetup).
; 5. Restore Map_Unk7F3728/3748/3768/3781 and Field_Unk1DF9 from
;    SceneSave_*.
; 6. Evt_RunObj0Func1.
; 7. If Field_UnkAEObj names an object, run Spr_LoadLargeObj on it.
; 8. If Field_Unk7F03FE is 1 or 2: put party members 2 and 3 on the
;    leader's position, enable control, set Field_Unk7F03FE = 3.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C001A5
Field_RestoreState:
    JSR Field_RestoreSaveBlock ; SceneSave_Buffer → Field_SaveBlock
    SEP #$10                ; X,Y → 8-bit
    JSL EngFD_UnkC2C1
    REP #$10                ; X,Y → 16-bit
    JSL Hdma_InitChannelsFD
    LDX.w #!Oam_Range2Limit
    STX.b !Oam_Range2PrevEnd
    LDX.w #!Oam_Range3Limit
    STX.b !Oam_Range3PrevEnd
    LDX.w #!Oam_Range1Limit
    STX.b !Oam_Range1PrevEnd
    JSR LocLoad_Unk0960
    JSR LocLoad_Unk6DCF
    JSR LocLoad_Unk7084
    JSR LocLoad_ClearPage1D00
    JSR LocLoad_UnkA33B
    JSR LocLoad_Unk09DD
    JSR LocLoad_Unk0A14
    JSR LocLoad_Unk56D4
    REP #$20                ; A → 16-bit
    LDA.l !SceneSave_MapWords
    STA.l !Map_Unk7F3728
    LDA.l !SceneSave_MapWords+2
    STA.l !Map_Unk7F3748
    LDA.l !SceneSave_MapWords+4
    STA.l !Map_Unk7F3768
    LDA.l !SceneSave_MapWords+6
    STA.l !Map_Unk7F3781
    SEP #$20                ; A → 8-bit
    LDA.l !SceneSave_Unk1DF9
    STA.w !Field_Unk1DF9
    JSR Evt_RunObj0Func1
    TDC                     ; C = D = $0100
    XBA                     ; B = 0 for the TAX below
    LDA.b !Field_UnkAEObj
    BMI .no_large_obj       ; Obj_None
    TAX
    STX.b !Obj_Cur          ; 16-bit store
    JSR Spr_LoadLargeObj
.no_large_obj:
    LDA.l !Field_Unk7F03FE
    BEQ .done               ; 0 → skip
    CMP #$03
    BCS .done               ; ≥ 3 → skip
    REP #$20                ; A → 16-bit
    LDX.b !Party_ObjSlot    ; leader
    LDA.w !Obj_PosX,X
    LDX.b !Party_ObjSlot1
    STA.w !Obj_PosX,X
    LDX.b !Party_ObjSlot2
    STA.w !Obj_PosX,X
    LDX.b !Party_ObjSlot
    LDA.w !Obj_PosY,X
    LDX.b !Party_ObjSlot1
    STA.w !Obj_PosY,X
    LDX.b !Party_ObjSlot2
    STA.w !Obj_PosY,X
    SEP #$20                ; A → 8-bit
    LDA #$01
    STA.b !Field_ControlEnabled
    LDA #$03
    STA.l !Field_Unk7F03FE
.done:
    RTS

; ============================================================
; $C0:0905 — Field_RestoreSaveBlock (19 bytes, $0905–$0917)
; (was Sub_0905.) Copies SceneSave_Buffer ($7F:2000) back over
; Field_SaveBlock ($7E:0920, $14E0 bytes). Reverse of
; Field_StashSaveBlock. Called first thing in Field_RestoreState, and
; from Scene_Unk0283 ($C0:0286).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C00905
Field_RestoreSaveBlock:
    LDY.w #!Field_SaveBlock ; destination (bank $00 mirror of $7E)
    LDX.w #!SceneSave_Buffer ; source (bank $7F)
    REP #$20                ; A → 16-bit
    LDA.w #!Field_SaveBlockSize-1 ; MVN count - 1
    PHB
    MVN !Bank00,!Bank7F     ; $7F:2000 → $00:0920  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20                ; A → 8-bit
    RTS

; ============================================================
; $C0:0918 — Field_StashSaveBlock (19 bytes, $0918–$092A)
; (was Sub_0918.) Copies Field_SaveBlock ($7E:0920, $14E0 bytes) to
; SceneSave_Buffer ($7F:2000). Called from Field_SaveState and from
; Scene_Unk024C ($C0:0268).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C00918
Field_StashSaveBlock:
    LDX.w #!Field_SaveBlock ; source (bank $00 mirror of $7E)
    LDY.w #!SceneSave_Buffer ; destination (bank $7F)
    REP #$20                ; A → 16-bit
    LDA.w #!Field_SaveBlockSize-1 ; MVN count - 1
    PHB
    MVN !Bank7F,!Bank00     ; $00:0920 → $7F:2000  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20                ; A → 8-bit
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
    LDA.b #FORCED_BLANK
    STA.w INIDISP           ; forced blank on, brightness 0
    LDA #$00
    STA.w NMITIMEN          ; disable NMI, IRQ, joypad auto-read
    STA.w MDMAEN            ; disable all DMA channels
    STA.w HDMAEN            ; disable all HDMA channels
    RTS

; ============================================================
; $C0:0B64 — InstallNMI (17 bytes)
; Writes JML NmiHandler ($C0:EA63) into the RAM trampoline at $7E:0500.
; Called with M=1 (8-bit A), X=0 (16-bit X).
; ============================================================
InstallNMI:
    LDA.b #!Op_JML          ; JML opcode
    STA.w !NmiTrampoline
    LDX.w #NmiHandler       ; low 16 bits of the target
    STX.w !NmiTrampoline+1
    LDA.b #bank(NmiHandler) ; bank byte
    STA.w !NmiTrampoline+3
    RTS

; ============================================================
; $C0:0B75 — InstallIRQ (17 bytes)
; Writes JML IrqHandler ($C0:ECCC) into the RAM trampoline at $7E:0504.
; Called with M=1 (8-bit A), X=0 (16-bit X); absolute stores, so DP
; does not matter (DB=$00 from InitHW or reset).
; ============================================================
InstallIRQ:
    LDA.b #!Op_JML
    STA.w !IrqTrampoline
    LDX.w #IrqHandler
    STX.w !IrqTrampoline+1
    LDA.b #bank(IrqHandler)
    STA.w !IrqTrampoline+3
    RTS

; ============================================================
; $C0:0B86 — Field_InitLoadState (240 bytes)
; (was FrameStateInit.) Called once per location load from
; GameLoop_LoadField, not per frame. Remembers where the location was
; entered, then resets the field direct page to its load-time defaults
; (including Field_HdmaEnable, the HDMAEN value the NMI handler writes).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: same widths.
; ============================================================
Field_InitLoadState:
    ; Remember the location and entry point this load started from
    LDX.b !Loc_Id
    STX.b !Loc_PrevId
    LDX.b !Loc_EntryX        ; 16-bit: entry X and Y
    STX.b !Loc_PrevX
    LDA.b !Loc_EntryFacing
    STA.b !Loc_PrevFacing
    ; Clear scene/fade request flags
    STZ.b !Field_Unk10
    STZ.b !Field_Unk11
    STZ.b !Field_SceneFlags
    STZ.b !Field_FadeFlags
    STZ.b !Field_Unk38
    STZ.b !Field_Unk0F
    ; Fixed colour starts at all channels / intensity 0, screen dark
    LDA.b #!Fade_FixedColorInit
    STA.b !Fade_FixedColor
    STZ.b !Fade_Brightness
    STZ.b !Field_UnkBC
    LDA #$02
    STA.w !Field_Unk0BDE
    ; Previous-frame OAM range ends = full range limits
    LDX.w #!Oam_Range2Limit
    STX.b !Oam_Range2PrevEnd
    LDX.w #!Oam_Range3Limit
    STX.b !Oam_Range3PrevEnd
    LDX.w #!Oam_Range1Limit
    STX.b !Oam_Range1PrevEnd
    ; Bank bytes of the four bank-$E4 pointers
    LDA.b #!BankE4
    STA.b !Field_E4Ptr0+2
    STA.b !Field_E4Ptr1+2
    STA.b !Field_E4Ptr2+2
    STA.b !Field_E4Ptr3+2
    LDA #$01
    STA.b !Field_ControlEnabled
    STA.b !Field_Unk20
    LDA #$05
    STA.b !Field_Unk68
    LDA.b #!Field_HdmaEnableInit
    STA.b !Field_HdmaEnable
    STZ.b !Field_Unk53
    STZ.b !Field_Unk26
    STZ.b !Field_Unk29
    STZ.b !Field_Unk2F
    STZ.b !Field_Unk2D
    STZ.b !Field_Unk30
    STZ.b !Field_Unk44
    STZ.b !Field_MapRedrawSel
    STZ.b !Field_MapRedrawDone
    STZ.b !Field_VramQueueFlags
    STZ.b !ObjQ_Unk78
    STZ.b !Field_UnkBB
    STZ.b !Field_Unk62
    LDA.b #!Field_Unk63Idle
    STA.b !Field_Unk63
    STZ.b !Field_EventHook
    STZ.b !Field_Unk54
    REP #$20                ; M=0: A -> 16-bit
    STZ.b !Field_Unk2B
    ; Low words of the four bank-$E4 pointers from the ROM table
    LDA.l !RomE4_PtrInit
    STA.b !Field_E4Ptr0
    LDA.l !RomE4_PtrInit+2
    STA.b !Field_E4Ptr1
    LDA.l !RomE4_PtrInit+4
    STA.b !Field_E4Ptr2
    LDA.l !RomE4_PtrInit+6
    STA.b !Field_E4Ptr3
    STZ.w !DP_Field+!Pad_Unk00F6Latch ; both latches (abs addressing in the original)
    LDA #$0000
    STA.l !Field_Unk7E2000
    STZ.b !Field_Unk58
    SEP #$20                ; M=1: A -> 8-bit
    ; No party/character objects yet
    LDA.b #!Obj_None
    STA.b !Party_ObjSlot
    STA.b !Party_ObjSlot1
    STA.b !Party_ObjSlot2
    STA.b !Chr_ObjSlot
    STA.b !Chr_ObjSlot+1
    STA.b !Chr_ObjSlot+2
    STA.b !Chr_ObjSlot+4
    STA.b !Chr_ObjSlot+3
    STA.b !Chr_ObjSlot+5
    STA.b !Chr_ObjSlot+6
    ; Snapshot the party so Party_ReinitIfChanged can tell when it changes
    LDA.l !Party_Members
    STA.b !Party_MembersCache
    LDA.l !Party_Members+1
    STA.b !Party_MembersCache+1
    LDA.l !Party_Members+2
    STA.b !Party_MembersCache+2
    LDA.b #!Field_UnkEBInit
    STA.b !Field_UnkEB
    STA.b !Field_UnkAEObj   ; = Obj_None
    LDA #$01
    STA.b !Field_Unk55
    LDA.b #!Audio_SfxDefaultA
    STA.b !Audio_SfxTileAnimA
    LDA.b #!Audio_SfxDefaultB
    STA.b !Audio_SfxTileAnimB
    LDA.b #!Audio_SfxDefaultFA
    STA.b !Audio_SfxUnkFA
    LDA #$00
    STA.l !Field_Unk7E2989
    LDA #$00
    STA.w !Field_Unk0BD9
    STA.w !Field_Unk0BDA
    STA.w !Field_Unk0BDB
    STA.w !Field_Unk0BE9
    LDA.w !Eng_Unk0400
    STA.b !Field_Unk0400Copy
    RTS

; ============================================================
; $C0:0C76 — Field_SceneChangeTick (258 bytes, $0C76–$0D77)
; (was Sub_0C76.) Runs every frame from GameLoop_FrameBody.
; Steps the two fades requested in Field_FadeFlags, then acts on
; Field_SceneFlags:
;   0           nothing to do.
;   bit 7       count Fade_Brightness down to 0, then warp: remember the
;               current location as the return point, copy Loc_Dest* into
;               Loc_Id/Loc_Entry*, reset the stack and restart through
;               ReentryVectors.
;   bit 6       count Fade_Brightness down (one frame per step, with
;               Field_FrameUpdate), save the field state and call
;               BankC2_Entry8000 with an argument chosen by
;               Field_BankC2Arg, then restore the field and fade in.
;   bit 4       run the tile-animation handler for the mode byte at
;               Map_TileProps[Field_TileAnimX/Y] (ModeE6..ModeFC_Handler);
;               any other mode goes to DefaultHandler.
;   otherwise   DefaultHandler.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00. The
; warp path never returns; the others return (or tail-jump) with M=1,
; X=0 and DP=$0100.
; ============================================================
org $C00C76
Field_SceneChangeTick:
    ; --- Step the fades requested in Field_FadeFlags ---
    LDA.b !Field_FadeFlags
    BEQ .chk_transition      ; no fade running
    BIT.b #!FadeFlag_Brightness
    BEQ .chk_fixed_color
    JSR Fade_StepBrightness
    LDA.b !Field_FadeFlags
.chk_fixed_color:
    BIT.b #!FadeFlag_FixedColor
    BEQ .chk_transition
    JSR Fade_StepFixedColor

.chk_transition:
    LDA.b !Field_SceneFlags
    BNE .has_transition
    RTS                      ; nothing pending — fast exit

.has_transition:
    BPL .not_warp            ; bit 7 clear → bits 6/4 paths

    ; --- Bit 7: fade out, then warp to Loc_Dest* ---
    LDA.b !Fade_Brightness
    BEQ .hard_restart        ; dark → warp now
    BMI .hard_restart
    DEC.b !Fade_Brightness
    RTS

.hard_restart:
    JSR InitHW                ; SEI + forced blank
    LDX.b !Loc_Id
    STX.b !Loc_ReturnId
    LDY.b !Party_ObjSlot
    LDA.w !Obj_TileX,Y
    STA.b !Loc_ReturnX
    LDA.w !Obj_TileY,Y
    STA.b !Loc_ReturnY
    LDA.w !Obj_Facing,Y
    EOR #$01
    STA.b !Loc_ReturnFacing
    LDX.b !Loc_DestId
    STX.b !Loc_Id
    LDX.b !Loc_DestX
    STX.b !Loc_EntryX
    LDA.b !Loc_DestFacing
    STA.b !Loc_EntryFacing
    LDX.w #!StackTop
    TXS                      ; reset the stack: the warp never returns
    BRL ReentryVectors       ; → GameLoop_Main (warm restart into the new location)

    ; --- Bit 7 clear: bit 6 (reload through bank $C2) or bit 4 ---
.not_warp:
    BIT.b #!SceneFlag_Reload
    BNE .run_fade_loop       ; bit 6 set → fade out and reload
    BRL .chk_tile_anim       ; bit 6 clear → check bit 4

.run_fade_loop:
    ; Fade out one brightness step per frame, input disabled
    LDA.b !Fade_Brightness
    BEQ .enter_transition
    BMI .enter_transition
    DEC.b !Fade_Brightness
    LDA.b !Field_ControlEnabled
    PHA
    STZ.b !Field_ControlEnabled
    JSR Field_FrameUpdate
    PLA
    STA.b !Field_ControlEnabled
    JSL FdVec_FFF7
    JSR Sub_EC60
    BRA .run_fade_loop

.enter_transition:
    ; Dark: save the field and hand over to bank $C2
    JSR InitHW
    JSR Field_SaveState
    TDC
    XBA                      ; B = 0 (dp high byte)
    LDA.b !Field_BankC2Arg
    BEQ .arg_5               ; 0 → argument 5 via Field_RunBankC2Mode5
    BMI .arg_from_bits       ; bit 7 → argument from bits 7-6

    ; Field_BankC2Arg bit 7 clear: argument 6 if bit 0 is clear, else 0
    BIT #$01
    BNE .arg_0
    LDA.b #!ExitMenu_Mode6
    BRA .call_bank_c2

.arg_0:
    LDA #$00
    BRA .call_bank_c2

.arg_5:
    LDA.b #!ExitMenu_Mode5   ; (Field_RunBankC2Mode5 loads 5 again itself)
    BRL Field_RunBankC2Mode5 ; bank-$C2 call with A = 5, then reload

.arg_from_bits:
    REP #$20                 ; A → 16-bit
    AND.w #!Field_ExitArgXMask ; bits 5-0 of Field_BankC2Arg → X
    TAX
    SEP #$20                 ; A → 8-bit
    LDA.b !Field_BankC2Arg
    ROL
    ROL
    ROL
    AND #$03                 ; bits 7-6 of Field_BankC2Arg → A

.call_bank_c2:
    JSL BankC2_Entry8000     ; A = argument
    JSR InitHW
    JSR InstallNMI
    JSR InstallIRQ
    REP #$20
    LDA.w #!DP_Field
    TCD                      ; DP = $0100
    SEP #$20
    JSR Field_RestoreState   ; reload the location around the saved state
    JSR Obj_ResetStates      ; clear Obj_State, then SprBuf_FreeAll
    LDA.b #!SceneFlag_Reload
    TRB.b !Field_SceneFlags
    LDA.b #!FadeFlag_Reloaded
    TSB.b !Field_FadeFlags
    BRL Field_FadeInAfterReload

    ; --- Bit 4: tile-animation mode handlers ---
.chk_tile_anim:
    BIT.b #!SceneFlag_TileAnim
    BNE .run_tile_anim
    BRL DefaultHandler

.run_tile_anim:
    LDA.b #!SceneFlag_TileAnim
    TRB.b !Field_SceneFlags
    JSR TileAnimList_AddCurrent ; remember this tile in the tile-animation list
    LDX.b !Field_TileAnimX   ; 16-bit: row*256 + column
    LDA.l !Map_TileProps,X   ; mode byte of the tile
    CMP.b #!TileAnim_ModeE6
    BNE .chk_ec
    BRL ModeE6_Handler

.chk_ec:
    CMP.b #!TileAnim_ModeEC
    BNE .chk_ee
    BRL ModeEC_Handler

.chk_ee:
    CMP.b #!TileAnim_ModeEE
    BNE .chk_fa
    BRL ModeEE_Handler

.chk_fa:
    CMP.b #!TileAnim_ModeFA
    BNE .chk_fc
    BRL ModeFA_Handler

.chk_fc:
    CMP.b #!TileAnim_ModeFC
    BNE .default_mode
    BRL ModeFC_Handler

.default_mode:
    BRL DefaultHandler

; ============================================================
; $C0:1F24 — Fade_StepBrightness (54 bytes, $1F24–$1F59)
; (was Sub_1F24.) Brightness fade: steps Fade_Brightness one unit
; toward Fade_BrightnessTarget every Fade_BrightnessDelay+1 frames and
; clears FadeFlag_Brightness when it gets there (or reaches 0 going down).
; Called from Field_SceneChangeTick while that flag is set. The NMI
; handler writes Fade_Brightness to INIDISP ($C0:EC4E; 0 becomes forced
; blank), which fixes the name; earlier notes read this as a scroll
; tracker.
; On entry: M=1 (8-bit A), X/Y not used, DP=$0100. Exit: M=1.
;
; Quirk: the step-up path loads Fade_Brightness and masks it before the
; INC, which works on memory, so A is dead there (kept from the original).
; ============================================================
org $C01F24
Fade_StepBrightness:
    LDA.b !Fade_Brightness
    AND.b #!INIDISP_BrightnessMask ; brightness bits only
    CMP.b !Fade_BrightnessTarget
    BEQ .at_target           ; equal → done
    BCS .above               ; above → count down

    ; below target: wait out the delay, then step up
    LDA.b !Fade_BrightnessTimer
    BEQ .reload_up           ; delay exhausted → reload and step
    DEC.b !Fade_BrightnessTimer
    RTS

.reload_up:
    LDA.b !Fade_BrightnessDelay
    STA.b !Fade_BrightnessTimer ; reload the delay
    LDA.b !Fade_Brightness
    AND.b #!INIDISP_BrightnessMask ; dead: the INC below works on memory
    INC.b !Fade_Brightness   ; step up
    RTS

.above:
    ; above target: wait out the delay, then step down
    LDA.b !Fade_BrightnessTimer
    BEQ .reload_dn
    DEC.b !Fade_BrightnessTimer
    RTS

.reload_dn:
    LDA.b !Fade_BrightnessDelay
    STA.b !Fade_BrightnessTimer
    LDA.b !Fade_Brightness
    DEC
    BEQ .at_zero             ; reached 0 → also done
    STA.b !Fade_Brightness
    RTS

.at_zero:
    STA.b !Fade_Brightness

.at_target:
    LDA.b #!FadeFlag_Brightness
    TRB.b !Field_FadeFlags   ; brightness fade done
    RTS

; ============================================================
; $C0:1F5A — Fade_StepFixedColor (45 bytes, $1F5A–$1F86)
; (was Sub_1F5A.) Fixed-colour fade: steps Fade_FixedColor one unit
; toward Fade_FixedColorTarget every Fade_FixedColorDelay+1 frames and
; clears FadeFlag_FixedColor when it gets there. Called from
; Field_SceneChangeTick while that flag is set. The NMI handler writes
; Fade_FixedColor to COLDATA ($C0:EC42), which fixes the name; earlier
; notes read this as a scroll-Y tracker.
; On entry: M=1 (8-bit A), X/Y not used, DP=$0100. Exit: M=1.
;
; Quirk: both step paths load Fade_FixedColor before an INC/DEC that
; works on memory, so that A is dead (kept from the original).
; ============================================================
org $C01F5A
Fade_StepFixedColor:
    LDA.b !Fade_FixedColor
    CMP.b !Fade_FixedColorTarget
    BEQ .at_target           ; equal → done
    BCS .above               ; above → count down

    ; below target
    LDA.b !Fade_FixedColorTimer
    BEQ .reload_up
    DEC.b !Fade_FixedColorTimer
    RTS

.reload_up:
    LDA.b !Fade_FixedColorDelay
    STA.b !Fade_FixedColorTimer
    LDA.b !Fade_FixedColor   ; dead: the INC below works on memory
    INC.b !Fade_FixedColor   ; step up
    RTS

.above:
    LDA.b !Fade_FixedColorTimer
    BEQ .reload_dn
    DEC.b !Fade_FixedColorTimer
    RTS

.reload_dn:
    LDA.b !Fade_FixedColorDelay
    STA.b !Fade_FixedColorTimer
    LDA.b !Fade_FixedColor   ; dead: the DEC below works on memory
    DEC.b !Fade_FixedColor   ; step down
    RTS

.at_target:
    LDA.b #!FadeFlag_FixedColor
    TRB.b !Field_FadeFlags   ; fixed-colour fade done
    RTS

; ============================================================
; $C0:2DF1 — ClearRAMDMA (45 bytes)
; Zeros a WRAM region via DMA channel 7, sourcing from MPYL (always 0
; since M7A=M7B=0). Caller sets DmaFill_Dest / DmaFill_Bank /
; DmaFill_Size first.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y: DmaFill_Dest and
; DmaFill_Size are word loads), DP=$0100 (the DmaFill_* names are dp
; offsets), DB=$00 (absolute register stores). Exit: same.
; ============================================================
org $C02DF1
ClearRAMDMA:
    LDA #$00
    STA.w M7A                 ; $211B: clear Mode-7 operand A (write twice per spec)
    STA.w M7A
    STA.w M7B                 ; $211C: clear Mode-7 operand B (write twice)
    STA.w M7B                 ; -> MPYL ($2134) = 0*0 = 0 (DMA source byte)
    LDA.b #!DMAP_BtoA
    STA.w DMAP7               ; $4370: B->A direction, byte unit, increment A-bus
    LDA.b #!BBAD_MPYL       ; B-bus $34 = $2134 = MPYL
    STA.w BBAD7               ; $4371: B-bus source = MPYL
    LDX.b !DmaFill_Dest
    STX.w A1T7L             ; $4372: A-bus (WRAM) destination address
    LDA.b !DmaFill_Bank
    STA.w A1B7                ; $4374: A-bus destination bank
    LDX.b !DmaFill_Size
    STX.w DAS7L             ; $4375: byte count
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN              ; $420B: enable DMA channel 7 (auto-clears when done)
    RTS

; ============================================================
; $C0:B192 — Obj_ResetStates (32 bytes, $B192–$B1B1)
; (was Sub_B192.) Clears Obj_State for every object the location
; defines (count in Evt_ObjCount), pointing DP at the Obj_State table
; so each clear is a 2-byte dp store, then tail-jumps to SprBuf_FreeAll
; (which marks every SprBuf_Owner entry free). Called at the end of
; every reload. The DEC/BNE count assumes Evt_ObjCount >= 1: a count of
; 0 would run 256 times, with the 8-bit Y wrapping round the page.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C0B192
Obj_ResetStates:
    PHD
    REP #$20                ; A → 16-bit
    LDA.w #!Obj_State
    TCD                     ; DP = Obj_State table
    SEP #$20                ; A → 8-bit
    SEP #$10                ; X,Y → 8-bit
    LDA.l !Evt_ObjCount     ; objects in this location
    LDX #$00                ; value to store
    LDY #$00                ; object offset
.zero_loop:
    STX.b !Dp_TableStart,Y  ; Obj_State[Y] = 0
    INY
    INY                     ; Y += 2
    DEC                     ; A-- (count)
    BNE .zero_loop
    REP #$10                ; X,Y → 16-bit
    PLD
    BRL SprBuf_FreeAll      ; marks every SprBuf_Owner entry free

; ============================================================
; $C0:B271 — Oam_BuildShadow (152 bytes)
; (was PostVBlank.) Rebuilds the OAM shadow ($0700 low table, $0900 high
; table) for the next frame; it runs before Sub_EC60's wait for the
; NMI, not after a VBlank. The shadow is split into three ranges, each with a
; low-table pointer (Oam_RangeNLoPtr) and a high-table pointer
; (Oam_RangeNHiPtr); Spr_AppendToOam appends each object's tiles to the range
; chosen by its flags. Objects are visited bucket by bucket from
; Obj_DrawBucket (last bucket first), following Obj_DrawNext chains.
; Afterwards, entries between each range's new end and last frame's
; end (Oam_RangeNPrevEnd) are parked off screen with Y = $E0.
;
; Entered via BRL tail-call from Field_EndOfFrame.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00 (the
; absolute stores to OamEntry and WMADDH need bank $00).
; Exit: same; RTS returns to Field_EndOfFrame's caller.
; ============================================================
org $C0B271
Oam_BuildShadow:
    LDX.w #!Oam_Range3HiStart
    STX.b !Oam_Range3HiPtr
    LDX #$0000
    STX.b !Oam_Range3HiUnk
    LDX.w #!Oam_Range1HiStart
    STX.b !Oam_Range1HiPtr
    LDX #$0000
    STX.b !Oam_Range1HiUnk
    LDX.w #!Oam_Range2HiStart
    STX.b !Oam_Range2HiPtr
    LDX #$0000
    STX.b !Oam_Range2HiUnk
    LDX.w #!Oam_Range3Start
    STX.b !Oam_Range3LoPtr
    LDX.w #!Oam_Range1Start
    STX.b !Oam_Range1LoPtr
    LDA #$00
    STA.w WMADDH              ; WMDATA writes go to bank $7E
    STA.b !Obj_CurHi        ; keep Obj_Cur's high byte 0
    LDX.w #!Oam_Range2Start
    STX.b !Oam_Range2LoPtr
    LDY.w #!Obj_DrawBucketLast ; 64 buckets x 2, last first
PV_BucketLoop:              ; (was PV_SpriteLoop) one Obj_DrawBucket entry
    LDA.w !Obj_DrawBucket,Y
    BMI PV_NextBucket       ; bit 7: empty bucket
    STA.b !Obj_Cur          ; first object in the bucket
    JSR Spr_AppendToOam
PV_CheckChain:
    LDX.b !Obj_Cur
    LDA.w !Obj_DrawNext,X   ; next object in the same bucket
    BMI PV_NextBucket
    STA.b !Obj_Cur
    JSR Spr_AppendToOam
    BRA PV_CheckChain
PV_NextBucket:              ; (was PV_NextSprite)
    DEY
    DEY
    BPL PV_BucketLoop
    LDX.b !Oam_Range1LoPtr
    LDA.b #!Oam_HiddenY     ; Y=$E0 parks the entry below the screen
PV_FillRange1:
    CPX.b !Oam_Range1PrevEnd
    BCS PV_EndRange1
    STA.w OamEntry.Y,X        ; X = entry address
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range1Limit
    BCC PV_FillRange1
PV_EndRange1:
    LDX.b !Oam_Range1LoPtr
    STX.b !Oam_Range1PrevEnd
    LDX.b !Oam_Range2LoPtr
PV_FillRange2:
    CPX.b !Oam_Range2PrevEnd
    BCS PV_EndRange2
    STA.w OamEntry.Y,X
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range2Limit
    BCC PV_FillRange2
PV_EndRange2:
    LDX.b !Oam_Range2LoPtr
    STX.b !Oam_Range2PrevEnd
    LDX.b !Oam_Range3LoPtr
PV_FillRange3:
    CPX.b !Oam_Range3PrevEnd
    BCS PV_EndRange3
    STA.w OamEntry.Y,X
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range3Limit
    BCC PV_FillRange3
PV_EndRange3:
    LDX.b !Oam_Range3LoPtr
    STX.b !Oam_Range3PrevEnd
    RTS

; ============================================================
; $C0:1B90 — Audio_PlayTileSfxA (23 bytes, $1B90–$1BA6)
; (was Sub_1B90.) Plays sound effect Audio_SfxTileAnimA through the
; sound driver: Audio_CmdId = $19 (play effect), Arg0 = effect id,
; Arg1 = the low byte of the party leader's Obj_ScreenX (presumably for
; panning). Called from the Mode*_Handler tile animations.
; Audio_PlaySfxAtLeader (was Sub_1B90_body) is the shared tail, entered
; by Audio_PlayTileSfxB with its own effect id in A.
; On entry: M=1 (A=8-bit), X/Y=16-bit, DP=$0100 (Audio_SfxTileAnimA
; and Party_ObjSlot are dp), DB=$00.
; ============================================================
org $C01B90
Audio_PlayTileSfxA:
    LDA.b !Audio_SfxTileAnimA
Audio_PlaySfxAtLeader:   ; ← entry for Audio_PlayTileSfxB, A = effect id
    STA.w !Audio_CmdArg0
    LDY.b !Party_ObjSlot ; leader's object
    LDA.w !Obj_ScreenX,Y
    STA.w !Audio_CmdArg1
    LDA.b #!Audio_CmdPlaySfx
    STA.w !Audio_CmdId
    JSL Audio_DriverCommand
    RTS

; ============================================================
; $C0:2824 — Field_FadeInAfterReload (36 bytes, $2824–$2847)
; (was Sub_2824.) Fade-in after a reload: unless Scene_ReloadStep
; returns nonzero, raises Fade_Brightness one step per frame (input
; disabled around Field_FrameUpdate) until it reaches full brightness.
; Clears Field_Unk1E and Field_FadeBusy on exit. Tail of
; Field_SceneChangeTick's reload path; also called after the
; bank-$C2 round trips.
; On entry: M=1 (A=8-bit), X/Y=16-bit, DP=$0100 (Fade_Brightness,
; Field_ControlEnabled and Field_Unk1E are dp), DB=$00.
; ============================================================
org $C02824
Field_FadeInAfterReload:
    JSR Scene_ReloadStep
    BNE .done            ; nonzero → skip the fade-in
.loop:
    INC.b !Fade_Brightness
    LDA.b !Field_ControlEnabled
    PHA
    STZ.b !Field_ControlEnabled ; no input during the fade
    JSR Field_FrameUpdate
    PLA
    STA.b !Field_ControlEnabled
    JSR Field_EndOfFrameShort
    JSR Sub_EC60
    LDA.b !Fade_Brightness
    CMP.b #!Fade_BrightnessMax
    BMI .loop            ; until full brightness
.done:
    STZ.b !Field_Unk1E
    STZ.w !Field_FadeBusy
    RTS

; ============================================================
; $C0:18D9 — Field_PauseAndMenuInput (172 bytes, $18D9–$1984)
; (was Sub_18D9.) Per-frame pause and menu input, called from
; GameLoop_FrameBody before Field_SceneChangeTick.
; On entry: M=1 (A 8-bit), X/Y 16-bit, DP=$0100.
;
; Pause: when Start is newly pressed (Pad_Pressed bit 0) with
;   Field_Unk11 = 0 and Field_ControlEnabled set, halve the brightness
;   and loop (Sub_EC60 + EngFD_UnkC2C1 each frame) until Start is
;   pressed again, then restore the brightness. (Earlier notes read
;   this as a VBlank-sync wait and had the exit test inverted.)
; Then Pad_Unk00F6: bit 0 → Field_FadeToBankC2Mode5; bit 6 (X in the
;   Pad_Pressed layout) → if control is enabled and Field_Unk62 /
;   Field_Unk10 are 0, fade out, save the field, call
;   BankC2_Entry8000 with A = 1 (TDC/XBA leaves DP's high byte in A;
;   very likely the main menu), and reload. When bit 6 is clear, run
;   Sub_1ADF if Field_Unk62 is set.
; Exit: M=1, X/Y 16-bit, DP=$0100.
; ============================================================
org $C018D9
Field_PauseAndMenuInput:
    LDA.w !Pad_Pressed
    BIT.b #!Pad_Start
    BEQ .chk_pad_f6      ; Start not pressed
    LDA.b !Field_Unk11
    BNE .chk_pad_f6
    LDA.b !Field_ControlEnabled
    BEQ .chk_pad_f6
    ; Pause: dim to half brightness until Start is pressed again
    LDA.b !Fade_Brightness
    STA.b !Fade_BrightnessSaved
    LSR                  ; halve
    STA.b !Fade_Brightness
    LDA.b #!Field_FadeBusyOn
    STA.w !Field_FadeBusy
.pause_loop:
    JSR Sub_EC60
    LDA.w !Pad_Pressed
    BIT.b #!Pad_Start
    BNE .unpause         ; Start pressed again → resume
    LDA.b !Fade_BrightnessSaved
    LSR
    STA.b !Fade_Brightness
    SEP #$10
    JSL EngFD_UnkC2C1
    STZ.b !Field_Unk53
    REP #$10
    BRA .pause_loop
.unpause:
    LDA.b !Fade_BrightnessSaved
    STA.b !Fade_Brightness
    STZ.w !Field_FadeBusy
.chk_pad_f6:
    LDA.w !Pad_Unk00F6
    BIT.b #!Pad_Unk00F6Mode5
    BEQ .no_mode5
    JSR Field_FadeToBankC2Mode5
    LDA.w !Pad_Unk00F6
.no_mode5:
    BIT.b #!Pad_Unk00F6Menu
    BNE .menu_request
    LDA.b !Field_Unk62
    BEQ .done
    JSR Sub_1ADF
.done:
    RTS
.menu_request:
    LDA.b !Field_ControlEnabled
    BNE .chk_unk62
    RTS
.chk_unk62:
    LDA.b !Field_Unk62
    BEQ .chk_unk10
    RTS
.chk_unk10:
    LDA.b !Field_Unk10
    BEQ .fade_loop
    RTS
.fade_loop:
    LDA.b #!Field_FadeBusyOn
    STA.w !Field_FadeBusy ; (set again every frame)
    LDA.b !Fade_Brightness
    BEQ .fade_done
    BMI .fade_done
    DEC.b !Fade_Brightness
    SEP #$10
    JSL EngFD_UnkC2C1
    REP #$10
    JSR Sub_EC60
    BRA .fade_loop
.fade_done:
    JSR InitHW
    JSR Field_SaveState
    TDC                  ; C = D = $0100
    XBA                  ; A = $01 (DP high byte), B = $00
    JSL BankC2_Entry8000
    JSR InitHW
    JSR InstallNMI
    JSR InstallIRQ
    REP #$20             ; A → 16-bit
    LDA.w #!DP_Field
    TCD                  ; DP = $0100
    SEP #$20             ; A → 8-bit
    JSR Field_RestoreState
    JSR Party_ReinitIfChanged ; party may have changed in the menu
    JSR Obj_ResetStates
    JSR Field_FadeInAfterReload
    STZ.w !Field_FadeBusy
    RTS

; ============================================================
; $C0:1985 — Field_FadeToBankC2Mode5 (66 bytes, $1985–$19C6)
; (was Sub_1985.) Called from Field_PauseAndMenuInput when
; Pad_Unk00F6 bit 0 is set. If Field_Unk26 is nonzero it only toggles
; its bits 0-1. Otherwise, if Eng_Unk7F0000 >= $49, control is enabled
; and Field_Unk62 / Field_Unk10 are 0, it fades out (one step per
; frame), saves the field and falls through to Field_RunBankC2Mode5.
; On entry: M=1 (A 8-bit), X/Y 16-bit, DP=$0100, DB=$00.
; Exit: M=1, X/Y 16-bit, DP=$0100 on every path.
; ============================================================
org $C01985
Field_FadeToBankC2Mode5:
    LDA.b !Field_Unk26
    BEQ .continue
    EOR #$03             ; toggle bits 0-1
    STA.b !Field_Unk26
    RTS
.continue:
    LDA.l !Eng_Unk7F0000
    SEC
    SBC.b #!Eng_Unk7F0000Min
    BCS .chk_control     ; ≥ Eng_Unk7F0000Min → continue
    RTS
.chk_control:
    LDA.b !Field_ControlEnabled
    BNE .chk_unk62       ; non-zero → continue
    RTS
.chk_unk62:
    LDA.b !Field_Unk62
    BEQ .chk_unk10       ; zero → continue
    RTS
.chk_unk10:
    LDA.b !Field_Unk10
    BEQ .fade_loop       ; zero → proceed
    RTS
.fade_loop:
    LDA.b #!Field_FadeBusyOn
    STA.w !Field_FadeBusy ; (set again every frame)
    LDA.b !Fade_Brightness
    BEQ .fade_done
    BMI .fade_done
    DEC.b !Fade_Brightness
    SEP #$10
    JSL EngFD_UnkC2C1
    REP #$10
    JSR Sub_EC60
    BRA .fade_loop
.fade_done:
    JSR InitHW
    JSR Field_SaveState
    ; fall through to Field_RunBankC2Mode5

; ============================================================
; $C0:19C7 — Field_RunBankC2Mode5 (60 bytes, $19C7–$1A02)
; (was Sub_19C7.) Calls BankC2_Entry8000 with A = 5, X = 0 (meaning
; of 5 unverified; earlier notes called it "BG mode 5"), then reloads
; the field: restore state, re-init changed party members, move a
; pending SceneFlag_Reload over to FadeFlag_Reloaded, reset object
; states and fade in. Reached from Field_SceneChangeTick (when
; Field_BankC2Arg is 0) and by fall-through from
; Field_FadeToBankC2Mode5. On entry: M=1 (A=8-bit), X/Y=16-bit.
; ============================================================
org $C019C7
Field_RunBankC2Mode5:
    LDX #$0000
    TDC                  ; C = D = $0100
    XBA                  ; B = $00 (A is reloaded next)
    LDA.b #!ExitMenu_Mode5
    JSL BankC2_Entry8000
    JSR InitHW
    JSR InstallNMI
    JSR InstallIRQ
    REP #$20             ; A → 16-bit
    LDA.w #!DP_Field
    TCD                  ; DP = $0100
    SEP #$20             ; A → 8-bit
    JSR Field_RestoreState
    JSR Party_ReinitIfChanged
    REP #$10             ; ensure X/Y 16-bit
    LDA.b !Field_SceneFlags
    BIT.b #!SceneFlag_Reload
    BEQ .no_bit6
    LDA.b #!SceneFlag_Reload
    TRB.b !Field_SceneFlags
    LDA.b #!FadeFlag_Reloaded
    TSB.b !Field_FadeFlags
.no_bit6:
    JSR Obj_ResetStates
    JSR Field_FadeInAfterReload
    STZ.w !Field_FadeBusy
    RTS

; ============================================================
; $C0:1A03 — Party_ReinitIfChanged (169 bytes, $1A03–$1AAB)
; (was Sub_1A03.) After a bank-$C2 round trip: if Party_Members no
; longer matches the copy taken at load (Party_MembersCache), re-run
; the init function of every character object that exists
; (Chr_ObjSlot entries in the order 0, 1, 2, 4, 3, 5, 6) and refresh
; the copy. Party_Members holds the party's character ids (earlier notes
; read them as palette colours). Either way, then put the party members
; back where Field_SaveState left them (SceneSave_Party*) and restore
; Field_UnkAB-AD — the second half of Field_SaveState's work.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: same.
; ============================================================
org $C01A03
Party_ReinitIfChanged:
    LDA.l !Party_Members
    CMP.b !Party_MembersCache
    BNE .party_changed
    LDA.l !Party_Members+1
    CMP.b !Party_MembersCache+1
    BNE .party_changed
    LDA.l !Party_Members+2
    CMP.b !Party_MembersCache+2
    BNE .party_changed
    RTS                     ; party unchanged → nothing to do

.party_changed:
    STZ.b !Obj_CurHi        ; keep Obj_Cur's high byte 0
    LDA.b !Chr_ObjSlot
    BMI .chk_chr1           ; Obj_None
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_chr1:
    LDA.b !Chr_ObjSlot+1
    BMI .chk_chr2
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_chr2:
    LDA.b !Chr_ObjSlot+2
    BMI .chk_chr4
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_chr4:
    LDA.b !Chr_ObjSlot+4
    BMI .chk_chr3
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_chr3:
    LDA.b !Chr_ObjSlot+3
    BMI .chk_chr5
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_chr5:
    LDA.b !Chr_ObjSlot+5
    BMI .chk_chr6
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_chr6:
    LDA.b !Chr_ObjSlot+6
    BMI .update_cache
    STA.b !Obj_Cur
    JSR Evt_RunObjInit

.update_cache:
    LDA.l !Party_Members    ; refresh the copy
    STA.b !Party_MembersCache
    LDA.l !Party_Members+1
    STA.b !Party_MembersCache+1
    LDA.l !Party_Members+2
    STA.b !Party_MembersCache+2

    LDX #$0000              ; party member x 2
.restore_loop:
    TDC                     ; C = D = $0100
    XBA                     ; B = 0 for the TAY below
    LDA.b !Party_ObjSlot,X
    BMI .next_restore       ; Obj_None
    TAY                     ; Y = member's object
    REP #$20                ; A → 16-bit
    LDA.l !SceneSave_PartyPosX,X
    STA.w !Obj_PosX,Y
    LDA.l !SceneSave_PartyPosY,X
    STA.w !Obj_PosY,Y
    LDA.l !SceneSave_PartyPrio,X
    STA.w !Obj_PrioLow,Y
    SEP #$20                ; A → 8-bit
.next_restore:
    INX
    INX                     ; X += 2
    CPX #$0006              ; 3 iterations
    BNE .restore_loop

    LDA.l !SceneSave_UnkAB
    STA.b !Field_UnkAB
    LDA.l !SceneSave_UnkAB+1
    STA.b !Field_UnkAC
    LDA.l !SceneSave_UnkAB+2
    STA.b !Field_UnkAD
    RTS

; ============================================================
; $C0:595C — Evt_RunObj0Func1 (33 bytes, $595C–$597C)
; (was Sub_595C.) Runs one event-script function of object 0: the
; offset stored at Evt_Data+2 (object 0's second function pointer),
; executing opcodes through Evt_OpcodeTable until opcode $00. Each
; opcode handler gets Y = the opcode's offset and must return with X
; at the next opcode. (Earlier notes called the opcodes "entity type
; bytes".) Called from Field_RestoreState, Scene_Unk0283 ($C0:0330)
; and Scene_PostLoadInit ($C0:56C8, on every location load).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C0595C
Evt_RunObj0Func1:
    REP #$20                ; A → 16-bit
    STZ.b !Obj_Cur          ; object 0 (16-bit store clears Obj_CurHi too)
    LDA.l !Evt_Data+2       ; object 0, function 1 offset
    TAX
    SEP #$20                ; A → 8-bit
.dispatch_loop:
    LDA.l !Evt_Data,X       ; opcode
    BEQ .done               ; $00 = return
    TXY                     ; Y = opcode's offset
    REP #$20                ; A → 16-bit
    AND.w #!Eng_LowByteMask
    ASL                     ; word table index
    TAX
    SEP #$20                ; A → 8-bit
    JSR (Evt_OpcodeTable,X) ; handler returns X = next opcode
    BRA .dispatch_loop
.done:
    RTS

; ============================================================
; $C0:597D — Evt_RunObjInit (92 bytes, $597D–$59D8)
; (was Sub_597D.) Runs object Obj_Cur's init function: the first of
; its 16 function offsets (Evt_Data + Obj_Cur*16, i.e. 32 bytes per
; object) is executed through Evt_OpcodeTable until opcode $00. Then
; Obj_ScriptPos = the offset after that $00, eight per-object words in
; bank $7F are cleared and Obj_Unk1C00 = 7.
; Called from Party_ReinitIfChanged for each character object.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C0597D
Evt_RunObjInit:
    LDA.b !Obj_Cur          ; object x 2
    REP #$20                ; A → 16-bit
    AND.w #!Eng_LowByteMask
    ASL
    ASL
    ASL
    ASL                     ; x 16 = object x 32: its function table
    TAX
    LDA.l !Evt_Data,X       ; function 0 (init) offset
    TAX
    SEP #$20                ; A → 8-bit
.inner_loop:
    LDA.l !Evt_Data,X       ; opcode
    BEQ .list_done          ; $00 = return
    TXY                     ; Y = opcode's offset
    REP #$20                ; A → 16-bit
    AND.w #!Eng_LowByteMask
    ASL                     ; word table index
    TAX
    SEP #$20                ; A → 8-bit
    JSR (Evt_OpcodeTable,X) ; handler returns X = next opcode
    BRA .inner_loop
.list_done:
    REP #$20                ; A → 16-bit
    INX                     ; past the $00
    TXA
    LDX.b !Obj_Cur          ; 16-bit; Obj_CurHi is 0
    STA.w !Obj_ScriptPos,X  ; where the object's script continues
    LDA #$0000
    STA.l !ObjX_Unk7F0580,X ; clear the object's bank-$7F words
    STA.l !ObjX_Unk7F0600,X
    STA.l !ObjX_Unk7F0680,X
    STA.l !ObjX_Unk7F0700,X
    STA.l !ObjX_Unk7F0780,X
    STA.l !ObjX_Unk7F0800,X
    STA.l !ObjX_Unk7F0880,X
    STA.l !ObjX_Unk7F0900,X
    SEP #$20                ; A → 8-bit
    LDA.b #!Obj_Unk1C00Init
    STA.w !Obj_Unk1C00,X
    RTS

; ============================================================
; $C0:1ADF — Sub_1ADF (87 bytes, $1ADF–$1B35)
; Leaf routine run by Field_PauseAndMenuInput when Field_Unk62 is set
; (and Pad_Unk00F6 bit 6 is clear); A = Field_Unk62.
; On entry: M=1, X/Y 16-bit, DP=$0100, DB=$00. Exit: same.
;
; A=1    → if Pad_Unk00F6 bit 7 is set, clear Field_Unk34.
; A=2    → Pad_Unk00F7 bit 2 steps Field_Unk63 up (wrapping from
;          Field_Unk65 to Field_Unk64), bit 3 steps it down (wrapping
;          the other way); else Pad_Unk00F8 bit 7 sets Field_Unk62 = 3.
;          (Bits 2/3 are Down/Up in the Pad_Pressed layout: a list
;          cursor is likely.)
; other  → save Field_Unk63 in Field_Unk66 and force it to 4 (unless it
;          is negative or already 4), then as A=1.
; ============================================================
org $C01ADF
Sub_1ADF:
    CMP #$01
    BEQ .chk_flags       ; A=1
    CMP #$02
    BNE .force_unk63     ; A≠1,2
    ; A=2
    LDA.w !Pad_Unk00F7
    BIT.b #!Pad_HiDown
    BNE .step_up
    BIT.b #!Pad_HiUp
    BNE .step_down
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit7
    BEQ .done
    LDA #$03
    STA.b !Field_Unk62
    RTS
.force_unk63:           ; A≠1,2
    LDA.b !Field_Unk63
    BMI .chk_flags       ; negative → leave it
    CMP #$04
    BEQ .chk_flags       ; already 4
    STA.b !Field_Unk66
    LDA #$04
    STA.b !Field_Unk63
.chk_flags:
    LDA.w !Pad_Unk00F6
    BIT.b #!Pad_Unk00F6Bit7
    BEQ .done            ; bit 7 clear → leave Field_Unk34
    LDX #$0000
    STX.b !Field_Unk34
.done:
    RTS
.step_up:                ; past Field_Unk65 → wrap to Field_Unk64
    LDA.b !Field_Unk63
    INC A
    CMP.b !Field_Unk65
    BEQ .store
    BCS .wrap_to_low
.store:
    STA.b !Field_Unk63
    RTS
.wrap_to_low:
    LDA.b !Field_Unk64
    BRA .store
.step_down:              ; below Field_Unk64 (or from 0) → wrap to Field_Unk65
    LDA.b !Field_Unk63
    BEQ .wrap_to_high
    DEC A
    CMP.b !Field_Unk64
    BCS .store
.wrap_to_high:
    LDA.b !Field_Unk65
    BRA .store

; ============================================================
; $C0:0D78 — ModeE6_Handler (231 bytes, $0D78–$0E5E)
; Tile animation for map-tile state $E6: a 1x2 column, the tile at
; (Field_TileAnimX, Field_TileAnimY) and the one above it.
; BRL target from Field_SceneChangeTick (Field_SceneFlags bit 4).
; On entry: A = $E6, X = Map_TileProps index of (col, row), M=1, X/Y
; 16-bit, DP=$0100 (TileAnim_* are dp), DB=$00 (absolute Map_* and
; TileAnim_VramAddrs stores).
; Exit: BRL DefaultHandler with M=1, X/Y 16-bit; X and Y clobbered.
;
; The general shape, shared by all five Mode*_Handlers:
;  1. Advance the state byte of each affected map tile in
;     Map_TileProps by one ($E6 → $E7 here), set TileAnim_PairCount
;     and play Audio_SfxTileAnimA.
;  2. For each affected map tile ("pass"), compute the VRAM word
;     address of its four 8x8 tiles in the 64x32 BG tilemap
;     (Bg_TilemapIndex64x32 + Map_TilemapVram) into TileAnim_VramAddrs,
;     4 words per map tile in TL, TR, BL, BR order.
;  3. Set VramQueue_TileAnim in Field_VramQueueFlags and continue in
;     DefaultHandler.
; Earlier comments here swapped rows and columns: Field_TileAnimX
; ($5B) is the map column, Field_TileAnimY ($5C) the row.
; ============================================================
org $C00D78
ModeE6_Handler:
    INC                  ; tile state $E6 → $E7
    STA.l !Map_TileProps,X ; tile (col, row)
    REP #$20             ; A → 16-bit
    TXA
    SEC
    SBC.w #!Map_RowStride ; index of (col, row-1)
    TAX
    LDA.l !Map_TileProps,X ; 16-bit: (col, row-1) and its right neighbour
    INC                  ; +1 lands in (col, row-1)
    STA.l !Map_TileProps,X
    SEP #$20             ; A → 8-bit
    STZ.b !TileAnim_PairCount ; one pair of tiles
    JSR Audio_PlayTileSfxA
    REP #$20             ; A → 16-bit
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY

    ; --- Pass 1: map tile (col, row) → TileAnim_VramAddrs+0..+6 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile
    ; --- Pass 2: map tile (col, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile
    SEP #$20             ; A → 8-bit
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags ; TileAnim_VramAddrs ready
    BRL DefaultHandler

; ============================================================
; $C0:1B36 — Bg_TilemapIndex64x32 (29 bytes, $1B36–$1B52)
; (was Sub_1B36.) Word offset of an 8x8 tile in a 64x32 BG tilemap
; made of two 32x32 screens side by side.
; On entry (M=0): A = tile row (0-31), Y = tile column (0-63).
; Returns A = row*32 + column for columns 0-31, or
;             row*32 + (column-32) + $0400 for columns 32-63.
; (Earlier comments had the row and column inputs swapped.)
; Called by the Mode*_Handlers and DefaultHandler; keeps row*32 in
; Bg_RowWordOfs.
; On entry: M=0, X/Y 16-bit, DP=$0100 (Bg_RowWordOfs is dp).
; Exit: M=0; X and Y unchanged (the callers rely on it).
; ============================================================
org $C01B36
Bg_TilemapIndex64x32:
    ASL
    ASL
    ASL
    ASL
    ASL                  ; row × 32
    STA.b !Bg_RowWordOfs
    TYA                  ; A = column
    CMP.w #!Bg_ScreenWidth
    BCS .right_screen    ; columns 32-63
    CLC
    ADC.b !Bg_RowWordOfs ; row*32 + column
    RTS
.right_screen:
    SEC
    SBC.w #!Bg_ScreenWidth ; column - 32
    CLC
    ADC.b !Bg_RowWordOfs
    CLC
    ADC.w #!Bg_ScreenWords ; + the left screen's $400 words
    RTS

; ============================================================
; $C0:0E5F — ModeEC_Handler (437 bytes, $0E5F–$1013)
; Tile animation for map-tile state $EC: a 2x2 block, columns
; col..col+1, rows row-1..row. Same shape as ModeE6_Handler; 4 passes.
; On entry: A = $EC, X = Map_TileProps index of (col, row), M=1, X/Y
; 16-bit, DP=$0100 (TileAnim_* are dp), DB=$00 (absolute Map_* and
; TileAnim_VramAddrs stores).
; Exit: BRL DefaultHandler with M=1, X/Y 16-bit; X and Y clobbered.
; ============================================================
org $C00E5F
ModeEC_Handler:
    INC A                   ; $EC → $ED
    STA.l !Map_TileProps,X  ; tile (col, row)
    INX                     ; X = tile (col+1, row)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col+1, row)
    REP #$20                ; M → 0 (16-bit A)
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col+1, row-1)
    TAX
    SEP #$20                ; M → 1 (8-bit A)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X
    DEX                     ; (col, row-1)
    LDA.l !Map_TileProps,X  ; load entry at (col, row-1)
    INC A
    STA.l !Map_TileProps,X
    LDA #$01
    STA.b !TileAnim_PairCount ; 2 pairs of tiles (stored minus 1)
    JSR Audio_PlayTileSfxA
    ; --- VRAM addresses of the 8x8 tiles ---
    REP #$20                ; M → 0 (16-bit A)
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY
    ; --- Pass 1: map tile (col, row) → TileAnim_VramAddrs+0..+6 ---
    LDX.b !Field_TileAnimX      ; LDX+TXA here, LDA in the other passes
    TXA
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile
    ; --- Pass 2: map tile (col, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile
    ; --- Pass 3: map tile (col+1, row) → TileAnim_VramAddrs+16..+22 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+16 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+18 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+20 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+22 ; bottom-right 8x8 tile
    ; --- Pass 4: map tile (col+1, row-1) → TileAnim_VramAddrs+24..+30 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+24 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+26 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+28 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+30 ; bottom-right 8x8 tile
    SEP #$20                ; A → 8-bit
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags ; TileAnim_VramAddrs ready
    BRL DefaultHandler

; ============================================================
; $C0:1014 — ModeEE_Handler (437 bytes, $1014–$11C8)
; Tile animation for map-tile state $EE: a 2x2 block, columns
; col-1..col, rows row-1..row (ModeEC_Handler mirrored). 4 passes.
; On entry: A = $EE, X = Map_TileProps index of (col, row), M=1, X/Y
; 16-bit, DP=$0100 (TileAnim_* are dp), DB=$00 (absolute Map_* and
; TileAnim_VramAddrs stores).
; Exit: BRL DefaultHandler with M=1, X/Y 16-bit; X and Y clobbered.
; ============================================================
org $C01014
ModeEE_Handler:
    ; --- Advance the state of the 4 tiles ---
    INC A                   ; tile state $EE → $EF
    STA.l !Map_TileProps,X  ; tile (col, row)
    DEX                     ; X = tile (col-1, row)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row)
    REP #$20                ; M → 0 (16-bit A)
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col-1, row-1)
    TAX
    SEP #$20                ; M → 1 (8-bit A)
    LDA.l !Map_TileProps,X  ; tile (col-1, row-1)
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row-1)
    INX                     ; X = tile (col, row-1)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-1)
    JSR Audio_PlayTileSfxA            ; (before setting TileAnim_PairCount here)
    LDA #$01
    STA.b !TileAnim_PairCount ; 2 pairs of tiles (stored minus 1)

    ; --- VRAM addresses of the 8x8 tiles ---
    REP #$20                ; M → 0 (16-bit A)
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY

    ; --- Pass 1: map tile (col-1, row) → TileAnim_VramAddrs+0..+6 ---
    LDX.b !Field_TileAnimX      ; LDX+TXA here, LDA in the other passes
    TXA
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile

    ; --- Pass 2: map tile (col-1, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile

    ; --- Pass 3: map tile (col, row) → TileAnim_VramAddrs+16..+22 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+16 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+18 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+20 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+22 ; bottom-right 8x8 tile

    ; --- Pass 4: map tile (col, row-1) → TileAnim_VramAddrs+24..+30 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+24 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+26 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+28 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+30 ; bottom-right 8x8 tile


    SEP #$20                ; A → 8-bit
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags ; TileAnim_VramAddrs ready
    BRL DefaultHandler

; ============================================================
; $C0:11C9 — ModeFA_Handler (651 bytes, $11C9–$1453)
; Tile animation for map-tile state $FA: a 2-wide, 3-tall block,
; columns col..col+1, rows row-2..row. 6 passes.
; On entry: A = $FA, X = Map_TileProps index of (col, row), M=1, X/Y
; 16-bit, DP=$0100 (TileAnim_* are dp), DB=$00 (absolute Map_* and
; TileAnim_VramAddrs stores).
; Exit: BRL DefaultHandler with M=1, X/Y 16-bit; X and Y clobbered.
; ============================================================
org $C011C9
ModeFA_Handler:
    ; --- Advance the state of the 6 tiles ---
    INC A                   ; tile state $FA → $FB
    STA.l !Map_TileProps,X  ; tile (col, row)
    INX                     ; X = tile (col+1, row)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col+1, row)
    REP #$20
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col+1, row-1)
    TAX
    SEP #$20
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col+1, row-1)
    DEX                     ; X = tile (col, row-1)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-1)
    REP #$20
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col, row-2)
    TAX
    SEP #$20
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-2)
    INX                     ; X = tile (col+1, row-2)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col+1, row-2)
    JSR Audio_PlayTileSfxA
    LDA #$02
    STA.b !TileAnim_PairCount ; 3 pairs of tiles (stored minus 1)

    ; --- VRAM addresses of the 8x8 tiles ---
    REP #$20
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY

    ; --- Pass 1: map tile (col, row) → TileAnim_VramAddrs+0..+6 ---
    LDX.b !Field_TileAnimX      ; LDX+TXA here, LDA in the other passes
    TXA
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile

    ; --- Pass 2: map tile (col, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile

    ; --- Pass 3: map tile (col, row-2) → TileAnim_VramAddrs+16..+22 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+16 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+18 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+20 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+22 ; bottom-right 8x8 tile

    ; --- Pass 4: map tile (col+1, row) → TileAnim_VramAddrs+24..+30 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+24 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+26 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+28 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+30 ; bottom-right 8x8 tile

    ; --- Pass 5: map tile (col+1, row-1) → TileAnim_VramAddrs+32..+38 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+32 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+34 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+36 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+38 ; bottom-right 8x8 tile

    ; --- Pass 6: map tile (col+1, row-2) → TileAnim_VramAddrs+40..+46 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+40 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+42 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+44 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+46 ; bottom-right 8x8 tile

    SEP #$20
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags
    BRL DefaultHandler

; ============================================================
; $C0:1454 — ModeFC_Handler (648 bytes, $1454–$16DB)
; Tile animation for map-tile state $FC: a 2-wide, 3-tall block,
; columns col-1..col, rows row-2..row (ModeFA_Handler mirrored).
; 6 passes; falls through into DefaultHandler.
; On entry: A = $FC, X = Map_TileProps index of (col, row), M=1, X/Y
; 16-bit, DP=$0100 (TileAnim_* are dp), DB=$00 (absolute Map_* and
; TileAnim_VramAddrs stores).
; Exit: falls into DefaultHandler with M=1, X/Y 16-bit; X and Y
; clobbered.
; ============================================================
org $C01454
ModeFC_Handler:
    ; --- Advance the state of the 6 tiles ---
    INC A                   ; tile state $FC → $FD
    STA.l !Map_TileProps,X  ; tile (col, row)
    DEX                     ; X = tile (col-1, row)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row)
    REP #$20
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col-1, row-1)
    TAX
    SEP #$20
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row-1)
    INX                     ; X = tile (col, row-1)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-1)
    REP #$20
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col, row-2)
    TAX
    SEP #$20
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-2)
    DEX                     ; X = tile (col-1, row-2)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row-2)
    JSR Audio_PlayTileSfxA
    LDA #$02
    STA.b !TileAnim_PairCount ; 3 pairs of tiles (stored minus 1)

    ; --- VRAM addresses of the 8x8 tiles ---
    REP #$20
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY

    ; --- Pass 1: map tile (col-1, row) → TileAnim_VramAddrs+0..+6 ---
    LDX.b !Field_TileAnimX      ; LDX+TXA here, LDA in the other passes
    TXA
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile

    ; --- Pass 2: map tile (col-1, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile

    ; --- Pass 3: map tile (col-1, row-2) → TileAnim_VramAddrs+16..+22 ---
    LDA.b !Field_TileAnimX
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+16 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+18 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+20 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+22 ; bottom-right 8x8 tile

    ; --- Pass 4: map tile (col, row) → TileAnim_VramAddrs+24..+30 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+24 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+26 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+28 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+30 ; bottom-right 8x8 tile

    ; --- Pass 5: map tile (col, row-1) → TileAnim_VramAddrs+32..+38 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+32 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+34 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+36 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+38 ; bottom-right 8x8 tile

    ; --- Pass 6: map tile (col, row-2) → TileAnim_VramAddrs+40..+46 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+40 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+42 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+44 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+46 ; bottom-right 8x8 tile


    SEP #$20
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags ; TileAnim_VramAddrs ready

; ============================================================
; $C0:16DC — DefaultHandler (509 bytes, $16DC–$18D8)
; The rest of Field_SceneChangeTick's request handling: reached by BRL
; when Field_SceneFlags bit 4 is clear or the tile mode is not one of
; the five Mode*_Handlers, by BRL at the end of ModeE6-FA, and by
; fall-through from ModeFC_Handler. Three independent requests:
;   bit 1 (SceneFlag_TileStep)  advance the single map tile at
;         Field_TileStepX/Y if its state is $FE or $E0, play
;         Audio_SfxTileAnimB and queue its four 8x8-tile VRAM
;         addresses in TileAnim_StepVramAddrs (VramQueue_TileStep).
;   bit 5 (SceneFlag_MapRedraw) run Field_Unk885A + Field_EndOfFrame
;         frames until Field_Unk38 clears, then redraw map layers
;         with the DP=$1D00 builders chosen by Field_MapRedrawSel and
;         tail into Sub_EC60.
;   bit 0 (SceneFlag_Battle)    unless Scene_Unk024C returns carry,
;         enter the battle engine (JSL EngCall_BattleMain), then
;         reinstall the interrupt handlers and rebuild the field;
;         either way set FadeFlag_AfterBattle and finish with
;         Field_IdleFrame.
; Earlier notes called bit 5 a "display-mode transition" and bit 0 a
; "scene swap"; the JSL into bank $C1 identifies bit 0 as the battle.
; On entry: M=1 (A 8-bit), X=0 (X/Y 16-bit), DP=$0100, DB=$00.
; Exit: M=1, X/Y 16-bit, DP=$0100 on every path (each builder call
; restores DP with PLD; the battle path sets it again).
; ============================================================
org $C016DC
DefaultHandler:
    ; --- Bit 1: single-tile step ---
    LDA.b !Field_SceneFlags
    BIT.b #!SceneFlag_TileStep
    BNE .vram_update
    BRL .bit5_check

.vram_update:
    STZ.b !TileAnim_StepKind
    LDA.b #!SceneFlag_TileStep
    TRB.b !Field_SceneFlags
    JSR Audio_PlayTileSfxB
    LDX.b !Field_TileStepX  ; 16-bit: Map_TileProps index
    LDA.l !Map_TileProps,X
    CMP.b #!TileAnim_StateFE
    BEQ .do_advance
    INC.b !TileAnim_StepKind ; 1 = the $E0 kind
    CMP.b #!TileAnim_StateE0
    BEQ .do_advance
    BRA .bit5_check         ; any other state: nothing to do

.do_advance:
    INC A                   ; $FE → $FF, $E0 → $E1
    STA.l !Map_TileProps,X

    ; --- VRAM addresses of the tile's four 8x8 tiles (as Mode*_Handler) ---
    REP #$20
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY
    TXA                     ; index: low byte = column
    ASL                     ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                     ; Y = tilemap column (0-63)
    LDA.b !Field_TileStepY
    ASL
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                     ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_StepVramAddrs ; top-left 8x8 tile
    TYA
    PHA
    INC A
    AND.w #!Bg_ColMask64
    TAY                     ; column + 1
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_StepVramAddrs+2 ; top-right
    PLY                     ; column
    TXA
    INC A
    AND.w #!Bg_RowMask32
    TAX                     ; row + 1
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_StepVramAddrs+4 ; bottom-left
    TYA
    INC A
    AND.w #!Bg_ColMask64
    TAY                     ; column + 1
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_StepVramAddrs+6 ; bottom-right
    SEP #$20                ; M=1 (8-bit A)
    LDA.b #!VramQueue_TileStep
    TSB.b !Field_VramQueueFlags ; TileAnim_StepVramAddrs ready
.bit5_check:
    ; --- Bit 5: map layer redraw ---
    LDA.b !Field_SceneFlags
    BIT.b #!SceneFlag_MapRedraw
    BNE .bit5_set
    BRL .bit0_check

.bit5_set:
    LDA.b #!SceneFlag_MapRedraw
    TRB.b !Field_SceneFlags

    ; Run Field_Unk885A + Field_EndOfFrame frames until it clears Field_Unk38
    LDA #$01
    STA.b !Field_Unk38

.loop_885A:
    JSR Field_Unk885A
    JSR Field_EndOfFrame
    LDA.b !Field_Unk38
    BEQ .loop_done
    JSR Sub_EC60
    BRA .loop_885A

.loop_done:
    JSR Field_UnkAF4E
    JSL FdVec_FFF7
    JSR Sub_EC60

    ; --- Redraw per Field_MapRedrawSel (1-4) ---
    LDA.b !Field_MapRedrawSel
    CMP #$01
    BNE .not_mode1

    ; 1: Field_BuildC800Mode1
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD                     ; DP = $1D00 for the builders
    SEP #$20
    JSR Field_BuildC800Mode1
    PLD
    JSR Field_Unk74D4
    JSR Field_EndOfFrameShort
    LDA #$01
    STA.b !Field_MapRedrawDone
    STZ.b !Field_MapRedrawSel
    JSR Sub_EC60
    JSR Field_EndOfFrameShort
    JSR Field_Unk87F1
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

.not_mode1:
    CMP #$02
    BNE .not_mode2

    ; 2: Field_BuildC800Mode2
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode2
    PLD
    JSR Field_Unk74E8
    JSR Field_EndOfFrameShort
    LDA #$02
    STA.b !Field_MapRedrawDone
    STZ.b !Field_MapRedrawSel
    JSR Sub_EC60
    JSR Field_EndOfFrameShort
    JSR Field_Unk87F1
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

.not_mode2:
    CMP #$03
    BEQ .mode3
    BRL .chk_mode4

.mode3:
    ; 3: Mode1, then Mode2, both on the normal tilemap bases. After
    ;    Mode2 the two bases are swapped; the swap holds for
    ;    Field_Unk74D4/74E8 and a second Mode1 build, and is undone
    ;    after that (presumably so both tilemaps get drawn)
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode1
    PLD
    JSR Field_EndOfFrameShort
    LDA #$03
    STA.b !Field_MapRedrawDone
    STZ.b !Field_MapRedrawSel
    JSR Sub_EC60

    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode2
    LDX.b !Map_TilemapVram-!DP_Map ; swap the two tilemap bases (DP=$1D00)
    PHX
    LDX.b !Map_TilemapVram2-!DP_Map
    STX.b !Map_TilemapVram-!DP_Map
    PLX
    STX.b !Map_TilemapVram2-!DP_Map
    PLD
    JSR Field_Unk74D4
    JSR Field_Unk74E8
    JSR Field_EndOfFrameShort
    LDA #$02
    STA.b !Field_MapRedrawDone
    JSR Sub_EC60

    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode1
    LDX.b !Map_TilemapVram-!DP_Map ; swap them back
    PHX
    LDX.b !Map_TilemapVram2-!DP_Map
    STX.b !Map_TilemapVram-!DP_Map
    PLX
    STX.b !Map_TilemapVram2-!DP_Map
    PLD
    JSR Field_Unk74D4
    JSR Field_EndOfFrameShort
    LDA #$01
    STA.b !Field_MapRedrawDone
    JSR Sub_EC60
    JSR Field_EndOfFrameShort
    JSR Field_Unk87F1
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

.chk_mode4:
    CMP #$04
    BNE .exit               ; none of 1-4

    ; 4: Field_BuildC800Mode4
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode4
    PLD
    JSR Field_Unk74F7
    JSR Field_EndOfFrameShort
    LDA #$04
    STA.b !Field_MapRedrawDone
    STZ.b !Field_MapRedrawSel
    JSR Sub_EC60
    JSR Field_EndOfFrameShort
    JSR Field_Unk87F1
    JSR Sub_EC60

.exit:
    RTS

    ; --- Bit 0: battle ---
.bit0_check:
    ; A still holds Field_SceneFlags from .bit5_check
    BIT.b #!SceneFlag_Battle
    BEQ .exit2
    JSR Scene_Unk024C
    BCS .clear_bit0         ; carry set → no battle after all

    JSL ScrollStepAccum
    LDA.b #!Field_Unk53Bit7
    TSB.b !Field_Unk53
    JSR Field_EndOfFrameShort
    LDA.b #!Field_Unk53Bit7
    TRB.b !Field_Unk53
    JSR Sub_EC60
    JSL EngCall_BattleMain  ; the battle (bank $C1)
    JSR InstallNMI          ; back in the field: reinstall our handlers
    JSR InstallIRQ
    REP #$20
    LDA.w #!DP_Field
    TCD                     ; DP = $0100
    SEP #$20
    LDA.b #!SceneFlag_Battle
    TRB.b !Field_SceneFlags
    LDA.b #!FadeFlag_AfterBattle
    TSB.b !Field_FadeFlags
    JSR Scene_Unk0283       ; rebuild the field
    JSR TileAnimList_ApplyAll
    JSR SprBuf_FreeAll
    JSR Field_IdleFrame

.exit2:
    RTS

.clear_bit0:
    LDA.b #!SceneFlag_Battle
    TRB.b !Field_SceneFlags
    LDA.b #!FadeFlag_AfterBattle
    TSB.b !Field_FadeFlags
    BRL Field_IdleFrame

; ============================================================
; $C0:1BA7 — Audio_PlayTileSfxB (4 bytes, $1BA7–$1BAA)
; (was Sub_1BA7.) Plays sound effect Audio_SfxTileAnimB: same as
; Audio_PlayTileSfxA with the other effect id, sharing its tail
; Audio_PlaySfxAtLeader. Called from DefaultHandler.
; On entry: M=1 (A 8-bit), X=0 (X/Y 16-bit), DP=$0100
; (Audio_SfxTileAnimB is dp), DB=$00.
; ============================================================
org $C01BA7
Audio_PlayTileSfxB:
    LDA.b !Audio_SfxTileAnimB ; effect id (Audio_PlayTileSfxA uses Audio_SfxTileAnimA)
    BRA Audio_PlaySfxAtLeader ; shared tail

; ============================================================
; $C0:CB0A — Obj_BuildFrameLayout (48 bytes, $CB0A–$CB39)
; (was Sub_CB0A.) Like Obj_BuildSpriteFrameStep, but for objects whose
; tiles are already in VRAM: tail-calls Obj_FrameLayout4 / 8 / 12,
; which only rewrite the SprTile records for Obj_LastFrame.
; Entry: M=1, X/Y 16-bit.
; ============================================================
org $C0CB0A
Obj_BuildFrameLayout:
    LDX.b !Obj_Cur           ; object
    LDA.w !Obj_Unk1100,X     ; skip when bit 7 is set
    BPL .cb0a_active         ; bit 7 clear → build
.cb0a_exit:
    RTS                      ; shared early-exit RTS at $CB11
.cb0a_active:                ; $CB12
    LDA.w !Obj_Unk1A81,X     ; Obj_Unk1A81
    BEQ .cb0a_exit           ; zero → early exit (back to $CB11)
    BMI .cb0a_exit           ; negative → early exit (back to $CB11)
    LDA.w !Obj_Unk0F00,X     ; Obj_AnimMode
    BEQ .cb0a_exit           ; zero → early exit (back to $CB11)
    LDA.w !Obj_SprSize,X     ; size class
    AND.b #!ObjSpr_SizeMask  ; isolate bits 0-1
    BEQ .cb0a_type0          ; == 0: single-slot
    CMP #$01
    BNE .cb0a_check2
    BRA .cb0a_type1          ; == 1: dual-slot
.cb0a_check2:
    CMP #$02
    BEQ .cb0a_type2          ; == 2: 12-slot
    CLC
    RTS                      ; other: CLC + RTS
.cb0a_type0:
    BRL Obj_FrameLayout4                ; tail-call Obj_FrameLayout4 ($CDC8)
.cb0a_type1:
    BRL Obj_FrameLayout8                ; tail-call Obj_FrameLayout8 ($D124)
.cb0a_type2:
    BRL Obj_FrameLayout12                ; tail-call Obj_FrameLayout12 ($DD28)

; ============================================================
; $C0:CB3A — Obj_AnimFrameLookup (162 bytes, $CB3A–$CBDB)
; (was Sub_CB3A.) Returns in A the frame number object X should show:
; Anim_FramePtr = Obj_AnimFrameTbl + (facing-dependent multiple of
; Obj_AnimFacingStride: 0 for facing 0, 1 for negative, 2 for 2, 3
; for the others) + row*4 + Obj_AnimColumn, row = Obj_AnimRow (or
; Obj_AnimRowAlt in mode 2), read from bank $E4.
;   entry ≠ $FF          → C=1, A = frame number.
;   $FF in mode 2        → count ObjX_AnimLoops down, C=0 (no frame).
;   $FF in other modes   → step back to the row start, set
;                          Obj_AnimColumn = $FF, C=1 with that entry.
; Entry: M=1, X/Y 16-bit, X = Obj_Cur. Preserves X.
; ============================================================
org $C0CB3A
Obj_AnimFrameLookup:
    LDA.w !Obj_Facing,X     ; animation state byte
    BEQ .zero               ; state = 0 → base path
    CMP #$02
    BEQ .two                ; state = 2 → double path
    BPL .plus               ; state > 0, != 2 → triple path
.neg:                       ; state < 0 (bit 7 set) → single-add path
    REP #$20
    LDA.w !Obj_AnimFacingStride,X ; facing stride
    CLC
    ADC.w !Obj_AnimFrameTbl,X ; + base offset
    STA.b !Anim_FramePtr
    BRA .common
.zero:
    REP #$20
    LDA.w !Obj_AnimFrameTbl,X ; base offset only
    STA.b !Anim_FramePtr
    BRA .common
.plus:                      ; state > 0, not 2 → triple-add
    REP #$20
    LDA.w !Obj_AnimFacingStride,X
    STA.b !Anim_Column      ; save width
    CLC
    ADC.b !Anim_Column      ; 2× width
    ADC.b !Anim_Column      ; 3× width
    ADC.w !Obj_AnimFrameTbl,X ; + base offset
    STA.b !Anim_FramePtr
    BRA .common
.two:                       ; state = 2 → double-add
    REP #$20
    LDA.w !Obj_AnimFacingStride,X
    ASL                     ; 2× width
    CLC
    ADC.w !Obj_AnimFrameTbl,X ; + base offset
    STA.b !Anim_FramePtr
    ; fall through to .common (M=0)
.common:
    LDA.w !Obj_AnimColumn,X ; animation row high byte (zero-extended)
    AND.w #!Anim_EndMarker
    STA.b !Anim_Column      ; save as animRowHi
    LDA.w !Obj_AnimMode,X   ; Obj_AnimMode
    AND.w #!Anim_EndMarker
    CMP #$0002              ; type == 2?
    BNE .not_two
.type_two:
    LDA.w !Obj_AnimRowAlt,X ; type-2 subfield
    AND.w #!Anim_EndMarker
    ASL                     ; × 2
    ASL                     ; × 4
    CLC
    ADC.b !Anim_Column      ; + animRowHi
    ADC.b !Anim_FramePtr    ; + base pointer
    STA.b !Anim_FramePtr    ; → adjusted frame pointer
    SEP #$20
    LDA.b [!Anim_FramePtr]  ; read frame data byte
    CMP.b #!Anim_EndMarker
    BNE .proceed            ; not $FF → sprite is ready
    LDA.l !ObjX_AnimLoops,X ; countdown timer (WRAM)
    DEC
    BEQ .skip_store         ; timer hit 0: just clear carry and return
    STA.l !ObjX_AnimLoops,X ; store decremented timer
.skip_store:
    CLC
    RTS                     ; not ready this frame
.not_two:
    LDA.w !Obj_AnimRow,X    ; standard anim frame field
    AND.w #!Anim_EndMarker
    ASL                     ; × 2
    ASL                     ; × 4
    CLC
    ADC.b !Anim_Column      ; + animRowHi
    ADC.b !Anim_FramePtr    ; + base pointer
    STA.b !Anim_FramePtr    ; → adjusted frame pointer
    SEP #$20
    LDA.b [!Anim_FramePtr]  ; read frame data byte
    CMP.b #!Anim_EndMarker
    BNE .proceed            ; not $FF → sprite is ready
    REP #$20
    LDA.b !Anim_FramePtr    ; current frame pointer
    SEC
    SBC.b !Anim_Column      ; subtract animRowHi → row start
    STA.b !Anim_FramePtr
    SEP #$20
    LDA.b #!Anim_EndMarker
    STA.w !Obj_AnimColumn,X ; mark frame row as exhausted
    LDA.b [!Anim_FramePtr]  ; re-read wrapped frame byte
.proceed:
    SEC
    RTS

; ============================================================
; $C0:CBDC — Obj_BuildFrame4 (492 bytes, $CBDC–$CDC7)
; (was Sub_CBDC.) Builds frame A (Obj_FixedFrame in mode 3, else
; Obj_AnimFrameLookup) of a 4-tile object, in one pass. Nothing to do
; (C=0) if it is still Obj_LastFrame or no SprBuf chunk is free.
; Otherwise: SprBuf_Alloc1; copy the frame's 16 8x8 tiles (frame
; record = Obj_FrameOfs + frame * 40, in Obj_FrameBank) into the
; chunk with Spr_CopyTile / Spr_CopyTileFlipped; queue the chunk's
; two halves for VRAM at Obj_VramTile (VramQ_*); write the 4
; SprTileSrc records (OfsX sign-extended, OfsY, Tile = Obj_VramTile
; + 2n, Attr = Obj_OamAttr | Obj_VramTileHi | Obj_PrioLow or, for
; OfsY >= $E8, Obj_PrioHigh); INC Obj_State. Returns C=0.
; Entry: M=1, X/Y 16-bit, X = Obj_Cur.
; ============================================================
org $C0CBDC
Obj_BuildFrame4:
    LDA.w !Obj_GfxBank,X    ; Obj_GfxBank
    STA.b !Spr_GfxPtr+2
    LDA.b #!Bank7F
    STA.b !Spr_WramPtr+2    ; dp:$D2 = $7F (pointer bank)
    REP #$20
    LDA.w !Obj_GfxOfs,X     ; 16-bit tile-table base address
    STA.b !Spr_GfxPtr
    SEP #$20
    LDA.b #!BankE4
    STA.b !Anim_FramePtr+2  ; bank $E4 of Anim_FramePtr
    LDA.w !Obj_AnimMode,X   ; Obj_AnimMode
    CMP #$03
    BNE .run_gate           ; not type-3: use animation gate
    LDA.w !Obj_FixedFrame,X ; type-3: use Obj_FixedFrame directly as frame byte
    BRA .frame_check
.run_gate:
    JSR Obj_AnimFrameLookup               ; animation-frame gate (Obj_AnimFrameLookup)
    BCS .frame_check        ; gate passed (SEC) → proceed
    RTS                     ; gate failed (CLC) → skip
.frame_check:
    CMP.w !Obj_LastFrame,X  ; same frame as last?
    BNE .new_frame
.no_work:
    CLC
    RTS                     ; same frame → no work
.new_frame:
    STA.b !Spr_NewFrame     ; save frame byte
    JSR SprBuf_Alloc1               ; single-slot allocator
    BCC .no_work            ; allocation failed → backward branch to CLC+RTS
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X  ; record current frame
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X    ; Obj_TileBuf (bank-$7F chunk address)
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X  ; frame# for multiplier
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame4_Bytes
    STA.w WRMPYB            ; WRMPYB = 40 (16 tiles × 2.5 bytes)
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; RDMPYL = frame# × 40
    CLC
    ADC.w !Obj_FrameOfs,X   ; + tile-row base → tile data pointer
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WMADDH = bank 1
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL = VRAM target
    LDA.w #!SprBuf_ChunkTiles ; loop count = 16 tiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .check              ; enter loop at condition check
.next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .fd_path
    JSR Spr_CopyTile               ; bank-switch tile copy
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
    BRA .after_loop
.fd_path:
    JSR Spr_CopyTileFlipped               ; FD00-table WRAM fill
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
.after_loop:
    ; --- SprTile/SprTileSrc: DMA descriptor into $09xx ---
    SEP #$10                ; X/Y → 8-bit
    LDX.b !Obj_Cur
    LDA.w !Obj_VramTile,X   ; object's first OAM tile number
    AND.w #!Obj_VramTileMask ; tile number bits
    ASL
    ASL
    ASL
    ASL                     ; x 16 = VRAM word address
    LDX.b !VramQ_Pos        ; queue position
    STA.w !VramQ_DestA,X    ; VRAM word address (tile * 16)
    CLC
    ADC.w #!Vram_TileRowWords
    STA.w !VramQ_DestB,X    ; next row of 16 tiles
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X    ; Obj_TileBuf
    LDX.b !VramQ_Pos
    STA.w !VramQ_SrcA,X     ; source: the object's chunk
    CLC
    ADC.w #!Gfx_8TilesBytes
    STA.w !VramQ_SrcB,X     ; second half
    LDA.w #!Gfx_8TilesBytes
    STA.w !VramQ_SizeA,X    ; bytes
    STA.w !VramQ_SizeB,X    ; bytes
    INC.w !VramQ_Valid,X    ; entry pending
    INX
    INX
    STZ.w !VramQ_Valid,X    ; ends the queue
    STX.b !VramQ_Pos        ; next queue entry
    ; --- Position offsets: OfsX (sign-extended), OfsY ---
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileRecOfs,X ; object's first tile record
    REP #$10                ; X → 16-bit
    TAX                     ; X = first tile record
    SEP #$20
    LDY.w #!Frame_TileWordBytes*16 ; position bytes follow the 16 tile words
    ; tile 0 offsets
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .y0pos
    LDA.b #!Eng_SignExtNeg
    BRA .y0hi
.y0pos:
    LDA #$00
.y0hi:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; tile 1 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .y1pos
    LDA.b #!Eng_SignExtNeg
    BRA .y1hi
.y1pos:
    LDA #$00
.y1hi:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; tile 2 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .y2pos
    LDA.b #!Eng_SignExtNeg
    BRA .y2hi
.y2pos:
    LDA #$00
.y2hi:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; tile 3 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .y3pos
    LDA.b #!Eng_SignExtNeg
    BRA .y3hi
.y3pos:
    LDA #$00
.y3hi:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; --- Tile numbers: Obj_VramTile + 2 per 16x16 tile ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y   ; object's first OAM tile number
    STA.l SprTileSrc.Tile,X
    INC
    INC
    STA.l SprTileSrc[1].Tile,X
    INC
    INC
    STA.l SprTileSrc[2].Tile,X
    INC
    INC
    STA.l SprTileSrc[3].Tile,X
    ; --- Attributes ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase     ; attribute bits before priority
    ; tile 0 attr
    LDA.l SprTileSrc.OfsY,X
    CMP.b #!Spr_UpperOfsY
    BCC .a0within
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc.Attr,X
    BRA .a1test
.a0within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTileSrc.Attr,X
    ; tile 1 attr
.a1test:
    LDA.l SprTileSrc[1].OfsY,X
    CMP.b #!Spr_UpperOfsY
    BCC .a1within
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[1].Attr,X
    BRA .a2test
.a1within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTileSrc[1].Attr,X
    ; tile 2 attr
.a2test:
    LDA.l SprTileSrc[2].OfsY,X
    CMP.b #!Spr_UpperOfsY
    BCC .a2within
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[2].Attr,X
    BRA .a3test
.a2within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTileSrc[2].Attr,X
    ; tile 3 attr
.a3test:
    LDA.l SprTileSrc[3].OfsY,X
    CMP.b #!Spr_UpperOfsY
    BCC .a3within
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[3].Attr,X
    BRA .cbdc_done
.a3within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTileSrc[3].Attr,X
.cbdc_done:
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:CDC8 — Obj_FrameLayout4 (301 bytes, $CDC8–$CEF4)
; (was Sub_CDC8.) Rewrites the 4 SprTile records of a 4-tile object
; for Obj_LastFrame directly (tiles already in VRAM): offsets from the
; frame record, Tile = Obj_VramTile + 2n, attributes as in
; Obj_BuildFrame4; then Obj_State = $80.
; Entry: M=1, X/Y 16-bit, X = Obj_Cur.
; ============================================================
org $C0CDC8
Obj_FrameLayout4:
    LDX.b !Obj_Cur
    LDA.w !Obj_LastFrame,X  ; current frame# (no gate)
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame4_Bytes
    STA.w WRMPYB            ; WRMPYB = 40
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame# × 40
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr     ; tile data pointer
    LDA.w !Obj_TileRecOfs,X ; object's first tile record
    REP #$10                ; X → 16-bit
    TAX                     ; X = first tile record
    SEP #$20
    LDY.w #!Frame_TileWordBytes*16 ; position bytes follow the 16 tile words
    ; tile 0 offsets → SprTile
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .y0pos
    LDA.b #!Eng_SignExtNeg
    BRA .y0hi
.y0pos:
    LDA #$00
.y0hi:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    ; tile 1 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .y1pos
    LDA.b #!Eng_SignExtNeg
    BRA .y1hi
.y1pos:
    LDA #$00
.y1hi:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    ; tile 2 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .y2pos
    LDA.b #!Eng_SignExtNeg
    BRA .y2hi
.y2pos:
    LDA #$00
.y2hi:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    ; tile 3 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .y3pos
    LDA.b #!Eng_SignExtNeg
    BRA .y3hi
.y3pos:
    LDA #$00
.y3hi:
    STA.l SprTile[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsY,X
    ; --- Tile numbers: Obj_VramTile + 2 per 16x16 tile ---
    LDY.b !Obj_Cur          ; object
    LDA.w !Obj_VramTile,Y   ; object's first OAM tile number
    STA.l SprTile.Tile,X
    INC
    INC
    STA.l SprTile[1].Tile,X
    INC
    INC
    STA.l SprTile[2].Tile,X
    INC
    INC
    STA.l SprTile[3].Tile,X
    ; --- Attributes ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase
    ; tile 0 attr
    LDA.l SprTile.OfsY,X
    CMP.b #!Spr_UpperOfsY
    BCC .a0within
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile.Attr,X
    BRA .a1test
.a0within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTile.Attr,X
    ; tile 1 attr
.a1test:
    LDA.l SprTile[1].OfsY,X
    CMP.b #!Spr_UpperOfsY
    BCC .a1within
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile[1].Attr,X
    BRA .a2test
.a1within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTile[1].Attr,X
    ; tile 2 attr
.a2test:
    LDA.l SprTile[2].OfsY,X
    CMP.b #!Spr_UpperOfsY
    BCC .a2within
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile[2].Attr,X
    BRA .a3test
.a2within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTile[2].Attr,X
    ; tile 3 attr
.a3test:
    LDA.l SprTile[3].OfsY,X
    CMP.b #!Spr_UpperOfsY
    BCC .a3within
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile[3].Attr,X
    BRA .cdc8_done
.a3within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTile[3].Attr,X
.cdc8_done:
    LDX.b !Obj_Cur
    LDA.b #!ObjState_Ready
    STA.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:CEF5 — Obj_BuildFrame8 (559 bytes, $CEF5–$D123)
; (was Sub_CEF5.) Builds the current frame of an 8-tile object. In
; mode 3 (fixed frame) all 32 tiles go into two chunks in one pass
; and Obj_State is incremented twice; otherwise the work is split:
; Obj_State count 0 → Obj_BuildFrame8Pass0, else Obj_BuildFrame8Pass1.
; Entry: M=1, X/Y 16-bit, X = Obj_Cur.
; ============================================================
org $C0CEF5
Obj_BuildFrame8:
    LDA.w !Obj_GfxBank,X
    STA.b !Spr_GfxPtr+2
    LDA.b #!Bank7F
    STA.b !Spr_WramPtr+2
    REP #$20
    LDA.w !Obj_GfxOfs,X
    STA.b !Spr_GfxPtr
    SEP #$20
    LDA.b #!BankE4
    STA.b !Anim_FramePtr+2
    LDA.w !Obj_AnimMode,X   ; Obj_AnimMode
    CMP #$03
    BNE .check_pass         ; not type-3 → check pass counter
    BRA .type3_path         ; type-3 → full 32-tile path
.check_pass:
    LDA.w !Obj_State,X
    AND.b #!ObjState_CountMask
    BEQ .first_pass         ; pass counter == 0: first pass
    BRL Obj_BuildFrame8Pass1               ; pass counter != 0: tail-call Obj_BuildFrame8Pass1
.first_pass:
    BRL Obj_BuildFrame8Pass0               ; tail-call Obj_BuildFrame8Pass0
    ; ---- type-3 full 32-tile path ----
.type3_path:
    LDA.w !Obj_FixedFrame,X ; use Obj_FixedFrame directly as frame byte
    CMP.w !Obj_LastFrame,X
    BNE .t3_new_frame
.t3_nc_exit:
    CLC
    RTS                     ; same frame → no work
.t3_new_frame:
    STA.b !Spr_NewFrame
    JSR SprBuf_Alloc2               ; dual-slot allocator
    BCC .t3_nc_exit         ; allocation failed → backward branch to CLC+RTS
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X    ; Obj_TileBuf
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame8_Bytes
    STA.w WRMPYB            ; WRMPYB = 80
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame# × 80
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$20
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    LDA.w #!SprBuf_ChunkTiles*2 ; 32 tiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .t3_check
.t3_next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.t3_check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .t3_fd
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .t3_next
    BRA .t3_after_loop
.t3_fd:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .t3_next
.t3_after_loop:
    ; --- SprTile/SprTileSrc for 32-tile dual-slot ---
    SEP #$10
    LDX.b !Obj_Cur
    LDA.w !Obj_VramTile,X
    AND.w #!Obj_VramTileMask
    ASL
    ASL
    ASL
    ASL
    LDX.b !VramQ_Pos
    STA.w !VramQ_DestA,X
    CLC
    ADC.w #!Vram_TileRowWords
    STA.w !VramQ_DestB,X
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    LDX.b !VramQ_Pos
    STA.w !VramQ_SrcA,X
    CLC
    ADC.w #!Gfx_8TilesBytes*2
    STA.w !VramQ_SrcB,X
    LDA.w #!Gfx_8TilesBytes*2
    STA.w !VramQ_SizeA,X
    STA.w !VramQ_SizeB,X
    INC.w !VramQ_Valid,X
    INX
    INX
    STZ.w !VramQ_Valid,X
    STX.b !VramQ_Pos
    ; --- Position offsets (after 32 tile words) ---
    REP #$20
    LDX.b !Obj_Cur
    LDA.l !Obj_TileRecOfs,X
    REP #$10
    TAX
    SEP #$20
    LDY.w #!Frame_TileWordBytes*32 ; offset = 64 (8 tile-entry pairs × 2 bytes, after 32 tiles)
    ; record 0 offsets
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .t3y0pos
    LDA.b #!Eng_SignExtNeg
    BRA .t3y0hi
.t3y0pos:
    LDA #$00
.t3y0hi:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; entry 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .t3y1pos
    LDA.b #!Eng_SignExtNeg
    BRA .t3y1hi
.t3y1pos:
    LDA #$00
.t3y1hi:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; entry 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .t3y2pos
    LDA.b #!Eng_SignExtNeg
    BRA .t3y2hi
.t3y2pos:
    LDA #$00
.t3y2hi:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; entry 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .t3y3pos
    LDA.b #!Eng_SignExtNeg
    BRA .t3y3hi
.t3y3pos:
    LDA #$00
.t3y3hi:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; entry 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsX,X
    BPL .t3y4pos
    LDA.b #!Eng_SignExtNeg
    BRA .t3y4hi
.t3y4pos:
    LDA #$00
.t3y4hi:
    STA.l SprTileSrc[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsY,X
    ; entry 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsX,X
    BPL .t3y5pos
    LDA.b #!Eng_SignExtNeg
    BRA .t3y5hi
.t3y5pos:
    LDA #$00
.t3y5hi:
    STA.l SprTileSrc[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsY,X
    ; entry 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsX,X
    BPL .t3y6pos
    LDA.b #!Eng_SignExtNeg
    BRA .t3y6hi
.t3y6pos:
    LDA #$00
.t3y6hi:
    STA.l SprTileSrc[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsY,X
    ; entry 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsX,X
    BPL .t3y7pos
    LDA.b #!Eng_SignExtNeg
    BRA .t3y7hi
.t3y7pos:
    LDA #$00
.t3y7hi:
    STA.l SprTileSrc[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsY,X
    ; --- Tile numbers: Obj_VramTile + 2 per 16x16 tile ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y
    STA.l SprTileSrc.Tile,X
    INC
    INC
    STA.l SprTileSrc[1].Tile,X
    INC
    INC
    STA.l SprTileSrc[2].Tile,X
    INC
    INC
    STA.l SprTileSrc[3].Tile,X
    INC
    INC
    STA.l SprTileSrc[4].Tile,X
    INC
    INC
    STA.l SprTileSrc[5].Tile,X
    INC
    INC
    STA.l SprTileSrc[6].Tile,X
    INC
    INC
    STA.l SprTileSrc[7].Tile,X
    ; --- attribute bytes ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase     ; A still holds the composite value
    ORA.w !Obj_PrioLow,Y    ; no LDA $D9 needed: A unchanged since STA $D9
    STA.l SprTileSrc.Attr,X
    STA.l SprTileSrc[1].Attr,X
    STA.l SprTileSrc[2].Attr,X
    STA.l SprTileSrc[3].Attr,X
    LDA.b !Spr_AttrBase     ; reload for second group (A was modified by ORA $0C00)
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[4].Attr,X
    STA.l SprTileSrc[5].Attr,X
    STA.l SprTileSrc[6].Attr,X
    STA.l SprTileSrc[7].Attr,X
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    INC.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:D124 — Obj_FrameLayout8 (358 bytes, $D124–$D289)
; (was Sub_D124.) As Obj_FrameLayout4 for an 8-tile object (frame
; record 80 bytes, positions after 32 tile words); the first four
; tiles take Obj_PrioLow, the last four Obj_PrioHigh.
; Entry: M=1, X/Y 16-bit, X = Obj_Cur.
; ============================================================
org $C0D124
Obj_FrameLayout8:
    LDA.w !Obj_LastFrame,X   ; current animation frame number
    STA.w WRMPYA             ; WRMPYA
    LDA.b #!Frame8_Bytes     ; multiply by $50 = 80 (bytes per frame entry)
    STA.w WRMPYB             ; WRMPYB → triggers multiply
    LDA.w !Obj_FrameBank,X   ; animation data bank byte
    STA.b !Spr_FramePtr+2
    REP #$20                 ; A 16-bit
    LDA.w RDMPYL             ; RDMPYL: result of frame# × $50
    CLC
    ADC.w !Obj_FrameOfs,X    ; add sprite base offset
    STA.b !Spr_FramePtr      ; dp:$D3 = animation data ptr (16-bit)
    REP #$20                 ; (already 16-bit; ensures A mode explicit)
    LDA.l !Obj_TileRecOfs,X  ; object's first tile record
    REP #$10                 ; X/Y 16-bit
    TAX                      ; X = first tile record
    SEP #$20                 ; A 8-bit
    LDY.w #!Frame_TileWordBytes*32 ; start at animation data offset $40
    ; --- 8 records: OfsX (sign-extended), OfsY ---
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .d124_y0p
    LDA.b #!Eng_SignExtNeg
    BRA .d124_y0h
.d124_y0p:
    LDA #$00
.d124_y0h:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .d124_y1p
    LDA.b #!Eng_SignExtNeg
    BRA .d124_y1h
.d124_y1p:
    LDA #$00
.d124_y1h:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .d124_y2p
    LDA.b #!Eng_SignExtNeg
    BRA .d124_y2h
.d124_y2p:
    LDA #$00
.d124_y2h:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .d124_y3p
    LDA.b #!Eng_SignExtNeg
    BRA .d124_y3h
.d124_y3p:
    LDA #$00
.d124_y3h:
    STA.l SprTile[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsX,X
    BPL .d124_y4p
    LDA.b #!Eng_SignExtNeg
    BRA .d124_y4h
.d124_y4p:
    LDA #$00
.d124_y4h:
    STA.l SprTile[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsX,X
    BPL .d124_y5p
    LDA.b #!Eng_SignExtNeg
    BRA .d124_y5h
.d124_y5p:
    LDA #$00
.d124_y5h:
    STA.l SprTile[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsX,X
    BPL .d124_y6p
    LDA.b #!Eng_SignExtNeg
    BRA .d124_y6h
.d124_y6p:
    LDA #$00
.d124_y6h:
    STA.l SprTile[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsX,X
    BPL .d124_y7p
    LDA.b #!Eng_SignExtNeg
    BRA .d124_y7h
.d124_y7p:
    LDA #$00
.d124_y7h:
    STA.l SprTile[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsY,X
    ; --- Tile numbers (8 slots, stride +2 each) ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y    ; base X coordinate
    STA.l SprTile.Tile,X
    INC
    INC
    STA.l SprTile[1].Tile,X
    INC
    INC
    STA.l SprTile[2].Tile,X
    INC
    INC
    STA.l SprTile[3].Tile,X
    INC
    INC
    STA.l SprTile[4].Tile,X
    INC
    INC
    STA.l SprTile[5].Tile,X
    INC
    INC
    STA.l SprTile[6].Tile,X
    INC
    INC
    STA.l SprTile[7].Tile,X
    ; --- priority/attribute bytes ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTile.Attr,X
    STA.l SprTile[1].Attr,X
    STA.l SprTile[2].Attr,X
    STA.l SprTile[3].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile[4].Attr,X
    STA.l SprTile[5].Attr,X
    STA.l SprTile[6].Attr,X
    STA.l SprTile[7].Attr,X
    LDX.b !Obj_Cur
    LDA.b #!ObjState_Ready
    STA.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:D28A — Obj_BuildFrame8Pass0 (131 bytes, $D28A–$D30C)
; (was Sub_D28A.) First pass of an 8-tile frame: look the frame up,
; SprBuf_Alloc2, copy tiles 0-15 into the first chunk, INC Obj_State,
; return C=1 (more to do). C=0 when nothing changed or no chunks.
; ============================================================
org $C0D28A
Obj_BuildFrame8Pass0:
    JSR Obj_AnimFrameLookup               ; animation-frame gate
    BCS .d28a_proceed
    RTS                     ; gate failed → CLC, skip
.d28a_proceed:
    CMP.w !Obj_LastFrame,X  ; same frame?
    BNE .d28a_new_frame
.d28a_nc_exit:
    CLC
    RTS
.d28a_new_frame:
    STA.b !Spr_NewFrame
    JSR SprBuf_Alloc2               ; dual-slot allocator
    BCC .d28a_nc_exit       ; allocation failed → backward branch to CLC+RTS
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame8_Bytes
    STA.w WRMPYB            ; WRMPYB = 80
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame# × 80
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    LDA.w #!SprBuf_ChunkTiles ; 16 tiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .d28a_check
.d28a_next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d28a_check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d28a_fd
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d28a_next
    BRA .d28a_done
.d28a_fd:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d28a_next
.d28a_done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D30D — Obj_BuildFrame8Pass1 (490 bytes, $D30D–$D4F6)
; (was Sub_D30D.) Second pass: tiles 16-31 into the second chunk
; (Obj_TileBuf + $200), queue the VRAM upload, write the 8
; SprTileSrc records, INC Obj_State; C=0.
; ============================================================
org $C0D30D
Obj_BuildFrame8Pass1:
    REP #$20
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*2 ; second chunk
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame8_Bytes
    STA.w WRMPYB            ; WRMPYB = 80
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame# × 80
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$20
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    LDA.w #!SprBuf_ChunkTiles ; 16 tiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*16 ; start at tile-data offset 32 (second half)
    BRA .d30d_check
.d30d_next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d30d_check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d30d_fd
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d30d_next
    BRA .d30d_after_loop
.d30d_fd:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d30d_next
.d30d_after_loop:
    ; --- SprTile/SprTileSrc ---
    SEP #$10
    LDX.b !Obj_Cur
    LDA.w !Obj_VramTile,X
    AND.w #!Obj_VramTileMask
    ASL
    ASL
    ASL
    ASL
    LDX.b !VramQ_Pos
    STA.w !VramQ_DestA,X
    CLC
    ADC.w #!Vram_TileRowWords
    STA.w !VramQ_DestB,X
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    LDX.b !VramQ_Pos
    STA.w !VramQ_SrcA,X
    CLC
    ADC.w #!Gfx_8TilesBytes*2
    STA.w !VramQ_SrcB,X
    LDA.w #!Gfx_8TilesBytes*2
    STA.w !VramQ_SizeA,X
    STA.w !VramQ_SizeB,X
    INC.w !VramQ_Valid,X
    INX
    INX
    STZ.w !VramQ_Valid,X
    STX.b !VramQ_Pos
    ; --- Position offsets (after 32 tile words) ---
    LDX.b !Obj_Cur
    LDA.l !Obj_TileRecOfs,X
    REP #$10
    TAX
    SEP #$20
    LDY.w #!Frame_TileWordBytes*32
    ; entry 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .d30d_y0pos
    LDA.b #!Eng_SignExtNeg
    BRA .d30d_y0hi
.d30d_y0pos:
    LDA #$00
.d30d_y0hi:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; entry 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .d30d_y1pos
    LDA.b #!Eng_SignExtNeg
    BRA .d30d_y1hi
.d30d_y1pos:
    LDA #$00
.d30d_y1hi:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; entry 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .d30d_y2pos
    LDA.b #!Eng_SignExtNeg
    BRA .d30d_y2hi
.d30d_y2pos:
    LDA #$00
.d30d_y2hi:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; entry 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .d30d_y3pos
    LDA.b #!Eng_SignExtNeg
    BRA .d30d_y3hi
.d30d_y3pos:
    LDA #$00
.d30d_y3hi:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; entry 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsX,X
    BPL .d30d_y4pos
    LDA.b #!Eng_SignExtNeg
    BRA .d30d_y4hi
.d30d_y4pos:
    LDA #$00
.d30d_y4hi:
    STA.l SprTileSrc[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsY,X
    ; entry 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsX,X
    BPL .d30d_y5pos
    LDA.b #!Eng_SignExtNeg
    BRA .d30d_y5hi
.d30d_y5pos:
    LDA #$00
.d30d_y5hi:
    STA.l SprTileSrc[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsY,X
    ; entry 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsX,X
    BPL .d30d_y6pos
    LDA.b #!Eng_SignExtNeg
    BRA .d30d_y6hi
.d30d_y6pos:
    LDA #$00
.d30d_y6hi:
    STA.l SprTileSrc[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsY,X
    ; entry 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsX,X
    BPL .d30d_y7pos
    LDA.b #!Eng_SignExtNeg
    BRA .d30d_y7hi
.d30d_y7pos:
    LDA #$00
.d30d_y7hi:
    STA.l SprTileSrc[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsY,X
    ; --- Tile numbers ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y
    STA.l SprTileSrc.Tile,X
    INC
    INC
    STA.l SprTileSrc[1].Tile,X
    INC
    INC
    STA.l SprTileSrc[2].Tile,X
    INC
    INC
    STA.l SprTileSrc[3].Tile,X
    INC
    INC
    STA.l SprTileSrc[4].Tile,X
    INC
    INC
    STA.l SprTileSrc[5].Tile,X
    INC
    INC
    STA.l SprTileSrc[6].Tile,X
    INC
    INC
    STA.l SprTileSrc[7].Tile,X
    ; --- attribute bytes (lower 4 use $0C00, upper 4 use $0C01) ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase     ; A still holds composite
    ORA.w !Obj_PrioLow,Y    ; no reload needed: A unchanged since STA $D9
    STA.l SprTileSrc.Attr,X
    STA.l SprTileSrc[1].Attr,X
    STA.l SprTileSrc[2].Attr,X
    STA.l SprTileSrc[3].Attr,X
    LDA.b !Spr_AttrBase     ; reload for upper group
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[4].Attr,X
    STA.l SprTileSrc[5].Attr,X
    STA.l SprTileSrc[6].Attr,X
    STA.l SprTileSrc[7].Attr,X
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:D4F7 — Obj_BuildFrame12 (79 bytes, $D4F7–$D545, plus the
; Obj_BuildFrame12Pass0 tail that follows it)
; (was Sub_D4F7.) Builds the current frame of a 12-tile object over
; three passes chosen by the Obj_State count (0 / 1 / 2+), each with
; an "Alt" variant when Obj_VramTile is $68 (different chunk/VRAM
; layout). Mode 3 objects return at once.
; ============================================================
org $C0D4F7
Obj_BuildFrame12:
    LDA.w !Obj_GfxBank,X    ; Obj_GfxBank
    STA.b !Spr_GfxPtr+2
    LDA.b #!Bank7F
    STA.b !Spr_WramPtr+2
    REP #$20
    LDA.w !Obj_GfxOfs,X     ; Obj_GfxOfs
    STA.b !Spr_GfxPtr
    SEP #$20
    LDA.b #!BankE4
    STA.b !Anim_FramePtr+2
    ; type-3 sprites bypass all init
    LDA.w !Obj_AnimMode,X
    CMP #$03
    BNE .d4f7_check_pass
    RTS
.d4f7_check_pass:
    LDA.w !Obj_State,X
    AND.b #!ObjState_CountMask ; pass counter (low 7 bits)
    BEQ .d4f7_pass0
    CMP #$01
    BEQ .d4f7_pass1
    ; pass 2+: further dispatch on Obj_VramTile
    LDA.w !Obj_VramTile,X
    CMP.b #!ObjTile_AltLayout
    BEQ .d4f7_p2_68
    BRL Obj_BuildFrame12Pass2            ; pass 2+, non-$68
.d4f7_p2_68:
    BRL Obj_BuildFrame12Pass2Alt            ; pass 2+, $68
.d4f7_pass0:
    LDA.w !Obj_VramTile,X
    CMP.b #!ObjTile_AltLayout
    BEQ .d4f7_p0_68
    BRA Obj_BuildFrame12Pass0            ; pass 0, non-$68 → tile DMA body below
.d4f7_p0_68:
    BRL Obj_BuildFrame12Pass0Alt            ; pass 0, $68 → 16-tile single-pass variant
.d4f7_pass1:
    LDA.w !Obj_VramTile,X
    CMP.b #!ObjTile_AltLayout
    BEQ .d4f7_p1_68
    BRL Obj_BuildFrame12Pass1            ; pass 1, non-$68
.d4f7_p1_68:
    BRL Obj_BuildFrame12Pass1Alt            ; pass 1, $68

; ============================================================
; $C0:D546 — Obj_BuildFrame12Pass0 (194 bytes, $D546–$D607)
; (was Sub_D546.) Pass 0: frame lookup, SprBuf_Alloc3, tiles 0-7 to
; the buffer start and tiles 8-15 to +$200, INC Obj_State; C=1.
; Reached by falling out of Obj_BuildFrame12.
; ============================================================
Obj_BuildFrame12Pass0:
    JSR Obj_AnimFrameLookup
    BCS .d546_proceed
    RTS
.d546_proceed:
    CMP.w !Obj_LastFrame,X  ; same frame already loaded?
    BNE .d546_new_frame
.d546_cle_rts:              ; shared exit: CLC + RTS (same-frame skip / alloc fail)
    CLC
    RTS
.d546_new_frame:
    STA.b !Spr_NewFrame     ; save current frame type
    JSR SprBuf_Alloc3            ; allocate three sprite slots
    BCC .d546_cle_rts       ; alloc failed → CLC RTS
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X  ; mark frame type as loaded
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X    ; WRAM base for this slot group
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X  ; frame number → multiply by $78 (120 tiles per frame)
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB            ; WRMPYB
    LDA.w !Obj_FrameBank,X  ; Obj_GfxBank
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; RDMPYL — frame# × 120 product
    CLC
    ADC.w !Obj_FrameOfs,X   ; add sprite base offset → frame data pointer
    STA.b !Spr_FramePtr
    ; WMADD bank bit = $7F
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    ; first 8-tile loop: Y=0..7 → WRAM base
    LDA #$0008
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .d546_loop1_entry
.d546_loop1_top:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d546_loop1_entry:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d546_loop1_e534
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d546_loop1_top
    BRA .d546_loop2_init
.d546_loop1_e534:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d546_loop1_top
.d546_loop2_init:
    ; second 8-tile loop: Y=8..15 → WRAM base+$200
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*2
    STA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL — advance WRAM dest to slot+$200
    REP #$10
    LDA #$0008
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*8 ; word 8 in frame data (Y=16 bytes in)
    BRA .d546_loop2_entry
.d546_loop2_top:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d546_loop2_entry:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d546_loop2_e534
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d546_loop2_top
    BRA .d546_done
.d546_loop2_e534:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d546_loop2_top
.d546_done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D608 — Obj_BuildFrame12Pass0Alt (131 bytes, $D608–$D68A)
; (was Sub_D608.) Pass 0, $68 layout: tiles 0-15 in one run to the
; buffer start. (An older comment here named a label
; "Obj_BuildFrameSize2_Start" that never existed.)
; ============================================================
org $C0D608
Obj_BuildFrame12Pass0Alt:
    JSR Obj_AnimFrameLookup
    BCS .d608_proceed
    RTS
.d608_proceed:
    CMP.w !Obj_LastFrame,X  ; same frame already loaded?
    BNE .d608_new_frame
.d608_cle_rts:
    CLC
    RTS
.d608_new_frame:
    STA.b !Spr_NewFrame
    JSR SprBuf_Alloc3            ; triple-slot alloc
    BCC .d608_cle_rts
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X  ; frame number
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB            ; WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; RDMPYL
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    ; 16-tile loop (single pass): Y=0..15 → WRAM base
    LDA.w #!SprBuf_ChunkTiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .d608_loop_entry
.d608_loop_top:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d608_loop_entry:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d608_e534
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d608_loop_top
    BRA .d608_done
.d608_e534:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d608_loop_top
.d608_done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D68B — Obj_BuildFrame12Pass1 (173 bytes, $D68B–$D737)
; (was Sub_D68B.) Pass 1: tiles 16-23 to +$100, tiles 24-31 to
; +$300; INC Obj_State; C=1.
; ============================================================
org $C0D68B
Obj_BuildFrame12Pass1:
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB            ; WRMPYB = 120
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; RDMPYL (= frame# × 120)
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    LDA #$0008
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*16
    BRA .d68b_check
.d68b_next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d68b_check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d68b_fd
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d68b_next
    BRA .d68b_loop2
.d68b_fd:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d68b_next
.d68b_loop2:
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*3
    STA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    REP #$10
    LDA #$0008
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*24
    BRA .d68b_check2
.d68b_next2:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d68b_check2:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d68b_fd2
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d68b_next2
    BRA .d68b_done
.d68b_fd2:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d68b_next2
.d68b_done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D738 — Obj_BuildFrame12Pass1Alt (173 bytes, $D738–$D7E4)
; (was Sub_D738.) Pass 1, $68 layout: tiles 16-23 to +$200, tiles
; 24-31 to +$400.
; ============================================================
org $C0D738
Obj_BuildFrame12Pass1Alt:
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*2
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB            ; WRMPYB = 120
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; RDMPYL (= frame# × 120)
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    LDA #$0008
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*16
    BRA .d738_check
.d738_next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d738_check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d738_fd
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d738_next
    BRA .d738_loop2
.d738_fd:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d738_next
.d738_loop2:
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*4
    STA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    REP #$10
    LDA #$0008
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*24
    BRA .d738_check2
.d738_next2:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d738_check2:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d738_fd2
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d738_next2
    BRA .d738_done
.d738_fd2:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d738_next2
.d738_done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D7E5 — Obj_BuildFrame12Pass2 (644 bytes, $D7E5–$DA68)
; (was Sub_D7E5.) Pass 2: tiles 32-47 to +$400, queue the VRAM
; upload, write the 12 SprTileSrc records (tiles in rows of 8 then
; 4), INC Obj_State; C=0.
; ============================================================
org $C0D7E5
Obj_BuildFrame12Pass2:
    REP #$20
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*4
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB            ; WRMPYB = 120
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; RDMPYL (= frame# × 120)
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$20
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    LDA.w #!SprBuf_ChunkTiles ; 16 tiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*32
    BRA .d7e5_check
.d7e5_next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.d7e5_check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .d7e5_fd
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d7e5_next
    BRA .d7e5_oam
.d7e5_fd:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .d7e5_next
.d7e5_oam:
    ; --- Queue the VRAM upload ---
    SEP #$10                ; X/Y = 8-bit; A stays 16-bit
    LDX.b !Obj_Cur
    LDA.w !Obj_VramTile,X
    AND.w #!Obj_VramTileMask
    ASL
    ASL
    ASL
    ASL
    LDX.b !VramQ_Pos
    STA.w !VramQ_DestA,X
    CLC
    ADC.w #!Vram_TileRowWords*3
    STA.w !VramQ_DestB,X
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    LDX.b !VramQ_Pos
    STA.w !VramQ_SrcA,X
    CLC
    ADC.w #!Gfx_8TilesBytes*5
    STA.w !VramQ_SrcB,X
    LDA.w #!Gfx_8TilesBytes*5
    STA.w !VramQ_SizeA,X
    LDA.w #!Gfx_8TilesBytes
    STA.w !VramQ_SizeB,X
    INC.w !VramQ_Valid,X
    INX
    INX
    STZ.w !VramQ_Valid,X
    STX.b !VramQ_Pos
    LDX.b !Obj_Cur
    LDA.w !Obj_TileRecOfs,X
    REP #$10                ; X/Y = 16-bit
    TAX
    SEP #$20                ; A = 8-bit
    LDY.w #!Frame_TileWordBytes*48
    ; --- Position offsets (after 48 tile words) ---
    ; entry 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .d7e5_y0p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y0h
.d7e5_y0p:
    LDA #$00
.d7e5_y0h:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; entry 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .d7e5_y1p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y1h
.d7e5_y1p:
    LDA #$00
.d7e5_y1h:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; entry 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .d7e5_y2p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y2h
.d7e5_y2p:
    LDA #$00
.d7e5_y2h:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; entry 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .d7e5_y3p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y3h
.d7e5_y3p:
    LDA #$00
.d7e5_y3h:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; entry 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsX,X
    BPL .d7e5_y4p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y4h
.d7e5_y4p:
    LDA #$00
.d7e5_y4h:
    STA.l SprTileSrc[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsY,X
    ; entry 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsX,X
    BPL .d7e5_y5p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y5h
.d7e5_y5p:
    LDA #$00
.d7e5_y5h:
    STA.l SprTileSrc[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsY,X
    ; entry 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsX,X
    BPL .d7e5_y6p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y6h
.d7e5_y6p:
    LDA #$00
.d7e5_y6h:
    STA.l SprTileSrc[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsY,X
    ; entry 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsX,X
    BPL .d7e5_y7p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y7h
.d7e5_y7p:
    LDA #$00
.d7e5_y7h:
    STA.l SprTileSrc[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsY,X
    ; entry 8
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[8].OfsX,X
    BPL .d7e5_y8p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y8h
.d7e5_y8p:
    LDA #$00
.d7e5_y8h:
    STA.l SprTileSrc[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[8].OfsY,X
    ; entry 9
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[9].OfsX,X
    BPL .d7e5_y9p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y9h
.d7e5_y9p:
    LDA #$00
.d7e5_y9h:
    STA.l SprTileSrc[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[9].OfsY,X
    ; entry 10
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[10].OfsX,X
    BPL .d7e5_y10p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y10h
.d7e5_y10p:
    LDA #$00
.d7e5_y10h:
    STA.l SprTileSrc[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[10].OfsY,X
    ; entry 11
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[11].OfsX,X
    BPL .d7e5_y11p
    LDA.b #!Eng_SignExtNeg
    BRA .d7e5_y11h
.d7e5_y11p:
    LDA #$00
.d7e5_y11h:
    STA.l SprTileSrc[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[11].OfsY,X
    ; --- Tile numbers (8 sequential, gap at slot boundary, 4 more) ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y
    STA.l SprTileSrc.Tile,X
    INC
    INC
    STA.l SprTileSrc[1].Tile,X
    INC
    INC
    STA.l SprTileSrc[2].Tile,X
    INC
    INC
    STA.l SprTileSrc[3].Tile,X
    INC
    INC
    STA.l SprTileSrc[4].Tile,X
    INC
    INC
    STA.l SprTileSrc[5].Tile,X
    INC
    INC
    STA.l SprTileSrc[6].Tile,X
    INC
    INC
    STA.l SprTileSrc[7].Tile,X
    INC
    INC
    CLC
    ADC.b #!Spr_TileRowStep
    STA.l SprTileSrc[8].Tile,X
    INC
    INC
    STA.l SprTileSrc[9].Tile,X
    INC
    INC
    STA.l SprTileSrc[10].Tile,X
    INC
    INC
    STA.l SprTileSrc[11].Tile,X
    ; --- attribute bytes ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTileSrc.Attr,X
    STA.l SprTileSrc[1].Attr,X
    STA.l SprTileSrc[2].Attr,X
    STA.l SprTileSrc[3].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[4].Attr,X
    STA.l SprTileSrc[5].Attr,X
    STA.l SprTileSrc[6].Attr,X
    STA.l SprTileSrc[7].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[8].Attr,X
    STA.l SprTileSrc[9].Attr,X
    STA.l SprTileSrc[10].Attr,X
    STA.l SprTileSrc[11].Attr,X
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:DA69 — Obj_BuildFrame12Pass2Alt (703 bytes, $DA69–$DD27)
; (was Sub_DA69.) Pass 2, $68 layout: tiles 32-39 to +$300 and 40-47
; to +$500, queue the upload, write the 12 SprTileSrc records (rows
; of 4 then 8); C=0.
; ============================================================
org $C0DA69
Obj_BuildFrame12Pass2Alt:
    REP #$20
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*3
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA            ; WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB            ; WRMPYB = 120
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; RDMPYL (= frame# × 120)
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$20
    LDA #$01
    STA.w WMADDH            ; WMADDH
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    LDA #$0008              ; 8 tiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*32
    BRA .da69_check
.da69_next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.da69_check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .da69_fd
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .da69_next
    BRA .da69_loop2
.da69_fd:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .da69_next
.da69_loop2:
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*5
    STA.b !Spr_WramPtr
    STA.w WMADDL            ; WMADDL
    LDA #$0008              ; 8 tiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*40
    BRA .da69_check2
.da69_next2:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.da69_check2:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .da69_fd2
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .da69_next2
    BRA .da69_oam
.da69_fd2:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .da69_next2
.da69_oam:
    ; --- Queue the VRAM upload ---
    SEP #$10                ; X/Y = 8-bit; A stays 16-bit
    LDX.b !Obj_Cur
    LDA.w !Obj_VramTile,X
    AND.w #!Obj_VramTileMask
    ASL
    ASL
    ASL
    ASL
    LDX.b !VramQ_Pos
    STA.w !VramQ_DestA,X
    CLC
    ADC.w #!Vram_TileRowWords
    STA.w !VramQ_DestB,X
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    LDX.b !VramQ_Pos
    STA.w !VramQ_SrcA,X
    CLC
    ADC.w #!Gfx_8TilesBytes
    STA.w !VramQ_SrcB,X
    LDA.w #!Gfx_8TilesBytes
    STA.w !VramQ_SizeA,X
    LDA.w #!Gfx_8TilesBytes*5
    STA.w !VramQ_SizeB,X
    INC.w !VramQ_Valid,X
    INX
    INX
    STZ.w !VramQ_Valid,X
    STX.b !VramQ_Pos
    LDX.b !Obj_Cur
    LDA.w !Obj_TileRecOfs,X
    REP #$10                ; X/Y = 16-bit
    TAX
    SEP #$20                ; A = 8-bit
    LDY.w #!Frame_TileWordBytes*48
    ; --- Position offsets (after 48 tile words) ---
    ; entry 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .da69_y0p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y0h
.da69_y0p:
    LDA #$00
.da69_y0h:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; entry 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .da69_y1p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y1h
.da69_y1p:
    LDA #$00
.da69_y1h:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; entry 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .da69_y2p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y2h
.da69_y2p:
    LDA #$00
.da69_y2h:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; entry 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .da69_y3p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y3h
.da69_y3p:
    LDA #$00
.da69_y3h:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; entry 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsX,X
    BPL .da69_y4p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y4h
.da69_y4p:
    LDA #$00
.da69_y4h:
    STA.l SprTileSrc[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsY,X
    ; entry 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsX,X
    BPL .da69_y5p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y5h
.da69_y5p:
    LDA #$00
.da69_y5h:
    STA.l SprTileSrc[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsY,X
    ; entry 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsX,X
    BPL .da69_y6p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y6h
.da69_y6p:
    LDA #$00
.da69_y6h:
    STA.l SprTileSrc[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsY,X
    ; entry 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsX,X
    BPL .da69_y7p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y7h
.da69_y7p:
    LDA #$00
.da69_y7h:
    STA.l SprTileSrc[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsY,X
    ; entry 8
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[8].OfsX,X
    BPL .da69_y8p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y8h
.da69_y8p:
    LDA #$00
.da69_y8h:
    STA.l SprTileSrc[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[8].OfsY,X
    ; entry 9
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[9].OfsX,X
    BPL .da69_y9p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y9h
.da69_y9p:
    LDA #$00
.da69_y9h:
    STA.l SprTileSrc[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[9].OfsY,X
    ; entry 10
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[10].OfsX,X
    BPL .da69_y10p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y10h
.da69_y10p:
    LDA #$00
.da69_y10h:
    STA.l SprTileSrc[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[10].OfsY,X
    ; entry 11
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[11].OfsX,X
    BPL .da69_y11p
    LDA.b #!Eng_SignExtNeg
    BRA .da69_y11h
.da69_y11p:
    LDA #$00
.da69_y11h:
    STA.l SprTileSrc[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[11].OfsY,X
    ; --- Tile numbers (4 sequential, gap at slot boundary, 8 more) ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y
    STA.l SprTileSrc.Tile,X
    INC
    INC
    STA.l SprTileSrc[1].Tile,X
    INC
    INC
    STA.l SprTileSrc[2].Tile,X
    INC
    INC
    STA.l SprTileSrc[3].Tile,X
    INC
    INC
    CLC
    ADC.b #!Spr_TileRowStep
    STA.l SprTileSrc[4].Tile,X
    INC
    INC
    STA.l SprTileSrc[5].Tile,X
    INC
    INC
    STA.l SprTileSrc[6].Tile,X
    INC
    INC
    STA.l SprTileSrc[7].Tile,X
    INC
    INC
    STA.l SprTileSrc[8].Tile,X
    INC
    INC
    STA.l SprTileSrc[9].Tile,X
    INC
    INC
    STA.l SprTileSrc[10].Tile,X
    INC
    INC
    STA.l SprTileSrc[11].Tile,X
    ; --- attribute bytes ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTileSrc.Attr,X
    STA.l SprTileSrc[1].Attr,X
    STA.l SprTileSrc[2].Attr,X
    STA.l SprTileSrc[3].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[4].Attr,X
    STA.l SprTileSrc[5].Attr,X
    STA.l SprTileSrc[6].Attr,X
    STA.l SprTileSrc[7].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTileSrc[8].Attr,X
    STA.l SprTileSrc[9].Attr,X
    STA.l SprTileSrc[10].Attr,X
    STA.l SprTileSrc[11].Attr,X
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:DD28 — Obj_FrameLayout12 (1026 bytes, $DD28–$E129)
; (was Sub_DD28.) As Obj_FrameLayout4 for a 12-tile object (frame
; record 120 bytes, positions after 48 tile words), with the two
; tile-number layouts of the 12-tile builders (Obj_VramTile = $68 →
; .dd28_alt); Obj_State = $80.
; Entry: M=1, X/Y 16-bit, X = Obj_Cur.
; ============================================================
org $C0DD28
Obj_FrameLayout12:
    LDA.w !Obj_VramTile,X    ; Obj_VramTile ($68 = alternate layout)
    CMP.b #!ObjTile_AltLayout
    BEQ .dd28_alt_branch     ; == $68: use alt path
    BRA .dd28_main           ; else: main path
.dd28_alt_branch:
    BRL .dd28_alt                ; tail-call alt path at $DF2F
    ; ---- main path ----
.dd28_main:
    LDA.w !Obj_LastFrame,X   ; animation frame number
    STA.w WRMPYA             ; WRMPYA
    LDA.b #!Frame12_Bytes    ; multiply by $78 = 120
    STA.w WRMPYB             ; WRMPYB → triggers multiply
    LDA.w !Obj_FrameBank,X   ; animation data bank byte
    STA.b !Spr_FramePtr+2
    REP #$20                 ; A 16-bit
    LDA.w RDMPYL             ; RDMPYL: frame# × $78
    CLC
    ADC.w !Obj_FrameOfs,X    ; add sprite base offset
    STA.b !Spr_FramePtr      ; dp:$D3 = animation data ptr
    LDA.w !Obj_TileRecOfs,X  ; object's first tile record
    REP #$10                 ; X/Y 16-bit
    TAX                      ; X = first tile record
    SEP #$20                 ; A 8-bit
    LDY.w #!Frame_TileWordBytes*48 ; animation data start offset
    ; --- 12 records: OfsX (sign-extended), OfsY ---
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .dd28_y0p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y0h
.dd28_y0p:
    LDA #$00
.dd28_y0h:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .dd28_y1p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y1h
.dd28_y1p:
    LDA #$00
.dd28_y1h:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .dd28_y2p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y2h
.dd28_y2p:
    LDA #$00
.dd28_y2h:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .dd28_y3p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y3h
.dd28_y3p:
    LDA #$00
.dd28_y3h:
    STA.l SprTile[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsX,X
    BPL .dd28_y4p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y4h
.dd28_y4p:
    LDA #$00
.dd28_y4h:
    STA.l SprTile[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsX,X
    BPL .dd28_y5p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y5h
.dd28_y5p:
    LDA #$00
.dd28_y5h:
    STA.l SprTile[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsX,X
    BPL .dd28_y6p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y6h
.dd28_y6p:
    LDA #$00
.dd28_y6h:
    STA.l SprTile[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsX,X
    BPL .dd28_y7p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y7h
.dd28_y7p:
    LDA #$00
.dd28_y7h:
    STA.l SprTile[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsY,X
    ; record 8
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsX,X
    BPL .dd28_y8p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y8h
.dd28_y8p:
    LDA #$00
.dd28_y8h:
    STA.l SprTile[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsY,X
    ; record 9
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsX,X
    BPL .dd28_y9p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y9h
.dd28_y9p:
    LDA #$00
.dd28_y9h:
    STA.l SprTile[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsY,X
    ; record 10
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsX,X
    BPL .dd28_y10p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y10h
.dd28_y10p:
    LDA #$00
.dd28_y10h:
    STA.l SprTile[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsY,X
    ; record 11
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsX,X
    BPL .dd28_y11p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28_y11h
.dd28_y11p:
    LDA #$00
.dd28_y11h:
    STA.l SprTile[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsY,X
    ; --- Tile numbers: 8-slot block, gap +$10, 4-slot block ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y    ; base X coordinate
    STA.l SprTile.Tile,X
    INC
    INC
    STA.l SprTile[1].Tile,X
    INC
    INC
    STA.l SprTile[2].Tile,X
    INC
    INC
    STA.l SprTile[3].Tile,X
    INC
    INC
    STA.l SprTile[4].Tile,X
    INC
    INC
    STA.l SprTile[5].Tile,X
    INC
    INC
    STA.l SprTile[6].Tile,X
    INC
    INC
    STA.l SprTile[7].Tile,X
    INC
    INC
    CLC
    ADC.b #!Spr_TileRowStep  ; gap: skip $10 pixels
    STA.l SprTile[8].Tile,X
    INC
    INC
    STA.l SprTile[9].Tile,X
    INC
    INC
    STA.l SprTile[10].Tile,X
    INC
    INC
    STA.l SprTile[11].Tile,X
    ; --- attribute bytes ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTile.Attr,X
    STA.l SprTile[1].Attr,X
    STA.l SprTile[2].Attr,X
    STA.l SprTile[3].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile[4].Attr,X
    STA.l SprTile[5].Attr,X
    STA.l SprTile[6].Attr,X
    STA.l SprTile[7].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile[8].Attr,X
    STA.l SprTile[9].Attr,X
    STA.l SprTile[10].Attr,X
    STA.l SprTile[11].Attr,X
    LDX.b !Obj_Cur
    LDA.b #!ObjState_Ready
    STA.w !Obj_State,X
    SEP #$10
    CLC
    RTS
    ; ---- alt path ($DF2F): for Obj_VramTile == $68 ----
.dd28_alt:
    LDA.w !Obj_LastFrame,X   ; animation frame number
    STA.w WRMPYA             ; WRMPYA
    LDA.b #!Frame12_Bytes    ; multiply by $78 = 120
    STA.w WRMPYB             ; WRMPYB
    LDA.w !Obj_FrameBank,X   ; animation data bank byte
    STA.b !Spr_FramePtr+2
    REP #$20                 ; A 16-bit
    LDA.w RDMPYL             ; RDMPYL: frame# × $78
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    LDA.w !Obj_TileRecOfs,X  ; OAM buffer index from ROM table
    REP #$10                 ; X/Y 16-bit
    TAX
    SEP #$20                 ; A 8-bit
    LDY.w #!Frame_TileWordBytes*48 ; animation data start offset
    ; --- 12 OAM tile-entry groups (stride $08, same as main path) ---
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .dd28a_y0p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y0h
.dd28a_y0p:
    LDA #$00
.dd28a_y0h:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .dd28a_y1p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y1h
.dd28a_y1p:
    LDA #$00
.dd28a_y1h:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .dd28a_y2p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y2h
.dd28a_y2p:
    LDA #$00
.dd28a_y2h:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .dd28a_y3p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y3h
.dd28a_y3p:
    LDA #$00
.dd28a_y3h:
    STA.l SprTile[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsX,X
    BPL .dd28a_y4p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y4h
.dd28a_y4p:
    LDA #$00
.dd28a_y4h:
    STA.l SprTile[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsX,X
    BPL .dd28a_y5p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y5h
.dd28a_y5p:
    LDA #$00
.dd28a_y5h:
    STA.l SprTile[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsX,X
    BPL .dd28a_y6p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y6h
.dd28a_y6p:
    LDA #$00
.dd28a_y6h:
    STA.l SprTile[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsX,X
    BPL .dd28a_y7p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y7h
.dd28a_y7p:
    LDA #$00
.dd28a_y7h:
    STA.l SprTile[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsY,X
    ; record 8
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsX,X
    BPL .dd28a_y8p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y8h
.dd28a_y8p:
    LDA #$00
.dd28a_y8h:
    STA.l SprTile[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsY,X
    ; record 9
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsX,X
    BPL .dd28a_y9p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y9h
.dd28a_y9p:
    LDA #$00
.dd28a_y9h:
    STA.l SprTile[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsY,X
    ; record 10
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsX,X
    BPL .dd28a_y10p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y10h
.dd28a_y10p:
    LDA #$00
.dd28a_y10h:
    STA.l SprTile[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsY,X
    ; record 11
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsX,X
    BPL .dd28a_y11p
    LDA.b #!Eng_SignExtNeg
    BRA .dd28a_y11h
.dd28a_y11p:
    LDA #$00
.dd28a_y11h:
    STA.l SprTile[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsY,X
    ; --- Tile numbers: 4-slot block, gap +$10, 8-slot block ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y    ; base X coordinate
    STA.l SprTile.Tile,X
    INC
    INC
    STA.l SprTile[1].Tile,X
    INC
    INC
    STA.l SprTile[2].Tile,X
    INC
    INC
    STA.l SprTile[3].Tile,X
    INC
    INC
    CLC
    ADC.b #!Spr_TileRowStep  ; gap: skip $10 pixels after 4th slot
    STA.l SprTile[4].Tile,X
    INC
    INC
    STA.l SprTile[5].Tile,X
    INC
    INC
    STA.l SprTile[6].Tile,X
    INC
    INC
    STA.l SprTile[7].Tile,X
    INC
    INC
    STA.l SprTile[8].Tile,X
    INC
    INC
    STA.l SprTile[9].Tile,X
    INC
    INC
    STA.l SprTile[10].Tile,X
    INC
    INC
    STA.l SprTile[11].Tile,X
    ; --- attribute bytes ---
    LDA.w !Obj_OamAttr,Y
    ORA.w !Obj_VramTileHi,Y
    STA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTile.Attr,X
    STA.l SprTile[1].Attr,X
    STA.l SprTile[2].Attr,X
    STA.l SprTile[3].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile[4].Attr,X
    STA.l SprTile[5].Attr,X
    STA.l SprTile[6].Attr,X
    STA.l SprTile[7].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y
    STA.l SprTile[8].Attr,X
    STA.l SprTile[9].Attr,X
    STA.l SprTile[10].Attr,X
    STA.l SprTile[11].Attr,X
    LDX.b !Obj_Cur
    LDA.b #!ObjState_Ready
    STA.w !Obj_State,X
    SEP #$10
    CLC
    RTS
