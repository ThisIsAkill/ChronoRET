#!/usr/bin/env bash
# tools/end_session.sh — open or close a working session.
#
#   tools/end_session.sh --audit        session START: everything must be green
#                                       before any new work; if not, fixing it
#                                       is the work.
#   tools/end_session.sh "message"      session END: regenerate every number
#                                       (with today's history row), run the
#                                       gate, commit.
#
# Documentation (devlog, systems pages) is written afterwards from the wiki's
# side, which pulls symbols/ from here; this repository never writes into it.
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
step() { printf "\n${BOLD}==> %s${RESET}\n" "$*"; }
ok()   { printf "${GREEN}  ✓ %s${RESET}\n" "$*"; }
bad()  { printf "${RED}  ✗ %s${RESET}\n" "$*"; FAILED=1; }
FAILED=0

audit() {
    step "Hooks installed"
    hooks=$(git rev-parse --git-common-dir)/hooks
    for h in pre-commit commit-msg pre-push; do
        if [ -x "$hooks/$h" ] && cmp -s "$hooks/$h" "tools/$( [ "$h" = commit-msg ] && echo pre-commit || echo "$h")"; then
            ok "$h is current"
        else
            bad "$h missing or stale: run make install-hook"
        fi
    done

    step "Byte-exact, full coverage, readability"
    if make --no-print-directory -s gate >/dev/null 2>&1; then ok "make gate"; else bad "make gate (run it to see why)"; fi

    step "Generated numbers and review log"
    if python3 tools/progress.py --check >/dev/null; then ok "generated symbols/ untracked and current"; else bad "tools/progress.py --check (run it to see why)"; fi
    if python3 tools/validate_functions.py >/dev/null; then ok "symbols/ valid"; else bad "tools/validate_functions.py"; fi

    step "Firewall fires on planted fixtures"
    if tools/test_hooks.sh >/dev/null 2>&1; then ok "tools/test_hooks.sh"; else bad "tools/test_hooks.sh (run it to see which check)"; fi

    step "Nothing that must never be tracked"
    tracked=$(git ls-files | grep -iE '\.(sfc|smc)$|(^|/)(C[L]AUDE\.md|SESSION[^/]*\.md)$' || true)
    if [ -z "$tracked" ]; then ok "no ROMs or local notes tracked"; else bad "tracked: $tracked"; fi

    remaining=$(grep -cv '^#' tools/readability_baseline.txt || true)
    step "Readability burn-down"
    ok "$remaining routine(s) still in tools/readability_baseline.txt"
}

if [ "${1:-}" = "--audit" ]; then
    audit
    [ "$FAILED" = 0 ] && printf "\n${GREEN}Audit clean.${RESET}\n" || { printf "\n${RED}Audit failed: fix this first.${RESET}\n"; exit 1; }
    exit 0
fi

MSG="${1:-}"
[ -n "$MSG" ] || { echo "Usage: $0 --audit | \"commit message\""; exit 1; }

step "Regenerate numbers (with today's history row)"
python3 tools/progress.py --update-history

audit
[ "$FAILED" = 0 ] || { printf "\n${RED}Not committing: fix the failures above.${RESET}\n"; exit 1; }

step "Commit"
git add -A
git status --short
git commit -m "$MSG"
printf "\n${GREEN}Session closed.${RESET} Update STATUS.md / NEXT.md if the target moved.\n"
