# Chapter 8 Implementation Plan: Strings

## Overview

Turbo Pascal short strings: length byte + up to 255 characters. Strings live in the
stack frame (or data segment for literals). All string helpers are compiler-generated
WASM functions emitted lazily with empty stubs for unused helpers.

## Scope

This chapter implements:
- `string` and `string[N]` variable declarations
- String assignment (`s := 'hello'`, `s := t`)
- `writeln(s)` for string variables and literals (already works for literals)
- `length(s)` inline
- String comparison operators (`=`, `<>`, `<`, `>`, `<=`, `>=`)
- `readln(s)` for string input
- `concat(s, t, ...)` as expression intrinsic
- `copy(s, idx, count)` as expression intrinsic
- `pos(sub, s)` as expression intrinsic
- `delete(var s, idx, count)` as statement intrinsic
- `insert(src, var s, idx)` as statement intrinsic
- String parameters (always passed by address)

**Not in scope:** `s + t` string concatenation operator (use `concat()` instead).

## Step 1: New Constants

Add to the constants section:

```pascal
{ Type IDs — Chapter 8 }
tyString = 4;

{ WASM opcodes — Chapter 8 }
OpMiscPrefix  = $FC;  { prefix for bulk memory instructions }
OpMemCopy     = $0A;  { memory.copy suffix (after $FC prefix) }
OpLocalTee    = $22;  { local.tee }
OpSelect      = $1B;  { select }

{ WASM type indices — Chapter 8 }
TypeII_I      = 3;  { (i32,i32) -> i32      __str_compare, __str_pos }
TypeII_V      = 4;  { (i32,i32) -> ()       __read_str }
TypeIII_V     = 5;  { (i32,i32,i32) -> ()   __str_assign, __str_append, __str_delete, __str_insert }
TypeIII_I     = 6;  { (i32,i32,i32) -> i32  __str_copy }

{ String helper slot indices (relative to numImports) }
SlotStart     = 0;
SlotWriteInt  = 1;
SlotStrAssign = 2;
SlotWriteStr  = 3;
SlotStrComp   = 4;
SlotReadStr   = 5;
SlotStrAppend = 6;
SlotStrCopy   = 7;
SlotStrPos    = 8;
SlotStrDel    = 9;
SlotStrIns    = 10;

{ Total compiler-defined functions before any user function }
NumBuiltinFuncs = 11;

{ Built-in identifier tokens — Chapter 8 }
tkLength     = 210;
tkCopy       = 211;   { string copy function }
tkPos        = 212;
tkDelete     = 213;
tkInsert     = 214;
tkConcat     = 215;
tkStringType = 216;   { STRING keyword for type declarations }
```

## Step 2: TSymEntry Field Addition

Add `strMaxLen: longint` to the TSymEntry record. For string variables, this stores
the declared maximum character count (e.g., 255 for `string`, 10 for `string[10]`).
For non-string variables this field is unused (0).

```pascal
TSymEntry = record
  name:        string[63];
  kind:        longint;
  typ:         longint;
  level:       longint;
  offset:      longint;
  size:        longint;
  isVarParam:  boolean;
  isConstParam: boolean;
  strMaxLen:   longint;   { NEW: for tyString vars/params; 0 for other types }
end;
```

## Step 3: New Global Variables

Add to the global variables section:

```pascal
{ String helper state — Chapter 8 }
strHelpersReserved: boolean;   { true once EnsureStringHelpers has been called }
idxFdRead:     longint;        { fd_read import index; -1 until imported }
addrStrScratch: longint;       { 256-byte scratch buffer for copy/concat results }
addrReadBuf:   longint;        { 1-byte buffer for fd_read }

{ String helper need flags and WASM indices }
needStrAssign:  boolean;  idxStrAssign:  longint;
needWriteStr:   boolean;  idxWriteStr:   longint;
needStrCompare: boolean;  idxStrCompare: longint;
needReadStr:    boolean;  idxReadStr:    longint;
needStrAppend:  boolean;  idxStrAppend:  longint;
needStrCopy:    boolean;  idxStrCopy:    longint;
needStrPos:     boolean;  idxStrPos:     longint;
needStrDelete:  boolean;  idxStrDelete:  longint;
needStrInsert:  boolean;  idxStrInsert:  longint;

{ All string helper bodies concatenated (swap-startCode pattern) }
strHelperCode:  TCodeBuf;

{ Per-helper byte range within strHelperCode: [strHlpStart[i], strHlpStart[i]+strHlpLen[i]) }
strHlpStart: array[0..8] of longint;
strHlpLen:   array[0..8] of longint;

{ Expression type tracking: set by ParseExpression after each prefix expression }
lastExprType: longint;   { tyInteger, tyBoolean, tyChar, tyString, 0=unknown }
lastExprStrMax: longint; { strMaxLen of the expression when lastExprType=tyString }
```

## Step 4: InitModule Additions

In InitModule, after registering type 2 (FdWrite):

```pascal
{ Register type 3: (i32,i32) -> i32  for __str_compare, __str_pos }
wasmTypes[3].nparams    := 2;
wasmTypes[3].params[0]  := WasmI32;
wasmTypes[3].params[1]  := WasmI32;
wasmTypes[3].nresults   := 1;
wasmTypes[3].results[0] := WasmI32;
{ Register type 4: (i32,i32) -> ()  for __read_str }
wasmTypes[4].nparams   := 2;
wasmTypes[4].params[0] := WasmI32;
wasmTypes[4].params[1] := WasmI32;
wasmTypes[4].nresults  := 0;
{ Register type 5: (i32,i32,i32) -> ()  for __str_assign, __str_append, __str_delete, __str_insert }
wasmTypes[5].nparams   := 3;
wasmTypes[5].params[0] := WasmI32;
wasmTypes[5].params[1] := WasmI32;
wasmTypes[5].params[2] := WasmI32;
wasmTypes[5].nresults  := 0;
{ Register type 6: (i32,i32,i32) -> i32  for __str_copy }
wasmTypes[6].nparams    := 3;
wasmTypes[6].params[0]  := WasmI32;
wasmTypes[6].params[1]  := WasmI32;
wasmTypes[6].params[2]  := WasmI32;
wasmTypes[6].nresults   := 1;
wasmTypes[6].results[0] := WasmI32;
numWasmTypes := 7;
{ Chapter 8 state }
strHelpersReserved := false;
idxFdRead        := -1;
addrStrScratch   := -1;
addrReadBuf      := -1;
needStrAssign    := false;  idxStrAssign  := -1;
needWriteStr     := false;  idxWriteStr   := -1;
needStrCompare   := false;  idxStrCompare := -1;
needReadStr      := false;  idxReadStr    := -1;
needStrAppend    := false;  idxStrAppend  := -1;
needStrCopy      := false;  idxStrCopy    := -1;
needStrPos       := false;  idxStrPos     := -1;
needStrDelete    := false;  idxStrDelete  := -1;
needStrInsert    := false;  idxStrInsert  := -1;
CodeBufInit(strHelperCode);
lastExprType    := 0;
lastExprStrMax  := 0;
```

## Step 5: InitBuiltins — Add STRING Type

Add the `STRING` built-in type symbol:

```pascal
s := AddSym('STRING', skType, tyString);
syms[s].size      := 256;   { default string: 1 length byte + 255 chars }
syms[s].strMaxLen := 255;
```

## Step 6: EnsureStringHelpers

Called before any string helper is needed, and from EnsureBuiltinImports.
Reserves all 9 string helper slots and imports fd_read exactly once.

```pascal
procedure EnsureStringHelpers;
begin
  if strHelpersReserved then exit;
  strHelpersReserved := true;
  { Must be called after EnsureWriteInt to preserve slot layout }
  EnsureFdWrite;
  EnsureProcExit;
  EnsureWriteInt;  { _start=numImports+0, __write_int=numImports+1 }
  { Import fd_read (same type as fd_write) }
  if idxFdRead < 0 then
    idxFdRead := AddImport('wasi_snapshot_preview1', 'fd_read', TypeFdWrite);
  { Reserve 9 string helper slots: numImports+2 through numImports+10 }
  idxStrAssign  := numImports + SlotStrAssign;
  idxWriteStr   := numImports + SlotWriteStr;
  idxStrCompare := numImports + SlotStrComp;
  idxReadStr    := numImports + SlotReadStr;
  idxStrAppend  := numImports + SlotStrAppend;
  idxStrCopy    := numImports + SlotStrCopy;
  idxStrPos     := numImports + SlotStrPos;
  idxStrDelete  := numImports + SlotStrDel;
  idxStrInsert  := numImports + SlotStrIns;
  numDefinedFuncs := numDefinedFuncs + 9;  { slots 2..10 }
end;
```

## Step 7: EnsureBuiltinImports — Add String Helpers

Extend the existing EnsureBuiltinImports to also call EnsureStringHelpers:

```pascal
procedure EnsureBuiltinImports;
begin
  EnsureFdWrite;
  EnsureProcExit;
  EnsureWriteInt;
  EnsureStringHelpers;  { NEW: reserve string helper slots before user funcs }
end;
```

## Step 8: Individual Ensure*Helper Functions

Each function sets its need flag and (on first call) also ensures string helpers are reserved:

```pascal
function EnsureStrAssign: longint;
begin
  EnsureStringHelpers;
  EnsureIOBuffers;   { not needed directly, but ensures addr state is valid }
  needStrAssign := true;
  EnsureStrAssign := idxStrAssign;
end;

function EnsureWriteStr: longint;
begin
  EnsureStringHelpers;
  EnsureIOBuffers;
  needWriteStr := true;
  EnsureWriteStr := idxWriteStr;
end;

function EnsureStrCompare: longint;
begin
  EnsureStringHelpers;
  needStrCompare := true;
  EnsureStrCompare := idxStrCompare;
end;

function EnsureReadStr: longint;
begin
  EnsureStringHelpers;
  if addrReadBuf < 0 then
    addrReadBuf := AllocData(1);
  needReadStr := true;
  EnsureReadStr := idxReadStr;
end;

function EnsureStrAppend: longint;
begin
  EnsureStringHelpers;
  needStrAppend := true;
  EnsureStrAppend := idxStrAppend;
end;

function EnsureStrCopy: longint;
begin
  EnsureStringHelpers;
  if addrStrScratch < 0 then
    addrStrScratch := AllocData(256);
  needStrCopy := true;
  EnsureStrCopy := idxStrCopy;
end;

function EnsureStrPos: longint;
begin
  EnsureStringHelpers;
  needStrPos := true;
  EnsureStrPos := idxStrPos;
end;

function EnsureStrDelete: longint;
begin
  EnsureStringHelpers;
  needStrDelete := true;
  EnsureStrDelete := idxStrDelete;
end;

function EnsureStrInsert: longint;
begin
  EnsureStringHelpers;
  needStrInsert := true;
  EnsureStrInsert := idxStrInsert;
end;
```

## Step 9: EmitDataPascalString

Stores a Pascal-format string (length byte + chars) in the data segment.
Returns the start address (address of the length byte).

```pascal
function EmitDataPascalString(const s: string): longint;
var addr: longint;
    i:    longint;
begin
  addr := DataBase + dataLen;
  SmallBufEmit(dataBuf, length(s));  { length byte }
  dataLen := dataLen + 1;
  for i := 1 to length(s) do begin
    SmallBufEmit(dataBuf, ord(s[i]));
    dataLen := dataLen + 1;
  end;
  EmitDataPascalString := addr;
end;
```

## Step 10: EmitMemoryCopy Helper

```pascal
procedure EmitMemoryCopy;
{ Emit memory.copy 0 0 (extended opcode: FC 0A 00 00) }
begin
  CodeBufEmit(startCode, OpMiscPrefix);
  CodeBufEmit(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);  { dst_mem }
  CodeBufEmit(startCode, 0);  { src_mem }
end;
```

## Step 11: EmitStrAddr — Push Address of a String Variable

Used in ParseExpression and ParseStatement to push a string variable's address.

```pascal
procedure EmitStrAddr(s: longint);
{ Push address of string symbol s. For frame vars: $sp+offset+N. For var params: local value. }
var localIdx: longint;
begin
  if syms[s].offset < 0 then begin
    localIdx := -(syms[s].offset + 1);
    EmitLocalGet(localIdx);  { local holds pointer directly }
  end else begin
    EmitFramePtr(syms[s].level);
    EmitI32Const(syms[s].offset);
    EmitOp(OpI32Add);
  end;
end;
```

## Step 12: LookupKeyword Additions

Add to the if-else chain in LookupKeyword:

```pascal
else if s = 'LENGTH'   then LookupKeyword := tkLength
else if s = 'COPY'     then LookupKeyword := tkCopy
else if s = 'POS'      then LookupKeyword := tkPos
else if s = 'DELETE'   then LookupKeyword := tkDelete
else if s = 'INSERT'   then LookupKeyword := tkInsert
else if s = 'CONCAT'   then LookupKeyword := tkConcat
else if s = 'STRING'   then LookupKeyword := tkStringType;
```

Note: `STRING` in var declarations is recognized as a type keyword (tkStringType), not
the scanner-level tkString (which is for string literals). The scanner uses tkString = 3
for tokens like `'hello'`; the keyword `STRING` is now tkStringType = 216.

## Step 13: ParseVarBlock — String Type

In ParseVarBlock, after looking up the type symbol and finding it's a `STRING` type,
handle `string[N]` bracket syntax:

```pascal
{ After type identifier lookup: }
if syms[typSym].typ = tyString then begin
  grpTyp := tyString;
  if tokStr = 'STRING' then begin
    { Check for string[N] }
    NextToken;
    if tokKind = tkLBracket then begin
      NextToken;
      if tokKind <> tkInteger then
        Error('expected string max length');
      grpStrMax := tokInt;
      if (grpStrMax < 1) or (grpStrMax > 255) then
        Error('string length must be 1..255');
      NextToken;
      Expect(tkRBracket);
    end else
      grpStrMax := 255;
    grpSz := grpStrMax + 1;  { 1 length byte + N data bytes }
  end;
end;
```

When adding each variable to the symbol table:
```pascal
syms[s].strMaxLen := grpStrMax;
syms[s].level     := curNestLevel;
```

Also handle string types in ParseProcDecl's parameter list: after determining
`grpTyp = tyString`, similarly detect `STRING[N]` syntax and set the param's
strMaxLen to the declared max (or 255 for plain `string`).

For string parameters, regardless of var/const/value, the WASM local holds an
address (pointer). Value string params are simplified as const (no copy).

## Step 14: ParseExpression — String Support

Add `lastExprType` tracking. After each prefix case:

### String literal prefix

```pascal
tkString: begin
  { Store Pascal-format string in data segment; push its address }
  addr := EmitDataPascalString(tokStr);
  EmitI32Const(addr);
  lastExprType   := tyString;
  lastExprStrMax := length(tokStr);  { approximation; actual max = 255 }
  NextToken;
end;
```

### String variable prefix (inside tkIdent case)

When `syms[s].typ = tyString`:

```pascal
if syms[s].typ = tyString then begin
  EmitStrAddr(s);
  lastExprType   := tyString;
  lastExprStrMax := syms[s].strMaxLen;
end else begin
  EmitVarLoad(s);
  lastExprType := syms[s].typ;
end;
```

### `length(s)` prefix

```pascal
tkLength: begin
  NextToken;
  Expect(tkLParen);
  if tokKind <> tkIdent then
    Error('length requires a string variable');
  s := LookupSym(tokStr);
  if (s < 0) or (syms[s].typ <> tyString) then
    Error('length argument must be a string variable');
  NextToken;
  EmitStrAddr(s);
  EmitI32Load8u(0, 0);   { load length byte }
  Expect(tkRParen);
  lastExprType := tyInteger;
end;
```

### `copy(s, idx, count)` prefix

```pascal
tkCopy: begin
  NextToken;
  Expect(tkLParen);
  { First arg: string variable or expression }
  if (tokKind = tkIdent) then begin
    s := LookupSym(tokStr);
    if (s >= 0) and (syms[s].typ = tyString) then begin
      NextToken;
      EmitStrAddr(s);
    end else
      Error('copy: first arg must be a string');
  end else if tokKind = tkString then begin
    addr := EmitDataPascalString(tokStr);
    EmitI32Const(addr);
    NextToken;
  end else
    Error('copy: first arg must be a string');
  Expect(tkComma);
  ParseExpression(PrecNone);  { idx }
  Expect(tkComma);
  ParseExpression(PrecNone);  { count }
  Expect(tkRParen);
  EmitCall(EnsureStrCopy);
  EmitI32Const(addrStrScratch);  { push address of result }
  lastExprType   := tyString;
  lastExprStrMax := 255;
end;
```

Wait: `__str_copy(src, idx, count)` writes to addrStrScratch and returns void.
After the call, push addrStrScratch as the result address.

Actually it's cleaner to have __str_copy return i32 (the scratch address):
`idxStrCopy` uses TypeIII_I: `(i32,i32,i32) -> i32`. The helper always returns
`addrStrScratch` as its result. Then the expression result is naturally on the stack.

### `pos(sub, s)` prefix

```pascal
tkPos: begin
  NextToken;
  Expect(tkLParen);
  { sub: string var or literal }
  EmitStringArg;  { helper: push string address from var or literal }
  Expect(tkComma);
  EmitStringArg;  { s }
  Expect(tkRParen);
  EmitCall(EnsureStrPos);
  lastExprType := tyInteger;
end;
```

### `concat(s1, s2, ...)` prefix

```pascal
tkConcat: begin
  NextToken;
  Expect(tkLParen);
  { First arg: assign to scratch }
  EnsureStrScratch;  { allocate addrStrScratch if not yet done }
  { Zero the scratch buffer }
  EmitI32Const(addrStrScratch);
  EmitI32Const(0);
  EmitI32Store8(0, 0);
  { Append each argument }
  repeat
    EmitI32Const(addrStrScratch);  { dst }
    EmitI32Const(255);             { max_len }
    EmitStringArg;                 { src: next argument string address }
    EmitCall(EnsureStrAppend);
    if tokKind = tkComma then
      NextToken
    else
      break;
  until false;
  Expect(tkRParen);
  EmitI32Const(addrStrScratch);
  lastExprType   := tyString;
  lastExprStrMax := 255;
end;
```

The helper `EnsureStrScratch` ensures addrStrScratch is allocated (calls AllocData if needed).

### String comparison in the infix loop

In ParseExpression's infix loop, when `lastExprType = tyString` and the operator
is a comparison:

```pascal
{ Before parsing right side: save left string address }
{ Since left is on WASM stack, emit call to compare after right is parsed }
if (lastExprType = tyString) and
   ((op = tkEq) or (op = tkNe) or (op = tkLt) or
    (op = tkGt) or (op = tkLe) or (op = tkGe)) then begin
  NextToken;
  { Right side must also be a string }
  EmitStringArgExpr;  { parse string expression, push its address }
  EmitCall(EnsureStrCompare);  { compare(left, right) -> i32 }
  EmitI32Const(0);
  { Map operator to comparison against 0 }
  case op of
    tkEq: EmitOp(OpI32Eq);
    tkNe: EmitOp(OpI32Ne);
    tkLt: EmitOp(OpI32LtS);
    tkGt: EmitOp(OpI32GtS);
    tkLe: EmitOp(OpI32LeS);
    tkGe: EmitOp(OpI32GeS);
  end;
  lastExprType := tyBoolean;
end else begin
  { ... existing integer infix handling ... }
end;
```

The "left" side: when `lastExprType = tyString`, the address is on the WASM stack.
We emit the right side address, then call `__str_compare(left_addr, right_addr)`.
The result is -1/0/1 which we compare against 0 using the appropriate operator.

## Step 15: ParseStatement — String Operations

### String assignment (`s := expr`)

After identifying `s` as a `skVar` with `typ = tyString` and seeing `:=`:

```pascal
if syms[s].typ = tyString then begin
  { dst address }
  EmitStrAddr(s);
  EmitI32Const(syms[s].strMaxLen);
  { src address from right-hand side }
  ParseStringExpr;   { parse rhs: pushes string address }
  EmitCall(EnsureStrAssign);
end else begin
  { existing integer/boolean/char assignment }
end;
```

`ParseStringExpr` is a helper that parses an expression whose result is a string address.

### `writeln(s)` / `write(s)` for strings

In ParseWriteArgs, when the argument is a string type (variable or literal):

For a string literal: already handled by the existing EmitWriteString path.

For a string variable: call `__write_str(addr)` instead of loading the value:

```pascal
if (tokKind = tkIdent) and (s >= 0) and (syms[s].typ = tyString) then begin
  NextToken;
  EmitStrAddr(s);
  EmitCall(EnsureWriteStr);
end else begin
  { existing path: ParseExpression + __write_int }
end;
```

### `readln(s)` for strings

In ParseStatement, when `tokKind = tkReadln` and the argument is a string variable:

```pascal
if syms[s].typ = tyString then begin
  EmitStrAddr(s);
  EmitI32Const(syms[s].strMaxLen);
  EmitCall(EnsureReadStr);
end else begin
  { existing readln(integer) path }
end;
```

### `delete(var s, idx, count)` statement

```pascal
tkDelete: begin
  NextToken;
  Expect(tkLParen);
  if tokKind <> tkIdent then
    Error('delete: first arg must be a string variable');
  s := LookupSym(tokStr);
  if (s < 0) or (syms[s].typ <> tyString) then
    Error('delete: first arg must be a string');
  NextToken;
  EmitStrAddr(s);
  Expect(tkComma);
  ParseExpression(PrecNone);  { idx }
  Expect(tkComma);
  ParseExpression(PrecNone);  { count }
  Expect(tkRParen);
  EmitCall(EnsureStrDelete);
end;
```

### `insert(src, var s, idx)` statement

```pascal
tkInsert: begin
  NextToken;
  Expect(tkLParen);
  { src: string expression }
  ParseStringExprOrLit;
  Expect(tkComma);
  { dst: string variable (by address) }
  s := LookupSym(tokStr);
  EmitStrAddr(s);
  NextToken;
  Expect(tkComma);
  ParseExpression(PrecNone);  { idx }
  Expect(tkRParen);
  EmitCall(EnsureStrInsert);
end;
```

## Step 16: ParseCallArgs — String Parameters

When calling a user-defined function/procedure with string parameters:

For var string params: existing var-param handling (pass address) works since strings
are already accessed by address.

For const string params: similar to existing const handling — pass address.

For value string params: pass address (simplified; callee treats as const).

The key change in ParseCallArgs: when argument is a string variable (`syms[argSym].typ = tyString`),
push its address rather than loading its value. For string literal arguments: store in data
segment and push address.

The caller-side logic needs to recognize when a parameter is of string type and push
the string address instead of evaluating the expression normally.

## Step 17: String Helper Bodies

All built in WriteModule (after parsing is complete). Each uses swap-startCode.

### `__str_assign(dst i32, max_len i32, src i32)` → ()

Locals: param 0=dst, param 1=max_len, param 2=src, local 3=copy_len.

```
copy_len = load8_u(src, 0)
if copy_len > max_len: copy_len = max_len
store8(dst, copy_len)
memory.copy(dst+1, src+1, copy_len)
```

```wasm
;; copy_len = src length
local.get 2
i32.load8_u 0 0
local.set 3
;; clamp to max_len
block $done
  local.get 3
  local.get 1
  i32.le_s
  br_if 0
  local.get 1
  local.set 3
end
;; dst[0] = copy_len
local.get 0
local.get 3
i32.store8 0 0
;; memory.copy(dst+1, src+1, copy_len)
local.get 0
i32.const 1
i32.add
local.get 2
i32.const 1
i32.add
local.get 3
memory.copy 0 0
end
```

### `__write_str(addr i32)` → ()

Locals: param 0=addr, local 1=len.
Uses addrIovec, addrNwritten, idxFdWrite (all known at build time).

```
len = load8_u(addr, 0)
iovec.ptr = addr + 1
iovec.len = len
if len > 0: fd_write(1, addrIovec, 1, addrNwritten); drop
```

### `__str_compare(a i32, b i32)` → i32

Locals: param 0=a, param 1=b, local 2=len_a, local 3=len_b, local 4=min_len, local 5=i.

```
len_a = load8_u(a)
len_b = load8_u(b)
min_len = if len_a < len_b then len_a else len_b
for i = 1 to min_len:
  ca = load8_u(a+i)
  cb = load8_u(b+i)
  if ca < cb: return -1
  if ca > cb: return 1
if len_a < len_b: return -1
if len_a > len_b: return 1
return 0
```

WASM: Use `block` + `br` for early returns, `loop` for the scan.

### `__read_str(addr i32, max_len i32)` → ()

Locals: param 0=addr, param 1=max_len, local 2=count, local 3=byte_val.
Uses addrReadBuf, idxFdRead.

```
count = 0
loop:
  if count >= max_len: break
  fd_read(0, &iovec(addrReadBuf, 1), 1, &nwritten)
  drop result
  byte_val = load8_u(addrReadBuf)
  if byte_val = 10: break  (newline)
  store8(addr + 1 + count, byte_val)
  count += 1
  br loop
addr[0] = count
```

Actually use the addrIovec for the read iovec too (set iovec.ptr = addrReadBuf, iovec.len = 1).

### `__str_append(dst i32, max_len i32, src i32)` → ()

Locals: param 0=dst, param 1=max_len, param 2=src, local 3=dst_len, local 4=src_len,
local 5=avail, local 6=copy_len.

```
dst_len  = load8_u(dst)
src_len  = load8_u(src)
avail    = max_len - dst_len
if avail <= 0: return
copy_len = if src_len <= avail then src_len else avail
memory.copy(dst + 1 + dst_len, src + 1, copy_len)
dst[0] = dst_len + copy_len
```

### `__str_copy(src i32, idx i32, count i32)` → i32

Locals: param 0=src, param 1=idx (1-based), param 2=count, local 3=src_len,
local 4=actual_start, local 5=avail, local 6=actual_count.

Returns addrStrScratch.

```
src_len     = load8_u(src)
actual_start = idx - 1   (0-based)
if actual_start >= src_len: scratch[0]=0; return addrStrScratch
avail       = src_len - actual_start
actual_count = if count <= avail then count else avail
scratch[0]  = actual_count
memory.copy(addrStrScratch+1, src+1+actual_start, actual_count)
return addrStrScratch
```

### `__str_pos(sub i32, s i32)` → i32

Locals: param 0=sub, param 1=s, local 2=sub_len, local 3=s_len,
local 4=i, local 5=j, local 6=match.

```
sub_len = load8_u(sub)
s_len   = load8_u(s)
if sub_len = 0: return 1
for i = 0 to s_len - sub_len:
  match = true
  for j = 0 to sub_len - 1:
    if load8_u(s+1+i+j) <> load8_u(sub+1+j):
      match = false; break
  if match: return i+1  (1-based)
return 0
```

### `__str_delete(s i32, idx i32, count i32)` → ()

Locals: param 0=s, param 1=idx (1-based), param 2=count, local 3=s_len,
local 4=actual_idx, local 5=actual_count, local 6=tail_start, local 7=tail_len.

```
s_len       = load8_u(s)
actual_idx  = if idx < 1 then 0 else idx - 1   (0-based)
if actual_idx >= s_len: return
actual_count = if actual_idx + count > s_len then s_len - actual_idx else count
tail_start   = actual_idx + actual_count
tail_len     = s_len - tail_start
memory.copy(s+1+actual_idx, s+1+tail_start, tail_len)
s[0] = s_len - actual_count
```

### `__str_insert(src i32, dst i32, idx i32)` → ()

Locals: param 0=src, param 1=dst, param 2=idx (1-based), local 3=src_len,
local 4=dst_len, local 5=dst_max, local 6=actual_idx, local 7=avail,
local 8=move_count, local 9=insert_count.

```
src_len    = load8_u(src)
dst_len    = load8_u(dst)
actual_idx = if idx < 1 then 0 else idx - 1   (0-based)
if actual_idx > dst_len: actual_idx = dst_len
avail      = 255 - dst_len    { use 255 as max since we don't pass max_len }
if avail <= 0: return
insert_count = if src_len <= avail then src_len else avail
move_count   = dst_len - actual_idx
{ shift tail right to make room }
{ must copy backwards to handle overlap: use memmove semantics }
{ WASM memory.copy handles overlaps correctly }
memory.copy(dst+1+actual_idx+insert_count, dst+1+actual_idx, move_count)
{ insert src }
memory.copy(dst+1+actual_idx, src+1, insert_count)
dst[0] = dst_len + insert_count
```

Note: `memory.copy` in WASM handles overlapping regions correctly (like memmove).

## Step 18: Building Helpers (BuildStringHelpers)

Add `BuildStringHelpers` (called from WriteModule):

```pascal
procedure BuildStringHelpers;
begin
  if needStrAssign  then BuildStrAssignHelper;
  if needWriteStr   then BuildWriteStrHelper;
  if needStrCompare then BuildStrCompareHelper;
  if needReadStr    then BuildReadStrHelper;
  if needStrAppend  then BuildStrAppendHelper;
  if needStrCopy    then BuildStrCopyHelper;
  if needStrPos     then BuildStrPosHelper;
  if needStrDelete  then BuildStrDeleteHelper;
  if needStrInsert  then BuildStrInsertHelper;
end;
```

Each `Build*Helper` procedure:
1. Saves `startCode` into a local `TCodeBuf`
2. Resets `startCode`
3. Emits WASM bytecodes using EmitXxx procedures
4. Records start/len in strHlpStart[i]/strHlpLen[i]
5. Copies `startCode` bytes into `strHelperCode`
6. Restores `startCode`

Helper index mapping: helpers are 0-indexed in strHlp arrays.

## Step 19: AssembleFunctionSection Changes

After `if needWriteInt then SmallBufEmit(secFunc, TypeI32Void)`, add:

```pascal
if strHelpersReserved then begin
  SmallBufEmit(secFunc, TypeIII_V);   { __str_assign: (i32,i32,i32)->() }
  SmallBufEmit(secFunc, TypeI32Void); { __write_str: (i32)->() }
  SmallBufEmit(secFunc, TypeII_I);    { __str_compare: (i32,i32)->i32 }
  SmallBufEmit(secFunc, TypeII_V);    { __read_str: (i32,i32)->() }
  SmallBufEmit(secFunc, TypeIII_V);   { __str_append: (i32,i32,i32)->() }
  SmallBufEmit(secFunc, TypeIII_I);   { __str_copy: (i32,i32,i32)->i32 }
  SmallBufEmit(secFunc, TypeII_I);    { __str_pos: (i32,i32)->i32 }
  SmallBufEmit(secFunc, TypeIII_V);   { __str_delete: (i32,i32,i32)->() }
  SmallBufEmit(secFunc, TypeIII_V);   { __str_insert: (i32,i32,i32)->() }
end;
```

## Step 20: AssembleCodeSection Changes

After the `__write_int` body block, add 9 string helper bodies:

```pascal
if strHelpersReserved then begin
  for j := 0 to 8 do
    EmitStringHelperBody(j);
end;
```

`EmitStringHelperBody(j)` emits the body for helper j:
- If needXxx[j]: emit full body from strHelperCode[strHlpStart[j]..+strHlpLen[j]]
- Else: emit stub body (0 locals, end only)

Each body has a local declarations header before the bytecodes. The local counts per helper:
- 0 (__str_assign): 1 extra local (copy_len i32)
- 1 (__write_str): 1 extra local (len i32)
- 2 (__str_compare): 4 extra locals (len_a, len_b, min_len, i — all i32)
- 3 (__read_str): 2 extra locals (count, byte_val — all i32)
- 4 (__str_append): 4 extra locals (dst_len, src_len, avail, copy_len)
- 5 (__str_copy): 4 extra locals (src_len, actual_start, avail, actual_count)
- 6 (__str_pos): 4 extra locals (sub_len, s_len, i, j) + flag (match)
- 7 (__str_delete): 5 extra locals (s_len, actual_idx, actual_count, tail_start, tail_len)
- 8 (__str_insert): 7 extra locals (src_len, dst_len, actual_idx, avail, move_count, insert_count, + spare)

The function section records N params + M extra locals. Extra locals are declared as
one group of M x i32 (since all are i32).

## Step 21: WriteModule Changes

```pascal
procedure WriteModule;
begin
  if strHelpersReserved then
    BuildStringHelpers;
  if needWriteInt then
    BuildWriteIntHelper;
  ...
end;
```

## Step 22: Test Programs

### t030_string_basic.pas

```pascal
program t030_string_basic;
var
  s: string;
  t: string[10];
begin
  s := 'Hello, world!';
  writeln(s);
  t := s;
  writeln(t);
  writeln(length(s));
  writeln(length(t));
end.
```

Expected output:
```
Hello, world!
Hello, wor
13
10
```

### t031_string_compare.pas

```pascal
program t031_string_compare;
var s, t: string;
begin
  s := 'abc';
  t := 'abc';
  if s = t then writeln('equal') else writeln('not equal');
  t := 'abd';
  if s < t then writeln('less') else writeln('not less');
end.
```

Expected: `equal` then `less`.

### t032_string_funcs.pas

```pascal
program t032_string_funcs;
var s, t, u: string;
    i: integer;
begin
  s := 'hello world';
  t := copy(s, 7, 5);
  writeln(t);
  i := pos('world', s);
  writeln(i);
  s := 'abcdefgh';
  delete(s, 3, 2);
  writeln(s);
  s := 'abcdef';
  t := 'XY';
  insert(t, s, 3);
  writeln(s);
  s := 'one';
  t := ' two';
  u := concat(s, t, ' three');
  writeln(u);
end.
```

Expected: `world`, `7`, `abefgh`, `abXYcdef`, `one two three`.

### t033_readln_string.pas

```pascal
program t033_readln_string;
var s: string; t: string[5];
begin
  readln(s);
  writeln(s);
  writeln(length(s));
  readln(t);
  writeln(t);
  writeln(length(t));
end.
```

With input `Hello` / `Testing`: outputs `Hello`, `5`, `Testi`, `5`.

## Key Risks and Notes

1. **EnsureStringHelpers ordering**: Must be called before any user function is declared.
   `EnsureBuiltinImports` (called from ParseProcDecl) must call `EnsureStringHelpers`.
   For programs with no user functions that use strings, call EnsureStringHelpers from
   the first Ensure*Helper function.

2. **Stub bodies for unused helpers**: WASM requires function section count to match code
   section count. All 9 helper slots in the function section must have bodies in the code
   section, even if the helper is unused. Emit `[0 locals][end]` as stub.

3. **addrStrScratch must be allocated before WriteModule**: `AllocData` changes the data
   segment, which is serialized in AssembleDataSection. Call EnsureStrCopy (or an explicit
   `EnsureStrScratch`) during parsing, not during WriteModule.

4. **No brace chars in brace comments**: Any helper-related comments that mention the
   helpers' signatures must not use braces inside `{ }` comments.

5. **lastExprType and recursion**: `ParseExpression` is recursive. `lastExprType` is a
   global that gets overwritten by recursive calls. Only read `lastExprType` immediately
   after a prefix parse (before any recursive call for the right side).

6. **String comparison left operand**: After parsing `a` (string), its address is on the
   WASM stack. When we then parse `b` for `a = b`, `b`'s address ends up on top.
   `__str_compare(a, b)` receives (a_addr, b_addr) in left-to-right order because WASM
   function arguments are pushed in order (first arg pushed first, last arg on top).
   This is correct: `a` is pushed first (by the prefix parse), then `b`.

7. **`tkString` vs `tkStringType`**: Ensure the scanner does NOT return `tkStringType`
   for string literals. The `LookupKeyword` change handles this: `STRING` (the type
   keyword) is looked up from identifier tokens, while string literals (`'hello'`) still
   produce `tkString = 3`.

8. **String parameters and ParseCallArgs**: When a user function takes string parameters,
   ParseCallArgs must push the string address (like a var-param). Add logic in ParseCallArgs
   to detect string-typed parameters and push addresses appropriately.

9. **Function section count**: `numDefinedFuncs` includes all 11 builtin slots plus user
   functions. AssembleFunctionSection must emit 11 type entries for builtin functions
   (1 _start + 1 __write_int + 9 string helpers) plus one per user function.
   The count byte at the start of the function section uses `numDefinedFuncs`.

10. **memory.copy alignment**: `memory.copy` with alignment=1 is always safe for
    byte-at-a-time string data. No alignment requirement for strings.

## Plan vs. Implementation

After completing the implementation, compare this plan to what was actually done and
record deviations in NOTES.md under "Chapter 8: Strings".
