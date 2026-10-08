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
; Exit: M=1, X=0, DP=$0100 (PLD), DB=$00; A and X clobbered;
; Spr_TileCount left at 0; Spr_PrepareTiles and its callees write DP
; Spr_BaseX/BaseY ($C3-$C6), Spr_FirstRec ($D9) and Spr_HiBits/HiBitTmp
; ($E5-$E7). Y is
; preserved (neither this routine nor its callees touch it), which
; Oam_BuildShadow relies on: it keeps its bucket index in Y across the call.
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
.t0_entries:                ; shared low-table copy (size 0)
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
    BRA .t0_entries

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
    BRA .t0_entries

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
.t1_entries:                ; shared low-table copy (size 1)
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
    BRA .t1_entries

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
    BRL .t1_entries

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
.t2_entries:                ; shared low-table copy (size 2)
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
    BRA .t2_entries

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
    BRL .t2_entries

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
.t3_entries:                ; shared low-table copy (size 3)
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
    BRL .t3_entries

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
    BRL .t3_entries

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
; object loop ($C0:A832, $C0:A878). Counts Obj_AnimTimer down; once it
; is 0 the object tries to join the frame-build queue (ObjQ_Head /
; ObjQ_Tail, linked through Obj_QueueNext): at the head when
; Obj_Unk1100 is 0 (or 1/2 with ObjQ_Unk78 = 2), else at the tail.
; It advances to its next frame only when it actually joins:
;   - Obj_AnimColumn advances, and the new frame's duration is read
;     from bank $E4 at Obj_AnimTimeTbl + row*4 + column. A zero
;     duration ends the row: the row's first entry becomes the timer
;     and the column restarts (mode 2 counts ObjX_AnimLoops first).
; It returns at once, with no advance and the timer left at 0 (so it
; tries again on the next call), when Obj_Unk1100 bit 7 is set or the
; object is already queued: it is the head (head path), or it is the
; tail or already has an Obj_QueueNext link (tail path).
; Earlier notes described the queue as primary/secondary "focus" slots.
; On entry: M=1, X/Y 8-bit, DP=$0100 (ObjQ_* and Anim_RowAddr are dp),
; DB=$00 (the Obj_* tables are absolute), Obj_Cur = object.
; Exit: M=1, X/Y 8-bit, DP and DB unchanged; A clobbered, X = Obj_Cur;
; Anim_RowAddr is scratch.
; ============================================================
org $C0C98A
Obj_AnimTickAndQueue:
    LDX.b !Obj_Cur
    LDA.w !Obj_AnimTimer,X
    BEQ .tick_done        ; already 0 (an earlier tick could not queue)
    DEC.w !Obj_AnimTimer,X
    BEQ .tick_done        ; just ran out
.rts:
    RTS                   ; still counting, or cannot queue now
.tick_done:
    LDA.w !Obj_Unk1100,X
    BEQ .queue_head       ; 0 → join at the head
    BMI .rts              ; bit 7 → skip
    CMP #$01
    BEQ .kind_1_or_2
    CMP #$02
    BEQ .kind_1_or_2
    CPX.b !ObjQ_Tail      ; any other value → join at the tail
    BEQ .rts              ; already the tail
    LDA.b !ObjQ_Tail
    BMI .append_tail      ; empty queue
    LDA.w !Obj_QueueNext,X
    BPL .rts              ; already linked into the queue
.append_tail:
    TXA                   ; A = this object
    LDX.b !ObjQ_Tail
    CPX.b #!ObjQ_Empty
    BPL .start_queue2     ; empty: this object becomes head and tail
    STA.w !Obj_QueueNext,X ; old tail → this object
    STA.b !ObjQ_Tail
    TAX
    INC.w !Obj_AnimColumn,X ; next frame
    BRA .do_anim
.start_queue1:            ; from .queue_head when the queue is empty
    TXA
.start_queue2:
    STA.b !ObjQ_Tail      ; only entry: head and tail
    STA.b !ObjQ_Head
    TAX
    INC.w !Obj_AnimColumn,X
    BRA .do_anim
.queue_head:
    CPX.b !ObjQ_Head
    BEQ .rts              ; already the head
    LDA.b !ObjQ_Head
    BMI .start_queue1     ; empty queue
    STA.w !Obj_QueueNext,X ; this object → old head
    STX.b !ObjQ_Head
    INC.w !Obj_AnimColumn,X
    BRA .do_anim
.kind_1_or_2:
    LDA.b !ObjQ_Unk78
    CMP #$02
    BNE .queue_tail2
    STZ.b !ObjQ_Unk78     ; one-shot: this object joins at the head
    BRA .queue_head
.queue_tail2:             ; same tail join as above
    CPX.b !ObjQ_Tail
    BEQ .rts
    LDA.b !ObjQ_Tail
    BMI .append_tail2
    LDA.w !Obj_QueueNext,X
    BPL .rts
.append_tail2:
    TXA
    LDX.b !ObjQ_Tail
    CPX.b #!ObjQ_Empty
    BPL .start_queue2
    STA.w !Obj_QueueNext,X
    STA.b !ObjQ_Tail
    TAX
    INC.w !Obj_AnimColumn,X
.do_anim:
    LDX.b !Obj_Cur
    LDA.w !Obj_AnimMode,X
    BEQ .use_row          ; modes 0 and 1: Obj_AnimRow
    DEC
    BEQ .use_row
    LDA.w !Obj_AnimRowAlt,X ; mode 2 and up: Obj_AnimRowAlt
    BRA .got_row
.use_row:
    LDA.w !Obj_AnimRow,X
.got_row:
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL
    ASL                   ; 4 frames per row
    CLC
    ADC.w !Obj_AnimTimeTbl,X
    STA.b !Anim_RowAddr   ; this row's durations in bank $E4
    LDA.w !Obj_AnimColumn,X
    AND.w #!Eng_LowByteMask
    ADC.b !Anim_RowAddr   ; carry is clear from the ADC above
    REP #$10
    TAX                   ; X = the new frame's duration entry
    SEP #$20
    LDA.l !AnimRom,X
    BNE .got_frame        ; nonzero → it is the new timer
    LDX.b !Anim_RowAddr   ; 0 ends the row: use its first entry
    LDA.l !AnimRom,X
    SEP #$10
    LDX.b !Obj_Cur
    STA.w !Obj_AnimTimer,X
    LDA.w !Obj_AnimMode,X
    CMP #$02
    BNE .mode_simple      ; not mode 2: restart the row
    LDA.l !ObjX_AnimLoops,X ; mode 2: count the loops down
    DEC
    BEQ .loop_end         ; was 1
    DEC
    BEQ .loop_one         ; was 2
    STA.l !ObjX_AnimLoops,X ; was 3 or more: two fewer, restart the row
    STZ.w !Obj_AnimColumn,X
    RTS
.loop_one:
    INC
    STA.l !ObjX_AnimLoops,X ; leave it at 1
.loop_end:
    DEC.w !Obj_AnimColumn,X ; back to the row's last frame
    RTS
.mode_simple:
    STZ.w !Obj_AnimColumn,X
    RTS
.got_frame:               ; X still 16-bit here
    SEP #$10
    LDX.b !Obj_Cur
    STA.w !Obj_AnimTimer,X
    RTS

; ============================================================
; $C0:CA76 — Field_ProcessAnimQueue (99 bytes, $CA76–$CAD8)
; Builds queued object frames while there is time left in the frame,
; called from Field_EndOfFrame ($C0:00D6). Does nothing while the VRAM
; upload queue from an earlier build is still pending (VramQ_Valid
; nonzero). Otherwise, while the V counter is at line 240 or later
; or below ObjQ_ScanlineLimit, it takes the queue head into Obj_Cur and
; runs Obj_BuildSpriteFrameStep; when that returns C=0 (step finished)
; the head is unlinked (Obj_QueueNext = $80) and the queue advances;
; C=1 retries the same object.
; On entry: M=1, X/Y 8-bit, DP=$0100 (ObjQ_* are dp), DB=$00 (the
; Obj_* tables, VramQ_Valid and the PPU ports are absolute).
; Exit: M=1, X/Y 8-bit, DP and DB unchanged; A and X clobbered, Y as
; the frame builders leave it; Obj_Cur = the last object built.
; ============================================================
org $C0CA76
Field_ProcessAnimQueue:
    LDA.w !VramQ_Valid
    BEQ .proceed
    RTS                   ; an upload is still pending: build nothing
.proceed:
    REP #$10              ; (no effect: undone by the next instruction)
    SEP #$10
    STZ.b !VramQ_Pos      ; start a new VRAM upload queue
    LDA.w STAT78          ; reset the OPVCT read flip-flop
.latch:                   ; read the V counter before each step
    LDA.w SLHV            ; latch H/V
    LDA.w OPVCT           ; low 8 bits
    XBA
    LDA.w OPVCT           ; bit 0 = bit 8 of V
    AND #$01
    XBA
    REP #$20              ; A = 9-bit V counter
    CMP.w #!Ppu_FirstHiddenLine
    BPL .in_window        ; line 240 or later: blanking, keep going
    CMP.b !ObjQ_ScanlineLimit
    BCS .exit_sep         ; reached ObjQ_ScanlineLimit: stop for this frame
.in_window:
    LDA #$0000            ; clear B
    SEP #$20
    LDA.b !ObjQ_Head
    BMI .exit_rts         ; queue empty
    STA.b !Obj_Cur
    LDA.b !ObjQ_Head
    CMP.b !ObjQ_Tail
    BEQ .same_slot        ; only one object queued
    JSR Obj_BuildSpriteFrameStep
    BCS .latch            ; C=1: not finished, run it again
    LDA.b !ObjQ_Head      ; finished: unlink the head
    TAX
    LDA.w !Obj_QueueNext,X
    STA.b !ObjQ_Head
    LDA.b #!ObjQ_Empty
    STA.w !Obj_QueueNext,X
    BRA .latch
.same_slot:               ; ObjQ_Head == ObjQ_Tail
    JSR Obj_BuildSpriteFrameStep
    BCS .latch
    LDA.b !ObjQ_Head      ; finished: the queue is now empty
    TAX
    LDA.b #!ObjQ_Empty
    STA.w !Obj_QueueNext,X
    STA.b !ObjQ_Head
    STA.b !ObjQ_Tail
    BRA .latch
.exit_rts:
    RTS
.exit_sep:
    SEP #$20
    RTS

; ============================================================
; $C0:CAD9 — Obj_BuildSpriteFrameStep (49 bytes, $CAD9–$CB09)
; One step of building object Obj_Cur's current frame, graphics
; included: skips (C=0) unless Obj_Unk1100 bit 7 is clear,
; Obj_Unk1A81 is 1..$7F and Obj_Unk0F00 is nonzero; then by size class
; tail-calls Obj_BuildFrame4 / 8 / 12 (size 3: C=0, nothing).
; C=1 from a builder means "call again" (a multi-pass build).
; Called by Field_ProcessAnimQueue ($C0:CAAE, $C0:CAC2) and the
; unmatched map-load pass at $C0:B0E6 ($C0:B109).
; On entry: M=1, X/Y 8-bit, DP=$0100 (Obj_Cur is dp), DB=$00 (the
; Obj_* tables are absolute), Obj_Cur = object.
; Exit: M=1, X/Y 8-bit, DP and DB unchanged (also through the
; builders, which BRL tail calls reach); C as above; A and X clobbered
; (X = Obj_Cur on the skip paths), Y as the builder leaves it.
; ============================================================
org $C0CAD9
Obj_BuildSpriteFrameStep:
    LDX.b !Obj_Cur
    LDA.w !Obj_Unk1100,X
    BPL .active           ; bit 7 set: skip
.no_carry_rts:            ; shared C=0 exit: nothing to build
    CLC
    RTS
.active:
    LDA.w !Obj_Unk1A81,X  ; meaning unknown; must be 1..$7F
    BEQ .no_carry_rts
    BMI .no_carry_rts
    LDA.w !Obj_Unk0F00,X  ; meaning unknown; 0 = no frame to build
    BEQ .no_carry_rts
    LDA.w !Obj_SprSize,X  ; size class
    AND.b #!ObjSpr_SizeMask ; isolate bits 0-1
    BEQ .type0            ; 0 → 4-tile builder
    CMP #$01
    BNE .check2
    BRA .type1            ; 1 → 8-tile builder
.check2:
    CMP #$02
    BEQ .type2            ; 2 → 12-tile builder
    CLC
    RTS                   ; 3 → nothing, C=0
.type0:
    BRL Obj_BuildFrame4
.type1:
    BRL Obj_BuildFrame8
.type2:
    BRL Obj_BuildFrame12

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
; from SprTileSrc, then X, the two high-table bytes and Y are set. Y
; clamps: Spr_BaseYHi != 0 keeps only a carried result of $E0-$FF;
; Spr_BaseY bit 7 set turns $E0-$FF into Oam_HiddenY; bit 7 clear turns
; $80-$DF into Oam_HiddenY for every record.
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
;   bit 7 clear           $80-$DF → Oam_HiddenY.
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
; reads Obj_SprSize itself; "size 3" is inferred from the 24 records it
; fills, which only Spr_Place24 (size 3) re-places, and from its caller
; at $C0:47E9, which calls it only when Obj_SprSize & 3 = 3.
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
; On entry: X = Obj_Cur (8- or 16-bit: the $C0:47E9 caller runs with X
; 8-bit; the routine widens X/Y itself), M=1, DP=$0100, DB=$00 (absolute
; object-table loads and DMA register stores). Callers (both JSR):
; Field_RestoreState ($C0:0212) for Field_UnkAEObj, and unmatched object
; set-up code at $C0:47E9, which first stores the object in
; Field_UnkAEObj.
; Exit: M=1, X/Y 16-bit, DP and DB unchanged; A, X and Y clobbered;
; Obj_LastFrame of the object set to 0; DP Spr_GfxPtr, Spr_WramPtr,
; Spr_FramePtr, Spr_TileCount and (in the tile copiers) Spr_SavedY
; written; WMADD, VMADD and DMA channel 7
; registers written.
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
    BNE .flipped_tile
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next_iter
    BRA .dma
.flipped_tile:          ; SprFrame_HFlip set: mirrored copy
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
; Callers (15 JSR sites): Obj_BuildFrame4 ($C0:CC6F), Obj_BuildFrame8
;   ($C0:CF8F), Obj_BuildFrame8Pass0 ($C0:D2FB), Obj_BuildFrame8Pass1
;   ($C0:D367), Obj_BuildFrame12Pass0 ($C0:D5B7, $C0:D5F6),
;   Obj_BuildFrame12Pass0Alt ($C0:D679), Obj_BuildFrame12Pass1 ($C0:D6E7,
;   $C0:D726), Obj_BuildFrame12Pass1Alt ($C0:D794, $C0:D7D3),
;   Obj_BuildFrame12Pass2 ($C0:D83F), Obj_BuildFrame12Pass2Alt ($C0:DAC3,
;   $C0:DAFE) and Spr_LoadLargeObj ($C0:E18D).
; On entry: M=0, X/Y 16-bit (TAY of tile*32), A = frame-data tile word
; (bit 14 set), Y = frame-data index, WMADD already at the destination,
; DP=$0100 (Spr_GfxPtr, Spr_SavedY are dp), DB=$00.
; Exit: M=0, Y restored from Spr_SavedY; X clobbered.
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
; Callers (15 JSR sites): Obj_BuildFrame4 ($C0:CC64), Obj_BuildFrame8
;   ($C0:CF84), Obj_BuildFrame8Pass0 ($C0:D2F0), Obj_BuildFrame8Pass1
;   ($C0:D35C), Obj_BuildFrame12Pass0 ($C0:D5AC, $C0:D5EB),
;   Obj_BuildFrame12Pass0Alt ($C0:D66E), Obj_BuildFrame12Pass1 ($C0:D6DC,
;   $C0:D71B), Obj_BuildFrame12Pass1Alt ($C0:D789, $C0:D7C8),
;   Obj_BuildFrame12Pass2 ($C0:D834), Obj_BuildFrame12Pass2Alt ($C0:DAB8,
;   $C0:DAF3) and Spr_LoadLargeObj ($C0:E182).
; On entry: M=0, X/Y 16-bit (TAX of the source offset, LDY of the
; destination), A = frame-data tile word (bit 14 clear), Y = frame-data
; index, DP=$0100 (Spr_GfxPtr, Spr_WramPtr, Spr_SavedY are dp), DB=$00
; (the WMADDL store after the PLB).
; Exit: M=0, Y restored from Spr_SavedY, X clobbered, WMADD just past
; the copied tile; the four bank copiers below end the same way.
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
; On entry (from Spr_CopyTile's BRL): M=1, X/Y 16-bit, X = source
; offset in bank $D4, Y = destination address in bank $7F, DP=$0100
; (Spr_SavedY holds the caller's frame-data index), DB=$00 (restored by
; the PLB before the WMADDL store); A is overwritten at once.
; Exit: M=0, X/Y 16-bit, DB unchanged, Y = Spr_SavedY, X unchanged
; (source offset), A = destination + 32, WMADD just past the tile.
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
; On entry (from Spr_CopyTile's BRL): M=1, X/Y 16-bit, X = source
; offset in bank $D2, Y = destination address in bank $7F, DP=$0100
; (Spr_SavedY holds the caller's frame-data index), DB=$00 (restored by
; the PLB before the WMADDL store); A is overwritten at once.
; Exit: M=0, X/Y 16-bit, DB unchanged, Y = Spr_SavedY, X unchanged
; (source offset), A = destination + 32, WMADD just past the tile.
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
; On entry (from Spr_CopyTile's BRL): M=1, X/Y 16-bit, X = source
; offset in bank $D3, Y = destination address in bank $7F, DP=$0100
; (Spr_SavedY holds the caller's frame-data index), DB=$00 (restored by
; the PLB before the WMADDL store); A is overwritten at once.
; Exit: M=0, X/Y 16-bit, DB unchanged, Y = Spr_SavedY, X unchanged
; (source offset), A = destination + 32, WMADD just past the tile.
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
; On entry (from Spr_CopyTile's BRL): M=1, X/Y 16-bit, X = source
; address in bank $7F, Y = destination address in bank $7F, DP=$0100
; (Spr_SavedY holds the caller's frame-data index), DB=$00 (restored by
; the PLB before the WMADDL store); A is overwritten at once.
; Exit: M=0, X/Y 16-bit, DB unchanged, Y = Spr_SavedY, X unchanged
; (source address), A = destination + 32, WMADD just past the tile.
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
; Callers: BRL from Obj_ResetStates ($C0:B1AF), and JSR from
; DefaultHandler after a battle ($C0:18C7), Scene_ReloadStep
; ($C0:2878) and Scene_PostLoadInit ($C0:56B9).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y). DP is saved and restored;
; DB does not matter (the stores are dp).
; Exit: M=1, X=0, DP and DB unchanged; A = Obj_None, X and Y preserved.
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
; Called from Obj_BuildFrame4 ($C0:CC0D, its only caller).
; On entry: M=1 (8-bit A), X/Y 8-bit, DP=$0100 (Obj_Cur is dp), DB=$00
; (SprBuf_Owner and Obj_TileBuf are absolute).
; Exit: M=1, X/Y 8-bit, DP and DB unchanged; A clobbered; X = Obj_Cur
; on success, 4 on failure; Y preserved.
; ============================================================
org $C0E952
SprBuf_Alloc1:
    LDX #$00
.loop:
    LDA.w !SprBuf_Owner,X
    BPL .next
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
.next:
    INX
    CPX #$04
    BMI .loop       ; loop for entries 0–3
    CLC                  ; all taken
    RTS

; ============================================================
; $C0:E97A — SprBuf_Alloc2 (48 bytes, $E97A–$E9A9)
; (was Sub_E97A.) As SprBuf_Alloc1 for two adjacent free chunks
; (start entries 0-2). Called from Obj_BuildFrame8 ($C0:CF2D) and
; Obj_BuildFrame8Pass0 ($C0:D299).
; On entry: M=1 (8-bit A), X/Y 8-bit, DP=$0100 (Obj_Cur is dp), DB=$00
; (SprBuf_Owner and Obj_TileBuf are absolute).
; Exit: M=1, X/Y 8-bit, DP and DB unchanged; C=1 on success with
; X = Obj_Cur, C=0 with X = 3 when no two adjacent chunks are free;
; A clobbered, Y preserved.
; ============================================================
org $C0E97A
SprBuf_Alloc2:
    LDX #$00
.loop:
    LDA.w !SprBuf_Owner,X
    BPL .next
    LDA.w !SprBuf_Owner+1,X
    BPL .next
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
.next:
    INX
    CPX #$03             ; search entries 0–2 (3 positions)
    BMI .loop
    CLC
    RTS

; ============================================================
; $C0:E9AA — SprBuf_Alloc3 (56 bytes, $E9AA–$E9E1)
; (was Sub_E9AA.) As SprBuf_Alloc1 for three adjacent free chunks
; (start entries 0-1). Called from Obj_BuildFrame12Pass0 ($C0:D555)
; and Obj_BuildFrame12Pass0Alt ($C0:D617).
; On entry: M=1 (8-bit A), X/Y 8-bit, DP=$0100 (Obj_Cur is dp), DB=$00
; (SprBuf_Owner and Obj_TileBuf are absolute).
; Exit: M=1, X/Y 8-bit, DP and DB unchanged; C=1 on success with
; X = Obj_Cur, C=0 with X = 2 when no three adjacent chunks are free;
; A clobbered, Y preserved.
; ============================================================
org $C0E9AA
SprBuf_Alloc3:
    LDX #$00
.loop:
    LDA.w !SprBuf_Owner,X
    BPL .next
    LDA.w !SprBuf_Owner+1,X
    BPL .next
    LDA.w !SprBuf_Owner+2,X
    BPL .next
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
.next:
    INX
    CPX #$02             ; only entries 0–1 for triple allocation
    BMI .loop
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

; ============================================================
; $C0:EA1F — SprBuf_Free3 (35 bytes, $EA1F–$EA41)
; (was Sub_EA1F.) As SprBuf_Free1 for a 3-chunk object (2 possible
; start entries). Run by Spr_PrepareTiles after Spr_Load12 (JSR at
; $C0:B76E, its only caller).
; On entry: M=1, X/Y 16-bit, DP=$0100 (Obj_Cur is dp), DB=$00.
; Exit: M=1, X/Y 16-bit (set again on both paths), DP and DB unchanged;
; A clobbered, X = the start entry found (or 2), Y preserved. Same dead
; LDX.b !Obj_Cur as SprBuf_Free1.
; ============================================================
org $C0EA1F
SprBuf_Free3:
    SEP #$10                ; X → 8-bit
    LDX.b !Obj_Cur          ; (discarded; immediately overwritten)
    LDX #$00
.loop:
    LDA.w !SprBuf_Owner,X
    CMP.b !Obj_Cur
    BEQ .found
    INX
    CPX #$02                ; start entries 0-1
    BNE .loop
    REP #$10                ; X → 16-bit (no match)
    RTS
.found:
    LDA.b #!Obj_None
    STA.w !SprBuf_Owner,X   ; free all three chunks
    STA.w !SprBuf_Owner+1,X
    STA.w !SprBuf_Owner+2,X
    REP #$10                ; X → 16-bit
    RTS

; ============================================================
; $C0:0000 — ReentryVectors (14 bytes)
; Mid-game re-entry vector table at the start of the bank. The BRA/BRL
; tail-dispatches to the target routine.
;   [0] is entered by JML (from $C2:2505, $C2:8349 and $FD:DA5B/DABA/
;       DB19/DB93) and by BRL from $C0:0CC4 and $C0:3B95; it never returns.
;   [1]-[4] are entered by JSL (one call site each in the ROM), and the
;       target's RTL returns straight to that caller.
;   [0] $0000  BRA → GameLoop_Main  (warm restart)
;   [1] $0002  JSL → ScrollStepAccum  ($C0:2C41)
;   [2] $0005  JSL → AudioDrvSync     ($C0:0AFF)
;   [3] $0008  JSL → MusicCueDispatch ($C0:1BAB)
;   [4] $000B  JSL → AudioFadeDispatch($C0:1BE6)
; Entry: each entry only branches, so the state is the target's: [0] as
;        GameLoop_Main expects (it sets DB itself); [1]-[4] the JSL
;        caller's state, passed through unchanged.
; Exit: [0] never returns; [1]-[4] the target's RTL returns to the JSL
;       caller with whatever state the target leaves.
; ============================================================
org $C00000

ReentryVectors:
    BRA GameLoop_Main       ; [0] warm restart — skip init, enter frame loop
    BRL ScrollStepAccum     ; [1] $C0:2C41
    BRL AudioDrvSync        ; [2] $C0:0AFF
    BRL MusicCueDispatch    ; [3] $C0:1BAB
    BRL AudioFadeDispatch   ; [4] $C0:1BE6

; ============================================================
; $C0:000E — GameLoop: full (cold) init, then the game loop
; Installs the interrupt trampolines, clears WRAM, starts the sound
; driver and bank $C2, then falls into GameLoop_Main. Reached twice
; over: at boot by JML $C0:000E from MainInit ($FD:C0D3), with DP=$2100,
; and by BRL from $C0:02CA (in Scene_Unk0283, after InitHW and
; S=$06FF), with DP=$0100. It sets M, X and DP itself, so only DB
; matters on entry.
; On entry: DB=$00 (InstallNMI/InstallIRQ store absolute before InitHW
; runs; from boot or set by InitHW at $C0:02C3).
; Exit: never returns; falls into GameLoop_Main with M=1, X=0,
; DP=$0100, DB=$00.
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

; GameLoop_Main ($C0:005D): warm-restart entry. Reinstalls the interrupt
; trampolines and dispatches on Loc_Id. Reached by:
;   - falling out of GameLoop;
;   - BRL GameLoop_Main at $C0:0301 (Scene_Unk0283, after S=$06FF);
;   - ReentryVectors[0] (BRA here), which is reached by JML $C0:0000
;     from banks $C2 ($C2:2505, $C2:8349) and $FD ($FD:DA5B, $FD:DABA,
;     $FD:DB19, $FD:DB93), and by BRL ReentryVectors at $C0:0CC4
;     (Field_SceneChangeTick's warp) and $C0:3B95, both after S=$06FF.
; None of these return, so neither does this.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y). DB is set to $00 by
; InitHW. DP is not known here (DP=$0100 when falling out of GameLoop,
; anything on a JML from another bank), so Loc_Id is read as the
; absolute address !DP_Field+!Loc_Id; GameLoop_LoadField sets DP=$0100.
; Exit: never returns; JML BankC2_Entry0000, BRL Sys_HaltWithColor, or into
; GameLoop_LoadField.
GameLoop_Main:
    JSR InitHW              ; forced blank, disable NMI/DMA
    JSR InstallNMI          ; reinstall NMI handler
    JSR InstallIRQ          ; reinstall IRQ handler

    ; Dispatch on the location index (Loc_Id, WRAM $0100, 16-bit)
    LDX.w !DP_Field+!Loc_Id
    CPX.w #!Loc_FirstBankC2
    BMI GameLoop_NotBankC2
    JML BankC2_Entry0000    ; Loc_Id $01F0-$81EF → handled in bank $C2

; GameLoop_NotBankC2 (was GL_ModeOk1): reached when bit 15 of
; Loc_Id - Loc_FirstBankC2 is set. Both tests (here and in GameLoop_Main)
; are CPX then BMI, which branch on bit 15 of the 16-bit difference, not
; a signed compare. Taken together:
;   Loc_Id $0000-$01EF  -> GameLoop_LoadField
;   Loc_Id $01F0-$81EF  -> bank $C2 (GameLoop_Main's JML)
;   Loc_Id $81F0-$81FE  -> Sys_HaltWithColor, with X = Halt_ColorBadLoc
;   Loc_Id $81FF-$FFFF  -> GameLoop_LoadField
; So Sys_HaltWithColor needs bit 15 of Loc_Id set; what sets it is not traced yet.
; On entry: M=1, X=0, X = Loc_Id (from GameLoop_Main's BMI), DB=$00.
; Exit: never returns; BRL Sys_HaltWithColor or into GameLoop_LoadField.
GameLoop_NotBankC2:
    CPX.w #!Loc_HaltLimit
    BMI GameLoop_LoadField
    LDX.w #!Halt_ColorBadLoc
    BRL Sys_HaltWithColor

; GameLoop_LoadField (was GL_ModeOk2): loads the field location Loc_Id
; and falls into the per-frame loop. Scene_SettleFrames runs
; Scene_ReloadStep once; if that returns zero it then raises
; Fade_Brightness one step per frame (Field_FrameUpdate,
; Field_EndOfFrame, frame wait) until it reaches $0F.
; On entry: M=1, X=0, DB=$00; DP is set to $0100 here.
; Exit: never returns (falls into GameLoop_FrameBody).
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
    JSR Scene_SettleFrames  ; reload step, then fade in to full brightness

; GameLoop_FrameBody: the per-frame field loop. Latches newly pressed
; buttons, runs the frame's field work in order, then Field_EndOfFrame
; and the frame wait, and loops; it never exits (scene changes leave
; through the warps reached from its callees, which reset the stack).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: never returns.
GameLoop_FrameBody:
    LDA.w !Pad_Pressed
    TSB.b !Pad_PressedLatch ; accumulate newly pressed buttons
    LDA.w !Pad_Unk00F6
    TSB.b !Pad_Unk00F6Latch ; accumulate Pad_Unk00F6
    JSR Field_PauseAndMenuInput
    JSR Field_SceneChangeTick
    JSR Field_FrameUpdate
    JSR Field_ActionButton
    JSL Field_Unk1F87
    JSR Field_EventHookDispatch
    JSR Field_ServiceUnk54
    JSR Field_EndOfFrame    ; end-of-frame work and OAM shadow build
    JSR Sub_EC60            ; wait for the NMI (the frame wait)
    BRA GameLoop_FrameBody

; ============================================================
; $C0:00BF — Field_EndOfFrame (was VBlankHandler)
; End-of-frame work, called once per frame just before Sub_EC60 waits
; for the NMI; it is not an interrupt handler and waits for nothing
; itself. Callers: GameLoop_FrameBody ($C0:00B7), DefaultHandler's
; map-redraw loop ($C0:1784) and Scene_SettleFrames ($C0:285A); those
; are all the JSR sites. Runs the Vblank_* helpers,
; EngFD_UnkC2C1, FdVec_FFF7 (ticks the counter table at $0520),
; Field_ProcessAnimQueue, then tail-jumps to Oam_BuildShadow, whose RTS
; returns to this routine's caller.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit (from Oam_BuildShadow): M=1, X=0, DP and DB unchanged; A, X, Y
; and Obj_Cur clobbered.
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
; FdVec_FFF7 part of Field_EndOfFrame only, for the fade and idle loops.
; Callers: 21 JSR sites: Field_IdleFrame ($C0:00EE),
; Field_FadeInAfterReload ($C0:2836), 11 in DefaultHandler
; ($C0:17B0-$C0:189D) and 8 in unmatched code at $C0:261E-$C0:271F
; (e.g. $C0:261E, $C0:262B, $C0:271F).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100. Sets 8-bit X/Y
; around EngFD_UnkC2C1, which needs it.
; Exit: M=1, X=0; A, X, Y as the two bank-$FD routines leave them.
Field_EndOfFrameShort:
    SEP #$10
    JSL EngFD_UnkC2C1
    REP #$10
    JSL FdVec_FFF7
    RTS

; Field_IdleFrame (was Sub_00EB): one frame of field upkeep without
; game logic: Field_FrameUpdate, Field_EndOfFrameShort, Sub_EC60 (tail
; jump, whose RTS returns to this routine's caller).
; Callers (8 sites: 5 JSR, 3 BRL): DefaultHandler ($C0:18CA, $C0:18D6) and
;   unmatched code at $C0:02AA, $C0:0319, $C0:0327, $C0:0340, $C0:0365,
;   $C0:038C.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100 (needed by
; Field_EndOfFrameShort), DB=$00.
; Exit: via Sub_EC60: M=1, X=0, DP=$0100; A = 0 (Sub_EC60's wait);
; X and Y are whatever the callees leave (not saved here).
Field_IdleFrame:
    JSR Field_FrameUpdate
    JSR Field_EndOfFrameShort
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

; ============================================================
; $C0:00F4 — LoadLocation (39 bytes, $00F4–$011A)
; One-time location-load called once per scene entry from
; GameLoop_LoadField (its only caller, JSR at $C0:0088).
; Calls 10 location-load steps (JSR) and two bank-$FD service vectors.
; NOT called per frame — only when entering a new location/map.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP=$0100 as far as is known: the steps are unmatched,
; and GameLoop_LoadField carries on without resetting any of them.
; A, X and Y are not saved.
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
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00 (the
; Obj_* tables and Field_Unk1DF9 are read absolute).
; Exit: M=1, X=0, DP and DB unchanged; A, X and Y clobbered.
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
; Callers (JSR): Field_SceneChangeTick ($C0:0D2D), Field_PauseAndMenuInput
;   ($C0:1975) and Field_RunBankC2Mode5 ($C0:19E3).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00 (the
; Obj_* tables and Field_Unk1DF9 are written absolute).
; Exit: M=1, X=0, DP=$0100 (as the unmatched load steps leave it);
; A, X and Y clobbered, and Obj_Cur = Field_UnkAEObj when step 7 ran.
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
; $C0:024C — Scene_Unk024C (55 bytes, $024C–$0282)
; The check DefaultHandler makes before starting a battle (its
; SceneFlag_Battle path): C=1 means no battle after all, and
; DefaultHandler then clears the flag; C=0 goes on to the battle.
; Field_Unk0617 (8-bit X/Y) fills the list at Field_BattleObjList with
; the objects found for it, $80-terminated (inferred from reading
; $C0:0617, not matched). If the list is empty, Field_Unk034B runs and
; C=1. Otherwise the field is saved much as Field_SaveState starts: if
; Field_Unk29 is set it is cleared here (Field_SaveState forces it to 1
; instead) along with Field_Unk26/27, then Field_Unk038F, then
; Field_StashSaveBlock, and the leader's tile X/Y and facing become the
; entry point (Loc_EntryX/Y/Facing); C=0. From the Field_Unk29 test to
; the facing store this is Field_SaveState's opening, with the value
; stored to Field_Unk29 changed ($00 for $01) and JSR Field_Unk038F
; added before Field_StashSaveBlock.
; Callers: DefaultHandler ($C0:1890) and unmatched code at $C0:2628
;   (event hook handler $C0:260E, from the Field_EventHookDispatch table).
; On entry: M=1 (8-bit A), X either width (set here), DP=$0100 (the
; Field_* and Loc_* names are dp), DB=$00 (Obj_* tables read absolute).
; Exit: M=1, X=0 as the unmatched callees leave it, DP and DB unchanged;
; C=1: no battle (list empty), C=0: field saved for the battle; A, X
; and Y clobbered.
; ============================================================
org $C0024C
Scene_Unk024C:
    SEP #$10                ; X,Y → 8-bit
    JSR Field_Unk0617       ; fill Field_BattleObjList
    REP #$10                ; X,Y → 16-bit
    LDA.b !Field_BattleObjList
    BMI .no_battle          ; first entry $80: the list is empty
    LDA.b !Field_Unk29
    BEQ .save
    LDA.b #$00
    STA.b !Field_Unk29
    LDA.b #$00
    STA.b !Field_Unk26
    STZ.b !Field_Unk27
.save:
    JSR Field_Unk038F
    JSR Field_StashSaveBlock ; Field_SaveBlock → SceneSave_Buffer
    LDY.b !Party_ObjSlot    ; leader's object (16-bit)
    LDA.w !Obj_TileX,Y
    STA.b !Loc_EntryX
    LDA.w !Obj_TileY,Y
    STA.b !Loc_EntryY
    LDA.w !Obj_Facing,Y
    STA.b !Loc_EntryFacing
    CLC                     ; C=0: go on to the battle
    RTS
.no_battle:
    JSR Field_Unk034B
    SEC                     ; C=1: no battle
    RTS

; ============================================================
; $C0:0905 — Field_RestoreSaveBlock (19 bytes, $0905–$0917)
; (was Sub_0905.) Copies SceneSave_Buffer ($7F:2000) back over
; Field_SaveBlock ($7E:0920, $14E0 bytes). Reverse of
; Field_StashSaveBlock. Called first thing in Field_RestoreState, and
; from Scene_Unk0283 ($C0:0286).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y); DP is not used.
; Exit: M=1, X=0, DB preserved (PHB/PLB around the MVN, which sets DB
; to the destination bank); A, X and Y clobbered by the MVN.
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
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y); DP is not used.
; Exit: M=1, X=0, DB preserved (PHB/PLB around the MVN, which sets DB
; to the destination bank); A, X and Y clobbered by the MVN.
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
; Disables interrupts, enables forced blank, clears NMI/DMA/HDMA, and
; sets DB=$00 (PHA/PLB), which GameLoop_Main and other callers rely on.
; Callers (14 JSR sites): GameLoop ($C0:0020), GameLoop_Main ($C0:005D),
;   Field_SceneChangeTick ($C0:0C9A, $C0:0CEA, $C0:0D1C),
;   Field_PauseAndMenuInput ($C0:1958, $C0:1964), Field_FadeToBankC2Mode5
;   ($C0:19C1), Field_RunBankC2Mode5 ($C0:19D2) and unmatched code at
;   $C0:02C3, $C0:02EA, $C0:3B76, $C0:3FD3, $C0:4186.
; On entry: M=1 (LDA #$00 is the 8-bit form), X either width; DP is not
; used. Any DB (the PLB comes before the absolute stores).
; Exit: M=1, X/Y unchanged, DB=$00, A=0, interrupts disabled (SEI).
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
; Callers (6 JSR sites): GameLoop ($C0:0012), GameLoop_Main ($C0:0060),
;   Field_SceneChangeTick ($C0:0D1F), DefaultHandler ($C0:18AB),
;   Field_PauseAndMenuInput ($C0:1967) and Field_RunBankC2Mode5 ($C0:19D5).
; On entry: M=1 (8-bit A), X=0 (16-bit X); DB=$00 (or another bank that
; maps $0500 to WRAM: the stores are absolute); DP is not used.
; Exit: M=1, X=0, DB unchanged; A and X clobbered.
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
; Callers (6 JSR sites): GameLoop ($C0:0015), GameLoop_Main ($C0:0063),
;   Field_SceneChangeTick ($C0:0D22), DefaultHandler ($C0:18AE),
;   Field_PauseAndMenuInput ($C0:196A) and Field_RunBankC2Mode5 ($C0:19D8).
; On entry: M=1 (8-bit A), X=0 (16-bit X); absolute stores, so DP
; does not matter (DB=$00 from InitHW or reset).
; Exit: M=1, X=0, DB unchanged; A and X clobbered.
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
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: the warp path never returns; the others return (or tail-jump)
; with M=1, X=0 and DP=$0100.
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
; Action button: what is in front of the leader ($C0:1CFC–$C0:1F23)
; Field_ActionButton calls Field_FindObjInFront, then always ends in
; Field_CheckTileInFront. Both pick a per-facing handler from
; Obj_Facing x 2 (0 up, 1 down, 2 left, 3 right: inferred from which
; sign of the Y / X difference each handler accepts, and from the map
; row / column it steps to; EOR 1 turns a facing around, which fits).
; ============================================================

; ------------------------------------------------------------
; $C0:1CFC — Field_FindObjInFront (90 bytes, $1CFC–$1D55)
; Looks for an object the leader can act on in the facing direction.
; Saves the leader's Obj_PosX/Y in Field_FindLeaderX/Y, then walks the
; object slots from Evt_ObjCount x 2 down to 2 (slot 0 is never tested)
; and skips a slot whose Obj_Unk0F00 is 0, whose Obj_Unk1100 has bit 7
; set, or that is the leader itself (unless its Obj_Unk1100 is
; Obj_Unk1100Seven: that path skips the leader test; the two calls are
; otherwise the same code twice). The rest are put in Field_UnkEB and
; tested by the Field_ObjInReachTable handler for the facing; the first
; one in reach wins (highest slot first).
; Quirk: the handlers subtract with SBC and no SEC, so the carry left
; here by the CMP / CPX before the call shifts the first difference by
; one (kept from the original).
; Callers: Field_ActionButton ($C0:1AD0), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00; A =
; Obj_Facing x 2 (only bits 1-2 used; B is masked off).
; Exit: M=1, X=0, DP and DB unchanged. C=1: found, X = Field_UnkEB =
; the object's slot. C=0: none, X = 0 and Field_UnkEB = $80
; (Field_UnkEBInit). A clobbered; Field_FindFacing2 ($DB/$DC) and
; Field_FindLeaderX/Y ($C3-$C6) overwritten, and the 16-bit store to
; Field_UnkEB also zeroes $01EC.
; ------------------------------------------------------------
org $C01CFC
Field_FindObjInFront:
    REP #$20
    AND.w #!Obj_FacingX2Mask
    STA.b !Field_FindFacing2
    LDA.w #!Field_UnkEBInit
    STA.b !Field_UnkEB          ; 16-bit: $EC = 0 as well
    LDX.b !Party_ObjSlot
    LDA.w !Obj_PosX,X
    STA.b !Field_FindLeaderX
    LDA.w !Obj_PosY,X
    STA.b !Field_FindLeaderY
    SEP #$30
    LDA.l !Evt_ObjCount
    ASL A
    TAX                         ; last slot (count x 2), 8-bit X
.next_slot:
    LDA.w !Obj_Unk0F00,X
    BNE .candidate
.skip:
    DEX
    DEX
    BNE .next_slot
    LDA.b #!Field_UnkEBInit
    STA.b !Field_UnkEB          ; nothing in reach
    REP #$10
    CLC
    RTS
.candidate:
    LDA.w !Obj_Unk1100,X
    BMI .skip
    CMP.b #!Obj_Unk1100Seven
    BEQ .test_any               ; leader test skipped (C=1 from the CMP)
    CPX.b !Party_ObjSlot
    BEQ .skip                   ; not the leader itself
    STX.b !Field_UnkEB
    LDX.b !Field_FindFacing2
    JSR (Field_ObjInReachTable,X)
    LDX.b !Field_UnkEB
    BCC .skip
    REP #$10
    RTS
.test_any:
    STX.b !Field_UnkEB
    LDX.b !Field_FindFacing2
    JSR (Field_ObjInReachTable,X)
    LDX.b !Field_UnkEB
    BCC .skip
    REP #$10
    RTS

; Field_ObjInReachTable: Field_FindObjInFront's reach test for each
; facing, indexed by Obj_Facing x 2.
Field_ObjInReachTable:
    dw Field_ObjInReachUp       ; 0
    dw Field_ObjInReachDown     ; 1
    dw Field_ObjInReachLeft     ; 2
    dw Field_ObjInReachRight    ; 3

; ------------------------------------------------------------
; $C0:1D5E — Field_ObjInReachUp (38 bytes, $1D5E–$1D83)
; Facing 0: the object in Field_UnkEB is in reach when it is above the
; leader (Obj_PosY - Field_FindLeaderY negative) by less than
; Field_ReachAhead and off the leader's column by less than
; Field_ReachSide. The SBCs have no SEC (the first uses the carry the
; caller left, the second the C=0 of the passed CMP) and negative
; differences are negated by EOR with Eng_Invert16 and no INC. The two
; slips cancel for a negative difference, so that bound is exact; a
; positive difference, or a caller's C=1, leaves the bound 1 unit
; generous. Never off by 2. With C=0 an object on the leader's own Y
; counts as above. Kept as found.
; Reached only through Field_ObjInReachTable (entry 0).
; On entry: M=1, X=1 (8-bit X/Y), DP=$0100, DB=$00; Field_UnkEB = the
; object's slot; Field_FindLeaderX/Y set; C as the caller left it.
; Exit: M=1, X=1, DP and DB unchanged; C=1 in reach, C=0 not;
; X = Field_UnkEB; A clobbered.
; ------------------------------------------------------------
Field_ObjInReachUp:
    REP #$20
    LDX.b !Field_UnkEB
    LDA.w !Obj_PosY,X
    SBC.b !Field_FindLeaderY    ; no SEC (quirk, see above)
    BPL Field_ObjInReach_No     ; not above the leader
    EOR.w #!Eng_Invert16
    CMP.w #!Field_ReachAhead
    BCS Field_ObjInReach_No
    LDA.w !Obj_PosX,X
    SBC.b !Field_FindLeaderX    ; C=0 here (no SEC, see above)
    BPL .dx_abs
    EOR.w #!Eng_Invert16
.dx_abs:
    CMP.w #!Field_ReachSide
    BCS Field_ObjInReach_No
    SEP #$20
    SEC
    RTS

; ------------------------------------------------------------
; $C0:1D84 — Field_ObjInReachDown (39 bytes, $1D84–$1DAA)
; Facing 1: as Field_ObjInReachUp for an object below the leader
; (Obj_PosY - Field_FindLeaderY not negative). Its tail
; Field_ObjInReach_No ($C0:1DA7, SEP #$20 / CLC / RTS) is the shared
; "not in reach" exit of all four handlers.
; Reached only through Field_ObjInReachTable (entry 1).
; On entry: M=1, X=1 (8-bit X/Y), DP=$0100, DB=$00; Field_UnkEB = the
; object's slot; Field_FindLeaderX/Y set; C as the caller left it.
; Exit: M=1, X=1, DP and DB unchanged; C=1 in reach, C=0 not;
; X = Field_UnkEB; A clobbered.
; ------------------------------------------------------------
Field_ObjInReachDown:
    REP #$20
    LDX.b !Field_UnkEB
    LDA.w !Obj_PosY,X
    SBC.b !Field_FindLeaderY
    BMI Field_ObjInReach_No     ; not below the leader
    CMP.w #!Field_ReachAhead
    BCS Field_ObjInReach_No
    LDA.w !Obj_PosX,X
    SBC.b !Field_FindLeaderX
    BPL .dx_abs
    EOR.w #!Eng_Invert16
.dx_abs:
    CMP.w #!Field_ReachSide
    BCS Field_ObjInReach_No
    SEP #$20
    SEC
    RTS
Field_ObjInReach_No:            ; header: see Field_ObjInReachDown
    SEP #$20
    CLC
    RTS

; ------------------------------------------------------------
; $C0:1DAB — Field_ObjInReachLeft (38 bytes, $1DAB–$1DD0)
; Facing 2: as Field_ObjInReachUp with X and Y swapped: in reach when
; the object is left of the leader (Obj_PosX - Field_FindLeaderX
; negative) by less than Field_ReachAhead and off its row by less than
; Field_ReachSide.
; Reached only through Field_ObjInReachTable (entry 2).
; On entry: M=1, X=1 (8-bit X/Y), DP=$0100, DB=$00; Field_UnkEB = the
; object's slot; Field_FindLeaderX/Y set; C as the caller left it.
; Exit: M=1, X=1, DP and DB unchanged; C=1 in reach, C=0 not;
; X = Field_UnkEB; A clobbered.
; ------------------------------------------------------------
Field_ObjInReachLeft:
    REP #$20
    LDX.b !Field_UnkEB
    LDA.w !Obj_PosX,X
    SBC.b !Field_FindLeaderX
    BPL Field_ObjInReach_No     ; not left of the leader
    EOR.w #!Eng_Invert16
    CMP.w #!Field_ReachAhead
    BCS Field_ObjInReach_No
    LDA.w !Obj_PosY,X
    SBC.b !Field_FindLeaderY
    BPL .dy_abs
    EOR.w #!Eng_Invert16
.dy_abs:
    CMP.w #!Field_ReachSide
    BCS Field_ObjInReach_No
    SEP #$20
    SEC
    RTS

; ------------------------------------------------------------
; $C0:1DD1 — Field_ObjInReachRight (35 bytes, $1DD1–$1DF3)
; Facing 3: as Field_ObjInReachLeft for an object right of the leader
; (Obj_PosX - Field_FindLeaderX not negative).
; Reached only through Field_ObjInReachTable (entry 3).
; On entry: M=1, X=1 (8-bit X/Y), DP=$0100, DB=$00; Field_UnkEB = the
; object's slot; Field_FindLeaderX/Y set; C as the caller left it.
; Exit: M=1, X=1, DP and DB unchanged; C=1 in reach, C=0 not;
; X = Field_UnkEB; A clobbered.
; ------------------------------------------------------------
Field_ObjInReachRight:
    REP #$20
    LDX.b !Field_UnkEB
    LDA.w !Obj_PosX,X
    SBC.b !Field_FindLeaderX
    BMI Field_ObjInReach_No     ; not right of the leader
    CMP.w #!Field_ReachAhead
    BCS Field_ObjInReach_No
    LDA.w !Obj_PosY,X
    SBC.b !Field_FindLeaderY
    BPL .dy_abs
    EOR.w #!Eng_Invert16
.dy_abs:
    CMP.w #!Field_ReachSide
    BCS Field_ObjInReach_No
    SEP #$20
    SEC
    RTS

; ------------------------------------------------------------
; $C0:1DF4 — Field_CheckTileInFront (158 bytes, $1DF4–$1E91; tail
; Field_CheckTileInFront_Start $1F0E–$1F23)
; The action button's map check: treasure on the tile in front of the
; leader. Does nothing while Field_Unk29 is set (its sequence is still
; running). The Field_TileInFrontTable handler for the leader's facing
; puts the map index of the tile in front in Field_FrontTile and
; returns C=1 when Map_TreasureIdx has bit 7 clear there. Then record
; (value & $7F) of the location, at TreasureRom +
; Map_TreasureLocRecs + n*4, must name that same tile (else nothing
; happens). Its number (record offset - Map_TreasureRec0) / 4 picks a
; Treasure_Flags bit:
; - already set: Field_Unk2A = TreasureKind_Opened;
; - else the bit is set, the tile is stepped (Field_TileStepX/Y =
;   Field_FrontTile, SceneFlag_TileStep for DefaultHandler) and the
;   contents given: gold (bit 15: amount bits 0-14 x 2, into
;   Treasure_Gold, BankC1_Entry8003 service 4, TreasureKind_Gold) or an
;   item (bits 0-8, into Treasure_ItemId, service 1,
;   TreasureKind_Item). With Treasure_Empty (bit 14) set it returns
;   right after stepping the tile: nothing given, no sequence started.
; Field_CheckTileInFront_Start then stores the kind in Field_Unk2A, the
; leader's slot in Field_Unk2E, zeroes Field_Unk32, Field_Unk30 and
; Field_Unk02A1, sets Field_Unk29 = Field_Unk29Start and
; Field54_WatchBox in Field_Unk54 (presumably the "got it" message,
; and the step undone if the leader walks out of the box; neither is
; traced). Field_CheckTileInFront_Start is reached by the BRLs at
; $C0:1E78, $C0:1E8A and $C0:1E8F above.
; Callers: Field_ActionButton ($C0:1ADC, BRL), its only call site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered; Y = the item id
; or amount when something was given, and whatever BankC1_Entry8003
; leaves (it saves P, X, DP, DB); Field_FrontTile, Field_TreasureRec
; and Eng_Scratch overwritten.
; ------------------------------------------------------------
Field_CheckTileInFront:
    LDA.b !Field_Unk29
    BNE .done
    LDX.b !Party_ObjSlot
    LDA.w !Obj_Facing,X
    ASL A
    REP #$20
    AND.w #!Obj_FacingX2Mask
    TAX
    JSR (Field_TileInFrontTable,X)
    BCS .treasure_tile
.done:
    SEP #$20
    RTS
.treasure_tile:
    REP #$20
    AND.w #!Map_TreasureIdxMask
    ASL A
    ASL A                       ; record n x 4
    CLC
    ADC.w !Map_TreasureLocRecs
    TAX
    LDA.l TreasureRom.Tile,X
    CMP.b !Field_FrontTile
    BNE .done                   ; record is for another tile
    STX.b !Field_TreasureRec
    TXA
    SEC
    SBC.w !Map_TreasureRec0
    LSR A
    LSR A
    STA.b !Eng_Scratch          ; treasure number
    LSR A
    LSR A
    LSR A
    AND.w #!Treasure_FlagByteMask
    TAX                         ; flag byte
    SEP #$20
    LDA.b !Eng_Scratch
    AND.b #!Treasure_FlagBitMask
    TAY
    LDA.w BitSet,Y
    STA.b !Eng_Scratch          ; flag bit
    LDA.l !Treasure_Flags,X
    BIT.b !Eng_Scratch
    BNE .already_opened
    ORA.b !Eng_Scratch
    STA.l !Treasure_Flags,X
    LDA.b #!SceneFlag_TileStep
    TSB.b !Field_SceneFlags
    LDX.b !Field_FrontTile
    STX.b !Field_TileStepX      ; column and row
    LDX.b !Field_TreasureRec
    REP #$20
    LDA.l TreasureRom.Contents,X
    BMI .gold
    BIT.w #!Treasure_Empty
    BEQ .item
    SEP #$20
    RTS
.item:
    AND.w #!Treasure_ItemMask
    STA.l !Treasure_ItemId
    TAY
    SEP #$20
    LDA.b #!BankC1Svc_AddItem
    JSL BankC1_Entry8003
    LDA.b #!TreasureKind_Item
    BRL Field_CheckTileInFront_Start
.gold:
    ASL A                       ; bits 0-14 x 2
    STA.w !Treasure_Gold
    TAY
    SEP #$20
    LDA.b #!BankC1Svc_AddGold
    JSL BankC1_Entry8003
    LDA.b #!TreasureKind_Gold
    BRL Field_CheckTileInFront_Start
.already_opened:
    LDA.b #!TreasureKind_Opened
    BRL Field_CheckTileInFront_Start

; Field_TileInFrontTable: Field_CheckTileInFront's tile pick for each
; facing, indexed by Obj_Facing x 2.
Field_TileInFrontTable:
    dw Field_TileInFrontUp      ; 0
    dw Field_TileInFrontDown    ; 1
    dw Field_TileInFrontLeft    ; 2
    dw Field_TileInFrontRight   ; 3

; ------------------------------------------------------------
; $C0:1E9A — Field_TileInFrontUp (45 bytes, $1E9A–$1EC6)
; Facing 0: the tile one row above the leader (Obj_TileY - 1). If its
; Map_TreasureIdx byte has bit 7 set (no treasure) it tries the tile
; two rows up instead; only this direction looks a second tile ahead.
; Reached only through Field_TileInFrontTable (entry 0). xref also
; confirms a JSL at $C9:DC13 (unmatched bank $C9); that is data that
; decodes as JSL, not a call: this routine ends in RTS, and the bytes
; around it ($9A $01 $FD $15 $2D ...) don't read as code.
; On entry: M=0 (set to 1 at once), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; C=1: A = the Map_TreasureIdx
; byte (bit 7 clear), B = its row, Field_FrontTile = its index;
; C=0: no treasure there. X clobbered.
; ------------------------------------------------------------
Field_TileInFrontUp:
    SEP #$20
    LDX.b !Party_ObjSlot
    LDA.w !Obj_TileY,X
    DEC A
    XBA
    LDA.w !Obj_TileX,X
    TAX                         ; row << 8 | column
    STX.b !Field_FrontTile
    LDA.l !Map_TreasureIdx,X
    BMI .two_up
    SEC
    RTS
.two_up:
    LDX.b !Party_ObjSlot
    LDA.w !Obj_TileY,X
    DEC A
    DEC A
    XBA
    LDA.w !Obj_TileX,X
    TAX
    STX.b !Field_FrontTile
    LDA.l !Map_TreasureIdx,X
    BMI Field_TileInFront_No
    SEC
    RTS

; ------------------------------------------------------------
; $C0:1EC7 — Field_TileInFrontDown (25 bytes, $1EC7–$1EDF)
; Facing 1: the tile one row below the leader. Its tail
; Field_TileInFront_No ($C0:1EDE, CLC / RTS) is the shared "no
; treasure" exit of all four handlers.
; Reached only through Field_TileInFrontTable (entry 1).
; On entry: M=0 (set to 1 at once), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; C=1: A = the Map_TreasureIdx
; byte (bit 7 clear), B = its row, Field_FrontTile = its index;
; C=0: no treasure there. X clobbered.
; ------------------------------------------------------------
Field_TileInFrontDown:
    SEP #$20
    LDX.b !Party_ObjSlot
    LDA.w !Obj_TileY,X
    INC A
    XBA
    LDA.w !Obj_TileX,X
    TAX
    STX.b !Field_FrontTile
    LDA.l !Map_TreasureIdx,X
    BMI Field_TileInFront_No
    SEC
    RTS
Field_TileInFront_No:           ; header: see Field_TileInFrontDown
    CLC
    RTS

; ------------------------------------------------------------
; $C0:1EE0 — Field_TileInFrontLeft (23 bytes, $1EE0–$1EF6)
; Facing 2: the tile one column left of the leader.
; Reached only through Field_TileInFrontTable (entry 2).
; On entry: M=0 (set to 1 at once), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; C=1: A = the Map_TreasureIdx
; byte (bit 7 clear), B = its row, Field_FrontTile = its index;
; C=0: no treasure there. X clobbered.
; ------------------------------------------------------------
Field_TileInFrontLeft:
    SEP #$20
    LDX.b !Party_ObjSlot
    LDA.w !Obj_TileY,X
    XBA
    LDA.w !Obj_TileX,X
    DEC A
    TAX
    STX.b !Field_FrontTile
    LDA.l !Map_TreasureIdx,X
    BMI Field_TileInFront_No
    SEC
    RTS

; ------------------------------------------------------------
; $C0:1EF7 — Field_TileInFrontRight (23 bytes, $1EF7–$1F0D)
; Facing 3: the tile one column right of the leader.
; Reached only through Field_TileInFrontTable (entry 3).
; On entry: M=0 (set to 1 at once), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; C=1: A = the Map_TreasureIdx
; byte (bit 7 clear), B = its row, Field_FrontTile = its index;
; C=0: no treasure there. X clobbered.
; ------------------------------------------------------------
Field_TileInFrontRight:
    SEP #$20
    LDX.b !Party_ObjSlot
    LDA.w !Obj_TileY,X
    XBA
    LDA.w !Obj_TileX,X
    INC A
    TAX
    STX.b !Field_FrontTile
    LDA.l !Map_TreasureIdx,X
    BMI Field_TileInFront_No
    SEC
    RTS

; Field_CheckTileInFront's tail: A = the TreasureKind_* value.
Field_CheckTileInFront_Start:   ; header: see Field_CheckTileInFront
    STA.b !Field_Unk2A
    LDA.b !Party_ObjSlot
    STA.b !Field_Unk2E
    STZ.b !Field_Unk32
    LDA.b #!Field_Unk29Start
    STA.b !Field_Unk29
    STZ.b !Field_Unk30
    LDA.b #!Field54_WatchBox
    TSB.b !Field_Unk54
    STZ.w !Field_Unk02A1
    RTS

; ============================================================
; $C0:1F24 — Fade_StepBrightness (54 bytes, $1F24–$1F59)
; (was Sub_1F24.) Brightness fade: steps Fade_Brightness one unit
; toward Fade_BrightnessTarget every Fade_BrightnessDelay+1 frames and
; clears FadeFlag_Brightness when it gets there (or reaches 0 going down).
; Called from Field_SceneChangeTick while that flag is set. The NMI
; handler writes Fade_Brightness to INIDISP ($C0:EC4E; 0 becomes forced
; blank), which fixes the name; earlier notes read this as a scroll
; tracker.
; On entry: M=1 (8-bit A), X/Y not used, DP=$0100.
; Exit: M=1; A clobbered; X, Y, DP and DB untouched.
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
; On entry: M=1 (8-bit A), X/Y not used, DP=$0100.
; Exit: M=1; A clobbered; X, Y, DP and DB untouched.
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
; $C0:2DC8 — VramDma_Upload (41 bytes, $2DC8–$2DF0)
; Copies a block to VRAM with DMA channel 7: VMADDL = VramDma_Addr,
; VMAIN = increment after the high byte, DMAP7 = VramDma_Mode, B-bus
; target VMDATAL, source VramDma_Src/SrcBank, VramDma_Size bytes. Its
; last 24 bytes (from the STA BBAD7 on) are the same instructions
; as ClearRAMDMA's, right after it, through the same argument bytes
; (VramDma_Src/SrcBank/Size are the DmaFill_* bytes under other names).
; The callers seen store VramDma_Mode = 1 (word writes); mode and target
; are not otherwise checked here.
; Callers (13 JSR, 1 BRL; all unmatched): $C0:6D61, $C0:6E1E, $C0:6E58,
;   $C0:6E84, $C0:6E9C, $C0:6EC7, $C0:6EED, $C0:6F08, $C0:6F23,
;   $C0:6F30, $C0:6F4A, $C0:6F57, $C0:6F75 and BRL from $C0:7F74 (e.g.
;   $C0:6E1E uploads $1000 bytes from $7F:5080 to VRAM $5000).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y: the address and size are
; word loads), DP=$0100 (the arguments are dp offsets, shared with
; ClearRAMDMA; not traced at every caller), DB=$00 (absolute register
; stores).
; Exit: M=1, X=0, DP and DB unchanged; A and X clobbered (A =
; MDMAEN_Ch7, X = VramDma_Size); Y preserved.
; ============================================================
org $C02DC8
VramDma_Upload:
    LDX.b !VramDma_Addr
    STX.w VMADDL
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDA.b !VramDma_Mode
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7               ; B-bus target: VMDATAL ($2118)
    LDX.b !VramDma_Src
    STX.w A1T7L
    LDA.b !VramDma_SrcBank
    STA.w A1B7
    LDX.b !VramDma_Size
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN              ; start channel 7 (the CPU halts until it is done)
    RTS

; ============================================================
; $C0:2DF1 — ClearRAMDMA (45 bytes)
; Zeros a WRAM region via DMA channel 7, sourcing from MPYL (always 0
; since M7A=M7B=0). Caller sets DmaFill_Dest / DmaFill_Bank /
; DmaFill_Size first.
; Callers (all JSR): GameLoop's three boot clears ($C0:0031, $C0:0042,
; $C0:0050), LocLoad_ClearPage1D00 ($C0:7F95) and unmatched code at
; $C0:5717, $C0:58B9 and $C0:58CA.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y: DmaFill_Dest and
; DmaFill_Size are word loads), DP=$0100 (the DmaFill_* names are dp
; offsets), DB=$00 (absolute register stores).
; Exit: M=1, X=0, DP and DB unchanged; A and X clobbered (A =
; MDMAEN_Ch7, X = DmaFill_Size); Y preserved.
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
; $C0:2E1E — Sys_HaltWithColor (73 bytes, $2E1E–$2E66)
; (was the stub LoadSavePath.) Stops the game on a single colour: the
; first 21 bytes are InitHW's body written inline (interrupts off, forced
; blank, NMI/DMA/HDMA off, DB=$00), then it also clears Field_HdmaEnable,
; turns every layer off on the main and sub screens (TM = TS = 0, so
; only the backdrop shows), sets CGRAM colour 0 (the backdrop) to X,
; points both interrupt trampolines at an RTI, enables NMI and joypad
; auto-read, sets full brightness, and spins forever with interrupts on.
; It looks like a fatal-error stop whose colour tells the cases apart:
; every caller is a BRL with its own X (blue $7C00 from
; GameLoop_NotBankC2 for Loc_Id $81F0-$81FE, $7FE0 from the six sites at
; $C0:3577-$C0:36E4, $7C1F from $C0:46D4/483D, $4010, $01F0 and $000F
; from $C0:5CB3/5CDA/5CE8, $1639 from $C0:5F71 in the handler at
; $C0:5F6E that Evt_OpcodeTable gives unused event opcodes); the
; conditions behind the other unmatched ones are not traced.
; Callers (13 BRL sites): GameLoop_NotBankC2 ($C0:007A) and unmatched
;   code at $C0:3577, $C0:35BC, $C0:3603, $C0:364A, $C0:36B1, $C0:36E4,
;   $C0:46D4, $C0:483D, $C0:5CB3, $C0:5CDA, $C0:5CE8 and $C0:5F71 (LDX
;   #$1639 / BRL at $C0:5F6E; xref marks it doubtful, as the bytes
;   before it are the opcode table, not code).
; On entry: M=1 (8-bit A), X=0 (16-bit X: the whole colour word moves
; through TXA), X = BGR555 colour; DP any (Fade_Brightness is written as
; an absolute address under DP_Field), DB any (set to $00 first).
; Exit: never returns.
; ============================================================
org $C02E1E
Sys_HaltWithColor:
    SEI
    LDA.b #$00
    PHA
    PLB                         ; DB = $00
    LDA.b #FORCED_BLANK
    STA.w INIDISP
    LDA.b #$00
    STA.w NMITIMEN
    STA.w MDMAEN
    STA.w HDMAEN
    STA.w !DP_Field+!Field_HdmaEnable
    STA.w TM                    ; no layers on the main screen
    STA.w TS                    ; nor the sub screen: only the backdrop
    STA.w CGADD                 ; CGRAM colour 0 (backdrop)
    REP #$20                    ; A → 16-bit
    TXA
    SEP #$20                    ; A → 8-bit
    STA.w CGDATA                ; colour low byte
    XBA
    STA.w CGDATA                ; colour high byte
    LDA.b #!Op_RTI
    STA.w !IrqTrampoline        ; IRQ and NMI now return at once
    LDA.b #!Op_RTI
    STA.w !NmiTrampoline
    LDA.b #!Fade_BrightnessMax
    STA.w !DP_Field+!Fade_Brightness
    LDA.b #NMI_ENABLE|AUTOJOY_ENABLE
    STA.w NMITIMEN
    LDA.b #!Fade_BrightnessMax
    STA.w INIDISP               ; forced blank off, full brightness
    CLI
.forever:
    BRA .forever

; ============================================================
; $C0:75A0 — Map_ClearBufC800 (73 bytes, $75A0–$75E8)
; (was Map_Unk75A0.) Zeroes the 2 KB WRAM buffer Map_BufC800
; ($7E:C800–$7E:CFFF) that Field_BuildC800Mode1/2/4 fill: the first MVN
; copies the 32 zero bytes at GfxRom_D2 to its start, and each later
; MVN copies the zeroed part ($C800..$C800+n-1) to the n bytes right
; after it (adjacent, not overlapping; X restarts at the buffer start
; each time, n = 32 up to 1,024), so the cleared size doubles from 64
; up to 2,048 bytes.
; Callers: Field_ServiceUnk54 ($C0:2787) and unmatched code at
; $C0:3E96.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DB any (saved); DP not
; used.
; Exit: M=1, X=0, DB unchanged (PHB/PLB around the MVNs, which set it
; to $7E); A = $FFFF (the last MVN's count ran out; B = $FF), X =
; $CC00, Y = $D000.
; ============================================================
org $C075A0
Map_ClearBufC800:
    REP #$20
    PHB
    LDX.w #!GfxRom_D2&$FFFF
    LDY.w #!Map_BufC800&$FFFF
    LDA.w #!Map_ZeroChunk-1
    MVN !Bank7E,!BankD2         ; 32 zeros -> $7E:C800  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!Map_BufC800&$FFFF
    LDA.w #!Map_ZeroChunk-1
    MVN !Bank7E,!Bank7E         ; $C800-$C81F -> $C820 (64 zeroed)  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!Map_BufC800&$FFFF
    LDA.w #!Map_ZeroChunk*2-1
    MVN !Bank7E,!Bank7E         ; 128 zeroed  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!Map_BufC800&$FFFF
    LDA.w #!Map_ZeroChunk*4-1
    MVN !Bank7E,!Bank7E         ; 256 zeroed  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!Map_BufC800&$FFFF
    LDA.w #!Map_ZeroChunk*8-1
    MVN !Bank7E,!Bank7E         ; 512 zeroed  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!Map_BufC800&$FFFF
    LDA.w #!Map_ZeroChunk*16-1
    MVN !Bank7E,!Bank7E         ; 1,024 zeroed  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!Map_BufC800&$FFFF
    LDA.w #!Map_ZeroChunk*32-1
    MVN !Bank7E,!Bank7E         ; 2,048 zeroed  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    RTS

; ============================================================
; Map layer redraws, row / column writers and edge VRAM addresses
; ($C0:75E9–$C0:8242)
; The map sits in WRAM as metatile numbers. Each 256-byte row of
; $7E:3000 holds layer 1 at +$00 (Map_TileProps), layer 2 at +$40
; (Map_Layer2Tiles), layer 3 at +$80 (Map_Layer3Tiles) and at +$C0 the
; high bits (Map_TileHiBits: bit 0 / bit 1 = bit 8 of the layer-1 /
; layer-2 number), inferred from the writers' reads. A 16x16 metatile is
; 8 bytes in Map_Meta12* (layers 1 and 2) or Map_Meta3* (layer 3): four
; tilemap words, top-left, top-right, bottom-left, bottom-right
; (inferred from which words a top / bottom and left / right half
; write). The six writers turn a run of the map into tilemap words and
; send them to WMDATA. The redraws Field_BuildC800Mode1/2/4 write a
; whole screen into Map_BufC800; the edge builders (Map_Build*, after
; this block) write one row or column into a layer's edge buffer.
; Map_UploadBuf* send Map_BufC800 to VRAM, and Sub_C07F9A with the
; Bg_*Span64x32 helpers computes the tilemap VRAM addresses of the
; edges. Layers 1-3 as in ram_engine.inc's map page notes.
; ============================================================
org $C075E9
; ------------------------------------------------------------
; $C0:75E9 — Field_BuildC800Mode1 (41 bytes, $75E9–$7611)
; Redraws layer 1 into Map_BufC800: points WMADD at $7E:C800 and writes
;   32 rows (Map_RedrawRows) of 16 metatiles (Map_RedrawLen: 32 tilemap
;   words, 64 bytes) with Map_WriteRow1, from row Map_TileOriginY and
;   column Map_TileOriginX: 2,048 bytes, the whole buffer.
; Callers: DefaultHandler ($C0:17A9, $C0:17FE, $C0:183E),
;   Field_HookLeaveToBankC3 ($C0:2617), Field_HookWinPulse ($C0:2658)
;   and unmatched code at $C0:0A96.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00
;   (WMADDL/H here and WMDATA in Map_WriteRow1 are written absolute).
; Exit: M=1, X=0, DP and DB unchanged; Map_RowsLeft = 0, Map_BuildRow
;   advanced by 32, Map_BuildLen = 0; A, X, Map_WrCol and Map_WrRow
;   clobbered by Map_WriteRow1; Y unchanged.
; ------------------------------------------------------------
Field_BuildC800Mode1:
    REP #$20
    LDA.w #!Map_BufC800&$FFFF
    STA.w WMADDL
    SEP #$20
    LDA.b #$00
    STA.w WMADDH
    LDA.b !Map_TileOriginY-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawRows
    STA.b !Map_RowsLeft-!DP_Map
.row_loop:
    LDA.b !Map_TileOriginX-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow1
    INC.b !Map_BuildRow-!DP_Map
    DEC.b !Map_RowsLeft-!DP_Map
    BNE .row_loop
    RTS

; ------------------------------------------------------------
; $C0:7612 — Map_WriteRow1 (466 bytes, $7612–$77E3)
; Writes one row of layer-1 tilemap words to WMDATA (WRAM at WMADD).
;   Arguments in 8x8-tile units: Map_BuildRow (bit 0, Map_HalfTileBit,
;   picks the top or bottom half of metatile row Map_BuildRow / 2),
;   Map_BuildCol (bit 0 set: start with a right half) and Map_BuildLen in
;   metatiles. The metatile row and column are ANDed with Map_RowMask1 /
;   Map_ColMask1, the column again at every step (so it wraps). Each
;   metatile's 9-bit number (Map_TileProps, bit 8 from Map_TileHiBits
;   bit 0) times 8 indexes Map_Meta12*; a top half writes its TL and TR
;   words, a bottom half BL and BR.
;   An even start writes Map_BuildLen whole metatiles. An odd start
;   writes the right word of the first metatile, Map_BuildLen - 1 whole
;   ones, and then one more word, again a right word (TR / BR) of the
;   next metatile where a left one would continue the row. Kept as is:
;   both give 2 x Map_BuildLen words, and the edge rows start one column
;   left of the screen, so that word probably lands off-screen (not
;   traced).
; Quirk: on an odd start the count is decremented once before the loop
;   tests it, so Map_BuildLen = 1 would run 256 more metatiles; callers
;   pass Map_RedrawLen or Map_EdgeRowLen.
; Callers: Field_BuildC800Mode1 ($C0:7608), Map_BuildRowYInc1 ($C0:825B)
;   and Map_BuildRowYDec1 ($C0:82DD).
; On entry: M=1 (8-bit A), X=0 (16-bit X: the map index row << 8 |
;   column, then the Map_Meta12* offset), DP=$1D00 (!DP_Map), DB=$00
;   (WMDATA written absolute).
; Exit: M=1, X=0, DP and DB unchanged; Map_BuildLen = 0; Map_WrRow =
;   the masked metatile row, Map_WrCol = the last or next metatile
;   column; A and X clobbered; Y unchanged; WMADD advanced past the
;   words written.
; ------------------------------------------------------------
Map_WriteRow1:
    LDA.b !Map_BuildRow-!DP_Map
    BIT.b #!Map_HalfTileBit
    BEQ .top_half
    BRL .bottom_half
.top_half:
    LSR A
    AND.b !Map_RowMask1-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .top_odd
    LSR A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.top_even_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12TR,X
    STA.w WMDATA
    LDA.l !Map_Meta12TR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .top_done
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .top_even_loop
.top_done:
    RTS
.top_odd:
    LSR A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    DEC.b !Map_BuildLen-!DP_Map
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.top_odd_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12TR,X
    STA.w WMDATA
    LDA.l !Map_Meta12TR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .top_odd_last
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .top_odd_loop
.top_odd_last:
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
.done:
    RTS
.bottom_half:
    LSR A
    AND.b !Map_RowMask1-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .bottom_odd
    LSR A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.bottom_even_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12BR,X
    STA.w WMDATA
    LDA.l !Map_Meta12BR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .bottom_even_loop
.bottom_odd:
    LSR A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    DEC.b !Map_BuildLen-!DP_Map
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.bottom_odd_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12BR,X
    STA.w WMDATA
    LDA.l !Map_Meta12BR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .bottom_odd_last
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .bottom_odd_loop
.bottom_odd_last:
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    RTS

; ------------------------------------------------------------
; $C0:77E4 — Map_WriteCol1 (264 bytes, $77E4–$78EB)
; Writes one column of layer-1 tilemap words to WMDATA, top to bottom.
;   Map_BuildCol bit 0 picks the left words (TL, BL) or the right ones
;   (TR, BR) of metatile column Map_BuildCol / 2; Map_BuildRow is the
;   first 8x8 row and Map_BuildLen counts metatiles. Each step writes a
;   metatile's top and bottom word and moves one metatile row down (ANDed
;   with Map_RowMask1, so it wraps). An odd first row writes the bottom
;   word of the first metatile alone and then Map_BuildLen whole ones:
;   2 x Map_BuildLen + 1 words, against 2 x Map_BuildLen for an even
;   start. Lookup as Map_WriteRow1 (Map_TileProps, Map_TileHiBits bit 0,
;   Map_Meta12*).
; Callers: Map_BuildColXInc1 ($C0:835D) and Map_BuildColXDec1 ($C0:83DD).
; On entry: M=1 (8-bit A), X=0 (16-bit X), DP=$1D00 (!DP_Map), DB=$00
;   (WMDATA written absolute).
; Exit: M=1, X=0, DP and DB unchanged; Map_BuildLen = 0; Map_WrCol =
;   the masked metatile column, Map_WrRow = the last metatile row; A and
;   X clobbered; Y unchanged; WMADD advanced past the words written.
; ------------------------------------------------------------
Map_WriteCol1:
    LDA.b !Map_BuildRow-!DP_Map
    BIT.b #!Map_HalfTileBit
    BEQ .even_row
    BRL .odd_row
.even_row:
    LSR A
    AND.b !Map_RowMask1-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .right_start
    LSR A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.left_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12BL,X
    STA.w WMDATA
    LDA.l !Map_Meta12BL+1,X
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    INC A
    AND.b !Map_RowMask1-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .left_loop
.right_start:
    LSR A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.right_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12BR,X
    STA.w WMDATA
    LDA.l !Map_Meta12BR+1,X
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    INC A
    AND.b !Map_RowMask1-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .right_loop
.done:
    RTS
.odd_row:
    LSR A
    AND.b !Map_RowMask1-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .odd_row_right
    LSR A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    INC A
    AND.b !Map_RowMask1-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRL .left_loop
.odd_row_right:
    LSR A
    AND.b !Map_ColMask1-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    AND.b #$01
    XBA
    LDA.l !Map_TileProps,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    INC A
    AND.b !Map_RowMask1-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRL .right_loop

; ------------------------------------------------------------
; $C0:78EC — Field_BuildC800Mode2 (227 bytes, $78EC–$79CE)
; Redraws layer 2 into Map_BufC800 (WMADD = $7E:C800) with
;   Map_WriteRow2, 16 metatiles (Map_RedrawLen) per row, one of three ways:
;   - Map_LayerEdgeOff bit 1 clear, Map_Unk0BC9 bit 7 clear: as
;     Field_BuildC800Mode1 (32 rows from Map_TileOriginY, column
;     Map_TileOriginX: layer 1's origin, as the normal-rate builders).
;   - bit 1 clear, Map_Unk0BC9 bit 7 set (half-rate layer 2): rows
;     Map_Unk1D16 through Map_Unk1D18 from column Map_Unk1D12.
;   - Map_LayerEdgeOff bit 1 set (no edge builds for the layer): a fixed
;     map from row 0, column 0. Rows 0-31 (2 KB), then a second 2 KB:
;     columns 32-63 when Map_Unk0BCF is not 16 (Map_ScreenMetatiles),
;     else rows 32-63 when Map_Unk0BD1 is not 16 (and the high byte of
;     Map_TilemapVram4 set to 2), else rows 0-31 again. The second block
;     runs past $7E:CFFF into Map_BufD000's space; $C0:0ABB then uploads
;     4 KB (Map_UploadBuf4K) when the bit is set.
; Quirk: the two layer-2-moving paths start with a REP #$20 that the
;   SEP #$20 after the branch undoes at once; kept.
; Callers: DefaultHandler ($C0:17D2, $C0:1817) and unmatched code at
;   $C0:0AAB.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00
;   (Map_LayerEdgeOff, Map_Unk0BC9, Map_Unk0BCF/0BD1, WMADD and WMDATA
;   are absolute).
; Exit: M=1, X=0, DP and DB unchanged; Map_BuildCol/Row/Len, A, X,
;   Map_WrCol and Map_WrRow clobbered (Map_RowsLeft = 0 on the first
;   path); Y unchanged.
; ------------------------------------------------------------
Field_BuildC800Mode2:
    REP #$20
    LDA.w #!Map_BufC800&$FFFF
    STA.w WMADDL
    SEP #$20
    LDA.b #$00
    STA.w WMADDH
    LDA.w !Map_LayerEdgeOff
    BIT.b #!Map_Layer2
    BEQ .not_edge_off
    BRL .edge_off
.not_edge_off:
    LDA.w !Map_Unk0BC9
    BMI .half_rate
    REP #$20
    BRA .normal_rate
.half_rate:
    REP #$20
    BRL .half_rate_rows
.normal_rate:
    SEP #$20
    LDA.b !Map_TileOriginY-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawRows
    STA.b !Map_RowsLeft-!DP_Map
.normal_row_loop:
    LDA.b !Map_TileOriginX-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow2
    INC.b !Map_BuildRow-!DP_Map
    DEC.b !Map_RowsLeft-!DP_Map
    BNE .normal_row_loop
    RTS
.half_rate_rows:
    SEP #$20
    LDA.b !Map_Unk1D12-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b !Map_Unk1D16-!DP_Map
.half_row_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow2
    LDA.b !Map_Unk1D12-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b !Map_Unk1D18-!DP_Map
    BCC .half_row_loop
    BEQ .half_row_loop
    RTS
.edge_off:
    SEP #$20
    STZ.b !Map_BuildCol-!DP_Map
    LDA.b #$00
.screen0_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow2
    STZ.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b #!Map_RedrawLastRow
    BCC .screen0_loop
    BEQ .screen0_loop
    LDA.w !Map_Unk0BCF
    CMP.b #!Map_ScreenMetatiles
    BNE .right_screen
    LDA.w !Map_Unk0BD1
    CMP.b #!Map_ScreenMetatiles
    BNE .lower_screen
    LDA.b #$00
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #$00
.repeat_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow2
    STZ.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b #!Map_RedrawLastRow
    BCC .repeat_loop
    BEQ .repeat_loop
    RTS
.right_screen:
    LDA.b #!Bg_ScreenWidth
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #$00
.right_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow2
    LDA.b #!Bg_ScreenWidth
    STA.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b #!Map_RedrawLastRow
    BCC .right_loop
    BEQ .right_loop
    RTS
.lower_screen:
    LDA.b #$00
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Bg_ScreenHeight
.lower_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow2
    LDA.b #$00
    STA.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b #!Map_RedrawLastRow2
    BCC .lower_loop
    BEQ .lower_loop
    LDA.b #$02
    STA.b !Map_TilemapVram4+1-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:79CF — Map_WriteRow2 (474 bytes, $79CF–$7BA8)
; As Map_WriteRow1 for layer 2: masks Map_RowMask2 / Map_ColMask2, the
;   number's low byte from Map_Layer2Tiles and bit 8 from Map_TileHiBits
;   bit 1, Map_Meta12* words. The same odd-start ending (a second right
;   word) and the same Map_BuildLen = 1 quirk.
; Callers: Field_BuildC800Mode2 ($C0:7925, $C0:793D, $C0:795A,
;   $C0:7982, $C0:799D, $C0:79BA), Map_BuildRowYInc2 ($C0:827D),
;   Map_BuildRowYInc2Half ($C0:829D), Map_BuildRowYDec2 ($C0:82FD) and
;   Map_BuildRowYDec2Half ($C0:831D).
; On entry: M=1 (8-bit A), X=0 (16-bit X), DP=$1D00 (!DP_Map), DB=$00
;   (WMDATA written absolute).
; Exit: as Map_WriteRow1: M=1, X=0, DP and DB unchanged; Map_BuildLen =
;   0; Map_WrRow / Map_WrCol changed; A and X clobbered; Y unchanged.
; ------------------------------------------------------------
Map_WriteRow2:
    LDA.b !Map_BuildRow-!DP_Map
    BIT.b #!Map_HalfTileBit
    BEQ .top_half
    BRL .bottom_half
.top_half:
    LSR A
    AND.b !Map_RowMask2-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .top_odd
    LSR A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.top_even_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12TR,X
    STA.w WMDATA
    LDA.l !Map_Meta12TR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .top_done
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .top_even_loop
.top_done:
    RTS
.top_odd:
    LSR A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    DEC.b !Map_BuildLen-!DP_Map
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.top_odd_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12TR,X
    STA.w WMDATA
    LDA.l !Map_Meta12TR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .top_odd_last
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .top_odd_loop
.top_odd_last:
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
.done:
    RTS
.bottom_half:
    LSR A
    AND.b !Map_RowMask2-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .bottom_odd
    LSR A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.bottom_even_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12BR,X
    STA.w WMDATA
    LDA.l !Map_Meta12BR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .bottom_even_loop
.bottom_odd:
    LSR A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    DEC.b !Map_BuildLen-!DP_Map
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.bottom_odd_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12BR,X
    STA.w WMDATA
    LDA.l !Map_Meta12BR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .bottom_odd_last
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .bottom_odd_loop
.bottom_odd_last:
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    RTS

; ------------------------------------------------------------
; $C0:7BA9 — Map_WriteCol2 (268 bytes, $7BA9–$7CB4)
; As Map_WriteCol1 for layer 2 (Map_RowMask2 / Map_ColMask2,
;   Map_Layer2Tiles, Map_TileHiBits bit 1, Map_Meta12*); an odd first
;   row also gives 2 x Map_BuildLen + 1 words.
; Callers: Map_BuildColXInc2 ($C0:837D), Map_BuildColXInc2Half
;   ($C0:839D), Map_BuildColXDec2 ($C0:83FD) and Map_BuildColXDec2Half
;   ($C0:841D).
; On entry: M=1 (8-bit A), X=0 (16-bit X), DP=$1D00 (!DP_Map), DB=$00
;   (WMDATA written absolute).
; Exit: as Map_WriteCol1: M=1, X=0, DP and DB unchanged; Map_BuildLen =
;   0; Map_WrCol / Map_WrRow changed; A and X clobbered; Y unchanged.
; ------------------------------------------------------------
Map_WriteCol2:
    LDA.b !Map_BuildRow-!DP_Map
    BIT.b #!Map_HalfTileBit
    BEQ .even_row
    BRL .odd_row
.even_row:
    LSR A
    AND.b !Map_RowMask2-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .right_start
    LSR A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.left_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12BL,X
    STA.w WMDATA
    LDA.l !Map_Meta12BL+1,X
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    INC A
    AND.b !Map_RowMask2-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .left_loop
.right_start:
    LSR A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.right_loop:
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12TR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta12BR,X
    STA.w WMDATA
    LDA.l !Map_Meta12BR+1,X
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    INC A
    AND.b !Map_RowMask2-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .right_loop
.done:
    RTS
.odd_row:
    LSR A
    AND.b !Map_RowMask2-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .odd_row_right
    LSR A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    INC A
    AND.b !Map_RowMask2-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRL .left_loop
.odd_row_right:
    LSR A
    AND.b !Map_ColMask2-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_TileHiBits,X
    LSR A
    AND.b #$01
    XBA
    LDA.l !Map_Layer2Tiles,X
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta12BR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    INC A
    AND.b !Map_RowMask2-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRL .right_loop

; ------------------------------------------------------------
; $C0:7CB5 — Field_BuildC800Mode4 (177 bytes, $7CB5–$7D65)
; As Field_BuildC800Mode2 for layer 3 with Map_WriteRow3, without the
;   half-rate path: Map_LayerEdgeOff bit 2 clear redraws 32 rows from
;   Map_TileOriginY / Map_TileOriginX; set builds the fixed map, the
;   second 2 KB chosen by Map_Unk0BD3 / Map_Unk0BD5 (not 16: columns
;   32-63 / rows 32-63, the latter storing 2 in Map_Unk1D86; else rows
;   0-31 again).
; Callers: DefaultHandler ($C0:186F) and unmatched code at $C0:0AD8.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00
;   (Map_LayerEdgeOff, Map_Unk0BD3/0BD5, WMADD and WMDATA are absolute).
; Exit: M=1, X=0, DP and DB unchanged; Map_BuildCol/Row/Len, A, X,
;   Map_WrCol and Map_WrRow clobbered (Map_RowsLeft = 0 on the first
;   path); Y unchanged.
; ------------------------------------------------------------
Field_BuildC800Mode4:
    REP #$20
    LDA.w #!Map_BufC800&$FFFF
    STA.w WMADDL
    SEP #$20
    LDA.b #$00
    STA.w WMADDH
    LDA.w !Map_LayerEdgeOff
    BIT.b #!Map_Layer3
    BEQ .normal
    BRA .edge_off
.normal:
    LDA.b !Map_TileOriginY-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawRows
    STA.b !Map_RowsLeft-!DP_Map
.row_loop:
    LDA.b !Map_TileOriginX-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow3
    INC.b !Map_BuildRow-!DP_Map
    DEC.b !Map_RowsLeft-!DP_Map
    BNE .row_loop
    RTS
.edge_off:
    STZ.b !Map_BuildCol-!DP_Map
    LDA.b #$00
.screen0_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow3
    STZ.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b #!Map_RedrawLastRow
    BCC .screen0_loop
    BEQ .screen0_loop
    LDA.w !Map_Unk0BD3
    CMP.b #!Map_ScreenMetatiles
    BNE .right_screen
    LDA.w !Map_Unk0BD5
    CMP.b #!Map_ScreenMetatiles
    BNE .lower_screen
    LDA.b #$00
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #$00
.repeat_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow3
    STZ.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b #!Map_RedrawLastRow
    BCC .repeat_loop
    BEQ .repeat_loop
    RTS
.right_screen:
    LDA.b #!Bg_ScreenWidth
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #$00
.right_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow3
    LDA.b #!Bg_ScreenWidth
    STA.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b #!Map_RedrawLastRow
    BCC .right_loop
    BEQ .right_loop
    RTS
.lower_screen:
    LDA.b #$00
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Bg_ScreenHeight
.lower_loop:
    STA.b !Map_BuildRow-!DP_Map
    LDA.b #!Map_RedrawLen
    STA.b !Map_BuildLen-!DP_Map
    JSR Map_WriteRow3
    LDA.b #$00
    STA.b !Map_BuildCol-!DP_Map
    LDA.b !Map_BuildRow-!DP_Map
    INC A
    CMP.b #!Map_RedrawLastRow2
    BCC .lower_loop
    BEQ .lower_loop
    LDA.b #$02
    STA.b !Map_Unk1D86-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:7D66 — Map_WriteRow3 (250 bytes, $7D66–$7E5F)
; As Map_WriteRow1 for layer 3: masks Map_RowMask3 / Map_ColMask3, an
;   8-bit metatile number from Map_Layer3Tiles (zero-extended), words
;   from Map_Meta3*. Unlike layers 1 and 2, an odd start writes the
;   first right word and then Map_BuildLen whole metatiles (2 x
;   Map_BuildLen + 1 words), with no extra word at the end and no early
;   decrement.
; Callers: Field_BuildC800Mode4 ($C0:7CDD, $C0:7CF1, $C0:7D19, $C0:7D34,
;   $C0:7D51), Map_BuildRowYInc3 ($C0:82BD) and Map_BuildRowYDec3
;   ($C0:833D).
; On entry: M=1 (8-bit A), X=0 (16-bit X), DP=$1D00 (!DP_Map), DB=$00
;   (WMDATA written absolute).
; Exit: M=1, X=0, DP and DB unchanged; Map_BuildLen = 0; Map_WrRow /
;   Map_WrCol changed; A and X clobbered; Y unchanged.
; ------------------------------------------------------------
Map_WriteRow3:
    LDA.b !Map_BuildRow-!DP_Map
    BIT.b #!Map_HalfTileBit
    BEQ .top_half
    BRL .bottom_half
.top_half:
    LSR A
    AND.b !Map_RowMask3-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .top_odd
    LSR A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.top_pair_loop:
    TAX
    LDA.l !Map_Layer3Tiles,X
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta3TL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta3TR,X
    STA.w WMDATA
    LDA.l !Map_Meta3TR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .top_pair_loop
.top_odd:
    LSR A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_Layer3Tiles,X
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta3TR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    BRA .top_pair_loop
.done:
    RTS
.bottom_half:
    LSR A
    AND.b !Map_RowMask3-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .bottom_odd
    LSR A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.bottom_pair_loop:
    TAX
    LDA.l !Map_Layer3Tiles,X
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta3BL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta3BR,X
    STA.w WMDATA
    LDA.l !Map_Meta3BR+1,X
    STA.w WMDATA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .bottom_pair_loop
.bottom_odd:
    LSR A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_Layer3Tiles,X
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta3BR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    INC A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    BRA .bottom_pair_loop

; ------------------------------------------------------------
; $C0:7E60 — Map_WriteCol3 (248 bytes, $7E60–$7F57)
; As Map_WriteCol1 for layer 3 (Map_RowMask3 / Map_ColMask3,
;   Map_Layer3Tiles zero-extended, Map_Meta3*); an odd first row gives
;   2 x Map_BuildLen + 1 words.
; Callers: Map_BuildColXInc3 ($C0:83BD) and Map_BuildColXDec3 ($C0:843D).
; On entry: M=1 (8-bit A), X=0 (16-bit X), DP=$1D00 (!DP_Map), DB=$00
;   (WMDATA written absolute).
; Exit: M=1, X=0, DP and DB unchanged; Map_BuildLen = 0; Map_WrCol /
;   Map_WrRow changed; A and X clobbered; Y unchanged.
; ------------------------------------------------------------
Map_WriteCol3:
    LDA.b !Map_BuildRow-!DP_Map
    BIT.b #!Map_HalfTileBit
    BEQ .even_row
    BRL .odd_row
.even_row:
    LSR A
    AND.b !Map_RowMask3-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .right_start
    LSR A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.left_loop:
    TAX
    LDA.l !Map_Layer3Tiles,X
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta3TL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta3BL,X
    STA.w WMDATA
    LDA.l !Map_Meta3BL+1,X
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    INC A
    AND.b !Map_RowMask3-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .left_loop
.right_start:
    LSR A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
.right_loop:
    TAX
    LDA.l !Map_Layer3Tiles,X
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta3TR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.l !Map_Meta3BR,X
    STA.w WMDATA
    LDA.l !Map_Meta3BR+1,X
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    DEC.b !Map_BuildLen-!DP_Map
    BEQ .done
    INC A
    AND.b !Map_RowMask3-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRA .right_loop
.done:
    RTS
.odd_row:
    LSR A
    AND.b !Map_RowMask3-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_BuildCol-!DP_Map
    BIT.b #!Map_HalfTileBit
    BNE .odd_row_right
    LSR A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_Layer3Tiles,X
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta3BL,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    INC A
    AND.b !Map_RowMask3-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRL .left_loop
.odd_row_right:
    LSR A
    AND.b !Map_ColMask3-!DP_Map
    STA.b !Map_WrCol-!DP_Map
    TAX
    LDA.l !Map_Layer3Tiles,X
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !Map_Meta3BR,X
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    LDA.b !Map_WrRow-!DP_Map
    INC A
    AND.b !Map_RowMask3-!DP_Map
    STA.b !Map_WrRow-!DP_Map
    XBA
    LDA.b !Map_WrCol-!DP_Map
    BRL .right_loop

; ------------------------------------------------------------
; $C0:7F58 — Map_UploadBufTo7400 (38 bytes, $7F58–$7F7D, four entries)
; Sends Map_BufC800 to VRAM through VramDma_Upload (VramDma_Mode 1,
;   source $7E:C800):
;   Map_UploadBufTo7400 ($7F58)  2 KB to VRAM word $7400;
;   Map_UploadBufTo7000 ($7F5D)  2 KB to VRAM word $7000;
;   Map_UploadBuf2K     ($7F62)  2 KB to the caller's VramDma_Addr;
;   Map_UploadBuf4K     ($7F77)  4 KB ($7E:C800-$D7FF, what the
;                                redraws build with the edge bit set) to
;                                the caller's VramDma_Addr.
;   The 4 KB entry sits after the BRL and branches back into the shared
;   tail Map_UploadBuf_Tail; Map_UploadBufToX is the shared store of X
;   into VramDma_Addr (global labels because the entries are global).
; Callers (all unmatched): Map_UploadBufTo7400 from $C0:EB5E;
;   Map_UploadBufTo7000 from $C0:EB4A; Map_UploadBuf2K from $C0:0A9F,
;   $C0:0AC0, $C0:0AED, $C0:EAE1, $C0:EB01, $C0:EB21 and $C0:EB38;
;   Map_UploadBuf4K from $C0:0ABB and $C0:0AE8 (e.g. $C0:0AAF loads
;   VramDma_Addr from Map_TilemapVram3 after Field_BuildC800Mode2).
;   xref also confirms a JML to Map_UploadBufToX at $D5:677B, inside the
;   object graphics of bank $D5 (GfxRom_D5), so data, not a call.
; On entry: M=1 (8-bit A), X=0 (16-bit X), DP=$0100 (!DP_Field: the
;   VramDma_* bytes are dp), DB=$00 (VramDma_Upload writes registers
;   absolute); Map_UploadBuf2K / 4K: VramDma_Addr set.
; Exit: through BRL VramDma_Upload, whose RTS returns to the caller:
;   M=1, X=0, DP and DB unchanged; A and X clobbered; VramDma_Addr,
;   Mode, Src, SrcBank and Size as above; Y preserved.
; ------------------------------------------------------------
Map_UploadBufTo7400:
    LDX.w #!Map_UploadVramA
    BRA Map_UploadBufToX
Map_UploadBufTo7000:                    ; header: see Map_UploadBufTo7400
    LDX.w #!Map_UploadVramB
Map_UploadBufToX:                       ; header: see Map_UploadBufTo7400
    STX.b !VramDma_Addr
Map_UploadBuf2K:                        ; header: see Map_UploadBufTo7400
    LDX.w #!Map_UploadSmall
    STX.b !VramDma_Size
Map_UploadBuf_Tail:                     ; header: see Map_UploadBufTo7400
    LDA.b #$01                          ; VramDma_Mode 1: word writes
    STA.b !VramDma_Mode
    LDX.w #!Map_BufC800&$FFFF
    STX.b !VramDma_Src
    LDA.b #!Bank7E
    STA.b !VramDma_SrcBank
    BRL VramDma_Upload
Map_UploadBuf4K:                        ; header: see Map_UploadBufTo7400
    LDX.w #!Map_UploadLarge
    STX.b !VramDma_Size
    BRA Map_UploadBuf_Tail

; ------------------------------------------------------------
; $C0:7F7E — LocLoad_ClearPage1D00 (28 bytes, $7F7E–$7F99)
; Zeroes the 256 bytes at $00:1D00-$1DFF (the map page !DP_Map, low
;   WRAM) with ClearRAMDMA: DmaFill_Size = $0100, DmaFill_Dest = $1D00,
;   DmaFill_Bank = $00.
; Callers: LoadLocation ($C0:0103) and Field_RestoreState ($C0:01CC).
; On entry: M=1 (8-bit A), X=0 (16-bit X for the word arguments); DP
;   any (saved, set to $0100 for the DmaFill_* bytes, restored); DB=$00
;   (ClearRAMDMA writes registers absolute).
; Exit: M=1, X=0, DP restored, DB unchanged; A and X clobbered (as
;   ClearRAMDMA leaves them); DmaFill_* at $0100 set as above; Y
;   preserved.
; ------------------------------------------------------------
LocLoad_ClearPage1D00:
    PHD
    REP #$20
    LDA.w #!DP_Field
    TCD
    SEP #$20
    LDX.w #!Map_PageBytes
    STX.b !DmaFill_Size
    LDX.w #!DP_Map
    STX.b !DmaFill_Dest
    LDA.b #$00
    STA.b !DmaFill_Bank
    JSR ClearRAMDMA
    PLD
    RTS

; ------------------------------------------------------------
; $C0:7F9A — Sub_C07F9A (419 bytes, $7F9A–$813C)
; Purpose not established (no reader of its results traced). For each
;   layer it stores tilemap VRAM word addresses in Map_EdgeVram1/2/3 and
;   byte counts in Map_EdgeSize1/2/3, probably the destinations of the
;   NMI's edge DMAs. Per layer, with c / r its column / row bias
;   (Map_BgColBias / RowBias, ...2, ...3) and its tilemap base
;   (Map_TilemapVram, Map_TilemapVram3, Map_TilemapVramL3) added to
;   each address:
;   - the row r from column c - 1 (Bg_RowSpan64x32): its three pieces
;     at Map_EdgeVram +0/+2/+4, sizes at Map_EdgeSize +0/+2/+4;
;   - the row r + 28 (mod 32) from the same column (Bg_RowSpan64x32Addr,
;     the same sizes): +6/+8/+10;
;   - the column c from row r - 1 (Bg_ColSpan64x32): two pieces at
;     +12/+14, sizes at Map_EdgeSize +6/+8;
;   - the column c + 32 (mod 64) from row r - 1 (Bg_ColSpan64x32Addr):
;     +16/+18.
;   Rows from column c - 1 and columns from row r - 1 match where the
;   edge builders start (one column left, one row above the origin).
; Callers: Map_Unk93E1 (BRL at $C0:9439 and $C0:9448) and unmatched
;   code: BRL at $C0:74D1 (the last instruction of the routine before
;   Field_Unk74D4), JSR at $C0:74E3 (in Field_Unk74D4, also reached by
;   Field_Unk74E8 and Field_Unk74F7 through its shared tail) and JSR at
;   $C0:8819.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map); DB not
;   used (all direct page).
; Exit: M=1, X=0, DP unchanged; A, X and Y clobbered; the Map_Span*
;   scratch (Map_SpanCol/Row/RowOfs/Len1-3, Map_SpanWrapVram) changed.
; ------------------------------------------------------------
Sub_C07F9A:
    REP #$20
    LDA.b !Map_BgRowBias-!DP_Map
    AND.w #!Bg_RowMask32
    TAY
    LDA.b !Map_BgColBias-!DP_Map
    DEC A
    AND.w #!Bg_ColMask64
    PHA
    JSR Bg_RowSpan64x32
    TXA
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+2-!DP_Map
    LDA.b !Map_SpanWrapVram-!DP_Map
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+4-!DP_Map
    LDA.b !Map_SpanLen1-!DP_Map
    STA.b !Map_EdgeSize1-!DP_Map
    LDA.b !Map_SpanLen2-!DP_Map
    STA.b !Map_EdgeSize1+2-!DP_Map
    LDA.b !Map_SpanLen3-!DP_Map
    STA.b !Map_EdgeSize1+4-!DP_Map
    LDA.b !Map_BgRowBias-!DP_Map
    CLC
    ADC.w #!Map_RowsUp4
    AND.w #!Bg_RowMask32
    TAY
    PLA
    JSR Bg_RowSpan64x32Addr
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+8-!DP_Map
    TXA
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+6-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+10-!DP_Map
    LDA.b !Map_BgRowBias-!DP_Map
    DEC A
    AND.w #!Bg_RowMask32
    PHA
    TAY
    LDA.b !Map_BgColBias-!DP_Map
    AND.w #!Bg_ColMask64
    JSR Bg_ColSpan64x32
    TXA
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+12-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+14-!DP_Map
    LDA.b !Map_SpanLen1-!DP_Map
    STA.b !Map_EdgeSize1+6-!DP_Map
    LDA.b !Map_SpanLen2-!DP_Map
    STA.b !Map_EdgeSize1+8-!DP_Map
    PLY
    LDA.b !Map_BgColBias-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWidth
    AND.w #!Bg_ColMask64
    JSR Bg_ColSpan64x32Addr
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+18-!DP_Map
    TXA
    CLC
    ADC.b !Map_TilemapVram-!DP_Map
    STA.b !Map_EdgeVram1+16-!DP_Map
    LDA.b !Map_BgRowBias2-!DP_Map
    AND.w #!Bg_RowMask32
    TAY
    LDA.b !Map_BgColBias2-!DP_Map
    DEC A
    AND.w #!Bg_ColMask64
    PHA
    JSR Bg_RowSpan64x32
    TXA
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+2-!DP_Map
    LDA.b !Map_SpanWrapVram-!DP_Map
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+4-!DP_Map
    LDA.b !Map_SpanLen1-!DP_Map
    STA.b !Map_EdgeSize2-!DP_Map
    LDA.b !Map_SpanLen2-!DP_Map
    STA.b !Map_EdgeSize2+2-!DP_Map
    LDA.b !Map_SpanLen3-!DP_Map
    STA.b !Map_EdgeSize2+4-!DP_Map
    LDA.b !Map_BgRowBias2-!DP_Map
    CLC
    ADC.w #!Map_RowsUp4
    AND.w #!Bg_RowMask32
    TAY
    PLA
    JSR Bg_RowSpan64x32Addr
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+8-!DP_Map
    TXA
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+6-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+10-!DP_Map
    LDA.b !Map_BgRowBias2-!DP_Map
    DEC A
    AND.w #!Bg_RowMask32
    PHA
    TAY
    LDA.b !Map_BgColBias2-!DP_Map
    AND.w #!Bg_ColMask64
    JSR Bg_ColSpan64x32
    TXA
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+12-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+14-!DP_Map
    LDA.b !Map_SpanLen1-!DP_Map
    STA.b !Map_EdgeSize2+6-!DP_Map
    LDA.b !Map_SpanLen2-!DP_Map
    STA.b !Map_EdgeSize2+8-!DP_Map
    PLY
    LDA.b !Map_BgColBias2-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWidth
    AND.w #!Bg_ColMask64
    JSR Bg_ColSpan64x32Addr
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+18-!DP_Map
    TXA
    CLC
    ADC.b !Map_TilemapVram3-!DP_Map
    STA.b !Map_EdgeVram2+16-!DP_Map
    LDA.b !Map_BgRowBias3-!DP_Map
    AND.w #!Bg_RowMask32
    TAY
    LDA.b !Map_BgColBias3-!DP_Map
    DEC A
    AND.w #!Bg_ColMask64
    PHA
    JSR Bg_RowSpan64x32
    TXA
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+2-!DP_Map
    LDA.b !Map_SpanWrapVram-!DP_Map
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+4-!DP_Map
    LDA.b !Map_SpanLen1-!DP_Map
    STA.b !Map_EdgeSize3-!DP_Map
    LDA.b !Map_SpanLen2-!DP_Map
    STA.b !Map_EdgeSize3+2-!DP_Map
    LDA.b !Map_SpanLen3-!DP_Map
    STA.b !Map_EdgeSize3+4-!DP_Map
    LDA.b !Map_BgRowBias3-!DP_Map
    CLC
    ADC.w #!Map_RowsUp4
    AND.w #!Bg_RowMask32
    TAY
    PLA
    JSR Bg_RowSpan64x32Addr
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+8-!DP_Map
    TXA
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+6-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+10-!DP_Map
    LDA.b !Map_BgRowBias3-!DP_Map
    DEC A
    AND.w #!Bg_RowMask32
    PHA
    TAY
    LDA.b !Map_BgColBias3-!DP_Map
    AND.w #!Bg_ColMask64
    JSR Bg_ColSpan64x32
    TXA
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+12-!DP_Map
    TYA
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+14-!DP_Map
    LDA.b !Map_SpanLen1-!DP_Map
    STA.b !Map_EdgeSize3+6-!DP_Map
    LDA.b !Map_SpanLen2-!DP_Map
    STA.b !Map_EdgeSize3+8-!DP_Map
    PLY
    LDA.b !Map_BgColBias3-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWidth
    AND.w #!Bg_ColMask64
    JSR Bg_ColSpan64x32Addr
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+18-!DP_Map
    TXA
    CLC
    ADC.b !Map_TilemapVramL3-!DP_Map
    STA.b !Map_EdgeVram3+16-!DP_Map
    SEP #$20
    RTS

; ------------------------------------------------------------
; $C0:813D — Bg_RowSpan64x32 (100 bytes, $813D–$81A0)
; Splits a run of 34 tilemap words (Map_EdgeRowTiles) along row Y from
;   column A of a 64x32 tilemap (two 32x32 screens, the right one
;   Bg_ScreenWords further on) into pieces contiguous in VRAM. Returns
;   X = word offset of (A, Y); Y = offset of the start of row Y in the
;   other screen; Map_SpanLen1 = bytes to the end of the row in A's
;   screen ((32 - column within the screen) x 2); Map_SpanLen2 = (34 -
;   that) x 2 bytes; Map_SpanLen3 = 0. When the first piece is one word
;   (column 31 or 63) the second is a whole row (64 bytes) and a third
;   piece of 2 bytes starts at Map_SpanWrapVram = X - 31, the start of
;   A's own row.
; Callers: Sub_C07F9A ($C0:7FA9, $C0:8033, $C0:80BD).
; On entry: M=0 (16-bit A = column 0-63), X=0 (Y = row 0-31), DP=$1D00
;   (!DP_Map); DB not used.
; Exit: M=0, X=0, DP unchanged; X, Y, Map_SpanLen1-3 as above (and
;   Map_SpanWrapVram on the three-piece path); A clobbered;
;   Map_SpanCol = column, Map_SpanRowOfs = row x 32.
; ------------------------------------------------------------
Bg_RowSpan64x32:
    STA.b !Map_SpanCol-!DP_Map
    TYA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !Map_SpanRowOfs-!DP_Map
    LDA.b !Map_SpanCol-!DP_Map
    CMP.w #!Bg_ScreenWidth
    BCS .right_screen
    CLC
    ADC.b !Map_SpanRowOfs-!DP_Map
    TAX
    LDA.b !Map_SpanRowOfs-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWords
    TAY
    LDA.w #!Bg_ScreenWidth
    SEC
    SBC.b !Map_SpanCol-!DP_Map
    STA.b !Map_SpanLen1-!DP_Map
    BRA .check_wrap
.right_screen:
    SEC
    SBC.w #!Bg_ScreenWidth
    CLC
    ADC.b !Map_SpanRowOfs-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWords
    TAX
    LDY.b !Map_SpanRowOfs-!DP_Map
    LDA.w #!Bg_MapWidth64
    SEC
    SBC.b !Map_SpanCol-!DP_Map
    STA.b !Map_SpanLen1-!DP_Map
.check_wrap:
    LDA.w #!Map_EdgeRowTiles
    SEC
    SBC.b !Map_SpanLen1-!DP_Map
    CMP.w #!Map_EdgeRowTiles-1
    BCC .two_pieces
    LDA.w #!Bg_ScreenWidth
    ASL A
    STA.b !Map_SpanLen2-!DP_Map
    ASL.b !Map_SpanLen1-!DP_Map
    LDA.w #$0002
    STA.b !Map_SpanLen3-!DP_Map
    TXA
    SEC
    SBC.w #!Bg_ScreenWidth-1
    STA.b !Map_SpanWrapVram-!DP_Map
    RTS
.two_pieces:
    ASL A
    STA.b !Map_SpanLen2-!DP_Map
    ASL.b !Map_SpanLen1-!DP_Map
    STZ.b !Map_SpanLen3-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:81A1 — Bg_RowSpan64x32Addr (53 bytes, $81A1–$81D5)
; The addresses of Bg_RowSpan64x32 without the sizes, in other
;   registers: X = word offset of (A, Y), A = offset of the start of row
;   Y in the other screen, Y = X - 31 (the third piece's address; the
;   start of A's own row only for column 31 or 63).
; Callers: Sub_C07F9A ($C0:7FD6, $C0:8060, $C0:80EA).
; On entry: M=0 (16-bit A = column 0-63), X=0 (Y = row 0-31), DP=$1D00
;   (!DP_Map); DB not used.
; Exit: M=0, X=0, DP unchanged; A, X, Y as above; Map_SpanCol and
;   Map_SpanRowOfs changed.
; ------------------------------------------------------------
Bg_RowSpan64x32Addr:
    STA.b !Map_SpanCol-!DP_Map
    TYA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !Map_SpanRowOfs-!DP_Map
    LDA.b !Map_SpanCol-!DP_Map
    CMP.w #!Bg_ScreenWidth
    BCS .right_screen
    CLC
    ADC.b !Map_SpanRowOfs-!DP_Map
    TAX
    SEC
    SBC.w #!Bg_ScreenWidth-1
    TAY
    LDA.b !Map_SpanRowOfs-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWords
    RTS
.right_screen:
    SEC
    SBC.w #!Bg_ScreenWidth
    CLC
    ADC.b !Map_SpanRowOfs-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWords
    TAX
    SEC
    SBC.w #!Bg_ScreenWidth-1
    TAY
    LDA.b !Map_SpanRowOfs-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:81D6 — Bg_ColSpan64x32 (66 bytes, $81D6–$8217)
; Splits a 32-word column of the 64x32 tilemap, column A from row Y and
;   wrapping at the screen's bottom, into two pieces: X = word offset of
;   (A, Y), Y = offset of (A, row 0) in the same screen; Map_SpanLen1 =
;   (32 - row) x 2 bytes, Map_SpanLen2 = row x 2 bytes.
; Callers: Sub_C07F9A ($C0:7FF7, $C0:8081, $C0:810B).
; On entry: M=0 (16-bit A = column 0-63), X=0 (Y = row 0-31), DP=$1D00
;   (!DP_Map); DB not used.
; Exit: M=0, X=0, DP unchanged; X, Y, Map_SpanLen1/2 as above; A
;   clobbered; Map_SpanCol, Map_SpanRow and Map_SpanRowOfs changed.
; ------------------------------------------------------------
Bg_ColSpan64x32:
    STA.b !Map_SpanCol-!DP_Map
    TYA
    STA.b !Map_SpanRow-!DP_Map
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !Map_SpanRowOfs-!DP_Map
    LDA.b !Map_SpanCol-!DP_Map
    CMP.w #!Bg_ScreenWidth
    BCS .right_screen
    CLC
    ADC.b !Map_SpanRowOfs-!DP_Map
    TAX
    LDY.b !Map_SpanCol-!DP_Map
    BRA .sizes
.right_screen:
    SEC
    SBC.w #!Bg_ScreenWidth
    CLC
    ADC.b !Map_SpanRowOfs-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWords
    TAX
    LDA.b !Map_SpanCol-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWords-!Bg_ScreenWidth
    TAY
.sizes:
    LDA.w #!Bg_ScreenWidth
    SEC
    SBC.b !Map_SpanRow-!DP_Map
    STA.b !Map_SpanLen1-!DP_Map
    LDA.w #!Bg_ScreenWidth
    SEC
    SBC.b !Map_SpanLen1-!DP_Map
    ASL A
    STA.b !Map_SpanLen2-!DP_Map
    ASL.b !Map_SpanLen1-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8218 — Bg_ColSpan64x32Addr (43 bytes, $8218–$8242)
; The addresses of Bg_ColSpan64x32 without the sizes: X = word offset
;   of (A, Y), A = offset of (A, row 0) in the same screen.
; Callers: Sub_C07F9A ($C0:8018, $C0:80A2, $C0:812C).
; On entry: M=0 (16-bit A = column 0-63), X=0 (Y = row 0-31), DP=$1D00
;   (!DP_Map); DB not used.
; Exit: M=0, X=0, DP unchanged; A and X as above; Y unchanged;
;   Map_SpanCol and Map_SpanRowOfs changed.
; ------------------------------------------------------------
Bg_ColSpan64x32Addr:
    STA.b !Map_SpanCol-!DP_Map
    TYA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !Map_SpanRowOfs-!DP_Map
    LDA.b !Map_SpanCol-!DP_Map
    CMP.w #!Bg_ScreenWidth
    BCS .right_screen
    CLC
    ADC.b !Map_SpanRowOfs-!DP_Map
    TAX
    LDA.b !Map_SpanCol-!DP_Map
    RTS
.right_screen:
    SEC
    SBC.w #!Bg_ScreenWidth
    CLC
    ADC.b !Map_SpanRowOfs-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWords
    TAX
    LDA.b !Map_SpanCol-!DP_Map
    CLC
    ADC.w #!Bg_ScreenWords-!Bg_ScreenWidth
    RTS

; ============================================================
; Layer edge builders ($C0:8243–$C0:8444)
; One small routine per layer, direction and kind (row or column):
; points WMADD at the layer's edge buffer (Map_BufC800 / D000 / D800,
; columns at +Map_BufColOfs), passes the first column, the row and a
; length in Map_BuildCol / Map_BuildRow / Map_BuildLen to the layer's
; row or column writer (not matched), and sets the layer's bit in the
; matching Map_Built* byte. Rows start one column left of the layer's
; left origin; columns start one row above its top origin. Rows for a
; rising Y go at the bottom bound (Map_Unk1D10 or Map_Unk1D18), for a
; falling Y at the top origin; columns likewise at the right bound
; (Map_Unk1D0C or Map_Unk1D14) or the left origin. Normal-rate layers
; 2 and 3 use layer 1's origin and bounds.
; ============================================================

; ------------------------------------------------------------
; $C0:8243 — Map_BuildRowYInc1 (32 bytes, $8243–$8262)
; Layer-1 row for a rising Y scroll: WMADD = Map_BufC800, Map_BuildCol =
;   Map_TileOriginX - 1, Map_BuildLen = Map_EdgeRowLen, Map_BuildRow =
;   Map_Unk1D10; runs Map_WriteRow1 and sets bit 0 in Map_BuiltRowYInc.
; Callers: Map_EdgeRowsYInc ($C0:9865) and Map_EdgeRowsYIncHalf
;   ($C0:9896).
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer1; X and the rest as
;   Map_WriteRow1 leaves them (not established).
; ------------------------------------------------------------
org $C08243
Map_BuildRowYInc1:
    LDX.w #!Map_BufC800&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    DEC A
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeRowLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_Unk1D10-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteRow1
    LDA.b #!Map_Layer1
    TSB.b !Map_BuiltRowYInc-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8263 — Map_BuildRowYInc2 (34 bytes, $8263–$8284)
; Layer-2 row for a rising Y scroll: WMADD = Map_BufD000, Map_BuildCol =
;   Map_TileOriginX - 1, Map_BuildLen = Map_EdgeRowLen, Map_BuildRow =
;   Map_Unk1D10; runs Map_WriteRow2 and sets bit 1 in Map_BuiltRowYInc.
; Quirk: a SEP #$20 after the WMADDL write, with M already 1, is kept.
; Callers: Map_EdgeRowsYInc ($C0:9875), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer2; X and the rest as
;   Map_WriteRow2 leaves them (not established).
; ------------------------------------------------------------
Map_BuildRowYInc2:
    LDX.w #!Map_BufD000&$FFFF
    STX.w WMADDL
    SEP #$20
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    DEC A
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeRowLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_Unk1D10-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteRow2
    LDA.b #!Map_Layer2
    TSB.b !Map_BuiltRowYInc-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8285 — Map_BuildRowYInc2Half (32 bytes, $8285–$82A4)
; Layer-2 row for a rising Y scroll: WMADD = Map_BufD000, Map_BuildCol =
;   Map_Unk1D12 - 1, Map_BuildLen = Map_EdgeRowLen, Map_BuildRow =
;   Map_Unk1D18; runs Map_WriteRow2 and sets bit 1 in Map_BuiltRowYInc.
; Callers: Map_EdgeRowsYIncHalf ($C0:98A6), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer2; X and the rest as
;   Map_WriteRow2 leaves them (not established).
; ------------------------------------------------------------
Map_BuildRowYInc2Half:
    LDX.w #!Map_BufD000&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_Unk1D12-!DP_Map
    DEC A
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeRowLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_Unk1D18-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteRow2
    LDA.b #!Map_Layer2
    TSB.b !Map_BuiltRowYInc-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:82A5 — Map_BuildRowYInc3 (32 bytes, $82A5–$82C4)
; Layer-3 row for a rising Y scroll: WMADD = Map_BufD800, Map_BuildCol =
;   Map_TileOriginX - 1, Map_BuildLen = Map_EdgeRowLen, Map_BuildRow =
;   Map_Unk1D10; runs Map_WriteRow3 and sets bit 2 in Map_BuiltRowYInc.
; Callers: Map_EdgeRowsYInc ($C0:9885) and Map_EdgeRowsYIncHalf
;   ($C0:98B6).
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer3; X and the rest as
;   Map_WriteRow3 leaves them (not established).
; ------------------------------------------------------------
Map_BuildRowYInc3:
    LDX.w #!Map_BufD800&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    DEC A
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeRowLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_Unk1D10-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteRow3
    LDA.b #!Map_Layer3
    TSB.b !Map_BuiltRowYInc-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:82C5 — Map_BuildRowYDec1 (32 bytes, $82C5–$82E4)
; Layer-1 row for a falling Y scroll: WMADD = Map_BufC800, Map_BuildCol =
;   Map_TileOriginX - 1, Map_BuildLen = Map_EdgeRowLen, Map_BuildRow =
;   Map_TileOriginY; runs Map_WriteRow1 and sets bit 0 in Map_BuiltRowYDec.
; Callers: Map_EdgeRowsYDec ($C0:98C7) and Map_EdgeRowsYDecHalf
;   ($C0:98F8).
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer1; X and the rest as
;   Map_WriteRow1 leaves them (not established).
; ------------------------------------------------------------
Map_BuildRowYDec1:
    LDX.w #!Map_BufC800&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    DEC A
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeRowLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteRow1
    LDA.b #!Map_Layer1
    TSB.b !Map_BuiltRowYDec-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:82E5 — Map_BuildRowYDec2 (32 bytes, $82E5–$8304)
; Layer-2 row for a falling Y scroll: WMADD = Map_BufD000, Map_BuildCol =
;   Map_TileOriginX - 1, Map_BuildLen = Map_EdgeRowLen, Map_BuildRow =
;   Map_TileOriginY; runs Map_WriteRow2 and sets bit 1 in Map_BuiltRowYDec.
; Callers: Map_EdgeRowsYDec ($C0:98D7), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer2; X and the rest as
;   Map_WriteRow2 leaves them (not established).
; ------------------------------------------------------------
Map_BuildRowYDec2:
    LDX.w #!Map_BufD000&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    DEC A
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeRowLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteRow2
    LDA.b #!Map_Layer2
    TSB.b !Map_BuiltRowYDec-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8305 — Map_BuildRowYDec2Half (32 bytes, $8305–$8324)
; Layer-2 row for a falling Y scroll: WMADD = Map_BufD000, Map_BuildCol =
;   Map_Unk1D12 - 1, Map_BuildLen = Map_EdgeRowLen, Map_BuildRow =
;   Map_Unk1D16; runs Map_WriteRow2 and sets bit 1 in Map_BuiltRowYDec.
; Callers: Map_EdgeRowsYDecHalf ($C0:9908), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer2; X and the rest as
;   Map_WriteRow2 leaves them (not established).
; ------------------------------------------------------------
Map_BuildRowYDec2Half:
    LDX.w #!Map_BufD000&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_Unk1D12-!DP_Map
    DEC A
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeRowLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_Unk1D16-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteRow2
    LDA.b #!Map_Layer2
    TSB.b !Map_BuiltRowYDec-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8325 — Map_BuildRowYDec3 (32 bytes, $8325–$8344)
; Layer-3 row for a falling Y scroll: WMADD = Map_BufD800, Map_BuildCol =
;   Map_TileOriginX - 1, Map_BuildLen = Map_EdgeRowLen, Map_BuildRow =
;   Map_TileOriginY; runs Map_WriteRow3 and sets bit 2 in Map_BuiltRowYDec.
; Callers: Map_EdgeRowsYDec ($C0:98E7) and Map_EdgeRowsYDecHalf
;   ($C0:9918).
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer3; X and the rest as
;   Map_WriteRow3 leaves them (not established).
; ------------------------------------------------------------
Map_BuildRowYDec3:
    LDX.w #!Map_BufD800&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    DEC A
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeRowLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteRow3
    LDA.b #!Map_Layer3
    TSB.b !Map_BuiltRowYDec-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8345 — Map_BuildColXInc1 (32 bytes, $8345–$8364)
; Layer-1 column for a rising X scroll: WMADD = Map_BufC800 +
;   Map_BufColOfs, Map_BuildCol = Map_Unk1D0C, Map_BuildLen =
;   Map_EdgeColLen, Map_BuildRow = Map_TileOriginY - 1; runs Map_WriteCol1
;   and sets bit 0 in Map_BuiltColXInc.
; Callers: Map_EdgeColsXInc ($C0:97A1), Map_EdgeColsXIncHalf ($C0:97D2)
;   and unmatched code at $C0:87FA.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer1; X and the rest as
;   Map_WriteCol1 leaves them (not established).
; ------------------------------------------------------------
Map_BuildColXInc1:
    LDX.w #(!Map_BufC800+!Map_BufColOfs)&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_Unk1D0C-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeColLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    DEC A
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteCol1
    LDA.b #!Map_Layer1
    TSB.b !Map_BuiltColXInc-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8365 — Map_BuildColXInc2 (32 bytes, $8365–$8384)
; Layer-2 column for a rising X scroll: WMADD = Map_BufD000 +
;   Map_BufColOfs, Map_BuildCol = Map_Unk1D0C, Map_BuildLen =
;   Map_EdgeColLen, Map_BuildRow = Map_TileOriginY - 1; runs Map_WriteCol2
;   and sets bit 1 in Map_BuiltColXInc.
; Callers: Map_EdgeColsXInc ($C0:97B1) and unmatched code at $C0:880D.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer2; X and the rest as
;   Map_WriteCol2 leaves them (not established).
; ------------------------------------------------------------
Map_BuildColXInc2:
    LDX.w #(!Map_BufD000+!Map_BufColOfs)&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_Unk1D0C-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeColLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    DEC A
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteCol2
    LDA.b #!Map_Layer2
    TSB.b !Map_BuiltColXInc-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8385 — Map_BuildColXInc2Half (32 bytes, $8385–$83A4)
; Layer-2 column for a rising X scroll: WMADD = Map_BufD000 +
;   Map_BufColOfs, Map_BuildCol = Map_Unk1D14, Map_BuildLen =
;   Map_EdgeColLen, Map_BuildRow = Map_Unk1D16 - 1; runs Map_WriteCol2
;   and sets bit 1 in Map_BuiltColXInc.
; Callers: Map_EdgeColsXIncHalf ($C0:97E2) and unmatched code at
;   $C0:8808.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer2; X and the rest as
;   Map_WriteCol2 leaves them (not established).
; ------------------------------------------------------------
Map_BuildColXInc2Half:
    LDX.w #(!Map_BufD000+!Map_BufColOfs)&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_Unk1D14-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeColLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_Unk1D16-!DP_Map
    DEC A
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteCol2
    LDA.b #!Map_Layer2
    TSB.b !Map_BuiltColXInc-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:83A5 — Map_BuildColXInc3 (32 bytes, $83A5–$83C4)
; Layer-3 column for a rising X scroll: WMADD = Map_BufD800 +
;   Map_BufColOfs, Map_BuildCol = Map_Unk1D0C, Map_BuildLen =
;   Map_EdgeColLen, Map_BuildRow = Map_TileOriginY - 1; runs Map_WriteCol3
;   and sets bit 2 in Map_BuiltColXInc.
; Callers: Map_EdgeColsXInc ($C0:97C1), Map_EdgeColsXIncHalf ($C0:97F2)
;   and unmatched code at $C0:8816.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer3; X and the rest as
;   Map_WriteCol3 leaves them (not established).
; ------------------------------------------------------------
Map_BuildColXInc3:
    LDX.w #(!Map_BufD800+!Map_BufColOfs)&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_Unk1D0C-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeColLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    DEC A
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteCol3
    LDA.b #!Map_Layer3
    TSB.b !Map_BuiltColXInc-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:83C5 — Map_BuildColXDec1 (32 bytes, $83C5–$83E4)
; Layer-1 column for a falling X scroll: WMADD = Map_BufC800 +
;   Map_BufColOfs, Map_BuildCol = Map_TileOriginX, Map_BuildLen =
;   Map_EdgeColLen, Map_BuildRow = Map_TileOriginY - 1; runs Map_WriteCol1
;   and sets bit 0 in Map_BuiltColXDec.
; Callers: Map_EdgeColsXDec ($C0:9803) and Map_EdgeColsXDecHalf
;   ($C0:9834).
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer1; X and the rest as
;   Map_WriteCol1 leaves them (not established).
; ------------------------------------------------------------
Map_BuildColXDec1:
    LDX.w #(!Map_BufC800+!Map_BufColOfs)&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeColLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    DEC A
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteCol1
    LDA.b #!Map_Layer1
    TSB.b !Map_BuiltColXDec-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:83E5 — Map_BuildColXDec2 (32 bytes, $83E5–$8404)
; Layer-2 column for a falling X scroll: WMADD = Map_BufD000 +
;   Map_BufColOfs, Map_BuildCol = Map_TileOriginX, Map_BuildLen =
;   Map_EdgeColLen, Map_BuildRow = Map_TileOriginY - 1; runs Map_WriteCol2
;   and sets bit 1 in Map_BuiltColXDec.
; Callers: Map_EdgeColsXDec ($C0:9813), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer2; X and the rest as
;   Map_WriteCol2 leaves them (not established).
; ------------------------------------------------------------
Map_BuildColXDec2:
    LDX.w #(!Map_BufD000+!Map_BufColOfs)&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeColLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    DEC A
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteCol2
    LDA.b #!Map_Layer2
    TSB.b !Map_BuiltColXDec-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8405 — Map_BuildColXDec2Half (32 bytes, $8405–$8424)
; Layer-2 column for a falling X scroll: WMADD = Map_BufD000 +
;   Map_BufColOfs, Map_BuildCol = Map_Unk1D12, Map_BuildLen =
;   Map_EdgeColLen, Map_BuildRow = Map_Unk1D16 - 1; runs Map_WriteCol2
;   and sets bit 1 in Map_BuiltColXDec.
; Callers: Map_EdgeColsXDecHalf ($C0:9844), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer2; X and the rest as
;   Map_WriteCol2 leaves them (not established).
; ------------------------------------------------------------
Map_BuildColXDec2Half:
    LDX.w #(!Map_BufD000+!Map_BufColOfs)&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_Unk1D12-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeColLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_Unk1D16-!DP_Map
    DEC A
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteCol2
    LDA.b #!Map_Layer2
    TSB.b !Map_BuiltColXDec-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8425 — Map_BuildColXDec3 (32 bytes, $8425–$8444)
; Layer-3 column for a falling X scroll: WMADD = Map_BufD800 +
;   Map_BufColOfs, Map_BuildCol = Map_TileOriginX, Map_BuildLen =
;   Map_EdgeColLen, Map_BuildRow = Map_TileOriginY - 1; runs Map_WriteCol3
;   and sets bit 2 in Map_BuiltColXDec.
; Callers: Map_EdgeColsXDec ($C0:9823) and Map_EdgeColsXDecHalf
;   ($C0:9854).
; On entry: M=1 (8-bit A), X=0 (16-bit X for the WMADDL/H pair), DP=$1D00
;   (!DP_Map), DB=$00 (WMADDL and WMADDH are written absolute).
; Exit: M=1, DP and DB unchanged; A = Map_Layer3; X and the rest as
;   Map_WriteCol3 leaves them (not established).
; ------------------------------------------------------------
Map_BuildColXDec3:
    LDX.w #(!Map_BufD800+!Map_BufColOfs)&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH          ; WRAM bank $7E
    LDA.b !Map_TileOriginX-!DP_Map
    STA.b !Map_BuildCol-!DP_Map
    LDA.b #!Map_EdgeColLen
    STA.b !Map_BuildLen-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    DEC A
    STA.b !Map_BuildRow-!DP_Map
    JSR Map_WriteCol3
    LDA.b #!Map_Layer3
    TSB.b !Map_BuiltColXDec-!DP_Map
    RTS

; ============================================================
; Field frame update and its first helpers ($C0:881E–$C0:8901)
; These run with DP = !DP_Map ($1D00): a dp operand is written as
; !Map_Name-!DP_Map, and field-page variables are reached absolute
; (!DP_Field+!Name).
; ============================================================

; ------------------------------------------------------------
; $C0:881E — Field_FrameUpdate (60 bytes, $881E–$8859)
; Field work done every frame, before input-driven checks such as
; Field_ActionButton: resets Field_UnkEB (the action-button target) to
; none, then with DP=$1D00 runs Map_ResetUnk1D2E, clears Map_Unk1D2C/
; 1D2D, runs Field_DpadDispatch only when Field_Unk62 is 0 and
; Field_ControlEnabled is set (so the fade loops, which clear
; Field_ControlEnabled around this call, get no input), Map_Unk8A6D
; (with 8-bit X) when Field_Unk20 is set (not matched yet), and then
; Map_Unk9175 (copies the X/Y steps to Map_Unk1D32/1D33 unless the
; leader is at that limit), Map_Unk99DE (may drop the frame's X/Y steps
; via Map_StepStop*), Map_Unk91AC and Map_Unk93E1 (the layer scroll).
; Callers (8 JSR sites): GameLoop_FrameBody ($C0:00A7), Field_IdleFrame
;   ($C0:00EB), Field_SceneChangeTick ($C0:0CDB), Field_FadeInAfterReload
;   ($C0:2830), Scene_SettleFrames ($C0:2854) and unmatched code at
;   $C0:02B7, $C0:02DE and $C0:3FC3.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100 (restored on
; exit; set to $1D00 inside), DB=$00 (absolute operands are bank $00).
; Exit: M=1, X=0, DP=$0100, DB unchanged; A, X and Y as the callees
; leave them (Map_Unk93E1 ends in the unmatched Sub_C07F9A; not
; established).
; ------------------------------------------------------------
org $C0881E
Field_FrameUpdate:
    LDA.b #!Field_UnkEBInit
    STA.w !DP_Field+!Field_UnkEB ; no action-button target yet
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD                     ; DP = $1D00
    SEP #$20
    JSR Map_ResetUnk1D2E
    STZ.b !Map_Unk1D2C-!DP_Map
    STZ.b !Map_Unk1D2D-!DP_Map
    LDA.w !DP_Field+!Field_Unk62
    BNE .no_input
    LDA.w !DP_Field+!Field_ControlEnabled
    BEQ .no_input
    JSR Field_DpadDispatch
.no_input:
    LDA.w !DP_Field+!Field_Unk20
    BEQ .skip_8a6d
    SEP #$10
    JSR Map_Unk8A6D
    REP #$10
.skip_8a6d:
    JSR Map_Unk9175
    JSR Map_Unk99DE
    JSR Map_Unk91AC
    JSR Map_Unk93E1
    PLD
    RTS

; ------------------------------------------------------------
; $C0:885A — Field_Unk885A (139 bytes, $885A–$88E4)
; A two-step job driven by Field_Unk38, run frame after frame by
; DefaultHandler's map-redraw path until it clears Field_Unk38:
; - Field_Unk38 = 1: zero Map_Unk1D2E/1D30/1D32/1D33. If Map_Unk1D93
;   is set, Map_Unk1D2E = +$10 when the leader's Obj_ScreenX (low byte)
;   is >= $80, else -$10 ($F0); if Map_Unk1D96 is set, Map_Unk1D30 =
;   +$10 when the leader's Obj_ScreenY (low byte) is >= $88, else -$10.
;   If neither is set it clears Field_Unk38 and stops; otherwise it
;   runs Map_Unk91AC and Map_Unk93E1 and moves on to step 2.
; - Field_Unk38 = 2: zero Map_Unk1D32/1D33, and Map_Unk1D2E or
;   Map_Unk1D30 where Map_Unk1D93 / Map_Unk1D96 is clear; if both are
;   clear it clears Field_Unk38, else runs Map_Unk91AC and Map_Unk93E1
;   again (and stays at step 2).
; - any other nonzero value: clears Field_Unk38.
; By the signs this looks like a step of $10 towards the side of the
; screen the leader is on (a camera recentre?); not established.
; Callers: DefaultHandler ($C0:1781), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100 (restored on
; exit; set to $1D00 inside), DB=$00.
; Exit: M=1, X=0 (8-bit X/Y only inside step 1), DP=$0100, DB
; unchanged; A, X clobbered, plus what Map_Unk91AC/93E1 change.
; ------------------------------------------------------------
Field_Unk885A:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD                     ; DP = $1D00
    SEP #$20
    LDA.w !DP_Field+!Field_Unk38
    BNE .active
    PLD
    RTS
.active:
    DEC A
    BEQ .step1
    DEC A
    BEQ .step2
    STZ.w !DP_Field+!Field_Unk38 ; unknown step: stop
    PLD
    RTS
.step1:
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D32-!DP_Map
    STZ.b !Map_Unk1D33-!DP_Map
    SEP #$10
    LDX.w !DP_Field+!Party_ObjSlot ; leader (8-bit X)
    LDA.b !Map_Unk1D93-!DP_Map
    BEQ .check_y
    LDA.w !Obj_ScreenX,X
    CMP.b #!Screen_HalfX
    BCC .x_left
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    BRA .check_y
.x_left:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D2E-!DP_Map
.check_y:
    LDA.b !Map_Unk1D96-!DP_Map
    BNE .y_side
    LDA.b !Map_Unk1D93-!DP_Map
    BNE .apply1
    REP #$10
    STZ.w !DP_Field+!Field_Unk38 ; neither enabled: done
    PLD
    RTS
.y_side:
    LDA.w !Obj_ScreenY,X
    CMP.b #!Screen_SplitY
    BCC .y_top
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    BRA .apply1
.y_top:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D30-!DP_Map
.apply1:
    REP #$10
    JSR Map_Unk91AC
    JSR Map_Unk93E1
    INC.w !DP_Field+!Field_Unk38 ; on to step 2
    PLD
    RTS
.step2:
    STZ.b !Map_Unk1D32-!DP_Map
    STZ.b !Map_Unk1D33-!DP_Map
    LDA.b !Map_Unk1D93-!DP_Map
    BNE .keep_x
    STZ.b !Map_Unk1D2E-!DP_Map
.keep_x:
    LDA.b !Map_Unk1D96-!DP_Map
    BNE .apply2
    STZ.b !Map_Unk1D30-!DP_Map
    LDA.b !Map_Unk1D93-!DP_Map
    BNE .apply2
    STZ.w !DP_Field+!Field_Unk38 ; neither enabled: done
    PLD
    RTS
.apply2:
    JSR Map_Unk91AC
    JSR Map_Unk93E1
    PLD
    RTS

; ------------------------------------------------------------
; $C0:88E5 — Map_ResetUnk1D2E (9 bytes, $88E5–$88ED)
; Copies Map_Unk1D2A to Map_Unk1D2E and Map_Unk1D2B to Map_Unk1D30 at
; the start of every Field_FrameUpdate (so those two hold per-frame
; values derived from a standing pair; meaning unknown).
; Callers: Field_FrameUpdate ($C0:882C), its only JSR site.
; On entry: M=1 (8-bit A), DP=$1D00.
; Exit: M=1, DP unchanged; A = Map_Unk1D2B.
; ------------------------------------------------------------
Map_ResetUnk1D2E:
    LDA.b !Map_Unk1D2A-!DP_Map
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b !Map_Unk1D2B-!DP_Map
    STA.b !Map_Unk1D30-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:88EE — Field_DpadDispatch (20 bytes, $88EE–$8901)
; Unless Field_Unk38 is busy, runs the Field_DpadHandlerTable entry
; picked by Pad_Unk00F9 bits 0-3 (16 entries; the D-pad bits, if
; Pad_Unk00F9 is laid out like Pad_Pressed's high byte), with 8-bit
; X/Y. The handlers (Field_DpadNone ... Field_DpadUpLeft) set the
; frame's D-pad step in Map_Unk1D2C/1D2D and add it to Map_Unk1D2E/1D30.
; Callers: Field_FrameUpdate ($C0:883D), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00, DB=$00.
; Exit: M=1, X=0, DP unchanged; A and X clobbered, plus what the
; handler changes.
; ------------------------------------------------------------
Field_DpadDispatch:
    LDA.w !DP_Field+!Field_Unk38
    BNE .done
    LDA.w !Pad_Unk00F9
    AND.b #!Pad_DpadMask
    ASL A
    SEP #$10
    TAX
    JSR (Field_DpadHandlerTable,X)
    REP #$10
.done:
    RTS

; Field_DpadHandlerTable: Field_DpadDispatch's handler for each value of
; Pad_Unk00F9 bits 0-3, read as Right (bit 0), Left (1), Down (2) and
; Up (3) from what the handlers do; impossible pairs (Left+Right,
; Up+Down) and three or more bits go to Field_DpadNone. A 17th word
; follows that the 4-bit index can never reach.
Field_DpadHandlerTable:
    dw Field_DpadNone           ; 0: nothing
    dw Field_DpadRight          ; 1: Right
    dw Field_DpadLeft           ; 2: Left
    dw Field_DpadNone           ; 3: Left+Right
    dw Field_DpadDown           ; 4: Down
    dw Field_DpadDownRight      ; 5: Down+Right
    dw Field_DpadDownLeft       ; 6: Down+Left
    dw Field_DpadNone           ; 7
    dw Field_DpadUp             ; 8: Up
    dw Field_DpadUpRight        ; 9: Up+Right
    dw Field_DpadUpLeft         ; 10: Up+Left
    dw Field_DpadNone           ; 11
    dw Field_DpadNone           ; 12: Up+Down
    dw Field_DpadNone           ; 13
    dw Field_DpadNone           ; 14
    dw Field_DpadNone           ; 15
    dw Field_DpadNone           ; 16: unreachable (index <= 15)

; ------------------------------------------------------------
; $C0:8924 — Field_DpadNone (1 byte, $8924)
; No direction (or an impossible combination): leaves Map_Unk1D2C/1D2D
; at the 0 Field_FrameUpdate set and Map_Unk1D2E/1D30 as they are.
; The handlers after it set the D-pad step: Map_Unk1D2C (X) and
; Map_Unk1D2D (Y) get the signed step of this frame, and the same step
; is added to Map_Unk1D2E / Map_Unk1D30 (which Map_ResetUnk1D2E reset
; from Map_Unk1D2A/1D2B just before). Reading these as the leader's
; movement for the frame (right / down positive) is an inference from
; the pad bits; how the steps are used is not traced yet.
; Reached only through Field_DpadHandlerTable (entries 0, 3, 7, 11-16).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: everything unchanged.
; ------------------------------------------------------------
Field_DpadNone:
    RTS

; ------------------------------------------------------------
; $C0:8925 — Field_DpadRight (31 bytes, $8925–$8943)
; Right: Map_Unk1D2C = +$10 and Map_Unk1D2E += $10;
; $20 each instead while Pad_Unk00F8 bit 1 (Pad_Unk00F8Bit1) is set.
; Reached only through Field_DpadHandlerTable (entry 1, Right).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=1, DP and DB unchanged; A clobbered.
; ------------------------------------------------------------
Field_DpadRight:
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit1
    BEQ .walk
    LDA.b #!Map_RunStepPos
    STA.b !Map_Unk1D2C-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b #!Map_RunStepPos
    STA.b !Map_Unk1D2E-!DP_Map
    RTS
.walk:
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D2C-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8944 — Field_DpadLeft (31 bytes, $8944–$8962)
; Left: Map_Unk1D2C = -$10 and Map_Unk1D2E -= $10;
; $20 each instead while Pad_Unk00F8 bit 1 (Pad_Unk00F8Bit1) is set.
; Reached only through Field_DpadHandlerTable (entry 2, Left).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=1, DP and DB unchanged; A clobbered.
; ------------------------------------------------------------
Field_DpadLeft:
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit1
    BEQ .walk
    LDA.b #!Map_RunStepNeg
    STA.b !Map_Unk1D2C-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    SEC
    SBC.b #!Map_RunStepPos
    STA.b !Map_Unk1D2E-!DP_Map
    RTS
.walk:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D2C-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    SEC
    SBC.b #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8963 — Field_DpadUp (31 bytes, $8963–$8981)
; Up: Map_Unk1D2D = -$10 and Map_Unk1D30 -= $10;
; $20 each instead while Pad_Unk00F8 bit 1 (Pad_Unk00F8Bit1) is set.
; Reached only through Field_DpadHandlerTable (entry 8, Up).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=1, DP and DB unchanged; A clobbered.
; ------------------------------------------------------------
Field_DpadUp:
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit1
    BEQ .walk
    LDA.b #!Map_RunStepNeg
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.b #!Map_RunStepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS
.walk:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8982 — Field_DpadDown (31 bytes, $8982–$89A0)
; Down: Map_Unk1D2D = +$10 and Map_Unk1D30 += $10;
; $20 each instead while Pad_Unk00F8 bit 1 (Pad_Unk00F8Bit1) is set.
; Reached only through Field_DpadHandlerTable (entry 4, Down).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=1, DP and DB unchanged; A clobbered.
; ------------------------------------------------------------
Field_DpadDown:
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit1
    BEQ .walk
    LDA.b #!Map_RunStepPos
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b #!Map_RunStepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS
.walk:
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:89A1 — Field_DpadDownRight (49 bytes, $89A1–$89D1)
; Down+Right: both steps +$10, both sums up by $10;
; $20 each instead while Pad_Unk00F8 bit 1 (Pad_Unk00F8Bit1) is set.
; Reached only through Field_DpadHandlerTable (entry 5, Down+Right).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=1, DP and DB unchanged; A clobbered.
; ------------------------------------------------------------
Field_DpadDownRight:
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit1
    BEQ .walk
    LDA.b #!Map_RunStepPos
    STA.b !Map_Unk1D2C-!DP_Map
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b #!Map_RunStepPos
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b #!Map_RunStepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS
.walk:
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D2C-!DP_Map
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:89D2 — Field_DpadDownLeft (53 bytes, $89D2–$8A06)
; Down+Left: X step -$10 (sum down), Y step +$10 (sum up);
; $20 each instead while Pad_Unk00F8 bit 1 (Pad_Unk00F8Bit1) is set.
; Reached only through Field_DpadHandlerTable (entry 6, Down+Left).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=1, DP and DB unchanged; A clobbered.
; ------------------------------------------------------------
Field_DpadDownLeft:
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit1
    BEQ .walk
    LDA.b #!Map_RunStepNeg
    STA.b !Map_Unk1D2C-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    SEC
    SBC.b #!Map_RunStepPos
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b #!Map_RunStepPos
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b #!Map_RunStepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS
.walk:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D2C-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    SEC
    SBC.b #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8A07 — Field_DpadUpRight (53 bytes, $8A07–$8A3B)
; Up+Right: X step +$10 (sum up), Y step -$10 (sum down);
; $20 each instead while Pad_Unk00F8 bit 1 (Pad_Unk00F8Bit1) is set.
; Reached only through Field_DpadHandlerTable (entry 9, Up+Right).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=1, DP and DB unchanged; A clobbered.
; ------------------------------------------------------------
Field_DpadUpRight:
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit1
    BEQ .walk
    LDA.b #!Map_RunStepPos
    STA.b !Map_Unk1D2C-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b #!Map_RunStepPos
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b #!Map_RunStepNeg
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.b #!Map_RunStepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS
.walk:
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D2C-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:8A3C — Field_DpadUpLeft (49 bytes, $8A3C–$8A6C)
; Up+Left: both steps -$10, both sums down by $10;
; $20 each instead while Pad_Unk00F8 bit 1 (Pad_Unk00F8Bit1) is set.
; Reached only through Field_DpadHandlerTable (entry 10, Up+Left).
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=1, DP and DB unchanged; A clobbered.
; ------------------------------------------------------------
Field_DpadUpLeft:
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit1
    BEQ .walk
    LDA.b #!Map_RunStepNeg
    STA.b !Map_Unk1D2C-!DP_Map
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    SEC
    SBC.b #!Map_RunStepPos
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.b #!Map_RunStepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS
.walk:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D2C-!DP_Map
    STA.b !Map_Unk1D2D-!DP_Map
    LDA.b !Map_Unk1D2E-!DP_Map
    SEC
    SBC.b #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    RTS

; ============================================================
; Leader collision ($C0:8A6D–$C0:9174 and $C0:9923–$C0:99DD,
; $C0:9AA1–$C0:9DC2)
; Map_Unk8A6D tests the frame's step (Map_Unk1D2E X, Map_Unk1D30 Y,
; in Obj_PosX/Y units, 1/256 tile) against the leader's box: X from
; -$70 to +$70 around Obj_PosX, Y from -$70 to 0 above Obj_PosY. Its
; probes are Map_ProbeHitsObj (other objects), Map_ProbeTileAttrs,
; Map_ProbeTileLevel and Map_ProbeLevelBlocked (the map tile under one
; point); Map_StepTileEffects commits a step. All run with DP =
; !DP_Map ($1D00) and DB=$00.
; ============================================================

; ------------------------------------------------------------
; $C0:8A6D — Map_Unk8A6D (1800 bytes, $8A6D–$9174)
; Probably the leader's collision with the map and with other objects
; (inferred: it zeroes the parts of the step whose moved box would have
; a corner on a blocking tile or touch a blocking object, and the steps
; it keeps are the ones Map_Unk9175 and the layer scroll then use).
; Picks a path by the signs of the two steps (both zero: nothing). Each
; path sign-extends the steps into Map_Unk1D2EHi / Map_Unk1D30Hi, copies
; the leader's Obj_PosX/Y into Map_LeaderX/Y, and first asks
; Map_ProbeHitsObj about the leading corner (the leading edge's middle
; for a straight step, at mid-height Y-$40 for a sideways one); a hit
; zeroes the step(s) and returns. Then it tests the corners of the moved
; box with .test_probe:
; - straight step: both corners of the leading edge. Both free: commit.
;   One blocked, the other free: slide by $10 on the other axis, away
;   from the blocked corner (written into that step), and test both
;   corners again with the slide added; by what still blocks it commits
;   both steps, keeps only the slide (when a corner moved by the slide
;   alone is free) or stops (see the comments at each block). A
;   treasure tile under the first corner tested (under either, for a
;   vertical step) stops the step at once.
; - diagonal step: see the comment at .up_right.
; "Commit" is Map_StepTileEffects (JSR or BRL to it), which also writes
; the frame's push into Map_Unk1D2A/1D2B. Where a step is cut its high
; byte ends up zero too (16-bit stores, or on the .up/.down object-hit
; paths 8-bit STZ with Map_Unk1D30Hi cleared or already zero).
; Callers: Field_FrameUpdate ($C0:8847), its only JSR site.
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$1D00 (!DP_Map), DB=$00
; (Obj_PosX/Y and the field page are read absolute).
; Exit: M=1, X=1 or X=0 (Map_ProbeHitsObj and a treasure probe return
; 16-bit X; Field_FrameUpdate sets X=0 after the call anyway), DP and DB
; unchanged; Map_Unk1D2E/1D30 (and their Hi bytes) hold the steps kept;
; A, X, Y clobbered; Map_LeaderX/Y,
; Map_ProbeX/Y and the probe scratch ($1D52-$1D6F) overwritten;
; Field_UnkEB may hold a touched object (Map_ProbeHitsObj); a commit
; changes what Map_StepTileEffects says.
; ------------------------------------------------------------
org $C08A6D
Map_Unk8A6D:
    LDA.b !Map_Unk1D30-!DP_Map
    BEQ .y_zero
    BMI .y_neg
    LDA.b !Map_Unk1D2E-!DP_Map
    BEQ .to_down
    BMI .to_down_left
    BRL .down_right
.to_down_left:
    BRL .down_left
.to_down:
    BRL .down
.y_zero:
    LDA.b !Map_Unk1D2E-!DP_Map
    BEQ .no_step
    BMI .to_left
    BRL .right
.to_left:
    BRL .left
.no_step:
    RTS
.y_neg:
    LDA.b !Map_Unk1D2E-!DP_Map
    BEQ .to_up
    BMI .to_up_left
    BRL .up_right
.to_up_left:
    BRL .up_left
.to_up:
    BRL .up
; Tile test of the point Map_ProbeX/Y (entered with M=0): A = the
; probe's map row << 8 | column. C=0: free. C=1 with Z=0 (A =
; Map_ProbeIsChest): a treasure tile; C=1 with Z=1: the half tile under
; the probe blocks (Map_ProbeLevelBlocked). Returns M=1.
.test_probe:
    LDA.b !Map_ProbeY-!DP_Map
    SEP #$20
    LDA.b !Map_ProbeTileX-!DP_Map
    JSR Map_ProbeTileAttrs
    BCC .probe_level
    LDA.b #!Map_ProbeIsChest            ; Z=0: a treasure tile
    RTS
.probe_level:
    JSR Map_ProbeTileLevel
    JSR Map_ProbeLevelBlocked
    LDA.b #!Map_ProbeIsTile             ; Z=1 (C from Map_ProbeLevelBlocked)
    RTS
; X step only, rightwards: objects at the right edge, mid-height; then
; the tiles under both right corners (.side_tiles, shared with .left).
.right:
    STZ.b !Map_Unk1D2EHi-!DP_Map
    STZ.b !Map_Unk1D30Hi-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot
    REP #$20
    LDA.w !Obj_PosX,X
    STA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.w !Obj_PosY,X
    STA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxMidY
    STA.b !Map_ProbeY-!DP_Map
    SEP #$20
    JSR Map_ProbeHitsObj
    BCC .side_tiles
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
; Bottom (foot) corner first, then the top one; both free: commit.
.side_tiles:
    REP #$20
    LDA.b !Map_LeaderY-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCS .side_foot_blocked
    REP #$20
    LDA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCS .side_slide_down
    JSR Map_StepTileEffects
    RTS
; Foot corner blocked: stop on a treasure; else, if the top corner is
; free, try sliding up around the corner.
.side_foot_blocked:
    BNE .side_stop_x
    REP #$20
    LDA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .side_slide_up
.side_stop_x:
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
; Y step -$10: test the foot corner moved up.
.side_slide_up:
    REP #$20
    LDA.w #!Map_StepNeg16
    STA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b !Map_LeaderY-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .side_up_head
    BRA .side_up_only
; Quirk: never taken; .test_probe returns Z=1 with C=0, and this is
; only reached with C=0. Kept from the original.
.side_up_head:
    BNE .side_stop_x
    REP #$20
    LDA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .side_up_commit
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.side_up_commit:
    BRL Map_StepTileEffects
; Foot free, top corner blocked (a treasure is not told apart here):
; Y step +$10, test the foot corner moved down.
.side_slide_down:
    REP #$20
    LDA.w #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b !Map_LeaderY-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .side_down_head
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.side_down_commit:
    BRL Map_StepTileEffects
.side_down_head:
    REP #$20
    LDA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .side_down_commit
    BRA .side_down_only
; The moved-up foot is blocked too: drop the X step and test the top
; corner straight up (at the leader's own right / left edge).
.side_up_only:
    REP #$20
    LDA.b !Map_ProbeX-!DP_Map
    SEC
    SBC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .side_up_only_commit
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.side_up_only_commit:
    BRL Map_StepTileEffects
; The moved-down top is blocked: drop the X step and move straight down
; if the foot corner allows it.
.side_down_only:
    REP #$20
    LDA.b !Map_ProbeX-!DP_Map
    SEC
    SBC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .side_down_only_commit
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.side_down_only_commit:
    BRL Map_StepTileEffects
; X step only, leftwards: as .right with the left edge.
.left:
    LDA.b #!Map_StepHiNeg
    STA.b !Map_Unk1D2EHi-!DP_Map
    STZ.b !Map_Unk1D30Hi-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot
    REP #$20
    LDA.w !Obj_PosX,X
    STA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    LDA.w !Obj_PosY,X
    STA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxMidY
    STA.b !Map_ProbeY-!DP_Map
    SEP #$20
    JSR Map_ProbeHitsObj
    BCC .left_tiles
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.left_tiles:
    BRL .side_tiles
; Y step only, upwards: objects at the top middle of the box, then the
; tiles under both top corners (left first). One corner blocked, the
; other free: slide $10 sideways away from the blocked corner, as in
; .side_tiles; a treasure under either corner stops the step.
.up:
    LDA.b #!Map_StepHiNeg
    STA.b !Map_Unk1D30Hi-!DP_Map
    STZ.b !Map_Unk1D2EHi-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot
    REP #$20
    LDA.w !Obj_PosX,X
    STA.b !Map_LeaderX-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.w !Obj_PosY,X
    STA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    SEP #$20
    JSR Map_ProbeHitsObj
    BCC .up_tiles
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D30Hi-!DP_Map
    RTS
.up_tiles:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .up_left_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .up_right_blocked
    BRL Map_StepTileEffects
.up_left_blocked:
    BNE .up_stop_y
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .up_slide_right
.up_stop_y:
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.up_slide_right:
    REP #$20
    LDA.w #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .up_right_edge
    BRA .up_right_only
.up_right_edge:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .up_commit_diag_r
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.up_commit_diag_r:
    BRL Map_StepTileEffects
.up_right_blocked:
    BNE .up_stop_y
    REP #$20
    LDA.w #!Map_StepNeg16
    STA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b !Map_LeaderX-!DP_Map
    ADC.w #!Map_BoxHalfW          ; no CLC: the carry from the add above (set when LeaderX >= $10) lands it 1 unit further right (quirk, kept)
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .up_left_edge
    BRA .up_left_only
.up_left_edge:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .up_commit_diag_l
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.up_commit_diag_l:
    BRL Map_StepTileEffects
; The moved box's left corner is blocked too: drop the Y step and move
; straight right if the right corner allows it.
.up_right_only:
    REP #$20
    LDA.b !Map_ProbeY-!DP_Map
    SEC
    SBC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .up_right_only_commit
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.up_right_only_commit:
    BRL Map_StepTileEffects
; As .up_right_only, moving straight left.
.up_left_only:
    REP #$20
    LDA.b !Map_ProbeY-!DP_Map
    SEC
    SBC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .up_left_only_commit
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.up_left_only_commit:
    BRL Map_StepTileEffects
; Y step only, downwards: as .up with the box's bottom edge (the
; leader's Y itself); its own copy of the corner tests.
.down:
    STZ.b !Map_Unk1D30Hi-!DP_Map
    STZ.b !Map_Unk1D2EHi-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot
    REP #$20
    LDA.w !Obj_PosX,X
    STA.b !Map_LeaderX-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.w !Obj_PosY,X
    STA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    SEP #$20
    JSR Map_ProbeHitsObj
    BCC .down_tiles
    STZ.b !Map_Unk1D30-!DP_Map
    RTS
.down_tiles:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .dn_left_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .dn_right_blocked
    BRL Map_StepTileEffects
.dn_left_blocked:
    BNE .dn_stop_y
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .dn_slide_right
.dn_stop_y:
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.dn_slide_right:
    REP #$20
    LDA.w #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .dn_right_edge
    BRA .dn_right_only
.dn_right_edge:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .dn_commit_diag_r
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.dn_commit_diag_r:
    BRL Map_StepTileEffects
.dn_right_blocked:
    BNE .dn_stop_y
    REP #$20
    LDA.w #!Map_StepNeg16
    STA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b !Map_LeaderX-!DP_Map
    ADC.w #!Map_BoxHalfW          ; no CLC: the carry from the add above (set when LeaderX >= $10) lands it 1 unit further right (quirk, kept)
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .dn_left_edge
    BRA .dn_left_only
.dn_left_edge:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .dn_commit_diag_l
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.dn_commit_diag_l:
    BRL Map_StepTileEffects
.dn_right_only:
    REP #$20
    LDA.b !Map_ProbeY-!DP_Map
    SEC
    SBC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .dn_right_only_commit
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.dn_right_only_commit:
    BRL Map_StepTileEffects
.dn_left_only:
    REP #$20
    LDA.b !Map_ProbeY-!DP_Map
    SEC
    SBC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCC .dn_left_only_commit
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.dn_left_only_commit:
    BRL Map_StepTileEffects
; Diagonal steps test three corners of the moved box: the leading one,
; then the other corner of the leading Y edge, then the other corner of
; the leading X edge. All free: commit. Second blocked: keep only the
; X step if the third is free (and redo as the straight step), else stop
; both. Second free, third blocked: keep only the Y step and redo as
; the straight step. Leading blocked but both others free: stop both.
.up_right:
    LDA.b #!Map_StepHiNeg
    STA.b !Map_Unk1D30Hi-!DP_Map
    STZ.b !Map_Unk1D2EHi-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot
    REP #$20
    LDA.w !Obj_PosX,X
    STA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.w !Obj_PosY,X
    STA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    SEP #$20
    JSR Map_ProbeHitsObj
    BCC .ur_tiles
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.ur_tiles:
    REP #$20
    JSR .test_probe
    BCS .ur_corner_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .ur_top_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCS .ur_keep_y
    BRL Map_StepTileEffects
.ur_corner_blocked:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .ur_top_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCS .ur_keep_y
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.ur_keep_y:
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    BRL .up
.ur_top_blocked:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .ur_keep_x
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.ur_keep_x:
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    BRL .right
; Quirk: the first two bottom-left probes below add the X step right after
; SBC with no CLC, so they land 1 unit (1/256 tile) further right (the one
; in .ul_top_blocked has its CLC); kept.
.up_left:
    LDA.b #!Map_StepHiNeg
    STA.b !Map_Unk1D30Hi-!DP_Map
    STA.b !Map_Unk1D2EHi-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot
    REP #$20
    LDA.w !Obj_PosX,X
    STA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.w !Obj_PosY,X
    STA.b !Map_LeaderY-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    SEP #$20
    JSR Map_ProbeHitsObj
    BCC .ul_tiles
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.ul_tiles:
    REP #$20
    JSR .test_probe
    BCS .ul_corner_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .ul_top_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCS .ul_keep_y
    BRL Map_StepTileEffects
.ul_corner_blocked:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .ul_top_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCS .ul_keep_y
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.ul_keep_y:
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    BRL .up
.ul_top_blocked:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .ul_keep_x
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.ul_keep_x:
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    BRL .left
; Quirk: the first two top-left probes below add the X step with no CLC
; after SBC (1 unit further right); kept.
.down_left:
    STZ.b !Map_Unk1D30Hi-!DP_Map
    LDA.b #!Map_StepHiNeg
    STA.b !Map_Unk1D2EHi-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot
    REP #$20
    LDA.w !Obj_PosX,X
    STA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.w !Obj_PosY,X
    STA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    SEP #$20
    JSR Map_ProbeHitsObj
    BCC .dl_tiles
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.dl_tiles:
    REP #$20
    JSR .test_probe
    BCS .dl_corner_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .dl_bottom_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .dl_commit
    BRL .dl_keep_y
.dl_commit:
    BRL Map_StepTileEffects
.dl_corner_blocked:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .dl_bottom_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCS .dl_keep_y
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.dl_bottom_blocked:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .dl_keep_x
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.dl_keep_y:
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    BRL .down
.dl_keep_x:
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    BRL .left
; Quirk: the bottom-left probes below add the X step with no CLC after
; SBC (1 unit further right); kept.
.down_right:
    STZ.b !Map_Unk1D30Hi-!DP_Map
    STZ.b !Map_Unk1D2EHi-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot
    REP #$20
    LDA.w !Obj_PosX,X
    STA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.w !Obj_PosY,X
    STA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    SEP #$20
    JSR Map_ProbeHitsObj
    BCC .dr_tiles
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.dr_tiles:
    REP #$20
    JSR .test_probe
    BCS .dr_corner_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .dr_bottom_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .dr_commit
    BRL .dr_keep_y
.dr_commit:
    BRL Map_StepTileEffects
.dr_corner_blocked:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    SEC
    SBC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    JSR .test_probe
    BCS .dr_bottom_blocked
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCS .dr_keep_y
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.dr_bottom_blocked:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.w #!Map_BoxHalfW
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    SEC
    SBC.w #!Map_BoxHeight
    STA.b !Map_ProbeY-!DP_Map
    JSR .test_probe
    BCC .dr_keep_x
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    RTS
.dr_keep_y:
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    SEP #$20
    BRL .down
.dr_keep_x:
    REP #$20
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    BRL .right

; ------------------------------------------------------------
; $C0:9175 — Map_Unk9175 (55 bytes, $9175–$91AB)
; Field_FrameUpdate's step after the D-pad: zeroes Map_Unk1D32/1D33,
; then copies Map_Unk1D2E (signed X step) into Map_Unk1D32 unless the
; leader is already at the limit in that direction (Map_LeaderPastColMax
; for a positive step, Map_LeaderPastColMin for a negative one), and
; Map_Unk1D30 into Map_Unk1D33 the same way with
; Map_LeaderPastRowMax / Map_LeaderPastRowMin. A zero step is left out.
; What 1D32/1D33 drive is not traced (Map_Unk91AC and Map_Unk93E1 run
; later in the same frame).
; Callers: Field_FrameUpdate ($C0:884C), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; X = the leader's slot; A
; clobbered; Eng_Scratch ($01D9) may be overwritten by the tests.
; ------------------------------------------------------------
org $C09175
Map_Unk9175:
    STZ.b !Map_Unk1D32-!DP_Map
    STZ.b !Map_Unk1D33-!DP_Map
    TDC
    XBA                         ; B = DP's low byte, 0
    LDA.w !DP_Field+!Party_ObjSlot
    TAX                         ; X = the leader's slot (16-bit)
    LDA.b !Map_Unk1D2E-!DP_Map
    BEQ .y_step
    BPL .right
    JSR Map_LeaderPastColMin
    BCS .y_step
    BRA .copy_x
.right:
    JSR Map_LeaderPastColMax
    BCS .y_step
.copy_x:
    LDA.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_Unk1D32-!DP_Map
.y_step:
    LDA.b !Map_Unk1D30-!DP_Map
    BEQ .done
    BPL .down
    JSR Map_LeaderPastRowMin
    BCS .done
    BRA .copy_y
.down:
    JSR Map_LeaderPastRowMax
    BCS .done
.copy_y:
    LDA.b !Map_Unk1D30-!DP_Map
    STA.b !Map_Unk1D33-!DP_Map
.done:
    RTS

; ============================================================
; Layer scroll: accumulate and step ($C0:91AC–$C0:9922)
; Map_Unk91AC adds up the frame's scroll amounts for three sets of
; scroll words in 1/16 pixel and splits out whole pixels; Map_Unk93E1
; steps the words a pixel at a time (Map_Scroll*), noting each 8-pixel
; boundary crossed per layer and direction (Map_Edge*), and then has
; the edge rows / columns built (Map_EdgeRows*/Cols*). All run with
; DP = !DP_Map ($1D00).
; ============================================================

; ------------------------------------------------------------
; $C0:91AC — Map_Unk91AC (565 bytes, $91AC–$93E0)
; Adds up this frame's scroll amounts for three sets of layer scroll
; words and splits them into whole pixels for Map_Unk93E1, which runs
; next. In order:
; 1. Scroll-to: while Map_ScrollToMode is nonzero, sets the camera step
;    Map_Unk1D2E to +$10 / -$10 while Map_TileOriginX (low byte) is
;    below / above Map_ScrollToX, and also -$10 when they are equal but
;    Map_Unk1D87 is not on a 16-pixel boundary; when both hold it sets
;    ScrollTo_XDone in Map_ScrollToDone and leaves Map_Unk1D2E alone.
;    The same for Y (Map_ScrollToY, Map_Unk1D30, Map_Unk1D89,
;    ScrollTo_YDone). Once both bits are set it stores ScrollTo_Arrived
;    in Map_ScrollToMode and clears Map_ScrollToDone (the mode stays
;    nonzero, so it keeps holding the target).
; 2. Shake: while Field_UnkBC is set, Map_ShakeX = $10 if Eng_Unk0400
;    bit 2 is set, else 0, Map_ShakeY the same from bit 1, both negated
;    when bit 0 is set; each is then zeroed while the low byte of
;    Map_TileOriginX / Y is 0. With Field_UnkBC clear the old values are kept.
; 3. Accumulate, in 1/16 pixel (a walking step of $10 = 1 pixel):
;    Map_Acc1X += Map_Unk1D2E + Map_Drift1X + Map_ShakeX, Map_Acc1Y the
;    same with Map_Unk1D30. Set 2 adds Map_OwnStep2X/Y and Map_Drift2X/Y
;    always, plus the camera step and the shake unless Map_OwnStepFlags
;    bit 1 is set; set 3 likewise with bit 2. All 8-bit, wrapping.
; 4. Split each Map_Acc*: the whole pixels (|acc| / 16) go to its
;    Map_Move*Pos or Map_Move*Neg byte by sign (the other is zeroed),
;    and the signed remainder stays in the accumulator.
; 5. Counts Map_DriftTimer down if it is running; when it reaches 0,
;    Map_Drift1X..Map_Drift3Y are zeroed.
; Callers: Field_FrameUpdate ($C0:8852), Field_Unk885A ($C0:88B9,
;   $C0:88DD).
; On entry: M=1 (8-bit A), DP=$1D00 (!DP_Map), DB=$00 (Eng_Unk0400 and
;   Field_UnkBC are read absolute). X is not used.
; Exit: M=1, DP and DB unchanged; A clobbered; X and Y unchanged.
; ------------------------------------------------------------
org $C091AC
Map_Unk91AC:
    LDA.b !Map_ScrollToMode-!DP_Map
    BEQ .shake
    LDA.b !Map_ScrollToX-!DP_Map
    CMP.b !Map_TileOriginX-!DP_Map
    BEQ .x_at_target
    BCC .x_back
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D2E-!DP_Map
    BRA .to_y
.x_back:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D2E-!DP_Map
    BRA .to_y
.x_at_target:
    LDA.b !Map_Unk1D87-!DP_Map
    AND.b #!Map_TilePixelMask
    BNE .x_back                 ; not on a 16-pixel boundary yet
    LDA.b #!ScrollTo_XDone
    TSB.b !Map_ScrollToDone-!DP_Map
.to_y:
    LDA.b !Map_ScrollToY-!DP_Map
    CMP.b !Map_TileOriginY-!DP_Map
    BEQ .y_at_target
    BCC .y_back
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    BRA .shake
.y_back:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D30-!DP_Map
    BRA .shake
.y_at_target:
    LDA.b !Map_Unk1D89-!DP_Map
    AND.b #!Map_TilePixelMask
    BNE .y_back
    LDA.b #!ScrollTo_YDone
    TSB.b !Map_ScrollToDone-!DP_Map
    LDA.b !Map_ScrollToDone-!DP_Map
    CMP.b #!ScrollTo_BothDone
    BNE .shake
    LDA.b #!ScrollTo_Arrived
    STA.b !Map_ScrollToMode-!DP_Map
    STZ.b !Map_ScrollToDone-!DP_Map
.shake:
    LDA.w !DP_Field+!Field_UnkBC
    BEQ .accumulate
    LDA.w !Eng_Unk0400
    BIT.b #!Eng0400_Negative
    BNE .shake_neg
    AND.b #!Eng0400_ShakeX
    ASL A
    ASL A
    STA.b !Map_ShakeX-!DP_Map
    LDA.w !Eng_Unk0400
    AND.b #!Eng0400_ShakeY
    ASL A
    ASL A
    ASL A
    STA.b !Map_ShakeY-!DP_Map
    BRA .shake_edges
.shake_neg:
    AND.b #!Eng0400_ShakeX
    ASL A
    ASL A
    EOR.b #!Eng_Invert8
    INC A
    STA.b !Map_ShakeX-!DP_Map
    LDA.w !Eng_Unk0400
    AND.b #!Eng0400_ShakeY
    ASL A
    ASL A
    ASL A
    EOR.b #!Eng_Invert8
    INC A
    STA.b !Map_ShakeY-!DP_Map
.shake_edges:
    LDA.b !Map_TileOriginX-!DP_Map
    BNE .shake_y_edge
    STZ.b !Map_ShakeX-!DP_Map
.shake_y_edge:
    LDA.b !Map_TileOriginY-!DP_Map
    BNE .accumulate
    STZ.b !Map_ShakeY-!DP_Map
.accumulate:
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b !Map_Acc1X-!DP_Map
    CLC
    ADC.b !Map_Drift1X-!DP_Map
    CLC
    ADC.b !Map_ShakeX-!DP_Map
    STA.b !Map_Acc1X-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b !Map_Acc1Y-!DP_Map
    CLC
    ADC.b !Map_Drift1Y-!DP_Map
    CLC
    ADC.b !Map_ShakeY-!DP_Map
    STA.b !Map_Acc1Y-!DP_Map
    LDA.b !Map_OwnStepFlags-!DP_Map
    BIT.b #!Map_OwnStep2
    BEQ .set2_follow
    CLC
    LDA.b !Map_OwnStep2X-!DP_Map
    ADC.b !Map_Acc2X-!DP_Map
    CLC
    ADC.b !Map_Drift2X-!DP_Map
    STA.b !Map_Acc2X-!DP_Map
    CLC
    LDA.b !Map_OwnStep2Y-!DP_Map
    ADC.b !Map_Acc2Y-!DP_Map
    CLC
    ADC.b !Map_Drift2Y-!DP_Map
    STA.b !Map_Acc2Y-!DP_Map
    BRA .set3
.set2_follow:
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b !Map_OwnStep2X-!DP_Map
    CLC
    ADC.b !Map_Acc2X-!DP_Map
    CLC
    ADC.b !Map_Drift2X-!DP_Map
    CLC
    ADC.b !Map_ShakeX-!DP_Map
    STA.b !Map_Acc2X-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b !Map_OwnStep2Y-!DP_Map
    CLC
    ADC.b !Map_Acc2Y-!DP_Map
    CLC
    ADC.b !Map_Drift2Y-!DP_Map
    CLC
    ADC.b !Map_ShakeY-!DP_Map
    STA.b !Map_Acc2Y-!DP_Map
.set3:
    LDA.b !Map_OwnStepFlags-!DP_Map
    BIT.b #!Map_OwnStep3
    BEQ .set3_follow
    CLC
    LDA.b !Map_OwnStep3X-!DP_Map
    ADC.b !Map_Acc3X-!DP_Map
    CLC
    ADC.b !Map_Drift3X-!DP_Map
    STA.b !Map_Acc3X-!DP_Map
    CLC
    LDA.b !Map_OwnStep3Y-!DP_Map
    ADC.b !Map_Acc3Y-!DP_Map
    CLC
    ADC.b !Map_Drift3Y-!DP_Map
    STA.b !Map_Acc3Y-!DP_Map
    BRA .split
.set3_follow:
    LDA.b !Map_Unk1D2E-!DP_Map
    CLC
    ADC.b !Map_OwnStep3X-!DP_Map
    CLC
    ADC.b !Map_Acc3X-!DP_Map
    CLC
    ADC.b !Map_Drift3X-!DP_Map
    CLC
    ADC.b !Map_ShakeX-!DP_Map
    STA.b !Map_Acc3X-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    CLC
    ADC.b !Map_OwnStep3Y-!DP_Map
    CLC
    ADC.b !Map_Acc3Y-!DP_Map
    CLC
    ADC.b !Map_Drift3Y-!DP_Map
    CLC
    ADC.b !Map_ShakeY-!DP_Map
    STA.b !Map_Acc3Y-!DP_Map
.split:                         ; the same split for each of the six accumulators
    LDA.b !Map_Acc1X-!DP_Map
    BMI .acc1x_neg
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move1XPos-!DP_Map
    STZ.b !Map_Move1XNeg-!DP_Map
    BRA .acc1x_rem
.acc1x_neg:
    EOR.b #!Eng_Invert8
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move1XNeg-!DP_Map
    STZ.b !Map_Move1XPos-!DP_Map
.acc1x_rem:
    LDA.b !Map_Acc1X-!DP_Map
    AND.b #!Map_SubMask
    BEQ .acc1x_store            ; no remainder: store 0
    LDA.b !Map_Acc1X-!DP_Map
    BPL .acc1x_pos
    ORA.b #!Map_SubSignExt
    BRA .acc1x_store
.acc1x_pos:
    AND.b #!Map_SubMask
.acc1x_store:
    STA.b !Map_Acc1X-!DP_Map
    LDA.b !Map_Acc1Y-!DP_Map
    BMI .acc1y_neg
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move1YPos-!DP_Map
    STZ.b !Map_Move1YNeg-!DP_Map
    BRA .acc1y_rem
.acc1y_neg:
    EOR.b #!Eng_Invert8
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move1YNeg-!DP_Map
    STZ.b !Map_Move1YPos-!DP_Map
.acc1y_rem:
    LDA.b !Map_Acc1Y-!DP_Map
    AND.b #!Map_SubMask
    BEQ .acc1y_store
    LDA.b !Map_Acc1Y-!DP_Map
    BPL .acc1y_pos
    ORA.b #!Map_SubSignExt
    BRA .acc1y_store
.acc1y_pos:
    AND.b #!Map_SubMask
.acc1y_store:
    STA.b !Map_Acc1Y-!DP_Map
    LDA.b !Map_Acc2X-!DP_Map
    BMI .acc2x_neg
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move2XPos-!DP_Map
    STZ.b !Map_Move2XNeg-!DP_Map
    BRA .acc2x_rem
.acc2x_neg:
    EOR.b #!Eng_Invert8
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move2XNeg-!DP_Map
    STZ.b !Map_Move2XPos-!DP_Map
.acc2x_rem:
    LDA.b !Map_Acc2X-!DP_Map
    AND.b #!Map_SubMask
    BEQ .acc2x_store
    LDA.b !Map_Acc2X-!DP_Map
    BPL .acc2x_pos
    ORA.b #!Map_SubSignExt
    BRA .acc2x_store
.acc2x_pos:
    AND.b #!Map_SubMask
.acc2x_store:
    STA.b !Map_Acc2X-!DP_Map
    LDA.b !Map_Acc2Y-!DP_Map
    BMI .acc2y_neg
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move2YPos-!DP_Map
    STZ.b !Map_Move2YNeg-!DP_Map
    BRA .acc2y_rem
.acc2y_neg:
    EOR.b #!Eng_Invert8
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move2YNeg-!DP_Map
    STZ.b !Map_Move2YPos-!DP_Map
.acc2y_rem:
    LDA.b !Map_Acc2Y-!DP_Map
    AND.b #!Map_SubMask
    BEQ .acc2y_store
    LDA.b !Map_Acc2Y-!DP_Map
    BPL .acc2y_pos
    ORA.b #!Map_SubSignExt
    BRA .acc2y_store
.acc2y_pos:
    AND.b #!Map_SubMask
.acc2y_store:
    STA.b !Map_Acc2Y-!DP_Map
    LDA.b !Map_Acc3X-!DP_Map
    BMI .acc3x_neg
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move3XPos-!DP_Map
    STZ.b !Map_Move3XNeg-!DP_Map
    BRA .acc3x_rem
.acc3x_neg:
    EOR.b #!Eng_Invert8
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move3XNeg-!DP_Map
    STZ.b !Map_Move3XPos-!DP_Map
.acc3x_rem:
    LDA.b !Map_Acc3X-!DP_Map
    AND.b #!Map_SubMask
    BEQ .acc3x_store
    LDA.b !Map_Acc3X-!DP_Map
    BPL .acc3x_pos
    ORA.b #!Map_SubSignExt
    BRA .acc3x_store
.acc3x_pos:
    AND.b #!Map_SubMask
.acc3x_store:
    STA.b !Map_Acc3X-!DP_Map
    LDA.b !Map_Acc3Y-!DP_Map
    BMI .acc3y_neg
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move3YPos-!DP_Map
    STZ.b !Map_Move3YNeg-!DP_Map
    BRA .acc3y_rem
.acc3y_neg:
    EOR.b #!Eng_Invert8
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_Move3YNeg-!DP_Map
    STZ.b !Map_Move3YPos-!DP_Map
.acc3y_rem:
    LDA.b !Map_Acc3Y-!DP_Map
    AND.b #!Map_SubMask
    BEQ .acc3y_store
    LDA.b !Map_Acc3Y-!DP_Map
    BPL .acc3y_pos
    ORA.b #!Map_SubSignExt
    BRA .acc3y_store
.acc3y_pos:
    AND.b #!Map_SubMask
.acc3y_store:
    STA.b !Map_Acc3Y-!DP_Map
    LDA.b !Map_DriftTimer-!DP_Map
    BEQ .done
    DEC.b !Map_DriftTimer-!DP_Map
    BNE .done
    STZ.b !Map_Drift1X-!DP_Map
    STZ.b !Map_Drift1Y-!DP_Map
    STZ.b !Map_Drift2X-!DP_Map
    STZ.b !Map_Drift2Y-!DP_Map
    STZ.b !Map_Drift3X-!DP_Map
    STZ.b !Map_Drift3Y-!DP_Map
.done:
    RTS

; ------------------------------------------------------------
; $C0:93E1 — Map_Unk93E1 (106 bytes, $93E1–$944A)
; Applies the pixels Map_Unk91AC split out this frame to the three sets
; of scroll words, then has the new tilemap edges built:
; - zeroes Map_EdgeRowYInc/YDec and Map_EdgeColXInc/XDec;
; - layer 1: Map_Scroll1XInc, XDec, YDec, YInc;
; - layer 2: Map_Scroll2XInc, XDec, YDec, YInc, or their *Half
;   versions (moving at half rate) when Map_Unk0BC9 bit 7 is set;
; - layer 3: Map_Scroll3XInc, XDec, YDec, YInc;
; - zeroes Map_BuiltRowYInc/YDec and Map_BuiltColXInc/XDec, then runs
;   Map_EdgeRowsYDec, YInc, Map_EdgeColsXDec, XInc (the *Half versions
;   with Map_Unk0BC9 bit 7, which use other builders for layer 2), and
;   ends in a BRL to
;   Sub_C07F9A (not matched; also called by Field_Unk74D4).
; Callers: Field_FrameUpdate ($C0:8855), Field_Unk885A ($C0:88BC,
;   $C0:88E0).
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll words are stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map), DB=$00 (Map_Unk0BC9 is read
;   absolute).
; Exit: as Sub_C07F9A leaves it (not established); A and X clobbered
;   here, Map_StepCount overwritten, plus what the edge builders change.
; ------------------------------------------------------------
Map_Unk93E1:
    STZ.b !Map_EdgeColXInc-!DP_Map
    STZ.b !Map_EdgeColXDec-!DP_Map
    STZ.b !Map_EdgeRowYInc-!DP_Map
    STZ.b !Map_EdgeRowYDec-!DP_Map
    JSR Map_Scroll1XInc
    JSR Map_Scroll1XDec
    JSR Map_Scroll1YDec
    JSR Map_Scroll1YInc
    LDA.w !Map_Unk0BC9
    BMI .layer2_half
    JSR Map_Scroll2XInc
    JSR Map_Scroll2XDec
    JSR Map_Scroll2YDec
    JSR Map_Scroll2YInc
    BRA .layer3
.layer2_half:
    JSR Map_Scroll2XIncHalf
    JSR Map_Scroll2XDecHalf
    JSR Map_Scroll2YDecHalf
    JSR Map_Scroll2YIncHalf
.layer3:
    JSR Map_Scroll3XInc
    JSR Map_Scroll3XDec
    JSR Map_Scroll3YDec
    JSR Map_Scroll3YInc
    STZ.b !Map_BuiltRowYInc-!DP_Map
    STZ.b !Map_BuiltRowYDec-!DP_Map
    STZ.b !Map_BuiltColXInc-!DP_Map
    STZ.b !Map_BuiltColXDec-!DP_Map
    LDA.w !Map_Unk0BC9
    BMI .edges_half
    JSR Map_EdgeRowsYDec
    JSR Map_EdgeRowsYInc
    JSR Map_EdgeColsXDec
    JSR Map_EdgeColsXInc
    BRL Sub_C07F9A
.edges_half:
    JSR Map_EdgeRowsYDecHalf
    JSR Map_EdgeRowsYIncHalf
    JSR Map_EdgeColsXDecHalf
    JSR Map_EdgeColsXIncHalf
    BRL Sub_C07F9A

; ------------------------------------------------------------
; $C0:944B — Map_Scroll1XInc (50 bytes, $944B–$947C)
; Layer 1, X rising: once per pixel in Map_Move1XPos, Map_Unk1D87 + 1
; and the fine counter Map_Unk1D93 + 1 (0-$0F, wrapping). When the
; counter goes from $07 to $08 or from $0F to 0 (every 8 pixels), the
; low bytes of Map_TileOriginX and Map_Unk1D0C go up by 1 and
; Map_EdgeColXInc is set to Map_Layer1 (a STA, not a TSB: this is the
; first writer after Map_Unk93E1 zeroes it).
; Callers: Map_Unk93E1 ($C0:93E9), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll1XInc:
    LDA.b !Map_Move1XPos-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D87-!DP_Map
    INX
    STX.b !Map_Unk1D87-!DP_Map
    LDA.b !Map_Unk1D93-!DP_Map
    CMP.b #!Map_FineLast
    BNE .not_last
    INC.b !Map_TileOriginX-!DP_Map
    INC.b !Map_Unk1D0C-!DP_Map
    LDA.b #!Map_Layer1
    STA.b !Map_EdgeColXInc-!DP_Map
    LDA.b #!Map_FineWrapDown   ; INC A below gives 0
.not_last:
    CMP.b #!Map_FineMid
    BNE .step
    INC.b !Map_TileOriginX-!DP_Map
    INC.b !Map_Unk1D0C-!DP_Map
    LDA.b #!Map_Layer1
    STA.b !Map_EdgeColXInc-!DP_Map
    LDA.b #!Map_FineMid
.step:
    INC A
    STA.b !Map_Unk1D93-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:947D — Map_Scroll1XDec (48 bytes, $947D–$94AC)
; Layer 1, X falling: as Map_Scroll1XInc with Map_Move1XNeg, stepping
; Map_Unk1D87 and Map_Unk1D93 down; the crossings are 0 to $0F and $08
; to $07, and lower the low bytes of Map_Unk1D0C and Map_TileOriginX
; (in that order) and store Map_Layer1 in Map_EdgeColXDec.
; Callers: Map_Unk93E1 ($C0:93EC), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll1XDec:
    LDA.b !Map_Move1XNeg-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D87-!DP_Map
    DEX
    STX.b !Map_Unk1D87-!DP_Map
    LDA.b !Map_Unk1D93-!DP_Map
    BNE .not_zero
    DEC.b !Map_Unk1D0C-!DP_Map
    DEC.b !Map_TileOriginX-!DP_Map
    LDA.b #!Map_Layer1
    STA.b !Map_EdgeColXDec-!DP_Map
    LDA.b #!Map_FineWrapUp     ; DEC A below gives $0F
.not_zero:
    CMP.b #!Map_FineMidUp
    BNE .step
    DEC.b !Map_Unk1D0C-!DP_Map
    DEC.b !Map_TileOriginX-!DP_Map
    LDA.b #!Map_Layer1
    STA.b !Map_EdgeColXDec-!DP_Map
    LDA.b #!Map_FineMidUp
.step:
    DEC A
    STA.b !Map_Unk1D93-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:94AD — Map_Scroll1YInc (50 bytes, $94AD–$94DE)
; Layer 1, Y rising: as Map_Scroll1XInc with Map_Move1YPos, Map_Unk1D89
; and the fine counter Map_Unk1D96; the crossings raise the low bytes
; of Map_TileOriginY and Map_Unk1D10 and store Map_Layer1 in
; Map_EdgeRowYInc.
; Callers: Map_Unk93E1 ($C0:93F2), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll1YInc:
    LDA.b !Map_Move1YPos-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D89-!DP_Map
    INX
    STX.b !Map_Unk1D89-!DP_Map
    LDA.b !Map_Unk1D96-!DP_Map
    CMP.b #!Map_FineLast
    BNE .not_last
    INC.b !Map_TileOriginY-!DP_Map
    INC.b !Map_Unk1D10-!DP_Map
    LDA.b #!Map_Layer1
    STA.b !Map_EdgeRowYInc-!DP_Map
    LDA.b #!Map_FineWrapDown   ; INC A below gives 0
.not_last:
    CMP.b #!Map_FineMid
    BNE .step
    INC.b !Map_TileOriginY-!DP_Map
    INC.b !Map_Unk1D10-!DP_Map
    LDA.b #!Map_Layer1
    STA.b !Map_EdgeRowYInc-!DP_Map
    LDA.b #!Map_FineMid
.step:
    INC A
    STA.b !Map_Unk1D96-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:94DF — Map_Scroll1YDec (48 bytes, $94DF–$950E)
; Layer 1, Y falling: as Map_Scroll1XDec with Map_Move1YNeg,
; Map_Unk1D89 and Map_Unk1D96; the crossings lower the low bytes of
; Map_TileOriginY and Map_Unk1D10 (in this order, unlike the X version)
; and store Map_Layer1 in Map_EdgeRowYDec.
; Callers: Map_Unk93E1 ($C0:93EF), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll1YDec:
    LDA.b !Map_Move1YNeg-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D89-!DP_Map
    DEX
    STX.b !Map_Unk1D89-!DP_Map
    LDA.b !Map_Unk1D96-!DP_Map
    BNE .not_zero
    DEC.b !Map_TileOriginY-!DP_Map
    DEC.b !Map_Unk1D10-!DP_Map
    LDA.b #!Map_Layer1
    STA.b !Map_EdgeRowYDec-!DP_Map
    LDA.b #!Map_FineWrapUp     ; DEC A below gives $0F
.not_zero:
    CMP.b #!Map_FineMidUp
    BNE .step
    DEC.b !Map_TileOriginY-!DP_Map
    DEC.b !Map_Unk1D10-!DP_Map
    LDA.b #!Map_Layer1
    STA.b !Map_EdgeRowYDec-!DP_Map
    LDA.b #!Map_FineMidUp
.step:
    DEC A
    STA.b !Map_Unk1D96-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:950F — Map_Scroll2XInc (54 bytes, $950F–$9544)
; Layer 2, X rising: once per pixel in Map_Move2XPos, Map_Unk1D8B + 1
; and the fine counter Map_Unk1D94 + 1 (0-$0F, wrapping). At the
; crossings ($07 to $08, $0F to 0) it sets Map_Layer2 in
; Map_EdgeColXInc unless Map_LayerEdgeOff has that bit. Unlike layer 1
; there is no tile origin to move.
; Callers: Map_Unk93E1 ($C0:93FA), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll2XInc:
    LDA.b !Map_Move2XPos-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D8B-!DP_Map
    INX
    STX.b !Map_Unk1D8B-!DP_Map
    LDA.b !Map_Unk1D94-!DP_Map
    CMP.b #!Map_FineLast
    BNE .not_last
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .wrap_off
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeColXInc-!DP_Map
.wrap_off:
    LDA.b #!Map_FineWrapDown   ; INC A below gives 0
.not_last:
    CMP.b #!Map_FineMid
    BNE .step
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .mid_off
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeColXInc-!DP_Map
.mid_off:
    LDA.b #!Map_FineMid
.step:
    INC A
    STA.b !Map_Unk1D94-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:9545 — Map_Scroll2XDec (52 bytes, $9545–$9578)
; Layer 2, X falling: as Map_Scroll2XInc with Map_Move2XNeg, stepping
; down (crossings 0 to $0F and $08 to $07; Map_EdgeColXDec).
; Callers: Map_Unk93E1 ($C0:93FD), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll2XDec:
    LDA.b !Map_Move2XNeg-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D8B-!DP_Map
    DEX
    STX.b !Map_Unk1D8B-!DP_Map
    LDA.b !Map_Unk1D94-!DP_Map
    BNE .not_zero
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .wrap_off
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeColXDec-!DP_Map
.wrap_off:
    LDA.b #!Map_FineWrapUp     ; DEC A below gives $0F
.not_zero:
    CMP.b #!Map_FineMidUp
    BNE .step
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .mid_off
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeColXDec-!DP_Map
.mid_off:
    LDA.b #!Map_FineMidUp
.step:
    DEC A
    STA.b !Map_Unk1D94-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:9579 — Map_Scroll2YInc (54 bytes, $9579–$95AE)
; Layer 2, Y rising: as Map_Scroll2XInc with Map_Move2YPos, Map_Unk1D8D
; and Map_Unk1D97 (Map_EdgeRowYInc).
; Callers: Map_Unk93E1 ($C0:9403), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll2YInc:
    LDA.b !Map_Move2YPos-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D8D-!DP_Map
    INX
    STX.b !Map_Unk1D8D-!DP_Map
    LDA.b !Map_Unk1D97-!DP_Map
    CMP.b #!Map_FineLast
    BNE .not_last
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .wrap_off
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeRowYInc-!DP_Map
.wrap_off:
    LDA.b #!Map_FineWrapDown   ; INC A below gives 0
.not_last:
    CMP.b #!Map_FineMid
    BNE .step
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .mid_off
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeRowYInc-!DP_Map
.mid_off:
    LDA.b #!Map_FineMid
.step:
    INC A
    STA.b !Map_Unk1D97-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:95AF — Map_Scroll2YDec (52 bytes, $95AF–$95E2)
; Layer 2, Y falling: as Map_Scroll2XDec with Map_Move2YNeg,
; Map_Unk1D8D and Map_Unk1D97 (Map_EdgeRowYDec).
; Callers: Map_Unk93E1 ($C0:9400), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll2YDec:
    LDA.b !Map_Move2YNeg-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D8D-!DP_Map
    DEX
    STX.b !Map_Unk1D8D-!DP_Map
    LDA.b !Map_Unk1D97-!DP_Map
    BNE .not_zero
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .wrap_off
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeRowYDec-!DP_Map
.wrap_off:
    LDA.b #!Map_FineWrapUp     ; DEC A below gives $0F
.not_zero:
    CMP.b #!Map_FineMidUp
    BNE .step
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .mid_off
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeRowYDec-!DP_Map
.mid_off:
    LDA.b #!Map_FineMidUp
.step:
    DEC A
    STA.b !Map_Unk1D97-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:95E3 — Map_Scroll2XIncHalf (54 bytes, $95E3–$9618)
; Layer 2 at half rate, X rising (Map_Unk0BC9 bit 7): once per step in
; Map_Move2XPos the fine counter Map_Unk1D94 + 1, here 0-$1F
; (wrapping), and Map_Unk1D8B + 1 only when the new count is even, so
; the scroll word moves half as far. When the counter goes from $0F to
; $10 or from $1F to 0 (every 8 pixels of Map_Unk1D8B), Map_Unk1D12
; and Map_Unk1D14 go up by 1 and Map_Layer2 is set in Map_EdgeColXInc;
; Map_LayerEdgeOff is not checked here.
; Callers: Map_Unk93E1 ($C0:9408), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll2XIncHalf:
    LDA.b !Map_Move2XPos-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDA.b !Map_Unk1D94-!DP_Map
    CMP.b #!Map_FineLastHalf
    BNE .not_last
    INC.b !Map_Unk1D12-!DP_Map
    INC.b !Map_Unk1D14-!DP_Map
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeColXInc-!DP_Map
    LDA.b #!Map_FineWrapDown   ; INC A below gives 0
.not_last:
    CMP.b #!Map_FineLast
    BNE .step
    INC.b !Map_Unk1D12-!DP_Map
    INC.b !Map_Unk1D14-!DP_Map
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeColXInc-!DP_Map
    LDA.b #!Map_FineLast
.step:
    INC A
    STA.b !Map_Unk1D94-!DP_Map
    AND.b #$01
    BNE .odd
    LDX.b !Map_Unk1D8B-!DP_Map
    INX
    STX.b !Map_Unk1D8B-!DP_Map
.odd:
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:9619 — Map_Scroll2XDecHalf (52 bytes, $9619–$964C)
; Layer 2 at half rate, X falling: as Map_Scroll2XIncHalf with
; Map_Move2XNeg, counting down (crossings 0 to $1F and $10 to $0F,
; which lower Map_Unk1D14 and Map_Unk1D12 and set Map_Layer2 in
; Map_EdgeColXDec); Map_Unk1D8B - 1 when the new count is even.
; Callers: Map_Unk93E1 ($C0:940B), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll2XDecHalf:
    LDA.b !Map_Move2XNeg-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDA.b !Map_Unk1D94-!DP_Map
    BNE .not_zero
    DEC.b !Map_Unk1D14-!DP_Map
    DEC.b !Map_Unk1D12-!DP_Map
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeColXDec-!DP_Map
    LDA.b #!Map_FineWrapUpHalf ; DEC A below gives $1F
.not_zero:
    CMP.b #!Map_FineWrapUp
    BNE .step
    DEC.b !Map_Unk1D14-!DP_Map
    DEC.b !Map_Unk1D12-!DP_Map
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeColXDec-!DP_Map
    LDA.b #!Map_FineWrapUp
.step:
    DEC A
    STA.b !Map_Unk1D94-!DP_Map
    AND.b #$01
    BNE .odd
    LDX.b !Map_Unk1D8B-!DP_Map
    DEX
    STX.b !Map_Unk1D8B-!DP_Map
.odd:
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:964D — Map_Scroll2YIncHalf (54 bytes, $964D–$9682)
; Layer 2 at half rate, Y rising: as Map_Scroll2XIncHalf with
; Map_Move2YPos, Map_Unk1D97 and Map_Unk1D8D; the crossings raise
; Map_Unk1D16 and Map_Unk1D18 (Map_EdgeRowYInc).
; Callers: Map_Unk93E1 ($C0:9411), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll2YIncHalf:
    LDA.b !Map_Move2YPos-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDA.b !Map_Unk1D97-!DP_Map
    CMP.b #!Map_FineLastHalf
    BNE .not_last
    INC.b !Map_Unk1D16-!DP_Map
    INC.b !Map_Unk1D18-!DP_Map
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeRowYInc-!DP_Map
    LDA.b #!Map_FineWrapDown   ; INC A below gives 0
.not_last:
    CMP.b #!Map_FineLast
    BNE .step
    INC.b !Map_Unk1D16-!DP_Map
    INC.b !Map_Unk1D18-!DP_Map
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeRowYInc-!DP_Map
    LDA.b #!Map_FineLast
.step:
    INC A
    STA.b !Map_Unk1D97-!DP_Map
    AND.b #$01
    BNE .odd
    LDX.b !Map_Unk1D8D-!DP_Map
    INX
    STX.b !Map_Unk1D8D-!DP_Map
.odd:
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:9683 — Map_Scroll2YDecHalf (52 bytes, $9683–$96B6)
; Layer 2 at half rate, Y falling: as Map_Scroll2XDecHalf with
; Map_Move2YNeg, Map_Unk1D97 and Map_Unk1D8D; the crossings lower
; Map_Unk1D16 and Map_Unk1D18 (Map_EdgeRowYDec).
; Callers: Map_Unk93E1 ($C0:940E), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll2YDecHalf:
    LDA.b !Map_Move2YNeg-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDA.b !Map_Unk1D97-!DP_Map
    BNE .not_zero
    DEC.b !Map_Unk1D16-!DP_Map
    DEC.b !Map_Unk1D18-!DP_Map
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeRowYDec-!DP_Map
    LDA.b #!Map_FineWrapUpHalf ; DEC A below gives $1F
.not_zero:
    CMP.b #!Map_FineWrapUp
    BNE .step
    DEC.b !Map_Unk1D16-!DP_Map
    DEC.b !Map_Unk1D18-!DP_Map
    LDA.b #!Map_Layer2
    TSB.b !Map_EdgeRowYDec-!DP_Map
    LDA.b #!Map_FineWrapUp
.step:
    DEC A
    STA.b !Map_Unk1D97-!DP_Map
    AND.b #$01
    BNE .odd
    LDX.b !Map_Unk1D8D-!DP_Map
    DEX
    STX.b !Map_Unk1D8D-!DP_Map
.odd:
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:96B7 — Map_Scroll3XInc (54 bytes, $96B7–$96EC)
; Layer 3, X rising: as Map_Scroll2XInc with Map_Move3XPos,
; Map_Unk1D8F, Map_Unk1D95 and the Map_Layer3 bit.
; Callers: Map_Unk93E1 ($C0:9414), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll3XInc:
    LDA.b !Map_Move3XPos-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D8F-!DP_Map
    INX
    STX.b !Map_Unk1D8F-!DP_Map
    LDA.b !Map_Unk1D95-!DP_Map
    CMP.b #!Map_FineLast
    BNE .not_last
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .wrap_off
    LDA.b #!Map_Layer3
    TSB.b !Map_EdgeColXInc-!DP_Map
.wrap_off:
    LDA.b #!Map_FineWrapDown   ; INC A below gives 0
.not_last:
    CMP.b #!Map_FineMid
    BNE .step
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .mid_off
    LDA.b #!Map_Layer3
    TSB.b !Map_EdgeColXInc-!DP_Map
.mid_off:
    LDA.b #!Map_FineMid
.step:
    INC A
    STA.b !Map_Unk1D95-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:96ED — Map_Scroll3XDec (52 bytes, $96ED–$9720)
; Layer 3, X falling: as Map_Scroll2XDec with Map_Move3XNeg,
; Map_Unk1D8F, Map_Unk1D95 and the Map_Layer3 bit.
; Callers: Map_Unk93E1 ($C0:9417), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll3XDec:
    LDA.b !Map_Move3XNeg-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    LDX.b !Map_Unk1D8F-!DP_Map
    DEX
    STX.b !Map_Unk1D8F-!DP_Map
    LDA.b !Map_Unk1D95-!DP_Map
    BNE .not_zero
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .wrap_off
    LDA.b #!Map_Layer3
    TSB.b !Map_EdgeColXDec-!DP_Map
.wrap_off:
    LDA.b #!Map_FineWrapUp     ; DEC A below gives $0F
.not_zero:
    CMP.b #!Map_FineMidUp
    BNE .step
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .mid_off
    LDA.b #!Map_Layer3
    TSB.b !Map_EdgeColXDec-!DP_Map
.mid_off:
    LDA.b #!Map_FineMidUp
.step:
    DEC A
    STA.b !Map_Unk1D95-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:9721 — Map_Scroll3YInc (62 bytes, $9721–$975E)
; Layer 3, Y rising: as Map_Scroll2YInc with Map_Move3YPos,
; Map_Unk1D91, Map_Unk1D98 and the Map_Layer3 bit; also adds 4 to
; Map_Unk1DFB per pixel (four INCs; what reads it is not traced).
; Callers: Map_Unk93E1 ($C0:941D), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll3YInc:
    LDA.b !Map_Move3YPos-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    INC.b !Map_Unk1DFB-!DP_Map
    INC.b !Map_Unk1DFB-!DP_Map
    INC.b !Map_Unk1DFB-!DP_Map
    INC.b !Map_Unk1DFB-!DP_Map
    LDX.b !Map_Unk1D91-!DP_Map
    INX
    STX.b !Map_Unk1D91-!DP_Map
    LDA.b !Map_Unk1D98-!DP_Map
    CMP.b #!Map_FineLast
    BNE .not_last
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .wrap_off
    LDA.b #!Map_Layer3
    TSB.b !Map_EdgeRowYInc-!DP_Map
.wrap_off:
    LDA.b #!Map_FineWrapDown   ; INC A below gives 0
.not_last:
    CMP.b #!Map_FineMid
    BNE .step
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .mid_off
    LDA.b #!Map_Layer3
    TSB.b !Map_EdgeRowYInc-!DP_Map
.mid_off:
    LDA.b #!Map_FineMid
.step:
    INC A
    STA.b !Map_Unk1D98-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:975F — Map_Scroll3YDec (60 bytes, $975F–$979A)
; Layer 3, Y falling: as Map_Scroll2YDec with Map_Move3YNeg,
; Map_Unk1D91, Map_Unk1D98 and the Map_Layer3 bit; also subtracts 4
; from Map_Unk1DFB per pixel.
; Callers: Map_Unk93E1 ($C0:941A), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: the scroll word is stepped
;   with LDX/INX/STX), DP=$1D00 (!DP_Map). DB is not used.
; Exit: M=1, X=0, DP unchanged; A clobbered, X too when the scroll
;   word was stepped; Map_StepCount is 0 when there was a step.
; ------------------------------------------------------------
Map_Scroll3YDec:
    LDA.b !Map_Move3YNeg-!DP_Map
    BNE .start
    RTS
.start:
    STA.b !Map_StepCount-!DP_Map
.loop:
    DEC.b !Map_Unk1DFB-!DP_Map
    DEC.b !Map_Unk1DFB-!DP_Map
    DEC.b !Map_Unk1DFB-!DP_Map
    DEC.b !Map_Unk1DFB-!DP_Map
    LDX.b !Map_Unk1D91-!DP_Map
    DEX
    STX.b !Map_Unk1D91-!DP_Map
    LDA.b !Map_Unk1D98-!DP_Map
    BNE .not_zero
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .wrap_off
    LDA.b #!Map_Layer3
    TSB.b !Map_EdgeRowYDec-!DP_Map
.wrap_off:
    LDA.b #!Map_FineWrapUp     ; DEC A below gives $0F
.not_zero:
    CMP.b #!Map_FineMidUp
    BNE .step
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .mid_off
    LDA.b #!Map_Layer3
    TSB.b !Map_EdgeRowYDec-!DP_Map
.mid_off:
    LDA.b #!Map_FineMidUp
.step:
    DEC A
    STA.b !Map_Unk1D98-!DP_Map
    DEC.b !Map_StepCount-!DP_Map
    BNE .loop
    RTS

; ------------------------------------------------------------
; $C0:979B — Map_EdgeColsXInc (49 bytes, $979B–$97CB)
; For each layer bit set in Map_EdgeColXInc (1, 2, 3 in that order)
; runs that layer's column builder (Map_BuildColXInc1/2/3)
; and then adds 1 to the layer's column bias (Map_BgColBias,
; Map_BgColBias2, Map_BgColBias3), wrapping at 64.
; Callers: Map_Unk93E1 ($C0:9436), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X) and DB=$00 as the builders
;   need them, DP=$1D00 (!DP_Map).
; Exit: M=1, DP and DB unchanged; A clobbered; Map_Built* bits set,
;   plus what the row / column writers change (not established).
; ------------------------------------------------------------
Map_EdgeColsXInc:
    LDA.b !Map_EdgeColXInc-!DP_Map
    BIT.b #!Map_Layer1
    BEQ .no_layer1
    JSR Map_BuildColXInc1
    LDA.b !Map_BgColBias-!DP_Map
    INC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias-!DP_Map
    LDA.b !Map_EdgeColXInc-!DP_Map
.no_layer1:
    BIT.b #!Map_Layer2
    BEQ .no_layer2
    JSR Map_BuildColXInc2
    LDA.b !Map_BgColBias2-!DP_Map
    INC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias2-!DP_Map
    LDA.b !Map_EdgeColXInc-!DP_Map
.no_layer2:
    BIT.b #!Map_Layer3
    BEQ .no_layer3
    JSR Map_BuildColXInc3
    LDA.b !Map_BgColBias3-!DP_Map
    INC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias3-!DP_Map
.no_layer3:
    RTS

; ------------------------------------------------------------
; $C0:97CC — Map_EdgeColsXIncHalf (49 bytes, $97CC–$97FC)
; As Map_EdgeColsXInc, with Map_BuildColXInc2Half as layer 2's builder
; (used while Map_Unk0BC9 bit 7 is set).
; Callers: Map_Unk93E1 ($C0:9445), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X) and DB=$00 as the builders
;   need them, DP=$1D00 (!DP_Map).
; Exit: M=1, DP and DB unchanged; A clobbered; Map_Built* bits set,
;   plus what the row / column writers change (not established).
; ------------------------------------------------------------
Map_EdgeColsXIncHalf:
    LDA.b !Map_EdgeColXInc-!DP_Map
    BIT.b #!Map_Layer1
    BEQ .no_layer1
    JSR Map_BuildColXInc1
    LDA.b !Map_BgColBias-!DP_Map
    INC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias-!DP_Map
    LDA.b !Map_EdgeColXInc-!DP_Map
.no_layer1:
    BIT.b #!Map_Layer2
    BEQ .no_layer2
    JSR Map_BuildColXInc2Half
    LDA.b !Map_BgColBias2-!DP_Map
    INC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias2-!DP_Map
    LDA.b !Map_EdgeColXInc-!DP_Map
.no_layer2:
    BIT.b #!Map_Layer3
    BEQ .no_layer3
    JSR Map_BuildColXInc3
    LDA.b !Map_BgColBias3-!DP_Map
    INC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias3-!DP_Map
.no_layer3:
    RTS

; ------------------------------------------------------------
; $C0:97FD — Map_EdgeColsXDec (49 bytes, $97FD–$982D)
; As Map_EdgeColsXInc for Map_EdgeColXDec: builders Map_BuildColXDec1/
; 2/3, and the column biases go down by 1 (wrapping at 64).
; Callers: Map_Unk93E1 ($C0:9433), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X) and DB=$00 as the builders
;   need them, DP=$1D00 (!DP_Map).
; Exit: M=1, DP and DB unchanged; A clobbered; Map_Built* bits set,
;   plus what the row / column writers change (not established).
; ------------------------------------------------------------
Map_EdgeColsXDec:
    LDA.b !Map_EdgeColXDec-!DP_Map
    BIT.b #!Map_Layer1
    BEQ .no_layer1
    JSR Map_BuildColXDec1
    LDA.b !Map_BgColBias-!DP_Map
    DEC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias-!DP_Map
    LDA.b !Map_EdgeColXDec-!DP_Map
.no_layer1:
    BIT.b #!Map_Layer2
    BEQ .no_layer2
    JSR Map_BuildColXDec2
    LDA.b !Map_BgColBias2-!DP_Map
    DEC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias2-!DP_Map
    LDA.b !Map_EdgeColXDec-!DP_Map
.no_layer2:
    BIT.b #!Map_Layer3
    BEQ .no_layer3
    JSR Map_BuildColXDec3
    LDA.b !Map_BgColBias3-!DP_Map
    DEC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias3-!DP_Map
.no_layer3:
    RTS

; ------------------------------------------------------------
; $C0:982E — Map_EdgeColsXDecHalf (49 bytes, $982E–$985E)
; As Map_EdgeColsXDec, with Map_BuildColXDec2Half for layer 2.
; Callers: Map_Unk93E1 ($C0:9442), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X) and DB=$00 as the builders
;   need them, DP=$1D00 (!DP_Map).
; Exit: M=1, DP and DB unchanged; A clobbered; Map_Built* bits set,
;   plus what the row / column writers change (not established).
; ------------------------------------------------------------
Map_EdgeColsXDecHalf:
    LDA.b !Map_EdgeColXDec-!DP_Map
    BIT.b #!Map_Layer1
    BEQ .no_layer1
    JSR Map_BuildColXDec1
    LDA.b !Map_BgColBias-!DP_Map
    DEC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias-!DP_Map
    LDA.b !Map_EdgeColXDec-!DP_Map
.no_layer1:
    BIT.b #!Map_Layer2
    BEQ .no_layer2
    JSR Map_BuildColXDec2Half
    LDA.b !Map_BgColBias2-!DP_Map
    DEC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias2-!DP_Map
    LDA.b !Map_EdgeColXDec-!DP_Map
.no_layer2:
    BIT.b #!Map_Layer3
    BEQ .no_layer3
    JSR Map_BuildColXDec3
    LDA.b !Map_BgColBias3-!DP_Map
    DEC A
    AND.b #!Bg_ColMask64
    STA.b !Map_BgColBias3-!DP_Map
.no_layer3:
    RTS

; ------------------------------------------------------------
; $C0:985F — Map_EdgeRowsYInc (49 bytes, $985F–$988F)
; As Map_EdgeColsXInc for rows: for each layer bit in Map_EdgeRowYInc
; runs Map_BuildRowYInc1/2/3 and adds 1 to the layer's
; row bias (Map_BgRowBias, Map_BgRowBias2, Map_BgRowBias3), wrapping
; at 32.
; Callers: Map_Unk93E1 ($C0:9430), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X) and DB=$00 as the builders
;   need them, DP=$1D00 (!DP_Map).
; Exit: M=1, DP and DB unchanged; A clobbered; Map_Built* bits set,
;   plus what the row / column writers change (not established).
; ------------------------------------------------------------
Map_EdgeRowsYInc:
    LDA.b !Map_EdgeRowYInc-!DP_Map
    BIT.b #!Map_Layer1
    BEQ .no_layer1
    JSR Map_BuildRowYInc1
    LDA.b !Map_BgRowBias-!DP_Map
    INC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias-!DP_Map
    LDA.b !Map_EdgeRowYInc-!DP_Map
.no_layer1:
    BIT.b #!Map_Layer2
    BEQ .no_layer2
    JSR Map_BuildRowYInc2
    LDA.b !Map_BgRowBias2-!DP_Map
    INC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias2-!DP_Map
    LDA.b !Map_EdgeRowYInc-!DP_Map
.no_layer2:
    BIT.b #!Map_Layer3
    BEQ .no_layer3
    JSR Map_BuildRowYInc3
    LDA.b !Map_BgRowBias3-!DP_Map
    INC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias3-!DP_Map
.no_layer3:
    RTS

; ------------------------------------------------------------
; $C0:9890 — Map_EdgeRowsYIncHalf (49 bytes, $9890–$98C0)
; As Map_EdgeRowsYInc, with Map_BuildRowYInc2Half for layer 2.
; Callers: Map_Unk93E1 ($C0:943F), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X) and DB=$00 as the builders
;   need them, DP=$1D00 (!DP_Map).
; Exit: M=1, DP and DB unchanged; A clobbered; Map_Built* bits set,
;   plus what the row / column writers change (not established).
; ------------------------------------------------------------
Map_EdgeRowsYIncHalf:
    LDA.b !Map_EdgeRowYInc-!DP_Map
    BIT.b #!Map_Layer1
    BEQ .no_layer1
    JSR Map_BuildRowYInc1
    LDA.b !Map_BgRowBias-!DP_Map
    INC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias-!DP_Map
    LDA.b !Map_EdgeRowYInc-!DP_Map
.no_layer1:
    BIT.b #!Map_Layer2
    BEQ .no_layer2
    JSR Map_BuildRowYInc2Half
    LDA.b !Map_BgRowBias2-!DP_Map
    INC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias2-!DP_Map
    LDA.b !Map_EdgeRowYInc-!DP_Map
.no_layer2:
    BIT.b #!Map_Layer3
    BEQ .no_layer3
    JSR Map_BuildRowYInc3
    LDA.b !Map_BgRowBias3-!DP_Map
    INC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias3-!DP_Map
.no_layer3:
    RTS

; ------------------------------------------------------------
; $C0:98C1 — Map_EdgeRowsYDec (49 bytes, $98C1–$98F1)
; As Map_EdgeRowsYInc for Map_EdgeRowYDec: builders Map_BuildRowYDec1/
; 2/3, and the row biases go down by 1 (wrapping at 32).
; Callers: Map_Unk93E1 ($C0:942D), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X) and DB=$00 as the builders
;   need them, DP=$1D00 (!DP_Map).
; Exit: M=1, DP and DB unchanged; A clobbered; Map_Built* bits set,
;   plus what the row / column writers change (not established).
; ------------------------------------------------------------
Map_EdgeRowsYDec:
    LDA.b !Map_EdgeRowYDec-!DP_Map
    BIT.b #!Map_Layer1
    BEQ .no_layer1
    JSR Map_BuildRowYDec1
    LDA.b !Map_BgRowBias-!DP_Map
    DEC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias-!DP_Map
    LDA.b !Map_EdgeRowYDec-!DP_Map
.no_layer1:
    BIT.b #!Map_Layer2
    BEQ .no_layer2
    JSR Map_BuildRowYDec2
    LDA.b !Map_BgRowBias2-!DP_Map
    DEC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias2-!DP_Map
    LDA.b !Map_EdgeRowYDec-!DP_Map
.no_layer2:
    BIT.b #!Map_Layer3
    BEQ .no_layer3
    JSR Map_BuildRowYDec3
    LDA.b !Map_BgRowBias3-!DP_Map
    DEC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias3-!DP_Map
.no_layer3:
    RTS

; ------------------------------------------------------------
; $C0:98F2 — Map_EdgeRowsYDecHalf (49 bytes, $98F2–$9922)
; As Map_EdgeRowsYDec, with Map_BuildRowYDec2Half for layer 2.
; Callers: Map_Unk93E1 ($C0:943C), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X) and DB=$00 as the builders
;   need them, DP=$1D00 (!DP_Map).
; Exit: M=1, DP and DB unchanged; A clobbered; Map_Built* bits set,
;   plus what the row / column writers change (not established).
; ------------------------------------------------------------
Map_EdgeRowsYDecHalf:
    LDA.b !Map_EdgeRowYDec-!DP_Map
    BIT.b #!Map_Layer1
    BEQ .no_layer1
    JSR Map_BuildRowYDec1
    LDA.b !Map_BgRowBias-!DP_Map
    DEC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias-!DP_Map
    LDA.b !Map_EdgeRowYDec-!DP_Map
.no_layer1:
    BIT.b #!Map_Layer2
    BEQ .no_layer2
    JSR Map_BuildRowYDec2Half
    LDA.b !Map_BgRowBias2-!DP_Map
    DEC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias2-!DP_Map
    LDA.b !Map_EdgeRowYDec-!DP_Map
.no_layer2:
    BIT.b #!Map_Layer3
    BEQ .no_layer3
    JSR Map_BuildRowYDec3
    LDA.b !Map_BgRowBias3-!DP_Map
    DEC A
    AND.b #!Bg_RowMask32
    STA.b !Map_BgRowBias3-!DP_Map
.no_layer3:
    RTS

; ------------------------------------------------------------
; $C0:9923 — Map_ProbeHitsObj (187 bytes, $9923–$99DD)
; Map_Unk8A6D's object test of the point Map_ProbeX/Y. Walks the object
; slots from Evt_ObjCount x 2 down to 2 (slot 0 is never tested), as
; Field_FindObjInFront does, skipping a slot whose Obj_Unk0F00 is 0,
; whose Obj_Unk1100 has bit 7 set, or that holds one of the three party
; members. The first one (highest slot) whose Obj_PosX and Obj_PosY are
; both less than Map_ObjNear ($E0) from the probe is touched: its slot
; goes to Field_UnkEB, and C=1 when its Obj_Unk1B01 bit 0 is set (it
; blocks), C=0 when not. No object touched: Field_UnkEB = $80
; (Field_UnkEBInit), C=0.
; Quirks (kept): the
; Y difference is taken with SBC and no SEC (the carry left by the CPX
; before it), and the X difference with the carry the CMP left (clear),
; so both can come out 1 smaller. The 16-bit store at the start also
; zeroes $01EC.
; Callers (8 JSR sites in Map_Unk8A6D): $C0:8AD8, $C0:8BEA, $C0:8C1B,
;   $C0:8D2D, $C0:8E49, $C0:8F1A, $C0:8FE6 and $C0:90BF.
; On entry: M=1 (8-bit A), X=1 or X=0 (set to 8-bit inside), DP=$1D00
; (!DP_Map), DB=$00 (Field_UnkEB and the object tables are reached
; absolute).
; Exit: M=1, X=0 (16-bit), DP and DB unchanged; C as above; X = the
; touched slot, or 0; A clobbered.
; ------------------------------------------------------------
org $C09923
Map_ProbeHitsObj:
    REP #$20
    LDA.w #!Field_UnkEBInit
    STA.w !DP_Field+!Field_UnkEB    ; 16-bit: $01EC = 0 as well
    SEP #$30
    LDA.l !Evt_ObjCount
    ASL A
    TAX                             ; last slot (count x 2), 8-bit X
.next_slot:
    LDA.w !Obj_Unk0F00,X
    BNE .candidate
.skip:
    DEX
    DEX
    BNE .next_slot
    LDA.b #!Field_UnkEBInit
    STA.w !DP_Field+!Field_UnkEB    ; nothing touched
    REP #$10
    CLC
    RTS
.candidate:
    LDA.w !Obj_Unk1100,X
    BMI .skip
    CPX.w !DP_Field+!Party_ObjSlot
    BEQ .skip
    CPX.w !DP_Field+!Party_ObjSlot1
    BEQ .skip
    CPX.w !DP_Field+!Party_ObjSlot2
    BEQ .skip
    LDA.w !Obj_Unk1B01,X
    BIT.b #!Obj_Unk1B01Solid
    BEQ .soft
    STX.w !DP_Field+!Field_UnkEB
    REP #$20
    LDA.w !Obj_PosY,X
    SBC.b !Map_ProbeY-!DP_Map       ; no SEC (quirk)
    BPL .solid_dy_pos
    EOR.w #!Eng_Invert16
    INC A
    CMP.w #!Map_ObjNear
    BCS .far
.solid_dx:
    LDA.w !Obj_PosX,X
    SBC.b !Map_ProbeX-!DP_Map       ; C=0 from the CMP: 1 extra (quirk)
    BPL .solid_dx_pos
    EOR.w #!Eng_Invert16
    INC A
    CMP.w #!Map_ObjNear
    BCS .far
    SEP #$20
    REP #$10
    SEC                             ; touched and blocking
    RTS
.solid_dy_pos:
    CMP.w #!Map_ObjNear
    BCS .far
    BRA .solid_dx
.solid_dx_pos:
    CMP.w #!Map_ObjNear
    BCS .far
    SEP #$20
    REP #$10
    SEC
    RTS
.far:
    SEP #$20
    BRA .skip
.soft:
    STX.w !DP_Field+!Field_UnkEB
    REP #$20
    LDA.w !Obj_PosY,X
    SBC.b !Map_ProbeY-!DP_Map       ; no SEC (quirk)
    BPL .soft_dy_pos
    EOR.w #!Eng_Invert16
    INC A
    CMP.w #!Map_ObjNear
    BCS .far
.soft_dx:
    LDA.w !Obj_PosX,X
    SBC.b !Map_ProbeX-!DP_Map
    BPL .soft_dx_pos
    EOR.w #!Eng_Invert16
    INC A
    CMP.w #!Map_ObjNear
    BCS .far
    SEP #$20
    REP #$10
    CLC                             ; touched, not blocking
    RTS
.soft_dy_pos:
    CMP.w #!Map_ObjNear
    BCS .far
    BRA .soft_dx
.soft_dx_pos:
    CMP.w #!Map_ObjNear
    BCS .far
    SEP #$20
    REP #$10
    CLC
    RTS

; ------------------------------------------------------------
; $C0:99DE — Map_Unk99DE (65 bytes, $99DE–$9A1E)
; Field_FrameUpdate's step after Map_Unk9175: may drop the frame's
; steps in Map_Unk1D2E (X) and Map_Unk1D30 (Y). For a nonzero step, n =
; |step| / 16 goes to the Map_StepStop* test for that direction
; (Right/Left, Down/Up); C=1 zeroes the step. By what the tests compare
; (Map_TileOriginX/Y / 2 and Map_Unk1D0C/1D10 / 2 against the limits
; Map_Unk1D1A-1D1D, the leader's Obj_ScreenX/Y against the screen
; middle) this looks like keeping a camera scroll inside the map and
; behind the leader; not established.
; Quirk: after a positive Y step is dropped there is no branch to the
; end, so it falls into the negative path: A (left by the test) is
; negated, shifted and passed to Map_StepStopUp, which may only zero
; Map_Unk1D30 again. The X half has the BRA. Kept from the original.
; Callers: Field_FrameUpdate ($C0:884F), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A and X clobbered; Map_StepTestN
; and Map_StepTestN2 overwritten.
; ------------------------------------------------------------
org $C099DE
Map_Unk99DE:
    LDA.b !Map_Unk1D2E-!DP_Map
    BEQ .y_step
    BMI .left
    LSR A
    LSR A
    LSR A
    LSR A
    JSR Map_StepStopRight
    BCC .y_step
    STZ.b !Map_Unk1D2E-!DP_Map
    BRA .y_step
.left:
    EOR.b #!Eng_Invert8
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    JSR Map_StepStopLeft
    BCC .y_step
    STZ.b !Map_Unk1D2E-!DP_Map
.y_step:
    LDA.b !Map_Unk1D30-!DP_Map
    BEQ .done
    BMI .up
    LSR A
    LSR A
    LSR A
    LSR A
    JSR Map_StepStopDown
    BCC .done
    STZ.b !Map_Unk1D30-!DP_Map ; no BRA: falls into .up (quirk, see above)
.up:
    EOR.b #!Eng_Invert8
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    JSR Map_StepStopUp
    BCC .done
    STZ.b !Map_Unk1D30-!DP_Map
.done:
    RTS

; ------------------------------------------------------------
; $C0:9A1F — Map_StepStopDown (30 bytes, $9A1F–$9A3C)
; Map_Unk99DE's test for a downward step, A = n (step / 16). Compares
; L = Map_Unk1D10 / 2 (low byte) with Map_Unk1D1D:
; - L < Map_Unk1D1D: C=1 when the leader's Obj_ScreenY (low byte) is
;   at or above Screen_SplitY ($88 >= it), i.e. it is not in the lower
;   part of the screen;
; - L = Map_Unk1D1D: C=1 when Map_Unk1D96 + n >= Map_FineLimit;
; - L > Map_Unk1D1D: C=1.
; Callers: Map_Unk99DE ($C0:9A09), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; C=1: drop the step; A
; clobbered; X = the leader's slot on the first path; Map_StepTestN = n.
; ------------------------------------------------------------
Map_StepStopDown:
    STA.b !Map_StepTestN-!DP_Map
    LDA.b !Map_Unk1D10-!DP_Map
    LSR A
    CMP.b !Map_Unk1D1D-!DP_Map
    BCC .by_screen
    BNE .stop
    LDA.b !Map_Unk1D96-!DP_Map
    CLC
    ADC.b !Map_StepTestN-!DP_Map
    CMP.b #!Map_FineLimit
    RTS
.stop:
    SEC
    RTS
.by_screen:
    LDA.b #!Screen_SplitY
    LDX.w !DP_Field+!Party_ObjSlot
    CMP.w !Obj_ScreenY,X
    RTS

; ------------------------------------------------------------
; $C0:9A3D — Map_StepStopUp (35 bytes, $9A3D–$9A5F)
; Map_Unk99DE's test for an upward step, A = n. Compares Map_Unk1D1C
; with T = Map_TileOriginY / 2 (low byte, kept in Map_StepTestN):
; - Map_Unk1D1C < T: C=1 when the leader's Obj_ScreenY (low byte) is
;   at or below Screen_SplitY;
; - Map_Unk1D1C = T: C=1 when Map_Unk1D96 - n is negative;
; - Map_Unk1D1C > T: C=1.
; Callers: Map_Unk99DE ($C0:9A17), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; C=1: drop the step; A
; clobbered; X = the leader's slot on the first path; Map_StepTestN =
; T, Map_StepTestN2 = n.
; ------------------------------------------------------------
Map_StepStopUp:
    STA.b !Map_StepTestN2-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    LSR A
    STA.b !Map_StepTestN-!DP_Map
    LDA.b !Map_Unk1D1C-!DP_Map
    CMP.b !Map_StepTestN-!DP_Map
    BCC .by_screen
    BNE .stop
    LDA.b !Map_Unk1D96-!DP_Map
    SEC
    SBC.b !Map_StepTestN2-!DP_Map
    BPL .keep
.stop:
    SEC
    RTS
.by_screen:
    LDX.w !DP_Field+!Party_ObjSlot
    LDA.w !Obj_ScreenY,X
    CMP.b #!Screen_SplitY
    RTS
.keep:
    CLC
    RTS

; ------------------------------------------------------------
; $C0:9A60 — Map_StepStopRight (30 bytes, $9A60–$9A7D)
; As Map_StepStopDown for a rightward step: L = Map_Unk1D0C / 2
; against Map_Unk1D1B, the leader's Obj_ScreenX against Screen_HalfX
; (C=1 when it is in the left half or at $80), Map_Unk1D93 + n against
; Map_FineLimit.
; Callers: Map_Unk99DE ($C0:99E8), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; C=1: drop the step; A
; clobbered; X = the leader's slot on the first path; Map_StepTestN = n.
; ------------------------------------------------------------
Map_StepStopRight:
    STA.b !Map_StepTestN-!DP_Map
    LDA.b !Map_Unk1D0C-!DP_Map
    LSR A
    CMP.b !Map_Unk1D1B-!DP_Map
    BCC .by_screen
    BNE .stop
    LDA.b !Map_Unk1D93-!DP_Map
    CLC
    ADC.b !Map_StepTestN-!DP_Map
    CMP.b #!Map_FineLimit
    RTS
.stop:
    SEC
    RTS
.by_screen:
    LDA.b #!Screen_HalfX
    LDX.w !DP_Field+!Party_ObjSlot
    CMP.w !Obj_ScreenX,X
    RTS

; ------------------------------------------------------------
; $C0:9A7E — Map_StepStopLeft (35 bytes, $9A7E–$9AA0)
; As Map_StepStopUp for a leftward step: Map_Unk1D1A against T =
; Map_TileOriginX / 2, the leader's Obj_ScreenX against Screen_HalfX
; (C=1 when it is in the right half), Map_Unk1D93 - n.
; Callers: Map_Unk99DE ($C0:99F8), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; C=1: drop the step; A
; clobbered; X = the leader's slot on the first path; Map_StepTestN =
; T, Map_StepTestN2 = n.
; ------------------------------------------------------------
Map_StepStopLeft:
    STA.b !Map_StepTestN2-!DP_Map
    LDA.b !Map_TileOriginX-!DP_Map
    LSR A
    STA.b !Map_StepTestN-!DP_Map
    LDA.b !Map_Unk1D1A-!DP_Map
    CMP.b !Map_StepTestN-!DP_Map
    BCC .by_screen
    BNE .stop
    LDA.b !Map_Unk1D93-!DP_Map
    SEC
    SBC.b !Map_StepTestN2-!DP_Map
    BPL .keep
.stop:
    SEC
    RTS
.by_screen:
    LDX.w !DP_Field+!Party_ObjSlot
    LDA.w !Obj_ScreenX,X
    CMP.b #!Screen_HalfX
    RTS
.keep:
    CLC
    RTS

; ------------------------------------------------------------
; $C0:9AA1 — Map_ProbeTileAttrs (39 bytes, $9AA1–$9AC7)
; Reads the map bytes of one tile for the collision probes. A (16-bit
; value: B = map row, A = column) is masked with Map_ColMask1 /
; Map_RowMask1 (one 16-bit AND) into the index X. A tile that holds
; treasure (Map_TreasureIdx bit 7 clear) blocks: C=1 at once. Otherwise
; (Map_ProbeTileAttrs_Load, also reached from Map_ProbeTileAttrsAny)
; Map_TileHiBits, Map_TileAttrA and Map_TileAttrB of the tile go to
; Map_ProbeHiBits, Map_ProbeAttrA and Map_ProbeAttrB, and C=0.
; Callers: Map_Unk8A6D ($C0:8AA4, in its .test_probe), its only JSR site.
; On entry: M=1 (8-bit A), X either (set to 16-bit inside), DP=$1D00
; (!DP_Map), DB any (long operands); A = row << 8 | column.
; Exit: M=1, DP and DB unchanged. C=1: X=0 (16-bit X holding the tile
; index), nothing read. C=0:
; X=1 (8-bit), X = the index's low byte; A = Map_ProbeAttrB.
; ------------------------------------------------------------
org $C09AA1
Map_ProbeTileAttrs:
    REP #$10
    REP #$20
    AND.b !Map_ColMask1-!DP_Map     ; 16-bit: Map_RowMask1 masks the row
    SEP #$20
    TAX
    LDA.l !Map_TreasureIdx,X
    BMI Map_ProbeTileAttrs_Load
    SEC                             ; a treasure tile blocks
    RTS
Map_ProbeTileAttrs_Load:            ; header: see Map_ProbeTileAttrs
    LDA.l !Map_TileHiBits,X
    STA.b !Map_ProbeHiBits-!DP_Map
    LDA.l !Map_TileAttrA,X
    STA.b !Map_ProbeAttrA-!DP_Map
    LDA.l !Map_TileAttrB,X
    STA.b !Map_ProbeAttrB-!DP_Map
    SEP #$10
    CLC
    RTS

; ------------------------------------------------------------
; $C0:9AC8 — Map_ProbeTileAttrsAny (11 bytes, $9AC8–$9AD2)
; As Map_ProbeTileAttrs without the treasure test: always reads the
; three bytes (branches into Map_ProbeTileAttrs_Load) and returns C=0.
; Callers (2 JSR sites): Map_StepTileEffects ($C0:9C8D) and unmatched
;   code at $C0:9DEA.
; On entry: M=1 (8-bit A), X either, DP=$1D00 (!DP_Map), DB any; A = row
; << 8 | column (16-bit value).
; Exit: M=1, X=1 (8-bit), DP and DB unchanged; X = the index's low byte;
; A = Map_ProbeAttrB; C=0.
; ------------------------------------------------------------
Map_ProbeTileAttrsAny:
    REP #$10
    REP #$20
    AND.b !Map_ColMask1-!DP_Map     ; 16-bit: Map_RowMask1 masks the row
    SEP #$20
    TAX
    BRA Map_ProbeTileAttrs_Load

; ------------------------------------------------------------
; $C0:9AD3 — Map_ProbeTileLevel (290 bytes, $9AD3–$9BF4; tables to $9C36)
; Decides which half of the probed tile the point Map_ProbeX/Y is in and
; loads that half's level. The shape number is Map_ProbeHiBits bits 2-7:
; - 0: half A; 1: half B (the whole tile either way);
; - 2-$17: Map_ProbeShape = shape - 2 indexes three 22-byte tables:
;   t = (Map_ProbeX low byte >> Map_SlopeShift bits 0-6, inverted when
;   bit 7 is set) + Map_SlopeBase - Map_ProbeFracY4 (the Y fraction / 4);
;   half A when t has the sign Map_SlopeSide gives ($00 positive, $FF
;   negative), else half B (inferred: a sloped line through the tile);
; - $18-$1D: half B in one half or quarter of the tile (MapShape_LeftB ...
;   MapShape_TopLeftB, by bit 7 of the X / Y fractions), else half A;
; - $1E: half A; Map_ProbeMoveFlags = Map_ProbeShape1E, and a nonzero
;   Map_Unk1D30 is cut to Map_StepPos / Map_StepNeg (its sign kept);
; - $1F-$3F: half A.
; Half A: Map_ProbeLevel = Map_ProbeAttrB bits 0-1, Map_ProbeNoLevel =
; bit 2. Half B: Map_ProbeLevel = bits 3-4 (shifted down), Map_ProbeNoLevel
; = bit 5. Both: Map_ProbePrio / Map_ProbePrioHi = Oam_Prio2 plus $10
; when bit 6 of Map_ProbeAttrA / Map_ProbeAttrB is set (OAM priority 2
; or 3, for the leader's Obj_PrioLow / Obj_PrioHigh).
; Callers (3 JSR sites): Map_Unk8A6D ($C0:8AAC, in its .test_probe),
;   Map_StepTileEffects ($C0:9C90) and unmatched code at $C0:9DF5.
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y: the table index and shift
; count), DP=$1D00 (!DP_Map), DB any (tables read long); Map_ProbeHiBits,
; Map_ProbeAttrA/B and Map_ProbeX/Y set.
; Exit: M=1, X=1, DP and DB unchanged; A, X, Y clobbered; Map_ProbeMoveFlags,
; Map_ProbeShape, Map_ProbeFracY4, Map_SlopeTest, Map_ProbeLevel,
; Map_ProbeNoLevel and Map_ProbePrio/PrioHi written; Map_Unk1D30 may be
; cut.
; ------------------------------------------------------------
Map_ProbeTileLevel:
    STZ.b !Map_ProbeMoveFlags-!DP_Map
    STZ.b !Map_ProbeShape-!DP_Map
    STZ.b !Map_ProbeLevel-!DP_Map
    STZ.b !Map_ProbeNoLevel-!DP_Map
    STZ.b !Map_ProbePrio-!DP_Map
    LDA.b !Map_ProbeY-!DP_Map
    LSR A
    LSR A
    STA.b !Map_ProbeFracY4-!DP_Map
    LDA.b !Map_ProbeHiBits-!DP_Map
    AND.b #!Map_ShapeMask
    LSR A
    LSR A                           ; shape number
    BEQ .half_a
    DEC A
    BEQ .half_b
    DEC A
    STA.b !Map_ProbeShape-!DP_Map
    CMP.b #!Map_ShapeTables
    BCC .sloped
    BRL .split
.sloped:
    TAX
    LDA.l Map_SlopeShift,X
    BMI .sloped_inverted
    TAY
    LDA.b !Map_ProbeX-!DP_Map
.shift:
    LSR A
    DEY
    BNE .shift
    STA.b !Map_SlopeTest-!DP_Map
    LDA.l Map_SlopeBase,X
    CLC
    ADC.b !Map_SlopeTest-!DP_Map
    SEC
    SBC.b !Map_ProbeFracY4-!DP_Map
    STA.b !Map_SlopeTest-!DP_Map
    LDA.l Map_SlopeSide,X
    EOR.b !Map_SlopeTest-!DP_Map
    BPL .half_a                     ; same sign as Map_SlopeSide
    BRA .half_b
.sloped_inverted:
    AND.b #!Map_SlopeShiftMask
    TAY
    LDA.b !Map_ProbeX-!DP_Map
.shift_inv:
    LSR A
    DEY
    BNE .shift_inv
    EOR.b #!Eng_Invert8
    STA.b !Map_SlopeTest-!DP_Map
    LDA.l Map_SlopeBase,X
    CLC
    ADC.b !Map_SlopeTest-!DP_Map
    SEC
    SBC.b !Map_ProbeFracY4-!DP_Map
    STA.b !Map_SlopeTest-!DP_Map
    LDA.l Map_SlopeSide,X
    EOR.b !Map_SlopeTest-!DP_Map
    BPL .half_a
    BRA .half_b
.half_a:
    LDA.b !Map_ProbeAttrB-!DP_Map
    AND.b #!TileAttrB_LevelA
    STA.b !Map_ProbeLevel-!DP_Map
    LDA.b !Map_ProbeAttrB-!DP_Map
    AND.b #!TileAttrB_NoLevelA
    STA.b !Map_ProbeNoLevel-!DP_Map
    LDA.b !Map_ProbeAttrA-!DP_Map
    LSR A
    LSR A
    AND.b #!TileAttr_PrioBit
    ORA.b #!Oam_Prio2
    STA.b !Map_ProbePrio-!DP_Map
    LDA.b !Map_ProbeAttrB-!DP_Map
    LSR A
    LSR A
    AND.b #!TileAttr_PrioBit
    ORA.b #!Oam_Prio2
    STA.b !Map_ProbePrioHi-!DP_Map
    RTS
.half_b:
    LDA.b !Map_ProbeAttrB-!DP_Map
    AND.b #!TileAttrB_LevelB
    LSR A
    LSR A
    LSR A
    STA.b !Map_ProbeLevel-!DP_Map
    LDA.b !Map_ProbeAttrB-!DP_Map
    AND.b #!TileAttrB_NoLevelB
    STA.b !Map_ProbeNoLevel-!DP_Map
    LDA.b !Map_ProbeAttrA-!DP_Map
    LSR A
    LSR A
    AND.b #!TileAttr_PrioBit
    ORA.b #!Oam_Prio2
    STA.b !Map_ProbePrio-!DP_Map
    LDA.b !Map_ProbeAttrB-!DP_Map
    LSR A
    LSR A
    AND.b #!TileAttr_PrioBit
    ORA.b #!Oam_Prio2
    STA.b !Map_ProbePrioHi-!DP_Map
    RTS
.split:
    BEQ .left_b                     ; Z from the CMP: MapShape_LeftB
    CMP.b #!MapShape_TopB
    BEQ .top_b
    CMP.b #!MapShape_BottomLeftB
    BEQ .bottom_left_b
    CMP.b #!MapShape_BottomRightB
    BEQ .bottom_right_b
    CMP.b #!MapShape_TopRightB
    BEQ .top_right_b
    CMP.b #!MapShape_TopLeftB
    BEQ .top_left_b
    CMP.b #!MapShape_Unk1E
    BEQ .shape_1e
    BRA .half_a
.left_b:
    LDA.b !Map_ProbeX-!DP_Map
    BPL .half_b
    BRL .half_a
.top_b:
    LDA.b !Map_ProbeY-!DP_Map
    BPL .half_b
    BRL .half_a
.top_left_b:
    LDA.b !Map_ProbeX-!DP_Map
    BPL .top_test
    BRL .half_a
.top_test:
    LDA.b !Map_ProbeY-!DP_Map
    BPL .to_half_b
    BRL .half_a
.to_half_b:
    BRL .half_b
.top_right_b:
    LDA.b !Map_ProbeX-!DP_Map
    BMI .top_test
    BRL .half_a
.bottom_left_b:
    LDA.b !Map_ProbeX-!DP_Map
    BPL .bottom_test
    BRL .half_a
.bottom_test:
    LDA.b !Map_ProbeY-!DP_Map
    BMI .to_half_b
    BRL .half_a
.bottom_right_b:
    LDA.b !Map_ProbeX-!DP_Map
    BMI .bottom_test
    BRL .half_a
.shape_1e:
    LDA.b #!Map_ProbeShape1E
    STA.b !Map_ProbeMoveFlags-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    BEQ .shape_1e_done
    BMI .shape_1e_up
    LDA.b #!Map_StepPos
    STA.b !Map_Unk1D30-!DP_Map
    BRL .half_a
.shape_1e_up:
    LDA.b #!Map_StepNeg
    STA.b !Map_Unk1D30-!DP_Map
.shape_1e_done:
    BRL .half_a

; Map_SlopeShift / Map_SlopeBase / Map_SlopeSide: Map_ProbeTileLevel's
; line for shapes 2-$17, indexed by Map_ProbeShape (shape - 2). Shift:
; bits 0-6 how far the X fraction is shifted right (1-3), bit 7 set:
; inverted after the shift. Base: added. Side: the sign that means half A.
Map_SlopeShift:
    db $82,$02,$02,$82,$81,$01,$01,$81,$83,$03,$03,$83
    db $81,$01,$01,$81,$83,$03,$03,$83,$82,$02
Map_SlopeBase:
    db $3D,$03,$03,$3D,$7D,$03,$C3,$3D,$3E,$23,$03,$1D
    db $3D,$C3,$03,$7D,$1E,$03,$23,$3D,$3D,$03
Map_SlopeSide:
    db $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
    db $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00

; ------------------------------------------------------------
; $C0:9C37 — Map_ProbeLevelBlocked (37 bytes, $9C37–$9C5B)
; Whether the half tile Map_ProbeTileLevel picked blocks the leader,
; against Field_Unk55 (looks like the level the leader stands on):
; - Map_ProbeNoLevel set: blocks only when Field_Unk55 is
;   Map_LevelAny (3);
; - else Map_ProbeLevel 0 blocks; level 3, the same level as
;   Field_Unk55, or Field_Unk55 = 3 lets the leader through; any other
;   level blocks.
; Callers (2 JSR sites): Map_Unk8A6D ($C0:8AAF, in its .test_probe) and
;   Map_StepTileEffects ($C0:9C93).
; On entry: M=1 (8-bit A), X either, DP=$1D00 (!DP_Map), DB=$00
; (Field_Unk55 is read absolute).
; Exit: M=1, X, DP and DB unchanged; C=1: blocked, C=0: free; A
; clobbered.
; ------------------------------------------------------------
Map_ProbeLevelBlocked:
    LDA.b !Map_ProbeNoLevel-!DP_Map
    BNE .no_level
    LDA.b !Map_ProbeLevel-!DP_Map
    BEQ .blocked
    CMP.b #!Map_LevelAny
    BEQ .free
    CMP.w !DP_Field+!Field_Unk55
    BEQ .free
    LDA.w !DP_Field+!Field_Unk55
    CMP.b #!Map_LevelAny
    BEQ .free
.blocked:
    SEC
    RTS
.free:
    CLC
    RTS
.no_level:
    LDA.w !DP_Field+!Field_Unk55
    CMP.b #!Map_LevelAny
    BEQ .blocked
    CLC
    RTS

; ------------------------------------------------------------
; $C0:9C5C — Map_StepTileEffects (359 bytes, $9C5C–$9DC2)
; Map_Unk8A6D's commit of a step it has kept. The leader's new point
; is Map_LeaderX/Y plus Map_Unk1D2E/1D30 (to Map_ProbeX/Y, and the X to
; Map_DestX); Map_NextRowY is that Y one tile further on (minus $100 for
; an upward step, else plus $100). Then:
; - the new point's tile (Map_ProbeTileAttrsAny, Map_ProbeTileLevel,
;   Map_ProbeLevelBlocked) blocks: zero both steps and return;
; - unless a warp is already requested (Field_SceneFlags bit 7): when
;   the tile's Map_TileExitIdx has bit 7 clear, ExitRom record (value)
;   of the location (Map_ExitRec0 + value x 7, multiplied on the CPU's
;   WRMPYA/WRMPYB) is checked: its TileX is the probe's column and its
;   TileY less than Map_ExitRowRange from the probe's row, or its TileY
;   is the probe's row. Then Loc_DestId (DestLo and DestHiFacing bit 0),
;   Loc_DestX/Y and Loc_DestFacing (DestHiFacing bits 1-4, plus its bit
;   7) are set and SceneFlag_Warp is requested (inferred: an exit tile);
; - the tile at Map_DestX's column and Map_NextRowY's row: when its
;   Map_TileAttrA has bit 4 set, its index goes to Field_TileAnimX/Y and
;   SceneFlag_TileAnim is requested;
; - unless Map_ProbeNoLevel: Field_Unk55 = Map_ProbeLevel, and the
;   leader's Obj_PrioLow / Obj_PrioHigh = Map_ProbePrio / PrioHi;
; - Map_Unk1D34 = Map_ProbeMoveFlags, plus Map_ProbePushing when the new
;   tile's Map_ProbeAttrA bits 2-3 are nonzero. Those pick a push of
;   $08 / $10 / $20 that goes into Map_Unk1D2A or Map_Unk1D2B (copied
;   into the step every frame by Map_ResetUnk1D2E) by bits 0-1: 0 up,
;   1 down, 2 left, 3 right; the other one is zeroed. Bits 2-3 zero
;   zero both.
; Quirks (kept): with a warp already requested the exit test is skipped
; with 8-bit X still set, so the TAX for the bit-4 tile keeps only the
; column (row 0 is read) and STX writes only Field_TileAnimX. The index
; built at .no_exit is never used: .anim_tile overwrites A at once.
; Callers (19 sites, all in Map_Unk8A6D: a JSR at $C0:8AFE and 18 BRL
;   tail jumps such as $C0:8B4A).
; On entry: M either (set to 16-bit inside), X either, DP=$1D00
; (!DP_Map), DB=$00 (the field page, Obj_Prio*, WRMPYA/RDMPYL absolute).
; Exit: M=1, X=1, DP and DB unchanged; A, X, Y clobbered; besides the
; above, Map_ProbeX/Y, Map_DestX, Map_NextRowY, Map_PushSpeed (or
; Map_ExitScratch, the same byte) and the
; probe bytes written.
; ------------------------------------------------------------
Map_StepTileEffects:
    REP #$20
    LDA.b !Map_LeaderX-!DP_Map
    CLC
    ADC.b !Map_Unk1D2E-!DP_Map
    STA.b !Map_ProbeX-!DP_Map
    STA.b !Map_DestX-!DP_Map
    LDA.b !Map_LeaderY-!DP_Map
    CLC
    ADC.b !Map_Unk1D30-!DP_Map
    STA.b !Map_ProbeY-!DP_Map
    LDA.b !Map_Unk1D30-!DP_Map
    BIT.w #!Map_StepSign16
    BEQ .next_row_down
    LDA.b !Map_ProbeY-!DP_Map
    SEC
    SBC.w #!Map_RowStride
    STA.b !Map_NextRowY-!DP_Map
    BRA .test_tile
.next_row_down:
    LDA.b !Map_ProbeY-!DP_Map
    CLC
    ADC.w #!Map_RowStride
    STA.b !Map_NextRowY-!DP_Map
.test_tile:
    LDA.b !Map_ProbeY-!DP_Map
    SEP #$20
    LDA.b !Map_ProbeTileX-!DP_Map   ; A = row << 8 | column
    JSR Map_ProbeTileAttrsAny
    JSR Map_ProbeTileLevel
    JSR Map_ProbeLevelBlocked
    BCC .free
    REP #$20
    STZ.b !Map_Unk1D2E-!DP_Map
    STZ.b !Map_Unk1D30-!DP_Map
    SEP #$20
    RTS
.free:
    LDA.w !DP_Field+!Field_SceneFlags
    BIT.b #!SceneFlag_Warp
    BEQ .exit_test
    BRL .no_exit                    ; X still 8-bit here (quirk)
.exit_test:
    LDA.b !Map_ProbeTileY-!DP_Map
    AND.b !Map_RowMask1-!DP_Map
    XBA
    LDA.b !Map_ProbeTileX-!DP_Map
    AND.b !Map_ColMask1-!DP_Map
    REP #$10
    TAX
    LDA.l !Map_TileExitIdx,X
    BMI .anim_tile
    STA.w WRMPYA
    LDA.b #!Map_ExitRecSize
    STA.w WRMPYB
    NOP
    NOP
    NOP                             ; wait for the product
    REP #$20
    LDA.w RDMPYL
    CLC
    ADC.b !Map_ExitRec0-!DP_Map
    TAX
    SEP #$20
    LDA.l ExitRom.TileX,X
    CMP.b !Map_ProbeTileX-!DP_Map
    BEQ .same_column
    LDA.l ExitRom.TileY,X
    CMP.b !Map_ProbeTileY-!DP_Map
    BEQ .take_exit
    BRA .no_exit
.same_column:
    LDA.l ExitRom.TileY,X
    SEC
    SBC.b !Map_ProbeTileY-!DP_Map
    BPL .row_distance
    EOR.b #!Eng_Invert8
    INC A
.row_distance:
    CMP.b #!Map_ExitRowRange
    BCS .no_exit
.take_exit:
    LDA.l ExitRom.DestHiFacing,X
    STA.b !Map_ExitScratch-!DP_Map
    LSR A
    AND.b #!Exit_FacingMask
    STA.w !DP_Field+!Loc_DestFacing
    LDA.b !Map_ExitScratch-!DP_Map
    AND.b #!Exit_FacingBit7
    TSB.w !DP_Field+!Loc_DestFacing
    LDA.b !Map_ExitScratch-!DP_Map
    AND.b #!Exit_DestHiBit
    STA.w !DP_Field+!Loc_DestId+1
    LDA.l ExitRom.DestLo,X
    STA.w !DP_Field+!Loc_DestId
    LDA.l ExitRom.DestX,X
    STA.w !DP_Field+!Loc_DestX
    LDA.l ExitRom.DestY,X
    STA.w !DP_Field+!Loc_DestX+1
    LDA.w !DP_Field+!Field_SceneFlags
    ORA.b #!SceneFlag_Warp
    STA.w !DP_Field+!Field_SceneFlags
.no_exit:
    LDA.b !Map_ProbeTileY-!DP_Map   ; unused: .anim_tile reloads A (quirk)
    AND.b !Map_RowMask1-!DP_Map
    XBA
    LDA.b !Map_ProbeTileX-!DP_Map
    AND.b !Map_ColMask1-!DP_Map
.anim_tile:
    LDA.b !Map_NextRowTileY-!DP_Map
    AND.b !Map_RowMask1-!DP_Map
    XBA
    LDA.b !Map_DestTileX-!DP_Map
    AND.b !Map_ColMask1-!DP_Map
    TAX
    LDA.l !Map_TileAttrA,X
    BIT.b #!TileAttrA_AnimNear
    BEQ .level
    STX.w !DP_Field+!Field_TileAnimX ; 16-bit X: Field_TileAnimY too
    LDA.w !DP_Field+!Field_SceneFlags
    ORA.b #!SceneFlag_TileAnim
    STA.w !DP_Field+!Field_SceneFlags
.level:
    SEP #$10
    LDA.b !Map_ProbeNoLevel-!DP_Map
    BNE .push
    LDA.b !Map_ProbeLevel-!DP_Map
    STA.w !DP_Field+!Field_Unk55
    LDX.w !DP_Field+!Party_ObjSlot
    LDA.b !Map_ProbePrio-!DP_Map
    STA.w !Obj_PrioLow,X
    LDA.b !Map_ProbePrioHi-!DP_Map
    STA.w !Obj_PrioHigh,X
.push:
    LDA.b !Map_ProbeMoveFlags-!DP_Map
    STA.b !Map_Unk1D34-!DP_Map
    LDA.b !Map_ProbeAttrA-!DP_Map
    AND.b #!TileAttrA_PushSpeed
    BEQ .no_push
    CMP.b #!TileAttrA_PushSlow
    BEQ .slow
    CMP.b #!TileAttrA_PushMid
    BEQ .mid
    LDA.b #!Map_PushFast
    STA.b !Map_PushSpeed-!DP_Map
    BRA .direction
.slow:
    LDA.b #!Map_PushSlow
    STA.b !Map_PushSpeed-!DP_Map
    BRA .direction
.mid:
    LDA.b #!Map_PushMid
    STA.b !Map_PushSpeed-!DP_Map
.direction:
    LDA.b #!Map_ProbePushing
    TSB.b !Map_Unk1D34-!DP_Map
    LDA.b !Map_ProbeAttrA-!DP_Map
    AND.b #!TileAttrA_PushDir
    BEQ .push_up
    DEC A
    BEQ .push_down
    DEC A
    BEQ .push_left
    LDA.b !Map_PushSpeed-!DP_Map    ; 3: right
    STA.b !Map_Unk1D2A-!DP_Map
    STZ.b !Map_Unk1D2B-!DP_Map
    RTS
.push_left:
    LDA.b #$00
    SEC
    SBC.b !Map_PushSpeed-!DP_Map
    STA.b !Map_Unk1D2A-!DP_Map
    STZ.b !Map_Unk1D2B-!DP_Map
    RTS
.push_down:
    LDA.b !Map_PushSpeed-!DP_Map
    STA.b !Map_Unk1D2B-!DP_Map
    STZ.b !Map_Unk1D2A-!DP_Map
    RTS
.push_up:
    LDA.b #$00
    SEC
    SBC.b !Map_PushSpeed-!DP_Map
    STA.b !Map_Unk1D2B-!DP_Map
    STZ.b !Map_Unk1D2A-!DP_Map
    RTS
.no_push:
    STZ.b !Map_Unk1D2A-!DP_Map
    STZ.b !Map_Unk1D2B-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:9DC3 — Map_InitEntryTile (102 bytes, $9DC3–$9E28)
; The sibling of Map_StepTileEffects for a location load: it reads the
; entry tile (Loc_EntryX/Y) with Map_ProbeTileAttrsAny and
; Map_ProbeTileLevel at the bottom middle of the tile (Map_ProbeX low
; byte Map_ProbeMidX, Map_ProbeY low byte Map_ProbeBottomY; the high
; bytes are left as they are, Map_ProbeTileLevel reads only the low
; ones), then:
; - Field_Unk55 = Map_ProbeLevel, or Map_EntryLevelMin when that is 0
;   (so a level-0 tile starts the leader at level 1);
; - the leader (Party_ObjSlot) gets Obj_PrioLow = Map_ProbePrio and
;   Obj_PrioHigh = Map_ProbePrioHi; the other two party slots get
;   Map_ProbePrioHi in both bytes (A is not reloaded; kept as found);
; - Map_Unk1D34 = Map_ProbeMoveFlags.
; Before that it zeroes Field_UnkAB-AD and byte 0 of ObjX_Unk7F0C00,
; 7F0C80, 7F0D00 and 7F0D80 (object 0's entry, if those are per-object
; tables like the ObjX_* ones; not established).
; Callers: BRL from unmatched location-load code at $C0:5926 (its
;   only call site; it returns to that code's caller).
; On entry: M=1 (8-bit A), X either (8-bit inside), DP any (saved, set
; to $1D00 = !DP_Map, restored), DB=$00 or $7E (Field_*, Obj_Prio*
; and Map_Unk1D34 written absolute in low RAM).
; Exit: M=1, X=0 (16-bit), DP and DB unchanged; A = Map_ProbeMoveFlags,
; X = Party_ObjSlot2 (low byte), Y clobbered; the probe bytes and
; Map_ProbeTileLevel's outputs written.
; ------------------------------------------------------------
Map_InitEntryTile:
    STZ.w !DP_Field+!Field_UnkAB
    STZ.w !DP_Field+!Field_UnkAC
    STZ.w !DP_Field+!Field_UnkAD
    LDA.b #$00
    STA.l !ObjX_Unk7F0C00
    STA.l !ObjX_Unk7F0C80
    STA.l !ObjX_Unk7F0D00
    STA.l !ObjX_Unk7F0D80
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    LDA.w !DP_Field+!Loc_EntryX         ; 16-bit: Loc_EntryY << 8 | Loc_EntryX
    SEP #$20
    JSR Map_ProbeTileAttrsAny
    LDA.b #!Map_ProbeMidX
    STA.b !Map_ProbeX-!DP_Map
    LDA.b #!Map_ProbeBottomY
    STA.b !Map_ProbeY-!DP_Map
    JSR Map_ProbeTileLevel
    LDA.b !Map_ProbeLevel-!DP_Map
    BNE .set_level
    LDA.b #!Map_EntryLevelMin
.set_level:
    STA.w !DP_Field+!Field_Unk55
    LDA.b !Map_ProbePrio-!DP_Map
    LDX.w !DP_Field+!Party_ObjSlot      ; 8-bit X: the slot's low byte
    STA.w !Obj_PrioLow,X
    LDA.b !Map_ProbePrioHi-!DP_Map
    STA.w !Obj_PrioHigh,X
    LDX.w !DP_Field+!Party_ObjSlot1
    STA.w !Obj_PrioLow,X                ; Map_ProbePrioHi in both bytes
    STA.w !Obj_PrioHigh,X
    LDX.w !DP_Field+!Party_ObjSlot2
    STA.w !Obj_PrioLow,X
    STA.w !Obj_PrioHigh,X
    LDA.b !Map_ProbeMoveFlags-!DP_Map
    STA.w !Map_Unk1D34
    PLD
    REP #$10
    RTS

; ============================================================
; Location map setup: the map-properties step of a location load
; (LocLoad_UnkA33B) with its three callees, which fill the layer sizes,
; wrap masks, scroll limits, own-step amounts, screen layers and the
; per-tile planes, and the exit and treasure tile planes
; ($C0:7399–$C0:74A5, $C0:A33B–$C0:A7E8).
; ============================================================

; ------------------------------------------------------------
; $C0:7399 — Map_InitMasksAndLimits (269 bytes, $7399–$74A5)
; Turns the six layer sizes LocLoad_UnkA33B just set into the wrap
; masks the row / column writers use: Map_ColMask1 from Map_Unk0BCB,
; Map_RowMask1 from Map_Unk0BCD, Map_ColMask2 / RowMask2 from
; Map_Unk0BCF / 0BD1, Map_ColMask3 / RowMask3 from Map_Unk0BD3 / 0BD5:
; $40 and $30 give $3F, $20 gives $1F, anything else $0F (a 48-metatile
; layer wraps at 64; the $40 and $30 cases are separate branches with
; the same store, kept as found). Then the four limits Map_Unk1D1A /
; 1D1C / 1D1B / 1D1D come from the location's LocRom.LimitLeft / Top /
; Right / Bottom, or, when LimitLeft has bit 7 set, are 0, 0,
; Map_Unk0BCB - 1 and Map_Unk0BCD - 1 (the edges of layer 1).
; Callers: LocLoad_UnkA33B ($C0:A4FD), its only call site.
; On entry: M=1 (8-bit A), X=0 (16-bit X: Loc_RecOfs), DP=$1D00
; (!DP_Map), DB=$00 or $7E (Map_Unk0BCB-0BD5 and Loc_RecOfs read
; absolute in low RAM).
; Exit: M=1, X=0, DP and DB unchanged; A clobbered; X = Loc_RecOfs;
; Map_ColMask1-Map_RowMask3 and Map_Unk1D1A-1D1D written.
; ------------------------------------------------------------
org $C07399
Map_InitMasksAndLimits:
    LDA.w !Map_Unk0BCB
    CMP.b #!Map_Metatiles64
    BEQ .col1_64
    CMP.b #!Map_Metatiles32
    BEQ .col1_32
    CMP.b #!Map_Metatiles48
    BEQ .col1_48
    LDA.b #!Map_WrapMask16
    STA.b !Map_ColMask1-!DP_Map
    BRA .row1
.col1_32:
    LDA.b #!Map_WrapMask32
    STA.b !Map_ColMask1-!DP_Map
    BRA .row1
.col1_48:
    LDA.b #!Map_WrapMask64
    STA.b !Map_ColMask1-!DP_Map
    BRA .row1
.col1_64:
    LDA.b #!Map_WrapMask64
    STA.b !Map_ColMask1-!DP_Map
.row1:
    LDA.w !Map_Unk0BCD
    CMP.b #!Map_Metatiles64
    BEQ .row1_64
    CMP.b #!Map_Metatiles32
    BEQ .row1_32
    CMP.b #!Map_Metatiles48
    BEQ .row1_48
    LDA.b #!Map_WrapMask16
    STA.b !Map_RowMask1-!DP_Map
    BRA .col2
.row1_32:
    LDA.b #!Map_WrapMask32
    STA.b !Map_RowMask1-!DP_Map
    BRA .col2
.row1_48:
    LDA.b #!Map_WrapMask64
    STA.b !Map_RowMask1-!DP_Map
    BRA .col2
.row1_64:
    LDA.b #!Map_WrapMask64
    STA.b !Map_RowMask1-!DP_Map
.col2:
    LDA.w !Map_Unk0BCF
    CMP.b #!Map_Metatiles64
    BEQ .col2_64
    CMP.b #!Map_Metatiles32
    BEQ .col2_32
    CMP.b #!Map_Metatiles48
    BEQ .col2_48
    LDA.b #!Map_WrapMask16
    STA.b !Map_ColMask2-!DP_Map
    BRA .row2
.col2_32:
    LDA.b #!Map_WrapMask32
    STA.b !Map_ColMask2-!DP_Map
    BRA .row2
.col2_48:
    LDA.b #!Map_WrapMask64
    STA.b !Map_ColMask2-!DP_Map
    BRA .row2
.col2_64:
    LDA.b #!Map_WrapMask64
    STA.b !Map_ColMask2-!DP_Map
.row2:
    LDA.w !Map_Unk0BD1
    CMP.b #!Map_Metatiles64
    BEQ .row2_64
    CMP.b #!Map_Metatiles32
    BEQ .row2_32
    CMP.b #!Map_Metatiles48
    BEQ .row2_48
    LDA.b #!Map_WrapMask16
    STA.b !Map_RowMask2-!DP_Map
    BRA .col3
.row2_32:
    LDA.b #!Map_WrapMask32
    STA.b !Map_RowMask2-!DP_Map
    BRA .col3
.row2_48:
    LDA.b #!Map_WrapMask64
    STA.b !Map_RowMask2-!DP_Map
    BRA .col3
.row2_64:
    LDA.b #!Map_WrapMask64
    STA.b !Map_RowMask2-!DP_Map
.col3:
    LDA.w !Map_Unk0BD3
    CMP.b #!Map_Metatiles64
    BEQ .col3_64
    CMP.b #!Map_Metatiles32
    BEQ .col3_32
    CMP.b #!Map_Metatiles48
    BEQ .col3_48
    LDA.b #!Map_WrapMask16
    STA.b !Map_ColMask3-!DP_Map
    BRA .row3
.col3_32:
    LDA.b #!Map_WrapMask32
    STA.b !Map_ColMask3-!DP_Map
    BRA .row3
.col3_48:
    LDA.b #!Map_WrapMask64
    STA.b !Map_ColMask3-!DP_Map
    BRA .row3
.col3_64:
    LDA.b #!Map_WrapMask64
    STA.b !Map_ColMask3-!DP_Map
.row3:
    LDA.w !Map_Unk0BD5
    CMP.b #!Map_Metatiles64
    BEQ .row3_64
    CMP.b #!Map_Metatiles32
    BEQ .row3_32
    CMP.b #!Map_Metatiles48
    BEQ .row3_48
    LDA.b #!Map_WrapMask16
    STA.b !Map_RowMask3-!DP_Map
    BRA .limits
.row3_32:
    LDA.b #!Map_WrapMask32
    STA.b !Map_RowMask3-!DP_Map
    BRA .limits
.row3_48:
    LDA.b #!Map_WrapMask64
    STA.b !Map_RowMask3-!DP_Map
    BRA .limits
.row3_64:
    LDA.b #!Map_WrapMask64
    STA.b !Map_RowMask3-!DP_Map
.limits:
    LDX.w !DP_Field+!Loc_RecOfs
    LDA.l LocRom.LimitLeft,X
    BMI .map_edges
    STA.b !Map_Unk1D1A-!DP_Map
    LDA.l LocRom.LimitTop,X
    STA.b !Map_Unk1D1C-!DP_Map
    LDA.l LocRom.LimitRight,X
    STA.b !Map_Unk1D1B-!DP_Map
    LDA.l LocRom.LimitBottom,X
    STA.b !Map_Unk1D1D-!DP_Map
    RTS
.map_edges:
    STZ.b !Map_Unk1D1A-!DP_Map
    STZ.b !Map_Unk1D1C-!DP_Map
    LDA.w !Map_Unk0BCB
    DEC A
    STA.b !Map_Unk1D1B-!DP_Map
    LDA.w !Map_Unk0BCD
    DEC A
    STA.b !Map_Unk1D1D-!DP_Map
    RTS

; ------------------------------------------------------------
; $C0:A33B — LocLoad_UnkA33B (461 bytes, $A33B–$A507)
; The map-properties step of a location load (name kept: LoadLocation
; and Field_RestoreState call it by it). It unpacks the location's
; MapProps (Map_PropsPtrs entry LocRom.MapProps) to $7E:B500 with
; Decomp_ToWramVec, then with DP=$1D00 splits it:
; - zeroes the high bytes Map_Unk0BCBHi-0BD5Hi;
; - from MapProps.Size3: Map_Unk0BCA = Map_Unk0BCAOn or 0 (bit 7),
;   Map_Unk0BC9 = Map_Unk0BC9Set or 0 (bit 6), Map_OwnStepFlags =
;   Map_OwnStep3 (bit 5) | Map_OwnStep2 (bit 4), Map_Unk0BD3 = (bits 0-1
;   + 1) x 16 and Map_Unk0BD5 = (bits 2-3 + 4) x 4 (layer 3's sizes);
; - from MapProps.Size1 the same for layer 1 (Map_Unk0BCB, Map_Unk0BCD)
;   and layer 2: Map_Unk0BCF = bits 4-5 + $10, Map_Unk0BD1 = bits 6-7
;   / 4 + $10 (all four sizes come out $10, $20, $30 or $40);
; - Ppu_Unk0BDF = Ppu_Unk0BE0 = MapProps.ColorMath;
; - Ppu_Unk0BD7 (TM) = MapProps.Screens bits 0-2, with bit 3 moved to
;   bit 4 (OBJ); Ppu_Unk0BD8 (TS) = bits 4-6 >> 4, bit 7 to bit 4; with
;   Field_UnkBB nonzero both are cut to Layer_Bg12Obj (no BG3);
; - Map_LayerEdgeOff = Map_OwnStepFlags, then for MapProps.Move2 (if
;   nonzero) Map_OwnStep2X / 2Y = 1 << (n - 1) for the 3-bit fields n,
;   negated by their sign bits (a field of 0 leaves its byte as it
;   was), and Map_Layer2 set in Map_LayerEdgeOff; the same for Move3
;   (Map_OwnStep3X/Y, Map_Layer3);
; - and calls Map_InitMasksAndLimits, Map_UnpackTilePlanes (which reads
;   the rest of MapProps from MapProps.Planes) and Map_LoadExitTiles.
; Callers: LoadLocation ($C0:0106), Field_RestoreState ($C0:01CF) and
;   unmatched code at $C0:0316.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100 (!DP_Field:
; Loc_RecOfs read as dp), DB=$00 (Map_Unk0BC9-0BE0 and Field_UnkBB
; absolute; Map_UnpackTilePlanes needs the WRAM port registers).
; Exit: M=1, X=0, DP restored, DB unchanged; A, X, Y clobbered;
; Eng_Scratch, the Decomp_* block, MapProps and the callees' outputs
; written (Map_ColMask1-RowMask3, Map_Unk1D1A-1D1D, the tile planes,
; Map_TileExitIdx, Map_ExitRec0 and their scratch bytes).
; ------------------------------------------------------------
org $C0A33B
LocLoad_UnkA33B:
    REP #$20
    LDX.b !Loc_RecOfs
    LDA.l LocRom.MapProps,X
    STA.b !Eng_Scratch
    CLC
    ADC.b !Eng_Scratch
    ADC.b !Eng_Scratch                  ; x Map_PropsPtrSize
    TAX
    LDA.l !Map_PropsPtrs,X
    STA.w !Decomp_Src
    LDA.w #MapProps&$FFFF
    STA.w !Decomp_Dest
    SEP #$20
    LDA.l !Map_PropsPtrs+2,X
    STA.w !Decomp_SrcBank
    LDA.b #!Bank7E
    STA.w !Decomp_DestBank
    JSL Decomp_ToWramVec
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    STZ.w !Map_Unk0BCBHi
    STZ.w !Map_Unk0BCDHi
    STZ.w !Map_Unk0BCFHi
    STZ.w !Map_Unk0BD1Hi
    STZ.w !Map_Unk0BD3Hi
    STZ.w !Map_Unk0BD5Hi
    LDA.l MapProps.Size3
    STA.b !Map_LoadScratch-!DP_Map
    BPL .no_layer3_plane
    LDA.b #!Map_Unk0BCAOn
    STA.w !Map_Unk0BCA
    BRA .half_rate
.no_layer3_plane:
    STZ.w !Map_Unk0BCA
.half_rate:
    LDA.b !Map_LoadScratch-!DP_Map
    BIT.b #!MapProps_HalfRate2
    BNE .half_rate_on
    STZ.w !Map_Unk0BC9
    BRA .own_step3
.half_rate_on:
    LDA.b #!Map_Unk0BC9Set
    STA.w !Map_Unk0BC9
.own_step3:
    LDA.b !Map_LoadScratch-!DP_Map
    BIT.b #!MapProps_OwnStep3
    BNE .own_step3_on
    STZ.b !Map_OwnStepFlags-!DP_Map
    BRA .own_step2
.own_step3_on:
    LDA.b #!Map_OwnStep3
    STA.b !Map_OwnStepFlags-!DP_Map
.own_step2:
    LDA.b !Map_LoadScratch-!DP_Map
    BIT.b #!MapProps_OwnStep2
    BEQ .layer3_size
    LDA.b !Map_OwnStepFlags-!DP_Map
    ORA.b #!Map_OwnStep2
    STA.b !Map_OwnStepFlags-!DP_Map
.layer3_size:
    LDA.b !Map_LoadScratch-!DP_Map
    AND.b #!MapProps_WidthBits
    INC A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.w !Map_Unk0BD3
    LDA.b !Map_LoadScratch-!DP_Map
    AND.b #!MapProps_HeightBits
    CLC
    ADC.b #!MapProps_HeightAdd
    ASL A
    ASL A
    STA.w !Map_Unk0BD5
    LDA.l MapProps.Size1
    STA.b !Map_PropsPart-!DP_Map
    AND.b #!MapProps_WidthBits
    INC A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.w !Map_Unk0BCB
    LDA.b !Map_PropsPart-!DP_Map
    AND.b #!MapProps_HeightBits
    CLC
    ADC.b #!MapProps_HeightAdd
    ASL A
    ASL A
    STA.w !Map_Unk0BCD
    LDA.b !Map_PropsPart-!DP_Map
    AND.b #!MapProps_L2WidthBits
    CLC
    ADC.b #!Map_ScreenMetatiles
    STA.w !Map_Unk0BCF
    LDA.b !Map_PropsPart-!DP_Map
    AND.b #!MapProps_L2HeightBits
    LSR A
    LSR A
    CLC
    ADC.b #!Map_ScreenMetatiles
    STA.w !Map_Unk0BD1
    LDA.l MapProps.ColorMath
    STA.w !Ppu_Unk0BDF
    STA.w !Ppu_Unk0BE0
    LDA.l MapProps.Screens
    STA.b !Map_LoadScratch-!DP_Map
    AND.b #!MapScreens_MainBgs
    STA.b !Map_PropsPart-!DP_Map
    LDA.b !Map_LoadScratch-!DP_Map
    AND.b #!MapScreens_MainObj
    ASL A                               ; OBJ: bit 3 -> bit 4
    ORA.b !Map_PropsPart-!DP_Map
    STA.w !Ppu_Unk0BD7
    LDA.w !DP_Field+!Field_UnkBB
    BEQ .sub_screen
    LDA.w !Ppu_Unk0BD7
    AND.b #!Layer_Bg12Obj
    STA.w !Ppu_Unk0BD7
.sub_screen:
    LDA.b !Map_LoadScratch-!DP_Map
    AND.b #!MapScreens_SubBgs
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Map_PropsPart-!DP_Map
    LDA.b !Map_LoadScratch-!DP_Map
    AND.b #!MapScreens_SubObj
    LSR A
    LSR A
    LSR A                               ; OBJ: bit 7 -> bit 4
    ORA.b !Map_PropsPart-!DP_Map
    STA.w !Ppu_Unk0BD8
    LDA.w !DP_Field+!Field_UnkBB
    BEQ .own_steps
    LDA.w !Ppu_Unk0BD8
    AND.b #!Layer_Bg12Obj
    STA.w !Ppu_Unk0BD8
.own_steps:
    LDA.b !Map_OwnStepFlags-!DP_Map
    STA.b !Map_LayerEdgeOff-!DP_Map
    LDA.l MapProps.Move2
    BEQ .move3
    STA.b !Map_PropsPart-!DP_Map
    SEP #$10
    AND.b #!MapMove_XBits
    BEQ .move2_y
    TAY
    LDA.b #$01
.move2_x_shift:
    DEY
    BEQ .move2_x_set
    ASL A
    BRA .move2_x_shift
.move2_x_set:
    STA.b !Map_OwnStep2X-!DP_Map
    LDA.b !Map_PropsPart-!DP_Map
    BIT.b #!MapMove_XNeg
    BEQ .move2_y
    LDA.b !Map_OwnStep2X-!DP_Map
    EOR.b #!Eng_Invert8
    INC A
    STA.b !Map_OwnStep2X-!DP_Map
.move2_y:
    LDA.b !Map_PropsPart-!DP_Map
    AND.b #!MapMove_YBits
    BEQ .move2_done
    LSR A
    LSR A
    LSR A
    LSR A
    TAY
    LDA.b #$01
.move2_y_shift:
    DEY
    BEQ .move2_y_set
    ASL A
    BRA .move2_y_shift
.move2_y_set:
    STA.b !Map_OwnStep2Y-!DP_Map
    LDA.b !Map_PropsPart-!DP_Map
    BIT.b #!MapMove_YNeg
    BEQ .move2_done
    LDA.b !Map_OwnStep2Y-!DP_Map
    EOR.b #!Eng_Invert8
    INC A
    STA.b !Map_OwnStep2Y-!DP_Map
.move2_done:
    LDA.b !Map_LayerEdgeOff-!DP_Map
    ORA.b #!Map_Layer2
    STA.b !Map_LayerEdgeOff-!DP_Map
    REP #$10
.move3:
    LDA.l MapProps.Move3
    BEQ .finish
    STA.b !Map_PropsPart-!DP_Map
    SEP #$10
    AND.b #!MapMove_XBits
    BEQ .move3_y
    TAY
    LDA.b #$01
.move3_x_shift:
    DEY
    BEQ .move3_x_set
    ASL A
    BRA .move3_x_shift
.move3_x_set:
    STA.b !Map_OwnStep3X-!DP_Map
    LDA.b !Map_PropsPart-!DP_Map
    BIT.b #!MapMove_XNeg
    BEQ .move3_y
    LDA.b !Map_OwnStep3X-!DP_Map
    EOR.b #!Eng_Invert8
    INC A
    STA.b !Map_OwnStep3X-!DP_Map
.move3_y:
    LDA.b !Map_PropsPart-!DP_Map
    AND.b #!MapMove_YBits
    BEQ .move3_done
    LSR A
    LSR A
    LSR A
    LSR A
    TAY
    LDA.b #$01
.move3_y_shift:
    DEY
    BEQ .move3_y_set
    ASL A
    BRA .move3_y_shift
.move3_y_set:
    STA.b !Map_OwnStep3Y-!DP_Map
    LDA.b !Map_PropsPart-!DP_Map
    BIT.b #!MapMove_YNeg
    BEQ .move3_done
    LDA.b !Map_OwnStep3Y-!DP_Map
    EOR.b #!Eng_Invert8
    INC A
    STA.b !Map_OwnStep3Y-!DP_Map
.move3_done:
    LDA.b !Map_LayerEdgeOff-!DP_Map
    ORA.b #!Map_Layer3
    STA.b !Map_LayerEdgeOff-!DP_Map
    REP #$10
.finish:
    JSR Map_InitMasksAndLimits
    JSR Map_UnpackTilePlanes
    JSR Map_LoadExitTiles
    PLD
    RTS

; ------------------------------------------------------------
; $C0:A508 — LocLoad_EmptyStep (1 byte, $A508)
; A lone RTS: does nothing. Its one caller calls it between two steps
; of the reload sequence (probably a step that was emptied out).
; Callers: LocLoad_DrawMap ($C0:0A70).
; Entry/Exit: any state; nothing changed.
; ------------------------------------------------------------
LocLoad_EmptyStep:
    RTS

; ------------------------------------------------------------
; $C0:A509 — Ppu_ApplyMapScreens (24 bytes, $A509–$A520)
; Writes the screen settings LocLoad_UnkA33B took from MapProps to the
; PPU: Ppu_Unk0BD7 to TM, Ppu_Unk0BD8 to TS, Ppu_Unk0BDF to CGADSUB,
; and 0 to MOSAIC (mosaic off).
; Callers: LocLoad_DrawMap ($C0:0A61) (xref also lists a doubtful
;   JSR at $C0:5CB9, inside other code's operands, not a call).
; On entry: M=1 (8-bit A), X any, DP any, DB=$00-$3F or $80-$BF (the
; PPU registers and Ppu_Unk0BD7-0BDF absolute; $00 from its caller).
; Exit: M=1, X, DP and DB unchanged; A = 0.
; ------------------------------------------------------------
Ppu_ApplyMapScreens:
    LDA.w !Ppu_Unk0BD7
    STA.w TM
    LDA.w !Ppu_Unk0BD8
    STA.w TS
    LDA.w !Ppu_Unk0BDF
    STA.w CGADSUB
    LDA.b #$00
    STA.w MOSAIC
    RTS

; ------------------------------------------------------------
; $C0:A521 — Map_UnpackTilePlanes (330 bytes, $A521–$A66A)
; Reads the rest of the unpacked MapProps (from MapProps.Planes, through
; the WRAM data port) into the map's per-tile planes. Each plane is
; filled row by row, index row << 8 | column, Map_RowEnd ending a row
; and Map_PlaneEnd the plane:
; - Map_TileProps (layer 1's tiles): Map_Unk0BCD rows of Map_Unk0BCB
;   bytes;
; - Map_Layer2Tiles: Map_Unk0BD1 rows of Map_Unk0BCF bytes;
; - Map_Layer3Tiles: Map_Unk0BD5 rows of Map_Unk0BD3 bytes, only when
;   Map_Unk0BCA bit 0 is set;
; - Map_TileHiBits, Map_TileAttrA and Map_TileAttrB together, over layer
;   1's size, as entries of three bytes (HiBits, AttrA, AttrB) for one
;   tile, or, when the first byte has bit 7 set, a run: HiBits = that
;   byte & Map_RunFlagMask, AttrA, AttrB, then a count (0 = 256) of
;   tiles that all get the three values, carried across row ends.
; It returns when the last plane is full (in the middle of a run if the
; run is longer).
; Callers: LocLoad_UnkA33B ($C0:A500), its only call site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00
; (WMADDL/WMADDH/WMDATA and Map_Unk0BC9-0BD5 absolute); MapProps
; unpacked at $7E:B500.
; Exit: M=1, X=0, DP and DB unchanged; A, X, Y clobbered; Map_PlaneEnd,
; Map_RowEnd and the Map_Run* bytes written; the WRAM port address left
; past the data read.
; ------------------------------------------------------------
Map_UnpackTilePlanes:
    LDX.w #MapProps.Planes&$FFFF
    STX.w WMADDL
    LDA.b #$00                          ; WRAM bank $7E (WMADDH bit 0 clear)
    STA.w WMADDH
    LDA.w !Map_Unk0BCD
    REP #$20
    XBA
    AND.w #!Eng_HighByteMask
    STA.b !Map_PlaneEnd-!DP_Map         ; rows << 8
    SEP #$20
    LDA.w !Map_Unk0BCB
    REP #$20
    AND.w #!Eng_LowByteMask
    STA.b !Map_RowEnd-!DP_Map           ; row 0, width
    SEP #$20
    LDX.w #$0000
.layer1:
    LDA.w WMDATA
    STA.l !Map_TileProps,X
    INX
    CPX.b !Map_RowEnd-!DP_Map
    BCC .layer1
    LDA.b !Map_RowEndRow-!DP_Map
    INC A
    STA.b !Map_RowEndRow-!DP_Map
    XBA
    LDA.b #$00
    TAX                                 ; X = next row << 8
    CPX.b !Map_PlaneEnd-!DP_Map
    BCC .layer1
    LDA.w !Map_Unk0BD1
    REP #$20
    XBA
    AND.w #!Eng_HighByteMask
    STA.b !Map_PlaneEnd-!DP_Map
    SEP #$20
    LDA.w !Map_Unk0BCF
    REP #$20
    AND.w #!Eng_LowByteMask
    STA.b !Map_RowEnd-!DP_Map
    SEP #$20
    LDX.w #$0000
.layer2:
    LDA.w WMDATA
    STA.l !Map_Layer2Tiles,X
    INX
    CPX.b !Map_RowEnd-!DP_Map
    BCC .layer2
    LDA.b !Map_RowEndRow-!DP_Map
    INC A
    STA.b !Map_RowEndRow-!DP_Map
    XBA
    LDA.b #$00
    TAX
    CPX.b !Map_PlaneEnd-!DP_Map
    BCC .layer2
    LDA.w !Map_Unk0BCA
    AND.b #!Map_Unk0BCAOn
    BEQ .attrs
    LDA.w !Map_Unk0BD5
    REP #$20
    XBA
    AND.w #!Eng_HighByteMask
    STA.b !Map_PlaneEnd-!DP_Map
    SEP #$20
    LDA.w !Map_Unk0BD3
    REP #$20
    AND.w #!Eng_LowByteMask
    STA.b !Map_RowEnd-!DP_Map
    SEP #$20
    LDX.w #$0000
.layer3:
    LDA.w WMDATA
    STA.l !Map_Layer3Tiles,X
    INX
    CPX.b !Map_RowEnd-!DP_Map
    BCC .layer3
    LDA.b !Map_RowEndRow-!DP_Map
    INC A
    STA.b !Map_RowEndRow-!DP_Map
    XBA
    LDA.b #$00
    TAX
    CPX.b !Map_PlaneEnd-!DP_Map
    BCC .layer3
.attrs:
    LDA.w !Map_Unk0BCD
    REP #$20
    XBA
    AND.w #!Eng_HighByteMask
    STA.b !Map_PlaneEnd-!DP_Map
    SEP #$20
    LDA.w !Map_Unk0BCB
    REP #$20
    AND.w #!Eng_LowByteMask
    STA.b !Map_RowEnd-!DP_Map
    SEP #$20
    LDX.w #$0000
    TDC
    XBA                                 ; B = 0 (the low byte of DP $1D00)
.attr_entry:
    LDA.w WMDATA
    BMI .run
    STA.l !Map_TileHiBits,X
    LDA.w WMDATA
    STA.l !Map_TileAttrA,X
    LDA.w WMDATA
    STA.l !Map_TileAttrB,X
.attr_next:
    INX
    CPX.b !Map_RowEnd-!DP_Map
    BCC .attr_entry
    LDA.b !Map_RowEndRow-!DP_Map
    INC A
    STA.b !Map_RowEndRow-!DP_Map
    XBA
    LDA.b #$00
    TAX
    CPX.b !Map_PlaneEnd-!DP_Map
    BCC .attr_entry
    RTS
.run:
    AND.b #!Map_RunFlagMask
    STA.b !Map_RunHiBits-!DP_Map
    STA.l !Map_TileHiBits,X
    LDA.w WMDATA
    STA.b !Map_RunAttrA-!DP_Map
    STA.l !Map_TileAttrA,X
    LDA.w WMDATA
    STA.b !Map_RunAttrB-!DP_Map
    STA.l !Map_TileAttrB,X
    TDC
    XBA                                 ; B = 0: Y = the count byte
    LDA.w WMDATA
    BNE .run_count
    LDY.w #!Map_RunLen256
    BRA .run_step
.run_count:
    TAY
.run_step:
    DEY
    BEQ .attr_next
    INX
    CPX.b !Map_RowEnd-!DP_Map
    BCC .run_tile
    LDA.b !Map_RowEndRow-!DP_Map
    INC A
    STA.b !Map_RowEndRow-!DP_Map
    XBA
    LDA.b #$00
    TAX
    CPX.b !Map_PlaneEnd-!DP_Map
    BCC .run_tile
    RTS
.run_tile:
    LDA.b !Map_RunHiBits-!DP_Map
    STA.l !Map_TileHiBits,X
    LDA.b !Map_RunAttrA-!DP_Map
    STA.l !Map_TileAttrA,X
    LDA.b !Map_RunAttrB-!DP_Map
    STA.l !Map_TileAttrB,X
    BRA .run_step

; ------------------------------------------------------------
; $C0:A66B — Map_LoadExitTiles (167 bytes, $A66B–$A711)
; Builds Map_TileExitIdx for the location: first every tile of all 64
; rows gets Map_ExitNone (row 0 filled, then copied to rows 63 down to
; 1 with MVN, one Map_PlaneBytes row at a time), then
; Map_ExitRec0 = ExitRom_LocOfs[Loc_Id & Loc_IdMask], and for each
; ExitRom record n from there up to the next location's first
; (Map_RecEnd) the tile at TileX / TileY (masked with Map_ColMask1 /
; Map_RowMask1) and the ExitRom.Span tiles after it get n: along the
; row when Span bit 7 is clear (only the column is masked again, so
; the run wraps within the row), down the column when it is set.
; Quirk (kept): the row loop comes back to its AND with 8-bit A (from
; a TXA after SEP #$20), so only the column byte is masked while B
; still holds the row; the column loop does the AND 16-bit.
; Callers: LocLoad_UnkA33B ($C0:A503), its only call site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00
; or $7E (Loc_Id read absolute; DB is saved around each MVN);
; Map_ColMask1/RowMask1 set.
; Exit: M=1, X=0, DP and DB unchanged; A, X, Y clobbered;
; Map_TileExitIdx, Map_ExitRec0, Map_RecOfs, Map_RecNum and Map_RecEnd
; written.
; ------------------------------------------------------------
Map_LoadExitTiles:
    LDA.b #!Map_ExitNone
    LDX.w #$0000
.clear_row0:
    STA.l !Map_TileExitIdx,X
    INX
    CPX.w #!Map_PlaneBytes
    BCC .clear_row0
    REP #$20
    LDY.w #(!Map_TileExitIdx+((!Map_PlaneRows-1)*!Map_RowStride))&$FFFF
.copy_row:
    LDX.w #!Map_TileExitIdx&$FFFF
    LDA.w #!Map_PlaneCopyLen
    PHB
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    TYA
    SEC
    SBC.w #!Map_RowStride+!Map_PlaneBytes ; back to the start of the row above
    TAY
    CPY.w #!Map_TileExitIdx&$FFFF
    BNE .copy_row
    LDA.w !DP_Field+!Loc_Id
    AND.w #!Loc_IdMask
    ASL A
    TAX
    LDA.l !ExitRom_LocOfs,X
    STA.b !Map_ExitRec0-!DP_Map
    INX
    INX
    LDA.l !ExitRom_LocOfs,X
    STA.b !Map_RecEnd-!DP_Map
    LDX.b !Map_ExitRec0-!DP_Map
    STZ.b !Map_RecNum-!DP_Map           ; 16-bit: also clears the byte after it
.next_record:
    CPX.b !Map_RecEnd-!DP_Map
    BCS .done
    LDA.w #$0000
    SEP #$20
    LDA.l ExitRom.Span,X
    BMI .column
    TAY
    REP #$20
    LDA.l ExitRom.TileX,X               ; 16-bit: TileY << 8 | TileX
    STX.b !Map_RecOfs-!DP_Map
.row_tile:
    AND.b !Map_ColMask1-!DP_Map         ; 16-bit the first time, 8-bit after (see above)
    TAX
    SEP #$20
    LDA.b !Map_RecNum-!DP_Map
    STA.l !Map_TileExitIdx,X
    CPY.w #$0000
    BEQ .record_done
    DEY
    INX
    TXA
    BRA .row_tile
.column:
    AND.b #!Exit_SpanLenMask
    TAY
    REP #$20
    LDA.l ExitRom.TileX,X
    STX.b !Map_RecOfs-!DP_Map
.column_tile:
    AND.b !Map_ColMask1-!DP_Map         ; 16-bit: Map_RowMask1 masks the row
    TAX
    SEP #$20
    LDA.b !Map_RecNum-!DP_Map
    STA.l !Map_TileExitIdx,X
    CPY.w #$0000
    BEQ .record_done
    DEY
    REP #$20
    TXA
    CLC
    ADC.w #!Map_RowStride
    BRA .column_tile
.record_done:
    INC A
    STA.b !Map_RecNum-!DP_Map
    REP #$20
    LDA.b !Map_RecOfs-!DP_Map
    CLC
    ADC.w #!Map_ExitRecSize
    TAX
    BRA .next_record
.done:
    SEP #$20
    RTS

; ------------------------------------------------------------
; $C0:A712 — Map_LoadTreasureTiles (170 bytes, $A712–$A7BB)
; As Map_LoadExitTiles for treasure: Map_TreasureIdx gets
; Map_TreasureNone on every tile (row 0, then MVN copies), then
; Map_TreasureRec0 = the first word of TreasureRom_LocOfs and the
; location's records run from TreasureRom_LocOfs[Loc_Id & Loc_IdMask]
; to the next word. When that list is not empty but its first record
; has a Tile word of 0, its Contents word is taken as another location
; number and that location's list is used instead (repeated while it
; holds; inferred from the indexing, which is the same). Each record n then marks its tile (Tile masked with
; Map_ColMask1/RowMask1) in Map_TreasureIdx with n, and when the
; treasure is already taken (Map_TreasureTaken, C=1) and the tile's
; layer-1 metatile has bit 8 set (Map_TileHiBits bit 0), a low byte
; of TileAnim_StateFE becomes TileAnim_StateFF and TileAnim_StateE0
; becomes TileAnim_StateE1 in Map_TileProps: the state the tile is
; stepped to when the treasure is taken (probably the opened chest).
; Map_TreasureLocRecs is left at the first record (of the list used).
; The STX to Map_LoadScratch is never read (kept as found).
; Callers (2 JSR sites): unmatched code at $C0:033C and LocLoad_DrawMap
;   ($C0:0A59).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00
; (Loc_Id read absolute, and Map_TreasureTaken reads BitSet at $FF20);
; Map_ColMask1/RowMask1, Map_TileHiBits and Map_TileProps set.
; Exit: M=1, X=0, DP and DB unchanged; A, X, Y clobbered;
; Map_TreasureIdx, Map_TreasureRec0, Map_TreasureLocRecs, Map_RecOfs,
; Map_RecNum, Map_RecEnd and Map_TreasureNum written.
; ------------------------------------------------------------
Map_LoadTreasureTiles:
    LDA.b #!Map_TreasureNone
    LDX.w #$0000
.clear_row0:
    STA.l !Map_TreasureIdx,X
    INX
    CPX.w #!Map_PlaneBytes
    BCC .clear_row0
    REP #$20
    LDY.w #(!Map_TreasureIdx+((!Map_PlaneRows-1)*!Map_RowStride))&$FFFF
.copy_row:
    LDX.w #!Map_TreasureIdx&$FFFF
    LDA.w #!Map_PlaneCopyLen
    PHB
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    TYA
    SEC
    SBC.w #!Map_RowStride+!Map_PlaneBytes
    TAY
    CPY.w #!Map_TreasureIdx&$FFFF
    BNE .copy_row
    LDA.l !TreasureRom_LocOfs
    STA.b !Map_TreasureRec0-!DP_Map
    LDA.w !DP_Field+!Loc_Id
    AND.w #!Loc_IdMask
.find_list:
    ASL A
    TAX
    LDA.l !TreasureRom_LocOfs+2,X
    STA.b !Map_RecEnd-!DP_Map
    LDA.l !TreasureRom_LocOfs,X
    CMP.b !Map_RecEnd-!DP_Map
    BEQ .done                           ; no treasure here
    STA.b !Map_TreasureLocRecs-!DP_Map
    STX.b !Map_LoadScratch-!DP_Map      ; never read
    TAX
    LDA.l TreasureRom.Tile,X
    BNE .records
    LDA.l TreasureRom.Contents,X        ; tile 0: use this location's list
    BRA .find_list
.records:
    LDX.b !Map_TreasureLocRecs-!DP_Map
    STZ.b !Map_RecNum-!DP_Map           ; 16-bit: also clears the byte after it
.next_record:
    CPX.b !Map_RecEnd-!DP_Map
    BCS .done
    LDA.l TreasureRom.Tile,X
    STX.b !Map_RecOfs-!DP_Map
    AND.b !Map_ColMask1-!DP_Map         ; 16-bit: Map_RowMask1 masks the row
    TAX
    SEP #$20
    LDA.b !Map_RecNum-!DP_Map
    STA.l !Map_TreasureIdx,X
    JSR Map_TreasureTaken
    BCC .record_done
    LDA.l !Map_TileHiBits,X
    BIT.b #!TileHiBits_L1Bit8
    BEQ .record_done
    LDA.l !Map_TileProps,X
    CMP.b #!TileAnim_StateFE
    BEQ .taken_fe
    CMP.b #!TileAnim_StateE0
    BNE .record_done
    LDA.b #!TileAnim_StateE1
    STA.l !Map_TileProps,X
    BRA .record_done
.taken_fe:
    LDA.b #!TileAnim_StateFF
    STA.l !Map_TileProps,X
.record_done:
    LDA.b !Map_RecNum-!DP_Map
    INC A
    STA.b !Map_RecNum-!DP_Map
    REP #$20
    LDA.b !Map_RecOfs-!DP_Map
    CLC
    ADC.w #!Map_TreasureRecSize
    TAX
    BRA .next_record
.done:
    SEP #$20
    RTS

; ------------------------------------------------------------
; $C0:A7BC — Map_TreasureTaken (45 bytes, $A7BC–$A7E8)
; Tests the Treasure_Flags bit of the record at Map_RecOfs: its number
; is (Map_RecOfs - Map_TreasureRec0) / 4, as in Field_CheckTileInFront.
; Returns C=1 when the bit is set (the treasure was taken), C=0 if not.
; Callers: Map_LoadTreasureTiles ($C0:A782), its only call site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$1D00 (!DP_Map), DB=$00
; (BitSet read absolute at $FF20); Map_RecOfs set.
; Exit: M=1, X=0, DP and DB unchanged; X preserved (PHX/PLX); A = the
; flag byte; Y = the bit number; Map_TreasureNum = the flag bit;
; C = taken.
; ------------------------------------------------------------
Map_TreasureTaken:
    PHX
    REP #$20
    LDA.b !Map_RecOfs-!DP_Map
    SEC
    SBC.b !Map_TreasureRec0-!DP_Map
    LSR A
    LSR A
    STA.b !Map_TreasureNum-!DP_Map     ; treasure number
    LSR A
    LSR A
    LSR A
    AND.w #!Treasure_FlagByteMask
    TAX                                 ; flag byte
    SEP #$20
    LDA.b !Map_TreasureNum-!DP_Map
    AND.b #!Treasure_FlagBitMask
    TAY
    LDA.w BitSet,Y
    STA.b !Map_TreasureNum-!DP_Map     ; flag bit
    LDA.l !Treasure_Flags,X
    BIT.b !Map_TreasureNum-!DP_Map
    BNE .taken
    PLX
    CLC
    RTS
.taken:
    PLX
    SEC
    RTS

; ------------------------------------------------------------
; $C0:A7E9 — Obj_ResetFrameState (39 bytes, $A7E9–$A80F)
; For each location object (Evt_ObjCount of them) writes 0 to its
; Obj_Unk0F00 (no frame to build) and Obj_LastFrameNone to its
; Obj_LastFrame (so the next frame is always rebuilt), through the WRAM
; data port from Obj_Unk0F00 on: two bytes per object, the objects'
; 2-byte slot stride. The DEC/BNE count assumes Evt_ObjCount >= 1 (0
; would write 256 pairs; kept as found).
; Callers (2 JSR sites): unmatched code at $C0:287E (in Scene_ReloadStep)
;   and $C0:56C2.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP any (saved, set to $2100
; = !DP_PPU, restored), DB any (Evt_ObjCount read long).
; Exit: M=1, X=0, DP restored, DB unchanged; A = 0, X = 0, Y =
; Obj_LastFrameNone; the WRAM port address left past the last pair.
; ------------------------------------------------------------
Obj_ResetFrameState:
    PHD
    REP #$20
    LDA.w #!DP_PPU
    TCD
    SEP #$20
    LDX.w #!Obj_Unk0F00
    STX.b WMADDL-!DP_PPU
    LDA.b #$00                          ; bank $7E: the low-RAM object tables
    STA.b WMADDH-!DP_PPU
    SEP #$10
    LDA.l !Evt_ObjCount
    LDX.b #$00
    LDY.b #!Obj_LastFrameNone
.object:
    STX.b WMDATA-!DP_PPU                ; Obj_Unk0F00
    STY.b WMDATA-!DP_PPU                ; Obj_LastFrame
    DEC A
    BNE .object
    REP #$10
    PLD
    RTS

; ============================================================
; Map drawing after a load: the reload step that puts the treasure
; tiles in, sets the screen registers and the scroll origin and builds
; and uploads the three layers ($C0:0A50), the origin setup and the
; per-layer scroll resets ($C0:74A6–$C0:759F), and the right-edge
; column build Field_Unk87F1 ($C0:87F1).
; ============================================================

; ------------------------------------------------------------
; $C0:0A50 — LocLoad_DrawMap (175 bytes, $0A50–$0AFE)
; Draws the freshly loaded map:
; - Map_LoadTreasureTiles (DP=$1D00), Ppu_SetBgLayout and
;   Ppu_ApplyMapScreens;
; - with DP=$1D00: Map_InitOrigin, LocLoad_EmptyStep, the tilemap VRAM
;   bases Map_TilemapVram = Map_VramTilemap1, Map_TilemapVram3 =
;   Map_VramTilemap2, Map_TilemapVramL3 = Map_VramTilemap3,
;   Map_TilemapVram2 = Map_VramTilemapAlt, and Map_TilemapVram4,
;   Map_TilemapVram4Hi and Map_Unk1D86 = Map_ScSizeInit;
; - layer 1: Field_BuildC800Mode1, then Map_UploadBuf2K to
;   Map_TilemapVram; layer 2: Field_BuildC800Mode2, uploaded to
;   Map_TilemapVram3 with Map_UploadBuf4K when Map_LayerEdgeOff has
;   Map_Layer2 set (the layer moves on its own), else Map_UploadBuf2K;
;   layer 3 the same (Field_BuildC800Mode4, Map_TilemapVramL3,
;   Map_Layer3), only when Map_Unk0BCA bit 0 is set and Field_UnkBB is 0;
; - Field_Unk87F1 (the right-edge columns), then Map_Unk1D86 =
;   Field_Unk0BE9 when that is nonzero.
; Callers: Scene_ReloadStep ($C0:286F), its only call site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100 (!DP_Field:
; VramDma_Addr written as dp), DB=$00 (the callees write PPU and WRAM
; port registers absolute).
; Exit: M=1, X=0, DP=$0100, DB unchanged; A, X, Y clobbered; besides the
; above, everything the callees write (the map planes and edge
; buffers, the origin and bounds, Map_EdgeVram*/EdgeSize*, VRAM).
; ------------------------------------------------------------
org $C00A50
LocLoad_DrawMap:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Map_LoadTreasureTiles
    PLD
    JSL Ppu_SetBgLayout
    JSR Ppu_ApplyMapScreens
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Map_InitOrigin
    JSR LocLoad_EmptyStep
    LDX.w #!Map_VramTilemap1
    STX.w !Map_TilemapVram
    LDX.w #!Map_VramTilemap2
    STX.w !Map_TilemapVram3
    LDX.w #!Map_VramTilemap3
    STX.w !Map_TilemapVramL3
    LDX.w #!Map_VramTilemapAlt
    STX.w !Map_TilemapVram2
    LDA.b #!Map_ScSizeInit
    STA.w !Map_TilemapVram4
    STA.w !Map_TilemapVram4Hi
    STA.w !Map_Unk1D86
    JSR Field_BuildC800Mode1
    PLD
    LDX.w !Map_TilemapVram
    STX.b !VramDma_Addr
    JSR Map_UploadBuf2K
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode2
    PLD
    LDX.w !Map_TilemapVram3
    STX.b !VramDma_Addr
    LDA.w !Map_LayerEdgeOff
    BIT.b #!Map_Layer2
    BEQ .layer2_2k
    JSR Map_UploadBuf4K
    BRA .layer3
.layer2_2k:
    JSR Map_UploadBuf2K
.layer3:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    LDA.w !Map_Unk0BCA
    AND.b #!Map_Unk0BCAOn
    BEQ .no_layer3
    LDA.w !DP_Field+!Field_UnkBB
    BNE .no_layer3
    JSR Field_BuildC800Mode4
    PLD
    LDX.w !Map_TilemapVramL3
    STX.b !VramDma_Addr
    LDA.w !Map_LayerEdgeOff
    BIT.b #!Map_Layer3
    BEQ .layer3_2k
    JSR Map_UploadBuf4K
    BRA .edges
.layer3_2k:
    JSR Map_UploadBuf2K
    BRA .edges
.no_layer3:
    PLD
.edges:
    JSR Field_Unk87F1
    LDA.w !Field_Unk0BE9
    BEQ .done
    STA.w !Map_Unk1D86
.done:
    RTS

; ------------------------------------------------------------
; $C0:74A6 — Map_InitOrigin (46 bytes, $74A6–$74D3)
; Sets the scroll origin for the leader's entry point: Map_InitOriginX
; and Map_InitOriginY, then, when Map_Unk0BC9 has bit 7 set (layer 2 at
; half rate), layer 2's half-rate origin and bounds: Map_Unk1D12 =
; Map_TileOriginX / 2 made even, Map_Unk1D14 = that + Bg_ScreenWidth,
; Map_Unk1D16 = Map_TileOriginY / 2, Map_Unk1D18 = that +
; Map_ScreenTileRows. Then it zeroes the six tilemap biases
; Map_BgColBias-Map_BgRowBias3 and tail-jumps to Sub_C07F9A.
; Callers: LocLoad_DrawMap ($C0:0A6D), its only call site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y, for Sub_C07F9A), DP=$1D00
; (!DP_Map), DB=$00 or $7E (Map_Unk0BC9 and Loc_EntryX/Y absolute in
; low RAM).
; Exit (from Sub_C07F9A, BRL tail call): M=1, X=0, DP and DB unchanged;
; A, X, Y clobbered; Map_TileOriginX/Y, Map_Unk1D0C, Map_Unk1D10 (low
; bytes), Map_Unk1D12-1D18, the biases, Map_OriginTest and
; Sub_C07F9A's outputs written.
; ------------------------------------------------------------
org $C074A6
Map_InitOrigin:
    JSR Map_InitOriginX
    JSR Map_InitOriginY
    LDA.w !Map_Unk0BC9
    BPL .biases
    LDA.b !Map_TileOriginX-!DP_Map
    LSR A
    AND.b #!Map_EvenMask
    STA.b !Map_Unk1D12-!DP_Map
    CLC
    ADC.b #!Bg_ScreenWidth
    STA.b !Map_Unk1D14-!DP_Map
    LDA.b !Map_TileOriginY-!DP_Map
    LSR A
    STA.b !Map_Unk1D16-!DP_Map
    CLC
    ADC.b #!Map_ScreenTileRows
    STA.b !Map_Unk1D18-!DP_Map
.biases:
    REP #$20
    STZ.b !Map_BgColBias-!DP_Map        ; 16-bit: with Map_BgRowBias
    STZ.b !Map_BgColBias2-!DP_Map       ; with Map_BgRowBias2
    STZ.b !Map_BgColBias3-!DP_Map       ; with Map_BgRowBias3
    SEP #$20
    BRL Sub_C07F9A

; ------------------------------------------------------------
; $C0:74D4 — Field_Unk74D4 (20 bytes, $74D4–$74E7)
; Resets layer 1's scroll: zeroes Map_BgColBias / Map_BgRowBias and the
; scroll words Map_Unk1D87 / Map_Unk1D89, then runs Sub_C07F9A for the
; new edge addresses. Field_Unk74E8 (layer 2) and Field_Unk74F7 (layer
; 3) do the same for their layer and branch into the shared tail
; Field_Unk74D4_Tail (SEP, the call, PLD, RTS).
; Callers: DefaultHandler ($C0:17AD, $C0:1825, $C0:184C) and
;   Field_HookLeaveToBankC3 ($C0:261B).
; On entry: M either (set to 16-bit inside), X=0 (16-bit X/Y, for
; Sub_C07F9A), DP any (saved, set to $1D00 = !DP_Map, restored), DB any
; (all direct page).
; Exit: M=1, X=0, DP restored, DB unchanged; A, X, Y clobbered;
; Sub_C07F9A's outputs written.
; ------------------------------------------------------------
org $C074D4
Field_Unk74D4:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    STZ.b !Map_BgColBias-!DP_Map        ; with Map_BgRowBias
    STZ.b !Map_Unk1D87-!DP_Map
    STZ.b !Map_Unk1D89-!DP_Map
Field_Unk74D4_Tail:                     ; header: see Field_Unk74D4
    SEP #$20
    JSR Sub_C07F9A
    PLD
    RTS

; ------------------------------------------------------------
; $C0:74E8 — Field_Unk74E8 (15 bytes, $74E8–$74F6)
; As Field_Unk74D4 for layer 2: zeroes Map_BgColBias2 / Map_BgRowBias2,
; Map_Unk1D8B and Map_Unk1D8D, then Field_Unk74D4_Tail.
; Callers: DefaultHandler ($C0:17D6, $C0:1828) and Field_HookWinPulse
;   ($C0:265C).
; Entry/Exit: as Field_Unk74D4.
; ------------------------------------------------------------
Field_Unk74E8:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    STZ.b !Map_BgColBias2-!DP_Map       ; with Map_BgRowBias2
    STZ.b !Map_Unk1D8B-!DP_Map
    STZ.b !Map_Unk1D8D-!DP_Map
    BRA Field_Unk74D4_Tail

; ------------------------------------------------------------
; $C0:74F7 — Field_Unk74F7 (15 bytes, $74F7–$7505)
; As Field_Unk74D4 for layer 3: zeroes Map_BgColBias3 / Map_BgRowBias3,
; Map_Unk1D8F and Map_Unk1D91, then Field_Unk74D4_Tail.
; Callers: DefaultHandler ($C0:1873) and Field_HookWinPulse ($C0:265F).
; Entry/Exit: as Field_Unk74D4.
; ------------------------------------------------------------
Field_Unk74F7:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    STZ.b !Map_BgColBias3-!DP_Map       ; with Map_BgRowBias3
    STZ.b !Map_Unk1D8F-!DP_Map
    STZ.b !Map_Unk1D91-!DP_Map
    BRA Field_Unk74D4_Tail

; ------------------------------------------------------------
; $C0:7506 — Map_InitOriginX (77 bytes, $7506–$7552)
; Puts layer 1's left origin (Map_TileOriginX, in 8x8 tiles: metatile
; column x 2) so that the entry column Loc_EntryX is Map_OriginLeadX
; metatiles from the screen's left edge, kept inside the limits
; Map_Unk1D1A-1D1B:
; - Loc_EntryX <= Map_Unk1D1A + Map_OriginLeadX: origin = Map_Unk1D1A x 2
;   (the equal and the lower case are separate branches with the same
;   code; kept as found);
; - else origin = (Loc_EntryX - Map_OriginLeadX) x 2, unless
;   Map_Unk1D1B - Map_OriginLeadX < Loc_EntryX: then the right bound is
;   (Map_Unk1D1B + 1) x 2 and the origin one screen (Bg_ScreenWidth)
;   left of it.
; Map_Unk1D0C (the right bound) = origin + Bg_ScreenWidth. Only the low
; bytes of Map_TileOriginX and Map_Unk1D0C are written.
; Callers: Map_InitOrigin ($C0:74A6), its only call site.
; On entry: M=1 (8-bit A), X any, DP=$1D00 (!DP_Map), DB=$00 or $7E
; (Loc_EntryX absolute).
; Exit: M=1, X, DP and DB unchanged; A clobbered; Map_OriginTest
; written.
; ------------------------------------------------------------
Map_InitOriginX:
    LDA.b !Map_Unk1D1A-!DP_Map
    CLC
    ADC.b #!Map_OriginLeadX
    STA.b !Map_OriginTest-!DP_Map
    LDA.w !DP_Field+!Loc_EntryX
    CMP.b !Map_OriginTest-!DP_Map
    BEQ .at_left
    BCS .past_left
    LDA.b !Map_Unk1D1A-!DP_Map
    ASL A
    STA.b !Map_TileOriginX-!DP_Map
    CLC
    ADC.b #!Bg_ScreenWidth
    STA.b !Map_Unk1D0C-!DP_Map
    BRA .done
.at_left:
    LDA.b !Map_Unk1D1A-!DP_Map
    ASL A
    STA.b !Map_TileOriginX-!DP_Map
    CLC
    ADC.b #!Bg_ScreenWidth
    STA.b !Map_Unk1D0C-!DP_Map
    BRA .done
.past_left:
    SEC
    SBC.b #!Map_OriginLeadX
    ASL A
    STA.b !Map_TileOriginX-!DP_Map
    LDA.b !Map_Unk1D1B-!DP_Map
    SEC
    SBC.b #!Map_OriginLeadX
    CMP.w !DP_Field+!Loc_EntryX
    BCS .bound_from_origin
    LDA.b !Map_Unk1D1B-!DP_Map
    INC A
    ASL A
    STA.b !Map_Unk1D0C-!DP_Map
    SEC
    SBC.b #!Bg_ScreenWidth
    STA.b !Map_TileOriginX-!DP_Map
    BRA .done
.bound_from_origin:
    LDA.b !Map_TileOriginX-!DP_Map
    CLC
    ADC.b #!Bg_ScreenWidth
    STA.b !Map_Unk1D0C-!DP_Map
.done:
    RTS

; ------------------------------------------------------------
; $C0:7553 — Map_InitOriginY (77 bytes, $7553–$759F)
; As Map_InitOriginX for rows: Map_TileOriginY from Loc_EntryY and the
; limits Map_Unk1D1C-1D1D, the leader Map_OriginLeadY metatiles below
; the top edge; the bottom bound Map_Unk1D10 = origin +
; Map_ScreenTileRows, and the bottom test is Map_Unk1D1D -
; Map_OriginLeadYBelow < Loc_EntryY (a 14-metatile screen: 8 rows above
; the leader, 6 below). Same duplicate equal / lower branches.
; Callers: Map_InitOrigin ($C0:74A9), its only call site.
; On entry: M=1 (8-bit A), X any, DP=$1D00 (!DP_Map), DB=$00 or $7E
; (Loc_EntryY absolute).
; Exit: M=1, X, DP and DB unchanged; A clobbered; Map_OriginTest
; written.
; ------------------------------------------------------------
Map_InitOriginY:
    LDA.b !Map_Unk1D1C-!DP_Map
    CLC
    ADC.b #!Map_OriginLeadY
    STA.b !Map_OriginTest-!DP_Map
    LDA.w !DP_Field+!Loc_EntryY
    CMP.b !Map_OriginTest-!DP_Map
    BEQ .at_top
    BCS .past_top
    LDA.b !Map_Unk1D1C-!DP_Map
    ASL A
    STA.b !Map_TileOriginY-!DP_Map
    CLC
    ADC.b #!Map_ScreenTileRows
    STA.b !Map_Unk1D10-!DP_Map
    BRA .done
.at_top:
    LDA.b !Map_Unk1D1C-!DP_Map
    ASL A
    STA.b !Map_TileOriginY-!DP_Map
    CLC
    ADC.b #!Map_ScreenTileRows
    STA.b !Map_Unk1D10-!DP_Map
    BRA .done
.past_top:
    SEC
    SBC.b #!Map_OriginLeadY
    ASL A
    STA.b !Map_TileOriginY-!DP_Map
    LDA.b !Map_Unk1D1D-!DP_Map
    SEC
    SBC.b #!Map_OriginLeadYBelow
    CMP.w !DP_Field+!Loc_EntryY
    BCS .bound_from_origin
    LDA.b !Map_Unk1D1D-!DP_Map
    INC A
    ASL A
    STA.b !Map_Unk1D10-!DP_Map
    SEC
    SBC.b #!Map_ScreenTileRows
    STA.b !Map_TileOriginY-!DP_Map
    BRA .done
.bound_from_origin:
    LDA.b !Map_TileOriginY-!DP_Map
    CLC
    ADC.b #!Map_ScreenTileRows
    STA.b !Map_Unk1D10-!DP_Map
.done:
    RTS

; ------------------------------------------------------------
; $C0:87F1 — Field_Unk87F1 (45 bytes, $87F1–$881D)
; Builds the right-hand edge column of each layer after a full redraw
; and recomputes the edge addresses: Map_BuildColXInc1; for layer 2,
; unless Map_LayerEdgeOff has Map_Layer2 set, Map_BuildColXInc2Half
; (Map_Unk0BC9 bit 7 set) or Map_BuildColXInc2; for layer 3, unless
; Map_Layer3 is set there, Map_BuildColXInc3; then Sub_C07F9A.
; Callers: LocLoad_DrawMap ($C0:0AF3) and DefaultHandler ($C0:17BF,
;   $C0:17E8, $C0:185C, $C0:1885).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP any (saved, set to
; $1D00 = !DP_Map, restored), DB=$00 (the builders write WMADDL/H).
; Exit: M=1, X=0, DP restored, DB unchanged; A, X, Y clobbered; the
; Map_BuiltColXInc bits, edge buffers and Sub_C07F9A's outputs written.
; ------------------------------------------------------------
org $C087F1
Field_Unk87F1:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Map_BuildColXInc1
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer2
    BNE .layer3
    LDA.w !Map_Unk0BC9
    BPL .layer2_full
    JSR Map_BuildColXInc2Half
    BRA .layer3
.layer2_full:
    JSR Map_BuildColXInc2
.layer3:
    LDA.b !Map_LayerEdgeOff-!DP_Map
    BIT.b #!Map_Layer3
    BNE .finish
    JSR Map_BuildColXInc3
.finish:
    JSR Sub_C07F9A
    PLD
    RTS

; ============================================================
; $C0:B192 — Obj_ResetStates (32 bytes, $B192–$B1B1)
; (was Sub_B192.) Clears Obj_State for every object the location
; defines (count in Evt_ObjCount), pointing DP at the Obj_State table
; so each clear is a 2-byte dp store, then tail-jumps to SprBuf_FreeAll
; (which marks every SprBuf_Owner entry free). Called at the end of
; every reload. The DEC/BNE count assumes Evt_ObjCount >= 1: a count of
; 0 would run 256 times, with the 8-bit Y wrapping round the page.
; Callers (4 JSR sites): GameLoop_LoadField ($C0:008B),
;   Field_SceneChangeTick ($C0:0D30), Field_PauseAndMenuInput ($C0:197B) and
;   Field_RunBankC2Mode5 ($C0:19F9).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; Exit (from SprBuf_FreeAll, BRL tail call): M=1, X=0, DP restored to
; $0100 (PLD), DB unchanged; A = Obj_None, X = 0, Y = 2 x count (low
; byte).
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
; $C0:B1B2 — VramQ_Flush (82 bytes, $B1B2–$B203)
; Uploads every pending entry of the VRAM upload queue (VramQ_*, filled
; by Obj_BuildFrame4, Obj_BuildFrame8, Obj_BuildFrame8Pass1,
; Obj_BuildFrame12Pass2 and Obj_BuildFrame12Pass2Alt) with DMA channel 7, two transfers per
; entry (the A and B halves), then marks the queue empty. Entries are
; walked 2 bytes at a time from the first until one whose VramQ_Valid
; low byte is 0; only the first entry's VramQ_Valid is cleared at the
; end, which is enough for Field_ProcessAnimQueue (it tests only that
; one). The channel 7 setup before the loop (VMAIN, BBAD7, DMAP7, A1B7)
; is the same 22 bytes (counting its SEP #$20) as in Spr_LoadLargeObj; every source is in bank
; $7F.
; Callers (2 JSR sites, unmatched): $C0:EB8C in NmiHandler (which sets
;   DP=$1D00 right after) and $C0:B111 (inside PHD/PLD, with REP #$10
;   before it).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y: the queue words are
; loaded into Y), DP any (set to DP_VramQ here), DB=$00 (absolute PPU
; and DMA register stores).
; Exit: M=1, X=0, DB unchanged; DP left at DP_VramQ ($0900), not
; restored; A = 0, X = 2 x entries uploaded, Y clobbered.
; ============================================================
org $C0B1B2
VramQ_Flush:
    REP #$20                ; A → 16-bit
    LDA.w #!DP_VramQ
    TCD                     ; DP = $0900: the queue is reached with dp loads
    SEP #$20                ; A → 8-bit
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!Bank7F
    STA.w A1B7              ; every source is in bank $7F
    LDX.w #$0000
.entry_loop:
    LDA.b !VramQ_Valid-!DP_VramQ,X
    BEQ .done               ; end of the queue
    LDY.b !VramQ_DestA-!DP_VramQ,X
    STY.w VMADDL
    LDY.b !VramQ_SrcA-!DP_VramQ,X
    STY.w A1T7L
    LDY.b !VramQ_SizeA-!DP_VramQ,X
    STY.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN            ; first half
    LDY.b !VramQ_DestB-!DP_VramQ,X
    STY.w VMADDL
    LDY.b !VramQ_SrcB-!DP_VramQ,X
    STY.w A1T7L
    LDY.b !VramQ_SizeB-!DP_VramQ,X
    STY.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN            ; second half
    INX
    INX
    BRA .entry_loop
.done:
    STZ.b !VramQ_Valid-!DP_VramQ ; queue empty
    RTS

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
; The global labels inside are this routine's loop points, not separate
; entries (nothing outside branches to them): Oam_BucketLoop,
; Oam_CheckChain, Oam_NextBucket, Oam_HideRange1, Oam_EndRange1,
; Oam_HideRange2, Oam_EndRange2, Oam_HideRange3 and Oam_EndRange3.
;
; Callers: BRL tail calls from Field_EndOfFrame ($C0:00DB) and from
; the unmatched routine at $C0:B0E6 ($C0:B124; that routine is called by
; Scene_ReloadStep), and a JSR from unmatched code at $C0:072B. On the
; tail calls the RTS returns to that routine's caller.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00 (the
; absolute stores to OamEntry and WMADDH need bank $00).
; Exit: M=1, X=0, DP and DB unchanged; A = Oam_HiddenY, X =
; Oam_Range3LoPtr, Y = $FFFE; Obj_Cur = the last object drawn.
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
Oam_BucketLoop:             ; one Obj_DrawBucket entry; header: see Oam_BuildShadow
    LDA.w !Obj_DrawBucket,Y
    BMI Oam_NextBucket       ; bit 7: empty bucket
    STA.b !Obj_Cur          ; first object in the bucket
    JSR Spr_AppendToOam
Oam_CheckChain:             ; header: see Oam_BuildShadow
    LDX.b !Obj_Cur
    LDA.w !Obj_DrawNext,X   ; next object in the same bucket
    BMI Oam_NextBucket
    STA.b !Obj_Cur
    JSR Spr_AppendToOam
    BRA Oam_CheckChain
Oam_NextBucket:             ; header: see Oam_BuildShadow
    DEY
    DEY
    BPL Oam_BucketLoop
    LDX.b !Oam_Range1LoPtr
    LDA.b #!Oam_HiddenY     ; Y=$E0 parks the entry below the screen
Oam_HideRange1:             ; header: see Oam_BuildShadow
    CPX.b !Oam_Range1PrevEnd
    BCS Oam_EndRange1
    STA.w OamEntry.Y,X        ; X = entry address
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range1Limit
    BCC Oam_HideRange1
Oam_EndRange1:              ; header: see Oam_BuildShadow
    LDX.b !Oam_Range1LoPtr
    STX.b !Oam_Range1PrevEnd
    LDX.b !Oam_Range2LoPtr
Oam_HideRange2:             ; header: see Oam_BuildShadow
    CPX.b !Oam_Range2PrevEnd
    BCS Oam_EndRange2
    STA.w OamEntry.Y,X
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range2Limit
    BCC Oam_HideRange2
Oam_EndRange2:              ; header: see Oam_BuildShadow
    LDX.b !Oam_Range2LoPtr
    STX.b !Oam_Range2PrevEnd
    LDX.b !Oam_Range3LoPtr
Oam_HideRange3:             ; header: see Oam_BuildShadow
    CPX.b !Oam_Range3PrevEnd
    BCS Oam_EndRange3
    STA.w OamEntry.Y,X
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range3Limit
    BCC Oam_HideRange3
Oam_EndRange3:              ; header: see Oam_BuildShadow
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
; Callers (5 JSR sites): ModeE6_Handler ($C0:0D92), ModeEC_Handler
;   ($C0:0E8F), ModeEE_Handler ($C0:1040), ModeFA_Handler ($C0:1212) and
;   ModeFC_Handler ($C0:149D).
; On entry: M=1 (A=8-bit), X/Y=16-bit, DP=$0100 (Audio_SfxTileAnimA
; and Party_ObjSlot are dp), DB=$00; at Audio_PlaySfxAtLeader, A =
; effect id.
; Exit (both entries): M=1, X/Y 16-bit, DP and DB unchanged; A and Y
; clobbered (Y = the leader's object), and whatever Audio_DriverCommand
; (unmatched) changes.
; ============================================================
org $C01B90
Audio_PlayTileSfxA:
    LDA.b !Audio_SfxTileAnimA
; Audio_PlaySfxAtLeader: shared tail; Audio_PlayTileSfxA falls in here
; and Audio_PlayTileSfxB branches here (BRA at $C0:1BA9).
; On entry: A = effect id, M=1, X/Y 16-bit, DP=$0100, DB=$00.
; Exit: M=1, X/Y 16-bit, DP and DB unchanged; A and Y clobbered (Y = the
; leader's object), and whatever Audio_DriverCommand (unmatched) changes.
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
; Field event hooks: window effects ($C0:21E1–$C0:274C)
;
; Field_EventHook (dp $39) names a per-frame job; 0 = none. Hooks 1-10
; and 12 drive a window (masking) effect (hook 11 leaves the field for
; bank $C3; 13 is idle, 14 is hook 5's shutdown tail, 15-16 unused):
; each sets the window and
; colour-math shadows the NMI handler copies to the PPU
; (Ppu_W12SelShadow .. Ppu_CgwSelShadow), turns on an HDMA channel
; (5, or 7 for hook 3) in Field_HdmaEnable, and has a bank-$C3 routine
; build the shape: BankC3_Entry0008 from WinFx_ArgX/Y/Size (hooks
; 1, 2, 4, 5, 7-10 and 12), BankC3_Entry000E (hook 3) or BankC3_Entry0011
; from four moving points (hook 6). The shapes those routines draw
; are not traced, so the handlers keep neutral names. Field_EventHook
; and WinFx_* are set by unmatched code at $C0:3FA9-$C0:41D8 and
; $C0:A4C4-$C0:A4F3 (not traced).
; ============================================================

; ------------------------------------------------------------
; $C0:21E1 — Field_EventHookDispatch (13 bytes, $21E1–$21ED)
; Runs the Field_EventHook handler for this frame: entry
; Field_EventHook - 1 of Field_EventHookTable; nothing when it is 0.
; Callers: GameLoop_FrameBody ($C0:00B1), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A and X clobbered, plus whatever
; the handler changes (see each).
; ------------------------------------------------------------
org $C021E1
Field_EventHookDispatch:
    TDC                     ; A = 0 (DP's low byte), so XBA clears B
    XBA
    LDA.b !Field_EventHook
    BEQ .done
    DEC A
    ASL A
    TAX
    JSR (Field_EventHookTable,X)
.done:
    RTS

; Field_EventHookTable: 16 handler addresses, indexed by
; (Field_EventHook - 1) x 2. Entries 7/8 and 9/10 share a handler that
; runs two frames (the first moves the hook on to the second); 13 is a
; bare RTS (the last byte of Field_HookWinC3E, hook 3) that hook 12 leaves set; 14
; is the shutdown tail of hook 5. 15 and 16 point at Evt_UnusedOpcode,
; the event interpreter's handler for unused opcodes.
Field_EventHookTable:
    dw Field_HookWinGrow0           ; 1
    dw Field_HookWinShrink0         ; 2
    dw Field_HookWinC3E             ; 3
    dw Field_HookWinGrow1           ; 4
    dw Field_HookWinShrink1         ; 5
    dw Field_HookWinQuad            ; 6
    dw Field_HookWinFixedA          ; 7
    dw Field_HookWinFixedA          ; 8
    dw Field_HookWinFixedB          ; 9
    dw Field_HookWinFixedB          ; 10
    dw Field_HookLeaveToBankC3      ; 11
    dw Field_HookWinPulse           ; 12
    dw Field_HookIdle               ; 13
    dw Field_HookWinShrink1_Off     ; 14
    dw Evt_UnusedOpcode             ; 15
    dw Evt_UnusedOpcode             ; 16

; ------------------------------------------------------------
; $C0:220E — Field_HookWinGrow0 (91 bytes, $220E–$2268)
; Hook 1: one frame of a growing window shape. Enables window 1 on BG1
; and BG2, HDMA channel 5 and the layer bytes Hdma_Unk7F1522/1523, then
; has BankC3_Entry0008 (mode 0) build the table for centre
; WinFx_CenterX/Y and size WinFx_Size into WinFx_TableA or WinFx_TableB
; (by Field_Unk53), and counts WinFx_Size up. Once WinFx_Size reaches
; WinFx_SizeLimit it clears Field_EventHook and draws a last frame one
; size smaller, so WinFx_Size ends at the limit again.
; Reached only through Field_EventHookTable (entry 1).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered (and whatever
; BankC3_Entry0008 changes; it saves P, DP and DB).
; ------------------------------------------------------------
Field_HookWinGrow0:
    LDA.b !WinFx_Size
    CMP.b !WinFx_SizeLimit
    BCS .done
.draw:
    LDA.b #!Layer_Bg123Obj
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #!W12SEL_Bg12Win1
    STA.w !Ppu_W12SelShadow
    LDA.b #$00
    STA.w !Ppu_W34SelShadow
    STA.w !Ppu_WObjSelShadow
    LDA.b !WinFx_CenterX
    STA.w !WinFx_ArgX
    LDA.b !WinFx_CenterY
    STA.w !WinFx_ArgY
    LDA.b !WinFx_Size
    STA.w !WinFx_ArgSize
    LDA.b #!HDMAEN_Ch5
    TSB.b !Field_HdmaEnable
    LDA.b !Field_Unk53
    BEQ .table_b
    LDX.w #!WinFx_TableA
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
    BRA .build
.table_b:
    LDX.w #!WinFx_TableB
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
.build:
    LDA.b #!WinFx_Mode0
    JSL BankC3_Entry0008
    INC.b !WinFx_Size
    RTS
.done:
    STZ.b !Field_EventHook
    DEC.b !WinFx_Size
    BRA .draw

; ------------------------------------------------------------
; $C0:2269 — Field_HookWinShrink0 (111 bytes, $2269–$22D7)
; Hook 2: the reverse of hook 1. While WinFx_Size is nonzero, counts it
; down and draws the shape as hook 1 does (mode 0); at 0 it clears
; Field_EventHook, the layer bytes and the three window-select shadows,
; and turns HDMA channel 5 off.
; Reached only through Field_EventHookTable (entry 2).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered.
; ------------------------------------------------------------
Field_HookWinShrink0:
    LDA.b !WinFx_Size
    BEQ .off
    DEC.b !WinFx_Size
    LDA.b #!Layer_Bg123Obj
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #!W12SEL_Bg12Win1
    STA.w !Ppu_W12SelShadow
    LDA.b #$00
    STA.w !Ppu_W34SelShadow
    STA.w !Ppu_WObjSelShadow
    LDA.b !WinFx_CenterX
    STA.w !WinFx_ArgX
    LDA.b !WinFx_CenterY
    STA.w !WinFx_ArgY
    LDA.b !WinFx_Size
    STA.w !WinFx_ArgSize
    LDA.b #!HDMAEN_Ch5
    TSB.b !Field_HdmaEnable
    LDA.b !Field_Unk53
    BEQ .table_b
    LDX.w #!WinFx_TableA
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
    BRA .build
.table_b:
    LDX.w #!WinFx_TableB
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
.build:
    LDA.b #!WinFx_Mode0
    JSL BankC3_Entry0008
    RTS
.off:
    STZ.b !Field_EventHook
    LDA.b #$00
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #$00
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_W34SelShadow
    STA.w !Ppu_WObjSelShadow
    LDA.b #!HDMAEN_Ch5
    TRB.b !Field_HdmaEnable
    RTS

; ------------------------------------------------------------
; $C0:22D8 — Field_HookWinC3E (82 bytes, $22D8–$2329)
; Hook 3. While WinFx_Busy (the bank-$C3 work byte at $0350) is
; nonzero: window 2 on every layer and the colour window, window 2
; spanning the whole line (WH2 = 0, WH3 = 255), one step of
; BankC3_Entry000E, HDMA channel 7 on and full brightness. Once
; BankC3_Entry000E has cleared WinFx_Busy, and only if WinFx_Size < 2,
; it clears the layer bytes, the window shadows and channel 7. It never
; clears Field_EventHook itself; other code must (not traced).
; Hdma_InitChannelsFD points channel 7 at WH2 or WH3 by WinFx_Size bit
; 0, which may be why WinFx_Size is tested here.
; Field_HookIdle (hook 13) is this routine's last byte, its RTS.
; Reached only through Field_EventHookTable (entry 3).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A clobbered (and whatever
; BankC3_Entry000E changes; it saves P, DP and DB).
; ------------------------------------------------------------
Field_HookWinC3E:
    LDA.w !WinFx_Busy
    BEQ .finished
    LDA.b #!Layer_Bg123Obj
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #!WSEL_BothWin2
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_W34SelShadow
    STA.w !Ppu_WObjSelShadow
    STZ.w !Ppu_Wh2Shadow
    LDA.b #!WH_RightEdge
    STA.w !Ppu_Wh3Shadow
    JSL BankC3_Entry000E
    LDA.b #!HDMAEN_Ch7
    TSB.b !Field_HdmaEnable
    LDA.b #!Fade_BrightnessMax
    STA.b !Fade_Brightness
    RTS
.finished:
    LDA.b !WinFx_Size
    CMP.b #!WinFx_Hook3SizeMin
    BCS Field_HookIdle
    LDA.b #$00
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #$00
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_W34SelShadow
    STA.w !Ppu_WObjSelShadow
    STA.w !Ppu_Wh3Shadow
    LDA.b #!HDMAEN_Ch7
    TRB.b !Field_HdmaEnable
Field_HookIdle:             ; header: see Field_HookWinC3E
    RTS

; ------------------------------------------------------------
; $C0:232A — Field_HookWinGrow1 (96 bytes, $232A–$2389)
; Hook 4: hook 1 with the colour window instead of BG windows:
; WOBJSEL enables colour window 1, CGWSEL limits colour math to inside
; the window (with the sub screen added), and BankC3_Entry0008 runs in
; mode 1. WinFx_Size counts up to WinFx_SizeLimit as in hook 1.
; Reached only through Field_EventHookTable (entry 4).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered.
; ------------------------------------------------------------
Field_HookWinGrow1:
    LDA.b !WinFx_Size
    CMP.b !WinFx_SizeLimit
    BCS .done
.draw:
    LDA.b #!Layer_Bg123Obj
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #$00
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_W34SelShadow
    LDA.b #!WOBJSEL_ColorWin1
    STA.w !Ppu_WObjSelShadow
    LDA.b #!CGWSEL_MathInWin
    STA.w !Ppu_CgwSelShadow
    LDA.b !WinFx_CenterX
    STA.w !WinFx_ArgX
    LDA.b !WinFx_CenterY
    STA.w !WinFx_ArgY
    LDA.b !WinFx_Size
    STA.w !WinFx_ArgSize
    LDA.b #!HDMAEN_Ch5
    TSB.b !Field_HdmaEnable
    LDA.b !Field_Unk53
    BEQ .table_b
    LDX.w #!WinFx_TableA
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
    BRA .build
.table_b:
    LDX.w #!WinFx_TableB
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
.build:
    LDA.b #!WinFx_Mode1
    JSL BankC3_Entry0008
    INC.b !WinFx_Size
    RTS
.done:
    STZ.b !Field_EventHook
    DEC.b !WinFx_Size
    BRA .draw

; ------------------------------------------------------------
; $C0:238A — Field_HookWinShrink1 (127 bytes, $238A–$2408)
; Hook 5: the reverse of hook 4 (mode 1, colour window). At WinFx_Size
; 0 it falls into Field_HookWinShrink1_Off, which clears
; Field_EventHook, the layer bytes and window selects, puts CGWSEL back
; to its load value, resets Fade_FixedColor and its target to
; Fade_FixedColorInit and turns HDMA channel 5 off.
; Field_HookWinShrink1_Off is also hook 14 on its own.
; Reached only through Field_EventHookTable (entries 5 and 14).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered.
; ------------------------------------------------------------
Field_HookWinShrink1:
    LDA.b !WinFx_Size
    BEQ Field_HookWinShrink1_Off
    DEC.b !WinFx_Size
    LDA.b #!Layer_Bg123Obj
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #$00
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_W34SelShadow
    LDA.b #!WOBJSEL_ColorWin1
    STA.w !Ppu_WObjSelShadow
    LDA.b #!CGWSEL_MathInWin
    STA.w !Ppu_CgwSelShadow
    LDA.b !WinFx_CenterX
    STA.w !WinFx_ArgX
    LDA.b !WinFx_CenterY
    STA.w !WinFx_ArgY
    LDA.b !WinFx_Size
    STA.w !WinFx_ArgSize
    LDA.b #!HDMAEN_Ch5
    TSB.b !Field_HdmaEnable
    LDA.b !Field_Unk53
    BEQ .table_b
    LDX.w #!WinFx_TableA
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
    BRA .build
.table_b:
    LDX.w #!WinFx_TableB
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
.build:
    LDA.b #!WinFx_Mode1
    JSL BankC3_Entry0008
    RTS
Field_HookWinShrink1_Off:   ; header: see Field_HookWinShrink1
    STZ.b !Field_EventHook
    LDA.b #$00
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #$00
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_W34SelShadow
    STA.w !Ppu_WObjSelShadow
    LDA.b #!CGWSEL_AddSub
    STA.w !Ppu_CgwSelShadow
    LDA.b #!Fade_FixedColorInit
    STA.b !Fade_FixedColor
    STA.b !Fade_FixedColorTarget
    LDA.b #!HDMAEN_Ch5
    TRB.b !Field_HdmaEnable
    RTS

; ------------------------------------------------------------
; $C0:2409 — Field_HookWinQuad (267 bytes, $2409–$2513)
; Hook 6: a colour-window shape from four moving points, for
; WinFx_QuadTimer frames. Each frame it sets the colour window up as
; hook 4 does, copies the high bytes of the four WinFx_QuadPos X/Y words
; to WinFx_QuadPoints, has BankC3_Entry0011 build the table into
; WinFx_TableA or WinFx_TableB (address in WinFx_QuadTablePtr), then
; adds each point's WinFx_QuadVel. When the timer is 0 it clears
; Field_EventHook and the X velocities of the four points (the Y
; velocities are left alone; the clears are at +0, +4, +8, +12, X
; only) and draws one last frame.
; Reached only through Field_EventHookTable (entry 6).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered (and whatever
; BankC3_Entry0011 changes; it saves P, DP and DB).
; ------------------------------------------------------------
Field_HookWinQuad:
    LDA.l !WinFx_QuadTimer
    BEQ .last_frame
    DEC A
    STA.l !WinFx_QuadTimer
    BRA .draw
.last_frame:
    STZ.b !Field_EventHook
    REP #$20
    LDA.w #$0000
    STA.l !WinFx_QuadVel
    STA.l !WinFx_QuadVel+4
    STA.l !WinFx_QuadVel+8
    STA.l !WinFx_QuadVel+12
    SEP #$20
.draw:
    LDA.b #!Layer_Bg123Obj
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    LDA.b #$00
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_W34SelShadow
    LDA.b #!WOBJSEL_ColorWin1
    STA.w !Ppu_WObjSelShadow
    LDA.b #!CGWSEL_MathInWin
    STA.w !Ppu_CgwSelShadow
    ; WinFx_QuadPoints = X, Y (integer parts) of points 0-3
    LDA.l !WinFx_QuadPos+1
    STA.w !WinFx_QuadPoints
    LDA.l !WinFx_QuadPos+5
    STA.w !WinFx_QuadPoints+2
    LDA.l !WinFx_QuadPos+9
    STA.w !WinFx_QuadPoints+4
    LDA.l !WinFx_QuadPos+13
    STA.w !WinFx_QuadPoints+6
    LDA.l !WinFx_QuadPos+3
    STA.w !WinFx_QuadPoints+1
    LDA.l !WinFx_QuadPos+7
    STA.w !WinFx_QuadPoints+3
    LDA.l !WinFx_QuadPos+11
    STA.w !WinFx_QuadPoints+5
    LDA.l !WinFx_QuadPos+15
    STA.w !WinFx_QuadPoints+7
    LDA.b #!HDMAEN_Ch5
    TSB.b !Field_HdmaEnable
    LDA.b !Field_Unk53
    BEQ .table_b
    LDX.w #!WinFx_TableA
    STX.w !WinFx_QuadTablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_QuadTableBank
    BRA .build
.table_b:
    LDX.w #!WinFx_TableB
    STX.w !WinFx_QuadTablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_QuadTableBank
.build:
    JSL BankC3_Entry0011
    ; move the four points
    REP #$20
    LDA.l !WinFx_QuadPos
    CLC
    ADC.l !WinFx_QuadVel
    STA.l !WinFx_QuadPos
    LDA.l !WinFx_QuadPos+2
    CLC
    ADC.l !WinFx_QuadVel+2
    STA.l !WinFx_QuadPos+2
    LDA.l !WinFx_QuadPos+4
    CLC
    ADC.l !WinFx_QuadVel+4
    STA.l !WinFx_QuadPos+4
    LDA.l !WinFx_QuadPos+6
    CLC
    ADC.l !WinFx_QuadVel+6
    STA.l !WinFx_QuadPos+6
    LDA.l !WinFx_QuadPos+8
    CLC
    ADC.l !WinFx_QuadVel+8
    STA.l !WinFx_QuadPos+8
    LDA.l !WinFx_QuadPos+10
    CLC
    ADC.l !WinFx_QuadVel+10
    STA.l !WinFx_QuadPos+10
    LDA.l !WinFx_QuadPos+12
    CLC
    ADC.l !WinFx_QuadVel+12
    STA.l !WinFx_QuadPos+12
    LDA.l !WinFx_QuadPos+14
    CLC
    ADC.l !WinFx_QuadVel+14
    STA.l !WinFx_QuadPos+14
    SEP #$20
    RTS

; ------------------------------------------------------------
; $C0:2514 — Field_HookWinFixedA (117 bytes, $2514–$2588)
; Hooks 7 and 8: a fixed shape (centre WinFx_FixedX/Y, size
; WinFx_FixedSizeA, mode 0) on BG3's window 1, inverted; colour math
; outside the window only. Also sets Map_Unk1D8D/1D8F/1D91 to fixed
; values (meaning unknown). Runs two frames: hook 7 moves on to 8, and
; hook 8 clears Field_EventHook (inferred: so that both buffers,
; WinFx_TableA and WinFx_TableB, get the table). The window stays on;
; nothing here turns it off.
; Reached only through Field_EventHookTable (entries 7 and 8).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered.
; ------------------------------------------------------------
Field_HookWinFixedA:
    LDA.b #!Layer_Bg123Obj
    STA.l !Hdma_Unk7F1522
    LDA.b #$00
    STA.l !Hdma_Unk7F1523
    LDA.b #$00
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_WObjSelShadow
    LDA.b #!W34SEL_Bg3Win1Inv
    STA.w !Ppu_W34SelShadow
    LDA.b #!CGWSEL_MathOutWin
    STA.w !Ppu_CgwSelShadow
    LDA.b #!WinFx_FixedX
    STA.w !WinFx_ArgX
    LDA.b #!WinFx_FixedY
    STA.w !WinFx_ArgY
    LDA.b #!WinFx_FixedSizeA
    STA.w !WinFx_ArgSize
    LDA.b #!HDMAEN_Ch5
    TSB.b !Field_HdmaEnable
    REP #$20
    LDA.w #!Map_Unk1D8DFixed
    STA.w !Map_Unk1D8D
    LDA.w #!Map_Unk1D8FFixed
    STA.w !Map_Unk1D8F
    LDA.w #!Map_Unk1D91Fixed
    STA.w !Map_Unk1D91
    SEP #$20
    LDA.b !Field_Unk53
    BEQ .table_b
    LDX.w #!WinFx_TableA
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
    BRA .build
.table_b:
    LDX.w #!WinFx_TableB
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
.build:
    LDA.b #!WinFx_Mode0
    JSL BankC3_Entry0008
    LDA.b !Field_EventHook
    CMP.b #!EventHook_WinFixedA1
    BNE .second_frame
    INC.b !Field_EventHook
    RTS
.second_frame:
    STZ.b !Field_EventHook
    RTS

; ------------------------------------------------------------
; $C0:2589 — Field_HookWinFixedB (133 bytes, $2589–$260D)
; Hooks 9 and 10: as hooks 7/8 with size WinFx_FixedSizeB, window 1 on
; BG2 and BG3 (not inverted), and different layer and colour-math
; bytes: Ppu_Unk0BD7/Hdma_Unk7F1520 = BG3, Ppu_Unk0BD8/Hdma_Unk7F1521 =
; BG1+BG2+OBJ, Ppu_Unk0BDF/Ppu_Unk0BE0 = 4. Only Map_Unk1D8D is set.
; Two frames, as hooks 7/8.
; Reached only through Field_EventHookTable (entries 9 and 10).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered.
; ------------------------------------------------------------
Field_HookWinFixedB:
    LDA.b #!Layer_Bg123Obj
    STA.l !Hdma_Unk7F1522
    LDA.b #$00
    STA.l !Hdma_Unk7F1523
    LDA.b #!W12SEL_Bg2Win1
    STA.w !Ppu_W12SelShadow
    LDA.b #$00
    STA.w !Ppu_WObjSelShadow
    LDA.b #!W34SEL_Bg3Win1
    STA.w !Ppu_W34SelShadow
    LDA.b #!CGWSEL_MathOutWin
    STA.w !Ppu_CgwSelShadow
    LDA.b #!Ppu_Unk0BDFHook9
    STA.w !Ppu_Unk0BDF
    STA.w !Ppu_Unk0BE0
    LDA.b #!Layer_Bg3
    STA.w !Ppu_Unk0BD7
    STA.l !Hdma_Unk7F1520
    LDA.b #!Layer_Bg12Obj
    STA.w !Ppu_Unk0BD8
    STA.l !Hdma_Unk7F1521
    REP #$20
    LDA.w #!Map_Unk1D8DFixed
    STA.w !Map_Unk1D8D
    SEP #$20
    LDA.b #!WinFx_FixedX
    STA.w !WinFx_ArgX
    LDA.b #!WinFx_FixedY
    STA.w !WinFx_ArgY
    LDA.b #!WinFx_FixedSizeB
    STA.w !WinFx_ArgSize
    LDA.b #!HDMAEN_Ch5
    TSB.b !Field_HdmaEnable
    LDA.b !Field_Unk53
    BEQ .table_b
    LDX.w #!WinFx_TableA
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
    BRA .build
.table_b:
    LDX.w #!WinFx_TableB
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
.build:
    LDA.b #!WinFx_Mode0
    JSL BankC3_Entry0008
    LDA.b !Field_EventHook
    CMP.b #!EventHook_WinFixedB1
    BNE .second_frame
    INC.b !Field_EventHook
    RTS
.second_frame:
    STZ.b !Field_EventHook
    RTS

; ------------------------------------------------------------
; $C0:260E — Field_HookLeaveToBankC3 (65 bytes, $260E–$264E)
; Hook 11: leaves the field for good. Redraws the map as
; DefaultHandler's redraw mode 1 does (Field_BuildC800Mode1 with
; DP=$1D00, Field_Unk74D4, a frame with Field_MapRedrawDone = 1), runs
; Scene_Unk024C and one more frame, then turns HDMA off, sets
; Field_Unk0F to $80, resets the stack to StackTop and JMLs to
; BankC3_Entry0000 with A = BankC3_HookArg (B = 0). The first 23 bytes
; repeat DefaultHandler's mode-1 redraw ($C0:16DC+$C4).
; Reached only through Field_EventHookTable (entry 11).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: never returns (JML with a fresh stack).
; ------------------------------------------------------------
Field_HookLeaveToBankC3:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD                     ; DP = $1D00 for the builder
    SEP #$20
    JSR Field_BuildC800Mode1
    PLD
    JSR Field_Unk74D4
    JSR Field_EndOfFrameShort
    LDA.b #$01
    STA.b !Field_MapRedrawDone
    JSR Sub_EC60
    JSR Scene_Unk024C
    JSR Field_EndOfFrameShort
    JSR Sub_EC60
    LDA.b #!NMITIMEN_NmiJoy
    STA.l NMITIMEN
    LDA.b #$00
    STA.l HDMAEN
    LDA.b #!Field_Unk0FHook11
    STA.l !DP_Field+!Field_Unk0F
    LDX.w #!StackTop
    TXS
    TDC                     ; A = 0 (DP's low byte), so XBA clears B
    XBA
    LDA.b #!BankC3_HookArg
    JML BankC3_Entry0000

; ------------------------------------------------------------
; $C0:264F — Field_HookWinPulse (214 bytes, $264F–$2724)
; Hook 12, a blocking sequence that runs its own frames (each one
; Field_EndOfFrameShort + Sub_EC60, with no Field_FrameUpdate): redraws
; the map (Field_BuildC800Mode1, Field_Unk74E8/74F7, redraw step 2),
; sets Hdma_Unk7F1520/1522, Map_Unk1DFD and Hdma_Unk7F14F1/1523 and
; waits Hook12_WaitFrames frames; then puts window 1 on BG1 and BG2
; (centre WinFx_Hook12X/Y, mode $80 through Field_WinPulseDraw) and
; grows WinFx_Size by 2 a frame for Hook12_RampFrames frames, holds for
; Hook12_HoldFrames and shrinks it for Hook12_RampFrames. Then it sets
; Field_EventHook to EventHook_Idle, clears the window and layer bytes,
; ORs Map_TilemapVram4's high byte into Hdma_Unk7F14F1 and ends with
; one more frame (tail jump to Sub_EC60).
; Quirk kept: Map_Unk1DFD is cleared with a long store (STA.l $00:1DFD)
; though it was set with an absolute one.
; Reached only through Field_EventHookTable (entry 12).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit (through Sub_EC60): M=1, X=0, DP=$0100, DB=$00; A = 0, X and Y
; clobbered (the frame helpers do not preserve them).
; ------------------------------------------------------------
Field_HookWinPulse:
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD                     ; DP = $1D00 for the builder
    SEP #$20
    JSR Field_BuildC800Mode1
    PLD
    JSR Field_Unk74E8
    JSR Field_Unk74F7
    JSR Field_EndOfFrameShort
    LDA.b #$02
    STA.b !Field_MapRedrawDone
    LDA.b #!Layer_Bg12Obj
    STA.l !Hdma_Unk7F1520
    LDA.b #!Layer_Bg1Obj
    STA.l !Hdma_Unk7F1522
    STA.w !Map_Unk1DFD
    LDA.w !Map_TilemapVram3+1
    STA.l !Hdma_Unk7F14F1
    STA.l !Hdma_Unk7F1523
    LDA.b #!Hook12_WaitFrames
    STA.w !Map_HookTimer
    JSR Sub_EC60
.wait:
    JSR Field_EndOfFrameShort
    JSR Sub_EC60
    DEC.w !Map_HookTimer
    BNE .wait
    LDA.b #!W12SEL_Bg12Win1
    STA.w !Ppu_W12SelShadow
    LDA.b #$00
    STA.w !Ppu_W34SelShadow
    STA.w !Ppu_WObjSelShadow
    LDA.b #!WinFx_Hook12X
    STA.w !WinFx_ArgX
    LDA.b #!WinFx_Hook12Y
    STA.w !WinFx_ArgY
    LDA.b #!WinFx_Hook12Size
    STA.b !WinFx_Size
    LDA.b #!HDMAEN_Ch5
    TSB.b !Field_HdmaEnable
    LDA.b #!Hook12_RampFrames
    STA.w !Map_HookTimer
.grow:
    JSR Field_WinPulseDraw
    INC.b !WinFx_Size
    INC.b !WinFx_Size
    JSR Field_EndOfFrameShort
    JSR Sub_EC60
    DEC.w !Map_HookTimer
    BNE .grow
    LDA.b #!Hook12_HoldFrames
    STA.w !Map_HookTimer
.hold:
    JSR Field_WinPulseDraw
    JSR Field_EndOfFrameShort
    JSR Sub_EC60
    DEC.w !Map_HookTimer
    BNE .hold
    LDA.b #!Hook12_RampFrames
    STA.w !Map_HookTimer
.shrink:
    JSR Field_WinPulseDraw
    DEC.b !WinFx_Size
    DEC.b !WinFx_Size
    JSR Field_EndOfFrameShort
    JSR Sub_EC60
    DEC.w !Map_HookTimer
    BNE .shrink
    LDA.b #!EventHook_Idle
    STA.b !Field_EventHook
    LDA.b #$00
    STA.l !Map_Unk1DFD      ; long store to $00:1DFD (quirk; set above with STA.w)
    STA.l !Hdma_Unk7F1522
    STA.l !Hdma_Unk7F1523
    STA.w !Ppu_W12SelShadow
    STA.w !Ppu_W34SelShadow
    STA.w !Ppu_WObjSelShadow
    LDA.b #!HDMAEN_Ch5
    TRB.b !Field_HdmaEnable
    LDA.w !Map_TilemapVram3+1
    ORA.w !Map_TilemapVram4+1
    STA.l !Hdma_Unk7F14F1
    JSR Field_EndOfFrameShort
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

; ------------------------------------------------------------
; $C0:2725 — Field_WinPulseDraw (40 bytes, $2725–$274C)
; One frame of Field_HookWinPulse's shape: WinFx_Size to WinFx_ArgSize,
; table WinFx_TableA or WinFx_TableB by Field_Unk53, then
; BankC3_Entry0008 in mode $80 (WinFx_ArgX/Y were set by the caller).
; Callers: Field_HookWinPulse ($C0:26BA, $C0:26D1, $C0:26E4).
; On entry: M=1, X=0, DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A, X clobbered.
; ------------------------------------------------------------
Field_WinPulseDraw:
    LDA.b !WinFx_Size
    STA.w !WinFx_ArgSize
    LDA.b !Field_Unk53
    BEQ .table_b
    LDX.w #!WinFx_TableA
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
    BRA .build
.table_b:
    LDX.w #!WinFx_TableB
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7F
    STA.w !WinFx_TableBank
.build:
    LDA.b #!WinFx_Mode80
    JSL BankC3_Entry0008
    RTS

; ============================================================
; $C0:274D — Field_ServiceUnk54 (215 bytes, $274D–$2823)
; (was Field_Unk274D.) Per-frame service of the Field_Unk54 requests,
; first match wins:
; - bit 4 (Field54_Credits): build the next line of the staff credits.
;   The line buffer Credits_LineBuf is cleared with 64 zero bytes (two
;   MVN copies of the 32 zero bytes at GfxRom_D2), then filled through
;   WMDATA with one tilemap word per character of Credits_Text from
;   Credits_TextPos: space -> tile 0, '.' -> tile $1B, other bytes - $40
;   (so 'A' -> 1), all with attribute byte Credits_TileAttr. A '/' ends
;   the line; Field_ServiceUnk54_SendLine then stores the position past
;   it, aims the upload at VRAM Credits_TilemapVram + row x 32 + column
;   (row = Credits_Row bits 0-5, column = Credits_Column bits 0-4) for
;   the rest of the row ($40 - 2 x column bytes), counts Credits_Row up
;   and sets Field_MapRedrawDone bit 5, so the NMI sends it
;   (its routine at $C0:EC77). A byte >= $80 ends the block: bit 4 is
;   cleared, the line sent, and Credits_Row counted once more (a blank
;   line). The text at Credits_Text ("PRODUCER//KAZUHIKO AOKI"...) is
;   what identifies this as the staff credits.
; - bit 2 or 3 (Field54_MapReq): copies them, shifted left once, into
;   Field_MapRedrawDone bits 3-4 (which the NMI handler acts on), runs
;   Map_ClearBufC800 and clears them.
; - bit 5 (Field54_WatchBox): sets Field_Unk29 to $0D
;   (Field_Unk29State0D) unless Map_TileOriginX / 2 < Field_TileStepX
;   <= Map_Unk1D0C / 2 and Map_TileOriginY / 2 < Field_TileStepY <=
;   Map_Unk1D10 / 2. The bounds are the low bytes of 16-bit variables.
;   What state $0D does is not traced.
; Callers: GameLoop_FrameBody ($C0:00B4), its only JSR site. The
; sub-entry Field_ServiceUnk54_SendLine is reached by BEQ and by the
; JSR at $C0:27E4, both inside this routine.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A clobbered; X and Y clobbered
; on the credits path (Y by the MVNs), and by Map_ClearBufC800 on bits
; 2-3. DB is saved around the MVNs.
; ============================================================
org $C0274D
Field_ServiceUnk54:
    LDA.b !Field_Unk54
    BIT.b #!Field54_AnyWork
    BNE .work
    BIT.b #!Field54_WatchBox
    BNE .watch_box
    RTS
.watch_box:
    LDA.w !Map_TileOriginX
    LSR A
    CMP.b !Field_TileStepX
    BCS .outside
    LDA.w !Map_Unk1D0C
    LSR A
    CMP.b !Field_TileStepX
    BCC .outside
    LDA.w !Map_TileOriginY
    LSR A
    CMP.b !Field_TileStepY
    BCS .outside
    LDA.w !Map_Unk1D10
    LSR A
    CMP.b !Field_TileStepY
    BCC .outside
    RTS
.outside:
    LDA.b #!Field_Unk29State0D
    STA.b !Field_Unk29
    RTS
.work:
    BIT.b #!Field54_Credits
    BNE .credits
    AND.b #!Field54_MapReq
    ASL A
    TSB.b !Field_MapRedrawDone
    JSR Map_ClearBufC800
    LDA.b #!Field54_MapReq
    TRB.b !Field_Unk54
    RTS
.credits:
    ; clear Credits_LineBuf: 2 x 32 zero bytes from the start of bank $D2
    REP #$20
    PHB
    LDX.w #!GfxRom_D2&$FFFF
    LDY.w #!Credits_LineBuf&$FFFF
    LDA.w #!Credits_ClearCount
    MVN !Bank7E,!BankD2     ; $D2:0000 -> $7E:D800  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #!GfxRom_D2&$FFFF
    LDA.w #!Credits_ClearCount
    MVN !Bank7E,!BankD2     ; $D2:0000 -> $7E:D820  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    LDX.w #!Credits_LineBuf&$FFFF
    STX.w WMADDL
    LDA.b #$00
    STA.w WMADDH            ; WRAM $7E:D800
    LDX.w !Credits_TextPos
.next_char:
    LDA.l !Credits_Text,X
    BMI .end_block
    CMP.b #!Credits_EndLine
    BEQ Field_ServiceUnk54_SendLine
    CMP.b #!Credits_Period
    BEQ .period
    CMP.b #!Credits_Space
    BNE .letter
    LDA.b #!Credits_TileSpace
    BRA .put
.period:
    LDA.b #!Credits_TilePeriod
    BRA .put
.letter:
    SEC
    SBC.b #!Credits_LetterBias
.put:
    STA.w WMDATA
    LDA.b #!Credits_TileAttr
    STA.w WMDATA
    INX
    BRA .next_char
.end_block:
    LDA.b #!Field54_Credits
    TRB.b !Field_Unk54
    JSR Field_ServiceUnk54_SendLine
    INC.w !Credits_Row      ; one blank line after the block
    RTS

Field_ServiceUnk54_SendLine: ; header: see Field_ServiceUnk54
    INX                     ; past the '/' (or the end byte)
    STX.w !Credits_TextPos
    LDA.w !Credits_Column
    REP #$20
    AND.w #!Credits_ColMask
    STA.b !Eng_Scratch      ; column
    LDA.w !Credits_Row
    AND.w #!Credits_RowMask
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A                   ; row x 32
    CLC
    ADC.b !Eng_Scratch
    CLC
    ADC.w #!Credits_TilemapVram
    STA.w !Credits_VramAddr
    LDA.w #!Credits_LineBytes
    SEC
    SBC.b !Eng_Scratch
    SEC
    SBC.b !Eng_Scratch      ; bytes from the column to the end of the row
    STA.w !Credits_DmaSize
    SEP #$20
    INC.w !Credits_Row
    LDA.b #!MapRedraw_CreditsLine
    TSB.b !Field_MapRedrawDone
    RTS

; ============================================================
; $C0:2824 — Field_FadeInAfterReload (36 bytes, $2824–$2847)
; (was Sub_2824.) Fade-in after a reload: unless Scene_ReloadStep
; returns nonzero, raises Fade_Brightness one step per frame (input
; disabled around Field_FrameUpdate) until it reaches full brightness.
; Clears Field_Unk1E and Field_FadeBusy on exit. Tail of
; Field_SceneChangeTick's reload path; also called after the
; bank-$C2 round trips.
; Callers (3 sites: 1 BRL, 2 JSR): Field_SceneChangeTick ($C0:0D3B),
;   Field_PauseAndMenuInput ($C0:197E) and Field_RunBankC2Mode5 ($C0:19FC).
; On entry: M=1 (A=8-bit), X/Y=16-bit, DP=$0100 (Fade_Brightness,
; Field_ControlEnabled and Field_Unk1E are dp), DB=$00.
; Exit: M=1, X/Y 16-bit, DP and DB unchanged (as the unmatched callees
; leave them); A, X and Y clobbered (Scene_ReloadStep,
; Field_FrameUpdate and Sub_EC60).
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
; $C0:2848 — Scene_SettleFrames (36 bytes, $2848–$286B)
; The field-load fade-in: a copy of Field_FadeInAfterReload just before
; it, differing in one call. Runs Scene_ReloadStep once; if that returns
; zero, raises Fade_Brightness one step per frame (input disabled around
; Field_FrameUpdate) until it reaches full brightness. Each frame runs the
; full Field_EndOfFrame (including Field_ProcessAnimQueue and the OAM
; shadow build) where the sibling runs only Field_EndOfFrameShort,
; presumably so objects are drawn while the screen fades in. Clears
; Field_Unk1E and Field_FadeBusy on exit.
; Callers: GameLoop_LoadField ($C0:0094), after the location load.
; On entry: M=1 (A=8-bit), X/Y=16-bit, DP=$0100 (Fade_Brightness,
; Field_ControlEnabled and Field_Unk1E are dp; GameLoop_LoadField sets
; it), DB=$00.
; Exit: M=1, X/Y 16-bit, DP and DB unchanged (as the callees leave them);
; A, X, Y and Obj_Cur clobbered (Scene_ReloadStep, Field_FrameUpdate,
; Field_EndOfFrame and Sub_EC60).
; ============================================================
org $C02848
Scene_SettleFrames:
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
    JSR Field_EndOfFrame
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
; On entry: M=1 (A 8-bit), X/Y 16-bit, DP=$0100, DB=$00 (Pad_Pressed,
; Pad_Unk00F6 and Field_FadeBusy are absolute).
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
; Exit: M=1, X/Y 16-bit, DP=$0100, DB=$00 (the menu path runs InitHW
; again); A, X and Y clobbered.
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
; Field_FadeToBankC2Mode5.
; On entry: M=1 (A=8-bit), X/Y=16-bit, DP=$0100: TDC/XBA clears B
; only because DP's low byte is 0. DB=$00 from both callers (InitHW
; sets it again after the bank-$C2 call).
; Exit: M=1, X/Y 16-bit, DP=$0100 (set again after the bank-$C2 call),
; DB=$00 (InitHW); A, X and Y clobbered.
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
; read them as palette colours). Only in that case does it then put the
; party members back where Field_SaveState left them (SceneSave_Party*)
; and restore Field_UnkAB-AD — the second half of Field_SaveState's
; work. When the party is unchanged it returns at once and restores
; neither.
; Callers (JSR): Field_PauseAndMenuInput ($C0:1978) and Field_RunBankC2Mode5
;   ($C0:19E6).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A clobbered; on the changed path
; X, Y and Obj_Cur clobbered too.
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
; $C0:1AAC — Field_ActionButton (51 bytes, $1AAC–$1ADE)
; (was Field_Unk1AAC.) Per-frame check of the action button: does
; nothing unless Pad_Unk00F6 bit 7 (A, if Pad_Unk00F6 has the
; Pad_Pressed layout) is set. Field_Unk34 = $FFFF swallows that one
; press (Field_Unk34 goes back to 0); with player control off
; (Field_ControlEnabled = 0) it returns too. Otherwise: unless
; Field_UnkEB already names an object, Field_FindObjInFront looks for
; one near the leader in the facing direction (A = Obj_Facing x 2) and
; stores it there; if there is one, Evt_StartTargetFunc1 starts that
; object's function 1 (with 8-bit X/Y). Every path past the control
; check ends in Field_CheckTileInFront (tail BRL), so the tile check
; runs whether or not an object was found.
; Field_FrameUpdate resets Field_UnkEB to $80 each frame before this
; runs; what may set it in between is not traced.
; Callers: GameLoop_FrameBody ($C0:00AA), its only JSR site.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, DB=$00.
; Exit: M=1, X=0, DP and DB unchanged; A and X clobbered, plus what the
; callees change (Field_CheckTileInFront returns to this routine's
; caller).
; ============================================================
org $C01AAC
Field_ActionButton:
    LDA.w !Pad_Unk00F6
    BIT.b #!Pad_Unk00F6Bit7
    BNE .pressed
    RTS
.pressed:
    LDX.b !Field_Unk34
    BEQ .check_control
    CPX.w #!Field_Unk34Swallow
    BNE .check_control
    INX                     ; $FFFF -> 0: this press is swallowed
    STX.b !Field_Unk34
    RTS
.check_control:
    LDA.b !Field_ControlEnabled
    BNE .control_on
    RTS
.control_on:
    LDA.b !Field_UnkEB
    BPL .activate           ; an object is already targeted
    LDX.b !Party_ObjSlot
    LDA.w !Obj_Facing,X
    ASL A
    JSR Field_FindObjInFront
    BCC .tile_check         ; C=0: nothing in front
.activate:
    SEP #$30
    JSR Evt_StartTargetFunc1
    REP #$10
.tile_check:
    BRL Field_CheckTileInFront

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
; Exit: M=1, X=0; A = 0, X = offset of the closing $00, Obj_Cur = 0
; (16-bit); Y and anything else are as the last opcode handler left them.
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
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100, Obj_Cur = object
; (Obj_CurHi 0).
; Exit: M=1, X=0; X = Obj_Cur, A = Obj_Unk1C00Init; Y and anything else
; are as the last opcode handler left them.
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
; $C0:5AC5 — Evt_StartTargetFunc1 (90 bytes, $5AC5–$5B1E)
; Starts function 1 of the object in Field_UnkEB (the one the action
; button found). It does nothing unless
; that object's Obj_Unk1C01 is 0, Obj_Unk1100 and Obj_Unk1000 have
; bit 7 clear and Obj_Unk1C00 is at least Obj_Unk1C00Min. Then it
; saves Obj_ScriptPos in the ObjX_Unk7F0580 table of level
; Obj_Unk1C00 (index level x Evt_PrioStride + slot, through the
; hardware multiplier), points Obj_ScriptPos at function 1 (the second
; word of the object's function table at Evt_Data + slot x 16), sets
; Obj_Unk1C00 = 1 and zeroes Obj_Unk1A80, Obj_Unk1A01 and Obj_Unk1001.
; Reading Obj_Unk1C00 as a priority level whose interrupted position is
; kept per level is an inference from this save; not established.
; The 16-bit loads of Field_UnkEB also take $01EC as the high byte;
; Field_FindObjInFront's 16-bit store keeps it 0.
; Callers: Field_ActionButton ($C0:1AD7), its only JSR site.
; On entry: M=1 (8-bit A), X=1 (8-bit X/Y), DP=$0100, DB=$00;
; Field_UnkEB = the object's slot (object x 2).
; Exit: M=1, X=1, DP and DB unchanged; A and X clobbered (when started:
; A = 1, X = the slot); Eng_Scratch overwritten.
; ============================================================
org $C05AC5
Evt_StartTargetFunc1:
    LDX.b !Field_UnkEB
    LDA.w !Obj_Unk1C01,X
    BNE .done
    LDA.w !Obj_Unk1100,X
    BMI .done
    LDA.w !Obj_Unk1000,X
    BMI .done
    LDA.w !Obj_Unk1C00,X
    CMP.b #!Obj_Unk1C00Min
    BCC .done
    STA.w WRMPYA
    LDA.b #!Evt_PrioStride
    STA.w WRMPYB
    NOP                         ; wait for the product
    NOP
    REP #$30
    CLC
    LDA.w RDMPYL
    ADC.b !Field_UnkEB
    STA.b !Eng_Scratch          ; level x $80 + slot
    LDA.w !Obj_ScriptPos,X
    LDX.b !Eng_Scratch
    STA.l !ObjX_Unk7F0580,X     ; save where the object was
    LDA.b !Field_UnkEB
    ASL A
    ASL A
    ASL A
    ASL A                       ; slot x 16: its function table
    CLC
    ADC.w #!Evt_Func1Ofs
    TAX
    LDA.l !Evt_Data,X
    LDX.b !Field_UnkEB
    STA.w !Obj_ScriptPos,X
    SEP #$30
    LDA.b #!Obj_Unk1C00Func1
    STA.w !Obj_Unk1C00,X
    STZ.w !Obj_Unk1A80,X
    STZ.w !Obj_Unk1A01,X
    STZ.w !Obj_Unk1001,X
.done:
    RTS

; ------------------------------------------------------------
; $C0:5B63 — Map_LeaderPastRowMax (14 bytes, $5B63–$5B70)
; Map_Unk9175's test for a downward step: C=1 when the leader's
; Obj_TileY is past Map_Unk1D1D (TileY >= Map_Unk1D1D + 1).
; Callers: Map_Unk9175 ($C0:91A2), its only JSR site.
; On entry: M=1 (8-bit A), X = the leader's slot (either width), DB=$00;
; absolute operands only, DP not used.
; Exit: M, X, DP and DB unchanged; C as above; A clobbered; Eng_Scratch
; ($01D9) = Map_Unk1D1D + 1.
; ------------------------------------------------------------
org $C05B63
Map_LeaderPastRowMax:
    LDA.w !Map_Unk1D1D
    INC A
    STA.w !DP_Field+!Eng_Scratch
    LDA.w !Obj_TileY,X
    CMP.w !DP_Field+!Eng_Scratch
    RTS

; ------------------------------------------------------------
; $C0:5B71 — Map_LeaderPastRowMin (8 bytes, $5B71–$5B78)
; Map_Unk9175's test for an upward step: C=1 when the leader's
; Obj_TileY <= Map_Unk1D1C + 1. Both row tests take their bound one
; row lower (+1) than the column tests do; kept as found.
; Callers: Map_Unk9175 ($C0:919B), its only JSR site.
; On entry: M=1 (8-bit A), X = the leader's slot (either width), DB=$00;
; absolute operands only, DP not used.
; Exit: M, X, DP and DB unchanged; C as above; A clobbered.
; ------------------------------------------------------------
Map_LeaderPastRowMin:
    LDA.w !Map_Unk1D1C
    INC A
    CMP.w !Obj_TileY,X
    RTS

; ------------------------------------------------------------
; $C0:5B79 — Map_LeaderPastColMax (13 bytes, $5B79–$5B85)
; Map_Unk9175's test for a rightward step: C=1 when the leader's
; Obj_TileX >= Map_Unk1D1B.
; Callers: Map_Unk9175 ($C0:918C), its only JSR site.
; On entry: M=1 (8-bit A), X = the leader's slot (either width), DB=$00;
; absolute operands only, DP not used.
; Exit: M, X, DP and DB unchanged; C as above; A clobbered; Eng_Scratch
; ($01D9) = Map_Unk1D1B.
; ------------------------------------------------------------
Map_LeaderPastColMax:
    LDA.w !Map_Unk1D1B
    STA.w !DP_Field+!Eng_Scratch
    LDA.w !Obj_TileX,X
    CMP.w !DP_Field+!Eng_Scratch
    RTS

; ------------------------------------------------------------
; $C0:5B86 — Map_LeaderPastColMin (7 bytes, $5B86–$5B8C)
; Map_Unk9175's test for a leftward step: C=1 when the leader's
; Obj_TileX <= Map_Unk1D1A.
; Callers: Map_Unk9175 ($C0:9185), its only JSR site.
; On entry: M=1 (8-bit A), X = the leader's slot (either width), DB=$00;
; absolute operands only, DP not used.
; Exit: M, X, DP and DB unchanged; C as above; A clobbered.
; ------------------------------------------------------------
Map_LeaderPastColMin:
    LDA.w !Map_Unk1D1A
    CMP.w !Obj_TileX,X
    RTS

; ============================================================
; $C0:1ADF — Sub_1ADF (87 bytes, $1ADF–$1B35)
; Purpose unknown: every variable it touches (Field_Unk34, Field_Unk62-66,
; Pad_Unk00F6-F8) is still unidentified, so it keeps its address name.
; Leaf routine run by Field_PauseAndMenuInput ($C0:192B, its only
; caller) when Field_Unk62 is set (and Pad_Unk00F6 bit 6 is clear);
; A = Field_Unk62.
; On entry: M=1, X/Y 16-bit, DP=$0100, DB=$00.
; Exit: M=1, X/Y 16-bit, DP and DB unchanged; A clobbered, X = 0 when
; Field_Unk34 is cleared.
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
; Callers (92 JSR sites): ModeE6_Handler (8 sites), ModeEC_Handler
;   (16 sites), ModeEE_Handler (16 sites), ModeFA_Handler (24 sites),
;   ModeFC_Handler (24 sites) and DefaultHandler (4 sites).
; On entry (M=0): A = tile row (0-31), Y = tile column (0-63).
; Returns A = row*32 + column for columns 0-31, or
;             row*32 + (column-32) + $0400 for columns 32-63.
; (Earlier comments had the row and column inputs swapped.)
; Keeps row*32 in Bg_RowWordOfs.
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
; Callers (BRL): Field_SceneChangeTick ($C0:0D5D).
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
; Callers (BRL): Field_SceneChangeTick ($C0:0D64).
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
; Callers (BRL): Field_SceneChangeTick ($C0:0D6B).
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
; Callers (BRL): Field_SceneChangeTick ($C0:0D72).
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
; fall-through from ModeFC_Handler. Three requests, tested in this
; order:
;   bit 1 (SceneFlag_TileStep)  play Audio_SfxTileAnimB (always, before
;         the state test), then advance the single map tile at
;         Field_TileStepX/Y if its state is $FE or $E0 and queue its
;         four 8x8-tile VRAM addresses in TileAnim_StepVramAddrs
;         (VramQueue_TileStep). Either way it goes on to bit 5.
;   bit 5 (SceneFlag_MapRedraw) run Field_Unk885A + Field_EndOfFrame
;         frames until Field_Unk38 clears, then redraw map layers
;         with the DP=$1D00 builders chosen by Field_MapRedrawSel and
;         tail into Sub_EC60. This path returns without looking at
;         bit 0, which waits for a later call.
;   bit 0 (SceneFlag_Battle)    only when bit 5 is clear; unless
;         Scene_Unk024C returns carry,
;         enter the battle engine (JSL EngCall_BattleMain), then
;         reinstall the interrupt handlers and rebuild the field;
;         either way set FadeFlag_AfterBattle and finish with
;         Field_IdleFrame.
; Earlier notes called bit 5 a "display-mode transition" and bit 0 a
; "scene swap"; the JSL into bank $C1 identifies bit 0 as the battle.
; Callers (6 BRL sites): Field_SceneChangeTick ($C0:0D42, $C0:0D75),
;   ModeE6_Handler ($C0:0E5C), ModeEC_Handler ($C0:1011), ModeEE_Handler
;   ($C0:11C6) and ModeFA_Handler ($C0:1451).
; On entry: M=1 (A 8-bit), X=0 (X/Y 16-bit), DP=$0100, DB=$00.
; Exit: M=1, X/Y 16-bit, DP=$0100 on every path (each builder call
; restores DP with PLD; the battle path sets it again); A, X and Y
; clobbered.
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
; Exit (through Audio_PlaySfxAtLeader): M=1, X/Y 16-bit, DP and DB
; unchanged; A and Y clobbered (Y = the leader's object), and whatever
; Audio_DriverCommand (unmatched) changes.
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
; Reached by BRL from $C0:086E and $C0:0902 (unmatched object set-up
; code), each right after JSR $C0:A9CD, which returns with X/Y 8-bit.
; On entry: M=1, X/Y 8-bit, DP=$0100, DB=$00, Obj_Cur = object.
; Exit: M=1, X/Y 8-bit. The early RTS (object skipped) leaves C as it
; was; size 3 returns C=0; the layouts return C=0.
; ============================================================
org $C0CB0A
Obj_BuildFrameLayout:
    LDX.b !Obj_Cur           ; object
    LDA.w !Obj_Unk1100,X     ; skip when bit 7 is set
    BPL .active              ; bit 7 clear → build
.exit:
    RTS                      ; skipped; C not set (as in the original)
.active:
    LDA.w !Obj_Unk1A81,X
    BEQ .exit                ; 0 → skip
    BMI .exit                ; $80-$FF → skip
    LDA.w !Obj_Unk0F00,X
    BEQ .exit                ; 0 → no frame to build
    LDA.w !Obj_SprSize,X     ; size class
    AND.b #!ObjSpr_SizeMask  ; isolate bits 0-1
    BEQ .size0               ; 0: 4 tiles
    CMP #$01
    BNE .check2
    BRA .size1               ; 1: 8 tiles
.check2:
    CMP #$02
    BEQ .size2               ; 2: 12 tiles
    CLC
    RTS                      ; 3: nothing, C=0
.size0:
    BRL Obj_FrameLayout4
.size1:
    BRL Obj_FrameLayout8
.size2:
    BRL Obj_FrameLayout12

; ============================================================
; $C0:CB3A — Obj_AnimFrameLookup (162 bytes, $CB3A–$CBDB)
; (was Sub_CB3A.) Returns in A the frame number object X should show:
; Anim_FramePtr = Obj_AnimFrameTbl + (Obj_Facing × Obj_AnimFacingStride)
; + row*4 + Obj_AnimColumn, row = Obj_AnimRow (or Obj_AnimRowAlt in
; mode 2), read from bank $E4. The multiple is the facing itself for
; facings 0-3; it is chosen by BEQ / CMP #2 / BPL, so facings $80/$81
; also get 3 and $82-$FF get 1.
;   entry ≠ $FF          → C=1, A = frame number.
;   $FF in mode 2        → count ObjX_AnimLoops down, C=0 (no frame).
;   $FF in other modes   → step back to the row start, set
;                          Obj_AnimColumn = $FF, C=1 with that entry.
; Called from Obj_BuildFrame4, Obj_BuildFrame8Pass0,
; Obj_BuildFrame12Pass0 and Obj_BuildFrame12Pass0Alt.
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X preserved; C and A as above.
; ============================================================
org $C0CB3A
Obj_AnimFrameLookup:
    LDA.w !Obj_Facing,X
    BEQ .facing0            ; 0 → × 0
    CMP #$02
    BEQ .facing2            ; 2 → × 2
    BPL .facing3            ; 3 (and $80/$81) → × 3
.facing1:                   ; 1 (and $82-$FF) → × 1
    REP #$20
    LDA.w !Obj_AnimFacingStride,X
    CLC
    ADC.w !Obj_AnimFrameTbl,X
    STA.b !Anim_FramePtr
    BRA .common
.facing0:
    REP #$20
    LDA.w !Obj_AnimFrameTbl,X
    STA.b !Anim_FramePtr
    BRA .common
.facing3:
    REP #$20
    LDA.w !Obj_AnimFacingStride,X
    STA.b !Anim_Column      ; (Anim_Column as scratch)
    CLC
    ADC.b !Anim_Column      ; × 2
    ADC.b !Anim_Column      ; × 3
    ADC.w !Obj_AnimFrameTbl,X
    STA.b !Anim_FramePtr
    BRA .common
.facing2:
    REP #$20
    LDA.w !Obj_AnimFacingStride,X
    ASL                     ; × 2
    CLC
    ADC.w !Obj_AnimFrameTbl,X
    STA.b !Anim_FramePtr
.common:                    ; M=0
    LDA.w !Obj_AnimColumn,X ; column (low byte)
    AND.w #!Anim_EndMarker
    STA.b !Anim_Column
    LDA.w !Obj_AnimMode,X
    AND.w #!Anim_EndMarker
    CMP #$0002              ; mode 2?
    BNE .not_two
.type_two:
    LDA.w !Obj_AnimRowAlt,X ; mode 2's row
    AND.w #!Anim_EndMarker
    ASL                     ; × 2
    ASL                     ; × 4
    CLC
    ADC.b !Anim_Column      ; + column
    ADC.b !Anim_FramePtr    ; + facing block
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
    LDA.w !Obj_AnimRow,X    ; row
    AND.w #!Anim_EndMarker
    ASL                     ; × 2
    ASL                     ; × 4
    CLC
    ADC.b !Anim_Column      ; + column
    ADC.b !Anim_FramePtr    ; + facing block
    STA.b !Anim_FramePtr    ; → adjusted frame pointer
    SEP #$20
    LDA.b [!Anim_FramePtr]  ; read frame data byte
    CMP.b #!Anim_EndMarker
    BNE .proceed            ; not $FF → sprite is ready
    REP #$20
    LDA.b !Anim_FramePtr    ; current frame pointer
    SEC
    SBC.b !Anim_Column      ; back to the row start
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
; record = Obj_FrameOfs + frame * 40, in Obj_FrameBank: 16 tile words
; then 4 position pairs) into the chunk with Spr_CopyTile /
; Spr_CopyTileFlipped; queue the chunk's two halves for VRAM at
; Obj_VramTile (VramQ_*); write the 4 SprTileSrc records (OfsX
; sign-extended, OfsY, Tile = Obj_VramTile + 2n, Attr = Obj_OamAttr |
; Obj_VramTileHi | Obj_PrioLow, or Obj_PrioHigh for OfsY >= $E8
; unsigned; see Spr_UpperOfsY); INC Obj_State. Returns C=0.
; The only caller is Obj_BuildSpriteFrameStep (BRL).
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00 (absolute
; object tables and WRAM/multiplier registers).
; Exit: M=1, X/Y 8-bit.
; ============================================================
org $C0CBDC
Obj_BuildFrame4:
    LDA.w !Obj_GfxBank,X
    STA.b !Spr_GfxPtr+2
    LDA.b #!Bank7F
    STA.b !Spr_WramPtr+2    ; the tile buffer is in bank $7F
    REP #$20
    LDA.w !Obj_GfxOfs,X     ; the object's tile graphics
    STA.b !Spr_GfxPtr
    SEP #$20
    LDA.b #!BankE4
    STA.b !Anim_FramePtr+2  ; bank $E4 of Anim_FramePtr
    LDA.w !Obj_AnimMode,X
    CMP #$03
    BNE .run_gate           ; modes 0-2: look the frame up
    LDA.w !Obj_FixedFrame,X ; mode 3: fixed frame
    BRA .frame_check
.run_gate:
    JSR Obj_AnimFrameLookup
    BCS .frame_check        ; C=1: A = frame
    RTS                     ; C=0: no frame this time
.frame_check:
    CMP.w !Obj_LastFrame,X  ; same frame as last?
    BNE .new_frame
.no_work:
    CLC
    RTS                     ; same frame → no work
.new_frame:
    STA.b !Spr_NewFrame
    JSR SprBuf_Alloc1       ; one chunk; returns X = Obj_Cur
    BCC .no_work            ; none free
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X    ; the chunk, in bank $7F
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA
    LDA.b #!Frame4_Bytes
    STA.w WRMPYB            ; frame × 40 (16 tile words + 4 position pairs)
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr     ; the frame record
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WRAM address bit 16 set: bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL            ; WMDATA writes go to the chunk
    LDA.w #!SprBuf_ChunkTiles ; 16 tiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .check
.next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip_path
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
    BRA .after_loop
.flip_path:
    JSR Spr_CopyTileFlipped ; mirrored tile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
.after_loop:
    ; --- Queue the chunk for VRAM (VramQ_*) ---
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
    LDA.w !Obj_TileBuf,X
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
    BPL .x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .x0hi
.x0pos:
    LDA #$00
.x0hi:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; tile 1 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .x1hi
.x1pos:
    LDA #$00
.x1hi:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; tile 2 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .x2hi
.x2pos:
    LDA #$00
.x2hi:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; tile 3 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .x3hi
.x3pos:
    LDA #$00
.x3hi:
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
    BRA .done
.a3within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTileSrc[3].Attr,X
.done:
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
; Obj_BuildFrame4 (by OfsY against Spr_UpperOfsY); then Obj_State =
; $80. Reached by BRL from Obj_BuildFrameLayout.
; On entry: M=1, X/Y 8-bit (the REP #$10 before the TAX of the record
; offset widens X here), DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit, C=0.
; ============================================================
org $C0CDC8
Obj_FrameLayout4:
    LDX.b !Obj_Cur
    LDA.w !Obj_LastFrame,X  ; the frame already loaded
    STA.w WRMPYA
    LDA.b #!Frame4_Bytes
    STA.w WRMPYB            ; frame × 40
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr     ; the frame record
    LDA.w !Obj_TileRecOfs,X ; object's first tile record
    REP #$10                ; X → 16-bit
    TAX                     ; X = first tile record
    SEP #$20
    LDY.w #!Frame_TileWordBytes*16 ; position bytes follow the 16 tile words
    ; tile 0 offsets → SprTile
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .x0hi
.x0pos:
    LDA #$00
.x0hi:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    ; tile 1 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .x1hi
.x1pos:
    LDA #$00
.x1hi:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    ; tile 2 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .x2hi
.x2pos:
    LDA #$00
.x2hi:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    ; tile 3 offsets
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .x3hi
.x3pos:
    LDA #$00
.x3hi:
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
    BRA .done
.a3within:
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y
    STA.l SprTile[3].Attr,X
.done:
    LDX.b !Obj_Cur
    LDA.b #!ObjState_Ready
    STA.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:CEF5 — Obj_BuildFrame8 (559 bytes, $CEF5–$D123)
; (was Sub_CEF5.) Builds the current frame of an 8-tile object. In
; mode 3 (fixed frame) all 32 tiles go into 2 SprBuf chunks in one pass
; and Obj_State is incremented twice; otherwise the work is split:
; Obj_State count 0 → Obj_BuildFrame8Pass0, else Obj_BuildFrame8Pass1.
; Records 0-3 take Obj_PrioLow, 4-7 Obj_PrioHigh (by index).
; The only caller is Obj_BuildSpriteFrameStep (BRL).
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit; C=0 (the passes return their own C).
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
    LDA.w !Obj_AnimMode,X
    CMP #$03
    BNE .check_pass         ; modes 0-2: two passes
    BRA .mode3_path         ; mode 3: all 32 tiles at once
.check_pass:
    LDA.w !Obj_State,X
    AND.b #!ObjState_CountMask
    BEQ .first_pass         ; count 0
    BRL Obj_BuildFrame8Pass1
.first_pass:
    BRL Obj_BuildFrame8Pass0
    ; ---- mode 3: fixed frame, 32 tiles in one pass ----
.mode3_path:
    LDA.w !Obj_FixedFrame,X
    CMP.w !Obj_LastFrame,X
    BNE .mode3_new_frame
.mode3_no_work:
    CLC
    RTS                     ; same frame → no work
.mode3_new_frame:
    STA.b !Spr_NewFrame
    JSR SprBuf_Alloc2       ; 2 adjacent SprBuf chunks
    BCC .mode3_no_work      ; none free
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA
    LDA.b #!Frame8_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$20
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    LDA.w #!SprBuf_ChunkTiles*2 ; 32 tiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .mode3_check
.mode3_next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.mode3_check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .mode3_flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .mode3_next
    BRA .mode3_after_loop
.mode3_flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .mode3_next
.mode3_after_loop:
    ; --- Queue both chunks for VRAM (VramQ_*) ---
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
    LDY.w #!Frame_TileWordBytes*32 ; position pairs follow the 32 tile words
    ; record 0 offsets
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .mode3_x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .mode3_x0hi
.mode3_x0pos:
    LDA #$00
.mode3_x0hi:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .mode3_x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .mode3_x1hi
.mode3_x1pos:
    LDA #$00
.mode3_x1hi:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .mode3_x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .mode3_x2hi
.mode3_x2pos:
    LDA #$00
.mode3_x2hi:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .mode3_x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .mode3_x3hi
.mode3_x3pos:
    LDA #$00
.mode3_x3hi:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsX,X
    BPL .mode3_x4pos
    LDA.b #!Eng_SignExtNeg
    BRA .mode3_x4hi
.mode3_x4pos:
    LDA #$00
.mode3_x4hi:
    STA.l SprTileSrc[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsX,X
    BPL .mode3_x5pos
    LDA.b #!Eng_SignExtNeg
    BRA .mode3_x5hi
.mode3_x5pos:
    LDA #$00
.mode3_x5hi:
    STA.l SprTileSrc[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsX,X
    BPL .mode3_x6pos
    LDA.b #!Eng_SignExtNeg
    BRA .mode3_x6hi
.mode3_x6pos:
    LDA #$00
.mode3_x6hi:
    STA.l SprTileSrc[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsX,X
    BPL .mode3_x7pos
    LDA.b #!Eng_SignExtNeg
    BRA .mode3_x7hi
.mode3_x7pos:
    LDA #$00
.mode3_x7hi:
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
    STA.b !Spr_AttrBase
    ORA.w !Obj_PrioLow,Y    ; records 0-3
    STA.l SprTileSrc.Attr,X
    STA.l SprTileSrc[1].Attr,X
    STA.l SprTileSrc[2].Attr,X
    STA.l SprTileSrc[3].Attr,X
    LDA.b !Spr_AttrBase
    ORA.w !Obj_PrioHigh,Y   ; records 4-7
    STA.l SprTileSrc[4].Attr,X
    STA.l SprTileSrc[5].Attr,X
    STA.l SprTileSrc[6].Attr,X
    STA.l SprTileSrc[7].Attr,X
    LDX.b !Obj_Cur
    INC.w !Obj_State,X      ; both passes' worth
    INC.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:D124 — Obj_FrameLayout8 (358 bytes, $D124–$D289)
; (was Sub_D124.) As Obj_FrameLayout4 for an 8-tile object (frame
; record 80 bytes, positions after 32 tile words); the first four
; tiles take Obj_PrioLow, the last four Obj_PrioHigh (by index, not
; by OfsY). Reached by BRL from Obj_BuildFrameLayout.
; On entry: M=1, X/Y 8-bit (widened before the TAX of the record
; offset), DP=$0100, DB=$00, X = Obj_Cur: unlike Obj_FrameLayout4 it
; does not load X itself, and relies on Obj_BuildFrameLayout's LDX.
; Exit: M=1, X/Y 8-bit, C=0; X = Obj_Cur (reloaded), A and Y clobbered;
; DP Spr_FramePtr and Spr_AttrBase written.
; ============================================================
org $C0D124
Obj_FrameLayout8:
    LDA.w !Obj_LastFrame,X   ; the frame already loaded
    STA.w WRMPYA
    LDA.b #!Frame8_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20                 ; A 16-bit
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr      ; the frame record
    REP #$20                 ; redundant: A is already 16-bit (as in the original)
    LDA.l !Obj_TileRecOfs,X  ; object's first tile record
    REP #$10                 ; X/Y 16-bit
    TAX                      ; X = first tile record
    SEP #$20                 ; A 8-bit
    LDY.w #!Frame_TileWordBytes*32 ; position pairs follow the 32 tile words
    ; --- 8 records: OfsX (sign-extended), OfsY ---
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .x0hi
.x0pos:
    LDA #$00
.x0hi:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .x1hi
.x1pos:
    LDA #$00
.x1hi:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .x2hi
.x2pos:
    LDA #$00
.x2hi:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .x3hi
.x3pos:
    LDA #$00
.x3hi:
    STA.l SprTile[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsX,X
    BPL .x4pos
    LDA.b #!Eng_SignExtNeg
    BRA .x4hi
.x4pos:
    LDA #$00
.x4hi:
    STA.l SprTile[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsX,X
    BPL .x5pos
    LDA.b #!Eng_SignExtNeg
    BRA .x5hi
.x5pos:
    LDA #$00
.x5hi:
    STA.l SprTile[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsX,X
    BPL .x6pos
    LDA.b #!Eng_SignExtNeg
    BRA .x6hi
.x6pos:
    LDA #$00
.x6hi:
    STA.l SprTile[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsX,X
    BPL .x7pos
    LDA.b #!Eng_SignExtNeg
    BRA .x7hi
.x7pos:
    LDA #$00
.x7hi:
    STA.l SprTile[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsY,X
    ; --- Tile numbers: Obj_VramTile + 2 per 16x16 tile ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y    ; first tile number
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
    ; --- Attributes: records 0-3 Obj_PrioLow, 4-7 Obj_PrioHigh ---
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
; SprBuf_Alloc2 (2 adjacent SprBuf chunks), copy tiles 0-15 into the
; first chunk, INC Obj_State, return C=1 (more to do). C=0 when
; nothing changed or no chunks are free. Reached by BRL from
; Obj_BuildFrame8.
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
; ============================================================
org $C0D28A
Obj_BuildFrame8Pass0:
    JSR Obj_AnimFrameLookup
    BCS .proceed
    RTS                     ; C=0: no frame this time
.proceed:
    CMP.w !Obj_LastFrame,X  ; same frame?
    BNE .new_frame
.no_work:
    CLC
    RTS
.new_frame:
    STA.b !Spr_NewFrame
    JSR SprBuf_Alloc2       ; 2 adjacent SprBuf chunks
    BCC .no_work            ; none free
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA
    LDA.b #!Frame8_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    LDA.w #!SprBuf_ChunkTiles ; 16 tiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .check
.next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
    BRA .done
.flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
.done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D30D — Obj_BuildFrame8Pass1 (490 bytes, $D30D–$D4F6)
; (was Sub_D30D.) Second pass: tiles 16-31 into the second chunk
; (Obj_TileBuf + $200), queue the VRAM upload ($200 bytes to
; Obj_VramTile*16, $200 more to the next tile row), write the 8
; SprTileSrc records (records 0-3 Obj_PrioLow, 4-7 Obj_PrioHigh),
; INC Obj_State; C=0. Reached by BRL from Obj_BuildFrame8.
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
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
    STA.w WRMPYA
    LDA.b #!Frame8_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$20
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    LDA.w #!SprBuf_ChunkTiles ; 16 tiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*16 ; tile words 16-31
    BRA .check
.next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
    BRA .after_loop
.flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
.after_loop:
    ; --- Queue both chunks for VRAM (VramQ_*) ---
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
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .x0hi
.x0pos:
    LDA #$00
.x0hi:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .x1hi
.x1pos:
    LDA #$00
.x1hi:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .x2hi
.x2pos:
    LDA #$00
.x2hi:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .x3hi
.x3pos:
    LDA #$00
.x3hi:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsX,X
    BPL .x4pos
    LDA.b #!Eng_SignExtNeg
    BRA .x4hi
.x4pos:
    LDA #$00
.x4hi:
    STA.l SprTileSrc[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsX,X
    BPL .x5pos
    LDA.b #!Eng_SignExtNeg
    BRA .x5hi
.x5pos:
    LDA #$00
.x5hi:
    STA.l SprTileSrc[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsX,X
    BPL .x6pos
    LDA.b #!Eng_SignExtNeg
    BRA .x6hi
.x6pos:
    LDA #$00
.x6hi:
    STA.l SprTileSrc[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsX,X
    BPL .x7pos
    LDA.b #!Eng_SignExtNeg
    BRA .x7hi
.x7pos:
    LDA #$00
.x7hi:
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
    ; --- Attributes: records 0-3 Obj_PrioLow, 4-7 Obj_PrioHigh ---
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
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:D4F7 — Obj_BuildFrame12 (79 bytes, $D4F7–$D545)
; (was Sub_D4F7.) Builds the current frame of a 12-tile object over
; three passes chosen by the Obj_State count (0 / 1 / 2+), each with
; an "Alt" variant when Obj_VramTile is ObjTile_AltLayout ($68; see
; there for the layout). Every pass is a BRL/BRA to its own routine.
; Mode 3 (fixed frame) objects return at once with C=1 left by the
; CMP #$03, so Field_ProcessAnimQueue keeps retrying the object until
; its scanline window closes; nothing is built (kept as in the
; original). The only caller is Obj_BuildSpriteFrameStep (BRL).
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
; ============================================================
org $C0D4F7
Obj_BuildFrame12:
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
    LDA.w !Obj_AnimMode,X
    CMP #$03
    BNE .check_pass
    RTS                     ; mode 3: C=1 from the CMP (see the header)
.check_pass:
    LDA.w !Obj_State,X
    AND.b #!ObjState_CountMask ; pass count (low 7 bits)
    BEQ .pass0
    CMP #$01
    BEQ .pass1
    ; count 2+
    LDA.w !Obj_VramTile,X
    CMP.b #!ObjTile_AltLayout
    BEQ .pass2_alt
    BRL Obj_BuildFrame12Pass2
.pass2_alt:
    BRL Obj_BuildFrame12Pass2Alt
.pass0:
    LDA.w !Obj_VramTile,X
    CMP.b #!ObjTile_AltLayout
    BEQ .pass0_alt
    BRA Obj_BuildFrame12Pass0 ; the next routine, by BRA
.pass0_alt:
    BRL Obj_BuildFrame12Pass0Alt
.pass1:
    LDA.w !Obj_VramTile,X
    CMP.b #!ObjTile_AltLayout
    BEQ .pass1_alt
    BRL Obj_BuildFrame12Pass1
.pass1_alt:
    BRL Obj_BuildFrame12Pass1Alt

; ============================================================
; $C0:D546 — Obj_BuildFrame12Pass0 (194 bytes, $D546–$D607)
; (was Sub_D546.) Pass 0: frame lookup, SprBuf_Alloc3 (3 adjacent
; SprBuf chunks), tiles 0-7 to the buffer start and tiles 8-15 to
; +$200, INC Obj_State; C=1. C=0 when nothing changed or no chunks
; are free. Reached by the BRA at $C0:D534 in Obj_BuildFrame12 (the
; byte before it ends in a BRL, so nothing falls in).
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
; ============================================================
Obj_BuildFrame12Pass0:
    JSR Obj_AnimFrameLookup
    BCS .proceed
    RTS
.proceed:
    CMP.w !Obj_LastFrame,X  ; same frame already loaded?
    BNE .new_frame
.no_work:                  ; same frame, or no chunks free
    CLC
    RTS
.new_frame:
    STA.b !Spr_NewFrame
    JSR SprBuf_Alloc3       ; 3 adjacent SprBuf chunks
    BCC .no_work            ; none free
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X    ; the first chunk
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X  ; frame × 120 bytes (48 tile words + 12 position pairs)
    STA.w WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X   ; the frame record
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    ; tile words 0-7 → the first chunk
    LDA.w #!SprBuf_HalfChunkTiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .loop1_entry
.loop1_top:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.loop1_entry:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .loop1_flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .loop1_top
    BRA .loop2_init
.loop1_flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .loop1_top
.loop2_init:
    ; tile words 8-15 → the second chunk (+$200)
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*2
    STA.b !Spr_WramPtr
    STA.w WMADDL
    REP #$10
    LDA.w #!SprBuf_HalfChunkTiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*8
    BRA .loop2_entry
.loop2_top:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.loop2_entry:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .loop2_flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .loop2_top
    BRA .done
.loop2_flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .loop2_top
.done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D608 — Obj_BuildFrame12Pass0Alt (131 bytes, $D608–$D68A)
; (was Sub_D608.) Pass 0 for the ObjTile_AltLayout ($68) layout:
; frame lookup, SprBuf_Alloc3, tiles 0-15 in one run to the buffer
; start, INC Obj_State; C=1 (C=0 when nothing changed or no chunks are
; free). The run differs from Obj_BuildFrame12Pass0 because tile $68
; is column 8 of a 16-tile VRAM row: the first row of 16x16 sprites
; holds only 4 of them, so the layout is 4 then 8 instead of 8 then 4.
; Reached by BRL from Obj_BuildFrame12.
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
; ============================================================
org $C0D608
Obj_BuildFrame12Pass0Alt:
    JSR Obj_AnimFrameLookup
    BCS .proceed
    RTS
.proceed:
    CMP.w !Obj_LastFrame,X  ; same frame already loaded?
    BNE .new_frame
.no_work:
    CLC
    RTS
.new_frame:
    STA.b !Spr_NewFrame
    JSR SprBuf_Alloc3       ; 3 adjacent SprBuf chunks
    BCC .no_work
    LDA.b !Spr_NewFrame
    STA.w !Obj_LastFrame,X
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    STA.b !Spr_WramPtr
    SEP #$20
    LDA.w !Obj_LastFrame,X
    STA.w WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    ; tile words 0-15 → the buffer start
    LDA.w #!SprBuf_ChunkTiles
    STA.b !Spr_TileCount
    LDY #$0000
    BRA .loop_entry
.loop_top:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.loop_entry:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .loop_top
    BRA .done
.flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .loop_top
.done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D68B — Obj_BuildFrame12Pass1 (173 bytes, $D68B–$D737)
; (was Sub_D68B.) Pass 1: tiles 16-23 to +$100, tiles 24-31 to
; +$300; INC Obj_State; C=1. Reached by BRL from Obj_BuildFrame12.
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
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
    STA.w WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    LDA.w #!SprBuf_HalfChunkTiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*16
    BRA .check
.next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
    BRA .loop2
.flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
.loop2:
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*3
    STA.b !Spr_WramPtr
    STA.w WMADDL
    REP #$10
    LDA.w #!SprBuf_HalfChunkTiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*24
    BRA .check2
.next2:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check2:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip2
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next2
    BRA .done
.flip2:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next2
.done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D738 — Obj_BuildFrame12Pass1Alt (173 bytes, $D738–$D7E4)
; (was Sub_D738.) Pass 1 for the ObjTile_AltLayout ($68) layout:
; tiles 16-23 to +$200, tiles 24-31 to +$400; INC Obj_State; C=1.
; Reached by BRL from Obj_BuildFrame12.
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
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
    STA.w WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$30
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    LDA.w #!SprBuf_HalfChunkTiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*16
    BRA .check
.next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
    BRA .loop2
.flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
.loop2:
    REP #$20
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*4
    STA.b !Spr_WramPtr
    STA.w WMADDL
    REP #$10
    LDA.w #!SprBuf_HalfChunkTiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*24
    BRA .check2
.next2:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check2:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip2
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next2
    BRA .done
.flip2:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next2
.done:
    SEP #$30
    LDX.b !Obj_Cur
    INC.w !Obj_State,X
    SEC
    RTS

; ============================================================
; $C0:D7E5 — Obj_BuildFrame12Pass2 (644 bytes, $D7E5–$DA68)
; (was Sub_D7E5.) Pass 2: tiles 32-47 to +$400, queue the VRAM
; upload ($500 bytes from Obj_TileBuf to Obj_VramTile*16, then $100
; bytes from +$500 to 3 tile rows further on, +$300 words), write the
; 12 SprTileSrc records (16x16 tiles in a row of 8, then 4 on the next
; tile row), INC Obj_State; C=0. Attributes by index: records 0-3
; Obj_PrioLow, 4-11 Obj_PrioHigh. Reached by BRL from Obj_BuildFrame12.
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
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
    STA.w WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$20
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    LDA.w #!SprBuf_ChunkTiles ; 16 tiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*32
    BRA .check
.next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
    BRA .queue
.flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
.queue:
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
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .x0hi
.x0pos:
    LDA #$00
.x0hi:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .x1hi
.x1pos:
    LDA #$00
.x1hi:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .x2hi
.x2pos:
    LDA #$00
.x2hi:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .x3hi
.x3pos:
    LDA #$00
.x3hi:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsX,X
    BPL .x4pos
    LDA.b #!Eng_SignExtNeg
    BRA .x4hi
.x4pos:
    LDA #$00
.x4hi:
    STA.l SprTileSrc[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsX,X
    BPL .x5pos
    LDA.b #!Eng_SignExtNeg
    BRA .x5hi
.x5pos:
    LDA #$00
.x5hi:
    STA.l SprTileSrc[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsX,X
    BPL .x6pos
    LDA.b #!Eng_SignExtNeg
    BRA .x6hi
.x6pos:
    LDA #$00
.x6hi:
    STA.l SprTileSrc[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsX,X
    BPL .x7pos
    LDA.b #!Eng_SignExtNeg
    BRA .x7hi
.x7pos:
    LDA #$00
.x7hi:
    STA.l SprTileSrc[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsY,X
    ; record 8
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[8].OfsX,X
    BPL .x8pos
    LDA.b #!Eng_SignExtNeg
    BRA .x8hi
.x8pos:
    LDA #$00
.x8hi:
    STA.l SprTileSrc[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[8].OfsY,X
    ; record 9
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[9].OfsX,X
    BPL .x9pos
    LDA.b #!Eng_SignExtNeg
    BRA .x9hi
.x9pos:
    LDA #$00
.x9hi:
    STA.l SprTileSrc[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[9].OfsY,X
    ; record 10
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[10].OfsX,X
    BPL .x10pos
    LDA.b #!Eng_SignExtNeg
    BRA .x10hi
.x10pos:
    LDA #$00
.x10hi:
    STA.l SprTileSrc[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[10].OfsY,X
    ; record 11
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[11].OfsX,X
    BPL .x11pos
    LDA.b #!Eng_SignExtNeg
    BRA .x11hi
.x11pos:
    LDA #$00
.x11hi:
    STA.l SprTileSrc[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[11].OfsY,X
    ; --- Tile numbers: 8 along one row of 16x16 tiles, 4 on the next ---
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
    ; --- Attributes: records 0-3 Obj_PrioLow, 4-11 Obj_PrioHigh ---
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
    LDA.b !Spr_AttrBase     ; redundant: A already holds this value
    ORA.w !Obj_PrioHigh,Y   ; (kept as in the original)
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
; (was Sub_DA69.) Pass 2 for the ObjTile_AltLayout ($68) layout:
; tiles 32-39 to +$300 and 40-47 to +$500, queue the upload ($100
; bytes to Obj_VramTile*16, then $500 bytes from +$100 to the next
; tile row), write the 12 SprTileSrc records (16x16 tiles in rows of
; 4 then 8), INC Obj_State; C=0. Attributes by index: records 0-3
; Obj_PrioLow, 4-11 Obj_PrioHigh. Reached by BRL from Obj_BuildFrame12.
; On entry: M=1, X/Y 8-bit, X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit.
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
    STA.w WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    SEP #$20
    LDA #$01
    STA.w WMADDH            ; WRAM bank $7F
    REP #$30
    LDA.b !Spr_WramPtr
    STA.w WMADDL
    LDA.w #!SprBuf_HalfChunkTiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*32
    BRA .check
.next:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
    BRA .loop2
.flip:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next
.loop2:
    LDX.b !Obj_Cur
    LDA.w !Obj_TileBuf,X
    CLC
    ADC.w #!Gfx_8TilesBytes*5
    STA.b !Spr_WramPtr
    STA.w WMADDL
    LDA.w #!SprBuf_HalfChunkTiles
    STA.b !Spr_TileCount
    LDY.w #!Frame_TileWordBytes*40
    BRA .check2
.next2:
    LDA.b !Spr_WramPtr
    CLC
    ADC.w #!Gfx_Tile4bppBytes
    STA.b !Spr_WramPtr
.check2:
    LDA.b [!Spr_FramePtr],Y
    BIT.w #!SprFrame_HFlip
    BNE .flip2
    JSR Spr_CopyTile
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next2
    BRA .queue
.flip2:
    JSR Spr_CopyTileFlipped
    INY
    INY
    DEC.b !Spr_TileCount
    BNE .next2
.queue:
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
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsX,X
    BPL .x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .x0hi
.x0pos:
    LDA #$00
.x0hi:
    STA.l SprTileSrc.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsX,X
    BPL .x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .x1hi
.x1pos:
    LDA #$00
.x1hi:
    STA.l SprTileSrc[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsX,X
    BPL .x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .x2hi
.x2pos:
    LDA #$00
.x2hi:
    STA.l SprTileSrc[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsX,X
    BPL .x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .x3hi
.x3pos:
    LDA #$00
.x3hi:
    STA.l SprTileSrc[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsX,X
    BPL .x4pos
    LDA.b #!Eng_SignExtNeg
    BRA .x4hi
.x4pos:
    LDA #$00
.x4hi:
    STA.l SprTileSrc[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsX,X
    BPL .x5pos
    LDA.b #!Eng_SignExtNeg
    BRA .x5hi
.x5pos:
    LDA #$00
.x5hi:
    STA.l SprTileSrc[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsX,X
    BPL .x6pos
    LDA.b #!Eng_SignExtNeg
    BRA .x6hi
.x6pos:
    LDA #$00
.x6hi:
    STA.l SprTileSrc[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsX,X
    BPL .x7pos
    LDA.b #!Eng_SignExtNeg
    BRA .x7hi
.x7pos:
    LDA #$00
.x7hi:
    STA.l SprTileSrc[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[7].OfsY,X
    ; record 8
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[8].OfsX,X
    BPL .x8pos
    LDA.b #!Eng_SignExtNeg
    BRA .x8hi
.x8pos:
    LDA #$00
.x8hi:
    STA.l SprTileSrc[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[8].OfsY,X
    ; record 9
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[9].OfsX,X
    BPL .x9pos
    LDA.b #!Eng_SignExtNeg
    BRA .x9hi
.x9pos:
    LDA #$00
.x9hi:
    STA.l SprTileSrc[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[9].OfsY,X
    ; record 10
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[10].OfsX,X
    BPL .x10pos
    LDA.b #!Eng_SignExtNeg
    BRA .x10hi
.x10pos:
    LDA #$00
.x10hi:
    STA.l SprTileSrc[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[10].OfsY,X
    ; record 11
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[11].OfsX,X
    BPL .x11pos
    LDA.b #!Eng_SignExtNeg
    BRA .x11hi
.x11pos:
    LDA #$00
.x11hi:
    STA.l SprTileSrc[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTileSrc[11].OfsY,X
    ; --- Tile numbers: 4 along one row of 16x16 tiles, 8 on the next ---
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
    ; --- Attributes: records 0-3 Obj_PrioLow, 4-11 Obj_PrioHigh ---
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
; (was Sub_DD28.) Rewrites the 12 SprTile records of a 12-tile object
; for Obj_LastFrame (tiles already in VRAM): offsets from the frame
; record (120 bytes, positions after 48 tile words), tile numbers in
; the two layouts of the 12-tile builders (8 then 4, or 4 then 8 for
; Obj_VramTile = ObjTile_AltLayout → .alt), attributes by index as in
; Obj_BuildFrame12Pass2 (records 0-3 Obj_PrioLow, 4-11 Obj_PrioHigh;
; unlike Obj_FrameLayout4, OfsY is not looked at); Obj_State = $80.
; Reached by BRL from Obj_BuildFrameLayout.
; On entry: M=1, X/Y 8-bit (widened before the TAX of the record
; offset), X = Obj_Cur, DP=$0100, DB=$00.
; Exit: M=1, X/Y 8-bit, C=0.
; ============================================================
org $C0DD28
Obj_FrameLayout12:
    LDA.w !Obj_VramTile,X
    CMP.b #!ObjTile_AltLayout
    BEQ .alt_far             ; the 4-then-8 layout
    BRA .main
.alt_far:
    BRL .alt
    ; ---- 8-then-4 layout ----
.main:
    LDA.w !Obj_LastFrame,X   ; the frame already loaded
    STA.w WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20                 ; A 16-bit
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr      ; the frame record
    LDA.w !Obj_TileRecOfs,X  ; object's first tile record
    REP #$10                 ; X/Y 16-bit
    TAX                      ; X = first tile record
    SEP #$20                 ; A 8-bit
    LDY.w #!Frame_TileWordBytes*48 ; position pairs follow the 48 tile words
    ; --- 12 records: OfsX (sign-extended), OfsY ---
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .x0hi
.x0pos:
    LDA #$00
.x0hi:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .x1hi
.x1pos:
    LDA #$00
.x1hi:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .x2hi
.x2pos:
    LDA #$00
.x2hi:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .x3hi
.x3pos:
    LDA #$00
.x3hi:
    STA.l SprTile[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsX,X
    BPL .x4pos
    LDA.b #!Eng_SignExtNeg
    BRA .x4hi
.x4pos:
    LDA #$00
.x4hi:
    STA.l SprTile[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsX,X
    BPL .x5pos
    LDA.b #!Eng_SignExtNeg
    BRA .x5hi
.x5pos:
    LDA #$00
.x5hi:
    STA.l SprTile[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsX,X
    BPL .x6pos
    LDA.b #!Eng_SignExtNeg
    BRA .x6hi
.x6pos:
    LDA #$00
.x6hi:
    STA.l SprTile[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsX,X
    BPL .x7pos
    LDA.b #!Eng_SignExtNeg
    BRA .x7hi
.x7pos:
    LDA #$00
.x7hi:
    STA.l SprTile[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsY,X
    ; record 8
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsX,X
    BPL .x8pos
    LDA.b #!Eng_SignExtNeg
    BRA .x8hi
.x8pos:
    LDA #$00
.x8hi:
    STA.l SprTile[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsY,X
    ; record 9
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsX,X
    BPL .x9pos
    LDA.b #!Eng_SignExtNeg
    BRA .x9hi
.x9pos:
    LDA #$00
.x9hi:
    STA.l SprTile[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsY,X
    ; record 10
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsX,X
    BPL .x10pos
    LDA.b #!Eng_SignExtNeg
    BRA .x10hi
.x10pos:
    LDA #$00
.x10hi:
    STA.l SprTile[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsY,X
    ; record 11
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsX,X
    BPL .x11pos
    LDA.b #!Eng_SignExtNeg
    BRA .x11hi
.x11pos:
    LDA #$00
.x11hi:
    STA.l SprTile[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsY,X
    ; --- Tile numbers: 8 along one row of 16x16 tiles, 4 on the next ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y    ; first tile number
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
    ADC.b #!Spr_TileRowStep  ; on to the next row of 16x16 tiles
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
    ; --- Attributes: records 0-3 Obj_PrioLow, 4-11 Obj_PrioHigh ---
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
    ; ---- 4-then-8 layout (Obj_VramTile = ObjTile_AltLayout) ----
.alt:
    LDA.w !Obj_LastFrame,X   ; the frame already loaded
    STA.w WRMPYA
    LDA.b #!Frame12_Bytes
    STA.w WRMPYB
    LDA.w !Obj_FrameBank,X
    STA.b !Spr_FramePtr+2
    REP #$20                 ; A 16-bit
    LDA.w RDMPYL            ; frame × record size
    CLC
    ADC.w !Obj_FrameOfs,X
    STA.b !Spr_FramePtr
    LDA.w !Obj_TileRecOfs,X  ; object's first tile record
    REP #$10                 ; X/Y 16-bit
    TAX
    SEP #$20                 ; A 8-bit
    LDY.w #!Frame_TileWordBytes*48 ; position pairs follow the 48 tile words
    ; --- 12 records: OfsX (sign-extended), OfsY ---
    ; record 0
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsX,X
    BPL .alt_x0pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x0hi
.alt_x0pos:
    LDA #$00
.alt_x0hi:
    STA.l SprTile.OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile.OfsY,X
    ; record 1
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsX,X
    BPL .alt_x1pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x1hi
.alt_x1pos:
    LDA #$00
.alt_x1hi:
    STA.l SprTile[1].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[1].OfsY,X
    ; record 2
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsX,X
    BPL .alt_x2pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x2hi
.alt_x2pos:
    LDA #$00
.alt_x2hi:
    STA.l SprTile[2].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[2].OfsY,X
    ; record 3
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsX,X
    BPL .alt_x3pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x3hi
.alt_x3pos:
    LDA #$00
.alt_x3hi:
    STA.l SprTile[3].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[3].OfsY,X
    ; record 4
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsX,X
    BPL .alt_x4pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x4hi
.alt_x4pos:
    LDA #$00
.alt_x4hi:
    STA.l SprTile[4].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[4].OfsY,X
    ; record 5
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsX,X
    BPL .alt_x5pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x5hi
.alt_x5pos:
    LDA #$00
.alt_x5hi:
    STA.l SprTile[5].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[5].OfsY,X
    ; record 6
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsX,X
    BPL .alt_x6pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x6hi
.alt_x6pos:
    LDA #$00
.alt_x6hi:
    STA.l SprTile[6].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[6].OfsY,X
    ; record 7
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsX,X
    BPL .alt_x7pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x7hi
.alt_x7pos:
    LDA #$00
.alt_x7hi:
    STA.l SprTile[7].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[7].OfsY,X
    ; record 8
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsX,X
    BPL .alt_x8pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x8hi
.alt_x8pos:
    LDA #$00
.alt_x8hi:
    STA.l SprTile[8].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[8].OfsY,X
    ; record 9
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsX,X
    BPL .alt_x9pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x9hi
.alt_x9pos:
    LDA #$00
.alt_x9hi:
    STA.l SprTile[9].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[9].OfsY,X
    ; record 10
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsX,X
    BPL .alt_x10pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x10hi
.alt_x10pos:
    LDA #$00
.alt_x10hi:
    STA.l SprTile[10].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[10].OfsY,X
    ; record 11
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsX,X
    BPL .alt_x11pos
    LDA.b #!Eng_SignExtNeg
    BRA .alt_x11hi
.alt_x11pos:
    LDA #$00
.alt_x11hi:
    STA.l SprTile[11].OfsX+1,X
    INY
    LDA.b [!Spr_FramePtr],Y
    STA.l SprTile[11].OfsY,X
    ; --- Tile numbers: 4 along one row of 16x16 tiles, 8 on the next ---
    LDY.b !Obj_Cur
    LDA.w !Obj_VramTile,Y    ; first tile number
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
    ADC.b #!Spr_TileRowStep  ; on to the next row of 16x16 tiles
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
    ; --- Attributes: records 0-3 Obj_PrioLow, 4-11 Obj_PrioHigh ---
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

; ============================================================
; $C0:FD00 — BitReverseTable (256 bytes, $C0:FD00–$FDFF)
; Byte N is N with its 8 bits in reverse order (bit 0 ↔ bit 7, 1 ↔ 6,
; ...): $01 → $80, $02 → $40, $03 → $C0. Checked against the ROM for all
; 256 entries. A 4bpp tile row stores one pixel per bit in each bitplane
; byte, so reversing each byte mirrors the row left-right.
; Read by Spr_CopyTileFlipped (32 × LDA.w BitReverseTable,X, DB=$00, so
; through the $00:FD00 mirror), and with LDA.l from bank $C1 (32 sites
; from $C1:1DDE, in the unmatched gap before BattleMenu_BuildTargetList),
; $C2 and $CD (found by tools/tables.py).
; ============================================================
org $C0FD00
BitReverseTable:
    db $00,$80,$40,$C0,$20,$A0,$60,$E0,$10,$90,$50,$D0,$30,$B0,$70,$F0 ; $00
    db $08,$88,$48,$C8,$28,$A8,$68,$E8,$18,$98,$58,$D8,$38,$B8,$78,$F8 ; $10
    db $04,$84,$44,$C4,$24,$A4,$64,$E4,$14,$94,$54,$D4,$34,$B4,$74,$F4 ; $20
    db $0C,$8C,$4C,$CC,$2C,$AC,$6C,$EC,$1C,$9C,$5C,$DC,$3C,$BC,$7C,$FC ; $30
    db $02,$82,$42,$C2,$22,$A2,$62,$E2,$12,$92,$52,$D2,$32,$B2,$72,$F2 ; $40
    db $0A,$8A,$4A,$CA,$2A,$AA,$6A,$EA,$1A,$9A,$5A,$DA,$3A,$BA,$7A,$FA ; $50
    db $06,$86,$46,$C6,$26,$A6,$66,$E6,$16,$96,$56,$D6,$36,$B6,$76,$F6 ; $60
    db $0E,$8E,$4E,$CE,$2E,$AE,$6E,$EE,$1E,$9E,$5E,$DE,$3E,$BE,$7E,$FE ; $70
    db $01,$81,$41,$C1,$21,$A1,$61,$E1,$11,$91,$51,$D1,$31,$B1,$71,$F1 ; $80
    db $09,$89,$49,$C9,$29,$A9,$69,$E9,$19,$99,$59,$D9,$39,$B9,$79,$F9 ; $90
    db $05,$85,$45,$C5,$25,$A5,$65,$E5,$15,$95,$55,$D5,$35,$B5,$75,$F5 ; $A0
    db $0D,$8D,$4D,$CD,$2D,$AD,$6D,$ED,$1D,$9D,$5D,$DD,$3D,$BD,$7D,$FD ; $B0
    db $03,$83,$43,$C3,$23,$A3,$63,$E3,$13,$93,$53,$D3,$33,$B3,$73,$F3 ; $C0
    db $0B,$8B,$4B,$CB,$2B,$AB,$6B,$EB,$1B,$9B,$5B,$DB,$3B,$BB,$7B,$FB ; $D0
    db $07,$87,$47,$C7,$27,$A7,$67,$E7,$17,$97,$57,$D7,$37,$B7,$77,$F7 ; $E0
    db $0F,$8F,$4F,$CF,$2F,$AF,$6F,$EF,$1F,$9F,$5F,$DF,$3F,$BF,$7F,$FF ; $F0

; ============================================================
; $C0:FE00 — RandomTable (256 bytes, $C0:FE00–$FEFF)
; The game's pseudo-random bytes, probably: a shuffle of 0-255 (every
; value appears exactly once; checked against the ROM). The name is
; inferred from how its readers use it. Readers are spread over many
; banks and none is matched yet, so the list below gives verified
; examples, not every reader:
;   - step a counter of their own and read the entry at it:
;     $C0:AE29 (INC $F8 / LDX $F8 / LDA $FE00,X),
;     $C0:6D0B (LDA $F8 / INC / STA $F8 / TAX / LDA $FE00,X),
;     $C2:2338 (LDX $1B30 / LDA.l $C0FE00,X / INC $1B30; bank $C6 has
;     more readers sharing the $1B30 counter),
;     $CD:2AAF (LDA $CD3B / INC $CD3B / TAX / LDA.l $C0FE00,X);
;   - $C2:B10E reads one byte with X from $0D00 and multiplies it by
;     100 (WRMPYA = $64), probably a 0-99 roll;
;   - $C2:8F09 copies 16-bit words from $C0FE00,X (+2, +4) with X from
;     $0D00, and $CD:0B19 forms its index with ADC $7C.
; Follows BitReverseTable directly; the boot code at $C0:FF00
; (bank00.asm) comes next.
; ============================================================
RandomTable:
    db $B1,$CA,$EE,$6C,$5A,$71,$2E,$55,$D6,$00,$CC,$99,$90,$6B,$7D,$EB ; $00
    db $4F,$A0,$07,$AC,$DF,$8A,$56,$9E,$F1,$9A,$63,$75,$11,$91,$A3,$B8 ; $10
    db $94,$73,$F7,$54,$D9,$6E,$72,$C0,$F4,$80,$DE,$B9,$BB,$8D,$66,$26 ; $20
    db $D0,$36,$E1,$E9,$70,$DC,$CD,$2F,$4A,$67,$5D,$D2,$60,$B5,$9D,$7F ; $30
    db $45,$37,$50,$44,$78,$04,$19,$2C,$EF,$FD,$64,$81,$03,$DA,$95,$4C ; $40
    db $7A,$0B,$AD,$1F,$BA,$DD,$3E,$F9,$D7,$1A,$29,$F8,$18,$B3,$20,$F6 ; $50
    db $D1,$5E,$34,$92,$7B,$24,$43,$88,$97,$D4,$0F,$35,$AA,$83,$68,$27 ; $60
    db $A8,$D5,$BE,$FA,$14,$31,$AF,$10,$0D,$D8,$6A,$CE,$23,$61,$F3,$3D ; $70
    db $A4,$08,$33,$E3,$A9,$38,$E6,$93,$1D,$1C,$F0,$0E,$87,$59,$65,$82 ; $80
    db $BC,$FF,$FE,$7E,$8F,$C1,$1E,$F5,$CB,$49,$02,$32,$09,$C4,$8E,$C6 ; $90
    db $2B,$40,$A7,$17,$76,$3B,$16,$2A,$C8,$FB,$B2,$58,$A5,$15,$AE,$25 ; $A0
    db $CF,$46,$C7,$48,$B4,$0A,$3F,$C9,$06,$85,$51,$89,$62,$4D,$12,$8C ; $B0
    db $EA,$A2,$98,$4B,$79,$6F,$5C,$47,$30,$1B,$E7,$C5,$22,$9C,$E8,$96 ; $C0
    db $3A,$E4,$7C,$E0,$69,$A1,$B7,$05,$39,$74,$01,$9F,$BD,$C3,$84,$FC ; $D0
    db $77,$86,$13,$4E,$BF,$F2,$53,$5B,$ED,$21,$8B,$6D,$C2,$41,$B6,$DB ; $E0
    db $3C,$D3,$28,$EC,$2D,$E2,$9B,$A6,$42,$52,$57,$5F,$E5,$AB,$B0,$0C ; $F0
