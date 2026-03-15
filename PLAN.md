# Compact Pascal — Project Plan

Compact Pascal is a new language in the Pascal family with a compiler that targets WASM 1.0. The compiler is written in Pascal, ships as a WASM binary, and is embedded in Rust and Zig libraries.

See `doc/compact-pascal-wp.md` for the full white paper and `doc/compact-pascal-ref.md` for the language reference.

## Goals

1. **Design a new Pascal-family language** — minimal, strongly typed, suitable for embedding. I/O via compiler intrinsics that lower to WASM host imports. Not a conforming implementation of any existing standard.
2. **Write the compiler in Pascal** — single-pass recursive-descent parser targeting WASM 1.0 binary output. Bootstrapped with fpc, then self-hosting.
3. **Ship the compiler as a WASM blob** — the compiler runs inside a WASM interpreter, so any host that can run WASM can compile Compact Pascal programs.
4. **Provide Rust and Zig embedding libraries** — high-level APIs to compile Pascal source, instantiate WASM modules, and bridge host-guest function calls. No external Pascal toolchain required.
5. **Run everywhere WASM runs** — native applications (via wasmi/wasm3), browsers (via native WebAssembly API), edge runtimes.
6. **Extend the language thoughtfully** — add macros for I/O, structural interfaces with methods, and potentially garbage collection, while preserving single-pass compilation and the language's minimalist character.

## Bootstrapping

Bootstrap using **fpc** in TP/BP 7.0 mode (`-Mtp`). Once the compiler can compile itself, ship a snapshot WASM blob (< 1 MB, committed to git). After that, only Rust or Zig is needed to build.

## Project Layout

```
compiler/       — Pascal source for the compiler (built with fpc)
compiler-tests/ — test suite modeled on BSI Pascal Validation Suite
src/            — Rust crate source
src-zig/        — Zig library source
snapshot/       — the compiler WASM blob (shared by Rust and Zig)
examples/
  rust/         — Rust example programs
  zig/          — Zig example programs
doc/            — white paper and language reference
Cargo.toml      — Rust build
build.zig       — Zig build
build.zig.zon   — Zig package manifest
```

## Phases

### Phase 1: Compact Pascal Compiler (Pascal, bootstrapped with fpc) — `NOT STARTED`

Write the compiler in Pascal (fpc `-Mtp` mode), targeting WASM output. Minimal core language — just enough to write a compiler. No dynamic allocation (`New`/`Dispose`) in this phase; stack-only allocation.

**Compiler infrastructure:**
- [ ] Lexer (tokenizer)
- [ ] Single-pass recursive-descent parser with deferred WASM binary output (section buffers)
- [ ] WASM linear memory layout: nil guard, data segment, stack (grows down), stack pointer in WASM global
- [ ] Compiler I/O via WASI preview 1 `fd_read`/`fd_write`/`proc_exit` (stdin=source, stdout=WASM, stderr=errors)
- [ ] Halt on first error with diagnostic to stderr via `proc_exit(1)`
- [ ] `-dump` flag for human-readable WASM instruction listing
- [ ] Compiler directive system: `{$DIRECTIVE}` / `{$DIRECTIVE VALUE}` (Free Pascal syntax)
- [ ] Compiles and runs under fpc `-Mtp`

**Core language features:**
- [ ] Integer and boolean types (`integer`, `boolean`, `char`)
- [ ] TP-compatible numeric types: `byte`, `word`, `shortint`, `longint`
- [ ] Arrays, records (including variant records), pointers (address-of only, no heap allocation)
- [ ] Set types (`set of T`, bitmap up to 256 bits) with union, intersection, difference, `in`
- [ ] Arithmetic and logical expressions
- [ ] Short-circuit operators: `and then`, `or else` (ISO 10206)
- [ ] Control flow: `if`/`else`, `while`, `for`, `case`, `repeat`/`until`, `with`/`do`
- [ ] Procedures and functions with value/var/const parameters (strings passed by reference for const/var)
- [ ] Nested procedures with upvalue access (display technique, max depth 8, WASM globals)
- [ ] `forward` declarations
- [ ] TP-style short strings (`string`, `string[n]`, length byte + data)
- [ ] Standard functions: `abs`, `ord`, `chr`, `odd`, `succ`, `pred`, `sqr`, `length`, `sizeof`, `lo`, `hi`
- [ ] Standard procedures: `inc`, `dec`, `exit`, `halt`
- [ ] String procedures/functions: `copy`, `pos`, `concat`, `delete`, `insert`
- [ ] `write`/`writeln` and `read`/`readln` as compiler intrinsics (lower to WASI `fd_write`/`fd_read`)
- [ ] `halt`/`halt(n)` lowers to WASI `proc_exit`
- [ ] Typed constants (`const x: integer = 5`)
- [ ] Type casts (`integer(ch)`)
- [ ] Hex literals (`$FF`), extended literals (`0x`, `0o`, `0b`) via `{$EXTLITERALS ON}`
- [ ] Program entry point compiled as WASI `_start` export
- [ ] Compiler directives: `{$R+/-}`, `{$Q+/-}`, `{$ALIGN}`, `{$MEMORY}`, `{$MAXMEMORY}`, `{$STACKSIZE}`, `{$DESCRIPTION}`, `{$EXTLITERALS}`
- [ ] `{$EXPORT}` and `{$IMPORT}` directives for WASM FFI

**Validation:**
- [ ] Can compile a non-trivial test program to valid WASM
- [ ] Compiler test suite (modeled on BSI Pascal Validation Suite): positive and negative tests
- [ ] Positive tests: compile, `wasm-validate`, run with `wasmtime`, compare stdout to `.expected`
- [ ] Negative tests: compile, verify failure and error message matches `.error`
- [ ] Shell script test runner (`compiler-tests/run-tests.sh`)

Extensions (modules, overloads, dynamic arrays, `New`/`Dispose`, exceptions, OOP) deferred to later phases.

### Phase 2: Embedding Libraries (Rust + Zig) — `NOT STARTED`

#### Rust (`compact-pascal` crate, using wasmi)

- [ ] Cargo project setup with wasmi dependency
- [ ] Embed the snapshot WASM blob of the compiler
- [ ] Run the compiler in wasmi to compile Pascal source to WASM bytes
- [ ] Provide WASI preview 1 host imports for the compiler (`fd_read`, `fd_write`, `proc_exit`)
- [ ] Instantiate and run compiled WASM modules via wasmi
- [ ] Host-guest FFI (imports and exports)
- [ ] String conversion helpers
- [ ] `{$INCLUDE}` / `{$I}` preprocessing (expand include directives before passing source to compiler)
- [ ] Example programs in `examples/rust/`

#### Zig (`compact-pascal` module, using wasm3 via C interop)

- [ ] `build.zig` / `build.zig.zon` project setup
- [ ] wasm3 C dependency integration via Zig build system
- [ ] Embed the snapshot WASM blob of the compiler
- [ ] Run the compiler in wasm3 to compile Pascal source to WASM bytes
- [ ] Provide WASI preview 1 host imports for the compiler (`fd_read`, `fd_write`, `proc_exit`)
- [ ] Instantiate and run compiled WASM modules via wasm3
- [ ] Host-guest FFI (imports and exports)
- [ ] String conversion helpers
- [ ] `{$INCLUDE}` / `{$I}` preprocessing (expand include directives before passing source to compiler)
- [ ] Example programs in `examples/zig/`

Both libraries share the same snapshot blob and compiler test suite. APIs should be idiomatic to each language.

### Phase 3: Self-Hosting — `NOT STARTED`

- [ ] Use the fpc-bootstrapped compiler to compile itself to WASM, producing the first snapshot binary
- [ ] Verify fixpoint: run the snapshot in wasmi, compile the compiler source again, diff the output
- [ ] Commit the snapshot blob to git (must be < 1 MB)
- [ ] Verify the Rust crate works end-to-end using only the snapshot (no fpc required)
- [ ] Verify the Zig library works end-to-end using only the snapshot (no fpc required)

### Phase 4: Browser / WASM Target — `NOT STARTED`

- [ ] Use wasm-bindgen to call the browser's `WebAssembly.instantiate` for compiled programs
- [ ] Verify the compiler snapshot runs in wasmi-in-WASM (interpreter-in-WASM)
- [ ] Example browser project

### Phase 5: Dynamic Allocation — `NOT STARTED`

- [ ] `New`/`Dispose` with free-list allocator in WASM linear memory
- [ ] Object headers with metadata (size, mark bits, link pointers) for future GC
- [ ] Future: Baker's Treadmill GC (non-moving, incremental, shadow stack for root tracking)

### Phase 5b: Richer String Type — `NOT STARTED`

- [ ] Pointer + length string type with no 255-character limit (requires dynamic allocation)
- [ ] `pascal` calling convention keyword for FFI compatibility between string representations
- [ ] Conversion between short strings and dynamic strings

### Phase 6: Macro System — `NOT STARTED`

- [ ] Design macro syntax (Rust-like macros as a language extension)
- [ ] Implement macro expansion in the compiler
- [ ] Explore support for other Pascal variants such as Component Pascal

### Phase 7: Interfaces and Methods — `NOT STARTED`

- [ ] Standalone methods with `for` receiver syntax
- [ ] Value receivers (call-by-value)
- [ ] Pointer receivers (reference semantics)
- [ ] Dot-notation method calls
- [ ] `interface` type declarations
- [ ] `implement` blocks for interface conformance
- [ ] `Self` keyword inside `implement` blocks
- [ ] Interface satisfaction checking at block close
- [ ] Implicit conversion from concrete type to interface type
- [ ] Type assertions (future)
- [ ] Type switches (future)

## Findings

### Language naming

Renamed from "Pascaline-Plus" to "Compact Pascal" — not a compatible superset of Standard Pascaline. "Fermat" (after Pascal's collaborator) was the runner-up.

### WAT vs direct WASM binary emission

Rejected WAT in favor of direct binary emission. WASM binary is simpler to emit. Section-ordering solved by buffering each section in memory during the single pass.

### WASI preview 1 I/O interface

Adopted standard WASI preview 1 signatures for I/O: `fd_read`, `fd_write` (iovec-based), and `proc_exit`, imported from `wasi_snapshot_preview1`. Originally considered a simplified non-WASI interface (`fd_write(fd, buf, len)`), but switched to real WASI because: (1) the iovec overhead is trivial — the compiler always passes a single iovec (`iovs_len = 1`), which is just two `i32.store` instructions; (2) standard WASI means the compiler and compiled programs run directly under `wasmtime`/`wasmer` with no custom host; (3) the test suite needs no custom harness — `wasmtime run test.wasm` works out of the box. Compiled programs that use `write`/`writeln`/`read`/`readln` are also WASI-compatible. Programs with no I/O have no WASI imports.

### Dynamic allocation: deferred to Phase 5

`New`/`Dispose` and heap allocation deferred from Phase 1 to keep the core compiler minimal. Phase 1 uses stack-only allocation. Baker's Treadmill GC is a good fit for WASM (non-moving, incremental) but requires a shadow stack for root tracking — deferred further until after `New`/`Dispose` is working.

### Error strategy: halt on first error

Most lightweight for single-pass. No recovery logic, no cascading false positives.

### Zig WASM runtime: wasm3 via C interop

wasm3 (C library) chosen for Zig side. Zig-native interpreters are immature. Zig's `@cImport` makes C interop trivial. Parallels Rust's wasmi choice. **Risk:** wasm3 development has slowed significantly. If the project becomes unmaintained, alternatives include writing a minimal WASM interpreter in Zig or switching to another C-based runtime.

### Short-circuit evaluation: `and then` / `or else`

Adopted ISO 10206 short-circuit operators rather than always-short-circuit (C-style) or a compiler directive (`{$B+/-}`). Explicit at the call site, no ambiguity. Standard `and`/`or` retain full-evaluation ISO 7185 semantics.

### Compiler directives: Free Pascal syntax

Adopted `{$DIRECTIVE}` / `{$DIRECTIVE VALUE}` syntax matching Free Pascal. Global directives (before any code): `{$MEMORY}`, `{$MAXMEMORY}`, `{$STACKSIZE}`, `{$DESCRIPTION}`. Local directives (anywhere): `{$R+/-}`, `{$Q+/-}`, `{$ALIGN}`, `{$I}`, `{$EXPORT}`, `{$IMPORT}`. The `{$EXPORT}` and `{$IMPORT}` directives are how programs declare the WASM FFI boundary.

### WASM linear memory layout

Industry-standard layout, matching LLVM/Rust/C WASM compilers:

```
[ nil guard | data segment (globals, string literals) | heap → ... ← stack ]
0           4                                          data_end    SP   memory_top
```

- **Nil guard:** First 4 bytes reserved (zeroed). Dereferencing `nil` (address 0) reads zeros rather than corrupting data.
- **Data segment** at low addresses — global variables, string literals, typed constants. Laid out by the compiler during compilation.
- **Heap** grows upward from end of data segment (Phase 5; unused in Phase 1).
- **Stack** grows downward from top of memory. In Phase 1, the entire space between data end and memory top is stack.
- **Stack pointer** is a mutable WASM global (`$sp`), initialized to the top of memory. Frame allocation: `$sp -= frame_size`. Frame deallocation: `$sp += frame_size`.

This layout is battle-tested across WASM toolchains, compatible with debugging/profiling tools, and sets up cleanly for Phase 5 heap allocation (heap and stack grow toward each other).

Stack-grows-up was considered and rejected: non-standard, overflow behavior is worse (runs off end of memory rather than hitting a known boundary), and tools don't expect it.

### Nested procedures: display with WASM globals

Pascal supports nested procedures that access enclosing scope variables (upvalues). WASM has no closures and all functions are top-level, so a mechanism is needed.

**Approach chosen: Dijkstra's display technique.** A fixed-size array of 8 WASM globals (`display[0]` through `display[7]`) where `display[N]` holds a pointer to the frame at nesting level N. Accessing an upvalue at level M is always exactly two loads: read `display[M]` to get the frame pointer, then load the variable at its offset within that frame. O(1) regardless of nesting depth.

**Why display over static links:** The alternative is a static link (hidden parameter pointing to parent frame), requiring O(depth) pointer chasing per upvalue access. The display is faster, simpler, and avoids adding hidden parameters that would complicate WASM function signatures, `{$EXPORT}`/`{$IMPORT}`, and procedural types.

**Zero overhead for non-nested procedures:** The compiler tracks nesting depth during parsing. Top-level procedures (level 0) emit no display code at all — no save, no restore, no global access. Only procedures at nesting level ≥ 1 emit the save/restore protocol:

```
; entry to procedure at level N:
saved := display[N]        ; global.get
display[N] := frame_ptr    ; global.set

; ... body (upvalue at level M: global.get display[M], then i32.load offset) ...

; exit:
display[N] := saved        ; global.set
```

That is 3 extra WASM instructions per nested procedure call. In practice, the vast majority of procedures are top-level and pay nothing.

**Maximum nesting depth of 8.** Real Pascal code rarely nests beyond 3-4 levels. The compiler emits a clear error if the limit is exceeded. 8 WASM globals is negligible.

**Recursion is handled correctly** because each entry saves and restores `display[N]`. Recursive calls at the same level see the correct frame.

### Go-style interfaces: representation trade-off

Inline vtable (Self + N function pointers) chosen for simplicity. Shared itable optimization deferred.

### Backward compatibility and self-hosting constraints

The compiler source must compile under both fpc `-Mtp` and Compact Pascal for self-hosting. This drives several language decisions:

**Strings:** Phase 1 uses TP-style short strings (length byte + data, max 255 chars) as the only string type. Short strings need no allocator, live on the stack or in records, and are identical to fpc `-Mtp` strings — so the compiler source works on both without adaptation. A richer pointer+length string type with no size limit will be added in Phase 5b when dynamic allocation is available.

**A hybrid layout** (pointer+length with a Pascal-compat length byte at offset -1) was considered and rejected for Phase 1. It requires maintaining two length fields in sync, creates a type split between "real strings" and "substrings/slices," and has no consumer in Phase 1 since there is no external Pascal code to interop with.

**Standard functions and procedures:** `abs`, `ord`, `chr`, `odd`, `succ`, `pred`, `sqr`, `length`, `sizeof`, `lo`, `hi`, `inc`, `dec`, `exit`, `halt` are included as compiler intrinsics. These are trivial to implement (inline WASM ops) and critical for compatibility — both with existing Pascal idioms and for writing the compiler source.

**Built-in I/O:** `write`/`writeln` and `read`/`readln` are compiler intrinsics that lower to WASI preview 1 `fd_write`/`fd_read` calls. This makes compiled programs WASI-compatible and runnable under `wasmtime` out of the box. The predefined file handles `input` (fd 0), `output` (fd 1), and `stderr` (fd 2) allow directing I/O to specific fds: `writeln(stderr, 'Error: ', msg)`.

**TP numeric types:** `byte`, `word`, `shortint`, `longint` are included as aliases to WASM integer types. These are trivial to add and important for the compiler source.

**Include file resolution:** `{$INCLUDE}` directives are resolved by the host application before invoking the compiler. The embedding library scans the source, expands includes by replacing the directive with file contents, and passes a single concatenated source stream to the compiler on stdin. This keeps the compiler's I/O interface minimal (three fds, no filesystem access). During fpc bootstrap, fpc handles `{$I}` natively. The Rust and Zig libraries provide a utility function for this — parsing `{$I 'filename'}` out of comments is straightforward.

**Built-in I/O scope:** Phase 1 supports a minimal subset of `write`/`writeln` (integers, characters, strings) and `read`/`readln` (integers, characters). Format specifiers (`:width`, `:width:decimals`), booleans, and reals are deferred. The first argument may be a predefined file handle (`input`, `output`, `stderr`) to direct I/O to a specific fd. This gives the compiler source a portable way to write error diagnostics: `writeln(stderr, 'Error: ', msg)` works under both fpc and Compact Pascal. There are no general-purpose file types — `text` exists solely for the three predefined handles.

**Sub-32-bit types in WASM:** WASM only has `i32` and `i64`. Types like `byte`, `word`, `shortint` are stored as `i32` internally. Range masking (e.g., `i32.and 0xFF` for `byte`) is only emitted when `{$R+}` is enabled. Without range checks, these types behave as `i32` with no overhead. The compiler source itself avoids subrange types to keep Phase 1 simple.

**Enumerated types and subranges:** All ordinal types (enumerations, subranges, `byte`, `word`, `shortint`, `char`, `boolean`) are stored as WASM `i32` internally. No packing or smaller representations. Range checks are only emitted with `{$R+}`.

**Integer size:** `integer` is 32-bit (WASM `i32`), unlike TP/BP where `integer` is 16-bit. This is a minor compatibility break — programs that don't overflow 16-bit integers are unaffected. `longint` remains 32-bit (same as `integer` on this target) for source compatibility. `maxint` is 2147483647.

**String parameter passing:** Follows the Turbo Pascal convention. `const` and `var` string parameters are passed by reference (pointer). Only value parameters copy the string data. This avoids copying up to 256 bytes per call for `const`/`var` params and matches fpc `-Mtp` behavior.

**Case sensitivity:** Compact Pascal is case-insensitive, as in standard Pascal. Identifiers, keywords, and type names are matched without regard to case. The sole exception is WASM import/export names in `{$IMPORT}` and `{$EXPORT}` directives, which are case-sensitive because they refer to external WASM symbols.

**Numeric literals:** TP-style hex literals (`$FF`) are supported in Phase 1. C-style prefixes (`0xFF`, `0o77`, `0b1010`) are available behind the `{$EXTLITERALS ON}` directive, disabled by default. Hex literals are essential for the compiler source (WASM binary encoding uses hex constants extensively).

**Set types:** `set of T` supported with bitmap representation sized to the base type's ordinal range, up to 256 bits (32 bytes). Operations: `+` (union), `*` (intersection), `-` (difference), `in` (membership), comparisons. Sets are useful for the compiler (e.g., character classification sets like `['0'..'9']`, `['a'..'z', 'A'..'Z']`).

**Variant records:** Supported via `case` tag in records. Variants share memory at the same offset; record size is the largest variant. Tag is a normal field. Maps directly to WASM linear memory (just overlapping offsets). Useful for the compiler's symbol table entries.

**`with` statement:** Included for record field access shorthand. Standard Pascal feature, common in TP code, and useful when working with nested record fields.

**Calling convention keyword (future):** A `pascal` keyword (analogous to `cdecl`/`stdcall` in TP/Delphi) was discussed for marking parameters that use Pascal string convention vs a future pointer+length convention. Deferred until Phase 5 when a second string type exists.

**Bootstrap dialect: fpc `-Mtp` confirmed.** TP 7.0 mode is the most restrictive fpc dialect, which is a feature — if the compiler source compiles under `-Mtp`, it almost certainly compiles under Compact Pascal too. A more permissive mode (`-Mobjfpc`, `-Mdelphi`) would risk accidental use of features not in Compact Pascal (`Result`, ansistrings, classes, overloads), creating self-hosting surprises. The only friction is `integer` being 16-bit in TP mode vs 32-bit in Compact Pascal; the compiler source uses `longint` (32-bit in both) to avoid this. Other costs are minor: assigning to function name instead of `Result` (standard Pascal anyway), no operator overloading (not needed). The restrictive mode serves as a guardrail that keeps the compiler source within the Compact Pascal subset.
