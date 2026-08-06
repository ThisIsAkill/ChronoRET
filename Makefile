ROM         ?= roms/chrono_trigger.sfc
BUILD_DIR   := build
OUT_ROM     := $(BUILD_DIR)/chrono_trigger.built.sfc
MAIN_ASM    := asm/main.asm

.PHONY: all build diff clean check-rom setup

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

clean:
	rm -rf $(BUILD_DIR)

# One-time environment sanity check
setup:
	python3 tools/check_env.py

# Install pre-commit hook (requires git repo)
install-hook:
	cp tools/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "pre-commit hook installed."
