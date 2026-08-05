#!/bin/bash
# Compile every self-contained Pascal example in the documentation.
#
# Nothing else checks these. Three defects in this project were found by
# running a documentation example by hand — a spurious blank line from Eof,
# an example using a form the compiler rejects, and a mechanism described
# backwards — so running them on purpose is worth the seconds it costs.
#
# Compiled without -I: a reference example that mentions {$I} is illustrating
# the directive, not shipping the file it names, and without the flag the
# directive is skipped exactly as it would be for a reader compiling the
# snippet as written.
#
# Only fenced ```pascal blocks that look like whole programs are compiled: a
# block must contain a `program` header and end with `end.`. Fragments are
# counted and reported rather than silently ignored, because a growing skip
# count is the signal that this check is drifting into uselessness.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="${CPAS:-$PROJECT_DIR/compiler/cpas}"
TMPDIR="${TMPDIR:-/tmp}/cpas-docex-$$"

export WASMTIME_HOME="${WASMTIME_HOME:-$HOME/.wasmtime}"
export PATH="$WASMTIME_HOME/bin:$PATH"

mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

docs=(
    "$PROJECT_DIR/doc/compact-pascal-ref.md"
    "$PROJECT_DIR/doc/compact-pascal-wp.md"
    "$PROJECT_DIR/README.md"
)

checked=0
skipped=0
failed=0
notrun=0

for doc in "${docs[@]}"; do
    [ -f "$doc" ] || continue
    name="$(basename "$doc")"

    # Split the file into ```pascal blocks, one file each.
    awk -v out="$TMPDIR" -v tag="${name%.md}" '
        /^```pascal$/ { inblock = 1; n++; file = sprintf("%s/%s-%03d.pas", out, tag, n); next }
        /^```$/       { if (inblock) { close(file); inblock = 0 } ; next }
        inblock       { print > file }
    ' "$doc"
done

for src in "$TMPDIR"/*.pas; do
    [ -f "$src" ] || continue
    # A whole program has a header and a terminating end.
    if ! grep -qi '^ *program ' "$src" || ! grep -q 'end\. *$' "$src"; then
        skipped=$((skipped + 1))
        continue
    fi
    checked=$((checked + 1))
    if ! "$COMPILER" < "$src" > "$src.wasm" 2>"$src.err"; then
        echo "FAIL $(basename "$src") (compilation failed)"
        sed 's/^/    /' "$src.err"
        echo "    --- source ---"
        sed 's/^/    /' "$src"
        failed=$((failed + 1))
        continue
    fi
    if ! wasm-validate "$src.wasm" 2>"$src.verr"; then
        echo "FAIL $(basename "$src") (wasm-validate failed)"
        sed 's/^/    /' "$src.verr"
        failed=$((failed + 1))
        continue
    fi
    # An example that declares host imports cannot run without the host that
    # satisfies them, so it is compiled and validated but not executed.
    if grep -q '{\$IMPORT' "$src"; then
        notrun=$((notrun + 1))
        continue
    fi
    # Run the rest. An example that compiles but traps is still wrong, and
    # the directory is granted so file examples work.
    if ! ( cd "$TMPDIR" && wasmtime run --dir=. "$src.wasm" >/dev/null 2>"$src.rerr" ); then
        echo "FAIL $(basename "$src") (run failed)"
        sed 's/^/    /' "$src.rerr"
        failed=$((failed + 1))
        continue
    fi
done

echo "doc examples: $checked compiled, $((checked - notrun - failed)) ran, $notrun need a host, $skipped fragments skipped, $failed failed"
[ "$failed" -eq 0 ]
