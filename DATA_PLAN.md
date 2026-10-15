# Data plan

How the rest of the ROM, everything the 65816 and SPC700 source does not emit yet, can be
described in source, so that one day the build no longer copies bytes from the original ROM.
The measured map is `symbols/data_survey.csv` (one row per region); `python3 tools/data_survey.py`
checks that it covers exactly the bytes `tools/verify.py` does not count as emitted, and prints
the totals below. Survey of 2026-10-15, from `main` at 306,435 emitted bytes (280,042 assembled,
plus the packed `$C3` module, 26,393 bytes, which `tools/c3pack.py` packs from source since PR #113
and verify counts apart).

## What is left

3,887,869 bytes (92.69% of the 4,194,304-byte ROM) in 2,227 rows. Shares are of the whole ROM.

| kind | bytes | share | rows | confirmed / probable / unknown |
|---|---:|---:|---:|---|
| packed_lz | 2,349,647 | 56.02% | 1,522 | 2,346,638 / 3,009 / 0 |
| graphics (raw tiles) | 336,619 | 8.03% | 28 | 328,331 / 8,288 / 0 |
| sprite_layout | 253,952 | 6.05% | 5 | 253,952 / 0 / 0 |
| text | 208,485 | 4.97% | 48 | 206,683 / 1,802 / 0 |
| brr_sample | 203,202 | 4.84% | 66 | 203,202 / 0 / 0 |
| table | 176,842 | 4.22% | 296 | 174,223 / 2,097 / 522 |
| music_sequence | 107,721 | 2.57% | 87 | 104,092 / 3,629 / 0 |
| battle_script | 102,443 | 2.44% | 12 | 102,443 / 0 / 0 |
| padding | 66,146 | 1.58% | 82 | 66,146 / 0 / 0 |
| palette | 32,292 | 0.77% | 46 | 25,042 / 7,250 / 0 |
| tilemap | 19,717 | 0.47% | 10 | 19,717 / 0 / 0 |
| font | 9,216 | 0.22% | 2 | 9,216 / 0 / 0 |
| event_script (scene animation table) | 7,946 | 0.19% | 1 | 7,946 / 0 / 0 |
| unknown | 6,865 | 0.16% | 17 | 0 / 0 / 6,865 |
| map (exit and treasure records) | 6,694 | 0.16% | 2 | 6,694 / 0 / 0 |
| spc_data | 82 | 0.00% | 3 | 82 / 0 / 0 |

Confidence over all 3,887,869 bytes: confirmed 3,854,407 (99.14%), probable 26,075 (0.67%),
unknown 7,387 (0.19%). "Confirmed" means a matched routine, or a pointer table a matched routine
reads, reaches the region and the code fixes its format; where only the start is reached, the
row's notes say the end is inferred (it runs to the next known region). The table and padding
counts include such inferred ends; how far each named table really runs is the main thing the
per-kind work below still has to settle.

### The packed bytes, by content

Every `packed_lz` row is one Decomp_ToWram stream (`$C3:0002`), and every one of the 1,522
repacks byte-exact with the packer of `tools/c3pack.py`:
`python3 tools/data_survey.py --packs` checks all of them (about 20 s).
960 use 11-bit offsets, 562 12-bit. Unpacked they hold 4,009,024 bytes.

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
| empty packs (3 bytes, reached by tables) | 51 | 0 | 17 |

## How the survey was made

1. The emitted ranges come from `tools/verify.py` (the source on all-$00 and all-$FF bases).
2. Packs: a scan of every unemitted offset for a stream Decomp_ToWram reads to its end marker
   that `c3pack.pack` rebuilds byte for byte (1,592 hits). A hit counts as a pack when a pointer
   table read by matched code points at it: the eighteen long-pointer tables the decompressor's
   42 callers index (listed in Decomp_ToWramVec's header, `$C3:0002`), the word table at
   `$D1:0000` (BattleAct_LoadCommon), `C2Scene_DialPacks` (`$C2:7220`), `Credits_GfxPack` and
   `MenuRom_ScreenGfx`. 12 unreferenced hits of 40 bytes or more are kept as probable packs;
   the other 86 hits are small (up to 30 bytes), lie inside tables, text and tiles, and are
   chance.
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
   64 or more at the end of a region whose end was only inferred is split off as padding.
6. The rest is listed one row each, with what is known (`unknown`, 17 rows).

## Per kind: what a byte-exact round trip needs

Effort is in working sessions of the size this project's matching sessions have been. Every
step ends the same way: the bytes come from source and assets instead of the ROM copy, and
`make gate` stays byte-exact.

**Fill and padding** (66 KB). A fill directive per row (value and count are in the CSV). No
risk. A few rows of stale bytes (`unknown`) sit beside the fill and stay raw blobs.
Difficulty trivial; with step 1 below.

**Packed streams** (2.35 MB, 56%). Store the unpacked contents and pack at build time; the
packer exists and is exact for every stream (Okumura's LZSS with the original's changes, the
two-segment framing and the per-stream mode, all in `tools/c3pack.py`). What the round trip has
to record: the mode of each stream (11 or 12 bit); the placement (streams sit back to back,
in table order in most banks, with a few gaps of stale bytes); and the pointer tables, which
become `dl Label` entries, except the entries that point at stale or non-pack bytes (Evt_PackPtrs
102-110, 231-235, 320-322; LocGfx_PackPtrs 204-218; LocGfx_Meta3Ptrs 19-22; Map_PropsPtrs 201)
and the tables with duplicate entries, which must keep their exact values. The 17 empty packs
are 3 bytes each. Build time: packing all 4 MB in Python takes about 20 s, so the build should
cache the packed output (as c3pack's module build does). Difficulty low; 1-2 sessions (the
packer and a packed build path exist since PR #113). Readable formats for the unpacked contents are separate, later work
(graphics to PNG, maps, event and scene script disassembly, below).

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
driver's command table (command lengths), with the songs' internal pointers turned into labels
at the ARAM base `$2000` (`!AudioAram_Song`) and the effect tracks at `$2F00`. Note
`Audio_SongTable` is not in address order (songs `$0E`/`$0F` are swapped in ROM). Difficulty
medium; 2-3 sessions.

**Text** (208 KB). 15 message tables (word pointers, then strings), the 127-entry dictionary at
`$DE:FA00`, the treasure strings, the scene labels and the fixed-length name tables in `$CC`.
The decoder is matched (TextWin_State0 and TextWin_CodeTable): `$A0`-`$FF` glyphs, `$21`-`$9F`
dictionary sub-strings, `$00`-`$20` control codes (`$01`, `$02`, `$03` and `$12` take one byte;
`$00` ends). The order-dependent part is the dictionary: a text-to-bytes encoder must choose the
same dictionary substitutions the original tool made. Two ways: keep dictionary references
explicit in the source text (always exact), or find the original rule (probably a greedy longest
match over a fixed entry order; testable over the 4,600 strings) and fall back to explicit
references where it differs. The string pointer tables follow from string lengths, but events
point into the middle of tables (op `$B8` with an address inside `$F7:4900`'s table), and a few
stale strings sit between tables (rows marked probable), so the tables keep labels for those.
Difficulty medium; 2-4 sessions.

**Tables** (177 KB in 296 rows) and **palettes** (32 KB). Battle data in `$CC` (items, techs,
enemies, growth, shop lists), `$CD`/`$CE` action records, `$E4` animation lists, `$F6` location
records, menu draw lists in `$FF`, and so on: every one has a named reader and a define comment
with its record layout. Work: `db`/`dw` with the record as an asar struct or macro, word offsets
turned into labels, and each table's true length settled from its reader (many ends are inferred
now). Palettes are BGR555 words. Difficulty low to medium per table, but many; 3-5 sessions.

**Battle scripts** (102 KB). Action scripts (`BattleAct` opcodes `$00`-`$DA`, lengths fixed by
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
2. **Extraction and placement framework** (1-2 sessions): `tools/extract_data.py` writes one
   asset per CSV row; a generated `asm/data/*.asm` per bank places each row (`incbin` of its
   asset, fill directives, labels at row starts). Verify then counts every byte as emitted.
   This is the step that ends the ROM copy for the structure; content is still binary.
3. **Packed streams from unpacked assets** (1-2 sessions): pack at build time with a cache;
   pointer tables as labels. Biggest share (56%) and the packer is done.
4. **Blobs that need no decoder** (1 session): padding, BRR samples, song and effect blocks,
   raw graphics, sprite layout, unknown rows. With 2 and 3 this covers about 85% of the
   remaining bytes.
5. **Text** (2-4 sessions): the encoder and the dictionary question; the pointer tables.
6. **Tables and palettes** (3-5 sessions), in bank order; settles the inferred table ends.
7. **Script languages**: battle scripts (3-5), location event scripts (3-6, depends on 3),
   scene scripts (2-3), music sequences (2-3).
8. **Readable assets**: tile and palette converters (2-3), sprite frames (2), maps if wanted.
9. **Unknown and probable rows** (1).

## Overall estimate

- A byte-exact build in which no region is copied from the ROM, with data as extracted binary
  assets (steps 1-4): about 4-6 sessions.
- Readable source for text, tables and scripts (steps 5-7): about 15-25 sessions more.
- Readable graphics, frames and maps (step 8): about 4-6 sessions more.

So roughly 25-35 sessions to describe everything in readable form, and under a tenth of that to
stop copying bytes. Uncertainties, largest first:

- **The script languages.** Event scripts (568 KB unpacked) and battle scripts depend on every
  opcode's operand length and on finding all jump targets; a handler whose length depends on
  its operands, or code that jumps into data, can stretch the estimate.
- **The text encoder.** If the original dictionary rule cannot be recovered, explicit references
  make the source text harder to edit (it still round-trips).
- **Table ends.** About a third of the table bytes run to the next named table only by
  inference; each has to be settled from its reader before it gets a struct.
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
  packed streams, one in an unpacked sprite pack, one in a sample), the rate expected by chance. The code survey's own checks (no
  instruction of matched code reaches an unmatched byte; routine-shaped runs in unmatched ROM no
  longer than 19 instructions) already covered the raw bytes.
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
- 17 unknown rows (6,865 bytes), each described in its notes: stale bytes beside unused pointer
  entries, four single bytes of the same value right after a run of packs, and small gaps.
- The internal layout of the sprite frame records and of `$E4:0000`-`$1FFF`.
