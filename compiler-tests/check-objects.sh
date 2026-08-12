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
for src in "$here"/objects/o*.pas; do
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


# Padded immediates are what makes a relocation patchable, and an object is
# never executed, so the encoders would otherwise go unchecked until the
# linker existed. -pad turns the same encoders on for a program, which can be
# validated and run. The padded module must be larger and behave identically.
pad_src="$here/objects/pad-program.pas"
if [ -f "$pad_src" ]; then
    "$cpas" < "$pad_src" > "$tmp/plain.wasm"
    "$cpas" -pad < "$pad_src" > "$tmp/padded.wasm"
    plain_size=$(wc -c < "$tmp/plain.wasm")
    padded_size=$(wc -c < "$tmp/padded.wasm")
    if [ "$padded_size" -le "$plain_size" ]; then
        echo "FAIL pad-program (padding did not grow the module)" >&2
        fail=$((fail + 1))
    elif ! wasm-validate "$tmp/padded.wasm" 2>"$tmp/pad.err"; then
        echo "FAIL pad-program (padded module does not validate)" >&2
        sed 's/^/  /' "$tmp/pad.err" >&2
        fail=$((fail + 1))
    else
        ( cd "$tmp" && wasmtime run plain.wasm > plain.out 2>&1 ) || true
        ( cd "$tmp" && wasmtime run padded.wasm > padded.out 2>&1 ) || true
        if ! diff -u "$tmp/plain.out" "$tmp/padded.out" > "$tmp/pad.diff"; then
            echo "FAIL pad-program (padded output differs)" >&2
            sed 's/^/  /' "$tmp/pad.diff" >&2
            fail=$((fail + 1))
        else
            echo "PASS pad-program"
        fi
    fi
fi


# A program compiled against a unit's object. Only what needs no linking yet:
# imported types and scalar constants. A call into a unit needs the linker.
for src in "$here"/link/*.pas; do
    case "$src" in *.unit.pas) continue;; esac
    [ -f "$src" ] || continue
    name=$(basename "$src" .pas)
    unit="$here/link/$name.unit.pas"
    want="$here/link/$name.expected"
    if ! "$cpas" -c -o "$tmp/$name.cpo" < "$unit" 2>"$tmp/$name.uerr"; then
        echo "FAIL $name (unit)" >&2; sed 's/^/  /' "$tmp/$name.uerr" >&2
        fail=$((fail + 1)); continue
    fi
    if ! "$cpas" "$tmp/$name.cpo" < "$src" > "$tmp/$name.wasm" 2>"$tmp/$name.perr"; then
        echo "FAIL $name (program)" >&2; sed 's/^/  /' "$tmp/$name.perr" >&2
        fail=$((fail + 1)); continue
    fi
    if ! wasm-validate "$tmp/$name.wasm" 2>"$tmp/$name.verr"; then
        echo "FAIL $name (invalid module)" >&2; sed 's/^/  /' "$tmp/$name.verr" >&2
        fail=$((fail + 1)); continue
    fi
    ( cd "$tmp" && wasmtime run "$name.wasm" > "$name.out" 2>&1 ) || true
    if ! diff -u "$want" "$tmp/$name.out" > "$tmp/$name.diff"; then
        echo "FAIL $name (output differs)" >&2; sed 's/^/  /' "$tmp/$name.diff" >&2
        fail=$((fail + 1)); continue
    fi
    echo "PASS $name"
done

if [ "$fail" -ne 0 ]; then
    echo "check-objects: $fail failed" >&2
    exit 1
fi
echo "check-objects: object round trip holds"
