---
title: "Writing a Pascal-to-WASM Compiler"
author: Jon Mayo
date: 2026
header-includes:
  - |
    ```{=typst}
    #set page(margin: (top: 2cm, bottom: 2cm, left: 2cm, right: 2cm))
    #set par(leading: 0.7em)
    #set block(spacing: 1.2em)
    ```
include-before:
  - |
    ```{=typst}
    #page(header: none, footer: none)[
      #v(1fr)
      #align(center)[
        #text(size: 18pt, weight: "bold")[Writing a Pascal-to-WASM Compiler]
        #v(0.5em)
        #text(size: 12pt, style: "italic")[A Compact Pascal Tutorial]
        #v(1.5em)
        #text(size: 11pt)[Jon Mayo]
        #v(0.3em)
        #text(size: 11pt)[2026]
      ]
      #v(1fr)
    ]
    #page(header: none, footer: none)[
      #v(1fr)
      #align(center, image("doc/compact-pascal-cover.svg", width: 50%))
      #v(1em)
      #align(center, text(weight: "bold", size: 12pt, fill: rgb("#cc0000"))[DRAFT — This document is a work in progress and subject to change.])
      #v(1fr)
    ]
    ```
---

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
| 1 | WASM binary emission | A valid WASM module (no Pascal yet) |
| 2 | Scanner (lexer) | Tokenized Pascal source |
| 3 | Expressions and code generation | `program P; begin halt(2+3) end.` |
| 4 | Variables and I/O | Programs with `var`, `:=`, `writeln` |
| 5 | Control flow | `if`, `while`, `for`, `repeat`, `case` |
| 6 | Procedures and functions | Subroutines, parameters, local variables |
| 7 | Nested scopes | Nested procedures with upvalue access |
| 8 | Strings | Short strings, `readln`, string operations |
| 9 | Structured types | Records, arrays, variant records, sets |
| 10 | The full compiler | Remaining features, compiler directives, self-hosting |

The book's source code *is* the compiler. Each chapter's code builds on the previous chapter, and the final chapter produces the complete Phase 1 compiler.

### Prerequisites

You need three tools installed:

- **Free Pascal Compiler (fpc)** — to bootstrap the compiler. We use `-Mtp` mode (Turbo Pascal 7.0 compatibility). Any fpc 3.x release works.
- **wasmtime** — a WASM runtime that supports WASI preview 1, for running compiled programs. wasmer also works.
- **wasm-validate** — from the wabt toolkit, for validating the WASM binaries our compiler produces.

### Conventions

Code examples are shown in Pascal with syntax highlighting. Generated WASM is shown as WebAssembly Text (WAT) for readability, even though the compiler emits binary directly:

```pascal
{ Pascal source }
x := a + b;
```

```wat
;; Generated WASM (WAT representation)
global.get $sp
i32.const 0       ;; offset of x
i32.add
global.get $sp
i32.const 4       ;; offset of a
i32.add
i32.load align=4 offset=0
global.get $sp
i32.const 8       ;; offset of b
i32.add
i32.load align=4 offset=0
i32.add
i32.store align=4 offset=0
```

When the compiler emits binary opcodes, the source code includes WAT pseudo-code in comments so you can see what instruction is being produced:

```pascal
{ ;; WAT: i32.add }
EmitByte($6A);
```

\newpage

## Chapter 1: A Minimal WASM Module

Before writing any Pascal parsing code, we need to understand our target. This chapter builds the infrastructure for emitting WASM binaries — section buffers, LEB128 encoding, and the module assembly logic. By the end, the compiler will accept the simplest possible Pascal program and produce a valid WASM module that does nothing and exits cleanly.

### What Is WebAssembly?

WebAssembly is a binary instruction format for a stack-based virtual machine. It was designed as a compilation target — you are not meant to write WASM by hand, but to compile source languages into it. A WASM module is a sequence of *sections*, each with a specific purpose:

| Section | ID | Purpose |
|---|---|---|
| Type | 1 | Function type signatures (parameter and return types) |
| Import | 2 | Functions provided by the host environment |
| Function | 3 | Maps function indices to type signatures |
| Memory | 5 | Linear memory declarations (size, limits) |
| Global | 6 | Mutable and immutable global variables |
| Export | 7 | Names visible to the host (functions, memory) |
| Code | 10 | Function bodies (local declarations + instructions) |
| Data | 11 | Initial values for linear memory (string literals, etc.) |
| Custom | 0 | Metadata (name section, debug info) |

Sections must appear in numerical order by ID. The compiler discovers information out of order during parsing — for example, it does not know all function types until it has parsed the entire program — so it accumulates each section in a separate in-memory buffer during the single pass, then writes them all in the correct order at the end. This is single-pass *parsing* with buffered output.

### The WASM Binary Format

Every WASM module starts with an 8-byte header:

```
00 61 73 6D    magic number (\0asm)
01 00 00 00    version 1
```

After the header, sections appear in order. Each section is encoded as:

```
section_id  (1 byte)
size        (unsigned LEB128 — byte length of the section body)
body        (size bytes of section-specific data)
```

The section body format varies by section type. Some sections start with a count of entries (type section lists its types, function section lists its function-to-type mappings, etc.).

### LEB128 Encoding

WASM uses LEB128 (Little-Endian Base 128) for variable-length integers throughout the binary format — section lengths, function indices, local counts, instruction operands, and more. Understanding LEB128 is essential because it appears in nearly every byte the compiler emits.

The idea is simple: use 7 bits of each byte for data and the high bit as a continuation flag. If the high bit is set, more bytes follow. If it is clear, this is the last byte.

**Unsigned LEB128** encodes non-negative integers:

| Value | Bytes | Explanation |
|---|---|---|
| 0 | `00` | Fits in 7 bits |
| 127 | `7F` | Maximum single-byte value |
| 128 | `80 01` | Low 7 bits = 0, continuation; next byte = 1 |
| 624485 | `E5 8E 26` | Three bytes needed |

Here is the implementation:

```pascal
procedure EmitULEB128(var b: TCodeBuf; value: longint);
var
  v: longint;
  byt: byte;
begin
  v := value;
  repeat
    byt := v and $7F;       { extract low 7 bits }
    v := v shr 7;           { shift right by 7 }
    if v <> 0 then
      byt := byt or $80;    { set continuation bit }
    CodeBufEmit(b, byt);
  until v = 0;
end;
```

**Signed LEB128** (SLEB128) is similar but uses sign extension. It encodes negative numbers by propagating the sign bit. The algorithm is trickier because Turbo Pascal's `shr` operator is a *logical* right shift (fills with zeros), not an *arithmetic* right shift (fills with the sign bit). We must handle negative values explicitly:

```pascal
procedure EmitSLEB128(var b: TCodeBuf; value: longint);
var
  byt: byte;
  more: boolean;
begin
  more := true;
  while more do begin
    byt := value and $7F;
    if value >= 0 then
      value := value shr 7
    else begin
      value := value shr 7;
      value := value or longint($FE000000);  { sign-extend }
    end;
    if (value = 0) and ((byt and $40) = 0) then
      more := false
    else if (value = -1) and ((byt and $40) <> 0) then
      more := false;
    if more then
      byt := byt or $80;
    CodeBufEmit(b, byt);
  end;
end;
```

The termination condition checks the sign bit (bit 6) of the last byte. If the value is non-negative and bit 6 is clear, we are done. If the value is -1 (all ones) and bit 6 is set, we are done. In both cases, the decoder can reconstruct the original value by sign-extending from bit 6.

### Section Buffers

The compiler uses fixed-size byte arrays as section buffers. Each buffer is a record with a data array and a length counter:

```pascal
type
  TSmallBuf = record
    data: array[0..4095] of byte;  { 4 KB }
    len: longint;
  end;

  TCodeBuf = record
    data: array[0..131071] of byte;  { 128 KB }
    len: longint;
  end;
```

Most sections are small (the type section, function section, and export section rarely exceed a few hundred bytes), so 4 KB is generous. The code section needs to be much larger because it contains every function body in the program. 128 KB is enough for any Phase 1 program; the compiler itself, once self-hosted, will be well under this limit.

Writing a byte to a buffer is trivial:

```pascal
procedure CodeBufEmit(var b: TCodeBuf; v: byte);
begin
  if b.len > CodeBufMax then
    Error('code buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;
```

These buffers are declared as global variables, not local variables, because Turbo Pascal has limited stack space and a 128 KB local variable would overflow it. As globals, they live in the data segment where space is plentiful.

### The Minimal Module

Our goal for this chapter is a WASM module that exports a `_start` function (the WASI entry point) which does nothing and returns. Here is what the module needs:

1. **Type section:** One type signature `() -> ()` (no parameters, no results) for `_start`.
2. **Function section:** One entry mapping function 0 to type 0.
3. **Memory section:** One linear memory, initially 1 page (64 KB), maximum 256 pages (16 MB).
4. **Global section:** One mutable `i32` global for the stack pointer, initialized to 65536 (top of the first memory page).
5. **Export section:** Two exports — `_start` as a function and `memory` as a memory.
6. **Code section:** One function body containing only the `end` opcode.

No import section (the empty program does not call any WASI functions), no data section (no string literals or global variables).

### Assembling the Type Section

The type section lists all function type signatures used in the module. Each entry starts with the `func` marker byte (`0x60`), followed by the parameter count, parameter types, result count, and result types. For our `() -> ()` type:

```
01          1 type entry
60          func marker
00          0 parameters
00          0 results
```

In the compiler, types are tracked in a global table and assembled into the section buffer at the end:

```pascal
procedure AssembleTypeSection;
var i, j: longint;
begin
  SmallBufInit(secType);
  SmallBufEmit(secType, numWasmTypes);
  for i := 0 to numWasmTypes - 1 do begin
    SmallBufEmit(secType, $60);  { func marker }
    SmallBufEmit(secType, wasmTypes[i].nparams);
    for j := 0 to wasmTypes[i].nparams - 1 do
      SmallBufEmit(secType, wasmTypes[i].params[j]);
    SmallBufEmit(secType, wasmTypes[i].nresults);
    for j := 0 to wasmTypes[i].nresults - 1 do
      SmallBufEmit(secType, wasmTypes[i].results[j]);
  end;
end;
```

### Assembling the Memory and Global Sections

The memory section declares one linear memory with an initial and maximum page count. The global section declares the stack pointer — a mutable `i32` global initialized to the top of the first memory page (65536 bytes):

```pascal
procedure AssembleGlobalSection;
begin
  SmallBufInit(secGlobal);
  SmallBufEmit(secGlobal, 1);        { 1 global }
  SmallBufEmit(secGlobal, $7F);      { type: i32 }
  SmallBufEmit(secGlobal, 1);        { mutable }
  { init expr: i32.const 65536, end }
  SmallBufEmit(secGlobal, $41);      { i32.const opcode }
  SmallBufEmit(secGlobal, $80);
  SmallBufEmit(secGlobal, $80);
  SmallBufEmit(secGlobal, $04);      { 65536 in SLEB128 }
  SmallBufEmit(secGlobal, $0B);      { end opcode }
end;
```

The initialization expression (`i32.const 65536; end`) is a restricted subset of WASM instructions that can appear in global initializers and data segment offsets. Only `*.const` and `end` are allowed — no function calls, no loads, no control flow.

### Assembling the Export Section

Exports make module contents visible to the host. Each export has a name (UTF-8 string), an export kind (function, memory, table, or global), and an index. The string is encoded as a length-prefixed byte sequence:

```pascal
procedure AssembleExportSection;
begin
  SmallBufInit(secExport);
  SmallBufEmit(secExport, 2);  { 2 exports }
  { "_start" as function }
  SmallBufEmit(secExport, 6);  { name length }
  SmallBufEmit(secExport, ord('_'));
  SmallBufEmit(secExport, ord('s'));
  SmallBufEmit(secExport, ord('t'));
  SmallBufEmit(secExport, ord('a'));
  SmallBufEmit(secExport, ord('r'));
  SmallBufEmit(secExport, ord('t'));
  SmallBufEmit(secExport, $00);  { export kind: function }
  SmallEmitULEB128(secExport, numImports);  { function index }
  { "memory" as memory 0 }
  SmallBufEmit(secExport, 6);
  SmallBufEmit(secExport, ord('m'));
  SmallBufEmit(secExport, ord('e'));
  SmallBufEmit(secExport, ord('m'));
  SmallBufEmit(secExport, ord('o'));
  SmallBufEmit(secExport, ord('r'));
  SmallBufEmit(secExport, ord('y'));
  SmallBufEmit(secExport, $02);  { export kind: memory }
  SmallBufEmit(secExport, 0);    { memory index 0 }
end;
```

Notice that the `_start` function index is `numImports`, not 0. In WASM, imported functions occupy the first indices (0 through `numImports-1`), and defined functions follow. Our empty program has no imports, so `_start` is function 0. But once we add WASI imports like `proc_exit` or `fd_write`, defined functions shift upward.

### Assembling the Code Section

The code section contains function bodies. Each body is encoded as a byte length (LEB128), followed by a vector of local declarations, followed by the instruction sequence, ending with the `end` opcode (`0x0B`):

```pascal
procedure AssembleCodeSection;
var bodyLen: longint;
begin
  CodeBufInit(secCode);
  EmitULEB128(secCode, numDefinedFuncs);  { function count }

  { _start body }
  bodyLen := 1 + startCode.len + 1;
  { = local_decl_count (1 byte, value 0)
    + instruction bytes
    + end opcode (1 byte) }
  EmitULEB128(secCode, bodyLen);
  CodeBufEmit(secCode, 0);  { 0 local declarations }
  CopyBufToCode(startCode); { copy accumulated instructions }
  CodeBufEmit(secCode, $0B);  { end }
end;
```

For the minimal module, `startCode` is empty — the function body is just `[0x00, 0x0B]` (zero locals, end).

### Writing the Module

With all sections assembled, writing the module is straightforward: emit the 8-byte header, then each section in order. Each section is written as its ID byte, followed by the section body length as ULEB128, followed by the body bytes:

```pascal
procedure WriteSection(id: byte; var buf; bufLen: longint);
begin
  if bufLen = 0 then exit;  { skip empty sections }
  WriteOutputByte(id);
  WriteOutputULEB128(bufLen);
  WriteOutputBytes(buf, bufLen);
end;

procedure WriteModule;
begin
  { Header }
  WriteOutputByte($00); WriteOutputByte($61);
  WriteOutputByte($73); WriteOutputByte($6D);  { \0asm }
  WriteOutputByte($01); WriteOutputByte($00);
  WriteOutputByte($00); WriteOutputByte($00);  { version 1 }

  { Sections in order }
  WriteSection(1, secType.data, secType.len);
  WriteSection(2, secImport.data, secImport.len);
  WriteSection(3, secFunc.data, secFunc.len);
  WriteSection(5, secMemory.data, secMemory.len);
  WriteSection(6, secGlobal.data, secGlobal.len);
  WriteSection(7, secExport.data, secExport.len);
  WriteSection(10, secCode.data, secCode.len);
  { ... data section handled separately }
end;
```

### Binary Output from fpc

One practical detail: the compiler writes binary WASM to stdout. In fpc, the standard `write` procedure is designed for text, not raw bytes. For binary output, we accumulate the entire module in a byte buffer (`outBuf`), then flush it at the end using `BlockWrite` on an untyped file:

```pascal
Assign(outFile, '/dev/stdout');
Rewrite(outFile, 1);
BlockWrite(outFile, outBuf.data, outBuf.len);
Close(outFile);
```

`BlockRead` and `BlockWrite` are the byte-level I/O primitives throughout the compiler — for reading source from stdin and writing binary WASM to stdout. They are standard Pascal, available in fpc's System unit on every platform (Linux, macOS, Windows) with no `uses` clause needed.

When the compiler compiles itself, it needs to emit code for these same `BlockRead`/`BlockWrite` calls. Here the self-hosted compiler takes a shortcut: it treats `file` as a `longint` — just an integer file descriptor. `Assign`, `Reset`, and `Rewrite` become no-ops. `BlockRead` and `BlockWrite` become thin wrappers around WASI `fd_read` and `fd_write`, building a single iovec in scratch memory and making the WASI call.

This works because the compiler's I/O is extremely narrow. It never opens files by name or accesses the filesystem — source comes from stdin (fd 0), binary output goes to stdout (fd 1), and error diagnostics go to stderr (fd 2). These three file descriptors are pre-opened by the WASI runtime. The `Assign`/`Reset`/`Rewrite` calls in the bootstrap source become dead code under self-hosting, and the `file` variables are just integer constants 0, 1, and 2. A general-purpose Pascal compiler could not get away with this, but a compiler that reads one stream and writes another can.

### Minimal Parser

To parse the simplest Pascal program — `program empty; begin end.` — we need just enough of a parser to recognize the keywords `program`, `begin`, and `end`, consume identifiers and semicolons, and expect a final dot. At this stage the scanner only needs to handle whitespace, identifiers, and the `;` and `.` punctuation characters.

The parser validates the structure and emits nothing into `startCode` (the function body is empty), then calls `WriteModule` to produce the output.

### Testing

```bash
$ echo 'program empty; begin end.' | ./cpas > empty.wasm
$ wasm-validate empty.wasm
$ wasmtime run empty.wasm
$ echo $?
0
```

The program compiles to a valid WASM module, passes validation, and exits with code 0. The output file is about 50 bytes — a complete WASM module with header, five sections, and a function body that does nothing.

\newpage

## Chapter 2: The Scanner

The scanner (also called lexer or tokenizer) reads Pascal source code character by character and produces a stream of tokens. It is the compiler's eyes — everything the parser sees has been filtered and classified by the scanner first.

### Character Input

The scanner reads from stdin one character at a time, tracking line and column numbers for error messages. A one-character pushback mechanism handles cases where the scanner reads one character too far (for example, distinguishing `(` from `(*`):

```pascal
var
  ch: char;
  srcLine, srcCol: longint;
  atEof: boolean;
  pushbackCh: char;
  hasPushback: boolean;

procedure ReadCh;
begin
  if hasPushback then begin
    ch := pushbackCh;
    hasPushback := false;
    exit;
  end;
  if eof(input) then begin
    ch := #0;
    atEof := true;
  end else begin
    read(input, ch);
    if ch = #10 then begin
      srcLine := srcLine + 1;
      srcCol := 0;
    end else
      srcCol := srcCol + 1;
  end;
end;

procedure UnreadCh(c: char);
begin
  pushbackCh := c;
  hasPushback := true;
end;
```

### Token Types

Each token has a kind (what it is), an optional string value (for identifiers and string literals), and an optional integer value (for numeric literals):

```pascal
var
  tokKind: longint;
  tokInt: longint;
  tokStr: string;
```

Token kinds are integer constants. Punctuation and operators get their own constants (`tkPlus`, `tkAssign`, `tkLParen`, etc.), keywords are recognized during identifier scanning, and there are two literal types: `tkInteger` and `tkString`.

The complete set of keywords the compiler recognizes includes all Pascal reserved words plus built-in identifiers like `write`, `writeln`, `halt`, `true`, and `false`. Keywords are case-insensitive — the scanner uppercases identifiers before checking the keyword table.

### The NextToken Procedure

The core of the scanner is `NextToken`, which advances to the next token by skipping whitespace and comments, then dispatching on the first significant character:

```pascal
procedure NextToken;
var ident: string;
    kw: longint;
begin
  SkipWhitespaceAndComments;

  if atEof then begin
    tokKind := tkEOF;
    exit;
  end;

  case ch of
    'A'..'Z', 'a'..'z', '_':
      { Scan identifier, check keyword table }
    '0'..'9':
      { Scan decimal integer }
    '$':
      { Scan hexadecimal integer }
    '''':
      { Scan string literal }
    '#':
      { Scan character constant }
    '+': begin tokKind := tkPlus; ReadCh; end;
    '-': begin tokKind := tkMinus; ReadCh; end;
    { ... other single-character tokens ... }
    ':': begin
      ReadCh;
      if ch = '=' then begin tokKind := tkAssign; ReadCh; end
      else tokKind := tkColon;
    end;
    '.': begin
      ReadCh;
      if ch = '.' then begin tokKind := tkDotDot; ReadCh; end
      else tokKind := tkDot;
    end;
  else
    Error('unexpected character: ' + ch);
  end;
end;
```

Multi-character tokens like `:=`, `<>`, `<=`, `>=`, and `..` are handled by reading the first character, then checking whether the next character extends the token.

### Case-Insensitive Keywords

Pascal is case-insensitive. The scanner uppercases each identifier as it is scanned, then checks it against a keyword lookup function:

```pascal
function LookupKeyword(const s: string): longint;
begin
  LookupKeyword := -1;
  if s = 'PROGRAM' then LookupKeyword := tkProgram
  else if s = 'BEGIN' then LookupKeyword := tkBegin
  else if s = 'END' then LookupKeyword := tkEnd
  else if s = 'VAR' then LookupKeyword := tkVar
  { ... all other keywords ... }
end;
```

If the uppercased identifier matches a keyword, `tokKind` is set to the keyword token. Otherwise, it is `tkIdent` and `tokStr` holds the uppercased name.

A hash table would be faster for a large keyword set, but our keyword list is small (under 40 entries) and a linear comparison chain compiles cleanly under Turbo Pascal. Optimization is not a concern at this stage.

### Comments

Compact Pascal supports three comment styles:

- **Brace comments:** `{ ... }` — the traditional Pascal comment.
- **Parenthesis-star comments:** `(* ... *)` — the alternative Pascal comment.
- **Line comments:** `// ...` — the Turbo Pascal/Delphi extension.

Additionally, if the very first byte of the source is `#`, the rest of the first line is ignored. This permits Unix-style interpreter directives (`#!/usr/bin/env cpas`). The check fires once during scanner initialization, before any tokens are read, so it does not conflict with the `#n` character constant syntax — a valid Pascal source file always begins with a keyword like `program`, never with `#`.

Comments are stripped by `SkipWhitespaceAndComments`, which runs at the start of every `NextToken` call. Two cases require lookahead to distinguish a comment from an operator:

- `(` vs `(*` — The scanner reads the character after `(`; if it is `*`, we enter comment-skipping mode. If not, we push the character back with `UnreadCh` and return `(` to the parser.
- `/` vs `//` — The scanner reads the character after `/`; if it is also `/`, we skip to end-of-line. If not, we push the character back and return `/` as the real division operator. (In Phase 1, `/` is recognized but rejected since the `real` type is deferred.)

The `(*` case:

```pascal
else if (not atEof) and (ch = '(') then begin
  ReadCh;
  if ch = '*' then begin
    SkipParenComment;
    done := false;
  end else begin
    UnreadCh(ch);  { push back the char after ( }
    ch := '(';     { restore ( as current char }
  end;
end;
```

Brace comments containing `{$` are compiler directives in Free Pascal. In Phase 1, the compiler skips all brace comments uniformly. Directive parsing will be added in Chapter 10.

### String Literals

String literals are enclosed in single quotes. A literal single quote within a string is escaped by doubling it: `'it''s'` produces the four-byte string `it's`.

The scanner also handles Turbo Pascal character constants: `#n` (decimal) and `#$n` (hexadecimal) produce raw byte values 0-255. Adjacent string segments and character constants are folded into a single string token by the scanner:

```
'Hello'#13#10    { one 7-byte string: Hello followed by CR LF }
#27'[2J'         { 4 bytes: ESC [ 2 J }
```

This folding happens at scan time, so the parser always receives a single `tkString` token containing the complete byte sequence.

### Numeric Literals

Decimal integers (`42`, `0`, `2147483647`) and hexadecimal integers (`$FF`, `$1A2B`) are scanned into `tokInt`. The scanner detects real number syntax (a dot followed by a digit, as in `3.14`) and rejects it with a clear error message — real numbers are not supported in Phase 1.

### Error Reporting

All compiler errors halt immediately with a diagnostic written to stderr:

```pascal
procedure Error(msg: string);
begin
  writeln(stderr, 'Error: [', srcLine, ':', srcCol, '] ', msg);
  halt(1);
end;
```

This "halt on first error" strategy is the simplest for a single-pass compiler. There is no error recovery, no attempt to continue parsing after an error, and no cascading false positives. The tradeoff is that you fix one error at a time, but each error message is always accurate.

### Two-Word Operators

Compact Pascal supports the ISO 10206 short-circuit operators `and then` and `or else`. These are two-word tokens: when the scanner sees `and`, it peeks ahead; if the next identifier is `then`, the token is `and then` (a short-circuit conjunction). Otherwise, it pushes the second identifier back as a pending token and returns plain `and`.

A simple pending-token mechanism handles the pushback:

```pascal
var
  pendingTok: boolean;
  pendingKind: longint;
  pendingStr: string;
```

At the start of `NextToken`, if `pendingTok` is true, the pending token is returned immediately without scanning. This mechanism is used only for the two-word operator lookahead.

\newpage

## Chapter 3: Expressions and Code Generation

This is where the compiler starts producing real output. We build a Pratt parser (precedence climbing) for expressions and emit WASM instructions as we parse. By the end of this chapter, the compiler can handle:

```pascal
program calc;
begin
  halt(6 * 7)
end.
```

Running this compiled program produces exit code 42.

### The Stack Machine Model

WASM is a stack machine. Every instruction consumes operands from the top of the stack and pushes results back. This is a perfect match for expression evaluation — the compiler simply emits instructions in the order it encounters expression nodes, and the stack takes care of the rest:

| Pascal | WASM instructions | Stack effect |
|---|---|---|
| `2 + 3` | `i32.const 2`, `i32.const 3`, `i32.add` | `[] → [2] → [2,3] → [5]` |
| `a * b + c` | load a, load b, `i32.mul`, load c, `i32.add` | `[] → [a*b] → [a*b+c]` |
| `-(x)` | load x, `i32.const -1`, `i32.mul` | `[] → [x] → [-x]` |

No temporary variables. No registers. The WASM operand stack *is* the expression evaluator. A recursive-descent parser that emits WASM instructions as it parses naturally produces correct code for arbitrarily complex expressions.

### Precedence Climbing

The classic Wirth approach uses a cascade of parsing functions — `ParseFactor` calls `ParseTerm`, which calls `ParseSimpleExpression`, which calls `ParseExpression` — one function per precedence level. This works but produces many small functions, each doing essentially the same thing with different operators.

Precedence climbing (also called Pratt parsing) replaces the cascade with a single function `ParseExpression(minPrec)` and a precedence table. The function parses a prefix (a literal, variable, unary operator, or parenthesized subexpression), then loops over infix operators. For each operator, it checks the operator's precedence against `minPrec`; if the operator binds tightly enough, it consumes the operator, recursively parses the right-hand side with the operator's precedence as the new minimum, and emits the operator instruction.

Here is the precedence table:

| Precedence | Operators |
|---|---|
| 1 (lowest) | `or`, `or else` |
| 2 | `and`, `and then` |
| 3 | `=`, `<>`, `<`, `>`, `<=`, `>=`, `in` |
| 4 | `+`, `-` |
| 5 | `*`, `div`, `mod` |
| 6 (highest) | `not`, unary `+`/`-` |

And the implementation:

```pascal
procedure ParseExpression(minPrec: longint);
var prec, op: longint;
begin
  { Parse prefix }
  case tokKind of
    tkInteger: begin
      EmitI32Const(tokInt);
      NextToken;
    end;
    tkTrue: begin
      EmitI32Const(1);
      NextToken;
    end;
    tkFalse: begin
      EmitI32Const(0);
      NextToken;
    end;
    tkLParen: begin
      NextToken;
      ParseExpression(PrecNone);
      Expect(tkRParen);
    end;
    tkMinus: begin
      NextToken;
      ParseExpression(PrecUnary);
      EmitI32Const(-1);
      EmitOp(OpI32Mul);
    end;
    tkNot: begin
      NextToken;
      ParseExpression(PrecUnary);
      EmitI32Const(-1);
      EmitOp(OpI32Xor);
    end;
    { ... identifiers, variables ... }
  end;

  { Parse infix operators }
  while true do begin
    op := tokKind;
    case op of
      tkPlus:      prec := PrecAdd;
      tkMinus:     prec := PrecAdd;
      tkStar:      prec := PrecMul;
      tkDiv:       prec := PrecMul;
      tkMod:       prec := PrecMul;
      tkAnd:       prec := PrecAnd;
      tkOr:        prec := PrecOr;
      tkEqual:     prec := PrecCompare;
      { ... other operators ... }
    else
      break;  { not an operator — stop }
    end;

    if prec <= minPrec then
      break;  { operator does not bind tightly enough }

    NextToken;
    ParseExpression(prec);  { parse right-hand side }

    { Emit the operator }
    case op of
      tkPlus:  EmitOp(OpI32Add);   { ;; WAT: i32.add }
      tkMinus: EmitOp(OpI32Sub);   { ;; WAT: i32.sub }
      tkStar:  EmitOp(OpI32Mul);   { ;; WAT: i32.mul }
      tkDiv:   EmitOp(OpI32DivS);  { ;; WAT: i32.div_s }
      tkMod:   EmitOp(OpI32RemS);  { ;; WAT: i32.rem_s }
      tkAnd:   EmitOp(OpI32And);   { ;; WAT: i32.and }
      tkOr:    EmitOp(OpI32Or);    { ;; WAT: i32.or }
      tkEqual: EmitOp(OpI32Eq);    { ;; WAT: i32.eq }
      { ... }
    end;
  end;
end;
```

### Why Precedence Climbing?

The Pratt approach has three advantages for this project:

1. **Fewer procedures.** One function handles all binary operators instead of four or five nested functions. Less code means less to self-host.
2. **Easy to extend.** Adding a new operator is one line in the precedence lookup and one line in the emit switch. No restructuring of the call chain.
3. **Identical parsing behavior.** Precedence climbing parses the exact same language as the Wirth cascade. The parse trees are identical — only the code structure differs.

The approach is still recursive descent. The prefix parsing uses recursion for subexpressions and unary operators. Only the infix operator handling uses a loop.

### Unary Minus

WASM has no negate instruction. The compiler implements unary minus as multiplication by -1:

```pascal
{ Parse: -expr }
EmitI32Const(-1);
EmitOp(OpI32Mul);  { ;; WAT: i32.const -1; i32.mul }
```

An alternative is `i32.const 0; <expr>; i32.sub`, but that requires emitting the zero *before* the expression value, which the compiler has already emitted. Multiplication by -1 works regardless of when the operand was pushed.

### The `halt` Intrinsic

To test expression evaluation, we need a way to observe the result. `halt(n)` calls WASI `proc_exit` with the given exit code, so the expression's value becomes the process exit code — directly observable from the shell.

`halt` is parsed as a statement, not a function call. When the compiler sees `halt`, it parses the optional parenthesized expression, emits the expression code (which leaves an i32 on the WASM stack), then emits a call to `proc_exit`:

```pascal
tkHalt: begin
  NextToken;
  if tokKind = tkLParen then begin
    NextToken;
    ParseExpression(PrecNone);
    Expect(tkRParen);
  end else
    EmitI32Const(0);          { halt with no argument = halt(0) }
  EmitCall(EnsureProcExit);   { ;; WAT: call $proc_exit }
end;
```

### WASI Imports

`proc_exit` is a function provided by the WASI host, not defined in our module. It must be *imported*. WASM imports are declared in the import section, and imported functions occupy the lowest function indices (before any defined functions).

The compiler tracks imports lazily — `proc_exit` is only imported if the program uses `halt`. The `EnsureProcExit` function checks whether the import already exists, adds it if not, and returns its function index:

```pascal
function EnsureProcExit: longint;
begin
  if idxProcExit < 0 then
    idxProcExit := AddImport(
      'wasi_snapshot_preview1', 'proc_exit', TypeI32Void);
  EnsureProcExit := idxProcExit;
end;
```

This lazy approach means the import section is empty for programs that do not use `halt` or I/O. Programs with no WASI imports can run on any WASM runtime, not just WASI-compatible ones.

### Function Index Arithmetic

WASM function indices are globally numbered. Imported functions get indices 0 through `numImports-1`, then defined functions continue from `numImports` onward. The `_start` function is always the first defined function, so its index is `numImports`.

When the export section references `_start`, it must use this computed index, not a hardcoded 0. Similarly, when the compiler emits a `call` instruction to `proc_exit`, it uses the import's index (which was assigned by `AddImport`).

### Testing

```
$ echo 'program calc; begin halt(6 * 7) end.' | ./cpas > calc.wasm
$ wasmtime run calc.wasm; echo $?
42
$ echo 'program math; begin halt((10 + 20) * 3 - 48 div 2) end.' \
    | ./cpas > math.wasm
$ wasmtime run math.wasm; echo $?
66
```

The expression `(10 + 20) * 3 - 48 div 2` evaluates to `30 * 3 - 24 = 66`. The compiler correctly handles operator precedence, parentheses, and all integer arithmetic operations.

\newpage

## Chapter 4: Variables and I/O

This chapter adds variable declarations, assignment statements, and the `write`/`writeln` intrinsics. By the end, the compiler produces the classic first program:

```pascal
program hello;
begin
  writeln('Hello, world!')
end.
```

### The Symbol Table

The symbol table maps identifiers to their meanings — is this name a variable, a constant, a type? What is its type? Where is it stored? The compiler uses the simplest possible data structure: a flat array of records with a scope stack.

```pascal
type
  TSymEntry = record
    name: string[63];
    kind: longint;     { skConst, skVar, skType, etc. }
    typ: longint;      { tyInteger, tyBoolean, etc. }
    level: longint;    { nesting level }
    offset: longint;   { stack offset for vars, value for consts }
    size: longint;     { byte size }
  end;

var
  syms: array[0..1023] of TSymEntry;
  numSyms: longint;
  scopeBase: array[0..31] of longint;
  scopeDepth: longint;
```

Entering a scope pushes a marker (the current symbol count). Leaving a scope resets the count back to the marker, effectively discarding all symbols added in that scope. Lookup walks backward from the top, so inner scopes shadow outer ones:

```pascal
procedure EnterScope;
begin
  scopeDepth := scopeDepth + 1;
  scopeBase[scopeDepth] := numSyms;
end;

procedure LeaveScope;
begin
  numSyms := scopeBase[scopeDepth];
  scopeDepth := scopeDepth - 1;
end;

function LookupSym(const name: string): longint;
var i: longint;
begin
  LookupSym := -1;
  for i := numSyms - 1 downto 0 do
    if syms[i].name = name then begin
      LookupSym := i;
      exit;
    end;
end;
```

Before parsing begins, the compiler pre-populates the symbol table with built-in types (`INTEGER`, `BOOLEAN`, `CHAR`, `LONGINT`) and constants (`TRUE`, `FALSE`, `MAXINT`).

### Memory Layout

Variables live in WASM linear memory, not on the WASM operand stack. The compiler uses a stack-based allocation scheme:

```
[ nil guard | data segment (string literals, scratch) | ... ← stack ]
0           4                                          SP   65536
```

- **Nil guard (bytes 0-3):** Reserved. Dereferencing `nil` reads zeros instead of corrupting data.
- **Data segment:** String literals, I/O scratch buffers, typed constants. Grows upward from address 4 during compilation.
- **Stack:** Grows downward from the top of memory. A mutable WASM global `$sp` (global index 0) points to the current stack top.

When a block with variables is entered, the compiler subtracts the frame size from `$sp`. When the block exits, it adds the frame size back. All variables in the block are accessed at fixed offsets from `$sp`:

```pascal
{ Frame prologue: $sp -= frameSize }
EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);  { global.get $sp }
EmitI32Const(curFrameSize);
EmitOp(OpI32Sub);                                  { i32.sub }
EmitOp(OpGlobalSet); EmitULEB128(startCode, 0);  { global.set $sp }
```

### Variable Declarations

Parsing `var x, y: integer;` adds two symbols to the symbol table, each with a stack offset and a size of 4 bytes (all ordinal types are stored as WASM `i32`):

```pascal
sym := AddSym(names[i], skVar, syms[typId].typ);
syms[sym].offset := curFrameSize;
syms[sym].size := 4;
curFrameSize := curFrameSize + 4;
```

After all `var` declarations are parsed, `curFrameSize` holds the total frame size for the current block. The frame prologue is emitted before the `begin...end` statement part.

### Assignment

An assignment `x := expr` computes the target address, evaluates the expression, and stores the result:

```pascal
{ Compute address: $sp + offset }
EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
EmitI32Const(syms[sym].offset);
EmitOp(OpI32Add);
{ Evaluate expression — leaves value on stack }
ParseExpression(PrecNone);
{ Store }
EmitI32Store(2, 0);  { ;; WAT: i32.store align=4 offset=0 }
```

The WASM `i32.store` instruction pops two values: the address and the value to store, in that order. The address must be computed *before* the expression, which is why the compiler emits the address calculation first.

### Loading Variables in Expressions

When an identifier appears in an expression and resolves to a variable, the compiler emits code to load its value:

```pascal
{ ;; WAT: global.get $sp
  ;;      i32.const <offset>
  ;;      i32.add
  ;;      i32.load align=4 offset=0 }
EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
EmitI32Const(syms[sym].offset);
EmitOp(OpI32Add);
EmitI32Load(2, 0);
```

### Writing String Literals

`write('Hello')` and `writeln('Hello')` write string data to stdout via WASI `fd_write`. The string literal is placed in the data segment at compile time (at a known address and length). At runtime, the compiler emits code to:

1. Set up an *iovec* (I/O vector) in the data segment — an 8-byte struct containing a buffer pointer and a length.
2. Call `fd_write(fd=1, iovs=iovec_addr, iovs_len=1, nwritten=scratch_addr)`.
3. Drop the errno return value.

```pascal
procedure EmitWriteString(addr, len: longint);
begin
  EnsureIOBuffers;
  { Set iovec.buf = addr }
  EmitI32Const(addrIovec);
  EmitI32Const(addr);
  EmitI32Store(2, 0);
  { Set iovec.len = len }
  EmitI32Const(addrIovec + 4);
  EmitI32Const(len);
  EmitI32Store(2, 0);
  { Call fd_write(1, iovec, 1, nwritten) }
  EmitI32Const(1);              { fd = stdout }
  EmitI32Const(addrIovec);
  EmitI32Const(1);              { iovs_len = 1 }
  EmitI32Const(addrNwritten);
  EmitCall(EnsureFdWrite);
  EmitOp(OpDrop);               { discard errno }
end;
```

The iovec, nwritten scratch, and newline byte are allocated in the data segment on first use by `EnsureIOBuffers`. They are aligned to 4-byte boundaries because WASM's `i32.store` requires aligned addresses.

### Writing Integers

Integer output is more complex — the value must be converted to decimal ASCII before writing. The compiler emits a separate WASM helper function, `__write_int`, that takes an `i32` parameter and writes its decimal representation to stdout.

The helper uses a 20-byte scratch buffer in the data segment and writes digits right-to-left:

1. If the value is negative, negate it and remember the sign.
2. If the value is zero, write `'0'` directly.
3. Otherwise, extract digits by repeated division: `digit = value mod 10 + '0'`, `value = value div 10`.
4. If negative, prepend `'-'`.
5. Call `fd_write` with the result region.

The helper function is emitted into its own code buffer (`helperCode`) and assembled into the code section alongside `_start`. It uses two WASM locals beyond its parameter: `pos` (the current write position) and `neg_flag` (whether the number is negative).

In the calling code, `writeln(42)` simply evaluates the expression (pushing `42` onto the WASM stack) and emits `call $__write_int`:

```pascal
procedure EmitWriteInt;
begin
  EmitCall(EnsureWriteInt);
end;
```

### The `writeln` Newline

After writing all arguments, `writeln` appends a newline character. The compiler stores a single newline byte (`\n`, value 10) in the data segment and emits a `fd_write` call for that one byte.

### Parsing write/writeln Arguments

`write` and `writeln` accept a variable number of arguments of different types — string literals and integer expressions — separated by commas. The parser dispatches on the current token:

```pascal
procedure ParseWriteArgs(withNewline: boolean);
begin
  if tokKind = tkLParen then begin
    NextToken;
    while tokKind <> tkRParen do begin
      if tokKind = tkString then begin
        { String literal — emit fd_write directly }
        addr := EmitDataString(tokStr);
        EmitWriteString(addr, length(tokStr));
        NextToken;
      end else begin
        { Integer expression }
        ParseExpression(PrecNone);
        EmitWriteInt;
      end;
      if tokKind = tkComma then NextToken;
    end;
    Expect(tkRParen);
  end;
  if withNewline then
    EmitWriteNewline;
end;
```

### Testing

```
$ echo 'program hello; begin writeln('"'"'Hello, world!'"'"') end.' \
    | ./cpas > hello.wasm
$ wasmtime run hello.wasm
Hello, world!

$ cat vars.pas
program vars;
var x: integer;
begin
  x := 42;
  writeln(x)
end.
$ ./cpas < vars.pas > vars.wasm && wasmtime run vars.wasm
42
```

\newpage

## Chapter 5: Control Flow

With variables and I/O in place, we can now add the control structures that make programs interesting: `if`/`else`, `while`, `for`, `repeat`/`until`, and compound statements with `begin`/`end`. This chapter is where WASM's structured control flow — `block`, `loop`, `br`, `br_if`, `if`/`else`/`end` — comes into play.

### WASM Structured Control Flow

Unlike most machine architectures, WASM does not have arbitrary `goto` or branch-to-address instructions. Instead, it provides *structured* control flow constructs:

- **`block ... end`** — a sequence of instructions with a label. `br N` branches forward to the end of the Nth enclosing `block`.
- **`loop ... end`** — a sequence of instructions with a label. `br N` branches backward to the *start* of the Nth enclosing `loop`.
- **`if ... else ... end`** — conditional execution. Pops an `i32` from the stack; if nonzero, executes the `if` body; otherwise, executes the `else` body (if present).
- **`br N`** — unconditional branch to the Nth enclosing block/loop label.
- **`br_if N`** — conditional branch. Pops an `i32`; branches if nonzero.

This design makes WASM programs *reducible* — there are no irreducible control flow graphs, which simplifies validation and JIT compilation. For a Pascal compiler, this is not a limitation because Pascal's control structures are already structured.

### `if`/`else`

Pascal's `if` maps directly to WASM's `if`/`else`/`end`:

```pascal
{ if expr then stmt1 else stmt2 }
ParseExpression(PrecNone);  { leaves condition on stack }
Expect(tkThen);
EmitOp(OpIf);
EmitOp(WasmVoid);           { block type: void }
ParseStatement;              { then branch }
if tokKind = tkElse then begin
  NextToken;
  EmitOp(OpElse);
  ParseStatement;            { else branch }
end;
EmitOp(OpEnd);
```

The generated WASM:

```wat
;; if x > 5 then writeln('yes') else writeln('no')
global.get $sp
i32.const 0          ;; offset of x
i32.add
i32.load align=4
i32.const 5
i32.gt_s             ;; x > 5?
if                   ;; consumes the i32 condition
  ;; ... code for writeln('yes') ...
else
  ;; ... code for writeln('no') ...
end
```

The dangling-else ambiguity (`if a then if b then s1 else s2`) is resolved in the standard way: `else` binds to the nearest unmatched `if`. Since the parser is recursive, this happens naturally — the inner `if` consumes the `else` before the outer `if` has a chance to.

### `while`

A `while` loop needs a backward branch (to repeat) and a forward branch (to exit). WASM provides this with a `block`/`loop` pair:

```pascal
{ while expr do stmt }
EmitOp(OpBlock); EmitOp(WasmVoid);  { outer block = exit target }
EmitOp(OpLoop);  EmitOp(WasmVoid);  { inner loop = continue target }
ParseExpression(PrecNone);
Expect(tkDo);
EmitOp(OpI32Eqz);                   { invert: if NOT condition }
EmitOp(OpBrIf); EmitULEB128(startCode, 1);  { br_if 1 = exit block }
ParseStatement;                      { loop body }
EmitOp(OpBr); EmitULEB128(startCode, 0);    { br 0 = continue loop }
EmitOp(OpEnd);                       { end loop }
EmitOp(OpEnd);                       { end block }
```

The label indices in `br` and `br_if` are relative to the enclosing constructs: 0 means the immediately enclosing `block`/`loop`, 1 means the next one out, and so on. In our `while` codegen, the `loop` is at depth 0 and the `block` is at depth 1. `br_if 1` exits the block (forward branch), and `br 0` continues the loop (backward branch to the loop header).

The key insight is that `br` on a `block` jumps *forward* (to after the `end`), but `br` on a `loop` jumps *backward* (to the loop start). This asymmetry is what makes loops possible in WASM's structured control flow.

### `for`

Pascal's `for` loop is syntactic sugar for an init-test-body-increment pattern:

```pascal
for i := 1 to 10 do writeln(i)
```

The compiler desugars this to:

1. Evaluate and store the initial value.
2. Evaluate and store the limit value (once, not on every iteration).
3. Emit a `block`/`loop` pair.
4. Compare the counter to the limit; `br_if` to exit if counter > limit.
5. Execute the body.
6. Increment the counter.
7. `br` back to the loop.

The limit value must be evaluated once and stored, because the limit expression could have side effects or be expensive. The compiler uses a scratch location in the data segment for this.

`downto` uses the same pattern but with `i32.lt_s` for the exit condition and `i32.sub` for the decrement.

### `repeat`/`until`

`repeat`/`until` is the simplest loop because the body always executes at least once, and the condition is tested at the bottom:

```pascal
{ repeat stmts until expr }
EmitOp(OpLoop); EmitOp(WasmVoid);  { loop target }
ParseStatement;
while tokKind = tkSemicolon do begin
  NextToken;
  if tokKind <> tkUntil then
    ParseStatement;
end;
Expect(tkUntil);
ParseExpression(PrecNone);
EmitOp(OpI32Eqz);                             { if NOT condition }
EmitOp(OpBrIf); EmitULEB128(startCode, 0);   { br_if 0 = repeat }
EmitOp(OpEnd);
```

No outer `block` is needed because the only branch is the backward `br_if` to the loop. When the condition becomes true, execution falls through the `end` naturally.

Notice that `repeat`/`until` allows multiple semicolon-separated statements between `repeat` and `until`, unlike `while` which takes a single statement (use `begin`/`end` for multiple statements).

### Compound Statements

`begin ... end` is a compound statement that groups multiple statements into one:

```pascal
tkBegin: begin
  NextToken;
  ParseStatement;
  while tokKind = tkSemicolon do begin
    NextToken;
    if tokKind <> tkEnd then
      ParseStatement;
  end;
  Expect(tkEnd);
end;
```

The `if tokKind <> tkEnd` check allows trailing semicolons before `end`, which is standard Pascal behavior. The empty statement between `;` and `end` is a no-op.

### Testing: FizzBuzz

With control flow in place, the compiler handles non-trivial algorithms:

```pascal
program fizzbuzz;
var i: integer;
begin
  for i := 1 to 20 do
  begin
    if (i mod 15) = 0 then
      writeln('FizzBuzz')
    else if (i mod 3) = 0 then
      writeln('Fizz')
    else if (i mod 5) = 0 then
      writeln('Buzz')
    else
      writeln(i)
  end
end.
```

Output:

```
1
2
Fizz
4
Buzz
Fizz
7
8
Fizz
Buzz
11
Fizz
13
14
FizzBuzz
16
17
Fizz
19
Buzz
```

This program exercises `for` loops, `if`/`else` chains, `mod` arithmetic, string output, and integer output — all working together.

### Testing: Factorial

```pascal
program fact5;
var n, f: integer;
begin
  n := 5;
  f := 1;
  while n > 1 do
  begin
    f := f * n;
    n := n - 1
  end;
  halt(f)
end.
```

Exit code: 120 (5! = 120).

\newpage

## Chapter 6: Procedures and Functions

*[Introduces procedure and function declarations, parameter passing (value, var, const), separate stack frames for each call, the `call` instruction, forward declarations, function return values via the function-name assignment, `exit` intrinsic, and external declarations for WASI imports. Test: recursive Fibonacci.]*

*[Forward declarations: when two procedures need to call each other (mutual recursion), the first one can be declared `forward`. The body appears later with the full header repeated — parameter list, types, and return type must all be restated. This differs from Turbo Pascal, where the forward body omits the parameter list. Compact Pascal follows the IP Pascal convention because it keeps the signature visible at the definition site, which is friendlier to readers who encounter the body without having seen the forward declaration. From the compiler's perspective, the repeated header is simply parsed and checked against the existing symbol table entry.]*

\newpage

## Chapter 7: Nested Scopes

*[The Dijkstra display technique: 8 WASM globals where `display[N]` holds the frame pointer for nesting level N. Upvalue access through the display — always two loads, O(1). Save/restore display on entry/exit. Zero overhead for top-level procedures. Scope enter/exit in the symbol table. The most conceptually challenging chapter. Test: nested procedure that accesses enclosing variable.]*

\newpage

## Chapter 8: Strings

*[Short string representation (length byte + data, max 255). String assignment copies the full string. String comparison (lexicographic). `length`, `copy`, `pos`, `concat`, `delete`, `insert` as compiler intrinsics. String parameters: `const`/`var` passed by reference, value parameters copied. `readln` implementation with a line buffer and `fd_read`. Integer-to-string and string-to-integer conversion for `read(n)`/`write(n)`. Test: program that reads a name and greets.]*

\newpage

## Chapter 9: Structured Types

*[Records: field offsets in linear memory, the `with` statement. Arrays: index calculation from base address and element size, bounds checking with `{$R+}`. Variant records: overlapping fields at the same offset, tag field. Set types: bitmap representation, `in`, `+`, `*`, `-` operators. Pointer types: address-of operator, dereference. `sizeof` intrinsic. Test: program with an array of records.]*

\newpage

## Chapter 10: The Full Compiler

*[Remaining features: typed constants, enumerated types and subranges, type casts, hex literals, compiler directives (`{$R+/-}`, `{$Q+/-}`, `{$MEMORY}`, `{$EXPORT}`, `{$IMPORT}`, `{$DESCRIPTION}`). The WASM name section for readable stack traces. The `-dump` flag for instruction listing. Error message formatting with tags. The test suite infrastructure (`compiler-tests/run-tests.sh`). Self-hosting: compiling the compiler with itself. Verifying the fixpoint.]*

\newpage

## Afterword: Where to Go from Here

The compiler you have built handles a substantial subset of Pascal and produces real WASM binaries. But the language was deliberately kept small to fit in a teachable, single-pass compiler. This afterword sketches several directions for extending the compiler — each one a project in its own right.

### Exceptions

Pascal's `try`/`except` (or a simpler `try`/`on` variant) can be implemented in WASM 1.0 without the WASM exception handling proposal. The key technique is *structured unwinding*: each `try` block becomes a WASM `block`, and raising an exception branches to the nearest enclosing handler via `br`. The exception value is passed through a global variable or a designated memory location.

The main complexity is cleanup: if a procedure has local resources (allocated memory, open files), the compiler must emit cleanup code at each `try` boundary. This is a form of stack unwinding — the compiler generates a chain of `br` instructions that unwind through nested blocks.

**What it requires:** No new WASM features. The parser needs `try`/`except`/`finally` syntax. Code generation adds `block`/`br` wrappers around protected regions. The symbol table needs to track which scopes have exception handlers.

**Further reading:** The WASM exception handling proposal (Phase 4 as of 2025) adds native `try`/`catch`/`throw` instructions. If targeting WASM runtimes that support it, exception handling becomes much simpler.

### Operator Overloading

Operator overloading maps operator tokens (`+`, `-`, `*`, `=`, etc.) to user-defined function calls through the symbol table. When the expression parser encounters `a + b` and both operands are of a type with an overloaded `+`, it emits a function call instead of `i32.add`.

**What it requires:** A way to register operator functions in the symbol table (keyed by operator token and operand types). The expression parser checks for overloads before emitting built-in operations. The type checker resolves which overload to call based on operand types. Single-pass compatible — the overload must be declared before use.

### Pattern Matching

An extended `case` statement with destructuring — matching record fields, nested variant tags, and guard expressions — improves ergonomics for code that currently uses nested `if`/`case` chains.

**What it requires:** The `case` parser is extended to accept record field patterns and nested matches. Code generation produces a decision tree of comparisons and branches. The main challenge is generating efficient code when patterns overlap or when the match is exhaustive.

### First-Class Closures

The compiler already supports nested procedures with upvalue access via the Dijkstra display. Making nested procedures *first-class* — assignable to variables, passable as arguments, returnable from functions — requires heap-allocated closure environments, because the enclosing stack frame may be gone when the closure runs.

**What it requires:** Dynamic allocation (`New`/`Dispose`), which means Phase 5 of the project. Each closure becomes a fat pointer: a function table index plus a pointer to the heap-allocated environment. The compiler must detect which variables are captured and allocate them on the heap instead of the stack. WASM's `call_indirect` instruction handles the dynamic dispatch.

### Generics

Monomorphized generics (like C++ templates or Rust generics) instantiate a separate copy of the generic code for each type argument. This produces efficient code but requires storing the generic body and replaying it for each instantiation — fundamentally a multi-pass operation.

**What it requires:** An AST or intermediate representation to store unparsed generic bodies. A second pass to instantiate them. This breaks the single-pass architecture, which is why generics were excluded from the core language. A restricted form (generics over pointer-sized types only, using type erasure) could preserve single-pass at the cost of runtime overhead.

### Suggested Reading

- Niklaus Wirth, *Compiler Construction* (1996/2005) — the single-pass recursive-descent tradition this compiler follows.
- Robert Nystrom, *Crafting Interpreters* (2021) — a modern, accessible compiler tutorial. Covers Pratt parsing, closures, and garbage collection.
- Andrew Appel, *Modern Compiler Implementation in ML/Java/C* (1998) — comprehensive treatment of type systems, register allocation, and optimization.
- The WebAssembly Specification, https://webassembly.github.io/spec/ — the definitive reference for the target format.

\newpage

## Appendix A: WASM Instruction Reference

A quick reference for the WASM instructions used by the compiler, organized by category.

### Stack Operations

| Instruction | Opcode | Stack | Description |
|---|---|---|---|
| `drop` | `0x1A` | `[val] → []` | Discard top value |
| `select` | `0x1B` | `[a,b,c] → [a or b]` | If c≠0 then a, else b |
| `local.get n` | `0x20` | `[] → [val]` | Push local variable |
| `local.set n` | `0x21` | `[val] → []` | Pop into local variable |
| `local.tee n` | `0x22` | `[val] → [val]` | Copy into local, keep on stack |
| `global.get n` | `0x23` | `[] → [val]` | Push global variable |
| `global.set n` | `0x24` | `[val] → []` | Pop into global variable |

### Integer Arithmetic

| Instruction | Opcode | Stack | Description |
|---|---|---|---|
| `i32.const n` | `0x41` | `[] → [n]` | Push integer constant (SLEB128) |
| `i32.add` | `0x6A` | `[a,b] → [a+b]` | Addition |
| `i32.sub` | `0x6B` | `[a,b] → [a-b]` | Subtraction |
| `i32.mul` | `0x6C` | `[a,b] → [a×b]` | Multiplication |
| `i32.div_s` | `0x6D` | `[a,b] → [a/b]` | Signed division |
| `i32.rem_s` | `0x6F` | `[a,b] → [a mod b]` | Signed remainder |
| `i32.and` | `0x71` | `[a,b] → [a∧b]` | Bitwise AND |
| `i32.or` | `0x72` | `[a,b] → [a∨b]` | Bitwise OR |
| `i32.xor` | `0x73` | `[a,b] → [a⊕b]` | Bitwise XOR |
| `i32.shl` | `0x74` | `[a,b] → [a≪b]` | Shift left |
| `i32.shr_s` | `0x75` | `[a,b] → [a≫b]` | Arithmetic shift right |
| `i32.shr_u` | `0x76` | `[a,b] → [a≫b]` | Logical shift right |

### Memory

| Instruction | Opcode | Stack | Description |
|---|---|---|---|
| `i32.load` | `0x28` | `[addr] → [val]` | Load 32-bit value |
| `i32.load8_s` | `0x2C` | `[addr] → [val]` | Load byte (sign-extend) |
| `i32.load8_u` | `0x2D` | `[addr] → [val]` | Load byte (zero-extend) |
| `i32.load16_s` | `0x2E` | `[addr] → [val]` | Load 16-bit (sign-extend) |
| `i32.load16_u` | `0x2F` | `[addr] → [val]` | Load 16-bit (zero-extend) |
| `i32.store` | `0x36` | `[addr,val] → []` | Store 32-bit value |
| `i32.store8` | `0x3A` | `[addr,val] → []` | Store low byte |
| `i32.store16` | `0x3B` | `[addr,val] → []` | Store low 16 bits |

Memory instructions take two immediate operands after the opcode: `align` (ULEB128, log2 of alignment) and `offset` (ULEB128, added to the address from the stack).

### Control Flow

| Instruction | Opcode | Description |
|---|---|---|
| `unreachable` | `0x00` | Trap immediately |
| `nop` | `0x01` | No operation |
| `block bt` | `0x02` | Begin block (forward branch target) |
| `loop bt` | `0x03` | Begin loop (backward branch target) |
| `if bt` | `0x04` | Conditional block (pops i32 condition) |
| `else` | `0x05` | Begin else branch |
| `end` | `0x0B` | End block/loop/if/function |
| `br n` | `0x0C` | Branch to nth enclosing label |
| `br_if n` | `0x0D` | Conditional branch (pops i32) |
| `return` | `0x0F` | Return from function |
| `call n` | `0x10` | Call function by index |
| `call_indirect` | `0x11` | Indirect call through table |

The block type `bt` is typically `0x40` (void — no value produced) or a value type byte (`0x7F` for i32) indicating the block produces a value.

### Comparison

| Instruction | Opcode | Stack | Description |
|---|---|---|---|
| `i32.eqz` | `0x45` | `[a] → [a==0]` | Equal to zero |
| `i32.eq` | `0x46` | `[a,b] → [a==b]` | Equal |
| `i32.ne` | `0x47` | `[a,b] → [a≠b]` | Not equal |
| `i32.lt_s` | `0x48` | `[a,b] → [a<b]` | Signed less than |
| `i32.lt_u` | `0x49` | `[a,b] → [a<b]` | Unsigned less than |
| `i32.gt_s` | `0x4A` | `[a,b] → [a>b]` | Signed greater than |
| `i32.gt_u` | `0x4B` | `[a,b] → [a>b]` | Unsigned greater than |
| `i32.le_s` | `0x4C` | `[a,b] → [a≤b]` | Signed less or equal |
| `i32.le_u` | `0x4D` | `[a,b] → [a≤b]` | Unsigned less or equal |
| `i32.ge_s` | `0x4E` | `[a,b] → [a≥b]` | Signed greater or equal |
| `i32.ge_u` | `0x4F` | `[a,b] → [a≥b]` | Unsigned greater or equal |

\newpage

## Appendix B: Compact Pascal Grammar

See the *Compact Pascal Language Reference* for the complete formal grammar in EBNF notation.

---

Copyright 2026 Jon Mayo. This document is licensed under the [Creative Commons Attribution 4.0 International License (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
