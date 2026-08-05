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

**Version 26.08.0** (CalVer: YY.MM.minor)

Compact Pascal is a new language in the Pascal family, rooted in ISO 7185 (Standard Pascal) and ISO 10206 (Extended Pascal), with modifications and additional extensions described in this document.

This is a living document. The version number follows [Calendar Versioning](https://calver.org/) using the YY.MM.minor scheme. The minor version increments for changes within the same month.

## Versioning and Stability

**Compact Pascal is pre-1.0 and the language is not yet stable.** The 26.x series is a beta. Anything in this document may change, including syntax and semantics of features that already work, and changes may arrive without a deprecation period. Pin an exact version if you depend on current behavior.

Version 1.0 will be the first stable release. From 1.0 onward the following are covered by a compatibility promise for the life of the 1.x series:

- **Language syntax and semantics.** A program that compiles under 1.x continues to compile, and continues to mean the same thing, under every later 1.x. See [Defined and Undefined Behavior](#defined-and-undefined-behavior) for what "the same thing" covers: behavior this document leaves undefined may change between any two releases.
- **The diagnostic format.** The tags and their layouts, so host tooling that parses compiler output keeps working. See [Compiler Diagnostics](#compiler-diagnostics).
- **The command-line interface.** Existing flags keep their meaning. New flags may be added.
- **The module contract.** The `_start` export, the WASI imports the compiler emits and the conditions under which it emits them, and the linear memory layout that `{$MEMORY}`, `{$MAXMEMORY}`, and `{$STACKSIZE}` control.

These are explicitly **not** covered, and may change in any release including a patch:

- **The exact bytes emitted.** Two compiler versions given identical source may produce different modules. Only the behavior of the compiled program is promised, not its encoding, so byte-for-byte reproducibility holds within one compiler version, not across versions.
- **Internal helper functions.** Their names, indices, and presence are an implementation detail, even though they appear in the module's function table.
- **Performance,** of the compiler or of compiled code.
- **Anything this document marks as a future extension or as deferred.**

Breaking changes to the covered surface require a major version. Where a change is known in advance, it is announced at least one release before it lands, and the outgoing behavior keeps working with a `Warning:` diagnostic during that release.

The embedding libraries version independently of the language and carry their own stability statements. A stable language does not imply a stable embedding API.

## Source Encoding

Source files must be encoded in **UTF-8**. The compiler treats source as a sequence of bytes; only ASCII-range bytes (0x00–0x7F) are significant to the lexer. Bytes 0x80–0xFF may appear in string literals and comments and are preserved verbatim. The compiler does not validate, decode, or normalize UTF-8 sequences.

This means `char` is a **byte**, not a Unicode codepoint. `length('café')` returns the byte length (5 in UTF-8, not 4), and `s[i]` indexes by byte. Programs that work with multi-byte characters must account for this, just as in C or Go's `[]byte`. Full Unicode-aware string operations are a library concern, not a language primitive.

A leading UTF-8 byte order mark (`EF BB BF`) is accepted and skipped. Many Windows editors write one by default, so rejecting it would turn an ordinary save into an error on line 1. A BOM anywhere other than the first three bytes is not special and is an error. The mark may be followed by a `#!` line; both are consumed before tokenizing.

Line endings may be LF, CRLF, or CR. All three are accepted, so a file edited on Windows compiles unchanged.

Legacy Turbo Pascal source files encoded in CP437 or other 8-bit code pages must be converted to UTF-8 before compilation. This is a one-time conversion performed by standard tools or libraries (e.g., `iconv`, Rust's `encoding_rs` crate, or a simple 128-entry lookup table).

## Core Language

The core language is a minimal subset of Pascal sufficient for systems programming and compiler construction. Advanced extensions (modules, overloads, dynamic arrays, exceptions, OOP) are not part of the core and may be added in later phases.

Compact Pascal is **case-insensitive** — identifiers, keywords, and type names are matched without regard to case, as in standard Pascal. The sole exception is WASM import/export names in `{$IMPORT}` and `{$EXPORT}` directives, which are case-sensitive because they refer to external WASM symbols.

### Types

- `integer` — signed 32-bit integer (mapped to WASM `i32`).
- `byte` — nominally an unsigned 8-bit integer (0..255).
- `shortint` — nominally a signed 8-bit integer (-128..127).
- `word` — nominally an unsigned 16-bit integer (0..65535).
- `longint` — signed 32-bit integer.

  The four names above are currently aliases for `integer`: all are 32-bit, `sizeof` reports 4, and the nominal ranges are not enforced. See [Types and Conversion](#types-and-conversion).
- `boolean` — `true` or `false`.
- `char` — single byte (0..255). Represents one byte of text, not a Unicode codepoint. See [Source Encoding](#source-encoding).
- `string` — TP-style short string (length byte + up to 255 characters). `string[n]` for a maximum length of `n`. See [String Representation](#string-representation).
- `real` — floating point (mapped to WASM `f64`). *(Deferred from Phase 1. The scanner recognizes real literals but the compiler rejects them with an error.)*
- `array` — fixed-size arrays: `array[lo..hi] of T`.
- `record` — composite types, including variant records with a `case` tag. See [Variant Records](#variant-records).
- `set` — bit-set types: `set of T` where T is an ordinal type with up to 256 values. See [Set Types](#set-types).
- Pointers — `^T` typed pointers, with `@x` for address-of, `p^` for dereference, and `nil`. No heap yet: a pointer must target storage that already exists. See [Pointers](#pointers).
- Enumerated types — mapped to WASM `i32`. Values are assigned sequentially from 0.
- Subranges — a restricted range of an ordinal type. The base type can be inferred from the constants (`1..12` is `integer`, `'A'..'Z'` is `char`, `Mon..Fri` is the enumerated type containing `Mon`) or specified explicitly using the GPC typed subrange syntax: `Day(Mon..Fri)`. Mapped to WASM `i32`. Range bounds are checked at assignment only when `{$R+}` is enabled.
- Procedural types — `procedure (params)` and `function (params): T`.

### Expressions

- Arithmetic: `+`, `-`, `*`, `div`, `mod`.
- Bitwise shift: `shl` (shift left), `shr` (shift right). Both operate on `integer` and `longint`. `x shl n` shifts `x` left by `n` bits; `x shr n` shifts right. They have the same precedence as `*`, `div`, and `mod`.
- Comparison: `=`, `<>`, `<`, `>`, `<=`, `>=`.
- Logical: `and`, `or`, `not`.
- Short-circuit logical: `and then`, `or else` (as in ISO 10206).
- Set operations: `+` (union), `*` (intersection), `-` (difference), `in` (membership).
- String concatenation: `+`.
- Pointer dereference: `p^`. Address-of: `@x`. Pointer comparison: `=`, `<>`.
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

- **A `text` type only.** `file of T` and untyped `file` are omitted; text files are sequential lines. See [Text Files](#text-files).
- **Built-in I/O is a compiler intrinsic.** `write`, `writeln`, `read`, `readln` are supported but compile to WASI preview 1 `fd_write`/`fd_read` calls rather than being part of the runtime. Any WASI-compatible host provides these automatically. See [Built-in I/O](#built-in-io).
- **Dynamic allocation.** `New` and `Dispose` over a first-fit free list. No garbage collection, no compaction. See [The Heap](#the-heap).
- **Short-circuit evaluation.** `and then` and `or else` operators from ISO 10206 are supported. See [Short-Circuit Evaluation](#short-circuit-evaluation).
- **TP-style short strings.** Strings use the Turbo Pascal length-byte representation, not ISO 7185 packed arrays of char. See [String Representation](#string-representation).
- **Type casts.** Turbo Pascal-style type casts (`integer(ch)`) are supported.
- **32-bit `integer`.** `integer` is 32-bit (WASM `i32`), unlike TP/BP where `integer` is 16-bit. Programs that do not overflow 16-bit values are unaffected.
- **`break` and `continue`.** Turbo Pascal extensions not in ISO 7185. `break` exits the innermost loop; `continue` skips to its next iteration. See the [Statements](#statements) summary.
- **`case` with `else` and silent fallthrough.** ISO 7185 treats an unmatched `case` selector as an error. Compact Pascal follows Turbo Pascal: the `else` clause handles unmatched values (extension), and if no branch matches and there is no `else` clause, execution silently continues after `end`. See [Case Statement](#case-statement).
- **`shl` and `shr`.** Bitwise shift operators not in ISO 7185. They appear at the `MulOp` level (same precedence as `*`, `div`, `mod`). See [Expressions](#expressions) and the [Operator Precedence](#operator-precedence) table.

## Constants

Compact Pascal has two forms of constant declaration.

### Untyped Constants

```pascal
const
  max = 100;
  greeting = 'Hello';
  limit = max * 2;
```

The type is inferred from the right-hand side. The expression is evaluated at compile time (see `ConstExpr` in Appendix A for the allowed operators and functions).

### Typed Constants

A typed constant names a storage location with a fixed type and an initial value:

```pascal
const
  pi_int: integer = 314;
  ch: char = 'Q';
  flag: boolean = true;
```

Scalar typed constants of ordinal type hold their value like an untyped constant. Structured typed constants — arrays, strings, records, and sets — are placed in the data segment at program startup.

**Array initializers** use parenthesized element lists. The number of elements must match the declared length exactly:

```pascal
const
  primes: array[1..5] of integer = (2, 3, 5, 7, 11);
  matrix: array[1..2, 1..3] of integer = ((1, 2, 3), (4, 5, 6));
```

Multi-dimensional arrays use nested initializers, one level of parentheses per dimension.

**String-literal shortcut.** For `array[lo..hi] of char`, a string literal may be used in place of a parenthesized list. Its length must equal `hi - lo + 1`:

```pascal
const
  greet: array[0..4] of char = 'hello';
```

**String-typed constants** accept a string literal, padded to the declared capacity:

```pascal
const
  prompt: string[10] = 'ready>';
```

**Record initializers** use parenthesized `field: value` pairs separated by semicolons. Fields must appear in declaration order and every field must be specified:

```pascal
type
  TPoint = record x, y: integer end;
const
  origin: TPoint = (x: 0; y: 0);
  p1: TPoint = (x: 3; y: 4);
```

Nested records, arrays, strings, and sets may appear as field values using the corresponding initializer syntax. Variant records are not supported as typed constants.

**Set initializers** use the standard set-literal syntax. Elements must be compile-time constants (integer/char/enum literals, previously declared constants) and may include ranges:

```pascal
type
  DigitSet = set of integer;
  CharSet  = set of char;
const
  primes: DigitSet = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29];
  digits: CharSet  = ['0'..'9'];
```

Typed constants are writable under Turbo Pascal's classic semantics (the compiler does not enforce immutability). Programs should treat them as constants and not rely on mutating them.

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

The embedding libraries provide helper functions to copy between host strings (Rust `&str`/`String`, C `const char *`) and the Pascal string representation in the WASM memory space.

A richer dynamically-allocated string type (pointer + length, no 255-character limit) is planned for a later phase, now that a heap exists to hold one.

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
'café'            { 5 bytes in UTF-8 }
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
'caf' + #u00E9    { string 'café' — rune encoded as UTF-8, 5 bytes }
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

Planned alongside Phase 6b (richer string type). Phase 1 has no `rune` type.

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
  CharSet  = set of char;               { 256 bits, 32 bytes }
  SmallSet = set of 0..31;              { packed into a 4-byte i32 }
  Digits   = set of 0..9;               { packed into a 4-byte i32 }
  Colors   = set of (Red, Green, Blue); { packed into a 4-byte i32 }
  Lower    = set of 'a'..'z';           { 32 bytes (high ordinal) }
type
  Day      = (Sun, Mon, Tue, Wed, Thu, Fri, Sat);
  Weekday  = set of Day(Mon..Fri);      { named-subrange form }
  Workday  = set of Mon..Fri;           { subrange-literal form }
```

### Representation

Sets are stored as bit arrays. Size is binary:

| High ordinal | Storage |
|---|---|
| `arrHi < 32` | 4 bytes, packed into an `i32` |
| `arrHi >= 32` | 32 bytes (256 bits) in linear memory |

Bit N is set iff the value with ordinal N is a member of the set. The bitmap is anchored at ordinal 0 regardless of the subrange low bound, so `set of 100..127` reserves the same 32 bytes as `set of char` and shares the same membership codegen. The low bound is still recorded on the type descriptor for future range-check diagnostics.

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

The tag field (`Kind`) is a normal field accessible at runtime. The tag field name is optional — `case TypeIdentifier of` is legal when you don't need to read the tag at runtime; omitting the name makes the variant anonymous and inaccessible as a field. All variant fields overlap in memory starting at the same offset. The record size is determined by the largest variant. With `{$R+}`, accessing a variant field checks the tag value.

Variant records map directly to WASM linear memory — the variants simply share the same byte offsets. No special WASM support is required.

## Text Files

A `text` variable is a file of lines. Filesystem access is opt-in: a program must say `{$FILES ON}` before its `program` header, which adds `path_open` and `fd_close` to the module's imports so a host can see the request without reading the source.

```pascal
{$FILES ON}
program Copy;
var
  f: text;
  line: string;
begin
  assign(f, 'out.txt');
  rewrite(f);
  writeln(f, 'first');
  writeln(f, 'count ', 42);
  close(f);

  assign(f, 'out.txt');
  reset(f);
  while not eof(f) do begin
    readln(f, line);
    writeln(line);
  end;
  close(f);
end.
```

| Operation | Meaning |
|---|---|
| `Assign(f, name)` | Record the file name. Does not open anything. |
| `Reset(f)` | Open for reading, from the start. |
| `Rewrite(f)` | Create or truncate, open for writing. |
| `Close(f)` | Flush and close. Closing an unopened file is harmless. |
| `Write(f, ...)`, `WriteLn(f, ...)` | Append strings, characters, and integers. |
| `ReadLn(f, s)` | Read the next line into a string. |
| `Eof(f)` | True once a read has run off the end. |
| `IOResult` | The last error, cleared by reading it. |

`Assign` separates naming from opening so a program can reopen the same file without repeating the name, and so a failed `Reset` leaves something to report about.

### Paths

A name is resolved relative to a directory the host preopens, and nothing outside it is reachable. With `wasmtime` that is `--dir=.`; a program run without it fails at `Reset` rather than at compile time, because whether a directory was granted is not knowable when the module is built.

The path is passed to the host as written. A host is expected to reject `..` and absolute paths; this language does not check them, because the sandbox boundary belongs to whoever granted the directory.

### Errors

`{$I+}`, the default, traps at the point an operation fails. That is the right behavior for a program that never checks, which is most of them: the alternative is carrying on with a file it does not have.

`{$I-}` records the error instead and lets the program continue. `IOResult` returns it and **clears it**, so reading twice gives zero the second time. This is Turbo Pascal's contract. Check it immediately, or store it:

```pascal
{$I-}
  reset(f);
{$I+}
  if IOResult <> 0 then
    writeln('cannot open the file');
```

The value is the host's WASI errno, not a Pascal error code. Compare it against zero rather than against a number; the numbering is the host's and this document does not fix it.

### What text files do not do yet

- **`ReadLn` reads into a string only.** Reading a number from a file means reading the line and parsing it. The console `ReadLn` accepts integers because it scans standard input directly, and the two paths share no code.
- **No `Read(f, ...)` without the line break**, no `Append`, no `SeekEof`, and no `file of T`. Text is sequential; there is no `Seek`.
- **Concatenation in a file write is rejected.** `writeln(f, a + b)` is a compile error naming the limitation; assign it to a string variable first. The concatenation machinery targets the console path's buffers.
- **A line longer than the destination string is truncated**, and the rest of that line is discarded rather than being seen as a second line.
- **The number of open files is whatever the host allows.** There is no table and no limit here.

### Hazards

These are consequences of the design rather than gaps in it, and each one costs data rather than merely being surprising.

- **A file that is not closed loses whatever is still buffered.** Nothing flushes at program exit: the state lives in the variable, and a variable that has gone out of scope cannot be found again. `Close` every file you `Rewrite`.
- **`Assign` to a file that is already open abandons the descriptor.** It does not close it first. Close before reassigning.
- **Reading a file open for writing yields nothing**, and writing to one open for reading does nothing. Both are reported as if the file were at its end rather than as an error, because a byte read has no error channel. Neither corrupts the other direction's buffer.
- **`Reset` on a file that was never assigned is undefined.** The name is read from the control block, and an unassigned local holds whatever the stack last had there. In practice it fails and sets `IOResult`, but it may open a file whose name is stack debris. Always `Assign` first.
- **`Read(f, c)` returns `chr(0)` at end of file**, which is indistinguishable from a NUL byte in the file. Use `Eof(f)` to tell them apart.

## Pointers

A pointer type is written `^T`, where `T` is the name of a type. A pointer holds a byte address in linear memory and occupies four bytes, the same as an `integer`.

```pascal
type
  PInt = ^integer;
  TRec = record a, b: integer end;
  PRec = ^TRec;
var
  i: integer;
  r: TRec;
  p: PInt;
  q: PRec;
begin
  p := @i;          { address of a variable }
  p^ := 7;          { assign through the pointer }
  writeln(p^);
  q := @r;
  q^.b := 99;       { selectors chain after a dereference }
end.
```

`@x` yields the address of `x`. The operand must be addressable: a variable, a field of an addressable record, an element of an addressable array, or a dereference. A scalar value parameter lives in a WASM local rather than in memory and has no address, so `@` on one is a compile error.

`p^` dereferences. It may be followed by further selectors, so `q^.b`, `q^.items[3]`, and `p^^` all parse as expected, and a dereference may appear on the left of an assignment.

`nil` is the pointer that points at nothing. It is address zero, which the [nil guard](#linear-memory-layout) reserves. `nil` is assignment-compatible with every pointer type.

Pointers compare with `=` and `<>` only. Ordering operators are a compile error: two pointers into different objects have no meaningful order, and the case where an order would be defined, two pointers into the same array, is better written on the indices.

### Forward References

A pointer type may name a type that has not been declared yet, provided the name is declared later in the **same** type declaration block:

```pascal
type
  PNode = ^TNode;       { TNode does not exist yet }
  TNode = record
    value: integer;
    next: PNode;
  end;
```

This is the language's only exception to declare-before-use, and it exists because without it a linked node type cannot be written at all: the record needs the pointer type and the pointer type needs the record. A name that never appears in the block is an error, reported at the end of the block with the line the reference was made on.

### What Pointers Do Not Do Yet

Pointer arithmetic does not exist and is not planned. A pointer is aimed at storage by `@x` or by [`New`](#memory-allocation), and nothing else produces one.

The compiler checks that a pointer is not assigned to a non-pointer and that a non-pointer is not assigned to a pointer. It does not yet check that the *targets* agree, so assigning a `^integer` to a `^TRec` compiles. Treat that as a gap to be closed, not as permission.

`with p^ do` is not accepted; the `with` statement takes a record variable, not a dereference. Write `p^.field` instead. This is a compile error, not a silent miscompile.

### Lifetime

A pointer does not keep its target alive. Taking the address of a local variable and using it after that variable's procedure has returned reads whatever the stack holds now. The language does not detect this. It is the same rule that already applies to `var` parameters and to interface values: the programmer owns the lifetime.

Under `{$S+}` a dereference of `nil` traps at the point of the dereference. A dereference of a stale-but-nonzero pointer does not, because nothing distinguishes it from a live one.

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
| `str(x, s)` | `integer × var string` | Convert integer `x` to its decimal string representation and store in `s`. |

### I/O Functions

| Function | Signature | Description |
|---|---|---|
| `eof` | `→ boolean` | Returns `true` when the last `read` encountered end-of-file, `false` otherwise. Reads from standard input (fd 0). This is a **post-read flag**: `eof` becomes `true` after a `read` hits EOF, not before. This differs from ISO 7185, where `eof` tests whether the *next* read would fail (lookahead). |

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

### Memory Procedures

| Procedure | Signature | Description |
|---|---|---|
| `fillchar(var x; count, value: integer)` | `var any × integer × integer` | Fill `count` bytes starting at `x` with the byte `value`. Used to zero-initialize records and arrays. |

### Memory Allocation

| Procedure | Signature | Description |
|---|---|---|
| `New(p)` | `var ^T` | Allocate a block big enough for a `T` and set `p` to point at it. |
| `Dispose(p)` | `var ^T` | Release the block `p` points at and set `p` to `nil`. |

The size comes from the pointer's target type, not from an argument, so it cannot be given wrongly. The argument must be a pointer *variable*: a value parameter has no address to write back to.

`Dispose` sets the pointer to `nil`. This is a deliberate departure — standard Pascal leaves it dangling and says nothing about using it afterwards. Clearing it costs one store and turns both a use after `Dispose` and a double `Dispose` into a trap under `{$S+}`, instead of a read of memory that now belongs to something else. Other pointers to the same block are *not* cleared and remain dangling; nothing can find them.

See [The Heap](#the-heap) for what the allocator does and does not guarantee.

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

**Phase 1 subset:** `read`/`readln` support integer and string arguments. Reading into a `char` variable (`read(ch)` where `ch: char`) and real parsing are deferred — `char` is not accepted as an argument type in Phase 1 even though `char` is otherwise available as a type alias for `byte`.

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

> **Note:** The compiler binary itself also imports `args_sizes_get` and `args_get`, which it uses to read command-line flags such as `-dump`, `-v`, `-debug`, `-progress`, `-O0`, `-O1`, `-dSYMBOL`, `-I`, and the check switches `-R+`/`-R-` and `-S+`/`-S-`. The check switches set the state a source file starts with; a directive in the source still overrides from the point it appears. It does not take a source file path: the source always arrives on stdin, and any argument that is not a recognized flag is rejected with `Error: unknown option: <arg>`. These imports appear in the compiler's own WASM module but are not emitted by the compiler for compiled programs.

Each iovec is an 8-byte struct in linear memory: `{ buf: i32, len: i32 }`. The generated code always passes a single iovec (`iovs_len = 1`).

Every compiled module declares the five core WASI imports whether or not it uses them: they are registered before parsing so that helper function indices are stable in a single pass, and an import list is positional, so an unused entry cannot simply be dropped. A program that does no I/O still imports `fd_write`, `fd_read`, `proc_exit`, `args_sizes_get`, and `args_get`, and never calls them. Earlier versions of this document claimed such a program had no imports; that was never true.

Filesystem access is the exception, because it is opt-in: `path_open` and `fd_close` appear only when a program asks for them with `{$FILES ON}`. A host can therefore tell from the import list alone whether a module wants to touch files.

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
- **Heap:** Grows upward from the end of the data segment. See [The Heap](#the-heap).
- **Stack:** Grows downward from top of memory.

The initial memory size is controlled by `{$MEMORY}` (default: 1 page = 64 KB). Maximum memory is controlled by `{$MAXMEMORY}` (default: 256 pages = 16 MB).

**The heap and the stack share one boundary**, held in a mutable WASM global. It starts at the end of the data segment and rises as the heap grows. Both guards read it: `New` refuses to carve a block that would cross the stack pointer, and every procedure prologue refuses to reserve a frame that would cross the heap. Growth from either side is caught by the check on the other.

### The Heap

`New` carves blocks from the space between the data segment and the stack. Each block carries an 8-byte header, so a block costs its payload rounded up to 8 bytes, plus 8.

Free blocks are held on a single list and reused first-fit. What the allocator does **not** do is as important as what it does:

- **No splitting.** A free block big enough for a smaller request is handed over whole. The remainder is not recovered until that block is freed again.
- **No coalescing.** Two adjacent free blocks stay two blocks. A large request will not be satisfied by several small neighbours.
- **No return to the operating system.** Freeing the most recently allocated block does not lower the heap boundary.
- **No garbage collection**, and none is planned. Every `New` needs a matching `Dispose`.

The practical consequence: **a program that allocates and frees the same shapes reuses its memory exactly.** That covers lists, trees, and pools, which is what a heap is usually for here. A program that mixes many sizes will fragment, and no amount of freeing will fix it. That is the programmer's problem, and it is stated here rather than hidden behind an allocator that would cost more than this language wants to spend.

**Running out is a trap, not a `nil`.** `New` does not fail softly. If the block would cross the stack pointer the program traps, in the same way an out-of-range index traps under `{$R+}`. A program that wants to survive exhaustion must bound its own allocation; there is no way to ask how much is left.

### Stack

The stack pointer is a mutable WASM global, initialized to the top of memory. Each procedure call subtracts the frame size on entry and records the resulting frame base. On exit the stack pointer is restored from that recorded base rather than by adding the frame size back to its current value. The difference matters when something inside the body moves the stack pointer without moving it back: restoring from the base contains the damage to that one call instead of leaving the stack pointer wrong for the remainder of the program. Local variables, including short strings and records, are allocated on the stack.

Under `{$S+}` the epilogue also compares the stack pointer against the recorded base and traps on a mismatch, so an unbalanced allocation is reported at the function that caused it.

**Frame size is fixed before the body is compiled.** The compiler is single-pass: it emits the prologue that reserves the frame, with the size as an immediate operand, before it has read a single statement of the body. Nothing later in the body can enlarge the frame. Two consequences follow, and both are properties of the language as specified, not passing implementation details:

- A construct needing caller-allocated temporaries whose count is not known from the declarations alone cannot be given frame storage. A function returning a structured type is the case that matters, and it is supported: the buffer is taken from the stack below the frame rather than from the frame itself, and released at the end of the statement. See [Structured Return Types](#structured-return-types).
**Stack overflow is detected.** Every prologue compares the stack pointer against a lower bound before reserving the frame, and traps if the new frame would cross it. The bound is the end of the data segment, so a program that recurses too deeply terminates at the moment of overflow instead of walking the stack pointer down through the heap and the data segment and corrupting whatever it passes. The check is six instructions on the path that does not trap, and measured 0.93% of the compiler's own code size. It is on by default. It can be turned off per-region with `{$S-}` and back on with `{$S+}`; with checks off the old undefined behavior returns, and a deep enough recursion silently corrupts memory.

The comparison happens before the subtraction, not after, so a single frame large enough to carry the stack pointer past zero is caught rather than wrapping around to a large unsigned address that compares as valid.

### Entry Point

The program's main `begin...end.` block (the statement part following all declarations) is compiled as the WASI `_start` export — a function with no parameters and no return value. This is the program's entry point. WASI-compatible runtimes call `_start` automatically:

```
wasmtime run program.wasm
```

If the program reaches the final `end.` without calling `halt`, execution returns from `_start` normally (implicit exit code 0). Calling `halt(n)` invokes WASI `proc_exit(n)` to terminate with a specific exit code.

### Nested Procedures

Nested procedures that access enclosing scope variables use Dijkstra's display technique. Eight WASM globals (`display[0]` through `display[7]`) hold frame pointers for each nesting level. Accessing an upvalue at any depth is O(1) — two loads. Top-level procedures emit no display code. Maximum nesting depth is 8.

## Defined and Undefined Behavior

Every rule below was verified against the compiler rather than inferred from the
implementation's intent. Where the compiler does not currently do what this
section says it should, that is called out explicitly.

### Evaluation Order

Binary operands are evaluated **left to right**. In `F + G`, `F` runs first.
Argument lists are likewise evaluated left to right. Programs may rely on this.

`and then` and `or else` short-circuit and are the only operators that may skip
evaluating an operand. Plain `and` and `or` always evaluate both sides, as in
ISO 7185.

### Integer Arithmetic

- **Overflow wraps** on two's complement, silently, by default. `maxint + 1` is
  `-2147483648`. With `{$Q+}` an overflowing `+`, `-`, or `*` traps instead.
- **Division by zero traps**, always, regardless of directive settings. `div`
  and `mod` both trap on a zero divisor. This is a WASM trap, not a catchable
  Pascal error, and terminates the program.
- **`div` truncates toward zero.** `7 div 2 = 3`, `-7 div 2 = -3`.
- **`mod` takes the sign of the dividend.** `7 mod 2 = 1`, `-7 mod 2 = -1`,
  `7 mod -2 = 1`. This is C's `%`, not the always-non-negative modulus of ISO
  7185, where `mod` with a negative left operand is an error.

### Initialization

- **Global variables are zero.** The data segment is zeroed, so an integer
  global reads 0, a boolean reads `false`, and a string reads as empty before
  any assignment.
- **Local variables are arbitrary.** Locals live in the stack frame, which is
  not cleared on entry. A local holds whatever the previous call at that depth
  left behind, which is reproducible but meaningless. Reading a local before
  assigning it is a bug the language does not detect.
- **An unassigned function result is zero.** If a function returns without
  assigning its result, the caller receives 0, `false`, or an empty string
  rather than arbitrary data. This is a consequence of WASM locals being
  zero-initialized and may be relied upon, though assigning the result on every
  path is better style.

### Types and Conversion

- `char` converts to `integer` implicitly in an assignment or expression, and
  `boolean` converts to `integer` as 0 or 1. Conversion in the other direction
  requires an explicit cast: `char(65)`, `boolean(1)`.
- `chr(n)` **truncates to the low byte**. `chr(300)` is `chr(44)`. It does not
  trap and is not checked under `{$R+}`.
- **`byte`, `word`, `shortint`, and `longint` are aliases for `integer`.** They
  are 32-bit, `sizeof` returns 4 for each, and assigning out of the nominal
  range neither truncates nor errors: `b: byte; b := 300` leaves `b` as 300,
  even under `{$R+}`. The names document intent and aid porting; they do not
  currently constrain values. See [Types](#types), which describes the nominal
  ranges those names imply.

### Scope and Aliasing

- **An inner declaration shadows an outer one** of the same name for the rest of
  the inner scope. Shadowing is legal and silent.
- **`var` parameters may alias each other and may alias globals.** The language
  does not detect it. Assignments through aliased parameters take effect in
  order, so `Bump(g, g)` with a body of `a := a + 1; b := b + 10` leaves `g` at
  11, not 1 or 10. Code that must not alias should say so in its documentation.

### Strings

- **Assignment truncates silently.** Assigning a longer string to `string[n]`
  keeps the first `n` bytes and sets the length accordingly. No error, no
  diagnostic, at any directive setting.
- **Comparison is lexicographic over unsigned bytes.** `'abc' < 'abd'`. When one
  string is a prefix of the other, the shorter sorts first: `'ab' < 'abc'`, and
  the empty string sorts before everything. Because comparison is by byte,
  ordering follows ASCII for ASCII text, so `'Z' < 'a'`, and UTF-8 text sorts by
  code unit rather than by any linguistic collation.

### Range Errors

Range checking is off by default and enabled with `{$R+}`.

- **An out-of-range array index is undefined behavior** with `{$R-}`. The access
  is performed at the computed address. Depending on how far out of range it is,
  the program may read or write an unrelated variable and continue with
  corrupted data, or fault if the address leaves linear memory. With `{$R+}` it
  traps.
- **Set membership outside the set's representation is `false`**, never an
  error and never a wrong answer. `99 in s` where `s: set of 0..7` is `false`,
  and so is a negative ordinal. This holds at any directive setting: the test is
  range-guarded rather than range-checked, so `{$R+}` does not turn it into a
  trap.
- **A `case` selector matching no branch, with no `else`, falls through**
  silently to the statement after `end`. This is Turbo Pascal behavior and is
  intentional; ISO 7185 makes it an error.

### Pointers

- **Dereferencing `nil` traps** under `{$S+}`, which is the default. Under
  `{$S-}` it reads or writes the four-byte nil guard at address 0. A read
  returns zeros, so the program continues on a value it never stored, which is
  the failure the check exists to replace.
- **Dereferencing a pointer to storage that no longer exists is undefined
  behavior** at any directive setting. A pointer to a local outlives that
  local's frame, and nothing distinguishes a stale address from a live one.
- **Assigning between pointer types with different targets is not yet
  rejected.** The compiler checks pointer against non-pointer but does not
  compare the targets. This is an implementation gap, not a language rule; do
  not write code that relies on it.
- **A second pointer to a disposed block is dangling.** `Dispose` clears the
  pointer it was given and nothing else. Reading through another pointer to
  the same block reads whatever the allocator has since put there, and writing
  through one corrupts the free list. Not detected at any directive setting.
- **`Dispose` on a pointer that did not come from `New` is undefined.** The
  allocator reads a block header eight bytes below the address it is given. A
  pointer from `@x` has no such header, so this corrupts the free list rather
  than reporting anything. Not detected.
- **A block is never zeroed.** `New` hands back whatever was last in that
  memory. Initialize every field; the nil guard protects only address zero.

## Conformance

This section states what an implementation must do to call itself Compact Pascal. It exists so that a second implementation is possible, and so that a program can say what it relies on.

### Requirements

A conforming implementation:

- **Accepts every program this document defines** and rejects every program this document says is an error. Where the document says an error is reported at a particular point, such as a `forward` header mismatch at the definition, it is reported there.
- **Emits WASM 1.0 (MVP)** with no post-MVP proposals. A module it produces runs on any compliant WASM 1.0 runtime.
- **Uses WASI preview 1** for I/O and termination, emitting only the imports listed under [Implicit WASI Imports](#implicit-wasi-imports). An implementation may declare an import it does not call, as the reference compiler does for the five core ones, but it may not declare `path_open` or `fd_close` unless the program asked for filesystem access. What a module *calls* must follow from what the program does; what it *declares* need not.
- **Writes the compiled module to standard output and every diagnostic to standard error**, in the formats given under [Compiler Diagnostics](#compiler-diagnostics). Nothing else may reach standard output.
- **Halts on the first error** with a nonzero exit status. Error recovery and multi-error reporting are not permitted, because a program's meaning after the first error is not defined.
- **Is deterministic.** The same source, the same flags, and the same implementation version produce byte-identical output. Nothing may depend on the time, the filesystem, the environment, or address-space layout.

Two conforming implementations may produce different modules from the same source. Only observable program behavior is required to agree.

### Errors and Undefined Behavior

The document uses three categories, and the difference matters:

- **An error** must be detected and reported, and compilation must stop. Example: assigning to a `const` parameter.
- **A trap** is detected at runtime and terminates the program. Traps are not catchable. Example: division by zero, or an out-of-range array index under `{$R+}`.
- **Undefined behavior** is not detected. The implementation may do anything, and different implementations may differ. Example: reading a local before assigning it, or an out-of-range array index under `{$R-}`.

A program that stays clear of undefined behavior and does not exceed the limits below behaves identically on every conforming implementation and every compliant runtime. That is the portability guarantee, and it is the whole of it.

### Minimum Limits

An implementation may impose limits, but not below these. A program staying within them is portable; the reference compiler's own limits are listed for reference and are what a program can currently rely on.

| Resource | Minimum | Reference compiler |
|---|---|---|
| Live symbols | 1024 | 1024 |
| Nested scopes | 32 | 32 |
| User-defined procedures and functions | 256 | 256 |
| Distinct named types | 256 | 256 |
| Record fields, all records combined | 512 | 512 |
| Parameters per procedure or function | 16 | 16 |
| Procedure nesting depth | 8 | 8 |
| Nested `with` statements | 8 | 8 |
| Exported symbols | 32 | 32 |
| Conditional symbols defined at once | 32 | 32 |
| `{$IFDEF}` nesting depth | 8 | 8 |
| Unresolved forward pointer references per type block | 32 | 32 |
| Include nesting depth | 8 | 8 |
| Operands in one string concatenation | 16 | 17 |
| String length | 255 | 255 |
| Set base type values | 256 | 256 |

Exceeding a limit is an error and must be reported as one. It is never undefined behavior.

Pointer types are counted against the named-type limit. A `^T` written anywhere, including inline in a `var` declaration, occupies an entry, though pointers with the same target share one. A program with many distinct pointer types can therefore reach the limit with fewer than 256 type declarations of its own.

Where the two columns differ, a program using the larger value compiles today but is not portable. The concatenation diagnostic counts saved pieces rather than operands, so it reports a maximum of 16 while accepting 17 operands; the operand count is what a program author sees, and it is what the table gives.

## Compiler Directives

Compiler directives use the same syntax as Free Pascal: `{$DIRECTIVE}` or `{$DIRECTIVE VALUE}`. They appear inside comments and control compiler behavior. The alternative syntax `(*$DIRECTIVE*)` is also accepted.

Directives are either **global** (must appear before the first declaration or statement in a compilation unit) or **local** (may appear anywhere and take effect from the point they appear).

An unrecognized directive is skipped and reported with a `Warning:` diagnostic. Skipping keeps sources portable across dialects, and the warning keeps a misspelled directive from silently doing nothing. The one exception is `{$MODE}`, which is accepted and ignored without a warning: Compact Pascal has a single dialect, and the compiler's own source carries the directive for the fpc bootstrap.

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
| `{$FILES ON}` | OFF | Request filesystem access. Adds `path_open` and `fd_close` to the module's imports. Must appear before the `program` header; cannot be switched off again. |

`{$FILES ON}` is a capability request, not a convenience. Turning it on is visible in the compiled module's import list, so a host can refuse to instantiate a program that wants files without having to read its source. A host grants the actual access by preopening a directory; see [The Heap](#the-heap) for the memory side of the same idea, where the limit is likewise enforced by the host rather than by the language.

The restriction to before the header is not arbitrary. Helper function indices are numbered from the import count, and those numbers become immediate operands in call instructions, so the count must be settled before any code is emitted. A single-pass compiler cannot revise it afterwards.

### Local Directives

Local directives may appear anywhere in the source. They take effect from the point they appear until changed by another directive of the same kind, or until the end of the compilation unit.

| Directive | Short | Default | Description |
|---|---|---|---|
| `{$RANGECHECKS ON/OFF}` | `{$R+/-}` | OFF | Emit runtime range checks for array indexing and subrange assignments. |
| `{$OVERFLOWCHECKS ON/OFF}` | `{$Q+/-}` | OFF | Emit runtime overflow checks for integer arithmetic. |
| `{$STACKCHECKS ON/OFF}` | `{$S+/-}` | ON | Emit a stack overflow guard in every procedure and function prologue, a frame balance check in every epilogue, and a nil check on every pointer dereference. |
| `{$I+/-}` | — | ON | Trap on a file operation that fails. With it off the error is recorded for `IOResult` instead. Distinguished from `{$I 'file'}` by the character after the `I`. |
| `{$ALIGN n}` | — | 4 | Record field alignment in bytes (1, 2, 4, or 8). Each field within a record is placed at the next multiple of `n`; the total record size is padded to a multiple of `n`. |
| `{$INCLUDE 'filename'}` | `{$I 'filename'}` | — | Include the contents of `filename` at this point. Resolved by the compiler with `-I`, or by the host beforehand. See [Include Files](#include-files). |
| `{$EXPORT name}` | — | — | Export the next procedure, function, or variable as `name` in the WASM module's export table. |
| `{$IMPORT 'module' name}` | — | — | Declare the next procedure or function as a WASM import from `module` with import name `name`. |
| `{$EXTLITERALS ON/OFF}` | — | OFF | Enable C-style numeric literal prefixes: `0x` (hex), `0o` (octal), `0b` (binary). |

### Conditional Compilation

| Directive | Description |
|---|---|
| `{$IFDEF symbol}` | Compile the following block only if `symbol` is defined. |
| `{$IFNDEF symbol}` | Compile the following block only if `symbol` is **not** defined. |
| `{$ELSE}` | Alternate block for the preceding `{$IFDEF}` or `{$IFNDEF}`. |
| `{$ENDIF}` | End of a conditional block. |
| `{$DEFINE symbol}` | Define `symbol` for the remainder of the compilation unit. |
| `{$UNDEF symbol}` | Undefine `symbol` for the remainder of the compilation unit. |

Symbol names are case-insensitive and may be up to 255 characters. Nesting is supported up to 8 levels deep. Up to 32 symbols may be defined at once (predefined + `{$DEFINE}` + `-d`).

The compiler predefines `CPAS` so sources can detect a Compact Pascal build. Additional symbols can be defined from the command line with `-dSYMBOL` (repeatable), or in source with `{$DEFINE symbol}` / `{$UNDEF symbol}`. The compiler's own source uses `{$IFDEF FPC}` to gate fpc-only code: when compiled with fpc, fpc predefines `FPC`; when compiled by the self-hosted cpas compiler, `FPC` is undefined and `{$IFDEF FPC}` blocks are skipped.

```pascal
{$IFDEF DEBUG}
  writeln('debug mode');    { compile with: cpas -dDEBUG < prog.pas }
{$ELSE}
  writeln('release mode');
{$ENDIF}

{$DEFINE VERBOSE}
{$IFDEF VERBOSE}
  writeln('verbose output enabled');
{$ENDIF}
{$UNDEF VERBOSE}

{$IFDEF CPAS}
  { built by Compact Pascal }
{$ENDIF}

{$IFDEF FPC}
  { fpc-only bootstrap code }
{$ELSE}
  { self-hosted path }
{$ENDIF}
```

### Examples

```pascal
{$MEMORY 4}           { 4 pages = 256 KB initial memory }
{$MAXMEMORY 64}       { up to 4 MB }
{$STACKSIZE 32768}    { 32 KB stack }

program Example;

{$I 'common.inc'}     { include shared definitions }

{$R+}                 { enable range checks from here }
{$Q+}                 { enable overflow checks from here }

{$ALIGN 1}            { pack fields, no padding }
type TPacked = record
  A: char;
  B: integer;
end;
{$ALIGN 4}            { restore default 4-byte alignment }

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

### Include Files

`{$I 'filename'}` inserts the contents of a file. There are two ways it gets resolved, and which one applies is the caller's choice, not the program's.

**The compiler resolves it**, given `-I`:

```
cpas -I < main.pas > main.wasm
```

Names are relative to the compiler's working directory. When the compiler is itself running as WASM, that is the directory the host preopened, and nothing outside it is reachable.

**Or the host resolves it first**, expanding every directive before the compiler sees the source. The Rust crate's `expand_includes` does this, confining resolution to a base directory the caller chooses. This is the older path and it stays supported: an embedder that wants to serve includes from a database, a zip file, or an editor buffer can, because the compiler never needs to know where the text came from.

Without `-I` the compiler **skips** the directive. That is what makes the two paths safe together: source already expanded by a host has no directives left, and one that still has them would otherwise be opened twice.

| Limit | Value |
|---|---|
| Nesting depth | 8 |
| A file including itself, directly or through others | Error |
| A file that cannot be opened | Error |

The depth is a specified limit rather than a consequence of available memory, so a program can rely on it. Each level costs one text control block.

A cycle is detected by comparing names against the files currently open, so `a` including `b` including `a` is caught at the second `a` rather than looping until the depth limit. The name is compared as written; two different spellings of the same file are two different files to this check.

During fpc bootstrap, the compiler runs as a native executable and fpc handles `{$I}` in the compiler's own source natively. That is unrelated to how the compiler handles `{$I}` in the source it is compiling.

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

Phase 1 uses `Error:` and `Warning:` by default, plus `Progress:`, `Info:`, and `Debug:` when the corresponding command-line flag is given. All five tags are implemented.

A `Warning:` is not fatal. The compiler reports it, continues, and still exits 0 if nothing else goes wrong, so a host must not treat the presence of output on stderr as a failure. Use the process exit status for that.

### Progress Tag

The `Progress:` tag uses a fixed `done/total` format (both integers) so the host can compute a percentage or display a progress bar. An optional human-readable message may follow the ratio:

```
Progress: 0/123
Progress: 20/100 Analyzing...
Progress: 100/100 Done
```

Progress reporting is off unless the `-progress` flag is given, so it never interferes with a host that does not want it. The compiler reads its source as a stream and never learns the total size on its own, which gives the flag two forms:

| Invocation | `total` means | Behavior |
|---|---|---|
| `-progress` | A fixed count of compilation stages | Reports at each stage boundary. Needs nothing from the host, but parsing is a single stage and dominates the run, so the ratio sits still for most of a large compile. |
| `-progress N` | The source line count, supplied by the host | Reports as the scanner advances, at most about 100 times over the whole source. Smooth and proportional to real work. |

The host writes the source to the compiler's stdin, so it already knows the line count and can pass it. `done` is clamped to `total`, and reporting stops once the scanner passes `total`, so a low `N` cannot drive a ratio above 1. Both forms end with a `Done` line at `total/total`.

### Info Tag

`Info:` lines carry no source position and are emitted only under the `-v` flag. After a successful compile the compiler reports the source line count, the number of imports, the number of user functions, and the size of the module written:

```
Info: 10984 source lines
Info: 5 imports
Info: 188 user functions
Info: 146081 bytes written
```

### Debug Tag

`Debug:` lines trace what the compiler does as it does it, and are emitted only under the `-debug` flag. Lines that correspond to a point in the source carry a position, formatted as `Error:` and `Warning:` format theirs. Lines that do not, such as the predefined symbols installed before reading begins, carry no position:

```
Debug: built-in type INTEGER
Debug: 2:6: enter scope 1
Debug: 3:0: declare const LIMIT at scope 1, level 0
Debug: 7:4: declare function DOUBLE at scope 1, level 0
Debug: 7:4: enter scope 2
Debug: 14:0: leave scope 2, discarding 2 symbols
Debug: 14:0: body of DOUBLE: 1 params, 2 locals, 54 bytes
```

The traced events are scope entry and exit, symbol declarations, and the size of each compiled procedure or function body. Because the compiler is single-pass with one token of lookahead, a position can sit slightly past the construct it describes: the scanner has already read ahead by the time the event fires. `Error:` positions behave the same way.

`-debug` is distinct from `-dump`. `-dump` prints a human-readable disassembly of the finished module; `-debug` traces decisions as they are made, interleaved with the reading of the source.

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

procedure Purr for (c: TCat);
begin
  { c is the receiver — a value of type TCat }
end;
```

The receiver appears after the `for` keyword in parentheses, as `(name: Type)`. It becomes the first implicit (hidden) argument of the method. The parentheses keep the receiver visually distinct from the return type: without them a function method reads `function Area for r: TRect: integer`, with two colons of different meaning in sequence.

#### Receiver Types

There are two types of method receivers:

- **Value receiver** — the receiver is passed by value (copied). Intended for small, immutable types. The method cannot modify the caller's copy.

  ```pascal
  function Area for (r: TRect): integer;
  begin
    Area := r.Width * r.Height;
  end;
  ```

- **Pointer receiver** — the receiver is passed as a pointer, giving the method reference semantics. It operates on the original data and can modify internal state. Preferred for large records or when mutation is needed.

  ```pascal
  procedure Rename for (c: ^TCat) (const NewName: string);
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

**The automatic address-of applies only to addressable operands.** An operand is addressable if it is a variable, a field of an addressable record, an element of an addressable array, or a pointer dereference. A function result, a type cast, a constant, and any other temporary are not addressable. Calling a pointer-receiver method on a temporary is a compile error:

```pascal
function Origin: TPoint; { returns a temporary }

Origin.Rename('X');   { ERROR: Rename needs an addressable receiver }
```

Without this rule the mutation would land in a temporary and be discarded with no diagnostic. Value-receiver methods have no such restriction: they copy, so a temporary receiver is harmless.

**A method may not share a name with a field of its receiver type.** The collision is reported at the method declaration, not at the call:

```pascal
type TCat = record Name: string; end;

function Name for (c: TCat): string;  { ERROR: TCat already has a field Name }
```

This keeps `MyCat.Name` unambiguous. The alternative, letting fields shadow methods, resolves the ambiguity just as well but breaks at a distance: adding a field to a record silently makes an existing method uncallable, and the error surfaces wherever the method was used rather than where the field was added.

### Structured Return Types

Standard Pascal restricts function return types to simple types and pointers. Compact Pascal lifts this restriction: a function may return a `string`, a record, or an array. This follows the precedent set by C, where functions can return structs by value.

```pascal
type TPoint = record
  X, Y: integer;
end;

function Origin: TPoint;
var P: TPoint;
begin
  P.X := 0;
  P.Y := 0;
  Origin := P;      { assign the whole value }
end;

function Greet(const Name: string): string;
begin
  Greet := 'hello, ' + Name;
end;

function Shout(const S: string): string[40];
begin
  Shout := S + '!';
end;
```

The return type must be a type *name*, or `string` / `string[n]`. An anonymous `record ... end` or `array[...] of T` is not accepted, because a caller has no way to name that type.

**Assign the result as a whole.** `Origin := P` is how a structured result is delivered. Assigning to a field or element of it, `Origin.X := 0`, is not supported and is a compile error naming the limitation. Build the value in a local variable and assign that.

**An `external` function cannot return a structured type.** The mechanism below is a private arrangement between the compiler's call sites and its own prologues; nothing tells a host what to do with it.

#### How it works, and what that costs

The caller allocates the result buffer and passes its address as a hidden **trailing** parameter; the callee writes through it and returns no WASM value. Trailing rather than leading so the visible parameters keep their indices.

The buffer comes from the stack, not from the caller's frame — the frame size is fixed before the body is compiled, so it cannot hold a count of temporaries that is not known from the declarations. It is released at the end of the statement. That is the shortest lifetime that works: a result can be an operand of anything within the statement, and nothing refers to it afterwards.

Two consequences worth knowing:

- **A statement that calls many structured-returning functions holds every result until it ends.** `writeln(F(1), F(2), F(3))` has three buffers alive at once. Each `string` result costs 256 bytes. With the default 64 KB stack this is not a practical limit, but a statement in a deeply recursive function is spending stack that the recursion also needs.
- **Loops release each iteration**, so a loop calling a string-returning function ten thousand times uses one buffer's worth of stack, not ten thousand. `exit`, `break`, and `continue` release before branching.

Under `{$S+}` an unbalanced release is caught by the frame balance check described under [Stack](#stack).

### Interfaces

An interface defines a set of method signatures that a concrete type can satisfy. There is no inheritance. Signatures are matched structurally, but conformance is declared explicitly in an implement block and verified at that single point, in one pass. This is closer to Rust's `impl Trait for Type` than to Go, where a type satisfies an interface implicitly and conformance is discoverable only by tooling. Explicit conformance suits a declare-before-use language: the compiler can check it the moment the block closes, and a type cannot satisfy an interface by accident.

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
- When the compiler reaches the closing `end;`, it verifies that every method declared in the interface is satisfied with a compatible signature.
- A type may implement multiple interfaces via separate `implement` blocks.

#### The Block Declares Conformance

An `implement` block is a **conformance declaration**, not a second place to define methods. When the block closes, each interface signature is resolved in this order:

1. A method of that name defined inside the block.
2. Otherwise, a standalone method already declared for the receiver type.

Only signatures with no matching standalone method need a body in the block. A type that already has the method it needs writes nothing:

```pascal
procedure Greet for (c: TCat) (const HumanName: string);
begin
  WriteLn('Meow, ', HumanName);
end;

implement IPet for TCat;
  { Greet is satisfied by the standalone method above.
    Only genuinely missing signatures are written here. }
end;
```

This resolution is still single-pass. Declare-before-use guarantees every candidate standalone method has already been seen by the time the block closes, so no lookahead is needed.

Methods defined inside an `implement` block are **not** dot-callable on the concrete type. The two forms have distinct jobs: a standalone method declares part of the type's own surface, while the block declares that the type conforms to an interface. A method that should be callable both ways is written once as a standalone method and then simply satisfies the interface.

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

**The `Self` pointer does not keep the concrete value alive.** An interface value is only valid while the data it points at is. Storing one in a global, returning one from the function whose local it refers to, or keeping one past the end of the block that declared the concrete variable all leave `Self` dangling, and the language does not detect it. This is the same rule Pascal already applies to `@x` and to `var` parameters: the programmer owns the lifetime. It is stated here because an interface value hides the pointer, so the hazard is less visible than it is with an explicit `^T`.

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
                 | Identifier ':' Type '=' Initializer ';' .
                 (* First form is an untyped constant.
                    Second form is a typed constant / initialized variable.
                    ConstExpr is evaluated at compile time.
                    LL(2): both alternatives begin with Identifier; peek for
                    '=' versus ':' to choose. *)

Initializer      = ConstExpr
                 | ArrayInitializer
                 | RecordInitializer
                 | SetInitializer
                 | STRING_LITERAL .
                 (* STRING_LITERAL is accepted as a shortcut for
                    array[lo..hi] of char; its length must equal hi-lo+1.
                    LL(2): ArrayInitializer and RecordInitializer both begin
                    with '('; peek for Identifier ':' to tell a record from an
                    array. *)

ArrayInitializer = '(' Initializer { ',' Initializer } ')' .
                 (* Element count must equal the array's declared length.
                    Nested arrays use nested parenthesized initializers. *)

RecordInitializer = '(' FieldInit { ';' FieldInit } [ ';' ] ')' .
FieldInit        = Identifier ':' Initializer .
                 (* Fields must appear in declaration order and every field of
                    the fixed part must be given. A variant record is
                    initialized through its tag field followed by the fields of
                    the selected variant. *)

SetInitializer   = '[' [ SetElem { ',' SetElem } ] ']' .
SetElem          = ConstExpr [ '..' ConstExpr ] .

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
                 (* LL(2): TypeIdentifier and SubrangeType both begin with
                    Identifier. Peek past it for '..' (subrange) or '(' (typed
                    subrange); anything else is a plain type name. EnumType is
                    distinguished by its leading '(' in the first position. *)

TypeIdentifier   = Identifier .
                 (* built-in: integer, boolean, char, real,
                    byte, shortint, word, longint *)
StringType       = 'string' [ '[' Constant ']' ] .
                 (* 'string' alone is 'string[255]'.
                    The reference compiler currently requires an
                    INTEGER_LITERAL here rather than a general Constant, so a
                    named constant is rejected as a string length. *)

EnumType         = '(' IdentList ')' .
SubrangeType     = Constant '..' Constant
                 | Identifier '(' Constant '..' Constant ')' .
                 (* Second form: typed subrange with explicit base type,
                    e.g. Day(Mon..Fri).
                    Not decidable by fixed lookahead. A Constant is a full
                    ConstExpr, so the first form may itself begin with a call:
                    chr(65)..chr(90) and Day(Mon..Fri) agree through
                    Identifier '(' and diverge only at the matching ')', which
                    is an unbounded distance away. The parser resolves it
                    semantically instead: an Identifier followed by '(' starts
                    the second form when that identifier names a type, and is
                    otherwise a constant expression. Declare-before-use makes
                    the symbol table authoritative at this point. *)

ArrayType        = 'array' '[' SubrangeType { ',' SubrangeType } ']' 'of' Type .

RecordType       = 'record' FieldList [ VariantPart ] 'end' .
FieldList        = [ FieldDecl { ';' FieldDecl } ] .
FieldDecl        = IdentList ':' Type .
VariantPart      = 'case' [ Identifier ':' ] TypeIdentifier 'of'
                   Variant { ';' Variant } .
                 (* LL(2): the optional tag name and the following
                    TypeIdentifier are both Identifier. Peek for ':' to tell a
                    tagged variant from a tagless one. *)
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
                    The production left-factors on 'for', so one token of
                    lookahead after the identifier decides between a method
                    and an ordinary procedure. LL(1) is preserved.
                    'external' is used with {$IMPORT} for WASM host-provided procedures.
                    A return type is a TypeIdentifier or a StringType, never an
                    anonymous record or array, and an 'external' function may
                    not return a structured type —
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

The repeated header must **match** the forward declaration: same parameter count, same parameter types, same `var` and `const` markers, and the same return type. A procedure may not be defined as a function, or the reverse. Any disagreement is a compile error at the definition.

```ebnf
FormalParams     = '(' FormalParam { ';' FormalParam } ')' .
FormalParam      = [ 'var' | 'const' ] IdentList ':' Type .

Receiver         = '(' Identifier ':' Type ')' .
                 (* Type may be a value type or '^TypeIdentifier' for pointer receiver.
                    The parentheses separate the receiver from a function's
                    return type, which would otherwise put two colons of
                    different meaning next to each other. *)
```

### Implement Blocks (Extension)

```ebnf
ImplementBlock   = 'implement' TypeIdentifier 'for' TypeIdentifier ';'
                   { ImplMethod }
                   'end' ';' .

ImplMethod       = ImplProcDecl | ImplFuncDecl .
ImplProcDecl     = 'procedure' Identifier [ FormalParams ] ';' Block ';' .
ImplFuncDecl     = 'function'  Identifier [ FormalParams ] ':' Type ';' Block ';' .
                 (* Self is implicitly available inside the block.
                    The block declares conformance: an interface signature with
                    no ImplMethod here is satisfied by a standalone method of
                    the receiver type, so the block may legitimately be empty.
                    ImplMethods are not dot-callable on the concrete type.
                    See Interfaces under Extensions. *)
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
                 (* The whole alternation is optional, so a Statement may be
                    empty. That is deliberate: it admits the empty statement
                    Pascal allows before 'end' and between semicolons. *)

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
AddOp            = '+' | '-' | 'or' .          (* 'or' requires negative lookahead: not followed by 'else' *)

Term             = Factor { MulOp Factor } .
MulOp            = '*' | 'div' | 'mod' | 'and' | 'shl' | 'shr' .
                                               (* 'and' requires negative lookahead: not followed by 'then' *)

Factor           = INTEGER_LITERAL
                 | REAL_LITERAL
                 | STRING_LITERAL
                 | 'nil'
                 | Designator          (* includes true, false as built-in identifiers *)
                 | '@' Designator      (* address of an addressable designator *)
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
                 (* Produces a rune value — a 32-bit Unicode codepoint.
                    Future extension: no production references it yet. When
                    'rune' lands it belongs in Factor and in case labels, so
                    check Constant and Factor at that point. *)

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

`self`, `true`, `false`, `input`, `output`, `stderr`, `maxint` are built-in identifiers, not reserved words. Compiler intrinsics (`write`, `writeln`, `read`, `readln`, `abs`, `ord`, `chr`, `odd`, `succ`, `pred`, `sqr`, `length`, `sizeof`, `lo`, `hi`, `inc`, `dec`, `exit`, `halt`, `copy`, `pos`, `concat`, `delete`, `insert`, `str`, `eof`, `fillchar`, `new`, `dispose`) are also built-in identifiers. WASM import/export names in `{$IMPORT}` and `{$EXPORT}` directives are case-sensitive.

### Operator Precedence (Highest to Lowest) {#operator-precedence}

| Precedence | Operators | Associativity |
|---|---|---|
| 1 (highest) | `not`, unary `+`/`-` | Right |
| 2 | `*`, `div`, `mod`, `and`, `shl`, `shr` | Left |
| 3 | `+`, `-`, `or` | Left |
| 4 | `=`, `<>`, `<`, `>`, `<=`, `>=`, `in` | None |
| 5 | `and then` | Left |
| 6 (lowest) | `or else` | Left |

> **Pascal unary sign quirk.** The grammar rule `SimpleExpr = ['+' | '-'] Term { AddOp Term }` means unary `+`/`−` apply to the entire first `Term` — including all `*`, `div`, `mod`, `shl`, `shr` operands in that term. As a result, `−a * b` parses as `−(a * b)`, not `(−a) * b`. The precedence table above reflects the conventional presentation; the grammar is authoritative for actual parse order. This matches ISO 7185 behavior.

> **Deviation from ISO 10206.** ISO Extended Pascal places `and then` with the multiplying-operators and `or else` with the adding-operators. Compact Pascal gives them their own levels below comparisons, matching the precedence of C's `&&` and `||`. This allows `x < 2 * y and then z - 1 < w` to parse as `(x < 2 * y) and then (z - 1 < w)` without parentheses. The eager operators `and` and `or` retain their standard Pascal precedence.

### Comments and Compiler Directives

The productions in this subsection, together with `CHARACTER` and `EOL` above,
describe the scanner rather than the parser. They are deliberately not reachable
from `Program`: comments and directives are consumed lexically and never reach a
parse rule.

```ebnf
EOL              = (* end of line, or end of input *) .
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

A comment begins with `{` or `(*` and ends at the first matching `}` or `*)`. The commentary within a brace or parenthesis-star comment must not contain the closing delimiter. Whether comments nest is undefined — an implementation may support nesting or may not. Programs that depend on nested comments are not portable. Comments may appear anywhere whitespace is permitted. Line comments (`//`) extend to the end of the line. A `$` immediately after `{` marks a compiler directive. Switch directives use `+`/`-` (e.g., `{$R+}`). The brace form is the only directive form: `(*$R+*)` is a comment and has no effect, unlike in Turbo Pascal. A directive written that way is silently ignored, which is worth knowing when porting. See [Compiler Directives](#compiler-directives) for the full directive list.

If the first byte of the source is `#`, the remainder of the first line is ignored. This permits Unix-style interpreter directives (e.g., `#!/usr/bin/env cpas`).

---

Copyright 2026 Jon Mayo. This document is licensed under the [Creative Commons Attribution 4.0 International License (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
