# Compiler Status

## Tests

88/88 passing (85 positive, 3 negative). All tests green.

## Three-Stage Self-Hosting Build

`make all` passes. Stage 1 and stage 2 produce identical WASM binaries (fixed point reached).

```
pascom.pas --[fpc]--> build/native/pascom              (bootstrap)
pascom.pas --[bootstrap]--> build/bootstrap/pascom.wasm (stage 1)
pascom.pas --[stage1]--> build/wasm/pascom.wasm         (stage 2, identical to stage 1)
```

## Compiler Size

7,322 lines (pascom.pas).

## Recent Work

- Set types implemented: small sets (`set of integer`, 0..31 as i32 bitmask) and large sets (`set of char`, 0..255 as 32-byte bitmap). All set operations (union, intersection, difference, membership, comparison) supported with inline WASM for small sets and helper functions for large sets.
- Three-stage build fixed: ULEB128 encoding for section counts >127, promoted dataBuf/secData to TCodeBuf for >4KB data segments, added `{$WASMHEAP N}` directive for configurable WASM memory pages, fixed `read(input, ch)` parsing.

## Supported Language Features

- Integer and char types, boolean expressions
- String types (Pascal strings, concatenation, comparison, copy, length, pos, delete, insert, str)
- Arrays (1D, 2D), records, enumerations
- Set types (set of integer, set of char)
- Constants, typed constants, variable initializers
- Control flow: if/else, for, while, repeat/until, case, break/continue
- Procedures and functions with value/var/const parameters
- Nested procedures with static link (display) access
- Built-in I/O: write, writeln, read, readln (integer, char, string)
- Built-in functions: ord, chr, length, abs, sqr, odd, succ, pred, inc, dec, halt, copy, pos, concat, delete, insert, str, eof
- Compiler directives: $MODE, $R+/-, $Q+/-, $EXTLITERALS, $IFDEF/$IFNDEF/$ELSE/$ENDIF, $WASMHEAP, $STACKSIZE
- Extended numeric literals: $HH, 0xHH, 0oOO, 0bBB, &OO, %BB
