{$MODE TP}
program pascom;

{ ---- Constants ---- }

const
  SmallBufMax = 4095;    { 4 KB }
  CodeBufMax  = 131071;  { 128 KB }

  { WASM value types }
  WasmI32 = $7F;

  { WASM section IDs }
  SecIdType   = 1;
  SecIdImport = 2;
  SecIdFunc   = 3;
  SecIdMemory = 5;
  SecIdGlobal = 6;
  SecIdExport = 7;
  SecIdCode   = 10;

  { WASM opcodes }
  OpEnd      = $0B;
  OpCall     = $10;
  OpDrop     = $1A;
  OpI32Const = $41;
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
  OpI32Shl   = $74;
  OpI32ShrS  = $75;
  OpI32ShrU  = $76;
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
  TypeI32Void  = 1;  { (i32) -> () used for proc_exit and __write_int }
  TypeFdWrite  = 2;  { (i32,i32,i32,i32) -> i32  used for fd_write }

  { WASM section IDs — Chapter 4 }
  SecIdData = 11;

  { WASM opcodes — Chapter 4 }
  OpLocalGet  = $20;
  OpLocalSet  = $21;
  OpGlobalGet = $23;
  OpGlobalSet = $24;
  OpI32Load   = $28;
  OpI32Load8u = $2D;
  OpI32Store  = $36;
  OpI32Store8 = $3A;
  OpBlock     = $02;
  OpLoop      = $03;
  OpIf        = $04;
  OpElse      = $05;
  OpBr        = $0C;
  OpBrIf      = $0D;
  OpReturn    = $0F;
  WasmVoid    = $40;  { block type: void }

  { Symbol kinds }
  skVar  = 1;
  skType = 2;
  skProc = 3;
  skFunc  = 4;
  skConst = 5;  { Chapter 10: compile-time constant }

  { Type IDs }
  tyInteger = 1;
  tyBoolean = 2;
  tyChar    = 3;

  { Symbol table and scope limits }
  MaxSyms      = 1024;
  MaxScopDepth = 32;

  { Data segment base address (0..3 is nil guard) }
  DataBase = 4;

  { Token kinds }
  tkEOF       = 0;
  tkIdent     = 1;
  tkInteger   = 2;
  tkString    = 3;
  tkPlus      = 10;
  tkMinus     = 11;
  tkStar      = 12;
  tkSlash     = 13;
  tkLParen    = 14;
  tkRParen    = 15;
  tkSemicolon = 16;
  tkColon     = 17;
  tkAssign    = 18;
  tkDot       = 19;
  tkDotDot    = 20;
  tkComma     = 21;
  tkLBracket  = 22;
  tkRBracket  = 23;
  tkEq        = 24;
  tkNe        = 25;
  tkLt        = 26;
  tkLe        = 27;
  tkGt        = 28;
  tkGe        = 29;
  tkCaret     = 30;
  { keywords }
  tkProgram   = 100;
  tkBegin     = 101;
  tkEnd       = 102;
  tkVar       = 103;
  tkConst     = 104;
  tkType      = 105;
  tkProcedure = 106;
  tkFunction  = 107;
  tkIf        = 108;
  tkThen      = 109;
  tkElse      = 110;
  tkWhile     = 111;
  tkDo        = 112;
  tkFor       = 113;
  tkTo        = 114;
  tkDownto    = 115;
  tkRepeat    = 116;
  tkUntil     = 117;
  tkAnd       = 118;
  tkOr        = 119;
  tkNot       = 120;
  tkDiv       = 121;
  tkMod       = 122;
  tkOf        = 123;
  tkArray     = 124;
  tkRecord    = 125;
  tkCase      = 126;
  tkWith      = 127;
  tkGoto      = 128;
  tkLabel     = 129;
  tkForward   = 130;
  tkNil       = 131;
  tkIn        = 132;
  tkFile      = 133;
  tkSet       = 134;
  tkAndThen   = 135;
  tkOrElse    = 136;
  tkShr       = 137;
  tkShl       = 138;
  { built-in identifiers treated as keywords }
  tkHalt      = 200;
  tkWrite     = 201;
  tkWriteln   = 202;
  tkRead      = 203;
  tkReadln    = 204;
  tkTrue      = 205;
  tkFalse     = 206;
  tkBreak     = 207;
  tkContinue  = 208;

  { WASM type table limit }
  MaxWasmTypes  = 64;
  MaxWasmParams = 8;

  { Function table limits }
  MaxFuncs  = 256;
  MaxParams = 16;

  { built-in identifier tokens }
  tkExit = 209;

  { Type IDs -- Chapter 8 }
  tyString = 4;

  { Type IDs -- Chapter 9 }
  tyRecord  = 5;
  tyArray   = 6;
  tyEnum    = 7;  { Chapter 10: enumerated type }

  { Type descriptor and field table limits -- Chapter 9 }
  MaxTypeDescs = 128;
  MaxFields    = 512;
  MaxDims      = 8;

  { WASM opcodes -- Chapter 8 }
  OpMiscPrefix = $FC;
  OpMemCopy    = $0A;
  OpLocalTee   = $22;
  OpSelect     = $1B;
  OpI32LtU     = $49;
  OpI32GtU     = $4B;

  { WASM type indices -- Chapter 8 }
  TypeII_I  = 3;
  TypeII_V  = 4;
  TypeIII_V = 5;
  TypeIII_I = 6;

  { String helper slot indices relative to numImports }
  SlotStrAssign = 2;
  SlotWriteStr  = 3;
  SlotStrComp   = 4;
  SlotReadStr   = 5;
  SlotStrAppend     = 6;
  SlotStrCopy       = 7;
  SlotStrPos        = 8;
  SlotStrDel        = 9;
  SlotStrIns        = 10;
  SlotStrAppendChar = 11;

  { Built-in identifier tokens -- Chapter 8 }
  tkLength     = 210;
  tkCopy       = 211;
  tkPos        = 212;
  tkDelete     = 213;
  tkInsert     = 214;
  tkConcat     = 215;
  tkStringType = 216;

{ ---- Types ---- }

type
  TSmallBuf = record
    data: array[0..SmallBufMax] of byte;
    len:  longint;
  end;

  TCodeBuf = record
    data: array[0..CodeBufMax] of byte;
    len:  longint;
  end;

  TWasmType = record
    nparams:  longint;
    params:   array[0..MaxWasmParams-1] of byte;
    nresults: longint;
    results:  array[0..MaxWasmParams-1] of byte;
  end;

  { Chapter 9: type descriptor and field table }
  TTypeDesc = record
    kind:        longint;   { tyRecord or tyArray }
    size:        longint;   { total byte size }
    fieldStart:  longint;   { index into fields[] (records) }
    fieldCount:  longint;
    arrLo:       longint;   { low bound (arrays) }
    arrHi:       longint;   { high bound }
    elemType:    longint;   { element type tag }
    elemTypeIdx: longint;   { types[] index for composite elements; -1 for scalars }
    elemSize:    longint;   { byte size of one element }
  end;

  TFieldEntry = record
    name:    string[63];
    typ:     longint;    { type tag }
    typeIdx: longint;    { types[] index if composite; -1 for scalars }
    offset:  longint;    { byte offset within record }
    size:    longint;    { byte size }
  end;

  TSymEntry = record
    name:        string[63];
    kind:        longint;    { skVar, skType, skProc, skFunc }
    typ:         longint;    { tyInteger, tyBoolean, tyChar, tyRecord, tyArray, ... }
    typeIdx:     longint;    { types[] index for tyRecord/tyArray; -1 otherwise }
    level:       longint;
    offset:      longint;    { var: frame offset (>=0) or -(localIdx+1) for params;
                               proc/func: WASM function index }
    size:        longint;    { var: byte size; proc/func: funcs[] index }
    isVarParam:  boolean;    { WASM local holds address, not value }
    isConstParam: boolean;   { assignment to this param is forbidden }
    strMaxLen:   longint;    { for tyString: max length (1..255) }
  end;

  TFuncEntry = record
    nparams:      longint;
    retType:      longint;   { 0=procedure, else tyInteger/tyBoolean/tyChar }
    wasmFuncIdx:  longint;   { absolute WASM function index }
    wasmTypeIdx:  longint;   { index into wasmTypes[] }
    bodyStart:    longint;   { byte offset in funcBodies (instructions only) }
    bodyLen:      longint;   { instruction byte count }
    isForward:    boolean;   { forward decl: body not yet compiled }
    needsCaseTemp: boolean;  { Chapter 10: body contains a case statement }
    varParams:    array[0..MaxParams-1] of boolean;
    constParams:  array[0..MaxParams-1] of boolean;
    paramSizes:   array[0..MaxParams-1] of longint;
    paramTypeIdxs: array[0..MaxParams-1] of longint;
  end;

{ ---- Global Variables ---- }

var
  { Section buffers (globals to avoid TP stack overflow) }
  secType:   TSmallBuf;
  secImport: TSmallBuf;
  secFunc:   TSmallBuf;
  secMemory: TSmallBuf;
  secGlobal: TSmallBuf;
  secExport: TSmallBuf;
  secCode:   TCodeBuf;
  secData:   TSmallBuf;
  startCode: TCodeBuf;
  outBuf:    TCodeBuf;  { final output accumulator }

  { WASM type table }
  wasmTypes:       array[0..MaxWasmTypes-1] of TWasmType;
  numWasmTypes:    longint;
  numImports:      longint;
  numDefinedFuncs: longint;

  { Scanner state }
  ch:          char;
  srcLine:     longint;
  srcCol:      longint;
  atEof:       boolean;
  pushbackCh:  char;
  hasPushback: boolean;
  tokKind:     longint;
  tokInt:      longint;
  tokStr:      string;
  pendingTok:  boolean;
  pendingKind: longint;
  pendingStr:  string;

  { Import state }
  idxProcExit: longint;   { function index of proc_exit; -1 until imported }
  importsBuf:  TSmallBuf; { raw import entry bytes, without count prefix }

  { Symbol table }
  syms:       array[0..MaxSyms-1] of TSymEntry;
  numSyms:    longint;
  scopeBase:  array[0..MaxScopDepth-1] of longint;
  scopeDepth: longint;

  { Frame allocation (current block's variable size) }
  curFrameSize: longint;

  { Data segment }
  dataBuf:  TSmallBuf;  { segment content, starts at address DataBase }
  dataLen:  longint;    { bytes emitted so far }

  { I/O scratch addresses in data segment; -1 until allocated }
  addrIovec:    longint;
  addrNwritten: longint;
  addrNewline:  longint;
  addrIntBuf:   longint;  { 20-byte scratch for integer-to-decimal }

  { Chapter 4 import index }
  idxFdWrite: longint;

  { Helper function state }
  idxWriteInt:  longint;
  needWriteInt: boolean;
  helperCode:   TCodeBuf;

  { Chapter 10: case statement temp local }
  curNeedsCaseTemp:   boolean;  { true when current function uses case }
  curCaseTempIdx:     longint;  { WASM local index of case selector temp }
  startNeedsCaseTemp: boolean;  { case temp needed in _start }

  { Control flow label depths; -1 means not inside a loop }
  breakDepth:    longint;
  continueDepth: longint;

  { exit-block depth: -1 = not in a procedure/function (exit is invalid);
    0 = at function body block; +N per enclosing control structure }
  exitDepth: longint;

  { Index into funcs[] of the function currently being compiled (-1 if none).
    Used to detect return-value assignment: funcname := expr inside func body. }
  currentFuncSlot: longint;

  { Nesting level currently being compiled: 0 = main program body,
    1 = top-level procedure body, 2 = nested inside that, etc.
    Used to select the correct display global for EmitFramePtr. }
  curNestLevel: longint;

  { User-defined function table }
  funcs:    array[0..MaxFuncs-1] of TFuncEntry;
  numFuncs: longint;

  { Accumulated function body instruction bytes (no local header, no end byte) }
  funcBodies: TCodeBuf;

  { Pending IMPORT directive }
  hasPendingImport: boolean;
  pendingImportMod: string;
  pendingImportFld: string;

  { Pending EXPORT directive }
  hasPendingExport:  boolean;
  pendingExportName: string;

  { User export entries accumulated for the export section }
  userExportsBuf: TSmallBuf;
  numUserExports: longint;

  { Chapter 9: type descriptor and field tables }
  types:           array[0..MaxTypeDescs-1] of TTypeDesc;
  numTypes:        longint;
  fields:          array[0..MaxFields-1] of TFieldEntry;
  numFields:       longint;
  lastExprTypeIdx: longint;  { types[] index of last expression; -1 for non-composite }

  { String helper state -- Chapter 8 }
  strHelpersReserved: boolean;
  idxFdRead:      longint;
  addrStrScratch:  longint;
  addrReadBuf:    longint;
  needStrAssign:  boolean;  idxStrAssign:  longint;
  needWriteStr:   boolean;  idxWriteStr:   longint;
  needStrCompare: boolean;  idxStrCompare: longint;
  needReadStr:    boolean;  idxReadStr:    longint;
  needStrAppend:  boolean;  idxStrAppend:  longint;
  needStrCopy:    boolean;  idxStrCopy:    longint;
  needStrPos:     boolean;  idxStrPos:     longint;
  needStrDelete:  boolean;  idxStrDelete:  longint;
  needStrInsert:     boolean;  idxStrInsert:     longint;
  needStrAppendChar: boolean;  idxStrAppendChar: longint;
  strHelperCode:  TCodeBuf;
  strHlpStart: array[0..9] of longint;
  strHlpLen:   array[0..9] of longint;
  lastExprType:   longint;
  lastExprStrMax: longint;

  { Output file }
  outFile: file;

{ ---- Error Handling ---- }

procedure Error(msg: string);
begin
  writeln(StdErr, 'Error: [', srcLine, ':', srcCol, '] ', msg);
  halt(1);
end;

{ ---- Buffer Procedures ---- }

procedure SmallBufInit(var b: TSmallBuf);
begin
  b.len := 0;
end;

procedure SmallBufEmit(var b: TSmallBuf; v: byte);
begin
  if b.len > SmallBufMax then
    Error('small buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;

procedure CodeBufInit(var b: TCodeBuf);
begin
  b.len := 0;
end;

procedure CodeBufEmit(var b: TCodeBuf; v: byte);
begin
  if b.len > CodeBufMax then
    Error('code buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;

{ ---- LEB128 Encoding ---- }

procedure EmitULEB128(var b: TCodeBuf; value: longint);
var
  v:   longint;
  byt: byte;
begin
  v := value;
  repeat
    byt := v and $7F;      { extract low 7 bits }
    v := v shr 7;          { logical right shift }
    if v <> 0 then
      byt := byt or $80;   { set continuation bit }
    CodeBufEmit(b, byt);
  until v = 0;
end;

procedure EmitSLEB128(var b: TCodeBuf; value: longint);
var
  byt:  byte;
  more: boolean;
begin
  more := true;
  while more do begin
    byt := value and $7F;
    if value >= 0 then
      value := value shr 7
    else begin
      value := value shr 7;
      value := value or longint($FE000000);  { sign-extend top 7 bits }
    end;
    if (value = 0) and ((byt and $40) = 0) then
      more := false
    else if (value = -1) and ((byt and $40) <> 0) then
      more := false;
    if more then
      byt := byt or $80;
    CodeBufEmit(b, byt);
  end;
end;

procedure SmallEmitULEB128(var b: TSmallBuf; value: longint);
var
  v:   longint;
  byt: byte;
begin
  v := value;
  repeat
    byt := v and $7F;
    v := v shr 7;
    if v <> 0 then
      byt := byt or $80;
    SmallBufEmit(b, byt);
  until v = 0;
end;

{ ---- Output Writing ---- }

{ Write a SmallBuf section: id byte, ULEB128 length, body bytes }
procedure WriteSection(id: byte; var buf: TSmallBuf);
var i: longint;
begin
  if buf.len = 0 then exit;  { skip empty sections }
  CodeBufEmit(outBuf, id);
  EmitULEB128(outBuf, buf.len);
  for i := 0 to buf.len - 1 do
    CodeBufEmit(outBuf, buf.data[i]);
end;

{ Write a CodeBuf section (for the code section which is large) }
procedure WriteCodeSec(id: byte; var buf: TCodeBuf);
var i: longint;
begin
  if buf.len = 0 then exit;
  CodeBufEmit(outBuf, id);
  EmitULEB128(outBuf, buf.len);
  for i := 0 to buf.len - 1 do
    CodeBufEmit(outBuf, buf.data[i]);
end;

{ ---- Forward declarations (assembly) ---- }

procedure BuildWriteIntHelper; forward;
procedure BuildStringHelpers; forward;

{ ---- Section Assembly ---- }

procedure AssembleTypeSection;
var i, j: longint;
begin
  SmallBufInit(secType);
  SmallBufEmit(secType, numWasmTypes);
  for i := 0 to numWasmTypes - 1 do begin
    SmallBufEmit(secType, $60);  { func marker }
    SmallBufEmit(secType, wasmTypes[i].nparams);
    for j := 0 to wasmTypes[i].nparams - 1 do
      SmallBufEmit(secType, wasmTypes[i].params[j]);
    SmallBufEmit(secType, wasmTypes[i].nresults);
    for j := 0 to wasmTypes[i].nresults - 1 do
      SmallBufEmit(secType, wasmTypes[i].results[j]);
  end;
end;

procedure AssembleImportSection;
var i: longint;
begin
  SmallBufInit(secImport);
  if numImports = 0 then exit;
  SmallEmitULEB128(secImport, numImports);
  for i := 0 to importsBuf.len - 1 do
    SmallBufEmit(secImport, importsBuf.data[i]);
end;

procedure AssembleFunctionSection;
var i: longint;
begin
  SmallBufInit(secFunc);
  SmallBufEmit(secFunc, numDefinedFuncs);
  SmallBufEmit(secFunc, TypeVoidVoid);            { _start: () -> () }
  if needWriteInt then
    SmallBufEmit(secFunc, TypeI32Void);           { __write_int: (i32) -> () }
  if strHelpersReserved then begin
    SmallBufEmit(secFunc, TypeIII_V);  { __str_assign (dst, max_len, src) -> void }
    SmallBufEmit(secFunc, TypeI32Void); { __write_str (addr) -> void }
    SmallBufEmit(secFunc, TypeII_I);   { __str_compare (a, b) -> i32 }
    SmallBufEmit(secFunc, TypeII_V);   { __read_str (addr, max_len) -> void }
    SmallBufEmit(secFunc, TypeIII_V);  { __str_append (dst, max_len, src) -> void }
    SmallBufEmit(secFunc, TypeIII_I);  { __str_copy (src, idx, count) -> i32 }
    SmallBufEmit(secFunc, TypeII_I);   { __str_pos (sub, s) -> i32 }
    SmallBufEmit(secFunc, TypeIII_V);  { __str_delete (s, idx, count) -> void }
    SmallBufEmit(secFunc, TypeIII_V);  { __str_insert (src, dst, idx) -> void }
    SmallBufEmit(secFunc, TypeIII_V);  { __str_append_char (dst, max_len, char_byte) -> void }
  end;
  for i := 0 to numFuncs - 1 do
    SmallEmitULEB128(secFunc, funcs[i].wasmTypeIdx);  { user functions }
end;

procedure AssembleMemorySection;
begin
  SmallBufInit(secMemory);
  SmallBufEmit(secMemory, 1);    { 1 memory }
  SmallBufEmit(secMemory, 1);    { limits: has maximum }
  SmallBufEmit(secMemory, $14);  { min: 20 pages (1.25 MB) }
  SmallBufEmit(secMemory, $80);  { max: 256 pages }
  SmallBufEmit(secMemory, $02);  { 256 in ULEB128 = 80 02 }
end;

procedure AssembleGlobalSection;
var i: longint;
begin
  SmallBufInit(secGlobal);
  SmallBufEmit(secGlobal, 9);    { 9 globals: $sp + display[0..7] }
  { Global 0: $sp (stack pointer), mutable i32, init 1310720 = 20 pages }
  SmallBufEmit(secGlobal, $7F);  { type: i32 }
  SmallBufEmit(secGlobal, 1);    { mutable }
  SmallBufEmit(secGlobal, $41);  { i32.const opcode }
  SmallBufEmit(secGlobal, $80);
  SmallBufEmit(secGlobal, $80);
  SmallBufEmit(secGlobal, $D0);
  SmallBufEmit(secGlobal, $00);  { 1310720 in SLEB128 = 80 80 D0 00 }
  SmallBufEmit(secGlobal, $0B);  { end }
  { Globals 1-8: display[0..7], mutable i32, init 0 }
  for i := 1 to 8 do begin
    SmallBufEmit(secGlobal, $7F);  { type: i32 }
    SmallBufEmit(secGlobal, 1);    { mutable }
    SmallBufEmit(secGlobal, $41);  { i32.const }
    SmallBufEmit(secGlobal, 0);    { 0 in SLEB128 }
    SmallBufEmit(secGlobal, $0B);  { end }
  end;
end;

procedure AssembleExportSection;
var i: longint;
begin
  SmallBufInit(secExport);
  SmallEmitULEB128(secExport, 2 + numUserExports);
  { "_start" as function }
  SmallBufEmit(secExport, 6);  { name length }
  SmallBufEmit(secExport, ord('_'));
  SmallBufEmit(secExport, ord('s'));
  SmallBufEmit(secExport, ord('t'));
  SmallBufEmit(secExport, ord('a'));
  SmallBufEmit(secExport, ord('r'));
  SmallBufEmit(secExport, ord('t'));
  SmallBufEmit(secExport, $00);  { export kind: function }
  SmallEmitULEB128(secExport, numImports);  { function index = numImports }
  { "memory" as memory 0 }
  SmallBufEmit(secExport, 6);
  SmallBufEmit(secExport, ord('m'));
  SmallBufEmit(secExport, ord('e'));
  SmallBufEmit(secExport, ord('m'));
  SmallBufEmit(secExport, ord('o'));
  SmallBufEmit(secExport, ord('r'));
  SmallBufEmit(secExport, ord('y'));
  SmallBufEmit(secExport, $02);  { export kind: memory }
  SmallBufEmit(secExport, 0);    { memory index 0 }
  { User exports from EXPORT directives }
  for i := 0 to userExportsBuf.len - 1 do
    SmallBufEmit(secExport, userExportsBuf.data[i]);
end;

procedure AssembleCodeSection;
var bodyLen, localBytes, i, j: longint;
begin
  CodeBufInit(secCode);
  EmitULEB128(secCode, numDefinedFuncs);  { function count }
  { _start body: [00] or [01 01 7F] + instructions + [0B] }
  if startNeedsCaseTemp then
    bodyLen := 3 + startCode.len + 1
  else
    bodyLen := 1 + startCode.len + 1;
  EmitULEB128(secCode, bodyLen);
  if startNeedsCaseTemp then begin
    CodeBufEmit(secCode, 1);    { 1 local group }
    CodeBufEmit(secCode, 1);    { 1 local: case temp }
    CodeBufEmit(secCode, $7F);  { i32 }
  end else
    CodeBufEmit(secCode, 0);  { 0 local declarations }
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(secCode, startCode.data[i]);
  CodeBufEmit(secCode, $0B);  { end }
  { __write_int body: [01 02 7F] + helperCode + [0B] }
  if needWriteInt then begin
    bodyLen := 3 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);    { 1 local declaration group }
    CodeBufEmit(secCode, 2);    { 2 locals }
    CodeBufEmit(secCode, $7F);  { type: i32 }
    for i := 0 to helperCode.len - 1 do
      CodeBufEmit(secCode, helperCode.data[i]);
    CodeBufEmit(secCode, $0B);  { end }
  end;
  { String helper bodies }
  if strHelpersReserved then begin
    for j := 0 to 9 do begin
      { Determine extra local count for this helper }
      case j of
        0: localBytes := 1;  { strAssign }
        1: localBytes := 1;  { writeStr }
        2: localBytes := 5;  { strCompare }
        3: localBytes := 2;  { readStr }
        4: localBytes := 4;  { strAppend }
        5: localBytes := 4;  { strCopy }
        6: localBytes := 5;  { strPos }
        7: localBytes := 5;  { strDelete }
        8: localBytes := 6;  { strInsert }
        9: localBytes := 1;  { strAppendChar }
      else localBytes := 0
      end;
      if strHlpLen[j] > 0 then begin
        { Full body: 1 group header (3 bytes) + instructions + end }
        bodyLen := 3 + strHlpLen[j] + 1;
        EmitULEB128(secCode, bodyLen);
        CodeBufEmit(secCode, 1);            { 1 local group }
        CodeBufEmit(secCode, localBytes);   { N extra locals }
        CodeBufEmit(secCode, $7F);          { type i32 }
        for i := strHlpStart[j] to strHlpStart[j] + strHlpLen[j] - 1 do
          CodeBufEmit(secCode, strHelperCode.data[i]);
        CodeBufEmit(secCode, $0B);          { end }
      end else begin
        { Stub body: 0 locals; for i32-returning helpers, return 0 }
        { j=2: __str_compare returns i32; j=5: __str_copy returns i32; j=6: __str_pos returns i32 }
        if (j = 2) or (j = 5) or (j = 6) then begin
          { Return i32: i32.const 0; end = 4 bytes }
          EmitULEB128(secCode, 4);
          CodeBufEmit(secCode, 0);    { 0 local groups }
          CodeBufEmit(secCode, $41);  { i32.const opcode }
          CodeBufEmit(secCode, 0);    { 0 in SLEB128 }
          CodeBufEmit(secCode, $0B);  { end }
        end else begin
          { Return void: 0 locals + end = 2 bytes }
          EmitULEB128(secCode, 2);
          CodeBufEmit(secCode, 0);    { 0 local groups }
          CodeBufEmit(secCode, $0B);  { end }
        end;
      end;
    end;
  end;
  { User function bodies }
  for j := 0 to numFuncs - 1 do begin
    { Header [01 count 7F] is always 3 bytes regardless of local count }
    localBytes := 3;
    bodyLen := localBytes + funcs[j].bodyLen + 1;  { +1 for end byte }
    EmitULEB128(secCode, bodyLen);
    if funcs[j].retType <> 0 then begin
      CodeBufEmit(secCode, 1);    { 1 local group }
      if funcs[j].needsCaseTemp then
        CodeBufEmit(secCode, 3)   { 3 locals: retval + display save + case temp }
      else
        CodeBufEmit(secCode, 2);  { 2 locals: retval + display save }
      CodeBufEmit(secCode, $7F);  { i32 }
    end else begin
      CodeBufEmit(secCode, 1);    { 1 local group }
      if funcs[j].needsCaseTemp then
        CodeBufEmit(secCode, 2)   { 2 locals: display save + case temp }
      else
        CodeBufEmit(secCode, 1);  { 1 local: display save }
      CodeBufEmit(secCode, $7F);  { i32 }
    end;
    for i := funcs[j].bodyStart to funcs[j].bodyStart + funcs[j].bodyLen - 1 do
      CodeBufEmit(secCode, funcBodies.data[i]);
    CodeBufEmit(secCode, $0B);  { end }
  end;
end;

procedure AssembleDataSection;
var i: longint;
begin
  SmallBufInit(secData);
  if dataLen = 0 then exit;
  SmallEmitULEB128(secData, 1);         { 1 segment }
  SmallEmitULEB128(secData, 0);         { memory index 0 }
  SmallBufEmit(secData, $41);           { i32.const }
  SmallEmitULEB128(secData, DataBase);  { offset = 4 }
  SmallBufEmit(secData, $0B);           { end }
  SmallEmitULEB128(secData, dataLen);   { byte count }
  for i := 0 to dataLen - 1 do
    SmallBufEmit(secData, dataBuf.data[i]);
end;

procedure WriteModule;
begin
  if strHelpersReserved then
    BuildStringHelpers;
  if needWriteInt then
    BuildWriteIntHelper;
  CodeBufInit(outBuf);
  AssembleTypeSection;
  AssembleImportSection;
  AssembleFunctionSection;
  AssembleMemorySection;
  AssembleGlobalSection;
  AssembleExportSection;
  AssembleCodeSection;
  AssembleDataSection;

  { WASM header: magic \0asm + version 1 }
  CodeBufEmit(outBuf, $00); CodeBufEmit(outBuf, $61);
  CodeBufEmit(outBuf, $73); CodeBufEmit(outBuf, $6D);
  CodeBufEmit(outBuf, $01); CodeBufEmit(outBuf, $00);
  CodeBufEmit(outBuf, $00); CodeBufEmit(outBuf, $00);

  { Sections in numerical ID order }
  WriteSection(SecIdType,   secType);
  WriteSection(SecIdImport, secImport);
  WriteSection(SecIdFunc,   secFunc);
  WriteSection(SecIdMemory, secMemory);
  WriteSection(SecIdGlobal, secGlobal);
  WriteSection(SecIdExport, secExport);
  WriteCodeSec(SecIdCode,   secCode);
  WriteSection(SecIdData,   secData);
end;

{ ---- Scanner ---- }

procedure ReadCh;
begin
  if hasPushback then begin
    ch := pushbackCh;
    hasPushback := false;
    exit;
  end;
  if eof(input) then begin
    ch := #0;
    atEof := true;
  end else begin
    read(input, ch);
    if ch = #10 then begin
      srcLine := srcLine + 1;
      srcCol := 0;
    end else
      srcCol := srcCol + 1;
  end;
end;

procedure UnreadCh(c: char);
begin
  pushbackCh := c;
  hasPushback := true;
end;

function UpperCh(c: char): char;
begin
  if (c >= 'a') and (c <= 'z') then
    UpperCh := chr(ord(c) - 32)
  else
    UpperCh := c;
end;

procedure SkipParenComment;
{ Called after '(' and '*' have been read; skips to closing '*)'  }
begin
  ReadCh;  { first char inside comment }
  while not atEof do begin
    if ch = '*' then begin
      ReadCh;
      if ch = ')' then begin
        ReadCh;  { first char after comment }
        exit;
      end;
    end else
      ReadCh;
  end;
  Error('unterminated (* comment');
end;

procedure ParseDirective;
{ Called after dollar-brace seen; reads directive keyword and args, then closes brace. }
var
  kw:  string;
  arg1: string;
  arg2: string;
begin
  { Read keyword (uppercase letters) }
  kw := '';
  ReadCh;  { ch is first char of keyword (after '$') }
  while not atEof and (ch > ' ') and (ch <> '}') do begin
    kw := concat(kw, UpperCh(ch));
    ReadCh;
  end;
  if kw = 'IMPORT' then begin
    { Skip whitespace }
    while not atEof and (ch = ' ') do ReadCh;
    { Read module name }
    arg1 := '';
    while not atEof and (ch > ' ') and (ch <> '}') do begin
      arg1 := concat(arg1, ch);
      ReadCh;
    end;
    { Skip whitespace }
    while not atEof and (ch = ' ') do ReadCh;
    { Read field name }
    arg2 := '';
    while not atEof and (ch > ' ') and (ch <> '}') do begin
      arg2 := concat(arg2, ch);
      ReadCh;
    end;
    hasPendingImport := true;
    pendingImportMod := arg1;
    pendingImportFld := arg2;
  end else if kw = 'EXPORT' then begin
    { Skip whitespace }
    while not atEof and (ch = ' ') do ReadCh;
    { Read export name }
    arg1 := '';
    while not atEof and (ch > ' ') and (ch <> '}') do begin
      arg1 := concat(arg1, ch);
      ReadCh;
    end;
    hasPendingExport  := true;
    pendingExportName := arg1;
  end;
  { Skip to closing brace }
  while not atEof and (ch <> '}') do ReadCh;
  if ch = '}' then ReadCh;
end;

procedure SkipBraceComment;
{ Called when ch is opening brace; skips to closing brace (or handles directive) }
begin
  ReadCh;  { first char inside comment }
  if ch = '$' then begin
    ParseDirective;
    exit;
  end;
  while not atEof do begin
    if ch = '}' then begin
      ReadCh;  { first char after comment }
      exit;
    end;
    ReadCh;
  end;
  Error('unterminated { comment');
end;

procedure SkipLineComment;
{ Called when second '/' seen; reads to end of line  }
begin
  while not atEof and (ch <> #10) do
    ReadCh;
  { ch = #10 or atEof; outer whitespace loop will consume newline }
end;

procedure SkipWhitespaceAndComments;
var done: boolean;
begin
  done := false;
  while not done do begin
    while not atEof and (ch <= ' ') do
      ReadCh;
    if atEof then
      done := true
    else if ch = '{' then
      SkipBraceComment
    else if ch = '(' then begin
      ReadCh;
      if (not atEof) and (ch = '*') then
        SkipParenComment
      else begin
        UnreadCh(ch);
        ch := '(';  { restore for token dispatch }
        done := true;
      end;
    end else if ch = '/' then begin
      ReadCh;
      if (not atEof) and (ch = '/') then
        SkipLineComment
      else begin
        UnreadCh(ch);
        ch := '/';  { restore for token dispatch }
        done := true;
      end;
    end else
      done := true;
  end;
end;

function LookupKeyword(const s: string): longint;
begin
  LookupKeyword := tkIdent;
  if      s = 'PROGRAM'   then LookupKeyword := tkProgram
  else if s = 'BEGIN'     then LookupKeyword := tkBegin
  else if s = 'END'       then LookupKeyword := tkEnd
  else if s = 'VAR'       then LookupKeyword := tkVar
  else if s = 'CONST'     then LookupKeyword := tkConst
  else if s = 'TYPE'      then LookupKeyword := tkType
  else if s = 'PROCEDURE' then LookupKeyword := tkProcedure
  else if s = 'FUNCTION'  then LookupKeyword := tkFunction
  else if s = 'IF'        then LookupKeyword := tkIf
  else if s = 'THEN'      then LookupKeyword := tkThen
  else if s = 'ELSE'      then LookupKeyword := tkElse
  else if s = 'WHILE'     then LookupKeyword := tkWhile
  else if s = 'DO'        then LookupKeyword := tkDo
  else if s = 'FOR'       then LookupKeyword := tkFor
  else if s = 'TO'        then LookupKeyword := tkTo
  else if s = 'DOWNTO'    then LookupKeyword := tkDownto
  else if s = 'REPEAT'    then LookupKeyword := tkRepeat
  else if s = 'UNTIL'     then LookupKeyword := tkUntil
  else if s = 'AND'       then LookupKeyword := tkAnd
  else if s = 'OR'        then LookupKeyword := tkOr
  else if s = 'NOT'       then LookupKeyword := tkNot
  else if s = 'DIV'       then LookupKeyword := tkDiv
  else if s = 'MOD'       then LookupKeyword := tkMod
  else if s = 'SHR'       then LookupKeyword := tkShr
  else if s = 'SHL'       then LookupKeyword := tkShl
  else if s = 'OF'        then LookupKeyword := tkOf
  else if s = 'ARRAY'     then LookupKeyword := tkArray
  else if s = 'RECORD'    then LookupKeyword := tkRecord
  else if s = 'CASE'      then LookupKeyword := tkCase
  else if s = 'WITH'      then LookupKeyword := tkWith
  else if s = 'GOTO'      then LookupKeyword := tkGoto
  else if s = 'LABEL'     then LookupKeyword := tkLabel
  else if s = 'FORWARD'   then LookupKeyword := tkForward
  else if s = 'NIL'       then LookupKeyword := tkNil
  else if s = 'IN'        then LookupKeyword := tkIn
  else if s = 'FILE'      then LookupKeyword := tkFile
  else if s = 'SET'       then LookupKeyword := tkSet
  else if s = 'HALT'      then LookupKeyword := tkHalt
  else if s = 'WRITE'     then LookupKeyword := tkWrite
  else if s = 'WRITELN'   then LookupKeyword := tkWriteln
  else if s = 'READ'      then LookupKeyword := tkRead
  else if s = 'READLN'    then LookupKeyword := tkReadln
  else if s = 'TRUE'      then LookupKeyword := tkTrue
  else if s = 'FALSE'     then LookupKeyword := tkFalse
  else if s = 'BREAK'     then LookupKeyword := tkBreak
  else if s = 'CONTINUE'  then LookupKeyword := tkContinue
  else if s = 'EXIT'      then LookupKeyword := tkExit
  else if s = 'LENGTH'    then LookupKeyword := tkLength
  else if s = 'COPY'      then LookupKeyword := tkCopy
  else if s = 'POS'       then LookupKeyword := tkPos
  else if s = 'DELETE'    then LookupKeyword := tkDelete
  else if s = 'INSERT'    then LookupKeyword := tkInsert
  else if s = 'CONCAT'    then LookupKeyword := tkConcat
  else if s = 'STRING'    then LookupKeyword := tkStringType;
end;

{ Scan a string segment starting with opening quote already the next char to read.
  ch on entry must be the opening quote (already confirmed).
  Appends the segment content to ident; on return ch is the first char after
  the closing quote. }
procedure ScanStringSegment(var ident: string);
begin
  ReadCh;  { consume opening quote; ch is now first char inside }
  while true do begin
    if atEof then
      Error('unterminated string literal');
    if ch = '''' then begin
      ReadCh;
      if ch = '''' then begin  { doubled quote: literal single-quote }
        if length(ident) >= 255 then
          Error('string literal too long');
        ident := concat(ident, '''');
        ReadCh;
      end else
        break;  { end of this segment; ch is first char after closing quote }
    end else begin
      if length(ident) >= 255 then
        Error('string literal too long');
      ident := concat(ident, ch);
      ReadCh;
    end;
  end;
end;

{ Scan a #n or #$n character constant. ch on entry must be '#'.
  Appends chr(val) to ident; on return ch is the first char after the digits. }
procedure ScanCharConst(var ident: string);
var val: longint;
begin
  ReadCh;  { consume '#'; ch is now digit or '$' }
  val := 0;
  if ch = '$' then begin
    ReadCh;  { consume '$' }
    while not atEof and
          (((ch >= '0') and (ch <= '9')) or
           ((ch >= 'A') and (ch <= 'F')) or
           ((ch >= 'a') and (ch <= 'f'))) do begin
      if (ch >= '0') and (ch <= '9') then
        val := val * 16 + (ord(ch) - ord('0'))
      else if (ch >= 'A') and (ch <= 'F') then
        val := val * 16 + (ord(ch) - ord('A') + 10)
      else
        val := val * 16 + (ord(ch) - ord('a') + 10);
      ReadCh;
    end;
  end else begin
    while not atEof and (ch >= '0') and (ch <= '9') do begin
      val := val * 10 + (ord(ch) - ord('0'));
      ReadCh;
    end;
  end;
  if (val < 0) or (val > 255) then
    Error('character constant out of range');
  if length(ident) >= 255 then
    Error('string literal too long');
  ident := concat(ident, chr(val));
end;

procedure NextToken;
var
  ident: string;
  val:   longint;
  c:     char;
begin
  { Return any token pushed back by and-then / or-else lookahead }
  if pendingTok then begin
    tokKind    := pendingKind;
    tokStr     := pendingStr;
    pendingTok := false;
    exit;
  end;

  SkipWhitespaceAndComments;

  if atEof then begin
    tokKind := tkEOF;
    exit;
  end;

  case ch of
    'A'..'Z', 'a'..'z', '_': begin
      ident := '';
      while not atEof and
            (((ch >= 'A') and (ch <= 'Z')) or
             ((ch >= 'a') and (ch <= 'z')) or
             ((ch >= '0') and (ch <= '9')) or
             (ch = '_')) do begin
        c := UpperCh(ch);
        ident := concat(ident, c);
        ReadCh;
      end;
      tokStr  := ident;
      tokKind := LookupKeyword(ident);
      { fold two-word operators }
      if tokKind = tkAnd then begin
        NextToken;
        if tokKind = tkThen then
          tokKind := tkAndThen
        else begin
          pendingTok  := true;
          pendingKind := tokKind;
          pendingStr  := tokStr;
          tokKind     := tkAnd;
          tokStr      := 'AND';
        end;
      end else if tokKind = tkOr then begin
        NextToken;
        if tokKind = tkElse then
          tokKind := tkOrElse
        else begin
          pendingTok  := true;
          pendingKind := tokKind;
          pendingStr  := tokStr;
          tokKind     := tkOr;
          tokStr      := 'OR';
        end;
      end;
    end;
    '''': begin
      ident := '';
      ScanStringSegment(ident);
      { fold any adjacent segments }
      while (ch = '''') or (ch = '#') do begin
        if ch = '''' then
          ScanStringSegment(ident)
        else
          ScanCharConst(ident);
      end;
      tokStr  := ident;
      tokKind := tkString;
    end;
    '#': begin
      ident := '';
      ScanCharConst(ident);
      { fold any adjacent segments }
      while (ch = '''') or (ch = '#') do begin
        if ch = '''' then
          ScanStringSegment(ident)
        else
          ScanCharConst(ident);
      end;
      tokStr  := ident;
      tokKind := tkString;
    end;
    '0'..'9': begin
      val := 0;
      while not atEof and (ch >= '0') and (ch <= '9') do begin
        val := val * 10 + (ord(ch) - ord('0'));
        ReadCh;
      end;
      { detect unsupported real number syntax }
      if ch = '.' then begin
        ReadCh;
        if (ch >= '0') and (ch <= '9') then
          Error('real numbers are not supported')
        else begin
          UnreadCh(ch);
          ch := '.';
        end;
      end;
      tokInt  := val;
      tokKind := tkInteger;
    end;
    '$': begin
      ReadCh;
      val := 0;
      while not atEof and
            (((ch >= '0') and (ch <= '9')) or
             ((ch >= 'A') and (ch <= 'F')) or
             ((ch >= 'a') and (ch <= 'f'))) do begin
        if (ch >= '0') and (ch <= '9') then
          val := val * 16 + (ord(ch) - ord('0'))
        else if (ch >= 'A') and (ch <= 'F') then
          val := val * 16 + (ord(ch) - ord('A') + 10)
        else
          val := val * 16 + (ord(ch) - ord('a') + 10);
        ReadCh;
      end;
      tokInt  := val;
      tokKind := tkInteger;
    end;
    '+': begin tokKind := tkPlus;      ReadCh; end;
    '-': begin tokKind := tkMinus;     ReadCh; end;
    '*': begin tokKind := tkStar;      ReadCh; end;
    '/': begin tokKind := tkSlash;     ReadCh; end;
    '(': begin tokKind := tkLParen;    ReadCh; end;
    ')': begin tokKind := tkRParen;    ReadCh; end;
    ';': begin tokKind := tkSemicolon; ReadCh; end;
    ',': begin tokKind := tkComma;     ReadCh; end;
    '[': begin tokKind := tkLBracket;  ReadCh; end;
    ']': begin tokKind := tkRBracket;  ReadCh; end;
    '^': begin tokKind := tkCaret;     ReadCh; end;
    '=': begin tokKind := tkEq;        ReadCh; end;
    ':': begin
      ReadCh;
      if (not atEof) and (ch = '=') then begin
        tokKind := tkAssign; ReadCh;
      end else
        tokKind := tkColon;
    end;
    '.': begin
      ReadCh;
      if (not atEof) and (ch = '.') then begin
        tokKind := tkDotDot; ReadCh;
      end else
        tokKind := tkDot;
    end;
    '<': begin
      ReadCh;
      if (not atEof) and (ch = '=') then begin
        tokKind := tkLe; ReadCh;
      end else if (not atEof) and (ch = '>') then begin
        tokKind := tkNe; ReadCh;
      end else
        tokKind := tkLt;
    end;
    '>': begin
      ReadCh;
      if (not atEof) and (ch = '=') then begin
        tokKind := tkGe; ReadCh;
      end else
        tokKind := tkGt;
    end;
  else
    Error(concat('unexpected character: ', ch));
  end;
end;

{ ---- Symbol Table ---- }

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
  syms[numSyms].name        := name;
  syms[numSyms].kind        := kind;
  syms[numSyms].typ         := typ;
  syms[numSyms].typeIdx     := -1;
  syms[numSyms].level       := scopeDepth;
  syms[numSyms].offset      := 0;
  syms[numSyms].size        := 0;
  syms[numSyms].isVarParam  := false;
  syms[numSyms].isConstParam := false;
  syms[numSyms].strMaxLen   := 0;
  AddSym  := numSyms;
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
  s := AddSym('BYTE', skType, tyChar);
  syms[s].size := 1;
  { FILE type: dummy 4-byte handle for TP file I/O procedures }
  s := AddSym('FILE', skType, tyInteger);
  syms[s].size := 4;
  { Chapter 8 }
  s := AddSym('STRING', skType, tyString);
  syms[s].size      := 256;
  syms[s].strMaxLen := 255;
end;

{ ---- Data Segment ---- }

function AllocData(nbytes: longint): longint;
{ Reserves nbytes in the data segment; returns its linear memory address. }
var addr: longint;
    i:    longint;
begin
  addr    := DataBase + dataLen;
  dataLen := dataLen + nbytes;
  for i := 1 to nbytes do
    SmallBufEmit(dataBuf, 0);
  AllocData := addr;
end;

function EmitDataString(const s: string): longint;
{ Places string s bytes into the data segment; returns start address. }
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

function EmitDataPascalString(const s: string): longint;
{ Stores a Pascal string (length-prefixed) in the data segment; returns start address. }
var
  addr: longint;
  i:    longint;
begin
  addr := DataBase + dataLen;
  SmallBufEmit(dataBuf, length(s));
  dataLen := dataLen + 1;
  for i := 1 to length(s) do begin
    SmallBufEmit(dataBuf, ord(s[i]));
    dataLen := dataLen + 1;
  end;
  EmitDataPascalString := addr;
end;

procedure EnsureIOBuffers;
{ Lazily allocates I/O scratch areas in the data segment on first call.
  iovec and nwritten require 4-byte alignment; pad dataLen if needed. }
begin
  if addrIovec >= 0 then exit;
  { align dataLen to 4 bytes so iovec/nwritten are at aligned addresses }
  while (dataLen mod 4) <> 0 do begin
    SmallBufEmit(dataBuf, 0);
    dataLen := dataLen + 1;
  end;
  addrIovec    := AllocData(8);   { iovec: ptr(4) + len(4) }
  addrNwritten := AllocData(4);   { nwritten return value }
  addrNewline  := AllocData(1);   { newline character }
  dataBuf.data[addrNewline - DataBase] := 10;  { '\n' }
  addrIntBuf   := AllocData(20);  { decimal digit scratch }
end;

{ ---- Code Generation ---- }

procedure EmitOp(op: byte); forward;
procedure EmitI32Const(n: longint); forward;
procedure EmitFramePtr(level: longint); forward;
procedure EmitStrAddr(s: longint); forward;
procedure EmitMemCopy; forward;
procedure EmitLocalTee(idx: longint); forward;

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

function AddImport(const modname, fieldname: string; typeIdx: longint): longint;
var i: longint;
begin
  SmallBufEmit(importsBuf, length(modname));
  for i := 1 to length(modname) do
    SmallBufEmit(importsBuf, ord(modname[i]));
  SmallBufEmit(importsBuf, length(fieldname));
  for i := 1 to length(fieldname) do
    SmallBufEmit(importsBuf, ord(fieldname[i]));
  SmallBufEmit(importsBuf, 0);              { import kind: function }
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
  { Register all imports before locking in __write_int's index.
    This keeps idxWriteInt stable even if halt is called later. }
  EnsureFdWrite;
  EnsureProcExit;
  { _start = numImports+0; __write_int = numImports+1 }
  idxWriteInt     := numImports + 1;
  needWriteInt    := true;
  numDefinedFuncs := numDefinedFuncs + 1;
  EnsureWriteInt  := idxWriteInt;
end;

procedure BuildWriteIntHelper;
{** Emits the __write_int WASM function body into helperCode.
  Must be called after all imports are finalized (from WriteModule).
  Parameter 0: i32 value to print.
  Local 1: pos  (current write position in intBuf).
  Local 2: neg  (1 if original value was negative). }
var
  bufEnd: longint;

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

  { if value < 0: neg=1, value=-value }
  HLocalGet(0); HI32Const(0); HEmit(OpI32LtS);
  HEmit(OpIf); HEmit(WasmVoid);
    HI32Const(1); HLocalSet(2);
    HI32Const(0); HLocalGet(0); HEmit(OpI32Sub); HLocalSet(0);
  HEmit(OpEnd);

  { handle value=0 vs nonzero }
  HLocalGet(0); HEmit(OpI32Eqz);
  HEmit(OpIf); HEmit(WasmVoid);
    { zero case: write single '0' digit }
    HLocalGet(1); HI32Const(1); HEmit(OpI32Sub); HLocalSet(1);
    HLocalGet(1); HI32Const(48); HEmit(OpI32Store8); HEmit(0); HEmit(0);
  HEmit(OpElse);
    { nonzero: extract digits right-to-left }
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
  HEmit(OpEnd);      { if/else }

  { if neg: prepend '-' }
  HLocalGet(2);
  HEmit(OpIf); HEmit(WasmVoid);
    HLocalGet(1); HI32Const(1); HEmit(OpI32Sub); HLocalSet(1);
    HLocalGet(1); HI32Const(45); HEmit(OpI32Store8); HEmit(0); HEmit(0);
  HEmit(OpEnd);

  { set iovec.buf = pos }
  HI32Const(addrIovec); HLocalGet(1);
  HEmit(OpI32Store); HEmit(2); HEmit(0);
  { set iovec.len = bufEnd - pos }
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

procedure BuildStrAssignHelper;
{ Emits __str_assign: copy string with length checking }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { copy_len = src[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { src }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { copy_len }

  { if copy_len > max_len: copy_len = max_len }
  CodeBufEmit(startCode, OpBlock); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { copy_len }
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { max_len }
    CodeBufEmit(startCode, OpI32LeS);
    CodeBufEmit(startCode, OpBrIf); CodeBufEmit(startCode, 0);
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { max_len }
    CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { copy_len }
  CodeBufEmit(startCode, OpEnd);

  { dst[0] = copy_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { dst }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { copy_len }
  CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

  { memory.copy(dst+1, src+1, copy_len) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { dst }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { src }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { copy_len }
  CodeBufEmit(startCode, OpMiscPrefix);
  CodeBufEmit(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);
  CodeBufEmit(startCode, 0);

  strHlpStart[0] := strHelperCode.len;
  strHlpLen[0] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildWriteStrHelper;
{ Emits __write_str: write string to stdout }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { len = addr[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { addr }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalTee); EmitULEB128(startCode, 1); { len }

  { if len > 0: ... }
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    { iovec.ptr = addr + 1 }
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrIovec);
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { addr }
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
    CodeBufEmit(startCode, OpI32Add);
    CodeBufEmit(startCode, OpI32Store); EmitULEB128(startCode, 2); EmitULEB128(startCode, 0);

    { iovec.len = len }
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrIovec + 4);
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { len }
    CodeBufEmit(startCode, OpI32Store); EmitULEB128(startCode, 2); EmitULEB128(startCode, 0);

    { fd_write(1, addrIovec, 1, addrNwritten); drop }
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrIovec);
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrNwritten);
    CodeBufEmit(startCode, OpCall); EmitULEB128(startCode, idxFdWrite);
    CodeBufEmit(startCode, OpDrop);
  CodeBufEmit(startCode, OpEnd);

  strHlpStart[1] := strHelperCode.len;
  strHlpLen[1] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildStrCompareHelper;
{ Emits __str_compare: compare two strings lexicographically }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { len_a = a[0]; len_b = b[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { a }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 2); { len_a }

  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { b }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { len_b }

  { min_len = min(len_a, len_b) using select }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { len_a }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { len_b }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { len_a }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { len_b }
  CodeBufEmit(startCode, OpI32LeS);
  CodeBufEmit(startCode, OpSelect);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 4); { min_len }

  { i = 1 }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { i }

  { result = 0 }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { result }

  { block (outer break) }
  CodeBufEmit(startCode, OpBlock); CodeBufEmit(startCode, WasmVoid);
    { block; loop (char scan) }
    CodeBufEmit(startCode, OpBlock); CodeBufEmit(startCode, WasmVoid);
      CodeBufEmit(startCode, OpLoop); CodeBufEmit(startCode, WasmVoid);
        { if i > min_len: br_if 1 (exit loop-block) }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { i }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { min_len }
        CodeBufEmit(startCode, OpI32GtS);
        CodeBufEmit(startCode, OpBrIf); CodeBufEmit(startCode, 1);

        { if a[i] < b[i]: result = -1; br 3 (exit outer) }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { a }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { i }
        CodeBufEmit(startCode, OpI32Add);
        CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { b }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { i }
        CodeBufEmit(startCode, OpI32Add);
        CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
        CodeBufEmit(startCode, OpI32LtS);
        CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
          CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, -1);
          CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { result }
          CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 3);
        CodeBufEmit(startCode, OpEnd);

        { if a[i] > b[i]: result = 1; br 3 (exit outer) }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { a }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { i }
        CodeBufEmit(startCode, OpI32Add);
        CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { b }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { i }
        CodeBufEmit(startCode, OpI32Add);
        CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
        CodeBufEmit(startCode, OpI32GtS);
        CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
          CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
          CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { result }
          CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 3);
        CodeBufEmit(startCode, OpEnd);

        { i++ }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { i }
        CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
        CodeBufEmit(startCode, OpI32Add);
        CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { i }

        { br 0 (loop) }
        CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 0);
      CodeBufEmit(startCode, OpEnd); { loop }
    CodeBufEmit(startCode, OpEnd); { block }

    { if len_a < len_b: result = -1; br 1 }
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { len_a }
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { len_b }
    CodeBufEmit(startCode, OpI32LtS);
    CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, -1);
      CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { result }
      CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 1);
    CodeBufEmit(startCode, OpEnd);

    { if len_a > len_b: result = 1; br 1 }
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { len_a }
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { len_b }
    CodeBufEmit(startCode, OpI32GtS);
    CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
      CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { result }
      CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 1);
    CodeBufEmit(startCode, OpEnd);
  CodeBufEmit(startCode, OpEnd); { outer block }

  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { result }

  strHlpStart[2] := strHelperCode.len;
  strHlpLen[2] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildReadStrHelper;
{ Emits __read_str: read string from stdin }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { count = 0 }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 2); { count }

  { block; loop; ... }
  CodeBufEmit(startCode, OpBlock); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpLoop); CodeBufEmit(startCode, WasmVoid);
      { if count >= max_len: br_if 1 }
      CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { count }
      CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { max_len }
      CodeBufEmit(startCode, OpI32GeS);
      CodeBufEmit(startCode, OpBrIf); CodeBufEmit(startCode, 1);

      { iovec.ptr = addrReadBuf }
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrIovec);
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrReadBuf);
      CodeBufEmit(startCode, OpI32Store); EmitULEB128(startCode, 2); EmitULEB128(startCode, 0);

      { iovec.len = 1 }
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrIovec + 4);
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
      CodeBufEmit(startCode, OpI32Store); EmitULEB128(startCode, 2); EmitULEB128(startCode, 0);

      { fd_read(0, addrIovec, 1, addrNwritten); drop }
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrIovec);
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrNwritten);
      CodeBufEmit(startCode, OpCall); EmitULEB128(startCode, idxFdRead);
      CodeBufEmit(startCode, OpDrop);

      { byte_val = addrReadBuf[0] }
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrReadBuf);
      CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
      CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { byte_val }

      { if byte_val < 32: br_if 1 (control char, exit) }
      CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { byte_val }
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 32);
      CodeBufEmit(startCode, OpI32LtS);
      CodeBufEmit(startCode, OpBrIf); CodeBufEmit(startCode, 1);

      { addr[1+count] = byte_val }
      CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { addr }
      CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { count }
      CodeBufEmit(startCode, OpI32Add);
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
      CodeBufEmit(startCode, OpI32Add);
      CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { byte_val }
      CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

      { count++ }
      CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { count }
      CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
      CodeBufEmit(startCode, OpI32Add);
      CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 2); { count }

      { br 0 (loop) }
      CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 0);
    CodeBufEmit(startCode, OpEnd); { loop }
  CodeBufEmit(startCode, OpEnd); { block }

  { addr[0] = count }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { addr }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { count }
  CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

  strHlpStart[3] := strHelperCode.len;
  strHlpLen[3] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildStrAppendHelper;
{ Emits __str_append: append src to dst with length checking }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { dst_len = dst[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { dst }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { dst_len }

  { src_len = src[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { src }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 4); { src_len }

  { avail = max_len - dst_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { max_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { dst_len }
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { avail }

  { if avail <= 0: return }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { avail }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
  CodeBufEmit(startCode, OpI32LeS);
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpReturn);
  CodeBufEmit(startCode, OpEnd);

  { copy_len = min(src_len, avail) using select }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { src_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { avail }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { src_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { avail }
  CodeBufEmit(startCode, OpI32LeS);
  CodeBufEmit(startCode, OpSelect);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { copy_len }

  { memory.copy(dst+1+dst_len, src+1, copy_len) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { dst }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { dst_len }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { src }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { copy_len }
  CodeBufEmit(startCode, OpMiscPrefix);
  CodeBufEmit(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);
  CodeBufEmit(startCode, 0);

  { dst[0] = dst_len + copy_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { dst }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { dst_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { copy_len }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

  strHlpStart[4] := strHelperCode.len;
  strHlpLen[4] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildStrCopyHelper;
{ Emits __str_copy: copy substring }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { src_len = src[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { src }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { src_len }

  { actual_start = idx - 1 }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { idx }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 4); { actual_start }

  { if actual_start >= src_len: scratch[0]=0; return addrStrScratch }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { actual_start }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { src_len }
  CodeBufEmit(startCode, OpI32GeS);
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrStrScratch);
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
    CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrStrScratch);
    CodeBufEmit(startCode, OpReturn);
  CodeBufEmit(startCode, OpEnd);

  { avail = src_len - actual_start }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { src_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { actual_start }
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { avail }

  { actual_count = min(count, avail) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { count }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { avail }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { count }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { avail }
  CodeBufEmit(startCode, OpI32LeS);
  CodeBufEmit(startCode, OpSelect);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { actual_count }

  { scratch[0] = actual_count }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrStrScratch);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { actual_count }
  CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

  { memory.copy(addrStrScratch+1, src+1+actual_start, actual_count) }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrStrScratch + 1);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { src }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { actual_start }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { actual_count }
  CodeBufEmit(startCode, OpMiscPrefix);
  CodeBufEmit(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);
  CodeBufEmit(startCode, 0);

  { return addrStrScratch }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, addrStrScratch);

  strHlpStart[5] := strHelperCode.len;
  strHlpLen[5] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildStrPosHelper;
{ Emits __str_pos: find substring position }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { sub_len = sub[0]; s_len = s[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { sub }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 2); { sub_len }

  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { s }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { s_len }

  { result = 0 }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { result }

  { if sub_len = 0: return 1 }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { sub_len }
  CodeBufEmit(startCode, OpI32Eqz);
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
    CodeBufEmit(startCode, OpReturn);
  CodeBufEmit(startCode, OpEnd);

  { block (outer) }
  CodeBufEmit(startCode, OpBlock); CodeBufEmit(startCode, WasmVoid);
    { i = 0 }
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
    CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 4); { i }

    { block; loop (i scan) }
    CodeBufEmit(startCode, OpBlock); CodeBufEmit(startCode, WasmVoid);
      CodeBufEmit(startCode, OpLoop); CodeBufEmit(startCode, WasmVoid);
        { if i + sub_len > s_len: br_if 1 }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { i }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { sub_len }
        CodeBufEmit(startCode, OpI32Add);
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { s_len }
        CodeBufEmit(startCode, OpI32GtS);
        CodeBufEmit(startCode, OpBrIf); CodeBufEmit(startCode, 1);

        { j = 0 }
        CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
        CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { j }

        { block; loop (j scan - match attempt) }
        CodeBufEmit(startCode, OpBlock); CodeBufEmit(startCode, WasmVoid);
          CodeBufEmit(startCode, OpLoop); CodeBufEmit(startCode, WasmVoid);
            { if j >= sub_len: br_if 1 }
            CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { j }
            CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { sub_len }
            CodeBufEmit(startCode, OpI32GeS);
            CodeBufEmit(startCode, OpBrIf); CodeBufEmit(startCode, 1);

            { if s[1+i+j] != sub[1+j]: br_if 1 }
            CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { s }
            CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
            CodeBufEmit(startCode, OpI32Add);
            CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { i }
            CodeBufEmit(startCode, OpI32Add);
            CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { j }
            CodeBufEmit(startCode, OpI32Add);
            CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
            CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { sub }
            CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
            CodeBufEmit(startCode, OpI32Add);
            CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { j }
            CodeBufEmit(startCode, OpI32Add);
            CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
            CodeBufEmit(startCode, OpI32Ne);
            CodeBufEmit(startCode, OpBrIf); CodeBufEmit(startCode, 1);

            { j++ }
            CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { j }
            CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
            CodeBufEmit(startCode, OpI32Add);
            CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { j }

            { br 0 (loop) }
            CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 0);
          CodeBufEmit(startCode, OpEnd); { loop }
        CodeBufEmit(startCode, OpEnd); { block }

        { if j = sub_len: result = i+1; br 2 (exit outer) }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { j }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { sub_len }
        CodeBufEmit(startCode, OpI32Eq);
        CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
          CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { i }
          CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
          CodeBufEmit(startCode, OpI32Add);
          CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { result }
          CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 2);
        CodeBufEmit(startCode, OpEnd);

        { i++ }
        CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { i }
        CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
        CodeBufEmit(startCode, OpI32Add);
        CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 4); { i }

        { br 0 (loop) }
        CodeBufEmit(startCode, OpBr); CodeBufEmit(startCode, 0);
      CodeBufEmit(startCode, OpEnd); { loop }
    CodeBufEmit(startCode, OpEnd); { block }
  CodeBufEmit(startCode, OpEnd); { outer block }

  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { result }

  strHlpStart[6] := strHelperCode.len;
  strHlpLen[6] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildStrDeleteHelper;
{ Emits __str_delete: delete substring }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { s_len = s[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { s }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { s_len }

  { actual_idx = max(idx-1, 0) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { idx }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { idx }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
  CodeBufEmit(startCode, OpI32GtS);
  CodeBufEmit(startCode, OpSelect);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 4); { actual_idx }

  { if actual_idx >= s_len: return }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { actual_idx }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { s_len }
  CodeBufEmit(startCode, OpI32GeS);
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpReturn);
  CodeBufEmit(startCode, OpEnd);

  { actual_count = min(count, s_len - actual_idx) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { count }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { s_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { actual_idx }
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { count }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { s_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { actual_idx }
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpI32LeS);
  CodeBufEmit(startCode, OpSelect);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { actual_count }

  { tail_start = actual_idx + actual_count }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { actual_idx }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { actual_count }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { tail_start }

  { tail_len = s_len - tail_start }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { s_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { tail_start }
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 7); { tail_len }

  { memory.copy(s+1+actual_idx, s+1+tail_start, tail_len) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { s }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { actual_idx }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { s }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { tail_start }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 7); { tail_len }
  CodeBufEmit(startCode, OpMiscPrefix);
  CodeBufEmit(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);
  CodeBufEmit(startCode, 0);

  { s[0] = s_len - actual_count }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { s }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { s_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { actual_count }
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

  strHlpStart[7] := strHelperCode.len;
  strHlpLen[7] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildStrInsertHelper;
{ Emits __str_insert: insert src into dst }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { src_len = src[0]; dst_len = dst[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { src }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { src_len }

  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { dst }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 4); { dst_len }

  { actual_idx = idx - 1 }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { idx }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { actual_idx }

  { if actual_idx < 0: actual_idx = 0 }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { actual_idx }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
  CodeBufEmit(startCode, OpI32LtS);
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
    CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { actual_idx }
  CodeBufEmit(startCode, OpEnd);

  { if actual_idx > dst_len: actual_idx = dst_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { actual_idx }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { dst_len }
  CodeBufEmit(startCode, OpI32GtS);
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { dst_len }
    CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 5); { actual_idx }
  CodeBufEmit(startCode, OpEnd);

  { avail = 255 - dst_len }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 255);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { dst_len }
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 6); { avail }

  { if avail <= 0: return }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { avail }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 0);
  CodeBufEmit(startCode, OpI32LeS);
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpReturn);
  CodeBufEmit(startCode, OpEnd);

  { insert_count = min(src_len, avail) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { src_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { avail }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { src_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 6); { avail }
  CodeBufEmit(startCode, OpI32LeS);
  CodeBufEmit(startCode, OpSelect);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 7); { insert_count }

  { move_count = dst_len - actual_idx }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { dst_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { actual_idx }
  CodeBufEmit(startCode, OpI32Sub);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 8); { move_count }

  { memory.copy(dst+1+actual_idx+insert_count, dst+1+actual_idx, move_count) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { dst }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { actual_idx }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 7); { insert_count }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { dst }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { actual_idx }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 8); { move_count }
  CodeBufEmit(startCode, OpMiscPrefix);
  CodeBufEmit(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);
  CodeBufEmit(startCode, 0);

  { memory.copy(dst+1+actual_idx, src+1, insert_count) }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { dst }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 5); { actual_idx }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { src }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 7); { insert_count }
  CodeBufEmit(startCode, OpMiscPrefix);
  CodeBufEmit(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);
  CodeBufEmit(startCode, 0);

  { dst[0] = dst_len + insert_count }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { dst }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 4); { dst_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 7); { insert_count }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

  strHlpStart[8] := strHelperCode.len;
  strHlpLen[8] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildStrAppendCharHelper;
{ Emits __str_append_char(dst, max_len, char_byte): append single char byte to dst string }
var savedCode: TCodeBuf;
    i: longint;
begin
  savedCode := startCode;
  CodeBufInit(startCode);

  { local 3 = dst_len = dst[0] }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { dst }
  CodeBufEmit(startCode, OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
  CodeBufEmit(startCode, OpLocalSet); EmitULEB128(startCode, 3); { dst_len }

  { if dst_len >= max_len: return }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { dst_len }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 1); { max_len }
  CodeBufEmit(startCode, OpI32GeS);
  CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
    CodeBufEmit(startCode, OpReturn);
  CodeBufEmit(startCode, OpEnd);

  { dst[1 + dst_len] = char_byte }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { dst }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { dst_len }
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 2); { char_byte }
  CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

  { dst[0] = dst_len + 1 }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 0); { dst }
  CodeBufEmit(startCode, OpLocalGet); EmitULEB128(startCode, 3); { dst_len }
  CodeBufEmit(startCode, OpI32Const); EmitSLEB128(startCode, 1);
  CodeBufEmit(startCode, OpI32Add);
  CodeBufEmit(startCode, OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);

  strHlpStart[9] := strHelperCode.len;
  strHlpLen[9] := startCode.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(strHelperCode, startCode.data[i]);

  startCode := savedCode;
end;

procedure BuildStringHelpers;
begin
  if needStrAssign then BuildStrAssignHelper;
  if needWriteStr then BuildWriteStrHelper;
  if needStrCompare then BuildStrCompareHelper;
  if needReadStr then BuildReadStrHelper;
  if needStrAppend then BuildStrAppendHelper;
  if needStrCopy then BuildStrCopyHelper;
  if needStrPos then BuildStrPosHelper;
  if needStrDelete then BuildStrDeleteHelper;
  if needStrInsert then BuildStrInsertHelper;
  if needStrAppendChar then BuildStrAppendCharHelper;
end;

function FindOrAddWasmType(np: longint; hasRet: boolean): longint;
{ Find or register a WASM type (i32)^np -> (i32 or void). }
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
  { Not found: add }
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

procedure EnsureStringHelpers;
begin
  if strHelpersReserved then exit;
  strHelpersReserved := true;
  EnsureFdWrite;
  EnsureProcExit;
  { Add fd_read BEFORE __write_int so the function index is computed with the
    final import count. If EnsureWriteInt was already called (without fd_read),
    we recalculate idxWriteInt after adding fd_read. }
  if idxFdRead < 0 then
    idxFdRead := AddImport('wasi_snapshot_preview1', 'fd_read', TypeFdWrite);
  if needWriteInt then
    idxWriteInt := numImports + 1  { fd_read just added: fix the stale index }
  else
    EnsureWriteInt;  { first call: computes with correct numImports }
  idxStrAssign  := numImports + SlotStrAssign;
  idxWriteStr   := numImports + SlotWriteStr;
  idxStrCompare := numImports + SlotStrComp;
  idxReadStr    := numImports + SlotReadStr;
  idxStrAppend  := numImports + SlotStrAppend;
  idxStrCopy    := numImports + SlotStrCopy;
  idxStrPos     := numImports + SlotStrPos;
  idxStrDelete      := numImports + SlotStrDel;
  idxStrInsert      := numImports + SlotStrIns;
  idxStrAppendChar  := numImports + SlotStrAppendChar;
  numDefinedFuncs := numDefinedFuncs + 10;
end;

function EnsureStrAssign: longint;
begin
  EnsureStringHelpers;
  EnsureIOBuffers;
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
  EnsureIOBuffers;
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

function EnsureStrAppendChar: longint;
begin
  EnsureStringHelpers;
  needStrAppendChar := true;
  EnsureStrAppendChar := idxStrAppendChar;
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

procedure EnsureBuiltinImports;
{ Register fd_write, proc_exit, and __write_int before any user function index
  is locked in. This ensures user functions always start at numImports+2. }
begin
  EnsureFdWrite;
  EnsureProcExit;
  EnsureWriteInt;
  EnsureStringHelpers;
end;

procedure EmitFramePtr(level: longint);
{ Emit code to push the frame pointer for the given scope level.
  If level = curNestLevel, the variable is local: use $sp (global 0).
  Otherwise, it is an upvalue: use display[level] (global level+1). }
begin
  if level = curNestLevel then
    EmitGlobalGet(0)
  else
    EmitGlobalGet(level + 1);
end;

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

procedure EmitExportEntry(name: string; funcIdx: longint);
{ Append one export entry to userExportsBuf: name bytes then function index. }
var i: longint;
begin
  SmallBufEmit(userExportsBuf, length(name));
  for i := 1 to length(name) do
    SmallBufEmit(userExportsBuf, ord(name[i]));
  SmallBufEmit(userExportsBuf, $00);  { export kind: function }
  SmallEmitULEB128(userExportsBuf, funcIdx);
end;

procedure EmitVarLoad(s: longint);
{ Emit WASM instructions to load the value of variable/parameter s onto stack. }
var localIdx: longint;
begin
  if syms[s].offset < 0 then begin
    { Parameter: WASM local, encoded as -(localIdx+1) }
    localIdx := -(syms[s].offset + 1);
    if syms[s].isVarParam then begin
      { Var param: local holds address -- dereference it }
      EmitLocalGet(localIdx);
      if syms[s].size = 1 then
        EmitI32Load8u(0, 0)
      else
        EmitI32Load(2, 0);
    end else
      EmitLocalGet(localIdx);
  end else begin
    { Frame variable: address = $sp + offset }
    EmitFramePtr(syms[s].level);
    EmitI32Const(syms[s].offset);
    EmitOp(OpI32Add);
    if syms[s].size = 1 then
      EmitI32Load8u(0, 0)
    else
      EmitI32Load(2, 0);
  end;
end;

procedure EmitStrAddr(s: longint);
{ Push address of string variable s onto WASM stack. }
var localIdx: longint;
begin
  if syms[s].offset < 0 then begin
    localIdx := -(syms[s].offset + 1);
    CodeBufEmit(startCode, OpLocalGet);
    EmitULEB128(startCode, localIdx);
  end else begin
    EmitFramePtr(syms[s].level);
    EmitI32Const(syms[s].offset);
    EmitOp(OpI32Add);
  end;
end;

procedure EmitMemCopy;
begin
  CodeBufEmit(startCode, OpMiscPrefix);
  CodeBufEmit(startCode, OpMemCopy);
  CodeBufEmit(startCode, 0);
  CodeBufEmit(startCode, 0);
end;

procedure EmitLocalTee(idx: longint);
begin
  EmitOp(OpLocalTee);
  EmitULEB128(startCode, idx);
end;

{ ---- Chapter 9: Type Descriptor Helpers ---- }

function AddTypeDesc: longint;
begin
  if numTypes >= MaxTypeDescs then
    Error('too many type descriptors');
  types[numTypes].kind        := 0;
  types[numTypes].size        := 0;
  types[numTypes].fieldStart  := 0;
  types[numTypes].fieldCount  := 0;
  types[numTypes].arrLo       := 0;
  types[numTypes].arrHi       := 0;
  types[numTypes].elemType    := 0;
  types[numTypes].elemTypeIdx := -1;
  types[numTypes].elemSize    := 0;
  AddTypeDesc := numTypes;
  numTypes    := numTypes + 1;
end;

procedure AddField(const fname: string; ftyp, ftypeIdx, foffset, fsize: longint);
begin
  if numFields >= MaxFields then
    Error('too many record fields');
  fields[numFields].name    := fname;
  fields[numFields].typ     := ftyp;
  fields[numFields].typeIdx := ftypeIdx;
  fields[numFields].offset  := foffset;
  fields[numFields].size    := fsize;
  numFields := numFields + 1;
end;

{ ---- Forward declarations ---- }

procedure ParseExpression(minPrec: longint); forward;
procedure ParseStatement; forward;
procedure ParseProcDecl; forward;
procedure ParseCallArgs(sym: longint); forward;
procedure ParseTypeSpec(var outTyp, outTypeIdx, outSize, outStrMax: longint); forward;

{ ---- Parser ---- }

procedure Expect(kind: longint);
begin
  if tokKind <> kind then begin
    writeln(StdErr, 'Error: [', srcLine, ':', srcCol, '] expected token ',
            kind, ' got ', tokKind);
    halt(1);
  end;
  NextToken;
end;

procedure ParseCallArgs(sym: longint);
{ Parse the actual argument list for a call to syms[sym] (a proc or func).
  Already consumed the opening paren. Stops before the closing paren. }
var
  argIdx: longint;
  fslot:  longint;
  argSym: longint;
begin
  fslot  := syms[sym].size;   { index into funcs[] }
  argIdx := 0;
  while tokKind <> tkRParen do begin
    if funcs[fslot].varParams[argIdx] then begin
      { Var param: pass address of the argument variable }
      if tokKind <> tkIdent then
        Error('var param requires a variable argument');
      argSym := LookupSym(tokStr);
      if argSym < 0 then
        Error(concat('unknown identifier: ', tokStr));
      NextToken;
      if (syms[argSym].offset < 0) and syms[argSym].isVarParam then begin
        { Caller's arg is itself a var param -- its local already holds address }
        EmitLocalGet(-(syms[argSym].offset + 1));
      end else if syms[argSym].offset < 0 then begin
        Error('cannot pass value parameter as var parameter');
      end else begin
        { Frame variable: push frame-ptr + offset }
        EmitFramePtr(syms[argSym].level);
        EmitI32Const(syms[argSym].offset);
        EmitOp(OpI32Add);
      end;
      { Handle array subscript: array_var[idx] -- compute element address }
      if tokKind = tkLBracket then begin
        NextToken;
        ParseExpression(PrecNone);  { index }
        if syms[argSym].typ = tyArray then begin
          if types[syms[argSym].typeIdx].arrLo <> 0 then begin
            EmitI32Const(types[syms[argSym].typeIdx].arrLo);
            EmitOp(OpI32Sub);
          end;
          if types[syms[argSym].typeIdx].elemSize <> 1 then begin
            EmitI32Const(types[syms[argSym].typeIdx].elemSize);
            EmitOp(OpI32Mul);
          end;
        end;
        EmitOp(OpI32Add);
        Expect(tkRBracket);
      end;
    end else if funcs[fslot].constParams[argIdx] then begin
      { Const param: pass by address (read-only) }
      if tokKind = tkString then begin
        { String literal: emit to data segment, push address }
        EmitI32Const(EmitDataPascalString(tokStr));
        NextToken;
      end else begin
        if tokKind <> tkIdent then
          Error('const param requires a variable argument');
        argSym := LookupSym(tokStr);
        if argSym < 0 then
          Error(concat('unknown identifier: ', tokStr));
        NextToken;
        if (syms[argSym].offset < 0) and syms[argSym].isVarParam then
          EmitLocalGet(-(syms[argSym].offset + 1))
        else if syms[argSym].offset < 0 then
          Error('cannot pass value parameter as const parameter')
        else begin
          EmitFramePtr(syms[argSym].level);
          EmitI32Const(syms[argSym].offset);
          EmitOp(OpI32Add);
        end;
        { Handle array subscript: array_var[idx] -- compute element address }
        if tokKind = tkLBracket then begin
          NextToken;
          ParseExpression(PrecNone);  { index }
          if syms[argSym].typ = tyArray then begin
            if types[syms[argSym].typeIdx].arrLo <> 0 then begin
              EmitI32Const(types[syms[argSym].typeIdx].arrLo);
              EmitOp(OpI32Sub);
            end;
            if types[syms[argSym].typeIdx].elemSize <> 1 then begin
              EmitI32Const(types[syms[argSym].typeIdx].elemSize);
              EmitOp(OpI32Mul);
            end;
          end;
          EmitOp(OpI32Add);
          Expect(tkRBracket);
        end;
      end;
    end else begin
      { Value param: evaluate expression normally }
      ParseExpression(PrecNone);
    end;
    argIdx := argIdx + 1;
    if tokKind = tkComma then
      NextToken;
  end;
end;

{ ---- Compile-time expression evaluator (Chapter 10) ---- }

function ConstBinPrec(op: longint): longint;
{ Returns precedence of a binary operator token for EvalConstExprP. }
begin
  case op of
    tkOr:                    ConstBinPrec := PrecOrElse;
    tkAnd:                   ConstBinPrec := PrecAndThen;
    tkEq, tkNe,
    tkLt, tkLe, tkGt, tkGe: ConstBinPrec := PrecCompare;
    tkPlus, tkMinus:         ConstBinPrec := PrecAdd;
    tkStar, tkDiv, tkMod,
    tkShr, tkShl:            ConstBinPrec := PrecMul;
  else
    ConstBinPrec := 0;
  end;
end;

procedure EvalConstExprP(minPrec: longint; var outVal: longint; var outTyp: longint);
{ Compile-time evaluator with precedence climbing (minPrec = minimum precedence). }
var
  op:     longint;
  lval:   longint;
  ltyp:   longint;
  rval:   longint;
  rtyp:   longint;
  prec:   longint;
  s:      longint;
  argVal: longint;
  argTyp: longint;
  typSym: longint;
begin
  { -- Atom -- }
  case tokKind of
    tkInteger: begin
      outVal := tokInt;
      outTyp := tyInteger;
      NextToken;
    end;
    tkTrue: begin
      outVal := 1;
      outTyp := tyBoolean;
      NextToken;
    end;
    tkFalse: begin
      outVal := 0;
      outTyp := tyBoolean;
      NextToken;
    end;
    tkString: begin
      if length(tokStr) = 1 then begin
        outVal := ord(tokStr[1]);
        outTyp := tyChar;
      end else begin
        outVal := EmitDataPascalString(tokStr);
        outTyp := tyString;
      end;
      NextToken;
    end;
    tkLParen: begin
      NextToken;
      EvalConstExprP(PrecNone, outVal, outTyp);
      Expect(tkRParen);
    end;
    tkMinus: begin
      NextToken;
      EvalConstExprP(PrecUnary, outVal, outTyp);
      outVal := -outVal;
    end;
    tkPlus: begin
      NextToken;
      EvalConstExprP(PrecUnary, outVal, outTyp);
    end;
    tkNot: begin
      NextToken;
      EvalConstExprP(PrecUnary, outVal, outTyp);
      if outTyp = tyBoolean then
        outVal := ord(outVal = 0)
      else
        outVal := not outVal;
    end;
    tkIdent: begin
      s := LookupSym(tokStr);
      if (s >= 0) and (syms[s].kind = skConst) then begin
        { Named constant: return its stored value }
        outVal := syms[s].offset;
        outTyp := syms[s].typ;
        NextToken;
      end else begin
        { Built-in functions }
        if tokStr = 'ORD' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, argVal, argTyp);
          outVal := argVal;
          outTyp := tyInteger;
          Expect(tkRParen);
        end else if tokStr = 'CHR' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, argVal, argTyp);
          outVal := argVal;
          outTyp := tyChar;
          Expect(tkRParen);
        end else if tokStr = 'ABS' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, outVal, outTyp);
          if outVal < 0 then outVal := -outVal;
          Expect(tkRParen);
        end else if tokStr = 'ODD' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, argVal, argTyp);
          outVal := ord((argVal and 1) <> 0);
          outTyp := tyBoolean;
          Expect(tkRParen);
        end else if tokStr = 'SUCC' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, outVal, outTyp);
          outVal := outVal + 1;
          Expect(tkRParen);
        end else if tokStr = 'PRED' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, outVal, outTyp);
          outVal := outVal - 1;
          Expect(tkRParen);
        end else if tokStr = 'SQR' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, outVal, outTyp);
          outVal := outVal * outVal;
          Expect(tkRParen);
        end else if tokStr = 'LO' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, outVal, outTyp);
          outVal := outVal and $FF;
          outTyp := tyInteger;
          Expect(tkRParen);
        end else if tokStr = 'HI' then begin
          NextToken; Expect(tkLParen);
          EvalConstExprP(PrecNone, outVal, outTyp);
          outVal := (outVal shr 8) and $FF;
          outTyp := tyInteger;
          Expect(tkRParen);
        end else if tokStr = 'SIZEOF' then begin
          NextToken; Expect(tkLParen);
          if tokKind <> tkIdent then
            Error('expected type name in sizeof');
          typSym := LookupSym(tokStr);
          if (typSym < 0) or (syms[typSym].kind <> skType) then
            Error(concat('sizeof: unknown type: ', tokStr));
          outVal := syms[typSym].size;
          outTyp := tyInteger;
          NextToken;
          Expect(tkRParen);
        end else begin
          Error(concat('not a constant: ', tokStr));
          outVal := 0; outTyp := tyInteger;
        end;
      end;
    end;
  else
    Error('expected constant expression');
    outVal := 0; outTyp := tyInteger;
  end;

  { -- Binary operator precedence climbing -- }
  prec := ConstBinPrec(tokKind);
  while prec > minPrec do begin
    op   := tokKind;
    NextToken;
    lval := outVal;
    ltyp := outTyp;
    EvalConstExprP(prec, rval, rtyp);  { left-associative: pass same prec }
    case op of
      tkPlus:  outVal := lval + rval;
      tkMinus: outVal := lval - rval;
      tkStar:  outVal := lval * rval;
      tkDiv:   outVal := lval div rval;
      tkMod:   outVal := lval mod rval;
      tkAnd:   begin
                 if ltyp = tyBoolean then
                   outVal := ord((lval <> 0) and (rval <> 0))
                 else
                   outVal := lval and rval;
               end;
      tkOr:    begin
                 if ltyp = tyBoolean then
                   outVal := ord((lval <> 0) or (rval <> 0))
                 else
                   outVal := lval or rval;
               end;
      tkShr:   outVal := lval shr rval;
      tkShl:   outVal := lval shl rval;
      tkEq:    begin outVal := ord(lval = rval);  outTyp := tyBoolean; end;
      tkNe:    begin outVal := ord(lval <> rval); outTyp := tyBoolean; end;
      tkLt:    begin outVal := ord(lval < rval);  outTyp := tyBoolean; end;
      tkLe:    begin outVal := ord(lval <= rval); outTyp := tyBoolean; end;
      tkGt:    begin outVal := ord(lval > rval);  outTyp := tyBoolean; end;
      tkGe:    begin outVal := ord(lval >= rval); outTyp := tyBoolean; end;
    end;
    prec := ConstBinPrec(tokKind);
  end;
end;

procedure EvalConstExpr(var outVal: longint; var outTyp: longint);
{ Public entry point: evaluate a constant expression at the lowest precedence. }
begin
  EvalConstExprP(PrecNone, outVal, outTyp);
end;

procedure ParseConstBlock;
{ Parse 'const Name = Expr; ...' declarations.
  Called after 'const' keyword has been consumed. }
var
  name:  string[63];
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

procedure ParseExpression(minPrec: longint);
{** Pratt-style precedence climbing. Parses an expression at the given
  minimum precedence level, emitting WASM instructions as it goes. }
var
  prec:       longint;
  op:         longint;
  s:          longint;
  curTyp:     longint;
  curTypeIdx: longint;
  curSize:    longint;
  fldIdx:     longint;
  fi:         longint;
begin
  { --- Prefix --- }
  case tokKind of
    tkInteger: begin
      EmitI32Const(tokInt);
      lastExprType := tyInteger;
      NextToken;
    end;
    tkTrue: begin
      EmitI32Const(1);
      lastExprType := tyInteger;
      NextToken;
    end;
    tkFalse: begin
      EmitI32Const(0);
      lastExprType := tyInteger;
      NextToken;
    end;
    tkString: begin
      if length(tokStr) = 1 then begin
        { Single-char literal: emit byte value as char, not string address }
        EmitI32Const(ord(tokStr[1]));
        lastExprType := tyChar;
        lastExprStrMax := 0;
      end else begin
        { Multi-char string literal: emit data segment address }
        EmitI32Const(EmitDataPascalString(tokStr));
        lastExprType := tyString;
        lastExprStrMax := length(tokStr);
      end;
      NextToken;
    end;
    tkIdent: begin
      if tokStr = 'ORD' then begin
        { ord(x): char/boolean->integer; no-op in our i32 world }
        NextToken; Expect(tkLParen);
        ParseExpression(PrecNone);
        Expect(tkRParen);
        lastExprType := tyInteger;
      end else if tokStr = 'CHR' then begin
        { chr(x): integer->char; no-op in our i32 world }
        NextToken; Expect(tkLParen);
        ParseExpression(PrecNone);
        Expect(tkRParen);
        lastExprType := tyChar;
      end else if tokStr = 'EOF' then begin
        { eof(f): returns atEof boolean variable }
        NextToken;
        if tokKind = tkLParen then begin
          { Skip file argument tokens until ')' }
          NextToken;
          while (tokKind <> tkRParen) and (tokKind <> tkEof) do NextToken;
          Expect(tkRParen);
        end;
        s := LookupSym('ATEOF');
        if s >= 0 then
          EmitVarLoad(s)
        else
          EmitI32Const(0);
        lastExprType := tyBoolean;
      end else begin
      s := LookupSym(tokStr);
      if s < 0 then
        Error(concat('unknown identifier: ', tokStr));
      if syms[s].kind = skConst then begin
        { Compile-time constant: inline as i32.const }
        EmitI32Const(syms[s].offset);
        lastExprType    := syms[s].typ;
        lastExprTypeIdx := -1;
        NextToken;
      end else if syms[s].kind = skFunc then begin
        { Function call as expression }
        NextToken;
        if funcs[syms[s].size].nparams = 0 then begin
          if tokKind = tkLParen then begin
            NextToken;
            Expect(tkRParen);
          end;
        end else begin
          Expect(tkLParen);
          ParseCallArgs(s);
          Expect(tkRParen);
        end;
        EmitCall(syms[s].offset);
        { return value is on the WASM stack }
        lastExprType := funcs[syms[s].size].retType;
      end else if syms[s].kind = skType then begin
        { Type cast e.g. longint(expr), byte(expr): no-op for scalar types }
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        Expect(tkRParen);
        lastExprType := syms[s].typ;
      end else begin
        if syms[s].kind <> skVar then
          Error(concat(tokStr, ' is not a variable'));
        NextToken;
        if syms[s].typ = tyString then begin
          { String variable: push address, or s[i] for char subscript }
          EmitStrAddr(s);
          if tokKind = tkLBracket then begin
            { s[i]: load byte at addr+i (1-indexed character) }
            NextToken;
            ParseExpression(PrecNone);  { index i }
            EmitOp(OpI32Add);           { addr + i }
            EmitI32Load8u(0, 0);        { load byte }
            Expect(tkRBracket);
            lastExprType    := tyChar;
            lastExprTypeIdx := -1;
          end else begin
            lastExprType    := tyString;
            lastExprStrMax  := syms[s].strMaxLen;
            lastExprTypeIdx := -1;
          end;
        end else if (syms[s].typ = tyRecord) or (syms[s].typ = tyArray) then begin
          { Composite variable: push base address then apply selector chain }
          EmitStrAddr(s);
          curTyp     := syms[s].typ;
          curTypeIdx := syms[s].typeIdx;
          curSize    := syms[s].size;
          while (tokKind = tkDot) or (tokKind = tkLBracket) do begin
            if tokKind = tkDot then begin
              NextToken;
              if curTyp <> tyRecord then
                Error('dot selector on non-record type');
              if tokKind <> tkIdent then
                Error('expected field name');
              fldIdx := -1;
              for fi := types[curTypeIdx].fieldStart to
                        types[curTypeIdx].fieldStart + types[curTypeIdx].fieldCount - 1 do begin
                if fields[fi].name = tokStr then begin
                  fldIdx := fi;
                  break;
                end;
              end;
              if fldIdx < 0 then
                Error(concat('unknown field: ', tokStr));
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
              if curTyp <> tyArray then
                Error('bracket selector on non-array type');
              ParseExpression(PrecNone);
              if types[curTypeIdx].arrLo <> 0 then begin
                EmitI32Const(types[curTypeIdx].arrLo);
                EmitOp(OpI32Sub);
              end;
              if types[curTypeIdx].elemSize <> 1 then begin
                EmitI32Const(types[curTypeIdx].elemSize);
                EmitOp(OpI32Mul);
              end;
              EmitOp(OpI32Add);
              { Multi-dim comma trick: treat a[i,j] as a[i][j] }
              if tokKind = tkComma then
                tokKind := tkLBracket
              else
                Expect(tkRBracket);
              fi         := types[curTypeIdx].elemSize;
              curTyp     := types[curTypeIdx].elemType;
              curTypeIdx := types[curTypeIdx].elemTypeIdx;
              if (curTyp = tyRecord) or (curTyp = tyArray) then
                curSize := types[curTypeIdx].size
              else if (curTyp = tyChar) or (curTyp = tyBoolean) then
                curSize := 1
              else if curTyp = tyString then
                curSize := fi
              else
                curSize := 4;
            end;
          end;
          { After selector chain: load scalar or leave composite address }
          if (curTyp = tyRecord) or (curTyp = tyArray) then begin
            { Composite: leave address on stack }
            lastExprType    := curTyp;
            lastExprTypeIdx := curTypeIdx;
          end else if curTyp = tyString then begin
            { String field/element: leave address on stack }
            lastExprType    := tyString;
            lastExprStrMax  := curSize - 1;
            lastExprTypeIdx := -1;
          end else begin
            { Scalar field/element: load the value }
            if curSize = 1 then
              EmitI32Load8u(0, 0)
            else
              EmitI32Load(2, 0);
            lastExprType    := curTyp;
            lastExprTypeIdx := -1;
          end;
        end else begin
          EmitVarLoad(s);
          lastExprType    := syms[s].typ;
          lastExprTypeIdx := -1;
        end;
      end;
      end; { end else (not ORD/CHR) }
    end;
    tkLength: begin
      { LENGTH(s) - returns length byte of string }
      NextToken;
      Expect(tkLParen);
      ParseExpression(PrecNone);
      { Address on stack; load length byte }
      CodeBufEmit(startCode, OpI32Load8u);
      EmitULEB128(startCode, 0);
      EmitULEB128(startCode, 0);
      Expect(tkRParen);
      lastExprType := tyInteger;
    end;
    tkCopy: begin
      { COPY(s, i, n) - extract substring }
      NextToken;
      Expect(tkLParen);
      ParseExpression(PrecNone);  { s }
      Expect(tkComma);
      ParseExpression(PrecNone);  { i }
      Expect(tkComma);
      ParseExpression(PrecNone);  { n }
      Expect(tkRParen);
      EnsureStrCopy;
      EmitCall(idxStrCopy);
      lastExprType := tyString;
      lastExprStrMax := 255;  { COPY returns string with max 255 bytes }
    end;
    tkPos: begin
      { POS(sub, s) - find substring (1-based) }
      NextToken;
      Expect(tkLParen);
      ParseExpression(PrecNone);  { sub }
      Expect(tkComma);
      ParseExpression(PrecNone);  { s }
      Expect(tkRParen);
      EnsureStrPos;
      EmitCall(idxStrPos);
      lastExprType := tyInteger;
    end;
    tkConcat: begin
      { CONCAT(a, b) - copy a to scratch, append b, return scratch address }
      NextToken;
      Expect(tkLParen);
      if addrStrScratch < 0 then begin
        EnsureStringHelpers;
        addrStrScratch := AllocData(256);
      end;
      EnsureStrAssign;
      EnsureStrAppend;
      { copy a to scratch }
      EmitI32Const(addrStrScratch);
      EmitI32Const(255);
      ParseExpression(PrecNone);  { a }
      EmitCall(idxStrAssign);
      Expect(tkComma);
      { append b to scratch }
      EmitI32Const(addrStrScratch);
      EmitI32Const(255);
      ParseExpression(PrecNone);  { b }
      Expect(tkRParen);
      if lastExprType = tyChar then begin
        EnsureStrAppendChar;
        EmitCall(idxStrAppendChar);  { __str_append_char(dst, max_len, char_byte) }
      end else
        EmitCall(idxStrAppend);      { __str_append(dst, max_len, src) }
      { result is scratch address }
      EmitI32Const(addrStrScratch);
      lastExprType := tyString;
      lastExprStrMax := 255;
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
      lastExprType := tyInteger;
    end;
    tkPlus: begin
      NextToken;
      ParseExpression(PrecUnary);
      { unary plus is a no-op }
      lastExprType := tyInteger;
    end;
    tkNot: begin
      NextToken;
      ParseExpression(PrecUnary);
      EmitOp(OpI32Eqz);   { ;; WAT: i32.eqz  (logical NOT: 0->1, non-zero->0) }
      lastExprType := tyInteger;
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
      tkShr:     prec := PrecMul;
      tkShl:     prec := PrecMul;
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
      tkAndThen: EmitOp(OpI32And);   { ;; WAT: i32.and }
      tkOrElse:  EmitOp(OpI32Or);    { ;; WAT: i32.or }
      tkShr:     EmitOp(OpI32ShrU);  { ;; WAT: i32.shr_u }
      tkShl:     EmitOp(OpI32Shl);   { ;; WAT: i32.shl }
      tkEq: begin
        if lastExprType = tyString then begin
          EnsureStrCompare;
          EmitCall(idxStrCompare);
          EmitI32Const(0);
          EmitOp(OpI32Eq);  { result == 0 means equal }
        end else
          EmitOp(OpI32Eq);    { ;; WAT: i32.eq }
      end;
      tkNe: begin
        if lastExprType = tyString then begin
          EnsureStrCompare;
          EmitCall(idxStrCompare);
          EmitI32Const(0);
          EmitOp(OpI32Ne);  { result != 0 means not equal }
        end else
          EmitOp(OpI32Ne);    { ;; WAT: i32.ne }
      end;
      tkLt: begin
        if lastExprType = tyString then begin
          EnsureStrCompare;
          EmitCall(idxStrCompare);
          EmitI32Const(0);
          EmitOp(OpI32LtS);  { result < 0 means less than }
        end else
          EmitOp(OpI32LtS);   { ;; WAT: i32.lt_s }
      end;
      tkGt: begin
        if lastExprType = tyString then begin
          EnsureStrCompare;
          EmitCall(idxStrCompare);
          EmitI32Const(0);
          EmitOp(OpI32GtS);  { result > 0 means greater than }
        end else
          EmitOp(OpI32GtS);   { ;; WAT: i32.gt_s }
      end;
      tkLe: begin
        if lastExprType = tyString then begin
          EnsureStrCompare;
          EmitCall(idxStrCompare);
          EmitI32Const(0);
          EmitOp(OpI32LeS);  { result <= 0 means less than or equal }
        end else
          EmitOp(OpI32LeS);   { ;; WAT: i32.le_s }
      end;
      tkGe: begin
        if lastExprType = tyString then begin
          EnsureStrCompare;
          EmitCall(idxStrCompare);
          EmitI32Const(0);
          EmitOp(OpI32GeS);  { result >= 0 means greater than or equal }
        end else
          EmitOp(OpI32GeS);   { ;; WAT: i32.ge_s }
      end;
    end;
  end;
end;

procedure ParseWriteArgs(withNewline: boolean);
{ Parses the argument list for write/writeln (already consumed the keyword).
  Strings are stored in the data segment and written with fd_write.
  Expressions are evaluated onto the WASM stack and passed to __write_int.
  String variables are passed to __write_str. }
var
  addr: longint;
  len:  longint;
  s:    longint;
begin
  if tokKind = tkLParen then begin
    NextToken;
    { Optional leading file argument (e.g. StdErr): skip it }
    if (tokKind = tkIdent) and (tokStr = 'STDERR') then begin
      NextToken;
      if tokKind = tkComma then NextToken;
    end;
    repeat
      if tokKind = tkString then begin
        addr := EmitDataString(tokStr);
        len  := length(tokStr);
        EmitWriteString(addr, len);
        NextToken;
      end else if (tokKind = tkIdent) and (LookupSym(tokStr) >= 0) and
                  (syms[LookupSym(tokStr)].kind = skVar) and
                  (syms[LookupSym(tokStr)].typ = tyString) then begin
        { String variable: call __write_str }
        s := LookupSym(tokStr);
        NextToken;
        EmitStrAddr(s);
        EnsureWriteStr;
        EmitCall(idxWriteStr);
      end else begin
        ParseExpression(PrecNone);
        { Check if this expression is a string (from COPY, CONCAT, etc) }
        if lastExprType = tyString then begin
          EnsureWriteStr;
          EmitCall(idxWriteStr);
        end else
          EmitWriteInt;
      end;
      if tokKind = tkComma then
        NextToken
      else
        break;
    until false;
    Expect(tkRParen);
  end;
  if withNewline then
    EmitWriteNewline;
end;

procedure ParseTypeSpec(var outTyp, outTypeIdx, outSize, outStrMax: longint);
{ Parse a type expression: a type name, 'record...end', or 'array[lo..hi,...] of T'.
  Returns outTyp (type tag), outTypeIdx (types[] index; -1 for scalars),
  outSize (byte size), outStrMax (max length for string; 0 otherwise). }
var
  tIdx:      longint;
  typSym:    longint;
  fieldOfs:  longint;
  ftyp:      longint;
  ftypeIdx:  longint;
  fsize:     longint;
  fstrMax:   longint;
  pad:       longint;
  fnameArr:  array[0..31] of string[63];
  fnameCount: longint;
  fi:        longint;
  dimLo:     array[0..MaxDims-1] of longint;
  dimHi:     array[0..MaxDims-1] of longint;
  nDims:     longint;
  elemTyp:   longint;
  elemTypeIdx: longint;
  elemSize:  longint;
  elemStrMax: longint;
  ordinal:   longint;  { Chapter 10: enum ordinal counter }
  enumSym:   longint;  { Chapter 10: enum constant symbol }
begin
  outStrMax := 0;
  if tokKind = tkLParen then begin
    { Enumerated type: (Ident, Ident, ...) }
    NextToken;
    tIdx := AddTypeDesc;
    types[tIdx].kind  := tyEnum;
    types[tIdx].size  := 4;
    types[tIdx].arrLo := 0;
    ordinal := 0;
    repeat
      if tokKind <> tkIdent then
        Error('expected identifier in enumerated type');
      enumSym := AddSym(tokStr, skConst, tyEnum);
      syms[enumSym].offset  := ordinal;
      syms[enumSym].typeIdx := tIdx;
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
  end else if tokKind = tkRecord then begin
    NextToken;
    tIdx := AddTypeDesc;
    types[tIdx].kind       := tyRecord;
    types[tIdx].fieldStart := numFields;
    fieldOfs := 0;
    while tokKind <> tkEnd do begin
      { Parse field name list }
      fnameCount := 0;
      repeat
        if tokKind <> tkIdent then
          Error('expected field name in record');
        fnameArr[fnameCount] := tokStr;
        fnameCount := fnameCount + 1;
        NextToken;
        if tokKind = tkComma then
          NextToken
        else
          break;
      until false;
      Expect(tkColon);
      ParseTypeSpec(ftyp, ftypeIdx, fsize, fstrMax);
      for fi := 0 to fnameCount - 1 do begin
        { 4-byte align field offset }
        pad := (4 - (fieldOfs mod 4)) mod 4;
        fieldOfs := fieldOfs + pad;
        AddField(fnameArr[fi], ftyp, ftypeIdx, fieldOfs, fsize);
        fieldOfs := fieldOfs + fsize;
      end;
      if tokKind = tkSemicolon then
        NextToken;
    end;
    Expect(tkEnd);
    types[tIdx].fieldCount := numFields - types[tIdx].fieldStart;
    { Pad total size to multiple of 4 }
    pad := (4 - (fieldOfs mod 4)) mod 4;
    fieldOfs := fieldOfs + pad;
    types[tIdx].size := fieldOfs;
    outTyp     := tyRecord;
    outTypeIdx := tIdx;
    outSize    := types[tIdx].size;
  end else if tokKind = tkArray then begin
    NextToken;
    Expect(tkLBracket);
    { Collect dimension bounds }
    nDims := 0;
    repeat
      EvalConstExpr(dimLo[nDims], ftyp);
      Expect(tkDotDot);
      EvalConstExpr(dimHi[nDims], ftyp);
      nDims := nDims + 1;
      if tokKind = tkComma then
        NextToken
      else
        break;
    until false;
    Expect(tkRBracket);
    Expect(tkOf);
    ParseTypeSpec(elemTyp, elemTypeIdx, elemSize, elemStrMax);
    { Build nested descriptors from innermost to outermost }
    fi := nDims - 1;
    while fi >= 0 do begin
      tIdx := AddTypeDesc;
      types[tIdx].kind        := tyArray;
      types[tIdx].arrLo       := dimLo[fi];
      types[tIdx].arrHi       := dimHi[fi];
      types[tIdx].elemType    := elemTyp;
      types[tIdx].elemTypeIdx := elemTypeIdx;
      types[tIdx].elemSize    := elemSize;
      types[tIdx].size        := (dimHi[fi] - dimLo[fi] + 1) * elemSize;
      elemTyp     := tyArray;
      elemTypeIdx := tIdx;
      elemSize    := types[tIdx].size;
      fi := fi - 1;
    end;
    outTyp     := tyArray;
    outTypeIdx := tIdx;
    outSize    := types[tIdx].size;
  end else if tokKind = tkStringType then begin
    outTyp     := tyString;
    outTypeIdx := -1;
    outStrMax  := 255;
    NextToken;
    if tokKind = tkLBracket then begin
      NextToken;
      if tokKind <> tkInteger then
        Error('expected number in string[N]');
      outStrMax := tokInt;
      if (outStrMax < 1) or (outStrMax > 255) then
        Error('string[N] must have 1 <= N <= 255');
      NextToken;
      Expect(tkRBracket);
    end;
    outSize := 1 + outStrMax;
  end else if tokKind = tkFile then begin
    { TP file type: dummy 4-byte handle }
    outTyp     := tyInteger;
    outTypeIdx := -1;
    outSize    := 4;
    outStrMax  := 0;
    NextToken;
  end else begin
    { Named type }
    if tokKind <> tkIdent then
      Error('expected type name');
    typSym := LookupSym(tokStr);
    if (typSym < 0) or (syms[typSym].kind <> skType) then
      Error(concat('unknown type: ', tokStr));
    outTyp     := syms[typSym].typ;
    outTypeIdx := syms[typSym].typeIdx;
    outSize    := syms[typSym].size;
    outStrMax  := syms[typSym].strMaxLen;
    NextToken;
  end;
end;

procedure ParseTypeBlock;
{ Parse 'type TName = TypeSpec; ...' declarations.
  Called after 'type' has been consumed. }
var
  tname:      string;
  outTyp:     longint;
  outTypeIdx: longint;
  outSize:    longint;
  outStrMax:  longint;
  s:          longint;
begin
  while tokKind = tkIdent do begin
    tname := tokStr;
    NextToken;
    Expect(tkEq);
    ParseTypeSpec(outTyp, outTypeIdx, outSize, outStrMax);
    Expect(tkSemicolon);
    s := AddSym(tname, skType, outTyp);
    syms[s].size      := outSize;
    syms[s].typeIdx   := outTypeIdx;
    syms[s].strMaxLen := outStrMax;
  end;
end;

procedure ParseVarBlock;
{ Parses one or more variable declaration lines.
  Called after 'var' has been consumed; stops when no identifier follows. }
var
  s:          longint;
  names:      array[0..31] of string[63];
  nnames:     longint;
  i:          longint;
  outTyp:     longint;
  outTypeIdx: longint;
  outSize:    longint;
  outStrMax:  longint;
  pad:        longint;
begin
  while tokKind = tkIdent do begin
    nnames := 0;
    repeat
      if tokKind <> tkIdent then
        Error('expected variable name');
      names[nnames] := tokStr;
      nnames := nnames + 1;
      NextToken;
      if tokKind = tkComma then
        NextToken
      else
        break;
    until false;
    Expect(tkColon);
    ParseTypeSpec(outTyp, outTypeIdx, outSize, outStrMax);
    Expect(tkSemicolon);
    for i := 0 to nnames - 1 do begin
      s := AddSym(names[i], skVar, outTyp);
      syms[s].size      := outSize;
      syms[s].typeIdx   := outTypeIdx;
      syms[s].strMaxLen := outStrMax;
      syms[s].level     := curNestLevel;
      if outTyp = tyString then begin
        { Strings: byte-packed, no alignment needed }
        syms[s].offset := curFrameSize;
        curFrameSize   := curFrameSize + outSize;
      end else if (outTyp = tyRecord) or (outTyp = tyArray) then begin
        { Structured: 4-byte align then advance by full size }
        pad := (4 - (curFrameSize mod 4)) mod 4;
        curFrameSize := curFrameSize + pad;
        syms[s].offset := curFrameSize;
        curFrameSize   := curFrameSize + outSize;
      end else begin
        { Scalar: 4-byte aligned slot }
        syms[s].offset := curFrameSize;
        curFrameSize   := curFrameSize + 4;
      end;
    end;
  end;
end;

procedure ParseStatement;
var
  s:            longint;
  sym:          longint;
  oldBreak:     longint;
  oldContinue:  longint;
  oldExit:      longint;
  limitAddr:    longint;
  isDownto:     boolean;
  curTyp:       longint;
  curTypeIdx:   longint;
  curSize:      longint;
  fldIdx:       longint;
  fi:           longint;
  { Chapter 10: case statement locals }
  armCount:     longint;
  labelCount:   longint;
  labelVal:     longint;
  labelTyp:     longint;
  hiVal:        longint;
  hiTyp:        longint;
  caseI:        longint;
begin
  case tokKind of
    tkIdent: begin
      if tokStr = 'ASSIGN' then begin
        { Assign(f, path): no-op in WASM }
        NextToken; Expect(tkLParen);
        ParseExpression(PrecNone); EmitOp(OpDrop);
        Expect(tkComma);
        ParseExpression(PrecNone); EmitOp(OpDrop);
        Expect(tkRParen);
      end else if tokStr = 'REWRITE' then begin
        { Rewrite(f, recsize): no-op in WASM }
        NextToken; Expect(tkLParen);
        ParseExpression(PrecNone); EmitOp(OpDrop);
        Expect(tkComma);
        ParseExpression(PrecNone); EmitOp(OpDrop);
        Expect(tkRParen);
      end else if tokStr = 'CLOSE' then begin
        { Close(f): no-op in WASM }
        NextToken; Expect(tkLParen);
        ParseExpression(PrecNone); EmitOp(OpDrop);
        Expect(tkRParen);
      end else if tokStr = 'BLOCKWRITE' then begin
        { BlockWrite(f, buf, count): write buf[0..count-1] to stdout via fd_write }
        NextToken; Expect(tkLParen);
        ParseExpression(PrecNone); EmitOp(OpDrop);  { file handle - ignored }
        Expect(tkComma);
        EnsureIOBuffers;
        EmitI32Const(addrIovec);
        ParseExpression(PrecNone);  { buffer: composite type leaves address on stack }
        EmitI32Store(2, 0);         { iovec.buf = buf_addr }
        Expect(tkComma);
        EmitI32Const(addrIovec + 4);
        ParseExpression(PrecNone);  { count }
        EmitI32Store(2, 0);         { iovec.len = count }
        Expect(tkRParen);
        EmitI32Const(1);            { fd = stdout }
        EmitI32Const(addrIovec);
        EmitI32Const(1);            { 1 iovec }
        EmitI32Const(addrNwritten);
        EmitCall(EnsureFdWrite);
        EmitOp(OpDrop);             { ignore result }
      end else begin
      s := LookupSym(tokStr);
      if s < 0 then
        Error(concat('unknown identifier: ', tokStr));
      NextToken;
      if syms[s].kind = skProc then begin
        { Procedure call as statement }
        if funcs[syms[s].size].nparams = 0 then begin
          if tokKind = tkLParen then begin
            NextToken;
            Expect(tkRParen);
          end;
        end else begin
          Expect(tkLParen);
          ParseCallArgs(s);
          Expect(tkRParen);
        end;
        EmitCall(syms[s].offset);
      end else if syms[s].kind = skFunc then begin
        if (tokKind = tkAssign) and (currentFuncSlot >= 0) and
           (syms[s].size = currentFuncSlot) then begin
          { Return-value assignment: funcname := expr inside function body }
          NextToken;
          ParseExpression(PrecNone);
          EmitLocalSet(funcs[currentFuncSlot].nparams);
        end else begin
          { Function call as statement: discard return value }
          if funcs[syms[s].size].nparams = 0 then begin
            if tokKind = tkLParen then begin
              NextToken;
              Expect(tkRParen);
            end;
          end else begin
            Expect(tkLParen);
            ParseCallArgs(s);
            Expect(tkRParen);
          end;
          EmitCall(syms[s].offset);
          EmitOp(OpDrop);
        end;
      end else if syms[s].kind = skVar then begin
        { Assignment to variable or parameter }
        if syms[s].typ = tyString then begin
          { String assignment: use __str_assign helper }
          Expect(tkAssign);
          EmitStrAddr(s);    { dst address }
          EmitI32Const(syms[s].strMaxLen);  { max_len }
          ParseExpression(PrecNone);  { src address }
          EnsureStrAssign;
          EmitCall(idxStrAssign);
        end else if (syms[s].typ = tyRecord) or (syms[s].typ = tyArray) then begin
          { Composite assignment: push base address, apply selector chain }
          if syms[s].isConstParam then
            Error(concat(syms[s].name, ' is a const parameter'));
          EmitStrAddr(s);
          curTyp     := syms[s].typ;
          curTypeIdx := syms[s].typeIdx;
          curSize    := types[curTypeIdx].size;
          { Selector chain on LHS }
          while (tokKind = tkDot) or (tokKind = tkLBracket) do begin
            if tokKind = tkDot then begin
              NextToken;
              if curTyp <> tyRecord then Error('dot selector on non-record');
              if tokKind <> tkIdent then Error('expected field name');
              fldIdx := -1;
              for fi := types[curTypeIdx].fieldStart to
                        types[curTypeIdx].fieldStart + types[curTypeIdx].fieldCount - 1 do begin
                if fields[fi].name = tokStr then begin fldIdx := fi; break; end;
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
              if curTyp <> tyArray then Error('bracket selector on non-array');
              ParseExpression(PrecNone);
              if types[curTypeIdx].arrLo <> 0 then begin
                EmitI32Const(types[curTypeIdx].arrLo);
                EmitOp(OpI32Sub);
              end;
              if types[curTypeIdx].elemSize <> 1 then begin
                EmitI32Const(types[curTypeIdx].elemSize);
                EmitOp(OpI32Mul);
              end;
              EmitOp(OpI32Add);
              if tokKind = tkComma then tokKind := tkLBracket
              else Expect(tkRBracket);
              fi         := types[curTypeIdx].elemSize;
              curTyp     := types[curTypeIdx].elemType;
              curTypeIdx := types[curTypeIdx].elemTypeIdx;
              if (curTyp = tyRecord) or (curTyp = tyArray) then
                curSize := types[curTypeIdx].size
              else if (curTyp = tyChar) or (curTyp = tyBoolean) then
                curSize := 1
              else if curTyp = tyString then
                curSize := fi
              else
                curSize := 4;
            end;
          end;
          Expect(tkAssign);
          if (curTyp = tyRecord) or (curTyp = tyArray) then begin
            { Composite-to-composite: memory.copy }
            ParseExpression(PrecNone);  { leaves src address on stack }
            EmitI32Const(curSize);
            EmitMemCopy;
          end else if curTyp = tyString then begin
            { String field/element assignment: use __str_assign }
            EmitI32Const(curSize - 1);  { max_len = size - 1 }
            ParseExpression(PrecNone);  { src address }
            EmitCall(EnsureStrAssign);
          end else begin
            { Selector chain ended at scalar field }
            ParseExpression(PrecNone);
            if curSize = 1 then EmitI32Store8(0, 0)
            else EmitI32Store(2, 0);
          end;
        end else if (syms[s].offset < 0) and syms[s].isVarParam then begin
          { Var param: local holds address, store through it }
          if syms[s].isConstParam then
            Error(concat(syms[s].name, ' is a const parameter'));
          EmitLocalGet(-(syms[s].offset + 1));
          Expect(tkAssign);
          ParseExpression(PrecNone);
          if syms[s].size = 1 then
            EmitI32Store8(0, 0)
          else
            EmitI32Store(2, 0);
        end else if syms[s].offset < 0 then begin
          { Value parameter: store into WASM local }
          if syms[s].isConstParam then
            Error(concat(syms[s].name, ' is a const parameter'));
          Expect(tkAssign);
          ParseExpression(PrecNone);
          EmitLocalSet(-(syms[s].offset + 1));
        end else begin
          { Frame variable: addr = $sp + offset }
          EmitFramePtr(syms[s].level);
          EmitI32Const(syms[s].offset);
          EmitOp(OpI32Add);
          Expect(tkAssign);
          ParseExpression(PrecNone);
          if syms[s].size = 1 then
            EmitI32Store8(0, 0)
          else
            EmitI32Store(2, 0);
        end;
      end else
        Error(concat(syms[s].name, ' is not callable or assignable'));
      end; { end else (not a file I/O builtin) }
    end;
    tkWrite: begin
      NextToken;
      ParseWriteArgs(false);
    end;
    tkWriteln: begin
      NextToken;
      ParseWriteArgs(true);
    end;
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
      ParseStatement;
      while tokKind = tkSemicolon do begin
        NextToken;
        if tokKind <> tkEnd then
          ParseStatement;
      end;
      Expect(tkEnd);
    end;
    tkIf: begin
      NextToken;
      ParseExpression(PrecNone);     { condition }
      Expect(tkThen);
      EmitOp(OpIf); EmitOp(WasmVoid);
      if breakDepth >= 0 then
        breakDepth := breakDepth + 1;
      if continueDepth >= 0 then
        continueDepth := continueDepth + 1;
      exitDepth := exitDepth + 1;
      ParseStatement;                { then branch }
      if tokKind = tkElse then begin
        NextToken;
        EmitOp(OpElse);
        ParseStatement;              { else branch }
      end;
      if breakDepth > 0 then
        breakDepth := breakDepth - 1;
      if continueDepth > 0 then
        continueDepth := continueDepth - 1;
      exitDepth := exitDepth - 1;
      EmitOp(OpEnd);
    end;
    tkWhile: begin
      NextToken;
      EmitOp(OpBlock); EmitOp(WasmVoid);   { outer block = break target }
      EmitOp(OpLoop);  EmitOp(WasmVoid);   { inner loop  = continue target }
      oldBreak      := breakDepth;
      oldContinue   := continueDepth;
      oldExit       := exitDepth;
      breakDepth    := 1;            { br 1 exits outer block }
      continueDepth := 0;            { br 0 re-enters loop }
      exitDepth     := exitDepth + 2;  { block + loop }
      ParseExpression(PrecNone);     { condition }
      Expect(tkDo);
      EmitOp(OpI32Eqz);
      EmitOp(OpBrIf); EmitULEB128(startCode, 1);  { exit if NOT condition }
      ParseStatement;                { loop body }
      EmitOp(OpBr); EmitULEB128(startCode, 0);     { back to loop }
      EmitOp(OpEnd);                 { end loop }
      EmitOp(OpEnd);                 { end block }
      breakDepth    := oldBreak;
      continueDepth := oldContinue;
      exitDepth     := oldExit;
    end;
    tkFor: begin
      NextToken;
      if tokKind <> tkIdent then Error('expected variable in for');
      sym := LookupSym(tokStr);
      if sym < 0 then Error('undefined variable in for');
      if syms[sym].kind <> skVar then Error('for variable is not a variable');
      NextToken;
      Expect(tkAssign);
      { Store initial value in loop variable: push addr then value }
      EmitGlobalGet(0);
      EmitI32Const(syms[sym].offset);
      EmitOp(OpI32Add);
      ParseExpression(PrecNone);
      EmitI32Store(2, 0);
      { Determine direction }
      if tokKind = tkTo then
        isDownto := false
      else if tokKind = tkDownto then
        isDownto := true
      else
        Error('expected TO or DOWNTO in for');
      NextToken;
      { Evaluate limit once; store in freshly allocated data segment slot }
      limitAddr := AllocData(4);
      EmitI32Const(limitAddr);       { push address }
      ParseExpression(PrecNone);     { push limit value }
      EmitI32Store(2, 0);            { store limit }
      { Emit block/loop pair; body wrapped in block so continue hits increment }
      EmitOp(OpBlock); EmitOp(WasmVoid);  { @exit: break target }
      EmitOp(OpLoop);  EmitOp(WasmVoid);  { @top: loop-back target }
      oldBreak      := breakDepth;
      oldContinue   := continueDepth;
      oldExit       := exitDepth;
      { Test: exit if counter has passed the limit -- emitted before body block }
      EmitGlobalGet(0);
      EmitI32Const(syms[sym].offset);
      EmitOp(OpI32Add);
      EmitI32Load(2, 0);             { load counter }
      EmitI32Const(limitAddr);
      EmitI32Load(2, 0);             { load limit }
      if isDownto then
        EmitOp(OpI32LtS)             { exit if counter < limit }
      else
        EmitOp(OpI32GtS);            { exit if counter > limit }
      EmitOp(OpBrIf); EmitULEB128(startCode, 1);  { br_if @exit }
      { Body wrapper: continue (br 0) exits this block, falls to increment }
      EmitOp(OpBlock); EmitOp(WasmVoid);  { @continue: continue target }
      breakDepth    := 2;            { br 2 exits @exit }
      continueDepth := 0;            { br 0 exits @continue, increment runs }
      exitDepth     := exitDepth + 3;  { @exit + @top + @continue }
      Expect(tkDo);
      ParseStatement;                { loop body }
      EmitOp(OpEnd);                 { end @continue }
      { Increment or decrement counter: push addr then new value }
      EmitGlobalGet(0);
      EmitI32Const(syms[sym].offset);
      EmitOp(OpI32Add);              { addr for store }
      EmitGlobalGet(0);
      EmitI32Const(syms[sym].offset);
      EmitOp(OpI32Add);
      EmitI32Load(2, 0);             { current counter value }
      EmitI32Const(1);
      if isDownto then
        EmitOp(OpI32Sub)
      else
        EmitOp(OpI32Add);
      EmitI32Store(2, 0);
      EmitOp(OpBr); EmitULEB128(startCode, 0);  { br @top }
      EmitOp(OpEnd);                 { end @top (loop) }
      EmitOp(OpEnd);                 { end @exit (block) }
      breakDepth    := oldBreak;
      continueDepth := oldContinue;
      exitDepth     := oldExit;
    end;
    tkRepeat: begin
      NextToken;
      oldBreak      := breakDepth;
      oldContinue   := continueDepth;
      oldExit       := exitDepth;
      EmitOp(OpBlock); EmitOp(WasmVoid);  { outer block: break target (br 1) }
        EmitOp(OpLoop); EmitOp(WasmVoid); { inner loop: continue target (br 0) }
        breakDepth    := 1;               { br 1 exits outer block }
        continueDepth := 0;               { br 0 re-enters loop }
        exitDepth     := exitDepth + 2;   { outer block + inner loop }
        { Body: one or more statements separated by semicolons }
        ParseStatement;
        while tokKind = tkSemicolon do begin
          NextToken;
          if tokKind <> tkUntil then
            ParseStatement;
        end;
        Expect(tkUntil);
        ParseExpression(PrecNone);        { condition }
        EmitOp(OpI32Eqz);                { loop if NOT condition }
        EmitOp(OpBrIf); EmitULEB128(startCode, 0);
        EmitOp(OpEnd);                   { end loop }
      EmitOp(OpEnd);                     { end block }
      breakDepth    := oldBreak;
      continueDepth := oldContinue;
      exitDepth     := oldExit;
    end;
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
    tkExit: begin
      { exit: branch out of procedure body block to run epilogue }
      NextToken;
      EmitOp(OpBr);
      EmitULEB128(startCode, exitDepth);
    end;
    tkDelete: begin
      { DELETE(s, i, n) - delete substring from string }
      NextToken;
      Expect(tkLParen);
      s := -1;
      { Parse first argument as variable reference }
      if tokKind <> tkIdent then
        Error('expected variable name in DELETE');
      s := LookupSym(tokStr);
      if s < 0 then
        Error(concat('unknown identifier: ', tokStr));
      if syms[s].kind <> skVar then
        Error(concat(tokStr, ' is not a variable'));
      if syms[s].typ <> tyString then
        Error(concat(tokStr, ' is not a string'));
      NextToken;
      Expect(tkComma);
      EmitStrAddr(s);    { string address }
      ParseExpression(PrecNone);  { i }
      Expect(tkComma);
      ParseExpression(PrecNone);  { n }
      Expect(tkRParen);
      EnsureStrDelete;
      EmitCall(idxStrDelete);
    end;
    tkInsert: begin
      { INSERT(src, dst, i) - insert src into dst at position i }
      NextToken;
      Expect(tkLParen);
      s := -1;
      { Parse second argument as variable reference }
      sym := -1;
      ParseExpression(PrecNone);  { src address }
      Expect(tkComma);
      if tokKind <> tkIdent then
        Error('expected variable name in INSERT');
      sym := LookupSym(tokStr);
      if sym < 0 then
        Error(concat('unknown identifier: ', tokStr));
      if syms[sym].kind <> skVar then
        Error(concat(tokStr, ' is not a variable'));
      if syms[sym].typ <> tyString then
        Error(concat(tokStr, ' is not a string'));
      NextToken;
      Expect(tkComma);
      EmitStrAddr(sym);   { dst address }
      ParseExpression(PrecNone);  { i }
      Expect(tkRParen);
      EnsureStrInsert;
      EmitCall(idxStrInsert);
    end;
    tkRead: begin
      { read(f, ch_var): read one byte from stdin via fd_read }
      NextToken; Expect(tkLParen);
      { Skip file argument - it may be an unknown identifier like 'input' }
      while (tokKind <> tkComma) and (tokKind <> tkRParen) and
            (tokKind <> tkEOF) do NextToken;
      Expect(tkComma);
      if tokKind <> tkIdent then Error('expected variable in read()');
      s := LookupSym(tokStr);
      if (s < 0) or (syms[s].kind <> skVar) then Error('expected variable in read()');
      NextToken;
      Expect(tkRParen);
      { Ensure io buffers and fd_read import }
      EnsureIOBuffers;
      if idxFdRead < 0 then begin
        idxFdRead := AddImport('wasi_snapshot_preview1', 'fd_read', TypeFdWrite);
        if needWriteInt then
          idxWriteInt := numImports + 1;
      end;
      if addrReadBuf < 0 then addrReadBuf := AllocData(1);
      { iovec.buf = addrReadBuf }
      EmitI32Const(addrIovec);
      EmitI32Const(addrReadBuf);
      EmitI32Store(2, 0);
      { iovec.len = 1 }
      EmitI32Const(addrIovec + 4);
      EmitI32Const(1);
      EmitI32Store(2, 0);
      { fd_read(0, addrIovec, 1, addrNwritten); drop result }
      EmitI32Const(0);
      EmitI32Const(addrIovec);
      EmitI32Const(1);
      EmitI32Const(addrNwritten);
      EmitCall(idxFdRead);
      EmitOp(OpDrop);
      { if nwritten == 0: atEof := true; ch := #0; else: ch := readBuf[0] }
      EmitI32Const(addrNwritten);
      EmitI32Load(2, 0);
      EmitI32Const(0);
      EmitOp(OpI32Eq);
      CodeBufEmit(startCode, OpIf); CodeBufEmit(startCode, WasmVoid);
        { atEof := true }
        sym := LookupSym('ATEOF');
        if sym >= 0 then begin
          EmitStrAddr(sym);
          EmitI32Const(1);
          EmitI32Store8(0, 0);
        end;
        { ch := #0 }
        EmitStrAddr(s);
        EmitI32Const(0);
        EmitI32Store8(0, 0);
      CodeBufEmit(startCode, OpElse);
        { ch := readBuf[0] }
        EmitStrAddr(s);
        EmitI32Const(addrReadBuf);
        EmitI32Load8u(0, 0);
        EmitI32Store8(0, 0);
      CodeBufEmit(startCode, OpEnd);
    end;
    tkReadln: begin
      { readln(s) - read string into variable }
      NextToken;
      Expect(tkLParen);
      if tokKind <> tkIdent then
        Error('expected variable name in readln');
      s := LookupSym(tokStr);
      if s < 0 then
        Error(concat('unknown identifier: ', tokStr));
      if syms[s].kind <> skVar then
        Error(concat(tokStr, ' is not a variable'));
      if syms[s].typ = tyString then begin
        { String read: call __read_str }
        NextToken;
        Expect(tkRParen);
        EmitStrAddr(s);
        EmitI32Const(syms[s].strMaxLen);
        EnsureReadStr;
        EmitCall(idxReadStr);
      end else
        Error('readln only supports string variables');
    end;

    tkCase: begin
      { case Expr of Label: Stmt; ... [else Stmt] end }
      NextToken;
      curNeedsCaseTemp := true;
      ParseExpression(PrecNone);     { selector on stack }
      EmitOp(OpLocalSet);
      EmitULEB128(startCode, curCaseTempIdx);  { store in temp local }
      Expect(tkOf);
      armCount := 0;
      oldBreak    := breakDepth;
      oldContinue := continueDepth;
      oldExit     := exitDepth;
      while (tokKind <> tkEnd) and (tokKind <> tkElse) and (tokKind <> tkEOF) do begin
        { Parse comma-separated label list for this arm }
        labelCount := 0;
        repeat
          EvalConstExpr(labelVal, labelTyp);
          if tokKind = tkDotDot then begin
            { Range: lo..hi }
            NextToken;
            EvalConstExpr(hiVal, hiTyp);
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curCaseTempIdx);
            EmitI32Const(labelVal);
            EmitOp(OpI32GeS);
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curCaseTempIdx);
            EmitI32Const(hiVal);
            EmitOp(OpI32LeS);
            EmitOp(OpI32And);
          end else begin
            { Single value }
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curCaseTempIdx);
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
        caseI := labelCount;
        while caseI > 1 do begin
          EmitOp(OpI32Or);
          caseI := caseI - 1;
        end;
        { if block for this arm: entering a new WASM if block, so break/continue/exit
          depths increase by 1 to keep targeting the correct outer constructs }
        EmitOp(OpIf); EmitOp(WasmVoid);
        if breakDepth >= 0 then breakDepth := breakDepth + 1;
        if continueDepth >= 0 then continueDepth := continueDepth + 1;
        exitDepth := exitDepth + 1;
        ParseStatement;
        armCount := armCount + 1;
        if tokKind = tkSemicolon then
          NextToken;
        if (tokKind <> tkEnd) and (tokKind <> tkElse) then begin
          { Nest next arm inside else }
          EmitOp(OpElse);
        end;
      end;
      { Optional else clause: goes in the else branch of the last arm's if }
      if tokKind = tkElse then begin
        EmitOp(OpElse);
        NextToken;
        { TP case-else allows multiple statements until 'end' }
        while (tokKind <> tkEnd) and (tokKind <> tkEOF) do begin
          ParseStatement;
          if tokKind = tkSemicolon then NextToken;
        end;
      end;
      { Close all nested if blocks }
      caseI := armCount;
      while caseI > 0 do begin
        EmitOp(OpEnd);
        caseI := caseI - 1;
      end;
      { Restore break/continue/exit depths: the if blocks are now closed }
      breakDepth    := oldBreak;
      continueDepth := oldContinue;
      exitDepth     := oldExit;
      Expect(tkEnd);
    end;

  else
    { empty statement }
  end;
end;

procedure ParseProcDecl;
{ Parse one procedure or function declaration.
  On entry: tokKind = tkProcedure or tkFunction. }
var
  name:         string[63];
  isFunc:       boolean;
  retType:      longint;
  fslot:        longint;
  wasmIdx:      longint;
  nparams:      longint;
  paramNames:   array[0..15] of string[63];
  paramTypes:   array[0..15] of longint;
  paramSizes:   array[0..15] of longint;
  paramIsVar:   array[0..15] of boolean;
  paramIsConst: array[0..15] of boolean;
  paramStrMax:  array[0..15] of longint;
  grpNames:     array[0..15] of string[63];
  grpCount:     longint;
  grpIsVar:     boolean;
  grpIsConst:   boolean;
  grpTyp:       longint;
  grpSz:        longint;
  grpStrMax:    longint;
  grpTypeIdx:   longint;
  paramTypeIdxs: array[0..15] of longint;
  numCopies:    longint;
  copyLocalIdx: array[0..15] of longint;
  copyFrameOff: array[0..15] of longint;
  copySize:     array[0..15] of longint;
  ci:           longint;
  i, j:         longint;
  sym:          longint;
  typSym:       longint;
  savedCode:          TCodeBuf;
  savedFrame:         longint;
  savedBreak:         longint;
  savedCont:          longint;
  savedExit:          longint;
  savedNestLevel:     longint;
  savedNeedsCaseTemp: boolean;   { Chapter 10 }
  displayLocalIdx: longint;
  existSym:        longint;
begin
  isFunc := (tokKind = tkFunction);
  NextToken;
  if tokKind <> tkIdent then
    Error('expected procedure/function name');
  name := tokStr;
  NextToken;

  { Parse parameter list }
  nparams := 0;
  if tokKind = tkLParen then begin
    NextToken;
      while tokKind <> tkRParen do begin
        grpIsVar   := false;
        grpIsConst := false;
        if tokKind = tkVar then begin
          grpIsVar := true;
          NextToken;
        end else if tokKind = tkConst then begin
          grpIsConst := true;
          NextToken;
        end;
        { Parse one or more parameter names in this group }
        grpCount := 0;
        repeat
          if tokKind <> tkIdent then
            Error('expected parameter name');
          grpNames[grpCount] := tokStr;
          grpCount := grpCount + 1;
          NextToken;
          if tokKind = tkComma then
            NextToken
          else
            break;
        until false;
        Expect(tkColon);
        { Handle STRING type keyword and string[N] syntax }
        grpStrMax := 0;  { Default: not a string }
        if tokKind = tkStringType then begin
          typSym := LookupSym('STRING');
          if (typSym < 0) or (syms[typSym].kind <> skType) then
            Error('STRING type not registered');
          grpStrMax := 255;  { Default max length }
          NextToken;
          { Check for string[N] syntax }
          if tokKind = tkLBracket then begin
            NextToken;
            if tokKind <> tkInteger then
              Error('expected number in string[N]');
            grpStrMax := tokInt;
            if (grpStrMax < 1) or (grpStrMax > 255) then
              Error('string[N] must have 1 <= N <= 255');
            NextToken;
            Expect(tkRBracket);
          end;
          grpTyp     := syms[typSym].typ;
          grpSz      := 1 + grpStrMax;  { Length byte + grpStrMax data bytes }
          grpTypeIdx := -1;
        end else begin
          if tokKind <> tkIdent then
            Error('expected parameter type');
          typSym := LookupSym(tokStr);
          if (typSym < 0) or (syms[typSym].kind <> skType) then
            Error(concat('unknown type: ', tokStr));
          grpTyp     := syms[typSym].typ;
          grpSz      := syms[typSym].size;
          grpTypeIdx := syms[typSym].typeIdx;
          NextToken;
        end;
        for i := 0 to grpCount - 1 do begin
          paramNames[nparams]    := grpNames[i];
          paramTypes[nparams]    := grpTyp;
          paramSizes[nparams]    := grpSz;
          paramIsVar[nparams]    := grpIsVar;
          paramIsConst[nparams]  := grpIsConst;
          paramStrMax[nparams]   := grpStrMax;
          paramTypeIdxs[nparams] := grpTypeIdx;
          nparams := nparams + 1;
        end;
        if tokKind = tkSemicolon then
          NextToken;
      end;
      Expect(tkRParen);
  end;

  { Parse return type for functions }
  retType := 0;
  if isFunc then begin
    Expect(tkColon);
    if tokKind <> tkIdent then
      Error('expected return type');
    typSym := LookupSym(tokStr);
    if (typSym < 0) or (syms[typSym].kind <> skType) then
      Error(concat('unknown return type: ', tokStr));
    retType := syms[typSym].typ;
    NextToken;
  end;

  Expect(tkSemicolon);

  { Is this the body of a forward-declared proc/func? }
  existSym := LookupSym(name);
  if (existSym >= 0) and
     ((syms[existSym].kind = skProc) or (syms[existSym].kind = skFunc)) and
     funcs[syms[existSym].size].isForward then begin
    { Body of a forward declaration: reuse existing slot }
    fslot   := syms[existSym].size;
    wasmIdx := syms[existSym].offset;
    funcs[fslot].isForward := false;
  end else begin
    { New declaration: allocate WASM function slot }
    EnsureBuiltinImports;
    wasmIdx := numImports + numDefinedFuncs;
    numDefinedFuncs := numDefinedFuncs + 1;
    fslot := numFuncs;
    numFuncs := numFuncs + 1;
    funcs[fslot].nparams     := nparams;
    funcs[fslot].retType     := retType;
    funcs[fslot].wasmFuncIdx := wasmIdx;
    funcs[fslot].isForward   := false;
    for i := 0 to nparams - 1 do begin
      funcs[fslot].varParams[i]   := paramIsVar[i];
      funcs[fslot].constParams[i] := paramIsConst[i];
    end;
    { Build WASM type signature: (i32)^nparams -> (i32 if func, else void) }
    funcs[fslot].wasmTypeIdx := FindOrAddWasmType(nparams, isFunc);
    { Register symbol at global scope }
    if isFunc then
      sym := AddSym(name, skFunc, retType)
    else
      sym := AddSym(name, skProc, 0);
    syms[sym].offset := wasmIdx;
    syms[sym].size   := fslot;
  end;

  { Check for forward declaration }
  if tokKind = tkForward then begin
    NextToken;
    Expect(tkSemicolon);
    { Forward: symbol already registered above; body comes later }
    if existSym < 0 then
      funcs[fslot].isForward := true;
    exit;
  end;

  { Increment nesting level for this procedure's body }
  savedNestLevel := curNestLevel;
  curNestLevel   := curNestLevel + 1;
  if curNestLevel > 7 then
    Error('procedure nesting too deep (max 7 levels)');

  { Compile the body using swap-startCode approach }
  savedCode           := startCode;
  savedFrame          := curFrameSize;
  savedBreak          := breakDepth;
  savedCont           := continueDepth;
  savedExit           := exitDepth;
  savedNeedsCaseTemp  := curNeedsCaseTemp;
  currentFuncSlot     := fslot;
  CodeBufInit(startCode);
  curFrameSize     := 0;
  breakDepth       := -1;
  continueDepth    := -1;
  exitDepth        := -1;
  curNeedsCaseTemp := false;
  { Chapter 10: case temp comes after params + return-value local + display save }
  if isFunc then
    curCaseTempIdx := nparams + 2  { params | retval | display | case temp }
  else
    curCaseTempIdx := nparams + 1; { params | display | case temp }

  numCopies := 0;
  EnterScope;
  { Declare parameters as WASM locals (negative offset encoding) }
  for i := 0 to nparams - 1 do begin
    j := AddSym(paramNames[i], skVar, paramTypes[i]);
    syms[j].offset       := -(i + 1);   { WASM local index i }
    syms[j].size         := paramSizes[i];
    syms[j].isVarParam   := paramIsVar[i];
    syms[j].isConstParam := paramIsConst[i];
    syms[j].strMaxLen    := paramStrMax[i];
    syms[j].typeIdx      := paramTypeIdxs[i];
    syms[j].level        := curNestLevel;
    { Composite value params: allocate frame space for callee copy }
    if ((paramTypes[i] = tyRecord) or (paramTypes[i] = tyArray)) and
       not paramIsVar[i] and not paramIsConst[i] then begin
      while (curFrameSize mod 4) <> 0 do curFrameSize := curFrameSize + 1;
      copyLocalIdx[numCopies] := i;
      copyFrameOff[numCopies] := curFrameSize;
      copySize[numCopies]     := paramSizes[i];
      numCopies               := numCopies + 1;
      curFrameSize            := curFrameSize + paramSizes[i];
      { After prologue copy, local will hold frame address -- treat as var param }
      syms[j].isVarParam := true;
    end;
  end;

  { Parse optional local const, type, and variable blocks }
  if tokKind = tkConst then begin
    NextToken;
    ParseConstBlock;
  end;
  if tokKind = tkType then begin
    NextToken;
    ParseTypeBlock;
  end;
  if tokKind = tkVar then begin
    NextToken;
    ParseVarBlock;
  end;

  { Parse nested procedure/function declarations (after var, before begin) }
  while (tokKind = tkProcedure) or (tokKind = tkFunction) do
    ParseProcDecl;

  { displayLocalIdx: WASM local that saves the old display[curNestLevel] value.
    Comes after params (and after return-value local for functions). }
  if isFunc then
    displayLocalIdx := nparams + 1
  else
    displayLocalIdx := nparams;

  { Save display[curNestLevel] into display save local before the exit block }
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

  { Prologue copies for composite value params: copy caller's data to frame }
  for ci := 0 to numCopies - 1 do begin
    { dst = display[curNestLevel] + frame offset of copy }
    EmitGlobalGet(curNestLevel + 1);
    EmitI32Const(copyFrameOff[ci]);
    EmitOp(OpI32Add);
    { src = WASM local (points to caller's data) }
    EmitLocalGet(copyLocalIdx[ci]);
    { size }
    EmitI32Const(copySize[ci]);
    EmitMemCopy;
    { Update local to point to frame copy }
    EmitGlobalGet(curNestLevel + 1);
    EmitI32Const(copyFrameOff[ci]);
    EmitOp(OpI32Add);
    EmitLocalSet(copyLocalIdx[ci]);
  end;

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

  { Frame epilogue: $sp += curFrameSize (outside exit block so exit runs it too) }
  if curFrameSize > 0 then begin
    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Add);
    EmitGlobalSet(0);
  end;

  { For functions: push return value local (index nparams) onto stack }
  if isFunc then
    EmitLocalGet(nparams);

  LeaveScope;

  { Store instruction bytes in funcBodies; AssembleCodeSection adds locals header and end }
  funcs[fslot].bodyStart    := funcBodies.len;
  funcs[fslot].bodyLen      := startCode.len;
  funcs[fslot].needsCaseTemp := curNeedsCaseTemp;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(funcBodies, startCode.data[i]);

  { Restore compilation context }
  startCode        := savedCode;
  curFrameSize     := savedFrame;
  breakDepth       := savedBreak;
  continueDepth    := savedCont;
  exitDepth        := savedExit;
  curNeedsCaseTemp := savedNeedsCaseTemp;
  currentFuncSlot  := -1;
  curNestLevel     := savedNestLevel;

  Expect(tkSemicolon);
end;

procedure ParseProgram;
begin
  Expect(tkProgram);
  if tokKind <> tkIdent then
    Error('expected program name');
  NextToken;
  Expect(tkSemicolon);
  { Pascal allows const/type/var/proc blocks in any order, possibly repeated }
  while (tokKind = tkConst) or (tokKind = tkType) or (tokKind = tkVar) or
        (tokKind = tkProcedure) or (tokKind = tkFunction) do begin
    if tokKind = tkConst then begin
      NextToken;
      ParseConstBlock;
    end else if tokKind = tkType then begin
      NextToken;
      ParseTypeBlock;
    end else if tokKind = tkVar then begin
      NextToken;
      ParseVarBlock;
    end else
      ParseProcDecl;
  end;
  { Chapter 10: _start case temp is local 0 (no params, no other locals) }
  curNeedsCaseTemp := false;
  curCaseTempIdx   := 0;
  { frame prologue: $sp -= curFrameSize }
  if curFrameSize > 0 then begin
    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Sub);
    EmitGlobalSet(0);
  end;
  { Set display[0] := $sp so nested procedures can access main-level variables }
  EmitGlobalGet(0);
  EmitGlobalSet(1);
  Expect(tkBegin);
  ParseStatement;
  while tokKind = tkSemicolon do begin
    NextToken;
    if tokKind <> tkEnd then
      ParseStatement;
  end;
  Expect(tkEnd);
  { Save case temp flag for _start }
  startNeedsCaseTemp := curNeedsCaseTemp;
  { frame epilogue: $sp += curFrameSize }
  if curFrameSize > 0 then begin
    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Add);
    EmitGlobalSet(0);
  end;
  Expect(tkDot);
end;

{ ---- Main ---- }

procedure InitScanner;
begin
  srcLine    := 1;
  srcCol     := 0;
  atEof      := false;
  hasPushback := false;
  ch         := ' ';
  ReadCh;
  { Handle Unix shebang: if first char is '#', skip the line }
  if ch = '#' then begin
    while not atEof and (ch <> #10) do
      ReadCh;
  end;
end;

procedure InitModule;
begin
  numWasmTypes    := 0;
  numImports      := 0;
  numDefinedFuncs := 1;  { _start only }
  CodeBufInit(startCode);
  { Register type 0: () -> () for _start }
  wasmTypes[0].nparams  := 0;
  wasmTypes[0].nresults := 0;
  { Register type 1: (i32) -> () for proc_exit and __write_int }
  wasmTypes[1].nparams     := 1;
  wasmTypes[1].params[0]   := WasmI32;
  wasmTypes[1].nresults    := 0;
  { Register type 2: (i32,i32,i32,i32) -> i32 for fd_write }
  wasmTypes[2].nparams     := 4;
  wasmTypes[2].params[0]   := WasmI32;
  wasmTypes[2].params[1]   := WasmI32;
  wasmTypes[2].params[2]   := WasmI32;
  wasmTypes[2].params[3]   := WasmI32;
  wasmTypes[2].nresults    := 1;
  wasmTypes[2].results[0]  := WasmI32;
  { Register type 3: (i32,i32) -> i32 }
  wasmTypes[3].nparams    := 2;
  wasmTypes[3].params[0]  := WasmI32;
  wasmTypes[3].params[1]  := WasmI32;
  wasmTypes[3].nresults   := 1;
  wasmTypes[3].results[0] := WasmI32;
  { Register type 4: (i32,i32) -> () }
  wasmTypes[4].nparams   := 2;
  wasmTypes[4].params[0] := WasmI32;
  wasmTypes[4].params[1] := WasmI32;
  wasmTypes[4].nresults  := 0;
  { Register type 5: (i32,i32,i32) -> () }
  wasmTypes[5].nparams   := 3;
  wasmTypes[5].params[0] := WasmI32;
  wasmTypes[5].params[1] := WasmI32;
  wasmTypes[5].params[2] := WasmI32;
  wasmTypes[5].nresults  := 0;
  { Register type 6: (i32,i32,i32) -> i32 }
  wasmTypes[6].nparams    := 3;
  wasmTypes[6].params[0]  := WasmI32;
  wasmTypes[6].params[1]  := WasmI32;
  wasmTypes[6].params[2]  := WasmI32;
  wasmTypes[6].nresults   := 1;
  wasmTypes[6].results[0] := WasmI32;
  numWasmTypes := 7;
  { Import state }
  idxProcExit := -1;
  SmallBufInit(importsBuf);
  { Symbol table }
  numSyms      := 0;
  scopeDepth   := 0;
  curFrameSize := 0;
  { Data segment }
  SmallBufInit(dataBuf);
  dataLen      := 0;
  addrIovec    := -1;
  addrNwritten := -1;
  addrNewline  := -1;
  addrIntBuf   := -1;
  { Chapter 4 imports }
  idxFdWrite   := -1;
  { Helper function }
  idxWriteInt  := -1;
  needWriteInt := false;
  CodeBufInit(helperCode);
  { Control flow }
  breakDepth    := -1;
  continueDepth := -1;
  exitDepth     := 0;
  { Chapter 6: procedures/functions }
  currentFuncSlot    := -1;
  numFuncs           := 0;
  { Chapter 7: nested scopes }
  curNestLevel       := 0;
  CodeBufInit(funcBodies);
  hasPendingImport   := false;
  pendingImportMod   := '';
  pendingImportFld   := '';
  hasPendingExport   := false;
  pendingExportName  := '';
  SmallBufInit(userExportsBuf);
  numUserExports     := 0;
  { Chapter 8: string helpers }
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
  needStrInsert    := false;  idxStrInsert     := -1;
  needStrAppendChar := false;  idxStrAppendChar := -1;
  CodeBufInit(strHelperCode);
  lastExprType    := 0;
  lastExprStrMax  := 0;
  lastExprTypeIdx := -1;
  { Chapter 9: structured types }
  numTypes  := 0;
  numFields := 0;
  { Pre-populate built-in type symbols }
  InitBuiltins;
end;

begin
  InitModule;
  InitScanner;
  NextToken;
  ParseProgram;
  WriteModule;

  { Flush binary output to stdout via BlockWrite }
  Assign(outFile, '/dev/stdout');
  Rewrite(outFile, 1);
  BlockWrite(outFile, outBuf.data, outBuf.len);
  Close(outFile);
end.
