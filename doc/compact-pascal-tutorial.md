---
title: |
  Building a Pascal Compiler\
  That Targets WebAssembly
subtitle: A Step-by-Step Guide Using Compact Pascal
author: Jon Mayo
date: 2026
header-includes:
  - |
    ```{=typst}
    #set page(margin: (top: 2.5cm, bottom: 2.5cm, left: 2.5cm, right: 2.5cm))
    #set par(leading: 0.7em)
    #set block(spacing: 1.2em)
    #align(center, image("doc/compact-pascal-cover.svg", width: 40%))
    #v(1em)
    #align(center, text(weight: "bold", size: 12pt, fill: rgb("#cc0000"))[DRAFT — This document is a work in progress and subject to change.])
    ```
---

\newpage

## Preface

This book walks you through building a complete Pascal compiler from scratch. The compiler reads Compact Pascal source code and produces WebAssembly (WASM) binaries that run in browsers, on the command line, or embedded in applications. By the end, you will have a working, self-hosting compiler — one that can compile its own source code.

The compiler is written in Pascal itself, which means you will learn the language by implementing it. Every design decision — from the lexer's character handling to the stack frame layout — is explained as it arises. No prior compiler experience is assumed, though familiarity with at least one programming language is expected.

### Why Pascal? Why WASM?

Pascal was designed for teaching. Its syntax is readable, its type system is strict, and its structure maps cleanly to a single-pass compiler. These qualities have not changed in fifty years.

WebAssembly is a modern compilation target — a portable, sandboxed bytecode that runs everywhere. WASM's stack machine architecture is a natural fit for a recursive-descent compiler: each expression evaluation maps directly to a sequence of stack operations with no register allocation.

Together, they make an ideal teaching project: the source language is simple enough to parse in one pass, and the target is modern enough to be practically useful.

### How This Book Is Organized

Each chapter adds one major capability to the compiler. After every chapter, you have a working compiler that handles a progressively larger subset of the language. The chapters follow the implementation order:

| Chapter | What You Build | What You Can Compile |
|---|---|---|
| 1 | Project setup, WASM basics | A minimal WASM module (no Pascal yet) |
| 2 | Scanner (lexer) | Tokenized Pascal source |
| 3 | Expressions and code generation | `program P; begin halt(2+3) end.` |
| 4 | Variables and assignment | Programs with `var`, `:=`, `write` |
| 5 | Control flow | `if`, `while`, `for`, `repeat`, `case` |
| 6 | Procedures and functions | Subroutines, parameters, local variables |
| 7 | Nested scopes | Nested procedures with upvalue access |
| 8 | Strings | Short strings, `readln`, string operations |
| 9 | Structured types | Records, arrays, variant records, sets |
| 10 | The full compiler | Remaining features, compiler directives, self-hosting |

The book's source code *is* the compiler. Each chapter's code builds on the previous chapter, and the final chapter produces the complete Phase 1 compiler.

### Conventions

Code examples are shown in Pascal with syntax highlighting. Generated WASM is shown as WebAssembly Text (WAT) for readability, even though the compiler emits binary directly:

```pascal
{ Pascal source }
x := a + b;
```

```wat
;; Generated WASM (WAT representation)
local.get $a
local.get $b
i32.add
local.set $x
```

When the compiler emits binary opcodes, the source code includes WAT pseudo-code in comments so you can see what instruction is being produced:

```pascal
{ ;; WAT: i32.add }
EmitByte($6A);
```

\newpage

## Chapter 1: A Minimal WASM Module

Before writing any Pascal parsing code, we need to understand our target. This chapter builds a minimal WASM binary by hand — byte by byte — to establish the foundation that the rest of the compiler builds on.

### What Is WebAssembly?

WebAssembly is a binary instruction format for a stack-based virtual machine. A WASM module is a sequence of sections, each with a specific purpose:

| Section | ID | Purpose |
|---|---|---|
| Type | 1 | Function signatures |
| Function | 3 | Maps function indices to type indices |
| Memory | 5 | Linear memory declarations |
| Export | 7 | Names visible to the host |
| Code | 10 | Function bodies (instructions) |
| Custom | 0 | Metadata (name section, debug info) |

The compiler will build each section in a separate in-memory buffer during parsing, then write them all in the correct order at the end. This is single-pass *parsing* with buffered output.

### The WASM Binary Format

Every WASM module starts with an 8-byte header:

```
00 61 73 6D    magic number (\0asm)
01 00 00 00    version 1
```

After the header, sections appear in order. Each section has a one-byte ID, a length (LEB128-encoded), and the section data.

### LEB128 Encoding

WASM uses LEB128 (Little-Endian Base 128) for variable-length integers. This encoding is used for section lengths, function indices, local counts, and many other values. Understanding it is essential:

```pascal
procedure EmitULEB(value: longint);
begin
  repeat
    { ;; Emit low 7 bits, set high bit if more bytes follow }
    if value > $7F then
      EmitByte(value and $7F or $80)
    else
      EmitByte(value and $7F);
    value := value shr 7;
  until value = 0;
end;
```

Signed LEB128 (SLEB128) is similar but uses sign extension. The compiler needs both: unsigned for lengths and indices, signed for integer constants.

### Building the Minimal Module

Our first program will be a WASM module that exports a `_start` function which calls `proc_exit(0)`. This is the WASI equivalent of a program that does nothing and exits successfully.

*[Chapter continues with step-by-step construction of each WASM section...]*

\newpage

## Chapter 2: The Scanner

The scanner (also called lexer or tokenizer) reads Pascal source code character by character and produces a stream of tokens. It is the compiler's eyes — everything the parser sees has been filtered and classified by the scanner.

### Token Types

```pascal
type
  TTokenKind = (
    tkIdentifier, tkInteger, tkString,
    tkPlus, tkMinus, tkStar, tkSlash,
    tkLParen, tkRParen, tkLBracket, tkRBracket,
    tkAssign, tkColon, tkSemicolon, tkComma, tkDot, tkDotDot,
    tkEqual, tkNotEqual, tkLess, tkGreater, tkLessEqual, tkGreaterEqual,
    tkCaret,
    { keywords }
    tkAnd, tkArray, tkBegin, tkCase, tkConst,
    tkDiv, tkDo, tkDownto, tkElse, tkEnd,
    tkExternal, tkFor, tkForward, tkFunction, tkIf,
    tkImplement, tkIn, tkInterface, tkMod, tkNil,
    tkNot, tkOf, tkOr, tkProcedure, tkProgram,
    tkRecord, tkRepeat, tkSet, tkString_, tkThen,
    tkTo, tkType, tkUntil, tkVar, tkWhile, tkWith,
    { special }
    tkEOF
  );
```

### The NextToken Procedure

The heart of the scanner is a single procedure that advances to the next token. The parser calls `NextToken` whenever it needs to consume a token, and examines the current token record to decide what to do:

```pascal
var
  Token: record
    Kind: TTokenKind;
    Name: string;       { identifier name or string value }
    Value: longint;     { integer value }
    Line, Col: integer; { source position for error messages }
  end;
```

*[Chapter continues with character classification, keyword lookup, string literal handling, character constants, comments, and compiler directives...]*

\newpage

## Chapter 3: Expressions and Code Generation

This is where the compiler starts producing real output. We build a Pratt parser (precedence climbing) for expressions and emit WASM instructions as we parse.

### The Stack Machine Model

WASM is a stack machine. Every instruction consumes operands from the stack and pushes results back. This is a perfect match for expression evaluation:

| Pascal | WASM instructions | Stack effect |
|---|---|---|
| `2 + 3` | `i32.const 2`, `i32.const 3`, `i32.add` | `[] → [2] → [2,3] → [5]` |
| `a * b + c` | `get a`, `get b`, `i32.mul`, `get c`, `i32.add` | `[] → [a] → [a,b] → [a*b] → [a*b,c] → [a*b+c]` |

No temporary variables. No registers. The WASM stack *is* the expression evaluator.

### Precedence Climbing

Rather than the classic Wirth cascade of `ParseFactor` / `ParseTerm` / `ParseSimpleExpression` / `ParseExpression`, we use a single `ParseExpression(minPrec)` function with a precedence table:

```pascal
function Precedence(op: TTokenKind): integer;
begin
  case op of
    tkEqual, tkNotEqual, tkLess, tkGreater,
    tkLessEqual, tkGreaterEqual, tkIn:
      Precedence := 1;
    tkPlus, tkMinus, tkOr:
      Precedence := 2;
    tkStar, tkDiv, tkMod, tkAnd:
      Precedence := 3;
  else
    Precedence := 0; { not an operator }
  end;
end;
```

*[Chapter continues with the full Pratt parser, unary operators, the Designator pattern, and emitting the first compilable program...]*

\newpage

## Chapter 4: Variables and Assignment

*[Introduces var declarations, the symbol table, stack frame layout, local.get/local.set, global variables in linear memory, and write/writeln as compiler intrinsics...]*

\newpage

## Chapter 5: Control Flow

*[Covers if/then/else, while, for, repeat/until, case statements. Introduces WASM structured control flow: block/loop/br/br_if. Explains how Pascal's control structures map to WASM's...]*

\newpage

## Chapter 6: Procedures and Functions

*[Parameter passing, call frames, the call instruction, forward declarations, function return values via the result variable, external declarations for WASI imports...]*

\newpage

## Chapter 7: Nested Scopes

*[The Dijkstra display technique, 8 WASM globals, accessing upvalues through the display, scope enter/exit in the symbol table. The most conceptually challenging chapter — takes time to explain the "why" behind the approach...]*

\newpage

## Chapter 8: Strings

*[Short string representation (length byte + data), string operations (copy, concat, compare), string parameters (const/var by reference, value by copy), readln implementation with a line buffer, integer-to-string conversion for write...]*

\newpage

## Chapter 9: Structured Types

*[Records and field access, arrays and index calculation, variant records, set types and bitmap operations, pointer types (deferred to Phase 5 for New/Dispose, but the type system supports them)...]*

\newpage

## Chapter 10: The Full Compiler

*[Remaining features: typed constants, compiler directives, the WASM name section, with statement, enumerated types and subranges. Putting it all together. Self-hosting: compiling the compiler with itself. Testing against the test suite...]*

\newpage

## Appendix A: WASM Instruction Reference

A quick reference for the WASM instructions used by the compiler, organized by category.

### Stack Operations

| Instruction | Opcode | Stack | Description |
|---|---|---|---|
| `local.get n` | `0x20` | `[] → [val]` | Push local variable |
| `local.set n` | `0x21` | `[val] → []` | Pop into local variable |
| `global.get n` | `0x23` | `[] → [val]` | Push global variable |
| `global.set n` | `0x24` | `[val] → []` | Pop into global variable |

### Integer Arithmetic

| Instruction | Opcode | Stack | Description |
|---|---|---|---|
| `i32.const n` | `0x41` | `[] → [n]` | Push integer constant |
| `i32.add` | `0x6A` | `[a,b] → [a+b]` | Addition |
| `i32.sub` | `0x6B` | `[a,b] → [a-b]` | Subtraction |
| `i32.mul` | `0x6C` | `[a,b] → [a*b]` | Multiplication |
| `i32.div_s` | `0x6D` | `[a,b] → [a/b]` | Signed division |
| `i32.rem_s` | `0x6F` | `[a,b] → [a mod b]` | Signed remainder |

### Memory

| Instruction | Opcode | Stack | Description |
|---|---|---|---|
| `i32.load` | `0x28` | `[addr] → [val]` | Load 32-bit value |
| `i32.store` | `0x36` | `[addr,val] → []` | Store 32-bit value |
| `i32.load8_u` | `0x2D` | `[addr] → [val]` | Load byte (zero-extend) |
| `i32.store8` | `0x3A` | `[addr,val] → []` | Store byte |

### Control Flow

| Instruction | Opcode | Description |
|---|---|---|
| `block` | `0x02` | Begin block (branch target) |
| `loop` | `0x03` | Begin loop (branch target) |
| `br n` | `0x0C` | Branch to enclosing block/loop |
| `br_if n` | `0x0D` | Conditional branch |
| `end` | `0x0B` | End block/loop/function |
| `call n` | `0x10` | Call function by index |
| `return` | `0x0F` | Return from function |
| `unreachable` | `0x00` | Trap |

### Comparison

| Instruction | Opcode | Stack | Description |
|---|---|---|---|
| `i32.eqz` | `0x45` | `[a] → [a==0]` | Equal to zero |
| `i32.eq` | `0x46` | `[a,b] → [a==b]` | Equal |
| `i32.ne` | `0x47` | `[a,b] → [a!=b]` | Not equal |
| `i32.lt_s` | `0x48` | `[a,b] → [a<b]` | Signed less than |
| `i32.gt_s` | `0x4A` | `[a,b] → [a>b]` | Signed greater than |
| `i32.le_s` | `0x4C` | `[a,b] → [a<=b]` | Signed less or equal |
| `i32.ge_s` | `0x4E` | `[a,b] → [a>=b]` | Signed greater or equal |

\newpage

## Appendix B: Compact Pascal Grammar

See the *Compact Pascal Language Reference* for the complete formal grammar.

---

Copyright 2026 Jon Mayo. This document is licensed under the [Creative Commons Attribution 4.0 International License (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
