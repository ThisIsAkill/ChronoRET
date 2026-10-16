# Data plan

How the rest of the ROM, everything the 65816 and SPC700 source does not emit yet, can be
described in source, so that one day the build no longer copies bytes from the original ROM.
The measured map is `symbols/data_survey.csv` (one row per region); `python3 tools/data_survey.py`
checks that it covers exactly the bytes `tools/verify.py` does not count as emitted, and prints
the totals below. Survey of 2026-10-15, from `main` at 306,435 emitted bytes (280,042 assembled,
plus the packed `$C3` module, 26,393 bytes, which `tools/c3pack.py` packs from source since PR #113
and verify counts apart).

## What is left

3,887,869 bytes (92.69% of the 4,194,304-byte ROM) in 2,244 rows. Shares are of the whole ROM.

| kind | bytes | share | rows | confirmed / probable / unknown |
|---|---:|---:|---:|---|
| packed_lz | 2,349,626 | 56.02% | 1,515 | 2,346,617 / 3,009 / 0 |
| graphics (raw tiles) | 336,704 | 8.03% | 28 | 328,416 / 8,288 / 0 |
| sprite_layout | 253,952 | 6.05% | 5 | 253,952 / 0 / 0 |
| text | 206,826 | 4.93% | 49 | 205,047 / 1,779 / 0 |
| brr_sample | 203,202 | 4.84% | 66 | 203,202 / 0 / 0 |
| table | 177,310 | 4.23% | 298 | 174,654 / 2,134 / 522 |
| music_sequence | 107,721 | 2.57% | 87 | 104,092 / 3,629 / 0 |
| battle_script | 102,763 | 2.45% | 12 | 102,763 / 0 / 0 |
| padding | 65,391 | 1.56% | 78 | 62,206 / 3,185 / 0 |
| palette | 32,062 | 0.76% | 46 | 24,812 / 7,250 / 0 |
| tilemap | 19,717 | 0.47% | 10 | 19,717 / 0 / 0 |
| font | 9,216 | 0.22% | 2 | 9,216 / 0 / 0 |
| event_script (scene animation table) | 7,946 | 0.19% | 1 | 7,946 / 0 / 0 |
| unknown | 8,657 | 0.21% | 42 | 0 / 0 / 8,657 |
| map (exit and treasure records) | 6,694 | 0.16% | 2 | 6,694 / 0 / 0 |
| spc_data | 82 | 0.00% | 3 | 82 / 0 / 0 |

Confidence over all 3,887,869 bytes: confirmed 3,849,416 (99.01%), probable 29,274 (0.75%),
unknown 9,179 (0.24%). "Confirmed" means a matched routine, or a pointer table a matched routine
reads, reaches the region and the code fixes its format. Of the confirmed bytes, 476,026
(12.4%) are in rows whose start is reached but whose end is inferred (it runs to the next known
region; the row's notes say so). In the tables that share is 40% (70,780 of 177,310 bytes). How
far each named table really runs is the main thing the per-kind work below still has to settle.

### The packed bytes, by content

Every `packed_lz` row is one Decomp_ToWram stream (`$C3:0002`), and every one of the 1,515
repacks byte-exact with the packer of `tools/c3pack.py`:
`python3 tools/data_survey.py --packs` checks all of them (about 20 s).
960 use 11-bit offsets, 555 12-bit. Unpacked they hold 4,009,024 bytes.

| content (pointer table) | packed | unpacked | packs |
|---|---:|---:|---:|
| location tile graphics, also battle backgrounds (`LocGfx_PackPtrs`) | 607,874 | 844,704 | 205 |
| object sprite tiles, 4bpp (`BattleRom_SprTilesPtr` = `Field_E4Ptr0`) | 540,847 | 699,872 | 241 |
| location maps: MapProps header and tile planes (`Map_PropsPtrs`) | 384,096 | 1,003,373 | 201 |
| location event scripts (`Evt_PackPtrs`) | 317,832 | 568,478 | 461 |
| layer 1/2 metatiles (`LocGfx_Meta12Ptrs`) | 163,353 | 221,194 | 64 |
| scene BG graphics (`C2SceneRom_BgPacks`) | 104,984 | 137,616 | 37 |
| data of the `$C3` module (`C3Rom_PackPtrs`) | 89,860 | 186,928 | 57 |
| scene sprite graphics (`C2SceneRom_ObjPacks`) | 30,592 | 65,536 | 14 |
| scene BG maps, metatiles, BG3 maps, palettes, lists, `$7000`/`$7200` data | 51,857 | 166,270 | 57 |
| scene dial pixels and palette (`C2Scene_DialPacks`, `$C2:7220`) | 4,302 | 12,352 | 3 |
| scene scripts (`C2SceneRom_ScriptPacks`) | 17,112 | 27,757 | 8 |
| battle action sprite frames (word table at `$D1:0000`) | 13,830 | 16,962 | 119 |
| layer 3 metatiles (`LocGfx_Meta3Ptrs`) | 12,839 | 38,912 | 19 |
| battle background maps (`BattleRom_BgMapPtrs`) | 6,525 | 12,288 | 6 |
| menu screen data (`MenuRom_ScreenGfx`) | 684 | 1,536 | 1 |
| no pointer found (probable) | 3,009 | 5,246 | 12 |
| empty packs (3 bytes, reached by tables) | 30 | 0 | 10 |

## How the survey was made

1. The emitted ranges come from `tools/verify.py` (the source on all-$00 and all-$FF bases).
2. Packs: a scan of every unemitted offset for a stream Decomp_ToWram reads to its end marker
   that `c3pack.pack` rebuilds byte for byte (1,591 hits, the now-emitted module left out). A hit counts as a pack when a pointer
   table read by matched code points at it: the eighteen long-pointer tables the decompressor's
   42 callers index (listed in Decomp_ToWramVec's header, `$C3:0002`), the word table at
   `$D1:0000` (BattleAct_LoadCommon), `C2Scene_DialPacks` (`$C2:7220`), `Credits_GfxPack` and
   `MenuRom_ScreenGfx`. 12 unreferenced hits of 40 bytes or more are kept as probable packs;
   the other 86 hits are small (up to 30 bytes), lie inside tables, text and tiles, and are
   chance. Entries 0-6 of `BattleRom_SprTilesPtr` point at raw tiles whose first 3 bytes happen
   to read as an empty pack; they are tiles (Battle_InitScene copies them raw, Menu_SprLoad skips
   the unpack for kind 0, Spr_CopyTile reads pointer + tile * 32).
3. Named data: every ROM address the source names (the `!*Rom*` defines and the ROM structs in
   `asm/include/`, 445 names) starts a row that runs to the next name or known region; the
   readers are the routines whose code uses the name.
4. Regions with their own readers, measured from the tables the code reads: the sound data
   (`Audio_SampleTable` and `Audio_SongTable` in bank `$C7`: 62 samples and 83 songs, back to
   back from `$C7:730D` to `$CB:F163`, and the boot blocks), the message tables (found from the
   event op `$B8` operands, Evt_OpB8_SetMsgPtr, in the unpacked event scripts; 15 tables, about
   4,600 string pointers, each table's end is the end of its last string), the dictionary
   (`TextWin_DictPtrs`), the battle script and object areas (the offset tables at
   `$CD:5EC6`-`$6E0B` and `$CE:0000`), exits, treasure and location records, the sprite frame
   data (the 256 long pointers at `$E4:2300`) and the character sprite tiles (entries 0-6 of
   `$E4:2000` point at raw tiles in `$D2`-`$D5`, not at packs).
5. Fill: runs of one value (16 bytes or more, or a whole gap of $00/$FF) are padding; a run of
   64 or more at the end of a region whose end was only inferred is split off as padding,
   confirmed only where the reader's index range ends before it (else probable); where a reader's
   index range covers such bytes (offset tables with $FFFF entries, `BattleRom_Kind3Act`,
   `BattleRom_InitTiles2bpp`) they stay in the table.
6. The rest is listed one row each, with what is known (`unknown`, 42 rows).

## Per kind: what a byte-exact round trip needs

Effort is in working sessions of the size this project's matching sessions have been. Every
step ends the same way: the bytes come from source and assets instead of the ROM copy, and
`make gate` stays byte-exact.

**Fill and padding** (65 KB). A fill directive per row (value and count are in the CSV). No
risk. A few rows of stale bytes (`unknown`) sit beside the fill and stay raw blobs.
Difficulty trivial; with step 1 below.

**Packed streams** (2.35 MB, 56%). Store the unpacked contents and pack at build time; the
packer exists and is exact for every stream (Okumura's LZSS with the original's changes, the
two-segment framing and the per-stream mode, all in `tools/c3pack.py`). What the round trip has
to record: the mode of each stream (11 or 12 bit); the placement (streams sit back to back,
in table order in most banks, with a few gaps of stale bytes); and the pointer tables, which
become `dl Label` entries, except the entries that point at stale or non-pack bytes (Evt_PackPtrs
102-110, 231-235, 320-322; LocGfx_PackPtrs 204-210 and 212-218, entry 211 being the pack at
`$F6:8000`; LocGfx_Meta3Ptrs 19-22; Map_PropsPtrs 201) and the tables with duplicate entries,
which must keep their exact values. Some of those entries are still selected (Evt_PackPtrs
231-235 by LocRom records 448 and 452-455, 320-322 by 461-463; LocGfx_PackPtrs 204, 211 and 212
by tileset 54, which no location uses). The 10 empty packs are 3 bytes each. Build time: packing all 4 MB in Python takes about 20 s, so the build should
cache the packed output (as c3pack's module build does). Difficulty low; 1-2 sessions (the
packer and a packed build path exist since PR #113). Readable formats for the unpacked
contents are separate, later work (graphics to PNG, maps, event and scene script disassembly,
below).

**Raw graphics** (337 KB) and **font** (9 KB). Mostly 4bpp sprite tiles (the seven characters'
sprite tiles in `$D2`-`$D5`, 236 KB), the battle effect tiles (`$CF:0000` 2bpp, `$D0:0000`
2bpp with a third plane for some), menu tiles (2bpp, 4bpp, the 3bpp set `Menu_Expand3bppTiles`
widens) and the text font (24-byte glyphs split into left 8 and right 4 pixels). A tile-to-PNG
converter per format is lossless (a tile format has no encoder choices). Difficulty low; 1
session for blobs, 2-3 for PNG converters with the palettes they need. The ends of the
character tile blocks are inferred (each runs to the next block); the highest tile number the
frame data uses would confirm them.

**BRR samples** (203 KB, 63 samples counting the built-in one). Store each as a `.brr` file with
its length word generated. BRR is a lossy encoding with encoder choices, so a WAV round trip
cannot be byte-exact; keep the BRR bytes. Loop points and envelope words are already in source
(`Audio_SampleLoop`, `Audio_SampleParamA/B`). Difficulty low; half a session.

**Music sequences** (108 KB). 83 songs (a length word, then the driver's byte code), the sound
effect block for ARAM `$2F00` and its alternate, and one orphan song at `$CB:F164` that no table
reaches. As blobs: trivial. As readable sequences: a disassembler driven by the matched SPC700
driver's command table (command lengths), with the songs' internal pointers turned into labels.
Those pointers are in each song header's own origin space: the driver rebases each track
pointer by `!AudioAram_Song + !SpcSong_Data - !SpcSong_Origin` (the header word at
`!SpcSong_Origin`; the header of the song start in `asm/spc700/driver.asm`, lines 1951-1954), so
a label must be written relative to the header's origin, not to `$2000`. The effect tracks sit
at `$2F00`. Note
`Audio_SongTable` is not in address order (songs `$0E`/`$0F` are swapped in ROM). Difficulty
medium; 2-3 sessions.

**Text** (208 KB). 15 message tables (word pointers, then strings), the dictionary at
`$DE:FA00` (127 entries for codes `$21`-`$9F`, and a 128th word reached only by code `$12`
with argument `$68`, which no message string uses), the treasure strings, the scene labels and the fixed-length name tables in `$CC`.
The decoder is matched (TextWin_State0 and TextWin_CodeTable): `$A0`-`$FF` glyphs, `$21`-`$9F`
dictionary sub-strings, `$00`-`$20` control codes (`$01`, `$02`, `$03` and `$12` take one byte;
`$00` ends). The order-dependent part is the dictionary: a text-to-bytes encoder must choose the
same dictionary substitutions the original tool made. Two ways: keep dictionary references
explicit in the source text (always exact), or find the original rule (probably a greedy longest
match over a fixed entry order; testable over the 4,600 strings) and fall back to explicit
references where it differs. The string pointer tables follow from string lengths, but events
point into the middle of five tables (op `$B8` with an address inside the tables at `$F7:0000`,
`$F7:4900`, `$F8:4650`, `$F9:B000` and `$FC:BA00`), and a few
stale strings sit between tables (rows marked probable), so the tables keep labels for those.
Difficulty medium; 2-4 sessions. Done (step 5, below): the original rule is a greedy longest
match, left to right over each run of glyphs, with dictionary entries 116-118 left out.

**Tables** (178 KB in 298 rows) and **palettes** (32 KB). Battle data in `$CC` (items, techs,
enemies, growth, shop lists), `$CD`/`$CE` action records, `$E4` animation lists, `$F6` location
records, menu draw lists in `$FF`, and so on: every one has a named reader and a define comment
with its record layout. Work: `db`/`dw` with the record as an asar struct or macro, word offsets
turned into labels, and each table's true length settled from its reader (many ends are inferred
now). Palettes are BGR555 words. Difficulty low to medium per table, but many; 3-5 sessions.

**Battle scripts** (103 KB). Action scripts (`BattleAct` opcodes `$00`-`$DA`, lengths fixed by
the matched opcode handlers and `BattleAct_OpcodeTable`), subscripts, the enemy behaviour scripts
(`$CC:8B08`, the `BattleAi_*` tables give the test and action record lengths; `BattleFD_AiActLength`
for actions), and the layer-effect scripts and maps in `$D1`. Offset tables use `$FFFF` for
"none". A disassembler per script language. Difficulty medium-high; 3-5 sessions.

**Sprite layout** (254 KB). The frame records the 256 pointers at `$E4:2300` reach (banks `$DC`,
`$DD`, `$DE`, `$E1`, `$E3`). As blobs: trivial. As readable frames: the record layout from
the Spr_* builders and Battle_InitScene; difficulty medium, 2 sessions.

**Maps, tilemaps, event and scene scripts.** Exits and treasure records are fixed-size structs
(`ExitRom`, `TreasureRom`, with per-location offset tables): low. The location event scripts
(568 KB unpacked, 461 streams) need a disassembler over `Evt_OpcodeTable`'s 256 handlers (each
handler's operand length is in its code: the X it returns), with jumps turned into labels;
difficulty medium-high, 3-6 sessions. Scene scripts (C2Scene bytecode, `C2SceneRom_ScriptPacks`)
and the scene animation table at `$C3:E000`: 2-3 sessions. Map tile planes and metatiles stay
binary unless an editor-friendly form is wanted.

**Unknown and probable** (33 KB). Mostly stale data beside unused pointer-table entries (a pack
that no longer decodes, old strings, a song no table reaches). They stay raw blobs with their
own labels; 1 session to re-check each with an emulator trace.

## Where the data layer stands (steps 2-4)

Done on the `data-packs` branch. `make build` no longer starts from a copy of the ROM:
`tools/build_rom.py` extracts the assets (`tools/extract_data.py extract`, into the ignored
`build/assets/`, checked against `rom.sha256`), packs the module and the 1,515 data packs from
their unpacked assets (cached per pack by asset, mode and packer), and assembles `asm/rom.asm`
(`asm/main.asm`, then the generated `asm/data/`) onto blank `$00` and `$FF` images, which must
be identical. The placement is generated from this survey and committed: per bank, one piece
per row (a pointer-table row with a partial last entry is two), each with an `org` and a label
(the survey's name, else the pointer table and entry that reach it, a sample or song number, or
kind and address). `symbols/data_assets.csv` is its manifest. Pieces:

| piece | bytes | how |
|---|---:|---|
| fill | 65,391 | the 78 padding rows, `fill` of the value in the survey (source) |
| table | 5,044 | 20 pointer tables of labels (source; below) |
| extracted | 1,248,980 | 493 blobs (485 rows, 8 table tails) incbin'd from `build/assets/<kind>/<label>.bin` |
| packed | 2,031,791 | 1,053 streams packed at build time from their unpacked assets |
| events | 317,835 | the 462 location event script packs, packed at build time from scripts assembled from their disassembly (step 7, below) |
| text | 202,895 | 45 rows in 31 text units, encoded at build time from readable text (step 5, below) |
| records | 15,933 | 101 rows: 73 tables (15,245 B) and 28 palettes (688 B), encoded at build time from readable records (step 6, below) |

`tools/verify.py` reports these seven apart from the code figures, which do not change; with
the code's 306,435 bytes they account for all 4,194,304. The tables written as labels are the
ten `C2SceneRom_*Packs`, `BattleRom_BgMapPtrs`, `BattleRom_PcAttackFrames` and
`BattleRom_ActFrames` (words), `BattleRom_SprTilesPtr`, `Map_PropsPtrs`, `LocGfx_Meta12Ptrs`,
`LocGfx_Meta3Ptrs`, `LocGfx_PackPtrs`, `Evt_PackPtrs` and `C3Rom_PackPtrs`: every entry is a
label, a label plus an offset (an entry into the middle of a row: the stale entries listed above,
the module's raw blocks in `$FE`) or `$000000`; five stale `LocGfx_PackPtrs` entries (206-210)
point into bank `$FD` code and are written relative to the code label before them. That is a
label in name only: the offset restates the stored pointer value, which no reader uses (no
LocRom record selects those entries); it keeps the table free of raw numbers, nothing more.

Left:

- **Code-side references to packs.** The code reaches the data through defines
  (`!Credits_GfxPack`, `!MenuRom_ScreenGfx`, `!C3Rom_PackPtrs`, ...) and `C2Scene_DialPacks`
  (`$C2:7220`) holds raw words, because `asm/main.asm` is assembled without the data layer by
  every measuring tool. `tools/extract_data.py` checks that each survey name that is a define or
  a ROM struct holds the address of the piece placed there. Making them labels needs the code
  tools to assemble `asm/rom.asm`.
- **Pointer tables inside other rows** (step 6 onward): `BattleRom_SprFramesPtr` (`$E4:2300`),
  the `$E4` animation offset tables, the offset tables of the battle scripts. (The text's
  tables are labels in its readable form, step 5.)
- **Readable formats**: every extracted piece is still a binary blob (steps 6-8). BRR samples
  keep their length word inside the blob.
- **Edited assets**: the placement is fixed by the survey's addresses; a pack whose size
  changes fails the build. Relocating data needs a layout pass (labels already carry it).
- The module's unmatched bytes still come from the ROM through `tools/c3pack.py`
  (`build/c3pack/rom_module.bin`), counted in the module's figure as before.

## The text (step 5)

Done on the `data-text` branch. `tools/text.py` holds the encoding, derived from the matched
decoder in bank `$C2`: the control codes and their operands come from `TextWin_CodeTable`
(read from the source; `$01`, `$02`, `$03` and `$12` take a byte), the dictionary bytes
`$21`-`$9F` from `TextWin_DictPtrs`, and the character of each glyph `$A0`-`$FF` from the
font as drawn and from `TextWin_HexGlyphs` and `TextWin_StrNadia`. No text is committed: the
tool holds the character map, the tag names and which survey rows form which unit.

- **Readable form.** `extract` writes one UTF-8 file per unit to `build/assets/text/<unit>.txt`:
  the 15 message tables (one each), the dictionary, the treasure messages, the map labels
  (`$C6`), the battle and menu string tables, the item, tech and enemy names (11-byte records),
  the staff credits (ASCII) and the stale rows between tables. Text is fully expanded; control
  codes are tags (`{line indent}`, `{wait 0B}`, `{char0}`, `{item}`, ...); a pointer table is a
  `@table`, and each string carries the entries that point at it (`@at 455 456 457`), so shared
  and mid-string entries (after a `{wait 00}`) need no address. Extraction checks that the
  file encodes back to the ROM's bytes.
- **The dictionary rule.** Each of the 10,883 runs of glyphs in the message tables (4,579 pointers) is
  what a greedy longest match gives, left to right, over dictionary entries 0-126 without
  116-118 (no string uses those three; with them 171 runs would differ). Entries never tie, so
  the encoder recompresses the expanded text byte-exact, with no dictionary tag anywhere in the
  message tables. The menu tables at `$FF:CF3B`-`$FF:D553` use no dictionary at all (`@mode
  plain`); only the stale rows need explicit runs (`«...»` with `[xyz]` per entry, 30 runs).
- **Build and verify.** `tools/build_rom.py` encodes every unit (the dictionary first) to
  `build/text/<label>.bin`, which `asm/data/` incbins like a pack (the manifest's piece kind
  `text`, the same FILEREAD rule and tests); a piece whose size changes fails the build.
  `tools/verify.py` counts these bytes apart, never as emitted by source: its "text" figure is
  every byte of the text units' rows, which hold text only (strings, their pointer tables, the
  dictionary and its pointers, the 11-byte names, the credits). Extraction fails on a byte in a
  unit that is not text. 16 entries of the map labels' table (`C2SceneRom_LabelStrings` entries
  112-127, 32 bytes) hold `$0000` and point at no string; the readable file keeps them as `@set`
  values, and they count as text with the rest of their table.
- **Survey rows settled.** Rows whose ends were inferred ran past their text; the non-text bytes
  are now rows of their own (extracted as data, counted as "extracted"): `$CC:36F4`-`$37FF`
  (`$FF` fill) and `$CC:3800`-`$3A08` (a word table and bytes) after `MenuRom_DescStrTable`;
  `$CC:3AFB`-`$3B0C` (18 bytes between `BattleRom_TechInfoStrings`' 121 pointers and its
  strings, now the row `$CC:3B0D`); `$CC:CD8F` (one byte between `BattleRom_ScriptMsgStrings`'
  227 pointers and its strings, `$CC:CD90`) and `$CC:DDC6`-`$DFFF` (570 bytes after them);
  `$C6:F356`-`$F3FF` (`$00` fill after the map labels); `$CC:6FC9`-`$6FCA` (2 bytes after the
  251st enemy name); `$FD:A7D1`-`$A80A` (after the last credits block); `$FF:D024`-`$D03D` (a
  rising table after `MenuRom_NameStrings`). The last string of `$CE:EF11` ends with its `$00`
  at `$CE:EFE0`, the first byte of `BattleRom_DissolveRec` (a byte its reader skips): that byte
  stays in the extracted record, so the text piece ends one byte before its last terminator.
  `$DE:FAFE` (the 128th dictionary pointer) is a `table` row but part of the dictionary unit.
- **Left:** the menu formats that are not TextWin strings (`MenuRom_ItemTextPtrs`,
  `MenuRom_StringPtrs`, the equipment labels at `$FF:C96A`-`$FF:C9AB`) stay extracted blobs;
  editing text needs extraction to keep an edited file (it restores every asset now) and a
  layout pass for strings whose length changes. (The event scripts' op `$B8` addresses into the
  tables are labels in their disassembly since step 7.)

## Tables and palettes (step 6, first part)

On the `data-tables-6` branch. `tools/records.py` holds layouts only (no value). A row is a
`records` piece only when its reader proves both the layout and the record count; every other
table and palette stays an extracted blob, however regular it looks. `extract` writes
`build/assets/records/<label>.tsv` (a header of the layout's columns, one line per record,
checked to encode back), the build encodes it to `build/records/<label>.bin`, `asm/data/`
incbins it through the manifest (the same FILEREAD rule and tests as packs and text), and
`tools/verify.py` counts it as "records", never as source.

- **Layouts.** Five rows are the records of a ROM struct of `asm/include/`, read from the struct
  itself, each with the count its reader's index bound gives: `BattleRom_EnemyReward` (255: a
  byte id, `$FF` skipped; this rests on a present enemy never having id `$FF`, and
  BattleSys_StealItem indexes the records with no `$FF` guard), `BattleRom_CursorSprite` (4: the
  loop ends at `BattleOam_CursorBytes`), `BattleRom_PcAttackScript` (1), `BattleRom_Kind3Act`
  (68: ids `$BC`-`$FF`) and `LocRom` (512: a 9-bit location id): 9,466 bytes. A struct field
  wider than a byte is a word only where its reader reads it so; otherwise it stays one
  unsplit column of bytes. 68 more table rows are arrays or small records whose element width
  (and, for some, fields) the survey's format takes from the reader, with the reader's index
  bound as the count: a mask (`AND #7`: 8 entries), a loop end (`Battle_SprRecCount`,
  `BankFF_ComboCount`, a step counter that stops at `$40`), the opcodes a handler serves
  (`$50`-`$55`: 6), a byte index (256), a 9-bit location id (513 offsets), or a variable's
  stated domain (character ids 0-6, the 3 PC slots, the 11 battler slots of
  `Battle_NumSlots`, cursor records 0-11). One line each in `records.ARRAYS`, with the reader.
  Words named as an address in a bank are written as the label of the piece they point at
  when they point at one's start; byte pairs read as two bytes are two fields
  (`BattleRom_Op80PairB`).
- **Palettes.** 28 rows whose reader copies a fixed number of colours, as BGR555 colours: R, G,
  B (0-31) and bit 15 per colour. `MenuRom_ObjPal` (`$FF:9DF0`) holds 13 colours; its reader's
  32-byte copy also takes the 3 colours of `MenuRom_MainPalC` after it (the rows overlap in
  that read, noted in the survey).
- **Extent corrections** (17 rows split; the bytes past the reader's reach are rows of their
  own, `unknown`): `BattleRom_CursorSprite` (40 B), `BattleRom_EnemyMoveInterval` (48 B),
  `BattleRom_PcKoFrame` (162 B), `BattleRom_EnemyTechTarget` (2 B), `BattleRom_EnemyReward` (7
  B), `BattleRom_FrameExtraCount` (1 B), `BattleRom_PcPathAlways` (1 B), `MenuRom_ComboNeeds`
  (1 B), `MenuRom_ComboMembers` (79 B), `BattleRom_FxRecByte0` (2 B), and seven palettes whose
  copy has a fixed length (`MenuRom_PalB`, `MenuRom_HealNumberPal`, `MenuRom_Icon0RedrawPal`,
  `MenuRom_Icon1PalA`, `MenuRom_Icon2PalB`, `MenuRom_LoadPalB`, `BattleRom_UnkColours38F2`).
  These rows no longer say "end inferred".
- **Left as blobs** (no reader bound proven, or the bound reaches past the row): the other
  struct tables (`BattleRom_TechRec`, `BattleRom_FrameLayout` (its index `Flags AND 7` reaches 8
  records, the row holds 6), the action record tables in `$CD`, `BattleRom_FxOverlaySpr`,
  `BattleRom_ActObjRec`'s and `BattleRom_ActObjInit`'s records, `BattleRom_EnemySpr`), counts
  that come from the data or the row rather than a reader (`AudioRom_SongSamples` and
  `AudioRom_SongEcho`: 83 songs, the index reaches 128; `BattleRom_PcAttackPals` 95 and
  `BattleRom_Kind3Pals` 96 of 256; `LocGfx_Lists` 64 of 255; `BattleRom_ActFrameBase`, whose
  frame list ends at a zero header; `LocPal_Rom`, its 88 rows from the largest
  `LocRom.Palette`), bounds that reach past the row (`BattleRom_Times16`: rows up to 15;
  `BattleRom_FrameBytes`, `BattleRom_FrameDmaSizeA`/`B`, `BattleRom_LayoutSprBytes`: 8 layouts;
  `MenuRom_ButtonLetters`: 9 entries for any byte), indexes whose high byte is not proven
  (`BattleRom_HalfPlaneEdge`) or whose domain is a guess (`MenuRom_PortraitTiles`/`Pals`),
  arrays indexed by tech, item, enemy or action ids from data, `BattleRom_Div5`, the
  `Menu_RunDrawList` lists, the `$E4` animation lists, the palette-step records in `$CD`, and
  18 palette rows without a fixed copy length. 204 table rows (157,019 B, with the 8 tails of
  the pointer tables of labels) and 18 palette rows (31,374 B) are still extracted.

## Location event scripts (step 7, first part)

On the `data-events` branch. The 462 packs `Evt_PackPtrs` reaches are `events` pieces: `extract`
writes a disassembly of each to `build/assets/events/<label>.evt`, afresh every time (checked to
assemble back, every opcode line against its handler; a non-empty pack it cannot follow fails
the extraction, the build and verify), the build assembles it to the unpacked bytes and packs
them as before, and `tools/verify.py` counts them as "events", never as source, with how much
is disassembled. What each handler does with given bytes is kept between runs in
`build/events/traces.json` (plain JSON; a first run takes about six minutes). The file carries
a sha256 that is tamper-evident, not tamper-proof: it catches a file changed by hand, not one
forged together with its key. CI never has the file and traces every handler afresh, and every
pack still has to assemble back to its bytes. The assembler also checks the structure: every
function entry and every jump lands on an opcode line (or an `@inner` line), and an `@bytes`
run follows only an opcode that does not go on to the next one. The files are regenerated by
extraction: an edit is lost when it runs again.

- **The opcodes come from the matched interpreter.** `tools/events.py` reads `Evt_OpcodeTable`
  from the source, and `tools/absint.py` runs each handler's assembled code (an assembly of
  `asm/main.asm`, not the ROM's bytes) with Y = the opcode's offset and the script known,
  everything else unknown: both ways of a branch on an unknown value, states joined in loops
  that keep changing, a callee it cannot follow (a dispatch on game state, a block move of
  unknown size, a long run) taken as returning with A, X and Y unknown. An opcode's operands
  are the script bytes it reads (a block move's source included); its length is where it goes
  on when that place is not computed from a script byte (else the bytes it reads); each return
  is next, stay (a wait), a jump (a place computed from an operand byte, whose encoding is
  found by changing that byte) or an end (opcode `$00`, the warps and scene exits). Every
  fixed length the handlers' headers state is the one derived; `$2E`, `$4E`, `$88`, `$F1` and
  `$FF` vary with their operands, as their handlers do.
- **The readable form.** Per pack the object count, the 16 function entries of each object as
  labels, the jump encodings used, then the opcodes by their handlers' names, jumps as labels,
  `$B8`'s pointer as the message table's label (all 416 of them), bytes no opcode reaches as
  `@bytes`, and an opcode a jump reaches inside another's operands as an `@inner` line.
- **Results.** 461 of 462 packs disassemble and assemble back byte-exact (the 462nd is empty):
  142,701 opcodes; of the 568,478 unpacked bytes 566,815 are code and headers and 1,663 bytes
  are never reached by an opcode (data).
- **Not pinned down:** the walking and following opcodes (`$8F`, `$94`-`$9A`, `$9E`-`$A1`) call
  object searches through a dispatch on game state that the interpreter cannot follow; on that
  path the next position is unknown (their other paths give their length and wait), so it adds
  nothing to the disassembly. The same holds for some `$FF` sub-opcodes and the menu, sound and
  sprite callees of `$29`, `$82`, `$83`, `$AF`/`$B0`, `$CF`-`$D7`, `$E8`-`$EC` and `$F8`-`$FA`,
  whose handlers keep the script position in direct page or on the stack around the call.
- **Left:** the battle scripts, the scene scripts and the music sequences (step 7); a
  message's string number is still a number (the text units' strings have no names yet).

## Order of work

0. **Decide where the data lives.** The README promises that no ROM data, assets or compressed
   graphics or music are stored here. Describing the data "in source" therefore cannot mean
   committing it. The usual answer in other decompilation projects is an extraction step: a tool
   reads the user's own ROM once, using this survey, and writes the assets (unpacked streams,
   tiles, text, samples) to an ignored directory; from then on the build assembles from the
   source and those assets, packs the streams, generates the pointer tables and never copies a
   ROM region. A build with no ROM at all would need the assets in the repository, which
   conflicts with the README's legal section. This is the owner's decision; the plan below
   assumes extraction.
1. **Done in PR #113**: the packer and the packed-module build path (`tools/c3pack.py`), the
   prerequisite for everything packed. Its build step is the model for step 3.
2. **Extraction and placement framework** (done, above): `tools/extract_data.py` writes one
   asset per CSV row; a generated `asm/data/*.asm` per bank places each row (`incbin` of its
   asset, fill directives, labels at row starts). The bytes of an extracted blob come from the
   ROM, not from source, so verify must count them apart from "emitted by source", the way it
   counts the packed module apart, never as source. This is the step that ends the ROM copy for
   the structure; content is still binary.
3. **Packed streams from unpacked assets** (done, above; code-side labels left): pack at build time with a cache;
   pointer tables as labels. Biggest share (56%) and the packer is done.
4. **Blobs that need no decoder** (done as placement, above; per-format files left): padding, BRR samples, song and effect blocks,
   raw graphics, sprite layout, unknown rows. With 2 and 3 this covers about 85% of the
   remaining bytes.
5. **Text** (done, above): the encoder and the dictionary question; the pointer tables.
6. **Tables and palettes** (first part done, below; 2-4 sessions left): the tables still
   extracted, and the inferred table ends.
7. **Script languages**: battle scripts (3-5), location event scripts (done, below),
   scene scripts (2-3), music sequences (2-3).
8. **Readable assets**: tile and palette converters (2-3), sprite frames (2), maps if wanted.
9. **Unknown and probable rows** (1).

## Overall estimate

- A byte-exact build in which no region is copied from the ROM, with data as extracted binary
  assets (steps 2-4; step 1 is done): 3-5 sessions.
- Readable source for text, tables and scripts (steps 5-7): 15-26 sessions more (2-4, 3-5 and
  10-17).
- Readable graphics and frames (step 8): 4-5 sessions more; maps only if wanted.
- The unknown and probable rows (step 9): 1 session.

So roughly 23-37 sessions to describe everything in readable form, of which 3-5 (about 10-20%)
stop the copying of bytes. Uncertainties, largest first:

- **The script languages.** Event scripts (568 KB unpacked) and battle scripts depend on every
  opcode's operand length and on finding all jump targets; a handler whose length depends on
  its operands, or code that jumps into data, can stretch the estimate.
- **The text encoder.** If the original dictionary rule cannot be recovered, explicit references
  make the source text harder to edit (it still round-trips).
- **Table ends.** 40% of the table bytes (70,780 of 177,310) run to the next named table only
  by inference; each has to be settled from its reader (step 6 settled the ones below).
- **Sprite frames and the character tile blocks**: format and ends not decoded yet.
- **Probable and unknown rows** (33 KB): these are stale data or a reader the survey missed; a
  missed reader would change a row's kind, not the plan.
- **The asset decision** (step 0) changes steps 2-4 in kind, not in size.

## Code hidden in data

None found beyond what is already known:

- The packed `$C3` module (`$C3:1313`-`$7A2B`, 26,393 bytes, 34,175 unpacked to `$7E:3000`) is
  65816 code and data. It is known, counted apart in `symbols/code_survey.csv`, and since PR #113
  it is packed from its source (`asm/bankC3/packed/`), so it is not a row of the data survey; of
  its 34,175 unpacked bytes, 763 are matched source and the rest are still the ROM's (incbin'd
  inside the module source), which is code-matching work, not data work.
- Evidence for the rest: every unemitted row, and every stream unpacked, was scanned for `JSL`
  and `JML` to the entry address of a matched routine. Only the module has more than one (60 in
  its unpacked bytes, 18 in its packed literals); seven other places have one each (five in
  packed streams, one in an unpacked sprite pack, one in a sample). Chance alone gives about
  14: about 7.9 million bytes scanned (3.9 M raw, 4.0 M unpacked) x 2/256 (the two opcodes) x
  3,736/2^24 (the share of 24-bit targets that are routine entries). Seven is within what chance
  gives, so this scan finds no sign of hidden code; it cannot prove there is none (see the limits
  below). The code survey's check that no instruction of matched code
  reaches an unmatched byte also covers the raw bytes; its further claim that routine-shaped
  runs in unmatched ROM are no longer than 19 instructions (PR #106) was not re-checked here.
- A limit no static scan removes: code reached only through a RAM pointer loaded from data (a
  jump through a vector filled from a table, or code copied to RAM and run there) cannot be
  ruled out this way; it would need an emulator trace.
- The SPC700 boot blocks are not code: block 2 (`$4700`) is the built-in sample (513 bytes, 57
  BRR blocks), blocks 3-5 are the sample directory and two parameter tables, and block 1
  (`$2F00`) and its alternate hold the sound-effect table and tracks the driver plays
  (`Spc_StartSfx`).
- Scene scripts call 65816 code (op `$4E`, into matched `$C6` code); they are bytecode, not code.

## What the survey did not resolve

- The extents marked "inferred" (each named table's end, the character tile blocks, the
  `$E4:2A00` palette area, the palette-step records after `$CD:F187`).
- 12 packs (3,009 bytes) that repack byte-exact but that no pointer reaches (`$E0:332C`,
  `$E0:FD93`, `$F8:AB72`, `$F8:AD83`, eight in `$FA:FB33`-`$FF09`): reached through data the
  survey did not follow (no word or long pointer to them is in ROM or source), or unused.
- 42 unknown rows (8,657 bytes), each described in its notes (seven of them are the non-text
  bytes split off the text rows in step 5, 17 the bytes past their readers' reach split off
  tables and palettes in step 6): stale bytes beside unused pointer
  entries, four single bytes of the same value right after a run of packs, and small gaps.
- The internal layout of the sprite frame records and of `$E4:0000`-`$1FFF`.
