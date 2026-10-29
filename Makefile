ROM         ?= roms/chrono_trigger.sfc
BUILD_DIR   := build
OUT_ROM     := $(BUILD_DIR)/chrono_trigger.built.sfc

.PHONY: all build extract data-check diff verify lint gate progress test-hooks test-tools duplicates duplicates-reloc xref clean check-rom setup tables-scan draft

all: build diff

check-rom:
	@if [ ! -f "$(ROM)" ]; then \
		echo "No ROM found at $(ROM)."; \
		echo "Copy your own legally-dumped Chrono Trigger ROM there first."; \
		exit 1; \
	fi

# The ROM from the source and the assets extracted from your own ROM
# (tools/build_rom.py): extract (build/assets/, cached), pack the module
# and the data packs (cached), then assemble asm/rom.asm onto blank $00 and
# $FF images, which must agree (every byte written). Nothing is copied
# from the original ROM.
build: check-rom
	@mkdir -p $(BUILD_DIR)
	python3 tools/build_rom.py -o $(OUT_ROM)

# The data layer's assets, from your ROM into build/assets/ (never
# committed; tools/extract_data.py), the game's text among them as
# readable files in build/assets/text/ (tools/text.py). `make build` runs
# it when needed.
extract: check-rom
	python3 tools/extract_data.py extract

# The manifest and asm/data/ are what tools/extract_data.py generates from
# symbols/data_survey.csv (the pointer tables' entries only with the ROM).
data-check:
	python3 tools/extract_data.py check

diff: build
	python3 tools/diff_rom.py $(ROM) $(OUT_ROM)

# Every source-emitted byte matches the ROM, independent of the base ROM.
verify: check-rom
	python3 tools/verify.py

# Readability standard (functions in tools/readability_baseline.txt are
# grandfathered and may only shrink).
lint:
	python3 tools/lint_readability.py

# Write the generated symbols/functions.csv and progress.json (untracked; the
# tools that read them also regenerate them on demand) and print the numbers.
progress: check-rom
	python3 tools/progress.py --update

# Byte-identical copies of matched routines elsewhere in the ROM.
duplicates: check-rom
	python3 tools/find_duplicates.py

# Every code reference to an address, each CONFIRMED or DOUBTFUL:
#   make xref ADDR=C100D7          (or ADDR=Battle_Divide, ADDR='$$C1:00D7')
#   make xref ADDR=C0007D XREF_FLAGS=--branches
xref: check-rom
	@if [ -z '$(value ADDR)' ]; then echo "Usage: make xref ADDR=C100D7 [XREF_FLAGS='--branches --json']"; exit 1; fi
	@python3 tools/xref.py '$(value ADDR)' $(XREF_FLAGS)

# Copies that differ only in absolute/long operands (call targets, data
# addresses), whole routines and fragments, outside matched code.
RELOC_FLAGS ?= --fragments 6 --unmatched-only --max-differing 3
duplicates-reloc: check-rom
	python3 tools/find_duplicates.py --relocatable $(RELOC_FLAGS)

# Candidate data tables (jump/pointer tables) in a bank's unmatched bytes;
# `python3 tools/tables.py emit ...` prints one as source.
BANK ?= C1
tables-scan: check-rom
	python3 tools/tables.py scan --bank $(BANK)

# Prove the pre-commit firewall rejects planted ROMs, notes and blocked words.
test-hooks:
	tools/test_hooks.sh

# The analysis tools' regression tests: xref's verdicts (including the
# held-out score), the lint's INDEX and SIZE rules, the SPC700 decoder and
# the lint's SPC700 rules, the packer of the $C3 module (tools/c3pack.py), its
# trace and the lint's module rules (tools/c3module.py, tools/lint_c3module.py),
# the data survey's coverage (tools/data_survey.py), the data layer's
# manifest, lint and isolation (tools/test_data_layer.py), the text
# encoder and its round trip (tools/test_text.py), the tables and
# palettes as records (tools/test_records.py), the event scripts'
# disassembly and its interpreter (tools/test_events.py), the battle
# scripts' readable form (tools/test_battle.py), the scene and
# layer-effect scripts' (tools/test_scripts.py), and the tile graphics as
# images (tools/test_graphics.py).
# They need the ROM and asar (skipped otherwise); about a minute together.
# CI's ROM job runs this.
test-tools:
	python3 tools/test_xref.py
	python3 tools/test_index_claims.py
	python3 tools/test_lint_size.py
	python3 tools/test_spc700.py
	python3 tools/test_lint_spc700.py
	python3 tools/test_c3pack.py
	python3 tools/test_c3module.py
	python3 tools/test_data_survey.py
	python3 tools/test_data_layer.py
	python3 tools/test_text.py
	python3 tools/test_records.py
	python3 tools/test_events.py
	python3 tools/test_battle.py
	python3 tools/test_scripts.py
	python3 tools/test_graphics.py

# Draft source for an unmatched routine, checked byte-exact, in build/:
#   make draft ADDR=C1:3714 [END=C1:373A] [DRAFT_ARGS="--x 1 --dp 0100 --db 00"]
draft: check-rom
	@if [ -z '$(value ADDR)' ]; then echo "Usage: make draft ADDR=C1:3714 [END=C1:373A] [DRAFT_ARGS='--m 1 --x 0 --dp 0 --db 7E']"; exit 1; fi
	@mkdir -p $(BUILD_DIR)
	@a='$(value ADDR)'; a=$${a#\$$}; out=$(BUILD_DIR)/draft_$$(echo "$$a" | tr -d ':').asm; \
	python3 tools/draft.py "$$a" $(if $(value END),'$(value END)') $(DRAFT_ARGS) --check -o "$$out"

# What a function needs before it reaches main.
gate: diff verify lint data-check

clean:
	rm -rf $(BUILD_DIR)

# One-time environment sanity check
setup:
	python3 tools/check_env.py

# Install pre-commit/commit-msg hooks (requires git repo)
install-hook:
	@hooks=$$(git rev-parse --git-common-dir)/hooks; \
	cp tools/pre-commit $$hooks/pre-commit; \
	cp tools/pre-commit $$hooks/commit-msg; \
	cp tools/pre-push $$hooks/pre-push; \
	chmod +x $$hooks/pre-commit $$hooks/commit-msg $$hooks/pre-push; \
	echo "pre-commit, commit-msg, pre-push hooks installed in $$hooks."
