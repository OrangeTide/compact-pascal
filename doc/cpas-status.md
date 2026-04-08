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
- [ ] Variant records
- [ ] Subrange types
- [ ] Pointers (`^T`)
- [ ] `real` (scanner recognizes literals; compiler rejects them)
- [ ] `rune`
- [ ] Procedural types

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
- [ ] `read` / `readln` for `real`
- [ ] `New` / `Dispose` (requires pointer types)

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

## Not Planned

- `goto` / `label`
- `file` types
- `packed` arrays
