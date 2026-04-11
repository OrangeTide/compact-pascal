# Chapter 10 Implementation Plan: Constants, Enums, and Case

## Overview

Chapter 10 adds three features that all require compile-time evaluation:
- **`const` declarations** with `EvalConstExpr`
- **Enumerated types** built on `skConst` + `tyEnum`
- **`case` statement** using compile-time labels and a WASM temp local

Note: **Hex literals** (`$FF`, `$0F`) are already implemented in the scanner's `$` branch of `NextToken`. No scanner changes needed for that.

## Feature 1: `skConst` and `EvalConstExpr`

### New constant

```pascal
skConst = 5;
```

Add after `skFunc = 4` in the constants section.

### `EvalConstExpr` procedure

Place before `ParseExpression` (in the Forward Declarations section). Signature:

```pascal
procedure EvalConstExpr(var outVal: longint; var outTyp: longint);
```

**Algorithm** — mirrors `ParseExpression` but computes values in Pascal variables instead of emitting WASM:

1. **Atom dispatch** (handle first token):
   - `tkInteger`: `outVal := tokInt; outTyp := tyInteger; NextToken;`
   - `tkString` (length 1): `outVal := ord(tokStr[1]); outTyp := tyChar; NextToken;`
   - `tkString` (length > 1): `outVal := EmitDataPascalString(tokStr); outTyp := tyString; NextToken;`
   - `tkTrue`: `outVal := 1; outTyp := tyBoolean; NextToken;`
   - `tkFalse`: `outVal := 0; outTyp := tyBoolean; NextToken;`
   - `tkLParen`: `NextToken; EvalConstExpr(outVal, outTyp); Expect(tkRParen);`
   - `tkMinus` (unary): `NextToken; EvalConstExpr(outVal, outTyp); outVal := -outVal;`
   - `tkPlus` (unary): `NextToken; EvalConstExpr(outVal, outTyp);` (no-op)
   - `tkNot`:
     ```pascal
     NextToken; EvalConstExpr(outVal, outTyp);
     if outTyp = tyBoolean then outVal := ord(outVal = 0)
     else outVal := not outVal;
     ```
   - `tkIdent`: look up identifier:
     - If `skConst`: `outVal := syms[s].offset; outTyp := syms[s].typ;`
     - If built-in function name (see below): handle inline
     - Else: `Error('not a constant: ...')`

2. **Built-in functions** (handled inside the `tkIdent` atom branch):
   - `ORD(x)`: `EvalConstExpr(x, t); outVal := x; outTyp := tyInteger;`
   - `CHR(x)`: `EvalConstExpr(x, t); outVal := x; outTyp := tyChar;`
   - `ABS(x)`: evaluate x; `if x < 0 then outVal := -x else outVal := x;`
   - `ODD(x)`: evaluate x; `outVal := ord((x and 1) <> 0); outTyp := tyBoolean;`
   - `SUCC(x)`: evaluate x; `outVal := x + 1;`
   - `PRED(x)`: evaluate x; `outVal := x - 1;`
   - `SQR(x)`: evaluate x; `outVal := x * x;`
   - `LO(x)`: evaluate x; `outVal := x and $FF; outTyp := tyInteger;`
   - `HI(x)`: evaluate x; `outVal := (x shr 8) and $FF; outTyp := tyInteger;`
   - `SIZEOF(T)`: look up type symbol, return its `.size` field.
   - All require `Expect(tkLParen)` before and `Expect(tkRParen)` after.

3. **Binary operators** — after evaluating the atom, check if next token is a binary operator (same precedence climbing approach as `ParseExpression`):
   ```
   while tokKind in [tkPlus, tkMinus, tkStar, tkDiv, tkMod, tkAnd, tkOr, tkXor,
                     tkEq, tkNe, tkLt, tkLe, tkGt, tkGe] do begin
     op := tokKind;
     NextToken;
     EvalConstExpr(rval, rtyp);
     { apply op to (outVal, rval) }
   end;
   ```

   Binary evaluation (after recording `ltyp := outTyp; lval := outVal`):
   ```pascal
   tkPlus:  outVal := lval + rval;
   tkMinus: outVal := lval - rval;
   tkStar:  outVal := lval * rval;
   tkDiv:   outVal := lval div rval;
   tkMod:   outVal := lval mod rval;
   tkAnd:   if ltyp = tyBoolean then outVal := ord((lval<>0) and (rval<>0))
            else outVal := lval and rval;
   tkOr:    if ltyp = tyBoolean then outVal := ord((lval<>0) or (rval<>0))
            else outVal := lval or rval;
   tkEq:    outVal := ord(lval = rval); outTyp := tyBoolean;
   tkNe:    outVal := ord(lval <> rval); outTyp := tyBoolean;
   tkLt:    outVal := ord(lval < rval); outTyp := tyBoolean;
   tkLe:    outVal := ord(lval <= rval); outTyp := tyBoolean;
   tkGt:    outVal := ord(lval > rval); outTyp := tyBoolean;
   tkGe:    outVal := ord(lval >= rval); outTyp := tyBoolean;
   ```

   Note: no short-circuit `and then`/`or else` — these are not needed at compile time. Also `tkXor` can be omitted (not in Compact Pascal).

   **Precedence**: implement full precedence climbing like `ParseExpression`. The recursive call should pass the current operator's precedence so left-associativity is maintained. Use a helper `EvalConstPrec(minPrec, var outVal, var outTyp)` and have `EvalConstExpr` call `EvalConstPrec(PrecNone, ...)`.

### `ParseConstBlock` procedure

```pascal
procedure ParseConstBlock;
var
  name: string[63];
  value: longint;
  typ:   longint;
  sym:   longint;
begin
  while tokKind = tkIdent do begin
    name := tokStr;
    NextToken;
    Expect(tkEq);
    EvalConstExpr(value, typ);
    sym := AddSym(name, skConst, typ);
    syms[sym].offset := value;
    Expect(tkSemicolon);
  end;
end;
```

### Wire up `ParseConstBlock`

In **`ParseProgram`**: change the `while` condition to also include `tkConst`:
```pascal
while (tokKind = tkType) or (tokKind = tkVar) or
      (tokKind = tkConst) or
      (tokKind = tkProcedure) or (tokKind = tkFunction) do begin
  if tokKind = tkConst then begin
    NextToken;
    ParseConstBlock;
  end else if tokKind = tkType then ...
```

In **`ParseProcDecl`** local block section (after param parsing, before `begin`):
```pascal
if tokKind = tkConst then begin
  NextToken;
  ParseConstBlock;
end;
if tokKind = tkType then ...
if tokKind = tkVar then ...
```

### Handle `skConst` in `ParseExpression`

In the `tkIdent` branch of `ParseExpression` (atom dispatch), before the `skFunc` check:
```pascal
if syms[s].kind = skConst then begin
  EmitI32Const(syms[s].offset);
  lastExprType := syms[s].typ;
  NextToken;
end else if syms[s].kind = skFunc then ...
```

## Feature 2: Enumerated Types

### New constant

```pascal
tyEnum = 7;
```

Add after `tyArray = 6`.

### Enum parsing in `ParseTypeSpec`

Add a branch for `tkLParen` before the `tkIdent` (named type) branch:

```pascal
end else if tokKind = tkLParen then begin
  { Enumerated type: (Ident, Ident, ...) }
  NextToken;
  tIdx := AddTypeDesc;
  types[tIdx].kind   := tyEnum;
  types[tIdx].size   := 4;
  types[tIdx].arrLo  := 0;
  ordinal := 0;
  repeat
    if tokKind <> tkIdent then
      Error('expected identifier in enum type');
    sym := AddSym(tokStr, skConst, tyEnum);
    syms[sym].offset   := ordinal;
    syms[sym].typeIdx  := tIdx;
    ordinal := ordinal + 1;
    NextToken;
    if tokKind = tkComma then
      NextToken
    else
      break;
  until false;
  Expect(tkRParen);
  types[tIdx].arrHi := ordinal - 1;
  outTyp     := tyEnum;
  outTypeIdx := tIdx;
  outSize    := 4;
```

Enum constants are registered as `skConst` with `typ = tyEnum`, so they flow through the same `skConst` path in `ParseExpression` — they emit `i32.const` with their ordinal.

Enum variables are stored as `i32` (size 4), identical to integers. All comparison operators work naturally.

### Local variables in ParseTypeSpec

Add `tIdx`, `sym`, `ordinal` to the `var` block of `ParseTypeSpec`.

## Feature 3: `case` Statement

### Case temp local tracking

Add to global variables:
```pascal
curNeedsCaseTemp: boolean;   { true if current function body uses a case statement }
curCaseTempIdx:   longint;   { WASM local index of the case selector temp }
startNeedsCaseTemp: boolean; { saved after _start body is compiled }
```

Add to `TFuncEntry`:
```pascal
needsCaseTemp: boolean;
```

**Setting `curCaseTempIdx`** at function entry:
- In `ParseProgram` before body parsing: `curNeedsCaseTemp := false; curCaseTempIdx := 0;`
  - `_start` has no params and no other locals (display uses globals). Case temp = local 0.
- In `ParseProcDecl` after `CodeBufInit(startCode)`:
  - For procedure: `curNeedsCaseTemp := false; curCaseTempIdx := nparams + 1;`
    - locals: 0..nparams-1 = params, nparams = display save. Case temp = nparams + 1.
  - For function: `curNeedsCaseTemp := false; curCaseTempIdx := nparams + 2;`
    - locals: 0..nparams-1 = params, nparams = return value, nparams+1 = display save. Case temp = nparams + 2.

**Saving** at the end of ParseProcDecl (before restoring context):
```pascal
funcs[fslot].needsCaseTemp := curNeedsCaseTemp;
```

**Saving** at the end of ParseProgram body (before `WriteModule`):
```pascal
startNeedsCaseTemp := curNeedsCaseTemp;
```

**Restoring** in ParseProcDecl: curNeedsCaseTemp is always reset at start of each function body — no restore of the outer value is needed because the outer function's `curNeedsCaseTemp` is saved in `ParseProcDecl`'s local var before resetting... 

Wait: `ParseProcDecl` is called recursively for nested functions. `curNeedsCaseTemp` is a global. If a nested proc sets it true, and then we restore to the outer function's compilation, the outer function's `curNeedsCaseTemp` would be wrong.

**Fix**: add `savedNeedsCaseTemp: boolean` to ParseProcDecl's local vars, save before resetting, restore after:
```pascal
savedNeedsCaseTemp := curNeedsCaseTemp;
curNeedsCaseTemp   := false;
...
funcs[fslot].needsCaseTemp := curNeedsCaseTemp;
curNeedsCaseTemp := savedNeedsCaseTemp;
```

### `ParseCase` — case statement parsing

Add a `tkCase` branch in `ParseStatement`:

```pascal
tkCase: begin
  NextToken;
  curNeedsCaseTemp := true;
  ParseExpression(PrecNone);          { selector on WASM stack }
  EmitOp(OpLocalSet);
  EmitULEB128(startCode, curCaseTempIdx);  { save selector }
  Expect(tkOf);
  armCount := 0;
  while (tokKind <> tkEnd) and (tokKind <> tkElse) and (tokKind <> tkEOF) do begin
    { Parse label list for this arm }
    labelCount := 0;
    repeat
      if tokKind = tkInteger then begin
        EvalConstExpr(labelVal, labelTyp);  { handles integer/ident constants }
      end else begin
        EvalConstExpr(labelVal, labelTyp);
      end;
      if tokKind = tkDotDot then begin
        { Range label: lo..hi }
        NextToken;
        EvalConstExpr(hiVal, labelTyp);
        { emit: local.get temp; i32.const lo; i32.ge_s }
        EmitOp(OpLocalGet); EmitULEB128(startCode, curCaseTempIdx);
        EmitI32Const(labelVal);
        EmitOp(OpI32GeS);
        { emit: local.get temp; i32.const hi; i32.le_s }
        EmitOp(OpLocalGet); EmitULEB128(startCode, curCaseTempIdx);
        EmitI32Const(hiVal);
        EmitOp(OpI32LeS);
        EmitOp(OpI32And);
      end else begin
        { Single value: local.get temp; i32.const val; i32.eq }
        EmitOp(OpLocalGet); EmitULEB128(startCode, curCaseTempIdx);
        EmitI32Const(labelVal);
        EmitOp(OpI32Eq);
      end;
      labelCount := labelCount + 1;
      if tokKind = tkComma then
        NextToken
      else
        break;
    until false;
    Expect(tkColon);
    { OR together multiple labels }
    while labelCount > 1 do begin
      EmitOp(OpI32Or);
      labelCount := labelCount - 1;
    end;
    { Emit if block for this arm }
    EmitOp(OpIf); EmitOp(WasmVoid);
    { Parse arm body (single statement) }
    ParseStatement;
    armCount := armCount + 1;
    if tokKind = tkSemicolon then
      NextToken;
    if (tokKind <> tkEnd) and (tokKind <> tkElse) and (tokKind <> tkEOF) then begin
      { More arms: start else block }
      EmitOp(OpElse);
    end;
  end;
  { Handle else clause }
  if tokKind = tkElse then begin
    NextToken;
    ParseStatement;
    if tokKind = tkSemicolon then NextToken;
  end;
  { Close all if blocks }
  i := armCount;
  while i > 0 do begin
    EmitOp(OpEnd);
    i := i - 1;
  end;
  Expect(tkEnd);
end;
```

**Note on label evaluation**: `EvalConstExpr` handles all constant atoms including enum constants (which are `skConst` symbols), integer literals, and hex literals. So no special dispatch is needed for labels.

**Note on `exitDepth`**: each `if` block increments nesting depth by 1. For `exit`/`break`/`continue` inside a case arm to work correctly, `exitDepth` must be incremented per arm. However, this is complex because the depth changes as we nest. A simpler approach: don't adjust `exitDepth` inside the case (case arms don't introduce loop/exit boundaries). The `exit` statement uses the exit block which sits outside all case nesting, so the depth arithmetic may be off. This is a known limitation for Chapter 10 — `exit` inside a case arm is deferred.

### `AssembleCodeSection` changes

**`_start` body** — change from always 0 locals to conditional:
```pascal
if startNeedsCaseTemp then begin
  bodyLen := 3 + startCode.len + 1;  { [01 01 7F] + code + end }
  EmitULEB128(secCode, bodyLen);
  CodeBufEmit(secCode, 1);    { 1 local group }
  CodeBufEmit(secCode, 1);    { 1 local }
  CodeBufEmit(secCode, $7F);  { i32 }
end else begin
  bodyLen := 1 + startCode.len + 1;  { [00] + code + end }
  EmitULEB128(secCode, bodyLen);
  CodeBufEmit(secCode, 0);    { 0 local declarations }
end;
```

**User function bodies** — the existing code emits either 1 or 2 extras (display save or return+display). Add 1 more for case temp:
```pascal
if funcs[j].retType <> 0 then begin
  if funcs[j].needsCaseTemp then extras := 3 else extras := 2;
end else begin
  if funcs[j].needsCaseTemp then extras := 2 else extras := 1;
end;
localBytes := 3;  { [01 N 7F] — 1 group, N locals, i32 }
{ N is `extras` }
bodyLen := localBytes + funcs[j].bodyLen + 1;
EmitULEB128(secCode, bodyLen);
CodeBufEmit(secCode, 1);       { 1 group }
CodeBufEmit(secCode, extras);  { N locals }
CodeBufEmit(secCode, $7F);     { i32 }
```

## Tests to Add

Following the tutorial's test numbering (t045 through t048):

### t045_const_basic.pas

Constants: integer arithmetic, hex, ord/chr, abs, sqr, lo/hi. Expected file shows computed values.

### t046_const_string.pas (optional)

String constant with address — verify const string in writeln works.

### t047_enum.pas

Enum type, enum variable, comparison of enum values.

### t048_case_basic.pas

Single labels, multiple comma-separated labels, ranges (`..`), and `else` clause.

## Implementation Order

1. Add `skConst = 5`, `tyEnum = 7` to constants section
2. Add `curNeedsCaseTemp`, `curCaseTempIdx`, `startNeedsCaseTemp` to global vars
3. Add `needsCaseTemp: boolean` to `TFuncEntry`
4. Implement `EvalConstExpr` (with precedence climbing)
5. Implement `ParseConstBlock`
6. Wire `ParseConstBlock` into `ParseProgram` and `ParseProcDecl`
7. Handle `skConst` in `ParseExpression` atom dispatch
8. Add enum support to `ParseTypeSpec`
9. Add `tkCase` branch to `ParseStatement` (with local vars: armCount, labelCount, labelVal, hiVal, labelTyp, i)
10. Update `AssembleCodeSection` for case temp locals
11. Initialize `curNeedsCaseTemp/curCaseTempIdx` in `ParseProgram` and `ParseProcDecl`
12. Save/restore `curNeedsCaseTemp` in `ParseProcDecl`
13. Add tests t045–t048

## Risks and Notes

- **`exit` inside `case`**: `exitDepth` tracks how many WASM blocks deep we are. The case `if` blocks increment nesting but we don't currently track this in `exitDepth`. Exit from inside a case arm will compute the wrong branch depth. Deferring this edge case.
- **`EvalConstExpr` vs `ParseExpression` precedence**: must implement proper precedence climbing to correctly handle `MaxSize - MinSize * 2` (not `(MaxSize - MinSize) * 2`).
- **Enum in `ParseTypeSpec` needs extra locals**: add `tIdx`, `sym`, `ordinal` to `ParseTypeSpec`'s var block (it already has `tIdx` for arrays — reuse it).
- **`skConst` in `ParseStatement`**: when an identifier is used as a statement start and its kind is `skConst`, that's an error (constants are not lvalues). The existing `skVar` check for assignment handles this; the `else if skVar` branch will catch it and if `kind <> skVar` it calls Error. But we need to ensure `skConst` doesn't fall through to an unexpected code path — verify the error message is sensible.
