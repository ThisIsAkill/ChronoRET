#!/usr/bin/env bash
# pre_push.sh — the gate every push goes through (installed as the pre-push
# hook by `make install-hook`). Checks the commits being pushed, then the tree.
#
#   - author and committer of every new commit is the maintainer identity
#   - no session links or blocked words in commit messages
#   - make gate (byte-exact, full coverage, readability) and symbols/ current
set -euo pipefail
IDENT='Akill <24420588+ThisIsAkill@users.noreply.github.com>'
fail() { printf '\033[0;31m[pre-push] %s\033[0m\n' "$*" >&2; exit 1; }

range="${1:-origin/main..HEAD}"
while read -r line; do
    [ "$line" = "$IDENT" ] || fail "commit by '$line' in $range (expected $IDENT)"
done < <(git log "$range" --format='%an <%ae>%n%cn <%ce>' | sort -u)

msgs=$(git log "$range" --format='%B')
if printf '%s' "$msgs" | grep -qiE 'c[l]aude\.[a]i/code|C[l]aude-Session:'; then
    fail "a commit message in $range carries a session link"
fi

make --no-print-directory -s gate >/dev/null || fail "make gate failed"
python3 tools/validate_functions.py >/dev/null || fail "symbols/ is invalid (tools/validate_functions.py)"
python3 tools/progress.py --check >/dev/null || fail "symbols/ is stale: run tools/progress.py --update"
echo "[pre-push] gate passed for $range"
