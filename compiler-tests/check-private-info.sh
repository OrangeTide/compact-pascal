#!/bin/bash
# Fail if any tracked file leaks a contributor's private information.
#
# Two layers:
#
#   1. Generic patterns, below. Absolute home directories and tilde paths
#      identify whoever committed them and mean nothing to anyone else. Name
#      the resource instead of saying where it sits on your disk.
#
#   2. Per-clone patterns, read from .git/info/private-patterns when that file
#      exists. One extended-regex per line, blank lines and # comments ignored.
#      Use it for personal domains, hostnames, user handles, and email
#      addresses.
#
# The second layer is deliberately NOT tracked. Writing "my-domain.example"
# into a committed file in order to block it would publish the very string it
# is meant to keep out of the repo. Keeping the list in .git/info/ gives each
# clone its own, the same way .git/info/exclude holds private ignore rules.
#
# Personal identifiers cannot be caught generically. Academic references
# legitimately use tilde-user URLs (university.example/~researcher/), and a
# project's own forge URL contains its owner's handle. Both are fine; only an
# explicit per-clone list can tell them apart from a leak.
#
# This script scans file content only. Commit author names and emails are
# inherent to git and are not checked.
#
# Run standalone or via `make check-private`. Intended to be wired into CI,
# where layer 2 is normally absent and only the generic patterns apply.
#
# Made by a machine. PUBLIC DOMAIN (CC0-1.0)

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

SELF='compiler-tests/check-private-info.sh'
LOCAL_PATTERNS="$(git rev-parse --git-dir)/info/private-patterns"

# /home/<user> and /Users/<user> are absolute home directories.
# ~/<Name> is a tilde path into a home directory. Bare ~/ is not matched, and
# $HOME and ${HOME} are fine because they resolve per-machine.
GENERIC='(/home/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+|~/[A-Za-z][A-Za-z0-9._/-]*)'

# vendor/ is third-party source; home/runner is GitHub Actions, not a person.
# This script is skipped so its own documentation cannot trip it.
scan() {
    git grep -n -I -E "$1" -- . ':!vendor/' ":!$SELF" \
        | grep -v -E '\$\{?HOME\}?|/home/runner'
}

status=0

hits="$(scan "$GENERIC" || true)"
if [ -n "$hits" ]; then
    echo "FAIL: tracked files contain local filesystem paths" >&2
    echo "$hits" >&2
    echo "" >&2
    echo "Name the resource instead of giving its path on your machine." >&2
    status=1
fi

if [ -f "$LOCAL_PATTERNS" ]; then
    while IFS= read -r pattern; do
        case "$pattern" in
            ''|\#*) continue ;;
        esac
        found="$(scan "$pattern" || true)"
        if [ -n "$found" ]; then
            echo "FAIL: tracked files match a private pattern" >&2
            echo "$found" >&2
            status=1
        fi
    done < "$LOCAL_PATTERNS"
else
    echo "note: no $LOCAL_PATTERNS, generic patterns only"
fi

if [ "$status" -eq 0 ]; then
    echo "check-private-info: clean"
fi
exit "$status"
