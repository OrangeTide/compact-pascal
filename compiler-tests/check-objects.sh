#!/bin/sh
# Round-trip a unit through an object file and compare the dump against what
# it should hold. The point is that the object format is proved by writing
# and reading it back, not by reading a hex dump.
#
# Made by a machine. PUBLIC DOMAIN (CC0-1.0)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
cpas="${CPAS:-$here/../compiler/cpas}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
for src in "$here"/objects/*.pas; do
    [ -f "$src" ] || continue
    name=$(basename "$src" .pas)
    want="$here/objects/$name.expected"
    if [ ! -f "$want" ]; then
        echo "check-objects: $name has no .expected" >&2
        fail=$((fail + 1))
        continue
    fi
    if ! "$cpas" -c -o "$tmp/$name.cpo" < "$src" 2>"$tmp/$name.err"; then
        echo "FAIL $name (compile)" >&2
        sed 's/^/  /' "$tmp/$name.err" >&2
        fail=$((fail + 1))
        continue
    fi
    if ! "$cpas" -dump-obj "$tmp/$name.cpo" > "$tmp/$name.got" 2>&1; then
        echo "FAIL $name (dump)" >&2
        sed 's/^/  /' "$tmp/$name.got" >&2
        fail=$((fail + 1))
        continue
    fi
    if ! diff -u "$want" "$tmp/$name.got" > "$tmp/$name.diff"; then
        echo "FAIL $name (dump differs)" >&2
        sed 's/^/  /' "$tmp/$name.diff" >&2
        fail=$((fail + 1))
        continue
    fi
    echo "PASS $name"
done

if [ "$fail" -ne 0 ]; then
    echo "check-objects: $fail failed" >&2
    exit 1
fi
echo "check-objects: object round trip holds"
