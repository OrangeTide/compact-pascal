---
title: Compact Pascal Language Reference
author: Jon Mayo
date: March 2026
header-includes:
  - |
    ```{=typst}
    #v(0.5em)
    #align(center, text(weight: "bold", size: 12pt, fill: rgb("#cc0000"))[DRAFT — This document is a work in progress and subject to change.])
    ```
---

**Version 26.03.0** (CalVer: YY.MM.minor)

Compact Pascal is a new language in the Pascal family, rooted in ISO 7185 (Standard Pascal) and ISO 10206 (Extended Pascal), with modifications and additional extensions described in this document.

This is a living document. The version number follows [Calendar Versioning](https://calver.org/) using the YY.MM.minor scheme. The minor version increments for changes within the same month.

## Source Encoding

Source files must be encoded in **UTF-8**. The compiler treats source as a sequence of bytes; only ASCII-range bytes (0x00–0x7F) are significant to the lexer. Bytes 0x80–0xFF may appear in string literals and comments and are preserved verbatim. The compiler does not validate, decode, or normalize UTF-8 sequences.

This means `char` is a **byte**, not a Unicode codepoint. `length('café')` returns the byte length (6 in UTF-8, not 4), and `s[i]` indexes by byte. Programs that work with multi-byte characters must account for this, just as in C or Go's `[]byte`. Full Unicode-aware string operations are a library concern, not a language primitive.

Legacy Turbo Pascal source files encoded in CP437 or other 8-bit code pages must be converted to UTF-8 before compilation. This is a one-time conversion performed by standard tools or libraries (e.g., `iconv`, Rust's `encoding_rs` crate, or a simple 128-entry lookup table in Zig).

## Core Language

The core language is a minimal subset of Pascal sufficient for systems programming and compiler construction. Advanced extensions (modules, overloads, dynamic arrays, exceptions, OOP) are not part of the core and may be added in later phases.

Compact Pascal is **case-insensitive** — identifiers, keywords, and type names are matched without regard to case, as in standard Pascal. The sole exception is WASM import/export names in `{$IMPORT}` and `{$EXPORT}` directives, which are case-sensitive because they refer to external WASM symbols.

### Types

- `integer` — signed 32-bit integer (mapped to WASM `i32`).
- `byte` — unsigned 8-bit integer (0..255).
- `shortint` — signed 8-bit integer (-128..127).
- `word` — unsigned 16-bit integer (0..65535).
- `longint` — signed 32-bit integer.
- `boolean` — `true` or `false`.
- `char` — single byte (0..255). Represents one byte of text, not a Unicode codepoint. See [Source Encoding](#source-encoding).
- `string` — TP-style short string (length byte + up to 255 characters). `string[n]` for a maximum length of `n`. See [String Representation](#string-representation).
- `real` — floating point (mapped to WASM `f64`). *(Deferred from Phase 1. The scanner recognizes real literals but the compiler rejects them with an error.)*
- `array` — fixed-size arrays: `array[lo..hi] of T`.
- `record` — composite types, including variant records with a `case` tag. See [Variant Records](#variant-records).
- `set` — bit-set types: `set of T` where T is an ordinal type with up to 256 values. See [Set Types](#set-types).
- Pointers — `^T` typed pointers.
- Enumerated types — mapped to WASM `i32`. Values are assigned sequentially from 0.
- Subranges — a restricted range of an ordinal type. The base type can be inferred from the constants (`1..12` is `integer`, `'A'..'Z'` is `char`, `Mon..Fri` is the enumerated type containing `Mon`) or specified explicitly using the GPC typed subrange syntax: `Day(Mon..Fri)`. Mapped to WASM `i32`. Range bounds are checked at assignment only when `{$R+}` is enabled.
- Procedural types — `procedure (params)` and `function (params): T`.

### Expressions

- Arithmetic: `+`, `-`, `*`, `div`, `mod`.
- Comparison: `=`, `<>`, `<`, `>`, `<=`, `>=`.
- Logical: `and`, `or`, `not`.
- Short-circuit logical: `and then`, `or else` (as in ISO 10206).
- Set operations: `+` (union), `*` (intersection), `-` (difference), `in` (membership).
- String concatenation: `+`.
- Pointer dereference: `p^`.
- Field access: `r.field`.
- Array indexing: `a[i]`.

### Statements

- Assignment: `:=`.
- Procedure call.
- `if ... then ... else` — dangling `else` binds to the nearest unmatched `if`.
- `while ... do`.
- `for ... := ... to/downto ... do`.
- `repeat ... until`.
- `case ... of ... else ... end` — with optional `else` default branch.
- `with ... do` — open a record's fields for unqualified access.
- `begin ... end` compound statement.
- `break` — exit the innermost enclosing loop.
- `continue` — skip to the next iteration of the innermost enclosing loop.

### Declarations

- `const` — named constants with compile-time constant expressions (`const a = 1; b = a + 10;`).
- Typed constants — `const x: integer = 5` (initialized variables, as in Turbo Pascal).
- `type` — type definitions.
- `var` — variable declarations, with optional initializers (`var x: integer = 5`).
- `procedure` and `function` — with value and `var` parameters, plus `const` parameters (pass by reference, immutable).
- `forward` — forward declarations for mutual recursion.
- `external` — marks a procedure or function as provided by the WASM host (used with `{$IMPORT}`). No Pascal body.
- `program` — program header.

### Differences from ISO 7185

- **No file types.** The `file` type and associated operations are omitted.
- **Built-in I/O is a compiler intrinsic.** `write`, `writeln`, `read`, `readln` are supported but compile to WASI preview 1 `fd_write`/`fd_read` calls rather than being part of the runtime. Any WASI-compatible host provides these automatically. See [Built-in I/O](#built-in-io).
- **Dynamic allocation deferred.** `New`/`Dispose` are planned (Phase 5) but not available in the initial release. Phase 1 uses stack-only allocation.
- **Short-circuit evaluation.** `and then` and `or else` operators from ISO 10206 are supported. See [Short-Circuit Evaluation](#short-circuit-evaluation).
- **TP-style short strings.** Strings use the Turbo Pascal length-byte representation, not ISO 7185 packed arrays of char. See [String Representation](#string-representation).
- **Type casts.** Turbo Pascal-style type casts (`integer(ch)`) are supported.
- **32-bit `integer`.** `integer` is 32-bit (WASM `i32`), unlike TP/BP where `integer` is 16-bit. Programs that do not overflow 16-bit values are unaffected.

## Short-Circuit Evaluation

Compact Pascal supports short-circuit (lazy) boolean evaluation using the `and then` and `or else` operators, as defined in ISO 10206 (Extended Pascal).

- `A and then B` — evaluates `B` only if `A` is `true`.
- `A or else B` — evaluates `B` only if `A` is `false`.

The standard `and` and `or` operators retain their ISO 7185 semantics: both operands are always evaluated, but the order of evaluation is unspecified.

Short-circuit operators are essential for guarding expressions that would be invalid if evaluated unconditionally:

```pascal
if (p <> nil) and then (p^.Value > 0) then
  ProcessItem(p);

if (n = 0) or else (total div n > threshold) then
  HandleEdgeCase;
```

`and then` and `or else` have the same precedence as `and` and `or` respectively.

## Case Statement

The `case` statement selects a branch based on the value of an ordinal expression. An optional `else` clause handles values not matched by any branch:

```pascal
case ch of
  '0'..'9': writeln('digit');
  'a'..'z', 'A'..'Z': writeln('letter');
  '+', '-', '*', '/': writeln('operator');
else
  writeln('other');
end;
```

The `else` clause is a Turbo Pascal extension (not in ISO 7185). If no branch matches and there is no `else` clause, execution continues after `end` without error.

## String Representation

Strings use the Turbo Pascal short string representation: a length byte followed by character data in WASM linear memory.

```
Memory layout:  [len: byte] [char1] [char2] ... [charN] [padding to maxlen]
```

- `string` is equivalent to `string[255]` (1 length byte + up to 255 bytes).
- `string[n]` declares a string with a maximum length of `n` bytes (1 ≤ n ≤ 255).
- The length byte at position 0 holds the current length in bytes.
- Bytes are indexed from 1 to `length(s)`.
- No null terminator.
- UTF-8 strings are stored as-is. A string containing multi-byte characters uses more bytes than it has codepoints, and `length` returns the byte count. See [Source Encoding](#source-encoding).

Short strings live on the stack or in records — no heap allocation is required. This representation is identical to Free Pascal in `-Mtp` mode.

The embedding libraries provide helper functions to copy between host strings (Rust `&str`/`String`, Zig `[]const u8`, C `const char *`) and the Pascal string representation in the WASM memory space.

A richer dynamically-allocated string type (pointer + length, no 255-character limit) is planned for Phase 5 when `New`/`Dispose` and heap allocation become available.

### String Parameter Passing

String parameters follow the Turbo Pascal convention:

| Parameter kind | Passing mechanism | Notes |
|---|---|---|
| Value (`s: string`) | Copy | The entire string (up to 256 bytes) is copied to the callee's stack frame. |
| Var (`var s: string`) | By reference | A pointer to the caller's string is passed. The callee can modify it. |
| Const (`const s: string`) | By reference | A pointer is passed, but the callee cannot modify it. |

This matches Turbo Pascal and Free Pascal behavior. `const` and `var` string parameters avoid copying, which is important for performance since a `string[255]` is 256 bytes.

## String Literals

String literals are enclosed in single quotes. A literal single quote within a string is escaped by doubling it (`''`):

```pascal
'hello'           { 5 bytes }
''                { empty string, 0 bytes }
'it''s'           { 4 bytes: i, t, ', s }
'café'            { 6 bytes in UTF-8 }
```

String literals may contain any bytes, including UTF-8 multi-byte sequences, which are preserved verbatim. See [Source Encoding](#source-encoding).

### Character Constants (`#`)

The `#` prefix produces a byte value from a decimal or hexadecimal integer. Values must be in the range 0–255; values above 255 are an error.

```pascal
#13              { CR, byte 13 }
#10              { LF, byte 10 }
#0               { null, byte 0 }
#$1B             { ESC, byte 27 }
#$FF             { byte 255 }
```

Character constants can be concatenated directly with string literals (no `+` operator needed). The scanner folds adjacent sequences into a single string constant:

```pascal
'Hello'#13#10'World'     { 12 bytes: Hello, CR, LF, World }
#27'[2J'                 { 4 bytes: ESC, [, 2, J }
'Tab'#9'here'            { 8 bytes: Tab, HT, here }
#13#10                   { 2 bytes: CR, LF (standalone) }
```

A standalone `#n` is a `char` constant. When concatenated with a string literal or other `#` constants, the result is a `string`.

### Unicode Character Constants (`#u`) *(Future Extension)*

A `#u` prefix followed by hexadecimal digits produces a `rune` value — a 32-bit Unicode codepoint. When a `rune` is concatenated with a string, the compiler encodes it as UTF-8 bytes. This is planned for a later phase alongside the `rune` type; Phase 1 does not support `#u`.

```pascal
#u41              { rune A — same codepoint as #$41 }
#u00E9            { rune é }
#u20AC            { rune € }
#u1F600           { rune 😀 }
'caf' + #u00E9    { string 'café' — rune encoded as UTF-8, 6 bytes }
```

Note that `#u` always uses hexadecimal (no `$` prefix needed). `#$41`, `#u41`, and `#u0041` all represent the same codepoint.

### Rune Type *(Future Extension)*

The `rune` type is a 32-bit ordinal type representing a Unicode codepoint (0 to $10FFFF), inspired by Go's `rune`. It is stored as WASM `i32`. `char` remains a byte; `rune` is a separate type for Unicode-aware operations.

**Concatenation rules:** When a `rune` is concatenated with a string, the rune is encoded as UTF-8. When a `char` with value above 127 is concatenated with a string or `rune`, the compiler emits a warning — bytes 128–255 are not valid standalone UTF-8 and the user almost certainly meant `#u`. This warning applies only to compile-time constants; runtime string operations are byte-level with no checks.

**Built-in functions:**

| Function | Signature | Description |
|---|---|---|
| `RuneLen(s)` | `string → integer` | Number of Unicode codepoints in a UTF-8 string. |
| `DecodeRune(s, i, r)` | `string, integer, var rune → integer` | Decode the rune at byte index `i`, store in `r`, return the next byte index. |
| `EncodeRune(r)` | `rune → string` | UTF-8 encoding of a rune (1–4 byte short string). |
| `RuneChr(n)` | `integer → rune` | Integer to rune (full Unicode range). |
| `ord(r)` | `rune → integer` | Codepoint value. |

Rune literals (`#uHHHH`) are valid in constant expressions, including `case` label ranges:

```pascal
case r of
  #u0000..#u007F: writeln('ASCII');
  #u0080..#u07FF: writeln('2-byte UTF-8');
  #u0800..#uFFFF: writeln('3-byte UTF-8');
end;
```

Planned alongside Phase 5b (richer string type). Phase 1 has no `rune` type.

## Numeric Literals

### Standard Literals

- Decimal integers: `42`, `0`, `1000`
- Hexadecimal (TP-style): `$FF`, `$1A3F`
- Real numbers: `3.14`, `1.0e10`, `2.5e-3` *(recognized by the scanner but rejected in Phase 1)*

### Extended Literals (Optional)

The `{$EXTLITERALS ON/OFF}` directive enables C-style numeric literal prefixes:

| Prefix | Base | Example | Equivalent |
|---|---|---|---|
| `0x` | Hexadecimal | `0xFF` | `$FF` |
| `0o` | Octal | `0o77` | `63` |
| `0b` | Binary | `0b10101010` | `170` |

Extended literals are disabled by default. When enabled, they are available alongside the standard TP `$` hex prefix. This directive is local and may be toggled anywhere in the source.

## Set Types

A set type is declared as `set of T` where `T` is an ordinal type with at most 256 values.

```pascal
type
  CharSet = set of char;          { 256 bits = 32 bytes }
  SmallSet = set of 0..31;        { 32 bits = 4 bytes }
  Digits = set of 0..9;           { 16 bits = 2 bytes (rounded up) }
  Colors = set of (Red, Green, Blue);  { 8 bits = 1 byte }
```

### Representation

Sets are stored as bit arrays in WASM linear memory. The size is determined by the ordinal range of the base type, rounded up to the nearest byte:

| Base type range | Bitmap size |
|---|---|
| 0..7 (8 values) | 1 byte |
| 0..15 (16 values) | 2 bytes |
| 0..31 (32 values) | 4 bytes |
| 0..63 (64 values) | 8 bytes |
| 0..127 (128 values) | 16 bytes |
| 0..255 (256 values) | 32 bytes |

Bit N is set if the value with ordinal N is a member of the set.

### Set Operations

| Operation | Syntax | Description |
|---|---|---|
| Union | `A + B` | Elements in either set. |
| Intersection | `A * B` | Elements in both sets. |
| Difference | `A - B` | Elements in A but not in B. |
| Membership | `x in A` | `true` if `x` is a member of A. |
| Equality | `A = B` | `true` if sets have the same members. |
| Inequality | `A <> B` | `true` if sets differ. |
| Subset | `A <= B` | `true` if every element of A is in B. |
| Superset | `A >= B` | `true` if every element of B is in A. |

### Set Constructors

```pascal
var
  Vowels: set of char;
begin
  Vowels := ['A', 'E', 'I', 'O', 'U', 'a', 'e', 'i', 'o', 'u'];
  if ch in Vowels then
    writeln('vowel');
end;
```

Set constructors support individual values and ranges: `[1, 3, 5..10]`.

## Variant Records

Records may include a variant part, allowing different fields to share the same memory. The variant part is introduced by a `case` tag at the end of the record:

```pascal
type
  TNodeKind = (nkConst, nkVar, nkProc);

  TSymbol = record
    Name: string[63];
    case Kind: TNodeKind of
      nkConst: (ConstValue: integer);
      nkVar:   (Offset: integer; VarType: integer);
      nkProc:  (ParamCount: integer; EntryPoint: integer);
  end;
```

The tag field (`Kind`) is a normal field accessible at runtime. All variant fields overlap in memory starting at the same offset. The record size is determined by the largest variant. With `{$R+}`, accessing a variant field checks the tag value.

Variant records map directly to WASM linear memory — the variants simply share the same byte offsets. No special WASM support is required.

## With Statement

The `with` statement opens a record variable's fields for unqualified access:

```pascal
var
  Sym: TSymbol;
begin
  with Sym do
  begin
    Name := 'count';
    Kind := nkVar;
    Offset := 16;
  end;
end;
```

Multiple record variables may be opened in a single `with`:

```pascal
with Sym, OtherRecord do
  { fields of both are accessible }
```

If field names conflict, the innermost (rightmost) record takes precedence.

## Built-in Functions and Procedures

These functions and procedures are compiler intrinsics, always available without requiring a `uses` clause or import.

### Arithmetic Functions

| Function | Signature | Description |
|---|---|---|
| `abs(x)` | `integer → integer` | Absolute value. (`real → real` in a future phase.) |
| `sqr(x)` | `integer → integer` | Square of `x` (`x * x`). (`real → real` in a future phase.) |

### Ordinal Functions

| Function | Signature | Description |
|---|---|---|
| `ord(x)` | `char → integer` or `boolean → integer` or `enumerated → integer` | Ordinal value. `ord(false) = 0`, `ord(true) = 1`. |
| `chr(x)` | `integer → char` | Character with ordinal value `x`. |
| `succ(x)` | `ordinal → ordinal` | Successor value. |
| `pred(x)` | `ordinal → ordinal` | Predecessor value. |
| `odd(x)` | `integer → boolean` | `true` if `x` is odd. |

### Size and Bit Functions

| Function | Signature | Description |
|---|---|---|
| `sizeof(x)` | `any → integer` | Size in bytes of `x` (a type or variable). |
| `length(s)` | `string → integer` | Current length of string `s`. |
| `lo(x)` | `integer → byte` | Low byte of `x`. |
| `hi(x)` | `integer → byte` | High byte of `x`. |

### String Functions and Procedures

| Function/Procedure | Signature | Description |
|---|---|---|
| `copy(s, i, n)` | `string × integer × integer → string` | Substring of `s` starting at position `i`, length `n`. |
| `pos(sub, s)` | `string × string → integer` | Position of `sub` in `s`, or 0 if not found. |
| `concat(s1, s2, ...)` | `string × ... → string` | Concatenation of strings. Equivalent to `s1 + s2 + ...`. |
| `delete(s, i, n)` | `var string × integer × integer` | Remove `n` characters from `s` starting at position `i`. |
| `insert(src, s, i)` | `string × var string × integer` | Insert `src` into `s` at position `i`. |

### Control Procedures

| Procedure | Signature | Description |
|---|---|---|
| `inc(x)` | `var ordinal` | Increment `x` by 1. |
| `inc(x, n)` | `var ordinal × integer` | Increment `x` by `n`. |
| `dec(x)` | `var ordinal` | Decrement `x` by 1. |
| `dec(x, n)` | `var ordinal × integer` | Decrement `x` by `n`. |
| `exit` | — | Exit the current procedure or function. |
| `halt` | — | Terminate the program with exit code 0. Compiles to WASI `proc_exit(0)`. |
| `halt(n)` | `integer` | Terminate the program with exit code `n`. Compiles to WASI `proc_exit(n)`. |

### Memory Allocation (Phase 5)

| Procedure | Signature | Description |
|---|---|---|
| `New(p)` | `var ^T` | Allocate a new record of type `T` and set `p` to point to it. |
| `Dispose(p)` | `var ^T` | Deallocate the record pointed to by `p`. |

These are not available in Phase 1 (stack-only allocation). They will use a free-list allocator in WASM linear memory.

### Predefined Constants

| Constant | Type | Value |
|---|---|---|
| `true` | `boolean` | 1 |
| `false` | `boolean` | 0 |
| `nil` | pointer | Null pointer (address 0). |
| `maxint` | `integer` | Maximum `integer` value (2147483647). |

## Built-in I/O

`write`, `writeln`, `read`, and `readln` are compiler intrinsics that generate calls to WASI preview 1 `fd_write` and `fd_read` imports. They are not part of a runtime library — the host must provide the `wasi_snapshot_preview1` module (any WASI-compatible runtime such as wasmtime or wasmer does this automatically).

### `write` / `writeln`

```pascal
write(args...);       { write to stdout (fd 1) }
writeln(args...);     { write to stdout with newline }
```

The first argument may optionally be a file handle to direct output to a specific file descriptor:

```pascal
write(stderr, 'Error: ', msg);    { write to stderr (fd 2) }
writeln(stderr, 'line ', lineNo); { write to stderr with newline }
```

**Phase 1 subset:** In the initial release, `write`/`writeln` support integer, character, and string arguments. Boolean and real formatting, and format specifiers (`:width`, `:width:decimals`), are deferred to a later phase.

**Full support (future):** All types including booleans and reals, with standard Pascal format specifiers:

```pascal
writeln(x:10);        { field width 10 }
writeln(r:10:2);      { field width 10, 2 decimal places }
```

### `read` / `readln`

```pascal
read(args...);        { read from stdin (fd 0) }
readln(args...);      { read from stdin, consume rest of line }
read(input, args...); { explicit file handle — same as default }
```

As with `write`/`writeln`, the first argument may optionally be a predefined file handle. In practice, `read`/`readln` only make sense with `input` (fd 0), which is already the default.

**Phase 1 subset:** `read`/`readln` support integer and string arguments. Character and real parsing are deferred.

### Predefined File Handles

| Handle | Type | File Descriptor | Description |
|---|---|---|---|
| `input` | `text` | fd 0 | Standard input (default for `read`/`readln`). |
| `output` | `text` | fd 1 | Standard output (default for `write`/`writeln`). |
| `stderr` | `text` | fd 2 | Standard error. |

These are predefined identifiers, not variables. They can only be used as the first argument to `write`/`writeln`/`read`/`readln`. There are no general-purpose file types — `text` exists solely for these handles.

### Implicit WASI Imports

When a program uses `write`/`writeln`, `read`/`readln`, or `halt`, the compiler emits imports from the `wasi_snapshot_preview1` module. These are the standard WASI preview 1 signatures:

| Import | Signature | Emitted when |
|---|---|---|
| `fd_read` | `(fd: i32, iovs: i32, iovs_len: i32, nread: i32) → errno: i32` | Program uses `read`/`readln` |
| `fd_write` | `(fd: i32, iovs: i32, iovs_len: i32, nwritten: i32) → errno: i32` | Program uses `write`/`writeln` |
| `proc_exit` | `(code: i32) → noreturn` | Program uses `halt` |

Each iovec is an 8-byte struct in linear memory: `{ buf: i32, len: i32 }`. The generated code always passes a single iovec (`iovs_len = 1`).

Programs that do not use any I/O or `halt` have **no implicit WASI imports** — the compiled WASM module is fully self-contained.

Any WASI-compatible runtime (wasmtime, wasmer, wasm3, browser polyfill) provides these imports automatically.

## Runtime Model

### Linear Memory Layout

Compiled programs use this layout in WASM linear memory:

```
[ nil guard | data segment | heap -> ....... <- stack ]
0           4               data_end         SP    memory_top
```

- **Nil guard (bytes 0-3):** Reserved, zeroed. Dereferencing a `nil` pointer reads zeros rather than corrupting data.
- **Data segment:** Global variables, string literals, and typed constants. Laid out by the compiler at compile time starting at address 4.
- **Heap:** Grows upward from end of data segment. Available in Phase 5 (`New`/`Dispose`); unused in Phase 1.
- **Stack:** Grows downward from top of memory.

The initial memory size is controlled by `{$MEMORY}` (default: 1 page = 64 KB). Maximum memory is controlled by `{$MAXMEMORY}` (default: 256 pages = 16 MB).

### Stack

The stack pointer is a mutable WASM global, initialized to the top of memory. Each procedure call subtracts the frame size on entry and adds it back on exit. Local variables, including short strings and records, are allocated on the stack.

### Entry Point

The program's main `begin...end.` block (the statement part following all declarations) is compiled as the WASI `_start` export — a function with no parameters and no return value. This is the program's entry point. WASI-compatible runtimes call `_start` automatically:

```
wasmtime run program.wasm
```

If the program reaches the final `end.` without calling `halt`, execution returns from `_start` normally (implicit exit code 0). Calling `halt(n)` invokes WASI `proc_exit(n)` to terminate with a specific exit code.

### Nested Procedures

Nested procedures that access enclosing scope variables use Dijkstra's display technique. Eight WASM globals (`display[0]` through `display[7]`) hold frame pointers for each nesting level. Accessing an upvalue at any depth is O(1) — two loads. Top-level procedures emit no display code. Maximum nesting depth is 8.

## Compiler Directives

Compiler directives use the same syntax as Free Pascal: `{$DIRECTIVE}` or `{$DIRECTIVE VALUE}`. They appear inside comments and control compiler behavior. The alternative syntax `(*$DIRECTIVE*)` is also accepted.

Directives are either **global** (must appear before the first declaration or statement in a compilation unit) or **local** (may appear anywhere and take effect from the point they appear).

### Syntax

```ebnf
Directive        = '{' '$' DirectiveName [ DirectiveValue ] '}'
                 | '(*' '$' DirectiveName [ DirectiveValue ] '*)' .

DirectiveName    = LETTER { LETTER } .
DirectiveValue   = SwitchValue | Identifier | INTEGER_LITERAL | STRING_LITERAL .
SwitchValue      = '+' | '-' .
```

Switch directives use `+` to enable and `-` to disable. They also accept a long form: `{$DIRECTIVE ON}` and `{$DIRECTIVE OFF}`.

### Global Directives

Global directives must appear before any declarations or statements. They affect the entire compilation unit.

| Directive | Default | Description |
|---|---|---|
| `{$MEMORY n}` | 1 | Initial WASM linear memory size in 64 KB pages. |
| `{$MAXMEMORY n}` | 256 | Maximum WASM linear memory size in 64 KB pages (0 = no limit). |
| `{$STACKSIZE n}` | 65536 | Stack size in bytes, allocated from linear memory. |
| `{$DESCRIPTION 'text'}` | — | Embedded description string in the WASM custom section. |

### Local Directives

Local directives may appear anywhere in the source. They take effect from the point they appear until changed by another directive of the same kind, or until the end of the compilation unit.

| Directive | Short | Default | Description |
|---|---|---|---|
| `{$RANGECHECKS ON/OFF}` | `{$R+/-}` | OFF | Emit runtime range checks for array indexing and subrange assignments. |
| `{$OVERFLOWCHECKS ON/OFF}` | `{$Q+/-}` | OFF | Emit runtime overflow checks for integer arithmetic. |
| `{$ALIGN n}` | — | 1 | Record field alignment in bytes (1, 2, 4, or 8). |
| `{$INCLUDE 'filename'}` | `{$I 'filename'}` | — | Include the contents of `filename` at this point. Resolved by the host before compilation — see below. |
| `{$EXPORT name}` | — | — | Export the next procedure, function, or variable as `name` in the WASM module's export table. |
| `{$IMPORT 'module' name}` | — | — | Declare the next procedure or function as a WASM import from `module` with import name `name`. |
| `{$EXTLITERALS ON/OFF}` | — | OFF | Enable C-style numeric literal prefixes: `0x` (hex), `0o` (octal), `0b` (binary). |

### Examples

```pascal
{$MEMORY 4}           { 4 pages = 256 KB initial memory }
{$MAXMEMORY 64}       { up to 4 MB }
{$STACKSIZE 32768}    { 32 KB stack }

program Example;

{$I 'common.inc'}     { include shared definitions }

{$R+}                 { enable range checks from here }
{$Q+}                 { enable overflow checks from here }

{$ALIGN 4}
type TAligned = record
  A: char;
  B: integer;          { aligned to 4-byte boundary }
end;
{$ALIGN 1}            { restore default }

{$IMPORT 'env' print_int}
procedure PrintInt(x: integer); external;

{$EXPORT main}
procedure Main;
var
  i: integer;
begin
  for i := 1 to 10 do
    PrintInt(i);
end;

begin
  Main;
end.
```

### Include File Resolution

The `{$INCLUDE}` directive is resolved by the **host application**, not by the compiler. Before invoking the compiler, the embedding library (or fpc during bootstrap) scans the source for `{$I}` / `{$INCLUDE}` directives and replaces them with the contents of the referenced files. The compiler receives a single, fully-expanded source stream on stdin.

This design keeps the compiler's I/O interface minimal (three file descriptors, no filesystem access). The Rust, Zig, and C embedding libraries each provide a utility function to perform include expansion. If the host cannot locate an included file, the embedding library reports an error before compilation begins.

During fpc bootstrap, the compiler runs as a native executable and fpc handles `{$I}` natively.

### Interaction with Single-Pass Compilation

All directives are processed in source order during the single pass. Global directives are validated before parsing begins. Local directives modify compiler state immediately — there is no deferred application.

## Compiler Diagnostics

The compiler writes all diagnostics to stderr (fd 2). Every line is prefixed with a tag so the host application can parse output mechanically without relying on free-text heuristics.

### Message Tags

| Tag | Meaning | Format |
|---|---|---|
| `Error:` | Compilation error (fatal) | `Error: line:col: message` |
| `Warning:` | Non-fatal diagnostic | `Warning: line:col: message` |
| `Info:` | Informational | `Info: message` |
| `Debug:` | Verbose debugging output | `Debug: message` |
| `Progress:` | Compilation progress | `Progress: done/total [message]` |

Phase 1 uses at minimum `Error:`. Additional tags may be introduced as the compiler matures.

### Progress Tag

The `Progress:` tag uses a fixed `done/total` format (both integers) so the host can compute a percentage or display a progress bar. An optional human-readable message may follow the ratio:

```
Progress: 0/123
Progress: 20/100 Analyzing...
Progress: 100/100 Done
```

### Error Format

On the first compilation error, the compiler writes a single tagged diagnostic and halts via `proc_exit(1)`. No error recovery or multi-error reporting:

```
Error: 42:10: Undeclared identifier 'foo'
```

## Extensions

These extensions go beyond ISO 7185 and ISO 10206 and are unique to Compact Pascal.

### Standalone Methods

Any data type can have methods associated with it without modifying the type's original declaration. Methods are declared using the `for` keyword to specify the receiver:

```pascal
type TCat = record
  Name: string;
end;

procedure Purr for c: TCat;
begin
  { c is the receiver — a value of type TCat }
end;
```

The receiver appears after the `for` keyword as `name: Type`. It becomes the first implicit (hidden) argument of the method.

#### Receiver Types

There are two types of method receivers:

- **Value receiver** — the receiver is passed by value (copied). Intended for small, immutable types. The method cannot modify the caller's copy.

  ```pascal
  function Area for r: TRect: integer;
  begin
    Area := r.Width * r.Height;
  end;
  ```

- **Pointer receiver** — the receiver is passed as a pointer, giving the method reference semantics. It operates on the original data and can modify internal state. Preferred for large records or when mutation is needed.

  ```pascal
  procedure Rename for c: ^TCat (const NewName: string);
  begin
    c^.Name := NewName;
  end;
  ```

#### Calling Methods

Methods are called using dot notation on the receiver:

```pascal
var
  MyCat: TCat;
begin
  MyCat.Purr;
  MyCat.Rename('Whiskers');
end;
```

When calling a pointer-receiver method on a value, the compiler automatically takes the address. When calling a value-receiver method on a pointer, the compiler automatically dereferences.

### Structured Return Types

Standard Pascal restricts function return types to simple types and pointers. Compact Pascal lifts this restriction: functions may return any type, including arrays and records. This follows the precedent set by C, where functions can return structs by value.

```pascal
type TPoint = record
  X, Y: integer;
end;

function Origin: TPoint;
begin
  Origin.X := 0;
  Origin.Y := 0;
end;

function MakeRow: array[1..5] of integer;
var i: integer;
begin
  for i := 1 to 5 do
    MakeRow[i] := i * 10;
end;
```

The compiler implements this via a hidden pointer parameter: the caller allocates space for the return value in its own stack frame and passes a pointer as a hidden first argument. The callee writes the result through that pointer. This is the same calling convention used by C compilers for struct returns.

### Interfaces

An interface defines a set of method signatures that a concrete type can satisfy. Interfaces use structural typing — there is no explicit inheritance.

#### Declaring Interfaces

An interface is declared with the `interface` keyword. Only procedural field definitions are allowed:

```pascal
type IPet = interface
  Greet: procedure (const HumanName: string);
  Name: function: string;
end;
```

The compiler adds a hidden `Self` field to store a pointer to the concrete data for each interface value.

#### Implementing Interfaces

Interface conformance is declared via an `implement` block that groups all required method implementations for a specific type-interface pair:

```pascal
implement IPet for TCat;

  procedure Greet(const HumanName: string);
  begin
    WriteLn('Meow, ' + HumanName + '! I am ' + Self.Name);
  end;

  function Name: string;
  begin
    Name := Self.Name;
  end;

end;
```

Rules for `implement` blocks:
- The receiver is implicit — individual methods do not use the `for` keyword.
- `Self` refers to the receiver inside the block.
- When the compiler reaches the closing `end;`, it verifies that all methods declared in the interface are implemented with compatible signatures.
- A type may implement multiple interfaces via separate `implement` blocks.

#### Implicit Conversion

After an `implement` block has been parsed, the concrete type can be used wherever the interface type is expected. The compiler silently inserts the conversion:

```pascal
procedure SayHello(Pet: IPet);
begin
  Pet.Greet('Alice');
end;

var
  MyCat: TCat;
begin
  MyCat.Name := 'Felix';
  SayHello(MyCat);  { implicit conversion: TCat -> IPet }
end;
```

The compiler emits code to:
1. Set the `Self` pointer to the address of the concrete value.
2. Fill the procedural fields with pointers to the actual method implementations.

No explicit cast is required.

#### Single-Pass Compilation

The `implement` block is a self-contained declaration unit. Interface satisfaction is verified when the block closes — no lookahead is needed. Implicit conversions from a concrete type to an interface are only valid after the corresponding `implement` block has been parsed. This is a natural declare-before-use rule consistent with Pascal's design.

#### Representation

An interface value is stored as an inline record containing:
- A `Self` pointer to the concrete data.
- One procedural field per interface method, filled with pointers to the concrete implementations.

This is an inline vtable. A future optimization could use shared interface tables (itables) per (concrete type, interface type) pair to reduce memory when many interface values share the same concrete type.

#### Future Extensions

- **Type assertions** — test at runtime whether an interface value holds a specific concrete type.
- **Type switches** — branch on the concrete type behind an interface value.

---

## Appendix A: Formal Grammar

The grammar is specified in Extended Backus-Naur Form (EBNF). The notation follows ISO 14977: `{ ... }` means zero or more repetitions, `[ ... ]` means optional, `( ... )` groups alternatives, `|` separates alternatives, and `=` defines a production. Terminal symbols are quoted. Comments are enclosed in `(* ... *)`.

### Program Structure

```ebnf
Program          = 'program' Identifier ';' Block '.' .

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
                 (* A ConstExpr is syntactically identical to Expression but
                    is evaluated at compile time. It may contain integer,
                    string, char, and boolean literals; references to
                    previously declared constants; arithmetic operators
                    (+, -, *, div, mod); boolean operators (not, and, or);
                    comparisons; string concatenation (+); and the standard
                    functions ord, chr, odd, abs, succ, pred, lo, hi, sizeof.
                    Example:
                      const hello = 'Hello'; world = 'World';
                            message = hello + ' ' + world; *)

TypeDeclPart     = 'type' TypeDef { TypeDef } .
TypeDef          = Identifier '=' Type ';' .

VarDeclPart      = 'var' VarDecl { VarDecl } .
VarDecl          = IdentList ':' Type [ '=' ConstExpr ] ';' .
                 (* Initialized variables: var x: integer = 5.
                    Only valid when IdentList has a single identifier.
                    Global initialized variables are placed in the data
                    segment. Local initialized variables reinitialize on
                    each scope entry. This is a Delphi/FPC extension not
                    present in Turbo Pascal. *)
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
                    see Structured Return Types under Extensions. *)
```

**Forward declarations.** A procedure or function may be declared `forward` to allow mutual recursion. The body must appear later in the same declaration section, and it must **repeat the full header** — parameter list, parameter types, and (for functions) the return type:

```pascal
procedure PrintResult(x: integer); forward;

function Compute(a, b: integer): integer;
begin
  Compute := a * b + 1
end;

procedure PrintResult(x: integer);
begin
  writeln(x)
end;
```

This differs from Turbo Pascal, where the forward body omits the parameter list. Compact Pascal follows the IP Pascal convention of repeating the full header, which keeps the parameter list visible at the definition site and avoids the need to look up the forward declaration to understand the body's signature.

```ebnf
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
                   | WithStmt
                   | BreakStmt
                   | ContinueStmt ] .

BreakStmt        = 'break' .
ContinueStmt     = 'continue' .

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
Expression       = OrElseExpr .
OrElseExpr       = AndThenExpr { 'or' 'else' AndThenExpr } .
AndThenExpr      = Comparison { 'and' 'then' Comparison } .
Comparison       = SimpleExpr [ RelOp SimpleExpr ] .
RelOp            = '=' | '<>' | '<' | '>' | '<=' | '>=' | 'in' .

SimpleExpr       = [ '+' | '-' ] Term { AddOp Term } .
AddOp            = '+' | '-' | 'or' .

Term             = Factor { MulOp Factor } .
MulOp            = '*' | 'div' | 'mod' | 'and' | 'shl' | 'shr' .

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
and       array     begin     break     case
const     continue  div       do        downto
else      end       external  for       forward
function  if        implement in        interface
mod       nil       not       of        or
procedure program   record    repeat    set
string    then      to        type      until
var       while     with
```

The language is **case-insensitive** — reserved words and identifiers are matched without regard to case.

`self`, `true`, `false`, `input`, `output`, `stderr`, `maxint` are built-in identifiers, not reserved words. Compiler intrinsics (`write`, `writeln`, `read`, `readln`, `abs`, `ord`, `chr`, `odd`, `succ`, `pred`, `sqr`, `length`, `sizeof`, `lo`, `hi`, `inc`, `dec`, `exit`, `halt`, `copy`, `pos`, `concat`, `delete`, `insert`, `new`, `dispose`) are also built-in identifiers. WASM import/export names in `{$IMPORT}` and `{$EXPORT}` directives are case-sensitive.

### Operator Precedence (Highest to Lowest)

| Precedence | Operators | Associativity |
|---|---|---|
| 1 (highest) | `not`, unary `+`/`-` | Right |
| 2 | `*`, `div`, `mod`, `and`, `shl`, `shr` | Left |
| 3 | `+`, `-`, `or` | Left |
| 4 | `=`, `<>`, `<`, `>`, `<=`, `>=`, `in` | None |
| 5 | `and then` | Left |
| 6 (lowest) | `or else` | Left |

> **Deviation from ISO 10206.** ISO Extended Pascal places `and then` with the multiplying-operators and `or else` with the adding-operators. Compact Pascal gives them their own levels below comparisons, matching the precedence of C's `&&` and `||`. This allows `x < 2 * y and then z - 1 < w` to parse as `(x < 2 * y) and then (z - 1 < w)` without parentheses. The eager operators `and` and `or` retain their standard Pascal precedence.

### Comments and Compiler Directives

```ebnf
Comment          = '{' Commentary '}'
                 | '(*' Commentary '*)'
                 | '//' { CHARACTER } EOL .
Commentary       = { CHARACTER - '}' - '*)' } .

Directive        = '{' '$' DirectiveName [ DirectiveValue ] '}'
                 | '(*' '$' DirectiveName [ DirectiveValue ] '*)' .

DirectiveName    = LETTER { LETTER } .
DirectiveValue   = SwitchValue | Identifier | INTEGER_LITERAL | STRING_LITERAL .
SwitchValue      = '+' | '-' .
```

A comment begins with `{` or `(*` and ends at the first matching `}` or `*)`. The commentary within a brace or parenthesis-star comment must not contain the closing delimiter. Whether comments nest is undefined — an implementation may support nesting or may not. Programs that depend on nested comments are not portable. Comments may appear anywhere whitespace is permitted. Line comments (`//`) extend to the end of the line. A `$` immediately after the opening delimiter marks a compiler directive. Switch directives use `+`/`-` (e.g., `{$R+}`). See [Compiler Directives](#compiler-directives) for the full directive list.

If the first byte of the source is `#`, the remainder of the first line is ignored. This permits Unix-style interpreter directives (e.g., `#!/usr/bin/env cpas`).

---

Copyright 2026 Jon Mayo. This document is licensed under the [Creative Commons Attribution 4.0 International License (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
