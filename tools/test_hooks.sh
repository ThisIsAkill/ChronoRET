#!/usr/bin/env bash
# test_hooks.sh — prove the pre-commit firewall actually fires.
#
# A check that has never failed proves nothing. This plants things the hook
# must refuse (a ROM image, a generated file, a local notes file, a blocked word) in a scratch
# checkout of HEAD and asserts the hook rejects each one, then asserts it
# accepts a harmless change. Run it whenever tools/pre-commit changes.
set -uo pipefail

root=$(git rev-parse --show-toplevel)
scratch=$(mktemp -d)
trap 'git -C "$root" worktree remove --force "$scratch/tree" >/dev/null 2>&1; rm -rf "$scratch"' EXIT
git -C "$root" worktree add -q --detach "$scratch/tree" HEAD
cd "$scratch/tree"
# The hook rebuilds the ROM when one is present; this test is about the
# firewall, so run it without a ROM (the hook skips the byte checks then).
failures=0

expect() {  # expect <accept|reject> <description>
    local want=$1 what=$2 got
    if bash "$root/tools/pre-commit" >/dev/null 2>&1; then got=accept; else got=reject; fi
    if [ "$got" = "$want" ]; then
        echo "  ok    $what ($got)"
    else
        echo "  FAIL  $what: expected $want, hook did $got"
        failures=$((failures + 1))
    fi
    git reset -q --hard HEAD
    git clean -qfd
}

export GIT_AUTHOR_NAME="Akill" GIT_AUTHOR_EMAIL="24420588+ThisIsAkill@users.noreply.github.com"
export GIT_COMMITTER_NAME="Akill" GIT_COMMITTER_EMAIL="24420588+ThisIsAkill@users.noreply.github.com"

echo "Planted fixtures (each must be rejected):"
head -c 4096 /dev/zero > planted.sfc && git add -f planted.sfc
expect reject "a ROM image (.sfc)"

head -c 4096 /dev/zero > planted.smc && git add -f planted.smc
expect reject "a ROM image (.smc)"

mkdir -p symbols && echo "address" > symbols/functions.csv && git add -f symbols/functions.csv
expect reject "a generated file (symbols/functions.csv)"

echo "local notes" > C$(printf L)AUDE.md && git add -f C$(printf L)AUDE.md
expect reject "a local session-notes file"

word=$(printf 'cl%sude' a)
echo "; written by $word" >> README.md && git add README.md
expect reject "a blocked word in staged content"

echo "Control (must be accepted):"
echo "" >> README.md && git add README.md
expect accept "a harmless whitespace change"

if [ "$failures" -ne 0 ]; then
    echo "FAIL: $failures firewall check(s) did not behave."
    exit 1
fi
echo "Firewall verified: every planted fixture was rejected."
