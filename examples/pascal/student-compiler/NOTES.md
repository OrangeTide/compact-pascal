# Compiler Notes

## Pascal / FPC -Mtp Gotchas

### Brace comments are not nestable
`{ ... }` comments end at the first `}`, even if the intent was to reference the character
inside the comment text. ISO Pascal does not allow nested brace comments, and Turbo Pascal
is "weird" about it (TP allows `(* { *)`-style nesting but not `{ { } }`).

**Rule:** Never write `{` or `}` inside a `{ ... }` comment. Use the words
"left-curly-brace" and "right-curly-brace" instead. Use `(* ... *)` only
when you need to embed a brace comment inside an outer comment.

Example of the bug:
```pascal
{ Called when ch = '{'; skips to closing '}' }
{ ^comment ends HERE^, not at the closing brace on the right }
```

Fixed:
```pascal
{ Called when ch is left-curly-brace; skips to closing right-curly-brace }
```

### concat() for string building
`concat(s, c)` where `c` is a `char` works in FPC even in -Mtp mode because FPC
implicitly converts `char` to a single-character `string`. Confirmed working.

### shr/shl are supported in -Mtp mode
Despite some sources suggesting otherwise, `shr` and `shl` work in FPC's `-Mtp`
mode. The tutorial uses them for LEB128 encoding. `shr` is logical (unsigned),
so sign extension for SLEB128 must be done manually:
```pascal
value := value shr 7;
value := value or longint($FE000000);  { restore top 7 sign bits }
```

### Large buffers must be global variables
Turbo Pascal has limited stack space. A 128 KB `TCodeBuf` as a local variable
would overflow the stack. Declare all large buffers as global variables so they
live in the data segment.

### Binary output requires BlockWrite
Pascal's `write` does text translation (e.g. LF -> CRLF on some platforms).
For raw binary output, accumulate bytes in a buffer then flush with:
```pascal
Assign(outFile, '/dev/stdout');
Rewrite(outFile, 1);
BlockWrite(outFile, buf.data, buf.len);
Close(outFile);
```

## Chapter 1: Minimal WASM Module

Completed: produces a valid `() -> ()` WASM module with:
- Type section: one `() -> ()` signature
- Function section: one entry (type 0)
- Memory section: 1 page min, 256 pages max
- Global section: mutable i32 stack pointer, init = 65536
- Export section: `_start` (function) + `memory` (memory)
- Code section: _start body = [0 locals, end]

Output is ~62 bytes. Passes `wasm-validate` and runs cleanly under `wasmtime`.

Testing commands:
```
make test                  # run all tests
make test-strap-empty      # build and wasm-validate tests/empty.pas via bootstrap compiler
```
`wasm-validate` exits 0 with no output on success.

The `_start` function index is `numImports`, not 0. When WASI imports are added
later, defined functions shift upward; the export must track `numImports` as offset.

### Plan vs. Implementation Findings

**Module size estimate was wrong.** `chap1plan.md` said ~41 bytes; actual is ~62 bytes.
The extra bytes come from the global section's init expression, export name strings, and
LEB128 overhead.

**`AssembleFunctionSection` uses raw bytes for counts, not LEB128.**
```pascal
SmallBufEmit(secFunc, numDefinedFuncs);
SmallBufEmit(secFunc, 0);  { type index }
```
For values 0–127 a single byte is valid LEB128, so Chapter 1 is fine. When multiple
defined functions or higher type indices are added, these will need `SmallEmitULEB128`.

**SLEB128 for global init i32.const.** The WASM spec requires SLEB128 for i32.const
operands in constant expressions (global init). For 65536 the bytes happen to be
identical to ULEB128 (`$80 $80 $04`) because bit 6 of the final group is 0 (positive).
`AssembleGlobalSection` hardcodes these bytes; `EmitSLEB128` is not exercised until
i32.const appears in the code section (Chapter 3+).

**`SkipWhitespaceAndComments` dual-restore for `(` lookahead.** After reading past `(`
and finding the next char is not `*`, two steps are needed:
```pascal
UnreadCh(ch);   { push back the non-'*' char }
ch := '(';      { restore ch so NextToken dispatches on '(' }
```
A single pushback is not enough because the scanner holds the current character in `ch`
permanently; both slots must be restored.

**`SkipBraceComment` discards the opening brace on its first `ReadCh`.** It is called
while `ch = '{'`; the first statement inside the loop is `ReadCh`, which advances past
the brace before scanning for `'}'`.

**`AssembleCodeSection` bodyLen counts content bytes, not the LEB128 size field.**
`bodyLen := 1 + startCode.len + 1` is the number of bytes in the body (0-locals byte +
instructions + end opcode). `EmitULEB128(secCode, bodyLen)` then encodes that count.

## Chapter 2: Scanner Additions

### Plan vs. Implementation Findings

**String/char scanning was extracted into helper procedures.** The plan described
both inline inside the `case` block. In practice they became two top-level procedures
(`ScanStringSegment`, `ScanCharConst`) that take `ident` by reference and append to
it. TP does not allow local procedures inside a `case` block; extracting them also
made the folding loop uniform (either helper can be called without a type check).

**`tokStr` must be explicitly restored after a failed and-then / or-else lookahead.**
The plan described storing the peeked token in `pendingTok`/`pendingKind`/`pendingStr`
and resetting `tokKind := tkAnd`, but did not mention resetting `tokStr`. The
`NextToken` peek call overwrites `tokStr`, so after a failed peek, `tokStr` must be
set back to `'AND'` (or `'OR'`) explicitly, or any caller reading `tokStr` after
receiving `tkAnd`/`tkOr` will see the wrong string.

**Real number detection matched the plan exactly.** `UnreadCh(ch); ch := '.'` is the
correct two-step restore after peeking past the dot.

**Adjacent string/char folding matched the plan exactly.** The `while (ch = '''') or
(ch = '#') do` loop works for both entry points (`''''` case and `'#'` case).

**`ScanCharConst` with no digits silently produces `chr(0)`.** The plan specified the
decimal and hex loops but did not address the case where no digit follows `#`. The
loop simply does not execute, `val` stays 0, and `chr(0)` is appended. Not a bug
(valid Pascal idiom), but unspecified behaviour in the plan.

**`LookupKeyword` required no changes.** `AND`, `OR`, `THEN`, `ELSE` were already in
the table from Chapter 1. This matched the plan.

### Helper procedures extracted from NextToken

The plan described string and character constant scanning inline inside `NextToken`'s
`case` block. In practice this was moved into two named procedures:

- `ScanStringSegment(var ident: string)` — scans `'...'` with doubled-quote escape;
  appends content to `ident`; on return `ch` is the first char after the closing quote.
- `ScanCharConst(var ident: string)` — scans `#n` or `#$n`; appends `chr(val)` to
  `ident`; on return `ch` is the first char after the digits.

Both take `ident` by reference and append rather than return, so the folding loop
in `NextToken` can call either one uniformly. TP does not allow local procedures
inside a `case` block, so top-level helpers are the only clean option.

### tokStr must be restored after and-then / or-else lookahead fails

The plan omitted this detail. When `and` is seen, `NextToken` is called to peek at
the next token, which overwrites `tokStr`. If the peeked token is not `then`, the
pending-token slot stores the peeked token correctly, but `tokKind` is reset to
`tkAnd` — and `tokStr` must also be restored to `'AND'` explicitly, because the
peek call has overwritten it. Same applies to `or` / `tokStr := 'OR'`. Without
the explicit restoration, `tokStr` would hold the wrong value for any caller that
reads it after receiving `tkAnd` or `tkOr`.

### Real number detection: UnreadCh then set ch

After peeking at the char following a decimal integer and finding it is not a digit
(so the dot belongs to the next token), the restore sequence is:
```pascal
UnreadCh(ch);
ch := '.';
```
`UnreadCh` pushes back the non-digit char; setting `ch := '.'` puts the dot back
as the current character. This matches the plan exactly and works correctly.

### String length check: error before appending

Both `ScanStringSegment` and `ScanCharConst` check `length(ident) >= 255` before
the `concat` call and call `Error` if true. The check is at 255, not 256, because
`string` in TP mode has a maximum length of 255; at 255 the string is already full
and appending one more byte would silently truncate or corrupt it.

### Helper entry/exit contract: callers never pre-advance

Both `ScanStringSegment` (trigger `'`) and `ScanCharConst` (trigger `#`) begin
with `ReadCh` to consume their own trigger character. The `case` branches in
`NextToken` call them directly without a preceding `ReadCh`. Uniform contract:
on entry `ch` is the trigger character; the helper consumes it; on return `ch`
is the first character after the scanned token.

### `and then` / `or else` folding is inside the identifier branch, not a separate case

The two-word operator folding is not a separate `case` entry. It happens at the
bottom of the `'A'..'Z'` branch, after `LookupKeyword` has set `tokKind`. Only
`tkAnd` and `tkOr` trigger a lookahead `NextToken` call. This placement means
the folding adds no overhead to other token kinds.

### `ScanCharConst` with no digits silently produces chr(0)

If `#` is followed by a non-digit (e.g., a space or EOF), neither the decimal nor
hex loop executes, `val` stays 0, and `chr(0)` is appended without error. The
plan does not address this edge case. `#0` is intentional Pascal idiom; a bare
`# ` (hash-space) silently producing `chr(0)` is a quirk to be aware of.

## Chapter 3: Expressions and Code Generation

### Left-associativity via same-precedence recursion

In `ParseExpression`, the infix loop calls `ParseExpression(prec)` — passing the
operator's own precedence as the new minimum. This makes every binary operator
left-associative: the recursive call stops before consuming another occurrence of
the same operator, so `a - b - c` parses as `(a - b) - c`, not `a - (b - c)`.

To make an operator right-associative (future use: e.g. exponentiation), pass
`prec - 1` instead of `prec`. All operators in Chapter 3 are left-associative, so
the plan uses `prec` throughout.

### `not` is bitwise complement, not logical NOT

`not expr` compiles to `i32.const -1; i32.xor` — flipping all 32 bits. For
integer operands this is correct bitwise complement. For boolean operands (0 or 1),
it produces -1 (true) or -2 (false), not 1/0. Logical NOT (converting any nonzero
to 0 and 0 to 1) requires `i32.eqz`, which is deferred to Chapter 5 where
boolean-context evaluation is handled via WASM `if` blocks.

### `WriteSection` skips empty sections

`WriteSection` checks `if buf.len = 0 then exit` before emitting anything. This
means programs with no imports produce no import section in the binary — the section
is simply absent. The plan relied on this to avoid a zero-count import section for
programs without `halt`.

### Import index assigned before incrementing

`AddImport` does `AddImport := numImports; numImports := numImports + 1`. The first
import gets index 0, the second gets 1, etc. Because `_start` is always the first
defined function, its export index is `numImports` after all imports are registered
— and `AssembleExportSection` already emits `numImports` for that index. No
adjustment needed when imports are added.

### Plan vs. Implementation Findings

The Chapter 3 implementation was a very close translation of the plan. Minor deviations:

**`InitModule` initialization order differs from plan.** The plan's Step 3 showed import
state init before type 1 registration:
```pascal
idxProcExit := -1;
SmallBufInit(importsBuf);
{ Register type 1: ... }
numWasmTypes := 2;
```
The implementation registers type 0 and type 1 together in one block, then sets
`numWasmTypes := 2`, then inits import state. Functionally identical; the unified type
block is cleaner since both types are unconditional.

**`tkAndThen`/`tkOrElse` WAT comments simplified.** The plan annotated the infix emit
with `{ ;; WAT: i32.and (short-circuit folded at scan time) }`. The implementation uses
`{ ;; WAT: i32.and }` — the parenthetical was dropped. The prose explanation in the plan
covers the semantics without cluttering the emit table.

**Unary `+` present in implementation but absent from plan's code listing.** The plan
lists unary `+` in the precedence table but the `ParseExpression` code snippet omits it.
The implementation includes the `tkPlus` prefix case (a no-op that just recurses). No
functional impact; the plan mentioned it under "Risks and Notes."

**`InitModule` type 0 registration.** The plan's Step 3 said "add after the existing
body" — implying type 0 was already registered from Chapter 1. In the implementation,
`InitModule` registers both type 0 and type 1 explicitly together. Not a deviation in
behavior, but the plan's framing implied a smaller diff than was actually written.

**All tests passed with no debug iteration.** calc (42), math (66), negation (43), plus
existing empty and comments tests. No surprises at runtime.

### tokInt warning cleared

The `tokInt is assigned but never used` warning present after Chapter 2 is gone:
`ParseExpression` reads `tokInt` in the `tkInteger` case.

## Chapter 4: Variables, Assignment, and I/O

Completed: `var` blocks, `:=` assignment, `write`/`writeln` with strings and integers.

### WASM data segment alignment for iovec

`fd_write` requires the iovec pointer to be 4-byte aligned. When string literals
are stored in the data segment before the I/O scratch buffers, the running
`dataLen` may not be a multiple of 4. `EnsureIOBuffers` must pad `dataLen` to
4-byte alignment before allocating `addrIovec` and `addrNwritten`:

```pascal
while (dataLen mod 4) <> 0 do begin
  SmallBufEmit(dataBuf, 0);
  dataLen := dataLen + 1;
end;
```

Wasmtime error without this fix: `Pointer not aligned to 4: Region { start: N, len: 4 }`.

### Import index stability for __write_int

`__write_int` is a defined function; its index is `numImports + 1`. If more
imports are added after this index is computed, the index becomes wrong.
`EnsureWriteInt` eagerly imports BOTH `fd_write` AND `proc_exit` before
computing the index, freezing `numImports`. Subsequent calls to
`EnsureFdWrite`/`EnsureProcExit` are no-ops. Programs using `writeln(integer)`
will always import `proc_exit` even if `halt` is never called (harmless).

### Forward declaration for BuildWriteIntHelper

`BuildWriteIntHelper` is defined in the Code Generation section but called from
`WriteModule` in the Section Assembly section. A forward declaration is needed:
```pascal
procedure BuildWriteIntHelper; forward;
```
Place it just before the `{ ---- Section Assembly ---- }` block.

### AssembleCodeSection for __write_int

The `__write_int` body has 2 extra i32 locals (pos, neg) declared as one group:
`[01, 02, 7F]` (1 group, 2 x i32). The param (value) is local 0 automatically.
Body size = 3 (local decls) + `helperCode.len` + 1 (end opcode).

### Test commands

```
make test                   # run all 9 tests
make test-strap-hello       # write('Hello, world!')
make test-strap-vars        # var + assignment + writeln(integer)
make test-strap-multivar    # multiple vars, arithmetic in writeln
make test-strap-negwrite    # negative integer writeln
```

### Plan vs. Implementation Findings

**`EnsureIOBuffers` adds 4-byte alignment padding — not in the plan.**
The plan called `AllocData(8)` for iovec immediately. The implementation first pads `dataLen`
to the next multiple of 4:
```pascal
while (dataLen mod 4) <> 0 do begin
  SmallBufEmit(dataBuf, 0);
  dataLen := dataLen + 1;
end;
```
Without this, wasmtime aborts: `Pointer not aligned to 4: Region { start: N, len: 4 }`.
String literals placed before `EnsureIOBuffers` may leave `dataLen` at a non-multiple of 4,
so the padding is mandatory whenever strings precede the first `write`/`writeln`.

**`AllocData` uses explicit `for`-loop instead of the plan's `while`-catch-up loop.**
Plan:
```pascal
while dataBuf.len < dataLen do SmallBufEmit(dataBuf, 0);
```
Implementation:
```pascal
for i := 1 to nbytes do SmallBufEmit(dataBuf, 0);
```
Same effect (emits exactly `nbytes` zeros); the `for`-loop is self-documenting.

**`ParseVarBlock` structure: plan consumed `var` internally; implementation does not.**
The plan's `ParseVarBlock` had an outer `while tokKind = tkVar do` loop that consumed the
`var` keyword itself, enabling multiple separate `var` sections (valid Turbo Pascal). In the
implementation, `ParseProgram` consumes the single `var` keyword and then calls
`ParseVarBlock`, which loops only on `tkIdent`. The result supports one contiguous `var`
block with multiple declaration lines — sufficient for Chapter 4 and typical Pascal usage,
but not the multi-section form.

**Assignment kind check moved before consuming tokens.**
Plan (Step 17): checks `syms[sym].kind <> skVar` AFTER `NextToken; Expect(tkAssign)`.
Implementation: checks kind immediately after the existence check, before consuming any tokens.
Produces a cleaner error without eating the `:=` first.

**Size check (`size = 1`) replaces type check (`typ = tyChar or tyBoolean`).**
Both Step 16 (expression load) and Step 17 (assignment store) in the plan tested
`(syms[sym].typ = tyChar) or (syms[sym].typ = tyBoolean)` to choose between 1-byte and
4-byte load/store. The implementation uses `syms[s].size = 1` throughout. This is more
general: any future 1-byte type is handled without updating the condition.

**`ParseWriteArgs` uses `repeat...until false` with `break` instead of `while ... <> tkRParen`.**
Plan:
```pascal
while tokKind <> tkRParen do begin
  ...
  if tokKind = tkComma then NextToken;
end;
```
Implementation:
```pascal
repeat
  ...
  if tokKind = tkComma then NextToken else break;
until false;
```
The `repeat...until false` with explicit `break` avoids entering the loop when the first
argument is syntactically complete and no comma follows, making the exit condition explicit.

**`AssembleDataSection` uses `SmallEmitULEB128` for segment count and memory index.**
Plan used raw `SmallBufEmit(secData, 1)` and `SmallBufEmit(secData, 0)`. Implementation
uses `SmallEmitULEB128`, which is correct for values that could exceed 127 in the future
(segment count for larger programs). For Chapter 4 the bytes are identical.

**`AssembleDataSection` exit guard uses `dataLen` instead of `dataBuf.len`.**
Plan: `if dataBuf.len = 0 then exit`. Implementation: `if dataLen = 0 then exit`.
`dataLen` is the logical counter; `dataBuf.len` is the buffer fill. They are always equal
here, but `dataLen` is the more meaningful variable to test.

**`names` array in `ParseVarBlock` is 32 entries, not 64.**
Plan specified `array[0..63]`; implementation uses `array[0..31]`. Sufficient for any
realistic comma-separated identifier list in one declaration line.

## Chapter 5: Control Flow

Completed: `if`/`else`, `while`, `for`/`to`/`downto`, `repeat`/`until`, `break`, `continue`.
Fixed `begin`/`end` compound statement to support trailing semicolons.

### `begin`/`end` trailing semicolon fix

Both `ParseStatement`'s `tkBegin` handler and `ParseProgram`'s body loop now use the
pattern:
```
ParseStatement;
while tokKind = tkSemicolon do begin
  NextToken;
  if tokKind <> tkEnd then ParseStatement;
end;
Expect(tkEnd);
```
The old `while tokKind <> tkEnd` form did not allow a trailing `;` before `end`.

### WASM block structure for loops

`while` and `for` use a `block`/`loop` pair:
- outer `block` is the break target (`br 1` from inside the loop)
- inner `loop` is the continue target (`br 0` re-enters the loop header)

`repeat`/`until` uses only a `loop` (no outer block), so `break` inside `repeat`
triggers an error (`breakDepth` is set to -1 while inside `repeat`).

### Break/continue depth tracking

`breakDepth` and `continueDepth` are global `longint` variables initialized to -1.
When entering a loop, absolute depths are set (1 for break, 0 for continue) and
previous values are saved/restored.

When entering an `if`/`else` block inside a loop, both depths are incremented by 1
(guarded by `>= 0` to avoid touching the -1 sentinel) and decremented by 1 after
`OpEnd` (guarded by `> 0`). This correctly accounts for the WASM `if` instruction
adding one label level.

### `for` loop limit stored in data segment

Each `for` statement calls `AllocData(4)` to allocate a fresh 4-byte slot for the
loop limit. The limit expression is evaluated once before the loop starts and stored
at that address. This naturally handles nested `for` loops — each gets its own slot.

### Counter increment: address-first pattern

WASM `i32.store` expects `(address, value)` with address pushed first and value on top.
For the counter increment, the store address is pushed before loading and modifying the
current counter value:
```
push sp+offset        (store destination address)
push sp+offset
i32.load              (current counter value)
i32.const 1
i32.add / i32.sub
i32.store             (writes new value to the pre-pushed address)
```
This avoids needing WASM local variables or tee_local.

### Plan vs. Implementation Findings

**Token values for `tkBreak`/`tkContinue` differ from plan.**
The plan specified `tkBreak = 118` and `tkContinue = 119`, but those values are already
used by `tkAnd = 118` and `tkOr = 119`. Assigned `tkBreak = 207` and `tkContinue = 208`
after the existing built-in keyword range.

**`for` limit store order corrected.**
The plan's pseudocode showed `ParseExpression` before `EmitI32Const(limitAddr)` for the
limit store. This is backwards — WASM `i32.store` expects address first, value second.
The implementation pushes `limitAddr` first, then evaluates the limit expression:
```pascal
EmitI32Const(limitAddr);    { push address }
ParseExpression(PrecNone);  { push value }
EmitI32Store(2, 0);
```

**`inc`/`dec` not available in TP mode — replaced with explicit arithmetic.**
The plan used `inc(breakDepth)` and `dec(breakDepth)`. In `-Mtp` mode, `inc`/`dec` are
available as built-ins, but to stay consistent with the rest of the codebase (which uses
`:= x + 1`), the implementation uses explicit addition/subtraction:
```pascal
breakDepth := breakDepth + 1;
breakDepth := breakDepth - 1;
```

**All 14 tests pass with no debug iteration.**
ifelse (exit 1), fact5 (exit 120), forsum (exit 55), repeattest (exit 64), fizzbuzz
(diff output), plus the 9 existing tests. No surprises at runtime.

## Chapter 6: Procedures and Functions

Completed: user-defined procedures and functions, value/var/const parameters, recursive
calls, function return assignment (`funcname := expr`), `exit` intrinsic, and the
`{$IMPORT}` / `{$EXPORT}` directives.

New tests: proc (output), func (exit 12), recurse (exit 120), varparam (output).

### Parameters as WASM locals (negative offset encoding)

Parameters are not allocated in the stack frame. They live in WASM locals. The encoding:
WASM local index `i` → `syms[s].offset = -(i+1)`. Loading a parameter: decode
`localIdx := -(offset+1)` then `EmitLocalGet(localIdx)`. This keeps `offset >= 0` reserved
for frame variables and `offset < 0` for WASM locals, with no overlap.

### var parameters: pointer semantics

A `var` parameter passes the address of the caller's variable. The WASM local holds an
`i32` address (pointer). Reads dereference it (`local.get + i32.load`); writes do the
same for the destination (`local.get + expr + i32.store`). The `isVarParam` flag on the
symbol selects this behavior in `EmitVarLoad` and the assignment path in `ParseStatement`.

At the call site, if the actual argument is a frame variable, its address is computed with
`EmitFramePtr + EmitI32Const(offset) + i32.add`. If the argument is itself a `var` param,
its local already holds an address, so `EmitLocalGet` suffices — no extra indirection.

### Function return value: hidden WASM local at index nparams

Each function has an implicit WASM local at index `nparams` (after all parameter locals).
`funcname := expr` inside the body stores to this local via `EmitLocalSet(nparams)`. After
the exit-wrapper `block` ends and the frame epilogue runs, `EmitLocalGet(nparams)` pushes
the return value onto the WASM stack for the `call` instruction to consume.

### currentFuncSlot tracks active function during body compilation

`currentFuncSlot` (global `longint`, init -1) is set to the `funcs[]` index when
compiling a function body, and restored to -1 afterward. `ParseStatement`'s `tkIdent`
branch checks:
```
(tokKind = tkAssign) and (currentFuncSlot >= 0) and (syms[s].size = currentFuncSlot)
```
to detect `funcname := expr` vs. a function call. Without this, the parser would
expect `(` for a call and error on `:=`.

### Swap-startCode for procedure bodies

Procedures are compiled before the main program body, but all emit to `startCode`.
Before compiling each procedure:
1. Save `startCode` into a local `TCodeBuf` variable
2. `CodeBufInit(startCode)` to reset it to empty
3. Compile the procedure body
4. Copy `startCode` bytes to `funcBodies`
5. Restore `startCode` from the saved copy

This avoids an AST and keeps single-pass compilation intact.

### EnsureBuiltinImports also reserves __write_int

The plan's `EnsureBuiltinImports` called only `EnsureFdWrite` and `EnsureProcExit`.
The implementation also calls `EnsureWriteInt`. Without this, a user function compiled
before any `write`/`writeln` would claim WASM index `numImports+1`, which `__write_int`
also expects. With the early reservation, user functions always start at `numImports+2`
regardless of whether the program uses integer output.

### exit intrinsic uses exitDepth to branch out of function block

Each function body is wrapped in a WASM `block`/`end` pair (the "exit block"). `exit`
emits `br exitDepth` where `exitDepth` counts enclosing WASM blocks and loops between
the `br` and the exit block. At function body level, `exitDepth = 0`. Each WASM `if`,
`block`, or `loop` entered inside the body increments it; leaving decrements it.
`exitDepth = -1` in the main program body means `exit` there is an error.

### Plan vs. Implementation Findings

**`EnsureBuiltinImports` must also call `EnsureWriteInt`.**
Plan only called `EnsureFdWrite` and `EnsureProcExit`. Without reserving `__write_int`
up front, user functions compiled before any integer output claim index `numImports+1`,
conflicting with `__write_int`. Fix: add `EnsureWriteInt` to `EnsureBuiltinImports`.

**`currentFuncSlot` global not in the plan.**
The plan said "when `sym` is `skFunc` and we see `:=`" without specifying how to
distinguish assignment from a call. The implementation uses `currentFuncSlot` (set to the
`funcs[]` index during body compilation) so `ParseStatement` can check `syms[s].size =
currentFuncSlot` to detect the return-value assignment case without lookahead.

**Plan required parens for all calls; implementation makes them optional for 0-param.**
Section 10 of the plan wrote `Expect(tkLParen)` unconditionally. Pascal style allows
`greet;` (no parens) for zero-parameter procedures. The implementation checks
`funcs[fslot].nparams = 0` and skips the paren requirement, consuming optional `()` if
present. Applied in both `ParseStatement` and `ParseExpression`.

**`ParseCallArgs` needed a forward declaration.**
The plan did not address compilation order. `ParseCallArgs` calls `ParseExpression`, which
is defined later in the file. Both `ParseCallArgs` and `ParseProcDecl` required forward
declarations added to the forward-declarations block.

**TP brace comments: `{$IMPORT}` and `{$EXPORT}` in comments.**
The directive-related code and plan pseudocode referenced `{$IMPORT}` and `{$EXPORT}`
inside `{ }` comments, which embed `}` and terminate the comment prematurely in TP mode.
Every such occurrence was rewritten to avoid braces: `{ Pending IMPORT directive }`,
`{ Skip to closing brace }`, etc. Multiple instances across the directive parser.

**Plan's call-site var-param check omitted `isVarParam` test.**
When passing an argument to a `var` parameter, the plan checked `syms[argSym].offset < 0`
to detect "argument is itself a var param." But value params also have `offset < 0`.
The implementation also checks `syms[argSym].isVarParam` to distinguish: if true, the
local already holds a pointer; if false (value param), passing it as `var` is an error.

**All 17 tests pass (13 pre-existing + proc, func, recurse, varparam).**
No surprises at runtime beyond the issues listed above.

## Chapter 7: Nested Scopes

Completed: procedures nested inside other procedures, upvalue access via Dijkstra
display, recursive procedures with nested inner procs, `curNestLevel` tracking.

New test: nested (output).

### Display globals (9 total)

The global section now emits 9 WASM globals: global 0 is $sp (mutable i32, init
65536), globals 1–8 are `display[0..7]` (mutable i32, init 0). `display[N]` holds
the frame pointer for the active procedure at nesting level N. `EmitFramePtr(level)`
emits `global.get 0` ($sp) when `level = curNestLevel`, or `global.get level+1`
(the display entry) when accessing an upvalue from an outer scope.

### `curNestLevel` global variable

`curNestLevel` is a Pascal global initialized to 0 in `InitModule`. It is saved,
incremented, and restored around each procedure body compilation in `ParseProcDecl`.
The main program body compiles at level 0. Top-level procedures compile at level 1.
Nested procedures inside those compile at level 2, and so on. The limit is 7 (8
levels total, matching 8 display globals).

### Display save/restore local

Each user-defined procedure or function now has one extra WASM local (the "display
save local") that holds the previous value of `display[curNestLevel]`. This is
needed to support recursion: each recursive call overwrites the display slot with its
own frame pointer, and the display local restores the prior value on return.

WASM local layout:
- params at locals 0..nparams-1
- return value (functions only) at local nparams
- display save local at nparams (procedures) or nparams+1 (functions)

`AssembleCodeSection` now emits 1 i32 local for procedures and 2 i32 locals for
functions. The previous values were 0 and 1 respectively.

### Frame epilogue moved outside the exit block

In Chapter 6, the frame epilogue ($sp += curFrameSize) was emitted INSIDE the exit
block, before `OpEnd`. The `exit` intrinsic (br 0) jumps to after `OpEnd`, which
would skip the epilogue — a latent stack-pointer leak. Chapter 7 moves the display
restore AND frame epilogue to AFTER `OpEnd` (outside the exit block). `exit` now
correctly runs both the display restore and the epilogue. No existing test exercised
`exit` inside a procedure with a non-zero frame, so this bug was silent before.

### Variable level assignment

`AddSym` sets `level = scopeDepth` for all symbols. For variables (skVar), the level
must reflect `curNestLevel` (the display index) rather than `scopeDepth` (the scope
stack depth). In `ParseVarBlock`, the level is now explicitly overridden:
```pascal
syms[s].level := curNestLevel;
```
Parameter symbols in `ParseProcDecl` similarly use `curNestLevel` instead of
`scopeDepth`. Type and proc/func symbols' level fields are unused for code
generation, so they retain whatever `AddSym` assigned.

### Plan vs. Implementation Findings

**`var` block comes before nested procedure declarations, not after.**
The plan's Step 5 placed nested `ParseProcDecl` calls before `ParseVarBlock`. Pascal
syntax requires `var` before nested procedures. Both `ParseProcDecl` and
`ParseProgram` needed the order: (1) var block, (2) nested proc/func declarations,
(3) begin..end body. The plan had the order wrong for `ParseProcDecl`.

**`ParseProgram` also needed reordering.**
The plan only discussed reordering in `ParseProcDecl`. `ParseProgram` had procedures
before the var block (from Chapter 6). The nested test program declares
`var result: integer;` before `procedure Outer;`, which requires `ParseProgram` to
parse the var block first. This was fixed alongside `ParseProcDecl`. Pre-existing
Chapter 6 test programs without program-level vars were unaffected.

**Frame epilogue move was not explicitly planned, but was implied.**
The plan mentioned "epilogue is now OUTSIDE the exit block so exit runs it too" in the
Risks section but treated it as an incidental fix. In practice it was a required
structural change, not optional. Moving the epilogue and display restore outside the
exit block changes the WASM byte layout of every user function.

**`exitDepth` initialized to `-1` instead of `0` before the exit block.**
The plan set `exitDepth := 0` at the top of the body compilation block (same as
Chapter 6). The implementation correctly sets `exitDepth := -1` initially, then sets
`exitDepth := 0` right after `EmitOp(OpBlock)`. This matches the Chapter 6 behavior
(exit is invalid before the block is opened), but the plan pseudocode showed `0` in
the initialization section.

**All 18 tests pass (17 pre-existing + nested).**
No runtime surprises beyond the ordering issues above.

## Chapter 8: Strings — Plan vs. Implementation

### What matched the plan

The overall structure matched well: lazy helper reservation via `EnsureStringHelpers`,
9 string helper slots (`SlotStrAssign`..`SlotStrIns`), all helpers built as WASM functions
with `memory.copy` for bulk byte moves, `addrStrScratch` as a shared 256-byte scratch
buffer in the data segment, and stubs for unused helpers (empty local+end bodies emitted
in `AssembleCodeSection`). The type system extension (`tyString = 4`), new token kinds
(`tkStringType`, `tkLength`, `tkCopy`, `tkPos`, etc.), and `strMaxLen` field on symbol
table entries all followed the plan. String assignment via `__str_assign`, `writeln(s)`
via `__write_str`, `length(s)` inline via `i32.load8_u`, and string comparison via
`__str_compare` all matched. The Dijkstra display for nested string variables was not
required (strings are accessed via frame pointer + offset, same as integers).

### Deviations and surprises

**`concat()` required a scratch buffer, not a direct call.**
The plan sketched `concat(a, b)` as calling `__str_append(a, b)` directly. The actual
implementation uses a two-step approach: `__str_assign(scratch, 255, a)` then
`__str_append(scratch, 255, b)`, then returns `scratch` as the result address. This is
because `__str_append` is in-place (modifies dst) and `a` must not be clobbered. A
one-argument `concat(a)` path was not implemented; only two-argument concat is supported.
Multi-argument concat from the plan (`concat(a, b, c, ...)`) is also not implemented.

**WASM local index collision in all TypeIII helpers.**
Helpers with 3 parameters (`__str_append`, `__str_copy`, `__str_delete`) had their
extra locals (first scratch variable) wrongly assigned to local index 2, which is the
third parameter. Parameters occupy locals 0..N-1, so for N=3 params, extras must start
at index 3. This was not flagged in the plan's risk section. All three helpers required
fixing: locals 2/3/4/5 shifted to 3/4/5/6 (and 7 for `__str_delete`). `__str_insert`
and `__str_assign` (2-param helpers with extras starting at 2 and 3 respectively) were
already correct.

**`EnsureStringHelpers` import ordering bug.**
The plan's risk item 1 warned about `EnsureStringHelpers` ordering but focused on
user-declared functions. The actual bug was internal: `EnsureWriteInt` was called
BEFORE `fd_read` was added as an import. Since `idxWriteInt = numImports + 1` is
computed at call time, adding `fd_read` afterward shifted all defined function indices
by 1, making `idxWriteInt` point to `_start` instead of `__write_int`. Any program
that used both string operations and integer output (via `writeln(n)` or `halt`)
produced "type mismatch at end of function" WASM validation errors.
Fix: add `fd_read` import first in `EnsureStringHelpers`, then recalculate `idxWriteInt`
if `needWriteInt` was already set.

**`addrStrScratch` allocation tied to `EnsureStrCopy` and `concat` handler.**
The plan mentioned an explicit `EnsureStrScratch` call. Instead, the scratch buffer is
allocated lazily in `EnsureStrCopy` and also in the `tkConcat` handler. Since both
`copy()` and `concat()` need the same scratch buffer, the first-use allocation is
idempotent — the second caller sees `addrStrScratch >= 0` and skips allocation.

**`lastExprType` propagation through `ParseWriteArgs`.**
The plan noted the risk of `lastExprType` being overwritten by recursive calls. The
actual issue surfaced in `ParseWriteArgs`: after parsing a `copy()` or `concat()`
expression (which sets `lastExprType := tyString`), the write dispatcher correctly
routes to `__write_str`. This worked correctly because the `if lastExprType = tyString`
check immediately follows `ParseExpression` before any further parsing.

**`concat()` inside string assignment consumed correctly.**
When `t := concat(s, ', world!')` is compiled, the outer assignment emits
`[t_addr, max_len]` then calls `ParseExpression` for the RHS. The concat handler
emits two void calls and then pushes `scratch_addr` as the single result. The outer
`__str_assign(t_addr, max_len, scratch_addr)` then consumes all three values. Stack
discipline is correct.

**Two tests added (t030_string_basic, t031_string_ops), not four.**
The plan proposed t030 through t033 (basic, compare, funcs, readln). Only two tests
were added: t030 (pre-existing, covers basic assignment and write) and t031 (new,
covers concat, length, copy, pos). The compare and readln tests were not added because
the primary debugging focus was on stack correctness, and coverage of the core
operations was achieved with t031.

**All 20 tests pass (18 pre-existing + 2 new string tests).**

---

## Chapter 9: Structured Types (Records and Arrays)

### Implementation Notes

**`EmitStrAddr` reused for all composite variables.**
The existing `EmitStrAddr` procedure already handles both frame vars (offset >= 0, emits
`$sp + offset`) and param locals (offset < 0, emits `local.get`). This made it usable
for composite type address computation without modification.

**`EmitMemCopy` already existed from Chapter 8.**
Chapter 8 added `EmitMemCopy` for string operations. Chapter 9 reused it for
whole-record and whole-array assignment — no new procedure needed.

**Selector chain duplicated in ParseExpression and ParseStatement.**
The plan noted this risk. The LHS selector chain in `ParseStatement` and the RHS
selector chain in `ParseExpression` share identical logic (dot lookup, bracket index
arithmetic, comma trick). They were not factored out into a shared procedure because
doing so would require passing function pointers or restructuring the code beyond TP
compatibility. The duplication is about 40 lines in each location.

**Composite value params set isVarParam=true after prologue copy.**
After the prologue copies a composite value param into the frame, the WASM local is
updated to point to the frame copy. Setting `isVarParam := true` in the symbol table
during param declaration makes `EmitStrAddr` emit `local.get` (correct — gives the
frame copy address) rather than trying to compute `$sp + offset` (which would be wrong
for a param local). This also allows the param to be passed as a `const` to nested
calls.

**`ParseProgram` needed flexible declaration order.**
The plan assumed `type` then `var` then `procs` in ParseProgram. Pascal allows
declaration sections in any order. The test `t043_record_param` placed `var` after the
procedure declarations — this caused a compile error. Fixed by changing ParseProgram's
linear checks to a `while` loop that accepts `type`, `var`, `procedure`, or `function`
tokens in any order.

**ParseProcDecl var/type block order handled separately.**
Within a procedure body, the order is `[type] [var] [nested procs] begin...end`.
This is already sequential (type before var), matching standard Pascal — no loop needed
there. Only `ParseProgram` needed the flexible loop.

**`curSize` tracking after bracket selector.**
After processing a bracket selector in ParseExpression, `curSize` needs to reflect the
element size. For composite elements, `curSize := types[curTypeIdx].size` uses the new
`curTypeIdx` (the element type's index). For scalar elements, `curSize := 4`. This must
be done AFTER updating `curTypeIdx` to the element's type index, since
`types[curTypeIdx]` is read after the update.

**Array vars in ParseVarBlock declared with `array[...]` syntax inline.**
`ParseTypeSpec` handles inline `array[...]` syntax in var declarations — no named type
alias needed. `t037_array_basic` uses `var a: array[1..5] of integer` directly.

**All 27 tests pass (20 pre-existing + 7 new structured type tests).**
Tests: t035 (record basic), t036 (record copy), t037 (array basic), t038 (array copy),
t039 (array of records), t040 (2D array), t043 (record params: const, var, value).

---

### Plan v. Implementation

**Step 7 (ParseStatement assignment) — selector chain not factored out.**
The plan suggested a `ParseSelectorChain` procedure to share logic between ParseExpression
(read) and ParseStatement (write). Implementation kept the loops inline in each procedure.
Factoring out requires passing state by reference through procedure parameters, which adds
complexity in TP-compatible code and was judged not worth it at this stage.

**Step 8 (structured params) — `isVarParam` flag set immediately.**
The plan described the prologue copy as a post-parsing runtime step, with `isVarParam`
set after the copy. In implementation, `isVarParam := true` is set in the param
declaration loop (before parsing the body), because the symbol table is read during body
parsing and must reflect the post-prologue state from the start. The runtime copy still
happens at the correct time (after frame setup).

**`ParseProgram` declaration order — flexible loop added.**
Plan assumed fixed order. The test program `t043_record_param` placed `var` after
procedures, which is valid Pascal. A flexible `while` loop replacing the linear checks
was necessary. This deviation was discovered during testing, not during planning.

**Step 4 (`ParseTypeBlock` placement) — used as designed.**
The plan said to add `type` block handling before `var` in both ParseProgram and
ParseProcDecl. This was done exactly as planned for ParseProcDecl. ParseProgram got the
more flexible loop instead.

**Test numbering.**
The plan proposed t035–t040 plus t043 (matching tutorial numbering). Implemented exactly
that: seven tests added with those numbers.

**No `paramTypeIdxs` in `TFuncEntry` needed.**
The plan mentioned adding `paramTypeIdxs` to `TFuncEntry`. In practice, this was not
needed — `ParseCallArgs` works on value params by calling `ParseExpression`, which
naturally leaves composite addresses on the stack. The `TFuncEntry` struct was not
extended; only the local `paramTypeIdxs` array in `ParseProcDecl` was used.

---

## Chapter 10: Constants, Enumerated Types, and Case Statements

### Implementation notes

**Hex literals already done.**
The scanner already handled `$FF`-style hex literals from Chapter 8's string work.
No scanner changes were needed for Chapter 10.

**`EvalConstExpr` split into two procedures.**
The plan described `EvalConstExprP(minPrec, ...)` as the core evaluator and `EvalConstExpr`
as a wrapper. This is exactly what was implemented: `ConstBinPrec` maps operator tokens
to precedence levels, `EvalConstExprP` does precedence-climbing with a `while prec > minPrec`
loop, and `EvalConstExpr` calls `EvalConstExprP(PrecNone, ...)`.

**Enum type stored via existing `arrLo`/`arrHi` fields.**
Enum ordinal range uses `types[tIdx].arrLo` (always 0) and `types[tIdx].arrHi` (max ordinal).
Enum members are stored as `skConst` symbols with `offset` = ordinal value and `typeIdx`
pointing to the enum type descriptor. No new type descriptor fields were needed.

**Case temp local index arithmetic.**
`_start` has no params or extra locals, so `curCaseTempIdx = 0`.
Procedures set `curCaseTempIdx = nparams + 1` (display save is at `nparams`).
Functions set `curCaseTempIdx = nparams + 2` (retval at `nparams`, display save at `nparams+1`).
Save/restore of `curNeedsCaseTemp` around nested `ParseProcDecl` calls is critical
because compilation of a nested function resets the global.

**`AssembleCodeSection` case temp handling.**
For `_start`: the local header is `[00]` (no locals) or `[01 01 7F]` (1 group, 1 i32) based
on `startNeedsCaseTemp`. The `bodyLen` changes from `1 + len + 1` to `3 + len + 1`.
For user functions: the existing single local group gets its count incremented by 1
(2→3 for functions, 1→2 for procedures). The header byte count stays 3 (1-group encoding
doesn't change size when only the count changes).

**Case `else` clause bug fixed: missing `OpElse`.**
When the arm loop exits because `tokKind = tkElse`, the last arm's `if` block is open
with no `else` yet. The else clause code must go into the `else` branch of that `if`.
The fix: emit `OpElse` immediately before consuming `tkElse` and parsing the else statement.
Without this, the else clause runs unconditionally (after the if/end), ignoring the selector.

### Plan v. Implementation

**`EvalConstExpr` atomic evaluation — precedence split needed.**
The plan described the evaluator in one procedure. The initial implementation had a broken
binary loop. The fix required splitting into `EvalConstExprP(minPrec)` plus wrapper, which
the plan had anticipated but hadn't made explicit as two separate Pascal procedures.

**Missing `OpElse` for case else clause.**
The plan did not call out this detail. The code structure (emit OpElse only between arms,
not before the else clause) was wrong. Discovered and fixed during testing.

**Test t046 (hex literals) skipped.**
The plan and tutorial mention t046. Since hex literals were already implemented and tested
indirectly (constants use `$FF` notation in t045), a separate t046 test was not added.
Tests t045, t047, t048 cover all three new features.

**All 30 tests pass (27 pre-existing + 3 new Chapter 10 tests).**
Tests: t045 (const expressions), t047 (enumerated types), t048 (case statement).

---

## Retrospective: Tutorial Gaps and Lessons Learned

This section records what was missing from the tutorial, what bugs could have been
avoided with better direction, and what reference material should have been provided
from the start. It is written after reaching a self-hosting stage-2 WASM compiler.

### What the tutorial was lacking

**WASM structured control flow explained concretely.**
The tutorial named `block`/`loop`/`end` and said "`br N` counts N+1 levels inward,"
but never gave a worked example of a for-loop with break AND continue correctly
handled. That omission caused the worst bug in the project: `continue` inside a
for-loop silently skipped the increment step (br 0 targeted the loop header rather
than a point after the increment). The tutorial should have included a diagram or
pseudocode showing the required `block @exit / loop @top / block @continue / body /
end @continue / increment / br 0 @top / end @top / end @exit` nesting, with explicit
depth counts for break, continue, and exit at each level.

**Import ordering invariants not stated as an invariant.**
`EnsureWriteInt` computes `idxWriteInt = numImports + 1` at call time. Any import
added afterward shifts all defined-function indices. This constraint was discovered
and worked around three separate times (Chapters 4, 6, 8). The tutorial should have
stated once, early: "freeze imports before assigning any defined-function index;
call all `Ensure*` procedures in a fixed order in `EnsureBuiltinImports`."

**TP compatibility constraint about brace comments not visible in the code.**
The rule "never write `{` or `}` inside a `{ }` comment" is in CLAUDE.md and in
the Gotchas section but not in the chapter plans that describe code to write. Any
plan pseudocode that references `{$IMPORT}`, `{$EXPORT}`, or uses `{` in a comment
example silently breaks the compiler in TP mode. The tutorial should have flagged
every plan pseudocode block that violates this rule.

**No guidance on debugging WASM binary output.**
When something goes wrong, the only output is a binary blob. The tutorial never
mentioned: `wasm2wat` (or `wasm-objdump -d`) for disassembly, how to interpret
`wasm-validate` error messages, or how to add strategic `halt(N)` calls to narrow
down where a compiled program goes wrong. A one-page debugging appendix would have
saved hours.

**Token constant assignment strategy not given.**
The tutorial defined new token constants without specifying which numeric range was
safe to use. `tkBreak` and `tkContinue` were assigned values already taken by
`tkAnd` and `tkOr`, causing a silent conflict. The tutorial should have given a
reserved range (e.g., "user-defined keywords: 200+") or told the reader to look up
existing values before adding new ones.

**`continue` semantics in Pascal vs. WASM not distinguished.**
Pascal's `continue` means "go to the next iteration," which for a for-loop means
"run the increment, then test the condition." WASM's `br 0` from inside a `loop`
means "jump to the loop header." These are not the same when the increment is
emitted after the body. The tutorial should have called this out explicitly as a
case where Pascal semantics require an extra wrapper block.

**No mention of the display-save local's effect on WASM local indices.**
Chapter 7 added a display-save local to every procedure/function, shifting
`curCaseTempIdx` formulas. Chapter 10's `curCaseTempIdx` arithmetic (nparams+1 for
procs, nparams+2 for funcs) was derived correctly only because the display-save
was already accounted for. Without a running table of WASM local layout across
chapters, each new local addition required auditing all index arithmetic from scratch.

### Bugs that better direction would have prevented

**for-loop `continue` infinite loop (stage-1 hang).**
Root cause: the plan's for-loop structure emitted `br 0` (continue) jumping to
`@top`, skipping the increment. Fix requires wrapping the body in `block @continue`.
Prevention: a concrete WASM block nesting diagram with all three control-flow exits
labelled and counted.

**Import index shifted by late `fd_read` addition (Chapter 8).**
`EnsureWriteInt` ran before `fd_read` was imported, so `idxWriteInt` pointed to
the wrong function slot. Prevention: a clear invariant — "all imports must be
registered before any defined-function index is recorded" — stated in Chapter 4
when the pattern is first established.

**`case...else...end` wrong `br` depth (Chapter 10).**
The `break` depth inside a case-with-else arm was off by one because the implicit
else-wrapper `if` block added an extra label level not accounted for in the plan.
Prevention: a table mapping each Pascal construct to its WASM label structure,
showing exactly how many `br` levels each construct adds.

**`var`/`proc` declaration order wrong in plan (Chapter 7).**
`ParseProcDecl` in the plan put nested proc declarations before the `var` block.
Pascal syntax requires `var` before nested procs. Prevention: a formal grammar
snippet for the declaration section in the chapter plan, not just prose.

**Missing `OpElse` before case else clause (Chapter 10).**
The else clause of a case statement must be inside the `else` branch of the last
arm's WASM `if` block. Emitting it after `end` runs it unconditionally. Prevention:
an explicit "emit OpElse here" marker in the pseudocode.

**WASM local index collision in 3-param string helpers (Chapter 8).**
Extra locals in 3-parameter helpers were assigned starting at index 2 (the third
parameter), overwriting it. Prevention: a clear rule — "extra locals start at
index nparams" — stated once when the first helper with extra locals is introduced.

**`ParseProgram` declaration order assumed fixed (Chapter 9).**
The plan assumed `type` then `var` then `procs`. Valid Pascal allows any order.
A test program with `var` after a procedure declaration failed. Prevention: either
state the limitation explicitly ("we support only this order") or design the
flexible loop from the start.

### Tests and references that should have been provided from the start

**A test for `continue` inside a for-loop.**
```pascal
program forconttest;
var i, sum: integer;
begin
  sum := 0;
  for i := 1 to 10 do begin
    if (i mod 2) = 0 then continue;
    sum := sum + i;
  end;
  halt(sum);  { expect 25 }
end.
```
This would have caught the `continue`-skips-increment bug in Chapter 5, long
before the stage-1 compiler needed to compile itself.

**A test for `break` and `continue` inside nested constructs.**
```pascal
{ break inside an if inside a loop }
{ continue inside a case inside a loop }
```
These catch off-by-one br depth errors that are invisible in simple loop tests.

**A WASM binary reference card.**
A one-page reference listing: opcode bytes for all used opcodes, LEB128 encoding
rules, section IDs and their order, function-body encoding format (size, local
groups, instructions, end), and import/export entry layouts. The spec is complete
but dense; a project-scoped cheat sheet would have avoided repeated spec lookups.

**`wasm2wat` / `wasm-objdump` introduced in Chapter 1.**
Disassembling the compiler's own output should have been the first debugging tool
introduced, before any code was written. "Here is how to read what you're
producing" is as important as "here is what to produce."

**A reference Pascal program compiled with FPC to compare output.**
For each chapter milestone, provide the expected WAT (or at least the expected
section structure) for a canonical test program. Diffing against a known-good
disassembly would have narrowed down most bugs in under a minute.

**FPC `-Mtp` constraint reference.**
A table of what is and is not available in `-Mtp` mode: no `class`, no initialized
variables, no `uses`, 16-bit `integer` (use `longint`), limited string operations,
no `inc`/`dec` in all contexts, `shr`/`shl` OK, `concat()` not `+` for strings.
The tutorial mentioned these one at a time as they came up; a consolidated list
at the start would have prevented several surprises.

**A test exercising forward declarations.**
Forward-declared procedures appear in `pascom.pas` itself. A test for
`procedure Foo; forward; procedure Bar; begin Foo; end; procedure Foo; begin end;`
would have validated the forward-declaration path early and caught index-assignment
ordering issues before self-hosting compilation.
