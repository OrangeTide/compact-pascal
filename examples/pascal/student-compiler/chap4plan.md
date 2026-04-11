# Chapter 4 Implementation Plan: Variables and I/O

## Goal

By the end of Chapter 4, the compiler handles:

```pascal
program hello;
begin
  writeln('Hello, world!')
end.
```

```pascal
program vars;
var x: integer;
begin
  x := 42;
  writeln(x)
end.
```

The chapter adds:

- Symbol table with built-in types and scope tracking
- `var` declarations for integer, boolean, and char variables
- Assignment statements (`:=`)
- Variable loads in expressions (identifier → memory load)
- `write` and `writeln` with string literal and integer expression arguments
- Data segment for string literals and I/O scratch buffers (WASM data section)
- `__write_int` helper function for integer-to-decimal conversion
- `fd_write` WASI import
- Frame prologue/epilogue in the main program block

## Current State (end of Chapter 3)

- Scanner: complete
- Parser: `program P; begin halt(expr) end.` with full expression support
- Code generation: `halt`, arithmetic, comparisons, bitwise ops
- No symbol table, no variables, no I/O beyond `halt`

## What Does NOT Change

- All scanner code
- Buffer infrastructure (SmallBuf, CodeBuf, LEB128 emitters)
- `EmitOp`, `EmitI32Const`, `EmitCall` (these still target `startCode`)
- `AddImport`, `EnsureProcExit`
- `ParseExpression` infix handling
- `ParseStatement` halt and begin/end arms
- `Expect`, `Error`

---

## Memory Layout

Variables live in WASM linear memory, not WASM locals. Layout:

```
Address 0:    [nil guard — 4 bytes, zeroed]
Address 4:    [data segment — string literals, iovec, scratch buffers]
              ...grows upward...
              ...empty space...
              [stack — grows downward]
Address 65536: [initial $sp]
```

The stack pointer is WASM global 0 (`$sp`). On entry to the main block, the compiler subtracts `curFrameSize` from `$sp` (frame prologue). On exit, it adds it back (frame epilogue). Variables are accessed at fixed offsets from `$sp`.

The data segment is assembled into a WASM data section (ID=11) at WriteModule time.

---

## Step 1: New Constants

Add to the const section:

```pascal
{ WASM opcodes — Chapter 4 }
OpGlobalGet = $23;
OpGlobalSet = $24;
OpI32Load   = $28;
OpI32Load8u = $2D;
OpI32Store  = $36;
OpI32Store8 = $3A;
OpLocalGet  = $20;
OpLocalSet  = $21;
OpIf        = $04;
OpElse      = $05;
OpBlock     = $02;
OpLoop      = $03;
OpBr        = $0C;
OpBrIf      = $0D;
OpReturn    = $0F;
WasmVoid    = $40;  { block type: void (= -64 as signed byte) }

{ WASM type index }
TypeFdWrite = 2;    { (i32,i32,i32,i32) -> i32  for fd_write }

{ WASM section ID }
SecIdData = 11;

{ Symbol kinds }
skVar  = 1;
skType = 2;

{ Type IDs }
tyInteger = 1;
tyBoolean = 2;
tyChar    = 3;

{ Symbol table limits }
MaxSyms      = 1024;
MaxScopDepth = 32;

{ Data segment base address — address 0 is nil guard }
DataBase = 4;
```

---

## Step 2: New Types

Add to the type section (after `TWasmType`):

```pascal
TSymEntry = record
  name:   string[63];
  kind:   longint;    { skVar, skType }
  typ:    longint;    { tyInteger, tyBoolean, tyChar }
  level:  longint;
  offset: longint;    { frame offset for vars }
  size:   longint;    { byte size: 4 for integer, 1 for char/boolean }
end;
```

---

## Step 3: New Global Variables

Add to the var block:

```pascal
{ Symbol table }
syms:       array[0..MaxSyms-1] of TSymEntry;
numSyms:    longint;
scopeBase:  array[0..MaxScopDepth-1] of longint;
scopeDepth: longint;

{ Frame allocation }
curFrameSize: longint;

{ Data segment }
dataBuf:  TSmallBuf;   { data segment content, starts at address DataBase }
dataLen:  longint;     { bytes emitted into dataBuf so far }

{ I/O scratch addresses in data segment; -1 until allocated }
addrIovec:    longint;
addrNwritten: longint;
addrNewline:  longint;
addrIntBuf:   longint;  { 20-byte scratch for integer-to-decimal }

{ Import indices }
idxFdWrite:  longint;   { -1 until imported }

{ Helper function state }
idxWriteInt:  longint;  { -1 until registered }
needWriteInt: boolean;
helperCode:   TCodeBuf; { __write_int body instructions }
```

---

## Step 4: Update InitModule

Add after existing body:

```pascal
{ Symbol table }
numSyms    := 0;
scopeDepth := 0;
curFrameSize := 0;

{ Data segment }
SmallBufInit(dataBuf);
dataLen      := 0;
addrIovec    := -1;
addrNwritten := -1;
addrNewline  := -1;
addrIntBuf   := -1;

{ Chapter 4 imports }
idxFdWrite  := -1;

{ Helper function }
idxWriteInt  := -1;
needWriteInt := false;
CodeBufInit(helperCode);

{ Register type 2: (i32,i32,i32,i32) -> i32 for fd_write }
wasmTypes[2].nparams   := 4;
wasmTypes[2].params[0] := WasmI32;
wasmTypes[2].params[1] := WasmI32;
wasmTypes[2].params[2] := WasmI32;
wasmTypes[2].params[3] := WasmI32;
wasmTypes[2].nresults  := 1;
wasmTypes[2].results[0] := WasmI32;
numWasmTypes := 3;
```

---

## Step 5: Symbol Table Procedures

```pascal
procedure EnterScope;
begin
  scopeDepth := scopeDepth + 1;
  scopeBase[scopeDepth] := numSyms;
end;

procedure LeaveScope;
begin
  numSyms    := scopeBase[scopeDepth];
  scopeDepth := scopeDepth - 1;
end;

function LookupSym(const name: string): longint;
var i: longint;
begin
  LookupSym := -1;
  for i := numSyms - 1 downto 0 do
    if syms[i].name = name then begin
      LookupSym := i;
      exit;
    end;
end;

function AddSym(const name: string; kind, typ: longint): longint;
begin
  if numSyms >= MaxSyms then
    Error('symbol table overflow');
  syms[numSyms].name  := name;
  syms[numSyms].kind  := kind;
  syms[numSyms].typ   := typ;
  syms[numSyms].level := scopeDepth;
  AddSym := numSyms;
  numSyms := numSyms + 1;
end;

procedure InitBuiltins;
var s: longint;
begin
  s := AddSym('INTEGER', skType, tyInteger);
  syms[s].size := 4;
  s := AddSym('LONGINT', skType, tyInteger);
  syms[s].size := 4;
  s := AddSym('BOOLEAN', skType, tyBoolean);
  syms[s].size := 1;
  s := AddSym('CHAR', skType, tyChar);
  syms[s].size := 1;
end;
```

`InitBuiltins` is called from `InitModule`. Names are stored uppercased to match scanner output.

---

## Step 6: Data Segment Procedures

```pascal
function AllocData(nbytes: longint): longint;
{ Reserves nbytes in dataBuf, returns the linear memory address. }
var addr: longint;
begin
  addr    := DataBase + dataLen;
  dataLen := dataLen + nbytes;
  while dataBuf.len < dataLen do
    SmallBufEmit(dataBuf, 0);
  AllocData := addr;
end;

function EmitDataString(const s: string): longint;
{ Places s into the data segment; returns its start address. }
var addr: longint;
    i:    longint;
begin
  addr := DataBase + dataLen;
  for i := 1 to length(s) do begin
    SmallBufEmit(dataBuf, ord(s[i]));
    dataLen := dataLen + 1;
  end;
  EmitDataString := addr;
end;

procedure EnsureIOBuffers;
{ Lazily allocates iovec (8 bytes), nwritten (4 bytes),
  newline byte, and int scratch (20 bytes) in the data segment. }
begin
  if addrIovec >= 0 then exit;
  addrIovec    := AllocData(8);   { iovec: ptr(4) + len(4) }
  addrNwritten := AllocData(4);   { nwritten return value }
  addrNewline  := AllocData(1);   { newline character }
  dataBuf.data[addrNewline - DataBase] := 10;  { '\n' }
  addrIntBuf   := AllocData(20);  { decimal digit scratch }
end;
```

---

## Step 7: New Emit Helpers

These emit into `startCode` (same as existing helpers):

```pascal
procedure EmitGlobalGet(idx: longint);
begin
  CodeBufEmit(startCode, OpGlobalGet);
  EmitULEB128(startCode, idx);
end;

procedure EmitGlobalSet(idx: longint);
begin
  CodeBufEmit(startCode, OpGlobalSet);
  EmitULEB128(startCode, idx);
end;

procedure EmitI32Load(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Load);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
end;

procedure EmitI32Store(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Store);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
end;

procedure EmitI32Load8u(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Load8u);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
end;

procedure EmitI32Store8(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Store8);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
end;
```

---

## Step 8: EnsureFdWrite and EnsureWriteInt

```pascal
function EnsureFdWrite: longint;
begin
  if idxFdWrite < 0 then
    idxFdWrite := AddImport('wasi_snapshot_preview1', 'fd_write', TypeFdWrite);
  EnsureFdWrite := idxFdWrite;
end;

function EnsureWriteInt: longint;
begin
  if idxWriteInt >= 0 then begin
    EnsureWriteInt := idxWriteInt;
    exit;
  end;
  { Register all imports that will ever be needed before locking in
    __write_int's function index. This keeps idxWriteInt stable. }
  EnsureFdWrite;
  EnsureProcExit;
  { _start = numImports + 0; __write_int = numImports + 1 }
  idxWriteInt   := numImports + 1;
  needWriteInt  := true;
  numDefinedFuncs := numDefinedFuncs + 1;
  EnsureWriteInt := idxWriteInt;
end;
```

**Import index stability:** `EnsureWriteInt` eagerly imports both `fd_write` and
`proc_exit` so that `numImports` is final before `idxWriteInt` is computed. Any
subsequent `EnsureProcExit`/`EnsureFdWrite` calls are no-ops. This means programs
that use `writeln` will always import both; programs that use only `halt` import only
`proc_exit`.

---

## Step 9: BuildWriteIntHelper

This procedure emits the `__write_int` WASM function body into `helperCode`. It is
called from `WriteModule` after parsing is complete (when all import indices are
final). The function takes one `i32` parameter (the value to print) and uses two
additional locals: `pos` (local 1, current write position) and `neg` (local 2, sign
flag).

Algorithm: negate negative values and record the sign, handle zero explicitly, extract
decimal digits right-to-left into `addrIntBuf`, prepend `'-'` if negative, then call
`fd_write`.

```pascal
procedure BuildWriteIntHelper;
{ Emits __write_int body into helperCode using direct CodeBufEmit calls.
  Must be called after all imports are registered (addrIovec etc. must be allocated). }
var
  bufEnd: longint;   { addrIntBuf + 20 }

  procedure HEmit(b: byte);
  begin
    CodeBufEmit(helperCode, b);
  end;

  procedure HEmitULEB128(v: longint);
  begin
    EmitULEB128(helperCode, v);
  end;

  procedure HEmitSLEB128(v: longint);
  begin
    EmitSLEB128(helperCode, v);
  end;

  procedure HLocalGet(idx: longint);
  begin
    HEmit(OpLocalGet); HEmitULEB128(idx);
  end;

  procedure HLocalSet(idx: longint);
  begin
    HEmit(OpLocalSet); HEmitULEB128(idx);
  end;

  procedure HI32Const(n: longint);
  begin
    HEmit(OpI32Const); HEmitSLEB128(n);
  end;

  procedure HCall(idx: longint);
  begin
    HEmit(OpCall); HEmitULEB128(idx);
  end;

begin
  EnsureIOBuffers;
  bufEnd := addrIntBuf + 20;

  { pos = bufEnd }
  HI32Const(bufEnd); HLocalSet(1);
  { neg = 0 }
  HI32Const(0); HLocalSet(2);

  { if value < 0: neg=1, value = -value }
  HLocalGet(0); HI32Const(0); HEmit(OpI32LtS);
  HEmit(OpIf); HEmit(WasmVoid);
    HI32Const(1); HLocalSet(2);
    HI32Const(0); HLocalGet(0); HEmit(OpI32Sub); HLocalSet(0);
  HEmit(OpEnd);

  { if value == 0: write '0' }
  HLocalGet(0); HEmit(OpI32Eqz);
  HEmit(OpIf); HEmit(WasmVoid);
    { pos-- }
    HLocalGet(1); HI32Const(1); HEmit(OpI32Sub); HLocalSet(1);
    { mem[pos] = '0' }
    HLocalGet(1); HI32Const(48); HEmit(OpI32Store8); HEmit(0); HEmit(0);
  HEmit(OpElse);
    { digit loop }
    HEmit(OpBlock); HEmit(WasmVoid);
      HEmit(OpLoop); HEmit(WasmVoid);
        HLocalGet(0); HEmit(OpI32Eqz); HEmit(OpBrIf); HEmit(1);
        HLocalGet(1); HI32Const(1); HEmit(OpI32Sub); HLocalSet(1);
        HLocalGet(1);
        HLocalGet(0); HI32Const(10); HEmit(OpI32RemS);
        HI32Const(48); HEmit(OpI32Add);
        HEmit(OpI32Store8); HEmit(0); HEmit(0);
        HLocalGet(0); HI32Const(10); HEmit(OpI32DivS); HLocalSet(0);
        HEmit(OpBr); HEmit(0);
      HEmit(OpEnd);  { loop }
    HEmit(OpEnd);    { block }
  HEmit(OpEnd);  { if/else }

  { if neg: pos--, mem[pos] = '-' }
  HLocalGet(2);
  HEmit(OpIf); HEmit(WasmVoid);
    HLocalGet(1); HI32Const(1); HEmit(OpI32Sub); HLocalSet(1);
    HLocalGet(1); HI32Const(45); HEmit(OpI32Store8); HEmit(0); HEmit(0);
  HEmit(OpEnd);

  { Set iovec.buf = pos }
  HI32Const(addrIovec); HLocalGet(1);
  HEmit(OpI32Store); HEmit(2); HEmit(0);
  { Set iovec.len = bufEnd - pos }
  HI32Const(addrIovec + 4);
  HI32Const(bufEnd); HLocalGet(1); HEmit(OpI32Sub);
  HEmit(OpI32Store); HEmit(2); HEmit(0);
  { fd_write(1, addrIovec, 1, addrNwritten) }
  HI32Const(1);
  HI32Const(addrIovec);
  HI32Const(1);
  HI32Const(addrNwritten);
  HCall(idxFdWrite);
  HEmit(OpDrop);
end;
```

---

## Step 10: EmitWriteString, EmitWriteNewline, EmitWriteInt

High-level emit procedures that target `startCode`:

```pascal
procedure EmitWriteString(addr, len: longint);
begin
  EnsureIOBuffers;
  { iovec.buf = addr }
  EmitI32Const(addrIovec);
  EmitI32Const(addr);
  EmitI32Store(2, 0);
  { iovec.len = len }
  EmitI32Const(addrIovec + 4);
  EmitI32Const(len);
  EmitI32Store(2, 0);
  { fd_write(1, iovec, 1, nwritten) }
  EmitI32Const(1);
  EmitI32Const(addrIovec);
  EmitI32Const(1);
  EmitI32Const(addrNwritten);
  EmitCall(EnsureFdWrite);
  EmitOp(OpDrop);
end;

procedure EmitWriteNewline;
begin
  EnsureIOBuffers;
  EmitWriteString(addrNewline, 1);
end;

procedure EmitWriteInt;
begin
  EmitCall(EnsureWriteInt);
end;
```

---

## Step 11: Update AssembleFunctionSection

Replace the current single-entry body:

```pascal
procedure AssembleFunctionSection;
var i: longint;
begin
  SmallBufInit(secFunc);
  SmallBufEmit(secFunc, numDefinedFuncs);
  SmallBufEmit(secFunc, TypeVoidVoid);  { _start: () -> () }
  if needWriteInt then
    SmallBufEmit(secFunc, TypeI32Void); { __write_int: (i32) -> () }
end;
```

---

## Step 12: Update AssembleCodeSection

Extend to emit `__write_int` body after `_start`:

```pascal
procedure AssembleCodeSection;
var bodyLen, i: longint;
begin
  CodeBufInit(secCode);
  EmitULEB128(secCode, numDefinedFuncs);

  { _start body: 0 locals }
  bodyLen := 1 + startCode.len + 1;
  EmitULEB128(secCode, bodyLen);
  CodeBufEmit(secCode, 0);
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(secCode, startCode.data[i]);
  CodeBufEmit(secCode, OpEnd);

  { __write_int body: 2 additional locals (pos, neg) }
  if needWriteInt then begin
    bodyLen := 3 + helperCode.len + 1;
    { 3 = local_decl_count(1) + count(2) + type($7F) }
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);    { 1 local group }
    CodeBufEmit(secCode, 2);    { 2 locals }
    CodeBufEmit(secCode, WasmI32);
    for i := 0 to helperCode.len - 1 do
      CodeBufEmit(secCode, helperCode.data[i]);
    CodeBufEmit(secCode, OpEnd);
  end;
end;
```

---

## Step 13: New AssembleDataSection

```pascal
procedure AssembleDataSection;
var i: longint;
begin
  SmallBufInit(secData);
  if dataBuf.len = 0 then exit;
  SmallBufEmit(secData, 1);    { 1 segment }
  SmallBufEmit(secData, 0);    { flags: active, default memory }
  { offset expression: i32.const DataBase (=4); end }
  SmallBufEmit(secData, $41);
  SmallEmitULEB128(secData, DataBase);
  SmallBufEmit(secData, $0B);
  SmallEmitULEB128(secData, dataBuf.len);
  for i := 0 to dataBuf.len - 1 do
    SmallBufEmit(secData, dataBuf.data[i]);
end;
```

Add `secData: TSmallBuf` to global variables.

---

## Step 14: Update WriteModule

Add two lines after `AssembleCodeSection`:

```pascal
BuildWriteIntHelper;     { builds helperCode; must be after all parsing is done }
AssembleCodeSection;
AssembleDataSection;
...
WriteSection(SecIdData, secData);
```

The full ordering becomes:

```pascal
procedure WriteModule;
begin
  CodeBufInit(outBuf);
  if needWriteInt then
    BuildWriteIntHelper;
  AssembleTypeSection;
  AssembleImportSection;
  AssembleFunctionSection;
  AssembleMemorySection;
  AssembleGlobalSection;
  AssembleExportSection;
  AssembleCodeSection;
  AssembleDataSection;

  { WASM header }
  ...

  WriteSection(SecIdType,   secType);
  WriteSection(SecIdImport, secImport);
  WriteSection(SecIdFunc,   secFunc);
  WriteSection(SecIdMemory, secMemory);
  WriteSection(SecIdGlobal, secGlobal);
  WriteSection(SecIdExport, secExport);
  WriteCodeSec(SecIdCode,   secCode);
  WriteSection(SecIdData,   secData);
end;
```

`BuildWriteIntHelper` must be called before `AssembleCodeSection` so that
`helperCode` is populated before it is copied into `secCode`.

---

## Step 15: ParseVarBlock (new procedure)

```pascal
procedure ParseVarBlock;
{** Parses a var block: VAR id {,id} : type ; ... until non-VAR token.
  Adds symbols to the symbol table with increasing curFrameSize offsets. }
var
  names:  array[0..63] of string[63];
  nnames: longint;
  typId:  longint;
  sym:    longint;
  i:      longint;
begin
  while tokKind = tkVar do begin
    NextToken;
    { parse one or more var declarations }
    while tokKind = tkIdent do begin
      nnames := 0;
      { collect identifier list }
      while true do begin
        if tokKind <> tkIdent then
          Error('expected variable name');
        names[nnames] := tokStr;
        nnames := nnames + 1;
        NextToken;
        if tokKind <> tkComma then break;
        NextToken;
      end;
      Expect(tkColon);
      { look up type name }
      if tokKind <> tkIdent then
        Error('expected type name');
      typId := LookupSym(tokStr);
      if (typId < 0) or (syms[typId].kind <> skType) then
        Error(concat('unknown type: ', tokStr));
      NextToken;
      Expect(tkSemicolon);
      { add each name as a variable }
      for i := 0 to nnames - 1 do begin
        sym := AddSym(names[i], skVar, syms[typId].typ);
        syms[sym].offset := curFrameSize;
        syms[sym].size   := syms[typId].size;
        curFrameSize     := curFrameSize + 4;  { 4-byte aligned slots }
      end;
    end;
  end;
end;
```

Variables are allocated in 4-byte slots regardless of type (alignment simplicity).
Only the low 1 byte is meaningful for `char` and `boolean`.

**Note on the `var` keyword:** `tkVar = 103` was already in the constant table from
Chapter 1. `ParseVarBlock` loops on `tkVar` to support multiple `var` sections, which
Turbo Pascal allows.

---

## Step 16: Update ParseExpression — add identifier loads

Add a new case in the prefix section (after `tkNot`):

```pascal
tkIdent: begin
  sym := LookupSym(tokStr);
  if sym < 0 then
    Error(concat('unknown identifier: ', tokStr));
  if syms[sym].kind <> skVar then
    Error(concat('not a variable: ', tokStr));
  NextToken;
  { load: $sp + offset }
  EmitGlobalGet(0);
  EmitI32Const(syms[sym].offset);
  EmitOp(OpI32Add);
  if (syms[sym].typ = tyChar) or (syms[sym].typ = tyBoolean) then
    EmitI32Load8u(0, 0)   { ;; i32.load8_u }
  else
    EmitI32Load(2, 0);    { ;; i32.load align=4 }
end;
```

---

## Step 17: Update ParseStatement — add assignment and write/writeln

Add new cases:

```pascal
tkIdent: begin
  sym := LookupSym(tokStr);
  if sym < 0 then
    Error(concat('unknown identifier: ', tokStr));
  NextToken;
  Expect(tkAssign);
  if syms[sym].kind <> skVar then
    Error('assignment target is not a variable');
  { address: $sp + offset }
  EmitGlobalGet(0);
  EmitI32Const(syms[sym].offset);
  EmitOp(OpI32Add);
  ParseExpression(PrecNone);
  if (syms[sym].typ = tyChar) or (syms[sym].typ = tyBoolean) then
    EmitI32Store8(0, 0)    { ;; i32.store8 }
  else
    EmitI32Store(2, 0);    { ;; i32.store align=4 }
end;
tkWrite: begin
  NextToken;
  ParseWriteArgs(false);
end;
tkWriteln: begin
  NextToken;
  ParseWriteArgs(true);
end;
```

---

## Step 18: ParseWriteArgs (new procedure)

```pascal
procedure ParseWriteArgs(withNewline: boolean);
{** Parses and emits write/writeln argument list.
  withNewline = true emits a trailing newline (writeln). }
var
  addr: longint;
  sym:  longint;
begin
  if tokKind = tkLParen then begin
    NextToken;
    while tokKind <> tkRParen do begin
      if tokKind = tkString then begin
        addr := EmitDataString(tokStr);
        EmitWriteString(addr, length(tokStr));
        NextToken;
      end else begin
        ParseExpression(PrecNone);
        EmitWriteInt;
      end;
      if tokKind = tkComma then
        NextToken;
    end;
    Expect(tkRParen);
  end;
  if withNewline then
    EmitWriteNewline;
end;
```

---

## Step 19: Update ParseProgram — var block, frame prologue/epilogue

Replace the body:

```pascal
procedure ParseProgram;
begin
  Expect(tkProgram);
  if tokKind <> tkIdent then
    Error('expected program name');
  NextToken;
  Expect(tkSemicolon);
  { optional var block }
  if tokKind = tkVar then
    ParseVarBlock;
  { frame prologue: $sp -= curFrameSize }
  if curFrameSize > 0 then begin
    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Sub);
    EmitGlobalSet(0);
  end;
  Expect(tkBegin);
  while tokKind <> tkEnd do begin
    ParseStatement;
    if tokKind = tkSemicolon then
      NextToken;
  end;
  Expect(tkEnd);
  { frame epilogue: $sp += curFrameSize }
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

## Step 20: Add InitBuiltins call to InitModule

After the existing body of `InitModule`, add:

```pascal
InitBuiltins;
```

---

## Step 21: Section Organization After Chapter 4

```
{ ---- Constants ---- }
{ ---- Types ---- }
{ ---- Global Variables ---- }
{ ---- Error Handling ---- }
{ ---- Buffer Procedures ---- }
{ ---- LEB128 Encoding ---- }
{ ---- Output Writing ---- }
{ ---- Section Assembly ---- }       (+ AssembleDataSection)
{ ---- Scanner ---- }
{ ---- Symbol Table ---- }           (new: EnterScope, LeaveScope, LookupSym, AddSym, InitBuiltins)
{ ---- Data Segment ---- }           (new: AllocData, EmitDataString, EnsureIOBuffers)
{ ---- Code Generation ---- }        (+ EmitGlobalGet/Set, EmitI32Load/Store variants,
                                         EnsureFdWrite, EnsureWriteInt,
                                         EmitWriteString, EmitWriteNewline, EmitWriteInt,
                                         BuildWriteIntHelper)
{ ---- Forward declarations ---- }
{ ---- Parser ---- }                 (+ ParseVarBlock, ParseWriteArgs; updated ParseExpression,
                                         ParseStatement, ParseProgram)
{ ---- Main ---- }
```

---

## Step 22: Test Cases

### tests/hello.pas (new)

```pascal
program hello;
begin
  writeln('Hello, world!')
end.
```

Expected output: `Hello, world!` (with newline).

### tests/vars.pas (new)

```pascal
program vars;
var x: integer;
begin
  x := 42;
  writeln(x)
end.
```

Expected output: `42` (with newline).

### tests/multivar.pas (new)

```pascal
program multivar;
var
  a, b: integer;
begin
  a := 10;
  b := 20;
  writeln(a + b)
end.
```

Expected output: `30` (with newline).

### tests/negwrite.pas (new)

```pascal
program negwrite;
begin
  writeln(-42)
end.
```

Expected output: `-42` (with newline). Verifies negative integer output.

### All Chapter 3 tests: must still pass

`empty`, `comments` (wasm-validate), `calc` (exit 42), `math` (exit 66),
`negation` (exit 43).

---

## Step 23: Expected Output Files

Create alongside the Pascal sources:

- `tests/hello.expected` — `Hello, world!\n`
- `tests/vars.expected` — `42\n`
- `tests/multivar.expected` — `30\n`
- `tests/negwrite.expected` — `-42\n`

---

## Step 24: Makefile Updates

```makefile
test-strap-hello: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/hello.wasm
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/hello.expected

test-strap-vars: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/vars.wasm
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/vars.expected

test-strap-multivar: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/multivar.wasm
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/multivar.expected

test-strap-negwrite: $(STRAP_OUTPUT_DIR)/$(TEST_DIR)/negwrite.wasm
	wasm-validate $<
	$(WASMRUN) $< | diff - $(TEST_DIR)/negwrite.expected

test: test-strap-empty test-strap-comments \
      test-strap-calc test-strap-math test-strap-negation \
      test-strap-hello test-strap-vars test-strap-multivar test-strap-negwrite
```

---

## Implementation Order

1. Add new constants (opcodes, type IDs, section ID, symbol kinds, limits)
2. Add `TSymEntry` type
3. Add new global variables (symbol table, frame, data segment, IO addresses, helper state)
4. Add `secData: TSmallBuf` to global variables
5. Update `InitModule` — register type 2, init new globals
6. Add symbol table procedures (`EnterScope`, `LeaveScope`, `LookupSym`, `AddSym`, `InitBuiltins`)
7. Add data segment procedures (`AllocData`, `EmitDataString`, `EnsureIOBuffers`)
8. Add new emit helpers (`EmitGlobalGet/Set`, `EmitI32Load/Store`, etc.)
9. Add `EnsureFdWrite` and `EnsureWriteInt`
10. Add `EmitWriteString`, `EmitWriteNewline`, `EmitWriteInt`
11. Add `BuildWriteIntHelper`
12. Add `AssembleDataSection`
13. Update `AssembleFunctionSection` — emit `__write_int` type if needed
14. Update `AssembleCodeSection` — emit `__write_int` body if needed
15. Update `WriteModule` — call `BuildWriteIntHelper` and `AssembleDataSection`
16. Update `ParseExpression` — add `tkIdent` load case
17. Add `ParseVarBlock`
18. Add `ParseWriteArgs`
19. Update `ParseStatement` — add assignment, `tkWrite`, `tkWriteln`
20. Update `ParseProgram` — parse var block, emit prologue/epilogue
21. Add test `.pas` files and `.expected` files
22. Update `Makefile` — add new test targets
23. `make test` — all nine tests should pass

---

## What Is NOT in Chapter 4

- `if`/`while`/`for`/`repeat` — Chapter 5
- `read`/`readln` — Chapter 5 (needs runtime support)
- Multiple `var` blocks (between `const`/`type`/`var`) — Chapter 6
- Procedures and functions — Chapter 6
- Nested scopes — Chapter 7
- String variables — Chapter 8
- Records and arrays — Chapter 9
- Type checking for assignment (incompatible types silently compile) — acceptable simplification
- `write` of `char` or `boolean` variables — only integer and string literal args in Chapter 4

---

## Risks and Notes

- **Import index stability.** `EnsureWriteInt` eagerly imports both `fd_write` and
  `proc_exit` to freeze `numImports` before computing `idxWriteInt`. Programs that use
  `writeln` will have a `proc_exit` import even if `halt` is never called. This is
  harmless — unused imports are valid WASM. Programs that use only `halt` are unchanged.

- **`__write_int` index.** After `EnsureWriteInt`, `idxWriteInt = numImports + 1`.
  `_start` is always `numImports + 0`. `BuildWriteIntHelper` uses `idxFdWrite` which is
  finalized at the same time. Cross-check: the function section emits two type entries
  and the code section emits two bodies, so `wasm-validate` will catch any mismatch.

- **Frame prologue with zero-size frame.** If the program has no `var` declarations,
  `curFrameSize = 0` and the prologue/epilogue `if` guards suppress emission. Programs
  from Chapters 1-3 continue to produce identical output.

- **Data section alignment.** `addrIovec` is the first allocation in the data segment
  (DataBase = 4), which is 4-byte aligned. Each subsequent allocation starts at
  `DataBase + dataLen`. `iovec` uses an aligned `i32.store` (align=2). The `int scratch`
  buffer uses unaligned `i32.store8` (align=0), which is always valid in WASM.

- **Negative zero.** The `__write_int` function negates negative values with
  `i32.sub` (0 - value). For `value = -2147483648` (MinInt), negation overflows back
  to `-2147483648`. The digit extraction loop will then produce incorrect output. This
  is an acceptable limitation for a teaching compiler; the fix (special-case MinInt)
  is left as an exercise.

- **`write` without args.** `write()` and `writeln()` with empty argument lists are
  handled: `ParseWriteArgs` sees `tkRParen` immediately and does nothing (or emits just
  the newline for `writeln`).
