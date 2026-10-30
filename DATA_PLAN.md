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
- **Left:** the music sequences (step 7; the battle, scene and layer-effect scripts are below); a
  message's string number is still a number (the text units' strings have no names yet).

## Battle scripts (step 7, second part)

On the `data-battle-scripts` branch. `tools/battle.py` makes two units of `battle` pieces, one
readable file each in `build/assets/battle/`, written afresh by `extract` (checked to assemble
back, every line against the readers; a unit it cannot follow fails the extraction, the build
and verify). The build assembles them to `build/battle/<label>.bin`, and `tools/verify.py`
counts them as "battle", never as source.

- **Action scripts (`actions.bscr`): a language.** The five script tables
  (`BattleRom_PcAttackScripts` to `Kind3Scripts`), the subscript table `BattleRom_ActSubscripts`
  (taken over from the records) and the five script regions in `$CD`/`$CE`. The opcodes are
  `BattleAct_OpcodeTable`'s ($00-$DA; a byte of `!Battle_ActNumOpcodes` or more halts the
  thread). `tools/absint.py` runs each handler's assembled code as `BattleAct_RunThread` calls it
  (Y = 0, B = 0, the pointer in DP $E6-$E8, the opcode in `!Battle_ActOpcode`), once for each
  kind of thread the handlers tell apart (a battler's, the target set's, an object's), with the
  script bytes known: its operands are the bytes it reads, and where it leaves the pointer is
  next (by a constant, or by a count from its own byte: `$80`), stay (a wait or the thread's
  end), a call (`$1E`: from the subscript table, the return address kept) or a return (from
  RAM). The movers that keep their length in RAM and wait (`$10`-`$18`, `$98`-`$9D`) are
  run a second frame from the state the first left: where they go on then is their length. A
  script's header is two thread masks (high byte first) and one offset per set bit
  (`BattleAct_LoadAttack` and the other loaders); threads 5-7 are never run. After a call the
  thread goes on only if the subscript can return. The assembler re-derives the structure from
  the bytes and refuses any line that differs (an opcode of another length, an opcode no thread
  reaches, reached bytes written as data, a header no table names, a thread or entry on the
  wrong kind of line).
- **Enemy behaviour scripts (`enemy.bscr`): records, not a language.** `BattleRom_AiScriptPtrs`
  (256 enemy ids) and the scripts after it have no jumps: a script is a main and a reaction part,
  each blocks of one or two 4-byte tests, `$FE`, action records, `$FE`, ended by `$FF`. They are
  read under the records rule, as the readers walk them (`BattleAi_RunMainPart`,
  `BattleAi_FindReactPart`, which starts the reaction part after the first `$FF`,
  `BattleAi_TestPassed`, which scans for the `$FE` from the passing test, `BattleAi_EnemyTurn`):
  an action record is `BattleFD_AiActLength[code]` bytes (read from the assembled source), code 4
  (`BattleAi_ChooseByChance`) its code alone, and a code of `$80` or more ends the records. As a
  cross-check, absint runs the run and choose handlers of every code used on a record: all 16
  it can follow read inside the record. The assembler re-reads every script label the table and
  the two fixed scripts (`$CC:8D08`, `$CC:8D1E`) name and refuses any line the readers do not read
  so.
- **Results.** All 12 pieces (87,204 B) assemble back byte-exact. Actions: 70,627 B, of which
  1,770 B of tables (757 script entries, 128 subscript entries; 212 are `$FFFF`), 464 headers
  (8,730 B, 3,437 thread offsets), 32,047 opcodes (59,529 B, 128 different opcodes, 742 calls) and
  598 B no opcode reaches. Behaviour scripts: 256 entries, 2,924 records and delimiters; 50 B are
  kept as bytes (below).
- **Not pinned down:** 77 table entries name no script: `BattleRom_EnemyTechScripts` 194-255 point
  at `$CD:EE23`, past every script region (the palette-step records), and
  `BattleRom_EnemyAttackScripts` 145-159 at `$CD:95C4`, which is thread code other scripts'
  headers share, not a header; they stay words. Enemy 127's script
  (`$CC:A3E0`, 50 B) is kept as bytes: its main part's blocks run past the first `$FF`, where
  `BattleAi_FindReactPart` starts the reaction part, so the two readers split it differently.
  One PC tech thread runs on, after its last subscript returns, into the next script's header
  (`$CE:30A3`); it is not followed there. The stale-OpLen path: `$98`/`$99` in the target-set
  thread and in an object thread entered mid-move (`.object_moving` -> `.done`, at `$CE:D58F` and
  `$CE:D62F`); `$18` in set and object threads. They advance by a length an earlier opcode left
  in RAM (`!Battle_ActThreadOpLen`, `!Battle_ActThreadPathLen`; the handlers' headers say so):
  classed "stale", not followed and not counted as returns; `tools/battle.py check` asserts
  that over the data only these are stale and only `$1F`/`$21` are returns.
  Opcode `$80` with a count of 0 (it copies 256 bytes and advances 1) is not modelled: the
  interpreter refuses it; no script has one. Opcode `$26` in an object thread
  runs its third byte as the next opcode (two `@inner` lines). The table extents are the survey's
  (several inferred); every entry in them decodes as a header, `$FFFF` or one of the words above.
  The layer-effect channel scripts are below.

## Scene and layer-effect scripts (step 7, third part)

On the `data-scene-fx-scripts` branch. `tools/scripts.py` handles two more languages the same way
as the battle scripts. `scene` pieces are the eight `C2SceneRom_ScriptPacks` streams: one file
each in `build/assets/scene/`, which the build assembles to the unpacked bytes and packs as before.
The `fx` piece is `BattleRom_FxScriptPtrs` (`$D1:646C`, its 148 entries and the scripts after
it): one file in `build/assets/fx/`, assembled to `build/fx/`. Both are written afresh by
`extract` and checked to assemble back. `tools/verify.py` counts them as "scene" and "fx", never as
source.

- **Both are languages.** absint runs each handler as its interpreter calls it, with the script
  bytes known and other RAM unknown. The handler's paths give the outcomes:
  - next (a constant; a count from its own bytes when no jump encoding fits);
  - stay;
  - jump or call: a target computed from the operands. Its encoding (a word in the script's
    bank plus a constant, or a signed, added or subtracted byte from the opcode) is found by
    changing the bytes and watching the target move. A call is a jump that keeps the place after
    its operands in RAM.
  - return: the position from the return slot, which the trace fills with a mark;
  - done: the task or channel ends;
  - ram: a position from other RAM.

  After a call the script goes on only when the part it calls can return. Bytes nothing reaches
  are data. A routine absint cannot follow (an indirect jump through RAM or a table it is not
  given, a block move of unknown size, a wait on the APU) is not taken as returning untouched:
  the opcode is refused unless the routine is one in `TRUST` (`tools/scripts.py`), each with the
  reason, from its code, that it leaves the script pointer, the return slot and the member words
  alone and starts no script. `check` asserts that the real scripts need exactly those routines
  for exactly the opcodes listed, and that in each one's code, followed statically from it with
  the tables its reason names, no store names those bytes directly and no spawn routine is
  called (its indexed stores are covered by the reason only). The routines and opcodes are under
  "Not pinned down". The assembler re-derives the structure from its bytes and refuses any line that
  differs: an opcode of another length, an opcode nothing reaches, reached bytes written as data,
  or an `@jump`/`@spawn` line that is not the operand's encoding. `tools/scripts.py check` also
  asserts which opcodes are classed return (scene `$37`, fx `$92`), done (`$52`, `$FF`) and ram
  (fx `$84`, `$86`, `$D0`; none in the scenes) over the data.
- **Scene scripts** (`C2Scene_TaskRunScript`, `C2Script_OpTable` `$00`-`$52`). The handler runs
  with M=0, A = X = opcode × 2 and `C2Script_Ptr` on the opcode. It returns Z=0 with the bytes to
  add (after its own changes to the pointer), or Z=1 to stop; C=1 then ends the task.
  - **Entries:**
    - the pack's start;
    - the `C2Scene_ListD` script addresses of the scene whose header (`C2SceneRom_HeaderTable`)
      names the pack (3 in all; `C2Scene_GetListBScript`). The table has 8 words: it ends where
      the first header starts (the 8 words after it, which `C2Scene_LocIdMask` would let scenes
      8-15 read, are header bytes). The build takes these from its own inputs (the header
      table's asset, `C2SceneRom_ListPacks` as `asm/data` names the packs, and their unpacked
      assets), and the `@entry` lines must name exactly them;
    - the addresses opcodes `$09`/`$43` hand to `C2Scene_TaskSpawnScript(Low)`;
    - the words opcode `$08` stores in `C2Scene_MemberWords`, the leader's and members' scripts
      (`C2Scene_LeaderScriptStart`, `C2Scene_MemberScriptStart`).

    397 entries come from those last two. The jumps are `$1A` (word + 1), `$36` (call) and the
    conditional branches (a signed byte). A call goes on after `$37` returns.
  - **Results:** all 8 packs (27,757 B unpacked, 17,112 B packed) assemble back byte-exact:
    8,235 opcodes (70 different opcodes, 580 jumps, 314 calls), and 1,089 B nothing reaches.
- **Layer-effect scripts** (`BattleCD_RunFxScript`).
  - **How the runner reads them:** a byte below `$7F` is a tile page and `$7F` a step with no
    page; both end the step. `$FF` ends the channel. These are traced in the runner itself.
    `$80`-`$F9` run through `BattleCD_RunFxOp` (`BattleCD_FxOpTable`), and the runner goes on at
    DP `$40` + 1. A script starts one byte after its table entry (the period byte: traced in
    `BattleCD_StartFxChannel`). `$91`/`$92` call and return, `$CA`/`$CB` jump, and the waits go
    back by a byte (`$A9`, `$BF`, `$F1`, `$F6`).
  - **Entries:** the table's words. A word inside the scripts must be written as a script's label
    (a `@head` line); only a word outside them is written as `$XXXX`.
  - **Results:** 142 scripts; 6,062 steps and opcodes (4,618 opcodes of 106 different ones, 830
    pages, 485 `$7F`, 129 ends) in 15,401 B read as scripts and table, and 414 B nothing reaches.
- **Not pinned down:**
  - Scene packs 1-4 and 6 hold 1,089 B no known entry reaches (one block in pack 4 spawns
    a script itself); they look like scripts started from elsewhere (tasks the scene code starts,
    lists not traced). They stay data.
  - Two scene scripts end with an opcode that goes on past the end of their pack (packs 0 and 6):
    not followed.
  - Fx opcodes `$84`/`$86` go back to their loop's start from RAM (the loop body is reached from
    `$83`/`$85` anyway).
  - The switch `$D0` at `$D1:82CE` (and `$D1`) jumps through a list after its operand: word n of
    it, n a nibble of a variable (`Battle_ActVars`), so at most 16 words. Which values the
    variable takes is not in the handler, and only the first 9 words of this list (up to its
    lowest target) point into the scripts; words 10-16 are the bytes after it and point
    elsewhere in the bank. So the list and what only it reaches stay data (271 B, `$D1:82D0`-
    `$D1:83DF`), although its 9 targets, `$D1:82E2`-`$D1:8347`, read as scripts when started there
    (32 opcodes, ending in a `$D1` switch with its own list).
  - Two runs read as whole scripts with no table entry: `$D1:7830` (2 B, `01 FF`: a period byte
    and End, after a return) and `$D1:9BF7` (141 B after an End: a period byte and 57 opcodes to
    an End). No word in the ROM is `$9BF7`, and the only `$7830` words are inside bank `$CD`'s
    action data, so they are kept as data: probably scripts no longer used.
  - The routines trusted without being followed (`TRUST`), with the opcodes that call them:
    `C2Anim_Run` (scene `$31`, `$39`, `$3F`, `$40`: the animation script's handlers, by an
    opcode in other data; ops 0-2 can write any task record byte their operand names, which an
    animation script could aim at the script pointer's record copy: not checked); through
    `$34`/`$4E`, the scene routines that unpack with `Decomp_ToWram` (its destination given and
    length the pack's: a pack longer than the room to the bank's end is not ruled out), that build
    window tables with the `$C3` window routines, and `C2Scene_ZoneSoundAtEntry` (the audio
    driver's wait on the APU); fx `$8B` (`BattleCD_FxOpDrawShape`, the shape handler from RAM)
    and `$B5` (`BattleCE_RunCopyWords`, the copy entry from DP `$4B`).
  - The fx opcodes with no handler (`$FA`-`$FE`) and scene opcodes above `$52` would jump through
    the code after their tables. None is reached; the interpreter refuses them.

## Graphics as images (step 8, first part: raw tiles)

On the `data-graphics` branch. `tools/graphics.py` turns tile graphics whose format a reader
proves into `graphics` pieces. Extraction writes an indexed PNG per region (16 tiles wide; the
palette index is the pixel value) and a sidecar (format, tile count, region) to
`build/assets/gfx/`. The build encodes them back to `build/gfx/`, and `tools/verify.py` counts
them as "graphics". No image is committed. The PNG reader is the tool's own (no library). It
takes indexed PNGs of bit depth 1-8 with any row filter. It refuses anything else, an image of
another size, an index the format cannot hold, and pixels in the cells past the last tile. The
palette is a grey ramp: the regions' own palettes are not proven here. The PNG must keep that
ramp (PLTE first entries as written). Many editors sort or optimise a palette and renumber the
pixels to match; the picture looks the same, but the bytes would differ, so the build refuses
it and says why. Bytes after IEND, a second IHDR, and a sidecar line given twice or naming other
addresses are refused too.

- **How a format is proved** (the proof of each region is in `graphics.FORMATS`): from where
  the code sends the bytes and what the PPU makes of that VRAM at that point, or from how the
  code itself rebuilds them:
  - **The menu** (`Menu_InitPpuAndRam`: mode 1, BG1/BG2 tiles at VRAM $0000, BG3 tiles at $7000,
    sprite tiles at $4000; `Menu_LoadGraphics` runs after it):
    - the 2bpp font (`MenuRom_Font2bpp`'s $E00 B, which covers three rows, and `MenuRom_Font2bppB`)
      goes to the BG3 tiles, and is also copied 16 B per tile into planes 0-1 of 4bpp tiles;
    - `MenuRom_Tiles4bpp`, `MenuRom_WindowGfx`, `MenuRom_VramTiles` and the two blocks
      `Menu_VramRecsWin` sends from `$FF:0000` and `$FF:E55C` go to the BG1/BG2 tiles: 4bpp;
    - `MenuRom_ObjTiles` goes to the sprite tiles. `Menu_TilesOrPlanes23` then sets planes 2-3
      to planes 0 OR 1, so the stored planes 2-3 are never shown. `MenuRom_WindowGfx`'s plane 3
      is replaced the same way (`Menu_TilesOrPlane3`). The images show the bytes as stored;
    - `MenuRom_Tiles3bpp` is 3bpp as `Menu_Expand3bppTiles` reads it (24 B: planes 0-1, then
      plane 2);
    - `MenuRom_GlyphRows` is 2bpp as `BankFF_BuildTileSets` copies it into planes 0-1.
  - **The character sprite tiles** (`$D2`-`$D5`): the sprite tile builders (`Spr_CopyTile` and
    its bank copiers, 32 B per tile number) fill the sprite tile buffer that goes to the OBJ
    tiles the OAM records name. Sprite tiles are 4bpp.
  - **The map view's markers**: `C2Scene_MapView` sets OBSEL and DMAs them to sprite tiles.
  - **`BattleRom_InitTiles2bpp`**: `Battle_InitSceneGfx` widens it, 16 B and 16 zero bytes per
    tile. The 16 B are planes 0-1, rows interleaved, which is the same layout at every depth, so
    the proof does not need the depth of the buffer or the layer.
  - **`BattleRom_InitTiles4bpp`** (`$D1:3900`): the same routine copies its 64 tiles, 32 B each,
    into that buffer after them. The buffer is the code's own 32-B tiles (2bpp ones widened to 32 B
    with zero planes 2-3), so they are 4bpp. The VRAM layer it reaches is not traced.
- **Survey rows cut to their readers.** Three rows are cut where their readers' extents end:
  - `$FF:0000`: its $1F80 B have the reader `Menu_VramRecsWin`, which the survey did not have;
    224 B after them have none.
  - `$FF:9390`: 8 B past the font's $E00 B.
  - `MenuRom_Tiles3bpp`: `Menu_Expand3bppTiles` reads $95 tiles, but only $65 are used, and the
    rest of the row is the 4bpp block sent to $1E00.
- **Results.** 22 regions, 244,952 B, encode back byte-exact: 6,848 4bpp tiles of the seven
  characters (219,136 B), the menu's tiles and the two smaller sets.
- **Not proven, still extracted** (100,736 B of `graphics` and `font` rows; listed in the survey):
  - the battle's uploads whose VRAM layer is not traced. The battle never writes BG12NBA, BG34NBA
    or OBSEL, and its BG mode comes from HDMA line data. These are `BattleRom_FxTileGfx` (`$CF`),
    `BattleRom_FxGfxSrc` (`$D0`), `BattleRom_InitTilesB/C/D` and `BattleRom_InitGfxA`;
  - the text font (`TextWinRom_Font`, `TextWinRom_FontRight`), which `TextWin_DrawGlyph` draws in
    code: not traced yet;
  - the mode-7 dial pixels (`C2SceneRom_DialNibbles`).
- **Left:** the packed graphics (location tiles, object sprite tiles, scene BG and sprite
  graphics, battle backgrounds) are the second part. Edits to any extracted asset are lost when
  extraction runs again (as for the text and scripts); the encoder itself takes edited PNGs.

## Location maps as text

On the `data-maps` branch. `tools/maps.py` gives the location maps and their metatiles readable
forms in `build/assets/maps/`. The build assembles them to `build/maps/` and packs them as before
(`tools/c3pack.py`). `tools/verify.py` counts them as "maps".

- **Maps** (`mapprops` pieces: the 201 `Map_PropsPtrs` packs, `LocRom.MapProps`).
  `LocLoad_UnkA33B` unpacks one to `MapProps` (`$7E:B500`) and reads its six header bytes (struct
  `MapProps`). `Map_UnpackTilePlanes` reads the rest through the WRAM port:
  - layer 1's and layer 2's metatile numbers, row by row, and layer 3's when `Size3` bit 7 is set
    (117 maps), sized `(two bits + 1) x 16` by `Size1`/`Size3`;
  - then three bytes per layer-1 tile (`Map_TileHiBits`, `Map_TileAttrA`, `Map_TileAttrB`): an
    entry, or with bit 7 of the first byte a run of a count of tiles (0 = 256) carried across row
    ends.

  `Map_WriteRow1`/`2` make bits 0/1 of HiBits bit 8 of the layer-1/2 metatile number. The text holds
  the header, a hex grid per layer, and a grid of the attribute triples. All 201 maps write their
  runs the same way: every repeat of two or more is a run of up to 256 tiles. So the assembler
  re-makes the runs from the grid, and extraction refuses a map written otherwise. Five maps'
  streams end before the attribute plane is full (`MapPropsPack_029`, `_058`, `_098`, `_191`, `_193`:
  13-135 tiles short). The game then reads whatever follows the unpacked bytes in WRAM; the text
  marks those cells `--------`.
- **Metatiles** (`metatiles` pieces: the 54 `LocGfx_Meta12Ptrs` packs of 512 and the 19
  `LocGfx_Meta3Ptrs` packs of 256). Each metatile is four words, top-left, top-right,
  bottom-left, bottom-right. The row and column writers send them unchanged to `Map_BufC800` and
  the edge buffers, which go to the layers' BG tilemaps, so they are SNES tilemap words. The text
  writes each word as `TTT/P` plus `p`, `h` and `v` (tile, palette, priority, flips).
- **Exits and treasures** are now records (`tools/records.py`):
  - `ExitRom` (814 x 7 B): `Map_LoadExitTiles` reads them through `ExitRom_LocOfs`, whose
    end entry gives the count;
  - `TreasureRom` (249 x 4 B; `Tile` and `Contents` read 16-bit by `Field_CheckTileInFront`).
- **Results.** 201 maps (384,096 B packed, 1,003,373 B unpacked) and 73 metatile packs
  (176,112 B packed, 260,096 B unpacked) assemble and pack back byte-exact. 6,694 B of exit and
  treasure records encode back too.
- **Not done here, kept as bytes:**
  - the ten 1-byte `LocGfx_Meta12Ptrs` packs (16, 55-63), which no location names;
  - `$F5:EE02` (510 B, not a valid pack; Map_PropsPtrs entry 201, unused);
  - `$EF:B168` (`LocGfx_Meta3Ptrs` entries 19-22, which do not unpack and no location selects);
  - `C2SceneRom_Bg3MapPacks` entry 5 (2,048 B), which only a script routine unpacks
    (`C2Scene_UnpackBg3MapPack`), with no traced reader of the result.
  - The other small tilemaps:
    - the battle menu window and command-list maps (`$CC:FA41`-`$FADC`, `$D1:5800`-`$5E0F`); the
      battle's BG layers are not traced;
    - `BattleRom_FxMapPtrs` (`$D1:A575`, 16,789 B), built by `BattleCD_BuildFxTilemap` in a layout
      not traced here;
    - the battle background map packs (`BattleRom_BgMapPtrs`), queued to VRAM `$6800`, whose layer
      is not traced;
    - `MenuRom_NameChoiceMap`.

Second part (`data-maps-2`): the scene layer packs the eight scene headers name
(`maps.SCENE_NAMED`; `check` derives it from the headers). Their proof is `BankC2_InitHwRegs`:
mode 1, BG1/BG2 maps at VRAM `$6000`/`$6800`, BG3's at `$7800` (64x32).
- **Scene metatiles** (`scenemeta`, the 6 `C2SceneRom_MetatilePacks`, 4,096 B):
  `C2Scene_LoadMetatiles` unpacks one to `C2Scene_Metatiles` (`$7E:3000`). `C2Scene_LayerMetatiles`
  puts layer 1's set there and layer 2's at `$3800`: 256 metatiles of 8 B each. Each metatile is
  four tilemap words, which `C2Scene_DrawMetatile` puts into the column buffer that
  `C2Scene_DrawBgLayer` queues to the layer's tilemap. Text: two lists of 256 metatiles.
- **Scene maps** (`scenemaps`, the 8 `C2SceneRom_MapPacks`, 12,288 B): `C2Scene_LoadBgMaps`
  unpacks one to `C2Scene_BgMaps` (`$7E:4000`). It holds layer 1's map, with layer 2's at `$5800`
  (`C2Scene_LayerMaps`): 96 x 64 metatile numbers each, row by row (`C2Scene_DrawMetatile` reads
  column + row x 96). Text: two hex grids.
- **Scene BG3 tilemaps** (`scenebg3`, `C2SceneRom_Bg3MapPacks` 0-4, 4,096 B):
  `C2Scene_LoadBg3Map` unpacks one to `C2Scene_DecompBuf`, and `C2Scene_LoadVram` DMAs $1000 B of
  it to VRAM `$7800`, BG3's tilemap (64x32: two 32x32 screens one after the other). Text: two
  screens of 32 rows of tilemap words.
- **Results.** 19 packs (24,576 + 98,304 + 20,480 B unpacked) assemble and pack back byte-exact;
  `tools/verify.py` counts them under "maps".

## Sprite frame records as text

On the `data-tables-2` branch. `tools/sprites.py` gives the sprite frame records of banks `$DC`,
`$DD`, `$DE`, `$E1` and `$E3` (the 253,952 B of `sprite_layout` rows) a readable form in
`build/assets/sprites/`. The build assembles it to `build/sprites/`, which is incbin'd;
`tools/verify.py` counts it as "sprite frames".

- **The pointers.** `BattleRom_SprFramesPtr` (`$E4:2300`) holds one long pointer per sprite set.
  The field reads the same table through `Field_E4Ptr1`, whose low word comes from
  `RomE4_PtrInit` word 1, and the menu through `MenuRom_E4FramePtrs`, the same word; `check`
  tests that. Every reader takes the set number from byte 1 (`SprRec_Frames`) of a sprite record
  (`RomE4_SprRec`, 5 B, or the first five bytes of a `RomE4_EnemySprRec` record):
  `Evt_LoadSpriteRec`, `Evt_Op82_InitWramSprite`, `Evt_Op83_InitEnemySprite`, `Menu_SprLoad`,
  `Battle_InitScene`.
- **The record size** is byte 4 (`SprRec_Size`) bits 0-1 of the same record, and all three readers
  agree on it (`sprites.size_problems` checks each against `CLASS_BYTES`):
  - the field: `Obj_BuildSpriteFrameStep` sends size 0/1/2 to `Obj_BuildFrame4/8/12`, at
    `Frame4/8/12_Bytes` (40, 80, 120 B) per frame; size 3 is `Spr_LoadLargeObj`, 96 tile words
    (`SprBuf_Tiles`) then 24 pairs at `LargeObj_LayoutOfs`, so 240 B;
  - the menu: `Menu_SprTileCounts[size]` units of `Menu_SprFrameBytes` (40, 80, 120, 240 B);
  - battle: an enemy's layout is `FieldBtlObj.Flags & 7`, which holds `Obj_SprSize &
    ObjSpr_SizeMask`, and `Battle_DrawBattlerFrameAnyLayout` steps `BattleRom_FrameBytes` (40, 80,
    120, 240 B for layouts 0-3) per frame id.
- **The record.** N tile words (N = 16, 32, 48, 96), then N/4 position pairs. Each word gives a
  tile in bits 0-10 (`SprFrame_TileMask`), copied by `Spr_CopyTile`, with bit 14
  (`SprFrame_HFlip`) mirrored; the battle reader draws tile 0 blank. No reader tests bits 11-13
  or 15. Each pair is the signed OfsX, OfsY of one 16x16 sprite (`SprTileSrc`; the battle and menu
  readers copy the same bytes). The text writes a frame as its words (`TTT`, then `h`, `v`, `^n`
  for the bits no reader tests) and an `@` line of pairs.
- **The extent is inferred.** Frame f of a set is at pointer + f x size, and no reader bounds f.
  So a run is taken from each pointer up to the next one; sets that share an address are one
  run. All 220 runs that end at another pointer are a whole number of their records. The last
  run of each of the five areas ends at its last non-zero byte, rounded up to a whole record;
  those five are where the old "remainder" bytes were. The zero bytes after it (13,672 B in
  five rows) are padding, marked probable because a frame id could still reach them.
- **Results.** 4,745 frame records in 225 runs (237,320 B, nine pieces) assemble back byte-exact.
  `check` derives the runs from the ROM and refuses pieces that are not those runs, a pointer
  outside the five areas, an area no set starts, a run with two record sizes, or an inner run
  that is not whole records.
- **Not proven, still extracted** (2,960 B, four `sprite_layout` rows): the runs of sets 8, 9 and
  10 (`$DD:B900`, 1,840 B), 197 (`$DE:B068`), 140 (`$E3:42E0`, 960 B) and 216 (`$E3:E858`). No
  sprite record names these sets, so no reader gives their record size.
- **Not settled:**
  - Which frames are really shown. The frame-id lists at `$E4:3000` are no bound: in 12 runs
    they name ids past the run. In four of these the next run's records are a different size,
    and set 228's ids would read past `$DE:C000` into the message tables. Those animation rows
    are probably never played.
  - The battle-action frames (`$D1`) are separate tables, not done here (`$E4:0000`-`$17FF` holds the
    sprite palettes: "Tables, part 2").

## Tables, part 2: readers' extents

On the `data-tables-3` branch. Of the 157,019 B of tables still raw in 212 pieces, 95,257 B now
have readable forms whose layout and extent come from the code that reads them. 11,703 B turned
out to be zero fill and 659 B are split off as unknown. 49,400 B in 143 pieces stay bytes (listed
below). Each group's bound is re-derived by its tool's `check` and again at extraction.

- **Sprite animation lists** (`tools/anims.py`; pieces `animframes`, `animtimes`; 39,495 B):
  `AnimRom_FrameLists` (`$E4:3000`, 30,192 B) and `AnimRom_TimeLists` (`$E4:A800`, 9,303 B), for
  193 animations from the offsets at `$E4:2600`/`$2800`.
  - The field (`Evt_LoadSpriteRec`), battle (`Battle_InitScene`) and the menu (`Menu_SprLoad`) all
    take a facing block's size from the next animation's offset: (next - this) / 4.
  - Facing f starts at + f x stride, and row r at + 4r (`Obj_AnimFrameLookup`,
    `Battle_TickPcSlots`, `Menu_SprAnimate`). So a frame-id list's extent is the readers'.
  - Durations are rows of 4 at + 4r (`Obj_AnimTickAndQueue` and the same two). No reader bounds the
    row count, so each list ends at the next offset (inferred, as for the sprite frames).
  - `check` derives both lists from the offsets. It also checks that the field and the menu read
    the same two tables (`RomE4_PtrInit` words 2/3, `MenuRom_E4AnimFrames`/`AnimTimes`), and that
    the lists start at `RomE4_PtrInit` words 5/6.
  - Animation 193's next offset is 0, so no reader gives it an extent and no sprite record names
    it. Its one byte (`$DD`) after each area is an unknown row, as at `$E1:DDB2`. The zeros after
    it are padding.
- **Menu draw lists** (`tools/drawlists.py`; piece `drawlist`; 56 lists, 1,784 B):
  `Menu_RunDrawList` reads commands up to the first byte with bit 7 set.
  - A command's argument count is `MenuRom_DrawArgLens[c] + 1`. The command must be even and inside
    `Menu_DrawCmdTable` (the names come from that table).
  - Two rows hold whole commands and no end byte (`MenuRom_ShopMembersList`, `ShopEquipList`).
    They run on into the next row's list: their text ends `continues`, and extraction refuses one
    with no draw list after it.
  - The bytes after the end of `MenuRom_XchgListA` (14 B) and of `MenuRom_TechMembersList`
    (11 B) are list-shaped, but no reader is known: unknown rows.
- **Records** (`tools/records.py`; 13 pieces, 54,490 B, including `$E4:2A00`'s offsets; `DERIVED`
  re-derives each bound):
  - Action object records (`BattleRom_ActObjRec_Lists`, `$CE:8870`, 4,691 x 4 B). Every word of
    the three `*Objs` tables is an object pointer: `Battle_ActObjIdx` is a byte x 2, so it reaches
    no further than these tables.
    - `BattleAct_IndexObjLists` reads 16 lists from each pointer: 1xx/001 ends a list, 010 marks
      it, and the first record of lists 1-15 is untested.
    - Together they cover `$CE:8870`-`$D1BB` with no gap (`obj_lists_extent`). The 620 B after
      that are reached by none: an unknown row.
  - Domain bounds:
    - `BattleRom_FxGfxLists` (`$CF:A000`, 256 sets x 32 words) and `FxGfxColours`: the set is a
      byte (`Battle_FxTileSet`).
    - `BattleRom_EnemyStats` (`$CC:4700`, 256 x 23 B, the fields as `BattleFD_UnkB438` copies
      them).
    - `BattleRom_EnemyEffectRecA` (255 x 12 B; part number $FF is skipped, and its 12 B are split
      off).
    - `BattleRom_ExpToLevel` (levels 0-`Battle_LevelMax`).
    - `BattleRom_EnemyActObjs`, `BattleRom_HalfPlaneEdge` (an angle byte),
      `MenuRom_SlotEraNibbles` (a 9-bit location / 2).
    - The sprite palettes `AnimRom_Palettes` (`$E4:0000`, 256 x 12 colours: a palette byte x
      `Pal_ObjColorBytes`) and their offsets `MenuRom_E4PalOffsets` (`$E4:2A00`).
    - `RomE4_SprRec`, now 263 records: `Evt_Op82_InitWramSprite` reads `SprRec_FirstNpc` + a byte,
      so the last record's size byte is the old padding's first byte.
  - Data bound: `LocGfx_Lists` holds 54 entries. Its index's only source is `LocRom.Tileset12`,
    whose values reach 53. Entries 54-63 (80 B) stay bytes.
- **Pointer table**: `BattleRom_SprFramesPtr` (`$E4:2300`) is now written as labels into the sprite
  frame pieces.
- **Still raw** (49,400 B in 143 pieces), by reader:
  - **Battle action loaders** (`BattleAct_*`, 25 pieces, 11,418 B): `BattleRom_PcAttackAct`,
    `PcTechAct`, `EnemyAttackAct`, `EnemyAttack2Act`, `EnemyTechAct`, `ActObjInit`, the palette
    steps (`$CD:EE23`), `TechObjs` and the other palette and object tables. Some indexes are read
    16-bit without the high byte cleared, so no bound is proved: `Battler_Unk984D` is a word, and
    `Battle_ActId` and the PC attack record have B not cleared. Others are bytes that reach past
    the row into the next table.
  - **Battle layer effects** (`BattleCD_*`, 10 pieces, 9,988 B):
    - `BattleRom_FxTileLists`: the set word is a byte plus bit 6 of the count byte, which reaches
      past the row;
    - `FxRecords` (masked with `$7FFF`) and `FxScripts`;
    - smaller tables indexed by values from those records.
  - **Sound** (`AudioRom_Song*`, 5,810 B), left for the music work.
  - **Battle system and stats** (`BattleSys_*`, `BattleFD_*`; 21 pieces, 9,275 B):
    - the area and item records at `$CC:0000`, the tech records, the equipment records;
    - `BattleRom_UnkCC6FCB`, the effect records B;
    - all indexed by values from other unproved tables.
  - **No reader found** (6 pieces, 2,756 B): `$CD:F188`, `$F8:AF6F`, `$CC:FC2C`, `$CC:F383`,
    `MenuRom_DrawArgLens` (indexed by any command byte below $80, while the commands stop at $14),
    and `LocGfx_Lists`' tail.
  - **HDMA sets** (`BattleRom_HdmaSetRecs`/`SetOfs`, 2,738 B): records, then tables at the
    offsets the records hold; not traced.
  - **`RomE4_EnemySprRec`** (2,528 B): battle's index is an enemy id x 10, which reaches into
    `RomE4_PtrInit`.
  - **Small menu, battle-menu, battle-sprite and scene tables** (75 pieces, 4,887 B): their
    readers' indexes reach past the row (a slot or row number wider than the table), or are
    computed from values not traced. This includes the `C2SceneRom_*_Tail` bytes after the scene
    pointer tables.

## Palettes

On the `data-tables-4` branch. A palette is converted only where its readers prove both how many
colours it holds and that they reach CGRAM. Each count is re-derived by `check`.

- **Raw palettes as records** (`tools/records.py` `PALETTES`, R/G/B columns with bit 15 kept;
  19,108 B):
  - `LocPal_Rom` (`$F6:24C0`, 616 rows of 15 colours). `LocLoad_Unk7084` copies 7 rows of colours
    1-15 (`LocPal_RowBytes` each) of entry `LocRom.Palette` to `Pal_Buf` rows 1-7.
    `Pal_LoadUnkRow0` copies `Pal_Buf` to `Pal_CgramBuf`, and `Pal_UploadCgram` DMAs that to CGRAM
    from colour 0. 88 entries: `LocRom`, this index's only source, names palettes 0-87 (`DERIVED`
    with `LocPal_SetBytes` = 7 x `LocPal_RowBytes`).
  - `BattleRom_BgSetPalettes` (`$D0:FA00`, 15 rows of 16). `BattleFx_LoadBgSet` copies 3 rows from
    `BattleFx_BgSetPalOfs[set]` (sets 0-5, read from the source) to BG palette rows 2-4 of the
    battle palette, which `$CF` sends to CGRAM in full. The 2 B after the last row are unknown.
  - The window palettes (`$FF:B210`, 9 x 8 colours). `Menu_LoadWindowPal` copies 8 colours of
    style 0-7; `Pal_LoadUnkRow0` copies 15 from style x 16 + 2, so it reaches `$FF:B29F`. The 112
    B after that are reached by no reader: a probable palette row.
  - `BattleRom_FxTintColours` (2 colours, written by `Battle_FxOverlay2Tint` into live palette
    bytes 6-9).
- **Scene palette packs** (`tools/maps.py`, piece `scenepal`; 8 packs, 2,813 B packed, 3,616 B
  unpacked; text rows of 16 colours as `R,G,B`, `!` for bit 15):
  - Packs 4-10 are the ones the scene headers name (`C2Scene_HdrPalettes`). `C2Scene_LoadPalettes`
    unpacks one to `C2Scene_PaletteStage`, which `C2Scene_LoadVram` DMAs to CGRAM from colour 0
    (`C2Scene_PaletteBytes`, 512 B).
  - Pack 3 is `C2Scene_ExtraPalPack`, unpacked into the CGRAM shadow `C2Scene_PaletteBuf`.
  - `scene_named` derives the set and `check` compares it.
- **Not proven, still bytes:**
  - `$F6:6CF0` (3,728 B), the palette-animation colours. `PalAnim_*` reads them at offsets from
    `FieldRom_AnimListB` records; their extent is not traced.
  - The three `$FE` palettes (1,986 B), read by the `$C3` module, whose code is being matched
    separately.
  - `BattleRom_PalSets14`/`PalSets6` (2,038 B): the set number comes from the palette-step records
    (`$CD:EE23`), which are not proved.
  - Rows whose readers' byte index reaches past the row:
    - `BattleRom_SpecialPals` (786 B: opcode `$69`'s operand x 24);
    - `BattleRom_FxColours` (576 B: a script id x 8);
    - `MenuRom_MainPalB` (16 B).
  - `BattleRom_FxCycleColours` (640 B), read through `BattleRom_FxCycleList`'s offsets, whose
    extent is not proved.
  - `BattleRom_WeaponColours` (192 B), indexed through `BattleRom_WeaponColourIdx`, which is not
    proved.
  - `BattleRom_GradColours` (286 B): 14-colour sets `$20` apart. The 4 B between sets are not read
    as colours, so the row is not one layout.
  - `MenuRom_SlotIconPals` (368 B): character x 32 reaches 224 B, but the row is not whole rows.
  - Scene palette packs 0 (the party pack: only the first 16 B of each character's 32 are read),
    1, 2 and 11-17 (no header names them; script loads are not traced), and 18
    (`C2Scene_UnkC600Pack`, whose use is not traced).

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
7. **Script languages**: battle, layer-effect, scene and location event scripts (done,
   below), music sequences (2-3).
8. **Readable assets**: tile converters (raw tiles: first part done, below; the packed ones
   next), palette converters, sprite frames (2), maps if wanted.
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
- **The character tile blocks**: ends not decoded yet (the sprite frame records are done: see
  "Sprite frame records as text"; their per-set ends stay inferred).
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
- (Settled: `$E4:0000`-`$17FF` is the sprite palettes, "Tables, part 2"; the sprite frame records,
  "Sprite frame records as text".)
