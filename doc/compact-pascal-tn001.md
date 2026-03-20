---
title: |
  | TN-001: Compact Pascal and Cowgol
  | — A Comparative Study
author: Jon Mayo
date: March 2026
---

## Overview

Cowgol [1] is a self-hosting, Ada-inspired language targeting 8-bit microcomputers (6502, Z80, 8080) and several larger platforms. It shares several structural properties with Compact Pascal: both are self-hosting, single-pass compilers that prioritize small compiler binaries and minimal runtime dependencies. Comparing the two highlights design choices in Compact Pascal that might otherwise go unnoticed.

## Shared Properties

Both projects sit in a surprisingly similar niche despite targeting opposite ends of the hardware spectrum:

- **Self-hosting compilers.** Both are written in their own language and bootstrap from a host toolchain. Cowgol bootstraps via a generated-C path; Compact Pascal bootstraps via Free Pascal (`fpc -Mtp`), then the native compiler compiles itself to produce a WASM snapshot.

- **Single-pass front ends.** Both avoid multi-pass compilation. Cowgol is strictly single-pass to minimize memory on 8-bit micros. Compact Pascal is single-pass by design heritage (Turbo Pascal lineage) and because it simplifies WASM code emission.

- **Forward declarations.** Both require forward declarations for mutual references, a direct consequence of single-pass parsing. Cowgol uses `@decl sub` / `@impl sub`; Compact Pascal uses `forward`.

- **Nested subroutines with lexical scoping.** Both support nested procedures that access enclosing scope variables. Cowgol uses static variable placement to make this cheap. Compact Pascal uses a Dijkstra display — 8 WASM globals where `display[N]` holds the frame pointer for nesting level N.

- **Tiny compilers.** Cowgol's 80386 binary is 70 KB. Compact Pascal's goal is a WASM blob small enough to embed in a Rust or Zig library. Both treat compiler size as a first-class design constraint.

- **No standard library.** Cowgol's system calls are platform-specific thin wrappers. Compact Pascal's I/O intrinsics lower directly to WASI `fd_write`/`fd_read`. Neither ships a runtime library.

## Feature Comparison

| | Cowgol | Compact Pascal |
|---|---|---|
| Language family | Ada-inspired, custom syntax | Pascal-family (TP dialect) |
| Target architectures | 6502, Z80, 8080, 80386, ARM, PowerPC, 68000, PDP-11, 8086 | WASM 1.0 only |
| Primary audience | Retro computing, 8-bit micros | Embedding in modern apps (Rust, Zig, browser) |
| Recursion | Forbidden — enables static variable overlap analysis | Supported — WASM provides a proper call stack with frames |
| Type system | Very strong, no implicit casts even between integer widths | TP-style ordinals, implicit widening, all stored as i32 |
| Multiple return values | Yes: `sub swap(a, b): (o1, o2)` | No — single return value (Pascal convention) |
| Memory model | Static allocation with overlap (linker maps non-concurrent variables to same addresses) | Stack frames in linear memory, `$sp` in WASM global; no heap in Phase 1 |
| Strings | Pointer-to-uint8, C-style | Short strings (length byte + data, max 255) |
| Code generation | AST → table-driven pattern matching with bottom-up register allocation | Direct WASM bytecode emission during parsing (no AST, no IR, no register allocator) |
| Linker / global analysis | `cowlink`: dead code removal, static variable placement | No linker — single compilation unit, external `wasm-validate` |
| Bootstrap chain | Cowgol → generated C → native Cowgol → self-hosting | Pascal → `fpc -Mtp` → native → compiles itself to WASM snapshot |
| Separate compilation | Yes, with global analysis across modules | No — host resolves `{$I}` includes before compilation |
| Portability strategy | Many native backends, each ~1–2 KLOC | One backend (WASM), portability via WASM runtimes (wasmi, wasm3, wasmtime, browser) |
| Compiler binary size | 70 KB (80386 Linux ELF), 58 KB (8080 CP/M) | Target: < 1 MB (WASM blob) |
| Self-compile time | ~80 ms on PC | TBD (runs inside WASM interpreter) |

## Design Observations

### Recursion as a design lever

Cowgol's most distinctive constraint is no recursion. This is not an oversight — it is what makes the whole project feasible. Without recursion, the linker can statically prove which functions cannot be live simultaneously, and overlap their variables in memory. On a 6502 with 256 bytes of zero page, this is the difference between "possible" and "impossible." The Cowgol compiler itself uses only 146 bytes of zero page thanks to this technique.

Compact Pascal faces no such pressure. WASM provides a proper call stack with frames, so recursion is free. Forbidding it would be an artificial constraint with no benefit.

### Who runs the compiler

Cowgol's aspiration is running the compiler *on* the target machine — compiling on a BBC Micro. Compact Pascal's aspiration is running the compiler *inside* your application — the WASM snapshot embedded in a Rust or Zig library. Both are forms of "the compiler goes where you are," but pointing in opposite directions: backward to tiny vintage hardware, forward to sandboxed modern runtimes.

### Code generation philosophy

Cowgol has a proper intermediate representation (AST bytecode) and a sophisticated bottom-up pattern-matching code generator with register allocation. This complexity is necessary because its targets have wildly different register files — the 6502 has one accumulator, the 80386 has eight general-purpose registers, the PDP-11 has six. The `newgen` tool reads a backend definition file and generates Cowgol source that performs instruction selection and register allocation simultaneously in a single bottom-up pass.

Compact Pascal emits WASM opcodes directly during parsing — no AST, no IR, no register allocator. WASM is a stack machine, so "register allocation" is the WASM runtime's problem. This dramatically simplifies the compiler. The cost is that Compact Pascal cannot target anything other than WASM without a fundamental architectural change.

### Static vs. dynamic memory

Cowgol's static allocation with overlap analysis is genuinely novel for this class of compiler. It is what a sufficiently smart linker can do when it knows the full call graph and can prove non-concurrency. Memory usage is statically bounded and deterministic.

Compact Pascal uses conventional stack frames in WASM linear memory. Memory usage is proportional to call depth. This is the standard approach for languages that support recursion, and WASM's structured control flow makes it natural.

### One target vs. many

Cowgol's `newgen` system is designed to add backends cheaply — the 80386 backend is 1.2 KLOC. Its value proposition is one language across every retro platform. Compact Pascal inverts this: one target (WASM), every modern platform. The embedding libraries (Rust crate, Zig module) provide portability through WASM runtimes rather than through multiple native backends.

## Potential Improvements Suggested by the Comparison

- **Dead code elimination.** Cowgol's linker strips unreferenced code from the final binary. Compact Pascal currently emits everything, including unused helper functions. WASM runtimes may optimize this away, but the compiler could be smarter about omitting code that is never called.

- **Array type operators.** Cowgol's `@sizeof` and `@indexof` type operators are useful ergonomics for arrays — `@sizeof` returns the element count, `@indexof` yields the smallest integer type that can index the array. These could translate naturally into Compact Pascal's type system as extensions to the existing `sizeof` intrinsic.

## References

[1] D. Given, "Cowgol 2.0," 2022. https://cowlark.com/cowgol/
