#!/bin/bash
# Compact Pascal compiler test runner
# Requires: cpas (compiler binary), wasm-validate (wabt), wasmtime
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="$PROJECT_DIR/compiler/cpas"
TMPDIR="${TMPDIR:-/tmp}/cpas-tests-$$"

export WASMTIME_HOME="${WASMTIME_HOME:-$HOME/.wasmtime}"
export PATH="$WASMTIME_HOME/bin:$PATH"

pass=0
fail=0
skip=0

mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

# Build compiler if needed
if [ ! -x "$COMPILER" ]; then
    echo "Building compiler..."
    (cd "$PROJECT_DIR/compiler" && fpc -Mtp cpas.pas) || {
        echo "FATAL: compiler build failed"
        exit 1
    }
fi

# Positive tests
for src in "$SCRIPT_DIR"/positive/*.pas; do
    name="$(basename "$src" .pas)"
    expected="$SCRIPT_DIR/positive/$name.expected"
    exitcode_file="$SCRIPT_DIR/positive/$name.exitcode"
    wasm="$TMPDIR/$name.wasm"
    actual="$TMPDIR/$name.out"

    if [ ! -f "$expected" ]; then
        echo "SKIP $name (no .expected file)"
        skip=$((skip + 1))
        continue
    fi

    # Compile
    if ! "$COMPILER" < "$src" > "$wasm" 2>"$TMPDIR/$name.err"; then
        echo "FAIL $name (compilation failed)"
        cat "$TMPDIR/$name.err"
        fail=$((fail + 1))
        continue
    fi

    # Validate
    if ! wasm-validate "$wasm" 2>"$TMPDIR/$name.err"; then
        echo "FAIL $name (wasm-validate failed)"
        cat "$TMPDIR/$name.err"
        fail=$((fail + 1))
        continue
    fi

    # Determine expected exit code
    expected_exit=0
    if [ -f "$exitcode_file" ]; then
        expected_exit="$(cat "$exitcode_file" | tr -d '[:space:]')"
    fi

    # Run (pipe .input file to stdin if present)
    input_file="$SCRIPT_DIR/positive/$name.input"
    actual_exit=0
    if [ -f "$input_file" ]; then
        wasmtime run "$wasm" < "$input_file" > "$actual" 2>"$TMPDIR/$name.runerr" || actual_exit=$?
    else
        wasmtime run "$wasm" > "$actual" 2>"$TMPDIR/$name.runerr" || actual_exit=$?
    fi

    # Check exit code
    if [ "$actual_exit" != "$expected_exit" ]; then
        echo "FAIL $name (exit code: expected $expected_exit, got $actual_exit)"
        fail=$((fail + 1))
        continue
    fi

    # Check output
    if ! diff -u "$expected" "$actual" > "$TMPDIR/$name.diff" 2>&1; then
        echo "FAIL $name (output mismatch)"
        cat "$TMPDIR/$name.diff"
        fail=$((fail + 1))
        continue
    fi

    echo "PASS $name"
    pass=$((pass + 1))
done

# Negative tests
for src in "$SCRIPT_DIR"/negative/*.pas; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .pas)"
    error_file="$SCRIPT_DIR/negative/$name.error"
    wasm="$TMPDIR/$name.wasm"

    if [ ! -f "$error_file" ]; then
        echo "SKIP $name (no .error file)"
        skip=$((skip + 1))
        continue
    fi

    expected_error="$(cat "$error_file")"

    # Compile - should fail
    if "$COMPILER" < "$src" > "$wasm" 2>"$TMPDIR/$name.err"; then
        echo "FAIL $name (compilation should have failed)"
        fail=$((fail + 1))
        continue
    fi

    # Check error message contains expected substring
    if grep -qi "$expected_error" "$TMPDIR/$name.err"; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name (error message mismatch)"
        echo "  expected: $expected_error"
        echo "  got: $(cat "$TMPDIR/$name.err")"
        fail=$((fail + 1))
    fi
done

echo ""
echo "Results: $pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] || exit 1
