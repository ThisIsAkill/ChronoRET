ROM         ?= roms/chrono_trigger.sfc
BUILD_DIR   := build
OUT_ROM     := $(BUILD_DIR)/chrono_trigger.built.sfc
MAIN_ASM    := asm/main.asm

.PHONY: all build diff verify lint gate progress test-hooks duplicates clean check-rom setup

all: build diff

check-rom:
	@if [ ! -f "$(ROM)" ]; then \
		echo "No ROM found at $(ROM)."; \
		echo "Copy your own legally-dumped Chrono Trigger ROM there first."; \
		exit 1; \
	fi

build: check-rom
	@mkdir -p $(BUILD_DIR)
	cp $(ROM) $(OUT_ROM)
	asar --fix-checksum=off $(MAIN_ASM) $(OUT_ROM)
	@echo "Built -> $(OUT_ROM)"

diff: build
	python3 tools/diff_rom.py $(ROM) $(OUT_ROM)

# Every source-emitted byte matches the ROM, independent of the base ROM.
verify: check-rom
	python3 tools/verify.py

# Readability standard (functions in tools/readability_baseline.txt are
# grandfathered and may only shrink).
lint:
	python3 tools/lint_readability.py

# Regenerate every generated number: symbols/ and the README/CONTRIBUTING/
# STATUS blocks.
progress: check-rom
	python3 tools/progress.py --update

# Byte-identical copies of matched routines elsewhere in the ROM.
duplicates: check-rom
	python3 tools/find_duplicates.py

# Prove the pre-commit firewall rejects planted ROMs, notes and blocked words.
test-hooks:
	tools/test_hooks.sh

# What a function needs before it reaches main.
gate: diff verify lint

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
