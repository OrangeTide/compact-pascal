# Chapter 7 Implementation Plan: Nested Scopes

## Goal

Add support for nested procedure/function declarations using the Dijkstra display
technique. An inner procedure can read and write local variables of any enclosing
procedure through a fixed-size array of frame pointers (the "display") stored in
WASM globals.

## Background

Current state (Chapter 6):

- One WASM global: global 0 = $sp (stack pointer, mutable i32, init 65536).
- `EmitFramePtr(level)` always emits `global.get 0` ($sp), ignoring the level.
- `ParseProgram` has a `while proc/func` loop; `ParseProcDecl` does not — nested
  procedure declarations inside a procedure body are not yet supported.
- The `level` field in `TSymEntry` is set to `scopeDepth` by `AddSym`, but is not
  used for code generation (EmitFramePtr ignores it).
- Frame prologue and epilogue are emitted INSIDE the exit block; `exit` skips the
  epilogue (latent bug, tests do not exercise it).

Chapter 7 fixes all of this.

## Data Model

### Display globals

Add 8 display globals, one per nesting level:

| Global index | Meaning             | Init value |
|---|---|---|
| 0            | $sp (stack pointer) | 65536      |
| 1            | display[0]          | 0          |
| 2            | display[1]          | 0          |
| ...          | ...                 | 0          |
| 8            | display[7]          | 0          |

`display[N]` holds the frame pointer (value of $sp after frame allocation) for the
currently executing procedure at nesting level N.

### `curNestLevel` global variable

Add a global Pascal variable `curNestLevel: longint` initialized to 0 in
`InitModule`. It tracks the nesting level currently being compiled:

- Main program body: curNestLevel = 0
- Top-level procedure body: curNestLevel = 1
- Procedure nested inside that: curNestLevel = 2
- (max supported: 7, matching display[0..7])

### Display save local per procedure

Each user-defined procedure or function gets one extra WASM local to save the
previous value of `display[curNestLevel]` so the display slot can be restored on
exit (enabling correct behavior under recursion).

WASM local layout per procedure:

| Local index       | Purpose                                    |
|---|---|
| 0 .. nparams-1    | Parameters                                 |
| nparams           | Return value (functions only, i32)         |
| nparams (proc)    | Display save local (i32)                   |
| nparams+1 (func)  | Display save local (i32)                   |

Let `displayLocalIdx := nparams + (1 if func else 0)`.

### Variable level assignment

`AddSym` currently sets `level = scopeDepth`. For Chapter 7, variables (skVar)
must record `curNestLevel` as their level, not `scopeDepth`. The change:

In `ParseVarBlock`, after `AddSym`, explicitly set:
```pascal
syms[s].level := curNestLevel;
```

In `ParseProcDecl`, for parameters, change:
```pascal
syms[j].level := scopeDepth;
```
to:
```pascal
syms[j].level := curNestLevel;
```

Type symbols (skType) and proc/func symbols (skProc/skFunc) have a `level` field
but it is not used for code generation, so `scopeDepth` is still fine for them.

## Step-by-Step Changes

### Step 1: Add `curNestLevel` global variable

In the global variables block (after `currentFuncSlot`):
```pascal
curNestLevel: longint;  { nesting level being compiled; 0 = main program }
```

Initialize in `InitModule`:
```pascal
curNestLevel := 0;
```

### Step 2: `AssembleGlobalSection` — emit 9 globals

Replace the current single-global emission with:

```pascal
procedure AssembleGlobalSection;
var i: longint;
begin
  SmallBufInit(secGlobal);
  SmallBufEmit(secGlobal, 9);    { 9 globals total }
  { Global 0: $sp (stack pointer), mutable i32, init 65536 }
  SmallBufEmit(secGlobal, $7F);  { type: i32 }
  SmallBufEmit(secGlobal, 1);    { mutable }
  SmallBufEmit(secGlobal, $41);  { i32.const }
  SmallBufEmit(secGlobal, $80);
  SmallBufEmit(secGlobal, $80);
  SmallBufEmit(secGlobal, $04);  { 65536 in SLEB128 }
  SmallBufEmit(secGlobal, $0B);  { end }
  { Globals 1-8: display[0..7], mutable i32, init 0 }
  for i := 1 to 8 do begin
    SmallBufEmit(secGlobal, $7F);  { type: i32 }
    SmallBufEmit(secGlobal, 1);    { mutable }
    SmallBufEmit(secGlobal, $41);  { i32.const }
    SmallBufEmit(secGlobal, 0);    { 0 }
    SmallBufEmit(secGlobal, $0B);  { end }
  end;
end;
```

### Step 3: `EmitFramePtr` — use display for upvalue access

```pascal
procedure EmitFramePtr(level: longint);
begin
  if level = curNestLevel then
    EmitGlobalGet(0)           { same level: use $sp directly }
  else
    EmitGlobalGet(level + 1);  { upvalue: display[level] = global level+1 }
end;
```

### Step 4: Variable level assignment

In `ParseVarBlock`, after the `AddSym` call and the `syms[s].size` and
`syms[s].offset` lines, add:
```pascal
syms[s].level := curNestLevel;
```

In `ParseProcDecl`, in the parameter-declaration loop, change
`syms[j].level := scopeDepth` to `syms[j].level := curNestLevel`.

### Step 5: `ParseProcDecl` — nested scope support

Add these local variables to `ParseProcDecl`:
```pascal
savedNestLevel:  longint;
displayLocalIdx: longint;
```

**Where to increment `curNestLevel`**: immediately before the body compilation
block (same place as `EnterScope`). This way nested `ParseProcDecl` calls that
appear in the body see the incremented level.

The body compilation block, restructured for Chapter 7:

```pascal
savedNestLevel   := curNestLevel;
curNestLevel     := curNestLevel + 1;

{ Compile the body using swap-startCode approach }
savedCode  := startCode;
savedFrame := curFrameSize;
savedBreak := breakDepth;
savedCont  := continueDepth;
savedExit  := exitDepth;
currentFuncSlot := fslot;
CodeBufInit(startCode);
curFrameSize  := 0;
breakDepth    := -1;
continueDepth := -1;
exitDepth     := -1;

EnterScope;
{ Declare parameters as WASM locals (negative offset encoding) }
for i := 0 to nparams - 1 do begin
  j := AddSym(paramNames[i], skVar, paramTypes[i]);
  syms[j].offset       := -(i + 1);
  syms[j].size         := paramSizes[i];
  syms[j].isVarParam   := paramIsVar[i];
  syms[j].isConstParam := paramIsConst[i];
  syms[j].level        := curNestLevel;
end;

{ Parse nested procedure/function declarations }
while (tokKind = tkProcedure) or (tokKind = tkFunction) do
  ParseProcDecl;

{ Parse optional local variable block }
if tokKind = tkVar then begin
  NextToken;
  ParseVarBlock;
end;

{ displayLocalIdx: first WASM local after params (and return local for funcs) }
if isFunc then
  displayLocalIdx := nparams + 1
else
  displayLocalIdx := nparams;

{ Save display[curNestLevel] into display save local }
EmitGlobalGet(curNestLevel + 1);
EmitLocalSet(displayLocalIdx);

{ Emit outer block -- the exit target; br 0 jumps to after end }
EmitOp(OpBlock); EmitOp(WasmVoid);
exitDepth := 0;

{ Frame prologue: $sp -= curFrameSize }
if curFrameSize > 0 then begin
  EmitGlobalGet(0);
  EmitI32Const(curFrameSize);
  EmitOp(OpI32Sub);
  EmitGlobalSet(0);
end;

{ Set display[curNestLevel] := $sp (our frame pointer) }
EmitGlobalGet(0);
EmitGlobalSet(curNestLevel + 1);

{ Parse body }
Expect(tkBegin);
ParseStatement;
while tokKind = tkSemicolon do begin
  NextToken;
  if tokKind <> tkEnd then
    ParseStatement;
end;
Expect(tkEnd);

EmitOp(OpEnd);  { end block (exit target) }

{ Restore display[curNestLevel] from display save local }
EmitLocalGet(displayLocalIdx);
EmitGlobalSet(curNestLevel + 1);

{ Frame epilogue: $sp += curFrameSize  (now OUTSIDE the exit block) }
if curFrameSize > 0 then begin
  EmitGlobalGet(0);
  EmitI32Const(curFrameSize);
  EmitOp(OpI32Add);
  EmitGlobalSet(0);
end;

{ For functions: push return value local onto stack }
if isFunc then
  EmitLocalGet(nparams);

LeaveScope;

{ Store instruction bytes in funcBodies }
funcs[fslot].bodyStart := funcBodies.len;
funcs[fslot].bodyLen   := startCode.len;
for i := 0 to startCode.len - 1 do
  CodeBufEmit(funcBodies, startCode.data[i]);

{ Restore compilation context }
startCode       := savedCode;
curFrameSize    := savedFrame;
breakDepth      := savedBreak;
continueDepth   := savedCont;
exitDepth       := savedExit;
currentFuncSlot := -1;
curNestLevel    := savedNestLevel;
```

Note: the epilogue is now OUTSIDE the exit block. `exit` (br 0) jumps past the
`end block`, then the display restore and epilogue still run. This fixes the latent
Chapter 6 bug where `exit` from a proc with a stack frame would leak stack space.

### Step 6: `ParseProgram` — set display[0]

After the frame prologue in `ParseProgram`, add:
```pascal
{ Set display[0] := $sp for the main program frame }
EmitGlobalGet(0);
EmitGlobalSet(1);
```

No save/restore needed: the main program runs once and never returns to a caller.

### Step 7: `AssembleCodeSection` — extra local for display save

Change the user-function locals emission:

```pascal
{ User function bodies }
for j := 0 to numFuncs - 1 do begin
  if funcs[j].retType <> 0 then begin
    localBytes := 5;  { 1 group: 2 x i32 (return value + display save) }
  end else begin
    localBytes := 3;  { 1 group: 1 x i32 (display save) }
  end;
  bodyLen := localBytes + funcs[j].bodyLen + 1;
  EmitULEB128(secCode, bodyLen);
  if funcs[j].retType <> 0 then begin
    CodeBufEmit(secCode, 1);    { 1 local group }
    CodeBufEmit(secCode, 2);    { 2 locals }
    CodeBufEmit(secCode, $7F);  { i32 }
  end else begin
    CodeBufEmit(secCode, 1);    { 1 local group }
    CodeBufEmit(secCode, 1);    { 1 local }
    CodeBufEmit(secCode, $7F);  { i32 }
  end;
  for i := funcs[j].bodyStart to funcs[j].bodyStart + funcs[j].bodyLen - 1 do
    CodeBufEmit(secCode, funcBodies.data[i]);
  CodeBufEmit(secCode, $0B);  { end }
end;
```

Previously:
- Procedure: `localBytes = 1` (0 local groups)
- Function:  `localBytes = 3` (1 group, 1 i32)

After:
- Procedure: `localBytes = 3` (1 group, 1 i32)
- Function:  `localBytes = 5` (1 group, 2 i32)

### Step 8: Test program and expected output

Create `tests/nested.pas`:

```pascal
program nested;
var result: integer;

procedure Outer;
var a: integer;

  procedure Inner;
  var b: integer;
  begin
    b := 10;
    a := a + b;
    result := a;
  end;

begin
  a := 32;
  Inner;
end;

procedure Accumulate(n: integer);
var local_n: integer;

  procedure AddToTotal;
  begin
    result := result + local_n;
  end;

begin
  local_n := n;
  if n > 0 then begin
    AddToTotal;
    Accumulate(n - 1);
  end;
end;

begin
  result := 0;
  Outer;
  writeln(result);
  result := 0;
  Accumulate(5);
  writeln(result);
end.
```

Expected output (`tests/nested.expected`):
```
42
15
```

Add Makefile target `test-strap-nested` and add it to the `test:` dependency list.

## Risks and Notes

### `exit` epilogue bug fixed
Moving the epilogue OUTSIDE the exit block (after `OpEnd`) means `exit` now
correctly restores $sp. Pre-existing tests that use `exit` in procedures without
frame variables are unaffected (the epilogue does nothing when curFrameSize=0).
Tests with `exit` inside procs WITH frame vars would have failed before; they now
work.

### `curNestLevel` bounds check
Adding a check `if curNestLevel > 7 then Error(...)` prevents misuse beyond 8
levels deep. The limit matches the 8 display globals (display[0..7] = globals 1-8).

### `scopeDepth` vs `curNestLevel`
These are intentionally different. `scopeDepth` controls which symbols are visible
in `LookupSym` / `EnterScope` / `LeaveScope`. `curNestLevel` controls which display
slot to use for frame pointer access. The two move together at procedure boundaries,
but `scopeDepth` could in principle increase inside a single block if begin/end scopes
were added later.

### `AddSym` level field
`AddSym` sets `level = scopeDepth`. We override the level explicitly for
variables (in `ParseVarBlock`) and parameters (in `ParseProcDecl`) using
`curNestLevel`. Type symbols and proc/func symbols do not need an accurate level.

### Main program sets display[0] but never restores
Main program sets `display[0] := $sp` so nested procedures (level 1) can access
main-level variables via upvalue. There is no restore because the program exits
when main ends.

### Forward declarations still work
`ParseProcDecl` increments `curNestLevel` only when compiling the body, not when
processing the forward declaration stub. The forward decl path exits early (before
the body block). When the body is later supplied, `curNestLevel` is properly set
from the surrounding context.

## Execution Order

1. Write `chap7plan.md` (this file).
2. Commit plan.
3. Implement steps 1-7 in `pascom.pas`.
4. Create `tests/nested.pas` and `tests/nested.expected`.
5. Update `Makefile` with `test-strap-nested`.
6. Bootstrap: `fpc -Mtp -obuild/native/pascom pascom.pas`
7. Run tests: `make test`
8. Update `NOTES.md`.
9. Commit `pascom.pas` and `NOTES.md`.
