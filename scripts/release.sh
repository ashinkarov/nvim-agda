#!/bin/sh
# Makes a release.  Usage:
#
#     scripts/release.sh X.Y.Z
#
# On a clean master, turns the "## Unreleased" section of CHANGELOG.md
# into "## X.Y.Z (date)" (with a new empty "## Unreleased" above it),
# sets M.version in lua/agda/init.lua, runs `make test`, commits, and
# creates the annotated tag vX.Y.Z with the changes as its message.
# Nothing is pushed; the script prints the commands for that.

set -eu
cd "$(dirname "$0")/.."

die() { echo "release: $*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: scripts/release.sh X.Y.Z"
v=$1
echo "$v" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' \
    || die "$v is not a version X.Y.Z"

branch=$(git symbolic-ref --short -q HEAD || true)
[ "$branch" = master ] || die "releases are made on master, not on ${branch:-a detached HEAD}"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "there are uncommitted changes"
! git rev-parse -q --verify "refs/tags/v$v" >/dev/null || die "the tag v$v exists"

last=$(sed -n 's/^M\.version = "\(.*\)"$/\1/p' lua/agda/init.lua)
[ -n "$last" ] || die "no M.version in lua/agda/init.lua"
[ "$last" != "$v" ] && [ "$(printf '%s\n%s\n' "$last" "$v" | sort -V | tail -n 1)" = "$v" ] \
    || die "$v is not newer than the current version $last"

grep -q '^## Unreleased$' CHANGELOG.md || die "no \"## Unreleased\" heading in CHANGELOG.md"
# The section, without the blank lines around it.
notes=$(awk '/^## Unreleased$/ { f = 1; next } /^## / { f = 0 } f { l[n++] = $0 }
             END { s = 0; while (s < n && l[s] == "") s++
                   e = n - 1; while (e >= s && l[e] == "") e--
                   for (i = s; i <= e; i++) print l[i] }' CHANGELOG.md)
[ -n "$notes" ] || die "the \"## Unreleased\" section of CHANGELOG.md is empty"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
awk -v h="## $v ($(date +%Y-%m-%d))" \
    '!done && /^## Unreleased$/ { print; print ""; print h; done = 1; next } { print }' \
    CHANGELOG.md > "$tmp"
cat "$tmp" > CHANGELOG.md
sed "s/^M\.version = \".*\"$/M.version = \"$v\"/" lua/agda/init.lua > "$tmp"
cat "$tmp" > lua/agda/init.lua

if ! make test >"$tmp" 2>&1; then
    cat "$tmp"
    git checkout -- CHANGELOG.md lua/agda/init.lua
    die "the tests failed; nothing was changed"
fi

git commit -q -m "Release $v" CHANGELOG.md lua/agda/init.lua
printf 'nvim-agda %s\n\n%s\n' "$v" "$notes" | git tag -a --cleanup=verbatim "v$v" -F -

echo "Committed and tagged v$v.  To publish it:"
echo
echo "    git push origin master v$v"
echo
echo "The changes (also the message of the tag, see \`git tag -n99 v$v\`):"
echo
echo "$notes"
