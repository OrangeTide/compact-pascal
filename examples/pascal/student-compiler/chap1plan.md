# Chapter 1 Implementation Plan: A Minimal WASM Module

## What the Initial Stub Provides

The initial `pascom.pas` is four lines:

```pascal
{$MODE TP}
program pascom;
begin
end.
```

It compiles with `fpc -Mtp` and does nothing. Everything in Chapter 1 is new.

## Goal

Produce a WASM binary that exports a `_start` function which does nothing and
returns cleanly, accepting the simplest legal Pascal program as input:

```pascal
program empty; begin end.
```

The output must pass `wasm-validate` and exit with code 0 under `wasmtime`.

## What Chapter 1 Builds

### 1. Constants

Declare named constants for:
- Buffer sizes: `SmallBufMax = 4095`, `CodeBufMax = 131071`
- WASM value types: `WasmI32 = $7F`
- WASM section IDs: `SecIdType=1`, `SecIdImport=2`, `SecIdFunc=3`, `SecIdMemory=5`,
  `SecIdGlobal=6`, `SecIdExport=7`, `SecIdCode=10`
- WASM opcodes: `OpEnd=$0B`, `OpI32Const=$41`
- Token kinds: `tkEOF=0` through `tkFalse=206` (full set, used in later chapters)
- WASM type table limits: `MaxWasmTypes=64`, `MaxWasmParams=8`

Declare all token kinds now rather than piecemeal, so `LookupKeyword` can be
written once. The ones not used in Chapter 1 are harmless forward scaffolding.

### 2. Types

```pascal
TSmallBuf  { data: array[0..4095] of byte; len: longint }
TCodeBuf   { data: array[0..131071] of byte; len: longint }
TWasmType  { nparams, params[0..7], nresults, results[0..7] }
```

`TSmallBuf` (4 KB) is used for all small sections. `TCodeBuf` (128 KB) is used
for the code section body, the final output accumulator, and the `startCode`
scratch area where instructions are generated during parsing.

Both buffer types must be global variables, not local ones — Turbo Pascal's stack
is limited and a 128 KB local would overflow it.

### 3. Global Variables

Section buffers (all global):
- `secType`, `secImport`, `secFunc`, `secMemory`, `secGlobal`, `secExport`: `TSmallBuf`
- `secCode`, `startCode`, `outBuf`: `TCodeBuf`

WASM module state:
- `wasmTypes: array[0..63] of TWasmType` — registered type signatures
- `numWasmTypes`, `numImports`, `numDefinedFuncs`: `longint`

Scanner state:
- `ch: char` — current character (always "peeked ahead")
- `srcLine`, `srcCol`: `longint` — for error messages
- `atEof: boolean`
- `pushbackCh: char`, `hasPushback: boolean` — one-character pushback
- `tokKind`, `tokInt`: `longint`; `tokStr: string` — current token

Output file:
- `outFile: file` — untyped file handle for `BlockWrite`

### 4. Error Handling

```pascal
procedure Error(msg: string);
```

Writes `Error: [line:col] msg` to stderr and calls `halt(1)`. All error paths in
the compiler funnel through this.

### 5. Buffer Procedures

`SmallBufInit`, `SmallBufEmit` — zero the length; append one byte with overflow
check.

`CodeBufInit`, `CodeBufEmit` — same for `TCodeBuf`.

### 6. LEB128 Encoding

Three procedures:

- `EmitULEB128(var b: TCodeBuf; value: longint)` — unsigned LEB128 into a
  `TCodeBuf`. Used for section lengths, function counts, body lengths.
- `EmitSLEB128(var b: TCodeBuf; value: longint)` — signed LEB128 into a
  `TCodeBuf`. Used for `i32.const` operands (global initializers, integer
  literals). Requires manual sign extension because TP's `shr` is logical, not
  arithmetic.
- `SmallEmitULEB128(var b: TSmallBuf; value: longint)` — unsigned LEB128 into a
  `TSmallBuf`. Used when emitting function indices into small sections (export
  section, function section).

**SLEB128 sign-extension pattern** (TP-specific):
```pascal
if value >= 0 then
  value := value shr 7
else begin
  value := value shr 7;
  value := value or longint($FE000000);  { restore sign bit }
end;
```

### 7. Output Writing

Two serialisation procedures that write a complete section to `outBuf`:

- `WriteSection(id: byte; var buf: TSmallBuf)` — emits id + ULEB128 length + body.
  Skips if `buf.len = 0`.
- `WriteCodeSec(id: byte; var buf: TCodeBuf)` — same but takes `TCodeBuf`. Used
  only for the code section (potentially large).

### 8. Section Assembly

Six procedures that build section buffers from the compiler's internal state:

| Procedure | Section | Content |
|---|---|---|
| `AssembleTypeSection` | Type (1) | `numWasmTypes` entries; each is `60 nparams [params] nresults [results]` |
| `AssembleFunctionSection` | Function (3) | `numDefinedFuncs` entries; Chapter 1 hardcodes one entry: type index 0 |
| `AssembleMemorySection` | Memory (5) | 1 memory; limits type 1 (has max); min=1, max=256 pages |
| `AssembleGlobalSection` | Global (6) | 1 mutable i32 global; init expr `i32.const 65536; end` |
| `AssembleExportSection` | Export (7) | 2 exports: `_start` (function, index=`numImports`) and `memory` (memory 0) |
| `AssembleCodeSection` | Code (10) | `numDefinedFuncs` bodies; `_start` body = `0 locals + startCode + end` |

`AssembleFunctionSection` in Chapter 1 hardcodes `type index 0`. Later chapters
must generalise this when multiple function types are in use.

**`_start` function index** is always `numImports`, not 0. In Chapter 1
`numImports = 0` so the distinction is moot, but the export section uses
`SmallEmitULEB128(secExport, numImports)` rather than a literal `0` so the
invariant is established from the start.

### 9. WriteModule

Orchestrates the full module assembly:

```
CodeBufInit(outBuf)
AssembleTypeSection
SmallBufInit(secImport)   { no imports }
AssembleFunctionSection
AssembleMemorySection
AssembleGlobalSection
AssembleExportSection
AssembleCodeSection
{ emit 8-byte header }
{ WriteSection / WriteCodeSec in section-ID order }
```

Sections are written in numerical ID order as required by the WASM spec. Sections
with zero length are skipped by `WriteSection`.

### 10. Scanner

Procedures, in dependency order:

- `ReadCh` — reads from stdin; respects `hasPushback`; tracks `srcLine`/`srcCol`;
  sets `atEof` on EOF and leaves `ch = #0`.
- `UnreadCh(c)` — stores one character of pushback.
- `UpperCh(c)` — ASCII uppercase, branchless for non-letters.
- `SkipBraceComment` — called when `ch = left-curly-brace`; reads until matching
  `right-curly-brace` then calls `ReadCh` once to prime `ch` for the next token.
- `SkipParenComment` — called after `(` and `*` are consumed; reads until `*)`.
- `SkipLineComment` — called after second `/` is seen; reads to end of line.
- `SkipWhitespaceAndComments` — outer loop that calls the above. Handles the `(`
  lookahead ambiguity: reads one more char; if `*` follows, it is a comment;
  otherwise pushes back and leaves `ch = '('` for token dispatch.
- `LookupKeyword(s)` — returns the token kind for an uppercased identifier, or
  `tkIdent` if not a keyword. All keywords through `tkFalse` are included.
- `NextToken` — the main scanner. Calls `SkipWhitespaceAndComments`, then dispatches
  on `ch`:

| Input | Action |
|---|---|
| `'A'..'Z'`, `'a'..'z'`, `'_'` | Scan identifier; uppercase each char; `LookupKeyword` |
| `'0'..'9'` | Scan decimal integer into `tokInt` |
| `'$'` | Scan hexadecimal integer into `tokInt` |
| `'+'`, `'-'`, `'*'`, `'/'`, `'('`, `')'`, `';'`, `','`, `'['`, `']'`, `'^'`, `'='` | Single-char token |
| `':'` | Peek: `':='` → `tkAssign`, else `tkColon` |
| `'.'` | Peek: `'..'` → `tkDotDot`, else `tkDot` |
| `'<'` | Peek: `'<='` → `tkLe`, `'<>'` → `tkNe`, else `tkLt` |
| `'>'` | Peek: `'>='` → `tkGe`, else `tkGt` |
| anything else | `Error('unexpected character: ...')` |

**Shebang handling**: in `InitScanner`, after the first `ReadCh`, if `ch = '#'`,
skip the rest of the line. This allows `pascom.pas` to be invoked as a shebang
interpreter (`#!/usr/bin/env pascom`). The shebang is consumed before any
`NextToken` call, so `NextToken` never sees `'#'` at this stage.

### 11. Parser (minimal)

Two procedures for the Chapter 1 grammar:

```
program <ident> ; begin end .
```

- `Expect(kind)` — asserts `tokKind = kind`, then calls `NextToken`. Writes an
  error to stderr (not via `Error` — inline `writeln` so the expected/got token
  numbers appear) and halts.
- `ParseProgram` — consumes `program <ident> ; begin end .`. Emits nothing into
  `startCode` — the function body is an empty sequence followed by `end`.

### 12. Main Block

```pascal
InitModule;    { zero wasmTypes, numImports=0, numDefinedFuncs=1, register type 0 }
InitScanner;   { srcLine=1, srcCol=0, ReadCh, handle shebang }
NextToken;
ParseProgram;
WriteModule;
Assign(outFile, '/dev/stdout');
Rewrite(outFile, 1);
BlockWrite(outFile, outBuf.data, outBuf.len);
Close(outFile);
```

Binary output requires `BlockWrite` on an untyped file. The standard `write`
procedure is text-mode and will corrupt binary output on some platforms.

## Implementation Order

1. Add constants (buffer sizes, WASM constants, token kinds)
2. Add `TSmallBuf`, `TCodeBuf`, `TWasmType` types
3. Add all global variables
4. Implement `Error`
5. Implement `SmallBufInit/Emit`, `CodeBufInit/Emit`
6. Implement `EmitULEB128`, `EmitSLEB128`, `SmallEmitULEB128`
7. Implement `WriteSection`, `WriteCodeSec`
8. Implement all six `Assemble*` procedures
9. Implement `WriteModule`
10. Implement scanner: `ReadCh`, `UnreadCh`, `UpperCh`, skip-comment procedures,
    `SkipWhitespaceAndComments`, `LookupKeyword`, `NextToken`
11. Implement `Expect`, `ParseProgram`
12. Implement `InitModule`, `InitScanner`, main block
13. Add `tests/empty.pas` (or confirm the Makefile generates it)
14. Run `make bootstrap && make test`

## LEB128 Encoding Reference

Values that appear verbatim in Chapter 1 binary output:

| Value | Use | Bytes |
|---|---|---|
| 65536 (SLEB128) | stack pointer init | `$80 $80 $04` |
| 256 (ULEB128) | memory max pages | `$80 $02` |
| 1 (ULEB128) | minimum memory pages, counts | `$01` |

The WASM module for `program empty; begin end.` is approximately 41 bytes.

## Tests

### `tests/empty.pas`

Generated by the Makefile (`echo 'program empty; begin end.' > $@`). No `.expected`
file needed — the test just validates the WASM binary:

```
make test-strap-empty
```

Checks: `build/native/pascom < tests/empty.pas > build/bootstrap/tests/empty.wasm`,
then `wasm-validate build/bootstrap/tests/empty.wasm`.

## What Is NOT in Chapter 1

- String literals, character constants — Chapter 2
- `and then` / `or else` — Chapter 2
- Expressions, integer arithmetic, `halt` — Chapter 3
- Variables, `:=`, `writeln` — Chapter 4
- Control flow — Chapter 5
- Procedures and functions — Chapter 6
- Import section population (WASI calls) — Chapter 3/4

## Key Design Decisions

**`numImports` invariant**: export the `_start` function as index `numImports`, not
literal 0. Establishes the correct formula from the start so it never needs to
change when imports are added in Chapter 3/4.

**`startCode` separation**: instructions for `_start` accumulate in a separate
`TCodeBuf` during parsing. `AssembleCodeSection` copies them into `secCode` at
the end. This keeps the code-generation path uniform across all chapters.

**`TCodeBuf` reused as `outBuf`**: no need for a separate output buffer type.
`outBuf` is just another `TCodeBuf`.

**No import section in Chapter 1**: `WriteModule` calls `SmallBufInit(secImport)`
to zero it; `WriteSection` skips sections with zero length. The import section
appears automatically as soon as something emits into `secImport`.
