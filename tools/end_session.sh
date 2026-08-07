#!/usr/bin/env bash
# tools/end_session.sh — close out a matching session in one command.
#
# Usage: ./tools/end_session.sh "session N: matched FooBar (N bytes)"
#
# What it does (in order):
#   1. Regenerate docs/includes/progress_summary.md from PROGRESS.md
#   2. Check for a devlog post dated today; prompt if missing
#   3. Remind about BANK_MAP.md / PROGRESS.md if asm/ changed
#   4. git add -A && git commit with your message (pre-commit hook runs automatically)

set -euo pipefail

MSG="${1:-}"
if [ -z "$MSG" ]; then
    echo "Usage: $0 \"commit message\""
    exit 1
fi

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
step() { printf "\n${BOLD}==> [%s/4] %s${RESET}\n" "$1" "$2"; }
warn() { printf "${YELLOW}  ! %s${RESET}\n" "$*"; }
ok()   { printf "${GREEN}  ✓ %s${RESET}\n" "$*"; }

echo ""
printf "${BOLD}=== End-of-session checklist ===${RESET}\n"

WIKI_DIR="../chrono-trigger-wiki"
WIKI_DOCS="${WIKI_DIR}/docs"

# ── 1. Regenerate progress snippet ───────────────────────────────────────────
step 1 "Regenerate progress snippet"
python3 tools/progress.py --update-index

# ── 2. Devlog check ──────────────────────────────────────────────────────────
step 2 "Check devlog"
TODAY=$(date +%Y-%m-%d)
POSTS_DIR="${WIKI_DOCS}/devlog/posts"
FOUND=$(ls "${POSTS_DIR}/${TODAY}"*.md 2>/dev/null || true)

if [ -n "$FOUND" ]; then
    ok "Found: $FOUND"
else
    warn "No devlog post for today ($TODAY)."
    warn "Expected a file matching: ${POSTS_DIR}/${TODAY}*.md"
    echo ""
    read -r -p "  Continue without a devlog entry? [y/N] " reply
    if [[ "${reply:-n}" != [Yy]* ]]; then
        echo "  Aborted. Write a devlog entry in the wiki repo and re-run."
        exit 1
    fi
fi

# ── 3. Manual-update reminders ───────────────────────────────────────────────
step 3 "Reminders"
# Check both unstaged and staged asm/ changes relative to HEAD
CHANGED_ASM=$(
    { git diff --name-only HEAD -- asm/ 2>/dev/null; \
      git diff --cached --name-only -- asm/ 2>/dev/null; } | sort -u || true
)
if [ -n "$CHANGED_ASM" ]; then
    warn "asm/ has changes — verify before committing:"
    warn "  ${WIKI_DOCS}/PROGRESS.md  — byte counts + matched function table"
    warn "  ${WIKI_DOCS}/BANK_MAP.md  — region status (Identified → Matched, end addresses)"
    warn "(commit wiki repo separately after updating those files)"
else
    ok "No asm/ changes detected — reminders skipped."
fi

# ── 4. Stage all and commit (pre-commit hook fires here) ─────────────────────
step 4 "Stage all and commit"
git add -A
echo ""
git status --short
echo ""
git commit -m "$MSG"

printf "\n${GREEN}Session closed.${RESET}\n"
