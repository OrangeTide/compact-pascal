# Compact Pascal — Project Plan

Compact Pascal is a new language in the Pascal family with a compiler that targets WASM 1.0. The compiler is written in Pascal, ships as a WASM binary, and is embedded in Rust, Zig, and C libraries.

See `doc/compact-pascal-wp.md` for the full white paper and `doc/compact-pascal-ref.md` for the language reference.

## Goals

1. **Design a new Pascal-family language** — minimal, strongly typed, suitable for embedding. I/O via compiler intrinsics that lower to WASM host imports. Not a conforming implementation of any existing standard.
2. **Write the compiler in Pascal** — single-pass recursive-descent parser targeting WASM 1.0 binary output. Bootstrapped with fpc, then self-hosting.
3. **Ship the compiler as a WASM blob** — the compiler runs inside a WASM interpreter, so any host that can run WASM can compile Compact Pascal programs.
4. **Provide Rust, Zig, and C embedding libraries** — high-level APIs to compile Pascal source, instantiate WASM modules, and bridge host-guest function calls. No external Pascal toolchain required. The C library uses a bring-your-own-WASM-runtime approach via a vtable interface.
5. **Run everywhere WASM runs** — native applications (via wasmi/wasm3), browsers (via native WebAssembly API), edge runtimes.
6. **Extend the language thoughtfully** — add structural interfaces with methods, and potentially garbage collection, while preserving single-pass compilation and the language's minimalist character.

## Bootstrapping

Bootstrap using **fpc** in TP/BP 7.0 mode (`-Mtp`). fpc produces a **native binary** (not WASM). The native compiler then compiles its own source to WASM, producing the first snapshot. Once a snapshot WASM blob exists (< 1 MB, committed to git), only Rust, Zig, or C (with a WASM runtime) is needed to build.

**Open question (checked when resolved) :**
- [x] do we keep the bootstrap compiler that can build in TP-mode of fpc? Or move entirely to the self-hosted compiler knowing that if we lose the .wasm binary that we are stuck? **RESOLVED: Keep fpc bootstrap permanently.** The TP subset fits the compiler's coding style naturally (flat arrays, integers, short strings), so the compatibility cost is near-zero. The main benefit is cross-checking: building via fpc (native → WASM) and via the snapshot (WASM → WASM) gives two independent paths to the same output. Diffing them is a fixpoint test that catches self-hosting bugs. Disaster recovery (rebuild without a WASM runtime) and easy onboarding (`fpc -Mtp cpas.pas` is one command) are secondary benefits. The compiler source must continue to avoid Compact Pascal extensions not present in fpc `-Mtp` (no initialized variables, no extended literals, etc.).

## Project Layout

```
compiler/       — Pascal source for the compiler (built with fpc)
compiler-tests/ — test suite modeled on BSI Pascal Validation Suite
src/
  rust/         — Rust crate source
  zig/          — Zig library source
  c/            — C embedding library (bring-your-own-WASM-runtime)
snapshot/       — the compiler WASM blob (shared by Rust, Zig, and C)
examples/
  pascal/       — Compact Pascal example programs
  lightout/     — Light's Out browser game (Canvas + WASM, see doc/lightout-example.md)
  rust/         — Rust embedding examples (hello, ffi, pode-server)
  zig/          — Zig embedding examples
  c/            — C embedding examples (wasm3)
  html/         — client-side browser playground (static HTML, no server)
pages/          — GitHub Pages site (includes deployed playground)
doc/            — white paper, language reference, and compiler tutorial
Cargo.toml      — Rust build (lib path: src/rust/lib.rs)
build.zig       — Zig build (root source: src/zig/)
build.zig.zon   — Zig package manifest
```

## Phases

### Phase 1: Compact Pascal Compiler (Pascal, bootstrapped with fpc) — `DONE`

**Shipped.** The compiler is written in Pascal (fpc `-Mtp` mode), self-hosts, and emits WASM 1.0. It covers the ISO-7185-compatible core (integers, booleans, chars, records, arrays, sets, pointers, short strings, enums, ranges), ISO 10206 short-circuit operators, Turbo Pascal extensions (typed casts, hex literals, `break`/`continue`), and Compact Pascal additions (extended literals, initialized variables, `{$MEMORY}`/`{$MAXMEMORY}`/`{$STACKSIZE}` directives, `{$EXPORT}`/`{$IMPORT}` FFI). I/O intrinsics lower to WASI preview 1. Nested procedures use the Dijkstra display. The fpc-built and self-built compilers produce bit-identical WASM (fixpoint validated).

Self-hosting milestone reached; the original Phase 1 goal (a self-hosted compiler sufficient to write itself) is complete. Remaining language polish, doc coverage, and example work has moved to Phase 1c. Peephole optimization remains in Phase 1b.

The authoritative record of what the compiler supports is the language reference (`doc/compact-pascal-ref.md`) plus the test suite (`compiler-tests/`).

**Standalone usage (no embedding library needed):**

```bash
wasmtime run compiler.wasm < hello.pas > hello.wasm
wasmtime run hello.wasm

# Inspect generated WASM instructions
wasmtime run compiler.wasm -- -dump < hello.pas > hello.wasm
```

### Phase 1b: Peephole Optimization (Optional) — `NOT STARTED`

Optional sliding-window peephole optimizer for the WASM code buffers. Entirely compile-time gated behind `{$IFDEF PEEPHOLE}` — when not defined, zero bytes are added to the compiler WASM image. Can be added to an existing compiler at any time without modifying the core codegen.

**Prerequisites:**
- [x] `-dSYMBOL` command-line flag for conditional compilation symbols (via WASI `args_get`); `{$DEFINE}` / `{$UNDEF}` directives; `CPAS` predefined
- [ ] `-O0` / `-O1` command-line flags (parsed, stored in global `optLevel`; ignored when peephole not compiled in)
- [ ] `{$OPT+/-}` compiler directive (toggles optimizer per-region; ignored when peephole not compiled in)

**Optimizer:**
- [ ] `TryPeephole` procedure called after each opcode emission, gated by `{$IFDEF PEEPHOLE}` and `optLevel > 0`
- [ ] Fixed lookback window on code buffer (compile-time constant, tunable)
- [ ] Switch/case pattern matcher on trailing opcode bytes
- [ ] LEB128 decode helper for constant-folding patterns
- [ ] Patterns: `local.set/get → tee`, constant folding, identity elimination, double negation, strength reduction (shift-for-multiply)
- [ ] Verify all rewrites preserve WASM stack typing

**Validation:**
- [ ] Existing test suite passes identically with `-O0` and `-O1`
- [ ] Disassemble non-trivial programs (`wasm-objdump -d`) to verify pattern elimination
- [ ] Measure code size reduction on compiler self-compilation

**Tutorial:**
- [ ] Appendix in tutorial book (not a numbered chapter) — optional exercise
- [ ] Covers: stack-machine redundancy patterns, sliding-window technique, conditional compilation, compiler-size vs output-quality trade-off, historical context (shift-vs-multiply on real hardware)

**Research notes:** `notes/research-peephole.md`

### Phase 1c: Language Completeness — `IN PROGRESS`

Polish items beyond the self-hosting cut. None of these block any later phase; they close the gap between "compiler writes itself" and "compiler is a complete Compact Pascal toolchain per the language reference."

**Language features:**
- [x] Typed constants — scalar, 1D/ND array, `array of char` string-literal shortcut, record `(field: value; ...)`, and set `[elem, ...]` initializers implemented (tests t086–t088, t091, t092). Stored in data segment; TP-style mutable. Variant-record initializers tracked under Milestone 11.
- [ ] Variant records — `case tag: T of ...` inside record types, and the corresponding typed-constant initializer form. Design: see Milestone 11 below.
- [ ] Subrange base types in `set of` — `set of 0..31`, `set of 'a'..'z'`, `set of Day(Mon..Fri)`. Docs already promise this; compiler currently rejects. Design: see Milestone 12 below.
- [x] `{$ALIGN n}` directive for record field alignment (n ∈ {1, 2, 4, 8}, default 4; test t089)
- [x] `-dump` flag in self-hosted builds (ParamCount/ParamStr intrinsics via WASI args_get)

**Documentation coverage:**
- [ ] fpdoc comments on all public procedures/functions, with detailed comments on core routines (see Findings)
- [ ] WAT pseudo-code comments on all WASM binary emission sites (partial coverage, ~17 comments today)

**Browser game example (Light's Out):**
- [ ] `examples/lightout/` — 5×5 Light's Out puzzle running in browser via HTML5 Canvas
- [ ] Design doc: `doc/lightout-example.md` (already written)
- [ ] `lightout.pas` — game logic, rendering, input (~120 lines)
- [ ] `host.js` — JS bridge: canvas, input, Web Audio tone generation (~80 lines)
- [ ] `index.html` — canvas scaffold (~20 lines)
- [ ] Makefile for building and local serving
- [ ] Demonstrates `{$IMPORT}`/`{$EXPORT}` FFI, arrays, constants, frame-driven game loop

### Phase 2: Embedding Libraries (Rust + Zig + C) — `NOT STARTED`

#### Rust (`compact-pascal` crate, using wasmi)

- [ ] Cargo project setup with wasmi dependency
- [ ] Embed the snapshot WASM blob of the compiler
- [ ] Run the compiler in wasmi to compile Pascal source to WASM bytes
- [ ] Provide WASI preview 1 host imports for the compiler (`fd_read`, `fd_write`, `proc_exit`)
- [ ] Instantiate and run compiled WASM modules via wasmi
- [ ] Host-guest FFI (imports and exports)
- [ ] String conversion helpers
- [ ] `{$INCLUDE}` / `{$I}` preprocessing (expand include directives before passing source to compiler)
- [ ] Example: `examples/rust/hello/` — minimal compile-and-run (~30 lines, shows basic API)
- [ ] Example: `examples/rust/ffi/` — host-guest FFI (register Rust function, call from Pascal, call Pascal export from Rust)
- [ ] Example: `examples/rust/pode-server/` — **Pode Server: The Pascal Node Clone** (see `doc/pode-server.md`)
  - [ ] File-based routing: `routes/*.pas` → HTTP endpoints (filename = route path)
  - [ ] Query string → stdin piping (`GET /fib?input=10` → `readln(n)` receives `"10"`)
  - [ ] stdout → HTTP response body, stderr → server console with colored `[route]` prefix
  - [ ] Hot reload: watch `routes/` via `notify` crate, recompile on save
  - [ ] Deno-style permission flags: `--allow-stdout`, `--allow-stdin`, `--allow-args`
  - [ ] Startup banner with ASCII toad
  - [ ] Auto-generated landing page at `GET /` listing all routes
  - [ ] Example routes: `hello.pas`, `fib.pas`, `greet.pas`
  - [ ] Dependencies: `compact-pascal`, `axum`, `tokio`, `notify`, `clap`

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

#### C (`compact-pascal` library, bring-your-own-WASM-runtime)

- [x] `src/c/compact_pascal.h` — public header with vtable interface, API functions, WASI helpers
- [x] `src/c/compact_pascal.c` — implementation
- [x] Vtable-based WASM engine abstraction (`cp_wasm_engine_t`) — user fills in function pointers for their chosen runtime
- [x] `cp_load_compiler_from_file()` — load compiler snapshot WASM from disk
- [x] `cp_load_compiler_from_string()` — load compiler snapshot WASM from memory buffer
- [x] WASI preview 1 callback implementations (fd_read, fd_write, proc_exit, args_get, args_sizes_get) that users wire into their runtime
- [x] String conversion helpers: C string ↔ Pascal short string in WASM linear memory
- [x] Host-guest FFI (imports and exports) through the vtable
- [ ] `{$INCLUDE}` / `{$I}` preprocessing (expand include directives before passing source to compiler)
- [x] Example: `examples/c/hello/` — minimal compile-and-run using wasm3

All three libraries share the same snapshot blob and compiler test suite. APIs should be idiomatic to each language.

### Phase 3: Self-Hosting — `NOT STARTED`

- [ ] Use the native (fpc-built) compiler to compile its own source to WASM, producing the first snapshot binary
- [ ] Verify fixpoint: run the snapshot in wasmi, compile the compiler source again, diff the output
- [ ] Commit the snapshot blob to git (must be < 1 MB)
- [ ] Verify the Rust crate works end-to-end using only the snapshot (no fpc required)
- [ ] Verify the Zig library works end-to-end using only the snapshot (no fpc required)
- [ ] Verify the C library works end-to-end using only the snapshot (no fpc required)

### Phase 4: Browser IDE (Playground) — `DONE`

Browser-based IDE at `pages/playground/index.html`. Vanilla HTML/CSS/JS, no build tools, no framework. Loads `compiler.wasm` via `fetch()`, compiles and runs Pascal programs entirely client-side.

Shipped: split-pane IDE layout, tabbed editor with empty-state logo, syntax highlighting (state-machine tokenizer, HTML-embedded), save/load/upload/download, auto-save and Save/Delete tab menu, unsaved-modified indicator, dark mode, compiler version display (`__version`), GitHub source link, pre-staged stdin for Run, compiler.wasm loaded and executed client-side with WASI shim, GitHub Pages deployment, homepage link.

Deferred / future polish (tracked as candidates, not blockers):
- Clipboard API Copy/Paste (native Ctrl+C/V works; explicit menu buttons not added).
- Version control integration (Gist/Snippet-style persistence) — see [Open Questions](#phase-4-open-questions).
- WebGL/sokol canvas integration — see [Open Questions](#phase-4-open-questions).

#### Phase 4 Open Questions
- Version control / persistent history for Playground buffers (Gist, Snippet, built-in Git/Fossil). Needs a separate design pass before committing to a Phase.
- WebGL canvas with a 3D API (TN-002). Plumbing and framework evaluation outstanding.

### Phase 5: Playground File I/O — `NOT STARTED`

Adds limited text file I/O to the compiler and wires it to an
editor-as-filesystem in the playground. Scoped to `text` files only
(no `file of record`) so it lands before dynamic allocation (Phase 6).

Interactive stdin via `SharedArrayBuffer` + `Atomics.wait` was considered
and dropped: the playground ships pre-staged stdin (user types input
before Run, passed as a blob). See Findings.

**Compiler changes (cpas.pas):**

- [ ] New WASI imports: `path_open` (9 i32 → i32, needs `TypeI32x9I32`),
  `fd_close` (1 i32 → i32, needs `TypeI32I32` distinct from `TypeI32Void`).
- [ ] `text` file variable representation: 8 bytes on the stack.
  - Bytes 0-3: fd (i32, -1 when closed)
  - Bytes 4-5: mode (0=closed, 1=read, 2=write)
  - Bytes 6-7: padding
  File variables do not store the filename.
- [ ] Global filename scratch area: 260 bytes (4-byte length + 256 bytes
  data) in the data segment, reused across `assign` calls.
- [ ] `fd_dir` global: WASM global initialized to 3 (pre-opened editor
  root directory).
- [ ] Built-ins: `assign(f, name)`, `reset(f)`, `rewrite(f)`, `close(f)`,
  `eof(f)`.
- [ ] Generalize `write`/`writeln` and `read`/`readln` codegen to accept
  a file variable as the first argument (use `f.fd` instead of the
  hardcoded 1/0). Verify `__write_int`/`__write_str`/`__read_int`/
  `__read_str` helpers take fd as a parameter.
- [ ] Error handling: halt on failed open for initial cut; revisit
  `IOResult` / `{$I-}` later.
- [ ] Update language reference: add `text` file type, `assign`, `reset`,
  `rewrite`, `close`, `eof(f)`. Document the Phase 5 restriction
  (no `file of record` until Phase 6).

**Runtime changes (run-worker.js):**

- [ ] Refactor hardcoded fd 0/1/2 into a proper fd table: each entry
  holds `read(buf, len) -> nread`, `write(buf, len) -> nwritten`,
  `close()`, `flags`. Initial state fills fd 0 = stdin,
  fd 1 = stdout, fd 2 = stderr.
- [ ] Implement `fd_close` WASI import: look up entry, invoke `close()`,
  null the slot. Closing 0/1/2 is allowed.
- [ ] Implement `path_open` WASI import:
  - Read path string from WASM memory; validate `fd_dir` is 3.
  - Check oflags: `O_CREAT` (1), `O_EXCL` (4), `O_TRUNC` (8).
  - Allocate next free fd table slot.
  - Write mode: file_ops with a write buffer; each `fd_write` posts
    `{ type: 'file_write', name, data }` to main thread. On `fd_close`,
    post `{ type: 'file_close', name }`.
  - Read mode: use the same main-thread message bridge as stdin
    (the pre-staged pattern) to fetch buffer content; subsequent
    `fd_read` calls consume from the local copy.
  - Store allocated fd at `fd_out` pointer in WASM memory.
  - Return 0 or errno (ENOENT=44, EBADF=8, etc.).
- [ ] Pre-open fd 3 as the editor root directory (directory-type entry,
  not readable/writable itself — only valid as `path_open`'s `fd_dir`).

**Main thread changes (index.html):**

- [ ] Handle `{ type: 'file_write', name, data }`: decode UTF-8, append
  to or create tab with that name; mark tab as program-generated.
- [ ] Handle `{ type: 'file_read_request', name }`: look up editor
  buffer; on hit, return content; on miss, return errno.
- [ ] Handle `{ type: 'file_close', name }`: final flush notification.

**Open items:**
- Decide error handling surface (halt vs `IOResult`) — start with halt.
- 26 drive-letter globals (A:–Z:) are future work; Phase 5 reserves the
  WASM global slots, initializing all but A: to -1.

### Phase 6: Dynamic Allocation — `NOT STARTED`

- [ ] `New`/`Dispose` with free-list allocator in WASM linear memory
- [ ] Object headers with metadata (size, mark bits, link pointers) for future GC
- [ ] Dynamic arrays with open-array unification (IP Pascal model) — see Findings
- [ ] Future: Baker's Treadmill GC (non-moving, incremental, shadow stack for root tracking)

### Phase 6b: Richer String Type — `NOT STARTED`

- [ ] Pointer + length string type with no 255-character limit (requires dynamic allocation)
- [ ] Strings remain a distinct type from dynamic arrays — see Findings
- [ ] `pascal` calling convention keyword for FFI compatibility between string representations
- [ ] Conversion between short strings and dynamic strings

### Phase 7: Units and Separate Compilation — `NOT STARTED`

- [ ] Design unit/module syntax (Component Pascal / Oberon-2 style modules, or TP-style units)
- [ ] Define `compact-pascal-meta` WASM custom section format for unit metadata (exported types, signatures, constants)
- [ ] Compiler reads dependency `.wasm` files and extracts type info from custom sections
- [ ] Host-side module linking at instantiation (connecting WASM imports to exports)
- [ ] Optional inline function bodies in metadata for cross-unit inlining
- [ ] Evaluate WASM Component Model compatibility as it stabilizes

### Phase 8: Interfaces and Methods — `NOT STARTED`

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

### Language design

**Language naming.** Renamed from "Pascaline-Plus" to "Compact Pascal" — a new language in the Pascal family, not a superset of any existing dialect. "Fermat" (after Pascal's collaborator) was the runner-up.

**Case sensitivity.** Compact Pascal is case-insensitive, as in standard Pascal. Identifiers, keywords, and type names are matched without regard to case. The sole exception is WASM import/export names in `{$IMPORT}` and `{$EXPORT}` directives, which are case-sensitive because they refer to external WASM symbols.

**Short-circuit evaluation: `and then` / `or else`.** Adopted ISO 10206 short-circuit operators rather than always-short-circuit (C-style) or a compiler directive (`{$B+/-}`). Explicit at the call site, no ambiguity. Standard `and`/`or` retain full-evaluation ISO 7185 semantics. **Precedence deviation from ISO 10206:** ISO Extended Pascal places `and then` at the same level as `*` (multiplying-operators) and `or else` at the same level as `+` (adding-operators). Compact Pascal instead gives `and then` and `or else` their own levels below comparisons, similar to C's `&&` and `||`. This allows natural expressions like `x < 2 * y and then z - 1 < w` to parse as `(x < 2 * y) and then (z - 1 < w)` without parentheses. Under ISO precedence the same expression would parse nonsensically. The eager `and`/`or` retain standard Pascal precedence (with multiplying and adding operators respectively) for fpc TP-mode bootstrap compatibility.

**Comment styles: `{ }`, `(* *)`, `//`, and `#!` shebang.** Three comment forms are supported: brace comments `{ }`, parenthesis-star comments `(* *)`, and C++-style line comments `//`. Line comments extend to end-of-line. Whether comments nest is undefined — an implementation may support nesting or not. Programs that depend on nested comments are not portable. This follows ISO 7185, which defines a comment as ending at the first `}` or `*)` without mentioning nesting. Additionally, if the first byte of the source is `#`, the rest of the first line is ignored — this permits Unix interpreter directives (`#!/usr/bin/env cpas`). The `#` handling is pre-lexical (fires once at scanner init before tokenization begins) and does not conflict with the `#n` character constant syntax, which can never appear at position 0 of a valid Pascal source file. The `//` line comment does not conflict with the `/` operator (real division) — the scanner distinguishes them by lookahead: `//` starts a comment, a lone `/` is a token. In Phase 1, `/` is recognized by the scanner but rejected by the compiler since `real` is deferred.

**Source encoding: UTF-8, char = byte.** Source files are UTF-8. The lexer only interprets ASCII-range bytes (0x00–0x7F) for tokens; bytes 0x80–0xFF pass through verbatim in string literals and comments. `char` remains a single byte (not a Unicode codepoint), `length` returns the byte count, and `s[i]` indexes by byte. This is the same model as C (`char`), Go (`[]byte`), and Rust (`&[u8]`). Phase 1 impact is near-zero: the scanner is already 8-bit clean since it copies literal/comment bytes without interpretation. No UTF-8 validation, decoding, or normalization is performed. `set of char` remains 256 bits (32 bytes). `ord`/`chr` operate on byte values 0–255. Legacy TP source in CP437 or other code pages must be converted to UTF-8 before compilation — this is a one-time step using standard tools (`iconv`, Rust `encoding_rs`, etc.), not a compiler feature. Unicode-aware string operations (codepoint iteration, normalization) are a library concern for later phases.

**String literal escaping.** A single quote within a string literal is escaped by doubling it: `'it''s'` produces a 4-byte string. This is standard Pascal/TP behavior. The scanner handles this during string literal tokenization.

**Character constants (`#n`).** TP-style `#n` character constants produce a raw byte (0–255). Decimal (`#13`) and hex (`#$1B`) are supported. Values above 255 are always an error — they are ambiguous (raw byte vs UTF-8 codepoint). Adjacent `#n` and `'...'` sequences are folded into a single string constant by the scanner: `'Hello'#13#10` is one 7-byte string, not three tokens. A standalone `#n` is a `char` constant.

**Unicode character constants (`#uHHHH`, future).** A `#u` prefix followed by hex digits produces a `rune` value (32-bit Unicode codepoint). `#u` always uses hexadecimal (no `$` prefix needed), so `#$41`, `#u41`, and `#u0041` all represent the same codepoint. For codepoints above 255, `#u` is the only way to express them — `#n` is restricted to 0–255. Not implemented in Phase 1; planned for a later phase alongside the `rune` type.

**`rune` type and Unicode model (future, Go-inspired).** Unicode support follows Go's byte/rune model rather than FPC/Delphi's WideChar/UnicodeString proliferation. `char` stays as a byte (0–255), preserving Phase 1 compatibility. A new `rune` type (32-bit, stored as WASM `i32`) represents a Unicode codepoint. Strings remain UTF-8 byte sequences at runtime — `s[i]` is byte access, `length` returns bytes. The key design rules:

*Concatenation:* When a `rune` is concatenated with a string, the compiler encodes the rune as UTF-8 bytes. When a `char` above 127 is concatenated with a string or rune, the compiler emits a warning — raw bytes 128–255 are not valid standalone UTF-8 and the user almost certainly meant `#u`. This warning only fires for literal/constant expressions where the value is known at compile time. Runtime string operations are byte-level with no checks.

*Concatenation result types:*
- `char + string` → string (byte append; warn if char > 127)
- `rune + string` → string (rune encoded as UTF-8)
- `rune + rune` → string (both encoded as UTF-8)
- `char + rune` → string (warn if char > 127; rune encoded as UTF-8)
- `char + char` → string (two bytes; warn if either > 127)

*Literals:* `#uHHHH` produces a `rune`, not raw UTF-8 bytes. Because source is UTF-8, all string literals are valid UTF-8. The warning for `char` > 127 catches mistakes like `'café' + #233` where the user meant `#u00E9`.

*Built-in functions:*
- `RuneLen(s: string): integer` — count of codepoints in a UTF-8 string
- `DecodeRune(s: string; i: integer; var r: rune): integer` — decode rune at byte index `i`, return next byte index
- `EncodeRune(r: rune): string` — return the UTF-8 encoding of a rune (1–4 byte short string)
- `RuneChr(n: integer): rune` — integer to rune (like `chr` but for the full Unicode range)
- `ord(r: rune): integer` — codepoint value (existing `ord` overloaded for `rune`)

*What stays the same:* `set of char` remains 256 bits. `chr(n)` returns a `char` (0–255). `s[i]` is byte access. Runtime strings are byte bags — the compiler does not validate or enforce UTF-8 at runtime. No `WideChar`, no `UnicodeString`, no type proliferation.

*Phase:* Planned alongside Phase 6b (richer string type). Phase 1 has no `rune` type — `#u` is a parse error.

**`case` statement `else` clause.** The `case` statement supports an optional `else` branch as a default, following the Turbo Pascal extension. If no branch matches and no `else` is present, execution continues past `end` without error.

**Typed subrange syntax (GPC convention).** Subranges can specify an explicit base type using the GNU Pascal Convention: `Day(Mon..Fri)`. This is in addition to the standard inferred form `Mon..Fri` where the compiler deduces the base type from the constants. The typed form is self-documenting and prepares for a future relaxation of the unique-names rule (e.g., qualified enum access like Modula-2). In the parser, it's an LL(2) distinction in `SimpleType`: after seeing `Identifier`, peek for `(` (typed subrange) vs `..` (untyped subrange) vs anything else (type identifier). Phase 1 impact is minimal — a small addition to type parsing with the same semantic checks already needed for untyped subranges.

**Single-file compiler source.** The compiler is kept as a single file (`compiler/cpas.pas`) rather than split via `{$I}` includes. At ~7400 lines, a single file with well-commented sections is navigable and matches the reality of the design — it's a single-pass compiler with tightly coupled shared global state. Pascal `{$I}` includes are textual paste, not modules, so splitting wouldn't reduce coupling or improve encapsulation. It would add host-side preprocessing complexity (the WASM-hosted compiler receives a pre-expanded source stream). Wirth's Oberon compiler follows the same single-file convention at ~4000 lines. Revisit if the file exceeds ~6000 lines.

**Numeric literals.** TP-style hex literals (`$FF`) are supported in Phase 1. C-style prefixes (`0xFF`, `0o77`, `0b1010`) are available behind the `{$EXTLITERALS ON}` directive, disabled by default. Hex literals are essential for the compiler source (WASM binary encoding uses hex constants extensively).

**Compiler directives: Free Pascal syntax.** Adopted `{$DIRECTIVE}` / `{$DIRECTIVE VALUE}` syntax matching Free Pascal. Global directives (before any code): `{$MEMORY}`, `{$MAXMEMORY}`, `{$STACKSIZE}`, `{$DESCRIPTION}`. Local directives (anywhere): `{$R+/-}`, `{$Q+/-}`, `{$ALIGN}`, `{$I}`, `{$EXPORT}`, `{$IMPORT}`. The `{$EXPORT}` and `{$IMPORT}` directives are how programs declare the WASM FFI boundary.

**`with` statement.** Included for record field access shorthand. Standard Pascal feature, common in TP code, and useful when working with nested record fields.

**Structured return types (extension, C-inspired).** Functions may return any type, including arrays and records. Standard Pascal restricts function return types to simple types and pointers; Compact Pascal lifts this restriction, following C's precedent where functions can return structs by value. The compiler implements this via a hidden pointer: functions returning structured types receive a caller-allocated hidden first parameter pointing to the return slot. The caller allocates the return space in its own stack frame and passes a pointer. The callee writes to that pointer. This is the same calling convention used by C compilers on most targets. The grammar uses `Type` (not `TypeIdentifier`) in function return type positions.

**Unified `Designator` in `Factor` (grammar cleanup).** ISO 7185's grammar has separate `Variable` and `FunctionDesignator` alternatives in `Factor`, creating an LL(1) conflict since both start with `Identifier`. Real Pascal compilers resolve this by consulting the symbol table, but the grammar itself is ambiguous at the syntax level. Our grammar merges these into a single `Designator` production that handles variables, function calls, type casts, and method calls uniformly. Function call parentheses `'(' [ExprList] ')'` are a `Selector` within `Designator`, alongside field access, array indexing, and pointer dereference. The parser does not distinguish variable access from function calls — that is a semantic analysis concern. This is strictly LL(1), matches what every practical Pascal compiler does, and parses the same programs identically. Compact Pascal's use of `[]` for array subscripts (TP convention) means `()` is unambiguously a call or type cast, which is cleaner than ISO 7185 where `()` is overloaded for both subscripts and calls.

**Advanced features: anti-goals and future possibilities.** Several advanced programming language features were evaluated against the project's core constraints — single-pass compilation, WASM 1.0 target, self-hosting in fpc `-Mtp`, minimalist character, and the <1 MB WASM blob budget. Most are anti-goals. The language's strength is that it is small enough to understand completely; the Go-style interfaces planned for Phase 8 are the intended ceiling for abstraction.

*Traits / bounded polymorphism: anti-goal.* Rust-style traits with generic type bounds require either monomorphization (code explosion in WASM, multi-pass to instantiate) or dictionary passing (runtime overhead, complex calling convention). Both break single-pass compilation or bloat the output. Associated types and trait coherence checking (orphan rules) require whole-program analysis that conflicts with separate compilation (Phase 6). The Phase 7 interfaces already cover the polymorphism use case — structural conformance with vtable dispatch, no generics machinery. If bounded polymorphism is ever needed, the Oberon-2/Component Pascal route (type-bound procedures on a type hierarchy) is more compatible with single-pass than Rust traits.

*Generics (monomorphized): anti-goal.* Template-style generics require the compiler to instantiate specialized copies of generic code, which is fundamentally a multi-pass operation — the generic body must be stored and replayed for each type argument. This conflicts with single-pass architecture and grows the WASM output. Most Compact Pascal code uses concrete types; the interfaces in Phase 8 handle the cases where abstraction over types is needed.

*Lambdas / first-class closures: anti-goal for Phase 1, possible future extension.* Nested procedures already capture enclosing scope variables via the Dijkstra display, but they are not first-class values. Making them first-class requires heap-allocated closure environments (the enclosing stack frame may be gone when the closure runs), so this is a Phase 6+ feature at earliest. In WASM 1.0, closures become fat pointers (function table index + environment pointer) dispatched via `call_indirect`. The single-pass compiler would need explicit syntax (e.g., a `lambda` keyword) to know at parse time whether captured variables need heap promotion. Procedural types (function pointers without capture, as in TP) are straightforward and planned; full closures add real code generation complexity for a feature the compiler itself does not need.

*Reflection / RTTI: anti-goal.* Runtime type information requires emitting type descriptors (names, field layouts, variant tags) into the data segment for every type. This causes code size explosion that threatens the blob budget, requires deferred or fixup emission that complicates single-pass output, and widens the API surface in an embedding context where the host already has full visibility into guest memory. Serialization and introspection are better handled by the host via FFI. If limited introspection is wanted, a compile-time `typename` function returning a string constant is cheap and sufficient for diagnostics.

*Async/await: anti-goal.* Requires either continuation-passing style transformation (a whole-program rewrite pass) or stackful coroutines (WASM has no stack switching in 1.0). Neither is compatible with single-pass compilation. The host handles async — WASM guest code runs synchronously, and the embedding library manages concurrency.

*Exceptions (`try`/`except`): possible future extension.* Implementable in WASM 1.0 using structured `block`/`br` chains for non-local exit, without requiring the WASM exception handling proposal. Medium complexity — needs stack unwinding logic and cleanup semantics. Not needed for Phase 1 (halt-on-error is sufficient), but a reasonable addition for later phases where robust error handling matters. A good candidate for a student extension project.

*Implicit success/failure flag (SNOBOL/Icon style): rejected.* Investigated adding a hidden one-bit success/failure flag to every function return, with a `fail` keyword to signal "no result." The flag would OR into a block-local accumulator and bubble up the call stack; loop constructs (`while`, `for`) would break on accumulated failure. Implementation cost in WASM is low (one global or local `i32`), and it sits in a useful sweet spot between error codes and full exceptions — no stack unwinding, no exception types, just a propagating bit. However, the concept is harder to explain to language users than it is to implement. SNOBOL's model relies on goto-based flow that is alien to structured programming; Icon's goal-directed evaluation is powerful but its silent-failure-by-default caused well-documented debugging problems (Tratt 2010). The mechanism would add a non-obvious implicit control flow path to every function call, which conflicts with Compact Pascal's goal of being approachable and predictable. If lightweight error signaling is needed in the future, explicit result types or simple exceptions are more conventional and easier to teach. See `notes/snobol.md` and `notes/icon.md` for detailed research on the SNOBOL/Icon models.

*`defer` (Go/Zig style): rejected.* Go's function-scoped `defer` requires a runtime defer stack with heap allocation — incompatible with pre-Phase 6 (no heap) and awkward in single-pass compilation. Zig's block-scoped variant is deterministic at compile time but still requires buffering deferred code and emitting it at every scope exit, complicating single-pass emission. More fundamentally, `defer` solves cleanup (closing files, freeing memory, releasing locks), and there is little to clean up before Phase 6. For cleanup after Phase 6, `goto`-to-label is sufficient — the pattern is proven in decades of Linux kernel C and maps cleanly to WASM's structured `br` instructions. No special language feature needed.

*Operator overloading: possible future extension.* Low implementation complexity — syntactic sugar that maps operator tokens to function calls via the symbol table. Compatible with single-pass compilation. Low priority because Compact Pascal's type system is simple enough that operator overloading has few compelling uses beyond cosmetic convenience. Interesting as a student project.

*Pattern matching: possible future extension.* An extended `case` statement with destructuring (matching record fields, nested variants) is compatible with single-pass parsing and would improve ergonomics for code that currently uses nested `if`/`case` chains. Medium complexity. Not needed for the core language but a natural extension point for students exploring language design.

### Constants and compile-time evaluation

**Constant expressions in `const` declarations.** Untyped constants (`const a = 1; b = a + 10;`) support compile-time constant expressions that may reference previously declared constants. This is standard Turbo Pascal behavior (also in FPC, Delphi, and IP Pascal). Implementation requires a `EvalConstExpr` function — a compile-time expression evaluator that walks the expression, resolves `skConst` symbol references to their stored values, evaluates arithmetic/boolean/comparison operators, and returns the result without emitting WASM. Structurally similar to `ParseExpression` but produces a value instead of code. Supported operations: integer arithmetic (`+`, `-`, `*`, `div`, `mod`), boolean operators (`not`, `and`, `or`), comparisons, `ord`, `chr`, `odd`, `abs`, parentheses, and references to previously declared constants. String constant expressions (concatenation of string/char constants) are a natural extension.

**Structured typed constants: TP syntax, no extensions needed.** Typed constants for records, arrays, sets, and nested structures use TP's initializer syntax: `(field: value; field: value)` for records, `(elem, elem, elem)` for arrays, `[elem, elem]` for sets. Fields must be in declaration order; all fields must be specified. This syntax has been unchanged across TP, Delphi, and FPC for 30+ years — neither added out-of-order fields, partial initialization, or designated initializers. IP Pascal's `fixed` keyword and C99's designated initializers are more flexible (out-of-order, partial init with zero-fill), but the TP baseline covers the practical cases: lookup tables, coordinate literals, keyword/opcode tables for self-hosting. Compact Pascal adopts the TP syntax as-is. Out-of-order or partial initialization could be considered later if real code demands it, but is not planned. The `{$J+/-}` directive (Delphi/FPC, controls typed constant mutability) is a reasonable future addition but not needed for Phase 1 where typed constants are always mutable (matching TP default behavior).

**Initialized variables (`var x: T = value`): adopted, Delphi convention.** Compact Pascal supports initialized variables in `var` declarations. This is a Delphi/FPC feature not present in Turbo Pascal. Semantics: global initialized variables are placed in the data segment with their initial value (same as typed constants mechanically). Local initialized variables reinitialize on each scope entry — the compiler emits initialization code at the top of the block. This is the natural WASM behavior since local stack frames are rebuilt each call, and it matches Delphi convention. Uses the same structured initializer syntax as typed constants for records/arrays. **Bootstrap note:** The compiler source (`cpas.pas`) must not use initialized variables since it must compile under fpc `-Mtp`, which does not support this syntax. This is a Compact Pascal extension only.

**Dynamic array typed constants: deferred to post-Phase 6.** FPC 3.2.0+ supports dynamic array typed constants (`const a: array of LongInt = (1, 2, 3)`) by placing backing data in the data segment with a static descriptor. Compact Pascal could adopt this when dynamic arrays are implemented (Phase 6+), but it requires distinguishing static-backed from heap-backed dynamic arrays to avoid freeing data segment memory. Not worth the complexity before dynamic arrays exist.

**Dynamic arrays: IP Pascal open-array unification (Phase 6).** Compact Pascal adopts IP Pascal's model where dynamic arrays are "containers" for static arrays. A type `array of T` (no bounds) is an open array that can hold either a heap-allocated buffer (via `new(a, N)`) or a reference to a static `array[lo..hi] of T`. A fat descriptor (pointer + lo + hi, 12 bytes) represents the array at runtime. `max` returns the upper bound. This solves the classic Pascal complaint that you can't write a procedure accepting arrays of different sizes — a `var a: array of integer` parameter accepts any integer array. When a dynamic array is passed to a parameter expecting a fixed-size array, a runtime bounds check verifies the dynamic array is at least as large as the expected type. Cost is one `i32.ge_u` + trap per call site.

**Strings are not dynamic char arrays.** IP Pascal defines `string = packed array of char`, unifying strings with dynamic arrays. This creates a semantic conflict: arrays have one size (allocation bounds), but strings have two (allocation capacity and content length). A `string[80]` holding `'Hi'` has 80 bytes of storage but 2 meaningful characters. Passing it as an `array of char` to something expecting a larger buffer would fail a bounds check even though reading 2 characters is safe. The bounds check can only enforce allocation size, not logical content length. TP/Delphi keep strings and arrays as distinct types, which avoids this confusion — the string carries its own length; the array carries its own bounds; neither pretends to be the other. Compact Pascal follows this separation: Phase 6 dynamic arrays use the IP Pascal open-array model for non-string types; Phase 6b strings remain a distinct type with separate length and capacity fields.

### Type system and data representation

**`real` type: deferred, scanner rejects.** The `real` type is deferred from Phase 1 (no `f64` support). The scanner recognizes real literal syntax (`3.14`, `1.0e10`) so it can produce a clear error message, but the compiler rejects them during semantic analysis. This avoids confusing parse errors when a user writes a real literal.

**Integer size.** `integer` is 32-bit (WASM `i32`), unlike TP/BP where `integer` is 16-bit. This is a minor compatibility break — programs that don't overflow 16-bit integers are unaffected. `longint` remains 32-bit (same as `integer` on this target) for source compatibility. `maxint` is 2147483647.

**Sub-32-bit types in WASM.** WASM only has `i32` and `i64`. Types like `byte`, `word`, `shortint` are stored as `i32` internally. Range masking (e.g., `i32.and 0xFF` for `byte`) is only emitted when `{$R+}` is enabled. Without range checks, these types behave as `i32` with no overhead. The compiler source itself avoids subrange types to keep Phase 1 simple.

**Enumerated types and subranges.** All ordinal types (enumerations, subranges, `byte`, `word`, `shortint`, `char`, `boolean`) are stored as WASM `i32` internally. No packing or smaller representations. Range checks are only emitted with `{$R+}`.

**Strings.** Phase 1 uses TP-style short strings (length byte + data, max 255 chars) as the only string type. Short strings need no allocator, live on the stack or in records, and are identical to fpc `-Mtp` strings — so the compiler source works on both without adaptation. A richer pointer+length string type with no size limit will be added in Phase 6b when dynamic allocation is available.

**A hybrid string layout** (pointer+length with a Pascal-compat length byte at offset -1) was considered and rejected for Phase 1. It requires maintaining two length fields in sync, creates a type split between "real strings" and "substrings/slices," and has no consumer in Phase 1 since there is no external Pascal code to interop with.

**String parameter passing.** Follows the Turbo Pascal convention. `const` and `var` string parameters are passed by reference (pointer). Only value parameters copy the string data. This avoids copying up to 256 bytes per call for `const`/`var` params and matches fpc `-Mtp` behavior.

**Set types: two-tier implementation.** `set of T` uses bitmap representation sized to the base type's ordinal range, up to 256 bits (32 bytes). Two tiers based on element count:

*Small sets (≤32 elements):* Stored as a single `i32`. Operations compile to single WASM instructions: `+` → `i32.or`, `*` → `i32.and`, `-` → `i32.and(not)`, `in` → `i32.shl` + `i32.and`, `=`/`<>` → `i32.eq`/`i32.ne`, `<=` (subset) → `and(not) = 0`, `>=` (superset) → swap + subset. Covers `set of 0..31`, small enums, and similar.

*Large sets (>32 elements, up to 256):* Stored as 32-byte arrays in the stack frame. Needed for `set of char` (256 elements). The `in` operator uses byte-level bit testing: `byte_index = elem >> 3`, `bit_pos = elem & 7`, load byte at `set_addr + byte_index`, shift right by `bit_pos`, AND with 1. Large set arithmetic operations (`+`, `*`, `-`, comparisons) use WASM helper functions (slots 16–20) that loop over 8 i32 words: `__set_union` (OR), `__set_intersect` (AND), `__set_diff` (AND NOT), `__set_eq` (word-by-word compare), `__set_subset` (a AND NOT b = 0). Two 32-byte temp buffers with flip strategy handle compound expressions (e.g., `s1 + s2 = s3 + s4`). A static 32-byte zero block (`addrSetZero`) handles empty set `[]` compatibility with large set operations and assignments.

*Constant set constructors:* Set expressions where all elements are compile-time constants are fully evaluated at compile time. For small sets, the result is a single `i32.const(bitmap)`. For large sets, the bitmap is stored in the data segment and referenced by address. This is the common case for character classification (`['0'..'9']`, `['a'..'z', 'A'..'Z']`).

*String-to-char coercion:* Single-character string literals (`'A'`) are `tyString` in the expression evaluator (to avoid breaking string concatenation). At the `in` operator and in char assignment contexts, the compiler emits a coercion that loads the character byte from `string_addr + 1` (skipping the Pascal length byte).

**Variant records.** Supported via `case` tag in records. Variants share memory at the same offset; record size is the largest variant. Tag is a normal field. Maps directly to WASM linear memory (just overlapping offsets). Useful for the compiler's symbol table entries.

**Calling convention keyword (future).** A `pascal` keyword (analogous to `cdecl`/`stdcall` in TP/Delphi) was discussed for marking parameters that use Pascal string convention vs a future pointer+length convention. Deferred until Phase 6b when a second string type exists.

**Go-style interfaces: representation trade-off.** Inline vtable (Self + N function pointers) chosen for simplicity. Shared itable optimization deferred.

### WASM code generation

**WAT vs direct WASM binary emission.** Rejected WAT in favor of direct binary emission. WASM binary is simpler to emit. Section-ordering solved by buffering each section in memory during the single pass.

**Units and separate compilation: WASM custom sections.** Compiled units will be standard `.wasm` files with a `compact-pascal-meta` custom section containing type metadata (exported type definitions, procedure/function signatures, exported constants, and optionally inline function bodies). This keeps each unit as a single file that standard WASM tools (`wasm-validate`, `wasm-objdump`, browser devtools) can still inspect. When compiling a unit that imports another, the compiler reads the dependency's `.wasm` file and extracts type info from its custom section. The host performs module linking at instantiation time by connecting WASM imports to exports — no custom linker needed.

*Alternatives rejected:* Sidecar files (`.cpsi` alongside `.wasm`) add file management burden for no real benefit — the metadata is tiny relative to the code, and a single file means `cp` copies everything. A new object format would require a custom linker, custom dumper, and abandon the WASM ecosystem. Source-only recompilation (`{$INCLUDE}`) is the Phase 1 fallback but doesn't scale to larger projects.

*WASM Component Model:* The official WASM answer to module composition is still evolving and not universally supported. The custom section approach works today on all runtimes. If the Component Model stabilizes, units could optionally target it in a future phase.

*Phase 1:* No units. Single-file programs only. `{$INCLUDE}` handles code reuse. The `{$DESCRIPTION}` directive already writes a custom section, so the mechanism exists.

**WASI preview 1 I/O interface.** Adopted standard WASI preview 1 signatures for I/O: `fd_read`, `fd_write` (iovec-based), and `proc_exit`, imported from `wasi_snapshot_preview1`. Originally considered a simplified non-WASI interface (`fd_write(fd, buf, len)`), but switched to real WASI because: (1) the iovec overhead is trivial — the compiler always passes a single iovec (`iovs_len = 1`), which is just two `i32.store` instructions; (2) standard WASI means the compiler and compiled programs run directly under `wasmtime`/`wasmer` with no custom host; (3) the test suite needs no custom harness — `wasmtime run test.wasm` works out of the box. Compiled programs that use `write`/`writeln`/`read`/`readln` are also WASI-compatible. Programs with no I/O have no WASI imports. The compiler itself also uses `args_sizes_get` and `args_get` to read command-line flags (e.g., `-dump`).

**WASI file I/O and playground stdin (Phase 5).** Four design decisions made for the playground's WASI plumbing:

(1) *Interactive stdin uses SharedArrayBuffer + Atomics.wait().* The simpler alternative (pre-load all stdin before running) was rejected — users expect interactive programs where they type input and see output interleaved. SharedArrayBuffer requires COOP/COEP headers; GitHub Pages gets these via the `coi-serviceworker` pattern (a service worker that injects the headers).

(2) *Filename scratch area is a global in the data segment, not in the file variable.* File variables are 8 bytes (fd + mode + padding), stack-allocated. The filename is only needed transiently during `assign` + `reset`/`rewrite`. A single 260-byte global scratch buffer holds the filename for `path_open`. This avoids 262-byte file variables and sidesteps the need for heap allocation. `__str_assign` is not used because `path_open` wants a raw pointer + length, not a Pascal string. Instead, `memory.copy` copies the string data (skipping the length byte) and the length byte value is passed separately.

(3) *Limited file I/O added before Phase 6.* Text files only (`text` type), stack-allocated file variables, no `file of record`. This makes the playground useful for teaching file I/O without requiring dynamic allocation. It also exercises the WASI path_open/fd_close codegen paths early, making Phase 6's `file of record` easier to add later.

(4) *Flush on each fd_write call.* Every write to a file-backed editor tab is immediately posted to the main thread. This is not high-performance but gives the least surprising user experience — output appears as the program produces it, not when the file is closed.

**Playground fd_dir model.** The WASM side maintains a table of 26 directory root globals (A: through Z:, like drive letters), all initialized to -1 except A: which is fd 3 (the pre-opened editor root). Programs pass `fd_dir_A` (global, value 3) as the first argument to `path_open`. The playground runtime pre-opens fd 3 as a virtual directory whose "files" are editor buffers. Phase 5 only uses A:. The other 25 slots are reserved for future use (e.g., B: for a read-only samples directory).

**WASM linear memory layout.** Industry-standard layout, matching LLVM/Rust/C WASM compilers:

```
[ nil guard | data segment (globals, string literals) | heap → ... ← stack ]
0           4                                          data_end    SP   memory_top
```

- **Nil guard:** First 4 bytes reserved (zeroed). Dereferencing `nil` (address 0) reads zeros rather than corrupting data.
- **Data segment** at low addresses — global variables, string literals, typed constants. Laid out by the compiler during compilation.
- **Heap** grows upward from end of data segment (Phase 6; unused in Phase 1).
- **Stack** grows downward from top of memory. In Phase 1, the entire space between data end and memory top is stack.
- **Stack pointer** is a mutable WASM global (`$sp`), initialized to the top of memory. Frame allocation: `$sp -= frame_size`. Frame deallocation: `$sp += frame_size`.

This layout is battle-tested across WASM toolchains, compatible with debugging/profiling tools, and sets up cleanly for Phase 6 heap allocation (heap and stack grow toward each other).

Stack-grows-up was considered and rejected: non-standard, overflow behavior is worse (runs off end of memory rather than hitting a known boundary), and tools don't expect it.

**Nested procedures: display with WASM globals.** Pascal supports nested procedures that access enclosing scope variables (upvalues). WASM has no closures and all functions are top-level, so a mechanism is needed.

*Approach chosen: Dijkstra's display technique.* A fixed-size array of 8 WASM globals (`display[0]` through `display[7]`) where `display[N]` holds a pointer to the frame at nesting level N. Accessing an upvalue at level M is always exactly two loads: read `display[M]` to get the frame pointer, then load the variable at its offset within that frame. O(1) regardless of nesting depth.

*Why display over static links:* The alternative is a static link (hidden parameter pointing to parent frame), requiring O(depth) pointer chasing per upvalue access. The display is faster, simpler, and avoids adding hidden parameters that would complicate WASM function signatures, `{$EXPORT}`/`{$IMPORT}`, and procedural types.

*Zero overhead for non-nested procedures:* The compiler tracks nesting depth during parsing. Top-level procedures (level 0) emit no display code at all — no save, no restore, no global access. Only procedures at nesting level ≥ 1 emit the save/restore protocol:

```
; entry to procedure at level N:
saved := display[N]        ; global.get
display[N] := frame_ptr    ; global.set

; ... body (upvalue at level M: global.get display[M], then i32.load offset) ...

; exit:
display[N] := saved        ; global.set
```

That is 3 extra WASM instructions per nested procedure call. In practice, the vast majority of procedures are top-level and pay nothing.

*Maximum nesting depth of 8.* Real Pascal code rarely nests beyond 3-4 levels. The compiler emits a clear error if the limit is exceeded. 8 WASM globals is negligible.

*Recursion is handled correctly* because each entry saves and restores `display[N]`. Recursive calls at the same level see the correct frame.

### Compiler architecture

**Single-pass recursive descent with precedence climbing for expressions.** The compiler parses and emits WASM binary in a single pass — no AST, no IR. Each `ParseStatement` / `ParseExpression` call emits directly to WASM section buffers (code, data, type, etc.). This keeps the compiler small enough to self-host in Phase 1.

**Expression parsing uses precedence climbing (Pratt-style)** rather than the classic Wirth cascade of `ParseFactor` / `ParseTerm` / `ParseSimpleExpression` / `ParseExpression`. A single `ParseExpression(minPrec)` function handles all binary operators via a precedence table lookup in a while loop. This means fewer procedures (less code to self-host), and adding operators in later phases is trivial. Still recursive descent — just the expression core uses a loop. Fully implementable in TP Pascal.

**Scanner is a separate tokenizer.** A `NextToken` procedure fills a current-token record (kind, value, line, col). The parser never touches raw characters. One token of lookahead is sufficient — Pascal's grammar is LL(1) with minor exceptions (e.g., `id` vs `id(`) resolved by the next token.

**Symbol table: linear search with scope stack.** A single flat array of symbol-entry records, with a scope index marking where each scope begins. Entering a scope pushes a marker; leaving a scope resets the index, discarding local symbols in O(1). Lookup walks backward from the top (most-local-first). This is the classic TP compiler technique — no dynamic allocation, trivially correct scope semantics, and fast enough for expected program sizes. Critbit trees and hash tables were considered but rejected: tree structures fight Pascal's nested-scope enter/exit pattern, and the expected symbol table sizes (hundreds of entries, not thousands) don't justify the complexity.

**Code generation is interleaved with parsing.** No separate code-gen pass. This is what makes true single-pass compilation possible and keeps memory usage minimal — critical for running the self-hosted compiler inside a WASM interpreter with limited linear memory.

**WAT pseudo-code in comments.** Every procedure that emits WASM binary opcodes includes a comment showing the equivalent WebAssembly Text (WAT) instruction. This makes the binary emission code self-documenting — a reader can see what WASM instruction sequence the compiler intends to produce without mentally decoding hex opcodes. It also serves the tutorial: each code generation routine is a worked example mapping Pascal semantics to WASM instructions. For example:

```pascal
{ ;; WAT: i32.add }
EmitByte($6A);

{ ;; WAT: local.get $sp
  ;;      i32.const <offset>
  ;;      i32.add
  ;;      i32.load }
EmitByte($20); EmitULEB(spLocal);
EmitByte($41); EmitSLEB(offset);
EmitByte($6A);
EmitByte($28); EmitByte($02); EmitULEB(0);
```

**WASM function index allocation.** WASM function indices are a single flat namespace: imports occupy indices 0..numImports-1, then defined functions follow. The compiler pre-registers all WASI imports (fd_write, proc_exit) at initialization so `numImports` is stable before any code emission. Defined function slots are: 0 = `_start`, 1 = `__write_int` (always reserved, empty stub if unused), 2+ = user-defined procedures/functions. This fixed-slot layout avoids a class of bugs where lazily-added imports shift defined function indices after call instructions have already been emitted. User function slots are allocated sequentially as declarations are parsed.

**Forward declarations need no second pass.** Pascal's `forward` keyword and declaration-before-use rule mean one pass is sufficient. Forward-declared procedures get a symbol table entry with a placeholder code offset; when the body appears, the placeholder is patched. WASM simplifies this since function indices are assigned up front in the type/function sections.

**Procedure/function code emission.** During declaration parsing, procedure/function bodies are compiled into the `startCode` buffer (which is empty at declaration time since the main begin..end hasn't started). After compilation, the body bytes are copied to a `funcBodies` accumulation buffer, and `startCode` is restored for subsequent declarations or the main block. At assembly time, function bodies are emitted in slot order: _start, __write_int, then user functions. Parameters are WASM locals (not stack frame variables); the function return value uses a hidden extra WASM local at index `nparams`. Assignment to the function name in Pascal (`FuncName := expr`) maps to `local.set` on this hidden local; the function epilogue emits `local.get` to push the return value onto the WASM stack.

**Error strategy: halt on first error.** Most lightweight for single-pass. No recovery logic, no cascading false positives.

**Command-line arguments via WASI `args_get`.** The compiler uses WASI `args_sizes_get` and `args_get` to read command-line arguments (e.g., `-dump`). This is standard WASI and works under `wasmtime run compiler.wasm -- -dump < source.pas`. The host embedding libraries pass arguments through the WASI interface when invoking the compiler.

**Integer-to-string conversion for `write`.** `write(42)` needs decimal conversion. The compiler reserves a 66-byte scratch buffer in the data segment (enough for 64 binary digits, a sign, and a null terminator). When the compiler first encounters an integer `write` argument, it emits a conversion routine as an internal WASM function; subsequent integer writes reuse it. The buffer is safe to share because `write`/`writeln` are not reentrant — they emit directly to `fd_write` before returning. This is straightforward for the single-pass compiler: the first integer write emits the helper function into the function section buffer and records its index; later writes just call it.

**`readln` line buffering.** Phase 1 uses a small fixed-size read buffer in the data segment. `readln` reads bytes via WASI `fd_read` until a newline or buffer exhaustion. The buffer needs to be large enough for the largest token the compiler might read (for self-hosting: identifier names, string literals, integer literals — a 256-byte buffer is sufficient). Byte-at-a-time reads via `fd_read` with a 1-byte buffer are an alternative but slower; a small buffer with scan is preferred.

**Compiler stderr tags.** All compiler stderr output is prefixed with a tag (`Error:`, `Warning:`, `Info:`, `Debug:`, `Progress:`) so the host embedding library can parse diagnostics mechanically. Phase 1 uses at minimum `Error:`. The `Progress:` tag has a fixed `done/total` integer format (e.g., `Progress: 20/100 Analyzing...`) so hosts can display a progress bar without parsing free text. This convention costs nothing to implement (just a string prefix on each `writeln(stderr, ...)` call) and makes the compiler output machine-friendly from day one.

**Debugging support: name section, no DWARF.** The compiler emits a WASM name section (custom section `"name"`) mapping function indices to their Pascal names. This is trivial to emit and gives human-readable function names in stack traces, profilers, and browser DevTools. Full DWARF debug info is not planned — it is complex to emit, and the compiler tutorial will cover source-level tracing via the `-dump` flag and WAT pseudo-code comments instead. Browser source maps may be added in Phase 4 for the browser playground. A simple source line table (compact array of `(wasm_offset, source_line)` pairs in a custom section) may be added in Phase 2 so the embedding library can report "error at line N" when a WASM trap occurs.

**Documentation comments (fpdoc).** The compiler source uses fpdoc-style `{**` comments. Every procedure and function gets a doc comment immediately before its declaration. fpdoc is Free Pascal's documentation generator; its comment syntax (`{** ... }`) is recognized by fpc and ignored by TP-mode compilation, so it costs nothing for self-hosting compatibility.

*Minimum documentation:* Every procedure/function gets a one-line summary. Core routines that implement non-obvious algorithms get expanded comments explaining the algorithm, invariants, and data flow. The following routines are specifically flagged for detailed documentation:

- **`ParseExpression` (Pratt parser):** Explain precedence climbing, the precedence table, how prefix/infix are dispatched, and the `minPrec` parameter contract.
- **`NextToken` (scanner):** Document the token record layout, how string literals and comments handle high bytes (UTF-8 pass-through), and the one-token lookahead model.
- **`EnterScope` / `LeaveScope` (symbol table):** Explain the flat-array-with-scope-markers technique, backward lookup order, and O(1) scope exit.
- **`EmitWasm*` (code generation):** Document the section buffer model — how deferred output works, when buffers are flushed, and the section ordering constraint.
- **`EmitDisplay` / upvalue access (nested procedures):** Explain the Dijkstra display technique, the 8-global array, and when display code is emitted vs skipped.

*fpdoc comment syntax:*

```pascal
{** One-line summary of what this procedure does.

  Longer description for complex routines. Explain the algorithm,
  invariants, parameters, and any non-obvious behavior.

  @param Name description of parameter
  @returns description of return value (for functions)
}
procedure DoSomething(Name: string);
```

fpdoc tags (`@param`, `@returns`) are optional — use them when the parameter names alone are not self-explanatory. Plain prose is preferred over mechanical `@param` listings for every trivial parameter.

**Tutorial: Phase 1 as a teachable compiler.** The Phase 1 compiler doubles as the subject of a step-by-step compiler construction tutorial (`doc/compact-pascal-tutorial.md`). Phase 1 is the right target because: (1) it is a complete, working compiler with a small enough feature set to cover end-to-end; (2) single-pass recursive descent targeting a stack machine (WASM) is a natural pedagogical architecture — WASM's operand stack maps directly to expression evaluation, so students see parsing and code generation connect without register allocation or SSA; (3) stack-only allocation, no `real` type, and short strings eliminate distractions; (4) WASM output is a modern hook — students get binaries that run in browsers and wasmtime, not a toy VM. The tutorial chapters mirror the implementation order (lexer → expressions → statements → procedures → nested scopes → strings → records/arrays), with each chapter producing a compiler that handles a larger subset. Where self-hosting needs pull a feature forward (e.g., `case` statements needed in the scanner before records are covered), the tutorial treats this as a teachable moment — explaining why a real compiler's requirements shape the build order.

**Doc pass (2026-04-18): fpdoc headers added, inline WAT comments deferred.** Added `{** ... }` fpdoc headers to all Phase 1 procedures/functions in `compiler/cpas.pas`, with expanded prose on the flagged routines (`NextToken`, `EnterScope`/`LeaveScope`, `ParseExpression`, `EmitFramePtr`, `EmitVarParamPtr`, `EmitWriteInt`) and WAT-style one-liners on all 26 `Emit*` headers. Committed in seven subsystem-scoped commits (scanner, diagnostics, symbol table, buffers/LEB, parser, codegen, driver). The inline `{ ;; WAT: ... }` annotation pass on the ~1,254 emission call sites was not done — the emitter headers now document the WAT shape, which gets most of the pedagogical value; annotating every call site would add noise without proportionate payoff. If the tutorial chapters end up wanting per-site WAT asides, that can be a later targeted pass rather than a blanket sweep. Build and 88-test suite still clean.

### Peephole optimization

**Peephole optimizer: optional, compile-time gated.** The optimizer is wrapped in `{$IFDEF PEEPHOLE}` so it adds zero bytes to the compiler WASM image when not defined. When compiled in, it defaults to enabled (`-O1`) and can be disabled at runtime (`-O0`) or toggled per-region with `{$OPT+/-}`. When peephole is not compiled in, `-O0`/`-O1` and `{$OPT}` are silently ignored. This keeps the base compiler small and gives students a clean on-ramp — build the compiler first, add optimization later.

**Requires `-dSYMBOL` flag in cpas.** The compiler needs a `-dSYMBOL` command-line option (like fpc) to define conditional compilation symbols via WASI `args_get`. This is how `PEEPHOLE` gets defined when self-hosting: `wasmtime run compiler.wasm -- -dPEEPHOLE < cpas.pas > cpas-opt.wasm`. The `-d` flag is independently useful for any conditional compilation, not just peephole.

**Sliding window on code buffers, not a separate pass.** The optimizer hooks into the emit path — `TryPeephole` is called after each opcode is appended to the code buffer. It checks whether the trailing bytes match a known pattern and rewrites in place by rewinding the buffer write pointer. No second pass, no extra memory, no changes to the rest of the compiler.

**Switch/case pattern matcher, not hash-based.** The pattern set for a WASM stack machine is small (10-20 patterns). A switch/case on trailing opcode bytes is transparent, needs no external tooling, and students can read and understand every pattern. A hash table or gperf-generated perfect hash would scale better but is not justified at this size. If the pattern set grows past ~20 entries, refactoring to a hash table is straightforward.

**Window size is a tunable constant.** Two instructions covers the highest-frequency pattern (`local.set/get → tee`), but longer windows are needed for constant folding (3 instructions) and for collapsing pathological sequences produced by single-pass codegen — repeated spill/reload, redundant address computation, nested store-then-load chains. The window size is a compile-time constant (`const PeepWindow = ...`) so students can experiment. The matcher only looks back as far as the longest known pattern.

**Instruction reordering: deferred.** Commutativity-aware reordering (e.g., recognizing `i32.const 0 / local.get X / i32.add` as a no-op by swapping operand order) could collapse some pathological sequences, but adds complexity and risks changing semantics across effectful operations. Better to observe real codegen patterns first and add reordering rules only where data justifies it.

**Strength reduction included as historical teaching point.** Replacing power-of-two multiplies with shifts (`i32.const 2 / i32.mul` → `i32.const 1 / i32.shl`) saves zero bytes and is almost certainly redundant — modern WASM JITs (V8, SpiderMonkey, wasmtime) recognize this pattern internally. It is included because it was a significant optimization on real hardware from the 1970s through 1990s, the era of Pascal's heyday, and it teaches students about the relationship between compiler optimization and runtime optimization: the same transform can matter on one layer and be redundant on another.

**Tutorial placement: appendix.** The peephole optimizer is covered in an appendix to the tutorial book, not a numbered chapter. It is a completely optional exercise. The appendix covers stack-machine redundancy patterns, the sliding-window technique, conditional compilation as a real-world technique, and the compiler-size vs output-quality trade-off.

**Research notes:** `notes/research-peephole.md` — detailed pattern tables, open questions on pathological codegen sequences, cascading rewrite strategy.

### Toolchain and self-hosting

**Bootstrap dialect: fpc `-Mtp` as stepping-stone.** TP 7.0 mode is the most restrictive fpc dialect, which is a feature — if the compiler source compiles under `-Mtp`, it almost certainly compiles under Compact Pascal too. A more permissive mode (`-Mobjfpc`, `-Mdelphi`) would risk accidental use of features not in Compact Pascal (`Result`, ansistrings, classes, overloads), creating self-hosting surprises. The only friction is `integer` being 16-bit in TP mode vs 32-bit in Compact Pascal; the compiler source uses `longint` (32-bit in both) to avoid this. Other costs are minor: assigning to function name instead of `Result` (standard Pascal anyway), no operator overloading (not needed). The restrictive mode serves as a guardrail that keeps the compiler source within the Compact Pascal subset. Note: real TP compatibility is not a goal — fpc `-Mtp` is a stepping-stone to self-hosting. Where TP mode constraints conflict with the self-hosting path, self-hosting wins.

**I/O abstraction: `BlockRead`/`BlockWrite` unified path.** The compiler source uses standard Pascal `BlockRead`/`BlockWrite` for all byte-level I/O. These are in the System unit (no `uses` clause needed), available on every fpc platform (Linux, macOS, Windows), and work in `-Mtp` mode.

- **fpc bootstrap:** Real `BlockRead(f, buf, count, result)` / `BlockWrite(f, buf, count, result)` on real `file` variables. `Input` and `Output` are already open. Stderr needs one `Assign`/`Rewrite` at init. This replaces the current `read(input, ch)` approach, which is text-mode and unsuitable for binary output.
- **Self-hosted Compact Pascal:** The compiler treats `file` as an alias for `longint` (the fd number). Predefined handles are constants: `Input = 0`, `Output = 1`, `StdErr = 2`. `BlockRead`/`BlockWrite` become compiler intrinsics that build a single iovec in scratch memory and call WASI `fd_read`/`fd_write`. `Assign`/`Reset`/`Rewrite` are recognized and emitted as no-ops — the compiler source never opens arbitrary files (source comes from stdin, output goes to stdout), so only the three predefined fd values are ever used.

This is simpler than the earlier `fpRead`/`fpWrite` via `BaseUnix` design: no `uses` clause, no platform-specific ifdefs, no pointer type mismatch between native and WASM. The compiler source uses standard Pascal I/O vocabulary and the self-hosted compiler implements it as thin fd wrappers. The fpc bootstrap path works identically on Linux, macOS, and Windows.

**Backward compatibility and self-hosting constraints.** The compiler source must compile under both fpc `-Mtp` and Compact Pascal for self-hosting. This drives several decisions:

- **Standard functions and procedures:** `abs`, `ord`, `chr`, `odd`, `succ`, `pred`, `sqr`, `length`, `sizeof`, `lo`, `hi`, `inc`, `dec`, `exit`, `halt` are included as compiler intrinsics. These are trivial to implement (inline WASM ops) and critical for compatibility — both with existing Pascal idioms and for writing the compiler source.
- **Built-in I/O:** `write`/`writeln` and `read`/`readln` are compiler intrinsics that lower to WASI preview 1 `fd_write`/`fd_read` calls. This makes compiled programs WASI-compatible and runnable under `wasmtime` out of the box. The predefined file handles `input` (fd 0), `output` (fd 1), and `stderr` (fd 2) allow directing I/O to specific fds: `writeln(stderr, 'Error: ', msg)`.
- **Built-in I/O scope:** Phase 1 supports a minimal subset of `write`/`writeln` (integers, characters, strings) and `read`/`readln` (integers, characters). Format specifiers (`:width`, `:width:decimals`), booleans, and reals are deferred. `write`/`writeln` always target stdout (fd 1). The compiler does not implement `write(stderr, ...)` as a language feature. Instead, the compiler source uses `WriteError`/`WriteErrorLn` wrapper procedures that are `{$IFDEF FPC}` switched: under fpc they call `writeln(stderr, s)`, under self-hosting they do WASI `fd_write` to fd 2 directly. Error messages are pre-formatted into a string using `Str()` and string concatenation before calling the wrapper. The `-dump` disassembler is wrapped in `{$IFDEF FPC}` and excluded from self-hosted builds.
- **Low-level I/O:** `BlockRead`/`BlockWrite` are the byte-level I/O primitives. Under fpc bootstrap they operate on real `file` variables. Under self-hosting they are compiler intrinsics wrapping WASI `fd_read`/`fd_write`. `Assign`/`Reset`/`Rewrite` are no-ops in self-hosted mode. See the I/O abstraction Finding for details.
- **TP numeric types:** `byte`, `word`, `shortint`, `longint` are included as aliases to WASM integer types. These are trivial to add and important for the compiler source.
- **Include file resolution:** `{$INCLUDE}` directives are resolved by the host application before invoking the compiler. The embedding library scans the source, expands includes by replacing the directive with file contents, and passes a single concatenated source stream to the compiler on stdin. This keeps the compiler's I/O interface minimal (three fds, no filesystem access). During fpc bootstrap, fpc handles `{$I}` natively. The Rust, Zig, and C libraries each provide a utility function for this — parsing `{$I 'filename'}` out of comments is straightforward.

**Rust, Zig, and C version targets.**

- **Rust MSRV: 1.85 (edition 2024).** This is the edition 2024 baseline and the minimum supported Rust version for the `compact-pascal` crate (set via `rust-version = "1.85"` in `Cargo.toml`). wasmi works on stable Rust; no nightly features are required. The MSRV can be bumped conservatively as needed.
- **Zig: 0.14.0 (latest stable release).** Zig is pre-1.0, so pinning to the latest stable release is standard practice. The C interop needed for wasm3 works on 0.14.x. The version should be documented in `build.zig.zon`. Expect to update when new Zig stable releases land; pinning to stable (not master/nightly) avoids unnecessary churn.
- **C: C99 or later.** The C embedding library targets C99 for maximum portability. No C11/C17 features required. The library has no WASM runtime dependency — users bring their own.

**Zig WASM runtime: wasm3 via C interop.** wasm3 (C library) chosen for Zig side. Zig-native interpreters are immature. Zig's `@cImport` makes C interop trivial. Parallels Rust's wasmi choice. **Risk:** wasm3 development has slowed significantly. If the project becomes unmaintained, alternatives include writing a minimal WASM interpreter in Zig or switching to another C-based runtime.

**Dynamic allocation: deferred to Phase 6.** `New`/`Dispose` and heap allocation deferred from Phase 1 to keep the core compiler minimal. Phase 1 uses stack-only allocation. Baker's Treadmill GC is a good fit for WASM (non-moving, incremental) but requires a shadow stack for root tracking — deferred further until after `New`/`Dispose` is working.

### Milestone 8: Records and arrays — `DONE`

**Overview.** Milestone 8 adds structured types: records, arrays, type declarations, `.field` and `[index]` selectors in designators, block copy for structured assignment via `memory.copy`, and structured parameters (var/const/value).

**Implementation order (completed):**

1. ~~Type descriptor table and `type` declarations~~
2. ~~Simple records (field access, assignment)~~
3. Variant records — deferred to Milestone 11
4. ~~One-dimensional arrays~~
5. ~~Multi-dimensional arrays (desugar to nested)~~
6. ~~Structured parameters (var/const/value with copy semantics)~~
7. ~~`write`/`writeln` support for record fields and array elements~~ (works naturally via designators)
8. `sizeof` intrinsic — deferred

**Tests:** t036–t044 (9 tests), covering record basic/nested, array basic/2d, array-of-record, record/array assignment, record/array params with all three calling conventions.

#### Step 1: Type descriptor table

The current type system uses integer tags (`tyInteger`, `tyBoolean`, `tyChar`, `tyString`). Structured types need metadata that doesn't fit in a single integer — records need field lists, arrays need bounds and element types. Add a type descriptor table alongside the symbol table.

**New constants:**

```pascal
const
  tyArray    = 5;
  tyRecord   = 6;
  MaxTypes   = 256;
  MaxFields  = 512;  { shared pool for all record types }
```

**New type descriptor record:**

```pascal
TTypeDesc = record
  kind: longint;      { tyArray or tyRecord }
  size: longint;      { total byte size }
  { Array fields: }
  elemType: longint;  { type tag of element (tyInteger, tyRecord, etc.) }
  elemTypeIdx: longint; { index into types[] for structured elements, -1 for simple }
  elemSize: longint;  { byte size of one element }
  arrLo: longint;     { lower bound }
  arrHi: longint;     { upper bound }
  { Record fields: }
  fieldStart: longint; { index into fields[] }
  fieldCount: longint; { number of fields }
  variantOfs: longint; { byte offset where variant part begins, -1 if none }
end;

TFieldDesc = record
  name: string[63];
  typ: longint;       { type tag }
  typeIdx: longint;   { index into types[] for structured fields, -1 for simple }
  offset: longint;    { byte offset from record start }
  size: longint;      { byte size }
  strMax: longint;    { for string fields }
end;
```

**Globals:**

```pascal
var
  types: array[0..MaxTypes-1] of TTypeDesc;
  numTypes: longint;
  fields: array[0..MaxFields-1] of TFieldDesc;
  numFields: longint;
```

**`TSymEntry` changes:** Add a `typeIdx` field (longint, default -1) that indexes into `types[]` when `typ` is `tyArray` or `tyRecord`. For simple types, `typeIdx` stays -1.

**`type` declarations:** Parse `type` section: `type Ident = TypeSpec;`. For each, add an `skType` symbol with `typ` set to the resolved type tag and `typeIdx` to the type descriptor index (or -1 for aliases to simple types). The existing `ParseVarDecl` type parsing must be refactored into a shared `ParseTypeSpec` that returns `(typ, typeIdx, size, strMax)`.

#### Step 2: Simple records

**Parsing:** When `ParseTypeSpec` sees `tkRecord`, parse `FieldList` per the grammar: `IdentList ':' Type { ';' IdentList ':' Type }` until `tkEnd`. Allocate a `TTypeDesc` with `kind = tyRecord`. For each field, add a `TFieldDesc` to the `fields[]` pool. Field offsets accumulate linearly with 4-byte alignment for i32 fields, 1-byte alignment for chars within strings. Total size is the sum of all field sizes (with alignment padding).

**Variable allocation:** In `ParseVarDecl`, when the type is `tyRecord`, allocate `types[typeIdx].size` bytes on the stack frame (with 4-byte alignment). The symbol's `size` field holds the total record size. The symbol's `typeIdx` points to the type descriptor.

**Field access (designator chaining):** This is the biggest refactor. Currently, assignment and expression evaluation handle variable access inline with lots of duplicated code for stack-frame vs var-param vs local. Milestone 8 introduces a **designator model**: after parsing an identifier, check for `.field` or `[index]` selectors and chain them.

The approach: after resolving a variable to its base address on the WASM stack, enter a selector loop:

```
while tokKind in [tkDot, tkLBrack] do
  if tkDot -> parse field name, emit i32.const(fieldOffset), i32.add
  if tkLBrack -> parse index expression, compute element offset, i32.add
```

This produces a final address on the WASM stack. For simple types, load the value (`i32.load`). For structured types, leave the address (records/arrays are always referenced by address in expressions, copied on assignment).

**Record assignment:** Whole-record assignment (`r1 := r2`) requires copying `size` bytes. Two options:

1. **`memory.copy` (WASM bulk-memory proposal):** Opcode `0xFC 0x0A 0x00 0x00`. Single instruction, efficient. Requires the runtime to support bulk-memory ops. wasmtime and wasmer both support this. This is the preferred approach.
2. **Byte-copy loop as a helper function:** Fallback if bulk-memory is not available. A `__mem_copy(dst, src, len)` helper emitted once on first use (same pattern as `__write_int`).

Use `memory.copy` — it's part of the WASM 1.0+ baseline that wasmtime/wasmer support, and it avoids emitting a helper function.

**Record comparison:** Records are not directly comparable in standard Pascal. No `=` or `<>` for records. (TP doesn't support it either.)

#### Step 3: Variant records

**Parsing:** When `ParseTypeSpec` encounters `tkCase` inside a record body, parse the variant part:

```
case [Ident ':'] TypeIdent of
  ConstList: (FieldList);
  { ';' ConstList: (FieldList) }
```

The tag field (if named) becomes a normal field at the current offset. Each variant's fields share the same starting offset (the offset after the tag). The record's total size is max(size of each variant) + offset of variant start.

**Codegen:** No special codegen — variant fields are just fields at overlapping offsets. The field table records each variant field with its offset. Field access is identical to regular fields. Tag checking (`{$R+}`) is deferred to milestone 10 with range checks.

**Case labels:** The case labels in variant declarations are parsed but not stored — they exist for documentation and future `{$R+}` tag checking. They don't affect code generation.

#### Step 4: One-dimensional arrays

**Parsing:** `array[lo..hi] of T`. Parse the subrange (`lo..hi` — integer constants for Phase 1), element type. Allocate a `TTypeDesc` with `kind = tyArray`, bounds, element type/size. Total size = `(hi - lo + 1) * elemSize`.

**Variable allocation:** Same as records — allocate `types[typeIdx].size` bytes on the stack frame.

**Array indexing:** In the designator selector loop, when `tkLBrack` is seen:

```
{ Stack has base address }
ParseExpression  { index value on stack }
EmitI32Const(lo)
EmitOp(OpI32Sub)       { normalize to 0-based }
EmitI32Const(elemSize)
EmitOp(OpI32Mul)       { byte offset }
EmitOp(OpI32Add)       { final element address }
```

For simple element types, follow with `i32.load`. For structured elements, leave the address.

**Bounds checking (`{$R+}`):** Deferred to milestone 10. Without it, out-of-bounds access corrupts memory silently (same as TP without `{$R+}`).

**Array assignment:** Whole-array assignment (`a := b`) uses `memory.copy` with the array's total size. Same mechanism as record assignment.

#### Step 5: Multi-dimensional arrays

`array[1..3, 1..5] of integer` desugars to `array[1..3] of array[1..5] of integer`. Parsing: when a comma follows a subrange inside `[`, parse the next subrange and nest. The outer array's element type is itself `tyArray` with a `typeIdx` pointing to the inner array's descriptor.

Multi-dimensional indexing works naturally through the designator loop: `a[i, j]` is equivalent to `a[i][j]` — the first index computes the address of the inner array, the second index computes the element within it. The parser can treat `a[i, j]` as syntactic sugar for chained indexing by processing each comma-separated index as a separate selector step.

#### Step 6: Structured parameters

**Record and array parameters** follow the same convention as strings:

- **`var` and `const` parameters:** Pass by reference (pointer). No copy.
- **Value parameters:** Copy the entire structure to the callee's stack frame. The caller pushes a pointer to the copy; the callee sees it as a local.

Actually, the simplest approach for value params of structured types: the caller pushes a pointer to the original, and the callee copies it into its own frame on entry. This matches how string value params work.

For `var`/`const` params of structured types: pass the address directly, same as strings.

The `ParseVarDecl` and `ParseProcDecl` parameter handling code needs to recognize structured types and apply reference-passing semantics.

#### Step 7: `write`/`writeln` for structured type fields

No special work needed. Once designators chain `.field` and `[index]`, individual fields/elements of simple types can be passed to `write`/`writeln` naturally. The result of `r.x` where `x: integer` is an integer value on the stack, which `write` already handles.

#### Step 8: `sizeof` intrinsic

`sizeof(T)` or `sizeof(v)` returns the byte size of a type or variable at compile time. For simple types: 4 (i32). For strings: `strMax + 1`. For structured types: `types[typeIdx].size`. Emits as `i32.const(size)`. Useful for self-hosting (buffer sizing, memory layout).

#### Refactoring plan: designator-based variable access

The biggest code change is introducing designator chaining. Currently, variable load/store code is duplicated across `ParseStatement` (assignment) and `ParseExpression` (variable read), with separate branches for stack-frame vars, var params, and WASM locals. Each branch handles the full address computation.

**New approach:** Extract an `EmitDesignator` procedure that:

1. Takes a symbol index.
2. Emits the base address (handling stack-frame, var-param, and local cases).
3. Enters a selector loop for `.field` and `[index]`.
4. Returns the final type info (type tag, typeIdx, size, strMax).

Callers then decide what to do with the address:
- **Assignment:** emit `i32.store` (simple) or `memory.copy` (structured).
- **Expression:** emit `i32.load` (simple) or leave address on stack (structured, since they're always passed by address).

This consolidates the duplicated address-computation code and makes all future selectors (pointer dereference, `with` fields) easy to add.

**WASM local variables:** Currently, `var` and `const` params of simple types use WASM locals (negative offset encoding). For structured types, even parameters need to go through the stack frame (since WASM locals can only hold i32/i64/f32/f64, not multi-byte structures). This is already how string params work — the local holds a pointer. The same pattern applies to record and array params.

#### Test plan (actual)

**Records (milestone 8):**
- `t036_record_basic.pas` — basic record: declare, assign fields, read fields, write fields
- `t037_record_nested.pas` — record with record field, chained `.` access
- `t041_record_assign.pas` — whole-record assignment (block copy)
- `t043_record_param.pas` — record as procedure parameter (var, const, value)

**Arrays (milestone 8):**
- `t038_array_basic.pas` — basic array: declare, assign elements, read/write
- `t039_array_record.pas` — array of records and record with array field
- `t040_array_2d.pas` — two-dimensional array
- `t042_array_assign.pas` — whole-array assignment
- `t044_array_param.pas` — array as procedure parameter

**Constants, enums, case, sets, standard functions (milestone 9):**
- `t045_const_basic.pas` — untyped constants with compile-time expressions
- `t046_const_string.pas` — string constants
- `t047_enum.pas` — enumerated types
- `t048_case_basic.pas` — case statement with integer/ranges/else
- `t049_case_char.pas` — case statement with char selectors
- `t050_std_funcs.pas` — abs, ord, chr, odd, succ, pred, sqr, sizeof, lo, hi
- `t051_inc_dec.pas` — inc and dec procedures
- `t052_set_basic.pas` — small set operations (union, intersection, difference, `in`)
- `t053_set_compare.pas` — set comparison operators (=, <>, <=, >=)
- `t054_set_char.pas` — large set (`set of char`) with `in` and constant constructors

**Directives, short-circuit, with, casts, extended literals, checks, init vars (milestone 10):**
- `t055_memory_directive.pas` — `{$MEMORY}` directive
- `t056_description.pas` — `{$DESCRIPTION}` directive
- `t057_stacksize.pas` — `{$STACKSIZE}` directive
- `t058_short_circuit_and.pas` — `and then` short-circuit evaluation
- `t059_short_circuit_or.pas` — `or else` short-circuit evaluation
- `t060_short_circuit_sideeffect.pas` — short-circuit side effect verification
- `t061_with_simple.pas` — simple `with` statement
- `t062_with_nested.pas` — nested `with` statement
- `t063_with_multiple.pas` — `with` with multiple record variables
- `t064_cast_chr_to_int.pas` — `integer(ch)` type cast
- `t065_cast_int_to_char.pas` — `char(n)` type cast
- `t066_cast_byte_mask.pas` — `byte(n)` masking cast
- `t067_extlit_hex.pas` — `{$EXTLITERALS ON}` hex (`0xFF`)
- `t068_extlit_octal.pas` — `{$EXTLITERALS ON}` octal (`0o77`)
- `t069_extlit_binary.pas` — `{$EXTLITERALS ON}` binary (`0b1010`)
- `t070_range_array_ok.pas` — `{$R+}` array bounds check (in-range)
- `t071_range_array_fail.pas` — `{$R+}` array bounds check (out-of-range, expected trap)
- `t072_range_disabled.pas` — `{$R-}` no range check
- `t073_overflow_add.pas` — `{$Q+}` overflow check (overflow, expected trap)
- `t074_overflow_ok.pas` — `{$Q+}` overflow check (no overflow)
- `t075_overflow_disabled.pas` — `{$Q-}` no overflow check
- `t076_var_init_global.pas` — global initialized variables
- `t077_var_init_local.pas` — local initialized variables (reinitialize on scope entry)
- `t078_var_init_string.pas` — initialized string variables

**Negative tests:**
- `n001_constparam_assign.pas` — assignment to const parameter rejected
- `n002_external_no_import.pas` — external procedure without `{$IMPORT}` rejected
- `n003_var_init_multi.pas` — initialized variable with multiple names rejected

#### Examples

##### Rust: Pode Server

Node-like Pascal server with Rust backend.

##### Zig: Compact Pascal IDE

Using zig-webui and the Playground javascript as a starting point. Implement an IDE with a Zig backend to handle the wasm runtime.

Zig's runtime provides local file access, so that the editor windows can read/write files as normal.
Wasm runtime is still in a sandbox by default.

##### C: To Be Determined

Possibilities:

- Tool to generate native command-line wrappers of wasm3+runtime. outputs stubs for gcc/clang (in .c) exporting the bare minimum to the app's runtime. A sort of mini-linker in C that assists in creating wasm-in-a-native bundle. This makes it possible to run 'cpas' at the command-line, or turn any of the .wasm output from cpas into a stand-alone command-line utility. (glibc or musl linked)

#### Releases

On tag (e.g. v1.2.3), release a set of packages on the Github release page.

- ZIP with PDFs: White Paper, Reference(s), and Tech Notes.
- ZIP with Rust release.
- ZIP with C release.
- ZIP with Zig release.
- ZIP with only the wasm binaries for the compiler.
- ZIP of the Playground website ready for people to deploy locally.

#### Dependencies and risks

- **`memory.copy` support:** wasmtime and wasmer both support bulk-memory operations. Need to verify `wasm-validate` accepts it (it does by default with `--enable-bulk-memory`, which is on by default in recent wabt).
- **Symbol table size:** Adding `typeIdx` to every `TSymEntry` adds 4 bytes × 1024 = 4 KB. Negligible.
- **Type descriptor pool size:** 256 types × ~44 bytes ≈ 11 KB. 512 fields × ~80 bytes ≈ 40 KB. Well within fpc memory limits.
- **Code size growth:** Designator refactor will net-reduce code (consolidating duplicated access patterns) while adding selector logic. Estimated +200 lines net for the full milestone.

### Milestone 11: Variant records — `NOT STARTED`

**Overview.** Add `case tag: T of labels: (fields); ...` variant parts to record type declarations, with overlapping field layout, field-table extensions for per-variant lookup, and typed-constant initializers for variant records. Picks up the work originally listed as Milestone 8 §Step 3 and deferred there.

**Why deferred until now.** Variant records aren't on the self-hosting critical path — the bootstrapped compiler already runs without them. They land in Phase 1c as language-completeness polish, alongside the other typed-constant work.

**Implementation order:**

1. **Parser.** Extend `ParseRecordType` to recognize `tkCase` after the fixed field list. Grammar: `case [Ident ':'] TypeIdent of ConstList ':' '(' FieldList ')' { ';' ConstList ':' '(' FieldList ')' }`. Tag field (if named) becomes a normal field at the current offset; each variant's fields restart at the offset immediately after the tag, applying `{$ALIGN n}` padding. Record total size = `tag_offset + sizeof(tag) + max(sizeof(variant_i))`.

2. **Field-table extension.** Add a `variantId` to `TFieldEntry` (0 for fixed-part fields, 1..n for variants). Phase 1 semantics match TP: `LookupField` is variant-blind — any variant's fields are accessible as a programmer-side view of the same memory, no runtime tag check. The `variantId` is stored only so future tag-checking (`{$R+}` extension) and the typed-const initializer can disambiguate.

3. **Typed-constant initializer.** TP syntax: `(fixed_field: v; ...; tag: N; variant_field: v; ...)`. The initializer parser:
   - Emits fixed-part fields in declaration order (existing logic).
   - When the tag field is reached, evaluates its value and selects the matching variant branch. Error if no `ConstList` covers the tag value.
   - Emits the selected variant's fields in declaration order.
   - Zero-fills from the end of that variant to the record's total size.
   - Reject unnamed-tag records (`case integer of ...` with no tag identifier) as typed constants — the initializer needs a discriminator name to anchor the variant selection.

4. **Tag range checking (`{$R+}`)** is out of scope for this milestone; tracked separately as a future addition once range checks already exist for arrays.

**Tests:**
- `t09X_variant_record_basic.pas` — declaration + field access across variants
- `t09X_variant_record_typed_const.pas` — typed constant for each variant branch
- Negative: initializer specifying a tag value with no matching variant; missing tag field in initializer; typed const for unnamed-tag record

**Documentation updates:**
- `doc/compact-pascal-ref.md` — add variant-record syntax under records; extend the typed-constant section with a variant initializer example.
- `doc/compact-pascal-wp.md` grammar appendix — add `RecordType` with the variant-part production, and a `VariantInitializer` form alongside `RecordInitializer`.
- This file — flip Milestone 8 §Step 3's "deferred to a later milestone" note to point at Milestone 11, and clear the "Variant-record initializers not supported" note from the Phase 1c typed-constants checkbox once shipped.

### Milestone 12: Subrange base types in `set of` — `NOT STARTED`

**Overview.** Accept `set of` over any ordinal subrange — integer, char, enum — so the existing documented forms (`set of 0..31`, `set of 'a'..'z'`, `set of Day(Mon..Fri)`) actually compile. The language reference and white-paper grammar already permit this; only the compiler's `ParseTypeSpec` set-type branch is gated to bare type names (`integer`, `char`, `boolean`, enum literal-list) and rejects subrange expressions with `"type name expected"`.

**Why this is its own milestone.** Independent from variant records. The change is narrow (parser + bitmap sizing) but touches set constructors, membership tests, and the typed-constant initializer for sets, so it needs its own tests and a deliberate encoding decision.

**Grammar** (already in white paper — no change needed):

```ebnf
SetType          = 'set' 'of' SimpleType .
SimpleType       = TypeIdentifier | EnumType | SubrangeType .
SubrangeType     = Constant '..' Constant
                 | Identifier '(' Constant '..' Constant ')' .
```

Examples the compiler must accept:

```pascal
type
  SmallSet = set of 0..31;
  Digits   = set of 0..9;
  Lower    = set of 'a'..'z';
  Weekdays = set of Day(Mon..Fri);  { Day is a previously declared enum }
```

**Encoding decision: anchor bitmaps at 0, not at `arrLo`.** The bitmap covers ordinals `0..arrHi`, rounded up to a byte (or packed into an `i32` when `arrHi < 32`). Bit N is set iff ordinal N is in the set. Consequences:

- **Pros:** `in`, set constructors, union/intersect/difference, and typed-constant initializers all stay identical to the current code. No bias subtraction on the hot path. Matches TP semantics.
- **Cons:** Wastes bits `0..arrLo-1` when `arrLo > 0` (e.g., `set of 100..127` reserves 128 bits / 16 bytes instead of 32 bits / 4 bytes). Bounded at 32 bytes total.
- **Rejected alternative:** biasing the bitmap by `arrLo` saves memory but adds a subtract to every membership test and a matching adjustment to every constant literal. Not worth it at Phase 1.

`arrLo` is still recorded on the type descriptor so a future `{$R+}` pass can range-check `x in s` (reject `x < arrLo` or `x > arrHi`). Phase 1 behavior without `{$R+}`: out-of-range membership test returns `false`, include/exclude is a no-op or silent bit-set at the raw ordinal — matching the existing `set of integer` (0..31) behavior today.

**Validation rules:**

- `arrLo >= 0` required. Reject negative subranges — the bitmap is unsigned-ordinal-indexed. (Workaround: shift the enum's ordinals.)
- `arrHi <= 255` required, same as today.
- `arrHi >= arrLo` required.
- For the `Ident(Lo..Hi)` form, `Ident` must resolve to an ordinal type and `Lo..Hi` must fit inside its range — same semantics as the subrange form used in array bounds.

**Implementation order:**

1. **Factor out subrange parsing.** The `array[...]` branch already parses subrange bounds via `EvalConstExpr` (cpas.pas ~line 2449). Extract a helper `ParseOrdinalSubrange(out lo, hi: longint; out baseTyp: longint; out baseTypeIdx: longint)` that handles:
   - `Constant '..' Constant` — infer base type from the constant's type (`tyInteger`, `tyChar`, `tyBoolean`, or `tyEnum`).
   - `Identifier '(' Constant '..' Constant ')'` — look up `Identifier` as a type, require it ordinal, parse bounds, verify both fit within the named type's range, use the named type as the base.
   - Single `Identifier` (existing path: bare type name) — return its full range as `(arrLo, arrHi)`. This makes the helper the single entry point.

2. **Rewrite the `tkSet` branch in `ParseTypeSpec` (cpas.pas line 2527).** Replace the hard-coded `elemTyp` discriminator with a call to `ParseOrdinalSubrange`. Populate `types[tIdx].arrLo`/`arrHi`/`elemType`/`elemTypeIdx` from its output. Keep the existing bitmap-size computation (`fi := arrHi - arrLo + 1; if fi <= 32 then size := 4 else size := (arrHi + 8) div 8`) — note the subtle change: bitmap size must be computed from `arrHi`, not from `fi`, to preserve the anchor-at-0 invariant. Update that line.

3. **Reuse the array subrange parser.** After the helper lands, replace the inline bound parsing in the `tkArray` branch with the same helper so both paths share logic and stay in sync.

4. **Typed-constant initializer.** No code change expected — `[lo..hi]` range elements and enumerated members already emit bits by raw ordinal, and the encoding decision above keeps the layout compatible. Add a test to confirm.

5. **Set constructors and `in`.** No code change expected for the same reason. Add tests for char- and enum-subrange membership to lock in behavior.

**Tests** (positive, under `compiler-tests/positive/`):

- `t09X_set_int_subrange.pas` — `set of 0..63` (straddles small/large boundary), union/intersect/difference, `in` across the boundary.
- `t09X_set_char_subrange.pas` — `set of 'a'..'z'`, constructor `['a'..'z']`, membership for lowercase letters, non-membership for uppercase.
- `t09X_set_enum_subrange.pas` — `type Day = (Mon,Tue,...Sun); Weekdays = set of Day(Mon..Fri)`; membership returns true for Mon..Fri, false for Sat/Sun.
- `t09X_typed_const_set_subrange.pas` — typed constants over each subrange form (already effectively covered by the existing `primes` test once the base type is accepted, but add an explicit case).

**Negative tests:**

- `set of -5..5` — reject (negative lower bound).
- `set of 0..300` — reject (exceeds 256-value ceiling).
- `set of 10..5` — reject (inverted range).
- `set of Day(BadIdent..Fri)` — reject (unknown constant in named-subrange form).

**Documentation updates:**

- `doc/compact-pascal-ref.md` — no production change; remove any language that suggests the feature already works if a reader might misread it. Add a one-line "bitmap is anchored at ordinal 0, so the low end of the subrange reserves but does not waste ordinals" note under Representation.
- `doc/compact-pascal-wp.md` grammar appendix — no change; `SetType = 'set' 'of' SimpleType` already covers the new cases.
- This file — flip the Phase 1c checkbox to `[x]` and reference the test IDs when shipped.

**Dependencies and risks:**

- No new runtime support needed. All ops reuse existing small/large-set codegen.
- Risk: the anchor-at-0 decision means `set of 200..255` reserves 32 bytes even though only 56 bits are meaningful. Acceptable at Phase 1; revisit if memory pressure shows up in real programs.
- Risk: `{$R+}` range-check extension must subtract `arrLo` only at the *diagnostic* level (reject out-of-range), not at the encoding level. Guard this in the checker design so we don't regress the trivial membership-test codegen.
