# WASM Tools for Compiler Writers

This document covers the tools useful for developing, debugging, and testing a
compiler that targets WebAssembly. All examples use Compact Pascal's compiler
(`cpas`), but the techniques apply to any WASM-targeting compiler.

## Runtimes

### wasmtime

Bytecode Alliance reference runtime. Supports WASI preview 1 (fd_write,
fd_read, proc_exit, args_get, args_sizes_get) out of the box.

```bash
# Compile a Pascal program and run it
cpas < hello.pas > hello.wasm
wasmtime run hello.wasm

# Pass command-line arguments (separated from runtime flags by --)
wasmtime run hello.wasm -- -dump

# Pipe input to stdin
echo "42" | wasmtime run hello.wasm

# AOT compile for faster repeated runs
wasmtime compile hello.wasm -o hello.cwasm
wasmtime run hello.cwasm
```

Useful flags for `wasmtime run`:

| Flag | Purpose |
|------|---------|
| `--` | Separates wasmtime flags from guest arguments |
| `-D debug-info` | Enable debug info for stack traces |
| `--profile=perfmap` | Generate perf map for profiling |

Trap behavior: wasmtime terminates with exit code 134 (128 + SIGABRT) on a WASM
trap (unreachable, out-of-bounds memory access, integer overflow when trapping).

Install: <https://wasmtime.dev>

### wasmer

Alternative WASI-compatible runtime with a package registry.

```bash
# Same basic usage as wasmtime
wasmer run hello.wasm
echo "42" | wasmer run hello.wasm

# Pass guest arguments
wasmer run hello.wasm -- -dump

# Validate a module without running
wasmer validate hello.wasm

# Inspect module metadata (imports, exports, memory)
wasmer inspect hello.wasm

# AOT compile
wasmer compile hello.wasm -o hello.wasmu
wasmer run hello.wasmu
```

Trap behavior: wasmer terminates with exit code 45 on a WASM trap. This differs
from wasmtime's 134. The test runner (`run-tests.sh`) handles this automatically.

Install: <https://wasmer.io>

### Browser WebAssembly API

WASM modules can run client-side in the browser using the native WebAssembly
API. WASI imports must be shimmed in JavaScript. See `pages/playground/` for a
working example.

```javascript
const response = await fetch('hello.wasm');
const bytes = await response.arrayBuffer();
const { instance } = await WebAssembly.instantiate(bytes, {
  wasi_snapshot_preview1: {
    fd_write(fd, iovs, iovs_len, nwritten) { /* ... */ },
    fd_read(fd, iovs, iovs_len, nread) { /* ... */ },
    proc_exit(code) { throw new WasiExit(code); },
  }
});
instance.exports._start();
```

## Analysis Tools (wabt)

The WebAssembly Binary Toolkit (wabt) provides command-line tools for
inspecting, validating, and transforming WASM binaries. Available as the `wabt`
package on most Linux distributions.

### wasm-validate

Validates binary structure and type safety without running. Catches malformed
sections, type mismatches, stack underflows, and invalid opcodes. Run this
after every compilation — it is fast and catches bugs that would otherwise
produce confusing runtime errors.

```bash
wasm-validate hello.wasm
# exit 0 = valid, exit 1 = invalid (errors to stderr)

# Verbose mode for detailed error context
wasm-validate -v hello.wasm
```

### wasm-objdump

Structural inspection. The single most useful debugging tool when your compiler
emits wrong binary output.

```bash
# Section headers — quick overview of what's in the module
wasm-objdump -h hello.wasm

# Full section details — types, imports, exports, globals, memory, data
wasm-objdump -x hello.wasm

# Disassembly — function bodies with WASM opcodes
wasm-objdump -d hello.wasm

# Single section only
wasm-objdump -x -j Type hello.wasm

# Raw hex dump of a section
wasm-objdump -s -j Data hello.wasm
```

Example output of `-x` for a simple program:

```
Section Details:

Type[9]:
 - type[0] (i32, i32, i32, i32) -> (i32)  ; fd_write signature
 - type[1] () -> ()                         ; _start, void procedures
 ...
Import[3]:
 - func[0] sig=0 <wasi_snapshot_preview1.fd_write>
 - func[1] sig=3 <wasi_snapshot_preview1.fd_read>
 - func[2] sig=4 <wasi_snapshot_preview1.proc_exit>
Memory[1]:
 - memory[0] pages: initial=1 max=256
Global[9]:
 - global[0] i32 mutable=1 - init i32=65536  ; $sp
 - global[1..8] i32 mutable=1                ; display[0..7]
Export[2]:
 - func[3] <_start>
 - memory[0] <memory>
```

This tells you everything about the module's interface without running it.

### wasm2wat

Converts binary WASM to WebAssembly Text Format (WAT). Readable S-expression
syntax. Best for reviewing the full generated code.

```bash
# Print to stdout
wasm2wat hello.wasm

# Write to file
wasm2wat hello.wasm -o hello.wat

# Fold expressions for more compact output
wasm2wat -f hello.wasm
```

The output is valid WAT that can be converted back with `wat2wasm`:

```bash
wat2wasm hello.wat -o hello2.wasm
```

This round-trip is useful for testing: if `wat2wasm(wasm2wat(x)) == x`, your
binary encoding is canonical.

### wasm-decompile

Converts binary WASM to C-like pseudocode. More readable than WAT for
understanding control flow and data access patterns.

```bash
wasm-decompile hello.wasm
```

Example output:

```
export function _start() {
  g_a = 65536;       // SP init
  d_b[0]:int = 56;   // iovec buffer ptr
  d_b[4]:int = 2;    // iovec length
  fd_write(1, 20, 1, 24);
}
```

Good for a first-pass sanity check. Does not preserve exact WASM semantics
(it is a decompilation, not a disassembly).

### wasm-stats

Opcode frequency analysis. Shows which instructions dominate the output.

```bash
wasm-stats hello.wasm
```

Useful for identifying optimization opportunities. If `i32.const` and
`local.get` dominate (they usually will for a stack-machine compiler), that is
normal. A high `unreachable` count may indicate dead code or stub functions.

### wasm-strip

Removes non-essential sections (name section, custom sections) to reduce
binary size.

```bash
# Strip everything
wasm-strip hello.wasm -o hello-stripped.wasm

# Keep the name section (for stack traces)
wasm-strip hello.wasm -o hello-stripped.wasm -k name

# Remove a specific custom section
wasm-strip hello.wasm -R name
```

The name section adds a few hundred bytes to the binary but makes stack traces
human-readable. Keep it during development; strip it for production.

## Debugging Workflow

When the compiler produces wrong output, use this sequence:

1. **`wasm-validate`** — Is the binary well-formed? If not, the error points
   to the broken section.

2. **`wasm-objdump -x`** — Check the module structure. Are imports, exports,
   types, memory, and globals what you expect? Wrong type signatures are a
   common source of validation errors and runtime traps.

3. **`wasm-decompile`** — Quick scan of the generated code. Look for obviously
   wrong control flow, missing function calls, or bad memory offsets.

4. **`wasm2wat`** — If the decompiled output looks suspicious, read the exact
   WAT instructions. Compare against the WAT pseudo-code comments in the
   compiler source.

5. **`wasm-objdump -d`** — Last resort: raw bytecode with hex offsets. Useful
   when the binary encoding itself is wrong (bad LEB128, wrong section sizes).

6. **`wasmtime run`** / **`wasmer run`** — Run and compare output. If one
   runtime traps and the other doesn't, the module may be relying on
   undefined behavior.

## Testing Across Runtimes

The test runner supports both wasmtime and wasmer:

```bash
# Auto-detect (prefers wasmtime)
./run-tests.sh

# Explicitly choose
./run-tests.sh wasmtime
./run-tests.sh wasmer
```

The `.exitcode` files in the test suite use wasmtime's trap exit code (134).
The test runner translates this to the correct exit code for the selected
runtime automatically.

Programs that do not trap should produce identical output on all runtimes. If
they don't, you have a bug — either in the compiler (relying on undefined
WASM behavior) or in your WASI host import implementations.

## Quick Reference

| Task | Command |
|------|---------|
| Validate binary | `wasm-validate hello.wasm` |
| Section overview | `wasm-objdump -h hello.wasm` |
| Full structure | `wasm-objdump -x hello.wasm` |
| Disassembly | `wasm-objdump -d hello.wasm` |
| WAT output | `wasm2wat hello.wasm` |
| WAT to binary | `wat2wasm hello.wat -o hello.wasm` |
| Pseudocode | `wasm-decompile hello.wasm` |
| Opcode stats | `wasm-stats hello.wasm` |
| Strip sections | `wasm-strip hello.wasm -o stripped.wasm` |
| Run (wasmtime) | `wasmtime run hello.wasm` |
| Run (wasmer) | `wasmer run hello.wasm` |
| Run with args | `wasmtime run hello.wasm -- arg1 arg2` |
| Pipe stdin | `echo input \| wasmtime run hello.wasm` |
