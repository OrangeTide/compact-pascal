# Compact Pascal — Project Plan

Compact Pascal is a new language in the Pascal family with a compiler that targets WASM 1.0. The compiler is written in Pascal, ships as a WASM binary, and is embedded in a Rust crate.

See `doc/compact-pascal-wp.md` for the full white paper and `doc/compact-pascal-ref.md` for the language reference.

## Goals

1. **Design a new Pascal-family language** — minimal, strongly typed, suitable for embedding. I/O via compiler intrinsics that lower to WASM host imports. Not a conforming implementation of any existing standard.
2. **Write the compiler in Pascal** — single-pass recursive-descent parser targeting WASM 1.0 binary output. Bootstrapped with fpc, then self-hosting.
3. **Ship the compiler as a WASM blob** — the compiler runs inside a WASM interpreter, so any host that can run WASM can compile Compact Pascal programs.
4. **Provide a Rust embedding crate** — a high-level API to compile Pascal source, instantiate WASM modules, and bridge host-guest function calls, with no external Pascal toolchain required. A host in another language implements the five WASI imports directly; a C library on a bring-your-own-runtime vtable was attempted and dropped in Phase G.
5. **Run everywhere WASM runs** — native applications (via wasmi or any WASM runtime), browsers (via native WebAssembly API), edge runtimes.
6. **Extend the language thoughtfully** — add structural interfaces with methods, and potentially garbage collection, while preserving single-pass compilation and the language's minimalist character.

## Bootstrapping

Bootstrap using **fpc** in TP/BP 7.0 mode (`-Mtp`). fpc produces a **native binary** (not WASM). The native compiler then compiles its own source to WASM, producing the first snapshot. Once a snapshot WASM blob exists (< 1 MB, committed to git), only Rust, or any language with a WASM runtime, is needed to build.

**Open question (checked when resolved) :**
- [x] do we keep the bootstrap compiler that can build in TP-mode of fpc? Or move entirely to the self-hosted compiler knowing that if we lose the .wasm binary that we are stuck? **RESOLVED: Keep fpc bootstrap permanently.** The TP subset fits the compiler's coding style naturally (flat arrays, integers, short strings), so the compatibility cost is near-zero. The main benefit is cross-checking: building via fpc (native → WASM) and via the snapshot (WASM → WASM) gives two independent paths to the same output. Diffing them is a fixpoint test that catches self-hosting bugs. Disaster recovery (rebuild without a WASM runtime) and easy onboarding (`fpc -Mtp cpas.pas` is one command) are secondary benefits. The compiler source must continue to avoid Compact Pascal extensions not present in fpc `-Mtp` (no initialized variables, no extended literals, etc.).

## Project Layout

```
compiler/       — Pascal source for the compiler (built with fpc)
compiler-tests/ — test suite modeled on BSI Pascal Validation Suite
src/rust/       — Rust crate source (compiler, runtime, WASI bridge, diagnostics)
snapshot/       — the compiler WASM blob, embedded in the crate
examples/
  pascal/       — Compact Pascal example programs
  lightout/     — Light's Out browser game (Canvas + WASM, see doc/lightout-example.md)
  rust/         — Rust embedding examples (hello, calculator, host-callback)
  c/            — reference sample for hosting the snapshot from C, not a library
pages/          — GitHub Pages site (includes deployed playground)
  playground/   — client-side browser playground (static HTML, no server)
doc/            — white paper, language reference, and compiler tutorial
Cargo.toml      — Rust build (lib path: src/rust/lib.rs)
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

### Phase 1b: Peephole Optimization (Optional) — `IN PROGRESS`

Optional sliding-window peephole optimizer for the WASM code buffers. Entirely compile-time gated behind `{$IFDEF PEEPHOLE}` — when not defined, zero bytes are added to the compiler WASM image. Can be added to an existing compiler at any time without modifying the core codegen.

**Prerequisites:**
- [x] `-dSYMBOL` command-line flag for conditional compilation symbols (via WASI `args_get`); `{$DEFINE}` / `{$UNDEF}` directives; `CPAS` predefined
- [x] `-O0` / `-O1` command-line flags (parsed, stored in global `optLevel`; ignored when peephole not compiled in). Default `optLevel = 1`.
- [x] `{$OPT+/-}` compiler directive, `ON`/`OFF` also accepted (toggles optimizer per-region; ignored when peephole not compiled in). Test: `t093_opt_directive`.

**Optimizer:**
- [x] `TryPeephole` procedure called after each opcode emission, gated by `{$IFDEF PEEPHOLE}` and `optLevel > 0`. Instruction-boundary hook via bundled `EmitOp`/`EmitLocalGet`/etc. helpers; non-bundled paths invalidate the window.
- [x] Fixed lookback window on code buffer (last two opcode starts tracked via `lastOpStart` / `prevOpStart` on `TCodeBuf`).
- [x] Switch/case pattern matcher on trailing opcode bytes (opcode-pair dispatch in `TryPeephole`).
- [x] LEB128 decode helper for operand comparison (`DecodeULEB128At`).
- [x] Patterns shipped: `local.set X / local.get X → local.tee X`; `i32.eqz / i32.eqz → drop both` (double-negation). Additional patterns (constant folding, identity elimination, shift-for-multiply) deferred — base codegen rarely emits the redundancies they target.
- [x] Verify rewrites preserve WASM stack typing (both shipped patterns are type-preserving; `local.tee` keeps the value on stack, double `eqz` returns an i32 equivalent to the input treated as i32 bool).

**Validation:**
- [x] Existing test suite passes identically under baseline (byte-identical output with `-O0` or without PEEPHOLE) and under `-dPEEPHOLE` (104/104 tests pass).
- [x] Disassemble non-trivial programs (`wasm-objdump -d`) to verify pattern elimination — `compiler-tests/peephole-check.sh` builds baseline + peephole compilers, compiles a case-statement fixture, asserts baseline has `local.set`/`local.get`, peephole has `local.tee`, and peephole output is strictly smaller.
- [x] Measure code size reduction on compiler self-compilation — 64 bytes (0.04%) reduction on self-compilation; 82 bytes (0.08%) across 99 test programs; 26 programs benefited.

**Tutorial:**
- [ ] Appendix in tutorial book (not a numbered chapter) — optional exercise
- [ ] Covers: stack-machine redundancy patterns, sliding-window technique, conditional compilation, compiler-size vs output-quality trade-off, historical context (shift-vs-multiply on real hardware)

**Research notes:** `notes/research-peephole.md`

### Phase 1c: Language Completeness — `IN PROGRESS`

Polish items beyond the self-hosting cut. None of these block any later phase; they close the gap between "compiler writes itself" and "compiler is a complete Compact Pascal toolchain per the language reference."

**Language features:**
- [x] Typed constants — scalar, 1D/ND array, `array of char` string-literal shortcut, record `(field: value; ...)`, and set `[elem, ...]` initializers implemented (tests t086–t088, t091, t092). Stored in data segment; TP-style mutable. Variant-record initializers tracked under Milestone 11.
- [x] Variant records — `case tag: T of ...` inside record types, and the corresponding typed-constant initializer form (tests t098–t099, n008–n009). Design: see Milestone 11 below.
- [x] Subrange base types in `set of` — `set of 0..31`, `set of 'a'..'z'`, `set of Day(Mon..Fri)` (tests t094–t097, n004–n007). Design: see Milestone 12 below.
- [ ] Standalone subrange types — `type T = 0..9;`, `type WorkDay = Mon..Fri;`, `var x: 0..255;`. `ParseSubrangeLiteral` exists but `ParseTypeSpec` has no top-level branch for it. See Findings.
- [x] `{$ALIGN n}` directive for record field alignment (n ∈ {1, 2, 4, 8}, default 4; test t089)
- [x] `-dump` flag in self-hosted builds (ParamCount/ParamStr intrinsics via WASI args_get)

**Documentation coverage:**
- [ ] fpdoc comments on all public procedures/functions, with detailed comments on core routines (see Findings)
- [ ] WAT pseudo-code comments on all WASM binary emission sites (partial coverage, ~17 comments today)

**Browser game example (Light's Out):**
- [x] `examples/lightout/` — 5×5 Light's Out puzzle running in browser via HTML5 Canvas
- [x] Design doc: `doc/lightout-example.md` (already written)
- [x] `lightout.pas` — game logic, rendering, input (~240 lines)
- [x] `host.js` — JS bridge: canvas, input, Web Audio tone generation
- [x] `index.html` — canvas scaffold
- [x] Makefile for building and local serving
- [x] Demonstrates `{$IMPORT}`/`{$EXPORT}` FFI, arrays, constants, frame-driven game loop

### Phase 2: Embedding Libraries — `DONE (Rust); C and Zig dropped`

Superseded by Phase F, which took the Rust crate to production grade, and by
Phase G, which dropped the C library. Zig was dropped earlier. The original
checklist for this phase is deleted rather than left standing, because it was
not merely stale: six items under the C library were marked done that were
never implemented, including the WASI callbacks, the host-guest FFI through the
vtable, and an example described as "minimal compile-and-run" that never
compiled anything. Leaving false ticks in place is worse than having no
checklist. See Findings.

Remaining ideas from that list that are still wanted, none of them blocking:

- [ ] Example: `examples/rust/pode-server/` — **Pode Server: The Pascal Node
      Clone** (see `doc/pode-server.md`). File-based routing over `routes/*.pas`,
      query string piped to stdin, stdout as the response body, hot reload, and
      Deno-style permission flags.

### Phase 3: Self-Hosting — `MOSTLY DONE`

Core self-hosting is complete: the fpc-built compiler compiles its own source to WASM, the snapshot produces bit-identical output (fixpoint validated), and the blob is committed at 131 KB. The Rust crate exercises the snapshot on every `cargo test`, so embedding is verified continuously rather than pending.

- [x] Use the native (fpc-built) compiler to compile its own source to WASM, producing the first snapshot binary
- [x] Verify fixpoint: fpc-built and self-built compilers produce bit-identical WASM
- [x] Commit the snapshot blob to git (131 KB, well under the 1 MB budget)
- [x] Verify the Rust crate works end-to-end using only the snapshot (no fpc required) — 10 integration tests in `tests/integration.rs`

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

**Method receiver is parenthesized: `for (r: TRect)`.** The original form put
two colons of different meaning next to each other (`function Area for r:
TRect: integer`). It parses fine and stays LL(1), but humans misread it. Go
reached the same place. Changed before anyone writes code against the published
form; after Phase F this would be a breaking change.

**A method may not share a name with a field of its receiver type.** Compile
error at the method declaration. The alternative, fields shadow methods,
resolves the ambiguity equally well but breaks at a distance: adding a field to
a record silently makes an existing method uncallable, and the error surfaces
wherever the method was called rather than where the field was added. Erroring
at the declaration puts the diagnostic where the author can act on it. Accepted
cost: a library adding a field can break a downstream method of the same name.

**The `implement` block declares conformance, it is not a second definition
site.** When the block closes, each interface signature resolves first to a
method defined in the block, otherwise to an existing standalone method of the
receiver type. Only genuinely missing signatures need a body, so a block can be
empty. This removes the duplication the original design forced on any type
wanting both a dot-callable method and interface conformance. It stays
single-pass: declare-before-use guarantees every candidate has already been
seen when the block closes, so no lookahead is needed. It also answers the
reverse question cleanly, and the reference now states it: implement-block
methods are not dot-callable on the concrete type. Standalone methods declare
the type's own surface; the block declares conformance.

**Pointer-receiver methods require an addressable operand.** Variables, fields,
array elements, and dereferences qualify; function results, casts, and other
temporaries do not. Without the rule, `Origin.Rename('X')` on a function result
mutates a temporary and discards it silently. Go forbids exactly this case.
Value receivers are unrestricted, since they copy.

**An interface value does not keep its concrete data alive.** `Self` can
dangle: store the interface in a global, or return one referring to a local,
and the pointer outlives the data. The language does not detect it. Same rule
Pascal already applies to `@x` and `var` parameters, stated explicitly because
an interface value hides the pointer and the hazard is less visible than with
an explicit `^T`.

**Interfaces are not structurally typed, and the reference said they were.**
Signatures are matched structurally, but conformance is declared in an
`implement` block and verified at that single point. The accurate comparison is
Rust's `impl Trait for Type`, not Go's implicit satisfaction. This is also the
better design for a declare-before-use language, since a type cannot conform by
accident, so the old label undersold it.


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

**Subrange parsing status (2026-05-02).** `ParseSubrangeLiteral` (cpas.pas ~line 2555) handles the `Constant '..' Constant` production and is used by `set of` (Milestone 12). Array bounds use inline `EvalConstExpr` + `..` but are equivalent. Standalone subrange types (`type T = 0..9;`, `var x: 0..255;`, `type WorkDay = Mon..Fri;`) are NOT implemented — `ParseTypeSpec` has no top-level branch for a literal or named constant followed by `..`. Adding it requires: (1) after the `tkIdent` branch resolves a type name, peek for `(` (typed subrange) or `..` (untyped); (2) add a `tkInteger`/`tkChar` entry point for literal-started subranges like `0..255`; (3) decide the runtime representation — since all ordinals are `i32` with no masking unless `{$R+}`, a subrange type is just its base type with bounds metadata for range checks and `set of` sizing. No new `tySubrange` kind is needed in Phase 1; store bounds in the type descriptor and alias the base type.

**Single-file compiler source.** The compiler is kept as a single file (`compiler/cpas.pas`) rather than split via `{$I}` includes. At ~10,400 lines, a single file with well-commented sections and fpdoc headers is navigable and matches the reality of the design — it's a single-pass compiler with tightly coupled shared global state. Pascal `{$I}` includes are textual paste, not modules, so splitting wouldn't reduce coupling or improve encapsulation. It would add host-side preprocessing complexity (the WASM-hosted compiler receives a pre-expanded source stream). Wirth's Oberon compiler follows the same single-file convention at ~4000 lines.

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
- **Stack pointer** is a mutable WASM global (`$sp`), initialized to the top of memory. Frame allocation: `$sp -= frame_size`. Frame deallocation: `$sp := display[level] + frame_size` (see the frame balance finding below).

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

**Reading includes is a compiler capability, not a program capability.** The
first attempt gated compiler-side `{$I}` on `{$FILES ON}`, which conflates two
different things: whether the compiler may read include files, and whether the
program being compiled may touch the filesystem. A program that includes a
file but does no I/O of its own would have had to declare a capability it never
uses and import two WASI functions it never calls. It is a `-I` flag on the
compiler instead.

Off by default, because an embedder may have expanded the includes already —
the Rust crate's `expand_includes` does — and opening them a second time would
be wrong. Skipping the directive without `-I` is what makes the two paths safe
together.

**Giving the compiler includes made the snapshot need filesystem imports.**
The compiler's own source declares `{$FILES ON}`, so the snapshot declares
`path_open` and `fd_close`, so the Rust bridge had to implement them or nothing
would instantiate. That is the same breakage the opt-in directive was
introduced to avoid, arriving from the other direction, and this time it could
not be designed away: a compiler that reads files needs the imports.

The bridge refuses by default. A host opts in with
`WasiContext::preopen_dir`, and paths are confined to it exactly as
`expand_includes` confines its own. Declaring an import and being allowed to
use it stay separate.

**Three failures on the way, each worth remembering.**

A `sed` pattern matched `numPendingPtr := 0` in `ResolvePendingPointers` as
well as in `Init`, so every `type` block silently reset the compiler's
file-access state. It presented as `{$FILES ON}` not working in one particular
large file while working in every small reproduction, which is a slow way to
discover that an edit landed in two places.

`(incDepth > 0) and eof(incFile[incDepth - 1])` is not short-circuit in this
language, so it indexed element -1 whenever no include was open, read a garbage
descriptor, and corrupted the scanner's line counter into a nine-digit number.
`and then` exists but fpc in TP mode does not have it, and this source has to
compile under both, so it is a loop with an explicit break.

The text operations accepted only a plain variable, so the compiler could not
use its own array of them. They take a designator now, evaluated once into a
data word because `Close` needs the address four times and re-evaluating an
index expression four times is both wasteful and wrong.

**`Eof(f)` looks ahead rather than reporting a read that already failed.** The
first implementation set a flag when a refill returned nothing, which is the
cheap thing to do and is wrong: `while not eof(f) do readln(f, s)` ran one
extra iteration and produced a spurious empty line. Found by running the
reference example rather than by reasoning about it, which is the third time a
documentation example has caught a defect in this project.

`Eof` now reads the next byte and puts it back by decrementing the buffer
position. That costs one buffered comparison, never a syscall, because a
refill has already happened if it was going to. Turbo Pascal's `Eof` looks
ahead for the same reason.

**A text variable is a control block, not a handle.** The plan said handle
table. A table needs entries created and destroyed in step with variable
lifetimes, and nothing in this language tracks those: a `text` local in a
recursive procedure would need a table slot per invocation. Putting the whole
state in the variable makes its lifetime the variable's lifetime, which the
frame already manages. The cost is 536 bytes per variable, most of it the
256-byte buffer and the 256-byte name.

`Assign` stores the name in the block rather than passing it to the open,
because Pascal separates naming from opening: a program assigns once and may
`Reset` and `Rewrite` the same variable repeatedly, and a failed `Reset` has
to leave something to report about.

**Two things the WASI layer only teaches by being run.** `path_open` rejects
all-ones rights: a host validates the field against the rights it knows and
refuses an unknown bit, so `-1` fails outright rather than being narrowed.
wasmtime reports that as an integer conversion error, which does not sound
like what it means. The compiler asks for bits 0 through 28 instead, every
right preview 1 defines.

And the preopened directory is assumed to be file descriptor 3. WASI does not
guarantee it; a guest is meant to walk `fd_prestat_get` upward from 3 and
match the directory it wants. Every host this targets grants one directory and
it lands on 3, so the walk would be three more imports and a loop to reach the
same answer. Written down as an assumption so it is not rediscovered as
folklore.

**Filesystem access is opt-in because always-on imports broke the embedding.**
The five core WASI imports are registered before parsing so that helper
function slots, numbered from the import count, are stable in a single pass.
Adding `path_open` and `fd_close` the same way seemed natural and broke every
Rust host at once: the bridge implements five WASI functions, so a snapshot
declaring seven could not be instantiated and the whole crate test suite
failed on the first run after the change.

The fix is better than what it replaced. `{$FILES ON}` makes the request
visible in the module's import list, so a host can refuse a program that wants
files without reading its source. That fits the sandbox story the embedding
guide already tells: capability is what the host grants, and now it is legible
before instantiation rather than only at the first call.

The directive has to precede the program header, and the compiler enforces it
rather than trusting it. Import indices are positional and helper slot numbers
become immediates in call instructions, so the count cannot be revised once
code exists.

**Three documents claimed programs without I/O have no imports. None did.** An
empty program has always declared five. The claim was in the reference, the
white paper, and the README, and it was checked by nobody until adding an
import made the import list worth looking at. The conformance requirement now
separates what a module *declares* from what it *calls*, which is the
distinction that was missing: a positional import list cannot drop an unused
entry without renumbering every call, and renumbering is what registering up
front exists to avoid.

This is the sixth defect in this project found by verifying a documentation
claim. It is also the second where the claim was in a *conformance*
requirement, which is the worst place for one, since it is what a second
implementation would be held to.

**The heap boundary and the stack limit are one global.** Phase D put a
`__stack_limit` global at the data segment's high-water mark and called it
immutable. That was a consequence of there being no heap, not a property, and
the comment stated it as though it were the latter. The global is now
`__heap_end`, mutable, and serves both roles: the allocator raises it when it
carves a block, the prologue guard compares against it before reserving a
frame. Growth from either side is caught by the check on the other, and there
is no way for the two to disagree because there is only one number.

Had the limit stayed fixed, the Phase D stack guard would have been quietly
wrong the moment a heap existed: it would have let a frame overwrite heap
blocks and reported nothing.

**`Dispose` clears the pointer.** Standard Pascal leaves it dangling and says
nothing about using it afterwards. Clearing costs one store and converts two
common mistakes into a nil trap: use after dispose, and double dispose. The
second is the valuable one, since pushing the same block onto the free list
twice makes a cycle that a later allocation walks forever.

It is not a memory-safety guarantee and the reference says so. Only the pointer
passed in is cleared; any other pointer to the same block is still dangling,
and nothing can find them.

**Exhaustion traps rather than returning nil.** The alternative is what most
Pascals do: `New` returns nil and the program is expected to check. No program
checks. A trap at the point of failure is worth more than a nil that surfaces
as a corrupt read later, and it matches what `{$R+}` and the stack guard
already do. Documented rather than assumed, because it means a program cannot
recover from exhaustion at all.

**The var-argument path was the sixth selector loop.** It accepted only
`[index]`, which was enough while no designator could reach through a pointer.
A tree insert wants `Ins(t^.left, v)`, so it learned `^` and `.field`. That
makes six near-identical selector loops in the compiler: two learned `^` in
Phase E, this one now, and three `with` paths still have not. Collapsing them
is still owed, and the list of things waiting on it is now three:
`with p^ do`, assigning to a field of a function result, and whatever the next
phase needs.

**Built-in names shadow user procedures.** `Insert`, `Delete`, `New`, and
`Dispose` are matched before symbol lookup, so a user procedure named `Insert`
is unreachable and the error names the built-in's argument rules, which is
baffling. Found while writing the tree test, whose insert had to be renamed.
Pre-existing and unfixed; the fix is to look the name up first and fall back to
the built-in only when it is not a user symbol.

**A structured result buffer is stack-allocated with a compile-time depth
counter.** The buffer cannot come from the frame, because the frame size is
fixed before the body is compiled, which was the original blocker. It comes
from the stack below the frame and is released at the end of the statement.

Every address involved is derived from `$sp` at run time by adding back what
was taken below it, and the amount is a compile-time constant the compiler
tracks in `stmtArenaBytes`. That counter is the part that took two wrong
attempts. Fixed offsets worked for one call and broke as soon as a call's
argument contained another structured-returning call, because the inner call's
buffer persists to the end of the statement and sits between `$sp` and the
outer one. Anything derived from `$sp` needs the running depth, not a fixed
size.

Order of allocation is load-bearing and worth stating: saved concat pieces
highest, then the result buffer, then the argument concat temps, which are the
only ones released at the call rather than at the statement.

**`exit`, `break`, and `continue` needed explicit releases; the plan said they
would not.** Phase D's epilogue restores `$sp` from the frame base, so the plan
assumed a branch out of a statement holding a buffer was already covered. It is
not, for two reasons. The frame balance check runs *before* the epilogue's
restore, so a buffer outstanding at `exit` trips a trap that is not a bug. And
`break` leaves a loop whose body statement never reached its release, so
without one the loop accumulates a buffer per iteration. All three now release
before branching, and loops release at the bottom of each iteration.

**One flag carried two meanings, and separating them mattered.**
`stmtUsedResultBuf` means both "this statement owes a release" and "$sp is
currently below the frame base". Clearing it on entry to a nested statement,
which is the obvious save/restore pattern, broke the second meaning:
`EmitFramePtr` reads `$sp` as a shortcut for the current frame, and a nested
statement that had cleared the flag addressed its frame variables through a
`$sp` that an enclosing statement's buffer was holding down. The flag is now
not cleared; the statement that owes the release is the one that finds it
false on entry.

**Pending concatenation pieces collided across a call.** The pieces of a
pending `+` chain lived in one static array at a fixed address. A callee that
concatenated wrote over its caller's pieces while the caller was still using
them, so `a + Wrap(b)` produced the wrong string. This predates Phase H
entirely: the old compiler gave `[)]` where `[A(B)]` was correct, reachable
through the accidental `type TS = string` return path. It is also what made a
recursive string function return empty.

Two fixes together, because either alone is insufficient. The slots are rebased
per compile-time nesting level, which handles one expression nesting inside
another. And the pending pieces are copied onto the stack across a call, which
handles the run-time case: the callee was compiled at base zero and writes
there no matter what base the caller chose. The copy is emitted only when there
are pieces to protect, so an ordinary call costs nothing.

**Known defect, not fixed here: char-to-string coercion aliases.** `a + '.' +
b + '.'` with two `char` operands gives `[B.]` instead of `[A.B.]`. Each char
is converted to a one-character string in a single static buffer, so the second
conversion overwrites the first. Same family as the concat-piece collision and
the same fix would apply. Present in the pre-Phase-H snapshot and unchanged by
it, verified by running both compilers on the same source. Found while checking
that a reference example actually ran.

**The C library is dropped, and the checklist had been describing it
generously.** "Partially implemented" appeared in the README and in this plan
for months. The assessment at the Phase G gate found that every function
needing a WASM engine was a stub, including `cp_compile` itself, so the library
could not compile Pascal at all. What worked was exactly the part that needs no
engine: include expansion and Pascal string conversion. Zero tests, no CI, and
`examples/c/hello` linked wasm3 directly rather than using the library, so the
one thing that appeared to demonstrate it demonstrated something else.

The design was the deeper problem. Bring-your-own-runtime through a vtable puts
the engine binding on the user, and the engine binding is the hard half. A C
user who has written it is most of the way to running the snapshot themselves;
`examples/c/hello` implements the whole WASI surface in about 300 lines. The
Rust crate's value comes from what C structurally cannot have: one dependency
with the snapshot and a runtime already inside it. The C library would have
stayed a thin wrapper over work the user still had to do.

Removing it also drops 532 KB of vendored wasm3 that nothing in the library
used. The example is kept because it answers the real question a C user has,
and it is labelled as documentation so it is not mistaken for a supported
library.

The general lesson, which is why this phase existed as a gate at all: a
checklist item that says "partial" stops being informative the moment nobody
re-measures it. The gate forced a measurement, and the measurement changed the
decision.

**The license is CC0-1.0.** The repository had stated three: `LICENSE-MIT` and
`LICENSE-APACHE` with a README badge saying MIT OR Apache-2.0, `Cargo.toml`
saying CC0-1.0, and twelve source files carrying `PUBLIC DOMAIN (CC0-1.0)`
headers. MIT OR Apache-2.0 is the Rust ecosystem convention and is what a
crates.io user expects, which is the argument against the choice made. The
argument for it, and the one that decided it: machine-written work carries no
copyright to assign, so a permissive license would be claiming a right in order
to license it back out. CC0 states what is already the case. Decided by the
maintainer when the inconsistency was raised.

**`proc_exit` signalled through an error message was the root of two bugs.**
The Rust bridge reported program exit by constructing a wasmi error whose
message read `proc_exit(0)`, and every call site matched that substring to
decide whether the program had succeeded. Two consequences: `halt(3)` was
indistinguishable from a trap, and a trap whose message happened to contain the
text would have been read as success. wasmi has `Error::i32_exit`, which
carries the status as structured data, and `i32_exit_status()` to read it back.
Now `halt(3)` is `RuntimeError::Exit(3)` and a trap is `RuntimeError::Trapped`.

The lesson generalizes past this instance: formatting structured information
into a string and parsing it back at the boundary loses the distinction the
structure carried. The same shape appears wherever a message is used as a
channel.

**Writing the embedding guide found the gap it was documenting.** The sandbox
section wanted to say "impose limits from the host side", and there was no way
to: `Instance` and `InstanceBuilder` each built their own `Engine::default()`,
so wasmi's fuel metering and memory ceiling were unreachable from this crate's
API. Documenting a boundary honestly means naming what is not defended, and
that is what surfaced it. `Limits` now exposes both.

This is the fourth time in this project that a bug was found by verifying a
documentation claim rather than by adding a test of the existing kind. The
others were the `/dev/stdout` portability failure, the `(*$...*)` directive
form, and the pointer-target check. Test-writing looks for cases the author
already imagined; documentation-writing forces a claim to be stated in full,
where a gap is visible.

**Include paths escaped their base directory, and the threat model found it.**
`build_path` was `base_dir.join(filename)` with no check. `Path::join` given an
absolute path discards the base and returns the absolute path, so
`{$I '/etc/passwd'}` read that file. `..` walked upward freely.

Found by reviewing the newly written `SECURITY.md` against the code: the threat
model listed "include resolution reaching outside its base directory" as in
scope, and checking whether that claim held showed it did not. Writing down
what a boundary is supposed to do is what makes it checkable.

The fix rejects `..`, absolute paths, and drive prefixes, by inspecting the
components of the written path rather than by touching the filesystem.
`canonicalize` would also catch a symlink pointing out of the base directory,
but it requires the target to exist, which turns a missing-file error into a
confusing one, and it resolves symlinks the host may have put there on purpose.
The symlink case is documented as a limit instead. Revisit if a host ever
serves untrusted source from a directory it does not fully control.

**Pointer types carry their target in the array element slots.** A `^T`
descriptor is an ordinary `TTypeDesc` with `kind = tyPointer` and the target
in `elemType`/`elemTypeIdx`/`elemSize`/`elemStrMax`, the same fields an array
uses for its element type. No new table, and the dereference selector reads
the target exactly the way array indexing reads the element type.

Descriptors are interned: `FindOrAddPointerType` reuses an existing descriptor
whose target matches. Without that, a program with many `^TNode` declarations
would exhaust the 256-entry type table on pointers alone. Interning is safe
because two pointer types with the same target are the same type.

Compatibility compares *targets*, not descriptor indices, because a forward
reference and a later direct reference to the same type produce two
descriptors. `nil` is descriptor index -1 and is compatible with everything.

**Forward pointer references are resolved at the end of the type block.** This
was not in the phase scope and was added anyway: `PNode = ^TNode` before
`TNode` is the one break from declare-before-use that Pascal allows, and it
exists because a linked node type cannot be written without it. Deferring it
would have meant retrofitting it during the heap phase, when there is more to
go wrong.

The mechanism is small because the grammar allows only a type *name* after
`^`, never an anonymous record or array. An unresolved `^Name` parks a
descriptor with `elemType = tyNone` and records the name and the line;
`ResolvePendingPointers` fills the targets in when the `type` block ends, and
errors with the original line number if the name never appeared. Interning
skips unresolved descriptors, since their target is not yet known.

The scope is the type block that opened the reference, matching standard
Pascal. A forward reference that crosses into a later `type` block is an error,
not a silent success.

**Pointers compare with `=` and `<>` only.** Ordering is a compile error rather
than an address comparison. Two pointers into different objects have no
meaningful order, and the one case where an order would be defined, two
pointers into the same array, reads better on the indices. This is stricter
than Turbo Pascal, which permits the comparison and gives it address
semantics.

**`write(p)` is rejected.** Printing a raw address is nearly always a debugging
accident, and the number is meaningless outside the run that produced it.

**`(*$...*)` is not a directive.** The scanner routes only `{$` to the
directive parser; `(*$R+*)` is an ordinary comment and is silently ignored.
Found while writing `t108`, which needed to pin `{$S+}` for the checks-off run
and quietly did nothing. This also means `t104`'s pin was never active: it
passed the checks-off run because unbounded recursion exhausts the WASM call
stack and traps anyway, not because the guard fired.

The reference now states the brace form is the only directive form, and calls
out that the Turbo Pascal spelling is accepted as a comment. Supporting the
paren-star form would mean teaching `SkipBraceComment` a second terminator,
which is more surgery than the parity is worth right now. Worth revisiting if
porting real Turbo Pascal sources becomes a goal.

**Stack overflow guard compares before subtracting.** The prologue checks `$sp < __stack_limit + frame_size` and traps, rather than subtracting first and checking `$sp < __stack_limit` afterwards. The second form looks simpler and is wrong: a frame large enough to carry `$sp` past zero wraps it to a large unsigned value, which compares as above the limit and sails through. Checking first also leaves `$sp` valid at the trap, so the backtrace is readable. The limit lives in an immutable WASM global (index 10, `__stack_limit`) initialized to the data end. Cost is six instructions per frame on the path that does not trap, eight emitted, and 0.93% of compiler code size. On by default pre-1.0 under `{$S+}`; silent corruption costs more to debug than the instructions cost to run.

The guard does not cover the 256-byte scratch allocations the body makes for string concatenation in const argument position. Those move `$sp` after the prologue check. Small enough not to matter at the depths the guard catches, and Phase H replaces the mechanism.

**Frame balance uses `display[N]`, not a new local.** PLAN originally called for saving entry SP in a WASM local. That is unnecessary: `display[curNestLevel]` already holds the frame base, is set in the prologue immediately after the allocation, and is saved and restored across recursion by the existing display protocol. Restoring `$sp` from it costs the same four instructions as the old relative `$sp += frame_size`, adds no local, and does not disturb the fixed local-index convention (params, return value, saved display, string temp, case temp), which a new local would have shifted.

The value is not primarily the assert. Restoring from a recorded base makes an unbalanced allocation self-healing at return: the damage is contained to the one call instead of desynchronizing `$sp` for the rest of the program, where it surfaces somewhere unrelated. Under `{$S+}` the epilogue also compares `$sp` against the base and traps first, so the bug is reported at the function that caused it. Verified by injecting a stray `$sp -= 16` into every epilogue and confirming the trap. The check is live, not speculative: the concat scratch allocations above are exactly the kind of ad-hoc SP movement it audits. Cost is 1.17% of compiler code size.

The epilogue ordering changed as a consequence. `display[N]` is now restored *after* the frame is released rather than before, because the release reads it.

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

**Doc pass (2026-04-18): fpdoc headers added, inline WAT comments deferred.** Added `{** ... }` fpdoc headers to all Phase 1 procedures/functions in `compiler/cpas.pas`, with expanded prose on the flagged routines (`NextToken`, `EnterScope`/`LeaveScope`, `ParseExpression`, `EmitFramePtr`, `EmitVarParamPtr`, `EmitWriteInt`) and WAT-style one-liners on all 26 `Emit*` headers. Committed in seven subsystem-scoped commits (scanner, diagnostics, symbol table, buffers/LEB, parser, codegen, driver). The inline `{ ;; WAT: ... }` annotation pass on the ~1,254 emission call sites was not done — the emitter headers now document the WAT shape, which gets most of the pedagogical value; annotating every call site would add noise without proportionate payoff. If the tutorial chapters end up wanting per-site WAT asides, that can be a later targeted pass rather than a blanket sweep. Build and test suite (now 104 tests: 97 positive + 7 negative) still clean.

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
- **Include file resolution:** `{$INCLUDE}` directives are resolved by the host application before invoking the compiler. The embedding library scans the source, expands includes by replacing the directive with file contents, and passes a single concatenated source stream to the compiler on stdin. This keeps the compiler's I/O interface minimal (three fds, no filesystem access). During fpc bootstrap, fpc handles `{$I}` natively. The Rust crate provides `expand_includes` for this, confining resolution to a base directory the host chooses; a host in another language does the expansion itself. Parsing `{$I ...}` out of comments is straightforward.

**Rust version target.**

- **Rust MSRV: 1.85 (edition 2024).** This is the edition 2024 baseline and the minimum supported Rust version for the `compact-pascal` crate (set via `rust-version = "1.85"` in `Cargo.toml`). wasmi works on stable Rust; no nightly features are required. The MSRV can be bumped conservatively as needed.

The Zig and C version targets that stood here are dropped along with those
libraries. The wasm3 dependency they implied is gone too, which removes the
risk noted at the time: wasm3's development had slowed and an unmaintained
runtime would have been the project's problem. The `examples/c/hello` sample
still uses wasm3, but it builds against an upstream checkout the reader
supplies and nothing in the repository depends on it.

**WASM snapshot hung on `{$IMPORT}` + `external` sources. RESOLVED.** The WASM compiler snapshot entered an infinite computation loop compiling any source carrying both `{$IMPORT 'module' name}` and `procedure/function ... external;`. No `fd_read` calls occurred, so it was pure computation rather than an I/O stall, and export-only sources compiled fine. **The root cause was not the FPC RTL, and not I/O at all.** It was the for-loop `continue` codegen bug fixed in `ee481a9`: `continue` branched past the loop increment, so any `for` loop containing it ran forever. Import handling reaches such a loop; export handling does not, which is why only import-bearing sources hung. Confirmed by bisecting the checked-in snapshots: the snapshot at `fff708d`, the commit that recorded this finding, still hangs on a minimal import source and compiles an export-only source fine, exactly as described. The snapshot at `ee481a9`, the very next commit, compiles both. The planned `BlockRead`/`BlockWrite` migration was chasing the wrong hypothesis and is not needed for this. The `compile_native` workaround in the Rust tests is removed; all four FFI tests now go through wasmi, and `snapshot_compiles_import_bearing_source` pins it.

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

##### Pode Server (Rust)

Node-like Pascal server with Rust backend.

##### A native command-line wrapper generator

Turn a `.wasm` from cpas into a stand-alone command-line utility: emit a small
C stub that embeds the module and links a WASM runtime, exporting the bare
minimum the program needs. A sort of mini-linker that produces a
wasm-in-a-native bundle, which would also give `cpas` itself a native
command-line form.

Language-agnostic, and no longer tied to the dropped C library. `examples/c/hello`
is most of the runtime half already.

The Zig IDE idea that stood here is dropped with the Zig binding.

#### Releases

On tag (e.g. v1.2.3), release a set of packages on the Github release page.

- ZIP with PDFs: White Paper, Reference(s), and Tech Notes.
- ZIP with only the wasm binaries for the compiler, plus a README covering
  `wasmtime run compiler.wasm < prog.pas > prog.wasm`. This is the Phase C
  release artifact and the only one that is committed.

The Rust crate is published to crates.io rather than as a zip. The C and Zig
release zips that stood here are dropped with those libraries.
- ZIP of the Playground website ready for people to deploy locally.

#### Dependencies and risks

- **`memory.copy` support:** wasmtime and wasmer both support bulk-memory operations. Need to verify `wasm-validate` accepts it (it does by default with `--enable-bulk-memory`, which is on by default in recent wabt).
- **Symbol table size:** Adding `typeIdx` to every `TSymEntry` adds 4 bytes × 1024 = 4 KB. Negligible.
- **Type descriptor pool size:** 256 types × ~44 bytes ≈ 11 KB. 512 fields × ~80 bytes ≈ 40 KB. Well within fpc memory limits.
- **Code size growth:** Designator refactor will net-reduce code (consolidating duplicated access patterns) while adding selector logic. Estimated +200 lines net for the full milestone.

### Milestone 11: Variant records — `DONE`

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
- `t098_variant_record_basic.pas` — declaration + field access across variants
- `t099_variant_record_typed_const.pas` — typed constant for each variant branch
- `n008_variant_bad_tag.pas` — tag value with no matching variant rejected
- `n009_variant_unnamed_tag.pas` — typed const for unnamed-tag record rejected

**Documentation updates:**
- `doc/compact-pascal-ref.md` — add variant-record syntax under records; extend the typed-constant section with a variant initializer example.
- `doc/compact-pascal-wp.md` grammar appendix — add `RecordType` with the variant-part production, and a `VariantInitializer` form alongside `RecordInitializer`.
- This file — flip Milestone 8 §Step 3's "deferred to a later milestone" note to point at Milestone 11, and clear the "Variant-record initializers not supported" note from the Phase 1c typed-constants checkbox once shipped.

### Milestone 12: Subrange base types in `set of` — `DONE`

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

**Encoding decision: anchor bitmaps at 0, not at `arrLo`.** The bitmap covers ordinals `0..arrHi`. Bit N is set iff ordinal N is in the set. Size is binary: 4 bytes (packed `i32`) when `arrHi < 32`, else 32 bytes matching existing large-set convention. Consequences:

- **Pros:** `in`, set constructors, union/intersect/difference, and typed-constant initializers all stay identical to the current code. No bias subtraction on the hot path. Matches TP semantics.
- **Cons:** Wastes bits `0..arrLo-1` when `arrLo > 0`. Bounded at 32 bytes total. A byte-rounded size (`(arrHi+8) div 8`) was briefly considered but would have required adjusting the set-constructor and set-copy codegen, which both assume 32 bytes for large sets — not worth it at Phase 1.
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

2. **Rewrite the `tkSet` branch in `ParseTypeSpec`.** Replace the hard-coded `elemTyp` discriminator with a three-form dispatch: bare type ident (legacy defaults), `T(Lo..Hi)` named subrange, or subrange literal via `ParseSubrangeLiteral`. Populate `types[tIdx].arrLo`/`arrHi`/`elemType`/`elemTypeIdx` from its output. **Size is binary: 4 bytes when `arrHi < 32`, else 32 bytes.** Originally planned as `(arrHi + 8) div 8`, but existing set constructor/copy codegen assumes large sets are exactly 32 bytes — anchor-at-0 makes that storage correct regardless of `arrLo`.

3. **Reuse the array subrange parser.** _Deferred._ The array-bound parsing in `tkArray` is similar in shape but has subtly different semantics (no same-type enforcement on the two bounds, different error message) — out of scope for M12. Not worth changing observable behavior to share a helper.

4. **Typed-constant initializer.** No code change expected — `[lo..hi]` range elements and enumerated members already emit bits by raw ordinal, and the encoding decision above keeps the layout compatible. Add a test to confirm.

5. **Set constructors and `in`.** No code change expected for the same reason. Add tests for char- and enum-subrange membership to lock in behavior.

**Tests shipped** (positive, under `compiler-tests/positive/`):

- `t094_set_int_subrange.pas` — `set of 0..9` and `set of 13..19` (integer literal bounds), union across subrange-typed sets.
- `t095_set_char_subrange.pas` — `set of 'a'..'z'`, `set of 'A'..'Z'`, constructors `['A'..'E', 'Z']`, difference across subrange-bound sets.
- `t096_set_enum_subrange.pas` — `Weekday = set of Day(Mon..Fri)` and `Workdays = set of Mon..Fri`; covers both named and literal enum-subrange forms plus union across compatible bases.
- `t097_typed_const_set_subrange.pas` — typed constants over integer- and enum-subrange set types.

**Negative tests shipped:**

- `n004_set_neg_bound.pas` — `set of -5..5` rejected: "set base type may not include negative values".
- `n005_set_oob_bound.pas` — `set of 0..300` rejected: "set base type too large".
- `n006_set_inverted.pas` — `set of 10..5` rejected: "inverted range".
- `n007_set_enum_oor.pas` — `set of Mon..Happy` (bounds from different enum types) rejected: "subrange bounds must belong to the same enum type".

**Documentation updates:**

- `doc/compact-pascal-ref.md` — no production change; remove any language that suggests the feature already works if a reader might misread it. Add a one-line "bitmap is anchored at ordinal 0, so the low end of the subrange reserves but does not waste ordinals" note under Representation.
- `doc/compact-pascal-wp.md` grammar appendix — no change; `SetType = 'set' 'of' SimpleType` already covers the new cases.
- This file — flip the Phase 1c checkbox to `[x]` and reference the test IDs when shipped.

**Dependencies and risks:**

- No new runtime support needed. All ops reuse existing small/large-set codegen.
- Risk: the anchor-at-0 decision means `set of 200..255` reserves 32 bytes even though only 56 bits are meaningful. Acceptable at Phase 1; revisit if memory pressure shows up in real programs.
- Risk: `{$R+}` range-check extension must subtract `arrLo` only at the *diagnostic* level (reject out-of-range), not at the encoding level. Guard this in the checker design so we don't regress the trivial membership-test codegen.

---

# Roadmap to Production (Phases A–I)

Adopted 2026-07-31. Supersedes the phase numbering above for all work after
Phase 1c; the older Phase 2–9 entries remain as background but the sequence
below is what gets executed.

Produced by a five-dimension survey of the repo (spec, compiler, test/release,
embedding, docs) followed by three competing roadmaps and an adversarial
judging pass. Risk-first sequencing won: phases are capped at three weeks so
estimation error stays bounded, and the decisions that cannot be walked back
once users exist are made first.

**Target: 1.0 declared at the end of Phase F. Roughly 16 weeks solo.**

1.0 means *trustworthy*, not *capable*: closed specification, gated CI, a proven
embedding, and failures that are loud rather than silent. It is deliberately
still stack-only, single-file, and heapless. Phases G through M are what make
the language capable enough to write arbitrary programs in, and they roughly
double the total. Naming them here rather than leaving them implied, because
"when can I allocate memory" and "can a program span files" are the first two
questions a prospective user asks.

## Decisions made up front

These were settled before any code, because each is expensive or impossible to
reverse later.

**1. FFI snapshot hang: fix in `cpas.pas`.** Not a documented workaround. The
hypothesis is already recorded below (FPC RTL text-mode I/O) with a planned
fix (migrate to `BlockRead`/`BlockWrite`), so Phase B is validating a stated
hypothesis rather than open-ended debugging. If the root cause turns out to sit
in the FPC RTL and is genuinely unreachable from `cpas.pas`, fall back to
documenting it and move on, but do not budget for that outcome.

**2. C embedding library deferred past 1.0. Zig dropped entirely.** Three
libraries in flight means three incomplete ones; Rust is the proof that the
embedding story works, and C follows only if that proof holds. Zig is not
deferred, it is removed: the Zig project adopted a no-AI-contribution policy,
and this compiler is substantially machine-written, so a Zig binding cannot be
contributed in good faith. Public docs should state plainly that Zig support is
not planned, without editorializing about the reason.

**3. Tutorial is maintained best-effort and is not up for archival.** The
judging pass recommended archiving the student compiler as a duplication
liability. Rejected. The tutorial is the project's strongest adoption asset,
and building a second compiler against the language is the best pressure test
the design gets — it has already caught real problems that the main compiler's
own test suite did not. Best-effort means: update it when a phase changes
something it teaches, do not gate merges on it, and accept bounded drift.

**4. 1.0 is declared at the end of Phase F.** Spec closed, CI gated, FFI
reliable, safety instrumentation in place, Rust library production-grade. The
method/module work in Phases H–I is 1.0.x and beyond, not a prerequisite.

**5. The self-hosting fixpoint stays byte-identical.** Never relaxed to
semantic equivalence. This forecloses non-deterministic optimization passes:
any optimizer must be deterministic and idempotent, or stay behind a compile
-time flag as the peephole pass already does.

## Phases

### Phase A: Specification closure — 3 weeks

Close every semantic gap while the spec is still cheap to change. Once users
exist, a spec change is a breaking change.

- [x] Four methods/interfaces gaps from `notes/spec-review-methods-interfaces.md`:
      receiver addressability (forbid pointer-receiver calls on temporaries),
      field/method name collision (forbid), the standalone-vs-implement-block
      seam, interface value lifetime. Also corrected the "structural typing"
      label and parenthesized the method receiver. See Findings.
- [x] Publish the frame-size constraint: frame size is fixed before body
      codegen (`cpas.pas:7743`), why that blocks caller-allocated temporaries,
      and what Phase D does about it. In the reference under Runtime Model /
      Stack, with the absence of stack overflow detection stated alongside it.
- [x] Specify the currently-unstated semantics: integer overflow, uninitialized
      variable contents, implicit conversions, identifier shadowing, parameter
      aliasing, forward-declaration mismatch, string comparison ordering, set
      bound errors. Reference gained a "Defined and Undefined Behavior" section;
      every rule was verified against the compiler, not inferred. Turned up four
      defects, one fixed and three open. See below.

**Defects found while verifying semantics.** Documenting behavior meant running
it, which is why these surfaced now rather than from a failing test.

- [x] `writeln` and `str` formatted -2147483648 as digit characters below `'0'`.
      Both formatters negated a negative value first, and `0 - INT_MIN`
      overflows back to itself. Fixed in a1fc117; both now carry a sign
      multiplier instead. Test t101.
- [x] Set membership with an out-of-range ordinal returned a wrong answer
      instead of `false`. Both representations were affected: the small set
      aliased via WASM's five-bit shift mask, and the large set read past its
      own storage. Fixed by clamping the ordinal to 0 for the access and
      masking the result with an unsigned range test, which also rejects
      negatives. Branchless, and the large-set load can no longer leave the
      set. Test t102.
- [x] A `forward` header that disagreed with the definition was not diagnosed.
      A differing parameter count emitted a module that failed WASM validation;
      a differing return type was accepted silently. TFuncEntry now retains
      each parameter's type and type index alongside the var/const flags, and
      the definition compares parameter count, types, var/const markers, return
      type, and procedure-versus-function against the forward. Tests n011, n012.
      Both remaining semantics defects are now closed.
- [ ] Decide whether `byte`, `word`, and `shortint` should enforce their nominal
      ranges. Today all four narrow names are aliases for `integer`: `sizeof`
      is 4 and `b: byte; b := 300` holds 300 even under `{$R+}`. The reference
      now documents the alias behavior, so this is a deliberate decision either
      way, not a silent contradiction. Enforcing would mean range checks on
      assignment under `{$R+}` and a storage-size decision for records.
- [x] Conformance statement: what a conforming implementation must do, what is
      an error, what is undefined. Reference gained a "Conformance" section with
      requirements, the error/trap/undefined distinction, and a minimum-limits
      table. Every limit in the table was verified by compiling at and over it.
- [x] Stability policy: CalVer 26.x is beta, 1.0 is the first stable series,
      breaking changes announced one release ahead. Reference gained a
      "Versioning and Stability" section naming what the 1.x promise covers
      (syntax and semantics, diagnostic format, CLI, module contract) and what
      it does not (emitted bytes, internal helpers, performance, deferred
      features).
- [x] Verify the EBNF appendix matches the prose and is actually LL(1). Done
      against the skill's verification procedure. Structural integrity is now
      clean: no undefined non-terminals, no left recursion, and the nine
      unreachable productions are all scanner-level and documented as such.

**Grammar audit findings.**

- Two undefined non-terminals: `Initializer` referenced `StringLiteral` where
  the token is `STRING_LITERAL`, and `EOL` was used by `Comment` but never
  defined. Both fixed.
- `SubrangeType` is **not decidable by fixed lookahead**. A `Constant` is a full
  `ConstExpr`, so `chr(65)..chr(90)` and `Day(Mon..Fri)` agree through
  `Identifier '('` and diverge only at the matching `')'`. The compiler resolves
  it semantically, by asking whether the identifier names a type, which
  declare-before-use makes reliable. Now documented rather than claimed LL(1).
- Four LL(2) productions were undocumented: `SimpleType`, `ConstDef`,
  `VariantPart`, and the new `Initializer`. All annotated. With `AddOp` and
  `MulOp`, which were already annotated, that is six LL(2) productions in a
  grammar that is otherwise LL(1).
- The reference's `Initializer` was **missing `RecordInitializer` and
  `SetInitializer`** even though record and set typed constants are implemented
  and tested (t091, t092, t097, t099). The white paper had them and the
  authoritative document did not. Added, with `FieldInit` and `SetElem`.
- White paper divergence, now synced: it still had the pre-parenthesis
  `Receiver`, listed `'true'`/`'false'` as `Factor` terminals where the
  reference treats them as built-in identifiers, claimed variant records cannot
  be initialized, and shared the `StringLiteral` casing bug. Production names
  now match exactly across both documents.
- Prose-versus-implementation gaps found by parsing probes, left as documented
  restrictions rather than silently wrong grammar: `StringType` allows a general
  `Constant` but the compiler requires an `INTEGER_LITERAL`, so `string[N]` with
  a named constant is rejected. `PointerType`, `ProceduralType`, `InterfaceType`
  and named subrange types are in the grammar and unimplemented, which is
  expected and tracked in cpas-status.md.
- `RUNE_LITERAL` is defined but unreferenced. Correct for a future extension;
  annotated with where it will need to be wired in.

**Exit:** no TODO markers in the reference; every gap above has an explicit
rule; an external reviewer reads it end to end with no open questions.

### Phase B: FFI snapshot hang — DONE, well inside the 1.5-week cap

- [x] Reproduce with a minimal `{$IMPORT}` + `external` source. Does not
      reproduce on any current snapshot, under wasmtime or wasmi, in any of
      six source shapes tried.
- [x] Validate the text-mode I/O hypothesis. **Rejected.** The snapshot is
      built by cpas, not fpc, so it contains no FPC RTL to blame. Bisecting the
      checked-in snapshots put the fix at `ee481a9`, the for-loop `continue`
      codegen fix, and the snapshot one commit earlier reproduces the hang
      exactly as recorded.
- [x] ~~Migrate compiler I/O to `BlockRead`/`BlockWrite`~~. Not needed for this
      defect. Worth doing on its own merits some day, but it is not Phase B and
      should not be justified by this finding.
- [x] Remove the `compile_native` workaround. All four Rust FFI tests now
      compile through wasmi; `snapshot_compiles_import_bearing_source` pins the
      scenario so the workaround cannot return.

**Exit:** the WASM snapshot compiles import-bearing sources in under 5s;
`compile_native()` is no longer needed as a workaround in the Rust tests.

**Stop rule:** if the root cause is not identified within one week, stop
investigating, document the workaround, and proceed. Do not let this reach
week three.

### Phase C: CI and fixpoint gating — 1.5 weeks

- [x] `.github/workflows/test.yml`: full suite plus byte-for-byte fixpoint
      check on every push and PR. Adds `make check-fixpoint`, which also
      catches a stale committed snapshot, not just a broken fixpoint.
- [x] Platform matrix: Linux, macOS, and Windows under Wine, all blocking.
      Target is **win64, not win32**: Ubuntu's `fp-units-win-rtl` ships
      `x86_64-win64` units, so the host `ppcx64` cross-compiles directly with
      no i386 cross-compiler and no multiarch. The first CI run failed on that
      wrong assumption; the job's preflight step reported it as a CI setup
      problem rather than a compiler defect, which is what it was designed to
      do. Verified end to end locally before re-enabling: extracted the units
      from the `.deb` without installing, cross-compiled, ran under Wine, and
      confirmed byte-identical output. Blocking from the start as a result.
- [ ] **Release artifact.** A CI rule that zips `snapshot/compiler.wasm` with a
      short README covering `wasmtime run compiler.wasm < prog.pas > prog.wasm`
      and attaches it to a tag. Least-effort distribution: no packaging, no
      installer, no platform matrix, just the one file that already works
      anywhere wasmtime does. Today the answer to "how do I get this" is "clone
      the repo and install fpc", which is not an answer. Feeds the 1.0 release
      story in Phase F.
- [x] Local `make test-all` running the same matrix a developer can reproduce.
      Verified against a fresh clone.
- [x] Pin `fpc`, `wasmtime`, and `wasm-validate` versions. Implemented as
      assertions rather than version-locked installs: the protection wanted is
      that a toolchain change is loud, and asserting gives that without
      fighting each platform's package manager. fpc is asserted exactly,
      wasmtime and wabt on major version.
- [ ] Branch protection: no merge without green CI.
- [x] Run `make check-private` in CI so no commit can add a local filesystem
      path. Blocking, and cheap: it is a `git grep` over tracked files.
- [ ] Decide how the personal layer of that guard reaches CI, or accept that
      it does not. `compiler-tests/check-private-info.sh` reads per-clone
      patterns from `.git/info/private-patterns`, which is deliberately never
      committed: writing a personal domain into a tracked file in order to
      block it would publish the string it is meant to keep out. CI therefore
      runs the generic layer only unless the list is injected from a repository
      secret. Recommendation: leave CI generic-only. The personal layer catches
      a mistake on the machine that would make it, which is where the mistake
      happens; a secret buys little and adds a way for the pattern list itself
      to leak through CI logs.
- [x] Publish `ROADMAP.md` (public; `PLAN.md` is the working document) and fix
      the README, which still advertised Rust + Zig + C embedding. Zig is gone
      from the README, the Makefile, and the phase table; the reason is stated
      in ROADMAP.md without editorializing.

**Exit:** a commit that breaks the fixpoint by one byte cannot be merged, and
one that adds a home-directory path fails the same way.

### Phase D: Runtime safety instrumentation — DONE, in one session rather than a week

The load-bearing phase. Debugging silent memory corruption costs more than the
instructions these checks add, and the frame-balance work here is what unblocks
caller-allocated temporaries (structured and string returns) later.

- [x] **Stack overflow guard. Land this first and alone if the rest slips.**
      The stack grows down from memory top with no guard; deep recursion
      currently walks through the heap and data segment into the nil guard,
      silently. Prologue traps if SP drops below the data end. Roughly five
      instructions per frame, and the cheapest debugging win available: a few
      wasted cycles against hours spent chasing corruption that has no
      symptom at the point it happens. A teaching compiler should have had
      this from the first milestone. Keep it simple; a compare and a trap, no
      guard pages, no red zone.
- [x] **Frame balance.** Restore SP at the epilogue from the recorded frame
      base instead of the relative `SP += frameSize`. This is not only a
      check: it makes an unbalanced stack allocation self-healing at function
      return rather than desynchronizing SP for the rest of the program. Under
      `{$S+}` the expected value is asserted first and a mismatch traps.
      Implemented without a new WASM local: `display[curNestLevel]` already
      holds the frame base, is set in the prologue right after the allocation,
      and is saved and restored across recursion. See Findings.
- [x] New `{$S+/-}` directive, default **ON** pre-1.0. Silent corruption is
      worse than the code size. Revisit the default at 1.0.
- [x] Run the whole suite twice in CI, checks on and checks off. `make
      test-checks`, driven by a `CPASFLAGS` environment variable the runner
      passes through to the positive and negative compilations.
- [x] Flip `{$R+}` on for the test suite even though the language default stays
      off. Done with new `-R+/-` and `-S+/-` command-line switches that set the
      state a file starts with, rather than editing every test. A test that
      must pin a setting regardless does so with a directive in its source;
      `t104` pins `{$S+}` so the checks-off run still proves the guard traps.

**Exit:** suite passes in both configurations; a deliberately over-deep
recursion traps instead of corrupting; a deliberately leaked stack allocation
is contained to its function.

**Why before pointers:** pointers add new corruption modes, and this phase is
what makes them debuggable rather than mysterious.

### Phase E: Pointer types — DONE, in one session rather than two weeks

Scoped deliberately to what does *not* need frame allocation. Pointers that
only reference existing storage (`@x`, `p^`, `nil` comparison, pointer
parameters, pointers in records) are implementable and testable without
touching the frame convention, even though a pointer type with no heap behind
it is not yet useful on its own. `New`/`Dispose` and the heap stay in a later
phase.

- [x] `^T` type declarations, `p^` dereference, `@x` address-of. Also forward
      references (`PNode = ^TNode` before `TNode`), which were not in the
      original scope but are the reason pointers exist in Pascal. See Findings.
- [x] `nil` literal, comparison, and the nil check under `{$S+}`.
- [x] Pointers as parameters, record fields, and array elements.
- [x] Negative tests: dereferencing nil traps under `{$S+}`, type mismatch
      rejected, ordering comparison rejected, unresolved forward reference
      rejected, writing a pointer rejected.

**Exit:** pointer tests pass in both check configurations; fixpoint holds.
Both met: 131 tests in each configuration, snapshot self-hosts.

**Left open deliberately.** `with p^ do` is rejected: the `with` statement's
own designator paths do not take a `^` selector. It is a clean compile error
rather than a miscompile, and `p^.field` covers the same ground. The compiler
has five near-identical selector loops; two of them, the expression and
assignment paths, learned `^`, and teaching the other three is better done by
first collapsing the duplication.

Pointer assignment checks the type tag but not the
target type, so `^integer := ^TRec` compiles. The expression parser reports its
result type in a global but keeps the descriptor index in a local, so the
target is not visible to the assignment paths. Closing this means threading the
descriptor index out of `ParseExpression`, which is worth doing once rather
than patching around. Recorded in the reference under Defined and Undefined
Behavior so nobody mistakes it for a language rule.

### Phase F: Rust embedding to production grade — DONE except for cutting the release

- [x] Complete the WASI bridge: `fd_read`, `fd_write`, `proc_exit`, args.
      `args_sizes_get`/`args_get` were stubs returning zero arguments; both now
      serve a real vector, which is what makes `Options` possible. `fd_write`
      and `fd_read` validate the descriptor instead of reporting success for
      one that does not exist. See Findings.
- [x] Error handling returning `Result` with actionable diagnostics, parsing
      the tagged `Error:`/`Warning:` stream the compiler now emits.
      `CompileError` distinguishes a rejected program from a compiler fault
      from an unresolved include, which decides whether to blame the source or
      file a bug.
- [x] Three end-to-end examples: hello, calculator, host callback. Each is
      covered by an integration test and run in CI, so a broken example fails
      the build rather than waiting to be found by a reader.
- [x] `EMBEDDING-GUIDE.md` and a published API stability policy. Writing the
      guide exposed a gap and closed it: the sandbox section wanted to say
      "impose limits from the host side" and there was no way to. New `Limits`
      type exposes wasmi's fuel metering and memory ceiling.
- [x] Governance: `SECURITY.md` with a disclosure process, `CHANGELOG.md`,
      contribution guide, license clarity. License settled on CC0-1.0 by the
      maintainer; see Findings.
- [x] Zig removal: delete the Makefile targets and README/doc references. The
      Makefile targets were already gone; the prose was not.

**Exit:** a third party can add the crate, compile and run a Pascal program,
get a useful error from a bad one, and file a bug against a documented process.
All four hold. **Declaring 1.0.0 is deliberately not done here** — it is a
publishing decision, and the standing rule is not to bump a version until the
maintainer asks. Everything a 1.0 needs is in place; cutting it is one commit
setting `Cargo.toml` to `1.0.0`, dating the `Unreleased` section of
`CHANGELOG.md`, and tagging.

### Phase G: C library decision gate — DONE, dropped

Decided: the C library does not ship and is removed from the tree, along with
the vendored copy of wasm3 it never used. Recorded publicly in `ROADMAP.md`
under "What is deliberately not planned", which is where the Zig decision also
lives. See Findings for the assessment behind it.

- [x] Assess what actually existed rather than what the checklist claimed.
- [x] Decide, and record the decision and rationale publicly.
- [x] Remove `src/c`, `vendor/wasm3`, and the Makefile targets.
- [x] Keep `examples/c/hello` as a reference sample, labelled as documentation
      rather than as a library, with build instructions against upstream wasm3.
- [x] Correct every document that described the C library in the present tense.

### Phase H: Structured and string return types — DONE

Depends on Phase D. `function F: string` is natural Pascal and is currently
rejected outright with "return type expected"; the reference documents it as an
unimplemented extension. The blocker was never the parser. A caller-allocated
result buffer needs stack space whose count is not known when the frame
prologue is emitted, and a leaked allocation used to desynchronize SP silently.
Phase D's epilogue change, restoring SP from a saved local, makes such a leak
self-healing at function return, which is what makes this implementable.

- [x] Accept `string`, `string[n]`, records, and arrays as return types. The
      return type must be a name or `string`/`string[n]`; an anonymous record
      or array is rejected, since a caller cannot name that type.
- [x] Hidden result pointer as the trailing parameter, which lands on the index
      the scalar result local already occupies, so the epilogue and
      `FuncName := expr` need no reindexing. This part worked exactly as
      written.
- [x] Caller allocates the buffer from SP and restores at end of statement.
      `exit`, `break`, and `continue` are NOT covered by the Phase D epilogue,
      contrary to the plan: each branches past the release, and the balance
      check runs before the epilogue restores. They release explicitly. Loops
      release per iteration so a long loop cannot accumulate. See Findings.
- [x] Reject a string return on an `external` declaration: the host cannot be
      handed a buffer this way.

**Exit:** a function returning a string can be assigned, passed, concatenated,
and written; suite passes with checks on and off; fixpoint holds. All met: 138
tests in both configurations, fixpoint holds.

**Not supported, deliberately:** assigning to a field or element of the result,
`MakePoint.x := 1`. It is ordinary Pascal and it is a compile error naming the
limitation rather than a mystery about a missing `end`. Build the value in a
local and assign the whole thing. Supporting it means treating the function
name as a designator over the hidden parameter, which is the same selector-loop
duplication that `with p^ do` ran into; both should be fixed together after the
five near-identical loops are collapsed.

### Phase I: Heap — `New` and `Dispose` — DONE

Depends on Phase E. The hard ceiling on what programs are expressible: today
every size is fixed at compile time, so no list, tree, or growable buffer can
be written at all.

- [x] Free-list allocator in linear memory, growing upward from the data
      segment end toward the stack. First fit, 8-byte header, no splitting and
      no coalescing.
- [x] `New(p)` and `Dispose(p)`, sized from the pointer's target type.
      `Dispose` also clears the pointer, which standard Pascal does not; see
      Findings.
- [x] Collision detection against the stack pointer. It is one shared
      boundary rather than two checks: the Phase D global became mutable and
      the allocator raises it, so each side is guarded by the other's check.
      Unconditional rather than under a directive, since a soft failure would
      mean returning nil and no program checks for it.
- [x] Document the allocator's guarantees: no splitting, no coalescing, no
      compaction, no garbage collection, no return to the heap end, and
      exhaustion traps rather than returning nil.

**Exit:** a linked list and a binary tree build, traverse, and free without
leaking; a deliberate heap-stack collision traps. All met: `t113` is the list,
`t114` the tree plus two thousand allocate-free cycles that do not grow the
heap, `t115` the collision.

### Phase J: File system access and the `text` type — DONE

Two things at once, because they are the same underlying work: the compiler
needs to read files for `{$I}`, and programs need file I/O for anything real.

Today `{$I}` is expanded by the host before the compiler sees it, so the
standalone compiler cannot build a multi-file program at all. It silently skips
the directive and then fails on the undeclared identifier, which is a poor
diagnostic for what is really a missing capability.

- [x] WASI file access: `path_open`, `fd_read`, `fd_write`, `fd_close`. Host
      grants a preopened directory; nothing is reachable outside it. `fd_seek`
      is not imported: text I/O is sequential and nothing in the phase needs
      it. Add it when a `file of T` type wants random access.

      Gated behind a new `{$FILES ON}` global directive rather than always
      present. Registering them unconditionally broke every Rust host, since
      the embedding bridge implements five WASI functions and a module
      importing seven cannot instantiate. See Findings.
- [x] The `text` type, promoted from the two predefined handles to a real
      type. A 536-byte control block per variable rather than a handle table:
      the block holds the descriptor, the buffer, and the name Assign
      recorded, so no side table has to be kept in step with variable
      lifetimes.
- [x] `Assign`, `Reset`, `Rewrite`, `Close`, `ReadLn`, `WriteLn`, `Eof`,
      `IOResult`, with the TP semantics including the clearing. `Eof` looks
      ahead rather than reporting a read that already failed; see Findings.
- [x] Compiler-side `{$I}`: the compiler resolves and expands includes itself
      under `-I`. The host-side path stays supported and is still the default,
      so an embedder that already expanded them does not open them twice.
- [x] Nesting depth limit and a cycle check on includes, both diagnosed. The
      depth is a fixed array of eight text blocks, so the limit is in the
      language reference rather than being whatever the stack allowed.

**Exit:** the compiler compiles a multi-file program from the CLI with no host
help; a program opens, writes, reopens, and reads back a file; `IOResult`
reports a missing file rather than trapping under `{$I-}`. **Not yet met.**

**All four exit conditions met.** `t117` writes, reopens, and reads a file;
`t118` and `t119` pin IOResult against a missing file with checks off and on;
`c006` through `c008` cover the include path — a working multi-file build, a
missing file, and a cycle.

The include stack is a fixed array of eight text blocks, chosen over a stack of
locals so the depth is a specified limit in the reference rather than a
consequence of how much stack happened to be available.

### Phase K: System units — 2 weeks

A system unit looks like a unit at the use site but is not compiled: it names a
set of bindings already built into the runtime. This gets the `uses` syntax and
the name resolution working against a fixed, known set of symbols, before any
of the separate-compilation machinery exists.

- [ ] `uses` clause parsing and scope injection.
- [ ] A binding table per system unit, resolved at compile time to existing
      intrinsics and WASI imports.
- [ ] Split the current always-on builtins into named units, keeping the
      current set available without `uses` for compatibility.

**Exit:** a program that says `uses Files;` gets the Phase J file routines and
a program that does not, does not.

### Phase L: Pascal units — 6 weeks, split

Real separate compilation: write a unit, compile it independently, use it from
another program. Substantial, and the largest single item on this roadmap. It
exceeds the three-week phase cap deliberately and is split so the design can be
reviewed before the implementation starts.

**L1, design and specification, 2 weeks.** Supersedes the old "module system
design" item.

- [ ] `unit` / `interface` / `implementation` syntax, and how it stays
      single-pass.
- [ ] A compiler-generated interface description consumed by importers, rather
      than a hand-written header. The spec review in `notes/` and Excelsior
      independently reached the same conclusion, which is decent evidence.
- [ ] How a unit maps onto a WASM module: one module per unit, or link-time
      merge. This is the decision that constrains everything after it.
- [ ] Initialization order, and whether a unit may have an initialization
      section at all.

**L2, implementation, 4 weeks.** Only after L1 is settled.

**Exit:** a three-unit program compiles from the CLI, each unit compiled
separately, and recompiling one unit does not require recompiling the others.

### Phase M: Method pointers and interfaces — 3 weeks

Procedural types, then the standalone methods and `implement` blocks whose
design Phase A settled. Last because it is the only remaining item that nothing
else depends on.

## Open decisions

Small, tracked so they are not lost. None blocks a phase.

- **Do `byte`, `word`, and `shortint` enforce their nominal ranges?** Today all
  are aliases for `integer`: `sizeof` is 4 and `b: byte; b := 300` holds 300
  even under `{$R+}`. The reference documents the alias behavior, so this is a
  decision either way rather than a silent contradiction. Enforcing means range
  checks on assignment and a storage-size decision for records.
- **Should `string[N]` accept a named constant for the length?** The grammar
  allows a general `Constant`; the compiler requires an `INTEGER_LITERAL`.
  Found in the Phase A grammar audit and recorded as a restriction.
- **When to bump the CalVer version.** Held at 26.04.1 through all of Phase A
  and B per the rule about waiting for an explicit publish, though the
  reference has changed substantially. Bumped to 26.08.0 when Phase C was
  tagged as a release.

## Standing invariants

Checked at every phase boundary without exception. A violation means the phase
is not done.

1. **Fixpoint is byte-identical.** fpc-built and self-compiled snapshots match
   exactly. One byte of divergence is a regression until proven otherwise.
2. **No test regressions**, in both check configurations after Phase D.
3. **CI is green** on Linux, macOS, and win32-under-Wine.
4. **The spec is self-consistent**: grammar matches prose, examples compile.
5. **Diagnostics stay on stderr.** The module goes to stdout; a diagnostic on
   the wrong stream corrupts output rather than merely looking untidy.
6. **No stray compiler output.** Positive tests without a `.warning` file must
   compile with nothing on stderr at all.

## Leading indicators that this is going wrong

- Fixpoint diverges and the cause is not found same-day. Roll back rather than
  investigate forward.
- A phase passes its estimate by more than half. Cut scope, do not extend.
- Phase B reaches week two without a root cause. Take the fallback.
- The tutorial has not been touched across two consecutive phases that changed
  language behavior. Best-effort has quietly become never.
- Checks-on and checks-off configurations start disagreeing. That is a real
  codegen bug, not a test problem.

## Deliberately not doing

Recorded so these do not get relitigated: Zig bindings (dropped), C library
before 1.0 (deferred), LSP and editor extensions (the playground suffices),
source-level debugger (WASM traps are acceptable), exception handling
(incompatible with single-pass), dynamic arrays and generics, `real` and
floating point, `rune` and Unicode, separate compilation before Phase I,
shipping the peephole optimizer on by default (0.04% code size on
self-compilation does not justify it; keep it behind `-dPEEPHOLE`).
