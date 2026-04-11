# Chapter 6 Implementation Plan: Procedures and Functions

## Overview

Chapter 6 adds procedure and function declarations to the compiler. Key features:
- User-defined procedures (no return value) and functions (return value)
- Value, `var`, and `const` parameters
- Function return assignment via function name
- Forward declarations (mutual recursion)
- The `exit` intrinsic (branch to end of function block, preserving epilogue)
- External declarations and `{$IMPORT}` / `{$EXPORT}` directives

All parameters are passed as `i32` in WASM. Parameters live as WASM locals (not frame
slots). Local variables inside procedures continue to use the stack frame ($sp).

---

## 1. New Constants

```pascal
{ Symbol kinds — add to existing skVar=1, skType=2 }
skProc = 3;   { procedure symbol }
skFunc = 4;   { function symbol }

{ Built-in keyword token }
tkExit = 209;

{ Function table limits }
MaxFuncs  = 256;
MaxParams = 16;
```

Also add to `LookupKeyword`: `'EXIT' → tkExit`.

---

## 2. New Types

### TFuncEntry

```pascal
TFuncEntry = record
  nparams:      longint;
  retType:      longint;   { 0=procedure, else tyInteger/tyBoolean/tyChar }
  wasmFuncIdx:  longint;   { absolute WASM function index }
  wasmTypeIdx:  longint;   { index into wasmTypes[] }
  bodyStart:    longint;   { byte offset in funcBodies (instruction bytes only) }
  bodyLen:      longint;   { instruction byte count in funcBodies }
  isForward:    boolean;   { declared forward, body not yet compiled }
  varParams:    array[0..MaxParams-1] of boolean;
  constParams:  array[0..MaxParams-1] of boolean;
end;
```

### TSymEntry additions

Add two boolean fields to the existing record:

```pascal
TSymEntry = record
  name:         string[63];
  kind:         longint;       { skVar, skType, skProc, skFunc }
  typ:          longint;
  level:        longint;
  offset:       longint;       { for skVar: frame offset (>=0) or WASM local idx -(i+1)
                                  for skProc/skFunc: WASM function index }
  size:         longint;       { for skVar: byte size; for skProc/skFunc: funcs[] index }
  isVarParam:   boolean;       { WASM local holds address, not value }
  isConstParam: boolean;       { assignment forbidden }
end;
```

For procedures/functions, `offset` = WASM function index (used in call instruction), and
`size` = index into `funcs[]` (used to look up `varParams`, `nparams`, etc.).

For parameters (value, var, const), `offset < 0` indicates a WASM local. The WASM local
index is `-(offset + 1)`.

---

## 3. New Global Variables

```pascal
{ Function table }
funcs:        array[0..MaxFuncs-1] of TFuncEntry;
numFuncs:     longint;

{ Accumulated function bodies: instruction bytes only, no local header, no end byte }
funcBodies:   TCodeBuf;

{ exit-block depth: -1 = not in a procedure/function (exit is invalid)
  0 = at the function body level block, +N per enclosing control structure }
exitDepth: longint;

{ Pending {$IMPORT} directive (set by scanner, consumed by ParseProcDecl) }
hasPendingImport:   boolean;
pendingImportMod:   string;
pendingImportFld:   string;

{ Pending {$EXPORT} directive (set by scanner, consumed by ParseProcDecl) }
hasPendingExport:   boolean;
pendingExportName:  string;

{ Extra export entries: name-bytes | funcIdx for each {$EXPORT} seen }
userExportsBuf:  TSmallBuf;
numUserExports:  longint;
```

---

## 4. Scanner Changes: Directive Parsing

Modify `SkipBraceComment` to detect `{$...}` directives. After reading the opening `{`,
peek at the next char. If it is `$`, call a new `ParseDirective` procedure instead of
skipping:

```pascal
procedure SkipBraceComment;
begin
  ReadCh;  { first char inside comment }
  if ch = '$' then begin
    ParseDirective;
    exit;
  end;
  while not atEof do begin
    if ch = '}' then begin
      ReadCh;
      exit;
    end;
    ReadCh;
  end;
  Error('unterminated { comment');
end;
```

`ParseDirective` reads until `}`, accumulating the directive text, then dispatches:

```pascal
procedure ParseDirective;
{ Called after '$' is seen inside a brace comment.
  Reads keyword and args until '}', then processes. }
var
  kw:  string;
  mod: string;
  fld: string;
  nm:  string;
begin
  { Read keyword (uppercase) }
  kw := '';
  ReadCh;  { skip '$', ch is now first letter }
  while not atEof and (ch > ' ') and (ch <> '}') do begin
    kw := concat(kw, UpperCh(ch));
    ReadCh;
  end;
  if kw = 'IMPORT' then begin
    { Read module name }
    while not atEof and (ch = ' ') do ReadCh;
    mod := '';
    while not atEof and (ch > ' ') and (ch <> '}') do begin
      mod := concat(mod, ch);
      ReadCh;
    end;
    { Read field name }
    while not atEof and (ch = ' ') do ReadCh;
    fld := '';
    while not atEof and (ch > ' ') and (ch <> '}') do begin
      fld := concat(fld, ch);
      ReadCh;
    end;
    hasPendingImport := true;
    pendingImportMod := mod;
    pendingImportFld := fld;
  end else if kw = 'EXPORT' then begin
    while not atEof and (ch = ' ') do ReadCh;
    nm := '';
    while not atEof and (ch > ' ') and (ch <> '}') do begin
      nm := concat(nm, ch);
      ReadCh;
    end;
    hasPendingExport := true;
    pendingExportName := nm;
  end;
  { Skip to closing '}' }
  while not atEof and (ch <> '}') do ReadCh;
  if ch = '}' then ReadCh;
end;
```

---

## 5. WASM Type Registry: FindOrAddWasmType

A helper to find (or add) a type signature by (nparams, hasReturn):

```pascal
function FindOrAddWasmType(np: longint; hasRet: boolean): longint;
{ All params are i32. Returns index into wasmTypes[]. }
var i, j: longint;
    match: boolean;
begin
  for i := 0 to numWasmTypes - 1 do begin
    if wasmTypes[i].nparams <> np then continue;
    if hasRet and (wasmTypes[i].nresults <> 1) then continue;
    if (not hasRet) and (wasmTypes[i].nresults <> 0) then continue;
    match := true;
    for j := 0 to np - 1 do
      if wasmTypes[i].params[j] <> WasmI32 then match := false;
    if match then begin
      FindOrAddWasmType := i;
      exit;
    end;
  end;
  { Not found: add new entry }
  if numWasmTypes >= MaxWasmTypes then
    Error('too many WASM types');
  wasmTypes[numWasmTypes].nparams := np;
  for i := 0 to np - 1 do
    wasmTypes[numWasmTypes].params[i] := WasmI32;
  if hasRet then begin
    wasmTypes[numWasmTypes].nresults   := 1;
    wasmTypes[numWasmTypes].results[0] := WasmI32;
  end else
    wasmTypes[numWasmTypes].nresults := 0;
  FindOrAddWasmType := numWasmTypes;
  numWasmTypes := numWasmTypes + 1;
end;
```

---

## 6. Code Generation Helpers

### EmitFramePtr

In Chapter 6 (no nested scopes), the frame pointer is always global 0:

```pascal
procedure EmitFramePtr(level: longint);
begin
  EmitGlobalGet(0);  { $sp }
end;
```

This stub is identical to `EmitGlobalGet(0)` in Chapter 6. Chapter 7 will extend it to
use the Dijkstra display.

### EmitLocalGet / EmitLocalSet

```pascal
procedure EmitLocalGet(idx: longint);
begin
  EmitOp(OpLocalGet);
  EmitULEB128(startCode, idx);
end;

procedure EmitLocalSet(idx: longint);
begin
  EmitOp(OpLocalSet);
  EmitULEB128(startCode, idx);
end;
```

### EnsureBuiltinImports

Called before assigning any user function's WASM index, to lock in built-in import
indices so they don't shift later:

```pascal
procedure EnsureBuiltinImports;
begin
  EnsureFdWrite;
  EnsureProcExit;
end;
```

---

## 7. Variable Load / Store Refactoring

The current code in `ParseExpression` and `ParseStatement` that loads/stores variables:

```pascal
EmitGlobalGet(0);
EmitI32Const(syms[s].offset);
EmitOp(OpI32Add);
if syms[s].size = 1 then EmitI32Load8u(0, 0)
else EmitI32Load(2, 0);
```

Needs to handle three cases based on `syms[s].offset`:

**Case 1: frame variable** (`offset >= 0`, `isVarParam = false`)
```
EmitFramePtr(level);
EmitI32Const(offset);
OpI32Add;
i32.load or i32.load8_u;
```

**Case 2: value parameter** (`offset < 0`, `isVarParam = false`)
```
EmitLocalGet(-(offset+1));
```
(The value is directly in the WASM local.)

**Case 3: var/const parameter** (`offset < 0`, `isVarParam = true`)
Read: get the pointer, then dereference:
```
EmitLocalGet(-(offset+1));   { pointer }
if size = 1 then EmitI32Load8u(0, 0)
else EmitI32Load(2, 0);
```
Write: get the pointer, evaluate expression, store:
```
EmitLocalGet(-(offset+1));   { pointer }
ParseExpression(PrecNone);
if size = 1 then EmitI32Store8(0, 0)
else EmitI32Store(2, 0);
```

Extract these into helpers `EmitVarLoad(sym)` and emit the store pattern inline in
`ParseStatement`.

---

## 8. ParseProcDecl

Handles both `procedure` and `function` declarations (and external variants).

```pascal
procedure ParseProcDecl;
var
  isFunc:        boolean;
  funcName:      string;
  np:            longint;    { number of parameters }
  paramNames:    array[0..MaxParams-1] of string[63];
  paramTypes:    array[0..MaxParams-1] of longint;  { type ID }
  paramSizes:    array[0..MaxParams-1] of longint;  { byte size }
  paramIsVar:    array[0..MaxParams-1] of boolean;
  paramIsConst:  array[0..MaxParams-1] of boolean;
  retType:       longint;    { 0 = procedure }
  retTypeSz:     longint;
  typeIdx:       longint;    { WASM type index }
  funcIdx:       longint;    { WASM function index }
  fslot:         longint;    { index into funcs[] }
  isExternal:    boolean;
  isForwardDecl: boolean;
  sym:           longint;
  existSym:      longint;
  savedStartCode: TCodeBuf;
  savedFrameSize: longint;
  savedExitDepth: longint;
  i:             longint;
  typSym:        longint;
  s:             longint;
  bodyStart:     longint;
begin
  isFunc := (tokKind = tkFunction);
  NextToken;  { consume 'procedure' or 'function' }

  { Parse name }
  if tokKind <> tkIdent then Error('expected procedure/function name');
  funcName := tokStr;
  NextToken;

  { Check if this is a re-declaration of a forward }
  existSym := LookupSym(funcName);
  if (existSym >= 0) and
     ((syms[existSym].kind = skProc) or (syms[existSym].kind = skFunc)) then begin
    { Must be a forward declaration being filled in }
    fslot := syms[existSym].size;
    if not funcs[fslot].isForward then
      Error(concat('duplicate declaration of ', funcName));
    { Use existing slot }
  end else
    fslot := -1;  { new declaration }

  { Parse parameter list }
  np := 0;
  if tokKind = tkLParen then begin
    NextToken;
    while tokKind <> tkRParen do begin
      { Detect var / const modifier }
      paramIsVar[np]   := false;
      paramIsConst[np] := false;
      if tokKind = tkVar then begin
        paramIsVar[np] := true;
        NextToken;
      end else if tokKind = tkConst then begin
        paramIsConst[np] := true;
        NextToken;
      end;
      { Collect names in this group }
      { (var a, b: integer groups parameters of the same modifier/type) }
      { For simplicity, parse one name per group iteration, allowing comma }
      repeat
        if tokKind <> tkIdent then Error('expected parameter name');
        paramNames[np] := tokStr;
        paramIsVar[np]   := paramIsVar[np-1];  { ??? }
        { Actually: collect names sharing the same modifier, then parse type }
        ...
      until ...;
      ...
    end;
    Expect(tkRParen);
  end;
```

**Note**: Parameter parsing is the trickiest part. Pascal allows `var a, b: integer`
grouping. The approach: collect a group of names sharing the same modifier, then parse
the shared type, then register all in the group. Here is a cleaner version:

```pascal
  { Parse parameter list }
  np := 0;
  if tokKind = tkLParen then begin
    NextToken;
    while tokKind <> tkRParen do begin
      { Each iteration: one parameter group (same modifier + type) }
      isVarGroup   := false;
      isConstGroup := false;
      if tokKind = tkVar then begin
        isVarGroup := true; NextToken;
      end else if tokKind = tkConst then begin
        isConstGroup := true; NextToken;
      end;
      { Collect names in this group }
      groupStart := np;
      repeat
        if tokKind <> tkIdent then Error('expected parameter name');
        paramNames[np]    := tokStr;
        paramIsVar[np]    := isVarGroup;
        paramIsConst[np]  := isConstGroup;
        np := np + 1;
        NextToken;
        if tokKind = tkComma then NextToken
        else break;
      until false;
      Expect(tkColon);
      { Parse type (shared by all names in this group) }
      if tokKind <> tkIdent then Error('expected type name');
      typSym := LookupSym(tokStr);
      if (typSym < 0) or (syms[typSym].kind <> skType) then
        Error(concat('unknown type: ', tokStr));
      for i := groupStart to np - 1 do begin
        paramTypes[i] := syms[typSym].typ;
        paramSizes[i] := syms[typSym].size;
      end;
      NextToken;
      if tokKind = tkSemicolon then NextToken;
    end;
    Expect(tkRParen);
  end;
```

**Parse return type (functions)**:
```pascal
  retType := 0;
  if isFunc then begin
    Expect(tkColon);
    if tokKind <> tkIdent then Error('expected return type');
    typSym := LookupSym(tokStr);
    if (typSym < 0) or (syms[typSym].kind <> skType) then
      Error(concat('unknown return type: ', tokStr));
    retType := syms[typSym].typ;
    NextToken;
  end;
```

**Detect forward / external**:
```pascal
  isForwardDecl := (tokKind = tkForward);
  isExternal    := (tokKind = tkIdent) and (tokStr = 'EXTERNAL');
  if isForwardDecl or isExternal then NextToken;
  Expect(tkSemicolon);
```

**Handle external declaration** (WASM import via `{$IMPORT}`):
```pascal
  if isExternal then begin
    if not hasPendingImport then
      Error('external procedure needs preceding {$IMPORT} directive');
    typeIdx  := FindOrAddWasmType(np, isFunc);
    funcIdx  := AddImport(pendingImportMod, pendingImportFld, typeIdx);
    hasPendingImport := false;
    { Register symbol }
    if fslot < 0 then begin
      fslot := numFuncs;
      numFuncs := numFuncs + 1;
    end;
    funcs[fslot].nparams     := np;
    funcs[fslot].retType     := retType;
    funcs[fslot].wasmFuncIdx := funcIdx;
    funcs[fslot].wasmTypeIdx := typeIdx;
    funcs[fslot].isForward   := false;
    for i := 0 to np - 1 do begin
      funcs[fslot].varParams[i]   := paramIsVar[i];
      funcs[fslot].constParams[i] := paramIsConst[i];
    end;
    if fslot = syms[existSym].size then { reuse } else begin
      sym := AddSym(funcName, (if isFunc then skFunc else skProc), retType);
      syms[sym].offset := funcIdx;
      syms[sym].size   := fslot;
    end;
    exit;
  end;
```

**Handle forward declaration**:
```pascal
  if isForwardDecl then begin
    EnsureBuiltinImports;  { lock in built-in import indices }
    typeIdx := FindOrAddWasmType(np, isFunc);
    funcIdx := numImports + numDefinedFuncs;
    numDefinedFuncs := numDefinedFuncs + 1;
    fslot := numFuncs;
    funcs[fslot].nparams     := np;
    funcs[fslot].retType     := retType;
    funcs[fslot].wasmFuncIdx := funcIdx;
    funcs[fslot].wasmTypeIdx := typeIdx;
    funcs[fslot].isForward   := true;
    funcs[fslot].bodyStart   := 0;
    funcs[fslot].bodyLen     := 0;
    for i := 0 to np - 1 do begin
      funcs[fslot].varParams[i]   := paramIsVar[i];
      funcs[fslot].constParams[i] := paramIsConst[i];
    end;
    numFuncs := numFuncs + 1;
    sym := AddSym(funcName,
                  (if isFunc then skFunc else skProc),
                  retType);
    syms[sym].offset := funcIdx;
    syms[sym].size   := fslot;
    exit;
  end;
```

**Handle normal (non-forward, non-external) declaration**:

```pascal
  { Assign WASM function index (if new declaration, not filling in a forward) }
  if fslot < 0 then begin
    EnsureBuiltinImports;
    typeIdx := FindOrAddWasmType(np, isFunc);
    funcIdx := numImports + numDefinedFuncs;
    numDefinedFuncs := numDefinedFuncs + 1;
    fslot := numFuncs;
    funcs[fslot].nparams     := np;
    funcs[fslot].retType     := retType;
    funcs[fslot].wasmFuncIdx := funcIdx;
    funcs[fslot].wasmTypeIdx := typeIdx;
    funcs[fslot].isForward   := false;
    for i := 0 to np - 1 do begin
      funcs[fslot].varParams[i]   := paramIsVar[i];
      funcs[fslot].constParams[i] := paramIsConst[i];
    end;
    numFuncs := numFuncs + 1;
    sym := AddSym(funcName, (if isFunc then skFunc else skProc), retType);
    syms[sym].offset := funcIdx;
    syms[sym].size   := fslot;
  end else begin
    { Filling in a forward: update wasmTypeIdx if needed, mark not forward }
    funcs[fslot].isForward := false;
    funcIdx := funcs[fslot].wasmFuncIdx;
    sym := existSym;
  end;

  { Handle {$EXPORT} }
  if hasPendingExport then begin
    { Store export: ULEB128 funcIdx + name bytes, accumulated in userExportsBuf }
    EmitExportEntry(userExportsBuf, pendingExportName, funcIdx);
    numUserExports := numUserExports + 1;
    hasPendingExport := false;
  end;

  { Save current code emission state }
  savedStartCode := startCode;
  CodeBufInit(startCode);
  savedFrameSize := curFrameSize;
  curFrameSize   := 0;
  savedExitDepth := exitDepth;

  { Enter scope; add parameters }
  EnterScope;
  for i := 0 to np - 1 do begin
    s := AddSym(paramNames[i],
                skVar,
                paramTypes[i]);
    syms[s].size        := paramSizes[i];
    syms[s].offset      := -(i + 1);   { WASM local index i }
    syms[s].isVarParam  := paramIsVar[i] or paramIsConst[i];
    syms[s].isConstParam := paramIsConst[i];
  end;
  { For functions: add return-value symbol (the function name itself,
    visible inside the body so `FuncName := expr` can assign the return) }
  { The function name sym already has kind=skFunc, so assignment-to-funcname
    is handled in ParseStatement. No separate symbol needed. }

  { Parse optional var block inside procedure }
  if tokKind = tkVar then begin
    NextToken;
    ParseVarBlock;
  end;

  { Frame prologue }
  if curFrameSize > 0 then begin
    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Sub);
    EmitGlobalSet(0);
  end;

  { Emit exit block wrapper }
  EmitOp(OpBlock);
  EmitOp(WasmVoid);
  exitDepth := 0;

  { Parse body }
  Expect(tkBegin);
  ParseStatement;
  while tokKind = tkSemicolon do begin
    NextToken;
    if tokKind <> tkEnd then ParseStatement;
  end;
  Expect(tkEnd);
  Expect(tkSemicolon);

  { End exit block }
  EmitOp(OpEnd);

  { Frame epilogue }
  if curFrameSize > 0 then begin
    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Add);
    EmitGlobalSet(0);
  end;

  { For functions: push return value }
  if isFunc then begin
    EmitOp(OpLocalGet);
    EmitULEB128(startCode, np);  { hidden return-value local at index np }
  end;

  { Copy body to funcBodies }
  funcs[fslot].bodyStart := funcBodies.len;
  funcs[fslot].bodyLen   := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(funcBodies, startCode.data[i]);

  { Leave scope and restore state }
  LeaveScope;
  startCode    := savedStartCode;
  curFrameSize := savedFrameSize;
  exitDepth    := savedExitDepth;
end;
```

**Note on `isFunc` conditional**: Pascal doesn't have inline conditionals. Use:
```pascal
if isFunc then syms[sym].kind := skFunc
else           syms[sym].kind := skProc;
```

---

## 9. exit Handling in ParseStatement

Add `tkExit` to the case:

```pascal
tkExit: begin
  NextToken;
  if exitDepth < 0 then
    Error('exit outside of procedure/function');
  EmitOp(OpBr);
  EmitULEB128(startCode, exitDepth);
end;
```

Also update all control flow constructs to track `exitDepth`:

**tkIf**: same +1/-1 as breakDepth/continueDepth (WASM `if` block = 1 block deep).

**tkWhile**: +2/-2 (outer block + inner loop).

**tkFor**: +2/-2 (outer block + inner loop).

**tkRepeat**: +1/-1 (single loop, no outer block).

Keep `exitDepth = -1` in the main program (set at ParseProgram entry, never changed
there). This ensures `exit` at top level errors.

---

## 10. Procedure/Function Calls in ParseStatement and ParseExpression

### ParseStatement: call as statement

Add to the `tkIdent` branch — when identifier resolves to `skProc` or `skFunc`:

```pascal
{ When sym is skProc or skFunc }
NextToken;
Expect(tkLParen);  { always require parens, even for 0 params }
{ Parse arguments }
argIdx := 0;
while tokKind <> tkRParen do begin
  fslot := syms[sym].size;
  if funcs[fslot].varParams[argIdx] then begin
    { var/const param: pass address of the argument variable }
    { Parse lvalue: must be identifier }
    if tokKind <> tkIdent then Error('var param requires variable');
    argSym := LookupSym(tokStr);
    if argSym < 0 then Error(concat('unknown: ', tokStr));
    NextToken;
    if syms[argSym].offset < 0 then begin
      { arg is itself a var param: the local already holds an address }
      EmitLocalGet(-(syms[argSym].offset + 1));
    end else begin
      { arg is a frame variable }
      EmitFramePtr(syms[argSym].level);
      EmitI32Const(syms[argSym].offset);
      EmitOp(OpI32Add);
    end;
  end else
    ParseExpression(PrecNone);  { value param: evaluate }
  argIdx := argIdx + 1;
  if tokKind = tkComma then NextToken;
end;
Expect(tkRParen);
EmitCall(syms[sym].offset);  { offset = WASM function index }
if syms[sym].kind = skFunc then
  EmitOp(OpDrop);  { discard return value when called as statement }
```

### ParseStatement: function return assignment

In the `tkIdent` branch, when `sym` is `skFunc` (and we see `:=`):

```pascal
{ Assignment to function name = set return value }
fslot := syms[sym].size;
NextToken;  { consume function name }
Expect(tkAssign);
ParseExpression(PrecNone);
EmitOp(OpLocalSet);
EmitULEB128(startCode, funcs[fslot].nparams);  { hidden return local }
```

### ParseExpression: function call as expression

In the prefix case for `tkIdent`, when `sym.kind` is `skFunc`:
- Parse call arguments (same as above, but no `OpDrop`)
- The return value remains on the WASM stack

### ParseExpression: variable load for parameters

In the `tkIdent` prefix case, update the load logic:

```pascal
if syms[s].offset < 0 then begin
  { WASM local }
  localIdx := -(syms[s].offset + 1);
  if syms[s].isVarParam then begin
    { pointer in local: dereference }
    EmitLocalGet(localIdx);
    if syms[s].size = 1 then EmitI32Load8u(0, 0)
    else EmitI32Load(2, 0);
  end else begin
    { value directly in local }
    EmitLocalGet(localIdx);
  end;
end else begin
  { Frame variable }
  EmitFramePtr(syms[s].level);
  EmitI32Const(syms[s].offset);
  EmitOp(OpI32Add);
  if syms[s].size = 1 then EmitI32Load8u(0, 0)
  else EmitI32Load(2, 0);
end;
```

---

## 11. Assembly Section Changes

### AssembleFunctionSection

Currently hardcodes _start and optionally __write_int. Extend to include user functions:

```pascal
procedure AssembleFunctionSection;
var i: longint;
begin
  SmallBufInit(secFunc);
  SmallBufEmit(secFunc, numDefinedFuncs);
  SmallBufEmit(secFunc, TypeVoidVoid);   { _start: () -> () }
  if needWriteInt then
    SmallBufEmit(secFunc, TypeI32Void);  { __write_int: (i32) -> () }
  for i := 0 to numFuncs - 1 do
    SmallBufEmit(secFunc, funcs[i].wasmTypeIdx);
end;
```

Note: external functions are in the import section, not here. `numFuncs` only counts
non-external (body-defined) functions including those filled in from forward decls.

Wait — `numDefinedFuncs` is already being incremented for user functions in ParseProcDecl
(via `numDefinedFuncs + 1` at index assignment). So `numDefinedFuncs` already includes
_start + __write_int (if needed) + user functions. The function section count is just
`numDefinedFuncs`. The type entries need to match: first _start, then __write_int, then
user funcs in declaration order.

Revised:
```pascal
procedure AssembleFunctionSection;
var i: longint;
begin
  SmallBufInit(secFunc);
  SmallBufEmit(secFunc, numDefinedFuncs);
  SmallBufEmit(secFunc, TypeVoidVoid);         { _start }
  if needWriteInt then
    SmallBufEmit(secFunc, TypeI32Void);        { __write_int }
  for i := 0 to numFuncs - 1 do
    SmallEmitULEB128(secFunc, funcs[i].wasmTypeIdx);  { user functions }
end;
```

### AssembleExportSection

Currently hardcodes `_start` and `memory`. Extend for user exports:

```pascal
procedure AssembleExportSection;
var i: longint;
begin
  SmallBufInit(secExport);
  SmallBufEmit(secExport, 2 + numUserExports);
  { _start }
  ... (existing _start export) ...
  { memory }
  ... (existing memory export) ...
  { User exports from userExportsBuf }
  for i := 0 to userExportsBuf.len - 1 do
    SmallBufEmit(secExport, userExportsBuf.data[i]);
end;
```

The `userExportsBuf` is populated by `EmitExportEntry` during ParseProcDecl when
`{$EXPORT}` is pending.

### AssembleCodeSection

Add user function bodies after _start and __write_int:

```pascal
procedure AssembleCodeSection;
var bodyLen, i, j, localBytes: longint;
begin
  CodeBufInit(secCode);
  EmitULEB128(secCode, numDefinedFuncs);

  { _start body }
  bodyLen := 1 + startCode.len + 1;
  EmitULEB128(secCode, bodyLen);
  CodeBufEmit(secCode, 0);   { 0 local groups }
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(secCode, startCode.data[i]);
  CodeBufEmit(secCode, $0B);

  { __write_int body (unchanged) }
  if needWriteInt then begin
    ...existing...
  end;

  { User function bodies }
  for j := 0 to numFuncs - 1 do begin
    if funcs[j].retType <> 0 then
      localBytes := 3   { 1 group: 1 x i32 }
    else
      localBytes := 1;  { 0 groups }
    bodyLen := localBytes + funcs[j].bodyLen + 1;  { +1 for end }
    EmitULEB128(secCode, bodyLen);
    if funcs[j].retType <> 0 then begin
      CodeBufEmit(secCode, 1);     { 1 local group }
      CodeBufEmit(secCode, 1);     { 1 local }
      CodeBufEmit(secCode, $7F);   { i32 }
    end else
      CodeBufEmit(secCode, 0);     { 0 local groups }
    for i := funcs[j].bodyStart to funcs[j].bodyStart + funcs[j].bodyLen - 1 do
      CodeBufEmit(secCode, funcBodies.data[i]);
    CodeBufEmit(secCode, $0B);     { end }
  end;
end;
```

---

## 12. ParseProgram Changes

Allow zero or more procedure/function declarations before the main `var` block:

```pascal
procedure ParseProgram;
begin
  Expect(tkProgram);
  if tokKind <> tkIdent then Error('expected program name');
  NextToken;
  Expect(tkSemicolon);
  { Procedure/function declarations }
  while (tokKind = tkProcedure) or (tokKind = tkFunction) do
    ParseProcDecl;
  { Main body variable declarations }
  if tokKind = tkVar then begin
    NextToken;
    ParseVarBlock;
  end;
  { Frame prologue }
  if curFrameSize > 0 then begin
    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Sub);
    EmitGlobalSet(0);
  end;
  { exitDepth = -1 in main: exit is not valid at top level }
  exitDepth := -1;
  Expect(tkBegin);
  ParseStatement;
  while tokKind = tkSemicolon do begin
    NextToken;
    if tokKind <> tkEnd then ParseStatement;
  end;
  Expect(tkEnd);
  { Frame epilogue }
  if curFrameSize > 0 then begin
    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Add);
    EmitGlobalSet(0);
  end;
  Expect(tkDot);
end;
```

---

## 13. InitModule Changes

Initialize new global variables:

```pascal
numFuncs         := 0;
CodeBufInit(funcBodies);
exitDepth        := -1;
hasPendingImport := false;
hasPendingExport := false;
numUserExports   := 0;
SmallBufInit(userExportsBuf);
```

---

## 14. Tests

### tests/recurse.pas

```pascal
program TestRecurse;

function Fib(n: integer): integer;
begin
  if n < 2 then
    Fib := n
  else
    Fib := Fib(n - 1) + Fib(n - 2)
end;

begin
  writeln(Fib(0));
  writeln(Fib(1));
  writeln(Fib(5));
  writeln(Fib(10))
end.
```

Expected output (`tests/recurse.expected`):
```
0
1
5
55
```

### tests/varparam.pas

```pascal
program TestVarParam;

procedure Swap(var a, b: integer);
var t: integer;
begin
  t := a;
  a := b;
  b := t
end;

var x, y: integer;
begin
  x := 10;
  y := 20;
  Swap(x, y);
  writeln(x);
  writeln(y)
end.
```

Expected: `20`, `10`.

### tests/varparam_recurse.pas

```pascal
program TestVarParamRecurse;

procedure Foo(var x: integer);
var local: integer;
begin
  if x = 99 then begin
    local := 0;
    x := 0;
    Foo(local);
    writeln(local);
    x := local;
  end else begin
    x := 42;
  end;
end;

var r: integer;
begin
  r := 99;
  Foo(r);
  writeln(r);
end.
```

Expected: `42`, `42`.

### tests/proc.pas (simple procedure with exit)

```pascal
program TestProc;

procedure PrintMax(a, b: integer);
begin
  if a > b then begin
    writeln(a);
    exit;
  end;
  writeln(b)
end;

begin
  PrintMax(3, 7);
  PrintMax(9, 2)
end.
```

Expected: `7`, `9`.

### Makefile additions

Add targets:
- `test-strap-recurse`
- `test-strap-varparam`
- `test-strap-varparam-recurse`
- `test-strap-proc`

And add them to the `test:` dependency list.

---

## 15. Implementation Order

1. Add constants: skProc, skFunc, tkExit, MaxFuncs, MaxParams.
2. Extend TSymEntry with isVarParam and isConstParam.
3. Add TFuncEntry type and global variables (funcs, numFuncs, funcBodies, exitDepth,
   pending import/export state).
4. Add `FindOrAddWasmType`, `EmitFramePtr`, `EmitLocalGet`, `EmitLocalSet`,
   `EnsureBuiltinImports`, `EmitExportEntry` helpers.
5. Modify `SkipBraceComment` and add `ParseDirective`.
6. Add `EXIT` to `LookupKeyword`.
7. Update `ParseExpression` (variable load with parameter/var-param cases; function
   call as expression).
8. Update `ParseStatement` (procedure/function call; function-name assignment;
   `exit`; exitDepth tracking in control flow).
9. Add `ParseProcDecl`.
10. Update `ParseProgram` to call `ParseProcDecl` in a loop.
11. Update `AssembleFunctionSection`, `AssembleExportSection`, `AssembleCodeSection`.
12. Update `InitModule`.
13. Write tests and update Makefile.

---

## 16. Known Risks and Watch-Outs

**WASM function index stability**: User function indices are computed as
`numImports + numDefinedFuncs` at declaration time. `EnsureBuiltinImports` is called
first to lock in fd_write and proc_exit. Any `{$IMPORT}` external declarations must
appear before non-external declarations in the source.

**exit block and exitDepth**: Every control-flow construct that adds a WASM block or
loop must increment exitDepth on entry and decrement on exit. Forgetting this causes
`exit` to branch to the wrong block depth, silently skipping the frame epilogue.

**varParams initialized before body**: `funcs[fslot].varParams[]` must be set before
ParseProcDecl compiles the body. Recursive calls inside the body use this array to
decide whether to pass addresses or values.

**Forward declaration re-parsing**: When filling in a forward, the full header (params,
types, return type) is re-parsed but discarded. The existing funcs[] slot is reused.

**Function return local index**: The hidden return local is at WASM local index
`nparams` (parameter locals are 0..nparams-1). The local is declared in AssembleCodeSection
as 1 group of 1 i32. The body ends with `local.get nparams`.

**Const parameter assignment**: Detected in the assignment path of ParseStatement when
`syms[s].isConstParam` is true — emit an error, do not store.

**Passing var params when arg is itself a var param**: If the caller is inside a
procedure where `x` is a var param, `x`'s WASM local already holds an address. Passing
`x` as a var param to a callee means passing that address directly, not computing a new
address. Check `syms[argSym].offset < 0 and syms[argSym].isVarParam`.
