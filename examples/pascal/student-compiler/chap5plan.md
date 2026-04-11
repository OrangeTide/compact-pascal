# Chapter 5 Implementation Plan: Control Flow

## Overview

Add `if`/`else`, `while`, `for`/`to`/`downto`, `repeat`/`until`, `break`, `continue`, and fix the `begin`/`end` compound statement to follow proper Pascal semicolon rules. All control flow maps to WASM's structured opcodes (`block`, `loop`, `if`, `else`, `br`, `br_if`).

The WASM opcodes `OpBlock`, `OpLoop`, `OpIf`, `OpElse`, `OpBr`, `OpBrIf` are already defined (lines 69–74). The tokens `tkIf`, `tkThen`, `tkElse`, `tkWhile`, `tkDo`, `tkFor`, `tkTo`, `tkDownto`, `tkRepeat`, `tkUntil` are already defined and scanned. `tkBegin`/`tkEnd` already work for compound statements but with a simpler loop. No `tkBreak` or `tkContinue` exist yet.

---

## Step 1: Add `tkBreak` and `tkContinue` token constants

In the token constants block (around line 129–151), add:

```pascal
tkBreak    = 118;
tkContinue = 119;
```

In `LookupKeyword` (around line 659–688), add:

```pascal
else if s = 'BREAK'    then LookupKeyword := tkBreak
else if s = 'CONTINUE' then LookupKeyword := tkContinue
```

---

## Step 2: Add `breakDepth` and `continueDepth` global variables

In the global variables section (around line 202–263), add two new `longint` globals:

```pascal
breakDepth:    longint;  { br label depth to exit innermost loop; -1 if none }
continueDepth: longint;  { br label depth to continue innermost loop; -1 if none }
```

Initialize both to `-1` in `InitModule` (wherever the other globals are initialized — search for `addrIovec := -1` etc.).

---

## Step 3: Add a `for`-loop limit scratch area in the data segment

The `for` loop must evaluate its limit expression once and store it. Use the data segment for this scratch word. Add a global:

```pascal
addrForLimit: longint;  { 4-byte scratch for for-loop limit; -1 until allocated }
```

Initialize to `-1` in `InitModule`. Add a lazy allocator (like `EnsureIOBuffers`):

```pascal
function EnsureForLimit: longint;
begin
  if addrForLimit < 0 then
    addrForLimit := AllocData(4);
  EnsureForLimit := addrForLimit;
end;
```

**Note**: `for` loops do not nest in Compact Pascal scope for this chapter (only one loop variable in scope at a time). A single scratch word suffices. If nested `for` loops are needed, each call to `EnsureForLimit` can allocate a new slot; for now, a single slot is fine because the tutorial does not require nested `for` loops sharing one limit cell. Consider allocating a fresh 4-byte slot per `for` (append to data, let `AllocData` grow) — but track the address in a local variable inside `ParseStatement`, not a global — to handle nesting correctly.

**Revised approach** (handles nesting): Do not use a global `addrForLimit`. Instead, inside the `tkFor` branch of `ParseStatement`, call `AllocData(4)` directly and store the returned address in a local variable `limitAddr`. This way, each nested `for` loop gets its own slot.

---

## Step 4: Fix `begin`/`end` compound statement (trailing semicolon)

The current `tkBegin` handler (line 1512–1519) uses `while tokKind <> tkEnd` which does not allow trailing semicolons before `end`. Replace with the pattern from the tutorial:

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

This also fixes `ParseProgram`'s body loop (lines 1544–1550) to use the same pattern.

---

## Step 5: Implement `if`/`else` in `ParseStatement`

Add a `tkIf` branch:

```pascal
tkIf: begin
  NextToken;
  ParseExpression(PrecNone);   { condition on stack }
  Expect(tkThen);
  EmitOp(OpIf); EmitOp(WasmVoid);
  ParseStatement;              { then branch }
  if tokKind = tkElse then begin
    NextToken;
    EmitOp(OpElse);
    ParseStatement;            { else branch }
  end;
  EmitOp(OpEnd);
end;
```

Dangling-else is handled naturally by recursion. No depth tracking needed for `break`/`continue` here because `if` uses WASM `if` opcode (not `block`/`loop`), but note: an `if` inside a loop does increase nesting depth. The `break`/`continue` depths must account for the WASM `if` block. See Step 8 for how to adjust depths when entering `if`.

**Important for break/continue inside if**: When `break` or `continue` is used inside an `if`/`else` body that is itself inside a loop, the WASM label depth increases by 1 for the `if` block. The tutorial's approach is to increment `breakDepth` and `continueDepth` before entering the if-body, and decrement after. But since WASM's `if` instruction is a block-like construct, `br` labels inside it count the `if` as depth 0. Therefore, before `ParseStatement` for the then/else branches, increment both depths by 1; after `OpEnd`, decrement by 1.

**Revised (simpler) approach**: Let `ParseStatement` handle this by bumping depths around the `if` body:

```pascal
tkIf: begin
  NextToken;
  ParseExpression(PrecNone);
  Expect(tkThen);
  EmitOp(OpIf); EmitOp(WasmVoid);
  if breakDepth >= 0 then inc(breakDepth);
  if continueDepth >= 0 then inc(continueDepth);
  ParseStatement;
  if tokKind = tkElse then begin
    NextToken;
    EmitOp(OpElse);
    ParseStatement;
  end;
  if breakDepth > 0 then dec(breakDepth);
  if continueDepth > 0 then dec(continueDepth);
  EmitOp(OpEnd);
end;
```

---

## Step 6: Implement `while` in `ParseStatement`

```pascal
tkWhile: begin
  NextToken;
  EmitOp(OpBlock); EmitOp(WasmVoid);   { outer block = break target (depth 1) }
  EmitOp(OpLoop);  EmitOp(WasmVoid);   { inner loop  = continue target (depth 0) }
  { save and set break/continue depths }
  oldBreak    := breakDepth;
  oldContinue := continueDepth;
  breakDepth    := 1;   { br 1 exits outer block }
  continueDepth := 0;   { br 0 re-enters loop }
  ParseExpression(PrecNone);
  Expect(tkDo);
  EmitOp(OpI32Eqz);
  EmitOp(OpBrIf); EmitULEB128(startCode, 1);  { exit if NOT condition }
  ParseStatement;                               { loop body }
  EmitOp(OpBr); EmitULEB128(startCode, 0);     { back to loop }
  EmitOp(OpEnd);                               { end loop }
  EmitOp(OpEnd);                               { end block }
  breakDepth    := oldBreak;
  continueDepth := oldContinue;
end;
```

Declare `oldBreak` and `oldContinue` as `longint` locals inside `ParseStatement` (or use a single pair since Pascal allows local `var` blocks at procedure/function level — in TP mode, declare them at the top of the `var` block for `ParseStatement`).

---

## Step 7: Implement `for` in `ParseStatement`

```pascal
tkFor: begin
  NextToken;
  { get loop variable }
  if tokKind <> tkIdent then Error('expected variable in for');
  sym := LookupSym(tokText);
  if sym < 0 then Error('undefined variable in for');
  NextToken;
  Expect(tkAssign);
  { emit initial value and store in loop variable }
  ParseExpression(PrecNone);
  EmitVarStore(sym);                          { store initial value }
  { determine direction }
  if tokKind = tkTo then
    isDownto := false
  else if tokKind = tkDownto then
    isDownto := true
  else
    Error('expected TO or DOWNTO in for');
  NextToken;
  { evaluate limit once, store in data segment scratch }
  limitAddr := AllocData(4);
  ParseExpression(PrecNone);
  EmitI32Const(limitAddr);
  EmitOp(OpI32Store); EmitOp($02); EmitOp($00);  { store limit }
  { emit block/loop }
  EmitOp(OpBlock); EmitOp(WasmVoid);
  EmitOp(OpLoop);  EmitOp(WasmVoid);
  oldBreak    := breakDepth;
  oldContinue := continueDepth;
  breakDepth    := 1;
  continueDepth := 0;
  { test: if counter > limit (to) or counter < limit (downto), exit }
  EmitVarLoad(sym);
  EmitI32Const(limitAddr);
  EmitOp(OpI32Load); EmitOp($02); EmitOp($00);
  if isDownto then
    EmitOp(OpI32LtS)   { exit if i < limit }
  else
    EmitOp(OpI32GtS);  { exit if i > limit }
  EmitOp(OpBrIf); EmitULEB128(startCode, 1);
  Expect(tkDo);
  ParseStatement;                             { body }
  { increment or decrement counter }
  EmitVarLoad(sym);
  EmitI32Const(1);
  if isDownto then
    EmitOp(OpI32Sub)
  else
    EmitOp(OpI32Add);
  EmitVarStore(sym);
  EmitOp(OpBr); EmitULEB128(startCode, 0);   { back to loop }
  EmitOp(OpEnd);
  EmitOp(OpEnd);
  breakDepth    := oldBreak;
  continueDepth := oldContinue;
end;
```

`EmitVarLoad` and `EmitVarStore` are inline sequences using the variable's frame offset (via `symEntry[sym].offset`). These already exist in the codebase (used in assignment and expression parsing) — extract or duplicate as needed, or call the existing emit sequences directly.

**Data segment note**: `AllocData(4)` grows the data segment each time `for` is parsed. For the tests in this chapter this is fine. The data segment only grows, never shrinks, so nested `for` loops each get their own slot.

**EmitI32Store / EmitI32Load for limit**: Use existing `EmitI32Store` and `EmitI32Load` helpers (check their signatures — they take alignment and offset params). The limit cell is at a fixed data segment address with offset 0, alignment 2.

---

## Step 8: Implement `repeat`/`until` in `ParseStatement`

```pascal
tkRepeat: begin
  NextToken;
  EmitOp(OpLoop); EmitOp(WasmVoid);   { loop = continue target }
  oldBreak    := breakDepth;
  oldContinue := continueDepth;
  breakDepth    := -1;   { repeat/until has no outer block for break }
  continueDepth := 0;
  { parse body: one or more statements separated by semicolons }
  ParseStatement;
  while tokKind = tkSemicolon do begin
    NextToken;
    if tokKind <> tkUntil then
      ParseStatement;
  end;
  Expect(tkUntil);
  ParseExpression(PrecNone);           { condition }
  EmitOp(OpI32Eqz);                   { loop if NOT condition }
  EmitOp(OpBrIf); EmitULEB128(startCode, 0);
  EmitOp(OpEnd);
  breakDepth    := oldBreak;
  continueDepth := oldContinue;
end;
```

**Note on `break` inside `repeat`/`until`**: The tutorial does not mention `break` inside `repeat`/`until`. Since there is no outer `block`, a bare `br` cannot exit the loop without one. If `break` inside `repeat` is needed, wrap it in a `block`/`loop` pair (like `while`). For now, set `breakDepth := -1` so that `break` inside `repeat` triggers an error.

**Revised**: To support `break` inside `repeat`, wrap with a block:

```pascal
EmitOp(OpBlock); EmitOp(WasmVoid);
EmitOp(OpLoop);  EmitOp(WasmVoid);
breakDepth    := 1;
continueDepth := 0;
...
EmitOp(OpEnd);  { end loop }
EmitOp(OpEnd);  { end block }
```

Follow the tutorial's code (which uses only `loop` without an outer `block`) if `break` inside `repeat` is not required for the chapter tests. Use the simpler form.

---

## Step 9: Implement `break` and `continue` in `ParseStatement`

```pascal
tkBreak: begin
  NextToken;
  if breakDepth < 0 then
    Error('break outside of loop');
  EmitOp(OpBr);
  EmitULEB128(startCode, breakDepth);
end;

tkContinue: begin
  NextToken;
  if continueDepth < 0 then
    Error('continue outside of loop');
  EmitOp(OpBr);
  EmitULEB128(startCode, continueDepth);
end;
```

---

## Step 10: Adjust depth tracking when entering WASM blocks in `if`

When an `if`/`else` is parsed inside a loop, the WASM `if` instruction creates a new label scope. `break`/`continue` labels inside the then/else body must be incremented. The revised Step 5 code handles this.

Similarly, any nested loop increments depths correctly because each loop resets depths to absolute values (1 and 0 for the new loop's block/loop pair) and restores saved values on exit.

**Careful**: When a `for` or `while` body contains an `if`, the `if` handler increments the loop's `breakDepth` and `continueDepth`. When the `if` ends, it decrements them. This is correct only if the if-handler checks `>= 0` before incrementing and `> 0` before decrementing (to avoid corrupting -1 sentinel). The Step 5 code does this.

---

## Step 11: `ParseStatement` local variable declarations

`ParseStatement` needs several new local variables. Add at the top of its `var` block:

```pascal
var
  oldBreak, oldContinue: longint;
  sym: longint;
  limitAddr: longint;
  isDownto: boolean;
```

---

## Step 12: Helper for variable load/store sequences

The `for` loop needs to load and store the loop variable by symbol index. Check how assignment currently emits these sequences (around line 1474–1492). The pattern is:

**Load** (`EmitVarLoad`):
```pascal
EmitGlobalGet(0);                   { $sp }
EmitI32Const(symEntry[sym].offset);
EmitOp(OpI32Add);
EmitI32Load(2, 0);                  { load i32, align=2, offset=0 }
```

**Store** (`EmitVarStore`):
```pascal
EmitGlobalGet(0);
EmitI32Const(symEntry[sym].offset);
EmitOp(OpI32Add);
{ value already on stack from ParseExpression }
EmitI32Store(2, 0);
```

For the `for` loop, note the store order: value is on the stack when the address sequence runs, so use the address-first / value-second form, or use `i32.store` which expects `(address, value)` — check the existing `EmitI32Store` calls to confirm argument order.

---

## Step 13: Tests to add

### `tests/ifelse.pas` — basic if/else

```pascal
program ifelse;
var x: integer;
begin
  x := 7;
  if x > 5 then
    halt(1)
  else
    halt(0)
end.
```
Expected exit code: 1. Test target: `test-strap-ifelse`.

### `tests/whileloop.pas` — factorial via while

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
Expected exit code: 120. Test target: `test-strap-fact5`.

### `tests/forloop.pas` — sum via for

```pascal
program forsum;
var i, s: integer;
begin
  s := 0;
  for i := 1 to 10 do
    s := s + i;
  halt(s)
end.
```
Expected exit code: 55. Test target: `test-strap-forsum`.

### `tests/repeatloop.pas` — repeat/until

```pascal
program repeattest;
var n: integer;
begin
  n := 1;
  repeat
    n := n * 2
  until n >= 64;
  halt(n)
end.
```
Expected exit code: 64. Test target: `test-strap-repeattest`.

### `tests/fizzbuzz.pas` + `tests/fizzbuzz.expected` — integration test

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
Expected output: lines 1–20, with Fizz/Buzz/FizzBuzz substitutions. Generate `fizzbuzz.expected` by running the test once with a known-good compiler. Test target: `test-strap-fizzbuzz`.

---

## Step 14: Makefile additions

Add to the `test:` dependency list:
```
test-strap-ifelse test-strap-fact5 test-strap-forsum test-strap-repeattest test-strap-fizzbuzz
```

Add exit-code test targets (pattern like `test-strap-calc`):
```makefile
test-strap-ifelse: build/bootstrap/tests/ifelse.wasm
	wasmtime $< ; test $$? -eq 1

test-strap-fact5: build/bootstrap/tests/fact5.wasm
	wasmtime $< ; test $$? -eq 120

test-strap-forsum: build/bootstrap/tests/forsum.wasm
	wasmtime $< ; test $$? -eq 55

test-strap-repeattest: build/bootstrap/tests/repeattest.wasm
	wasmtime $< ; test $$? -eq 64
```

Add output test target (pattern like `test-strap-hello`):
```makefile
test-strap-fizzbuzz: build/bootstrap/tests/fizzbuzz.wasm tests/fizzbuzz.expected
	wasmtime $< | diff - tests/fizzbuzz.expected
```

---

## Implementation Order

1. Add token constants (`tkBreak`, `tkContinue`) and scanner keywords.
2. Add global variables (`breakDepth`, `continueDepth`); initialize to -1 in `InitModule`.
3. Fix `begin`/`end` compound statement (trailing semicolon).
4. Add `ParseStatement` local vars (`oldBreak`, `oldContinue`, `sym`, `limitAddr`, `isDownto`).
5. Implement `tkIf` (with depth adjustments).
6. Implement `tkWhile`.
7. Implement `tkFor`.
8. Implement `tkRepeat`.
9. Implement `tkBreak` and `tkContinue`.
10. Rebuild bootstrap: `fpc -Mtp -obuild/native/pascom pascom.pas`.
11. Add test `.pas` files and `.expected` files.
12. Update Makefile.
13. Run `make test`.

---

## Known Gotchas

- **No `{` or `}` inside brace comments** — use words for Pascal examples in source comments.
- **`longint` everywhere** — TP `integer` is 16-bit; use `longint` for `breakDepth`, `continueDepth`, etc.
- **`for` variable must be a declared local `longint`** — no type checking needed yet, but don't accidentally look up a string variable.
- **`EmitI32Store` argument order** — the store helper likely pushes address then value; the `for` limit store needs to push the address (data address constant) before the limit value from `ParseExpression`. Check the existing store pattern: if it uses `EmitGlobalGet` first (address) and leaves the value on stack from a prior expression, the `for` limit store must push the limit into a local or reorder. The safest approach: evaluate limit with `ParseExpression` (leaves value on stack), then use a local `i32.set`/`i32.get` local variable — but TP Pascal has no WASM locals exposed. Instead, use a scratch data segment address: emit the limit store before the loop block, not inside. The plan above does this correctly.
- **Depth tracking when `if` is inside a loop**: The depth adjustment in Step 5 must only adjust when `breakDepth >= 0` (i.e., inside a loop). The guarded `inc`/`dec` in Step 5 handles this.
- **`repeat`/`until` multi-statement body**: Unlike `while`, `repeat` allows multiple statements without `begin`/`end`. The loop in Step 8 handles this.
