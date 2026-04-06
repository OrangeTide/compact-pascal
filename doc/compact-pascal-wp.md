---
title: "Compact Pascal: An Embeddable Pascal-to-WASM Compiler"
author: Jon Mayo
date: March 2026
header-includes:
  - |
    ```{=typst}
    #align(center, image("doc/compact-pascal-cover.svg", width: 50%))
    #v(0.5em)
    #align(center, text(weight: "bold", size: 12pt, fill: rgb("#cc0000"))[DRAFT — This document is a work in progress and subject to change.])
    ```
---

## Abstract

This document proposes **Compact Pascal**, a new programming language in the Pascal family, and a portable toolchain for embedding it in Rust and Zig applications. The compiler is written in Pascal itself, compiles to WebAssembly (WASM), and ships as a self-contained WASM binary that host applications execute via an interpreter. The result is a lightweight, embeddable Pascal environment that runs anywhere WASM runs — native applications, browsers, and edge runtimes — with no external dependencies beyond the host language's standard toolchain.

## Introduction

### Motivation

Pascal has a long history as a language for teaching, systems programming, and compiler construction. Its clear syntax, strong typing, and structured design make it well-suited for domains where correctness and readability matter. However, modern Pascal implementations (Free Pascal, Delphi) are large, monolithic toolchains that cannot be easily embedded in other applications or run in constrained environments like WebAssembly.

At the same time, WebAssembly has emerged as a universal compilation target — a portable, sandboxed bytecode format supported by browsers, server runtimes, and embedded systems. WASM's design as a compilation target (not a source language) creates an opportunity: a language compiler that *itself* runs as WASM can be embedded in any host environment, turning the compiler into a library rather than a standalone tool.

Compact Pascal exploits this opportunity. It is a minimal Pascal variant designed from the ground up to:

1. **Compile to WASM 1.0 (MVP)** for maximum portability.
2. **Run as WASM** so the compiler itself is embeddable.
3. **Require no I/O runtime library** — I/O intrinsics (`write`/`read`) compile to WASI host imports, so the runtime footprint is minimal and programs without I/O have no implicit imports.
4. **Support single-pass compilation**, keeping the compiler fast and simple — especially important when the compiler runs inside a WASM interpreter.
5. **Extend Pascal thoughtfully** with modern features (structural interfaces) that respect the language's character while addressing real gaps.

### Relationship to Existing Pascal Standards

Compact Pascal draws inspiration from several sources in the Pascal family:

- **ISO 7185 (Standard Pascal)** [1] provides the syntactic and semantic foundation: block structure, strong typing, the declare-before-use rule, and the core type system.
- **ISO 10206 (Extended Pascal)** [2] informs the dynamic memory model (`New`/`Dispose`) and serves as a reference for language extensions.
- **Component Pascal / Oberon** [3] (Wirth's later Pascal-lineage languages) inspire the minimalist philosophy: a small, coherent language rather than a feature-laden one.
- **Go** [4] provides the model for structural interfaces — polymorphism without inheritance.
- **Pascaline / IP Pascal** [20] demonstrates that Pascal can be extended with modules, dynamic arrays, and concurrency while preserving full ISO 7185 compatibility and type safety. Compact Pascal's `const` parameters, `forward` declaration style, and eventual dynamic array design draw on Pascaline's precedent.
- **SuperPascal** [21] and the broader Brinch Hansen tradition (Concurrent Pascal [22], Joyce [23]) show that safe concurrency can be expressed in Pascal-family syntax. SuperPascal's single-pass disjointness checking — verifying at compile time that parallel processes do not interfere — is a technique Compact Pascal could adapt if concurrency is added in a future phase.
- **ParaSail** [24] takes the radical approach of eliminating pointers, global variables, and aliasing entirely, making every expression safe for parallel evaluation. Its region-based memory management (no global GC heap) and Hoare-style assertions built into the syntax are relevant models for future Compact Pascal extensions.
- **Vector Pascal** [25] extends Pascal with APL-derived array operations (maps, reductions, slicing) that map to SIMD hardware. Its dimensional type system (compile-time unit checking for scientific quantities) is an independently interesting extension model.

Compact Pascal is not a conforming implementation of any existing Pascal standard. It is a new language that inherits Pascal's syntax and values while making deliberate departures where they serve the goals of embeddability, simplicity, and WASM compatibility.

### Design Principles

- **Minimalism.** Include only what is needed. Features earn their place by being essential to the language's purpose, not by precedent.
- **Embeddability.** The compiler and runtime must function as a library, not a standalone tool. No implicit I/O, no filesystem access, no assumptions about the host environment.
- **Single-pass friendliness.** The language design should not require multi-pass compilation. Declare-before-use, explicit interface conformance blocks, and forward declarations keep the compiler simple and fast.
- **Portability.** Target WASM 1.0 MVP only. No WASM extensions, no platform-specific features, no assumptions beyond what the MVP specification guarantees.
- **Interoperability.** Host applications (Rust, Zig, browser JavaScript) must be able to call into Pascal code and provide functions that Pascal code can call, through WASM's import/export mechanism.

### Non-Goals

Compact Pascal deliberately excludes several features common in modern languages. These are not oversights — each was evaluated against the project's constraints and found to conflict with single-pass compilation, the WASM 1.0 target, the self-hosting requirement, or the language's minimalist character.

- **Traits and bounded generics.** Rust-style trait bounds require either monomorphization (multi-pass, code explosion) or dictionary passing (complex calling convention). Both conflict with single-pass compilation. The Go-style structural interfaces planned for a later phase provide polymorphism without generics machinery.
- **Monomorphized generics.** Template instantiation is fundamentally multi-pass — the generic body must be stored and replayed for each type argument. This conflicts with the single-pass architecture and grows WASM output.
- **First-class closures.** Nested procedures already capture enclosing variables, but making them first-class values requires heap-allocated closure environments and fat-pointer dispatch (`call_indirect` + environment pointer). Procedural types (function pointers without capture) are supported; full closures are deferred.
- **Reflection and RTTI.** Runtime type descriptors cause code size explosion and complicate single-pass emission. In the embedding model, the host already has full visibility into guest memory and can provide serialization via FFI.
- **Async/await.** Requires continuation-passing transformation or stackful coroutines, neither of which is compatible with WASM 1.0 or single-pass compilation. The host manages concurrency; guest code runs synchronously.

Some features are compatible with the architecture and may be interesting as future extensions or student projects: exceptions (implementable via WASM `block`/`br` chains), operator overloading (symbol table dispatch), and pattern matching (destructuring `case` statements).

## Architecture

### Overview

The system has three layers:

```{=typst}
#align(center, image("doc/compact-pascal-arch.svg", width: 100%))
```

```{=html}
<pre>
┌───────────────────────────────────────────────────┐
│  Host Application (Rust / Zig / Browser JS)       │
├───────────────────────────────────────────────────┤
│  Embedding Library (compact-pascal crate/module)  │
│                                                   │
│  ┌────────────────┐   ┌───────────────────────┐   │
│  │ WASM Runtime   │   │ Host–Guest FFI        │   │
│  │ (wasmi / wasm3)│   │ (imports / exports)   │   │
│  └────────────────┘   └───────────────────────┘   │
├───────────────────────────────────────────────────┤
│  Compiler (WASM blob, written in Pascal)          │
│  source → fd 0 → compiler → fd 1 → .wasm         │
├───────────────────────────────────────────────────┤
│  Compiled Program (WASM module)                   │
│  executed by the same WASM runtime                │
└───────────────────────────────────────────────────┘
</pre>
```

1. **The compiler** is a Pascal program compiled to WASM. It reads Compact Pascal source from fd 0, writes a WASM binary to fd 1, and writes errors to fd 2. It ships as a snapshot blob embedded in the library.
2. **The embedding library** (one for Rust, one for Zig) bundles the compiler blob and a WASM interpreter. It provides a high-level API: compile source, instantiate modules, register host functions, call exported procedures.
3. **The host application** uses the embedding library to compile and run Pascal code, providing whatever host functions the Pascal program needs through WASM imports.

### Core Language

The core is a minimal subset of Pascal sufficient for systems programming and compiler construction: integer, boolean, char, and string types; arrays, records (including variant records), set types, and pointers; standard control flow (including `with` for record field access); procedures and functions with value, `var`, and `const` parameters; nested procedures with access to enclosing scope variables. Floating point (`real`) and dynamic allocation (`New`/`Dispose`) are planned for later phases. The language is case-insensitive; hexadecimal literals (`$FF`) are supported, with optional C-style prefixes (`0x`, `0o`, `0b`) behind a compiler directive.

Source files are UTF-8. The compiler's lexer only acts on ASCII-range bytes (0x00–0x7F); bytes 0x80–0xFF pass through verbatim in string literals and comments. `char` is a byte, not a Unicode codepoint, and `length` returns the byte count — the same model as C and Go's `[]byte`. Legacy source files in CP437 (the code page used by DOS-era Pascal systems) or other encodings must be converted to UTF-8 before compilation using standard tools (`iconv`, `encoding_rs`, etc.).

The familiar I/O procedures `write`, `writeln`, `read`, `readln` are supported as **compiler intrinsics** — the compiler generates calls to `fd_write`/`fd_read` WASM host imports rather than providing a runtime library. The host application must supply these imports, keeping the WASM runtime footprint minimal. There are no file types; all I/O goes through host imports.

### String Representation

Phase 1 uses Turbo Pascal-style short strings: a length byte followed by up to 255 bytes. This representation is identical to Free Pascal in `-Mtp` mode, which is critical for self-hosting — the compiler source must compile under both fpc and Compact Pascal. Short strings require no heap allocator and live on the stack or in records. Strings are byte strings — UTF-8 content is stored verbatim, and `length` returns the byte count. A richer dynamically-allocated string type (pointer + length, no 255-byte limit) is planned for a later phase.

The embedding libraries provide helper functions to convert between host strings (Rust `&str`/`String`, Zig `[]const u8`) and the Pascal representation in WASM memory.

### Standard Functions and Procedures

Compact Pascal includes standard functions and procedures as compiler intrinsics: `abs`, `ord`, `chr`, `odd`, `succ`, `pred`, `sqr`, `length`, `sizeof`, `lo`, `hi`, `inc`, `dec`, `exit`, `halt`, and string operations (`copy`, `pos`, `concat`, `delete`, `insert`). TP-compatible numeric types (`byte`, `word`, `shortint`, `longint`) are also supported. These additions maximize backward compatibility with existing Pascal code and ensure the compiler source compiles naturally on both fpc and Compact Pascal.

### Language Extensions

- **Structural interfaces and methods:** Go-style interfaces with `implement` blocks, designed for single-pass compilation.

The full language specification is maintained in the Compact Pascal Language Reference (`doc/compact-pascal-ref.md`).

### Host-Guest FFI

The embedding libraries expose a bidirectional foreign function interface through WASM's import/export mechanism:

- **Imports (host → guest):** The host registers functions that Pascal code can call. These appear as external procedures in Pascal and are resolved as WASM imports at instantiation.
- **Exports (guest → host):** The host can call Pascal-defined procedures/functions and access Pascal globals through the WASM module's exported symbols.

This is the primary integration point. All I/O, system access, and application-specific behavior flows through imports and exports.

### API Sketch

**Rust:**

```rust
let compiler = compact_pascal::Compiler::new();
let wasm_bytes = compiler.compile(pascal_source)?;

let mut runtime = compact_pascal::Runtime::new();
runtime.register_import("print_int", |val: i32| { println!("{val}"); })?;
let instance = runtime.instantiate(&wasm_bytes)?;
instance.call("main", &[])?;
```

**Zig (conceptual):**

```zig
const cp = @import("compact-pascal");

var compiler = cp.Compiler.init();
const wasm_bytes = try compiler.compile(pascal_source);

var runtime = cp.Runtime.init();
try runtime.registerImport("print_int", printInt);
var instance = try runtime.instantiate(wasm_bytes);
try instance.call("main", &.{});
```

### Compiler I/O Interface

The compiler itself (running as WASM) communicates through the **WASI preview 1** [6] I/O interface. The host must provide these WASM imports from the `wasi_snapshot_preview1` module:

- `fd_read(fd: i32, iovs: i32, iovs_len: i32, nread: i32) -> errno: i32`
- `fd_write(fd: i32, iovs: i32, iovs_len: i32, nwritten: i32) -> errno: i32`
- `proc_exit(code: i32) -> noreturn`
- `args_sizes_get(argc: i32, argv_buf_size: i32) -> errno: i32`
- `args_get(argv: i32, argv_buf: i32) -> errno: i32`

Each iovec is an 8-byte struct in linear memory: `{ buf: i32, len: i32 }`. In practice, the compiler always passes a single iovec (`iovs_len = 1`), making the generated call sequence trivial — two `i32.store` instructions to build the iovec, then the call.

Standard POSIX file descriptors: 0 = stdin, 1 = stdout, 2 = stderr.

The compiler reads Pascal source from fd 0, writes WASM binary output to fd 1, and writes error messages to fd 2. On the first error, the compiler writes a diagnostic to stderr and halts via `proc_exit(1)`.

Because the compiler uses standard WASI, it runs directly under any WASI-compatible runtime (wasmtime, wasmer, wasm3, browser polyfills) without a custom host:

```bash
# Compile a Pascal program to WASM
wasmtime run compiler.wasm < hello.pas > hello.wasm

# Run the compiled program
wasmtime run hello.wasm

# Use the -dump flag to inspect generated WASM instructions
wasmtime run compiler.wasm -- -dump < hello.pas > hello.wasm

# Works identically with wasmer
wasmer run compiler.wasm < hello.pas > hello.wasm
wasmer run hello.wasm
```

Programs compiled by the compiler that use `write`/`writeln`/`read`/`readln` also emit WASI `fd_write`/`fd_read` calls, making them WASI-compatible out of the box. Programs that do not use I/O have no implicit WASI imports.

### WASM Target

The compiler emits **WASM 1.0** (MVP) [5] only — no extensions (bulk memory, multi-value, GC, etc.). This maximizes portability across runtimes and ensures compiled programs run on any compliant WASM implementation.

### WASM Code Generation Strategy

The compiler uses single-pass parsing with **deferred binary output**. WASM binary format requires sections in a fixed order (type, function, memory, export, code), but the compiler discovers functions as it parses. The solution: accumulate each section in a separate in-memory buffer during the single pass, then write all sections in the correct order at the end. This is single-pass *parsing* with buffered output — not multi-pass compilation.

A `-dump` flag emits a human-readable listing of the generated WASM instructions for debugging (not full WAT, just an instruction log). The compiler reads command-line arguments via WASI `args_get` to detect flags like `-dump`.

### Linear Memory Layout

Compiled programs use the industry-standard WASM memory layout, matching LLVM, Rust, and C WASM toolchains:

```
[ nil guard | data segment | heap -> ....... <- stack ]
0           4               data_end         SP    memory_top
```

- **Nil guard (bytes 0-3):** Reserved, zeroed. Dereferencing `nil` (address 0) reads zeros rather than corrupting data.
- **Data segment:** Global variables, string literals, and typed constants, laid out at compile time.
- **Heap:** Grows upward from end of data (Phase 5; unused in Phase 1).
- **Stack:** Grows downward from top of memory. The stack pointer is a mutable WASM global (`$sp`), initialized to the top of memory. Procedure entry subtracts the frame size; exit adds it back.

In Phase 1 (no heap), the entire space between the data segment and memory top is available for the stack.

### Nested Procedures

Pascal supports nested procedures with access to enclosing scope variables. Since WASM functions are all top-level with no closure support, the compiler uses **Dijkstra's display technique** [9] (a classic approach for implementing lexical scoping in flat-address-space targets): a fixed-size array of 8 WASM globals where `display[N]` holds the frame pointer for nesting level N. Accessing an upvalue is always O(1) — two loads regardless of nesting depth. Top-level procedures (the vast majority) emit no display code and pay zero overhead. Maximum nesting depth is 8.

### Memory Management

Phase 1 uses stack-only allocation — all variables (including strings and records) live on the stack or in the data segment. No heap allocator is needed.

**Future (Phase 5):** `New`/`Dispose` with a free-list allocator in WASM linear memory. The heap grows upward from the end of the data segment, toward the stack. Object headers will include metadata (size, mark bits, link pointers) designed to support a future garbage collector.

**Future: Baker's Treadmill GC** [10]**.** A non-moving, incremental garbage collector suitable for WASM linear memory. Requires a shadow stack in linear memory for GC root tracking (since the WASM operand stack is opaque). Deferred until after `New`/`Dispose` is working.

### Error Handling

The compiler halts on the first error with a diagnostic written to stderr (fd 2). It performs no error recovery and reports no subsequent errors. This keeps the single-pass compiler simple — no recovery logic, no cascading false positives.

### WASM Runtimes

| Host Language | WASM Runtime | Rationale |
|---|---|---|
| **Rust** | wasmi [11] | Pure Rust, no native dependencies, small binary, works for WASM-in-WASM |
| **Zig** | wasm3 [12] (C) | Fast interpreter, small footprint, trivial C interop via `@cImport` |
| **Browser** | Native `WebAssembly` API | Full-speed execution via wasm-bindgen |

## Bootstrapping

The compiler is written in Pascal from the start — not in Rust or Zig. This creates a bootstrapping problem: the compiler cannot compile itself until it exists as an executable.

### Bootstrap Strategy

Bootstrap using the **Free Pascal Compiler (fpc)** [7] in Turbo Pascal [8] / BP 7.0 compatibility mode (`-Mtp`):

1. Write the Compact Pascal compiler in a Pascal subset compatible with fpc's Turbo Pascal mode. This keeps the compiler source close to classic Pascal and avoids fpc-specific extensions.
2. Use fpc to build the compiler as a native executable. Run the native compiler on Compact Pascal source to produce WASM binaries.
3. Once the compiler can compile itself, produce a **snapshot binary**: the compiler compiled to WASM by itself. Commit this snapshot to git (acceptable as long as it stays under 1 MB; revisit if it exceeds that).
4. Future updates: use the snapshot compiler (running in wasmi/wasm3) to compile newer versions of itself. Update the snapshot blob when the compiler changes.

### Developer Experience

The fpc dependency is only needed for the initial bootstrap or if the snapshot becomes invalid. Once a snapshot WASM binary exists, developers only need Rust (or Zig) to build the embedding library — no Pascal toolchain required.

### Compiler Tutorial

The Phase 1 compiler serves as the subject of a step-by-step compiler construction tutorial (`doc/compact-pascal-tutorial.md`). The tutorial walks through implementing the compiler from scratch — lexer, expressions, statements, procedures, nested scopes, strings, and structured types — with each chapter producing a working compiler that handles a progressively larger subset of the language. Phase 1's architecture (single-pass recursive descent, WASM stack machine target, stack-only allocation) is well-suited for teaching: the concepts map directly without the distractions of register allocation, garbage collection, or multi-pass optimization. The tutorial targets both students learning Compact Pascal and students studying compiler construction. An afterword suggests next steps for readers who want to extend the compiler: exceptions, operator overloading, pattern matching, closures, and generics — explaining what each feature requires and why it was excluded from the core language.

## Project Layout

```
compiler/       — Pascal source for the compiler (built with fpc)
compiler-tests/ — test suite modeled on BSI Pascal Validation Suite
src/            — Rust crate source
src-zig/        — Zig library source
snapshot/       — the compiler WASM blob (shared by Rust and Zig)
examples/
  rust/         — Rust example programs (hello, ffi, pode-server)
  zig/          — Zig example programs
  html/         — client-side browser playground (static HTML, no server)
pages/          — GitHub Pages site (includes deployed playground)
doc/            — language specification, white paper, and compiler tutorial
Cargo.toml      — Rust build
build.zig       — Zig build
build.zig.zon   — Zig package manifest
```

### Test Suite

The `compiler-tests/` directory contains positive and negative tests modeled on the BSI Pascal Validation Suite [13]:

```
compiler-tests/
  positive/
    t001_hello.pas            — source
    t001_hello.expected        — expected stdout
  negative/
    e001_type_mismatch.pas     — source (should fail to compile)
    e001_type_mismatch.error   — expected error substring
  run-tests.sh
```

- **Positive tests:** valid Compact Pascal programs that should compile to WASM and produce expected output when executed. The test harness compiles each `.pas` file, validates the output with `wasm-validate` (wabt), runs it with `wasmtime`, and compares stdout against the `.expected` file.
- **Negative tests:** invalid programs that should cause the compiler to emit a diagnostic to stderr and halt. The test harness verifies that compilation fails and the error output contains the expected substring from the `.error` file.

Since the compiler and compiled programs both use standard WASI for I/O, tests run directly under `wasmtime` with no custom host or test harness binary needed — just a shell script.

Tests cover key compiler features: types, expressions, control flow, procedures/functions, strings, records, arrays, and scoping rules.

## Similar Projects

Several other projects occupy related niches -- small compilers, embeddable languages, Pascal variants, or languages targeting WASM. Compact Pascal shares goals with each but differs in important ways.

**Cowgol** [15] is a self-hosting, Ada-inspired language targeting 8-bit microcomputers (6502, Z80, 8080) and several larger platforms. Like Compact Pascal, it emphasizes compiler minimalism and self-hosting on constrained targets. Cowgol forbids recursion to enable static variable overlap analysis -- a technique that allows the linker to map non-concurrent variables to the same memory addresses, critical for machines with tiny address spaces. Compact Pascal faces no such constraint (WASM provides a proper call stack) and instead focuses on embeddability via WASM rather than running on vintage hardware.

**PascalScript** (RemObjects) [16] is an embeddable Pascal scripting engine used in Inno Setup and other applications. It interprets Pascal source at runtime, providing scripting capabilities within a host application. Unlike Compact Pascal, PascalScript is an interpreter rather than a compiler, and it does not produce portable bytecode -- the host must include the PascalScript runtime. Compact Pascal compiles to WASM, producing standalone modules that any WASM runtime can execute.

**Turbo Rascal Syntax Error (TRSE)** [17] is a Pascal-like IDE and compiler targeting retro platforms (6502, Z80, 68000, x86). It shares Cowgol's focus on vintage hardware but takes a different approach: TRSE is written in C++ and provides a full IDE with sprite editors and graphics tools, making it more of a development environment than a minimal compiler. Its Pascal dialect includes platform-specific extensions for hardware access.

**Grain** [18] is a functional programming language designed for WASM from the ground up. Like Compact Pascal, it compiles to WASM and treats it as the primary (and only) target. However, Grain is a modern functional language with algebraic data types, pattern matching, and a garbage collector -- a very different design philosophy from Compact Pascal's minimalist, imperative approach.

**AssemblyScript** [19] is a TypeScript-like language that compiles to WASM. It occupies a similar "language designed for WASM" niche but targets developers already familiar with TypeScript/JavaScript rather than the Pascal community. Its compiler is itself written in AssemblyScript and runs as WASM, paralleling Compact Pascal's self-hosting-via-WASM approach.

**TinyLisp** [29] is a minimal Lisp interpreter written in Zig that compiles to WASM for browser-based execution. It supports atoms, lists, arithmetic, conditionals, and closures, with an interactive REPL backed by a JavaScript terminal emulator. TinyLisp uses NaN boxing for value representation and a simple garbage collection strategy. Like Compact Pascal, it demonstrates the pattern of writing a language implementation in a systems language, compiling to WASM, and embedding it in a web page — though TinyLisp is an interpreter rather than a compiler, and targets Lisp rather than Pascal.

### Pascal-Family Connections

The Pascal family is richer than is commonly appreciated. Beyond the well-known line from Standard Pascal through Turbo Pascal to Delphi, the family includes significant work in concurrency, parallelism, array programming, and verified computing. Compact Pascal sits within this broader tradition, and several family members inform its design or represent directions it may explore in the future.

**Pascaline / IP Pascal** [20] (Scott A. Moore) is a highly extended superset of ISO 7185 Pascal that adds modules with namespace control (`uses` for merged namespaces, `joins` for qualified access), monitor-based concurrency, dynamic arrays that are fully interchangeable with static arrays, `view` (read-only reference) parameters, `fixed` structured constant initializers, constant expressions, underscores in numeric literals, and boolean bit operations on integers. Pascaline's design principle — extend Pascal to modern functionality without ever reducing type safety — is one Compact Pascal shares. IP Pascal's forward declaration style (repeating the full header at the definition) influenced Compact Pascal's forward syntax. **Pascal-P6** [20] is the open-source implementation of Pascaline, continuing the Pascal-P compiler lineage that seeded UCSD Pascal and indirectly Turbo Pascal. It is self-compiling and includes a native AMD64 code generator alongside the traditional P-code interpreter.

**Concurrent Pascal** [22] (Per Brinch Hansen, 1974) introduced the monitor concept to Pascal: shared data encapsulated with the procedures that access it, with automatic mutual exclusion. It removed pointers, variant records, `goto`, and procedures-as-parameters to guarantee memory safety — a security-through-restriction philosophy that Compact Pascal echoes in its own omissions. **Joyce** [23] (Brinch Hansen, 1987) replaced monitors with CSP-style agents communicating through typed channels, demonstrating that safe concurrency in Pascal need not require shared memory. **SuperPascal** [21] (Brinch Hansen, 1993) synthesized these ideas into a *publication language* for parallel scientific computing, with `parallel` and `forall` statements, typed channels, and a single-pass compiler that checks parallel processes for disjointness at compile time — detecting race conditions without runtime overhead. SuperPascal's proof that a single-pass Pascal compiler can enforce concurrency safety is directly relevant to Compact Pascal's architecture.

**ParaSail** [24] (S. Tucker Taft / AdaCore, 2009) takes the most radical approach in the Pascal family: it eliminates pointers, global variables, parameter aliasing, explicit threads, and runtime exceptions entirely. Every expression has parallel evaluation semantics; the compiler automatically identifies parallelism and detects race conditions at compile time. Region-based memory management replaces garbage collection. Hoare-style preconditions, postconditions, and class invariants are part of the standard syntax. ParaSail's parameterized modules with bounded generics (type parameters that must implement an interface) represent a form of generics that is more tractable for single-pass compilation than monomorphization.

**Vector Pascal** [25] (Paul Cockshott, University of Glasgow, ~2002) extends Pascal with APL-derived array programming: all operators automatically extend to work element-wise on arrays, with reductions, slicing, conditional masking, and index generation. The compiler maps these operations to SIMD instructions (MMX, SSE, AltiVec), achieving 12x speedups on parallel data. Vector Pascal also introduces a dimensional type system for scientific computing (compile-time unit checking) and a pixel type with saturating fixed-point arithmetic. These ideas — type-level guarantees for scientific quantities and automatic vectorization through language design — are relevant to any Pascal targeting modern hardware.

**Pascal-FC** [26] (Alan Burns and Geoff Davies, University of York) is a teaching language that uniquely offers *five* concurrency models in a single Pascal dialect: semaphores, monitors, CSP channels, Ada-style rendezvous, and Ada 95 protected types. Its runtime uses random process switching to expose timing-dependent bugs. While not a production language, Pascal-FC's multi-paradigm approach is a useful reference for understanding the design space of concurrency in Pascal.

**Zonnon** [27] (Jürg Gutknecht et al., ETH Zürich) represents the most recent evolution of the Wirth school, adding active objects (objects with encapsulated threads), compositional inheritance via definitions/implementations, operator overloading, and exception handling to the Oberon lineage. Its syntax-controlled dialogs for inter-object communication protocols are a novel contribution.

**Pascal-XSC** [28] (University of Karlsruhe) extended Pascal with interval arithmetic and verified numerical computing — operators that deliver results guaranteed accurate to within one rounding unit. While Compact Pascal does not target scientific computing, Pascal-XSC demonstrates that Pascal's type system can be extended with domain-specific guarantees that are checked at compile time.

---

## Appendix A: Grammar Summary

This appendix is an EBNF summary of the Compact Pascal grammar, covering the core language and extension syntax. Terminals are shown in `'single quotes'` or as UPPER_CASE token names. Non-terminals are in CamelCase. `{ ... }` denotes zero or more repetitions, `[ ... ]` denotes optional elements, and `|` denotes alternation.

### Programs

```ebnf
Program          = 'program' Identifier ';' Block '.' .
```

### Blocks and Declarations

```ebnf
Block            = { DeclSection } StatementPart .

DeclSection      = ConstDeclPart
                 | TypeDeclPart
                 | VarDeclPart
                 | ProcOrFuncDecl
                 | ImplementBlock .

ConstDeclPart    = 'const' ConstDef { ConstDef } .
ConstDef         = Identifier '=' ConstExpr ';'
                 | Identifier ':' Type '=' ConstExpr ';' .
                 (* First form is an untyped constant.
                    Second form is a typed constant / initialized variable.
                    ConstExpr is evaluated at compile time. *)

ConstExpr        = Expression .
                 (* Syntactically identical to Expression but evaluated at
                    compile time. May reference previously declared constants,
                    literals, string concatenation (+), and standard functions
                    (ord, chr, abs, etc.). *)

TypeDeclPart     = 'type' TypeDef { TypeDef } .
TypeDef          = Identifier '=' Type ';' .

VarDeclPart      = 'var' VarDecl { VarDecl } .
VarDecl          = IdentList ':' Type [ '=' ConstExpr ] ';' .
                 (* Initialized variables (Delphi/FPC extension).
                    Single identifier only when initializer is present.
                    Locals reinitialize on each scope entry. *)
IdentList        = Identifier { ',' Identifier } .
```

### Types

```ebnf
Type             = SimpleType
                 | StringType
                 | ArrayType
                 | RecordType
                 | SetType
                 | PointerType
                 | InterfaceType
                 | ProceduralType .

SimpleType       = TypeIdentifier
                 | EnumType
                 | SubrangeType .

TypeIdentifier   = Identifier .
                 (* built-in: integer, boolean, char, real,
                    byte, shortint, word, longint *)
StringType       = 'string' [ '[' Constant ']' ] .
                 (* 'string' alone is 'string[255]' *)

EnumType         = '(' IdentList ')' .
SubrangeType     = Constant '..' Constant
                 | Identifier '(' Constant '..' Constant ')' .
                 (* second form: typed subrange with explicit base type,
                    e.g. Day(Mon..Fri). Base type is verified semantically. *)

ArrayType        = 'array' '[' SubrangeType { ',' SubrangeType } ']' 'of' Type .

RecordType       = 'record' FieldList [ VariantPart ] 'end' .
FieldList        = [ FieldDecl { ';' FieldDecl } ] .
FieldDecl        = IdentList ':' Type .
VariantPart      = 'case' [ Identifier ':' ] TypeIdentifier 'of'
                   Variant { ';' Variant } .
Variant          = CaseLabelList ':' '(' FieldList ')' .

SetType          = 'set' 'of' SimpleType .
                 (* base type must have at most 256 ordinal values *)

PointerType      = '^' TypeIdentifier .

InterfaceType    = 'interface' InterfaceFieldList 'end' .
InterfaceFieldList = [ InterfaceField { ';' InterfaceField } ] .
InterfaceField   = Identifier ':' ProceduralType .

ProceduralType   = 'procedure' [ FormalParams ]
                 | 'function' [ FormalParams ] ':' Type .
```

### Procedures, Functions, and Methods

```ebnf
ProcOrFuncDecl   = ProcDecl | FuncDecl .

ProcDecl         = 'procedure' Identifier
                   ( 'for' Receiver [ FormalParams ] ';' Block ';'
                   | [ FormalParams ] ';' ( Block ';' | 'forward' ';' | 'external' ';' ) ) .
FuncDecl         = 'function'  Identifier
                   ( 'for' Receiver [ FormalParams ] ':' Type ';' Block ';'
                   | [ FormalParams ] ':' Type ';' ( Block ';' | 'forward' ';' | 'external' ';' ) ) .
                 (* 'for' Receiver marks a standalone method — see Extensions.
                    'external' is used with {$IMPORT} for WASM host-provided procedures.
                    Return type is any Type, including arrays and records —
                    see Structured Return Types under Extensions.
                    Forward bodies repeat the full header (IP Pascal convention),
                    unlike Turbo Pascal where the body omits the parameter list. *)

FormalParams     = '(' FormalParam { ';' FormalParam } ')' .
FormalParam      = [ 'var' | 'const' ] IdentList ':' Type .

Receiver         = Identifier ':' Type .
                 (* Type may be a value type or '^TypeIdentifier' for pointer receiver *)
```

### Implement Blocks (Extension)

```ebnf
ImplementBlock   = 'implement' TypeIdentifier 'for' TypeIdentifier ';'
                   { ImplMethod }
                   'end' ';' .

ImplMethod       = ImplProcDecl | ImplFuncDecl .
ImplProcDecl     = 'procedure' Identifier [ FormalParams ] ';' Block ';' .
ImplFuncDecl     = 'function'  Identifier [ FormalParams ] ':' Type ';' Block ';' .
                 (* Self is implicitly available inside the block *)
```

### Statements

```ebnf
StatementPart    = CompoundStmt .
CompoundStmt     = 'begin' StmtSequence 'end' .
StmtSequence     = Statement { ';' Statement } .

Statement        = [ AssignOrCallStmt
                   | CompoundStmt
                   | IfStmt
                   | WhileStmt
                   | ForStmt
                   | RepeatStmt
                   | CaseStmt
                   | WithStmt ] .

AssignOrCallStmt = Designator [ ':=' Expression ] .
                 (* a bare Designator is a procedure call; includes method calls
                    via dot notation: Designator '.' Identifier '(' ... ')' *)

IfStmt           = 'if' Expression 'then' Statement [ 'else' Statement ] .
                 (* Dangling else: 'else' binds to the nearest unmatched 'if'. *)
WhileStmt        = 'while' Expression 'do' Statement .
ForStmt          = 'for' Identifier ':=' Expression ( 'to' | 'downto' ) Expression
                   'do' Statement .
RepeatStmt       = 'repeat' StmtSequence 'until' Expression .
CaseStmt         = 'case' Expression 'of' CaseElement { ';' CaseElement } [ ';' ]
                   [ 'else' StmtSequence ] 'end' .
CaseElement      = CaseLabelList ':' Statement .
CaseLabelList    = CaseLabel { ',' CaseLabel } .
CaseLabel        = Constant [ '..' Constant ] .

WithStmt         = 'with' Designator { ',' Designator } 'do' Statement .
```

### Expressions

```ebnf
Expression       = SimpleExpr [ RelOp SimpleExpr ] .
RelOp            = '=' | '<>' | '<' | '>' | '<=' | '>=' | 'in' .

SimpleExpr       = [ '+' | '-' ] Term { AddOp Term } .
AddOp            = '+' | '-' | 'or' | 'or' 'else' .

Term             = Factor { MulOp Factor } .
MulOp            = '*' | 'div' | 'mod' | 'and' | 'and' 'then' .

Factor           = INTEGER_LITERAL
                 | REAL_LITERAL
                 | STRING_LITERAL
                 | 'true' | 'false'
                 | 'nil'
                 | Designator
                 | '(' Expression ')'
                 | 'not' Factor
                 | SetConstructor .

SetConstructor   = '[' [ SetElement { ',' SetElement } ] ']' .
SetElement       = Expression [ '..' Expression ] .

Designator       = Identifier { Selector } .
Selector         = '.' Identifier             (* field access or method call *)
                 | '[' ExprList ']'            (* array indexing *)
                 | '(' [ ExprList ] ')'        (* function call or type cast —
                                                  resolved semantically *)
                 | '^' .                       (* pointer dereference *)

ExprList         = Expression { ',' Expression } .
```

### Constants

```ebnf
Constant         = ConstExpr .
                 (* RUNE_LITERAL = '#u' followed by hex digits, e.g. #u2261.
                    STRING_LITERAL includes #n char constants folded by the scanner. *)
```

### Lexical Elements

```ebnf
Identifier       = LETTER { LETTER | DIGIT | '_' } .
INTEGER_LITERAL  = DIGIT { DIGIT }
                 | '$' HEX_DIGIT { HEX_DIGIT } .
                 (* with {$EXTLITERALS ON}, the following forms are also accepted:
                    '0x' HEX_DIGIT { HEX_DIGIT }
                    '0o' OCTAL_DIGIT { OCTAL_DIGIT }
                    '0b' BIN_DIGIT { BIN_DIGIT }
                    where OCTAL_DIGIT = '0'..'7' and BIN_DIGIT = '0' | '1' *)
REAL_LITERAL     = DIGIT { DIGIT } '.' DIGIT { DIGIT } [ 'e' [ '+' | '-' ] DIGIT { DIGIT } ] .
STRING_LITERAL   = StringElement { StringElement } .
StringElement    = "'" { CHARACTER | "''" } "'"
                 | '#' INTEGER_LITERAL .
                 (* "''" is an escaped single quote within a string *)
                 (* '#' followed by 0..255 produces a byte; values > 255 are an error *)
RUNE_LITERAL     = '#u' HEX_DIGIT { HEX_DIGIT } .
                 (* produces a rune value — a 32-bit Unicode codepoint *)

LETTER           = 'a'..'z' | 'A'..'Z' .
DIGIT            = '0'..'9' .
HEX_DIGIT        = '0'..'9' | 'a'..'f' | 'A'..'F' .
CHARACTER        = (* any byte; UTF-8 sequences are preserved verbatim *) .
```

### Reserved Words

```
and       array     begin     case      const
div       do        downto    else      end
external  for       forward   function  if
implement in        interface mod       nil
not       of        or        procedure program
record    repeat    set       string    then
to        type      until     var       while
with
```

The language is **case-insensitive** — reserved words and identifiers are matched without regard to case.

Note: `self`, `true`, `false`, `input`, `output`, `stderr`, `maxint` are built-in identifiers, not reserved words. Compiler intrinsics (`write`, `writeln`, `read`, `readln`, `abs`, `ord`, `chr`, `odd`, `succ`, `pred`, `sqr`, `length`, `sizeof`, `lo`, `hi`, `inc`, `dec`, `exit`, `halt`, `copy`, `pos`, `concat`, `delete`, `insert`, `new`, `dispose`) are also built-in identifiers. `implement` and `interface` are reserved to support core features and future extensions. `external` is reserved for declaring imported procedures. `string`, `set`, `in`, and `with` are reserved as language keywords. The reserved words `and then` and `or else` form two-word operators for short-circuit boolean evaluation (ISO 10206). WASM import/export names in `{$IMPORT}` and `{$EXPORT}` directives are case-sensitive.

### Operator Precedence (Highest to Lowest)

| Precedence | Operators | Associativity |
|---|---|---|
| 1 (highest) | `not`, unary `+`/`-` | Right |
| 2 | `*`, `div`, `mod`, `and`, `and then` | Left |
| 3 | `+`, `-`, `or`, `or else` | Left |
| 4 (lowest) | `=`, `<>`, `<`, `>`, `<=`, `>=`, `in` | None |

### Comments and Compiler Directives

```ebnf
Comment          = '{' { CHARACTER } '}'
                 | '(*' { CHARACTER } '*)'
                 | '//' { CHARACTER } EOL .

Directive        = '{' '$' DirectiveName [ DirectiveValue ] '}'
                 | '(*' '$' DirectiveName [ DirectiveValue ] '*)' .

DirectiveName    = LETTER { LETTER } .
DirectiveValue   = SwitchValue | Identifier | INTEGER_LITERAL | STRING_LITERAL .
SwitchValue      = '+' | '-' .
```

Comments do not nest. They may appear anywhere whitespace is permitted. Line comments (`//`) extend to the end of the line.

If the first byte of the source is `#`, the remainder of the first line is ignored. This permits Unix-style interpreter directives (e.g., `#!/usr/bin/env cpas`).

Compiler directives use the Free Pascal convention: a `$` immediately after the opening brace. Switch directives use `+`/`-` (e.g., `{$R+}`). Directives are either global (before any declarations) or local (anywhere, effective from that point). See the Language Reference for the full directive list.

---

## Acknowledgments

This document and the Compact Pascal language design were developed with the assistance of **Claude Code** (Anthropic) [14], an AI-powered software engineering tool. Claude Code contributed to design discussions, document drafting, grammar review, and iterative refinement of the language specification, white paper, and project planning. All design decisions were made by the author; Claude Code served as a research and writing collaborator.

## References

[1] ISO/IEC 7185:1990, *Programming languages — Pascal*. International Organization for Standardization, 1990.

[2] ISO/IEC 10206:1991, *Programming languages — Extended Pascal*. International Organization for Standardization, 1991.

[3] N. Wirth, "The Programming Language Oberon," *Software — Practice and Experience*, vol. 18, no. 7, pp. 671–690, 1988. See also: *Component Pascal Language Report*, Oberon Microsystems, 1997.

[4] The Go Programming Language. https://go.dev/

[5] WebAssembly Core Specification, Version 1.0. W3C, 2019. https://www.w3.org/TR/wasm-core-1/

[6] WASI Preview 1 (wasi_snapshot_preview1). https://github.com/WebAssembly/WASI/blob/main/legacy/preview1/docs.md

[7] Free Pascal Compiler. https://www.freepascal.org/

[8] A. Hejlsberg, *Turbo Pascal*. Borland International, 1983. Turbo Pascal 7.0 is the dialect targeted for bootstrap compatibility.

[9] E. W. Dijkstra, "Recursive Programming," *Numerische Mathematik*, vol. 2, pp. 312–318, 1960. The display technique for implementing lexical scoping in block-structured languages.

[10] H. G. Baker, "The Treadmill: Real-Time Garbage Collection Without Motion Sickness," *ACM SIGPLAN Notices*, vol. 27, no. 3, pp. 66–70, 1992.

[11] wasmi — WebAssembly interpreter written in Rust. https://github.com/wasmi-labs/wasmi

[12] wasm3 — A fast WebAssembly interpreter written in C. https://github.com/wasm3/wasm3 Note: project maintenance status is uncertain as of 2026.

[13] BSI Pascal Validation Suite. https://github.com/pascal-validation/validation-suite

[14] Anthropic, "Claude Code," 2025. https://docs.anthropic.com/en/docs/claude-code

[15] D. Given, "Cowgol 2.0," 2022. An Ada-inspired language for very small systems. https://cowlark.com/cowgol/

[16] RemObjects Software, "PascalScript." An embeddable Pascal scripting engine. https://github.com/nickelsworth/pascalscript

[17] N. Morten, "Turbo Rascal Syntax Error (TRSE)." A Pascal-like IDE and compiler for retro platforms. https://lemonspawn.com/turbo-rascal-syntax-error-expected-but-alarm/

[18] O. Falvai et al., "Grain: A strongly-typed functional programming language for WebAssembly." https://grain-lang.org/

[19] AssemblyScript Contributors, "AssemblyScript." A TypeScript-like language targeting WebAssembly. https://www.assemblyscript.org/

[20] S. A. Moore, "The Language Pascaline." A highly extended superset of ISO 7185 Pascal. https://standardpascal.org/pascaline.htm — See also: Pascal-P6 (open-source Pascaline implementation), https://github.com/samiam95124/Pascal-P6

[21] P. Brinch Hansen, "The Programming Language SuperPascal," *Software: Practice and Experience*, vol. 24, no. 5, pp. 399–406, 1994. See also: "SuperPascal — A Publication Language for Parallel Scientific Computing," *Concurrency: Practice and Experience*, vol. 6, no. 5, pp. 461–483, 1994.

[22] P. Brinch Hansen, "The Programming Language Concurrent Pascal," *IEEE Transactions on Software Engineering*, vol. 1, no. 2, pp. 199–207, 1975.

[23] P. Brinch Hansen, "Joyce — A Programming Language for Distributed Systems," *Software: Practice and Experience*, vol. 17, no. 1, pp. 29–50, 1987.

[24] S. Tucker Taft, "ParaSail: A Pointer-Free Pervasively-Parallel Language for Irregular Computations," *Programming Journal*, vol. 3, no. 7, 2019. https://parasail-lang.org/

[25] P. Cockshott, "Vector Pascal, an Array Language," *ACM SIGPLAN Notices*, vol. 37, no. 6, pp. 59–69, 2002. https://dl.acm.org/doi/10.1145/571727.571737

[26] A. Burns and G. L. Davies, "Pascal-FC: A Language for Teaching Concurrent Programming," *ACM SIGPLAN Notices*, vol. 23, no. 9, 1988.

[27] J. Gutknecht et al., "Project Zonnon: A Compositional Language for Distributed Computing," IEEE, 2008. https://zonnon.org/

[28] R. Klatte et al., *PASCAL-XSC: Language Reference with Examples*, Springer, 1992. https://www2.math.uni-wuppertal.de/wrswt/xsc/pxsc.html

[29] D. Sanchez, "TinyLisp: A minimal Lisp interpreter in Zig targeting WebAssembly," 2025. https://daneelsan.github.io/2025/03/20/tinylisp.html

---

Copyright 2026 Jon Mayo. This document is licensed under the [Creative Commons Attribution 4.0 International License (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
