#!/bin/bash
# Peephole optimizer smoke test.
#
# Builds cpas with and without -dPEEPHOLE, compiles a fixture that
# deterministically produces a `local.set X / local.get X` pair, and
# verifies:
#   * the peephole build rewrites it to `local.tee`
#   * the baseline build still emits the unrewritten pair
#   * the peephole build's WASM output is strictly smaller
#
# Does not run the test suite — that is what run-tests.sh is for, and it
# already accepts CPAS=.../cpas-opt to run the full suite against the
# peephole build.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE="$PROJECT_DIR/compiler/cpas"
OPT="$PROJECT_DIR/compiler/cpas-opt"
TMPDIR="${TMPDIR:-/tmp}/cpas-peephole-$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

command -v wasm-objdump >/dev/null || {
    echo "FATAL: wasm-objdump not found (install wabt)" >&2
    exit 1
}

# Build both compilers.
(cd "$PROJECT_DIR/compiler" && fpc -Mtp cpas.pas >/dev/null) || {
    echo "FATAL: baseline compiler build failed" >&2
    exit 1
}
(cd "$PROJECT_DIR/compiler" && fpc -Mtp -dPEEPHOLE cpas.pas -ocpas-opt >/dev/null) || {
    echo "FATAL: peephole compiler build failed" >&2
    exit 1
}

# Fixture: a case statement — codegen stashes the selector in a local,
# then re-reads it for each arm's compare. That produces the
# `local.set N / local.get N` pair the optimizer targets.
cat > "$TMPDIR/fixture.pas" <<'EOF'
program peephole_fixture;
var x: integer;
begin
  x := 2;
  case x of
    1: writeln('a');
    2: writeln('b');
  else
    writeln('c');
  end;
end.
EOF

"$BASELINE" < "$TMPDIR/fixture.pas" > "$TMPDIR/baseline.wasm"
"$OPT"      < "$TMPDIR/fixture.pas" > "$TMPDIR/opt.wasm"

base_size=$(wc -c < "$TMPDIR/baseline.wasm")
opt_size=$(wc -c < "$TMPDIR/opt.wasm")

wasm-objdump -d "$TMPDIR/baseline.wasm" > "$TMPDIR/baseline.dis"
wasm-objdump -d "$TMPDIR/opt.wasm"      > "$TMPDIR/opt.dis"

fail=0

# 1. Baseline must contain the unrewritten local.set / local.get pair.
if ! grep -q 'local\.set' "$TMPDIR/baseline.dis" \
   || ! grep -q 'local\.get' "$TMPDIR/baseline.dis"; then
    echo "FAIL baseline does not contain expected local.set/local.get pair"
    fail=1
fi

# 2. Peephole build must contain local.tee (evidence the pattern fired).
if ! grep -q 'local\.tee' "$TMPDIR/opt.dis"; then
    echo "FAIL peephole build is missing local.tee"
    fail=1
fi

# 3. Peephole output must be strictly smaller.
if [ "$opt_size" -ge "$base_size" ]; then
    echo "FAIL peephole output ($opt_size B) not smaller than baseline ($base_size B)"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    saved=$((base_size - opt_size))
    echo "PASS peephole rewrote local.set/local.get -> local.tee (saved $saved bytes)"
fi

exit "$fail"
