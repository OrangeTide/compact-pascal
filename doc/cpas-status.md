# Compact Pascal Compiler Status

Current implementation status of the Compact Pascal compiler (`cpas`).
The language specification is in the
[Language Reference](compact-pascal-ref.md) — this page tracks which
parts of that specification the compiler implements today.

## Types

- [x] `integer`, `boolean`, `char`
- [x] `byte`, `shortint`, `word`, `longint` (mapped to `i32`)
- [x] `string` (short strings, length byte + data)
- [x] `array` (single and multi-dimensional)
- [x] `record`
- [x] Enumerated types
- [x] `set` (small and large bitmap sets)
- [x] Variant records (`case` tag, named or anonymous)
- [ ] Subrange types (partial: usable as a `set of` base type, including
      the `T(Lo..Hi)` form, but not as a named type or variable type)
- [ ] Pointers (`^T`)
- [ ] `real` (scanner recognizes literals; compiler rejects them)
- [ ] `rune`
- [ ] Procedural types
- [ ] `text` (only `stderr` is recognized; see I/O below)

## Statements

- [x] `if` / `then` / `else`
- [x] `while` / `do`
- [x] `repeat` / `until`
- [x] `for` / `to` / `downto`
- [x] `case` / `of` / `else` / `end`
- [x] `with` / `do`
- [x] `break` / `continue`
- [x] `begin` / `end` compound statement
- [x] Assignment (`:=`)
- [x] Procedure call

## Expressions and Operators

- [x] Arithmetic: `+`, `-`, `*`, `div`, `mod`
- [x] Comparison: `=`, `<>`, `<`, `>`, `<=`, `>=`
- [x] Logical: `and`, `or`, `not`
- [x] Short-circuit: `and then`, `or else`
- [x] Bit shift: `shl`, `shr`
- [x] Set operations: `+`, `*`, `-`, `in`
- [x] String concatenation: `+`
- [x] Unary `+` / `-`

## Declarations

- [x] `const` (compile-time constants)
- [x] Typed constants (initialized variables)
- [x] `type` definitions
- [x] `var` declarations with optional initializers
- [x] `procedure` / `function`
- [x] Value, `var`, and `const` parameters
- [x] Nested procedures (Dijkstra display, 8 levels)
- [x] `forward` declarations
- [x] `external` (WASM imports)

## Built-in Functions and Procedures

- [x] `write` / `writeln` (integer, char, boolean, string; field widths)
- [x] `read` / `readln` (integer, char, string)
- [x] `abs`, `sqr`
- [x] `ord`, `chr`, `succ`, `pred`, `odd`
- [x] `length`, `sizeof`
- [x] `lo`, `hi`
- [x] `inc`, `dec` (with optional step)
- [x] `exit`, `halt`
- [x] `copy`, `pos`, `concat`, `delete`, `insert`
- [x] `str`
- [x] `eof`
- [x] `maxint`
- [ ] `fillchar`
- [ ] `read` / `readln` for `real`
- [ ] `New` / `Dispose` (requires pointer types)
- [ ] `RuneLen`, `DecodeRune`, `EncodeRune`, `RuneChr` (require `rune`)

## Built-in I/O

- [x] `write` / `writeln` to standard output (default target)
- [x] `read` / `readln` from standard input (default target)
- [x] `stderr` as an explicit first argument
- [ ] `input` and `output` as explicit first arguments

## Compiler Directives

- [x] `{$MEMORY n}`, `{$MAXMEMORY n}`, `{$STACKSIZE n}`
- [x] `{$DESCRIPTION 'text'}`
- [x] `{$R+/-}` / `{$RANGECHECKS ON/OFF}`
- [x] `{$Q+/-}` / `{$OVERFLOWCHECKS ON/OFF}`
- [x] `{$ALIGN n}`
- [x] `{$IMPORT 'module' name}`, `{$EXPORT name}`
- [x] `{$I 'filename'}` / `{$INCLUDE 'filename'}` (resolved by host)
- [x] `{$EXTLITERALS ON/OFF}`
- [x] `{$IFDEF}`, `{$IFNDEF}`, `{$ELSE}`, `{$ENDIF}`, `{$DEFINE}`

## Extensions

None of the extensions described in the Language Reference are implemented
yet. Standalone methods and structured return types are independent of each
other; interfaces depend on both procedural types and pointers.

- [ ] Standalone methods (`procedure P for r: T`)
- [ ] Pointer receivers (`for c: ^TCat`) and automatic address-of/dereference
- [ ] Structured return types (functions returning records or arrays)
- [ ] Interfaces and `implement` blocks
- [ ] Unicode character constants (`#u`)

## Compiler Diagnostics

- [x] `Error: line:col: message`, the form the Language Reference specifies
- [x] `Warning: line:col: message`, non-fatal, compilation continues
- [x] All diagnostics on stderr (fd 2), never stdout
- [x] First error is fatal, exit via `proc_exit(1)`
- [ ] `Info:`, `Debug:` tags
- [ ] `Progress: done/total` protocol

One warning is emitted today: an unrecognized compiler directive. `{$MODE}`
is exempt, since the compiler's own source carries it for the fpc bootstrap.

Command-line errors, such as an unrecognized option, carry the `Error:` tag
but no source position, since none applies.

Keeping diagnostics off stdout is not cosmetic. The compiler writes the
compiled module to stdout, so a message on the wrong stream corrupts the
output rather than merely looking untidy.

Three tests guard this. `negative/n010_error_format` matches an anchored
`^Error: 9:13: undeclared identifier: BOGUS$`, which pins the tag, the
position, and the separators. `cli/c001_unknown_option` runs the compiler
with a bad flag and requires a nonzero exit, the tagged message on stderr,
and an empty stdout. `positive/t100_warning_unknown_directive` pins the
warning line and checks that compilation still succeeds.

Positive tests without a `.warning` file must compile with nothing on
stderr at all, so a stray diagnostic fails the suite rather than passing
unnoticed.

## Not Planned

- `goto` / `label`
- `file` types
- `packed` arrays
