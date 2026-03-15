# Compact Pascal: An Embeddable Pascal-to-WASM Compiler

**DRAFT** — This document is a work in progress and subject to change.

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
5. **Extend Pascal thoughtfully** with modern features (structural interfaces, macros) that respect the language's character while addressing real gaps.

### Relationship to Existing Pascal Standards

Compact Pascal draws inspiration from several sources in the Pascal family:

- **ISO 7185 (Standard Pascal)** provides the syntactic and semantic foundation: block structure, strong typing, declare-before-use, and the core type system.
- **ISO 10206 (Extended Pascal)** informs the dynamic memory model (`New`/`Dispose`) and serves as a reference for language extensions.
- **Standard [Pascaline](https://www.standardpascaline.org/pascaline.htm)** was the original starting point, but Compact Pascal has diverged significantly and is not a compatible superset.
- **Component Pascal / Oberon** inspire the minimalist philosophy: a small, coherent language rather than a feature-laden one.
- **Go** provides the model for structural interfaces — polymorphism without inheritance.

Compact Pascal is not a conforming implementation of any existing Pascal standard. It is a new language that inherits Pascal's syntax and values while making deliberate departures where they serve the goals of embeddability, simplicity, and WASM compatibility.

### Design Principles

- **Minimalism.** Include only what is needed. Features earn their place by being essential to the language's purpose, not by precedent.
- **Embeddability.** The compiler and runtime must function as a library, not a standalone tool. No implicit I/O, no filesystem access, no assumptions about the host environment.
- **Single-pass friendliness.** The language design should not require multi-pass compilation. Declare-before-use, explicit interface conformance blocks, and forward declarations keep the compiler simple and fast.
- **Portability.** Target WASM 1.0 MVP only. No WASM extensions, no platform-specific features, no assumptions beyond what the MVP specification guarantees.
- **Interoperability.** Host applications (Rust, Zig, browser JavaScript) must be able to call into Pascal code and provide functions that Pascal code can call, through WASM's import/export mechanism.

## Architecture

### Overview

The system consists of three layers:

```
+---------------------------------------------------+
|  Host Application (Rust / Zig / Browser JS)       |
+---------------------------------------------------+
|  Embedding Library (compact-pascal crate/module)   |
|                                                    |
|  +----------------+   +-----------------------+    |
|  | WASM Runtime   |   | Host-Guest FFI        |    |
|  | (wasmi / wasm3)|   | (imports / exports)   |    |
|  +----------------+   +-----------------------+    |
+---------------------------------------------------+
|  Compiler (WASM blob, written in Pascal)           |
|  source -> [fd 0] -> compiler -> [fd 1] -> .wasm  |
+---------------------------------------------------+
|  Compiled Program (WASM module)                    |
|  executed by the same WASM runtime                 |
+---------------------------------------------------+
```

1. **The compiler** is a Pascal program compiled to WASM. It reads Compact Pascal source from fd 0, writes a WASM binary to fd 1, and writes errors to fd 2. It ships as a snapshot blob embedded in the library.
2. **The embedding library** (one for Rust, one for Zig) bundles the compiler blob and a WASM interpreter. It provides a high-level API: compile source, instantiate modules, register host functions, call exported procedures.
3. **The host application** uses the embedding library to compile and run Pascal code, providing whatever host functions the Pascal program needs through WASM imports.

### Core Language

The core is a minimal subset of Pascal sufficient for systems programming and compiler construction: integer, boolean, char, and string types; arrays, records (including variant records), set types, and pointers; standard control flow (including `with` for record field access); procedures and functions with value, `var`, and `const` parameters; nested procedures with access to enclosing scope variables. Floating point (`real`) and dynamic allocation (`New`/`Dispose`) are planned for later phases. The language is case-insensitive; hexadecimal literals (`$FF`) are supported, with optional C-style prefixes (`0x`, `0o`, `0b`) behind a compiler directive.

The familiar I/O procedures `write`, `writeln`, `read`, `readln` are supported as **compiler intrinsics** — the compiler generates calls to `fd_write`/`fd_read` WASM host imports rather than providing a runtime library. The host application must supply these imports, keeping the WASM runtime footprint minimal. There are no file types; all I/O goes through host imports.

### String Representation

Phase 1 uses Turbo Pascal-style short strings: a length byte followed by up to 255 characters. This representation is identical to Free Pascal in `-Mtp` mode, which is critical for self-hosting — the compiler source must compile under both fpc and Compact Pascal. Short strings require no heap allocator and live on the stack or in records. A richer dynamically-allocated string type (pointer + length, no 255-character limit) is planned for a later phase.

The embedding libraries provide helper functions to convert between host strings (Rust `&str`/`String`, Zig `[]const u8`) and the Pascal representation in WASM memory.

### Standard Functions and Procedures

Compact Pascal includes standard functions and procedures as compiler intrinsics: `abs`, `ord`, `chr`, `odd`, `succ`, `pred`, `sqr`, `length`, `sizeof`, `lo`, `hi`, `inc`, `dec`, `exit`, `halt`, and string operations (`copy`, `pos`, `concat`, `delete`, `insert`). TP-compatible numeric types (`byte`, `word`, `shortint`, `longint`) are also supported. These additions maximize backward compatibility with existing Pascal code and ensure the compiler source compiles naturally on both fpc and Compact Pascal.

### Language Extensions

- **Macros:** Rust-like macros for compile-time code generation and domain-specific syntax.
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

The compiler itself (running as WASM) communicates through the **WASI preview 1** I/O interface. The host must provide the following WASM imports from the `wasi_snapshot_preview1` module:

- `fd_read(fd: i32, iovs: i32, iovs_len: i32, nread: i32) -> errno: i32`
- `fd_write(fd: i32, iovs: i32, iovs_len: i32, nwritten: i32) -> errno: i32`
- `proc_exit(code: i32) -> noreturn`

Each iovec is an 8-byte struct in linear memory: `{ buf: i32, len: i32 }`. In practice, the compiler always passes a single iovec (`iovs_len = 1`), making the calling code trivial — two `i32.store` instructions to build the iovec, then the call.

Standard POSIX file descriptors: 0 = stdin, 1 = stdout, 2 = stderr.

The compiler reads Pascal source from fd 0, writes WASM binary output to fd 1, and writes error messages to fd 2. On the first error, the compiler writes a diagnostic to stderr and halts via `proc_exit(1)`.

Because the compiler uses standard WASI, it runs directly under any WASI-compatible runtime (wasmtime, wasmer, wasm3, browser polyfills) without a custom host.

Programs compiled by the compiler that use `write`/`writeln`/`read`/`readln` also emit WASI `fd_write`/`fd_read` calls, making them WASI-compatible out of the box. Programs that do not use I/O have no implicit WASI imports.

### WASM Target

The compiler emits **WASM 1.0** (MVP) only — no extensions (bulk memory, multi-value, GC, etc.). This maximizes portability across runtimes and ensures compiled programs run on any compliant WASM implementation.

### WASM Code Generation Strategy

The compiler uses single-pass parsing with **deferred binary output**. WASM binary format requires sections in a fixed order (type, function, memory, export, code), but the compiler discovers functions as it parses. The solution: accumulate each section in a separate in-memory buffer during the single pass, then write all sections in the correct order at the end. This is single-pass *parsing* with buffered output — not multi-pass compilation.

A `-dump` flag emits a human-readable listing of the generated WASM instructions for debugging (not full WAT, just an instruction log).

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

Pascal supports nested procedures with access to enclosing scope variables. Since WASM functions are all top-level with no closure support, the compiler uses **Dijkstra's display technique**: a fixed-size array of 8 WASM globals where `display[N]` holds the frame pointer for nesting level N. Accessing an upvalue is always O(1) — two loads regardless of nesting depth. Top-level procedures (the vast majority) emit no display code and pay zero overhead. Maximum nesting depth is 8.

### Memory Management

Phase 1 uses stack-only allocation — all variables (including strings and records) live on the stack or in the data segment. No heap allocator is needed.

**Future (Phase 5):** `New`/`Dispose` with a free-list allocator in WASM linear memory. The heap grows upward from the end of the data segment, toward the stack. Object headers will include metadata (size, mark bits, link pointers) designed to support a future garbage collector.

**Future: Baker's Treadmill GC.** A non-moving, incremental garbage collector suitable for WASM linear memory. Requires a shadow stack in linear memory for GC root tracking (since the WASM operand stack is opaque). Deferred until after `New`/`Dispose` is working.

### Error Handling

The compiler halts on the first error with a diagnostic written to stderr (fd 2). No error recovery or multi-error reporting. This is the most lightweight strategy for a single-pass compiler — no recovery logic, no cascading false positives.

### WASM Runtimes

| Host Language | WASM Runtime | Rationale |
|---|---|---|
| **Rust** | wasmi | Pure Rust, no native dependencies, small binary, works for WASM-in-WASM |
| **Zig** | wasm3 (C) | Fast interpreter, small footprint, trivial C interop via `@cImport` |
| **Browser** | Native `WebAssembly` API | Full-speed execution via wasm-bindgen |

## Bootstrapping

The compiler is written in Pascal from the start — not in Rust or Zig. This creates a bootstrapping problem: the compiler cannot compile itself until it exists as an executable.

### Bootstrap Strategy

Bootstrap using the **Free Pascal Compiler (fpc)** in TP/BP 7.0 compatibility mode (`-Mtp`):

1. Write the Compact Pascal compiler in a Pascal subset compatible with fpc's Turbo Pascal mode. This keeps the compiler source close to classic Pascal and avoids fpc-specific extensions.
2. Use fpc to build the compiler as a native executable. Run the native compiler on Compact Pascal source to produce WASM binaries.
3. Once the compiler can compile itself, produce a **snapshot binary**: the compiler compiled to WASM by itself. Commit this snapshot to git (acceptable as long as it stays under 1 MB; revisit if it exceeds that).
4. Future updates: use the snapshot compiler (running in wasmi/wasm3) to compile newer versions of itself. Update the snapshot blob when the compiler changes.

### Developer Experience

The fpc dependency is only needed for the initial bootstrap or if the snapshot becomes invalid. Once a snapshot WASM binary exists, developers only need Rust (or Zig) to build the embedding library — no Pascal toolchain required.

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
doc/            — language specification and white paper
Cargo.toml      — Rust build
build.zig       — Zig build
build.zig.zon   — Zig package manifest
```

### Test Suite

The `compiler-tests/` directory contains positive and negative tests modeled on the [BSI Pascal Validation Suite](https://github.com/pascal-validation/validation-suite):

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

Tests cover key compiler features: types, expressions, control flow, procedures/functions, pointers, strings, and scoping rules.

---

## Appendix A: Grammar Summary

The following is an EBNF summary of the Compact Pascal grammar. This covers the core language and the extension syntax. Terminals are shown in `'single quotes'` or as UPPER_CASE token names. Non-terminals are in CamelCase. `{ ... }` denotes zero or more repetitions, `[ ... ]` denotes optional elements, and `|` denotes alternation.

### Programs

```ebnf
Program          = ProgramHeading ';' Block '.' .
ProgramHeading   = 'program' Identifier .
```

### Blocks and Declarations

```ebnf
Block            = { DeclarationPart } StatementPart .

DeclarationPart  = ConstDeclPart
                 | TypeDeclPart
                 | VarDeclPart
                 | ProcOrFuncDecl
                 | MethodDecl
                 | ImplementBlock .

ConstDeclPart    = 'const' ConstDef { ConstDef } .
ConstDef         = Identifier '=' Expression ';'
                 | Identifier ':' Type '=' Expression ';' .
                 (* second form is a typed constant / initialized variable *)

TypeDeclPart     = 'type' TypeDef { TypeDef } .
TypeDef          = Identifier '=' Type ';' .

VarDeclPart      = 'var' VarDecl { VarDecl } .
VarDecl          = IdentList ':' Type ';' .
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
SubrangeType     = Constant '..' Constant .

ArrayType        = 'array' '[' SubrangeType { ',' SubrangeType } ']' 'of' Type .

RecordType       = 'record' FieldList [ VariantPart ] 'end' .
FieldList        = [ FieldDecl { ';' FieldDecl } ] .
FieldDecl        = IdentList ':' Type .
VariantPart      = 'case' Identifier ':' TypeIdentifier 'of'
                   Variant { ';' Variant } .
Variant          = CaseLabelList ':' '(' FieldList ')' .

SetType          = 'set' 'of' SimpleType .
                 (* base type must have at most 256 ordinal values *)

PointerType      = '^' TypeIdentifier .

InterfaceType    = 'interface' InterfaceFieldList 'end' .
InterfaceFieldList = [ InterfaceField { ';' InterfaceField } ] .
InterfaceField   = Identifier ':' ProceduralType .

ProceduralType   = 'procedure' [ FormalParams ]
                 | 'function' [ FormalParams ] ':' TypeIdentifier .
```

### Procedures and Functions

```ebnf
ProcOrFuncDecl   = ProcDecl | FuncDecl .

ProcDecl         = 'procedure' Identifier [ FormalParams ] ';'
                   ( Block ';' | 'forward' ';' | 'external' ';' ) .
FuncDecl         = 'function'  Identifier [ FormalParams ] ':' TypeIdentifier ';'
                   ( Block ';' | 'forward' ';' | 'external' ';' ) .
                 (* 'external' is used with {$IMPORT} for WASM host-provided procedures *)

FormalParams     = '(' FormalParam { ';' FormalParam } ')' .
FormalParam      = [ 'var' | 'const' ] IdentList ':' Type .
```

### Standalone Methods (Extension)

```ebnf
MethodDecl       = MethodProcDecl | MethodFuncDecl .

MethodProcDecl   = 'procedure' Identifier 'for' Receiver [ FormalParams ] ';' Block ';' .
MethodFuncDecl   = 'function'  Identifier 'for' Receiver [ FormalParams ] ':' TypeIdentifier ';'
                   Block ';' .

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
ImplFuncDecl     = 'function'  Identifier [ FormalParams ] ':' TypeIdentifier ';' Block ';' .
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

AssignOrCallStmt = Designator [ ':=' Expression ]
                 | Identifier '(' [ ExprList ] ')' .
                 (* includes method calls via dot notation: Designator '.' Identifier *)

IfStmt           = 'if' Expression 'then' Statement [ 'else' Statement ] .
WhileStmt        = 'while' Expression 'do' Statement .
ForStmt          = 'for' Identifier ':=' Expression ( 'to' | 'downto' ) Expression
                   'do' Statement .
RepeatStmt       = 'repeat' StmtSequence 'until' Expression .
CaseStmt         = 'case' Expression 'of' CaseElement { ';' CaseElement } 'end' .
CaseElement      = CaseLabelList ':' Statement .
CaseLabelList    = Constant { ',' Constant } .

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
                 | Identifier '(' [ ExprList ] ')'
                 (* function call or type cast — resolved semantically;
                    if Identifier is a type name, this is a type cast *)
                 | '(' Expression ')'
                 | 'not' Factor
                 | SetConstructor .

SetConstructor   = '[' [ SetElement { ',' SetElement } ] ']' .
SetElement       = Expression [ '..' Expression ] .

Designator       = Identifier { Selector } .
Selector         = '.' Identifier             (* field access or method call *)
                 | '[' ExprList ']'            (* array indexing *)
                 | '^' .                       (* pointer dereference *)

ExprList         = Expression { ',' Expression } .
```

### Constants

```ebnf
Constant         = [ '+' | '-' ] ( INTEGER_LITERAL | REAL_LITERAL | Identifier )
                 | STRING_LITERAL .
```

### Lexical Elements

```ebnf
Identifier       = LETTER { LETTER | DIGIT | '_' } .
INTEGER_LITERAL  = DIGIT { DIGIT }
                 | '$' HEX_DIGIT { HEX_DIGIT } .
                 (* with {$EXTLITERALS ON}: '0x' HEX, '0o' OCTAL, '0b' BINARY *)
REAL_LITERAL     = DIGIT { DIGIT } '.' DIGIT { DIGIT } [ 'e' [ '+' | '-' ] DIGIT { DIGIT } ] .
STRING_LITERAL   = "'" { CHARACTER } "'" .

LETTER           = 'a'..'z' | 'A'..'Z' .
DIGIT            = '0'..'9' .
HEX_DIGIT        = '0'..'9' | 'a'..'f' | 'A'..'F' .
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
                 | '(*' { CHARACTER } '*)' .

Directive        = '{' '$' DirectiveName [ DirectiveValue ] '}'
                 | '(*' '$' DirectiveName [ DirectiveValue ] '*)' .

DirectiveName    = LETTER { LETTER } .
DirectiveValue   = SwitchValue | Identifier | INTEGER_LITERAL | STRING_LITERAL .
SwitchValue      = '+' | '-' .
```

Comments do not nest. They may appear anywhere whitespace is permitted.

Compiler directives use the Free Pascal convention: a `$` immediately after the opening brace. Switch directives use `+`/`-` (e.g., `{$R+}`). Directives are either global (before any declarations) or local (anywhere, effective from that point). See the Language Reference for the full directive list.
