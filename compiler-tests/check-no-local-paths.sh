#!/bin/bash
# Fail if any tracked file records a path from a contributor's own machine.
#
# Absolute home directories and tilde paths identify whoever committed them and
# are meaningless to everyone else. Describe the resource instead: "held
# locally: foo.pdf" rather than "~/Documents/Papers/foo.pdf".
#
# Run standalone or via `make check-paths`. Intended to be wired into CI.
#
# Made by a machine. PUBLIC DOMAIN (CC0-1.0)

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

# /home/<user> and /Users/<user> are absolute home directories.
# ~/<Name> is a tilde path into a home directory. Bare ~/ is not matched, and
# $HOME and ${HOME} are fine because they resolve per-machine.
PATTERN='(/home/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+|~/[A-Za-z][A-Za-z0-9._/-]*)'

# vendor/ is third-party source; home/runner is GitHub Actions, not a person.
hits="$(git grep -n -I -E "$PATTERN" -- . ':!vendor/' \
        | grep -v -E '\$\{?HOME\}?|/home/runner' || true)"

if [ -n "$hits" ]; then
    echo "FAIL: tracked files contain local filesystem paths" >&2
    echo "" >&2
    echo "$hits" >&2
    echo "" >&2
    echo "Describe the resource instead of giving its path on your machine." >&2
    exit 1
fi

echo "check-no-local-paths: clean"
