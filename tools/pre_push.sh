#!/usr/bin/env bash
# pre_push.sh — the gate every push goes through (installed as the pre-push
# hook by `make install-hook`). Checks the commits being pushed, then the tree.
#
#   - author and committer of every new commit is the maintainer identity
#   - no session links or blocked words in commit messages
#
# "New" means not yet on the remote: commits already reachable from an
# origin/* ref are public and left alone, so merging origin/main into a
# feature branch does not trip over GitHub's own merge commits. Every commit
# the push would publish is still checked.
#   - make gate (byte-exact, full coverage, readability), symbols/ valid, and
#     no generated file tracked
set -euo pipefail
IDENT='Akill <24420588+ThisIsAkill@users.noreply.github.com>'
fail() { printf '\033[0;31m[pre-push] %s\033[0m\n' "$*" >&2; exit 1; }

range="${1:-origin/main..HEAD}"
new=(git log "$range" --not --remotes=origin)
while read -r line; do
    [ "$line" = "$IDENT" ] || fail "commit by '$line' in $range (expected $IDENT)"
done < <("${new[@]}" --format='%an <%ae>%n%cn <%ce>' | sort -u)

msgs=$("${new[@]}" --format='%B')
if printf '%s' "$msgs" | grep -qiE 'c[l]aude\.[a]i/code|C[l]aude-Session:'; then
    fail "a commit message in $range carries a session link"
fi

make --no-print-directory -s gate >/dev/null || fail "make gate failed"
python3 tools/validate_functions.py >/dev/null || fail "symbols/ is invalid (tools/validate_functions.py)"
python3 tools/progress.py --check >/dev/null || fail "generated files tracked or doc blocks back (tools/progress.py --check)"
echo "[pre-push] gate passed for $range"
