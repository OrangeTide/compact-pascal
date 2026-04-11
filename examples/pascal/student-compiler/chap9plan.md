# Chapter 9 Implementation Plan: Structured Types

## Overview

Chapter 9 adds records and arrays — the first composite types. The two features share a
type descriptor table. Records come first (simpler codegen), then arrays (index arithmetic),
then multi-dimensional arrays (desugared to nested arrays), and finally structured
parameters (address passing + value-copy prologue).

---

## Step 0: Constants and Limits

Add to the `const` section:

```pascal
{ Type IDs -- Chapter 9 }
tyRecord  = 5;
tyArray   = 6;

{ Type descriptor and field table limits }
MaxTypeDescs = 128;
MaxFields    = 512;
```

WASM opcode for memory.copy is already present (`OpMiscPrefix = $FC`, `OpMemCopy = $0A`)
from Chapter 8.

---

## Step 1: New Record Types

### 1a. `TTypeDesc`

Add to the `type` section:

```pascal
TTypeDesc = record
  kind:        longint;  { tyRecord or tyArray }
  size:        longint;  { total byte size }
  { Record fields }
  fieldStart:  longint;  { index into fields[] }
  fieldCount:  longint;
  { Array }
  arrLo:       longint;
  arrHi:       longint;
  elemType:    longint;  { type tag of element (tyInteger, tyRecord, tyArray, ...) }
  elemTypeIdx: longint;  { index into types[] if elem is composite; -1 for scalars }
  elemSize:    longint;  { byte size of one element }
end;
```

### 1b. `TFieldEntry`

```pascal
TFieldEntry = record
  name:    string[63];
  typ:     longint;    { type tag }
  typeIdx: longint;    { types[] index if composite; -1 for scalars }
  offset:  longint;    { byte offset within record }
  size:    longint;    { byte size }
end;
```

### 1c. Global variables

```pascal
types:    array[0..MaxTypeDescs-1] of TTypeDesc;
numTypes: longint;
fields:   array[0..MaxFields-1] of TFieldEntry;
numFields: longint;
```

### 1d. `TSymEntry` extension

Add `typeIdx: longint` to `TSymEntry` — the index into `types[]` for composite-typed
variables. `-1` for scalar types. This is needed so the code generator can look up the
type descriptor when emitting selectors and memory.copy.

Similarly, add `typeIdx` to `TFuncEntry`'s param tracking arrays:

```pascal
paramTypeIdxs: array[0..MaxParams-1] of longint;
```

and in `TSymEntry`:

```pascal
typeIdx: longint;   { index into types[] for tyRecord/tyArray; -1 otherwise }
```

---

## Step 2: Helper Procedures

### 2a. `AddTypeDesc` — allocate a new type descriptor

```pascal
function AddTypeDesc: longint;
begin
  if numTypes >= MaxTypeDescs then
    Error('too many type descriptors');
  AddTypeDesc := numTypes;
  numTypes := numTypes + 1;
end;
```

### 2b. `AddField` — add a field entry to the fields table

```pascal
procedure AddField(const fname: string; ftyp, ftypeIdx, foffset, fsize: longint);
var fi: longint;
begin
  if numFields >= MaxFields then
    Error('too many record fields');
  fi := numFields;
  numFields := numFields + 1;
  fields[fi].name    := fname;
  fields[fi].typ     := ftyp;
  fields[fi].typeIdx := ftypeIdx;
  fields[fi].offset  := foffset;
  fields[fi].size    := fsize;
end;
```

### 2c. `EmitMemoryCopy`

```pascal
procedure EmitMemoryCopy;
begin
  CodeBufEmit(startCode, OpMiscPrefix);
  EmitULEB128(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);  { dst mem idx }
  CodeBufEmit(startCode, 0);  { src mem idx }
end;
```

(This may already exist from Chapter 8 string operations — verify and reuse if so.)

---

## Step 3: `ParseTypeSpec`

A new procedure `ParseTypeSpec` that parses a type expression (used in `type` blocks and
also in `var` blocks). It returns the type tag, type index (into `types[]`), and size:

```pascal
procedure ParseTypeSpec(var outTyp, outTypeIdx, outSize, outStrMax: longint);
```

**Record branch** (`tkRecord`):

1. Consume `tkRecord`.
2. Call `AddTypeDesc` → `tIdx`. Set `types[tIdx].kind := tyRecord`.
3. Set `types[tIdx].fieldStart := numFields`.
4. Parse field groups until `tkEnd`:
   - Collect names (comma-separated list).
   - Expect `tkColon`.
   - Recurse: `ParseTypeSpec(fieldTyp, fieldTypeIdx, fieldSize, fieldStrMax)`.
   - For each name: pad `fieldOfs` to 4-byte alignment, call `AddField`, advance `fieldOfs`.
5. `types[tIdx].fieldCount := numFields - types[tIdx].fieldStart`.
6. Pad `fieldOfs` to multiple of 4 (record total size alignment).
7. `types[tIdx].size := fieldOfs`.
8. Consume `tkEnd`.
9. Return `outTyp := tyRecord`, `outTypeIdx := tIdx`, `outSize := types[tIdx].size`.

**Array branch** (`tkArray`):

1. Consume `tkArray`, `tkLBracket`.
2. Collect dimensions: parse `lo..hi` pairs (comma-separated) into `dimLo[]`/`dimHi[]`.
   Up to `MaxDims = 8` dimensions.
3. Consume `tkRBracket`, `tkOf`.
4. `ParseTypeSpec` for the element type → `elemTyp, elemTypeIdx, elemSize, _`.
5. Build nested descriptors from innermost to outermost:
   ```
   for fi := nDims - 1 downto 0 do begin
     tIdx := AddTypeDesc;
     types[tIdx].kind := tyArray;
     types[tIdx].arrLo := dimLo[fi];
     types[tIdx].arrHi := dimHi[fi];
     types[tIdx].elemType := elemTyp;
     types[tIdx].elemTypeIdx := elemTypeIdx;
     types[tIdx].elemSize := elemSize;
     types[tIdx].size := (dimHi[fi] - dimLo[fi] + 1) * elemSize;
     elemTyp := tyArray;
     elemTypeIdx := tIdx;
     elemSize := types[tIdx].size;
   end;
   ```
6. Return outermost descriptor: `outTyp := tyArray`, `outTypeIdx := tIdx`, `outSize`.

**Scalar / named-type branch** (any other `tkIdent`):

- Look up in symbol table as `skType`.
- If the symbol's `typ` is `tyRecord` or `tyArray`, propagate its `typeIdx` from `syms[typSym].typeIdx`.
- Return the looked-up type's tag, typeIdx, size.

---

## Step 4: `ParseTypeBlock`

A new procedure to parse the `type` declaration section:

```pascal
procedure ParseTypeBlock;
var
  tname: string;
  tIdx, outTyp, outTypeIdx, outSize, outStrMax: longint;
  s: longint;
begin
  while tokKind = tkIdent do begin
    tname := tokStr;
    NextToken;
    Expect(tkEq);
    ParseTypeSpec(outTyp, outTypeIdx, outSize, outStrMax);
    Expect(tkSemicolon);
    s := AddSym(tname, skType, outTyp);
    syms[s].size    := outSize;
    syms[s].typeIdx := outTypeIdx;
    syms[s].strMaxLen := outStrMax;
  end;
end;
```

Add `tkType` handling to `ParseProgram` and `ParseProcDecl` (after the `var` block):

```pascal
if tokKind = tkType then begin
  NextToken;
  ParseTypeBlock;
end;
```

---

## Step 5: `ParseVarBlock` Updates

When the type after `:` is a structured type (resolved via `skType` symbol with
`typ = tyRecord` or `typ = tyArray`), the variable's `typeIdx` must be stored:

```pascal
syms[s].typeIdx := syms[typSym].typeIdx;
```

Also, structured variables need `curFrameSize` aligned to 4 bytes and advanced by the
full `outSize` (not just 4). The existing code already does this for strings; extend it:

```pascal
if (syms[typSym].typ = tyRecord) or (syms[typSym].typ = tyArray) then begin
  { 4-byte align frame offset }
  while (curFrameSize mod 4) <> 0 do
    curFrameSize := curFrameSize + 1;
  syms[s].offset := curFrameSize;
  curFrameSize := curFrameSize + sz;
end else ...
```

---

## Step 6: Dot Selector and Bracket Selector in ParseExpression

### Context: current expression state

When the parser sees a variable in `ParseExpression`, it emits the address of the
variable on the WASM stack (or its value for scalars). For composite types, we need to
track the current type through a selector chain.

Introduce two working variables in `ParseExpression`:

```pascal
curTyp:     longint;  { current type tag }
curTypeIdx: longint;  { current types[] index }
curSize:    longint;  { current element size }
isAddr:     boolean;  { true = address on stack, needs load at end }
```

After resolving a variable, set `curTyp`, `curTypeIdx` from the symbol, `isAddr := true`
for record/array vars.

### Dot selector loop

After emitting the variable's address, enter a selector loop:

```pascal
while (tokKind = tkDot) or (tokKind = tkLBracket) do begin
  if tokKind = tkDot then begin
    NextToken;
    { Look up field name in types[curTypeIdx] }
    if tokKind <> tkIdent then Error('expected field name');
    fldIdx := -1;
    for fi := types[curTypeIdx].fieldStart to
               types[curTypeIdx].fieldStart + types[curTypeIdx].fieldCount - 1 do begin
      if fields[fi].name = tokStr then begin
        fldIdx := fi;
        break;
      end;
    end;
    if fldIdx < 0 then Error(concat('unknown field: ', tokStr));
    NextToken;
    if fields[fldIdx].offset <> 0 then begin
      EmitI32Const(fields[fldIdx].offset);
      EmitOp(OpI32Add);
    end;
    curTyp     := fields[fldIdx].typ;
    curTypeIdx := fields[fldIdx].typeIdx;
    curSize    := fields[fldIdx].size;
  end else begin
    { tkLBracket: array subscript }
    NextToken;
    { types[curTypeIdx] must be an array }
    if curTyp <> tyArray then Error('not an array');
    ParseExpression(PrecNone);
    { subtract arrLo if non-zero }
    if types[curTypeIdx].arrLo <> 0 then begin
      EmitI32Const(types[curTypeIdx].arrLo);
      EmitOp(OpI32Sub);
    end;
    { multiply by elemSize if > 1 }
    if types[curTypeIdx].elemSize <> 1 then begin
      EmitI32Const(types[curTypeIdx].elemSize);
      EmitOp(OpI32Mul);
    end;
    EmitOp(OpI32Add);
    { Handle multi-dim comma trick }
    if tokKind = tkComma then
      tokKind := tkLBracket
    else
      Expect(tkRBracket);
    curTyp     := types[curTypeIdx].elemType;
    curTypeIdx := types[curTypeIdx].elemTypeIdx;
    curSize    := types[curTypeIdx].elemSize;  { if curTyp = tyArray }
  end;
end;
```

After the selector loop:
- If `curTyp` is scalar (integer/boolean/char), emit `i32.load` (or `i32.store` for assignment LHS).
- If `curTyp` is composite (record/array), the address is on the stack; leave it for memory.copy or further selectors.

### Integration with assignment

The LHS of an assignment is currently dispatched by `ParseStatement` when it sees
`tkIdent` followed by `tkAssign`. For structured types, the RHS is also an address.
The store path must be:

1. Emit LHS address (via selector chain if any).
2. Emit RHS address (ParseExpression for the composite value).
3. Emit `i32.const <size>`.
4. Emit `memory.copy`.

For scalar field selection followed by `:=`, do the normal `i32.store`.

---

## Step 7: Assignment Dispatch in ParseStatement

The variable assignment block needs a new branch for structured types:

```pascal
if (syms[s].typ = tyRecord) or (syms[s].typ = tyArray) then begin
  { Structured assignment: memory.copy }
  { Emit dst address (LHS) }
  EmitVarAddr(s);
  { Process any selectors on LHS; if selector chain ends at composite: address on stack }
  ParseSelectors(curTyp, curTypeIdx, curSize);
  if (curTyp = tyRecord) or (curTyp = tyArray) then begin
    Expect(tkAssign);
    { Emit src address (RHS) }
    ParseExpression(PrecNone);  { leaves address on stack for composite types }
    EmitI32Const(curSize);
    EmitMemoryCopy;
  end else begin
    { Ends at scalar field }
    Expect(tkAssign);
    ParseExpression(PrecNone);
    EmitOp(OpI32Store); EmitOp($02); EmitOp($00);  { align=4 }
  end;
end
```

Note: `ParseSelectors` would be the factored-out selector loop described in Step 6, or
the logic may remain inline in ParseStatement for the LHS.

---

## Step 8: Structured Parameters

### 8a. Param type tracking

`TFuncEntry` needs `paramTypeIdxs: array[0..MaxParams-1] of longint` and
`paramSizes: array[0..MaxParams-1] of longint`.

`ParseProcDecl` already stores `paramSizes`. Add `paramTypeIdxs` storage.

### 8b. Calling convention for structured params

At the WASM level, all parameters are `i32`. For structured types:

- **var/const params**: Caller pushes the address of the variable. Callee accesses
  fields through this pointer (WASM local holds address).
- **Value params**: Caller pushes address. Callee copies the data into its own stack
  frame in the prologue via `memory.copy`, then updates the WASM local to point to
  the frame copy.

### 8c. Prologue copy for value params

In `ParseBlock` (currently `ParseProcDecl` body compilation), after the frame prologue
but before `Expect(tkBegin)`:

```pascal
{ Copy structured value params into frame }
for ci := 0 to numStructCopies - 1 do begin
  { dst = display[curNestLevel] + frameOffset }
  EmitGlobalGet(curNestLevel);   { current $sp (after prologue) }
  EmitI32Const(structCopyFrameOff[ci]);
  EmitOp(OpI32Add);
  { src = WASM local (pointer to caller's data) }
  EmitLocalGet(structCopyLocal[ci]);
  EmitI32Const(structCopySize[ci]);
  EmitMemoryCopy;
  { Update WASM local to point to frame copy }
  EmitGlobalGet(curNestLevel);
  EmitI32Const(structCopyFrameOff[ci]);
  EmitOp(OpI32Add);
  EmitLocalSet(structCopyLocal[ci]);
end;
```

`numStructCopies`, `structCopyFrameOff[]`, `structCopyLocal[]`, `structCopySize[]` are
local arrays collected during param declaration.

### 8d. Caller side

When calling a procedure/function with a structured argument, `ParseCallArgs` must push
the address (not the value) of the actual parameter, even for value params. This is
consistent with passing a pointer; the callee is responsible for copying.

If the actual argument is a structured variable reference (selector chain ending at
composite type), the address is already on the WASM stack.

---

## Step 9: Tests

### t035_record_basic.pas

```pascal
program t035_record_basic;
type
  TPoint = record
    x: integer;
    y: integer;
  end;
var
  p: TPoint;
begin
  p.x := 3;
  p.y := 4;
  writeln(p.x, ' ', p.y);
end.
```

Expected: `3 4`

### t036_record_copy.pas

```pascal
program t036_record_copy;
type
  TPoint = record x: integer; y: integer; end;
var a, b: TPoint;
begin
  a.x := 10; a.y := 20;
  b := a;
  b.x := 99;
  writeln(a.x, ' ', a.y);  { 10 20 -- unchanged }
  writeln(b.x, ' ', b.y);  { 99 20 }
end.
```

Expected:
```
10 20
99 20
```

### t037_array_basic.pas

```pascal
program t037_array_basic;
var
  a: array[1..5] of integer;
  i: integer;
begin
  for i := 1 to 5 do
    a[i] := i * i;
  for i := 1 to 5 do
    writeln(a[i]);
end.
```

Expected:
```
1
4
9
16
25
```

### t038_array_copy.pas

```pascal
program t038_array_copy;
var
  a, b: array[1..3] of integer;
  i: integer;
begin
  for i := 1 to 3 do a[i] := i;
  b := a;
  b[2] := 99;
  for i := 1 to 3 do writeln(a[i]);  { 1 2 3 }
  for i := 1 to 3 do writeln(b[i]);  { 1 99 3 }
end.
```

Expected:
```
1
2
3
1
99
3
```

### t039_array_record.pas (from tutorial)

Array of records. Expected output: `10 11 / 20 21 / 30 31`.

### t040_array_2d.pas (from tutorial)

2D array using `array[1..3, 1..3]`. Expected: 3x3 matrix.

### t043_record_param.pas (from tutorial)

Record parameters: `const`, `var`, and value. Last line `13 24` confirms value param
copy semantics.

---

## Step 10: `ParseProgram` and `ParseProcDecl` Integration

Add `type` block parsing before the `var` block (Pascal allows `type` before `var` in
the declaration section):

```pascal
{ type block }
if tokKind = tkType then begin
  NextToken;
  ParseTypeBlock;
end;
{ var block }
if tokKind = tkVar then begin
  NextToken;
  ParseVarBlock;
end;
```

Both `ParseProgram` and `ParseProcDecl` need this pattern.

---

## Implementation Order

1. Constants (`tyRecord`, `tyArray`, limits).
2. `TTypeDesc`, `TFieldEntry` types; global vars; init in `InitModule`.
3. `TSymEntry` + `TFuncEntry` `typeIdx` field.
4. `EmitMemoryCopy` (verify or add).
5. `ParseTypeSpec` + `ParseTypeBlock`.
6. `ParseVarBlock` updates (structured type support + `typeIdx`).
7. Selector loop in `ParseExpression` (dot + bracket, read path).
8. Assignment dispatch in `ParseStatement` (write path + memory.copy).
9. Structured parameter support in `ParseProcDecl` and `ParseCallArgs`.
10. Tests + Makefile targets.

---

## Risks and Notes

- **`typeIdx` in `TSymEntry`**: all existing scalar variable creation sites must set
  `syms[s].typeIdx := -1` to avoid garbage. Initialize in `AddSym` if possible.

- **Selector chain in both read and write contexts**: the selector loop must work in
  two contexts — reading (push value or address) and writing (emit store or memory.copy
  after emitting dest address first). These are currently both inside `ParseExpression`
  (read) and `ParseStatement` (write). The cleanest solution is to factor out a
  `ParseSelectorChain` procedure that can emit address computation for both.

- **`memory.copy` bulk memory**: the WASM runtime must support the bulk memory proposal
  (`--wasm-features=bulk-memory` for wasmtime if not enabled by default). Verify
  wasmtime version supports it without flags. (It should: bulk memory is in WASM 1.0.)

- **Pascal declaration order**: `type` sections can precede `var` sections in standard
  Pascal. Types defined in the `type` section are registered as `skType` symbols, so
  `var` blocks can refer to them by name.

- **Nested types**: `record` fields can themselves be `record` or `array`. The recursive
  `ParseTypeSpec` handles this naturally.

- **Frame alignment**: structured variables occupy `size` bytes. The frame must remain
  4-byte aligned. Add padding before each structured variable if needed.

- **String fields in records**: Not planned for Chapter 9. Records with string fields
  would require special handling (strings have length-byte headers). Defer to a later
  chapter or treat as unsupported.
