; ============================================================
; Bank $FF — data, and the menu helpers at its end
; File offset 0x3F0000 (bank $FF = ROM offset $3F0000)
;
; $FF:0000-$FF:F547 is data (graphics, palettes and tables the menu and
; the field read) and stays as ROM bytes. $FF:F548-$FF:FC66 is menu
; code with its small tables, matched below: tile and palette builders,
; the save-slot code (save, load, check), the wave step and an HDMA
; table builder, reached by JSL from bank $C2. The bytes from $FF:FC67
; to the end are not reached (fragments of older builds of this code,
; by their look) and stay as ROM bytes.
; ============================================================

arch snes.cpu
hirom

org $FFF548
; ============================================================
; Menu helpers ($FF:F548–$FF:FC66)
; ============================================================

; $FF:F548 — BankFF_BuildTileSets (224 bytes, $F548–$F627)
; Builds tile sets in WRAM from the ten 2bpp tiles of MenuRom_GlyphRows
; (narrow glyphs, probably the digits 0-9: the code combines their
; right-hand pixels into tile pairs):
;   - copies the ten tiles into Menu_SprUnpackBuf 32 bytes apart (planes
;     0-1 of ten 4bpp tiles), then copies those $140 bytes on over the
;     next $C80 (eleven copies in all, $B000-$BDBF);
;   - into the first hundred tiles, tile g * 10 + t, ORs glyph g's rows
;     shifted left 5 (its three right-hand pixel columns moved to the
;     left edge) over glyph t: probably the two-digit numbers 00-99;
;   - zeroes Menu_SprScratch $9890-$989F and copies glyphs 1 and 2 after
;     it ($98A0-$98BF); then builds three groups of ten tiles at
;     Menu_TileSetC: each byte is the Menu_SprScratch byte (0, glyph 1 or
;     glyph 2, by group) shifted left 2 with bits 4-3 of glyph t's byte
;     below (probably 0-9, 10-19 and 20-29 in a narrower layout; not
;     traced); then zeroes the first 16 bytes of Menu_TileSetC.
; Menu_Unk51 is the start offset of both output loops, and of the glyph
; reads of the second (the caller keeps it 0, probably; not traced).
; Callers (1 JSL site): Menu_ShopInit ($C2:DB5B).
; Entry: M, X any (P saved; REP #$30 here), DP=0 (Menu_Tmp00-07,
;        Menu_Unk51), DB any (the first MVN sets $7E before the absolute
;        accesses)
; Exit:  P restored; DB=$7E (MVN); A, X, Y and DP $00-$07 clobbered
BankFF_BuildTileSets:
    PHP
    REP #$30
    LDX.w #!MenuRom_GlyphRows&$FFFF
    LDY.w #!Menu_SprUnpackBuf
.copy_glyph:
    LDA.w #!BankFF_GlyphBytes-1
    MVN !Bank7E,!BankFF                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    TYA
    CLC
    ADC.w #!BankFF_GlyphBytes
    TAY
    CPX.w #(!MenuRom_GlyphRows+(!BankFF_GlyphCount*!BankFF_GlyphBytes))&$FFFF
    BCC .copy_glyph
    LDX.w #!Menu_SprUnpackBuf
    LDY.w #!Menu_SprUnpackBuf+!BankFF_TileSetABytes
    LDA.w #!BankFF_TileSetACopies-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.b !Menu_Unk51
    ; Tile g * 10 + t |= glyph g << 5, byte by byte (Y runs through the hundred tiles).
    STZ.b !Menu_Tmp00
    SEP #$20
.group:
    LDA.b #!BankFF_GlyphCount
    STA.b !Menu_Tmp07
.tile:
    LDA.b #!BankFF_GlyphBytes
    STA.b !Menu_Tmp06
    LDX.b !Menu_Tmp00
.tile_byte:
    LDA.l !MenuRom_GlyphRows,X
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.w !Menu_SprUnpackBuf,Y
    STA.w !Menu_SprUnpackBuf,Y
    INX
    INY
    DEC.b !Menu_Tmp06
    BNE .tile_byte
    REP #$20
    TYA
    CLC
    ADC.w #!BankFF_GlyphBytes
    TAY
    SEP #$20
    DEC.b !Menu_Tmp07
    BNE .tile
    LDA.b !Menu_Tmp00
    CLC
    ADC.b #!BankFF_GlyphBytes
    STA.b !Menu_Tmp00
    CMP.b #!BankFF_GlyphCount*!BankFF_GlyphBytes
    BCC .group
    ; Menu_SprScratch: 16 zero bytes, then glyphs 1 and 2.
    REP #$30
    STZ.w !Menu_SprScratch
    LDX.w #!Menu_SprScratch
    LDY.w #!Menu_SprScratch+2
    LDA.w #!BankFF_ScratchClearBytes-3
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #(!MenuRom_GlyphRows+!BankFF_GlyphBytes)&$FFFF
    LDY.w #!Menu_SprScratch+!BankFF_ScratchClearBytes
    LDA.w #!BankFF_ScratchTableBytes-1
    MVN !Bank7E,!BankFF                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    ; Menu_TileSetC: three groups of ten tiles, (Menu_SprScratch byte << 2) | glyph bits 4-3.
    LDY.b !Menu_Unk51
    STZ.b !Menu_Tmp00
.row_group:
    LDX.b !Menu_Unk51
.row_tile:
    SEP #$20
    LDA.b #!BankFF_GlyphBytes
    STA.b !Menu_Tmp02
    LDA.b !Menu_Tmp00
    STA.b !Menu_Tmp06
.row_byte:
    LDA.l !MenuRom_GlyphRows,X
    STA.b !Menu_Tmp04
    PHX
    LDX.b !Menu_Tmp06
    LDA.w !Menu_SprScratch,X
    PLX
    ASL.b !Menu_Tmp04
    ASL.b !Menu_Tmp04
    ASL.b !Menu_Tmp04
    ASL.b !Menu_Tmp04
    ROL A
    ASL.b !Menu_Tmp04
    ROL A
    STA.w !Menu_TileSetC,Y
    INC.b !Menu_Tmp06
    INX
    INY
    DEC.b !Menu_Tmp02
    BNE .row_byte
    REP #$20
    TYA
    CLC
    ADC.w #!BankFF_GlyphBytes
    TAY
    CPX.w #!BankFF_GlyphCount*!BankFF_GlyphBytes
    BCC .row_tile
    LDA.b !Menu_Tmp00
    CLC
    ADC.w #!BankFF_GlyphBytes
    STA.b !Menu_Tmp00
    CMP.w #!BankFF_TileSetCGroups*!BankFF_GlyphBytes
    BCC .row_group
    STZ.w !Menu_TileSetC
    LDX.w #!Menu_TileSetC
    LDY.w #!Menu_TileSetC+2
    LDA.w #!BankFF_ScratchClearBytes-3
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLP
    RTL
; $FF:F628 — BankFF_LoadE4Palette (79 bytes, $F628–$F676)
; Copies a set of 12 colours from bank $E4 into Menu_PalBuf and marks it
; for upload (Menu_PalDirty counted up). DP $00 bits 0-2 pick the set (its
; address is entry n of MenuRom_E4Palettes, a word in bank $E4), and the
; same bits pick the place (XBA moves DP $00 into the high byte before the
; AND #$0700; DP $01 is not used): Menu_PalBuf + $122 + n * 32 (colours
; $91-$9C of palette 9 + n). When DP $02's high byte is non-zero each colour is
; halved first ((colour >> 1) & $3DEF).
; Callers (2 JSL sites): Menu_ShopToMembers ($C2:E038) and Menu_ShopDimMembers ($C2:E093).
; Entry: M, X any (P and X saved; REP #$30 here), DP=0 (Menu_Tmp00 and
;        Menu_Tmp02: the arguments), DB=$7E (Menu_PalDirty; the halved
;        path stores with STA abs,Y)
; Exit:  P and X restored; DB=$7E; A and Y clobbered; on the halved path
;        DP $00 = 0 (its counter)
BankFF_LoadE4Palette:
    PHX
    PHP
    REP #$30
    INC.w !Menu_PalDirty
    LDA.b !Menu_Tmp00
    XBA
    AND.w #!BankFF_PalRowMask
    LSR A
    LSR A
    LSR A
    ADC.w #!Menu_PalBuf+!BankFF_PalBufStart
    TAY
    LDA.b !Menu_Tmp00
    AND.w #!BankFF_PalSetMask
    ASL A
    ADC.l !MenuRom_E4Palettes
    TAX
    LDA.l !MenuRom_BankE4,X
    TAX
    LDA.b !Menu_Tmp02
    AND.w #!BankFF_PalHalveFlag
    BNE .halved
    LDA.w #!BankFF_PalBytes-1
    MVN !Bank7E,!BankE4                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLP
    PLX
    RTL
    ; Halved: 12 colours, each (colour >> 1) & $3DEF.
.halved:
    LDA.w #!BankFF_PalColours
    STA.b !Menu_Tmp00
.halved_colour:
    LDA.l !MenuRom_BankE4,X
    LSR A
    AND.w #!BankFF_PalHalveMask
    STA.w !Eng_PtrBase,Y
    INX
    INX
    INY
    INY
    DEC.b !Menu_Tmp00
    BNE .halved_colour
    PLP
    PLX
    RTL
; $FF:F677 — BankFF_BuildScreenMap (123 bytes, $F677–$F6F1)
; Unpacks MenuRom_ScreenGfx into Menu_SprUnpackBuf (Decomp_ToWramVec),
; sets Menu_Unk0D0E to $01FF, and builds a map at Menu_Bg3TileBuf: six
; pairs of identical 32-byte rows, each row the 16 tile words counting up
; from BankFF_ScreenMapTiles entry k; those $180 bytes are then copied on
; over the next $680 ($4F80-$55FF: the pattern repeated). Last it copies
; BankFF_ScreenColoursB to Menu_PalBuf + $30 and BankFF_ScreenColoursA to
; Menu_Unk9100. What screen this is for is not traced.
; Callers (1 JSL site): unmatched ($C2:CE86).
; Entry: M=1 (the first two stores are 8-bit LDA/STA before the REP), X
;        any, DP=0 (Menu_Tmp00-05), DB=$7E (the Decomp_* arguments at
;        $0300 and Menu_Unk0D0E are absolute)
; Exit:  P restored; DB=$7E; A, X, Y and DP $00-$05 clobbered
; Calls: Decomp_ToWramVec.
BankFF_BuildScreenMap:
    PHP
    LDA.b #!MenuRom_ScreenGfx>>16
    STA.w !Menu_DecompSrcBank
    LDA.b #!Bank7E
    STA.w !Menu_DecompDestBank
    REP #$30
    LDA.w #!MenuRom_ScreenGfx&$FFFF
    STA.w !Menu_DecompSrc
    LDA.w #!BankFF_ScreenGfxDest
    STA.w !Menu_DecompDest
    JSL Decomp_ToWramVec
    LDA.w #!BankFF_Unk0D0EInit
    STA.w !Menu_Unk0D0E
    STZ.b !Menu_Tmp00
    LDA.w #!Menu_Bg3TileBuf
    STA.b !Menu_Tmp02
    LDA.w #!BankFF_ScreenMapRows
    STA.b !Menu_Tmp04
.map_row:
    LDX.b !Menu_Tmp00
    LDA.l BankFF_ScreenMapTiles,X
    LDX.w #!BankFF_MapRowEntries
    LDY.b !Menu_Tmp02
.map_entry:
    STA.w !Eng_PtrBase,Y
    INC A
    INY
    INY
    DEX
    BNE .map_entry
    LDX.b !Menu_Tmp02
    LDA.w #!BankFF_MapRowBytes-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    STY.b !Menu_Tmp02
    INC.b !Menu_Tmp00
    INC.b !Menu_Tmp00
    DEC.b !Menu_Tmp04
    BNE .map_row
    ; Repeat the six row pairs over the rest of the buffer, then the colours.
    LDX.w #!Menu_Bg3TileBuf
    LDY.w #!Menu_Bg3TileBuf+!BankFF_ScreenMapHead
    LDA.w #!BankFF_ScreenMapFill-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #BankFF_ScreenColoursB
    LDY.w #!Menu_PalBuf+!BankFF_ScreenColoursBOfs
    LDA.w #!BankFF_ScreenColoursBBytes-1
    MVN !Bank7E,!BankFF                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDX.w #BankFF_ScreenColoursA
    LDY.w #!Menu_Unk9100
    LDA.w #!BankFF_ScreenColoursABytes-1
    MVN !Bank7E,!BankFF                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLP
    RTL

; $FF:F6F2 — BankFF_ScreenMapTiles (12 bytes, $F6F2–$F6FD)
; 6 tilemap words, the first entry of each row pair BankFF_BuildScreenMap
; writes (each next entry is one tile on).
BankFF_ScreenMapTiles:
    dw $1800,$1C10,$1820,$1830,$1C40,$1850

; $FF:F6FE — BankFF_ScreenColoursA (8 bytes, $F6FE–$F705)
; 4 words BankFF_BuildScreenMap copies to !Menu_Unk9100 (colours, probably,
; from the values; the reader is not traced).
BankFF_ScreenColoursA:
    dw $0614,$1770,$1748,$0614

; $FF:F706 — BankFF_ScreenColoursB (16 bytes, $F706–$F715)
; 8 colours BankFF_BuildScreenMap copies to !Menu_PalBuf + $30 (colours
; $18-$1F of the menu's CGRAM copy).
BankFF_ScreenColoursB:
    dw $0000,$1041,$1040,$1020,$001F,$0C20,$0C00,$0800

; $FF:F716 — BankFF_StepWave (67 bytes, $F716–$F758)
; Steps a wave and writes it out: Menu_WavePhase and Menu_WaveTick count
; up; every 4th call Menu_Unk0D0C counts up, Menu_Unk0D0E down and the
; phase goes back by 2 (a net drift of 1 back per 4 calls). Then for Y
; from Menu_Unk51 to $20 in steps of 2: Menu_WaveOut + Y = ScrollWaveFF_A
; entry (phase * 2 & $3E, then 4 bytes on per word) + Menu_Unk0D0C. The
; table reads run on into ScrollWaveFF_B (A's second period), so they
; need no wrap. There is no CLC: inside the loop C is clear (the BCC that
; loops), but the first ADC takes the C the 16-bit ASL of $0F10/$0F11 left
; (bit 7 of Menu_WaveTick). Kept as found; what the words drive is not
; traced ("Scroll" follows the bank $00 copy's guessed name).
; Callers (1 JSL site): unmatched ($C2:CECE).
; Entry: M any (SEP #$20 here), X any, DP=0 (Menu_Tmp00, Menu_Unk51),
;        DB=$7E (absolute RAM)
; Exit:  P restored; A, X, Y and DP $00-$01 clobbered
BankFF_StepWave:
    PHP
    SEP #$20
    INC.w !Menu_WavePhase
    INC.w !Menu_WaveTick
    LDA.w !Menu_WaveTick
    AND.b #!BankFF_WaveDriftMask
    BNE .no_drift
    INC.w !Menu_Unk0D0C
    DEC.w !Menu_Unk0D0E
    DEC.w !Menu_WavePhase
    DEC.w !Menu_WavePhase
.no_drift:
    REP #$30
    LDA.w !Menu_Unk0D0C
    STA.b !Menu_Tmp00
    LDA.w !Menu_WavePhase
    ASL A
    AND.w #!BankFF_WavePhaseMask
    TAX
    LDY.b !Menu_Unk51
.entry:
    LDA.l ScrollWaveFF_A,X
    ADC.b !Menu_Tmp00
    STA.w !Menu_WaveOut,Y
    INX
    INX
    INX
    INX
    INY
    INY
    CPY.w #!BankFF_WaveOutBytes
    BCC .entry
    PLP
    RTL

; ============================================================
; Wave tables ($FF:F759–$FF:F7D8)
; A byte-identical copy of ScrollWaveA/ScrollWaveB in bank $00
; ($C0:FF30–$C0:FFAF): one period of a sine-like wave between -6 and +6
; (32 signed 16-bit entries), stored twice. Read by BankFF_StepWave just
; before it (the only long reference to $FFF759), which steps 4 bytes per
; word and runs on from A into B, so B is A's second period and lets the
; loop read ahead without masking each index.
; ============================================================

ScrollWaveFF_A:         ; $FF:F759 (32 × sint16)
    dw  $0000,$0001,$0002,$0003,$0004,$0005,$0005,$0006
    dw  $0006,$0006,$0005,$0005,$0004,$0003,$0002,$0001
    dw  $0000,$FFFF,$FFFE,$FFFD,$FFFC,$FFFB,$FFFB,$FFFA
    dw  $FFFA,$FFFA,$FFFB,$FFFB,$FFFC,$FFFD,$FFFE,$FFFF

ScrollWaveFF_B:         ; $FF:F799 (32 × sint16: A's second period)
    dw  $0000,$0001,$0002,$0003,$0004,$0005,$0005,$0006
    dw  $0006,$0006,$0005,$0005,$0004,$0003,$0002,$0001
    dw  $0000,$FFFF,$FFFE,$FFFD,$FFFC,$FFFB,$FFFB,$FFFA
    dw  $FFFA,$FFFA,$FFFB,$FFFB,$FFFC,$FFFD,$FFFE,$FFFF

; $FF:F7D9 — BankFF_WidenTiles (58 bytes, $F7D9–$F812)
; Copies the ten 2bpp tiles of MenuRom_ShadowTiles into Menu_ShadowTiles
; 32 bytes apart, and sets each tile's plane-2 bytes (offset $10, $12 ...
; $1E) to plane 0 | plane 1 of the same row, so every drawn pixel also
; gets colour bit 2 (plane 3, offsets $11 ... $1F, is not written). What
; the tiles are is not traced.
; Callers (1 JSL site): Menu_ShowHealNumbers ($C2:8F6F).
; Entry: M, X any (P saved; REP #$30 here), DP=0 (Menu_Tmp00-02), DB any
;        (the first MVN sets $7E before the absolute accesses)
; Exit:  P restored; DB=$7E; A, X, Y and DP $00-$02 clobbered
BankFF_WidenTiles:
    PHP
    REP #$30
    LDX.w #!MenuRom_ShadowTiles&$FFFF
    LDA.w #!Menu_ShadowTiles
    STA.b !Menu_Tmp00
.tile:
    LDY.b !Menu_Tmp00
    LDA.w #!BankFF_GlyphBytes-1
    MVN !Bank7E,!BankFF                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    SEP #$20
    LDA.b #!BankFF_GlyphRows
    STA.b !Menu_Tmp02
    LDY.b !Menu_Tmp00
.row:
    LDA.w !Eng_PtrBase,Y
    ORA.w !Eng_PtrBase+1,Y
    STA.w !Eng_PtrBase+16,Y
    INY
    INY
    DEC.b !Menu_Tmp02
    BNE .row
    REP #$21
    LDA.b !Menu_Tmp00
    ADC.w #!BankFF_TileBytes
    STA.b !Menu_Tmp00
    CPX.w #(!MenuRom_ShadowTiles+(!BankFF_ShadowTileCount*!BankFF_GlyphBytes))&$FFFF
    BCC .tile
    PLP
    RTL
; $FF:F813 — BankFF_UnkF813 (318 bytes, $F813–$F950)
; Part of Menu_BuildItemTables' set-up of the tech data (meaning partly
; inferred). In order:
;   - Menu_Unk85 = Menu_PartyActive, or Menu_PartyTotal when
;     Eng_Unk7F0000 >= $49 and Menu_Flag7F00BA bit 0 is clear;
;     Menu_Unk86 = 0;
;   - bit 7 set in Menu_ItemInfo0 entries $09, $0C, $0F, $1A, $1D, $21,
;     $24, $27 and $29;
;   - BankFF_UnkF958 (the five combos' availability);
;   - Menu_TechShown byte i = Menu_TechBits byte i for each of the 37
;     bytes whose MenuRom_TechByteMembers lists no character missing
;     from Menu_PartyOrder (the others are left as they were);
;   - for each character 0-6: n = the number of its single techs shown
;     (bits set from bit 7 down; 8 with bit 0 set); unless its
;     Menu_Unk7F01E0 bit is set, it stops when n >= BankFF_TechStepLimit;
;     else the next tech's bit (BankFF_CharBits entry n; none when n = 8)
;     is set in Menu_TechShown, and Menu_ItemInfo0 entry char * 8 + n + 1
;     gets bit 6 over its bits 1-4 (the table's bytes past the items,
;     probably, used for the techs);
;   - through Menu_ListPtr = $7E:1640: for each of 15 records, three
;     pairs of MenuRom_TechMenuTiles bytes at the two offsets (64 * byte 1
;     / byte 2 of the record's MenuRom_TechMenuRec entry), the pointer
;     moving on one byte per pair; then, for each record again, one
;     MenuRom_TechLineTiles byte at 64 * n for each set bit n (from bit 7)
;     of MenuRom_TechLineBits, the pointer moving on one byte per record.
; What the $7E:1640 bytes are drawn as is not traced.
; Callers (1 JSL site): Menu_BuildItemTables ($C2:9973).
; Entry: M=0, X=0 (Menu_BuildItemTables' REP #$30; P is saved, SEP #$30
;        here), DP=0 (Menu_Tmp00-08, Menu_ListPtr, Menu_PartyActive...),
;        DB=$7E (absolute RAM); DP $05 = 0 assumed, not established: in
;        .line_tile X is 16-bit and LDX $04 reads DP $05 (never written
;        here) as the high byte of the MenuRom_TechLineTiles index
; Exit:  P restored; A, X, Y, DP $00-$04, $06-$09 and $16-$19 clobbered;
;        Menu_Unk85/86 set
; Calls: BankFF_UnkF958.
BankFF_UnkF813:
    PHP
    SEP #$30
    LDX.b !Menu_PartyActive
    LDA.l !Eng_Unk7F0000
    CMP.b #!Eng_Unk7F0000Min
    BCC .count_set
    LDA.l !Menu_Flag7F00BA
    BIT.b #!Menu_Flag7F00BABit0
    BNE .count_set
    LDX.b !Menu_PartyTotal
.count_set:
    STX.b !Menu_Unk85
    STZ.b !Menu_Unk86
    LDA.b #!Menu_ItemInfo0Unk80
    TSB.w !Menu_ItemInfo0+9
    TSB.w !Menu_ItemInfo0+12
    TSB.w !Menu_ItemInfo0+15
    TSB.w !Menu_ItemInfo0+26
    TSB.w !Menu_ItemInfo0+29
    TSB.w !Menu_ItemInfo0+33
    TSB.w !Menu_ItemInfo0+36
    TSB.w !Menu_ItemInfo0+39
    TSB.w !Menu_ItemInfo0+41
    JSL BankFF_UnkF958
    ; Menu_Tmp00 = the characters (bits 7-1) not in Menu_PartyOrder.
    LDA.b #!BankFF_AllCharsMask
    STA.b !Menu_Tmp00
    LDY.b #!BankFF_PartySlots-1
.absent_member:
    LDX.w !Menu_PartyOrder,Y
    BMI .next_member
    LDA.l BankFF_CharBits,X
    TRB.b !Menu_Tmp00
.next_member:
    DEY
    BPL .absent_member
    LDX.b #!BankFF_TechBytes-1
.copy_tech_byte:
    LDA.l !MenuRom_TechByteMembers,X
    AND.b !Menu_Tmp00
    BNE .next_tech_byte
    LDA.w !Menu_TechBits,X
    STA.w !Menu_TechShown,X
.next_tech_byte:
    DEX
    BPL .copy_tech_byte
    ; Next single tech of each character (Menu_Tmp02 = Menu_Unk7F01E0, bit 0 = character 0).
    LDA.l !Menu_Unk7F01E0
    STA.b !Menu_Tmp02
    LDY.b #$00
.char_techs:
    LDA.b #!BankFF_TechsPerChar
    STA.b !Menu_Tmp00
    LDA.w !Menu_TechShown,Y
.find_bit:
    LSR A
    BCS .bit_found
    DEC.b !Menu_Tmp00
    BNE .find_bit
.bit_found:
    LSR.b !Menu_Tmp02
    BCS .unlocked
    TYX
    LDA.b !Menu_Tmp00
    CMP.l BankFF_TechStepLimit,X
    BCS .next_char
.unlocked:
    LDX.b !Menu_Tmp00
    LDA.l BankFF_CharBits,X
    BEQ .next_char
    ORA.w !Menu_TechShown,Y
    STA.w !Menu_TechShown,Y
    TYA
    ASL A
    ASL A
    ASL A
    ADC.b !Menu_Tmp00
    TAX
    LDA.w !Menu_ItemInfo0+1,X
    AND.b #!Menu_ItemInfo0Mask
    ORA.b #!Menu_TechInfoLearnt
    STA.w !Menu_ItemInfo0+1,X
.next_char:
    INY
    CPY.b #!Pc_NumChars
    BCC .char_techs
    ; The 15 records through Menu_ListPtr ($7E:1640): three byte pairs each ...
    REP #$30
    STZ.b !Menu_Tmp06
    LDA.w #!Menu_TechMenuArea&$FFFF
    STA.b !Menu_ListPtr
    LDA.w #!Menu_TechMenuArea>>16
    STA.b !Menu_ListPtr+2
.menu_rec:
    REP #$30
    LDA.b !Menu_Tmp06
    ASL A
    ADC.b !Menu_Tmp06
    TAX
    ASL A
    STA.b !Menu_Tmp08
    LDA.l !MenuRom_TechMenuRec,X
    AND.w #!BankFF_HighByteMask
    LSR A
    LSR A
    STA.b !Menu_Tmp00
    LDA.l !MenuRom_TechMenuRec+1,X
    AND.w #!BankFF_HighByteMask
    LSR A
    LSR A
    STA.b !Menu_Tmp02
    SEP #$20
    LDX.b !Menu_Tmp08
    LDA.b #3
    STA.b !Menu_Tmp04
.menu_rec_tile:
    LDY.b !Menu_Tmp00
    LDA.l !MenuRom_TechMenuTiles,X
    STA.b [!Menu_ListPtr],Y
    INX
    LDY.b !Menu_Tmp02
    LDA.l !MenuRom_TechMenuTiles,X
    STA.b [!Menu_ListPtr],Y
    INC.b !Menu_ListPtr
    INX
    DEC.b !Menu_Tmp04
    BNE .menu_rec_tile
    INC.b !Menu_Tmp06
    LDA.b !Menu_Tmp06
    CMP.b #!BankFF_TechMenuRecs
    BCC .menu_rec
    ; ... then one byte per set bit of each record's MenuRom_TechLineBits.
    STZ.b !Menu_Tmp04
    STZ.b !Menu_Tmp06
.line:
    LDX.b !Menu_Tmp06
    LDA.l !MenuRom_TechLineBits,X
    STA.b !Menu_Tmp00
    STZ.b !Menu_Tmp02
    STZ.b !Menu_Tmp03
    DEC.b !Menu_Tmp03
.line_bit:
    INC.b !Menu_Tmp03
    ASL.b !Menu_Tmp00
    BCS .line_tile
    LDA.b !Menu_Tmp00
    BNE .line_bit
    INC.b !Menu_Tmp06
    INC.b !Menu_ListPtr
    LDA.b !Menu_Tmp06
    CMP.b #!BankFF_TechMenuRecs
    BCC .line
    PLP
    RTL
.line_tile:
    REP #$20
    LDA.b !Menu_Tmp02
    LSR A
    LSR A
    TAY
    LDX.b !Menu_Tmp04
    SEP #$20
    LDA.l !MenuRom_TechLineTiles,X
    STA.b [!Menu_ListPtr],Y
    INC.b !Menu_Tmp04
    BRA .line_bit

; $FF:F951 — BankFF_TechStepLimit (7 bytes, $F951–$F957)
; 1 B per character id 0-6, read by BankFF_UnkF813: a character whose
; !Menu_Unk7F01E0 bit is clear gets its next single tech marked only while
; the count it found is below this ($FF: always; 0: never).
BankFF_TechStepLimit:
    db $02,$02,$02,$FF,$02,$FF,$00

; $FF:F958 — BankFF_UnkF958 (99 bytes, $F958–$F9BA)
; Sets Menu_Unk04A4 entry c (c = 0-4) to 1 when combo c is available, else
; 0: all the characters in its MenuRom_ComboMembers are in Menu_PartyOrder
; and the three techs its MenuRom_ComboNeeds names (1-based bit numbers
; into Menu_TechBits) are all learned. Works with DP = Menu_CmdDp
; (Menu_AbsentChars, Menu_TechCombo...).
; Callers (2 JSL sites): Menu_Unk834D ($C2:837B) and BankFF_UnkF813 ($FF:F84B).
; Entry: M, X any (P and DP saved; SEP #$30 and DP = $0400 here), DP any,
;        DB=$7E (Menu_PartyOrder and Menu_TechBits are absolute)
; Exit:  P and DP restored; A, X, Y clobbered (8-bit values: with an X=0
;        caller their high bytes are 0); $04A0-$04A8 written
BankFF_UnkF958:
    PHD
    PHP
    SEP #$30
    PEA.w !Menu_CmdDp
    PLD
    LDA.b #!BankFF_AllCharsMask
    STA.b !Menu_AbsentChars-!Menu_CmdDp
    LDY.b #!BankFF_PartySlots-1
.absent_member:
    LDX.w !Menu_PartyOrder,Y
    BMI .next_member
    LDA.l BankFF_CharBits,X
    TRB.b !Menu_AbsentChars-!Menu_CmdDp
.next_member:
    DEY
    BPL .absent_member
    STZ.b !Menu_TechCombo-!Menu_CmdDp
.combo:
    LDX.b !Menu_TechCombo-!Menu_CmdDp
    STZ.b !Menu_Unk04A4-!Menu_CmdDp,X
    LDA.l !MenuRom_ComboMembers,X
    AND.b !Menu_AbsentChars-!Menu_CmdDp
    BNE .next_combo
    LDA.b !Menu_TechCombo-!Menu_CmdDp
    ASL A
    ADC.b !Menu_TechCombo-!Menu_CmdDp
    TAX
    LDA.b #$03
    STA.b !Menu_TechComboLeft-!Menu_CmdDp
.combo_need:
    LDA.l !MenuRom_ComboNeeds,X
    DEC A
    STA.b !Menu_TechComboBit-!Menu_CmdDp
    LSR A
    LSR A
    LSR A
    TAY
    LDA.b !Menu_TechComboBit-!Menu_CmdDp
    AND.b #$07
    PHX
    TAX
    LDA.l BankFF_CharBits,X
    PLX
    AND.w !Menu_TechBits,Y
    BEQ .next_combo
    INX
    DEC.b !Menu_TechComboLeft-!Menu_CmdDp
    BNE .combo_need
    LDX.b !Menu_TechCombo-!Menu_CmdDp
    INC.b !Menu_Unk04A4-!Menu_CmdDp,X
.next_combo:
    INC.b !Menu_TechCombo-!Menu_CmdDp
    LDA.b !Menu_TechCombo-!Menu_CmdDp
    CMP.b #!BankFF_ComboCount
    BCC .combo
    PLP
    PLD
    RTL

; $FF:F9BB — BankFF_CharBits (9 bytes, $F9BB–$F9C3)
; $80 >> n for n = 0-7, then 0: a character id's bit (as in
; !Menu_Unk29AF and the tech bytes). Read (long addressing; these are
; all nine references in the ROM) by Menu_CmdJoin ($C2:8C95),
; Menu_CanEquip (AND.l at $C2:93B8), BankFF_UnkF813 ($FF:F85A,
; $FF:F89B), BankFF_UnkF958 ($FF:F96B, $FF:F99D), and in unmatched
; code: LDA.l at $C2:BC07 and $C2:BCD0, AND.l at $C2:CD59. Entry 8 (0)
; is reached by BankFF_UnkF813 when bit 0 of a Menu_TechShown byte is
; set (its bit search starts at 8 and stops at the first set bit).
BankFF_CharBits:
    db $80,$40,$20,$10,$08,$04,$02,$01,$00

; $FF:F9C4 — BankFF_UnkF9C4 (55 bytes, $F9C4–$F9FA)
; Checks save slot DP $79 (low 2 bits): BankFF_SetSlotOfs, then with DB
; = $30 (SRAM): A = DP $00 (16-bit) = BankFF_SlotNoSign ($8080) when the
; slot's Menu_SramSlotSign is not BankFF_SlotSign, BankFF_SlotBadSum
; ($4040) when BankFF_SlotChecksum differs from its Menu_SramSlotSum,
; else 0.
; Callers note: Menu_LoadSlotSummaries runs it with DP=0 (DP $79 =
;   Menu_SlotIdx), Menu_CmdBootCheckSaves with DP = Menu_CmdDp (DP $79 =
;   Menu_SaveSlot); there the result also lands in $0400, the first
;   Menu_PlayTime byte (not traced whether that matters at boot).
; Callers (2 JSL sites): Menu_CmdBootCheckSaves ($C2:8D6E) and Menu_LoadSlotSummaries ($C2:D16D).
; Entry: M, X any (X, DB and P saved; REP #$30 here), DP as the caller
;        (DP $79, $7B and $00 relative to it), DB any (set to $30 here)
; Exit:  P, DB and X restored; A = the result (16 bits; the low byte
;        after an M=1 caller's PLP); Y clobbered; DP $00 = the result,
;        DP $7B = the slot's SRAM offset
; Calls: BankFF_SetSlotOfs, BankFF_SlotChecksum.
BankFF_UnkF9C4:
    PHX
    PHB
    PHP
    REP #$30
    PEA.w !BankFF_SramBanks
    PLB
    PLB
    JSR BankFF_SetSlotOfs
    LDA.b !Menu_SlotIdx
    AND.w #$0003
    ASL A
    TAX
    LDA.w !Menu_SramSlotSign,X
    CMP.w #!BankFF_SlotSign
    BNE .no_sign
    JSR BankFF_SlotChecksum
    CMP.w !Menu_SramSlotSum,X
    BNE .bad_sum
    LDA.w #$0000
    BRA .store
.no_sign:
    LDA.w #!BankFF_SlotNoSign
    BRA .store
.bad_sum:
    LDA.w #!BankFF_SlotBadSum
.store:
    STA.b !Menu_Tmp00
    PLP
    PLB
    PLX
    RTL
; $FF:F9FB — BankFF_SaveSlot (128 bytes, $F9FB–$FA7A)
; Saves the game to slot DP $79 (Menu_SlotIdx): Menu_Unk0414 = the slot;
; Menu_SaveCount counts up (it stays at $FFFF); then each
; BankFF_SaveRecords block goes to SRAM through Menu_NmiMoveCode, written
; as MVN to bank $30 (source bank patched per record) / RTL, starting at
; the slot's offset; then the slot's checksum and BankFF_SlotSign are
; stored, Menu_SramLastSlot = the slot, and Menu_SramUnk7FE1 counts up
; when it equals Menu_Unk299E. The records are copied to Menu_SprScratch
; first and read from Menu_Unk51 on (0, probably).
; Callers (1 JSL site): unmatched ($C2:CF51).
; Entry: M, X any (P saved; SEP #$20 / REP #$30 here), DP=0 (Menu_SlotIdx,
;        Menu_SlotSramOfs, Menu_Tmp00, Menu_Unk51), DB=$7E (absolute RAM;
;        saved around each move)
; Exit:  P restored; DB=$7E; A, X, Y, DP $00-$01 and $7B clobbered;
;        Menu_NmiMoveCode overwritten
; Calls: BankFF_SetSlotOfs, Menu_NmiMoveCodeLong, BankFF_SlotChecksum.
BankFF_SaveSlot:
    PHP
    SEP #$20
    LDA.b !Menu_SlotIdx
    STA.w !Menu_Unk0414
    REP #$30
    LDA.w !Menu_SaveCount
    INC A
    BEQ .count_kept
    STA.w !Menu_SaveCount
.count_kept:
    LDA.w #!BankFF_SaveMoveCode
    STA.w !Menu_NmiMoveCode
    LDA.w #!BankFF_SaveMoveCodeHi
    STA.w !Menu_NmiMoveSrcBank
    LDX.w #BankFF_SaveRecords
    LDY.w #!Menu_SprScratch
    LDA.w #!BankFF_SaveRecordsBytes-1
    MVN !Bank7E,!BankFF                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    ; Y = the slot's SRAM offset; each record: X = its address, A = length - 1.
    JSR BankFF_SetSlotOfs
    PHX
    TAY
    LDX.b !Menu_Unk51
.save_record:
    SEP #$20
    LDA.w !Menu_SprScratch+2,X
    STA.w !Menu_NmiMoveSrcBank
    REP #$20
    LDA.w !Menu_SprScratch,X
    STA.b !Menu_Tmp00
    LDA.w !Menu_SprScratch+3,X
    DEC A
    PHX
    LDX.b !Menu_Tmp00
    PHB
    JSL !Menu_NmiMoveCodeLong
    PLB
    PLA
    CLC
    ADC.w #!BankFF_SaveRecordBytes
    TAX
    CMP.w #!BankFF_SaveRecordsBytes
    BCC .save_record
    ; Checksum and signature; note the slot saved last.
    JSR BankFF_SlotChecksum
    PLX
    STA.l !Menu_SramSlotSumLong,X
    LDA.w #!BankFF_SlotSign
    STA.l !Menu_SramSlotSignLong,X
    SEP #$20
    LDA.b !Menu_SlotIdx
    STA.l !Menu_SramLastSlot
    LDA.l !Menu_SramUnk7FE1
    CMP.w !Menu_Unk299E
    BNE .done
    INC A
    STA.l !Menu_SramUnk7FE1
.done:
    PLP
    RTL

; $FF:FA7B — BankFF_SaveRecords (40 bytes, $FA7B–$FAA2)
; The blocks of a save slot, in order (BankFF_SaveSlot, BankFF_LoadSlot):
; 8 records of 5 B: address (2 B), bank (1 B), length (2 B). Their
; lengths add up to $834 B; the slot's checksum covers $A00 B.
BankFF_SaveRecords:
    dw $2400 : db $7E : dw $05B0        ; inventory and the party / config bytes ($2400-$29AF)
    dw $2C23 : db $7E : dw $0033        ; !Pc_CharNames and what follows
    dw $0400 : db $7E : dw $0010        ; play time and the bytes after it
    dw $0100 : db $00 : dw $0010
    dw $0000 : db $7F : dw $0200        ; !Menu_FlagBlock7F
    dw $027E : db $00 : dw $0002
    dw $0290 : db $00 : dw $0011
    dw $2C7C : db $7E : dw $001E        ; Battle_SavedCursor and the item cursor

; $FF:FAA3 — BankFF_LoadSlot (74 bytes, $FAA3–$FAEC)
; Loads slot Menu_SlotIdx back: the same BankFF_SaveRecords blocks, read
; from SRAM (Menu_NmiMoveCode as MVN from bank $30, destination bank
; patched per record), from the slot's offset on. No checksum test here.
; Callers (1 JSL site): Menu_Mode0EH1 ($C2:E657).
; Entry: M, X any (P saved; REP #$30 here), DP=0 (Menu_SlotIdx,
;        Menu_SlotSramOfs, Menu_Tmp00, Menu_Unk51), DB=$7E (absolute RAM)
; Exit:  P restored; DB=$7E; A, X, Y, DP $00-$01 and $7B clobbered;
;        Menu_NmiMoveCode overwritten
; Calls: BankFF_SetSlotOfs, Menu_NmiMoveCodeLong.
BankFF_LoadSlot:
    PHP
    REP #$30
    LDA.w #!BankFF_SaveMoveCode
    STA.w !Menu_NmiMoveCode
    LDA.w #!BankFF_LoadMoveCodeHi
    STA.w !Menu_NmiMoveSrcBank
    LDX.w #BankFF_SaveRecords
    LDY.w #!Menu_SprScratch
    LDA.w #!BankFF_SaveRecordsBytes-1
    MVN !Bank7E,!BankFF                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    JSR BankFF_SetSlotOfs
    TAX
    LDY.b !Menu_Unk51
.load_record:
    SEP #$20
    LDA.w !Menu_SprScratch+2,Y
    STA.w !Menu_NmiMoveDestBank
    REP #$20
    LDA.w !Menu_SprScratch,Y
    STA.b !Menu_Tmp00
    LDA.w !Menu_SprScratch+3,Y
    DEC A
    PHY
    LDY.b !Menu_Tmp00
    PHB
    JSL !Menu_NmiMoveCodeLong
    PLB
    PLA
    CLC
    ADC.w #!BankFF_SaveRecordBytes
    TAY
    CMP.w #!BankFF_SaveRecordsBytes
    BCC .load_record
    PLP
    RTL
; $FF:FAED — BankFF_LoadSlotPart (212 bytes, $FAED–$FBC0)
; Loads part of slot Menu_SlotIdx: the BankFF_PartRecords blocks (the
; inventory without $2980-$29AF, and the names), then
; Menu_Unk7F01E0 = the slot's byte $07E3; then puts each character 6-0
; back into its starting equipment: for the equipment offsets of
; BankFF_EquipOffsets (all four, or three for character 5, whose $29 byte
; is skipped), Menu_RunCommand $0A (equip) with the item id from its
; MenuRom_CharRecordInit record ($CC:0000 + character * $50, through
; Menu_ListPtr); then commands 6 and 7 (the refills). Last it empties every
; inventory slot (of $F2) whose item has Menu_ItemInfo0 bit 4, and sets
; Menu_Unk7F01CF to $10. Probably the start of a new game from a cleared
; save (items and names kept, equipment reset); not traced.
; Callers (1 JSL site): Menu_Mode0EH2 ($C2:E6D8).
; Entry: M, X any (P saved; REP #$30 here), DP=0 (Menu_SlotIdx,
;        Menu_SlotSramOfs, Menu_Tmp00-05, Menu_ListPtr, Menu_Unk51),
;        DB=$7E (absolute RAM)
; Exit:  P restored; DB=$7E; A, X, Y, DP $00-$05, $16-$18 and $7B
;        clobbered; Menu_NmiMoveCode overwritten
; Calls: BankFF_SetSlotOfs, Menu_NmiMoveCodeLong, BankC2_Entry8004
;        (Menu_RunCommand).
BankFF_LoadSlotPart:
    PHP
    REP #$30
    LDA.w #!BankFF_SaveMoveCode
    STA.w !Menu_NmiMoveCode
    LDA.w #!BankFF_LoadMoveCodeHi
    STA.w !Menu_NmiMoveSrcBank
    LDX.w #BankFF_PartRecords
    LDY.w #!Menu_SprScratch
    LDA.w #!BankFF_PartRecordsBytes-1
    MVN !Bank7E,!BankFF                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    JSR BankFF_SetSlotOfs
    TAX
    LDY.b !Menu_Unk51
.load_record:
    SEP #$20
    LDA.w !Menu_SprScratch+4,Y
    STA.w !Menu_NmiMoveDestBank
    REP #$21
    LDA.w !Menu_SprScratch,Y
    ADC.b !Menu_SlotSramOfs
    TAX
    LDA.w !Menu_SprScratch+2,Y
    STA.b !Menu_Tmp00
    LDA.w !Menu_SprScratch+5,Y
    DEC A
    PHY
    LDY.b !Menu_Tmp00
    PHB
    JSL !Menu_NmiMoveCodeLong
    PLB
    PLA
    CLC
    ADC.w #!BankFF_PartRecordBytes
    TAY
    CMP.w #!BankFF_PartRecordsBytes
    BCC .load_record
    ; Menu_Unk7F01E0 from the slot.
    SEP #$20
    LDX.b !Menu_SlotSramOfs
    LDA.l !Menu_SramUnk07E3,X
    STA.l !Menu_Unk7F01E0
    ; Starting equipment of characters 6-0 (Menu_RunCommand $0A per item).
    SEP #$20
    LDA.b #!Pc_NumChars-1
    STA.b !Menu_Tmp00
.char:
    LDA.b !Menu_Tmp00
    STA.l WRMPYA
    LDA.b #!Menu_CharRecBytes
    STA.l WRMPYB
    LDA.b #!MenuRom_CharRecordInit>>16
    STA.b !Menu_ListPtr+2
    REP #$31
    LDA.w #3
    STA.b !Menu_Tmp04
    LDA.l RDMPYL
    ADC.w #$0000
    STA.b !Menu_ListPtr
    CMP.w #!Pc_CharAyla*!Menu_CharRecBytes
    BNE .equip_count
    DEC.b !Menu_Tmp04
.equip_count:
    SEP #$30
.equip:
    LDX.b !Menu_Tmp04
    LDA.l BankFF_EquipOffsets,X
    TAY
    LDA.b [!Menu_ListPtr],Y
    TAX
    LDY.b !Menu_Tmp00
    LDA.b #!Menu_CmdIdEquip
    JSL BankC2_Entry8004
    DEC.b !Menu_Tmp04
    BPL .equip
    DEC.b !Menu_Tmp00
    BPL .char
    LDA.b #!Menu_CmdIdRefillWord3
    JSL BankC2_Entry8004
    LDA.b #!Menu_CmdIdRefillByte7
    JSL BankC2_Entry8004
    ; Drop the inventory slots whose item has Menu_ItemInfo0 bit 4.
    SEP #$30
    LDX.b #$00
.inv_slot:
    LDY.w !Menu_InvIds,X
    BEQ .next_inv_slot
    LDA.w !Menu_ItemInfo0,Y
    AND.b #!Menu_ItemInfo0Unk10
    BEQ .next_inv_slot
    LDA.b #$00
    STA.w !Menu_InvIds,X
    STA.w !Menu_InvCounts,X
.next_inv_slot:
    INX
    CPX.b #!BankFF_InvSlots
    BCC .inv_slot
    LDA.b #!BankFF_Unk7F01CFValue
    STA.l !Menu_Unk7F01CF
    PLP
    RTL

; $FF:FBC1 — BankFF_PartRecords (14 bytes, $FBC1–$FBCE)
; BankFF_LoadSlotPart's blocks: 2 records of 7 B: offset in the slot
; (2 B), address (2 B), bank (1 B), length (2 B). The first stops $30 B
; short of the first BankFF_SaveRecords block, so $2980-$29AF (party
; order and config) are not loaded.
BankFF_PartRecords:
    dw $0000,$2400 : db $7E : dw $0580
    dw $05B0,$2C23 : db $7E : dw $0033

; $FF:FBCF — BankFF_EquipOffsets (4 bytes, $FBCF–$FBD2)
; Offsets of four equipment bytes in a character record ($27, $28, $2A,
; $29), read backwards by BankFF_LoadSlotPart (entry 3, the $29 byte, is
; left out for character 5).
BankFF_EquipOffsets:
    db $27,$28,$2A,$29

; $FF:FBD3 — BankFF_SetSlotOfs (14 bytes, $FBD3–$FBE0)
; Menu_SlotSramOfs (DP $7B) = BankFF_SlotSramOfs entry DP $79 & 3.
; Callers (4 JSR sites): BankFF_UnkF9C4 ($FF:F9CE), BankFF_SaveSlot ($FF:FA26), BankFF_LoadSlot
;   ($FF:FABE) and BankFF_LoadSlotPart ($FF:FB08).
; Entry: M=0, X=0 (16-bit AND and TAX), DP as the caller's (DP $79 and $7B
;        relative to it), DB any (long read)
; Exit:  RTS; M=0, X=0; A = the offset, X = slot * 2; Y unchanged
BankFF_SetSlotOfs:
    LDA.b !Menu_SlotIdx
    AND.w #!BankFF_SlotMask
    ASL A
    TAX
    LDA.l BankFF_SlotSramOfs,X
    STA.b !Menu_SlotSramOfs
    RTS

; $FF:FBE1 — BankFF_SlotSramOfs (6 bytes, $FBE1–$FBE6)
; SRAM offset of save slots 0-2 ($A00 B apart).
BankFF_SlotSramOfs:
    dw $6000,$6A00,$7400

; $FF:FBE7 — BankFF_SlotChecksum (29 bytes, $FBE7–$FC03)
; Sums the $500 words of the slot at Menu_SlotSramOfs (DP $7B) in SRAM
; (bank $30, through DP $00 as a pointer), with the carry of each ADC
; going into the next.
; Callers (2 JSR sites): BankFF_UnkF9C4 ($FF:F9E0) and BankFF_SaveSlot ($FF:FA54).
; Entry: M, X any (P and DB saved; REP #$30 and DB = $30 here), DP as the
;        caller's (DP $7B, $00)
; Exit:  RTS; P and DB restored; A = the sum (16 bits; with an M=1 caller
;        the high byte is in B); Y = $FFFE (16-bit); DP $00-$01 = the
;        slot's offset
BankFF_SlotChecksum:
    PHP
    PHB
    REP #$30
    PEA.w !BankFF_SramBanks
    PLB
    PLB
    LDA.b !Menu_SlotSramOfs
    STA.b !Menu_Tmp00
    LDY.w #!BankFF_SlotSumBytes-2
    LDA.w #$0000
    CLC
.word:
    ADC.b (!Menu_Tmp00),Y
    DEY
    DEY
    BPL .word
    PLB
    PLP
    RTS
; $FF:FC04 — BankFF_BuildGradHdma (83 bytes, $FC04–$FC56)
; Points DMA channel 1's table (A1T1L/H) at Menu_GradHdma and builds an
; HDMA table there: $60 lines with the two bytes $00, $E0, then 16
; groups of three 1-line entries with the bytes $02 (groups 0-7) or $82
; (groups 8-15) and BankFF_GradValues entry g, and an end byte. Which
; registers channel 1 writes is not set here (the values fit CGADSUB /
; COLDATA: colour math adding, then subtracting, a fixed colour stepping
; down and up; probably).
; Callers (1 JSL site): Menu_NameInit ($C2:E503).
; Entry: M, X any (P saved; REP #$30 then SEP #$30 here), DP=0
;        (Menu_Tmp00-02), DB=$7E (Menu_GradHdma is absolute; A1T1L long)
; Exit:  P restored; A, X, Y and DP $00-$02 clobbered
BankFF_BuildGradHdma:
    PHP
    REP #$30
    LDA.w #!Menu_GradHdma
    STA.l A1T1L
    LDX.w #!BankFF_GradHdmaHead
    STX.w !Menu_GradHdma
    LDA.w #!BankFF_GradHdmaHead2
    STA.w !Menu_GradHdma+2
    STZ.w !Menu_GradHdmaEnd
    SEP #$30
    STZ.b !Menu_Tmp02
    LDA.b #$02
    STA.b !Menu_Tmp00
    LDY.b #$03
.group:
    LDA.b #$03
    STA.b !Menu_Tmp01
.entry:
    LDA.b #$01
    STA.w !Menu_GradHdma,Y
    INY
    LDA.b !Menu_Tmp00
    STA.w !Menu_GradHdma,Y
    INY
    LDX.b !Menu_Tmp02
    LDA.l BankFF_GradValues,X
    STA.w !Menu_GradHdma,Y
    INY
    DEC.b !Menu_Tmp01
    BNE .entry
    INC.b !Menu_Tmp02
    LDA.b !Menu_Tmp02
    CMP.b #!BankFF_GradHalf
    BCC .next_group
    LDX.b #!BankFF_GradValue2
    STX.b !Menu_Tmp00
.next_group:
    CMP.b #!BankFF_GradGroups
    BCC .group
    PLP
    RTL

; $FF:FC57 — BankFF_GradValues (16 bytes, $FC57–$FC66)
; The third byte of each BankFF_BuildGradHdma group: $E8 down to $E0, then
; $E1 up to $E7 (COLDATA-style values, probably; the register channel 1
; feeds is not set here).
BankFF_GradValues:
    db $E8,$E7,$E6,$E5,$E4,$E3,$E2,$E1,$E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7
