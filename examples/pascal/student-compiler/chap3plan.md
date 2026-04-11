# Chapter 3 Implementation Plan: Expressions and Code Generation

## Goal

By the end of Chapter 3, the compiler handles:

```pascal
program calc;
begin
  halt(6 * 7)
end.
```

Running the compiled program exits with code 42. The chapter adds:

- Precedence-climbing expression parser (Pratt-style)
- WASM code generation for integer arithmetic and comparisons
- `halt(expr)` intrinsic via WASI `proc_exit`
- Lazy WASI import mechanism (secImport built from importsBuf)
- Statement parsing in ParseProgram

## Current State (end of Chapter 2)

- Scanner: complete — identifiers, keywords, integers, hex, strings, char constants,
  two-word operators
- Parser: handles only `program P; begin end.`
- `startCode` buffer exists but nothing is ever emitted into it
- `tokInt` is set by the scanner but never read (noted in NOTES.md)
- `WriteModule` assembles a valid empty _start function

## What Does NOT Change

- All scanner code
- Buffer infrastructure (SmallBuf, CodeBuf, LEB128 emitters)
- Type section, function section, memory section, global section, export section assembly
- `Expect`, `Error` procedures
- `ParseProgram` signature (only its body changes)

---

## Step 1: New Constants

Add to the const section, after the existing WASM opcodes:

```pascal
{ WASM opcodes - Chapter 3 }
OpCall     = $10;
OpDrop     = $1A;
OpI32Eqz   = $45;
OpI32Eq    = $46;
OpI32Ne    = $47;
OpI32LtS   = $48;
OpI32GtS   = $4A;
OpI32LeS   = $4C;
OpI32GeS   = $4E;
OpI32Add   = $6A;
OpI32Sub   = $6B;
OpI32Mul   = $6C;
OpI32DivS  = $6D;
OpI32RemS  = $6F;
OpI32And   = $71;
OpI32Or    = $72;
OpI32Xor   = $73;

{ Precedence levels for ParseExpression }
PrecNone    = 0;
PrecOrElse  = 1;
PrecAndThen = 2;
PrecCompare = 3;
PrecAdd     = 4;
PrecMul     = 5;
PrecUnary   = 6;

{ WASM type indices }
TypeVoidVoid = 0;  { () -> ()   used for _start }
TypeI32Void  = 1;  { (i32) -> () used for proc_exit }
```

`TypeVoidVoid` is already implicitly type 0 — naming it makes intent clearer.

---

## Step 2: New Global Variables

Add to the var block:

```pascal
idxProcExit: longint;   { function index of proc_exit; -1 until imported }
importsBuf:  TSmallBuf; { raw import entry bytes, without count prefix }
```

---

## Step 3: Update InitModule

In `InitModule`, add after the existing body:

```pascal
{ Chapter 3: init import state }
idxProcExit := -1;
SmallBufInit(importsBuf);

{ Register type 1: (i32) -> () for proc_exit }
wasmTypes[1].nparams     := 1;
wasmTypes[1].params[0]   := WasmI32;
wasmTypes[1].nresults    := 0;
numWasmTypes := 2;
```

`AssembleTypeSection` already iterates 0..numWasmTypes-1, so type 1 is picked up
automatically.

---

## Step 4: AssembleImportSection

Add a new section-assembly procedure (alongside the others):

```pascal
procedure AssembleImportSection;
var i: longint;
begin
  SmallBufInit(secImport);
  if numImports = 0 then exit;
  SmallEmitULEB128(secImport, numImports);
  for i := 0 to importsBuf.len - 1 do
    SmallBufEmit(secImport, importsBuf.data[i]);
end;
```

In `WriteModule`, replace:

```pascal
SmallBufInit(secImport);  { no imports in Chapter 1 }
```

with:

```pascal
AssembleImportSection;
```

`WriteSection` already skips empty sections (`if buf.len = 0 then exit`), so programs
that don't use `halt` still produce a module without an import section.

---

## Step 5: AddImport and EnsureProcExit

Add to the { ---- Code Generation ---- } section:

```pascal
function AddImport(const modname, fieldname: string; typeIdx: longint): longint;
var i: longint;
begin
  SmallBufEmit(importsBuf, length(modname));
  for i := 1 to length(modname) do
    SmallBufEmit(importsBuf, ord(modname[i]));
  SmallBufEmit(importsBuf, length(fieldname));
  for i := 1 to length(fieldname) do
    SmallBufEmit(importsBuf, ord(fieldname[i]));
  SmallBufEmit(importsBuf, 0);             { import kind: function }
  SmallEmitULEB128(importsBuf, typeIdx);
  AddImport := numImports;
  numImports := numImports + 1;
end;

function EnsureProcExit: longint;
begin
  if idxProcExit < 0 then
    idxProcExit := AddImport('wasi_snapshot_preview1', 'proc_exit', TypeI32Void);
  EnsureProcExit := idxProcExit;
end;
```

**Function index arithmetic:** imported functions get indices 0..numImports-1; defined
functions start at numImports. `AssembleExportSection` already emits
`SmallEmitULEB128(secExport, numImports)` for the _start index — this is correct
regardless of how many imports exist.

---

## Step 6: Instruction Emitters

Add low-level emit helpers (these emit into `startCode`):

```pascal
procedure EmitOp(op: byte);
begin
  CodeBufEmit(startCode, op);
end;

procedure EmitI32Const(n: longint);
begin
  CodeBufEmit(startCode, OpI32Const);  { ;; WAT: i32.const n }
  EmitSLEB128(startCode, n);
end;

procedure EmitCall(funcIdx: longint);
begin
  CodeBufEmit(startCode, OpCall);      { ;; WAT: call funcIdx }
  EmitULEB128(startCode, funcIdx);
end;
```

---

## Step 7: Forward Declarations

Add to { ---- Forward declarations ---- } section (create this section if not present):

```pascal
procedure ParseExpression(minPrec: longint); forward;
procedure ParseStatement; forward;
```

Both are mutually recursive: `ParseExpression` calls itself for subexpressions;
`ParseStatement` calls `ParseExpression` for halt's argument and calls itself for
compound `begin...end` blocks.

---

## Step 8: ParseExpression

Full body, placed before ParseStatement:

```pascal
procedure ParseExpression(minPrec: longint);
{** Pratt-style precedence climbing. Parses an expression at the given
  minimum precedence level, emitting WASM instructions as it goes. }
var
  prec: longint;
  op:   longint;
begin
  { --- Prefix --- }
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
      EmitOp(OpI32Mul);   { ;; WAT: i32.const -1; i32.mul }
    end;
    tkPlus: begin
      NextToken;
      ParseExpression(PrecUnary);
      { unary plus is a no-op }
    end;
    tkNot: begin
      NextToken;
      ParseExpression(PrecUnary);
      EmitI32Const(-1);
      EmitOp(OpI32Xor);   { ;; WAT: i32.const -1; i32.xor  (bitwise NOT) }
    end;
  else
    Error('expected expression');
  end;

  { --- Infix --- }
  while true do begin
    op := tokKind;
    case op of
      tkOrElse:  prec := PrecOrElse;
      tkAndThen: prec := PrecAndThen;
      tkEq:      prec := PrecCompare;
      tkNe:      prec := PrecCompare;
      tkLt:      prec := PrecCompare;
      tkGt:      prec := PrecCompare;
      tkLe:      prec := PrecCompare;
      tkGe:      prec := PrecCompare;
      tkPlus:    prec := PrecAdd;
      tkMinus:   prec := PrecAdd;
      tkOr:      prec := PrecAdd;
      tkStar:    prec := PrecMul;
      tkDiv:     prec := PrecMul;
      tkMod:     prec := PrecMul;
      tkAnd:     prec := PrecMul;
    else
      break;
    end;

    if prec <= minPrec then
      break;

    NextToken;
    ParseExpression(prec);

    case op of
      tkPlus:    EmitOp(OpI32Add);   { ;; WAT: i32.add }
      tkMinus:   EmitOp(OpI32Sub);   { ;; WAT: i32.sub }
      tkStar:    EmitOp(OpI32Mul);   { ;; WAT: i32.mul }
      tkDiv:     EmitOp(OpI32DivS);  { ;; WAT: i32.div_s }
      tkMod:     EmitOp(OpI32RemS);  { ;; WAT: i32.rem_s }
      tkAnd:     EmitOp(OpI32And);   { ;; WAT: i32.and }
      tkOr:      EmitOp(OpI32Or);    { ;; WAT: i32.or }
      tkAndThen: EmitOp(OpI32And);   { ;; WAT: i32.and (short-circuit folded at scan time) }
      tkOrElse:  EmitOp(OpI32Or);    { ;; WAT: i32.or }
      tkEq:      EmitOp(OpI32Eq);    { ;; WAT: i32.eq }
      tkNe:      EmitOp(OpI32Ne);    { ;; WAT: i32.ne }
      tkLt:      EmitOp(OpI32LtS);   { ;; WAT: i32.lt_s }
      tkGt:      EmitOp(OpI32GtS);   { ;; WAT: i32.gt_s }
      tkLe:      EmitOp(OpI32LeS);   { ;; WAT: i32.le_s }
      tkGe:      EmitOp(OpI32GeS);   { ;; WAT: i32.ge_s }
    end;
  end;
end;
```

**Precedence table:**

| Level | Operators | Notes |
|---|---|---|
| 1 | `or else` | lowest |
| 2 | `and then` | |
| 3 | `=`, `<>`, `<`, `>`, `<=`, `>=` | comparisons |
| 4 | `+`, `-`, `or` | additive |
| 5 | `*`, `div`, `mod`, `and` | multiplicative |
| 6 | unary `not`, unary `-`, unary `+` | highest |

**Note on `not`:** `i32.xor -1` implements bitwise NOT (complement all bits). For
boolean operands this is not the same as logical NOT (which would be `i32.eqz`). The
tutorial uses bitwise NOT here; Chapter 5 handles boolean-correct NOT in condition
contexts implicitly through the WASM `if` opcode (which treats any nonzero value as
true). Logical NOT of a boolean is deferred to Chapter 5.

**Note on `and then` / `or else`:** The scanner already folds these to single tokens
(`tkAndThen`, `tkOrElse`). The code generator emits `i32.and` / `i32.or` — identical
to `and` / `or`. Short-circuit semantics are not implemented in Chapter 3; both
operands are always evaluated. True short-circuit requires WASM `if` blocks and is
deferred to Chapter 5.

---

## Step 9: ParseStatement

```pascal
procedure ParseStatement;
begin
  case tokKind of
    tkHalt: begin
      NextToken;
      if tokKind = tkLParen then begin
        NextToken;
        ParseExpression(PrecNone);
        Expect(tkRParen);
      end else
        EmitI32Const(0);             { halt with no argument exits 0 }
      EmitCall(EnsureProcExit);      { ;; WAT: call $proc_exit }
    end;
    tkBegin: begin
      NextToken;
      while tokKind <> tkEnd do begin
        ParseStatement;
        if tokKind = tkSemicolon then
          NextToken;
      end;
      Expect(tkEnd);
    end;
  else
    { empty statement }
  end;
end;
```

The `tkBegin` arm handles compound statements: `begin stmt; stmt; stmt end`. This
allows nested `begin...end` blocks inside the main program body, even though Chapter 3
programs don't require them.

---

## Step 10: ParseProgram

Replace the body with:

```pascal
procedure ParseProgram;
begin
  Expect(tkProgram);
  if tokKind <> tkIdent then
    Error('expected program name');
  NextToken;
  Expect(tkSemicolon);
  Expect(tkBegin);
  while tokKind <> tkEnd do begin
    ParseStatement;
    if tokKind = tkSemicolon then
      NextToken;
  end;
  Expect(tkEnd);
  Expect(tkDot);
end;
```

The only change from Chapter 2 is that `Expect(tkEnd)` is replaced by the statement
loop. The `{** ...}` comment should be updated to remove the Chapter 1 disclaimer.

---

## Step 11: Section Organization

After adding these procedures, the file sections should be ordered:

```
{ ---- Constants ---- }
{ ---- Types ---- }
{ ---- Global Variables ---- }
{ ---- Error Handling ---- }
{ ---- Buffer Procedures ---- }
{ ---- LEB128 Encoding ---- }
{ ---- Output Writing ---- }
{ ---- Section Assembly ---- }       (includes new AssembleImportSection)
{ ---- Scanner ---- }
{ ---- Code Generation ---- }        (new: EmitOp, EmitI32Const, EmitCall, AddImport, EnsureProcExit)
{ ---- Forward declarations ---- }   (new: ParseExpression, ParseStatement)
{ ---- Parser ---- }                 (ParseExpression body, ParseStatement, ParseProgram)
{ ---- Main ---- }
```

---

## Step 12: Test Cases

### tests/calc.pas (new)

```pascal
program calc;
begin
  halt(6 * 7)
end.
```

Expected exit code: **42**.

### tests/math.pas (new)

```pascal
program math;
begin
  halt((10 + 20) * 3 - 48 div 2)
end.
```

Expected exit code: **66**. Verifies parentheses, operator precedence, and subtraction.

### tests/negation.pas (new)

```pascal
program negation;
begin
  halt(-(3 + 4) + 50)
end.
```

Expected exit code: **43**. Verifies unary minus.

### tests/empty.pas — already exists; keep passing

### tests/comments.pas — already exists; keep passing

---

## Step 13: Makefile Updates

The existing `test-strap-%` pattern only runs `wasm-validate`. Chapter 3 tests need
to run the program and check the exit code. Add a new pattern and new test targets:

```makefile
# run the wasm and check the exit code
test-run-strap-%-N : $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/%.wasm | $(STRAP_PC)
```

Since Make patterns can't carry the expected exit code, use explicit targets:

```makefile
test-strap-calc: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/calc.wasm
	wasm-validate $<
	$(WASMRUN) $<; test $$? -eq 42

test-strap-math: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/math.wasm
	wasm-validate $<
	$(WASMRUN) $<; test $$? -eq 66

test-strap-negation: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/negation.wasm
	wasm-validate $<
	$(WASMRUN) $<; test $$? -eq 43

test: test-strap-empty test-strap-comments test-strap-calc test-strap-math test-strap-negation
```

`wasmtime run` exits with the program's exit code when the program calls `proc_exit`.
The shell `test $$? -eq N` checks it.

---

## Implementation Order

1. Add new WASM opcode and precedence constants
2. Add `TypeVoidVoid` / `TypeI32Void` constants
3. Add `idxProcExit` and `importsBuf` globals
4. Update `InitModule` — init new globals, register type 1
5. Add `AssembleImportSection` procedure
6. Update `WriteModule` — call `AssembleImportSection` instead of `SmallBufInit(secImport)`
7. Add `EmitOp`, `EmitI32Const`, `EmitCall`
8. Add `AddImport`, `EnsureProcExit`
9. Add forward declarations (`ParseExpression`, `ParseStatement`)
10. Add `ParseExpression` body
11. Add `ParseStatement`
12. Modify `ParseProgram`
13. Add `tests/calc.pas`, `tests/math.pas`, `tests/negation.pas`
14. Update `Makefile` — add new test targets
15. `make test` — all five tests should pass

---

## What Is NOT in Chapter 3

- Variable declarations (`var`) — Chapter 4
- Assignment (`:=`) — Chapter 4
- `write` / `writeln` — Chapter 4
- `if` / `while` / `for` / `repeat` — Chapter 5
- Identifiers in expressions (variable loads) — Chapter 4
- Real-number literals — not supported (scanner already emits error)
- `/` division — not supported (integer division uses `div`; `/` is left unrecognized
  by the infix loop, causing a parser error at the statement level)
- True short-circuit `and then` / `or else` — Chapter 5

---

## Risks and Notes

- **`tokInt` warning clears.** The `pascom.pas(149,3) Note: Local variable "tokInt"
  is assigned but never used` warning goes away once `ParseExpression` reads `tokInt`
  in the `tkInteger` case.

- **`and then` / `or else` semantics.** The scanner produces `tkAndThen` / `tkOrElse`
  tokens. The code generator emits bitwise `i32.and` / `i32.or`. This is semantically
  correct for integer expressions and for boolean expressions where both operands are
  simple (no side effects). Short-circuit behavior requires WASM `if` blocks
  and is deferred.

- **Exit code range.** WASI `proc_exit` takes an `i32`. Most shells report exit codes
  modulo 256. Tests should use values in 0..127 to avoid ambiguity.

- **Empty _start still valid.** Programs with no `halt` produce an empty _start body
  (just `end`). WASM validation accepts this. The program exits normally with code 0
  when `_start` returns.

- **Import section ordering.** WASM requires sections in numerical ID order. Import
  section (ID=2) comes after Type (ID=1) and before Function (ID=3). The existing
  `WriteModule` already calls them in this order; replacing `SmallBufInit(secImport)`
  with `AssembleImportSection` preserves that order.

- **Function index shift.** When `proc_exit` is imported (numImports becomes 1), the
  `_start` function index shifts to 1. `AssembleExportSection` emits
  `SmallEmitULEB128(secExport, numImports)` for _start's index — this is already
  correct since `numImports` is updated by `AddImport` before `WriteModule` runs.
