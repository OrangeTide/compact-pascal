#!/bin/bash
# Build the release artifact and check that it works.
#
# The artifact is deliberately the smallest useful thing: the compiler as a
# WASM module and a README explaining how to run it. No installer, no platform
# matrix, no wrapper scripts. A user with a WASM runtime needs nothing else,
# and a user without one is not helped by a zip.
#
# Built and verified here rather than only in a tag-triggered workflow, so a
# broken artifact is found before it is published rather than after.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$PROJECT_DIR/build/release}"

export WASMTIME_HOME="${WASMTIME_HOME:-$HOME/.wasmtime}"
export PATH="$WASMTIME_HOME/bin:$PATH"

version="$(grep -m1 '^\*\*Version ' "$PROJECT_DIR/doc/compact-pascal-ref.md" \
           | sed 's/^\*\*Version \([0-9.]*\).*/\1/')"
if [ -z "$version" ]; then
    echo "::error::cannot read the version from the language reference" >&2
    exit 1
fi

stage="$OUT_DIR/compact-pascal-$version"
rm -rf "$OUT_DIR"
mkdir -p "$stage"

cp "$PROJECT_DIR/snapshot/compiler.wasm" "$stage/compiler.wasm"
cp "$PROJECT_DIR/LICENSE" "$stage/LICENSE"

cat > "$stage/README.md" <<EOF
# Compact Pascal $version

The compiler, as a WebAssembly module. It reads Pascal source on standard
input and writes a WebAssembly module on standard output; diagnostics go to
standard error.

## Running it

You need a WebAssembly runtime that supports WASI preview 1.
[wasmtime](https://wasmtime.dev) is the one this is tested against.

\`\`\`
wasmtime run compiler.wasm < hello.pas > hello.wasm
wasmtime run hello.wasm
\`\`\`

## Options

| Flag | Meaning |
|---|---|
| \`-R+\` / \`-R-\` | Range checks on array indexing and subrange assignment. Off by default. |
| \`-S+\` / \`-S-\` | Stack overflow guard, frame balance check, nil check. **On** by default. |
| \`-I\` | Resolve \`{\$I 'file'}\` includes. Needs a granted directory: \`wasmtime run --dir=. compiler.wasm -- -I < main.pas\`. |
| \`-dNAME\` | Define a conditional compilation symbol. |
| \`-v\` | Report what the compiler decided, as \`Info:\` lines. |

A compiled program that opens files needs a directory too:

\`\`\`
wasmtime run --dir=. hello.wasm
\`\`\`

## What this is not

There is no installer and no native binary. The compiler is a WASM module
because that is what makes it embeddable; running it standalone is the same
module a host would embed.

The language reference, white paper, and tutorial are not in this archive.
They are at https://github.com/OrangeTide/compact-pascal.

## License

Public domain, CC0 1.0 Universal. See LICENSE.
EOF

# Verify before packaging: an artifact that does not work is worse than none.
if ! wasm-validate "$stage/compiler.wasm"; then
    echo "::error::the staged compiler.wasm does not validate" >&2
    exit 1
fi

probe="$OUT_DIR/probe.pas"
printf "program Probe;\nbegin\n  writeln('release artifact works');\nend.\n" > "$probe"
( cd "$stage" && wasmtime run compiler.wasm < "$probe" > "$OUT_DIR/probe.wasm" )
out="$(wasmtime run "$OUT_DIR/probe.wasm")"
if [ "$out" != "release artifact works" ]; then
    echo "::error::the staged compiler produced a module that does not run" >&2
    exit 1
fi

# The artifact must be the same compiler the repository has.
if ! cmp -s "$stage/compiler.wasm" "$PROJECT_DIR/snapshot/compiler.wasm"; then
    echo "::error::the staged compiler differs from the committed snapshot" >&2
    exit 1
fi

( cd "$OUT_DIR" && zip -q -r "compact-pascal-$version.zip" "compact-pascal-$version" )

echo "release: build/release/compact-pascal-$version.zip"
echo "  $(cd "$OUT_DIR" && unzip -l "compact-pascal-$version.zip" | tail -1 | tr -s ' ')"
echo "  compiler.wasm validated, compiled a program, and that program ran"
